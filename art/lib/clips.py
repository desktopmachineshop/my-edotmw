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
CLIP_ORDER = ("idle", "walk", "attack", "rout")


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


CLIPS = {"idle": idle, "walk": walk, "attack": attack, "rout": rout}


def pose_at(clip: str, phase: float) -> Pose:
    return CLIPS[clip](phase % 1.0)
