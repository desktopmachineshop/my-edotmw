"""Animation clips, as pure functions of phase (D-065).

A clip is `f(phase) -> Pose` where phase runs 0..1 and wraps. Nothing here
holds state, and no frame is computed from the frame before it — the bake can
evaluate frame 9 without having evaluated frame 8, and does so in whatever order
it likes. That purity is the offline mirror of the runtime rule D-065 turns on:
phase is derived, never accumulated.

## Parts move in groups, and the groups are what clips address

A spear is not animated; the arm holding it is, and the spear inherits that
rotation because it shares the shoulder pivot. Addressing groups rather than
parts is what lets one `walk` clip serve a spearman, an archer and an axeman
without knowing which kit each is carrying.

## The clips are chosen for what they have to communicate

- `idle` and `walk` are the ambient states.
- `attack` exists because combat (D-024) currently resolves with no visible
  cause: casualties appear and nothing on screen swung at anything.
- `rout` exists because D-019's morale break has been in the simulation since M2
  and has never once been legible on screen. It is criterion 7 of D-063 and it
  is deliberately the most exaggerated clip here — a routing squad should be
  readable at a glance, at the distance the game is actually played at.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from .geom import Vec3

# Which group each part follows. A part not named here does not move.
GROUP_OF: dict[str, str] = {
    "leg_l": "leg_l",
    "leg_r": "leg_r",
    "torso": "torso",
    "cloak": "torso",
    "arm_l": "left_arm",
    "shield": "left_arm",
    "arm_r": "right_arm",
    "weapon": "right_arm",
    "spearhead": "right_arm",
    "axehead": "right_arm",
    "head": "head",
    "helmet": "head",
    "crest": "head",
    "horn_l": "head",
    "horn_r": "head",
    # A horse trots on diagonal pairs, so its legs reuse the infantry leg
    # groups rather than needing clips of their own. `clips` therefore contains
    # no concept of a horse at all.
    "horse_leg_fl": "leg_l",
    "horse_leg_rr": "leg_l",
    "horse_leg_fr": "leg_r",
    "horse_leg_rl": "leg_r",
    "horse_tail": "torso",
    "horse_neck": "head",
    "horse_head": "head",
}

FRAMES_PER_CLIP = 16

# Clip order is the wire order: the shader selects a clip by index, and
# `animation_state.gd` must agree with this list. Changing the order without
# changing both is a silent mismatch, so the names are exported and asserted
# against the Godot side by a test.
#
# ## This is the INDEX SPACE, not what any one model carries
#
# Every archetype used to bake all four of these, so "the clip list" and "this
# model's clips" were the same tuple and nobody had to tell them apart. The
# gatherer's work clips broke that: an axe stroke is worth 16 frames on the one
# unit that owns an axe and is 48 wasted VAT rows on every soldier who does
# not.
#
# So CLIP_ORDER is the numbering — index 4 means `chop` for everyone, whether
# or not they have one — and `clips_for` says which PREFIX of it a given model
# actually bakes. The prefix property is load-bearing: the shader finds a frame
# at `clip * frames_per_clip + local`, so a model's clips must occupy indices
# 0..n-1 with no gaps, and `_assert_prefix` below refuses any other
# arrangement rather than leaving it to be discovered as a soldier playing the
# wrong animation.
#
# A model asked for a clip it did not bake is resolved on the CPU
# (`UnitMesh.clip_index`), never in the shader: sampling row 4 of a 4-clip VAT
# is not an error, it is the NORMALS block, and a militia would come apart
# rather than fail.
CLIP_ORDER = ("idle", "walk", "attack", "rout", "chop", "mine", "forage")

# What every model bakes, and has since M7.
BASE_CLIPS = ("idle", "walk", "attack", "rout")

# What a given archetype bakes ON TOP of the base four.
#
# Keyed by ARCHETYPE, never by civ — both civs' gatherers are one model, so a
# thrall and a colonus swing the same axe (D-046 criterion 3).
EXTRA_CLIPS: dict[str, tuple[str, ...]] = {
    # The work clips. A crew rings a node and looked identical whether it was
    # felling a tree, cutting a seam or picking fruit; these are what make the
    # tools on its back mean something.
    "gatherers": ("chop", "mine", "forage"),
}


def clips_for(name: str) -> tuple[str, ...]:
    """The clips `name` bakes: a PREFIX of CLIP_ORDER, base four first."""
    clips = BASE_CLIPS + EXTRA_CLIPS.get(name, ())
    _assert_prefix(name, clips)
    return clips


def _assert_prefix(name: str, clips: tuple[str, ...]) -> None:
    if tuple(CLIP_ORDER[:len(clips)]) != clips:
        raise SystemExit(
            f"{name}: clips {clips} are not a prefix of CLIP_ORDER "
            f"{CLIP_ORDER}. The shader indexes rows arithmetically, so a gap "
            "would silently play a different animation — reorder CLIP_ORDER so "
            "the base four come first and every extra follows them.")


@dataclass
class Pose:
    """Rotations per group, plus a whole-body offset."""

    rotations: dict[str, list[tuple[str, float]]] = field(default_factory=dict)
    offset: Vec3 = (0.0, 0.0, 0.0)


def _swing(phase: float) -> float:
    return math.sin(math.tau * phase)


def idle(phase: float) -> Pose:
    """Breathing and a slight weight shift. Small on purpose.

    An idle army fills most of the screen most of the time; anything with real
    amplitude here reads as twitching rather than as life.
    """
    breath = math.sin(math.tau * phase) * 0.5 + 0.5
    return Pose(
        rotations={
            "torso": [("x", -0.012 * breath)],
            "left_arm": [("x", 0.045 * breath)],
            "right_arm": [("x", 0.04 * breath)],
            "head": [("y", 0.05 * math.sin(math.tau * phase))],
        },
        offset=(0.0, 0.012 * breath, 0.0),
    )


def walk(phase: float) -> Pose:
    """A march. Legs lead, arms counter-swing, body bobs twice per cycle."""
    s = _swing(phase)
    bob = abs(math.sin(math.tau * phase)) * 0.035
    return Pose(
        rotations={
            "leg_l": [("x", 0.52 * s)],
            "leg_r": [("x", -0.52 * s)],
            "left_arm": [("x", -0.34 * s)],
            "right_arm": [("x", 0.30 * s)],
            "torso": [("y", 0.07 * s)],
            "head": [("y", -0.05 * s)],
        },
        offset=(0.0, bob, 0.0),
    )


def attack(phase: float) -> Pose:
    """A thrust: wind up over the first third, strike, recover.

    Asymmetric in time rather than a sine, because a symmetric swing reads as
    waving. The strike wants to be fast and the recovery slow.
    """
    if phase < 0.35:
        t = phase / 0.35
        drive = -0.45 * t                     # wind back
    elif phase < 0.55:
        t = (phase - 0.35) / 0.20
        drive = -0.45 + 1.6 * t               # strike
    else:
        t = (phase - 0.55) / 0.45
        drive = 1.15 * (1.0 - t)              # recover
    return Pose(
        rotations={
            "right_arm": [("x", -drive)],
            "left_arm": [("x", 0.25 * drive)],
            "torso": [("y", -0.20 * drive), ("x", -0.06 * drive)],
            "head": [("y", -0.10 * drive)],
            "leg_l": [("x", 0.10 * drive)],
        },
        offset=(0.0, 0.0, 0.05 * max(drive, 0.0)),
    )


def rout(phase: float) -> Pose:
    """A broken run: fast, wide, arms up, pitched forward.

    Deliberately over-acted. This is the clip that has to be readable when the
    squad is 40 soldiers of 12 pixels each, and subtlety at that size is
    indistinguishable from `walk`.
    """
    s = _swing(phase)
    bob = abs(math.sin(math.tau * phase)) * 0.055
    return Pose(
        rotations={
            # Wider and faster than `walk`, but NOT so wide that the legs read
            # as splits. The first attempt used 0.95 rad each way — 108 degrees
            # between the legs — and the preview showed a figure falling over
            # rather than running. Silhouette, not amplitude, is what carries
            # this at 12 pixels tall.
            "leg_l": [("x", 0.68 * s)],
            "leg_r": [("x", -0.68 * s)],
            # Arms thrown up and forward. The forward lean does the work of
            # saying "fleeing"; the arms only have to not look like marching.
            "left_arm": [("x", -0.62 + 0.28 * s), ("z", -0.30)],
            "right_arm": [("x", -0.62 - 0.28 * s), ("z", 0.30)],
            "torso": [("x", 0.20), ("y", 0.10 * s)],
            "head": [("x", -0.12), ("y", 0.16 * s)],
        },
        offset=(0.0, bob, 0.0),
    )


def _stroke(phase: float, raise_for: float, strike_for: float,
            rest: float = 0.2) -> float:
    """One stroke's timing, as `drive` in [-1, 1], and it MUST loop.

    -1 is wound up, +1 is the far end of the stroke. `rest` is where the cycle
    both starts and ends: a clip is sampled at 16 discrete frames and looped,
    so a stroke recovering to anything else snaps back across the seam in one
    frame — 135 degrees of arm in a sixteenth of a second, which reads as a
    twitch rather than a rhythm. Mirrors `author_clips._swing_drive`, which is
    the same rule for a real rig.
    """
    if phase < raise_for:
        return rest + (-1.0 - rest) * (phase / raise_for)
    if phase < raise_for + strike_for:
        return -1.0 + 2.0 * (phase - raise_for) / strike_for
    settle = 1.0 - raise_for - strike_for
    return 1.0 + (rest - 1.0) * (phase - raise_for - strike_for) / settle


def chop(phase: float) -> Pose:
    """Felling a tree: a two-handed axe stroke, over the shoulder and down.

    Wider and slower than `attack`, because a woodcutter is not fencing — the
    haul back goes further, the stroke carries through past the low point, and
    the settle takes the rest of the cycle.

    The torso does most of the work. At the size a gatherer is actually seen
    (D-063's thirty-pixel soldier, and `author_clips.py`'s note on the same),
    an arm swinging inside its own silhouette is invisible; a trunk folding
    forward and back is not.
    """
    drive = _stroke(phase, 0.45, 0.17)
    return Pose(
        rotations={
            "right_arm": [("x", -1.25 * drive)],
            "left_arm": [("x", -1.05 * drive)],
            "torso": [("x", 0.34 * drive), ("y", -0.10 * drive)],
            "head": [("x", 0.18 * drive)],
            "leg_l": [("x", 0.08 * max(drive, 0.0))],
        },
        offset=(0.0, -0.05 * max(drive, 0.0), 0.0),
    )


def mine(phase: float) -> Pose:
    """Working a seam: shorter, sharper pickaxe strokes, twice a cycle.

    Two strokes where `chop` has one, because that is the difference a player
    reads between the two without being told which is which — a woodcutter
    winds up, a miner chips away. Less trunk travel and more arm, since a pick
    is swung from the shoulders rather than the hips.
    """
    drive = _stroke((phase * 2.0) % 1.0, 0.48, 0.19)
    return Pose(
        rotations={
            "right_arm": [("x", -1.05 * drive)],
            "left_arm": [("x", -0.85 * drive)],
            "torso": [("x", 0.22 * drive), ("y", -0.14 * drive)],
            "head": [("x", 0.12 * drive)],
        },
        offset=(0.0, -0.03 * max(drive, 0.0), 0.0),
    )


def forage(phase: float) -> Pose:
    """Gathering by hand: stoop, pick, straighten. No tool at all.

    The one work clip with no swing in it, and that is the whole point — a
    crew at a fruit tree should read as bending and reaching where a crew at
    an oak reads as striking. Both arms reach ahead and the body folds; there
    is no impact anywhere in the cycle.
    """
    fold = 0.5 - 0.5 * math.cos(math.tau * phase)
    reach = math.sin(math.tau * phase)
    return Pose(
        rotations={
            "torso": [("x", 0.46 * fold)],
            "right_arm": [("x", -0.72 * fold), ("z", 0.12 * reach)],
            "left_arm": [("x", -0.62 * fold), ("z", -0.12 * reach)],
            "head": [("x", 0.24 * fold)],
            "leg_l": [("x", 0.14 * fold)],
            "leg_r": [("x", -0.06 * fold)],
        },
        offset=(0.0, -0.075 * fold, 0.0),
    )


CLIPS = {"idle": idle, "walk": walk, "attack": attack, "rout": rout,
         "chop": chop, "mine": mine, "forage": forage}


def pose_at(clip: str, phase: float) -> Pose:
    return CLIPS[clip](phase % 1.0)
