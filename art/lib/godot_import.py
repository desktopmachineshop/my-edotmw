"""Godot import settings, written as part of the build (D-064).

## Why the build writes these at all

Godot stores per-asset import settings in a sibling `.import` file, normally
edited through the editor's Import dock. This project has no editor in the loop
by design, so an import setting that has to be remembered by a human is an
import setting that will be wrong.

## The one that actually bites

`detect_3d/compress_to` defaults to 1. The first time a texture is used in 3D,
Godot silently RE-IMPORTS it with VRAM block compression and mipmaps. For an
ordinary albedo texture that is a helpful default. For a vertex animation
texture it is corruption: block compression quantises position data across 4x4
texel blocks that have no spatial relationship to each other — neighbouring
columns are unrelated vertices — and mipmaps average vertices together.

The failure mode is the worst kind. It does not happen at build time, it happens
the first time the asset is rendered in 3D, and it leaves the model looking
subtly melted rather than broken. So it is turned off here, in generated data,
rather than trusted to a checklist.

Mipmaps are off for VATs for the same reason and on for the terrain atlas for
the opposite one — terrain is viewed at distance and needs them, and D-066's
tile inset keeps the mip chain from bleeding between biomes.
"""

from __future__ import annotations

import os

# Filtering is deliberately NOT set here: Godot 4 has no per-texture filter
# import setting, and the VAT's nearest-filtering requirement is expressed in
# the shader's sampler hint instead. Recorded so nobody hunts for it.

VAT_PARAMS = {
    "compress/mode": "0",
    "mipmaps/generate": "false",
    "detect_3d/compress_to": "0",
    "process/hdr_as_srgb": "false",
}

ATLAS_PARAMS = {
    "compress/mode": "0",
    "mipmaps/generate": "true",
    "detect_3d/compress_to": "0",
}

_STUB = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

"""


def ensure_import_params(asset_path: str, params: dict[str, str]) -> None:
    """Force `params` into the asset's `.import`, leaving everything else alone.

    Existing files are edited key by key rather than rewritten, because Godot
    owns `[remap]` and `[deps]` — including the asset's UID, which is committed
    and must stay stable across rebuilds. Overwriting the whole file would mint
    a new UID on every build and make `generated/` churn forever.
    """
    import_path = asset_path + ".import"

    if not os.path.exists(import_path):
        body = _STUB + "".join(f"{k}={v}\n" for k, v in sorted(params.items()))
        with open(import_path, "w", newline="\n") as handle:
            handle.write(body)
        return

    with open(import_path, "r", newline="") as handle:
        lines = handle.read().splitlines()

    remaining = dict(params)
    out: list[str] = []
    params_section = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            # Leaving [params]: anything still unwritten gets appended here, so
            # a key Godot has never emitted still lands in the right section.
            if params_section and remaining:
                out.extend(f"{k}={v}" for k, v in sorted(remaining.items()))
                remaining.clear()
            params_section = stripped == "[params]"
            out.append(line)
            continue

        key = stripped.split("=", 1)[0] if "=" in stripped else None
        if params_section and key in remaining:
            out.append(f"{key}={remaining.pop(key)}")
        else:
            out.append(line)

    if remaining:
        if not params_section:
            out.append("")
            out.append("[params]")
            out.append("")
        out.extend(f"{k}={v}" for k, v in sorted(remaining.items()))

    with open(import_path, "w", newline="\n") as handle:
        handle.write("\n".join(out).rstrip("\n") + "\n")
