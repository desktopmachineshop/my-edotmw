"""Per-biome terrain texture atlas (D-066).

## The atlas modulates; it does not decide

D-066 keeps `TerrainGen.biome_color()` as the single source of truth for what a
cell looks like, because that function also feeds the minimap and the preview
PNG, and because `terrain_gen.gd` states the invariant plainly: a cell that
looks like forest is a cell that yields wood, by construction.

So every tile here is written to average close to NEUTRAL. The mesh multiplies
tile by vertex colour, so a tile whose mean is 1.0 leaves the biome's colour
exactly as `biome_color` chose it, and the tile's job is only the variation
around that mean. A tile with a colour cast would tint the biome and quietly
put the 3D view out of step with the minimap — which is the failure this whole
arrangement exists to prevent.

`NEUTRAL_MEAN` is slightly under 1.0 on purpose: terrain detail reads better
when the texture darkens crevices than when it brightens peaks, and the shading
in this game is a single directional light with no ambient occlusion to do that
job.

## Tiles must tile

Each tile repeats across thousands of hexes, so its noise is PERIODIC by
construction — the lattice is generated with wraparound and interpolated, rather
than generated large and cropped. This is the same discipline `terrain_gen.gd`
already applies to the world itself for the torus seam (D-008); here the reason
is a visible grid rather than a visible seam, but the fix is the same shape.

## Biome order is a contract

`BIOMES` must match `TerrainGen.Biome`'s enum order exactly — the mesh computes
a tile index from the biome value, so a reordering here silently paints forest
on water. A Godot-side test asserts the two agree.
"""

from __future__ import annotations

import os

import numpy as np

# Must match the enum order in terrain_gen.gd.
BIOMES = (
    "deep_water", "water", "beach", "dry_grassland",
    "grassland", "forest", "mountain", "peak",
)

TILE = 512
COLUMNS = 4
ROWS = 2
NEUTRAL_MEAN = 0.92
SEED = 20260809          # fixed: D-063 criterion 1 wants byte-identical rebuilds


def _periodic_noise(size: int, period: int, rng: np.random.Generator) -> np.ndarray:
    """Value noise that wraps exactly at `size`, built on a `period` lattice."""
    lattice = rng.random((period, period))
    # Bilinear interpolation with wraparound indices.
    ys = np.linspace(0.0, period, size, endpoint=False)
    xs = np.linspace(0.0, period, size, endpoint=False)
    y0 = np.floor(ys).astype(int) % period
    x0 = np.floor(xs).astype(int) % period
    y1 = (y0 + 1) % period
    x1 = (x0 + 1) % period
    fy = (ys - np.floor(ys))[:, None]
    fx = (xs - np.floor(xs))[None, :]
    # Smoothstep, so the lattice does not read as diamonds.
    fy = fy * fy * (3.0 - 2.0 * fy)
    fx = fx * fx * (3.0 - 2.0 * fx)

    top = lattice[np.ix_(y0, x0)] * (1 - fx) + lattice[np.ix_(y0, x1)] * fx
    bottom = lattice[np.ix_(y1, x0)] * (1 - fx) + lattice[np.ix_(y1, x1)] * fx
    return top * (1 - fy) + bottom * fy


def _fbm(size: int, octaves: int, base_period: int,
         rng: np.random.Generator) -> np.ndarray:
    """Fractal sum of periodic noise. Stays periodic because every octave is."""
    total = np.zeros((size, size))
    amplitude = 1.0
    norm = 0.0
    period = base_period
    for _ in range(octaves):
        total += _periodic_noise(size, period, rng) * amplitude
        norm += amplitude
        amplitude *= 0.5
        period *= 2
    return total / norm


def _normalise(field: np.ndarray, spread: float) -> np.ndarray:
    """Centre a field on 1.0 with a given peak-to-peak spread."""
    centred = field - field.mean()
    peak = np.abs(centred).max()
    if peak > 1e-9:
        centred = centred / peak
    return 1.0 + centred * spread


def _tile(biome: str, rng: np.random.Generator) -> np.ndarray:
    """One RGB tile, centred near neutral. Returns (TILE, TILE, 3) floats."""
    if biome in ("deep_water", "water"):
        # Broad, soft swell. Water is mostly flat colour with slow variation;
        # high-frequency detail here reads as static.
        field = _fbm(TILE, 3, 3, rng)
        value = _normalise(field, 0.10)
        tint = np.stack([value * 0.97, value, value * 1.04], axis=-1)
    elif biome == "beach":
        grain = _fbm(TILE, 5, 16, rng)
        value = _normalise(grain, 0.13)
        tint = np.stack([value * 1.03, value, value * 0.96], axis=-1)
    elif biome in ("grassland", "dry_grassland"):
        # Two scales: clumping at low frequency, blade speckle at high.
        clump = _fbm(TILE, 3, 4, rng)
        speckle = _fbm(TILE, 2, 48, rng)
        spread = 0.18 if biome == "grassland" else 0.22
        value = _normalise(clump * 0.6 + speckle * 0.4, spread)
        warm = 1.06 if biome == "dry_grassland" else 0.98
        tint = np.stack([value * warm, value, value * 0.94], axis=-1)
    elif biome == "forest":
        # Canopy: rounded blobs with dark gaps between them.
        canopy = _fbm(TILE, 4, 6, rng)
        canopy = np.clip((canopy - 0.35) * 2.2, 0.0, 1.0)
        detail = _fbm(TILE, 2, 32, rng)
        value = _normalise(canopy * 0.75 + detail * 0.25, 0.30)
        tint = np.stack([value * 0.94, value, value * 0.90], axis=-1)
    elif biome == "mountain":
        # Strata: stretched noise, so the rock reads as bedded rather than
        # cloudy.
        rock = _fbm(TILE, 5, 8, rng)
        strata = _fbm(TILE, 3, 24, rng)
        strata = np.roll(strata, TILE // 3, axis=1)
        value = _normalise(rock * 0.65 + strata * 0.35, 0.26)
        tint = np.stack([value, value * 0.99, value * 0.98], axis=-1)
    else:  # peak
        snow = _fbm(TILE, 4, 10, rng)
        value = _normalise(snow, 0.12)
        tint = np.stack([value * 0.99, value, value * 1.03], axis=-1)

    return np.clip(tint * NEUTRAL_MEAN, 0.0, 2.0)


def build_atlas() -> np.ndarray:
    """Assemble every biome tile into one sheet. Returns (H, W, 3) floats."""
    sheet = np.zeros((ROWS * TILE, COLUMNS * TILE, 3))
    for index, biome in enumerate(BIOMES):
        # One RNG stream per biome, seeded from its index, so adding a biome
        # later cannot change the appearance of the ones before it.
        rng = np.random.default_rng(SEED + index * 977)
        row, col = divmod(index, COLUMNS)
        sheet[row * TILE:(row + 1) * TILE, col * TILE:(col + 1) * TILE] = _tile(biome, rng)
    return sheet


def write_atlas(out_dir: str) -> dict:
    """Write the atlas PNG and return its layout metadata."""
    import bpy

    os.makedirs(out_dir, exist_ok=True)
    sheet = build_atlas()
    height, width = sheet.shape[0], sheet.shape[1]

    # Blender images are bottom-row-first and RGBA.
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[:, :, :3] = sheet[::-1, :, :]

    image = bpy.data.images.new("terrain_atlas", width=width, height=height,
                                alpha=False)
    image.pixels = rgba.reshape(-1).tolist()
    image.file_format = "PNG"
    path = os.path.join(out_dir, "terrain_atlas.png")
    image.filepath_raw = path
    image.save()

    return {
        "path": "generated/textures/terrain_atlas.png",
        "width": width,
        "height": height,
        "tile": TILE,
        "columns": COLUMNS,
        "rows": ROWS,
        "biomes": list(BIOMES),
        "neutral_mean": NEUTRAL_MEAN,
    }
