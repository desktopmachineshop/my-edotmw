"""Author a rigged `art/source/<name>.blend`'s clips onto its bones.

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

`blend_source` bakes `clips_for(name)` 16 frames at a time — the base four
for most of the roster, and three more work clips for the gatherer, who is
the only unit that carries tools. Frame 0 is `REST_FRAME`: the
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
from art.lib.clips import FRAMES_PER_CLIP, clips_for         # noqa: E402


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
    # Not driven by any clip — read, so a tool can be put in it. `_find`
    # prefers an exact match and skips twist bones, so this lands on the hand
    # rather than on a forearm twist that merely shares the prefix.
    "hand_l": ("l_hand",),
    "hand_r": ("r_hand",),
}

## Bones a clip may drive. `hand_*` are deliberately absent: they are read to
## place a tool and never posed, and keyframing them here would quietly
## override whatever a future rig does with fingers.
DRIVEN_ROLES = tuple(r for r in ROLES if not r.startswith("hand_"))

## The tool sockets `art/attach_tools.py` adds, and which clip draws each.
##
## A socket the rig does not have is simply skipped, so this file still runs
## unchanged against every other model in the roster — none of which carries
## a tool, and none of which should grow one by accident.
TOOL_SOCKETS = {
    "Tool_Axe": "chop",
    "Tool_Pick": "mine",
}

## Where the fist closes on the handle, in the HAND bone's own space.
##
## +Y is out through the fingers, so the small positive Y puts the grip just
## past the wrist and lets the handle run out of the fist rather than through
## the palm. The roll is about the handle: it turns an axe's blade square to
## the stroke instead of edge-on to it, which is the difference between
## chopping and waving a stick.
## Where the haft sits IN THE HAND, in the hand bone's own space.
##
## Measured, not chosen: with the fingers closed, this is the midpoint between
## the fingertip centroid and the knuckle centroid — the centre of the hole a
## closed fist makes. Hand-local (0.0299, 0.0756, -0.0138) on the right hand
## at the chop strike.
##
## It used to be (0, 0.035, 0): straight out along the bone from the wrist,
## which is close to the hand's AXIS but not to the space between the curled
## fingers and the palm. The fist closed and the haft lay across the back of
## it — the fingers were gripping thin air a centimetre from the handle.
GRIP_IN_HAND = (0.0299, 0.0756, -0.0138)
## The finger joints `art/attach_tools.py` adds, per hand, knuckles first.
##
## A rig without them is simply left alone, so this file still runs unchanged
## against every other model in the roster — none of which has fingers, and
## none of which should grow them by accident.
FINGER_BONES = {
    "r": ("R_Fingers", "R_FingerTips"),
    "l": ("L_Fingers", "L_FingerTips"),
}

## How far each joint folds, in degrees, for a hand CLOSED on a haft.
##
## Split across two joints rather than spent on one: a single 90-degree fold
## is a rigid flap, and the fingertips finish outside a haft 0.03 across
## instead of round it. 62 + 58 brings the tips back to the palm.
##
## Measured, not guessed: at these angles the fingertip centroid sits 0.014
## from the haft's own axis on the right hand, against a haft radius of about
## 0.015 — i.e. touching it. See `_assert_fingers_reach_the_haft`.
FINGER_CLOSED = (95.0, 90.0)

## The same for a hand holding nothing. Not zero: a flat splayed hand reads as
## a mannequin, and this rig's mitts are modelled fully open. A light curl is
## what a hand does at rest.
FINGER_RELAXED = (16.0, 14.0)

## Picking fruit — nearly closed, but a pinch rather than a grip.
FINGER_PICKING = (44.0, 40.0)

## Which way the fingers fold. The haft is collinear with the hand bone, so
## both signs close round it and this decides which way the knuckles face —
## chosen by looking at the render once, and stated here rather than buried
## in a sign somewhere.
FINGER_FOLD_SIGN = -1.0

## Which hand holds the tool, and which one joins it on the haft.
##
## `attach_tools` sockets every tool off the RIGHT hand (`GRIP_IN_HAND` is a
## point in that hand's space), so the lead is fixed here to match rather than
## being a number two files could disagree about.
LEAD_HAND = "r"
OFF_HAND = "l"

## How far down the haft from the leading hand the OFF hand takes hold, in
## mesh units, per clip.
##
## Both hands on one haft is what a felling axe and a pickaxe are actually
## swung with, and the first version did not do it: both arms followed the
## SAME arc with a small lateral nudge, so the off arm mimed the stroke
## empty-handed beside a tool only the leading hand held. The owner's playtest
## reported exactly that.
##
## Toward the BUTT, which is where the off hand goes on a two-handed swing:
## the leading hand rides up near the head for control and the off hand
## anchors low for leverage.
##
## Per clip because it is not only taste — it is REACH. An arm here is 0.21
## long (0.115 upper + 0.095 forearm), and `mine` holds the tool overhead
## where the off shoulder is furthest from it: at the axe's 0.06 the target
## sits past what the arm can span, the solve clamps, and the hand hangs 0.05
## short of the haft. Further down the haft is also lower, which is nearer the
## off shoulder — so the wider pick grip is what a dwarf would use and what
## the arm can actually reach.
##
## `mine` does NOT fully reach, and that is measured rather than hoped: swept
## at 0.11 / 0.15 / 0.19 / 0.23 the off hand settles 0.072 / 0.063 / 0.058 /
## 0.059 from the haft's axis, so it plateaus. Held overhead the pick's haft
## is simply outside a 0.21 arm reaching across 0.26 of shoulder — no grip
## point on it is close enough. The solve clamps, which leaves the arm fully
## extended POINTING at the haft; at the distance a gatherer is seen that
## reads as a two-handed grip, and it is far better than the off arm miming
## the stroke beside the tool. Narrowing the mine arc would close it, at the
## cost of the vertical stroke that tells a pick from an axe.
OFF_HAND_DOWN_HAFT = {"chop": 0.06, "mine": 0.19}
OFF_HAND_DOWN_HAFT_DEFAULT = 0.08

## How far the fingers must have folded, in degrees, before a hand counts as
## gripping rather than waving. Measured from the hand bone's own direction
## round to the fingertip bone's.
##
## ## Why this and not the distance to the haft
##
## The first version of this check measured the nearest fingertip to the
## haft's axis, and it was VACUOUS: with the grip sitting in the fist's hole
## the haft passes through where the OPEN fingers already are, so an open hand
## scored 0.0036 against a closed one's 0.0040. Zeroing the curl entirely left
## the check green.
##
## Which is this project's own oldest trap — a check that passes for a reason
## unrelated to the thing it is guarding — and it was caught only by
## deliberately breaking the feature and watching the guard not fire.
##
## The fold angle cannot do that: an unfolded hand is 0 by construction.
MIN_FINGER_FOLD_DEGREES = 60.0

GRIP_ROLL = {"Tool_Axe": 90.0, "Tool_Pick": 90.0}

## The two swings, as numbers rather than as prose.
##
## `wound` and `struck` are where the upper arm points at each end of the
## stroke, in `_sagittal` degrees — 0 hanging down, +90 reaching forward, -90
## reaching behind. `fold` is how far the elbow closes at the top of the
## wind-up, `lean` how far the trunk follows the stroke.
##
## Named constants rather than literals in the pose functions because these
## were TUNED against a measurement, not chosen: what a stroke has to do is
## move the tool's head a long way, mostly vertically, in front of the man —
## and the arm angle that achieves that is not the arm angle that sounds
## right, because the trunk carries the shoulders and the tool extends the
## forearm. `.scratch`-style eyeballing put the axe head RISING through the
## strike. See `art/tune_swing.py` for the probe.
## Each swing as an ARC the tool head travels, not a pair of angles.
##
## `wound` and `struck` are the directions the UPPER ARM points at the two
## ends of the stroke, in (forward, up, side) — forward is the way the model
## faces, side is its LEFT. The pose interpolates between them, so the whole
## shape of a stroke is these six numbers and a reader can see the plane it
## sweeps without picturing a quaternion.
##
## They replace a pair of angles in the sagittal plane plus a lateral offset,
## which is a fore-and-aft swing with the hands held out at the sides — the
## owner's report against the first build was that both crews "just wave the
## tool by their sides", and that formulation cannot do anything else. An arc
## between two arbitrary directions can cross the body; a sagittal angle
## cannot.
##
## `fold` is how far ALONG THE ARC the forearm runs ahead of the upper arm at
## the top of the wind-up, as a fraction of it. That is what puts the tool
## head behind the head rather than above the shoulder.
##
## `lean` is the trunk pitching into the stroke and `twist` its yaw. A chop
## has both — a diagonal blow turns the shoulders — and a vertical pick swing
## has almost no twist at all, which is a large part of what tells the two
## apart at thirty pixels.
CHOP = {
    # Up and back over the RIGHT shoulder, down and across to the LEFT front:
    # the diagonal a woodcutter actually swings, crossing the body.
    # Swept, not guessed. Measured as the axe head's own path: this reaches
    # z 0.910 on a model 0.795 tall — over the helmet, which is what makes a
    # stroke visible from a camera looking down 59 degrees — strikes at
    # x +0.083 (past the midline, so it really has crossed the body) and
    # y -0.335 (well out in front), sweeping 0.571 across.
    #
    # `fold` is the sensitive one and it trades against height: at 0.30 the
    # forearm leads so far round the arc that the hand is already coming down
    # while the shoulder is still going up, and the head tops out at 0.412 —
    # chest height, invisible from above.
    "wound": (-0.34, 0.90, -0.34),
    "struck": (0.34, -0.86, 0.38),
    # Lean was 30 and read as too deep in motion (the owner's playtest): a
    # 30-degree chest over a waist that follows at 0.55 of it folds the man
    # nearly 47 degrees at the strike, which is a bow rather than a chop.
    "lean": 18.0, "twist": 26.0, "fold": 0.14,
    # One big stroke: nearly half the cycle hauling back, a sixth striking.
    "raise_for": 0.45, "strike_for": 0.17, "rest": 0.62, "beats": 1,
}
MINE = {
    # Straight overhead and straight down, on the midline. A pick is swung
    # down into the ground in front of you, not across you.
    "wound": (-0.10, 0.99, 0.0),
    "struck": (0.18, -0.98, 0.0),
    "lean": 14.0, "twist": 4.0, "fold": 0.26,
    # Two shorter beats per cycle: a miner chips where a woodcutter hauls.
    "raise_for": 0.48, "strike_for": 0.19, "rest": 0.60, "beats": 2,
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
# ROUND THREE, from play again: "nothing during the main move but when the
# unit jostled around at the end they did the animation". The jostle is
# per-soldier TRANSFORM motion, which reads instantly; the march is a
# locked formation gliding, where the only cue is limb cycling — and this
# model's cycling happened INSIDE its own top-down silhouette (under the
# pack, behind the apron). Motion the outline never shows might as well
# not exist at this size. So the arms swing far enough fore-aft that the
# hands clear the body seen from above, and the knee folds far enough
# that a heel kicks up past the pack behind. The outline itself has to
# change shape, every half-cycle, or the march reads as sliding.
STRIDE = 38.0          # thigh swing, peak to centre
KNEE_BEND = 74.0       # trailing knee fold — kicks the heel up past the pack
ANKLE_ROLL = 16.0      # foot counter-rotation, keeps the sole near flat
ARM_SWING = 55.0       # hands clear the torso fore-and-aft, seen from above
ELBOW_BEND = 26.0      # a carried-arm bend, not a straight stick
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
TRUNK_YAW = 26.0       # shoulders/backpack twist, the overhead read
PELVIS_YAW = 12.0      # hips counter-twist, so the trunk works against itself
SWAY = 0.028           # lateral body shift, as a FRACTION of model height

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


def _point(pose_bone, target_world, parent_delta=None):
    """Rotate a bone so that it POINTS along `target_world`. Returns how far.

    `_swing` and `_compose` say how far to turn; this says where to end up,
    and for a limb that is very often the thing actually being described. An
    arm raised over the head and brought down through a stroke is one arc in
    world space; expressed as rotations about a T-posed bone's own axes it is
    a composition of three of them, and getting that composition slightly
    wrong does not look slightly wrong — it looks like the arm swinging out
    sideways, which is how this file's first pass at `chop` came out.

    Same basis problem as `_swing`, solved the same way: the rotation is built
    in world space and conjugated into the bone's rest basis, because
    `rotation_quaternion` is expressed there.

    ## `parent_delta` is not optional for a bone whose parent moved

    A pose bone's rotation is relative to its PARENT's pose, not to the world.
    So pointing an upper arm and then pointing the forearm the same way leaves
    the forearm carrying the shoulder's rotation twice, and the arm folds
    across the chest instead of extending — which is exactly what the second
    pass at `chop` did. Hand back what `_point` returned for the parent and
    the doubled rotation is divided out.

    Bones ABOVE the one whose delta is passed are deliberately not divided
    out: the trunk carries the shoulders, so a chest that folds into the
    stroke deepens it, which is wanted.
    """
    from mathutils import Vector

    bone = pose_bone.bone
    rest = bone.tail_local - bone.head_local
    target = Vector(target_world)
    if rest.length <= 1e-9 or target.length <= 1e-9:
        return None
    delta = rest.normalized().rotation_difference(target.normalized())
    own = delta if parent_delta is None else parent_delta.inverted() @ delta
    basis = bone.matrix_local.to_3x3()
    pose_bone.rotation_quaternion = (
        basis.inverted() @ own.to_matrix() @ basis).to_quaternion()
    return delta


def _reach(bpy, pose, side: str, target, pole, frame: int) -> None:
    """Put one hand ON `target`, by solving that arm's two bones for it.

    ## Why this is IK and not another pair of angles

    Every other pose in this file says where a limb POINTS, which is the right
    way to describe a swing. The off hand on a two-handed haft is the opposite
    kind of statement: it has to arrive at a POINT the other arm decides, frame
    by frame, and no fixed pair of angles can express that.

    Standard two-bone solve. Shoulder, elbow and hand form a triangle whose
    third side is the reach; the law of cosines gives how far off the straight
    line to the target the upper arm must sit. `pole` picks which way the elbow
    breaks out of the ring of otherwise equal solutions — outward from the
    body, or the arm bends backwards.

    A target further away than the arm is long is CLAMPED rather than refused:
    the hand falls short along the same line, which reads as a stretch instead
    of a dislocation.

    ## The bone is KEYED between the two halves, and that is not optional

    The forearm has to be aimed from where the elbow ENDS UP, which means the
    shoulder must already be posed when it is read. Setting the shoulder is
    not enough — `pose_bone.tail` is only as current as the last depsgraph
    evaluation, and evaluating re-applies the ACTION, which would throw the
    change away. So the shoulder is keyed first, and the update that follows
    reads it back out of the action. Same trap as `_key_tools`, two files
    apart.
    """
    from mathutils import Quaternion, Vector

    shoulder = pose.get("shoulder_%s" % side)
    forearm = pose.get("elbow_%s" % side)
    if shoulder is None or forearm is None:
        return

    upper_len = (shoulder.bone.tail_local - shoulder.bone.head_local).length
    fore_len = (forearm.bone.tail_local - forearm.bone.head_local).length
    origin = shoulder.head.copy()

    to_target = Vector(target) - origin
    reach = to_target.length
    if reach <= 1e-6 or upper_len <= 1e-6 or fore_len <= 1e-6:
        return
    direction = to_target / reach
    reach = min(max(reach, abs(upper_len - fore_len) + 1e-4),
                upper_len + fore_len - 1e-4)

    cos_off = ((upper_len * upper_len + reach * reach - fore_len * fore_len)
               / (2.0 * upper_len * reach))
    off = math.acos(max(-1.0, min(1.0, cos_off)))

    axis = direction.cross(Vector(pole))
    if axis.length <= 1e-6:
        axis = direction.cross(Vector((0.0, 0.0, 1.0)))
    if axis.length <= 1e-6:
        return
    axis.normalize()

    upper_dir = direction.copy()
    upper_dir.rotate(Quaternion(axis, off))
    _point_world(shoulder, upper_dir)
    shoulder.keyframe_insert("rotation_quaternion", frame=frame)
    shoulder.keyframe_insert("location", frame=frame)

    bpy.context.view_layer.update()
    fore_dir = Vector(target) - forearm.head
    if fore_dir.length > 1e-6:
        _point_world(forearm, fore_dir.normalized())
        forearm.keyframe_insert("rotation_quaternion", frame=frame)
        forearm.keyframe_insert("location", frame=frame)


def _point_world(pose_bone, target_world) -> None:
    """Swing a bone about its own HEAD until it points along `target_world`.

    `_point`'s sibling for the second pass. `_point` conjugates through the
    bone's REST basis and needs a moved parent divided out by hand; here the
    parents are already posed by the action, so the bone's current pose matrix
    is the honest frame to work from.

    The head is put back afterwards, and that is the whole subtlety: composing
    the rotation onto the pose matrix rotates the bone about the ARMATURE's
    origin, which does not swing a limb — it throws it across the room.
    """
    from mathutils import Matrix, Vector

    head = pose_bone.head.copy()
    current = pose_bone.tail - pose_bone.head
    if current.length <= 1e-9:
        return
    delta = current.normalized().rotation_difference(
        Vector(target_world).normalized())
    rotated = (delta.to_matrix() @ pose_bone.matrix.to_3x3()).to_4x4()
    rotated.translation = head
    pose_bone.matrix = rotated


def _sagittal(axes, degrees: float, lateral: float = 0.0):
    """A direction `degrees` around the swing plane, measured from STRAIGHT DOWN.

    0 is hanging down, +90 is reaching forward, +180 is straight up in front,
    -90 is reaching behind. `lateral` pushes it out to the side, which is all
    the two arms of a two-handed grip need to stop overlapping.

    Which way is forward comes from `axes["forward"]`, measured off the model's
    own toes — see `_forward_sign`. Every angle in the work clips below is
    stated in these terms, so a pose can be read off the numbers.
    """
    turn = math.radians(degrees)
    forward = axes["y"] * axes["forward"]
    direction = forward * math.sin(turn) - axes["z"] * math.cos(turn)
    return (direction + axes["x"] * lateral).normalized()


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


def _arc_dir(axes, triple):
    """A (forward, up, side) triple as a world direction.

    `side` is the model's LEFT, so a right-handed swing winds up at negative
    side and strikes through positive — which is what makes it cross the body
    instead of hanging off the shoulder it started on.
    """
    forward, up, side = triple
    return (axes["y"] * axes["forward"] * forward
            + axes["z"] * up
            + axes["x"] * side).normalized()


def _two_handed_swing(pose, axes, drive: float, wound, struck,
                      lean: float, twist: float, fold: float) -> None:
    """Both arms driving one tool along an ARC, at `drive` in [-1, 1].

    -1 is wound up, +1 is the far end of the stroke. The upper arm is slerped
    between the two directions, and the forearm runs the same arc a little
    further ahead — so a fold is "more of the same stroke" rather than a
    second rotation about some other axis, and the hand path stays in one
    plane the whole way down.

    Shared by `chop` and `mine`, because the difference between felling a
    tree and working a seam is WHICH ARC and how it is timed, not a different
    body. That is also why the two read as distinct at thirty pixels.
    """
    from mathutils import Vector

    start = _arc_dir(axes, wound)
    finish = _arc_dir(axes, struck)
    travelled = (drive + 1.0) * 0.5
    # The forearm leads the upper arm through the wind-up, which is what puts
    # the head of the tool behind the shoulder rather than above it.
    lead = min(1.0, travelled + fold * max(0.0, -drive))

    upper = start.slerp(finish, travelled)
    fore = start.slerp(finish, lead)

    # Both hands are on one haft, so both arms follow one arc. The small
    # opposing nudge keeps the two from occupying the same space without
    # letting them drift into separate swings.
    # Both arms follow the arc HERE, and the off arm is then overwritten in
    # the second pass once the haft has a real position to reach for
    # (`_key_tools`). Posing it now anyway keeps the first pass a complete
    # animation in its own right, which is what a human scrubbing the file
    # sees if the second pass is ever skipped.
    for side, nudge in (("l", 0.09), ("r", -0.09)):
        shoulder = pose.get("shoulder_%s" % side)
        carried = None
        if shoulder is not None:
            carried = _point(shoulder, (upper + axes["x"] * nudge).normalized())
        forearm = pose.get("elbow_%s" % side)
        if forearm is not None:
            _point(forearm, (fore + axes["x"] * nudge * 0.5).normalized(),
                   parent_delta=carried)

    chest = pose.get("chest")
    if chest is not None:
        _swing(chest, axes["x"], lean * drive * axes["forward"])
        # Yaw INTO the stroke. A diagonal blow turns the shoulders through
        # it; without this the arms swing across a trunk that stays square,
        # which is most of what reads as waving rather than chopping.
        _compose(chest, axes["z"], -twist * drive)
    waist = pose.get("waist")
    if waist is not None:
        _swing(waist, axes["x"], 0.55 * lean * drive * axes["forward"])
        _compose(waist, axes["z"], -0.45 * twist * drive)
    head = pose.get("head")
    if head is not None:
        # The head follows the work down. A miner watching the sky while his
        # arms come down is the single most obvious thing wrong with a swing.
        _swing(head, axes["x"], 0.30 * lean * drive * axes["forward"])
    pelvis = pose.get("pelvis")
    if pelvis is not None:
        _shift(pelvis, axes["z"] * axes["height"] * -0.05 * max(drive, 0.0))


def _swing_drive(phase: float, raise_for: float, strike_for: float,
                 rest: float) -> float:
    """One stroke's timing, as `drive` in [-1, 1], and it MUST loop.

    -1 is wound up, +1 is the far end of the stroke. `raise_for` is the share
    of the cycle spent hauling the tool back and `strike_for` the share spent
    bringing it down; whatever is left is the settle.

    `rest` is where the cycle both starts and ends, and it carries two jobs.

    It has to be the pose the man HOLDS between strokes, because that is where
    the cycle spends its slowest moments — and `drive` maps onto an arc from
    overhead to the ground, so a rest near zero is the arm HALFWAY, sticking
    straight out in front. That is what the first arc version did, and a crew
    of dwarves holding their axes out at arm's length is not a rest pose. It
    belongs well down the arc, near where a tool hangs.

    It also has to be the same at both ends, because a clip is sampled at 16
    discrete frames and looped: a stroke that ended anywhere else would snap
    back across the seam in one frame. An earlier version recovered to 0 and
    restarted at -1 — 135 degrees of arm in a sixteenth of a second, which
    read as a twitch rather than a rhythm.
    """
    if phase < raise_for:
        return rest + (-1.0 - rest) * (phase / raise_for)
    if phase < raise_for + strike_for:
        return -1.0 + 2.0 * (phase - raise_for) / strike_for
    settle = 1.0 - raise_for - strike_for
    return 1.0 + (rest - 1.0) * (phase - raise_for - strike_for) / settle


def _close_hands(fingers: dict, amounts) -> None:
    """Fold both hands' finger joints by `amounts` (knuckle, mid) in degrees.

    Rotated about each bone's own local X, which `attach_tools` aligned ACROSS
    the knuckles when it set the bones' roll — so this is a fold, not a splay,
    without needing to know which way the hand is pointing at the time.
    """
    from mathutils import Quaternion, Vector

    for names in fingers.values():
        for bone, degrees in zip(names, amounts):
            if bone is None:
                continue
            bone.rotation_quaternion = Quaternion(
                Vector((1.0, 0.0, 0.0)),
                math.radians(degrees * FINGER_FOLD_SIGN))


def _pose_swing(pose, axes, phase: float, spec: dict) -> None:
    """One work stroke, timing and geometry both taken from `spec`.

    `beats` is how many strokes fill a cycle. It is the whole difference
    between felling and mining at the size a gatherer is seen: a woodcutter
    hauls back and swings once, a miner chips twice, and that rhythm reads
    from further away than either arm angle does.
    """
    beat = (phase * spec["beats"]) % 1.0
    drive = _swing_drive(beat, spec["raise_for"], spec["strike_for"],
                         spec["rest"])
    _two_handed_swing(pose, axes, drive, spec["wound"], spec["struck"],
                      spec["lean"], spec["twist"], spec["fold"])


def _pose_chop(pose, axes, phase: float) -> None:
    """Felling: one big axe stroke per cycle, over the shoulder and down.

    Diagonal, and that is the point — up and back over the right shoulder,
    down and across the front to the left. Slower and wider than `attack`,
    because what reads as an axe blow at this size is the SPEED DIFFERENCE
    between raising and striking; an evenly paced arc is a man waving.
    """
    _pose_swing(pose, axes, phase, CHOP)


def _pose_mine(pose, axes, phase: float) -> None:
    """Working a seam: TWO shorter pickaxe strokes per cycle, straight down.

    Vertical where `chop` is diagonal, and twice where `chop` is once. Those
    two differences are what tell a player which crew is which without being
    told — a woodcutter hauls back and swings across himself, a miner lifts
    over his head and chips down in front.
    """
    _pose_swing(pose, axes, phase, MINE)


def _pose_forage(pose, axes, phase: float) -> None:
    """Gathering by hand: stoop, pick, straighten. No tool leaves the back.

    The one work clip with no impact in it, and that is its whole job — a crew
    at a fruit tree must not read like a crew at an oak. So it is built on a
    smooth `cos` rather than the timed drive the two swings share: there is no
    moment in this cycle that wants to be fast.
    """
    stoop = 0.5 - 0.5 * math.cos(2.0 * math.pi * phase)
    sway = math.sin(2.0 * math.pi * phase)
    forward = axes["forward"]

    for side, lateral in (("l", 0.34), ("r", -0.34)):
        shoulder = pose.get("shoulder_%s" % side)
        carried = None
        if shoulder is not None:
            carried = _point(shoulder, _sagittal(axes, 16.0 + 40.0 * stoop,
                                                 lateral + 0.10 * sway))
        forearm = pose.get("elbow_%s" % side)
        if forearm is not None:
            # The forearms come UP relative to the upper arm as the body
            # folds, so the hands stay out in front of the chest instead of
            # ploughing into the ground the man is stooping over.
            _point(forearm, _sagittal(axes, 34.0 + 52.0 * stoop,
                                      lateral * 0.45 + 0.14 * sway),
                   parent_delta=carried)

    chest = pose.get("chest")
    if chest is not None:
        _swing(chest, axes["x"], 24.0 * stoop * forward)
    waist = pose.get("waist")
    if waist is not None:
        _swing(waist, axes["x"], 22.0 * stoop * forward)
    head = pose.get("head")
    if head is not None:
        _swing(head, axes["x"], 13.0 * stoop * forward)
    # Knees take the stoop. A back that folds over locked legs is the pose
    # every safety poster is about, and it looks it.
    for side in ("l", "r"):
        knee = pose.get("knee_%s" % side)
        if knee is not None:
            _swing(knee, axes["x"], -28.0 * stoop * forward)
    pelvis = pose.get("pelvis")
    if pelvis is not None:
        _shift(pelvis, axes["z"] * axes["height"] * -0.06 * stoop)


def _key_tools(bpy, armature, sockets, pose, clips) -> None:
    """Second pass: put each clip's tool in the hand, and key it there.

    ## Why this cannot be done in the same pass as the body

    A socket's pose is derived from the HAND's, and the hand's pose matrix is
    only correct once the depsgraph has evaluated the arm. Asking for it in
    the middle of posing means asking the depsgraph to evaluate — and by then
    the armature HAS an action, because the earlier frames have been keyed, so
    what comes back is the action sampled at whatever frame the scene happens
    to be sitting on. Not the pose just set.

    Measured before this was split out: the hand tracked 0.598, 0.647, 0.516,
    0.349, 0.484, 0.668 up and down the chop cycle — the arc of no arm, and
    the axe faithfully followed it. The socket machinery was right the whole
    time and was being handed the wrong hand.

    So the body is keyed first, and then the scene is SCRUBBED frame by frame
    so that the action itself poses the arm. `pose_bone.matrix` is then the
    real thing, and what gets keyed onto the socket is where the tool actually
    belongs.

    A socket is keyed on EVERY frame, including the ones where its tool stays
    on the back: an unkeyed channel would hold whatever the previous clip left
    there, and the axe would ride the hand through `walk`.
    """
    hand = pose.get("hand_%s" % LEAD_HAND)
    if hand is None or not sockets:
        return
    from mathutils import Matrix, Vector

    scene = bpy.context.scene
    for clip_index, clip in enumerate(clips):
        for step in range(FRAMES_PER_CLIP):
            frame = clip_index * FRAMES_PER_CLIP + step
            scene.frame_set(frame)
            for bone_name, socket in sockets.items():
                if TOOL_SOCKETS.get(bone_name) == clip:
                    grip = (
                        Matrix.Translation(Vector(GRIP_IN_HAND))
                        @ Matrix.Rotation(
                            math.radians(GRIP_ROLL.get(bone_name, 0.0)), 4, "Y"))
                    socket.matrix = hand.matrix @ grip
                else:
                    # Identity IS the stowed pose — the socket's rest
                    # transform is where `attach_tools.py` strapped the tool.
                    socket.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
                    socket.location = (0.0, 0.0, 0.0)
                socket.keyframe_insert("rotation_quaternion", frame=frame)
                socket.keyframe_insert("location", frame=frame)

            # The OFF hand joins the leading one on the same haft, lower down.
            #
            # It belongs in THIS pass for the same reason the tool does: where
            # the haft is depends on where the leading arm ended up, and that
            # is only real once the action poses it. Solved in pass one it
            # would reach for last frame's hand — the bug `_key_tools`'
            # docstring is about, in a second place.
            # Asked of the CLIP, not of `bone_name`: that name is the socket
            # loop's variable and by here it holds whichever socket came last,
            # so the check fired for `mine` and never for `chop` — a leaked
            # loop variable reading as "the off hand works on one tool only".
            if clip in TOOL_SOCKETS.values():
                _grip_off_hand(bpy, armature, pose, frame, clip)


def _grip_off_hand(bpy, armature, pose, frame: int, clip: str) -> None:
    """Put the off hand on the haft, below the leading hand, and key it.

    The haft runs along the leading hand's own direction — that is exactly
    what put the tool there a moment ago — so a point down it is the leading
    hand's position stepped back along that direction. `OFF_HAND_DOWN_HAFT`
    is how far, toward the butt.

    The elbow is poled AWAY from the chest so the arm breaks outward like an
    arm; poled the other way a two-handed grip folds the off elbow through
    the ribs.
    """
    from mathutils import Vector

    lead = pose.get("hand_%s" % LEAD_HAND)
    shoulder = pose.get("shoulder_%s" % OFF_HAND)
    if lead is None or shoulder is None:
        return
    bpy.context.view_layer.update()
    along = (lead.tail - lead.head).normalized()
    target = lead.head - along * OFF_HAND_DOWN_HAFT.get(
        clip, OFF_HAND_DOWN_HAFT_DEFAULT)

    # Pole outward: away from the body's midline, on the off hand's own side.
    pole = Vector((shoulder.head.x, 0.0, 0.0))
    if pole.length <= 1e-6:
        pole = Vector((1.0, 0.0, 0.0))
    _reach(bpy, pose, OFF_HAND, target, pole.normalized(), frame)


def _assert_hands_grip(armature, fingers, name: str) -> None:
    """Refuse a model whose fists do not close.

    The point of the finger joints is invisible to every other check: a hand
    that stays flat open beside a haft is still the right hand, in the right
    place, holding the tool by the right point — it simply is not gripping it,
    which is what the owner reported of the first version.

    Measured off the POSED BONES rather than the mesh: the angle from the hand
    bone's own direction round to the fingertip bone's is exactly "how far the
    fingers have folded", it needs no depsgraph evaluation, and — unlike the
    distance-to-haft measure it replaces — an open hand cannot score well on
    it by accident.
    """
    if not fingers:
        return
    for side, held in fingers.items():
        hand_name = FINGER_BONES[side][0].rsplit("_", 1)[0] + "_Hand"
        hand = armature.pose.bones.get(hand_name)
        tip = held[-1]
        if hand is None:
            continue
        straight = (hand.tail - hand.head).normalized()
        folded = (tip.tail - tip.head).normalized()
        angle = math.degrees(straight.angle(folded))
        if angle < MIN_FINGER_FOLD_DEGREES:
            raise SystemExit(
                f"{name}: {hand_name}'s fingers fold only {angle:.1f} degrees, "
                f"under the {MIN_FINGER_FOLD_DEGREES} that counts as a grip — "
                "the hand is open beside the tool rather than closed on it. "
                "Check FINGER_CLOSED and FINGER_FOLD_SIGN.")
        print(f"  grip:  {hand_name} folds {angle:.1f} degrees "
              f"(minimum {MIN_FINGER_FOLD_DEGREES:.0f})")


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

    # Tool sockets, if this rig has any (`art/attach_tools.py`). Kept apart
    # from `pose` because they are placed by a matrix rather than posed by an
    # angle, and because every other model in the roster has none.
    sockets = {}
    for bone_name in sorted(TOOL_SOCKETS):
        socket = armature.pose.bones.get(bone_name)
        if socket is not None:
            socket.rotation_mode = "QUATERNION"
            sockets[bone_name] = socket

    # The finger joints, if this rig has any. Kept out of `driven` because
    # they are set per CLIP rather than per frame of a pose function, and
    # because every other model in the roster has none.
    fingers = {}
    for side, names in FINGER_BONES.items():
        held = [armature.pose.bones.get(name) for name in names]
        if all(bone is not None for bone in held):
            for bone in held:
                bone.rotation_mode = "QUATERNION"
            fingers[side] = held
    if fingers and len(fingers) != len(FINGER_BONES):
        raise SystemExit(
            f"{name}: this rig has finger joints on one hand and not the "
            "other, so one fist would close and the other stay open. Re-run "
            "art/attach_tools.py against a source restored from git.")

    driven = {role: pose[role] for role in DRIVEN_ROLES if role in pose}

    clips = clips_for(name)
    missing_socket = [b for b, clip in TOOL_SOCKETS.items()
                      if clip in clips and b not in sockets]
    if missing_socket:
        raise SystemExit(
            f"{name}: bakes {[TOOL_SOCKETS[b] for b in missing_socket]} but has "
            f"no {missing_socket} bone to hold the tool. Run "
            "art/attach_tools.py first — a work clip with nothing in the fist "
            "is a soldier miming.")

    print("  rig: %d bones, %d roles mapped, %d tool socket(s), %d hand(s) "
          "that grip, faces %sY, height %.3f"
          % (len(armature.data.bones), len(driven), len(sockets), len(fingers),
             "+" if forward > 0 else "-", axes["height"]))

    # Start from nothing: re-running this must not compound onto the last run.
    armature.animation_data_clear()
    scene = bpy.context.scene
    scene.frame_start = 0
    scene.frame_end = FRAMES_PER_CLIP * len(clips) - 1

    for clip_index, clip in enumerate(clips):
        for step in range(FRAMES_PER_CLIP):
            frame = clip_index * FRAMES_PER_CLIP + step
            phase = float(step) / float(FRAMES_PER_CLIP)

            # Every bone resets each frame, then the clip poses it. Without
            # the reset a clip inherits the previous frame's rotation and the
            # cycle drifts open instead of looping. A socket reset to identity
            # is the tool back on its owner's back, which is what every clip
            # but one wants.
            for pose_bone in driven.values():
                pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
                pose_bone.location = (0.0, 0.0, 0.0)

            # The hands close on the clip, not on the frame: a fist that
            # opened and shut through a stroke would be a man losing his grip.
            if clip in ("chop", "mine"):
                _close_hands(fingers, FINGER_CLOSED)
            elif clip == "forage":
                _close_hands(fingers, FINGER_PICKING)
            else:
                _close_hands(fingers, FINGER_RELAXED)

            _base_pose(driven, roles, axes)
            if clip == "walk":
                _pose_walk(driven, axes, phase, STRIDE, 1.0)
            elif clip == "rout":
                _pose_walk(driven, axes, phase, STRIDE * 1.45, 1.5)
            elif clip == "attack":
                _pose_attack(driven, axes, phase)
            elif clip == "chop":
                _pose_chop(driven, axes, phase)
            elif clip == "mine":
                _pose_mine(driven, axes, phase)
            elif clip == "forage":
                _pose_forage(driven, axes, phase)
            else:
                _pose_idle(driven, axes, phase)

            for pose_bone in driven.values():
                pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
                pose_bone.keyframe_insert("location", frame=frame)
            for held in fingers.values():
                for pose_bone in held:
                    pose_bone.keyframe_insert(
                        "rotation_quaternion", frame=frame)

    # The tools go on afterwards, off the arms this pass just keyed — see
    # `_key_tools` for why that ordering is load-bearing rather than tidy.
    _key_tools(bpy, armature, sockets, pose, clips)

    # On a clip that actually holds something. The scene is left wherever
    # `_key_tools` finished, so scrub to a tool clip's strike first — the pose
    # bones read whatever frame the action is sitting on.
    for bone_name, clip in TOOL_SOCKETS.items():
        if clip not in clips or bone_name not in sockets:
            continue
        scene.frame_set(clips.index(clip) * FRAMES_PER_CLIP + 10)
        bpy.context.view_layer.update()
        _assert_hands_grip(armature, fingers, name)
        break

    # Every frame is keyed, so the curve between keys is never sampled — but
    # a human opening this file should see what the game sees.
    if armature.animation_data and armature.animation_data.action:
        for fcurve in armature.animation_data.action.fcurves:
            for keyframe in fcurve.keyframe_points:
                keyframe.interpolation = "LINEAR"

    bpy.ops.wm.save_mainfile()
    print("  wrote %d frames (%s) into %s"
          % (FRAMES_PER_CLIP * len(clips), ", ".join(clips),
             os.path.relpath(path, _ROOT)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="archetype to animate")
    args = parser.parse_args()
    author(args.name)


if __name__ == "__main__":
    main()
