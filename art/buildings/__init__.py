"""Building models, parametric like the units (D-064).

Buildings are STATIC — no vertex animation texture. A town hall does not walk,
and baking 64 identical frames for it would be storage spent on nothing.

That makes them the simpler half of the pipeline in one way and a different
shape in another: buildings render as individual `MeshInstance3D`s rather than
through a `MultiMesh`, so the mesh's own COLOR_0 attribute survives all the way
to the fragment stage, and they need only a small static shader rather than the
VAT one. (Units cannot do that — see the note in `art/lib/bake.py` about
MultiMesh overriding COLOR.)

Owner colour works exactly as it does for units: vertex alpha is the mask, and
the roof and banner carry most of it. D-052's reason applies with more force
here than anywhere, because a town hall tells you whose ground you are standing
on.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..lib.geom import Model, box, prism, rotate_geometry

# D-076 amendment: the world's neighbour-to-neighbour hex spacing at the
# game's one shipped hex_size (both maps/*.tres pin hex_size = 1.0, and
# every other authored dimension in this file already assumes it rather
# than reading it from anywhere). A wall/gate segment's `length` used to be
# 2.4 — longer than the ~1.73 gap between adjacent cell centres — so two
# segments placed on neighbouring cells overlapped by close to 0.7 units.
# Matching it here means each segment reaches exactly half the distance to
# its neighbour, so a straight run's segments meet with (deliberately) a
# hair of overlap rather than a gap or a real one.
_HEX_SPACING = 1.7320508075688772  # sqrt(3) * hex_size, hex_size == 1.0
WALL_LENGTH = _HEX_SPACING * 1.02

# Playtest fix: a wall segment used to TILT to follow sloped terrain — reverted
# (client.gd no longer touches rotation.z at all) because a leaning wall reads
# as toppling, not as following the ground; a real wall's courses stay
# vertical even where its footing doesn't. The actual fix is depth, here: every
# ground-touching part of a wall/gate/tower reaches this far below y=0, so
# broken terrain buries the extra length instead of exposing a gap under it.
# height_scale (terrain_gen.gd) is 15.0; this is not trying to survive the
# single worst possible cell-to-cell jump in that range, only whatever the
# game's actual (smooth, low-frequency) noise plausibly produces under one
# wall segment's own small footprint.
SKIRT_DEPTH = 3.0


@dataclass
class BuildingParams:
    """What distinguishes one building's model from another."""

    footprint: float = 2.4        # width and depth of the main mass
    height: float = 1.9           # wall height, before the roof
    roof: str = "gable"           # gable | flat | spire | none
    banner: bool = False
    palisade: bool = False

    wall: tuple[float, float, float] = (0.62, 0.56, 0.46)
    timber: tuple[float, float, float] = (0.35, 0.25, 0.17)
    roof_colour: tuple[float, float, float] = (0.45, 0.30, 0.24)
    stone: tuple[float, float, float] = (0.60, 0.60, 0.58)

    roof_mask: float = 0.75       # how much of the roof takes owner colour
    banner_mask: float = 1.0

    # D-076: the wall/gate/tower family (block | wall | tower_access) is a
    # different silhouette shape from every earlier building — long and low
    # rather than a single roofed mass — so it branches build() entirely
    # rather than stretching the gable/flat/spire roof cases to cover it.
    shape: str = "block"
    length: float = 2.4           # wall segment span, local +X (D-076 facing axis)
    thickness: float = 1.0        # wall segment depth, local Z
    style: str = "stake"          # stake | stone | timber_slats (shape=="wall" only)
    walkway: bool = False         # parapet + walkway slab — the garrison tier only
    is_gate: bool = False         # inserts a door assembly mid-span


def build(name: str, p: BuildingParams) -> Model:
    if p.shape == "wall":
        return _build_wall(name, p)
    if p.shape == "tower_access":
        return _build_tower_access(name, p)

    m = Model(name=name)
    half = p.footprint / 2.0

    # Walls. Slight inward taper so the silhouette is not a perfect prism —
    # at this scale that is most of what separates "building" from "crate".
    m.add("walls",
          box((p.footprint, p.height, p.footprint),
              centre=(0.0, p.height / 2.0, 0.0), taper=0.94),
          rgb=p.wall, mask=0.12)

    # Corner posts, which do the work of reading as constructed rather than
    # extruded.
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            m.add(f"post_{'n' if sz < 0 else 's'}{'w' if sx < 0 else 'e'}",
                  box((0.16, p.height + 0.06, 0.16),
                      centre=(sx * (half - 0.06), (p.height + 0.06) / 2.0,
                              sz * (half - 0.06))),
                  rgb=p.timber, mask=0.0)

    if p.roof == "gable":
        # A real ridge: full width at the top, almost no depth, so the two
        # slopes meet in a line rather than at a point. Tapering both axes
        # gave a pyramid, which from this camera read as a flat plate.
        m.add("roof",
              box((p.footprint * 1.06, p.footprint * 0.42, p.footprint * 1.06),
                  centre=(0.0, p.height + p.footprint * 0.21, 0.0),
                  taper=1.0, taper_z=0.05),
              rgb=p.roof_colour, mask=p.roof_mask)
    elif p.roof == "flat":
        m.add("roof",
              box((p.footprint * 1.1, 0.18, p.footprint * 1.1),
                  centre=(0.0, p.height + 0.09, 0.0)),
              rgb=p.roof_colour, mask=p.roof_mask)
        # Battlements: four blocks, enough to read as a fortification.
        for sx, sz in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            m.add(f"merlon_{sx}_{sz}",
                  box((0.34 if sz else 0.22, 0.34, 0.22 if sz else 0.34),
                      centre=(sx * half * 1.02, p.height + 0.35, sz * half * 1.02)),
                  rgb=p.stone, mask=0.0)
    elif p.roof == "spire":
        m.add("roof",
              prism(p.footprint * 0.78, 1.15, sides=6,
                    centre=(0.0, p.height + 0.575, 0.0), taper=0.04),
              rgb=p.roof_colour, mask=p.roof_mask)

    if p.banner:
        # A pole and a cloth. Almost pure owner colour, and tall enough to be
        # visible over the roofline at the angle this game is played at.
        m.add("pole",
              box((0.07, 1.25, 0.07), centre=(half * 0.72, p.height + 1.0, -half * 0.72)),
              rgb=p.timber, mask=0.0)
        m.add("banner",
              box((0.04, 0.62, 0.46),
                  centre=(half * 0.72 + 0.02, p.height + 1.35, -half * 0.72 + 0.26)),
              rgb=p.roof_colour, mask=p.banner_mask)

    if p.palisade:
        # A low fence on two sides — a tower reads as defended rather than
        # merely tall.
        for sz in (-1.0, 1.0):
            m.add(f"palisade_{'n' if sz < 0 else 's'}",
                  box((p.footprint * 1.3, 0.55, 0.12),
                      centre=(0.0, 0.275, sz * half * 1.35)),
                  rgb=p.timber, mask=0.0)

    return m


def _buried(size: tuple[float, float, float], centre: tuple[float, float, float],
            taper: float = 1.0, taper_z: float | None = None):
    """`box()`, extended SKIRT_DEPTH below y=0 (playtest fix).

    For a part whose bottom face IS the ground contact — a stake, a slat, a
    post, a solid rampart body. Its silhouette from y=0 up is unchanged
    (the extra depth is added by lowering the centre exactly as much as the
    height grows), so a flat-ground render looks identical to before; on
    broken ground the buried extra length is what a gap would have shown
    through otherwise. Never use this for an ELEVATED part (a walkway,
    rail, merlon — nothing under those is meant to touch the ground) or for
    the animated gate leaf (burying it would carry a chunk of "underground"
    geometry up into view the moment it swings open).
    """
    sx, sy, sz = size
    cx, cy, cz = centre
    return box((sx, sy + SKIRT_DEPTH, sz), centre=(cx, cy - SKIRT_DEPTH / 2.0, cz),
               taper=taper, taper_z=taper_z)


def _add_merlons(m: Model, p: BuildingParams, top_y: float, half_t: float,
                  half: float, count: int, colour=None) -> None:
    """Battlements along both long edges of a walkway top (D-076).

    Shared by the stone rampart and the timber-slat gate — the parapet
    silhouette is what says "garrison tier", the colour is what says which
    material it's built from.
    """
    rgb = colour if colour is not None else p.stone
    span = half * 1.6
    for i in range(count):
        x = 0.0 if count == 1 else (i / (count - 1) - 0.5) * span
        for sz in (-1.0, 1.0):
            m.add(f"merlon_{i}_{'n' if sz < 0 else 's'}",
                  box((0.34, 0.5, 0.22),
                      centre=(x, top_y + 0.25, sz * (half_t - 0.08))),
                  rgb=rgb, mask=0.0)


def _add_gate_leaf(m: Model, width: float, height: float, thickness: float,
                    centre_y: float, rgb, mask: float) -> None:
    """A hinged door leaf (playtest fix, D-076 amendment).

    Named exactly "gate_leaf" and given a PIVOT at its hinge edge — that
    pivot is what `bake.py`'s `door_hinge_uv` looks for to tag this part's
    vertices in the mesh's otherwise-unused UV1 channel (buildings carry no
    VAT, D-064, so it costs nothing else). `building_static.gdshader` reads
    the tag to swing the leaf open about that same edge, driven by the
    `gate_open` uniform instead of TIME the way a soldier's clip is. Every
    OTHER part in this file is genuinely rigid for its building's whole
    life, so this is the one place a building needs a pivot at all.
    """
    hinge_x = -width / 2.0
    m.add("gate_leaf",
          box((width, height, thickness), centre=(0.0, centre_y, 0.0)),
          rgb=rgb, mask=mask, pivot=(hinge_x, centre_y, 0.0))


def _add_stake_door(m: Model, p: BuildingParams) -> None:
    """A gate's door assembly: two frame posts, a lintel and a hinged plank
    leaf, filling the gap the cheap-tier stake row leaves at its centre."""
    frame_h = p.height + 0.1
    for sx in (-1.0, 1.0):
        m.add(f"gate_post_{'w' if sx < 0 else 'e'}",
              _buried((0.2, frame_h, 0.2), (sx * 0.4, frame_h / 2.0, 0.0)),
              rgb=p.timber, mask=0.0)
    m.add("gate_lintel",
          box((1.0, 0.16, 0.22), centre=(0.0, frame_h - 0.08, 0.0)),
          rgb=p.timber, mask=0.0)
    _add_gate_leaf(m, width=0.62, height=p.height * 0.82, thickness=0.1,
                   centre_y=p.height * 0.41, rgb=p.timber, mask=0.05)


def _build_wall(name: str, p: BuildingParams) -> Model:
    """A wall or gate segment: long and low, D-076's second building shape.

    Length runs along local +X — the axis client.gd rotates to match a
    segment's `facing` — so every wall/gate/garrison piece shares one
    length-axis convention regardless of style, the same way the primitive
    fallback box's `mesh_size.x` already does.
    """
    m = Model(name=name)
    half = p.length / 2.0
    half_t = p.thickness / 2.0

    if p.style == "stake":
        # Cheap tier: a row of pointed timber stakes tied by two rails.
        # No walkway — this is a pure blocker, nothing stands on it.
        count = 7
        centre_gap = (count - 1) / 2.0
        for i in range(count):
            if p.is_gate and abs(i - centre_gap) < 1.6:
                continue  # left open for the door assembly below
            x = (i - centre_gap) / centre_gap * half * 0.92
            m.add(f"stake_{i}",
                  _buried((0.16, p.height, 0.16), (x, p.height / 2.0, 0.0), taper=0.25),
                  rgb=p.timber, mask=0.0)
        for j, ry in enumerate((p.height * 0.55, p.height * 0.88)):
            m.add(f"rail_{j}",
                  box((p.length * 0.92, 0.07, 0.07), centre=(0.0, ry, 0.0)),
                  rgb=p.timber, mask=0.0)
        if p.is_gate:
            _add_stake_door(m, p)

    elif p.style == "stone":
        # Garrison tier: a solid crenellated stone rampart, its thickness
        # axis (mesh_size.z) wide enough for two soldiers abreast — that's
        # a BuildingDef/gameplay fact, this only has to render it.
        body_h = p.height
        m.add("body", _buried((p.length, body_h, p.thickness),
                               (0.0, body_h / 2.0, 0.0), taper=0.97),
              rgb=p.stone, mask=0.12)
        m.add("walkway", box((p.length * 0.98, 0.14, p.thickness * 0.98),
                              centre=(0.0, body_h + 0.07, 0.0)),
              rgb=p.stone, mask=0.0)
        _add_merlons(m, p, body_h + 0.14, half_t, half, count=4)

    elif p.style == "timber_slats":
        # Garrison gate: the same walkway/parapet silhouette as the stone
        # rampart, built from vertical planks instead. Playtest fix: this
        # used to draw every slat regardless of `is_gate`, so a garrison
        # gate had no door-shaped opening at all — material was the ONLY
        # cue, and nothing ever visibly passed through it. A gate now
        # leaves the same kind of gap the cheap "stake" tier always did,
        # filled by a real hinged leaf (`_add_gate_leaf`).
        body_h = p.height
        slats = 7
        span = p.length * 0.94
        slat_w = span / slats
        centre_gap = (slats - 1) / 2.0
        for i in range(slats):
            if p.is_gate and abs(i - centre_gap) < 1.6:
                continue  # left open for the hinged leaf below
            x = (i - centre_gap) * slat_w
            m.add(f"slat_{i}",
                  _buried((slat_w * 0.82, body_h, p.thickness * 0.9),
                          (x, body_h / 2.0, 0.0)),
                  rgb=p.timber, mask=0.12)
        for sx in (-1.0, 1.0):
            m.add(f"post_{'w' if sx < 0 else 'e'}",
                  _buried((0.18, body_h + 0.08, 0.18),
                          (sx * (half - 0.09), (body_h + 0.08) / 2.0, 0.0)),
                  rgb=p.timber, mask=0.0)
        m.add("walkway", box((p.length * 0.98, 0.14, p.thickness * 0.98),
                              centre=(0.0, body_h + 0.07, 0.0)),
              rgb=p.timber, mask=0.0)
        _add_merlons(m, p, body_h + 0.14, half_t, half, count=3, colour=p.timber)
        if p.is_gate:
            _add_gate_leaf(m, width=slat_w * 3.0, height=body_h * 0.92,
                           thickness=p.thickness * 0.82, centre_y=body_h * 0.46,
                           rgb=p.timber, mask=0.08)

    return m


def _build_tower_access(name: str, p: BuildingParams) -> Model:
    """The wall-top access point (D-076): a squat stone tower, crenellated
    on all four sides, with a door on local +X only.

    +X is the axis client.gd rotates by `facing` — the same convention
    `_build_wall` uses for a segment's length — so the modelled door always
    ends up pointing at the one ground cell the climb/descend check in
    squad_sim.gd actually permits, without any per-instance mesh logic.
    """
    m = Model(name=name)
    half = p.footprint / 2.0
    body_h = p.height

    m.add("body", _buried((p.footprint, body_h, p.footprint),
                           (0.0, body_h / 2.0, 0.0), taper=0.95),
          rgb=p.stone, mask=0.12)
    m.add("walkway", box((p.footprint * 0.98, 0.14, p.footprint * 0.98),
                          centre=(0.0, body_h + 0.07, 0.0)),
          rgb=p.stone, mask=0.0)

    top_y = body_h + 0.14
    for side, (sx, sz) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
        for offset in (-0.55, 0.55):
            centre = ((sx * (half - 0.08), top_y + 0.25, offset) if sx
                      else (offset, top_y + 0.25, sz * (half - 0.08)))
            m.add(f"merlon_{side}_{offset}",
                  box((0.22, 0.5, 0.22), centre=centre),
                  rgb=p.stone, mask=0.0)

    door_h = min(1.7, body_h * 0.62)
    for sz in (-1.0, 1.0):
        m.add(f"jamb_{'n' if sz < 0 else 's'}",
              box((0.3, door_h, 0.16), centre=(half - 0.08, door_h / 2.0, sz * 0.42)),
              rgb=p.stone, mask=0.0)
    m.add("lintel",
          box((1.0, 0.18, 0.2), centre=(half - 0.08, door_h, 0.0)),
          rgb=p.stone, mask=0.0)
    m.add("doorway",
          box((0.1, door_h - 0.16, 0.72),
              centre=(half - 0.02, (door_h - 0.16) / 2.0, 0.0)),
          rgb=p.timber, mask=0.0)

    return m


ROSTER: dict[str, BuildingParams] = {
    # The centre of a base, and the thing a player looks for first. Biggest
    # mass, a banner, and the most owner colour on the map.
    "town_centre": BuildingParams(
        footprint=4.6, height=3.6, roof="gable", banner=True,
        roof_colour=(0.48, 0.30, 0.26),
    ),

    # Where soldiers come from. Long, plain, workmanlike.
    "barracks": BuildingParams(
        footprint=3.6, height=2.8, roof="gable",
        wall=(0.58, 0.50, 0.40), roof_colour=(0.40, 0.30, 0.26),
    ),

    # Tall and stone, with battlements. Height alone should say "this shoots".
    "tower": BuildingParams(
        footprint=2.0, height=5.0, roof="flat", palisade=True,
        wall=(0.62, 0.62, 0.60), roof_colour=(0.52, 0.52, 0.50),
        roof_mask=0.55,
    ),

    # Small, squat, a spire so it is not mistaken for a barracks at a glance.
    "storehouse": BuildingParams(
        footprint=2.8, height=2.1, roof="spire",
        wall=(0.60, 0.54, 0.42), roof_colour=(0.42, 0.36, 0.28),
    ),

    # --- D-076: walls, gates and the walkable garrison tier ------------
    #
    # Cheap tier: a wooden stake fence — a pure blocker, no walkway.
    "wall": BuildingParams(
        shape="wall", style="stake", length=WALL_LENGTH, thickness=1.0, height=1.95,
        timber=(0.38, 0.27, 0.16),
    ),
    "gate": BuildingParams(
        shape="wall", style="stake", is_gate=True,
        length=WALL_LENGTH, thickness=1.0, height=1.95,
        timber=(0.38, 0.27, 0.16),
    ),

    # Garrison tier: walkable, D-025/D-076's second elevation layer. Height
    # is chosen so body + walkway slab lands exactly on garrison_wall.tres's
    # top_height=3.0 — soldiers standing there should stand ON this mesh,
    # not float above or sink into it.
    "garrison_wall": BuildingParams(
        shape="wall", style="stone", walkway=True,
        length=WALL_LENGTH, thickness=1.0, height=2.86,
        stone=(0.58, 0.58, 0.56),
    ),
    # Same silhouette family as garrison_wall, wood instead of stone — the
    # gate is marked by material AND, since the playtest fix below, a real
    # hinged leaf rather than a gap in the rampart alone.
    "garrison_gate": BuildingParams(
        shape="wall", style="timber_slats", is_gate=True, walkway=True,
        length=WALL_LENGTH, thickness=1.0, height=2.86,
        timber=(0.42, 0.30, 0.19),
    ),

    # The access tower: the only piece in the roster with a door, on local
    # +X, rotated into place by the placed instance's own `facing`. Height
    # lands body+walkway on wall_tower.tres's top_height=4.0.
    "wall_tower": BuildingParams(
        shape="tower_access", footprint=2.6, height=3.86,
        stone=(0.58, 0.58, 0.56),
    ),
}
