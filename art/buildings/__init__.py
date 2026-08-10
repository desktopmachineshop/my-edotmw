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


def build(name: str, p: BuildingParams) -> Model:
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
}
