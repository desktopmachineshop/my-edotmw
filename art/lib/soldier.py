"""Parametric soldier construction (D-064).

This is mesh tier 2 — "interchangeable parts combined programmatically" — being
absorbed into tier 3 rather than skipped. An archetype is a set of parameters,
not a bespoke model, so a new unit is a few numbers in `art/units/` and never a
new builder.

## Scale is not free to choose

The placeholder capsule is 1.8 units tall with a 0.3 radius, and everything
downstream is tuned against that: `formation_spacing` defaults to 1.0,
`RenderCull.max_camera_height` was measured against the current on-screen
density, and selection-disc radii are picked to sit under a soldier. So the
authored soldier is built to the SAME 1.8 units. Art that changed the scale
would silently retune the camera and the formations.

D-045's rule applies to anything here that is tempted to scale a soldier by
distance or importance: a distant squad is drawn thinner, never smaller — unit
size is tactical information a player reads off the screen.

## The triangle budget

D-064 sets ~300 triangles per soldier. `build()` reports its count and
`art/build.py` fails the build if an archetype exceeds the budget, so the number
is enforced rather than aspired to.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import math

from .geom import Model, Part, box, prism, rotate_geometry

# Rest-pose landmarks. Named because three modules need the same numbers: the
# builder places parts against them, the clips rotate about them, and the VAT
# bake needs the model's height to normalise its bounding box.
HEIGHT = 1.8
HIP_Y = 0.80
SHOULDER_Y = 1.36
HIP_PIVOT = (0.0, HIP_Y, 0.0)


@dataclass
class SoldierParams:
    """Everything that distinguishes one archetype's model from another.

    Deliberately flat and all-defaulted: an archetype file overrides the two or
    three fields that matter and inherits the rest, so the roster stays legible
    as a set of differences rather than a set of full specifications.
    """

    # Build
    scale: float = 1.0            # multiplies overall height
    bulk: float = 1.0             # torso and limb thickness
    stance: float = 1.0           # how wide the legs are planted

    # Colour. `mask` fields say how much of a part takes the OWNER's colour
    # (D-052) rather than its own.
    skin: tuple[float, float, float] = (0.76, 0.60, 0.47)
    cloth: tuple[float, float, float] = (0.42, 0.38, 0.34)
    metal: tuple[float, float, float] = (0.62, 0.64, 0.70)
    leather: tuple[float, float, float] = (0.34, 0.24, 0.17)
    wood: tuple[float, float, float] = (0.45, 0.33, 0.20)

    # Kit
    helmet: str = "cap"           # none | cap | crested | horned
    weapon: str = "spear"         # none | spear | sword | bow | axe
    shield: bool = True
    cloak: bool = False
    mount: bool = False           # cavalry ride; the rider's legs stop swinging

    # How strongly the torso reads as this player's colour. Cloaks and shields
    # carry most of it; the tunic carries the rest.
    tunic_mask: float = 0.85
    shield_mask: float = 0.9


HORSE_BACK_Y = 0.92          # where a rider sits
HORSE_LENGTH = 1.35


def build(name: str, p: SoldierParams) -> Model:
    """Assemble a unit — a soldier, or a rider on a horse if `mount` is set."""
    if not p.mount:
        return _build_rider(name, p)

    m = _build_horse(name, p)
    rider = _build_rider(name, p)
    for part in rider.parts:
        # A seated rider's legs grip rather than swing. Renaming them out of
        # `clips.GROUP_OF` is what stops the walk clip from animating them —
        # the clip needs no knowledge that cavalry exists.
        renamed = part.name
        if part.name in ("leg_l", "leg_r"):
            renamed = part.name + "_seated"
        m.parts.append(
            Part(
                name=renamed,
                verts=[(v[0], v[1] + HORSE_BACK_Y, v[2]) for v in part.verts],
                faces=part.faces,
                rgb=part.rgb,
                mask=part.mask,
                pivot=(part.pivot[0], part.pivot[1] + HORSE_BACK_Y, part.pivot[2]),
            )
        )
    return m


def _build_horse(name: str, p: SoldierParams) -> Model:
    """A low-poly horse.

    The four legs are deliberately mapped onto the SAME two animation groups the
    infantry legs use, in diagonal pairs — front-left with rear-right. That is
    a real trot, and it means `clips.walk` animates a horse correctly without
    knowing what a horse is.
    """
    m = Model(name=name)
    hide = (0.36, 0.27, 0.21)
    body_y = HORSE_BACK_Y - 0.10

    m.add("horse_body",
          box((0.42, 0.44, HORSE_LENGTH), centre=(0.0, body_y, 0.0)),
          rgb=hide, mask=0.15, pivot=(0.0, body_y, 0.0))
    m.add("horse_neck",
          box((0.22, 0.46, 0.26), centre=(0.0, body_y + 0.28, HORSE_LENGTH * 0.42),
              taper=0.8),
          rgb=hide, mask=0.0, pivot=(0.0, body_y, HORSE_LENGTH * 0.4))
    m.add("horse_head",
          box((0.18, 0.19, 0.34), centre=(0.0, body_y + 0.50, HORSE_LENGTH * 0.55)),
          rgb=hide, mask=0.0, pivot=(0.0, body_y, HORSE_LENGTH * 0.4))
    m.add("horse_tail",
          box((0.09, 0.34, 0.09), centre=(0.0, body_y + 0.02, -HORSE_LENGTH * 0.52)),
          rgb=(0.22, 0.17, 0.13), mask=0.0,
          pivot=(0.0, body_y + 0.18, -HORSE_LENGTH * 0.5))

    leg_h = body_y - 0.22
    for tag, sx, sz in (("fl", -1.0, 1.0), ("fr", 1.0, 1.0),
                        ("rl", -1.0, -1.0), ("rr", 1.0, -1.0)):
        cx = sx * 0.17
        cz = sz * HORSE_LENGTH * 0.34
        m.add(f"horse_leg_{tag}",
              box((0.12, leg_h, 0.13), centre=(cx, leg_h / 2.0 + 0.02, cz)),
              rgb=hide, mask=0.0, pivot=(cx, leg_h + 0.02, cz))
    return m


def _build_rider(name: str, p: SoldierParams) -> Model:
    """Assemble a soldier. Returns a Model whose parts carry their own pivots."""
    m = Model(name=name)
    s = p.scale
    bulk = p.bulk

    leg_w = 0.17 * bulk
    leg_h = HIP_Y * s
    leg_x = 0.115 * p.stance

    # --- legs. Pivot at the hip so a walk cycle swings from the right place.
    for side, sign in (("l", -1.0), ("r", 1.0)):
        m.add(
            f"leg_{side}",
            box((leg_w, leg_h, leg_w * 1.15), centre=(sign * leg_x, leg_h / 2.0, 0.0)),
            rgb=p.leather, mask=0.0,
            pivot=(sign * leg_x, leg_h, 0.0),
        )

    # --- torso. The main owner-colour surface: it is the largest flat area a
    # player sees from above, which is the angle this game is played at.
    torso_h = (SHOULDER_Y - HIP_Y + 0.10) * s
    m.add(
        "torso",
        box((0.40 * bulk, torso_h, 0.24 * bulk),
            centre=(0.0, HIP_Y * s + torso_h / 2.0 - 0.02, 0.0), taper=0.92),
        rgb=p.cloth, mask=p.tunic_mask,
        pivot=(0.0, HIP_Y * s, 0.0),
    )

    # --- arms. Pivot at the shoulder.
    arm_w = 0.10 * bulk
    arm_h = 0.46 * s
    arm_x = 0.25 * bulk
    shoulder = SHOULDER_Y * s
    for side, sign in (("l", -1.0), ("r", 1.0)):
        m.add(
            f"arm_{side}",
            box((arm_w, arm_h, arm_w), centre=(sign * arm_x, shoulder - arm_h / 2.0, 0.0)),
            rgb=p.skin, mask=0.0,
            pivot=(sign * arm_x, shoulder, 0.0),
        )

    # --- head and helmet
    head_y = (SHOULDER_Y + 0.14) * s
    m.add(
        "head",
        box((0.18, 0.19, 0.18), centre=(0.0, head_y, 0.0)),
        rgb=p.skin, mask=0.0,
        pivot=(0.0, SHOULDER_Y * s, 0.0),
    )
    if p.helmet != "none":
        helm_y = head_y + 0.11
        m.add(
            "helmet",
            prism(0.125, 0.13, sides=6, centre=(0.0, helm_y, 0.0), taper=0.55),
            rgb=p.metal, mask=0.0,
            pivot=(0.0, SHOULDER_Y * s, 0.0),
        )
        if p.helmet == "crested":
            # A crest is pure silhouette — it is the cheapest way to tell two
            # archetypes apart at the distance this game is actually played at.
            m.add(
                "crest",
                box((0.035, 0.11, 0.30), centre=(0.0, helm_y + 0.11, 0.0)),
                rgb=p.cloth, mask=p.tunic_mask,
                pivot=(0.0, SHOULDER_Y * s, 0.0),
            )
        elif p.helmet == "horned":
            for sign in (-1.0, 1.0):
                m.add(
                    f"horn_{'l' if sign < 0 else 'r'}",
                    prism(0.055, 0.20, sides=5,
                          centre=(sign * 0.13, helm_y + 0.09, 0.0), taper=0.15),
                    rgb=(0.86, 0.83, 0.74), mask=0.0,
                    pivot=(0.0, SHOULDER_Y * s, 0.0),
                )

    # --- weapon, held in the right hand and pivoting with that shoulder
    hand_y = shoulder - arm_h
    if p.weapon == "spear":
        m.add(
            "weapon",
            box((0.045, 2.05 * s, 0.045), centre=(arm_x + 0.02, hand_y + 0.72 * s, 0.06)),
            rgb=p.wood, mask=0.0,
            pivot=(arm_x, shoulder, 0.0),
        )
        m.add(
            "spearhead",
            prism(0.055, 0.26, sides=4,
                  centre=(arm_x + 0.02, hand_y + 1.86 * s, 0.06), taper=0.05),
            rgb=p.metal, mask=0.0,
            pivot=(arm_x, shoulder, 0.0),
        )
    elif p.weapon == "sword":
        m.add(
            "weapon",
            box((0.05, 0.70 * s, 0.11), centre=(arm_x + 0.02, hand_y + 0.24 * s, 0.05)),
            rgb=p.metal, mask=0.0,
            pivot=(arm_x, shoulder, 0.0),
        )
    elif p.weapon == "axe":
        m.add(
            "weapon",
            box((0.05, 0.85 * s, 0.05), centre=(arm_x + 0.02, hand_y + 0.30 * s, 0.05)),
            rgb=p.wood, mask=0.0,
            pivot=(arm_x, shoulder, 0.0),
        )
        m.add(
            "axehead",
            box((0.06, 0.24, 0.20), centre=(arm_x + 0.02, hand_y + 0.70 * s, 0.13)),
            rgb=p.metal, mask=0.0,
            pivot=(arm_x, shoulder, 0.0),
        )
    elif p.weapon == "bow":
        # Stood on edge in the sagittal plane. Built about Y like every other
        # prism and then tipped, because a bow left flat reads as a plate.
        m.add(
            "weapon",
            rotate_geometry(
                prism(0.30, 0.045, sides=7,
                      centre=(arm_x + 0.06, hand_y + 0.34 * s, 0.0), taper=1.0),
                "z", math.pi / 2.0,
                pivot=(arm_x + 0.06, hand_y + 0.34 * s, 0.0),
            ),
            rgb=p.wood, mask=0.0,
            pivot=(arm_x, shoulder, 0.0),
        )

    # --- shield, on the left arm
    if p.shield:
        m.add(
            "shield",
            prism(0.215, 0.05, sides=6,
                  centre=(-arm_x - 0.06, shoulder - 0.24 * s, 0.03)),
            rgb=p.cloth, mask=p.shield_mask,
            pivot=(-arm_x, shoulder, 0.0),
        )

    # --- cloak: a flat slab down the back. Reads as owner colour from above,
    # which is where the camera is.
    if p.cloak:
        m.add(
            "cloak",
            box((0.36 * bulk, 0.72 * s, 0.05),
                centre=(0.0, shoulder - 0.38 * s, -0.15 * bulk), taper=1.25),
            rgb=p.cloth, mask=1.0,
            pivot=(0.0, shoulder, 0.0),
        )

    return m
