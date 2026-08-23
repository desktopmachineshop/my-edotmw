"""Write the initial `art/source/*.blend` files from the old generators
(D-20260821-game-assets-are-files).

    tools/blender-venv/bin/python art/seed_source.py [--only NAME]
    just seed-art-source

## This is a MIGRATION, run once per model, not part of the build

`just build-assets` never calls this. Once `art/source/<name>.blend` exists it
is the source of truth and this script would overwrite an artist's work with a
generator's — so it refuses to clobber an existing file unless `--force` says
otherwise, and says which files it skipped.

## Why seed at all, rather than starting from an empty file

An empty `.blend` is a worse starting point than the model that ships. Seeding
means opening `militia.blend` gives you the militia that is in the game right
now — right scale, right palette, right owner-colour masks, and a timeline
already playing `idle`/`walk`/`attack`/`rout` correctly. Reshaping something
that exists is a different job from authoring to an undocumented convention,
and every convention this pipeline has is demonstrated by the seeded file
rather than written in a document nobody opens.

## The file is Z-UP, because a person opens it

`geom.py` authors Y-up to match Godot. A Y-up mesh in a Z-up application lies
on its back — wrong floor, swapped ortho views, mirror on the wrong axis, and
every rigging tool Blender has assuming Z-up. So the seed converts on the way
IN (`_to_blender`) and `blend_source._to_engine` converts back on the way out.
The two are exact inverses and a test pins both.

Everything is converted together or nothing is: vertices, the part's PIVOT, and
the clip ROTATIONS. A pose is a rotation about an axis named in Y-up terms, so
it is conjugated into the new basis rather than relabelled — see `_key_clips`.

## What a seeded file contains

One object per `Part`, named for it, with:

- **its origin at the part's pivot**, so rotating the object in the viewport
  is the same motion `clips.py` applied. A hip rotation is a hip rotation.
- **`COLOR_0`** carrying the part's rgb with the owner mask (D-052) in alpha,
  which is what `blend_source` reads back and what vertex paint edits.
- **rotation keyframes on all 64 frames**, CONSTANT interpolation. Constant
  rather than Bezier because the VAT is sampled with nearest filtering: an
  eased curve in the file would bake to the same 64 rows but would show the
  artist a smoothness the game does not have, which is the "preview lies about
  the runtime" failure this project keeps paying for.

An armature is deliberately NOT generated. Rigid parts are what the current
clips express, and inventing a skeleton the animation does not use would be a
rig nobody authored, sitting in every file, that an artist has to delete before
doing the thing they actually want. Add one when you rig a model; the bake
evaluates the depsgraph and does not care either way.
"""

from __future__ import annotations

import argparse
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from art.buildings import ROSTER as BUILDING_ROSTER          # noqa: E402
from art.buildings import build as build_building            # noqa: E402
from art.lib.blend_source import (                           # noqa: E402
    SOURCE_DIR, TOTAL_FRAMES, source_path,
)
from art.lib.clips import CLIP_ORDER, FRAMES_PER_CLIP, GROUP_OF, pose_at  # noqa: E402
from art.lib.geom import pose_part                           # noqa: E402
from art.lib.soldier import build as build_soldier           # noqa: E402
from art.units import ROSTER as UNIT_ROSTER                  # noqa: E402


def _to_blender(v) -> tuple[float, float, float]:
    """Engine Y-up -> Blender Z-up. The inverse of `blend_source._to_engine`.

    A +90 degrees rotation about X: (x, y, z) -> (x, -z, y), since a rotation
    by theta sends y to y*cos - z*sin and z to y*sin + z*cos. Read it against
    its inverse `(x, y, z) -> (x, z, -y)`; the pair is small enough to check by
    eye, which is the point of writing both as explicit tuples.
    """
    return (v[0], -v[2], v[1])


def _basis(mathutils):
    """The same rotation as `_to_blender`, as a quaternion.

    Needed because a clip's rotations are expressed about axes named in Y-UP
    terms. Relabelling them (y becomes z, and so on) gets the handedness wrong
    on one axis and produces an animation that is subtly mirrored — so the pose
    is CONJUGATED into the new basis instead, which cannot be got half right.
    """
    # +90, matching `_to_blender`. The sign matters and got this wrong once:
    # a quaternion that is the INVERSE of the vector transform still produces a
    # model that stands up correctly in the viewport, because the rest pose is
    # carried by the vertices — only the ANIMATION comes out wrong, and only by
    # a rotation. It was caught by the round-trip check (0.32 world units
    # against an expected 1e-7), which is what that check is for.
    return mathutils.Quaternion(mathutils.Vector((1.0, 0.0, 0.0)), 1.5707963267948966)


def _reset(bpy) -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)


def _object_for(bpy, part):
    """One Blender object per Part, with its origin ON the part's pivot.

    Vertices are stored pivot-relative and the object placed at the pivot, so
    the object's own rotation reproduces `pose_part` exactly. Storing model
    -space vertices and rotating them would bake the pose into the mesh and
    leave an artist with a part that turns about the world origin.
    """
    px, py, pz = part.pivot
    mesh = bpy.data.meshes.new(part.name)
    # Pivot-relative FIRST, in the authored space, then converted — the two
    # operations do not commute and doing them the other way round puts every
    # part's geometry at the wrong offset from its own origin.
    mesh.from_pydata(
        [_to_blender((v[0] - px, v[1] - py, v[2] - pz)) for v in part.verts],
        [], [tuple(f) for f in part.faces])
    mesh.update()

    layer = mesh.color_attributes.new(name="COLOR_0", type="FLOAT_COLOR",
                                      domain="CORNER")
    for i in range(len(mesh.loops)):
        layer.data[i].color = (part.rgb[0], part.rgb[1], part.rgb[2], part.mask)

    mesh.shade_flat()
    obj = bpy.data.objects.new(part.name, mesh)
    obj.location = _to_blender((px, py, pz))
    obj.rotation_mode = "QUATERNION"
    bpy.context.collection.objects.link(obj)
    return obj


def _key_clips(bpy, model, objects) -> None:
    """Keyframe every part across the whole 64-frame timeline.

    The rotation for a frame is taken from `clips.pose_at`, converted from the
    (axis, angle) list `geom.pose_part` applies into a quaternion, so the file
    plays what the VAT used to store. The whole-body `offset` a clip carries is
    applied as a location key on every part, since there is no root object to
    put it on and inventing one would change what an artist sees at the origin.
    """
    import mathutils
    from mathutils import Quaternion, Vector

    # Axes as `clips.py` names them — i.e. in the AUTHORED Y-up space.
    axes = {"x": Vector((1.0, 0.0, 0.0)),
            "y": Vector((0.0, 1.0, 0.0)),
            "z": Vector((0.0, 0.0, 1.0))}
    basis = _basis(mathutils)
    basis_inv = basis.inverted()

    for clip_index, clip in enumerate(CLIP_ORDER):
        for f in range(FRAMES_PER_CLIP):
            frame = clip_index * FRAMES_PER_CLIP + f
            pose = pose_at(clip, f / FRAMES_PER_CLIP)
            for part, obj in zip(model.parts, objects):
                rotations = pose.rotations.get(GROUP_OF.get(part.name, ""), [])
                q = Quaternion((1.0, 0.0, 0.0, 0.0))
                # `pose_part` applies its list in order about the same pivot,
                # so composing left-to-right here matches it.
                for axis, angle in rotations:
                    if angle:
                        q = Quaternion(axes[axis], angle) @ q
                # Conjugate into Blender's basis; see `_basis`.
                obj.rotation_quaternion = basis @ q @ basis_inv
                obj.location = _to_blender((part.pivot[0] + pose.offset[0],
                                            part.pivot[1] + pose.offset[1],
                                            part.pivot[2] + pose.offset[2]))
                obj.keyframe_insert("rotation_quaternion", frame=frame)
                obj.keyframe_insert("location", frame=frame)

    # CONSTANT interpolation — see the module docstring. The VAT is sampled
    # nearest, so the file must not show an easing the game cannot play.
    for action in bpy.data.actions:
        for fcurve in action.fcurves:
            for keyframe in fcurve.keyframe_points:
                keyframe.interpolation = "CONSTANT"


def _markers(bpy) -> None:
    """A timeline marker at the start of each clip.

    Purely for the artist: scrubbing 64 unlabelled frames gives no clue where
    `walk` ends and `attack` begins, and the clip boundaries are a hard
    convention (`CLIP_ORDER`, `FRAMES_PER_CLIP`) that the file should state
    rather than leave to be counted.
    """
    scene = bpy.context.scene
    for marker in list(scene.timeline_markers):
        scene.timeline_markers.remove(marker)
    for i, clip in enumerate(CLIP_ORDER):
        scene.timeline_markers.new(clip, frame=i * FRAMES_PER_CLIP)


def seed(name: str, model, force: bool, animated: bool = True) -> bool:
    import bpy

    path = source_path(name)
    if os.path.exists(path) and not force:
        print(f"  {name:16s} SKIP — {os.path.relpath(path, _ROOT)} already exists")
        return False

    _reset(bpy)
    objects = [_object_for(bpy, part) for part in model.parts]
    scene = bpy.context.scene
    if animated:
        _key_clips(bpy, model, objects)
        _markers(bpy)
        scene.frame_start = 0
        scene.frame_end = TOTAL_FRAMES - 1
    else:
        # A town hall does not walk (D-082 bakes no VAT for a building), so
        # keyframing 64 frames of identity would put a timeline in the file
        # that means nothing and invites someone to animate against it.
        scene.frame_start = 0
        scene.frame_end = 0
    scene.frame_set(0)

    os.makedirs(SOURCE_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    print(f"  {name:16s} {len(model.parts):2d} parts  "
          f"{model.triangle_count():4d} tris  -> {os.path.relpath(path, _ROOT)}")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", default=None)
    parser.add_argument("--force", action="store_true",
                        help="overwrite an existing source file — this DISCARDS "
                             "whatever was authored in it")
    args = parser.parse_args()

    written = 0
    print("seeding units:")
    for name in sorted(UNIT_ROSTER):
        if args.only and name != args.only:
            continue
        written += seed(name, build_soldier(name, UNIT_ROSTER[name]), args.force)

    print("seeding structures:")
    for name in sorted(BUILDING_ROSTER):
        if args.only and name != args.only:
            continue
        written += seed(name, build_building(name, BUILDING_ROSTER[name]),
                        args.force, animated=False)

    print(f"{written} file(s) written. `just build-assets` bakes them; "
          f"`just blender-gui <name>` opens one.")


if __name__ == "__main__":
    main()
