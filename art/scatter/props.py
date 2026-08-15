"""Ground-cover props: the small stuff between the forests (D-100).

Seventeen low-poly clumps — ferns, tufts, mushrooms, driftwood, scree — built
from the same two primitives every other model in this project uses
(`art/lib/geom.py`), baked to `generated/models/prop_*.glb` by `art/build.py`.
`GroundCover` (ground_cover.gd) decides which of them a cell wears.

## These are decoration, and that is the whole design

D-087's resource nodes are simulation entities: the server places them, fog
gates them, and their depletion is a wire event. A prop is the deliberate
opposite — the client derives it from terrain it already has, nothing is
gated because a grass tuft leaks no information, and nothing goes on the wire.
The contrast is stated in ground_cover.gd's header too, because the one way
this feature goes wrong later is somebody "fixing" it by replicating it.

## Two gameplay rules constrain the art, not just the placement

Props stay SHORT — `MAX_HEIGHT` is enforced here, at build time, not left to
whoever authors the next one — and they carry no owner-colour mask, because
nothing about a fern should read as "this ground is blue's". A soldier is
~1.8 units tall; the tallest thing in this file is 0.46 before scale. Unit
readability is tactical information (D-045's "thinner, never smaller").

## Winding is checked, not hoped for

Every `box()` in this repo was wound inside-out for a whole milestone and
nothing failed, because a small convex object under back-face culling has an
identical silhouette either way — only the LIGHTING was inverted (see the note
at the top of `geom.py`). Props are small convex objects, which is exactly the
shape that hides it, and there will be dozens of thousands of them. So
`build()` computes each part's signed volume and fails the build if any part
is inside-out: outward-wound closed geometry has positive volume by the
divergence theorem. Rotations preserve winding; MIRRORING does not, which is
why nothing here is built by negating a coordinate.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from ..lib.geom import Model, Vec3, box, prism, rotate_geometry

# Well under a soldier (~1.8 units). Enforced by `validate`, and mirrored on
# the GDScript side by GroundCover.MAX_PROP_HEIGHT so the placement module's
# scale range cannot quietly push a prop up to soldier height.
MAX_HEIGHT = 0.5

# Props are drawn in the thousands from one MultiMesh per (chunk, model), so
# their budget is throughput, not silhouette. A soldier is 300 (D-081).
TRIANGLE_BUDGET = 80

# --- palette -------------------------------------------------------------
#
# Chosen against `TerrainGen.biome_color()` under D-086's ACES tonemap: each
# prop is a shade or two off its ground so it reads as a thing standing on
# the terrain rather than a stain in it, without turning into a colour accent
# the eye tracks instead of tracking units.
#
# These are BRIGHTER than the ground values they sit next to, and deliberately.
# Terrain faces point up and take the sun full on; a blade of grass or a fern
# frond is nearly vertical and lives mostly on sky ambient, so the same number
# renders a good deal darker on a prop than on the ground under it. Every value
# here was picked by looking at `artifacts/cover-godot.png`, not by matching
# `biome_color()` on paper.

GRASS = (0.46, 0.66, 0.30)
GRASS_DEEP = (0.34, 0.52, 0.26)
FERN = (0.37, 0.58, 0.30)
MOSS = (0.39, 0.58, 0.29)
DRY_GRASS = (0.78, 0.70, 0.40)
DRY_STALK = (0.66, 0.58, 0.34)
BARK = (0.42, 0.31, 0.21)
BARK_PALE = (0.55, 0.45, 0.33)
DRIFTWOOD = (0.63, 0.58, 0.49)
CAP = (0.70, 0.31, 0.25)
STEM = (0.86, 0.82, 0.70)
STONE = (0.62, 0.62, 0.60)
STONE_DARK = (0.50, 0.49, 0.48)
STONE_WARM = (0.66, 0.62, 0.54)
SAND = (0.80, 0.73, 0.52)
SHELL = (0.90, 0.85, 0.76)
CACTUS = (0.42, 0.58, 0.35)
REED = (0.44, 0.62, 0.38)
FLOWER_GOLD = (0.87, 0.75, 0.30)
FLOWER_LILAC = (0.76, 0.72, 0.86)
SNOW = (0.93, 0.93, 0.96)


# --- construction helpers ------------------------------------------------


def _at(geometry, dx: float = 0.0, dy: float = 0.0, dz: float = 0.0):
    """Translate a (verts, faces) pair. Winding is untouched."""
    verts, faces = geometry
    return [(v[0] + dx, v[1] + dy, v[2] + dz) for v in verts], faces


def _grounded(geometry):
    """Lift a part until its lowest vertex sits exactly on y=0.

    Leaning anything about its base swings the lower corner of its base BELOW
    the ground — a 5 cm blade at 0.55 rad dips 1.3 cm, which is invisible in a
    render and is the whole prop's foot buried on a slope. `validate` fails the
    build on it; this is what keeps that from happening in the first place.
    """
    verts, faces = geometry
    lift = -min(v[1] for v in verts)
    if lift <= 0.0:
        return verts, faces
    return [(v[0], v[1] + lift, v[2]) for v in verts], faces


def _blade(height: float, width: float, lean: float, yaw: float,
           thickness: float = 0.02, taper: float = 0.12):
    """One grass-like blade: a thin tapered box, tilted and turned.

    Built standing at the origin and rotated about its BASE, so a blade's foot
    stays on the ground however far it leans — the alternative (building it
    leaning) puts half of it underground on the steep ones.
    """
    geometry = box((width, height, thickness), centre=(0.0, height / 2.0, 0.0),
                   taper=taper)
    geometry = rotate_geometry(geometry, "z", lean)
    return _grounded(rotate_geometry(geometry, "y", yaw))


def _fan(model: Model, name: str, rgb, count: int, height: float, width: float,
         lean: float, spread: float = 0.055, thickness: float = 0.02,
         taper: float = 0.12, height_step: float = 0.0) -> None:
    """A ring of blades leaning outward — the shape every tuft in this file is.

    Deterministic by construction: blade `i` is placed at a fixed fraction of
    a turn with a fixed lean, never rolled. Variety between two tufts on the
    map comes from `GroundCover`'s per-cell yaw and scale, which is where it
    belongs — an art generator that rolled dice would have to seed them, and a
    seed is a hidden input D-081 does not allow.
    """
    for i in range(count):
        yaw = math.tau * i / count
        h = height + height_step * (i % 2)
        blade = _blade(h, width, lean, yaw, thickness=thickness, taper=taper)
        model.add(f"{name}_{i}", _at(blade, math.cos(yaw) * spread, 0.0,
                                    math.sin(yaw) * spread), rgb=rgb)


def _signed_volume(verts: list[Vec3], faces: list[tuple[int, int, int]]) -> float:
    """Six times the enclosed volume of a closed mesh (divergence theorem).

    Positive when triangles are wound counter-clockwise seen from OUTSIDE,
    which is what glTF and Godot mean by front-facing and what `bake.py`
    derives its normals from. See the module docstring.
    """
    total = 0.0
    for a, b, c in faces:
        p, q, r = verts[a], verts[b], verts[c]
        total += (p[0] * (q[1] * r[2] - q[2] * r[1])
                  - p[1] * (q[0] * r[2] - q[2] * r[0])
                  + p[2] * (q[0] * r[1] - q[1] * r[0]))
    return total


# --- the props -----------------------------------------------------------


def _grass_tuft() -> Model:
    m = Model(name="prop_grass_tuft")
    _fan(m, "blade", GRASS, count=4, height=0.30, width=0.055, lean=0.34,
         height_step=0.06)
    return m


def _dune_grass() -> Model:
    """Marram: taller, paler, thinner than pasture grass — a beach reads as a
    beach partly because its grass is stringy."""
    m = Model(name="prop_dune_grass")
    _fan(m, "blade", DRY_GRASS, count=4, height=0.40, width=0.035, lean=0.46,
         spread=0.05, height_step=-0.07)
    return m


def _dry_tussock() -> Model:
    m = Model(name="prop_dry_tussock")
    _fan(m, "blade", DRY_GRASS, count=4, height=0.24, width=0.05, lean=0.55,
         spread=0.06, height_step=0.05)
    m.add("crown", prism(0.075, 0.06, sides=5, centre=(0.0, 0.03, 0.0), taper=0.5),
          rgb=DRY_STALK)
    return m


def _reeds() -> Model:
    m = Model(name="prop_reeds")
    _fan(m, "stalk", REED, count=5, height=0.46, width=0.03, lean=0.16,
         spread=0.045, taper=0.35, height_step=-0.08)
    return m


def _wildflowers() -> Model:
    m = Model(name="prop_wildflowers")
    _fan(m, "leaf", GRASS, count=3, height=0.20, width=0.05, lean=0.42)
    # Two heads at different heights: a flat bed of identical dots reads as a
    # texture, two heights read as plants.
    m.add("head_a", box((0.09, 0.05, 0.09), centre=(0.05, 0.25, 0.02)),
          rgb=FLOWER_GOLD)
    m.add("head_b", box((0.08, 0.045, 0.08), centre=(-0.045, 0.20, -0.035)),
          rgb=FLOWER_LILAC)
    # Same green as the leaves on purpose: one distinct colour per part is one
    # more glTF material, which is one more surface in every MultiMesh that
    # draws this prop.
    m.add("stalks", box((0.02, 0.22, 0.02), centre=(0.02, 0.11, -0.01)),
          rgb=GRASS)
    return m


def _fern() -> Model:
    """Fronds, not blades: wide and flat, leaning further, in forest green."""
    m = Model(name="prop_fern")
    _fan(m, "frond", FERN, count=4, height=0.28, width=0.14, lean=0.62,
         spread=0.04, thickness=0.015, taper=0.05)
    m.add("crown", prism(0.05, 0.05, sides=5, centre=(0.0, 0.025, 0.0), taper=0.4),
          rgb=GRASS_DEEP)
    return m


def _bush() -> Model:
    m = Model(name="prop_bush")
    m.add("body", box((0.34, 0.30, 0.30), centre=(0.0, 0.15, 0.0), taper=0.55),
          rgb=GRASS_DEEP)
    m.add("lobe_a", box((0.18, 0.16, 0.17), centre=(0.10, 0.28, 0.04), taper=0.4),
          rgb=GRASS)
    m.add("lobe_b", box((0.15, 0.13, 0.15), centre=(-0.09, 0.24, -0.06), taper=0.4),
          rgb=GRASS)
    return m


def _cactus() -> Model:
    m = Model(name="prop_cactus")
    m.add("trunk", prism(0.075, 0.42, sides=6, centre=(0.0, 0.21, 0.0), taper=0.8),
          rgb=CACTUS)
    arm = rotate_geometry(
        box((0.05, 0.16, 0.05), centre=(0.0, 0.08, 0.0)), "z", -0.9)
    m.add("arm_e", _at(arm, 0.07, 0.16, 0.0), rgb=CACTUS)
    arm_w = rotate_geometry(
        box((0.045, 0.13, 0.045), centre=(0.0, 0.065, 0.0)), "z", 0.9)
    m.add("arm_w", _at(arm_w, -0.07, 0.21, 0.02), rgb=CACTUS)
    return m


def _mushrooms() -> Model:
    m = Model(name="prop_mushrooms")
    for i, (x, z, h, r) in enumerate(((0.0, 0.0, 0.13, 0.085),
                                      (0.10, 0.06, 0.09, 0.06))):
        m.add(f"stem_{i}", box((r * 0.45, h, r * 0.45), centre=(x, h / 2.0, z)),
              rgb=STEM)
        m.add(f"cap_{i}",
              prism(r, 0.055, sides=5, centre=(x, h + 0.0275, z), taper=0.25),
              rgb=CAP)
    return m


def _log() -> Model:
    """A fallen trunk. Built upright and rotated onto its side, so the taper
    runs along the log rather than across it."""
    m = Model(name="prop_log")
    trunk = rotate_geometry(
        box((0.13, 0.46, 0.13), centre=(0.0, 0.23, 0.0), taper=0.8), "z", math.pi / 2.0)
    m.add("trunk", _at(trunk, 0.0, 0.07, 0.0), rgb=BARK)
    stub = rotate_geometry(box((0.05, 0.14, 0.05), centre=(0.0, 0.07, 0.0)),
                           "x", 0.7)
    m.add("branch", _at(stub, -0.13, 0.10, 0.02), rgb=BARK_PALE)
    m.add("moss", box((0.22, 0.03, 0.09), centre=(0.02, 0.14, 0.0)), rgb=MOSS)
    return m


def _driftwood() -> Model:
    m = Model(name="prop_driftwood")
    plank = rotate_geometry(
        box((0.08, 0.44, 0.06), centre=(0.0, 0.22, 0.0), taper=0.6), "z", 1.42)
    m.add("plank", _at(plank, 0.0, 0.04, 0.0), rgb=DRIFTWOOD)
    spar = rotate_geometry(
        box((0.06, 0.30, 0.05), centre=(0.0, 0.15, 0.0), taper=0.6), "z", 1.15)
    spar = rotate_geometry(spar, "y", 1.0)
    m.add("spar", _at(spar, 0.02, 0.03, 0.04), rgb=BARK_PALE)
    return m


def _shell() -> Model:
    m = Model(name="prop_shell")
    shell = rotate_geometry(
        prism(0.075, 0.05, sides=5, centre=(0.0, 0.025, 0.0), taper=0.15),
        "x", 0.5)
    m.add("shell", _at(shell, 0.0, 0.015, 0.0), rgb=SHELL)
    m.add("chip", prism(0.04, 0.02, sides=5, centre=(0.09, 0.01, -0.05), taper=0.3),
          rgb=SAND)
    return m


def _moss_rock() -> Model:
    m = Model(name="prop_moss_rock")
    m.add("rock", prism(0.17, 0.19, sides=6, centre=(0.0, 0.095, 0.0), taper=0.55),
          rgb=STONE_DARK)
    m.add("moss", box((0.17, 0.035, 0.15), centre=(0.01, 0.19, 0.0), taper=0.7),
          rgb=MOSS)
    return m


def _boulder() -> Model:
    m = Model(name="prop_boulder")
    m.add("mass", prism(0.21, 0.26, sides=6, centre=(0.0, 0.13, 0.0), taper=0.5),
          rgb=STONE)
    m.add("shoulder", prism(0.10, 0.11, sides=5, centre=(0.19, 0.055, 0.06),
                            taper=0.6),
          rgb=STONE_DARK)
    return m


def _snow_boulder() -> Model:
    m = Model(name="prop_snow_boulder")
    m.add("mass", prism(0.20, 0.24, sides=6, centre=(0.0, 0.12, 0.0), taper=0.5),
          rgb=STONE_DARK)
    m.add("snow", prism(0.115, 0.05, sides=6, centre=(0.0, 0.25, 0.0), taper=0.6),
          rgb=SNOW)
    return m


def _rock_spike() -> Model:
    m = Model(name="prop_rock_spike")
    m.add("spike", prism(0.13, 0.44, sides=5, centre=(0.0, 0.22, 0.0), taper=0.18),
          rgb=STONE)
    m.add("shard", prism(0.08, 0.20, sides=5, centre=(0.15, 0.10, 0.05), taper=0.25),
          rgb=STONE_DARK)
    return m


def _scree() -> Model:
    """Loose stone: four flat chips, no two the same size. The clump is what
    reads at play distance, never the individual pebble."""
    m = Model(name="prop_scree")
    chips = ((0.0, 0.0, 0.15, 0.07), (0.13, 0.06, 0.11, 0.05),
             (-0.10, 0.09, 0.09, 0.045), (0.04, -0.12, 0.12, 0.055))
    for i, (x, z, w, h) in enumerate(chips):
        rgb = STONE if i % 2 == 0 else STONE_DARK
        m.add(f"chip_{i}", box((w, h, w * 0.8), centre=(x, h / 2.0, z), taper=0.6),
              rgb=rgb)
    return m


def _cracked_slab() -> Model:
    """Sun-cracked stone lying flush with dry ground: two plates with a gap."""
    m = Model(name="prop_cracked_slab")
    m.add("plate_a", box((0.26, 0.07, 0.19), centre=(-0.07, 0.035, 0.0), taper=0.85),
          rgb=STONE_WARM)
    m.add("plate_b", box((0.19, 0.055, 0.16), centre=(0.14, 0.0275, 0.04), taper=0.85),
          rgb=STONE)
    return m


@dataclass
class PropSpec:
    """One prop: how to build it, and what it is FOR.

    `note` is not decoration. Every entry here has to justify its place in a
    biome palette (ground_cover.gd's PALETTES), and a prop nobody can say the
    purpose of is a prop that should not ship.
    """

    build: object
    note: str


ROSTER: dict[str, PropSpec] = {
    "prop_grass_tuft": PropSpec(_grass_tuft, "pasture grass; the grassland staple"),
    "prop_wildflowers": PropSpec(_wildflowers, "colour accent on open ground"),
    "prop_bush": PropSpec(_bush, "small shrub; forest floor and grassland alike"),
    "prop_fern": PropSpec(_fern, "forest undergrowth"),
    "prop_mushrooms": PropSpec(_mushrooms, "damp forest floor detail"),
    "prop_log": PropSpec(_log, "fallen trunk; says the forest is old"),
    "prop_moss_rock": PropSpec(_moss_rock, "mossy rock; forest floor"),
    "prop_boulder": PropSpec(_boulder, "the occasional bare rock; open and high ground"),
    "prop_dry_tussock": PropSpec(_dry_tussock, "sparse dry grass"),
    "prop_cactus": PropSpec(_cactus, "arid marker, matches the acacia/saguaro trees"),
    "prop_cracked_slab": PropSpec(_cracked_slab, "sun-cracked stone on dry ground"),
    "prop_reeds": PropSpec(_reeds, "waterline reeds on the beach side"),
    "prop_dune_grass": PropSpec(_dune_grass, "marram grass above the waterline"),
    "prop_driftwood": PropSpec(_driftwood, "beach flotsam"),
    "prop_shell": PropSpec(_shell, "shells at the tide line"),
    "prop_scree": PropSpec(_scree, "loose stone at the mountain foot"),
    "prop_rock_spike": PropSpec(_rock_spike, "angular outcrop; mountain"),
    "prop_snow_boulder": PropSpec(_snow_boulder, "snow-dusted rock; peaks"),
}


def validate(name: str, model: Model) -> dict:
    """Fail the build on anything a picture would only find later.

    Three gates, each of which has actually gone wrong in this repo or is one
    step away from it: inside-out winding (a whole milestone, silently),
    a prop tall enough to hide a soldier (D-045's readability rule, and the
    reason cover is allowed to exist at all), and a prop floating above or
    sunk below the ground it is placed on.

    Returns the bounds the manifest records, so the GDScript side can assert
    the same height rule against the SHIPPED numbers rather than trusting
    this to have run.
    """
    for part in model.parts:
        volume = _signed_volume(part.verts, part.faces)
        if volume <= 0.0:
            raise SystemExit(
                f"{name}: part '{part.name}' is wound inside-out "
                f"(signed volume {volume:.6f}). Its normals would point in, so "
                f"it would be lit by the inverse of the sun — the defect that "
                f"hid for a whole milestone in geom.box (D-081).")

    ys = [v[1] for part in model.parts for v in part.verts]
    low, high = min(ys), max(ys)
    if high > MAX_HEIGHT:
        raise SystemExit(
            f"{name}: {high:.3f} units tall exceeds MAX_HEIGHT {MAX_HEIGHT} — "
            f"ground cover must never hide a soldier (D-045, D-100).")
    if low < -0.01:
        raise SystemExit(
            f"{name}: reaches {low:.3f} below its base. Props are placed ON the "
            f"sampled ground, so anything below y=0 is buried.")
    if high < 0.05:
        raise SystemExit(f"{name}: {high:.3f} units tall is invisible at play distance.")

    tris = model.triangle_count()
    if tris > TRIANGLE_BUDGET:
        raise SystemExit(
            f"{name}: {tris} triangles exceeds the {TRIANGLE_BUDGET} prop budget. "
            f"Tens of thousands of these are drawn at once (D-100).")

    return {"height": round(high, 6), "base": round(low, 6)}


def build(name: str) -> Model:
    """Build one prop by name. Pure — no seeds, no clock, no globals.

    The assembled model is settled onto y=0 as a whole (never per part, which
    would push a mushroom cap down through its own stem). `GroundCover` places
    a prop at the terrain height sampled at its own offset, so "the model's
    lowest point is its footing" is the contract between this file and that
    one — a prop authored 5 mm high hovers over the whole map.
    """
    model = ROSTER[name].build()
    lowest = min(v[1] for part in model.parts for v in part.verts)
    if lowest != 0.0:
        for part in model.parts:
            part.verts = [(v[0], v[1] - lowest, v[2]) for v in part.verts]
    return model
