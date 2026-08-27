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
            force: bool, decimate: int = 0, yaw: float = 0.0) -> None:
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

    obj.name = name
    obj.data.name = name

    # Some supplied files arrive with leftover ACTIONS (Tripo exports ship
    # preview animations). The gatherer's had none, so this never mattered
    # before — but an action left assigned poses the armature, which would
    # deform the mesh under the decimation below and bake into every frame
    # of a model whose clips are meant to be authored by author_clips.py
    # (which writes its own and clears these anyway). The REST pose is the
    # contract; anything else is discarded out loud.
    for action in list(bpy.data.actions):
        print(f"  dropping supplied action '{action.name}' — clips are "
              "authored, not imported (D-20260824)")
        bpy.data.actions.remove(action)
    for other in bpy.data.objects:
        if other.type != "ARMATURE":
            continue
        for pose_bone in other.pose.bones:
            pose_bone.location = (0.0, 0.0, 0.0)
            pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            pose_bone.scale = (1.0, 1.0, 1.0)

    # Decimate BEFORE anything measures or samples: a VAT column exists per
    # flattened CORNER, and the 16,384-texture-width ceiling every targeted
    # GPU shares works out to 5,461 triangles for a whole model, kit
    # included (art/build.py's MAX_VAT_WIDTH). The supplied Tripo bodies
    # arrive at ~9,600-10,300 triangles — none of them can bake at all
    # without this pass. Decimating first also means the COLOR_0 sampling
    # below colours the geometry that actually ships, and the collapse
    # preserves the vertex groups a skinned mesh's weights live in.
    if decimate > 0:
        obj.data.calc_loop_triangles()
        source_tris = len(obj.data.loop_triangles)
        if source_tris > decimate:
            for other in bpy.data.objects:
                other.select_set(other == obj)
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new("decimate", "DECIMATE")
            modifier.decimate_type = "COLLAPSE"
            modifier.ratio = decimate / float(source_tris)
            bpy.ops.object.modifier_apply(modifier="decimate")
            obj.data.calc_loop_triangles()
            print(f"  decimated {source_tris} -> "
                  f"{len(obj.data.loop_triangles)} triangles "
                  f"(asked for {decimate})")

    # THE RIG IS KEPT, and that is what makes the model animatable.
    #
    # `blend_source.bake` steps the timeline and flattens through the
    # DEPENDENCY GRAPH, so bones deform the mesh and the result lands in the
    # VAT with nothing else told about it (D-20260821). Dropping the skeleton
    # on the way in would throw away the only part of the asset that makes
    # animation cheap — see `art/author_clips.py`.
    armature = None
    if obj.parent is not None and obj.parent.type == "ARMATURE":
        armature = obj.parent
    else:
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE" and modifier.object is not None:
                armature = modifier.object
                break
    keep = set([obj]) | (set([armature]) if armature is not None else set())
    for other in list(bpy.data.objects):
        if other not in keep:
            bpy.data.objects.remove(other, do_unlink=True)

    root = armature if armature is not None else obj

    # FACING is not part of the glTF contract, and the supplied bodies do
    # not agree on one: the shieldwarden arrived facing -Y (this project's
    # forward), the crossbow body facing +X and the warrior likewise — a
    # T-posed humanoid gives no machine-readable clue beyond its toes, and
    # an unrigged model not even that. So the yaw is STATED per import and
    # verified below (toes) and by a render.
    #
    # Applied to the DATA — bone rest positions and mesh vertices — NOT as
    # an object rotation, and the difference was found the expensive way:
    # `author_clips.py` poses bones in ARMATURE space and measures forward
    # from the toes in that same space, so a yaw parked on the object left
    # every clip authored against a rig whose local forward was still
    # sideways — a baked walk that marches at 90 degrees to the model's
    # face. Rotating the data keeps local == world and every downstream
    # assumption true. (Scale stays on the root, unapplied, because scale
    # interacts with skinning the other way — see below.)
    if yaw != 0.0:
        import math as _math
        from mathutils import Matrix
        rotation = Matrix.Rotation(_math.radians(yaw), 4, "Z")
        for other in bpy.data.objects:
            if other.type not in ("ARMATURE", "MESH"):
                continue
            # Data-level transforms only compose if every object's local
            # frame is the identity the glTF importer normally leaves;
            # a mesh parented with its own rotation would rotate apart
            # from its bones.
            local = other.matrix_local.to_3x3()
            if max(abs(local[0][1]), abs(local[0][2]), abs(local[1][0]),
                   abs(local[1][2]), abs(local[2][0]), abs(local[2][1])) > 1e-4:
                raise SystemExit(
                    f"{name}: '{other.name}' carries its own local rotation, "
                    "so a data-level yaw would twist it apart from the rig. "
                    "Open the file and sort the transforms out by hand.")
            other.data.transform(rotation)
        bpy.context.view_layer.update()

    # Measured in WORLD space and corrected on the ROOT object, UNAPPLIED.
    #
    # `blend_source` bakes `matrix_world`, so an object-level transform is
    # already part of what it reads. Mutating vertex coordinates instead —
    # which is what this did while the rig was being discarded — would slide
    # a skinned mesh out from under the bones that drive it, and the model
    # would come apart the moment anything posed it.
    corners = [obj.matrix_world @ v.co for v in obj.data.vertices]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    zs = [c.z for c in corners]
    raw_height = max(zs) - min(zs)
    if raw_height <= 0.0:
        raise SystemExit(
            f"{name}: the model has no height along Z — the up-axis "
            "conversion did not happen, so it is lying on its back.")

    scale = height / raw_height
    root.scale = (scale, scale, scale)
    root.location = (
        -(max(xs) + min(xs)) * 0.5 * scale,
        -(max(ys) + min(ys)) * 0.5 * scale,
        -min(zs) * scale,
    )

    # FACING is asserted, not trusted (the archers body shipped a quarter
    # turn wrong on the first pass of exactly this converter). A rigged
    # humanoid's toes point the way it faces; -Y is this project's forward
    # (author_clips measures the same thing the same way). An unrigged
    # model gives nothing to measure, so only the render can check it.
    if armature is not None:
        toe_y = []
        for bone in armature.data.bones:
            if "toe" in bone.name.lower():
                direction = (armature.matrix_world.to_3x3()
                             @ (bone.tail_local - bone.head_local)).normalized()
                toe_y.append(direction.y)
        if toe_y and sum(toe_y) / len(toe_y) > -0.5:
            raise SystemExit(
                f"{name}: the toes point y={sum(toe_y) / len(toe_y):+.2f}, "
                "so this model does not face -Y. Pass --yaw to turn it — "
                "the supplied bodies do not agree on a forward axis.")

    image = _basecolor_image(bpy, obj)
    if image is None:
        print(f"  NOTE: {name} has no basecolor image; COLOR_0 is left alone "
              "and the bake will use flat white. Paint it in vertex paint.")
        corner_count = 0
    else:
        corner_count = _sample_texture_into_colours(bpy, obj, image, owner_mask)

    os.makedirs(SOURCE_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=target)

    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"  {name}: {len(obj.data.vertices)} vertices, {tris} triangles, "
          f"{corner_count} corner colours, {raw_height:.3f} -> {height:.3f} tall")
    print("  rig: %s" % ("NONE — this model cannot be animated"
                         if armature is None
                         else f"{len(armature.data.bones)} bones kept"))
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
    parser.add_argument("--yaw", type=float, default=0.0,
                        help="degrees to turn the model about Z so it faces "
                             "-Y, this project's forward. Stated per model "
                             "and checked by a render — supplied bodies do "
                             "not agree on a forward axis.")
    parser.add_argument("--decimate", type=int, default=0,
                        help="collapse the mesh to roughly this many "
                             "triangles first (0 keeps it as supplied). The "
                             "VAT width limit works out to 5,461 triangles "
                             "per model, kit included — see art/build.py's "
                             "MAX_VAT_WIDTH.")
    args = parser.parse_args()

    if not os.path.exists(args.glb):
        raise SystemExit(f"{args.glb}: no such file")
    convert(args.glb, args.name, args.height, args.owner_mask, args.force,
            args.decimate, args.yaw)


if __name__ == "__main__":
    main()
