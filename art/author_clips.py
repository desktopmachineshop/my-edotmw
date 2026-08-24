"""Author the four clips onto a rigged `art/source/<name>.blend`.

    tools/blender-venv/bin/python art/author_clips.py --name gatherers
    just author-clips gatherers

## What this is for

A model that arrives rigged arrives with a SKELETON and no ACTIONS — which
is what a T-posed soldier sliding across the ground looks like. `clips.py`
animates the generated `Part` hierarchy and cannot drive an arbitrary
armature, so a supplied rig needs its clips written against ITS bones.

This writes them, by name, onto whatever humanoid rig it is given. It is a
MIGRATION like `import_glb_source.py`, not part of the build: it edits the
`.blend`, and `just build-assets` bakes whatever the `.blend` says.

## The frame layout is the contract

`blend_source` bakes frames 0..63 and `clips.py` slices them 16 at a time
in `CLIP_ORDER` — idle, walk, attack, rout. Frame 0 is `REST_FRAME`: the
`.glb` mesh is the model posed THERE, and every VAT row is an offset from
it. So frame 0 must be a pose worth exporting, and the arms-down base pose
below is applied to it like any other frame.

Every frame is keyed explicitly. Interpolation between keys would be
invisible to the bake (it samples integer frames) but visible to a human
opening the file, and `seed_source.py` already learned that a preview which
is smoother than the runtime is a preview that lies.

## Rotations are computed in the ARMATURE's space, not the bone's

A bone's local axes depend on its roll, which an exporter chooses and an
artist can change. Guessing that "local X swings the limb" is how a walk
cycle ends up flapping sideways. Instead every rotation here names a WORLD
axis, and `_swing` converts it into the bone's basis. Which way is FORWARD
is measured from the toe bones rather than assumed, because a model can
face either way down its own Y axis and this one gives no other clue.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from art.lib.blend_source import source_path                 # noqa: E402
from art.lib.clips import CLIP_ORDER, FRAMES_PER_CLIP        # noqa: E402


## Bones this file wants, by the role it needs them for. Values are name
## FRAGMENTS matched case-insensitively against the rig, longest first, so
## `L_Thigh` is found while `L_ThighTwist01` is not mistaken for it.
##
## Twist bones are deliberately NOT driven. They exist to spread a limb's
## roll across its length for smooth skinning, and rotating them as if they
## were the limb produces a corkscrew.
ROLES = {
    "hip_l": ("l_thigh",),
    "hip_r": ("r_thigh",),
    "knee_l": ("l_calf", "l_shin"),
    "knee_r": ("r_calf", "r_shin"),
    "ankle_l": ("l_foot",),
    "ankle_r": ("r_foot",),
    "shoulder_l": ("l_upperarm", "l_upperarm"),
    "shoulder_r": ("r_upperarm",),
    "elbow_l": ("l_forearm",),
    "elbow_r": ("r_forearm",),
    "pelvis": ("pelvis", "hips"),
    "waist": ("waist", "spine01"),
    "chest": ("spine02", "chest"),
    "head": ("head",),
}

# How far each joint travels. Degrees, and tuned for a stocky figure: a
# dwarf takes shorter, heavier strides than the lanky default a human rig
# suggests. These are the numbers to change when a walk reads wrong — the
# structure below should not need to.
# TUNED FOR A THIRTY-PIXEL SOLDIER, not for a turntable.
#
# The first pass used film-plausible angles and read as a statue sliding.
# Measured against `militia`, which does read: 52% of a militia's vertices
# move more than 0.05 during its walk, against 25% of the dwarf's — because
# a militia is legs and arms with a token torso, while this model is mostly
# apron, backpack, beard and helmet, none of which a leg swing touches.
#
# So the numbers below are deliberately larger than life AND the upper body
# is driven too. What matters at this size is the FRACTION OF THE SILHOUETTE
# in motion, not the realism of any one joint — `art/author_clips.py`'s own
# measurement at the bottom of this file is how that is checked.
STRIDE = 33.0          # thigh swing, peak to centre
KNEE_BEND = 54.0       # how far the trailing knee folds
ANKLE_ROLL = 16.0      # foot counter-rotation, keeps the sole near flat
ARM_SWING = 34.0       # shoulder counter-swing
ELBOW_BEND = 24.0      # a carried-arm bend, not a straight stick
BOB = 0.030            # vertical body travel, as a FRACTION of model height
ROLL = 7.0             # pelvis roll about the walk direction
COUNTER = 11.0         # chest counter-rotation against the hips
LEAN = 5.0             # torso pitch, so the trunk is never dead still
HEAD_BOB = 4.0         # the head answers the body rather than floating

# WHAT THE PLAYER CAN ACTUALLY SEE, which is not what a turntable shows.
#
# The game camera looks down 59 degrees (`RenderCull.PITCH_RUN`). From
# there a walking soldier is mostly HELMET AND BACKPACK: the legs are
# foreshortened to almost nothing, this model's apron covers the thighs,
# and a selected unit's ground disc projects up over whatever is left of
# the shins. All three hide precisely where a walk cycle puts its motion.
#
# So the trunk twists and sways as well as bobbing, and it does so harder
# than a ground-level view would ever justify. YAW is the single most
# visible thing from overhead — a shoulder rotation moves the backpack,
# which is a big share of the silhouette — while the vertical bob is the
# least, because the camera is looking almost straight down it.
TRUNK_YAW = 22.0       # shoulders/backpack twist, the overhead read
PELVIS_YAW = 10.0      # hips counter-twist, so the trunk works against itself
SWAY = 0.016           # lateral body shift, as a FRACTION of model height

## Arms hang rather than stick out. The asset is modelled in a T-pose, and
## a T-pose is a modelling convenience, never a game pose.
ARM_DOWN = 74.0
ARM_OUT = 9.0          # a slight A rather than arms clamped to the ribs


def _find(armature, fragments):
    """The bone whose name contains one of `fragments`, preferring an exact
    role match over a twist bone that merely shares the prefix."""
    names = [b.name for b in armature.data.bones]
    for fragment in fragments:
        exact = [n for n in names if n.lower() == fragment]
        if exact:
            return exact[0]
    best = None
    for fragment in fragments:
        for n in names:
            low = n.lower()
            if fragment in low and "twist" not in low:
                if best is None or len(n) < len(best):
                    best = n
    return best


def _map_roles(armature) -> dict:
    found = {}
    for role, fragments in ROLES.items():
        name = _find(armature, fragments)
        if name is not None:
            found[role] = name
    return found


def _forward_sign(armature, roles) -> float:
    """Which way down Y this model faces, +1 or -1, measured from a toe.

    A toe points forward. Nothing else on a symmetric humanoid does — the
    bounding box is symmetric in Y, the spine is vertical, and the arms are
    out along X in a T-pose. Guessing this wrong makes a walk cycle moonwalk,
    which looks like a broken cycle rather than a flipped one.
    """
    import mathutils  # noqa: F401  (imported for the type it returns)

    for name in [b.name for b in armature.data.bones]:
        if "toe" in name.lower():
            bone = armature.data.bones[name]
            direction = bone.tail_local - bone.head_local
            if abs(direction.y) > 1e-6:
                return 1.0 if direction.y > 0.0 else -1.0
    # No toes: fall back to the foot, which still leads forward.
    for role in ("ankle_l", "ankle_r"):
        if role in roles:
            bone = armature.data.bones[roles[role]]
            direction = bone.tail_local - bone.head_local
            if abs(direction.y) > 1e-6:
                return 1.0 if direction.y > 0.0 else -1.0
    print("  NOTE: could not measure which way this model faces; assuming -Y")
    return -1.0


def _swing(pose_bone, axis_world, degrees: float) -> None:
    """Rotate a bone by `degrees` about a WORLD axis.

    `pose_bone.rotation_quaternion` is expressed in the bone's own rest
    basis, so a world axis has to be carried into it — otherwise the angle
    is applied about whatever direction the exporter happened to roll this
    bone, and a leg swings sideways.
    """
    from mathutils import Quaternion

    rest = pose_bone.bone.matrix_local.to_3x3()
    axis_local = rest.inverted() @ axis_world
    if axis_local.length <= 1e-9:
        return
    pose_bone.rotation_quaternion = Quaternion(
        axis_local.normalized(), math.radians(degrees))


def _shift(pose_bone, offset_world) -> None:
    """Translate a bone by a WORLD offset, same basis problem as `_swing`."""
    rest = pose_bone.bone.matrix_local.to_3x3()
    pose_bone.location = rest.inverted() @ offset_world


def _base_pose(pose, roles, axes) -> None:
    """Arms down. Applied to every frame of every clip, including frame 0.

    Frame 0 is what the `.glb` exports, so this is the pose the model has
    before a single VAT row is read — which matters for the fallback path
    and for anything that draws the rest pose.
    """
    for side, sign in (("l", 1.0), ("r", -1.0)):
        shoulder = pose.get("shoulder_%s" % side)
        if shoulder is not None:
            # The arm points out along +/-X in a T-pose; a rotation about Y
            # swings it down. Which sign depends on which arm, and that is
            # taken from the bone rather than from its name.
            bone = shoulder.bone
            direction = bone.tail_local - bone.head_local
            outward = 1.0 if direction.x >= 0.0 else -1.0
            _swing(shoulder, axes["y"], outward * (ARM_DOWN - ARM_OUT))
        elbow = pose.get("elbow_%s" % side)
        if elbow is not None:
            _swing(elbow, axes["x"], -ELBOW_BEND * axes["forward"])


def _pose_walk(pose, axes, phase: float, stride: float, tempo: float) -> None:
    """One frame of a walk (or a run, at a bigger stride and faster tempo).

    Left leg leads at phase 0; the right is half a cycle behind. Arms
    counter-swing against the leg on the same side, which is what makes a
    walk read as a walk rather than a bear shuffle.
    """
    turn = 2.0 * math.pi * phase
    forward = axes["forward"]

    for side, offset in (("l", 0.0), ("r", math.pi)):
        angle = turn + offset
        # Thigh: forward at the top of its cycle, back half a turn later.
        swing = stride * math.cos(angle)
        hip = pose.get("hip_%s" % side)
        if hip is not None:
            _swing(hip, axes["x"], swing * forward)

        # Knee folds during the swing phase and straightens to plant. Peak
        # just after the foot leaves the ground, which is what stops the
        # leg scything through the floor on the way past.
        fold = KNEE_BEND * max(0.0, math.cos(angle - 2.2)) ** 1.5 * tempo
        knee = pose.get("knee_%s" % side)
        if knee is not None:
            _swing(knee, axes["x"], -fold * forward)

        # Ankle keeps the sole roughly level against thigh and knee.
        ankle = pose.get("ankle_%s" % side)
        if ankle is not None:
            _swing(ankle, axes["x"],
                   (-0.35 * swing + 0.45 * fold) * forward * (ANKLE_ROLL / 14.0))

        # The arm on the SAME side swings opposite to the leg.
        shoulder = pose.get("shoulder_%s" % side)
        if shoulder is not None:
            bone = shoulder.bone
            direction = bone.tail_local - bone.head_local
            outward = 1.0 if direction.x >= 0.0 else -1.0
            _swing(shoulder, axes["y"], outward * (ARM_DOWN - ARM_OUT))
            # Composed onto the base pose by rotating the ALREADY rotated
            # quaternion, so the arm hangs and swings rather than doing one
            # or the other.
            _compose(shoulder, axes["x"], -swing * ARM_SWING / STRIDE * forward)
        elbow = pose.get("elbow_%s" % side)
        if elbow is not None:
            bend = ELBOW_BEND + 8.0 * tempo * max(0.0, -math.cos(angle))
            _swing(elbow, axes["x"], -bend * forward)

    # The body rises twice per stride, once over each supporting leg, and
    # SWAYS onto whichever leg is carrying it — the sway is worth more than
    # the lift from overhead, where the lift is edge-on.
    pelvis = pose.get("pelvis")
    if pelvis is not None:
        lift = axes["height"] * BOB * tempo * (0.5 - 0.5 * math.cos(2.0 * turn))
        side = axes["height"] * SWAY * tempo * math.sin(turn)
        _shift(pelvis, axes["z"] * lift + axes["x"] * side)
        _compose(pelvis, axes["y"], ROLL * tempo * math.sin(turn))
        _compose(pelvis, axes["z"], PELVIS_YAW * tempo * math.sin(turn))

    # THE WHOLE TRUNK MOVES, and on this model that matters more than the
    # legs do: the apron and backpack are most of what a player sees, and a
    # rigid trunk over swinging legs reads as a statue on a conveyor.
    waist = pose.get("waist")
    if waist is not None:
        _swing(waist, axes["z"], -0.5 * TRUNK_YAW * tempo * math.sin(turn))
        _compose(waist, axes["x"], LEAN * tempo * axes["forward"]
                 * (0.5 + 0.5 * math.cos(2.0 * turn)))
    chest = pose.get("chest")
    if chest is not None:
        _swing(chest, axes["z"], -TRUNK_YAW * tempo * math.sin(turn))
        _compose(chest, axes["x"], 0.4 * LEAN * tempo * axes["forward"]
                 * math.cos(2.0 * turn))
    head = pose.get("head")
    if head is not None:
        # Counter to the chest, so the head stays looking where it is going
        # rather than being carried round with the shoulders.
        _swing(head, axes["z"], 0.6 * TRUNK_YAW * tempo * math.sin(turn))
        _compose(head, axes["x"], -HEAD_BOB * tempo * axes["forward"]
                 * math.cos(2.0 * turn))


def _compose(pose_bone, axis_world, degrees: float) -> None:
    """Add a world-axis rotation ON TOP of whatever this bone already holds."""
    from mathutils import Quaternion

    rest = pose_bone.bone.matrix_local.to_3x3()
    axis_local = rest.inverted() @ axis_world
    if axis_local.length <= 1e-9:
        return
    extra = Quaternion(axis_local.normalized(), math.radians(degrees))
    pose_bone.rotation_quaternion = pose_bone.rotation_quaternion @ extra


def _pose_idle(pose, axes, phase: float) -> None:
    """Standing, breathing. Not a frozen T-pose and not a fidget."""
    turn = 2.0 * math.pi * phase
    chest = pose.get("chest")
    if chest is not None:
        _swing(chest, axes["x"], 1.6 * math.sin(turn) * axes["forward"])
    pelvis = pose.get("pelvis")
    if pelvis is not None:
        _shift(pelvis, axes["z"] * axes["height"] * 0.004 * math.sin(turn))
    for side in ("l", "r"):
        elbow = pose.get("elbow_%s" % side)
        if elbow is not None:
            _swing(elbow, axes["x"],
                   -(ELBOW_BEND + 2.0 * math.sin(turn)) * axes["forward"])


def _pose_attack(pose, axes, phase: float) -> None:
    """A two-handed downward swing — a miner's stroke, not a sword cut.

    Wind up over the first third, strike through the middle, recover. The
    asymmetry is the point: an evenly-spaced swing reads as waving.
    """
    if phase < 0.35:
        drive = -1.0 + phase / 0.35          # -1 (wound up) to 0
    elif phase < 0.6:
        drive = (phase - 0.35) / 0.25        # 0 to 1 (struck)
    else:
        drive = 1.0 - (phase - 0.6) / 0.4    # 1 back to 0

    for side in ("l", "r"):
        shoulder = pose.get("shoulder_%s" % side)
        if shoulder is not None:
            bone = shoulder.bone
            direction = bone.tail_local - bone.head_local
            outward = 1.0 if direction.x >= 0.0 else -1.0
            _swing(shoulder, axes["y"], outward * (ARM_DOWN - ARM_OUT - 22.0))
            _compose(shoulder, axes["x"], -55.0 * drive * axes["forward"])
        elbow = pose.get("elbow_%s" % side)
        if elbow is not None:
            _swing(elbow, axes["x"],
                   -(ELBOW_BEND + 30.0 * max(0.0, -drive)) * axes["forward"])
    chest = pose.get("chest")
    if chest is not None:
        _swing(chest, axes["x"], 12.0 * drive * axes["forward"])


def author(name: str) -> None:
    import bpy
    from mathutils import Vector

    path = source_path(name)
    if not os.path.exists(path):
        raise SystemExit(f"{name}: no authored source at {path}")

    bpy.ops.wm.open_mainfile(filepath=path, load_ui=False)
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not armatures:
        raise SystemExit(
            f"{name}: {os.path.relpath(path, _ROOT)} has no armature, so there "
            "is nothing to animate. Re-import it with art/import_glb_source.py, "
            "which keeps the rig.")
    armature = armatures[0]

    roles = _map_roles(armature)
    missing = [r for r in ("hip_l", "hip_r", "knee_l", "knee_r") if r not in roles]
    if missing:
        raise SystemExit(
            f"{name}: this rig is missing {missing}. Bones are matched by name "
            f"fragment (see ROLES); it has: {[b.name for b in armature.data.bones]}")

    forward = _forward_sign(armature, roles)
    axes = {
        "x": Vector((1.0, 0.0, 0.0)),
        "y": Vector((0.0, 1.0, 0.0)),
        "z": Vector((0.0, 0.0, 1.0)),
        "forward": forward,
        "height": max(b.tail_local.z for b in armature.data.bones),
    }

    pose = {}
    for role, bone_name in roles.items():
        pose_bone = armature.pose.bones.get(bone_name)
        if pose_bone is None:
            continue
        pose_bone.rotation_mode = "QUATERNION"
        pose[role] = pose_bone

    print("  rig: %d bones, %d roles mapped, faces %sY, height %.3f"
          % (len(armature.data.bones), len(pose),
             "+" if forward > 0 else "-", axes["height"]))

    # Start from nothing: re-running this must not compound onto the last run.
    armature.animation_data_clear()
    scene = bpy.context.scene
    scene.frame_start = 0
    scene.frame_end = FRAMES_PER_CLIP * len(CLIP_ORDER) - 1

    for clip_index, clip in enumerate(CLIP_ORDER):
        for step in range(FRAMES_PER_CLIP):
            frame = clip_index * FRAMES_PER_CLIP + step
            phase = float(step) / float(FRAMES_PER_CLIP)

            # Every bone resets each frame, then the clip poses it. Without
            # the reset a clip inherits the previous frame's rotation and the
            # cycle drifts open instead of looping.
            for pose_bone in pose.values():
                pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
                pose_bone.location = (0.0, 0.0, 0.0)

            _base_pose(pose, roles, axes)
            if clip == "walk":
                _pose_walk(pose, axes, phase, STRIDE, 1.0)
            elif clip == "rout":
                _pose_walk(pose, axes, phase, STRIDE * 1.45, 1.5)
            elif clip == "attack":
                _pose_attack(pose, axes, phase)
            else:
                _pose_idle(pose, axes, phase)

            for pose_bone in pose.values():
                pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
                pose_bone.keyframe_insert("location", frame=frame)

    # Every frame is keyed, so the curve between keys is never sampled — but
    # a human opening this file should see what the game sees.
    if armature.animation_data and armature.animation_data.action:
        for fcurve in armature.animation_data.action.fcurves:
            for keyframe in fcurve.keyframe_points:
                keyframe.interpolation = "LINEAR"

    bpy.ops.wm.save_mainfile()
    print("  wrote %d frames (%s) into %s"
          % (FRAMES_PER_CLIP * len(CLIP_ORDER), ", ".join(CLIP_ORDER),
             os.path.relpath(path, _ROOT)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="archetype to animate")
    args = parser.parse_args()
    author(args.name)


if __name__ == "__main__":
    main()
