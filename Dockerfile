# Headless-only layer (D-014): server, bots, tests, terrain preview.
# The GUI editor and GUI client are NOT containerized — see
# game_design_decisions.md D-014 for why (no GPU benefit on the dev
# machine, GPU passthrough into a Linux container on Windows is fragile).
#
# NOT YET BUILD-TESTED: WSL2/Docker Desktop is broken on the dev machine
# as of 2026-07-28 (see game_design_decisions.md D-014 consequences).
# This file is scaffolded to be correct, but hasn't been run through
# `docker build` yet. Verify once WSL2 is repaired.

FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.1
ENV GODOT_VERSION=${GODOT_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/godot.zip \
        "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -q /tmp/godot.zip -d /usr/local/bin \
    && mv "/usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /work

ENTRYPOINT ["godot", "--headless"]
