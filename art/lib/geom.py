"""Pure-Python low-poly primitives and the rigid-part model (D-064).

No `bpy` import here on purpose. Mesh construction is plain arithmetic over
lists, so it can be unit-tested and iterated on without paying Blender's import
cost, and so a mistake in the shape is debuggable as data rather than through a
scene graph. `gltf.py` is the only module that touches Blender.

## Why rigid parts rather than a skinned armature

D-065 bakes animation into a vertex animation texture, and a VAT only needs to
know where each vertex is on each frame. Rigid parts with an explicit pivot give
that directly: a frame is a rotation per part, applied to that part's vertices.
An armature would add skinning weights, bind poses and an evaluation dependency
graph to produce the same numbers, and none of that survives the bake.

It also matches the art direction. Stylised low-poly reads on silhouette, and
rigid limbs rotating about clean pivots is the look, not a compromise toward it.

## Vertex colour carries two things

`rgb` is the part's own colour. `mask` goes in the ALPHA channel and marks how
much of this part is owner-coloured (D-052) — 1.0 on cloaks, shields and
banners, 0.0 on skin and steel. The shader mixes toward the player's colour by
that mask, so "whose army is this" survives on authored models without needing a
texture at all at this tier.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

Vec3 = tuple[float, float, float]


# --- primitives ---------------------------------------------------------
#
# Every primitive returns (verts, faces) with faces as triangles wound
# counter-clockwise when viewed from outside. Godot and glTF both use
# counter-clockwise front faces, so getting this wrong shows up as a model
# lit from the inside rather than as an error.


def box(size: Vec3, centre: Vec3 = (0.0, 0.0, 0.0),
        taper: float = 1.0) -> tuple[list[Vec3], list[tuple[int, int, int]]]:
    """An axis-aligned box, optionally tapered toward +Y.

    `taper` scales the top face in X and Z: 1.0 is a plain box, 0.7 gives the
    slight wedge that reads as a torso rather than a crate. 12 triangles.
    """
    sx, sy, sz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    cx, cy, cz = centre
    tx, tz = sx * taper, sz * taper

    verts: list[Vec3] = [
        (cx - sx, cy - sy, cz - sz), (cx + sx, cy - sy, cz - sz),
        (cx + sx, cy - sy, cz + sz), (cx - sx, cy - sy, cz + sz),
        (cx - tx, cy + sy, cz - tz), (cx + tx, cy + sy, cz - tz),
        (cx + tx, cy + sy, cz + tz), (cx - tx, cy + sy, cz + tz),
    ]
    faces = [
        (0, 2, 1), (0, 3, 2),          # bottom
        (4, 5, 6), (4, 6, 7),          # top
        (0, 1, 5), (0, 5, 4),          # -Z
        (2, 3, 7), (2, 7, 6),          # +Z
        (1, 2, 6), (1, 6, 5),          # +X
        (3, 0, 4), (3, 4, 7),          # -X
    ]
    return verts, faces


def prism(radius: float, height: float, sides: int = 6,
          centre: Vec3 = (0.0, 0.0, 0.0),
          taper: float = 1.0) -> tuple[list[Vec3], list[tuple[int, int, int]]]:
    """An N-sided prism about the Y axis. Used for helmets, shields and hafts.

    `sides=6` is the default because the whole game is hexagonal and it keeps
    the silhouette language consistent, not because it is cheapest.
    """
    cx, cy, cz = centre
    half = height / 2.0
    verts: list[Vec3] = []
    for ring, (y, r) in enumerate(((cy - half, radius), (cy + half, radius * taper))):
        for i in range(sides):
            a = math.tau * i / sides
            verts.append((cx + math.cos(a) * r, y, cz + math.sin(a) * r))
    bottom_centre = len(verts)
    verts.append((cx, cy - half, cz))
    top_centre = len(verts)
    verts.append((cx, cy + half, cz))

    faces: list[tuple[int, int, int]] = []
    for i in range(sides):
        j = (i + 1) % sides
        lo_i, lo_j, hi_i, hi_j = i, j, sides + i, sides + j
        faces.append((lo_i, hi_i, hi_j))
        faces.append((lo_i, hi_j, lo_j))
        faces.append((bottom_centre, lo_j, lo_i))
        faces.append((top_centre, hi_i, hi_j))
    return verts, faces


# --- parts --------------------------------------------------------------


def rotate_geometry(geometry, axis: str, angle: float, pivot: Vec3 = (0.0, 0.0, 0.0)):
    """Rotate a whole (verts, faces) pair in place of construction.

    `prism` builds about the Y axis, which is right for helmets and shields and
    wrong for anything held edge-on — a bow built about Y lies flat like a
    dinner plate. Rather than give every primitive an orientation argument, the
    few parts that need one are rotated after the fact.
    """
    verts, faces = geometry
    return [rotate_about(v, pivot, axis, angle) for v in verts], faces


@dataclass
class Part:
    """One rigid piece of a model, with the pivot it rotates about.

    Vertices are stored in MODEL space, not pivot-relative space. Posing
    subtracts the pivot, rotates, and adds it back — which keeps the rest pose
    directly readable as coordinates and means a part with no animation needs
    no special case.
    """

    name: str
    verts: list[Vec3]
    faces: list[tuple[int, int, int]]
    rgb: tuple[float, float, float]
    mask: float = 0.0
    pivot: Vec3 = (0.0, 0.0, 0.0)

    def triangle_count(self) -> int:
        return len(self.faces)


@dataclass
class Model:
    """An assembled model: parts in a fixed order, plus its tri budget."""

    name: str
    parts: list[Part] = field(default_factory=list)

    def add(self, name: str, geometry, rgb, mask: float = 0.0,
            pivot: Vec3 = (0.0, 0.0, 0.0)) -> Part:
        verts, faces = geometry
        part = Part(name=name, verts=list(verts), faces=list(faces),
                    rgb=rgb, mask=mask, pivot=pivot)
        self.parts.append(part)
        return part

    def triangle_count(self) -> int:
        return sum(p.triangle_count() for p in self.parts)

    def vertex_count(self) -> int:
        """Vertices AFTER flat-shading splits every triangle (see gltf.py).

        This is the number that sizes the VAT, so it is worth having on the
        model rather than rediscovering it at bake time.
        """
        return self.triangle_count() * 3


# --- posing -------------------------------------------------------------


def rotate_about(point: Vec3, pivot: Vec3, axis: str, angle: float) -> Vec3:
    """Rotate `point` about `pivot` around a world axis. Angle in radians."""
    x, y, z = point[0] - pivot[0], point[1] - pivot[1], point[2] - pivot[2]
    c, s = math.cos(angle), math.sin(angle)
    if axis == "x":
        y, z = y * c - z * s, y * s + z * c
    elif axis == "y":
        x, z = x * c + z * s, -x * s + z * c
    elif axis == "z":
        x, y = x * c - y * s, x * s + y * c
    else:
        raise ValueError(f"unknown axis {axis!r}")
    return (x + pivot[0], y + pivot[1], z + pivot[2])


def pose_part(part: Part, transforms: list[tuple[str, float]],
              offset: Vec3 = (0.0, 0.0, 0.0)) -> list[Vec3]:
    """Apply a list of (axis, angle) rotations about the part's pivot.

    Returns new vertices; never mutates the rest pose. Purity here is not
    stylistic — the rest pose is sampled again for every frame of every clip,
    and a mutating pose would make frame N depend on frame N-1, which is
    exactly the accumulation D-065 forbids on the runtime side.
    """
    out: list[Vec3] = []
    for v in part.verts:
        p = v
        for axis, angle in transforms:
            if angle:
                p = rotate_about(p, part.pivot, axis, angle)
        out.append((p[0] + offset[0], p[1] + offset[1], p[2] + offset[2]))
    return out
