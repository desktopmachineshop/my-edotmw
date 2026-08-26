"""Give an unrigged authored body the family skeleton, with automatic weights.

    tools/blender-venv/bin/python art/transplant_rig.py \
        --name spearmen --donor militia

A MIGRATION like `import_glb_source.py`: run once per model, never part of
the build. It exists because the supplied bodies do not all arrive rigged —
the dwarf knight shipped as a bare mesh — while every rigged one carries
the IDENTICAL 41-bone Tripo skeleton. So rigging the stragglers is not a
modelling job: append the donor's armature, scale it to this body's own
height, and let Blender's bone-heat weighting bind the mesh.

## What this cannot promise

Automatic weights are a fit, not an authoring. On a squat armoured body
whose proportions match the donor's they land well; the check is a RENDER
of the posed clips, not this script's own prints. If a body comes out
creasing at the shoulders, the fix is weight paint in `just blender-gui`,
which is exactly the affordance authored sources exist for
(D-20260821-game-assets-are-files).
"""

from __future__ import annotations

import argparse
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from art.lib.blend_source import source_path                 # noqa: E402


def transplant(name: str, donor: str) -> None:
    import bpy

    path = source_path(name)
    donor_path = source_path(donor)
    for required in (path, donor_path):
        if not os.path.exists(required):
            raise SystemExit(f"no authored source at {required}")

    bpy.ops.wm.open_mainfile(filepath=path, load_ui=False)
    body = bpy.data.objects.get(name)
    if body is None or body.type != "MESH":
        raise SystemExit(
            f"{name}: expected a mesh named '{name}' in "
            f"{os.path.relpath(path, _ROOT)}")
    if any(o.type == "ARMATURE" for o in bpy.data.objects):
        raise SystemExit(
            f"{name}: already has an armature. This transplants into a "
            "bare mesh — run it against a source restored from git.")

    before = set(bpy.data.objects)
    bpy.ops.wm.append(
        directory=os.path.join(donor_path, "Object") + os.sep,
        filename="Armature")
    added = [o for o in bpy.data.objects
             if o not in before and o.type == "ARMATURE"]
    if len(added) != 1:
        raise SystemExit(
            f"{name}: appending the donor armature brought "
            f"{[(o.name, o.type) for o in bpy.data.objects if o not in before]}")
    armature = added[0]

    # The donor armature arrives sized for the DONOR's body. Scale it so
    # its height span matches this body's, feet at the floor — both stand
    # at z=0 by import_glb_source's construction. Applied to the OBJECT,
    # unapplied, exactly like the import scale: blend_source bakes
    # matrix_world, and it keeps the armature-space bone lengths the
    # author_clips constants were tuned against.
    def world_height(obj) -> float:
        depsgraph = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(depsgraph)
        mesh = ev.to_mesh()
        zs = [(obj.matrix_world @ v.co).z for v in mesh.vertices]
        ev.to_mesh_clear()
        return max(zs)

    body_height = world_height(body)
    donor_height = max(
        (armature.matrix_world @ b.tail_local).z for b in armature.data.bones)
    # The skeleton's crown sits below the mesh's helmet tip on every rigged
    # body in the family (the head bone ends at the skull, not the helm), so
    # match on a shared fraction rather than exactly: bones at ~93% of mesh
    # height is what the rigged bodies measure.
    scale = (body_height * 0.93) / donor_height
    armature.scale = tuple(s * scale for s in armature.scale)
    bpy.context.view_layer.update()

    for obj in bpy.data.objects:
        obj.select_set(False)
    body.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    groups = len(body.vertex_groups)
    if groups < 20:
        raise SystemExit(
            f"{name}: automatic weighting produced only {groups} vertex "
            "groups — the bind failed (a mesh with disconnected shells "
            "sometimes defeats bone heat). Open it in blender-gui.")

    bpy.ops.wm.save_mainfile()
    print(f"  {name}: bound to {donor}'s skeleton "
          f"({len(armature.data.bones)} bones, {groups} vertex groups, "
          f"armature scaled x{scale:.3f})")
    print(f"  wrote {os.path.relpath(path, _ROOT)} — attach kit, then "
          "author clips")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="the bare body")
    parser.add_argument("--donor", default="militia",
                        help="rigged source whose skeleton to copy")
    args = parser.parse_args()
    transplant(args.name, args.donor)


if __name__ == "__main__":
    main()
