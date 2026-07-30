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

FROM debian:bookworm-slim AS base

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

# --- GUI test layer ---------------------------------------------------
#
# A second target, built only for `just test-client`. It renders the real
# GUI client with Mesa's llvmpipe software rasteriser under a virtual X
# server, so no GPU is involved at all.
#
# This does NOT reverse D-014. D-014 rejected containerising the GUI
# client for *interactive development* — GPU passthrough on this hardware
# is fragile and buys nothing — and that still stands; `just run-client`
# is still native. This target exists for a different job: an automated,
# reproducible check that the client renders the right thing, which was
# the one M1 exit criterion nothing could verify.
#
# Software rendering is a feature here, not a compromise. Output does not
# vary with driver version or vendor, so a rendered frame is comparable
# run to run. What it deliberately does NOT test is real GPU behaviour or
# performance — that remains a human judgement made via `just run-client`.
#
# xauth is required by xvfb-run even though nothing authenticates; without
# it xvfb-run fails with a bare "xauth command not found".
FROM base AS gui

RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb x11-utils \
        libgl1-mesa-dri libglu1-mesa libegl1 \
        libxcursor1 libxinerama1 libxrandr2 libxi6 libxkbcommon0 \
        libasound2 libpulse0 libudev1 \
    && rm -rf /var/lib/apt/lists/*

# Force Mesa's software path rather than letting it probe for a GPU.
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV GALLIUM_DRIVER=llvmpipe

COPY gui_entrypoint.sh /usr/local/bin/gui_entrypoint.sh
RUN chmod +x /usr/local/bin/gui_entrypoint.sh

ENTRYPOINT ["/usr/local/bin/gui_entrypoint.sh"]
