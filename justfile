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
# run-server, run-bots, test-unit, test-load, test-scenario, scenarios,
# gen-terrain-preview, replay-info.
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

# --- Multi-agent isolation (D-095) — HARD RULES ------------------------
# Several agents develop this repo in parallel, each in its own worktree,
# each launching its own server and clients. Everything that could let
# them touch each other's instances derives from ONE identity, computed
# by instance-id.sh (the single definition — nothing may re-derive it):
#
#   instance         from the git branch (agents: claude-<session>)
#   port             stable hash of instance into 20000-29999 (udp)
#   compose_project  edotmw-<instance>
#
# So `just down` here can only ever remove THIS worktree's containers,
# two agents' servers bind two different host ports, and a client shows
# which instance it belongs to in its title bar. The in-container port
# stays 4433 (compose maps it), so bots and the in-network client-test
# service are untouched.
#
# Breaking the isolation is an explicit, human-requested act only:
# EDOTMW_INSTANCE / EDOTMW_PORT override the derivation (see
# instance-id.sh). Never hardcode the shared project name or a literal
# host port back into a recipe — tests/test_multi_agent_isolation.gd
# fails if the old shared literals reappear.
instance := `bash instance-id.sh name`
port := `bash instance-id.sh port`
compose_project := "edotmw-" + instance
# docker-compose.yml publishes "${EDOTMW_HOST_PORT}:4433/udp". Exported
# here so every compose invocation below publishes THIS instance's port.
export EDOTMW_HOST_PORT := port
native_godot := tools_dir + "/godot"
blender_version := `cat .blender-version`
blender_venv := tools_dir + "/blender-venv"
# `python -m venv` lays out Scripts/ on Windows and bin/ everywhere else —
# both are reached through this same bash-shelled justfile (Git Bash on
# Windows per CLAUDE.md), so the venv's own layout must be branched on,
# not assumed.
blender_python := if os_family() == "windows" { blender_venv + "/Scripts/python.exe" } else { blender_venv + "/bin/python" }
blender_pip := if os_family() == "windows" { blender_venv + "/Scripts/pip.exe" } else { blender_venv + "/bin/pip" }

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

    # Skipped when nothing an import cares about has changed (D-098). It
    # is ~10 s and it ran on EVERY recipe, which was half the cost of a
    # filtered unit-test run.
    #
    # Handled with more care than a normal cache, because the failure mode
    # here is not slowness: verifying against a stale .godot cache gives a
    # confident WRONG answer, which this project has already paid for once
    # during M7's asset work. So:
    #
    #   - the stamp is taken BEFORE the import and written only on
    #     success, so a file edited while the import runs still looks
    #     newer than the stamp and forces another one;
    #   - the comparison covers everything Godot imports, not just .gd;
    #   - a skip is PRINTED, never silent;
    #   - EDOTMW_FORCE_IMPORT=1 overrides it.
    #
    # The stamp lives beside the import cache it describes, so the two
    # cannot be separated — `just nuke` removing one removes the other.
    cache_dir=".godot-container"
    [ "{{runtime}}" = "docker" ] || cache_dir=".godot"
    stamp="$cache_dir/.edotmw-import-stamp"
    if [ "${EDOTMW_FORCE_IMPORT:-0}" != "1" ] && [ -f "$stamp" ]; then
        changed="$(find . -newer "$stamp" \
            \( -name '*.gd' -o -name '*.tres' -o -name '*.tscn' \
               -o -name '*.gdshader' -o -name '*.gdshaderinc' \
               -o -name '*.glb' -o -name '*.exr' -o -name '*.png' \
               -o -name 'project.godot' \) \
            -not -path './.godot*' -not -path './tools/*' \
            -print -quit 2>/dev/null || true)"
        if [ -z "$changed" ]; then
            echo "import: skipped — nothing changed since $(date -r "$stamp" '+%H:%M:%S')"
            exit 0
        fi
    fi

    pending="$cache_dir/.edotmw-import-pending"
    mkdir -p "$cache_dir"
    : > "$pending"
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} run --rm --no-deps test --path . --import
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --path . --import
    fi
    # Only now, and dated to BEFORE the import started.
    mv "$pending" "$stamp"

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
        docker compose -p {{compose_project}} up -d --build server
        echo "up: instance {{instance}} — server published on udp {{port}} (host)"
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
        docker compose -p {{compose_project}} down --remove-orphans
        # `compose down` removes what `compose up` created. It does NOT
        # reliably remove a still-RUNNING one-off `compose run` container,
        # and `--remove-orphans` does not either — a client-test container
        # that hung at startup survived a full `just nuke` and was found
        # still running half an hour later. That is precisely the stray
        # container D-014 exists to prevent, so sweep by project label as
        # well. The label filter is scoped to THIS INSTANCE's compose
        # project (D-095), exact-match, so it can never touch anything
        # else — including another agent's edotmw-* project.
        strays="$(docker ps -aq --filter 'label=com.docker.compose.project={{compose_project}}' || true)"
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
        docker compose -p {{compose_project}} down --rmi all --volumes --remove-orphans || true
    fi
    rm -rf "{{tools_dir}}" "{{artifacts_dir}}" .godot .godot-container
    echo "nuked: repo is back to pure source"
    echo "note: tools/ (including just) is gone — run ./bootstrap.ps1 to set up again."

# This worktree's derived identity (D-095). Run it in ANOTHER worktree to
# learn the port to pass `run-client` when deliberately crossing instances.
[doc("Print this worktree's instance name, udp port, compose project")]
instance:
    @echo "instance:        {{instance}}"
    @echo "udp port (host): {{port}}"
    @echo "compose project: {{compose_project}}"

# Running containers (docker) or tracked native processes.
status:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} ps
    else
        if [ -f "{{artifacts_dir}}/server.pid" ]; then
            echo "server pid: $(cat {{artifacts_dir}}/server.pid)"
        else
            echo "no tracked native server process"
        fi
    fi

# Manual dev loop: run the server in the foreground.
# AI is how many computer opponents to seat (D-051). They take ordinary
# player slots, read the world through a client like you do, and are held
# to every rule you are.
# LOBBY=1 holds the server in the lobby (D-048): the world is NOT
# generated until the admin presses start, because its size, seed and
# shape are all still being chosen (D-049). The first human to connect is
# admin and adds AI seats there — a lobby of one cannot start a match.
[doc("Headless server. AI=N seats opponents, LOBBY=1 waits in the lobby")]
run-server AI="0" MAP="res://maps/default.tres" LOBBY="0": _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{server_scene}}" ]; then
        echo "NOT IMPLEMENTED UNTIL M1: {{server_scene}} doesn't exist yet." >&2
        exit 1
    fi
    if [ "{{runtime}}" = "docker" ]; then
        # Replaces the service's default command, so it has to restate it
        # in full. The image ENTRYPOINT already supplies --headless.
        # In-container the server still listens on 4433; compose maps it
        # to this instance's host port (D-095).
        echo "run-server: instance {{instance}} — reachable on udp {{port}} (host)"
        docker compose -p {{compose_project}} run --rm --service-ports server \
            --path . "{{server_scene}}" -- --ai={{AI}} --map={{MAP}} --lobby={{LOBBY}}
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --path . "{{server_scene}}" -- \
            --port={{port}} --ai={{AI}} --map={{MAP}} --lobby={{LOBBY}}
    fi

# Start a lobby server AND the GUI client, which is what "play a game"
# actually means (D-048). One recipe rather than two, because the two have
# to agree about the port and about lobby mode.
#
# Deliberately its OWN recipe instead of `run-server`'s LOBBY parameter.
# just takes arguments POSITIONALLY, so `just run-server LOBBY=1` silently
# parses "LOBBY=1" as the AI count, passes --ai=LOBBY=1, and int() reads
# that as 0 — no error, no lobby, a server that looks fine and is not in
# the mode you asked for. Exactly the silent-default class this project
# keeps getting bitten by.
#
# The world is NOT generated until the admin presses start (D-049): its
# size, seed and shape are all still being chosen, so there is genuinely
# nothing behind the lobby.
[doc("Play: lobby server + GUI client. You are admin; add AI seats, then Start")]
lobby PLAYERS="1":
    #!/usr/bin/env bash
    set -euo pipefail
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: the GUI client needs a native Godot (D-014)." >&2
        echo "      Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi

    # Whatever happens next, do not leave a server holding this
    # instance's port ({{port}} — D-095; other instances are untouched).
    trap '"{{just_executable()}}" down > /dev/null 2>&1 || true' EXIT INT TERM
    "{{just_executable()}}" down > /dev/null 2>&1 || true

    mkdir -p "{{artifacts_dir}}"
    log="{{artifacts_dir}}/lobby-server.log"
    "{{just_executable()}}" _import
    # Deliberately NOT --rm. Since D-075 the server exits by itself when
    # the last human disconnects, and --rm would delete the container the
    # moment it did — taking the log this recipe collects below with it.
    # The trap's `just down` still removes it, by project label.
    docker compose -p {{compose_project}} run --service-ports -d --name {{compose_project}}-lobby \
        server --path . "{{server_scene}}" -- \
        --lobby=1 --players={{PLAYERS}} > /dev/null

    # Wait for the port rather than sleeping a guessed number of seconds.
    for _i in $(seq 1 60); do
        if docker logs {{compose_project}}-lobby 2>&1 | grep -q "listening"; then break; fi
        sleep 1
    done
    if ! docker logs {{compose_project}}-lobby 2>&1 | grep -q "(lobby)"; then
        echo "FAIL: the server did not come up in LOBBY mode:" >&2
        docker logs {{compose_project}}-lobby 2>&1 | tail -20 >&2
        exit 1
    fi
    docker logs {{compose_project}}-lobby 2>&1 | grep "listening"

    echo "lobby: you are the admin. Add AI seats, pick civs, then press Start."
    "$godot" --headless --path . --import
    "$godot" --path . client.tscn -- --address=127.0.0.1 --port={{port}} --instance={{instance}}
    docker logs {{compose_project}}-lobby > "$log" 2>&1 || true

# Quick test match: you + 3 AI, no lobby to click through, every seat
# (yours included) drawn from CivRoster.resolve(RANDOM, ...) instead of the
# round-robin `run-server`/`lobby` default — so you don't know your own civ
# going in, same as an AI seat would draw. SEED reruns the same draw
# (civ_rng is seeded from it, same as everywhere else civs are randomised).
#
# Its own recipe rather than `run-server AI=3` flags typed by hand, for the
# same reason `lobby` is its own recipe: server and client have to agree on
# port and mode, and skipping the lobby means there is no admin screen to
# fall back on if you get that wrong.
#
# SANDBOX defaults to "auto": ON when this checkout is an agent worktree
# (instance claude-*), OFF for the human's own checkout. An agent going
# straight into quick launch is always dev-testing, so it gets the dev
# build — sandbox mode (D-077) with its cheats panel — without having to
# remember to ask for it. Pass SANDBOX=0/1 to override either way.
[doc("Quick test: you + 3 AI, all random civs, no lobby (agents get sandbox)")]
quick-test SEED="1337" SANDBOX="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    sandbox="{{SANDBOX}}"
    if [ "$sandbox" = "auto" ]; then
        case "{{instance}}" in
            claude-*) sandbox=1 ;;
            *)        sandbox=0 ;;
        esac
    fi
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: the GUI client needs a native Godot (D-014)." >&2
        echo "      Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi

    # Whatever happens next, do not leave a server holding this
    # instance's port ({{port}} — D-095; other instances are untouched).
    trap '"{{just_executable()}}" down > /dev/null 2>&1 || true' EXIT INT TERM
    "{{just_executable()}}" down > /dev/null 2>&1 || true

    mkdir -p "{{artifacts_dir}}"
    log="{{artifacts_dir}}/quick-test-server.log"
    "{{just_executable()}}" _import
    # Not --rm, for the same reason as `lobby`: the server now exits on the
    # last human disconnect (D-075) and would take its own log with it.
    docker compose -p {{compose_project}} run --service-ports -d --name {{compose_project}}-quick-test \
        server --path . "{{server_scene}}" -- \
        --ai=3 --players=1 --lobby=0 --seed={{SEED}} --random-civs=1 \
        --sandbox=$sandbox > /dev/null

    # Wait for the port rather than sleeping a guessed number of seconds.
    for _i in $(seq 1 60); do
        if docker logs {{compose_project}}-quick-test 2>&1 | grep -q "listening"; then break; fi
        sleep 1
    done
    if ! docker logs {{compose_project}}-quick-test 2>&1 | grep -q "listening"; then
        echo "FAIL: the server did not come up:" >&2
        docker logs {{compose_project}}-quick-test 2>&1 | tail -20 >&2
        exit 1
    fi
    docker logs {{compose_project}}-quick-test 2>&1 | grep -E "listening|AI seated"

    "$godot" --headless --path . --import
    "$godot" --path . client.tscn -- --address=127.0.0.1 --port={{port}} --instance={{instance}}
    docker logs {{compose_project}}-quick-test > "$log" 2>&1 || true

# Manual dev loop: run a client. Always native — needs a GPU (D-014), so
# this recipe ignores EDOTMW_RUNTIME and refuses to pretend otherwise.
#
# ADDRESS defaults to localhost; pass the server's host when connecting to
# one running elsewhere. Controls: WASD pans, wheel zooms, Q/E and
# Ctrl+wheel turn the view (D-063), ESC opens the game menu, right-click
# orders every owned squad to the clicked cell.
#
# PORT defaults to THIS instance's derived port (D-095), so `just
# run-client` from a worktree connects to that worktree's server and no
# other. To look at a different instance's server, pass its port
# explicitly (`just instance` in that worktree prints it).
[doc("Run the GUI client natively (WASD pan, wheel zoom, right-click order)")]
run-client ADDRESS="127.0.0.1" PORT=port:
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
    "$godot" --path . client.tscn -- --address={{ADDRESS}} --port={{PORT}} --instance={{instance}}

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
        # In-network: the bots reach this project's server as "server:4433",
        # so no host port is involved (D-095).
        docker compose -p {{compose_project}} run --rm --no-deps bots --headless --script bot_client.gd -- --clients={{N}} --duration={{DURATION}}
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script bot_client.gd -- --clients={{N}} --duration={{DURATION}} --port={{port}}
    fi

# GUT unit tests, headless. Imports the project first so global
# class_names (UnitDef, PrimitiveUnit, GUT's own classes) are registered
# — Godot's headless import cache is required before gut_cmdln.gd can
# resolve them, and is otherwise a confusing first-run failure.
#
# FILTER selects test FILES by substring, TEST selects one test by name
# (D-098) — the full suite is minutes, and iterating on one behaviour
# should not cost that.
[doc("Run the GUT suite headless. FILTER selects files, TEST selects one test")]
test-unit FILTER="" TEST="": _import
    #!/usr/bin/env bash
    set -euo pipefail
    args=(-s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit)
    [ -n "{{FILTER}}" ] && args+=("-gselect={{FILTER}}")
    [ -n "{{TEST}}" ] && args+=("-gunit_test_name={{TEST}}")
    if [ "{{runtime}}" = "docker" ]; then
        # The service's default command is the unfiltered run; passing
        # args replaces it, so they are restated in full.
        docker compose -p {{compose_project}} run --rm --no-deps test "${args[@]}"
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless "${args[@]}"
    fi

# Full load test: server + N bots for DURATION seconds, then check the
# result several independent ways. Teardown runs via trap on success,
# failure, AND Ctrl-C — an interrupted load test must not leave
# containers running (D-014).
#
# Why not just the log scan: the log scan alone once reported "clean" for
# a run in which every bot had exited non-zero, because the bots' failure
# message said ERROR and the scan only looked for warning/desync.
# Grepping for the absence of bad news cannot distinguish "nothing went
# wrong" from "nothing happened". So:
#
#   1. bots' exit status         — did the run itself succeed?
#   2. explicit VERDICT line     — did every bot connect, replicate,
#                                  verify its state against the server's,
#                                  AND (M2) actually observe a casualty, a
#                                  conceal, and a reveal (D-026 criterion 9)?
#   3. fog-gating comparison     — did the bots collectively know FEWER
#                                  squads than the server actually
#                                  simulated (D-026 criterion 6's load half)?
#   4. diagnostic log scan       — did anything complain along the way?
#
# Check 2 is the one that makes this a test rather than a smoke run: a bot
# that connects and receives nothing would otherwise pass 1 and 4. M1's
# equivalent required state-hash checks to actually RUN, not merely that
# none failed — M2 extends the same principle: a run in which nobody ever
# died, or nothing was ever hidden and re-shown, proves nothing about
# combat or fog, however clean the rest looks. Both new bot-side
# conditions (casualties/conceal/reveal) live inside bot_client.gd's own
# _verdict_ok(), so check 1/2 already fail on them; check 3 is the one
# condition bot_client.gd cannot check itself, because a client never
# learns the server's TOTAL squad count, only what it can see.
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
        docker compose -p {{compose_project}} stop server >/dev/null 2>&1 || true
        docker compose -p {{compose_project}} logs server > "$server_log" 2>&1 || true
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

    # D-026 criterion 6's load half: fog must be shown gating a REAL
    # multi-client run, not a test fixture — even the single MOST-INFORMED
    # bot must know FEWER squads than the server actually simulated. This
    # is deliberately per-bot, not a sum/union across every bot: every
    # squad belongs to exactly one connected player, and an owner always
    # sees its own squads regardless of vision, so a union across ALL bots
    # would equal the server's total on every run whether fog gates
    # anything or not — see bot_client.gd's _max_known_squads() for why.
    # Compared via two distinct, structured key=value markers (never a
    # substring of unrelated prose, per the rule below) rather than
    # inferred from prose. Absence of either marker is itself a failure —
    # a check that silently skips because it found nothing to compare is
    # exactly the "passes vacuously" shape D-022's audit was written
    # against.
    known_squads_max="$(grep -oE 'known_squads_max=[0-9]+' "$bots_log" | tail -1 | cut -d= -f2)"
    total_squads="$(grep -oE 'FOG_TOTAL_SQUADS=[0-9]+' "$server_log" | tail -1 | cut -d= -f2)"
    if [ -z "${known_squads_max:-}" ] || [ -z "${total_squads:-}" ]; then
        echo "test-load: could not find known_squads_max (bots log) or FOG_TOTAL_SQUADS (server log) — can't check fog gating" >&2
        exit 1
    fi
    if [ "$known_squads_max" -ge "$total_squads" ]; then
        echo "test-load: fog did not gate anything at load — the most-informed bot knew $known_squads_max of $total_squads simulated squads (expected fewer)" >&2
        exit 1
    fi
    echo "test-load: fog gated at least $((total_squads - known_squads_max)) of $total_squads simulated squads even from the most-informed bot (known_squads_max=$known_squads_max)"

    # The same check for RESOURCE POSITIONS (D-061). Every node on the map
    # used to be sent to every client at join, so a player knew where each
    # opponent had to expand and where to raid without scouting for any of
    # it — and a modified client could read it straight out of the packet.
    #
    # Checked here rather than only in a unit test for the reason the
    # squad gate is: a per-client filter can be correct in isolation and
    # still be bypassed by some other send path, and only a live run with
    # real clients exercises all of them.
    nodes_known_max="$(grep -oE 'nodes_known_max=[0-9]+' "$bots_log" | tail -1 | cut -d= -f2)"
    total_nodes="$(grep -oE 'FOG_TOTAL_NODES=[0-9]+' "$server_log" | tail -1 | cut -d= -f2)"
    if [ -z "${nodes_known_max:-}" ] || [ -z "${total_nodes:-}" ]; then
        echo "test-load: could not find nodes_known_max or FOG_TOTAL_NODES — can't check resource gating" >&2
        exit 1
    fi
    if [ "$nodes_known_max" -ge "$total_nodes" ]; then
        echo "test-load: resource positions are NOT gated — the most-informed bot knew $nodes_known_max of $total_nodes nodes (expected fewer)" >&2
        exit 1
    fi
    echo "test-load: fog gated $((total_nodes - nodes_known_max)) of $total_nodes resource nodes from the most-informed bot (nodes_known_max=$nodes_known_max)"

    # Both civilisations must actually have fielded something (D-046
    # criterion 10). A run where everyone happened to draw the same civ
    # exercises half the roster and proves nothing about the other half —
    # and it would pass every other check in this recipe, which is exactly
    # the vacuous-pass shape D-022's audit exists to catch.
    civs_fielded="$(grep -oE 'CIVS_FIELDED [0-9]+ of [0-9]+' "$server_log" | tail -1 | awk '{print $2}')"
    civs_total="$(grep -oE 'CIVS_FIELDED [0-9]+ of [0-9]+' "$server_log" | tail -1 | awk '{print $4}')"
    if [ -z "${civs_fielded:-}" ]; then
        echo "test-load: no CIVS_FIELDED marker in the server log — can't check both civs played" >&2
        exit 1
    fi
    if [ "$civs_fielded" -lt 2 ]; then
        echo "test-load: only $civs_fielded of $civs_total civilisations ever fielded a squad — the match exercised one roster (D-046 criterion 10)" >&2
        exit 1
    fi
    echo "test-load: $civs_fielded of $civs_total civilisations fielded squads"

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
    # us/squad is meaningless without its squad count (CLAUDE.md) — the
    # server's own summary line carries both, plus vision/combat as
    # identifiable components (D-026 criterion 10), so surface it here
    # rather than making a human dig through server_log for it.
    grep -E "server: final" "$server_log" || true

# The fast integration loop: a REAL server and REAL bots, but starting
# mid-match from a scenario instead of playing the opening (D-098).
#
# `test-load` needs ~120 s and that is not waste — a town hall takes 40 s
# and consumes the founding party (D-031), production runs after it, and
# spawns are scattered far apart (D-039). None of that is under test when
# you are working on combat, fog, buildings or the wire, and paying two
# minutes for it every iteration is what makes people stop running it.
#
# This is NOT a replacement for `test-load`, and must never become one. A
# scenario hands out finished buildings and adjacent armies, so it cannot
# see a bug in founding, in production, or in spawn placement — the very
# things it skips. `just test-load 4 120` stays the gate a change passes
# before it is called done; this is the loop you iterate in.
#
# The checks follow test-load's shape, plus one this recipe needs and
# test-load does not: the server must confirm IN ITS LOG that it actually
# played the scenario. A --scenario typo, or a stray server without the
# flag, would otherwise produce a fast, clean, entirely ordinary run — a
# pass that means nothing, which is the exact shape D-022's audit exists
# to catch.
[doc("Fast integration loop: server + bots from a mid-game scenario (~31s at DURATION=15)")]
test-scenario SCENARIO="siege" N="4" DURATION="30":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    trap '"{{just_executable()}}" down > /dev/null 2>&1 || true' EXIT INT TERM
    "{{just_executable()}}" _import

    bots_log="{{artifacts_dir}}/test-scenario-bots.log"
    server_log="{{artifacts_dir}}/test-scenario-server.log"

    # Through `up`, not a bare `compose run`: `run` does not give the
    # container the `server` network alias, so the bots — which resolve
    # `server:4433` and always have — connected to nothing and reported a
    # clean 0/4. The scenario travels as an environment variable for
    # exactly that reason.
    export EDOTMW_SCENARIO="{{SCENARIO}}"
    "{{just_executable()}}" up

    bots_status=0
    "{{just_executable()}}" run-bots {{N}} {{DURATION}} > "$bots_log" 2>&1 || bots_status=$?

    docker compose -p {{compose_project}} stop server >/dev/null 2>&1 || true
    docker compose -p {{compose_project}} logs server > "$server_log" 2>&1 || true

    # 1. Did the server actually play the scenario? Structured marker, not
    #    prose — the standing rule after a log grep for a word no code
    #    path printed passed vacuously for a whole milestone.
    if ! grep -q "SCENARIO id={{SCENARIO}} " "$server_log"; then
        echo "test-scenario: the server never reported playing scenario '{{SCENARIO}}'" >&2
        echo "               (no 'SCENARIO id={{SCENARIO}}' marker in $server_log)" >&2
        grep -E "SCENARIO|listening" "$server_log" >&2 | head -5 || true
        exit 1
    fi

    # 2. Did placement quietly drop anything? A scenario that failed to
    #    place half an army would otherwise read as a simulation losing it.
    if grep -q "SCENARIO_SKIPPED" "$server_log"; then
        echo "test-scenario: the scenario could not place everything it describes:" >&2
        grep "SCENARIO_SKIPPED" "$server_log" >&2 | head -10
        exit 1
    fi

    # 3. The bots' own verdict, exactly as test-load treats it.
    if [ "$bots_status" -ne 0 ]; then
        echo "test-scenario: bots exited with status $bots_status (see $bots_log)" >&2
        grep -E "VERDICT" "$bots_log" >&2 | tail -2 || true
        exit 1
    fi
    if ! grep -q "VERDICT ok" "$bots_log"; then
        echo "test-scenario: bots did not report a successful verdict (see $bots_log)" >&2
        grep -E "VERDICT" "$bots_log" >&2 || echo "test-scenario: no VERDICT line at all" >&2
        exit 1
    fi

    # 4. Engine diagnostics, by line PREFIX rather than by scary word.
    if grep -Eq '(^|\| *)(ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING):' \
            "$bots_log" "$server_log"; then
        echo "test-scenario: engine errors or warnings found" >&2
        grep -EIn '(^|\| *)(ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING):' \
            "$bots_log" "$server_log" >&2 | head -20
        exit 1
    fi

    echo "test-scenario: clean — scenario '{{SCENARIO}}', {{N}} bots, {{DURATION}}s"
    grep -E "server: SCENARIO id=" "$server_log"
    grep -E "VERDICT" "$bots_log"
    grep -E "server: final" "$server_log" || true

# Every shipped scenario and what it is for (D-098).
[doc("List the mid-game scenarios test-scenario and --scenario can name")]
scenarios: _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} run --rm --no-deps test \
            --headless --script scenario_list.gd
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script scenario_list.gd
    fi

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
# M2: a lone client with no opponent cannot exercise combat or fog at all
# — every squad stays at full strength and ghosts=0 no matter how correct
# the rendering is, which would verify M1's rendering again and say
# nothing about M2 (see game_design_decisions.md D-026 criterion 11). So
# BOTS virtual load-test bots come up alongside the client as a second
# player, and the client itself runs a scripted rally/withdraw/re-rally
# (client.gd's _drive_m2_scenario, capture-mode only — it never runs
# during `just run-client`) toward that neighbour's estimated spawn, for
# the same reason bot_client.gd scripts its own bot-vs-bot contact: leaving
# it to chance would make the verdict conditions below flaky rather than a
# real check.
#
# Checks, in the same shape as test-load: the client's exit status, an
# explicit VERDICT line, that the frame contains more than one flat colour
# (a scene that rendered nothing still writes a perfectly valid PNG), AND
# — mirroring test-load's combat/fog conditions — that this run's client
# actually observed a casualty, a conceal, AND a reveal, not merely that it
# didn't complain (D-022's standing rule).
[doc("Render the GUI client headlessly with bots as a second player and verify the frame (software GPU)")]
test-client SECONDS="60" BOTS="3": _import
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
    bots_log="{{artifacts_dir}}/test-client-bots.log"
    rm -f "$shot"
    trap '"{{just_executable()}}" down' EXIT INT TERM
    "{{just_executable()}}" up

    # Bots run for a little longer than the client so they don't vanish out
    # from under it right before the screenshot is taken. Backgrounded (not
    # `--rm`-raced against the client): its own container is still labelled
    # for this compose project, so `just down`'s stray sweep (D-014) cleans
    # it up even if it somehow outlives this recipe.
    docker compose -p {{compose_project}} run --rm --no-deps bots --headless --script bot_client.gd \
        -- --clients={{BOTS}} --duration=$(({{SECONDS}} + 10)) \
        > "$bots_log" 2>&1 &
    bots_pid=$!

    # gl_compatibility, not the Forward+ default: the image ships Mesa's
    # software OpenGL rasteriser (llvmpipe), not a software Vulkan one, so
    # Forward+ hangs at startup with no diagnostic whatsoever.
    # Dummy audio because the container has no sound card and ALSA's
    # failure is a dozen lines of noise in the log.
    status=0
    docker compose -p {{compose_project}} run --rm --no-deps client-test \
        --path . client.tscn \
        --rendering-method gl_compatibility \
        --audio-driver Dummy \
        --resolution 1280x720 \
        -- --address=server --run-seconds={{SECONDS}} \
        --screenshot=res://artifacts/client-frame.png \
        > "$log" 2>&1 || status=$?

    # Best-effort: the bots' OWN verdict (bot_client.gd's _verdict_ok())
    # judges itself against ITS OWN teammates, which with a single bot and
    # no other bot to rally toward is not the thing this recipe is
    # checking — the CLIENT's observations, asserted below, are. So the
    # bots' exit status is not a pass/fail gate here, only diagnostic
    # context kept in its own log.
    wait "$bots_pid" || true

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

    # Structured key=value markers (per the standing "scary words vs
    # structured markers" rule — test-load's own known_squads_max/
    # FOG_TOTAL_SQUADS check follows the same shape), not an inference from
    # prose. Absence of any of these, or a zero value, means M2 was not
    # actually exercised by this run even if everything else looks clean.
    casualties="$(grep -oE 'casualties_applied=[0-9]+' "$log" | tail -1 | cut -d= -f2)"
    conceals="$(grep -oE 'conceal_events=[0-9]+' "$log" | tail -1 | cut -d= -f2)"
    reveals="$(grep -oE 'reveal_events=[0-9]+' "$log" | tail -1 | cut -d= -f2)"
    if [ -z "${casualties:-}" ] || [ "$casualties" -le 0 ]; then
        echo "test-client: no casualties observed (casualties_applied=${casualties:-<missing>}) — M2 combat did not happen this run" >&2
        exit 1
    fi
    if [ -z "${conceals:-}" ] || [ "$conceals" -le 0 ]; then
        echo "test-client: no conceal events observed (conceal_events=${conceals:-<missing>}) — fog never hid anything from this client" >&2
        exit 1
    fi
    # Reveals are REPORTED here, not gated — the same call client.gd's
    # own verdict makes, and for the same reason. A reveal needs an
    # opponent to wander back into vision inside a bounded capture run,
    # which on the 128x64 map is luck: consecutive runs produced 3 and
    # then 0 with nothing else changed. A gate that fails good runs gets
    # muted, which is precisely the failure this file already records
    # from the "0 desyncs" scan.
    #
    # The property stays gated where it is reliable: `test-load` runs four
    # mutually-converging armies and sees reveals in the tens every run.
    if [ -z "${reveals:-}" ]; then
        echo "test-client: reveal_events missing from the verdict line — did the client report at all?" >&2
        exit 1
    fi

    grep -E "^client: VERDICT" "$log"
    echo "test-client: clean — frame at $shot (casualties_applied=$casualties conceal_events=$conceals reveal_events=$reveals)"

# Inspect a recorded replay (D-016). Reads the curve log back and
# reconstructs world state from it — the read half of "replays are the
# primary desync-forensics tool". Exits non-zero on an empty or
# unreadable replay.
[doc("Inspect a replay curve log from artifacts/")]
replay-info FILE="res://artifacts/replay-4433.edmw": _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} run --rm --no-deps test --headless --script replay_info.gd -- --file={{FILE}}
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
        docker compose -p {{compose_project}} run --rm --no-deps test --headless --script terrain_preview.gd -- --chunk-size={{CHUNK_SIZE}}
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script terrain_preview.gd -- --chunk-size={{CHUNK_SIZE}}
    fi

# Build every model and texture from art/ (D-064).
#
# Runs Blender HEADLESS AS A LIBRARY (`bpy`, a PyPI wheel) — no GUI, no
# GPU, no system Blender install. The generators under art/ are the source
# of truth; generated/ is a build product that is nonetheless committed, so
# a fresh clone plays without any of this.
#
# The `--import` at the end is not optional and not tidiness. Godot serves
# assets from its import cache, so a rebuilt .glb or .exr is INVISIBLE to
# the engine until it re-imports — verifying a fresh bake against a stale
# cache produced a confident wrong answer for several rounds during M7.
[doc("Rebuild models/textures from art/ (needs the bpy venv; see bootstrap-art)")]
build-assets ONLY="": 
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -x "{{blender_python}}" ]; then
        echo "FAIL: no bpy environment at {{blender_venv}}"
        echo "Run: {{just_executable()}} bootstrap-art"
        exit 1
    fi
    args=""
    [ -n "{{ONLY}}" ] && args="--only={{ONLY}}"
    "{{blender_python}}" art/build.py $args
    # QUOTED, unlike every other `{{just_executable()}}` call in this file,
    # because this one is reached on Windows where the path is absolute and
    # backslash-separated: unquoted, the shell eats the separators and the
    # line dies as `C:UsersdmasoDocuments...toolsjust.exe: command not
    # found`. The build itself had already succeeded, so the only casualty
    # was the import — which is the step CLAUDE.md warns about, since a
    # rebuild Godot has not re-imported is invisible and gives confident
    # wrong answers about a mesh that did change.
    "{{just_executable()}}" _import

# Rebuild the resource-node markers (D-028's food/wood/gold/stone props)
# from the hand-authored source under art/resources/source/.
#
# UNLIKE build-assets, this needs no bpy: the source is already a glTF
# binary and Godot's own GLTFDocument can read and write that format, so
# this runs on the plain headless image. It is a deliberate exception to
# the parametric art/ pipeline (CLAUDE.md: "any forced binary-only or
# GUI-only step ... should be flagged explicitly as an exception"), not a
# second generator pattern to imitate — see art/resources/split_markers.gd's
# header for why merging into one mesh per kind matters, not just splitting.
[doc("Rebuild resource-node marker models from art/resources/source/")]
build-resource-models:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} run --rm --no-deps test \
            --path . --script res://art/resources/split_markers.gd
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --path . --script res://art/resources/split_markers.gd
    fi
    {{just_executable()}} _import

# Fetch the pinned bpy into a gitignored venv under tools/.
#
# Separate from `bootstrap` because it is ~1 GB and only asset work needs
# it: everything else in this project, including running and testing the
# game, works from the committed generated/ output.
[doc("Install the pinned bpy for asset builds")]
bootstrap-art:
    #!/usr/bin/env bash
    set -euo pipefail
    python3 -m venv "{{blender_venv}}"
    # `python -m pip` rather than the pip.exe shim: pip cannot overwrite its
    # own running executable on Windows and exits 1 telling you to do this.
    "{{blender_python}}" -m pip install --quiet --upgrade pip
    "{{blender_pip}}" install "bpy=={{blender_version}}"
    # Godot scans every directory under the project. Without this it walks
    # ~1 GB of Blender's own bundled textures and imports them.
    : > "{{tools_dir}}/.gdignore"
    "{{blender_python}}" -c "import bpy; print('bpy', bpy.app.version_string)"

# Contact sheet of every authored model, animated, on real terrain (D-063).
#
# Software-rasterised, so unlike `bench-render` this needs no GPU and runs
# anywhere. It answers "is the picture right", never "how fast" — and the
# PNG is meant to be LOOKED AT, which is a rule this project has paid for
# twice: M1's first client frame contained no soldiers and M6's contained
# no terrain, both while every number reported healthy.
#
# Renders TWICE at different times and fails if the two are identical:
# animation is driven from TIME in the shader (D-065), so a frozen VAT
# would otherwise produce a perfectly plausible still.
[doc("Render every model, animated, to artifacts/models-godot.png")]
gen-model-preview SECONDS="1.2": _import
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: gen-model-preview needs the portable Godot in tools/"
        echo "Run: {{just_executable()}} bootstrap"
        exit 1
    fi
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
    run() {
        if command -v xvfb-run >/dev/null 2>&1; then
            xvfb-run -a -s "-screen 0 1400x900x24" "$godot" --path . \
                --rendering-method gl_compatibility --resolution 1400x900 \
                model_preview.tscn -- --seconds="$1" --out="$2"
        else
            "$godot" --path . --rendering-method gl_compatibility \
                --resolution 1400x900 model_preview.tscn -- --seconds="$1" --out="$2"
        fi
    }
    run "{{SECONDS}}" "res://artifacts/models-godot.png"
    run "$(echo "{{SECONDS}} + 1.7" | bc)" "res://artifacts/models-godot-b.png"
    if cmp -s "{{artifacts_dir}}/models-godot.png" "{{artifacts_dir}}/models-godot-b.png"; then
        echo "VERDICT: FAIL - two renders 1.7s apart are byte-identical;"
        echo "         the vertex animation texture is not advancing (D-065)."
        exit 1
    fi
    rm -f "{{artifacts_dir}}/models-godot-b.png"
    echo "VERDICT: ok - models rendered and animating; LOOK AT artifacts/models-godot.png"

# Ground cover on real terrain, with real soldiers standing in it (D-100).
#
# The same idea as gen-model-preview and for the same reason — every check
# in tests/test_ground_cover.gd counts things, and none of them can see a
# fern lit from the inside or grass that vanishes into the ground colour.
# Software-rasterised, so no GPU: this answers "is the picture right", and
# `bench-render` answers "how fast".
#
# The verdict gates on the two failures a screenshot of bare ground would
# otherwise hide: nothing drawn at all, and a model the palettes can name
# that never made it onto the map.
[doc("Render ground cover to artifacts/cover-godot.png")]
gen-cover-preview SECONDS="0.6": _import
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: gen-cover-preview needs the portable Godot in tools/"
        echo "Run: {{just_executable()}} bootstrap"
        exit 1
    fi
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
    log="{{artifacts_dir}}/cover-preview.log"
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a -s "-screen 0 1400x900x24" "$godot" --path . \
            --rendering-method gl_compatibility --resolution 1400x900 \
            cover_preview.tscn -- --seconds="{{SECONDS}}" \
            --out="res://artifacts/cover-godot.png" | tee "$log"
    else
        "$godot" --path . --rendering-method gl_compatibility \
            --resolution 1400x900 cover_preview.tscn -- --seconds="{{SECONDS}}" \
            --out="res://artifacts/cover-godot.png" | tee "$log"
    fi
    if [ ! -s "{{artifacts_dir}}/cover-godot.png" ]; then
        echo "VERDICT: FAIL - no PNG was written"
        exit 1
    fi
    summary="$(grep -o 'cells dressed of [0-9]*, [0-9]* instances, [0-9]*/[0-9]* models drawn' "$log" | head -n 1)"
    if [ -z "$summary" ]; then
        echo "VERDICT: FAIL - the preview never reported what it drew"
        exit 1
    fi
    drawn="$(echo "$summary" | sed 's/.* \([0-9]*\)\/[0-9]* models drawn/\1/')"
    known="$(echo "$summary" | sed 's/.*\/\([0-9]*\) models drawn/\1/')"
    instances="$(echo "$summary" | sed 's/.*, \([0-9]*\) instances.*/\1/')"
    if [ "$instances" -lt 100 ]; then
        echo "VERDICT: FAIL - only $instances prop instances; the ground is bare"
        exit 1
    fi
    if [ "$drawn" != "$known" ]; then
        echo "VERDICT: FAIL - $drawn of $known prop models reached the picture;"
        echo "         a palette names a model that did not load (run build-assets)."
        exit 1
    fi
    echo "VERDICT: ok - $summary; LOOK AT artifacts/cover-godot.png"

# A rendered picture of a WOOD, framed on the densest one on the patch.
#
# The same idea as gen-cover-preview and bought the same way: forests read
# as ranks and files for a whole milestone with every number healthy,
# because trees stood one per cell at the exact cell centre. Nothing that
# counts things can see a lattice. Neither could either instrument that
# existed — gen-terrain-preview's PNG is top-down and has no trees in it,
# and test-client aims its camera at a spawn, which is open ground by
# construction and so the one place a wood is least likely to be.
#
# Software-rasterised, so no GPU: this answers "is the picture right", and
# `bench-render` answers "how fast".
#
# The verdict gates on the failures a screenshot of an empty meadow would
# otherwise hide: no trees drawn at all, and a stand that is still one tree
# per node cell.
[doc("Render a wood to artifacts/forest-godot.png")]
gen-forest-preview SECONDS="0.6": _import
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: gen-forest-preview needs the portable Godot in tools/"
        echo "Run: {{just_executable()}} bootstrap"
        exit 1
    fi
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
    log="{{artifacts_dir}}/forest-preview.log"
    out="{{artifacts_dir}}/forest-godot.png"
    rm -f "$out"
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a -s "-screen 0 1400x900x24" "$godot" --path . \
            --rendering-method gl_compatibility --resolution 1400x900 \
            forest_preview.tscn -- --seconds="{{SECONDS}}" \
            --out="res://artifacts/forest-godot.png" | tee "$log"
    else
        "$godot" --path . --rendering-method gl_compatibility \
            --resolution 1400x900 forest_preview.tscn -- --seconds="{{SECONDS}}" \
            --out="res://artifacts/forest-godot.png" | tee "$log"
    fi
    if [ ! -s "$out" ]; then
        echo "VERDICT: FAIL - no PNG was written"
        exit 1
    fi
    summary="$(grep -o '[0-9]* trees ([0-9.]* per node), [0-9]* instances in [0-9]* multimeshes, [0-9]* models' "$log" | head -n 1)"
    if [ -z "$summary" ]; then
        echo "VERDICT: FAIL - the preview never reported what it drew"
        exit 1
    fi
    trees="$(echo "$summary" | sed 's/\([0-9]*\) trees.*/\1/')"
    per_node="$(echo "$summary" | sed 's/.*(\([0-9.]*\) per node).*/\1/')"
    if [ "$trees" -lt 100 ]; then
        echo "VERDICT: FAIL - only $trees trees; the map has no wood on it"
        exit 1
    fi
    # One tree per node cell IS the defect: placement at hex resolution,
    # which no amount of jitter or scaling hides.
    if awk -v n="$per_node" 'BEGIN { exit !(n < 1.5) }'; then
        echo "VERDICT: FAIL - $per_node trees per node cell; a stand is one tree again"
        exit 1
    fi
    echo "VERDICT: ok - $summary; LOOK AT artifacts/forest-godot.png"

# A rendered picture of the GROUND, in the shipping lighting rig (D-096/D-097).
#
# `gen-terrain-preview` prints healthy numbers and a top-down biome PNG, and
# both stayed healthy for two milestones while the ground read as a honeycomb
# of flat hexes with no cliff visible anywhere. `test-client` renders the real
# thing but points its camera at a spawn, which is walkable ground by
# construction and therefore the one place a cliff cannot be. This frames the
# terrain on purpose: it finds the longest stretch of passability boundary on
# the map and looks at it from a shallow angle.
#
# Software-rasterised like `gen-model-preview`, so it needs no GPU and says
# nothing about speed — `bench-render` is the recipe for that.
#
# LOOK AT the PNG. That is the entire point of the recipe.
[doc("Render the terrain, framed on a cliff, to artifacts/terrain-3d.png")]
gen-terrain-shot HEIGHT="14": _import
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: gen-terrain-shot needs the portable Godot in tools/"
        echo "Run: {{just_executable()}} bootstrap"
        exit 1
    fi
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
    out="{{artifacts_dir}}/terrain-3d.png"
    rm -f "$out"
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a -s "-screen 0 1400x900x24" "$godot" --path . \
            --rendering-method gl_compatibility --resolution 1400x900 \
            terrain_shot.tscn -- --height={{HEIGHT}}
    else
        "$godot" --path . --rendering-method gl_compatibility \
            --resolution 1400x900 terrain_shot.tscn -- --height={{HEIGHT}}
    fi
    if [ ! -s "$out" ]; then
        echo "gen-terrain-shot: no frame was written to $out" >&2
        exit 1
    fi

# M4's tiered scale sweep (D-027 criterion 17's successor, D-012, D-020).
#
# Drives the simulation directly at 100/250/500/1000 squads rather than
# playing a match, because squad count in a real game is whatever
# production produces and D-018 targets ~1,000. Prints CSV: the SHAPE of
# the curve is the deliverable, not the endpoint — cost should stay flat
# per squad, and a bend means something is accidentally quadratic.
[doc("Scale sweep: simulation cost at 100/250/500/1000 squads")]
profile: _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} run --rm --no-deps test --headless --script profile_sweep.gd
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script profile_sweep.gd
    fi

# Client render benchmark (D-044 criteria 1-3, closing Q15's trigger).
#
# NATIVE ONLY, and for the same reason `run-client` is (D-014): this needs
# a GPU. `just test-client` renders through Mesa's software rasteriser in
# docker, which is the right tool for "is the picture correct" and useless
# for "how fast is it" — it measures the CPU, not the hardware anyone will
# play on.
#
# Prints the video adapter it ran on. A frame time with no hardware
# attached is not a number anyone can use, the same way CLAUDE.md forbids
# quoting us/squad without a squad count.
#
# Like `run-client`, this cannot use the shared `_import` dependency:
# `_import` follows EDOTMW_RUNTIME (docker by default) and populates
# .godot-container, while anything native reads .godot. Without a native
# import, global class_names do not resolve and it dies with parse errors
# naming unrelated lines.
[doc("Render benchmark: frame time and draw calls at 0/100/250/500/1000 squads")]
bench-render COUNTS="0,100,250,500,1000" FRAMES="120" HEIGHT="40":
    #!/usr/bin/env bash
    set -euo pipefail
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: the render benchmark needs a native Godot with a GPU (D-014)." >&2
        echo "      Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi
    "$godot" --headless --path . --import
    "$godot" --path . bench_render.tscn -- --counts={{COUNTS}} --frames={{FRAMES}} --height={{HEIGHT}}

# Screenshot the LOBBY (D-048), so its layout can actually be looked at.
#
# Separate from `test-client` because it wants the opposite setup: a
# server that STAYS in the lobby (`--lobby=1`, so it waits for an admin
# who never presses start) and a client that renders the seat list rather
# than a battlefield. Docker only, same software-GL reasoning as
# test-client.
[doc("Screenshot the lobby screen into artifacts/lobby.png")]
lobby-shot SECONDS="8" AI="2" PRESET="0": _import
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{runtime}}" != "docker" ]; then
        echo "lobby-shot requires the docker runtime (it needs the software-GL image)." >&2
        exit 1
    fi
    mkdir -p "{{artifacts_dir}}"
    shot="{{artifacts_dir}}/lobby.png"
    log="{{artifacts_dir}}/lobby-shot.log"
    rm -f "$shot"
    trap '"{{just_executable()}}" down' EXIT INT TERM

    docker compose -p {{compose_project}} run --rm --no-deps -d --name {{compose_project}}-lobby-server \
        server --headless --path . server.tscn -- --lobby=1 --players=8 > /dev/null
    sleep 3

    status=0
    timeout 180 docker compose -p {{compose_project}} run --rm --no-deps client-test \
        --path . client.tscn \
        --rendering-method gl_compatibility \
        --audio-driver Dummy \
        --resolution 1280x720 \
        -- --address={{compose_project}}-lobby-server --run-seconds={{SECONDS}} \
        --lobby-ai={{AI}} \
        --lobby-preset-steps={{PRESET}} \
        --screenshot=res://artifacts/lobby.png \
        > "$log" 2>&1 || status=$?

    docker rm -f {{compose_project}}-lobby-server > /dev/null 2>&1 || true
    if [ ! -f "$shot" ]; then
        echo "lobby-shot: no screenshot written (see $log)" >&2
        exit 1
    fi
    echo "lobby-shot: wrote $shot"

# AI ladder (D-054): headless AI-vs-AI matches, to make "smarter" a
# measurement rather than an opinion.
#
# Runs the REAL server rather than a re-implementation of it. M4 paid for
# that lesson twice: a harness is a workload, and a workload has blind
# spots — `just profile` reported a healthy 29 ms for code that spent
# 866 ms in a live server, because the harness resolved its UnitDefs once
# at setup and the live one did not.
#
# Uses maps/ladder.tres — small, four close spawns — so opponents actually
# meet inside a match. On the 128x64 ship map two AI can grow old without
# ever seeing each other, which measures nothing.
#
# Reports the SPREAD and the sample size, not a bare win rate: ten matches
# where one side wins six proves nothing, and this project has twice been
# burned by a number that looked conclusive.
#
# SECONDS defaults to 600, and that number is load-bearing. It was 240,
# then 300, tuned when gatherer crews were 16 strong and the AI's first
# attack landed at 121-160 s. Crews are 5 now, and TRAIN_COOLDOWN is per
# ORDER — so the same labour force takes 22 productions instead of 7, and
# first contact moved to ~326 s. Every run at 300 s reported `attacks=0`
# and I read it as a broken AI for most of a session. It was the window.
#
# This is CLAUDE.md's standing rule biting again: when the opening
# changes, every timing tuned against the old one is stale. If crew size,
# TRAIN_COOLDOWN or the town hall's build time move, re-derive this
# before believing a run that says the AI never fought.
[doc("AI ladder: N headless AI-vs-AI matches, win rates and economy curves")]
ai-ladder MATCHES="10" SECONDS="600" AI="2": _import
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{artifacts_dir}}"
    log="{{artifacts_dir}}/ai-ladder.log"
    : > "$log"

    echo "ai-ladder: {{MATCHES}} matches, {{AI}} AI, {{SECONDS}}s cap, map=ladder"
    for i in $(seq 1 {{MATCHES}}); do
        # A different seed per match: same seed every time would measure
        # one map repeatedly and call it a win rate.
        # --players=0: nobody human is coming. This said --players=1 for
        # three milestones, so the server waited for a third participant
        # that the recipe never launches and EVERY ladder match sat in
        # Phase.LOBBY for its whole cap — reported below as a draw, and
        # read as an AI weakness through several rounds of AI work. The
        # "match actually started" assertion after the loop is what makes
        # that unrepeatable; this is only the fix.
        if [ "{{runtime}}" = "docker" ]; then
            docker compose -p {{compose_project}} run --rm --no-deps server \
                --headless --path . server.tscn -- \
                --map=res://maps/ladder.tres --lobby=0 --players=0 \
                --ai={{AI}} --seed=$i --run-seconds={{SECONDS}} \
                >> "$log" 2>&1 || true
        else
            godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
            "$godot" --headless --path . server.tscn -- \
                --map=res://maps/ladder.tres --lobby=0 --players=0 \
                --ai={{AI}} --seed=$i --run-seconds={{SECONDS}} \
                >> "$log" 2>&1 || true
        fi
        printf '.'
    done
    echo

    # The ladder reports averages, and an average cannot report a fault.
    # An AI seat was silently never sent composition for its own squads
    # for a whole milestone: it played on, the numbers all looked
    # plausible, and the ONLY thing that ever said so was a push_error in
    # ClientState that no recipe read. `test-load` has scanned for this
    # since M1 (line 423) — the ladder is the newer harness and simply
    # did not inherit it.
    if grep -Eq '(^|\| *)(ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING):' "$log"; then
        echo "ai-ladder: FAILED — engine diagnostics during the matches:" >&2
        grep -EIn '(^|\| *)(ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING):' "$log" >&2 | head -20
        exit 1
    fi

    # ASSERT THE MATCH HAPPENED, before reading a single statistic off it.
    #
    # This is CLAUDE.md's standing rule — "assert the thing did happen, not
    # merely that nothing complained" — arriving in the one harness that
    # most needed it. The ladder spent three milestones reporting
    # `draws (time cap): N` for matches that never left the lobby: a
    # harness describing a game that was never played, in the exact
    # vocabulary of an AI that would not fight. Every number below is
    # meaningless without this line.
    started=$(grep -c '^server: match started' "$log" || true)
    if [ "$started" -lt "{{MATCHES}}" ]; then
        echo "ai-ladder: FAILED — only $started of {{MATCHES}} matches ever left the lobby." >&2
        echo "  A match that never started is not a draw. Check --players/--ai against" >&2
        echo "  the server's players_expected, and see $log." >&2
        exit 1
    fi

    echo "ai-ladder: --- results over {{MATCHES}} matches ---"
    awk '
        /MATCH_RESULT/ {
            match($0, /winner=(-?[0-9]+)/, w)
            match($0, /phase=([0-9]+)/, ph)
            # phase 0 is LOBBY. A summary printed while still in the lobby
            # is a match that never ran, whatever its winner field says.
            if (ph[1] == "0") { unstarted++ }
            if (w[1] == "-1") { draws++ } else { wins[w[1]]++ }
            matches++
        }
        /AI_STATS/ {
            match($0, /player=([0-9]+)/, p)
            match($0, /civ=([a-z_]+)/, c)
            match($0, /squads_peak=([0-9]+)/, s)
            match($0, /workers_peak=([0-9]+)/, wk)
            match($0, /buildings=([0-9]+)/, b)
            match($0, /first_attack=(-?[0-9.]+)/, fa)
            civ[p[1]] = c[1]
            sq[p[1]] += s[1]; wkr[p[1]] += wk[1]; bld[p[1]] += b[1]; n[p[1]]++
            if (fa[1] >= 0) { atk[p[1]] += fa[1]; atkn[p[1]]++ }
        }
        END {
            if (matches == 0) { print "  no matches completed — see the log"; exit 1 }
            if (unstarted > 0) {
                printf "  FAILED: %d of %d matches ended still in the lobby — nothing was measured\n", unstarted, matches
                exit 1
            }
            printf "  decided: %d of %d   draws (time cap): %d\n", matches - draws, matches, draws
            for (k in n) {
                printf "  player %-5s civ=%-10s wins=%-3d squads_peak~%.1f workers_peak~%.1f buildings~%.1f",
                    k, civ[k], wins[k] + 0, sq[k]/n[k], wkr[k]/n[k], bld[k]/n[k]
                if (atkn[k] > 0) printf "  first_attack~%.0fs", atk[k]/atkn[k]
                else printf "  first_attack=never"
                printf "\n"
            }
            if (draws == matches) {
                print "  EVERY match hit the time cap — the AI is not seeking combat, which is a finding, not a pass"
            }
        }
    ' "$log"
