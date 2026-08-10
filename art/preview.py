"""Offline contact sheet of every model and clip.

    tools/blender-venv/bin/python art/preview.py [--out artifacts/models.png]

A tiny orthographic software rasteriser — no GPU, no Godot, no Blender render
engine. It exists because the alternative feedback loop for "is the shape
right?" is a full asset build plus an engine launch, and at that price the
models do not get looked at often enough.

`CLAUDE.md` records why looking matters: the first frame the client ever
rendered contained no soldiers while every numeric check passed. A triangle
count and a budget check cannot tell you a spearman is holding his spear through
his own head.

This is a PREVIEW, deliberately not a renderer. It approximates what Godot will
draw — same vertex colours, same owner-colour mix (D-052), same flat shading —
but the authority on appearance remains `just test-client` and, for anything
about performance, `just bench-render` on real hardware.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from art.lib.bake import flatten, bake_frames, _face_normal      # noqa: E402
from art.lib.clips import CLIP_ORDER, FRAMES_PER_CLIP            # noqa: E402
from art.lib.soldier import build as build_soldier               # noqa: E402
from art.units import ROSTER                                     # noqa: E402

CELL = 200
BACKGROUND = (0.13, 0.14, 0.16)
LIGHT = np.array([0.45, 0.80, 0.38])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
# A stand-in player colour, so the preview shows what the mask actually does.
OWNER_COLOUR = np.array([0.20, 0.45, 0.85])


def _basis():
    """A fixed three-quarter view, roughly the angle the game is played at."""
    forward = np.array([0.62, -0.52, 0.85])
    forward = forward / np.linalg.norm(forward)
    right = np.cross(np.array([0.0, 1.0, 0.0]), forward)
    right = right / np.linalg.norm(right)
    up = np.cross(forward, right)
    return right, up


def render(positions, normals, colours, triangles, size=CELL, height=2.1):
    """Flat-shaded orthographic render with a z-buffer. Returns (size,size,3)."""
    right, up = _basis()
    verts = np.asarray(positions, dtype=float)

    # Project. Scale so `height` world units fill the frame, and centre on the
    # model's own footprint so a mounted unit is not cropped.
    u = verts @ right
    v = verts @ up
    depth = verts @ np.cross(right, up)

    scale = size / height
    cx = (u.min() + u.max()) / 2.0
    px = (u - cx) * scale + size / 2.0
    py = size - ((v - v.min()) * scale + size * 0.06)

    image = np.zeros((size, size, 3))
    image[:, :] = BACKGROUND
    zbuf = np.full((size, size), np.inf)

    cols = np.asarray(colours, dtype=float)
    norms = np.asarray(normals, dtype=float)

    for tri in triangles:
        i0, i1, i2 = tri
        x0, y0 = px[i0], py[i0]
        x1, y1 = px[i1], py[i1]
        x2, y2 = px[i2], py[i2]

        min_x = max(int(math.floor(min(x0, x1, x2))), 0)
        max_x = min(int(math.ceil(max(x0, x1, x2))), size - 1)
        min_y = max(int(math.floor(min(y0, y1, y2))), 0)
        max_y = min(int(math.ceil(max(y0, y1, y2))), size - 1)
        if min_x > max_x or min_y > max_y:
            continue

        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue

        ys, xs = np.mgrid[min_y:max_y + 1, min_x:max_x + 1]
        xs_c, ys_c = xs + 0.5, ys + 0.5
        w0 = ((x1 - x0) * (ys_c - y0) - (y1 - y0) * (xs_c - x0)) / area
        w1 = ((x2 - x1) * (ys_c - y1) - (y2 - y1) * (xs_c - x1)) / area
        w2 = 1.0 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue

        z = w2 * depth[i0] + w0 * depth[i2] + w1 * depth[i1]
        patch = zbuf[min_y:max_y + 1, min_x:max_x + 1]
        visible = inside & (z < patch)
        if not visible.any():
            continue

        base = cols[i0][:3]
        mask = cols[i0][3]
        albedo = base * (1.0 - mask) + OWNER_COLOUR * mask
        n = norms[i0]
        lambert = max(float(np.dot(n, LIGHT)), 0.0)
        shade = albedo * (0.32 + 0.68 * lambert)

        patch[visible] = z[visible]
        target = image[min_y:max_y + 1, min_x:max_x + 1]
        target[visible] = np.clip(shade, 0.0, 1.0)

    return image


def _label_bar(width: int, height: int = 3) -> np.ndarray:
    bar = np.zeros((height, width, 3))
    bar[:, :] = (0.30, 0.32, 0.36)
    return bar


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(_ROOT, "artifacts", "models.png"))
    parser.add_argument("--frames", type=int, default=4,
                        help="frames sampled per clip")
    args = parser.parse_args()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    columns = 1 + len(CLIP_ORDER) * args.frames
    rows: list[np.ndarray] = []

    for archetype in sorted(ROSTER):
        model = build_soldier(archetype, ROSTER[archetype])
        flat = flatten(model)
        positions_per_frame, normals_per_frame = bake_frames(model, flat)

        height = 2.6 if ROSTER[archetype].mount else 2.1
        cells = [render(flat["positions"], flat["normals"], flat["colours"],
                        flat["triangles"], height=height)]

        for clip_index, _clip in enumerate(CLIP_ORDER):
            for k in range(args.frames):
                f = clip_index * FRAMES_PER_CLIP + int(k * FRAMES_PER_CLIP / args.frames)
                cells.append(render(positions_per_frame[f], normals_per_frame[f],
                                    flat["colours"], flat["triangles"],
                                    height=height))
        row = np.concatenate(cells, axis=1)
        rows.append(row)
        rows.append(_label_bar(row.shape[1]))
        print(f"  {archetype:16s} {model.triangle_count():4d} tris")

    sheet = np.concatenate(rows, axis=0)

    import bpy
    h, w = sheet.shape[0], sheet.shape[1]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    # Preview only, so encode straight to sRGB-ish for viewing rather than
    # carrying linear data nobody is going to composite.
    rgba[:, :, :3] = np.clip(sheet[::-1], 0.0, 1.0) ** (1.0 / 2.2)
    image = bpy.data.images.new("preview", width=w, height=h, alpha=False)
    image.pixels = rgba.reshape(-1).tolist()
    image.file_format = "PNG"
    image.filepath_raw = args.out
    image.save()
    print(f"wrote {args.out}  ({w}x{h}, columns: rest + "
          f"{'/'.join(CLIP_ORDER)} x{args.frames})")


if __name__ == "__main__":
    main()
