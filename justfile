# my-edotmw dev command vocabulary — see CLAUDE.md and
# game_design_decisions.md D-014/D-015.
#
# Runtime backend switch (D-014): EDOTMW_RUNTIME=native (default, works
# without Docker/WSL2) or EDOTMW_RUNTIME=docker (once WSL2 + Docker
# Desktop are working — see `just doctor`). Recipes are the stable
# interface either way; only the backend invocation differs.
#
# STATUS (M0): doctor/up/down/nuke/status/bootstrap and run-bots are
# real. run-server/run-client/test-unit/gen-terrain-preview reference
# scenes/scripts/addons that don't exist yet (server.tscn, tests/, GUT,
# terrain_preview.gd) — they fail loudly with "not implemented until M1"
# rather than silently succeeding. See CLAUDE.md's testing section: a
# recipe must never report success for something that didn't run.

set shell := ["bash", "-cu"]

godot_version := `cat .godot-version`
# Docker path verified working 2026-07-28 (see game_design_decisions.md
# D-014) — default is now docker; override with EDOTMW_RUNTIME=native
# for the GUI editor/client pieces that still can't be containerized.
runtime := env_var_or_default("EDOTMW_RUNTIME", "docker")
tools_dir := justfile_directory() + "/tools"
artifacts_dir := justfile_directory() + "/artifacts"
native_godot := tools_dir + "/godot"

default:
    @just --list

# Preflight: verify the current runtime's prerequisites are actually met.
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Runtime: {{runtime}}"
    echo "Pinned Godot version: {{godot_version}}"
    if [ "{{runtime}}" = "docker" ]; then
        command -v docker >/dev/null 2>&1 || { echo "FAIL: docker not found on PATH"; exit 1; }
        docker info >/dev/null 2>&1 || { echo "FAIL: docker daemon not reachable (Docker Desktop / WSL2 not running — see game_design_decisions.md D-014)"; exit 1; }
        echo "OK: docker reachable"
    else
        if [ ! -x "{{native_godot}}" ] && [ ! -x "{{native_godot}}.exe" ]; then
            echo "FAIL: portable Godot not found under {{tools_dir}} — run: just bootstrap"
            exit 1
        fi
        echo "OK: native godot present"
    fi
    if command -v just >/dev/null 2>&1; then
        echo "OK: just on PATH"
    elif [ -x "{{tools_dir}}/just.exe" ] || [ -x "{{tools_dir}}/just" ]; then
        echo "OK: just present in {{tools_dir}} (not on PATH — invoke via ./tools/just.exe)"
    else
        echo "FAIL: just not found on PATH or in {{tools_dir}}"
        exit 1
    fi

# Fetch the pinned portable Godot binary into tools/ (native runtime).
# Deliberately not automated in M0 — downloading a binary is an explicit,
# permission-gated step, not something a recipe does silently.
bootstrap:
    @echo "Fetch Godot {{godot_version}} (headless export template + editor) into {{tools_dir}}/ — ask before automating this, it downloads a file."
    @echo "See: https://godotengine.org/download/ or https://github.com/godotengine/godot-builds/releases/tag/{{godot_version}}-stable"

# Start the server detached (docker runtime only — native has no
# persistent 'up' state, use run-server directly).
up:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw up -d --build server
    else
        echo "native runtime: nothing to bring up persistently — use 'just run-server'"
    fi

# Stop everything this project started. Never leaves a stray process or
# container behind (D-014's whole point).
down:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw down --remove-orphans
    else
        if [ -f "{{artifacts_dir}}/server.pid" ]; then
            kill "$(cat {{artifacts_dir}}/server.pid)" 2>/dev/null || true
            rm -f "{{artifacts_dir}}/server.pid"
        fi
        echo "native runtime: stopped tracked processes (if any)"
    fi

# Full teardown: containers, image, portable tools, artifacts, import
# caches. Leaves the repo as pure source. Safe to run any time.
nuke: down
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw down --rmi all --volumes --remove-orphans || true
    fi
    rm -rf "{{tools_dir}}" "{{artifacts_dir}}" .godot .godot-container
    echo "nuked: repo is back to pure source"

# Running containers (docker) or tracked native processes.
status:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw ps
    else
        if [ -f "{{artifacts_dir}}/server.pid" ]; then
            echo "server pid: $(cat {{artifacts_dir}}/server.pid)"
        else
            echo "no tracked native server process"
        fi
    fi

# Manual dev loop: run the server in the foreground.
run-server:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "NOT IMPLEMENTED UNTIL M1: server.tscn / server bootstrap scene doesn't exist yet." >&2
    exit 1

# Manual dev loop: run a client (always native — needs a GPU, D-014).
run-client:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "NOT IMPLEMENTED UNTIL M1: no client scene/UI exists yet." >&2
    exit 1

# Spawn N virtual load-test bots (single process, D-018) against a
# running server. Real as of M0, but bot_client.gd is a stub — it
# reports intent, it does not actually connect until M1.
run-bots N:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm bots --headless --script bot_client.gd -- --clients={{N}}
    else
        "{{native_godot}}" --headless --script bot_client.gd -- --clients={{N}}
    fi

# GUT unit tests, headless. Imports the project first so global
# class_names (UnitDef, PrimitiveUnit, GUT's own classes) are registered
# — Godot's headless import cache is required before gut_cmdln.gd can
# resolve them, and is otherwise a confusing first-run failure.
test-unit:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm test --path . --import
        docker compose -p edotmw run --rm test
    else
        "{{native_godot}}" --headless --path . --import
        "{{native_godot}}" --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
    fi

# Full load test: server + N bots for DURATION seconds, then grep logs
# for warnings/desyncs. Depends on run-server, so fails until M1 by
# design — that's the honest state, not a bug.
test-load N DURATION:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    trap 'just down' EXIT
    just up
    just run-server > "{{artifacts_dir}}/test-load-server.log" 2>&1 &
    just run-bots {{N}} > "{{artifacts_dir}}/test-load-bots.log" 2>&1
    sleep {{DURATION}}
    if grep -Ei "warning|desync" "{{artifacts_dir}}"/test-load-*.log; then
        echo "test-load: warnings/desyncs found"
        exit 1
    fi
    echo "test-load: clean"

# Fast terrain-gen iteration loop without launching the full game.
gen-terrain-preview:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "NOT IMPLEMENTED UNTIL M1: terrain_preview.gd doesn't exist yet." >&2
    exit 1
