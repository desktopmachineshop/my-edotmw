# Headless-only layer (D-014): server, bots, tests, terrain preview.
# The GUI editor and GUI client are NOT containerized — see
# game_design_decisions.md D-014 for why (no GPU benefit on the dev
# machine, GPU passthrough into a Linux container on Windows is fragile).
#
# Build-verified 2026-07-28 (D-014 update): WSL2 repaired, Docker Desktop
# installed, `docker compose build server` and `docker compose run --rm
# bots` both confirmed working end-to-end. `docker` is now the default
# EDOTMW_RUNTIME.
#
# GDScript only — no .NET SDK belongs in this image (D-021). If a kernel
# ever needs native speed the answer is GDExtension, which changes the
# build matrix rather than this base layer.

FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.1
ENV GODOT_VERSION=${GODOT_VERSION}

# libfontconfig1 is not needed to run anything headless, but without it
# Godot emits ten "Unable to load fontconfig" ERROR lines on every single
# invocation. That noise floods the logs `just test-load` scans, and a
# log full of routine ERRORs is one where a real one goes unnoticed.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/godot.zip \
        "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -q /tmp/godot.zip -d /usr/local/bin \
    && mv "/usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /work

ENTRYPOINT ["godot", "--headless"]
