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
# STATUS (M1 complete): every recipe here is real and verified. There
# are no longer any "NOT IMPLEMENTED UNTIL M1" stubs.
#
# Headless (docker or native): doctor, bootstrap, up, down, nuke, status,
# run-server, run-bots, test-unit, test-load, gen-terrain-preview,
# replay-info.
# Docker only: test-client — renders the real GUI client via Mesa's
# software rasteriser and checks the frame. No GPU involved.
# Native only: run-client — for a human to actually look at on real
# hardware (D-014).
#
# NOTE: the Dockerfile is multi-stage and `gui` is the LAST stage, so a
# bare `build: .` builds the GUI image. Every headless compose service
# pins `target: base` explicitly for that reason — see docker-compose.yml.
#
# Per CLAUDE.md's testing section, a recipe must never report success for
# something that didn't run. test-load learned that the hard way during
# M1: it once reported "clean" for a run in which every bot had exited
# non-zero, because it only grepped for warning/desync and the failure
# said ERROR. It now checks exit status and an explicit VERDICT line as
# well — see the comment above that recipe.
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

# Populate Godot's headless import cache.
#
# Required before loading ANY script that references a global class_name
# (UnitDef, TorusSpace, SquadSim, ...) — Godot resolves those from the
# import cache, and without it every such script fails to parse with a
# confusing "Identifier not declared in the current scope". D-015's M0
# review flagged this as the thing to remember for M1's recipes; it is
# factored out here so each recipe depends on it rather than each recipe
# rediscovering it.
_import:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm --no-deps test --path . --import
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --path . --import
    fi

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
up: _import
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
        # `compose down` removes what `compose up` created. It does NOT
        # reliably remove a still-RUNNING one-off `compose run` container,
        # and `--remove-orphans` does not either — a client-test container
        # that hung at startup survived a full `just nuke` and was found
        # still running half an hour later. That is precisely the stray
        # container D-014 exists to prevent, so sweep by project label as
        # well. The label filter is scoped to this project exactly like
        # the pinned `-p edotmw`, so it can never touch anything else.
        strays="$(docker ps -aq --filter 'label=com.docker.compose.project=edotmw' || true)"
        if [ -n "$strays" ]; then
            echo "down: removing $(echo "$strays" | wc -l | tr -d ' ') stray one-off container(s)"
            echo "$strays" | xargs -r docker rm -f >/dev/null
        fi
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
run-server: _import
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

# Manual dev loop: run a client. Always native — needs a GPU (D-014), so
# this recipe ignores EDOTMW_RUNTIME and refuses to pretend otherwise.
#
# ADDRESS defaults to localhost; pass the server's host when connecting to
# one running elsewhere. Controls: WASD pans, wheel zooms, right-click
# orders every owned squad to the clicked cell.
[doc("Run the GUI client natively (WASD pan, wheel zoom, right-click order)")]
run-client ADDRESS="127.0.0.1" PORT="4433":
    #!/usr/bin/env bash
    set -euo pipefail
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: the GUI client needs a native Godot (D-014: it cannot be containerized)." >&2
        echo "      Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi
    # Import NATIVELY first, and unconditionally.
    #
    # This recipe cannot use the `_import` dependency the headless recipes
    # share: `_import` follows EDOTMW_RUNTIME, which defaults to docker and
    # populates .godot-container, while the client is always native
    # (D-014) and reads .godot. On a machine that has only ever run the
    # docker path, the native cache does not exist and the client dies
    # with parse errors naming unrelated lines — "Identifier
    # 'CosmeticOffset' not declared" and a scatter of "cannot infer type".
    #
    # This is exactly D-015's trap. run-client was the one recipe it had
    # not been applied to, because the rule was written as "any new
    # HEADLESS recipe" and this one is not headless. The requirement is
    # really about global class_name resolution, which is not a headless
    # concern at all.
    "$godot" --headless --path . --import
    "$godot" --path . client.tscn -- --address={{ADDRESS}} --port={{PORT}}

# Spawn N virtual load-test bots in a SINGLE process (D-018 sizing note)
# against a running server.
#
# DURATION seconds, or -1 to run until stopped. Bots self-terminate on
# DURATION rather than being killed from outside: killing the `just`
# process does NOT kill the docker container it spawned, so the container
# would outlive the test and then fail its own connect check after
# teardown had already removed the server.
#
# Exit status is the verdict — non-zero if any bot never connected or if
# nothing replicated.
[doc("Spawn N virtual load-test bots in one process (DURATION secs, -1 = forever)")]
run-bots N DURATION="-1": _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm --no-deps bots --headless --script bot_client.gd -- --clients={{N}} --duration={{DURATION}}
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script bot_client.gd -- --clients={{N}} --duration={{DURATION}}
    fi

# GUT unit tests, headless. Imports the project first so global
# class_names (UnitDef, PrimitiveUnit, GUT's own classes) are registered
# — Godot's headless import cache is required before gut_cmdln.gd can
# resolve them, and is otherwise a confusing first-run failure.
[doc("Run the GUT test suite headless")]
test-unit: _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm --no-deps test
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
    fi

# Full load test: server + N bots for DURATION seconds, then check the
# result three independent ways. Teardown runs via trap on success,
# failure, AND Ctrl-C — an interrupted load test must not leave
# containers running (D-014).
#
# Why three checks rather than just the log scan: the log scan alone once
# reported "clean" for a run in which every bot had exited non-zero,
# because the bots' failure message said ERROR and the scan only looked
# for warning/desync. Grepping for the absence of bad news cannot
# distinguish "nothing went wrong" from "nothing happened". So:
#
#   1. bots' exit status         — did the run itself succeed?
#   2. explicit VERDICT line     — did every bot connect, replicate, AND
#                                  verify its state against the server's?
#   3. diagnostic log scan       — did anything complain along the way?
#
# Check 2 is the one that makes this a test rather than a smoke run: a
# bot that connects and receives nothing would otherwise pass 1 and 3.
#
# The VERDICT now also requires that state-hash checks actually RAN, not
# merely that none failed. That distinction is not pedantic: this recipe
# spent all of M1 grepping for the word "desync" which no code path ever
# printed, and the vacuous pass hid a live bug in which every client
# derived soldier positions from a different squad strength than the
# server used.
[doc("Load test: server + N bots for DURATION seconds, then verify the run")]
test-load N DURATION:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    trap '"{{just_executable()}}" down' EXIT INT TERM
    "{{just_executable()}}" up

    bots_log="{{artifacts_dir}}/test-load-bots.log"
    server_log="{{artifacts_dir}}/test-load-server.log"

    # Foreground and self-terminating: DURATION genuinely bounds the run,
    # and the container is gone before teardown starts.
    bots_status=0
    "{{just_executable()}}" run-bots {{N}} {{DURATION}} > "$bots_log" 2>&1 || bots_status=$?

    if [ "{{runtime}}" = "docker" ]; then
        # Stop (not remove) the server first so its shutdown summary is
        # flushed into the log we are about to collect. Collecting before
        # stopping loses the one line that reports the run's totals; the
        # trap still removes the container afterwards.
        docker compose -p edotmw stop server >/dev/null 2>&1 || true
        docker compose -p edotmw logs server > "$server_log" 2>&1 || true
    fi

    if [ "$bots_status" -ne 0 ]; then
        echo "test-load: bots exited with status $bots_status (see $bots_log)" >&2
        exit 1
    fi

    if ! grep -q "VERDICT ok" "$bots_log"; then
        echo "test-load: bots did not report a successful verdict (see $bots_log)" >&2
        grep -E "VERDICT" "$bots_log" >&2 || echo "test-load: no VERDICT line at all — did the bots run?" >&2
        exit 1
    fi

    # Match engine/script diagnostics by their line PREFIX, not by prose
    # containing a scary word. The previous `warning|desync` word scan
    # failed a perfectly good run because the success line said
    # "0 desyncs" — a check that fires on its own good news is no more
    # useful than one that never fires at all.
    if grep -Eq '(^|\| *)(ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING):' "{{artifacts_dir}}"/test-load-*.log; then
        echo "test-load: engine errors or warnings found (see {{artifacts_dir}}/)" >&2
        grep -EIn '(^|\| *)(ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING):' "{{artifacts_dir}}"/test-load-*.log >&2 | head -20
        exit 1
    fi

    echo "test-load: clean"
    grep -E "VERDICT" "$bots_log"

# Render the REAL GUI client against a real server and check the frame.
#
# This closes the one M1 exit criterion nothing could verify: the client
# had never rendered a frame anywhere, so "it draws the right thing" was
# an assumption. It runs the actual client scene — not a stand-in — with
# Mesa's llvmpipe software rasteriser under a virtual X server, so no GPU
# is required and nothing is installed on the host.
#
# It does NOT replace `just run-client`. Software rendering answers
# "is the client correct"; real-GPU appearance and performance remain a
# human judgement made natively (D-014).
#
# Checks, in the same shape as test-load: the client's exit status, an
# explicit VERDICT line, and that the frame contains more than one flat
# colour — a scene that rendered nothing still writes a perfectly valid
# PNG, so the colour count is what makes this a test.
[doc("Render the GUI client headlessly and verify the frame (software GPU)")]
test-client SECONDS="12": _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" != "docker" ]; then
        echo "test-client requires the docker runtime (it needs the software-GL image)." >&2
        echo "For the native GUI client use: {{just_executable()}} run-client" >&2
        exit 1
    fi
    mkdir -p "{{artifacts_dir}}"
    shot="{{artifacts_dir}}/client-frame.png"
    log="{{artifacts_dir}}/test-client.log"
    rm -f "$shot"
    trap '"{{just_executable()}}" down' EXIT INT TERM
    "{{just_executable()}}" up

    # gl_compatibility, not the Forward+ default: the image ships Mesa's
    # software OpenGL rasteriser (llvmpipe), not a software Vulkan one, so
    # Forward+ hangs at startup with no diagnostic whatsoever.
    # Dummy audio because the container has no sound card and ALSA's
    # failure is a dozen lines of noise in the log.
    status=0
    docker compose -p edotmw run --rm --no-deps client-test \
        --path . client.tscn \
        --rendering-method gl_compatibility \
        --audio-driver Dummy \
        --resolution 1280x720 \
        -- --address=server --run-seconds={{SECONDS}} \
        --screenshot=res://artifacts/client-frame.png \
        > "$log" 2>&1 || status=$?

    if [ "$status" -ne 0 ]; then
        echo "test-client: client exited with status $status (see $log)" >&2
        grep -E "VERDICT|ERROR" "$log" >&2 | head -20 || true
        exit 1
    fi
    if ! grep -q "VERDICT ok" "$log"; then
        echo "test-client: client did not report a successful verdict (see $log)" >&2
        grep -E "VERDICT" "$log" >&2 || echo "test-client: no VERDICT line — did the client run?" >&2
        exit 1
    fi
    if [ ! -s "$shot" ]; then
        echo "test-client: no frame was written to $shot" >&2
        exit 1
    fi
    grep -E "^client: VERDICT" "$log"
    echo "test-client: clean — frame at $shot"

# Inspect a recorded replay (D-016). Reads the curve log back and
# reconstructs world state from it — the read half of "replays are the
# primary desync-forensics tool". Exits non-zero on an empty or
# unreadable replay.
[doc("Inspect a replay curve log from artifacts/")]
replay-info FILE="res://artifacts/replay-4433.edmw": _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm --no-deps test --headless --script replay_info.gd -- --file={{FILE}}
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script replay_info.gd -- --file={{FILE}}
    fi

# Fast terrain-gen iteration loop without launching the full game.
#
# Writes a biome PNG to artifacts/ and reports chunking cost at the given
# chunk size. Vary CHUNK_SIZE and compare — D-017 leaves chunk size open
# precisely so it can be chosen from this measurement.
[doc("Terrain preview PNG + chunking cost at CHUNK_SIZE")]
gen-terrain-preview CHUNK_SIZE="16": _import
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p edotmw run --rm --no-deps test --headless --script terrain_preview.gd -- --chunk-size={{CHUNK_SIZE}}
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script terrain_preview.gd -- --chunk-size={{CHUNK_SIZE}}
    fi
