"""Turn a supplied `.glb` into an authored `art/source/<name>.blend`.

    tools/blender-venv/bin/python art/import_glb_source.py \
        --glb art/source/gatherers.glb --name gatherers

## Why this exists, and why it is not a second pipeline

`just build-assets` bakes `art/source/*.blend` and nothing else
(D-20260821-game-assets-are-files). A model that arrives from outside — a
sculpt, a marketplace asset, something a generator produced — is not a
`.blend`, and the honest way to bring one in is to CONVERT IT INTO ONE
rather than to teach the bake a second source format. After this runs, the
model is an ordinary authored source: `just blender-gui <name>` opens it,
vertex paint edits its colours, and `blend_source.bake` owns it exactly as
it owns a hand-modelled file. Nothing downstream learns a new word.

This is `seed_source.py`'s sibling — a MIGRATION, run once per model, never
part of the build — and it borrows that file's rule: it refuses to
overwrite an existing source unless `--force` says otherwise, because that
file may be an artist's work.

## What it has to fix on the way in

- **Up axis.** glTF is Y-up and this project's sources are Z-up (a Y-up mesh
  in a Z-up application lies on its back). Blender's glTF importer converts
  on import, so this file does not do the arithmetic itself — it asserts the
  result, because "the importer handles it" is exactly the kind of claim
  that is true until a flag changes.
- **Scale.** An asset arrives at whatever size its generator chose. Soldiers
  in this roster stand 1.59-1.68 engine units, ground cover is authored not
  to hide them, and formation spacing is tuned around that silhouette — so
  the model is scaled to a stated height rather than trusted.
- **Colour.** The VAT carries ONE baked colour row and the unit shader has
  exactly one sampler (the VAT itself) — there is no texture path for units,
  so a model's basecolor image cannot be sampled at runtime. Its colours are
  transferred into `COLOR_0` per corner instead, which IS the contract
  `blend_source` reads. A texture becomes vertex colours or it becomes
  nothing; this does the former.

## What it deliberately does NOT do

**It does not invent animation.** An imported model arrives with whatever
clips it has, and a model with none bakes 64 identical frames — a figure
that slides rather than walks. `art/clips.py` animates the generated `Part`
hierarchy and cannot drive an arbitrary armature, so retargeting is a
modelling job in Blender, not something to fake here. The bake will say how
many frames it wrote; it cannot say whether they differ.
"""

from __future__ import annotations

import argparse
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from art.lib.blend_source import SOURCE_DIR, source_path     # noqa: E402


## How tall the converted model stands, in ENGINE units, feet on the floor.
##
## Matched to the shipped gatherer (1.595) rather than to the asset's own
## proportions, and that is a deliberate trade worth knowing: a dwarf at a
## human's height does not read as a dwarf. It reads as SAFE — squad
## footprints (D-20260818), selection geometry (D-061) and the ground-cover
## rule that a prop may never hide a soldier (D-100) are all tuned against
## this silhouette, and none of them is re-measured by importing a model.
## Change this one number when the roster's proportions are decided.
DEFAULT_HEIGHT = 1.595


def _reset(bpy) -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)
    for image in list(bpy.data.images):
        bpy.data.images.remove(image, do_unlink=True)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material, do_unlink=True)
    for armature in list(bpy.data.armatures):
        bpy.data.armatures.remove(armature, do_unlink=True)


def _basecolor_image(bpy, obj):
    """The image feeding Base Color on this object's first material, or None.

    Walked through the node tree rather than taken from `material.node_tree
    .nodes['Image Texture']` by name: a glTF importer names its nodes
    whatever it likes, and a lookup by name would break on the next exporter
    that arrives.
    """
    for slot in obj.material_slots:
        material = slot.material
        if material is None or not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            link = node.inputs["Base Color"].links
            if not link:
                continue
            source = link[0].from_node
            if source.type == "TEX_IMAGE" and source.image is not None:
                return source.image
    # No Principled BSDF wired up — take any image the material references,
    # which is what a simpler exporter produces.
    for slot in obj.material_slots:
        material = slot.material
        if material is None or not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                return node.image
    return None


def _srgb_to_linear(c: float) -> float:
    # Godot's importer converts a glTF material factor linear -> sRGB and
    # nothing converts it back (D-100). A COLOR_0 attribute is not a
    # material factor and takes the other road: Blender stores vertex
    # colours LINEAR, and an image's pixels are already linear when the
    # image is not marked sRGB. `image.pixels` hands back linear floats for
    # a colour-space-sRGB image, so no conversion happens here — this helper
    # exists so the decision is visible rather than implied by its absence.
    return c


def _sample_texture_into_colours(bpy, obj, image, owner_mask: float) -> int:
    """Write the basecolor image into `COLOR_0`, one colour per CORNER.

    Per corner, not per point, because UVs live on corners: two faces meeting
    at a seam sample different texels, and averaging them at the shared point
    would smear the seam. `blend_source._colour_at` reads either domain.

    Nearest-texel, not bilinear. The VAT is sampled with nearest filtering
    and one colour per vertex is all it can carry, so a filtered sample would
    be a precision this pipeline cannot represent — the "preview lies about
    the runtime" failure `seed_source.py` already names.
    """
    mesh = obj.data
    uv_layer = mesh.uv_layers.active
    if uv_layer is None:
        raise SystemExit(
            f"{obj.name}: no UV layer, so its texture cannot be sampled into "
            "COLOR_0. Unwrap it, or paint colours by hand.")

    width, height = image.size
    if width == 0 or height == 0:
        raise SystemExit(f"{image.name}: image has no pixels")
    pixels = list(image.pixels)  # one flat read; per-texel access is glacial

    # THE UVs ARE COPIED OUT BEFORE THE COLOUR ATTRIBUTE IS CREATED, and that
    # ordering is load-bearing rather than tidy.
    #
    # A UV map IS an attribute in modern Blender, so `mesh.color_attributes
    # .new()` can reallocate the mesh's attribute storage — and a `uv_layer`
    # fetched beforehand is left pointing at freed memory. Reading it after
    # returns plausible garbage: not an error, not zeroes, just coordinates
    # that are no longer this model's. Sampling those gave every corner a
    # colour from somewhere arbitrary, which averaged to one flat brown and
    # rendered as soup. `mesh.color_attributes.get("COLOR_0")` immediately
    # afterwards read back values that did not match what the sampler
    # returned for the same corner — that mismatch is what identified it,
    # and it is the only symptom there was.
    uvs = [tuple(uv_layer.data[i].uv) for i in range(len(mesh.loops))]

    existing = mesh.color_attributes.get("COLOR_0")
    if existing is not None:
        mesh.color_attributes.remove(existing)
    layer = mesh.color_attributes.new(
        name="COLOR_0", type="FLOAT_COLOR", domain="CORNER")

    # V IS NOT FLIPPED HERE, and getting that wrong is what made the first
    # version of this file produce mud.
    #
    # glTF's UV origin is top-left, so "flip V when reading a glTF UV" is the
    # reflex — and it is WRONG on this side of the importer, twice over.
    # Blender's glTF importer has already flipped V on the way in, and
    # `image.pixels` starts at the BOTTOM-left row. Flipping again
    # double-flips: every UV island samples some OTHER island's content.
    #
    # It does not look like a flipped texture, which is why it was not
    # obvious. This atlas is dozens of small islands, so a double flip does
    # not mirror the dwarf — it deals every body part a different part's
    # colours, and they average to uniform brown. Measured on this model,
    # mean rgb of the top 12% of the body against the bottom 10%:
    #
    #   double-flipped   head 0.316,0.248,0.181   feet 0.284,0.227,0.178
    #   correct          head 0.635,0.589,0.480   feet 0.237,0.158,0.097
    #
    # The correct one puts a cream helmet on the head and dark boots on the
    # feet. The wrong one has no contrast between head and feet AT ALL, and
    # that collapse is the signature `_warn_if_flat` below looks for.
    for loop in mesh.loops:
        u, v = uvs[loop.index]
        # Wrap rather than clamp: a UV marginally outside [0,1] is ordinary
        # in an exported asset, and clamping would smear the border texel
        # along a whole edge.
        x = int((u % 1.0) * width) % width
        y = int((v % 1.0) * height) % height
        i = (y * width + x) * 4
        layer.data[loop.index].color = (
            _srgb_to_linear(pixels[i]),
            _srgb_to_linear(pixels[i + 1]),
            _srgb_to_linear(pixels[i + 2]),
            owner_mask,
        )
    _warn_if_flat(mesh, layer)
    return len(mesh.loops)


def _warn_if_flat(mesh, layer) -> None:
    """Say so when the sampled colours have collapsed to one shade.

    A character that samples its atlas correctly is not one colour: a head
    and a pair of boots differ. When they DO NOT, the usual cause is that
    the UVs and the image disagree about which way is up, and the symptom is
    not a mirrored model — it is mud, because a fragmented atlas deals every
    part somebody else's colours.

    A WARNING and not a failure: a model really can be monochrome, and a
    converter that refused one would be asserting taste. What it must not do
    is stay quiet, which is what let a whole bake ship as brown soup.
    """
    zs = [v.co.z for v in mesh.vertices]
    if not zs:
        return
    lo, hi = min(zs), max(zs)
    if hi - lo <= 0.0:
        return
    bands = {"top": [], "bottom": []}
    for loop in mesh.loops:
        z = mesh.vertices[loop.vertex_index].co.z
        f = (z - lo) / (hi - lo)
        if f >= 0.88:
            bands["top"].append(layer.data[loop.index].color)
        elif f <= 0.10:
            bands["bottom"].append(layer.data[loop.index].color)
    if not bands["top"] or not bands["bottom"]:
        return

    def mean(rows):
        return [sum(r[i] for r in rows) / len(rows) for i in range(3)]

    top, bottom = mean(bands["top"]), mean(bands["bottom"])
    spread = max(abs(top[i] - bottom[i]) for i in range(3))
    print("  colour check: top %s vs bottom %s (spread %.3f)"
          % ([round(c, 3) for c in top], [round(c, 3) for c in bottom], spread))
    if spread < 0.08:
        print("  WARNING: the top and bottom of this model sample almost the "
              "SAME colour. That is the signature of UVs and image disagreeing "
              "about which way is up — check the sampling before baking.")


def convert(glb: str, name: str, height: float, owner_mask: float,
            force: bool) -> None:
    import bpy

    target = source_path(name)
    if os.path.exists(target) and not force:
        raise SystemExit(
            f"{target} already exists. That file is a source of truth — pass "
            "--force if you really mean to replace it.")

    _reset(bpy)
    bpy.ops.import_scene.gltf(filepath=glb)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"{glb}: imported no mesh at all")

    # THE MODEL IS THE BIGGEST MESH, and everything else is named out loud.
    #
    # Not "join every mesh object", which is what this did first and which
    # was silently wrong: Blender's glTF importer adds helper objects that
    # the file does not contain — this asset declares exactly one mesh and
    # imports as two, the second a 42-vertex Icosphere — and joining them
    # made the HELPER the active object. The bake then wrote a perfectly
    # valid 80-triangle sphere as the gatherer, and every count downstream
    # agreed with it. A converter that picks silently is a converter that
    # can ship the wrong model with a green build, so what it ignores is
    # printed with its vertex count.
    meshes.sort(key=lambda o: len(o.data.vertices), reverse=True)
    obj = meshes[0]
    for ignored in meshes[1:]:
        print(f"  ignoring '{ignored.name}' ({len(ignored.data.vertices)} "
              "vertices) — not the largest mesh in the file")

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    obj.name = name
    obj.data.name = name

    # The armature is dropped, and its deformation with it. A rig with no
    # actions poses nothing, so the rest pose IS the mesh; keeping a
    # skeleton nobody authored is what `seed_source.py` refuses to generate
    # for exactly this reason. Rig it in Blender when it is time to animate.
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)
    for other in list(bpy.data.objects):
        if other is not obj:
            bpy.data.objects.remove(other, do_unlink=True)

    # Bake the import's own transform in before measuring: the glTF importer
    # expresses its Y-up -> Z-up conversion as a rotation ON THE OBJECT, so
    # the mesh's own coordinates are still Y-up until this is applied.
    # Measuring first would size the model against the wrong axis.
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    zs = [v.co.z for v in obj.data.vertices]
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    raw_height = max(zs) - min(zs)
    if raw_height <= 0.0:
        raise SystemExit(
            f"{name}: the model has no height along Z after import — the "
            "up-axis conversion did not happen, so it is lying on its back "
            "(see the module docstring).")
    if raw_height < (max(xs) - min(xs)) * 0.5:
        # Not fatal — a model CAN be wider than it is tall — but it is the
        # signature of an up-axis that went wrong, and this pipeline has
        # already paid for that once (every seeded soldier lay on its back).
        print(f"  NOTE: {name} is much wider than tall "
              f"({max(xs) - min(xs):.3f} x {raw_height:.3f}); check the pose.")

    scale = height / raw_height
    for v in obj.data.vertices:
        v.co.x = (v.co.x - (max(xs) + min(xs)) * 0.5) * scale
        v.co.y = (v.co.y - (max(ys) + min(ys)) * 0.5) * scale
        v.co.z = (v.co.z - min(zs)) * scale
    obj.location = (0.0, 0.0, 0.0)

    image = _basecolor_image(bpy, obj)
    if image is None:
        print(f"  NOTE: {name} has no basecolor image; COLOR_0 is left alone "
              "and the bake will use flat white. Paint it in vertex paint.")
        corners = 0
    else:
        corners = _sample_texture_into_colours(bpy, obj, image, owner_mask)

    os.makedirs(SOURCE_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=target)

    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"  {name}: {len(obj.data.vertices)} vertices, {tris} triangles, "
          f"{corners} corner colours, {raw_height:.3f} -> {height:.3f} tall")
    print(f"  wrote {os.path.relpath(target, _ROOT)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True, help="the model to import")
    parser.add_argument("--name", required=True,
                        help="archetype it becomes (art/source/<name>.blend)")
    parser.add_argument("--height", type=float, default=DEFAULT_HEIGHT,
                        help="engine units, feet on the floor")
    parser.add_argument("--owner-mask", type=float, default=0.0,
                        help="COLOR_0 alpha: how much of the owner's colour "
                             "this model takes (D-052). 0 keeps its own.")
    parser.add_argument("--force", action="store_true",
                        help="replace an existing source")
    args = parser.parse_args()

    if not os.path.exists(args.glb):
        raise SystemExit(f"{args.glb}: no such file")
    convert(args.glb, args.name, args.height, args.owner_mask, args.force)


if __name__ == "__main__":
    main()
