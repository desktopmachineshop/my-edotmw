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
from art.lib.bake import (                                        # noqa: E402
    door_hinge_uv, flatten, write_glb, write_prop_glb, write_vat,
)
from art.lib.godot_import import (                               # noqa: E402
    ATLAS_PARAMS, MODEL_PARAMS, VAT_PARAMS, ensure_import_params,
)
from art.lib.soldier import build as build_soldier              # noqa: E402
from art.scatter.props import ROSTER as PROP_ROSTER             # noqa: E402
from art.scatter.props import build as build_prop               # noqa: E402
from art.scatter.props import settle as settle_prop             # noqa: E402
from art.scatter.props import validate as validate_prop         # noqa: E402
from art.terrain.atlas import write_atlas                       # noqa: E402
from art.units import ROSTER                                    # noqa: E402

TRIANGLE_BUDGET = 300
MOUNTED_TRIANGLE_BUDGET = 460   # a horse is a second body; stated, not implied
# Buildings are few and never instanced in the thousands, so their budget is
# about silhouette clarity rather than throughput.
BUILDING_TRIANGLE_BUDGET = 400

GENERATED = os.path.join(_ROOT, "generated")


# Files under art/ that CANNOT change a single byte of `generated/`, and are
# therefore excluded from the staleness hash. Keyed by path relative to art/,
# and duplicated in tests/test_art_assets.gd — the two must agree or the test
# reports a stale build on a clean tree.
#
# `gui.py` is a VIEWER (D-20260821): it opens the real Blender GUI on the
# generators and bakes only by calling `main()` below. Hashing it would mean
# every edit to a panel label marked `generated/` stale and demanded a rebuild
# that produces byte-identical output — a staleness signal that cries wolf
# stops being read, which is the whole value of this hash.
#
# What makes the exclusion SAFE rather than merely convenient is
# `tests/test_blender_gui.gd`, which fails if `gui.py` ever grows geometry of
# its own or bakes by any route but this file. Without that test this list
# would be a hole in the invariant; with it, it is a statement the invariant
# is checked somewhere else.
#
# Do NOT add a generator here to avoid a rebuild. `preview.py` is deliberately
# absent despite also being a viewer: it has been in the hash since M7 and
# taking it out now would change the hash of an unchanged tree, which is the
# exact false alarm this list exists to prevent.
NOT_A_GENERATOR = frozenset({"gui.py"})


def source_hash() -> str:
    """A stable hash over every generator source file."""
    digest = hashlib.sha256()
    for dirpath, dirnames, filenames in os.walk(_HERE):
        dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
        for name in sorted(filenames):
            if not name.endswith(".py"):
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
        model = build_soldier(archetype, params)

        budget = MOUNTED_TRIANGLE_BUDGET if params.mount else TRIANGLE_BUDGET
        tris = model.triangle_count()
        if tris > budget:
            raise SystemExit(
                f"{archetype}: {tris} triangles exceeds the {budget} budget "
                f"(D-064). Simplify the model or change the budget deliberately."
            )

        flat = flatten(model)
        glb_path = os.path.join(models_dir, f"{archetype}.glb")
        vat_path = os.path.join(vat_dir, f"{archetype}.exr")
        write_glb(model, flat, glb_path)
        # LODs and vertex compression off — see MODEL_PARAMS.
        ensure_import_params(glb_path, MODEL_PARAMS)
        layout = write_vat(model, flat, vat_path)
        # A VAT that Godot re-imports as a compressed 3D texture is silently
        # ruined; see godot_import.py.
        ensure_import_params(vat_path, VAT_PARAMS)

        entries[archetype] = {
            "model": f"generated/models/{archetype}.glb",
            "vat": f"generated/vat/{archetype}.exr",
            "triangles": tris,
            "vertices": len(flat["positions"]),
            "mounted": params.mount,
            **layout,
        }
        print(f"  {archetype:16s} {tris:4d} tris  {len(flat['positions']):5d} verts  "
              f"vat {layout['width']}x{layout['height']}")
    return entries


def build_buildings() -> dict:
    """Buildings: mesh only, no VAT (D-064). A town hall does not walk."""
    models_dir = os.path.join(GENERATED, "models")
    os.makedirs(models_dir, exist_ok=True)

    entries: dict[str, dict] = {}
    for building in sorted(BUILDING_ROSTER):
        model = build_building(building, BUILDING_ROSTER[building])
        tris = model.triangle_count()
        if tris > BUILDING_TRIANGLE_BUDGET:
            raise SystemExit(
                f"{building}: {tris} triangles exceeds the "
                f"{BUILDING_TRIANGLE_BUDGET} budget (D-064).")

        flat = flatten(model)
        glb_path = os.path.join(models_dir, f"{building}.glb")
        write_glb(model, flat, glb_path, uv1_override=door_hinge_uv(model, flat))
        # Critical HERE specifically: this is the call that smuggles the
        # door hinge through UV2, which LOD welding and UV quantisation
        # both destroy. See MODEL_PARAMS.
        ensure_import_params(glb_path, MODEL_PARAMS)

        entries[building] = {
            "model": f"generated/models/{building}.glb",
            "triangles": tris,
            "vertices": len(flat["positions"]),
        }
        print(f"  {building:16s} {tris:4d} tris  {len(flat['positions']):5d} verts")
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
