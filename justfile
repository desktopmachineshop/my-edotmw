# my-edotmw dev command vocabulary — see CLAUDE.md and
# game_design_decisions.md D-014/D-015.
#
# Runtime backend switch (D-014):
#   EDOTMW_RUNTIME=docker  (default) — headless server, bots, tests.
#   EDOTMW_RUNTIME=native            — needs portable Godot in tools/;
#                                      required for the GUI editor and
#                                      GUI client, which cannot be
#                                      containerized (see D-014).
# Recipes are the stable interface either way; only the backend
# invocation differs.
#
# STATUS (M0 complete): doctor / bootstrap / up / down / nuke / status /
# run-bots / test-unit are real and verified. run-server / run-client /
# gen-terrain-preview reference scenes that don't exist until M1 and
# fail loudly rather than silently succeeding; test-load is wired
# correctly but gated on run-server, so it fails clearly until M1. Per
# CLAUDE.md's testing section: a recipe must never report success for
# something that didn't run.
#
# Note: recipes invoke each other via {{just_executable()}}, not a bare
# `just` — `just` normally lives in tools/ and is NOT on PATH.

set shell := ["bash", "-cu"]

godot_version := `cat .godot-version`
runtime := env_var_or_default("EDOTMW_RUNTIME", "docker")
tools_dir := justfile_directory() + "/tools"
artifacts_dir := justfile_directory() + "/artifacts"
native_godot := tools_dir + "/godot"

# Single source of truth for the M1 server entry scene, so the recipes
# that depend on it agree about when it exists.
server_scene := "server.tscn"

[doc("List all available recipes")]
default:
    @"{{just_executable()}}" --list

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
    if [ -x "{{tools_dir}}/just.exe" ] || [ -x "{{tools_dir}}/just" ]; then
        echo "OK: just present in {{tools_dir}}"
    elif command -v just >/dev/null 2>&1; then
        echo "OK: just on PATH"
    else
        echo "FAIL: just not found on PATH or in {{tools_dir}}"
        exit 1
    fi
    echo "OK: preflight passed"

# Fetch the pinned portable Godot into tools/ (only needed for the
# native runtime — the docker runtime builds its own Godot into the
# image). This downloads a file, so it is deliberately an explicit,
# user-invoked step and never a side effect of another recipe.
#
# For a fresh clone with no `just` yet, run ./bootstrap.ps1 first — it
# fetches `just` itself and resolves the chicken-and-egg.
[doc("Fetch pinned portable Godot into tools/ (native runtime only)")]
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{tools_dir}}"
    if [ -x "{{native_godot}}" ] || [ -x "{{native_godot}}.exe" ]; then
        echo "Godot {{godot_version}} already present in {{tools_dir}} — nothing to do."
        exit 0
    fi
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            asset="Godot_v{{godot_version}}-stable_win64.exe.zip"
            target="{{native_godot}}.exe" ;;
        *)
            asset="Godot_v{{godot_version}}-stable_linux.x86_64.zip"
            target="{{native_godot}}" ;;
    esac
    url="https://github.com/godotengine/godot-builds/releases/download/{{godot_version}}-stable/${asset}"
    echo "Fetching ${asset} ..."
    curl -fsSL -o "{{tools_dir}}/godot.zip" "$url"
    unzip -o -q "{{tools_dir}}/godot.zip" -d "{{tools_dir}}"
    rm -f "{{tools_dir}}/godot.zip"
    extracted="$(find "{{tools_dir}}" -maxdepth 1 -name 'Godot_v{{godot_version}}-stable*' -type f | head -n 1)"
    if [ -z "$extracted" ]; then
        echo "FAIL: could not find the extracted Godot binary in {{tools_dir}}" >&2
        exit 1
    fi
    mv "$extracted" "$target"
    chmod +x "$target"
    echo "OK: Godot {{godot_version}} installed at $target"

# Start the server detached (docker runtime only — native has no
# persistent 'up' state, use run-server directly).
[doc("Start the server detached (docker runtime)")]
up:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{server_scene}}" ]; then
        echo "NOT IMPLEMENTED UNTIL M1: {{server_scene}} doesn't exist yet, so there is no server to bring up." >&2
        exit 1
    fi
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw up -d --build server
    else
        echo "native runtime: nothing to bring up persistently — use 'just run-server'"
    fi

# Stop everything this project started. Never leaves a stray process or
# container behind (D-014's whole point). Safe to run when nothing is up.
[doc("Stop containers / tracked processes this project started")]
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

# Full teardown: containers, images, portable tools, artifacts, import
# caches. Leaves the repo as pure source. Safe to run any time.
#
# This deletes tools/ — including the `just` binary you are running it
# with. That is intentional (D-014: teardown must leave nothing behind);
# re-run ./bootstrap.ps1 to come back.
[doc("Full teardown: containers, images, tools/, artifacts, caches")]
nuke: down
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw down --rmi all --volumes --remove-orphans || true
    fi
    rm -rf "{{tools_dir}}" "{{artifacts_dir}}" .godot .godot-container
    echo "nuked: repo is back to pure source"
    echo "note: tools/ (including just) is gone — run ./bootstrap.ps1 to set up again."

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
    if [ ! -f "{{server_scene}}" ]; then
        echo "NOT IMPLEMENTED UNTIL M1: {{server_scene}} doesn't exist yet." >&2
        exit 1
    fi
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm --service-ports server
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --path . "{{server_scene}}"
    fi

# Manual dev loop: run a client. Always native — needs a GPU (D-014).
run-client:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "NOT IMPLEMENTED UNTIL M1: no client scene/UI exists yet." >&2
    exit 1

# Spawn N virtual load-test bots in a SINGLE process (D-018 sizing note)
# against a running server. The recipe is real; bot_client.gd is still a
# stub that reports intent rather than connecting — that lands in M1.
[doc("Spawn N virtual load-test bots in one process")]
run-bots N:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm bots --headless --script bot_client.gd -- --clients={{N}}
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script bot_client.gd -- --clients={{N}}
    fi

# GUT unit tests, headless. Imports the project first so global
# class_names (UnitDef, PrimitiveUnit, GUT's own classes) are registered
# — Godot's headless import cache is required before gut_cmdln.gd can
# resolve them, and is otherwise a confusing first-run failure.
[doc("Run the GUT test suite headless")]
test-unit:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm test --path . --import
        docker compose -p edotmw run --rm test
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --path . --import
        "$godot" --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
    fi

# Full load test: server + N bots for DURATION seconds, then scan logs
# for warnings/desyncs. Teardown runs via trap on success, failure, AND
# Ctrl-C — an interrupted load test must not leave containers running
# (D-014). Gated on run-server, so this fails clearly until M1.
[doc("Load test: server + N bots for DURATION seconds, then scan logs")]
test-load N DURATION:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    trap '"{{just_executable()}}" down' EXIT INT TERM
    "{{just_executable()}}" up
    "{{just_executable()}}" run-bots {{N}} > "{{artifacts_dir}}/test-load-bots.log" 2>&1 &
    bots_pid=$!
    sleep {{DURATION}}
    kill "$bots_pid" 2>/dev/null || true
    wait "$bots_pid" 2>/dev/null || true
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw logs server > "{{artifacts_dir}}/test-load-server.log" 2>&1 || true
    fi
    if grep -Ein "warning|desync" "{{artifacts_dir}}"/test-load-*.log; then
        echo "test-load: warnings/desyncs found (see {{artifacts_dir}}/)" >&2
        exit 1
    fi
    echo "test-load: clean"

# Fast terrain-gen iteration loop without launching the full game.
gen-terrain-preview:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "NOT IMPLEMENTED UNTIL M1: terrain_preview.gd doesn't exist yet." >&2
    exit 1
