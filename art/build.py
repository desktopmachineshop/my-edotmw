"""Asset build entry point (D-064).

    tools/blender-venv/bin/python art/build.py [--only ARCHETYPE]

Writes `generated/` from `art/`. Run by `just build-assets`.

## Determinism is a requirement, not a nicety

D-063 criterion 1 says two runs must be byte-identical, and D-063 criterion 2
says a stale `generated/` must fail `just test-unit`. Both depend on this script
having no hidden inputs: iteration is over sorted keys, there are no timestamps
in the output, and nothing is seeded from the clock.

The manifest records a hash of every `art/**/*.py` file. That is what makes
staleness detectable — if a generator changes and nobody rebuilds, the hash in
`generated/manifest.json` no longer matches the sources and the Godot-side test
fails. It deliberately hashes the SOURCES rather than the outputs: a hash of the
outputs would only prove the outputs were not corrupted, which is not the
failure anyone is worried about.

## The triangle budget is enforced here

D-064 sets ~300 triangles per soldier. An over-budget archetype fails the build
rather than printing a warning, because a warning in a build log is how the
budget stops being a budget.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

# Allow both `python art/build.py` and `python -m art.build`.
_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from art.buildings import ROSTER as BUILDING_ROSTER                # noqa: E402
from art.buildings import build as build_building                  # noqa: E402
from art.lib import blend_source                                  # noqa: E402
from art.lib.bake import (                                        # noqa: E402
    bake_frames, door_hinge_uv, flatten, write_glb, write_prop_glb, write_vat,
)
from art.lib.godot_import import (                               # noqa: E402
    ALBEDO_PARAMS, ATLAS_PARAMS, MODEL_PARAMS, VAT_PARAMS, ensure_import_params,
)
from art.lib.soldier import build as build_soldier              # noqa: E402
from art.scatter.props import ROSTER as PROP_ROSTER             # noqa: E402
from art.scatter.props import build as build_prop               # noqa: E402
from art.scatter.props import settle as settle_prop             # noqa: E402
from art.scatter.props import validate as validate_prop         # noqa: E402
from art.terrain.atlas import write_atlas                       # noqa: E402
from art.lib.clips import clips_for                            # noqa: E402
from art.units import ROSTER                                    # noqa: E402

TRIANGLE_BUDGET = 300
MOUNTED_TRIANGLE_BUDGET = 460   # a horse is a second body; stated, not implied

# Archetypes allowed past the budget while a PLACEHOLDER stands in for the
# real model, and the ceiling they are allowed up to.
#
# This is the "change the budget deliberately" the failure below invites,
# scoped as narrowly as it can be: a named set, not a raised global. An
# imported asset (art/import_glb_source.py) arrives at whatever density its
# generator chose — the dwarf standing in for the gatherer is 4,824 against
# a roster whose every other model is 72-256 — and the choice is to see it
# in the game now or to decimate 94% of it away and see something else.
#
# THE COST IS REAL AND IS NOT PAID BY THIS FILE. D-041 measured the client
# CPU-bound on soldier derivation, but triangles are the GPU's half and
# nothing here has re-measured it: gatherers are the most numerous unit a
# player fields, so a 16x model on 20 players' crews is the one place this
# could hurt most. `just bench-render` is the instrument, and it has not
# been run against this. Treat every entry here as owing that measurement.
PLACEHOLDER_TRIANGLE_BUDGET = 6000
PLACEHOLDER_ARCHETYPES = frozenset({"gatherers"})
# Buildings are few and never instanced in the thousands, so their budget is
# about silhouette clarity rather than throughput.
BUILDING_TRIANGLE_BUDGET = 400

## The widest VAT this project will write, in pixels.
##
## A model's triangle count is a TEXTURE WIDTH: `art/lib/bake.py` gives every
## flattened vertex a column, so 5,461 triangles is 16,383 pixels across.
## 16,384 is the 2D texture limit shared by every GPU this game targets — the
## owner's Iris Xe included — and a texture that exceeds it is not created at
## all. So the failure is not a slow frame: it is a squad that does not render,
## on somebody else's machine, long after the build said fine.
##
## Checked here rather than left to the triangle budgets above because those
## are per-source (a soldier, a tool, an imported placeholder) while this is a
## property of the SUM, and the sum is what the texture has to hold.
MAX_VAT_WIDTH = 16384

GENERATED = os.path.join(_ROOT, "generated")


# What the staleness hash covers. `.blend` is in the list because authored
# sources ARE the source of truth now (D-20260821-game-assets-are-files): a
# model edited in Blender and not rebuilt leaves `generated/` stale in exactly
# the way an edited generator does, and the whole job of this hash is to make
# that fail loudly instead of shipping yesterday's mesh.
SOURCE_SUFFIXES = (".py", ".blend", ".glb")
# `.glb` is here for SUPPLIED models (art/import_glb_source.py). The
# `.blend` it converts to is the thing the bake reads, so the `.glb`
# alone changes no output — which is exactly why it has to be hashed:
# without it, replacing the supplied asset and forgetting to re-convert
# leaves the game drawing the previous model with every check green.

# Files under art/ that CANNOT change a single byte of `generated/`, and are
# therefore excluded. Keyed by path relative to art/, and duplicated in
# tests/test_art_assets.gd — the two must agree or the test reports a stale
# build on a clean tree.
#
# `seed_source.py` writes the initial `art/source/*.blend` from the legacy
# generators. `main()` below never calls it, and it refuses to overwrite an
# existing source, so editing it cannot change any output — while hashing it
# would mark every model stale over a change to a migration script that will
# not be run again. A staleness signal that cries wolf stops being read, which
# is the whole value of this hash.
#
# Do NOT add a real generator here to avoid a rebuild.
NOT_A_GENERATOR = frozenset({"seed_source.py"})


def source_hash() -> str:
    """A stable hash over every asset source: generators AND authored files."""
    digest = hashlib.sha256()
    for dirpath, dirnames, filenames in os.walk(_HERE):
        dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
        for name in sorted(filenames):
            if not name.endswith(SOURCE_SUFFIXES):
                continue
            relative = os.path.relpath(os.path.join(dirpath, name), _HERE)
            if relative.replace("\\", "/") in NOT_A_GENERATOR:
                continue
            path = os.path.join(dirpath, name)
            digest.update(os.path.relpath(path, _ROOT).replace("\\", "/").encode())
            with open(path, "rb") as handle:
                digest.update(handle.read())
    return digest.hexdigest()


def build_units(only: str | None) -> dict:
    models_dir = os.path.join(GENERATED, "models")
    vat_dir = os.path.join(GENERATED, "vat")
    os.makedirs(models_dir, exist_ok=True)
    os.makedirs(vat_dir, exist_ok=True)

    entries: dict[str, dict] = {}
    for archetype in sorted(ROSTER):
        if only and archetype != only:
            continue
        params = ROSTER[archetype]
        flat, frames, source = _unit_geometry(
            archetype, params, os.path.join(GENERATED, "textures"))

        placeholder = archetype in PLACEHOLDER_ARCHETYPES
        if placeholder:
            budget = PLACEHOLDER_TRIANGLE_BUDGET
        else:
            budget = MOUNTED_TRIANGLE_BUDGET if params.mount else TRIANGLE_BUDGET
        tris = len(flat["triangles"])
        if tris > budget:
            raise SystemExit(
                f"{archetype}: {tris} triangles exceeds the {budget} budget "
                f"(D-064). Simplify the model or change the budget deliberately."
            )

        texture = str(flat.get("texture", ""))
        if texture:
            ensure_import_params(
                os.path.join(_ROOT, texture.replace("/", os.sep)),
                ALBEDO_PARAMS)

        glb_path = os.path.join(models_dir, f"{archetype}.glb")
        vat_path = os.path.join(vat_dir, f"{archetype}.exr")
        write_glb(archetype, flat, glb_path)
        # LODs and vertex compression off — see MODEL_PARAMS.
        ensure_import_params(glb_path, MODEL_PARAMS)
        layout = write_vat(archetype, flat, vat_path, frames,
                           clips=clips_for(archetype))
        if layout["width"] > MAX_VAT_WIDTH:
            raise SystemExit(
                f"{archetype}: a {layout['width']}-pixel VAT exceeds the "
                f"{MAX_VAT_WIDTH} texture limit ({tris} triangles x 3). The "
                "model cannot be uploaded on the hardware this game targets — "
                "reduce it, or split the archetype.")
        # A VAT that Godot re-imports as a compressed 3D texture is silently
        # ruined; see godot_import.py.
        ensure_import_params(vat_path, VAT_PARAMS)

        entries[archetype] = {
            "model": f"generated/models/{archetype}.glb",
            "vat": f"generated/vat/{archetype}.exr",
            "triangles": tris,
            "vertices": len(flat["positions"]),
            "mounted": params.mount,
            # Where this model's own albedo lives, or "" for the vertex-
            # coloured models that are the rest of the roster
            # (D-20260824-a-textured-model-keeps-its-texture).
            "texture": texture,
            # Recorded rather than inferred, so the Godot-side budget test
            # reads the same answer this file reached instead of keeping a
            # second copy of the set that can drift from it.
            "placeholder": placeholder,
            "source": source,
            **layout,
        }
        print(f"  {archetype:16s} {tris:4d} tris  {len(flat['positions']):5d} verts  "
              f"vat {layout['width']}x{layout['height']}  [{source}"
              f"{', PLACEHOLDER' if placeholder else ''}]")
    return entries


def _unit_geometry(archetype: str, params, texture_dir: str | None = None):
    """The flattened mesh and its animation frames, from whichever source owns
    this archetype (D-20260821-game-assets-are-files).

    An authored `art/source/<name>.blend` WINS. The generated path is the
    fallback, kept because props and the terrain atlas still use it, because a
    model can be migrated one at a time rather than on a flag day, and because
    a clone that has never authored anything still builds.

    Which one ran is recorded in the manifest rather than inferred, so a
    surprising `.glb` can be traced to a file rather than guessed at.
    """
    if blend_source.has_source(archetype):
        flat, frames = blend_source.bake(archetype, texture_dir)
        return flat, frames, "authored"
    model = build_soldier(archetype, params)
    flat = flatten(model)
    return flat, bake_frames(model, flat), "generated"


def build_buildings() -> dict:
    """Buildings: mesh only, no VAT (D-064). A town hall does not walk."""
    models_dir = os.path.join(GENERATED, "models")
    os.makedirs(models_dir, exist_ok=True)

    entries: dict[str, dict] = {}
    for building in sorted(BUILDING_ROSTER):
        if blend_source.has_source(building):
            # A building has no VAT, so only the rest frame is wanted; the
            # frames are evaluated and discarded rather than given a second
            # code path that could disagree about the rest pose.
            flat, _frames = blend_source.bake(building)
            source = "authored"
        else:
            flat = flatten(build_building(building, BUILDING_ROSTER[building]))
            source = "generated"
        tris = len(flat["triangles"])
        if tris > BUILDING_TRIANGLE_BUDGET:
            raise SystemExit(
                f"{building}: {tris} triangles exceeds the "
                f"{BUILDING_TRIANGLE_BUDGET} budget (D-064).")

        glb_path = os.path.join(models_dir, f"{building}.glb")
        write_glb(building, flat, glb_path, uv1_override=door_hinge_uv(flat))
        # Critical HERE specifically: this is the call that smuggles the
        # door hinge through UV2, which LOD welding and UV quantisation
        # both destroy. See MODEL_PARAMS.
        ensure_import_params(glb_path, MODEL_PARAMS)

        entries[building] = {
            "model": f"generated/models/{building}.glb",
            "triangles": tris,
            "vertices": len(flat["positions"]),
            "source": source,
        }
        print(f"  {building:16s} {tris:4d} tris  {len(flat['positions']):5d} verts"
              f"  [{source}]")
    return entries


def build_props() -> dict:
    """Ground-cover props (D-100): mesh only, materials baked in.

    Their budget and their HEIGHT limit are both enforced inside
    `art/scatter/props.py`'s `validate`, which also refuses inside-out
    geometry — see that module's header for why a prop is the exact shape
    that hides a winding mistake.
    """
    models_dir = os.path.join(GENERATED, "models")
    os.makedirs(models_dir, exist_ok=True)

    entries: dict[str, dict] = {}
    for prop in sorted(PROP_ROSTER):
        model = build_prop(prop)
        # Settle, then validate what the settle DID — `validate` used to be
        # handed an already-settled model and asked whether it was settled.
        settled_by = settle_prop(model)
        bounds = validate_prop(prop, model, settled_by)
        glb_path = os.path.join(models_dir, f"{prop}.glb")
        stats = write_prop_glb(model, glb_path)

        entries[prop] = {
            "model": f"generated/models/{prop}.glb",
            "triangles": model.triangle_count(),
            "note": PROP_ROSTER[prop].note,
            **bounds,
            **stats,
        }
        print(f"  {prop:20s} {model.triangle_count():3d} tris  "
              f"{bounds['height']:.2f} tall  {stats['materials']} mat")
    return entries


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default=None,
                        help="build a single archetype (for the spike loop)")
    parser.add_argument("--skip-terrain", action="store_true")
    args = parser.parse_args()

    os.makedirs(GENERATED, exist_ok=True)
    print("building units:")
    units = build_units(args.only)

    print("building structures:")
    buildings = build_buildings()

    print("building ground cover:")
    props = build_props()

    terrain = {}
    if not args.skip_terrain:
        print("building terrain atlas:")
        terrain = write_atlas(os.path.join(GENERATED, "textures"))
        ensure_import_params(
            os.path.join(_ROOT, terrain["path"].replace("/", os.sep)), ATLAS_PARAMS)
        print(f"  atlas {terrain['width']}x{terrain['height']}  "
              f"{len(terrain['biomes'])} biomes")

    manifest = {
        "source_hash": source_hash(),
        "units": units,
        "buildings": buildings,
        "props": props,
        "terrain": terrain,
    }
    # sort_keys + trailing newline: two runs must diff clean.
    with open(os.path.join(GENERATED, "manifest.json"), "w", newline="\n") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"manifest source_hash={manifest['source_hash'][:16]}…")


if __name__ == "__main__":
    main()
