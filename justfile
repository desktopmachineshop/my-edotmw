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
# ai-ladder, test-ai-teams, gen-terrain-preview, replay-info.
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
# The GodotSteam release paired with THAT engine version (D-093, #181).
# Its own file, beside .godot-version, because the two are a PAIR and a
# mismatched pair fails at LOAD rather than at build — on a player's
# machine, not the builder's. Reported by `just doctor`; nothing here
# requires it, because absent Steam costs Steam features and never the
# game.
godotsteam_version := `cat .godotsteam-version`
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

# --- exported builds (D-20260827, #178, D-094 criterion 1) -------------
# THE build version, read out of the one place it is written down
# (project.godot's application/config/version — see build_version.gd).
# The recipes below only ever PRINT it; nothing here may compute a
# version of its own, which is the entire point of there being one.
build_version := `grep -m1 '^config/version=' project.godot | cut -d'"' -f2`
build_dir := justfile_directory() + "/build"
# Export templates live UNDER tools/, not in the machine's Godot data
# directory, because bootstrap.ps1 promises a fresh clone installs
# nothing system-wide and `just nuke` promises to leave pure source.
# Godot puts its editor data beside its own binary when a file named
# `_sc_` sits there ("self-contained mode"), which is what makes that
# possible without any per-preset absolute path.
export_templates_dir := tools_dir + "/editor_data/export_templates/" + godot_version + ".stable"

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

    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Acquired HERE rather than at the top of the recipe, because the skip
    # above is the common case and costs nothing — a recipe that imports
    # nothing must not queue behind another agent's load test. When the
    # caller already holds a slot (test-load -> up -> _import) this
    # inherits it and does not wait.
    gate="$(bash host-gate.sh acquire medium '_import' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM

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

    # --- exported builds (#178) ----------------------------------------
    # Reported, never required. Producing a build needs export templates;
    # running, testing and playing the game does not, which is the same
    # rule the art tooling below is reported under.
    echo
    echo "Build version: {{build_version}} (project.godot, application/config/version)"
    if [ -f "{{export_templates_dir}}/version.txt" ]; then
        echo "OK: export templates $(cat "{{export_templates_dir}}/version.txt") present"
    else
        echo "note: no export templates — \`just export\` needs \`just bootstrap-export-templates\` first"
    fi

    # --- art tooling (D-20260821) --------------------------------------
    # Reported, never required. Neither the wheel nor the application is
    # needed to run, test or play the game: generated/ is committed, so a
    # clone with no Blender at all is a working game (D-081). Reported
    # anyway because the two are easy to confuse and only one of them has
    # a window — blender-path.sh's header says which.
    echo
    bash blender-path.sh explain | sed 's/^/blender: /'

    # --- Steam (D-093, #181) -------------------------------------------
    # Reported, never required, and never a FAILURE: Steam-less is the
    # configuration every automated context here runs in — docker, CI,
    # the bots, this whole test estate — so a preflight that failed on it
    # would fail everywhere that matters.
    #
    # What is printed is the PAIRING, because that is the part a human
    # can get wrong: whether Steam is actually reachable is a runtime
    # question and `platform.gd` is the one thing allowed to
    # answer it (a second definition in shell would be free to disagree).
    echo
    echo "GodotSteam pin: {{godotsteam_version}} (for Godot {{godot_version}}) — platform.gd decides availability at runtime"
    echo "note: absent Steam costs Steam features (relay, lobbies, invites), never the game (D-093)"
    # --- Steam depot (#185, D-094 criterion 2) -------------------------
    # Reported, never required, exactly like the art tooling above: none
    # of it is needed to run, test or play the game, and an app id does
    # not exist until the owner has a partner account. Printed so that
    # "why did steam-upload refuse" is answered where people already
    # look rather than by reading a script.
    echo
    bash steam-depot.sh plan | sed 's/^/steam: /'

    # --- host budget (D-20260818) -------------------------------------
    # Reported, never enforced here: doctor's job is to say what the
    # machine looks like, and a preflight that FAILED on a busy host
    # would be a gate with no queue.
    echo
    bash host-gate.sh status
    if [ "${EDOTMW_NO_GATE:-0}" = "1" ]; then
        echo "WARN: EDOTMW_NO_GATE=1 — this shell is not being gated at all"
    fi
    # WSL2 with no .wslconfig may take 50% of RAM on demand and hold it,
    # which is the mechanism behind "Docker Desktop dies under parallel
    # agents". Applying a cap needs `wsl --shutdown`, which would kill
    # every OTHER agent's running containers — so this reports and a
    # human decides. The repo must never do that to a machine.
    if [ -n "${USERPROFILE:-}" ]; then
        wslcfg="$(cygpath -u "$USERPROFILE" 2>/dev/null || echo "$HOME")/.wslconfig"
        if [ -f "$wslcfg" ]; then
            echo "OK: .wslconfig present ($(grep -c . "$wslcfg" 2>/dev/null || echo 0) lines) — WSL memory is capped"
        else
            echo "WARN: no ~/.wslconfig — WSL2 may grow to 50% of RAM ($(( $(bash host-budget.sh total) / 2 )) MB) and hold it."
            echo "      Recommended, applied by a HUMAN at a quiet moment (it needs 'wsl --shutdown',"
            echo "      which kills every other agent's running containers):"
            echo "        [wsl2]"
            echo "        memory=4GB"
            echo "        processors=8"
            echo "        autoMemoryReclaim=gradual"
        fi
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

# Wrap an exported build into the thing a tester actually downloads
# (#183). One zip, named for the build inside it.
#
# The name carries the version because a tester's Downloads folder is
# where mixed builds are BORN: "my-edotmw.zip" twice is two files called
# "my-edotmw (1).zip", and the resulting desync report ends in "you were
# on last week's build". #179's handshake catches that at the join now —
# this is the half that stops it happening.
#
# The version comes from the one place it is written down (D-20260827),
# and the archive's entries are written in SORTED order so two packages
# of one build do not differ merely because a filesystem enumerated
# differently. It is NOT claimed to be byte-identical run to run — a zip
# stores mtimes — which is why the recipe prints a sha256 for whoever is
# about to hand it to somebody: the checksum you quote is the checksum of
# the file you send, not of a rebuild.
[doc("Zip an exported build for a tester (TARGET: windows-client|linux-server)")]
package TARGET="windows-client": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh enum TARGET "{{TARGET}}" windows-client windows-server linux-server
    # Host admission gate (D-20260818): this runs Godot over a 100+ MB
    # build, and `tests/test_host_budget.gd` is what caught it not
    # declaring a class — a recipe that can start while the machine has
    # nothing left is what that gate exists to stop.
    gate="$(bash host-gate.sh acquire medium 'package' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    version="{{build_version}}"
    if [ -z "$version" ]; then
        echo "FAIL: project.godot has no application/config/version — see build_version.gd" >&2
        exit 1
    fi
    case "{{TARGET}}" in
        windows-client)  dir="{{build_dir}}/windows" ;;
        windows-server)  dir="{{build_dir}}/windows-server" ;;
        linux-server)    dir="{{build_dir}}/linux-server" ;;
    esac
    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        echo "FAIL: nothing exported at $dir — run: {{just_executable()}} export {{TARGET}}" >&2
        exit 1
    fi
    mkdir -p "{{build_dir}}/packages"
    name="my-edotmw-{{TARGET}}-$version"
    out="{{build_dir}}/packages/$name.zip"
    rm -f "$out"
    # The README travels WITH the build, because a tester who downloaded a
    # zip six weeks ago has no repo to look anything up in and the
    # instructions have to be in the same folder as the thing they are
    # about. docs/alpha/testers.md is the one copy; this is a copy of it,
    # made at package time so it cannot go stale on its own.
    staging="{{build_dir}}/packages/.$name"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp -r "$dir"/. "$staging/"
    cp docs/alpha/testers.md "$staging/README.txt"
    # Packed by GODOT, not by `zip`. `zip` is not on Git Bash's PATH on
    # Windows and `Compress-Archive` is PowerShell-only; adding either as
    # a dependency would break the promise that a fresh clone needs
    # nothing but ./bootstrap.ps1. The engine is already pinned (D-001)
    # and is the same binary that produced the build being packed.
    #
    # Paths from INSIDE the staging directory, so the archive opens as
    # the build itself rather than as a folder a tester has to descend
    # into.
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: packaging needs a native Godot. Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi
    "$godot" --headless --path . --script package_zip.gd -- \
        --dir="$staging" --out="$out"
    rm -rf "$staging"
    if [ ! -s "$out" ]; then
        echo "FAIL: no package was written at $out" >&2
        exit 1
    fi
    echo "package: $out"
    # `sha256sum` prefixes the digest with a backslash when the path it
    # was given contains one, which every Windows path does — strip it,
    # or the checksum quoted to a tester does not match the one they
    # compute.
    echo "package: $(du -h "$out" | cut -f1), sha256 $(sha256sum "$out" | cut -d' ' -f1 | sed 's|^\\||')"
    echo "package: version $version — hand this to a tester with docs/alpha/testers.md"
# Bundle this machine's logs, replays and system details into one file a
# tester can attach to a bug report (#288).
#
# The recipe half of the feature. The half that MATTERS is the "Report a
# problem" button in both client menus, because a tester installing a zip
# has no `just` and no checkout — this is here for the person running the
# session, who has both and who is the one that ends up assembling other
# people's reports.
#
# `LIST=1` answers "what would you send" without writing anything. That
# is the question a tester is entitled to ask first, and it is also what
# makes the recipe useful on a machine that has played nothing.
#
# Host-gated, which the first version of this comment got wrong: it said
# "not gated, it copies a few files", and the files are not the cost —
# STARTING GODOT is, which is exactly what the gate rations
# (D-20260818). `test_host_budget.gd` caught it, which is what that scan
# is for. It also depends on `_import`, because it names global classes
# (ReportBundle, ArtifactPath, BuildVersion).
[doc("Zip logs, replays and system info into one attachable file (LIST=1 to preview)")]
report-bundle LIST="0": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh enum LIST "{{LIST}}" 0 1
    gate="$(bash host-gate.sh acquire medium 'report-bundle' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: needs a native Godot. Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi
    if [ "{{LIST}}" = "1" ]; then
        "$godot" --headless --script make_report.gd -- --list=1
    else
        "$godot" --headless --script make_report.gd
    fi



# Push a package to a PRIVATE itch.io channel via butler (#183).
#
# **This recipe has never been run against a real target.** It needs an
# itch.io account, a project, and a butler API key, none of which exist in
# a worktree — so what is verified here is the half that CAN be: it
# refuses, loudly and specifically, when butler or the key is missing,
# which is the state every automated context is in. The push itself is
# the human remainder, and the PR that added this says so.
#
# It exists as a recipe rather than as a line in the runbook because the
# invocation is the part that is easy to get wrong: the channel name is
# what itch uses to decide "is this the same product", and the `--userversion`
# is what makes a tester's client able to say which build it has. Both
# come from the one version (D-20260827) rather than from whoever is
# typing.
#
# It is also a rehearsal for steamcmd (#185) on purpose — same shape,
# same versioning question, and cheaper to get wrong.
[doc("Push a package to a private itch.io channel via butler (needs BUTLER_API_KEY)")]
publish-itch TARGET="windows-client" PROJECT="":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh enum TARGET "{{TARGET}}" windows-client windows-server linux-server
    if ! command -v butler >/dev/null 2>&1; then
        echo "FAIL: butler is not on PATH." >&2
        echo "      It is itch.io's uploader: https://itch.io/docs/butler/" >&2
        echo "      Nothing here installs it — it is a personal tool with a personal key," >&2
        echo "      the same reason blender-path.sh finds Blender rather than fetching it." >&2
        exit 1
    fi
    if [ -z "${BUTLER_API_KEY:-}" ]; then
        echo "FAIL: BUTLER_API_KEY is not set — butler cannot authenticate." >&2
        echo "      Get one with: butler login" >&2
        exit 1
    fi
    # The env fallback is read HERE rather than as a `just` default
    # expression. `tests/test_recipe_args.gd` scans recipe signatures for
    # parameters that are not checked, and a default of the form
    # `NAME=env_var_or_default(...)` parses as a parameter of its own —
    # so the guard reported a bare `"")` as an unchecked argument. No
    # other recipe here uses a function-call default, and matching the
    # house style is cheaper than reshaping a shared guard around one
    # unusual signature.
    project="{{PROJECT}}"
    if [ -z "$project" ]; then
        project="${EDOTMW_ITCH_PROJECT:-}"
    fi
    if [ -z "$project" ]; then
        echo "FAIL: no itch project. Pass it, or set EDOTMW_ITCH_PROJECT." >&2
        echo "      It looks like: yourname/my-edotmw" >&2
        exit 1
    fi
    version="{{build_version}}"
    package="{{build_dir}}/packages/my-edotmw-{{TARGET}}-$version.zip"
    if [ ! -s "$package" ]; then
        echo "FAIL: no package at $package — run: {{just_executable()}} package {{TARGET}}" >&2
        exit 1
    fi
    # The channel is the PRODUCT identity on itch, and `alpha-` keeps
    # these off any public channel name a store page would offer
    # (D-087: M8 produces no public artifact).
    channel="alpha-{{TARGET}}"
    echo "publish-itch: pushing $package to $project:$channel as $version"
    butler push "$package" "$project:$channel" --userversion "$version"
    butler status "$project:$channel"

# Fetch the PINNED engine's export templates into tools/.
#
# Separate from `bootstrap` for the same reason `bootstrap-art` is: it is
# a ~1.3 GB download and only somebody producing a build needs it.
# Everything else in this repo — running, testing, playing — works
# without it.
#
# The templates MUST match the engine exactly (a 4.7.1 build exported
# with 4.7.0 templates fails at load, not at export), so the version
# comes from .godot-version like everything else and is never typed here.
[doc("Fetch the pinned engine's export templates into tools/ (needed by `just export`)")]
bootstrap-export-templates:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{export_templates_dir}}/version.txt" ]; then
        echo "export templates {{godot_version}} already present — nothing to do."
        echo "  {{export_templates_dir}}"
        exit 0
    fi
    mkdir -p "{{tools_dir}}"
    # Godot's "self-contained mode" marker. With this file beside the
    # binary, editor data — export templates included — lives in
    # tools/editor_data instead of %APPDATA%/Godot or ~/.local/share/godot.
    # That is what keeps bootstrap.ps1's "nothing is installed
    # system-wide" promise true and what makes `just nuke` complete.
    : > "{{tools_dir}}/_sc_"
    url="https://github.com/godotengine/godot-builds/releases/download/{{godot_version}}-stable/Godot_v{{godot_version}}-stable_export_templates.tpz"
    echo "Fetching export templates for Godot {{godot_version}} (~1.3 GB) ..."
    curl -fL --retry 2 -o "{{tools_dir}}/export_templates.tpz" "$url"
    rm -rf "{{tools_dir}}/tpz"
    mkdir -p "{{tools_dir}}/tpz"
    unzip -o -q "{{tools_dir}}/export_templates.tpz" -d "{{tools_dir}}/tpz"
    if [ ! -f "{{tools_dir}}/tpz/templates/version.txt" ]; then
        echo "FAIL: the downloaded archive has no templates/version.txt — not an export template pack?" >&2
        exit 1
    fi
    got="$(cat "{{tools_dir}}/tpz/templates/version.txt")"
    if [ "$got" != "{{godot_version}}.stable" ]; then
        echo "FAIL: templates say '$got', .godot-version says '{{godot_version}}.stable'" >&2
        exit 1
    fi
    mkdir -p "{{export_templates_dir}}"
    cp -f "{{tools_dir}}"/tpz/templates/* "{{export_templates_dir}}/"
    rm -rf "{{tools_dir}}/tpz" "{{tools_dir}}/export_templates.tpz"
    echo "OK: export templates $got installed at {{export_templates_dir}}"

# Produce the shipping builds (D-094 criterion 1, #178).
#
# TARGET is one of: all (default), windows-client, windows-server,
# linux-server. The presets themselves live in export_presets.cfg, which
# is COMMITTED — that is what makes "from a clean clone" true, and
# tests/test_export.gd fails if a preset this recipe names stops
# existing.
#
# NATIVE ONLY, and not for D-014's usual reason: exporting needs the
# engine's editor half (it is `--export-release`, an editor operation),
# and the docker image ships the headless server binary. It imports
# natively first for exactly the reason `run-client` does — `_import`
# follows EDOTMW_RUNTIME and would populate the wrong cache.
#
# There is no timestamp, no git sha and no build counter anywhere in
# here: the version comes from project.godot and nothing else, so two
# clean clones of one commit export the same bytes (D-081's rule, and
# #178's own).
[doc("Export shipping builds (TARGET: all|windows-client|windows-server|linux-server)")]
export TARGET="all":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh enum TARGET "{{TARGET}}" all windows-client windows-server linux-server
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    gate="$(bash host-gate.sh acquire medium 'export' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM

    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: exporting needs a native Godot. Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi
    if [ ! -f "{{export_templates_dir}}/version.txt" ]; then
        echo "FAIL: no export templates for Godot {{godot_version}}." >&2
        echo "      Run: {{just_executable()}} bootstrap-export-templates" >&2
        exit 1
    fi
    version="{{build_version}}"
    if [ -z "$version" ]; then
        echo "FAIL: project.godot has no application/config/version — see build_version.gd" >&2
        exit 1
    fi

    # Import NATIVELY and unconditionally, for the same reason run-client
    # does: an export resolves every global class_name out of the import
    # cache, and .godot-container is the wrong one.
    "$godot" --headless --path . --import

    echo "export: my-edotmw $version (Godot {{godot_version}})"

    do_export () {
        preset="$1"; out="$2"
        mkdir -p "$(dirname "$out")"
        rm -f "$out"
        echo "  -> $preset"
        # --export-release, never --export-debug: a debug export carries
        # the debug template and would report a different build to a
        # player than the one that was tested.
        "$godot" --headless --path . --export-release "$preset" "$out"
        if [ ! -s "$out" ]; then
            echo "FAIL: '$preset' produced no binary at $out" >&2
            exit 1
        fi
        echo "     $(du -h "$out" | cut -f1)  $out"
    }

    if [ "{{TARGET}}" = "all" ] || [ "{{TARGET}}" = "windows-client" ]; then
        do_export "Windows Client" "{{build_dir}}/windows/my-edotmw.exe"
    fi
    if [ "{{TARGET}}" = "all" ] || [ "{{TARGET}}" = "windows-server" ]; then
        do_export "Windows Server" "{{build_dir}}/windows-server/my-edotmw-server.exe"
    fi
    if [ "{{TARGET}}" = "all" ] || [ "{{TARGET}}" = "linux-server" ]; then
        do_export "Linux Server" "{{build_dir}}/linux-server/my-edotmw-server.x86_64"
    fi
    echo "OK: exported my-edotmw $version into {{build_dir}}"

# Push the exported build to a private Steam branch (#185, D-094
# criterion 2).
#
# DRY BY DEFAULT, and that is the safety property rather than a
# convenience: an upload is outward-facing and cannot be taken back from
# a worktree, so `live` has to be typed. MODE is POSITIONAL like every
# other recipe argument (D-20260817-recipe-args-are-positional) and goes
# through recipe-arg.sh, so `just steam-upload MODE=live` is refused
# loudly rather than silently binding a string.
#
#   just steam-upload           validate + generate the VDFs, send nothing
#   just steam-upload live      the above, then steamcmd
#
# Every RULE lives in steam-depot.sh, not here, for the reason
# recipe-arg.sh and gate-check.sh do: the test estate cannot reach a
# recipe body, and `tests/test_steam_depot.gd` watches each of those
# rules fail. This recipe only decides whether to authenticate.
#
# Not host-gated: the gate rations MEMORY (D-20260818) and an upload is
# network-bound. `just export`, which this depends on and does not run
# for you, is gated.
[doc("Upload the exported build to a private Steam branch (dry run unless MODE=live)")]
steam-upload MODE="dry":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh enum MODE "{{MODE}}" dry live

    # Validation first, always, and identically in both modes: a dry run
    # that checked less than a live one would be a rehearsal of a
    # different performance.
    bash steam-depot.sh validate
    bash steam-depot.sh plan

    app_vdf="$(bash steam-depot.sh vdf "{{build_dir}}/steam")"

    if [ "{{MODE}}" = "dry" ]; then
        echo
        echo "DRY RUN — nothing was sent, and no credential was read."
        echo "  app build script: $app_vdf"
        echo "  a live run would then execute:"
        echo "      steamcmd +login \$EDOTMW_STEAM_USER +run_app_build $app_vdf +quit"
        echo "  re-run as: {{just_executable()}} steam-upload live"
        exit 0
    fi

    # --- the credential seam ------------------------------------------
    # Everything above this line is exercised by the dry run and by the
    # tests. Everything below needs a Steamworks account that does not
    # exist yet (#185: "the recipe can only be finished against a real
    # app id"), so it is written, refuses loudly, and has NOT been run
    # against Steam by anybody. Say so when you first do.
    steamcmd="$(bash steam-depot.sh find-steamcmd || true)"
    if [ -z "$steamcmd" ]; then
        echo "FAIL: no steamcmd. Set EDOTMW_STEAMCMD or put it on PATH." >&2
        echo "      This repo does not install it — see steam-depot.sh's header for why." >&2
        exit 1
    fi
    if [ -z "${EDOTMW_STEAM_USER:-}" ]; then
        echo "FAIL: EDOTMW_STEAM_USER is not set, so there is nobody to upload as." >&2
        echo "      See docs/status/m8-steam-depot.md — the password is NOT an env var;" >&2
        echo "      log in once interactively so steamcmd caches the Steam Guard sentry." >&2
        exit 1
    fi

    echo
    echo "steam-upload: LIVE — uploading as $EDOTMW_STEAM_USER"
    # The password is deliberately absent. Steam Guard makes an unattended
    # password login fail anyway on a machine that has not been trusted,
    # and the working practice is a cached sentry from one interactive
    # login — so a password here would be a secret in a process list that
    # does not even remove the prompt.
    "$steamcmd" +login "$EDOTMW_STEAM_USER" +run_app_build "$app_vdf" +quit
    echo "OK: submitted. The build is on the branch but Steam decides when it is live —"
    echo "    check the Builds page on the partner site."


# Start the server detached (docker runtime only — native has no
# persistent 'up' state, use run-server directly).
[doc("Start the server detached (docker runtime)")]
up: _import
    #!/usr/bin/env bash
    set -euo pipefail
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'up' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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

# --- host load (D-20260818-dev-work-is-admitted-against-a-host-budget) ---
#
# Several agents share one laptop. `instance` says who you are; these say
# what the machine has left, who is holding it, and what a change to any
# of it actually bought.

[doc("What the host has left, and who is holding it (D-20260818)")]
host-status:
    #!/usr/bin/env bash
    set -euo pipefail
    bash host-gate.sh status

# Drop gate holders whose process is gone. Runs automatically on every
# acquire; exposed because a human staring at an unexplained wait wants
# to be able to check rather than guess.
[doc("Drop admission-gate holders whose process died")]
host-reap:
    #!/usr/bin/env bash
    set -euo pipefail
    bash host-gate.sh reap
    echo "host-reap: done"
    bash host-gate.sh status

# THE instrument. Every number in D-20260818 came out of this, and any
# claim that the gate helped has to come out of it too — the same rule
# as gen-terrain-shot existing because no counter could see the ground.
#
# Windows-only: it reads Win32 performance counters. On any other host it
# says so rather than printing something it did not measure.
[doc("Sample host CPU/memory for SECONDS while you run something else")]
host-profile SECONDS="60" TAG="untagged":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int SECONDS "{{SECONDS}}"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) ;;
        *) echo "host-profile: Windows only — it reads Win32 perf counters." >&2; exit 1 ;;
    esac
    mkdir -p "{{artifacts_dir}}"
    out="{{artifacts_dir}}/host-profile-{{TAG}}.csv"
    echo "host-profile: sampling {{SECONDS}}s into $out — run the thing you are measuring NOW"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File host-sample.ps1         -Seconds {{SECONDS}} -Interval 1.5 -Out "$(cygpath -w "$out")" -Tag "{{TAG}}"

# Remove containers left behind by worktrees that NO LONGER EXIST.
#
# Keyed on the worktree being gone, never on age: D-095 forbids touching
# another agent's instance, and a live agent's container may legitimately
# sit idle for hours. A worktree that has been deleted has no agent left
# to own its containers, so this cannot race anyone. Found the need by
# measurement — five containers from other instances were sitting Exited
# for up to 42 hours despite a teardown-scoped design.
[doc("Remove containers whose worktree no longer exists (dry run unless APPLY=1)")]
reap-orphans APPLY="0":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh enum APPLY "{{APPLY}}" 0 1
    command -v docker >/dev/null 2>&1 || { echo "reap-orphans: no docker on PATH — nothing to do"; exit 0; }

    # The instance a container belongs to is derived from a git BRANCH, so
    # the only safe test for "orphaned" is that NO worktree still has that
    # branch. Matching container names against worktree PATHS was tried
    # first and is wrong in exactly the dangerous direction: instance
    # "ao-my-edotmw-45-reveal-gate" lives in a directory called
    # "my-edotmw-45", so a path match finds nothing and the container of a
    # LIVE agent looks orphaned. D-095's line is that a worktree never
    # removes another instance's containers — a heuristic that can be
    # wrong here is not allowed to be the one that runs.
    #
    # Sanitising is instance-id.sh's, character for character, because two
    # sanitisers that drift produce exactly the same false orphan.
    sanitise() {
        printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//'
    }
    live_file="$(mktemp)"
    trap 'rm -f "$live_file"' EXIT INT TERM
    git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p' | while read -r br; do
        [ -n "$br" ] && sanitise "$br" >> "$live_file"
        [ -n "$br" ] && echo >> "$live_file"
    done
    echo "{{instance}}" >> "$live_file"

    removed=0; kept=0
    while read -r name; do
        [ -n "$name" ] || continue
        # edotmw-<instance>-<service>[-run]-<suffix>
        inst="${name#edotmw-}"
        inst="$(echo "$inst" | sed -E 's/-(server|bots|test|client-test)(-run)?-[a-z0-9]+$//')"
        # Exact branch match, OR the same AO session on a different branch.
        # Worktrees 30 and 38 were both found still registered and ACTIVE
        # while their containers named the branch they had moved off — so
        # an exact-branch-only rule proposed deleting a live agent's
        # containers. Keeping too much costs an exited container; keeping
        # too little is the D-095 breach this recipe exists inside.
        # Greedy up to the LAST number: ao-my-edotmw-30-root -> ao-my-edotmw-30.
        # A [a-z0-9]+ class cannot span the dashes in "my-edotmw", which is
        # why the first attempt silently matched nothing and kept nobody.
        session="$(echo "$inst" | sed -E 's/^(.*-[0-9]+)-.*$/\1/')"
        if grep -qx "$inst" "$live_file" || grep -q "^$session-" "$live_file"; then
            kept=$((kept + 1)); continue
        fi
        if [ "{{APPLY}}" = "1" ]; then
            echo "reap-orphans: removing $name (branch for instance '$inst' is gone)"
            docker rm -f "$name" >/dev/null 2>&1 || true
        else
            echo "reap-orphans: WOULD remove $name (branch for instance '$inst' is gone)"
        fi
        removed=$((removed + 1))
        # NOT `docker ps -aq`: -q overrides --format and yields container IDs,
    # which then parse as instance names that match no branch — so every
    # LIVE agent's container reads as an orphan. Caught only because this
    # recipe dry-runs by default; it had five live containers queued for
    # deletion. A destructive default here would have been a D-095 breach
    # shipped as a cleanup convenience.
    done < <(docker ps -a --filter "name=^edotmw-" --format '{{{{.Names}}' 2>/dev/null || true)
    if [ "{{APPLY}}" = "1" ]; then
        echo "reap-orphans: removed $removed, kept $kept"
    else
        echo "reap-orphans: $removed orphan(s), $kept kept — DRY RUN, re-run with APPLY=1 to remove"
    fi

# Manual dev loop: run the server in the foreground.
# AI is how many computer opponents to seat (D-051). They take ordinary
# player slots, read the world through a client like you do, and are held
# to every rule you are. It is POSITIONAL — `run-server 3`, never
# `run-server AI=3`: that binds the whole string "AI=3" to AI, and it
# only ever worked because `int()` strips the non-digits. The same typo
# on the third parameter — `run-server LOBBY=1` — binds to AI instead and
# gives you one AI and no lobby. Both fail loudly now (#89,
# D-20260817-recipe-args-are-positional).
# LOBBY=1 (positionally, the third argument) holds the server in the
# lobby (D-048): the world is NOT
# generated until the admin presses start, because its size, seed and
# shape are all still being chosen (D-049). The first human to connect is
# admin and adds AI seats there — a lobby of one cannot start a match.
[doc("Headless server. AI=N seats opponents, LOBBY=1 waits in the lobby")]
run-server AI="0" MAP="res://maps/default.tres" LOBBY="0": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int AI "{{AI}}"
    bash recipe-arg.sh enum LOBBY "{{LOBBY}}" 0 1
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire heavy 'run-server' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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
# just takes arguments POSITIONALLY, so `just run-server LOBBY=1` parses
# "LOBBY=1" as the AI count, passes --ai=LOBBY=1, and int() reads that as
# 0 — no lobby, and a server that looks fine and is not in the mode you
# asked for. That is no longer SILENT — every recipe below checks what it
# was handed (D-20260817-recipe-args-are-positional, #89) — but this
# recipe stays, because "play a game" needs server and client to agree
# about port and mode whatever the arguments say.
#
# The world is NOT generated until the admin presses start (D-049): its
# size, seed and shape are all still being chosen, so there is genuinely
# nothing behind the lobby.
[doc("Play: lobby server + GUI client. You are admin; add AI seats, then Start")]
lobby PLAYERS="1":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int PLAYERS "{{PLAYERS}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire gpu 'lobby' $$)"
    export EDOTMW_GATE_HELD="$gate"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: the GUI client needs a native Godot (D-014)." >&2
        echo "      Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi

    # Whatever happens next, do not leave a server holding this
    # instance's port ({{port}} — D-095; other instances are untouched).
    trap '"{{just_executable()}}" down > /dev/null 2>&1 || true; bash host-gate.sh release "$gate"' EXIT INT TERM
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
# SANDBOX defaults to "auto", resolved by `instance-id.sh agent`: ON for
# an agent worktree, OFF for the human's own checkout on the default
# branch. An agent going straight into quick launch is always
# dev-testing, so it gets the dev build — sandbox mode (D-077) with its
# cheats panel — without having to remember to ask for it.
#
# Both arguments are POSITIONAL, like every just recipe's:
#   {{just_executable()}} quick-test 1337 1     # this seed, sandbox ON
#   {{just_executable()}} quick-test 1337 0     # this seed, sandbox OFF
# Writing `SANDBOX=1` binds that whole string to SEED instead, which used
# to launch with --seed=SANDBOX=1 and sandbox off, silently — and since
# `int()` strips the non-digits, on world seed 1 rather than 1337 (#89).
# Both values are checked below, so it now fails loudly
# (D-20260817-recipe-args-are-positional).
[doc("Quick test: you + 3 AI, all random civs, no lobby (agents get sandbox)")]
quick-test SEED="1337" SANDBOX="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int SEED "{{SEED}}"
    bash recipe-arg.sh enum SANDBOX "{{SANDBOX}}" 0 1 auto
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire gpu 'quick-test' $$)"
    export EDOTMW_GATE_HELD="$gate"
    sandbox="{{SANDBOX}}"
    if [ "$sandbox" = "auto" ]; then
        sandbox="$(bash instance-id.sh agent)"
    fi
    # Say what was resolved. Both halves of this failed SILENTLY before
    # (#89) and the only tell was a cheats panel that never appeared,
    # which reads as a broken feature rather than a mistyped command.
    if [ "$sandbox" = "1" ]; then
        echo "quick-test: instance {{instance}}, seed {{SEED}} — sandbox ON (dev build, D-077)"
    else
        echo "quick-test: instance {{instance}}, seed {{SEED}} — sandbox off"
    fi
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: the GUI client needs a native Godot (D-014)." >&2
        echo "      Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi

    # Whatever happens next, do not leave a server holding this
    # instance's port ({{port}} — D-095; other instances are untouched).
    trap '"{{just_executable()}}" down > /dev/null 2>&1 || true; bash host-gate.sh release "$gate"' EXIT INT TERM
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
# Every formation icon, magnified AND at the size the button really is.
#
# It exists because `test-client`'s capture scenario never selects a squad,
# so the panel it photographs has no formation buttons in it and
# structurally cannot show whether these read as the right shapes — the
# same blind spot `gen-terrain-shot` was added for. The second row is at
# true button size on purpose: an icon that reads at 96 px can be mush at
# 26, which is how the first version (24 dots on a shared scale) shipped
# looking like six identical blobs.
#
# Software-rasterised, no GPU needed. LOOK at artifacts/formation-icons.png.
[doc("Render every formation icon to artifacts/formation-icons.png")]
gen-formation-icons: _import
    #!/usr/bin/env bash
    set -euo pipefail
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'gen-formation-icons' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: needs a native Godot. Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi
    mkdir -p "{{artifacts_dir}}"
    "$godot" --headless --path . --import > /dev/null 2>&1 || true
    "$godot" --headless --path . --script formation_icon_preview.gd
    echo "look at {{artifacts_dir}}/formation-icons.png"


[doc("Regenerate the placeholder sound effects into generated/audio")]
build-audio:
    #!/usr/bin/env bash
    set -euo pipefail
    # NOT host-gated and needs NOTHING installed: `wave`, `math` and
    # `struct` are the standard library, so unlike `build-assets` (a ~1 GB
    # bpy wheel, blocked host-wide by an Application Control policy at the
    # time of writing) this runs on a fresh clone. Audio has no such
    # constraint and should not inherit one.
    #
    # Two runs must be byte-identical (D-081): fixed seeds, sorted
    # iteration, no timestamps.
    python audio/sfx.py
    echo "audio: now run   {{just_executable()}} test-unit audio   to check the table still resolves"
# A picture of the PRE-CONNECTION menu (#180).
#
# It exists because every other instrument this project has is aimed at a
# CONNECTED client: `test-client` needs a server to point at, and
# `lobby-shot` photographs the lobby, which is only reachable once a
# socket exists. The menu is the first thing a tester who installs a
# build ever sees, and until this recipe nothing could look at it — which
# is the blind spot this project has now paid for four times (cliffs,
# forest interiors, the fog edge, the HUD at 1080p).
#
# Modelled on `lobby-shot`, including being DOCKER-ONLY: it renders
# through Mesa's software GL under a virtual X server, so it needs no GPU
# and — the part that matters here — opens no window on anybody's
# desktop. `--headless` cannot be used instead: the dummy rendering
# driver draws nothing, so the screenshot would be a blank image that
# looked like a broken menu.
#
# Unlike `lobby-shot` it starts NO SERVER, and that is the point: the menu
# is the one screen that must render with nothing running.
#
# LOOK at artifacts/main-menu.png.
[doc("Render the pre-connection main menu to artifacts/main-menu.png")]
menu-shot SECONDS="4" RESOLUTION="1280x720" CONTROLS="0" MANUAL="": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh num SECONDS "{{SECONDS}}"
    # CONTROLS=1 photographs the CONTROLS screen instead of the menu
    # behind it (#282). Validated like every other numeric argument,
    # because `int()` strips non-digits and a mistyped value would
    # silently photograph the wrong screen
    # (D-20260817-recipe-args-are-positional).
    bash recipe-arg.sh enum CONTROLS "{{CONTROLS}}" 0 1
    # MANUAL=<page> photographs that page of the MANUAL instead (#305),
    # and wins over CONTROLS when both are given. A page id rather than a
    # flag, because "the manual" is a dozen screens and a shot of the
    # first one says nothing about the ones with tables on them.
    #
    # NOT validated against a list here: the pages are `manual.gd`'s
    # registry plus whatever `.tres` sit in /manual, and a second copy of
    # that list in a shell script is exactly the pair that comes to
    # disagree. The client refuses an unknown page and this recipe reads
    # the marker it prints, below.
    gate="$(bash host-gate.sh acquire medium 'menu-shot' $$)"
    export EDOTMW_GATE_HELD="$gate"
    if [ "{{runtime}}" != "docker" ]; then
        echo "menu-shot requires the docker runtime (it needs the software-GL image)." >&2
        echo "A native run would open a real window on somebody's desktop, which an" >&2
        echo "instrument has no business doing." >&2
        exit 1
    fi
    mkdir -p "{{artifacts_dir}}"
    shot="{{artifacts_dir}}/main-menu.png"
    if [ "{{CONTROLS}}" = "1" ]; then shot="{{artifacts_dir}}/controls.png"; fi
    if [ -n "{{MANUAL}}" ]; then shot="{{artifacts_dir}}/manual-{{MANUAL}}.png"; fi
    log="{{artifacts_dir}}/menu-shot.log"
    rm -f "$shot"
    trap '"{{just_executable()}}" down; bash host-gate.sh release "$gate"' EXIT INT TERM

    status=0
    # `--menu=1` forces the screen even though `--run-seconds` is capture
    # mode, which would otherwise connect. `=1` rather than a bare flag
    # because CmdArgs only parses `--key=value` and drops the rest — see
    # main_menu.gd, where the bare version cost a wrong picture.
    # No --address anywhere, and no server: this recipe is only honest if
    # nothing is running.
    timeout 180 docker compose -p {{compose_project}} run --rm --no-deps client-test \
        --path . client.tscn \
        --rendering-method gl_compatibility \
        --audio-driver Dummy \
        --resolution {{RESOLUTION}} \
        -- --menu=1 --controls={{CONTROLS}} --manual={{MANUAL}} \
        --run-seconds={{SECONDS}} \
        --screenshot="res://artifacts/$(basename "$shot")" \
        > "$log" 2>&1 || status=$?

    if [ ! -s "$shot" ]; then
        echo "menu-shot: no screenshot written — the menu did not render (see $log)" >&2
        exit 1
    fi
    # A frame that rendered NOTHING still saves as a valid PNG — it is one
    # flat colour. The capture path already counts distinct colours for
    # exactly that reason, so read its count rather than trusting the
    # file's existence (CLAUDE.md: assert the thing happened).
    colours="$(grep -oE 'distinct_colours=[0-9]+' "$log" | tail -1 | cut -d= -f2 || true)"
    if [ -z "$colours" ] || [ "$colours" -lt 8 ]; then
        echo "menu-shot: the frame has ${colours:-no} distinct colours — nothing was drawn (see $log)" >&2
        exit 1
    fi
    # The client's own VERDICT is expected to FAIL here and its exit
    # status with it: that verdict is about a MATCH — terrain, squads,
    # state hashes — and this recipe deliberately runs with no server at
    # all. Reported rather than hidden, so a real crash is still visible.
    # Assert the page ASKED FOR is the page drawn, rather than trusting
    # that a screenshot exists. `--controls=1` was written as a bare
    # `--menu` flag once and silently photographed the failure path with
    # every check green (#180); this is that lesson applied to an
    # argument that can name a page which does not exist.
    if [ -n "{{MANUAL}}" ]; then
        if ! grep -q "client: MANUAL page={{MANUAL}}" "$log"; then
            echo "menu-shot: the client did not open manual page '{{MANUAL}}' (see $log)" >&2
            grep -E "is not a page" "$log" >&2 || true
            exit 1
        fi
    fi
    echo "menu-shot: wrote $shot — $colours distinct colours, client exit $status (its match verdict does not apply here)"
    echo "menu-shot: LOOK AT IT"

# In-process hosting, proved against REAL remote clients (#182, D-088).
#
# A hosting client is a client and a server in ONE process: the host's
# own game reaches the simulation through the loopback peer D-051's AI
# seats already use, and remote players arrive over the ordinary socket.
# The interesting failure is therefore not "does it run" but "do the two
# halves agree" — so this points real bots at a real hosting client and
# reads the state-hash machinery on BOTH sides.
#
# NATIVE ONLY, for the same reason `run-client` is (D-014): the host is a
# client. It runs headless — the point here is the wire and the tick, not
# the picture — so it needs no GPU and opens no window.
#
# The menu with a REAL game in the list — the picture for #187.
#
# `menu-shot`'s sibling, and deliberately its opposite: that one is only
# honest with nothing running, because it photographs the screen a player
# sees before anything exists. This one is only honest with a server up,
# because what it photographs is a game that was FOUND.
#
# Docker, like `menu-shot`, for the same two reasons: the software-GL
# image, and that a native run would open a real window on somebody's
# desktop. A compose bridge is not a LAN and need not carry a broadcast,
# so the client is pointed at the `server` service BY NAME — the same
# `--browser-probe=` a player would use for a machine on another subnet,
# resolved once by `LanDiscovery`.
#
# LOOK AT THE PNG. The rest of the browser is asserted headlessly
# (`just browser-check`, `just test-unit game_browser`); this is the half
# that is a screen.
[doc("Photograph the menu with a real discovered game in it (#187)")]
browser-shot SECONDS="6" RESOLUTION="1280x720": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh num SECONDS "{{SECONDS}}"
    gate="$(bash host-gate.sh acquire heavy 'browser-shot' $$)"
    export EDOTMW_GATE_HELD="$gate"
    if [ "{{runtime}}" != "docker" ]; then
        echo "browser-shot requires the docker runtime (it needs the software-GL image)." >&2
        echo "A native run would open a real window on somebody's desktop, which an" >&2
        echo "instrument has no business doing." >&2
        exit 1
    fi
    mkdir -p "{{artifacts_dir}}"
    shot="{{artifacts_dir}}/game-browser.png"
    log="{{artifacts_dir}}/browser-shot.log"
    rm -f "$shot"
    trap '"{{just_executable()}}" down; bash host-gate.sh release "$gate"' EXIT INT TERM

    "{{just_executable()}}" up

    status=0
    # `--menu=1` forces the screen: this service sets EDOTMW_SERVER_ADDRESS,
    # which is a connection ASKED FOR (`MainMenu.autoconnect`), so without
    # it the client would join the very server it is supposed to be
    # browsing for. `--host-port=4433` is the IN-CONTAINER port, which is
    # the one the server binds inside the compose network (D-095 makes
    # only the HOST side per-instance).
    timeout 240 docker compose -p {{compose_project}} run --rm client-test \
        --path . client.tscn \
        --rendering-method gl_compatibility \
        --audio-driver Dummy \
        --resolution {{RESOLUTION}} \
        -- --menu=1 --run-seconds={{SECONDS}} \
        --host-port=4433 --browser-probe=server \
        --screenshot=res://artifacts/game-browser.png \
        > "$log" 2>&1 || status=$?

    if [ ! -s "$shot" ]; then
        echo "browser-shot: no screenshot written (see $log)" >&2
        exit 1
    fi
    # A frame that rendered NOTHING still saves as a valid PNG.
    colours="$(grep -oE 'distinct_colours=[0-9]+' "$log" | tail -1 | cut -d= -f2 || true)"
    if [ -z "$colours" ] || [ "$colours" -lt 8 ]; then
        echo "browser-shot: the frame has ${colours:-no} distinct colours — nothing was drawn (see $log)" >&2
        exit 1
    fi
    # And the point: the picture must contain a GAME. A shot of an empty
    # list would be a perfectly valid PNG of the feature not working.
    if ! grep -q "BROWSER_GAME" "$log"; then
        echo "browser-shot: the client found no game, so the picture shows an empty list (see $log)" >&2
        grep "BROWSER" "$log" | tail -3 >&2 || true
        exit 1
    fi
    echo "browser-shot: wrote $shot — $colours distinct colours, $(grep -c 'BROWSER_GAME' "$log") listing line(s), client exit $status"
    echo "browser-shot: LOOK AT IT"

# Prove the game browser end to end: a server announces, a client FINDS it.
#
# The gate for #187's LAN half, and it needs no GPU, no docker and no
# second machine — a headless client still builds its menu, still polls
# its providers, and prints a structured `BROWSER_GAME` line per row
# (client.gd), so "the list found the game" is a thing a recipe can
# assert rather than a thing somebody looked at.
#
# NATIVE, because docker's bridge is not a LAN and this is about a LAN.
# It probes 127.0.0.1 as well as broadcasting, so it proves the exchange
# on any machine — including one whose network drops broadcasts, which is
# the one thing it therefore CANNOT prove. Two players on one wifi is the
# owner's playtest.
#
# The server binds THIS INSTANCE's port (D-095), so two agents running it
# at once cannot find each other's game — and the discovery port is
# derived from that one, which is the whole reason it is derived.
[doc("Prove the game browser: a server announces, a client finds it (#187)")]
browser-check SECONDS="8": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int SECONDS "{{SECONDS}}"
    gate="$(bash host-gate.sh acquire medium 'browser-check' $$)"
    export EDOTMW_GATE_HELD="$gate"
    mkdir -p "{{artifacts_dir}}"
    server_log="{{artifacts_dir}}/browser-check-server.log"
    client_log="{{artifacts_dir}}/browser-check-client.log"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: browser-check needs the portable Godot in tools/" >&2
        echo "Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi
    server_pid=""
    cleanup () {
        if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
        bash host-gate.sh release "$gate"
    }
    trap cleanup EXIT INT TERM

    name="browser-check {{instance}}"
    "$godot" --headless --path . server.tscn -- \
        --port={{port}} --lobby=1 --name="$name" \
        --run-seconds=$(( {{SECONDS}} + 30 )) > "$server_log" 2>&1 &
    server_pid=$!

    # Wait for the socket rather than sleeping a guess (test-host's
    # lesson: world generation is tens of seconds on the shipped map).
    waited=0
    until grep -q "server: listening on" "$server_log" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -gt 120 ]; then
            echo "browser-check: the server never started listening (see $server_log)" >&2
            exit 1
        fi
    done

    "$godot" --headless --path . client.tscn -- \
        --menu=1 --run-seconds={{SECONDS}} --host-port={{port}} \
        --browser-probe=127.0.0.1 > "$client_log" 2>&1 || true

    fail=0
    # 1. The server offered itself at all. A beacon that never bound is
    #    the honest failure this must not report as "no games found".
    if ! grep -q "server: answering on port" "$server_log"; then
        echo "browser-check: the server opened no discovery socket (see $server_log)" >&2
        fail=1
    fi
    # 2. The client FOUND it — by name, at this instance's port, joinable.
    #    Structured markers, never a scary-word scan (CLAUDE.md).
    found="$(grep -cE "BROWSER_GAME name=$name address=[0-9.]+ port={{port}} joinable=true" "$client_log" || true)"
    if [ "${found:-0}" -lt 1 ]; then
        echo "browser-check: the client never listed this game (see $client_log)" >&2
        grep "BROWSER" "$client_log" | tail -5 >&2 || true
        fail=1
    fi
    # 3. And it listed it ONCE. A machine answers a broadcast on every
    #    interface it has, so the first end-to-end run of this listed one
    #    server three times — the defect that put a host token in the
    #    metadata (GameBrowser.entry_id), and the check that keeps it
    #    fixed.
    most="$(grep -oE "BROWSER games=[0-9]+" "$client_log" | grep -oE "[0-9]+" | sort -n | tail -1 || true)"
    if [ -n "${most:-}" ] && [ "$most" -gt 1 ]; then
        echo "browser-check: one server was listed $most times — the dedupe is broken" >&2
        fail=1
    fi
    # 4. The beacon really was asked. Zero questions and zero answers is
    #    what a browser that never sent anything also looks like.
    asked="$(grep -oE "answering on port [0-9]+ \([0-9]+ asked\)" "$server_log" | tail -1 || true)"
    if [ "$fail" -eq 0 ]; then
        echo "browser-check: ok — \"$name\" found on udp {{port}}, listed once ($asked at start)"
    fi
    exit "$fail"

# The host binds THIS INSTANCE's port (D-095), never the shared 4433: two
# agents running this at once must not find each other's match.
[doc("Prove in-process hosting: a hosting client, real bots joining it (#182)")]
test-host N="2" DURATION="60" AI="1": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int N "{{N}}"
    bash recipe-arg.sh int DURATION "{{DURATION}}"
    bash recipe-arg.sh int AI "{{AI}}"
    gate="$(bash host-gate.sh acquire heavy 'test-host' $$)"
    export EDOTMW_GATE_HELD="$gate"
    mkdir -p "{{artifacts_dir}}"
    host_log="{{artifacts_dir}}/test-host-host.log"
    bots_log="{{artifacts_dir}}/test-host-bots.log"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: test-host needs a native Godot (the host IS a client, D-014)." >&2
        exit 1
    fi
    host_pid=""
    cleanup () {
        if [ -n "$host_pid" ]; then kill "$host_pid" 2>/dev/null || true; fi
        bash host-gate.sh release "$gate"
    }
    trap cleanup EXIT INT TERM

    # The host runs a little longer than the bots so it is still there to
    # print its own verdict after they have gone.
    host_seconds=$(( {{DURATION}} + 20 ))
    "$godot" --headless --path . client.tscn --         --host=1 --host-port={{port}} --host-ai={{AI}}         --run-seconds="$host_seconds" > "$host_log" 2>&1 &
    host_pid=$!

    # Wait for the host to be LISTENING rather than sleeping a guess:
    # world generation is tens of seconds on the shipped map, and a bot
    # that connects before the socket exists fails for the wrong reason.
    waited=0
    until grep -q "server: listening on" "$host_log" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -gt 120 ]; then
            echo "test-host: the host never started listening (see $host_log)" >&2
            exit 1
        fi
    done
    echo "test-host: host is listening on udp {{port}} after ${waited}s"

    bots_status=0
    "$godot" --headless --script bot_client.gd --         --clients={{N}} --duration={{DURATION}} --port={{port}}         > "$bots_log" 2>&1 || bots_status=$?

    wait "$host_pid" || true
    host_pid=""

    fail=0
    # 1. The server really did run inside the client.
    if ! grep -q "the server is in this process" "$host_log"; then
        echo "test-host: the client did not host in-process (see $host_log)" >&2
        fail=1
    fi
    # 2. Remote clients really did join it over a socket — otherwise this
    #    proves only that a host can play alone, which the loopback makes
    #    true trivially.
    if ! grep -qE "{{N}}/{{N}} bots connected" "$bots_log"; then
        echo "test-host: not every bot connected to the host (see $bots_log)" >&2
        fail=1
    fi
    # 3. Both sides agree, and the comparison ACTUALLY RAN: zero desyncs
    #    over zero checks is nothing (the vacuous-pass rule).
    for pair in "host:$host_log" "bots:$bots_log"; do
        who="${pair%%:*}"; log="${pair#*:}"
        checks="$(grep -oE '[0-9]+ state.hash checks|state_hash_checks=[0-9]+' "$log" | tail -1 | grep -oE '[0-9]+' || true)"
        desyncs="$(grep -oE '[0-9]+ desyncs' "$log" | tail -1 | grep -oE '[0-9]+' || true)"
        if [ -z "${checks:-}" ] || [ "${checks:-0}" -lt 1 ]; then
            echo "test-host: $who ran no state-hash comparisons — nothing was proved (see $log)" >&2
            fail=1
        fi
        if [ -n "${desyncs:-}" ] && [ "$desyncs" -gt 0 ]; then
            echo "test-host: $who reported $desyncs desync(s) (see $log)" >&2
            fail=1
        fi
    done
    if [ "$bots_status" -ne 0 ] && ! grep -q "VERDICT" "$bots_log"; then
        echo "test-host: the bots exited with status $bots_status and no verdict (see $bots_log)" >&2
        fail=1
    fi

    if [ "$fail" -ne 0 ]; then exit 1; fi
    echo "test-host: clean — a hosting client and {{N}} remote client(s), no desyncs"
    grep -E "server: final" "$host_log" || true
    grep -E "client: state sync" "$host_log" || true
    grep -E "VERDICT" "$bots_log" || true

[doc("Run the GUI client natively (WASD pan, wheel zoom, right-click order)")]
run-client ADDRESS="127.0.0.1" PORT=port:
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int PORT "{{PORT}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire gpu 'run-client' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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
    bash recipe-arg.sh int N "{{N}}"
    bash recipe-arg.sh int DURATION "{{DURATION}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire heavy 'run-bots' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    # The bots are told which SCENARIO is being played, if any, so their
    # verdict can be scoped to what that scenario actually contains
    # (#230). `test-scenario` already exports EDOTMW_SCENARIO for the
    # server; empty means a real opening, which is what `test-load` and a
    # bare `just run-bots` are, and nothing about the run changes there.
    #
    # The bots do not act on it — it reaches the VERDICT only. A scenario
    # that places no buildings cannot satisfy a buildings gate however
    # healthy the run is, and failing every run identically is not a
    # check.
    scenario="${EDOTMW_SCENARIO:-}"
    if [ "{{runtime}}" = "docker" ]; then
        # In-network: the bots reach this project's server as "server:4433",
        # so no host port is involved (D-095).
        docker compose -p {{compose_project}} run --rm --no-deps bots --headless --script bot_client.gd -- --clients={{N}} --duration={{DURATION}} --scenario="$scenario"
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script bot_client.gd -- --clients={{N}} --duration={{DURATION}} --port={{port}} --scenario="$scenario"
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
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'test-unit' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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
#   3. log comparisons           — did fog gate squads and resource
#                                  positions from even the best-informed
#                                  bot (D-026 criterion 6's load half,
#                                  D-061), and did both civs field
#                                  something (D-046 criterion 10)? They
#                                  live in gate-check.sh so the FAST
#                                  loop makes them too.
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
# The protocol version handshake, both ways (#179, D-094 criterion 3).
#
# `test-load` and `test-scenario` prove the ACCEPT path on every run —
# `gate-check.sh handshake` fails a run in which anybody joined without
# one. Nothing they do can reach the REFUSAL, because every binary in
# this repo is built from the same net_protocol.gd and therefore agrees
# with itself by construction.
#
# So this recipe presents a deliberately wrong build to a REAL server
# over a REAL socket, and fails unless it is refused with a message that
# names both builds. That is the observed-to-fail rule made permanent
# rather than performed once by hand and written up: a refusal path
# nothing ever takes is a refusal path that will be broken the first time
# it matters, and that first time is a player's.
#
# It checks BOTH directions in one run, and the second half is not
# decoration: a server that refused everybody would satisfy the first
# half perfectly.
[doc("Prove a version-mismatched client is refused, and a matched one is not (#179)")]
test-handshake:
    #!/usr/bin/env bash
    set -euo pipefail
    gate="$(bash host-gate.sh acquire heavy 'test-handshake' $$)"
    export EDOTMW_GATE_HELD="$gate"
    mkdir -p "{{artifacts_dir}}"
    trap '"{{just_executable()}}" down; bash host-gate.sh release "$gate"' EXIT INT TERM
    "{{just_executable()}}" up

    stale_log="{{artifacts_dir}}/test-handshake-stale.log"
    matched_log="{{artifacts_dir}}/test-handshake-matched.log"
    server_log="{{artifacts_dir}}/test-handshake-server.log"

    # THE wrong version, derived from the right one rather than typed, so
    # bumping PROTOCOL_VERSION cannot silently make this recipe test a
    # version that happens to be valid again.
    ours="$(grep -oE '^const PROTOCOL_VERSION := [0-9]+' net_protocol.gd | grep -oE '[0-9]+$')"
    if [ -z "$ours" ]; then
        echo "test-handshake: could not read PROTOCOL_VERSION out of net_protocol.gd" >&2
        exit 1
    fi
    stale=$((ours + 1))
    echo "test-handshake: this build speaks protocol $ours; presenting $stale"

    # 1. The wrong build. Its bot never becomes a client, so it cannot
    #    take the server down with it on the way out (which is a rule of
    #    its own in server.gd's disconnect path, and was worth having).
    stale_status=0
    "{{just_executable()}}" run-bots-protocol 1 8 "$stale" > "$stale_log" 2>&1 || stale_status=$?

    # 2. The right one, against the SAME still-running server.
    matched_status=0
    "{{just_executable()}}" run-bots 1 8 > "$matched_log" 2>&1 || matched_status=$?

    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} stop server >/dev/null 2>&1 || true
        docker compose -p {{compose_project}} logs server > "$server_log" 2>&1 || true
    fi

    fail=0

    # The server said so, naming the protocol it was offered.
    if ! grep -q "server: REFUSED a client on protocol $stale" "$server_log"; then
        echo "test-handshake: the server did not refuse protocol $stale (see $server_log)" >&2
        fail=1
    fi
    # The CLIENT said so too, and could say what to do about it. A
    # refusal the far end never hears is a silent disconnect, which is
    # the confusing symptom this whole ticket replaces.
    if ! grep -q "REFUSED —" "$stale_log"; then
        echo "test-handshake: the stale client was never told why (see $stale_log)" >&2
        fail=1
    fi
    if ! grep -q "Update to the same build as the server" "$stale_log"; then
        echo "test-handshake: the refusal did not tell the player what to do (see $stale_log)" >&2
        fail=1
    fi
    if ! grep -q "refused=1" "$stale_log"; then
        echo "test-handshake: the stale run's verdict did not report a refusal (see $stale_log)" >&2
        fail=1
    fi

    # And the matched build got in — otherwise a server that refused
    # everyone would pass everything above. Asked through the SAME
    # `gate-check.sh handshake` that `test-load` and `test-scenario` run
    # on every ordinary run, rather than by a private grep here: the
    # comparison lives in one place, so this recipe cannot pass a check
    # the gate would fail (D-20260818-the-fast-loop-carries-the-gate's
    # rule, applied in the other direction).
    bash gate-check.sh handshake "$matched_log" "$server_log" || fail=1
    if [ "$matched_status" -ne 0 ]; then
        echo "test-handshake: the matched bot exited with status $matched_status" >&2
        fail=1
    fi

    if [ "$fail" -ne 0 ]; then
        exit 1
    fi
    echo "test-handshake: clean — protocol $stale refused with an actionable message, protocol $ours admitted"
    grep -E "server: REFUSED" "$server_log"
    grep -E "REFUSED —" "$stale_log"

# `run-bots`, but claiming a protocol version of your choosing. Dev-only
# and used by exactly one caller (`test-handshake`) — a separate recipe
# rather than a fourth positional argument on `run-bots`, because just
# binds arguments POSITIONALLY and a load test silently measured on the
# wrong protocol is precisely the class of accident
# D-20260817-recipe-args-are-positional exists to stop.
[doc("run-bots claiming PROTOCOL instead of this build's (dev only, #179)")]
run-bots-protocol N DURATION PROTOCOL: _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int N "{{N}}"
    bash recipe-arg.sh int DURATION "{{DURATION}}"
    bash recipe-arg.sh int PROTOCOL "{{PROTOCOL}}"
    gate="$(bash host-gate.sh acquire heavy 'run-bots-protocol' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} run --rm --no-deps bots --headless --script bot_client.gd -- --clients={{N}} --duration={{DURATION}} --protocol={{PROTOCOL}}
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script bot_client.gd -- --clients={{N}} --duration={{DURATION}} --port={{port}} --protocol={{PROTOCOL}}
    fi

[doc("Load test: server + N bots for DURATION seconds, then verify the run")]
test-load N DURATION:
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int N "{{N}}"
    bash recipe-arg.sh int DURATION "{{DURATION}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire heavy 'test-load' $$)"
    export EDOTMW_GATE_HELD="$gate"
    mkdir -p "{{artifacts_dir}}"
    trap '"{{just_executable()}}" down; bash host-gate.sh release "$gate"' EXIT INT TERM
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

    # The comparisons that need BOTH logs, in gate-check.sh rather
    # than inline (D-20260818-the-fast-loop-carries-the-gate): fog gating
    # of squads (D-026 criterion 6's load half), fog gating of resource
    # positions (D-061), both civilisations having fielded something
    # (D-046 criterion 10), and every client having joined through the
    # protocol version handshake (#179, D-094 criterion 3). They were
    # written here and copied nowhere, so
    # `test-scenario` — the loop people iterate in, because this one is
    # five minutes — asserted none of them. The reasoning for each lives
    # in the script; a test fails if this recipe makes a check the fast
    # loop does not.
    bash gate-check.sh fog-squads "$bots_log" "$server_log"
    bash gate-check.sh fog-nodes "$bots_log" "$server_log"
    bash gate-check.sh civs "$server_log"
    bash gate-check.sh handshake "$bots_log" "$server_log"

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
    # Memory, with ITS conditions — players, squads and cells (#111).
    # The same rule applied to a different number: "43.3 MB" says
    # nothing until you know it was four squads on a 32,592-cell map.
    grep -E "server: MEMORY" "$server_log" || true
    grep -E "MEMORY —" "$bots_log" || true

# The fast integration loop: a REAL server and REAL bots, but starting
# mid-match from a scenario instead of playing the opening (D-098).
#
# `test-load` needs ~120 s and that is not waste — a town hall takes 40 s
# and consumes the crew that founds it
# (D-20260823-the-opening-is-a-crew-and-a-general), production runs after it, and
# spawns are scattered far apart (D-039). None of that is under test when
# you are working on combat, fog, buildings or the wire, and paying two
# minutes for it every iteration is what makes people stop running it.
#
# This is NOT a replacement for `test-load`, and must never become one. A
# scenario hands out finished buildings and adjacent armies, so it cannot
# see a bug in founding, in production, or in spawn placement — the very
# things it skips. `just test-load` stays the gate a change passes before
# it is called done (its DURATION lives in docs/status/load-testing.md,
# because it scales with map size); this is the loop you iterate in.
#
# The checks ARE test-load's, plus one this recipe needs and test-load
# does not: the server must confirm IN ITS LOG that it actually
# played the scenario. A --scenario typo, or a stray server without the
# flag, would otherwise produce a fast, clean, entirely ordinary run — a
# pass that means nothing, which is the exact shape D-022's audit exists
# to catch.
[doc("Fast integration loop: server + bots from a mid-game scenario (~31s at DURATION=15)")]
test-scenario SCENARIO="siege" N="4" DURATION="30":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int N "{{N}}"
    bash recipe-arg.sh int DURATION "{{DURATION}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire heavy 'test-scenario' $$)"
    export EDOTMW_GATE_HELD="$gate"
    mkdir -p "{{artifacts_dir}}"
    trap '"{{just_executable()}}" down > /dev/null 2>&1 || true; bash host-gate.sh release "$gate"' EXIT INT TERM
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

    # 4. The same log comparisons the GATE makes, from the same
    #    script (D-20260818-the-fast-loop-carries-the-gate). This recipe
    #    said "the checks follow test-load's shape" and had copied one of
    #    four; the missing three cost nothing here, because a scenario
    #    run already prints every marker they read. Fog gating is if
    #    anything HARDER to satisfy mid-game than during the opening —
    #    armies are in reach, so more of the board is visible — which is
    #    what makes it worth asserting on the loop that actually runs.
    #
    #    The peak-knowledge comparison is asked only of a scenario that
    #    can answer it (#230). `fog-squads` says even the MOST-INFORMED
    #    client knew fewer squads than the server simulated, at every
    #    moment — and a scenario whose armies all converge has a moment
    #    when somebody has seen everything. `clash` is that scenario by
    #    construction, and it is declared so in its own `.tres` rather
    #    than named here, so a new scenario is covered the day it is
    #    written.
    #
    #    NOT SILENT. gate-check.sh's own header is explicit that "a
    #    comparison that silently skips is the vacuous pass D-022's audit
    #    was written against", so the skip is printed with its reason —
    #    and `fog-nodes` still runs, so fog is asserted here either way,
    #    as are the conceal/reveal events the bots' own verdict gates on.
    if grep -q "proves_fog_gating=false" "$server_log"; then
        echo "gate-check(fog-squads): SKIPPED — scenario '{{SCENARIO}}' declares it cannot prove"
        echo "  peak fog gating: its armies converge, so the best-informed client ends up"
        echo "  having seen every squad. Fog is still asserted by fog-nodes below and by the"
        echo "  bots' own conceal/reveal gates. See #230 and scenario_def.gd."
    else
        bash gate-check.sh fog-squads "$bots_log" "$server_log"
    fi
    bash gate-check.sh fog-nodes "$bots_log" "$server_log"
    bash gate-check.sh civs "$server_log"
    bash gate-check.sh handshake "$bots_log" "$server_log"

    # 5. Engine diagnostics, by line PREFIX rather than by scary word.
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

# Re-stamp the manual's prose pages against the rules they describe (#305).
#
# Only the PROSE needs this. The manual's roster, stat, counter, building
# and formation pages are derived from the shipped .tres when a player
# opens them, so there is nothing there to rebuild and nothing that can go
# stale — `just build-manual` has no work to do for them at all.
#
# MODE=verify changes nothing and exits non-zero if anything is stale,
# which is what you want before deciding whether you have prose to write.
# `just test-unit manual` makes the same comparison and is the gate.
[doc("Re-stamp the manual's prose pages against the rules they describe")]
build-manual MODE="write": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh enum MODE "{{MODE}}" write verify
    # Host admission gate (D-20260818). `medium`, the same class as the
    # gen-* previews: the work is small but the Godot process this project
    # starts is not, and classing it `free` would be claiming a measurement
    # nobody took. `tests/test_host_budget.gd` is structural about the
    # declaration existing at all — a recipe that runs Godot declares a
    # class, or the machine is un-gated by one more thing nobody
    # remembered.
    gate="$(bash host-gate.sh acquire medium 'build-manual' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    args=""
    if [ "{{MODE}}" = "verify" ]; then args="--verify"; fi
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} run --rm --no-deps test \
            --headless --script manual_stamp.gd -- $args
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script manual_stamp.gd -- $args
    fi

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
# DURATION was raised 60 -> 90 on 2026-08-25, and the reason is the standing
# one: `conceal_events` needs a bot to wander OUT of vision, which happens on
# the match's clock while the capture window is fixed wall-clock — so anything
# that slows the client's start eats the margin.
#
# It had none. Measured A/B on one host, same seed: with the gatherer's
# pre-tools assets the verdict passed twice at `conceal_events=1` and 71-72
# state-hash checks; with the tooled gatherer (double the VAT, seven clips
# instead of four) it failed three times at 0 and 66 checks. Six ticks of
# window, against a gate clearing by exactly one event.
#
# At 90 it clears with room — 10 conceal and 10 reveal events, 106 checks.
# This is CLAUDE.md's "when the opening changes, every timing tuned against
# the old one is stale" applied to an ASSET getting heavier, and the honest
# direction is to lengthen the run rather than to weaken the check.
# didn't complain (D-022's standing rule).
# RESOLUTION is a parameter for the same reason `lobby-shot` grew one: this
# recipe was pinned to 1280x720, which is the reference window `hud_layout.gd`
# is designed against, and therefore the one size at which a scaling or
# anchoring defect is a deliberate no-op - #90 was invisible here for exactly
# that reason. The default is unchanged, so every frame taken before this is
# still comparable.
[doc("Render the GUI client headlessly with bots as a second player and verify the frame (software GPU)")]
test-client SECONDS="90" BOTS="3" RESOLUTION="1280x720" HOLD="0": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh num SECONDS "{{SECONDS}}"
    bash recipe-arg.sh int BOTS "{{BOTS}}"
    # HOLD reaches the client as `--hold-opening=N` and is read with
    # `int()`, which STRIPS non-digits rather than failing — so `HOLD=yes`
    # would silently mean 0 and the capture would found anyway, producing
    # the empty-banner frame this flag exists to avoid
    # (D-20260817-recipe-args-are-positional). Caught by
    # `test_every_numeric_recipe_argument_is_checked`, not by me.
    bash recipe-arg.sh enum HOLD "{{HOLD}}" 0 1
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire heavy 'test-client' $$)"
    export EDOTMW_GATE_HELD="$gate"
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
    trap '"{{just_executable()}}" down; bash host-gate.sh release "$gate"' EXIT INT TERM
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
        --resolution {{RESOLUTION}} \
        -- --address=server --run-seconds={{SECONDS}} \
        --hold-opening={{HOLD}} \
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
    # structured markers" rule — gate-check.sh's comparisons follow the
    # same shape), not an inference from prose. Absence of any of these, or a zero value, means M2 was not
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
    bash recipe-arg.sh int CHUNK_SIZE "{{CHUNK_SIZE}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'gen-terrain-preview' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'build-assets' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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

# Open an authored asset in your LOCALLY INSTALLED Blender
# (D-20260821-game-assets-are-files).
#
# TARGET is a unit or building id — `art/source/<TARGET>.blend`, which is
# an ordinary Blender file and the SOURCE OF TRUTH for that model. Model
# it, rig it, animate it, save it, then `just build-assets`.
#
# With no TARGET it lists what is there. There is deliberately no "open
# everything": these are files now, and a file is opened one at a time.
#
# Blender is a NORMAL DESKTOP INSTALL, not something this repo manages.
# There is no bootstrap recipe and nothing is downloaded into tools/:
# install Blender the way you install any other application and this
# finds it. blender-path.sh is the one definition of where it looks, and
# EDOTMW_BLENDER names one outright if you keep several.
#
# It opens with YOUR Blender — your preferences, your add-ons, your
# startup file. No --factory-startup, no wrapper script and no custom
# panel: it is your Blender opening your file, which is the point.
#
# NATIVE ONLY, for the same reason as run-client (D-014): it opens a
# window for a human to look at. It ignores EDOTMW_RUNTIME.
#
# NOT host-gated, deliberately. Every other heavy recipe is admitted
# against the machine budget (D-20260818) because it is agent work
# competing with other agents. This is the owner opening their modelling
# application; they can launch the same binary from the desktop with no
# queue at all, so a gate here protects nothing and only puts a wait in
# front of a double-click.
[doc("Open art/source/<TARGET>.blend in your locally installed Blender")]
blender-gui TARGET="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{TARGET}}" ]; then
        echo "Authored sources in art/source/ — pass one as TARGET:"
        for f in art/source/*.blend; do
            [ -e "$f" ] || { echo "  (none yet — {{just_executable()}} seed-art-source)"; break; }
            echo "  $(basename "$f" .blend)"
        done
        echo
        echo "  {{just_executable()}} blender-gui militia"
        exit 0
    fi
    blend="art/source/{{TARGET}}.blend"
    if [ ! -f "$blend" ]; then
        echo "FAIL: no $blend" >&2
        echo "      {{just_executable()}} blender-gui   # lists what exists" >&2
        exit 1
    fi
    blender="$(bash blender-path.sh find)"
    bash blender-path.sh check >/dev/null
    echo "blender-gui: $blend in $blender"
    echo "  edit, save (Ctrl-S), then: {{just_executable()}} build-assets {{TARGET}}"
    "$blender" "$blend"

# Seed art/source/*.blend from the LEGACY generators (D-20260821).
#
# A migration, run once per model, and never part of the build. It
# refuses to overwrite an existing source file, because that file is the
# source of truth now and a generator writing over it would be a script
# discarding an artist's work.
[doc("Create art/source/*.blend from the legacy generators (one-time)")]
seed-art-source ONLY="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -x "{{blender_python}}" ]; then
        echo "FAIL: no bpy environment at {{blender_venv}}"
        echo "Run: {{just_executable()}} bootstrap-art"
        exit 1
    fi
    args=""
    [ -n "{{ONLY}}" ] && args="--only={{ONLY}}"
    "{{blender_python}}" art/seed_source.py $args

# Put the axe and the pickaxe on the gatherer's back.
#
# A migration like seed-art-source and author-clips, never part of the build:
# it edits art/source/gatherers.blend, and `build-assets` bakes whatever the
# .blend says. It refuses to run against a model that already has the tools,
# because a second run would attach a second pair — restore the source from
# git first if you are re-tuning where they sit.
#
# Order matters and the recipe below is the whole of it:
#
#   attach-tools               the tools become part of the mesh, on two bones
#   author-clips gatherers     chop/mine/forage, drawing the right one
#   build-assets               bake it into the game
#
# author-clips REFUSES if the sockets are missing, so the middle step cannot
# silently write a work clip onto a model with nothing in its fist.
[doc("Attach the axe and pickaxe to art/source/gatherers.blend")]
attach-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -x "{{blender_python}}" ]; then
        echo "FAIL: no bpy environment at {{blender_venv}}"
        echo "Run: {{just_executable()}} bootstrap-art"
        exit 1
    fi
    "{{blender_python}}" art/attach_tools.py
    echo "Now animate them: {{just_executable()}} author-clips gatherers"

# A migration like attach-tools, for FIGHTING kit: weapon into the fist,
# shield onto the forearm, standard onto the back, each skinned 1.0 to an
# existing bone so it follows whatever author-clips does to the arm
# (D-20260826-the-dwarf-roster-wears-supplied-models).
[doc("Attach a unit's fighting kit to art/source/<TARGET>.blend")]
attach-kit TARGET="militia":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -x "{{blender_python}}" ]; then
        echo "FAIL: no bpy environment at {{blender_venv}}"
        echo "Run: {{just_executable()}} bootstrap-art"
        exit 1
    fi
    "{{blender_python}}" art/attach_kit.py --name "{{TARGET}}"
    echo "Now animate it: {{just_executable()}} author-clips {{TARGET}}"

# Bind an UNRIGGED authored body to the family skeleton with automatic
# weights (D-20260826). A migration: run once, against a source restored
# from git, then attach-kit and author-clips.
[doc("Give a bare art/source/<TARGET>.blend the DONOR's skeleton")]
transplant-rig TARGET="spearmen" DONOR="militia":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -x "{{blender_python}}" ]; then
        echo "FAIL: no bpy environment at {{blender_venv}}"
        echo "Run: {{just_executable()}} bootstrap-art"
        exit 1
    fi
    "{{blender_python}}" art/transplant_rig.py --name "{{TARGET}}" --donor "{{DONOR}}"

# Write a rigged art/source/<name>.blend's clips onto its bones.
#
# A migration like seed-art-source, never part of the build: it edits the
# .blend, and `build-assets` bakes whatever the .blend says.
#
# Which clips depends on the archetype: the base four for most of the
# roster, plus chop/mine/forage for the gatherer, who is the only unit that
# carries tools (`clips_for` in art/lib/clips.py).
#
# A model that arrives rigged arrives with a SKELETON and no ACTIONS, which
# is a T-posed soldier sliding across the ground. `art/clips.py` animates
# the generated `Part` hierarchy and cannot drive an arbitrary armature, so
# a supplied rig needs its clips written against ITS bones — matched by
# name, with which way the model FACES measured from its toes rather than
# assumed (D-20260824-a-supplied-rig-is-animated-against-its-own-bones).
#
# Re-runnable: it clears the previous animation first, so tuning a stride
# is edit-and-rerun rather than edit-and-hope.
[doc("Author a rigged art/source/<name>.blend's clips onto its bones")]
author-clips NAME="":
    #!/usr/bin/env bash
    set -euo pipefail
    # A default of "" rather than a bare required parameter, for a test's
    # reason as much as a usability one: `tests/test_recipe_args.gd` treats
    # every no-default recipe parameter as a NUMBER owed a recipe-arg.sh
    # check, because until this recipe every such parameter was one. NAME is
    # an archetype, so it takes the `seed-art-source ONLY=""` shape instead
    # and refuses loudly here.
    if [ -z "{{NAME}}" ]; then
        echo "FAIL: author-clips needs an archetype, e.g.:"
        echo "  {{just_executable()}} author-clips gatherers"
        exit 1
    fi
    if [ ! -x "{{blender_python}}" ]; then
        echo "FAIL: no bpy environment at {{blender_venv}}"
        echo "Run: {{just_executable()}} bootstrap-art"
        exit 1
    fi
    "{{blender_python}}" art/author_clips.py --name="{{NAME}}"
    echo "Now rebuild: {{just_executable()}} build-assets"

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
    bash recipe-arg.sh num SECONDS "{{SECONDS}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'gen-model-preview' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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
# One unit model, filling the frame, through the real render path.
#
# `gen-model-preview` frames the WHOLE roster, which puts every soldier at
# about thirty pixels — enough to answer "did they all draw", useless for
# "what does this one look like". That gap cost a session: an imported model
# rendered as brown noise and the roster shot could not show whether the
# fault was the colours, the geometry or the scale
# (D-20260824-a-textured-model-keeps-its-texture). A close-up settles it in
# one look.
#
# MODEL is a `UnitDef.model_id`, not a unit id — several units share one.
# CLIP names a pose to hold, and `unit_shot.gd` has taken one since it was
# written — the recipe simply never passed it, so every shot this recipe has
# ever produced was a `walk`. That matters more since a model can carry clips
# others do not (D-20260825): the gatherer's axe and pickaxe are ON ITS BACK
# in every clip but `chop` and `mine`, so a walk shot is the one framing that
# cannot show whether it draws them.
[doc("Render one unit model close up to artifacts/unit-shot.png")]
gen-unit-shot MODEL="gatherers" CLIP="walk": _import
    #!/usr/bin/env bash
    set -euo pipefail
    gate="$(bash host-gate.sh acquire medium 'gen-unit-shot' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    mkdir -p "{{artifacts_dir}}"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: gen-unit-shot needs the portable Godot in tools/"
        echo "Run: {{just_executable()}} bootstrap"
        exit 1
    fi
    log="{{artifacts_dir}}/unit-shot.log"
    "$godot" --path . --rendering-method gl_compatibility         --resolution 1000x1000 unit_shot.tscn -- --model="{{MODEL}}"         --clip="{{CLIP}}" --out="res://artifacts/unit-shot.png" | tee "$log"
    if [ ! -s "{{artifacts_dir}}/unit-shot.png" ]; then
        echo "VERDICT: FAIL - no PNG was written"
        exit 1
    fi
    # Say whether the model took its TEXTURE or its vertex colours. The two
    # look nothing alike at this density and identical in every counter.
    grep -o 'textured=[a-z]*' "$log" | head -n 1
    echo "VERDICT: ok - LOOK AT artifacts/unit-shot.png"

[doc("Render ground cover to artifacts/cover-godot.png")]
gen-cover-preview SECONDS="0.6": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh num SECONDS "{{SECONDS}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'gen-cover-preview' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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

# A rendered picture of a MELEE with the Tier 1 duel pass applied
# (D-20260818-rome-total-war-formations-in-three-tiers, exit criterion 1
# of D-20260818-battle-quality-outranks-player-count).
#
# The same idea as the previews above and needed for the same reason: the
# duel is a picture, every unit test about it is about indices and
# distances, and no existing instrument can frame a fight — test-client
# aims its camera at a spawn, which is the one place a melee is not.
#
# Software-rasterised, so no GPU: this answers "is the picture right", and
# `bench-render` answers "how fast".
gen-duel-preview SECONDS="0.6": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh num SECONDS "{{SECONDS}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    gate="$(bash host-gate.sh acquire medium 'gen-duel-preview' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    mkdir -p "{{artifacts_dir}}"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: gen-duel-preview needs the portable Godot in tools/"
        echo "Run: {{just_executable()}} bootstrap"
        exit 1
    fi
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
    log="{{artifacts_dir}}/duel-preview.log"
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a -s "-screen 0 1400x900x24" "$godot" --path . \
            --rendering-method gl_compatibility --resolution 1400x900 \
            duel_preview.tscn -- --seconds="{{SECONDS}}" \
            --out="res://artifacts/duel-godot.png" | tee "$log"
    else
        "$godot" --path . --rendering-method gl_compatibility \
            --resolution 1400x900 duel_preview.tscn -- --seconds="{{SECONDS}}" \
            --out="res://artifacts/duel-godot.png" | tee "$log"
    fi
    if [ ! -s "{{artifacts_dir}}/duel-godot.png" ]; then
        echo "VERDICT: FAIL - no PNG was written"
        exit 1
    fi
    summary="$(grep -o '[0-9]* men, [0-9]* moved, [0-9]* in contact, mean gap [0-9.]*' "$log" | head -n 1)"
    if [ -z "$summary" ]; then
        echo "VERDICT: FAIL - the preview never reported what it drew"
        exit 1
    fi
    moved="$(echo "$summary" | sed 's/[0-9]* men, \([0-9]*\) moved.*/\1/')"
    contact="$(echo "$summary" | sed 's/.* \([0-9]*\) in contact.*/\1/')"
    if [ "$moved" -eq 0 ]; then
        echo "VERDICT: FAIL - no man stepped into the fight; the duel pass did nothing"
        exit 1
    fi
    if [ "$contact" -eq 0 ]; then
        echo "VERDICT: FAIL - nobody reached contact; two squads are swinging at the air"
        exit 1
    fi
    # The fallen (D-20260819-a-casualty-is-visible): the same picture is the
    # instrument for exit criterion 2, so a frame with no bodies in it fails.
    corpses="$(grep -o '[0-9]* corpses laid' "$log" | head -n 1 | sed 's/ corpses laid//')"
    if [ -z "$corpses" ] || [ "$corpses" -eq 0 ]; then
        echo "VERDICT: FAIL - no corpses were laid; the battlefield has no memory"
        exit 1
    fi
    echo "VERDICT: ok - $summary, $corpses corpses; LOOK AT artifacts/duel-godot.png"

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
    bash recipe-arg.sh num SECONDS "{{SECONDS}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'gen-forest-preview' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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
    bash recipe-arg.sh num HEIGHT "{{HEIGHT}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'gen-terrain-shot' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
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

# A rendered picture of the TORUS SEAM, with armies standing on it.
#
# Written for playtest #32, which asks whether the wrapped world reads as
# seamless. Nothing in the estate could frame that question: `test-client`
# points at a spawn, `gen-terrain-shot` finds a cliff, `gen-forest-preview`
# finds the densest wood — three deliberate framings of something else, and
# a seam is no likelier to appear in any of them than any other cell.
#
# SEAM is "q" (the width wrap), "r" (the height wrap) or "corner" (both at
# once). Squads are drawn through the client's own three-call copy pipeline
# (RenderCull.visible_offsets_of_extent -> LatticeCopies.draw), so a squad
# straddling the wrap line is drawn exactly where the game would draw it.
#
# Software-rasterised, so it needs no GPU and says nothing about speed.
#
# LOOK AT the PNG. That is the entire point of the recipe.
[doc("Render the torus seam with armies on it, to artifacts/seam-<seam>.png")]
gen-seam-shot SEAM="q" HEIGHT="16": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh num HEIGHT "{{HEIGHT}}"
    gate="$(bash host-gate.sh acquire medium 'gen-seam-shot' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    mkdir -p "{{artifacts_dir}}"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: gen-seam-shot needs the portable Godot in tools/"
        echo "Run: {{just_executable()}} bootstrap"
        exit 1
    fi
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
    out="{{artifacts_dir}}/seam-{{SEAM}}.png"
    rm -f "$out"
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a -s "-screen 0 1400x900x24" "$godot" --path . \
            --rendering-method gl_compatibility --resolution 1400x900 \
            playtest_seam_shot.tscn -- --height={{HEIGHT}} --seam={{SEAM}} \
            --out=res://artifacts/seam-{{SEAM}}.png
    else
        "$godot" --path . --rendering-method gl_compatibility \
            --resolution 1400x900 playtest_seam_shot.tscn -- \
            --height={{HEIGHT}} --seam={{SEAM}} \
            --out=res://artifacts/seam-{{SEAM}}.png
    fi
    if [ ! -s "$out" ]; then
        echo "gen-seam-shot: no frame was written to $out" >&2
        exit 1
    fi

# M4's tiered scale sweep (D-027 criterion 17's successor, D-012, D-020).
#
# Drives the simulation directly at 100/250/500/1000 squads rather than
# playing a match, because squad count in a real game is whatever
# production produces and D-018 targets ~1,000. Prints CSV: the SHAPE of
# the curve is the deliverable, not the endpoint — cost should stay flat
# per squad, and a bend means something is accidentally quadratic.
# ONLY selects one section — count, map, derive or ladder — instead of all
# four. Empty runs everything, so a bare `just profile` is what it was.
# The ladder (#304) is the section a perf question usually wants, and the
# whole sweep is minutes of work.
[doc("Scale sweep: simulation cost at 100/250/500/1000 squads; ONLY=count|map|derive|ladder")]
profile ONLY="" COUNTS="": _import
    #!/usr/bin/env bash
    set -euo pipefail
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire heavy 'profile' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    if [ "{{runtime}}" = "docker" ]; then
        docker compose -p {{compose_project}} run --rm --no-deps test --headless --script profile_sweep.gd -- --only="{{ONLY}}" --counts="{{COUNTS}}"
    else
        godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
        "$godot" --headless --script profile_sweep.gd -- --only="{{ONLY}}" --counts="{{COUNTS}}"
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
bench-render COUNTS="0,100,250,500,1000" FRAMES="120" HEIGHT="40" HOST="0" PRESET="" HULLS="0" ARGS="":
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int FRAMES "{{FRAMES}}"
    bash recipe-arg.sh num HEIGHT "{{HEIGHT}}"
    # HOST and HULLS are numeric and therefore go through the checker
    # (D-20260817-recipe-args-are-positional): GDScript's `int()` STRIPS
    # non-digits rather than failing, so `HOST=islands` would silently be
    # host mode OFF and the run would measure a client while claiming to
    # measure a host. PRESET is a name and is passed through as one.
    bash recipe-arg.sh int HOST "{{HOST}}"
    bash recipe-arg.sh int HULLS "{{HULLS}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire gpu 'bench-render' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: the render benchmark needs a native Godot with a GPU (D-014)." >&2
        echo "      Run: {{just_executable()}} bootstrap" >&2
        exit 1
    fi
    "$godot" --headless --path . --import
    # ARGS is the attribution channel (#229): --clamp=0, --sampler=0,
    # --copies=0, --cells_wide=84 --cells_high=96. Empty by default, so a
    # bare `just bench-render` measures the shipping client exactly as it
    # always did and every number ever quoted stays comparable.
    "$godot" --path . bench_render.tscn -- --counts={{COUNTS}} --frames={{FRAMES}} --height={{HEIGHT}} --host={{HOST}} --preset="{{PRESET}}" --hulls={{HULLS}} {{ARGS}}

# Is the recorded render baseline about THIS tree? (#286)
#
# Seconds, headless, no GPU — so it can run on every pull request, which
# is the point: it cannot tell you the client got slower, and it CAN tell
# you that nobody has measured since the map, the roster, the built
# assets or the render path last moved. That absence is what let #229 be
# a 3x regression found months later by a human playing the game.
#
# STRICT=1 exits non-zero when the baseline is stale. Off by default: a
# stale baseline is news, not a fault, and a check that fails every PR
# touching formation.gd is a check that gets muted (D-022's audit block
# from the other direction). The nightly job is where STRICT belongs.
[doc("Are the recorded render baselines about this map, roster, assets, render path?")]
bench-stale STRICT="0": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int STRICT "{{STRICT}}"
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    "$godot" --headless --path . --script bench_check.gd --         --stale --strict={{STRICT}}

# Run the render benchmark and compare it against the recorded baseline.
#
# NATIVE and needs a real GPU, exactly like `bench-render` — the numbers
# are only meaningful on hardware somebody can name (D-014, D-044
# criterion 2).
#
# GATES ON COUNTS, never on milliseconds. Given the same map, roster and
# render path a run draws the same men at the same LOD in the same draw
# calls every time; a millisecond is a statement about the host, and this
# project has already gone red on a wall-clock gate with nothing wrong
# (D-106's amendment). Times are printed with their deltas and decide
# nothing.
[doc("Run bench-render and compare it against the recorded baseline (#286)")]
bench-check COUNTS="250,1000" FRAMES="90" STRICT="0": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int FRAMES "{{FRAMES}}"
    bash recipe-arg.sh int STRICT "{{STRICT}}"
    gate="$(bash host-gate.sh acquire gpu 'bench-check' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: bench-check needs a native Godot with a GPU (D-014)." >&2
        exit 1
    fi
    mkdir -p "{{artifacts_dir}}"
    "$godot" --path . bench_render.tscn -- --counts={{COUNTS}}         --frames={{FRAMES}} --json=res://artifacts/bench-latest.json
    "$godot" --headless --path . --script bench_check.gd --         --run=res://artifacts/bench-latest.json --strict={{STRICT}}

# Record the render baseline `bench-check` compares against (#286).
#
# A deliberate, human act: it overwrites a committed file with numbers
# from THIS machine, and the file names the adapter they came from. Never
# run it to make a red check green without reading what moved first — a
# baseline re-recorded on a regression is how the mechanism becomes a
# rubber stamp.
[doc("Record this machine's render baseline slot (one file per adapter)")]
bench-record COUNTS="250,1000" FRAMES="90": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int FRAMES "{{FRAMES}}"
    gate="$(bash host-gate.sh acquire gpu 'bench-record' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
    if [ ! -x "$godot" ]; then
        echo "FAIL: bench-record needs a native Godot with a GPU (D-014)." >&2
        exit 1
    fi
    mkdir -p bench "{{artifacts_dir}}"
    # `--record=1`, not `--json=<path>`: the RUN names the file, because
    # it is the only thing that knows which adapter it measured on
    # (#285). One slot per GPU, so recording here cannot overwrite the
    # numbers somebody took on other hardware — structurally, rather than
    # by a flag anybody has to remember.
    "$godot" --path . bench_render.tscn -- --counts={{COUNTS}}         --frames={{FRAMES}} --record=1
    echo "recorded this machine's slot in bench/ — COMMIT IT. The file is"
    echo "named for the adapter, and no other adapter's slot was touched."

# Screenshot the LOBBY (D-048), so its layout can actually be looked at.
#
# Separate from `test-client` because it wants the opposite setup: a
# server that STAYS in the lobby (`--lobby=1`, so it waits for an admin
# who never presses start) and a client that renders the seat list rather
# than a battlefield. Docker only, same software-GL reasoning as
# test-client.
#
# RESOLUTION is a parameter because the lobby's whole reported failure was
# resolution-dependent (#91): it fit the 1280x720 this recipe was pinned
# to and ran off the bottom of the ~1920x1000 window the playtest used, so
# the one instrument that could have shown it was aimed at the one size
# where it did not happen. Same lesson as `test-client` aiming its camera
# at a spawn.
[doc("Screenshot the lobby screen into artifacts/lobby.png")]
lobby-shot SECONDS="8" AI="2" PRESET="0" RESOLUTION="1280x720": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh num SECONDS "{{SECONDS}}"
    bash recipe-arg.sh int AI "{{AI}}"
    bash recipe-arg.sh int PRESET "{{PRESET}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire medium 'lobby-shot' $$)"
    export EDOTMW_GATE_HELD="$gate"
    # Release is folded into this recipe's own teardown trap below — a
    # second `trap ... EXIT` here would REPLACE it and silently drop the
    # teardown, which is the whole reason that trap is not additive.
    if [ "{{runtime}}" != "docker" ]; then
        echo "lobby-shot requires the docker runtime (it needs the software-GL image)." >&2
        exit 1
    fi
    mkdir -p "{{artifacts_dir}}"
    shot="{{artifacts_dir}}/lobby.png"
    log="{{artifacts_dir}}/lobby-shot.log"
    rm -f "$shot"
    trap '"{{just_executable()}}" down; bash host-gate.sh release "$gate"' EXIT INT TERM

    docker compose -p {{compose_project}} run --rm --no-deps -d --name {{compose_project}}-lobby-server \
        server --headless --path . server.tscn -- --lobby=1 --players=8 > /dev/null
    sleep 3

    status=0
    timeout 180 docker compose -p {{compose_project}} run --rm --no-deps client-test \
        --path . client.tscn \
        --rendering-method gl_compatibility \
        --audio-driver Dummy \
        --resolution {{RESOLUTION}} \
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
# the profile's train cooldown or the town hall's build time move,
# re-derive this before believing a run that says the AI never fought.
#
# TEAMS defaults to 0 — a free-for-all, which is what every ladder number
# recorded before #119 was measured on, so the default run stays
# comparable with them. TEAMS=2 with AI=4 is a 2v2, and the reason it
# exists is that allied AI behaviour was exercised by NOTHING: #83 shipped
# an AI that marched its army onto its own teammate's town for a
# milestone, and the ladder — a free-for-all — could not have noticed on
# any map, at any cap, for any number of matches. Arguments are POSITIONAL
# (D-20260817-recipe-args-are-positional): `just ai-ladder 3 600 4 2`.
#
# PROFILES pairs difficulties against each other
# (D-20260818-ai-profiles-are-data): a comma-separated list of AI profile
# ids, dealt round-robin across the AI seats, e.g.
# `just ai-ladder 6 600 2 0 cautious,relentless`. Empty — the default —
# seats every AI on the shipped profile, so an invocation written before
# profiles existed measures exactly what it measured then. It is the
# FIFTH argument because TEAMS is the fourth: two branches each adding
# "one more positional argument" is how a run silently measures a pairing
# nobody asked for.
#
# QUOTE ANY RESULT FROM THIS RECIPE WITH ITS CAP. A stronger opponent
# lengthens matches and a truncated match reads as a draw, so "2 of 3
# decided" means nothing without the seconds beside it.
[doc("AI ladder: N headless AI-vs-AI matches, win rates and economy curves")]
ai-ladder MATCHES="10" SECONDS="600" AI="2" TEAMS="0" PROFILES="" MAP="res://maps/ladder.tres": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int MATCHES "{{MATCHES}}"
    bash recipe-arg.sh int SECONDS "{{SECONDS}}"
    bash recipe-arg.sh int AI "{{AI}}"
    bash recipe-arg.sh int TEAMS "{{TEAMS}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire heavy 'ai-ladder' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    mkdir -p "{{artifacts_dir}}"
    log="{{artifacts_dir}}/ai-ladder.log"
    : > "$log"

    profiles="{{PROFILES}}"
    died=""
    echo "ai-ladder: {{MATCHES}} matches, {{AI}} AI, {{TEAMS}} teams, {{SECONDS}}s cap, map={{MAP}}, profiles=${profiles:-<default>}"
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
        #
        # --stop-after-match: a decided match stops rather than simulating
        # its winner gathering against nobody for the rest of the cap
        # (#224). One ladder match was decided at 95s of a 600s cap and
        # then simulated 505 further seconds — 84% of its wall clock —
        # which is why `ai-ladder 3 600` cost a flat half hour however
        # fast the matches decided. ONLY this recipe passes it, so every
        # other harness measures the window it always did.
        #
        # And the exit status is KEPT rather than discarded with
        # `|| true`. It was discarded, so a server killed from outside
        # (this host OOMs — #153) vanished from the results with nothing
        # anywhere saying so.
        status=0
        if [ "{{runtime}}" = "docker" ]; then
            docker compose -p {{compose_project}} run --rm --no-deps server \
                --headless --path . server.tscn -- \
                --map={{MAP}} --lobby=0 --players=0 \
                --ai={{AI}} --ai-teams={{TEAMS}} --ai-profiles="$profiles" \
                --seed=$i --run-seconds={{SECONDS}} --stop-after-match=5 \
                >> "$log" 2>&1 || status=$?
        else
            godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
            "$godot" --headless --path . server.tscn -- \
                --map={{MAP}} --lobby=0 --players=0 \
                --ai={{AI}} --ai-teams={{TEAMS}} --ai-profiles="$profiles" \
                --seed=$i --run-seconds={{SECONDS}} --stop-after-match=5 \
                >> "$log" 2>&1 || status=$?
        fi
        if [ "$status" -ne 0 ]; then
            died="$died seed=$i(exit $status)"
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

    # AND ASSERT IT FINISHED. The mirror of the check above, and the half
    # D-107 did not write (#224): three matches left the lobby, one of
    # them died mid-run printing nothing at all, and the ladder reported
    # "decided: 2 of 2" for a run of THREE — a denominator counted from
    # the matches that survived, so a vanished match cannot appear in it
    # by construction.
    #
    # None of the existing guards could see it. The started-check passed,
    # because it did start. The diagnostics grep found nothing, because a
    # process that is killed prints no ERROR. And `|| true` swallowed the
    # exit code. This is D-107's own lesson one layer in: that entry made
    # the ladder assert that matches START, and nothing asserted they END.
    finished=$(grep -c '^server: MATCH_RESULT' "$log" || true)
    if [ "$finished" -lt "{{MATCHES}}" ]; then
        echo "ai-ladder: FAILED — $finished of {{MATCHES}} matches produced a result;" >&2
        echo "  $(( {{MATCHES}} - finished )) started and then vanished without one." >&2
        if [ -n "$died" ]; then
            echo "  servers that exited non-zero:$died" >&2
            echo "  (137 is SIGKILL — on this project's host that is usually the OOM" >&2
            echo "   killer rather than a game defect: see #153 and 'just host-status')" >&2
        else
            echo "  every server exited 0, so the loss is inside the run, not the process." >&2
        fi
        echo "  A missing match is not a drawn match. See $log." >&2
        exit 1
    fi

    echo "ai-ladder: --- results over {{MATCHES}} matches ---"
    awk -v asked={{MATCHES}} '
        /MATCH_RESULT/ {
            match($0, /winner=(-?[0-9]+)/, w)
            match($0, /team=(-?[0-9]+)/, wt)
            match($0, /phase=([0-9]+)/, ph)
            # phase 0 is LOBBY. A summary printed while still in the lobby
            # is a match that never ran, whatever its winner field says.
            if (ph[1] == "0") { unstarted++ }
            if (w[1] == "-1") { draws++ }
            else {
                wins[w[1]]++
                # A TEAM can win (D-050). The winner field names one member
                # of the winning side, so in a 2v2 a per-player tally
                # credits one of two allies with a victory both won — and
                # reads as a 1-of-4 win rate for a side that took every
                # match.
                if (wt[1] + 0 > 0) team_wins[wt[1]]++
            }
            matches++
        }
        /AI_STATS/ {
            match($0, /defences_standing=([0-9]+)/, ds); defences_total += ds[1] + 0
            match($0, /defences_ordered=([0-9]+)/, do_); defences_ordered_total += do_[1] + 0
            match($0, /defences_fought=([0-9]+)/, df); defences_fought_total += df[1] + 0
            match($0, /gate_orders=([0-9]+)/, go); gate_orders_total += go[1] + 0
            match($0, /player=([0-9]+)/, p)
            match($0, /civ=([a-z_]+)/, c)
            match($0, / team=([0-9]+)/, t)
            match($0, /profile=([a-z_]+)/, pr)
            match($0, /squads_peak=([0-9]+)/, s)
            match($0, /workers_peak=([0-9]+)/, wk)
            match($0, / buildings=([0-9]+)/, b)
            match($0, /allies_seen=([0-9]+)/, al)
            match($0, /ally_objectives=([0-9]+)/, ao)
            match($0, /first_attack=(-?[0-9.]+)/, fa)
            match($0, /first_attack_soldiers=([0-9]+)/, fs)
            civ[p[1]] = c[1]
            team[p[1]] = t[1] + 0
            prof[p[1]] = pr[1]
            sq[p[1]] += s[1]; wkr[p[1]] += wk[1]; bld[p[1]] += b[1]; n[p[1]]++
            allies[p[1]] += al[1]; ally_obj[p[1]] += ao[1]; ally_obj_total += ao[1]
            if (fa[1] >= 0) { atk[p[1]] += fa[1]; atkn[p[1]]++; men[p[1]] += fs[1] }
        }
        END {
            if (matches == 0) { print "  no matches completed — see the log"; exit 1 }
            if (unstarted > 0) {
                printf "  FAILED: %d of %d matches ended still in the lobby — nothing was measured\n", unstarted, matches
                exit 1
            }
            # Denominator is what was ASKED for, never what survived.
            # The self-referential version is what printed "2 of 2" for a
            # run of three (#224); the bash check above catches this
            # first, and this is here so the LINE cannot lie even if
            # somebody reaches the awk another way.
            printf "  decided: %d of %d   draws (time cap): %d\n", matches - draws, asked, draws
            if (asked > 0 && matches != asked) {
                printf "  FAILED: only %d of %d matches produced a result\n", matches, asked
                exit 1
            }
            for (k in n) {
                printf "  player %-5s civ=%-10s ai=%-11s team=%-2d wins=%-3d squads_peak~%.1f workers_peak~%.1f buildings~%.1f allies_seen~%.1f",
                    k, civ[k], prof[k], team[k], wins[k] + 0, sq[k]/n[k], wkr[k]/n[k], bld[k]/n[k], allies[k]/n[k]
                if (atkn[k] > 0) printf "  first_attack~%.0fs with ~%.0f men", atk[k]/atkn[k], men[k]/atkn[k]
                else printf "  first_attack=never"
                printf "\n"
                # Per PROFILE, which is the number a pairing was run to
                # get: seats are dealt round-robin, so several seats can
                # share a difficulty, and a per-player line cannot answer
                # "did the harder one win".
                pwins[prof[k]] += wins[k] + 0
                pplayed[prof[k]] += n[k]
                if (atkn[k] > 0) { patk[prof[k]] += atk[k]; patkn[prof[k]] += atkn[k]; pmen[prof[k]] += men[k] }
            }
            for (k in pplayed) {
                printf "  profile %-11s wins %d of %d seats played", k, pwins[k], pplayed[k]
                if (patkn[k] > 0) printf "   first_attack~%.0fs with ~%.0f men", patk[k]/patkn[k], pmen[k]/patkn[k]
                printf "\n"
            }
            print "  (quote a pairing WITH its cap: a stronger opponent lengthens matches, and a truncated match reads as a draw)"
            for (k in team_wins) printf "  team %-2s wins=%d of %d\n", k, team_wins[k], matches
            # An objective on a friend is #83 coming back, and a ladder
            # measuring an AI parked on its own ally is measuring nothing.
            # Reported per player so the log says WHICH seat did it.
            if (ally_obj_total > 0) {
                printf "  FAILED: %d attack objective(s) landed on a friend — see #83/#119\n", ally_obj_total
                for (k in ally_obj) if (ally_obj[k] > 0) printf "    player %s: %d\n", k, ally_obj[k]
                exit 1
            }
            # #337, and the standing gap D-076 recorded: no AI built or
            # used a wall, so this harness could not exercise the feature
            # at all — the shape that left BuildingSim.damage() uncalled
            # for two milestones (D-055).
            #
            # Gated on a defence STANDING rather than on one being
            # ordered. An order is an intent, and D-107 is the standing
            # reason not to trust one: the first version of this feature
            # reported 40 orders and 1 building.
            #
            # defences_fought is REPORTED, not gated. A wall is only
            # fought over if somebody attacks it, which needs a match that
            # reaches contact — and a gate that fails an honest run is how
            # "test-load 4 40" came to be the documented recommendation
            # for a milestone while being unable to pass (D-031). Measured:
            # 4 seats at a 600s cap reported defences_fought=71 on one
            # seat, and 2 seats at 420s reported zero. The counter is here
            # so the gate is one line the day somebody settles which
            # configuration always reaches it.
            #
            # NOTE: no apostrophes anywhere in this awk program. It is a
            # single-quoted shell string, so one ends the quoting and the
            # error you get is "awk: cmd. line:N: (END OF FILE)" pointing
            # at a line that is fine. That cost two ladder runs.
            if (defences_total <= 0) {
                print "  FAILED: no AI built any static defence — walls, gates and towers"
                print "    are shipped (D-076) and #337 exists because nothing exercised them."
                print "    Check AI_STATS defences_ordered= against defences_standing=: orders"
                print "    with nothing standing means the sites are being refused."
                exit 1
            }
            printf "  static defence: %d standing across seats, %d ordered, %d fought over, %d gate order(s)\n", defences_total, defences_ordered_total, defences_fought_total, gate_orders_total
            if (defences_fought_total == 0) {
                print "  (no wall was attacked this run — reported, not gated; see D-20260828-an-ai-that-fortifies)"
            }
            if (draws == matches) {
                print "  EVERY match hit the time cap — the AI is not seeking combat, which is a finding, not a pass"
            }
        }
    ' "$log"


# A TEAMED all-AI match, played for real, that fails if an AI marches on a
# friend (#119).
#
# This exists because #83 — an AI whose targeting read "not mine" as
# "hostile", so an allied AI parked its whole army on its teammate's town
# centre and milled there for the rest of the match — shipped for a
# milestone with NOTHING in the estate able to see it. `just ai-ladder` is
# a free-for-all, `tests/test_ai_player.gd` seated its AI on team 0 (which
# D-050 says is not a team), and the `--lobby=0` path never handed
# `SquadSim.teams` over at all, so even a teamed seat list would have
# produced a simulation in which nobody was anybody's ally. The one
# configuration that breaks a thing was the one nothing ran.
#
# It is a SCENARIO run (D-098), not an opening: #83 needs an AI with an
# army, a teammate with a base, and both of them in sight of each other,
# which the real opening takes ~170 s of production and walking to
# produce. `siege` hands every seat a town centre, a tower and two
# militia squads on the first tick, so the AI reaches its first objective
# in seconds and the harness costs a minute rather than ten.
#
# It plays MATCHES seeds, and that is not thoroughness for its own sake.
# The bug fires when an ALLY is the nearest thing an AI knows about, and
# spawn points are scattered at `min_spawn_spacing` (D-039) — so which
# neighbour a seat gets is a property of the seed, not of the seating.
# One seed with the fix reverted found ONE offending seat of four; a
# harness that catches its bug in a quarter of cases is not a harness.
# Every seed is a fresh world, and the verdict is over all of them.
#
# What it asserts, and why each one is here rather than implied:
#
#   the match started            the standing rule — the ladder reported
#                                three milestones of matches that never
#                                left the lobby as draws
#   SIM_TEAMS has >= 2 sides     teams reached the SIMULATION, printed
#                                from `_sim.teams` itself. Without this
#                                every alliance assertion below passes
#                                vacuously on a free-for-all
#   every AI saw an ally         the vacuity guard for the next line: an
#                                AI with no teammate in sight cannot have
#                                marched on one and reports the same 0
#   every AI attacked            an AI that never picked an objective
#                                cannot have picked a bad one
#   ally_objectives == 0         the finding itself
#
# Observed to FAIL before it was trusted, per CLAUDE.md: with the #83 fix
# reverted (`_hostile` in `_enemy_target` put back to an ownership test)
# this recipe reports ally objectives on every seat. See
# decisions/D-20260818-allied-ai-is-exercised-by-something.md for the two
# runs.
# PROFILES is the LAST argument and defaults to empty, which seats every
# AI on the shipped default — so with no argument this recipe measures
# exactly the match #119 measured. Given a list
# (`just test-ai-teams 3 90 4 2 siege cautious,relentless`) it deals
# difficulties across the seats and then ASSERTS THEY ARRIVED: every seat
# must report the profile it was dealt, and a list naming more than one
# must produce more than one at the table.
#
# That check is here rather than in a harness of its own for the reason
# this recipe exists at all. #119's finding was that the one configuration
# which breaks a thing is very often the one nothing runs; a difficulty
# that is real in a unit test and silently lost on the way to a seat is
# the same defect wearing D-20260818-ai-profiles-are-data's clothes. The
# unit tests prove a profile field changes a DECISION. Only a real match
# proves it survives the seating path — and this is already the one path
# that deals a seat something per-seat.
#
# PAIR PROFILES ON A SCENARIO WHOSE STARTING ARMY EVERY PROFILE CAN
# COMMIT, which is `clash` and not the default `siege`. Measured: `siege`
# hands each seat TWO military squads, and a profile whose
# `attack_squads_minimum` is 4 therefore never attacks inside a short cap
# — so this recipe fails on its own vacuity gate ("2 AI seat-match(es)
# never attacked anything"), correctly and confusingly. `clash` starts
# five squads a seat, which clears the highest threshold that ships.
#
# The gate is right and neither side of it should be tuned to fit the
# other: a seat that never committed proves nothing about what it would
# have aimed at, and a difficulty must not be watered down to suit a
# harness. This is CLAUDE.md's standing "when the opening changes, every
# timing tuned against the old one is stale" rule arriving from a new
# direction — the opening a HARNESS hands out is an opening too.
[doc("Teamed all-AI matches that fail if an AI attacks its own ally (#119)")]
test-ai-teams MATCHES="3" SECONDS="90" AI="4" TEAMS="2" SCENARIO="siege" PROFILES="": _import
    #!/usr/bin/env bash
    set -euo pipefail
    bash recipe-arg.sh int MATCHES "{{MATCHES}}"
    bash recipe-arg.sh int SECONDS "{{SECONDS}}"
    bash recipe-arg.sh int AI "{{AI}}"
    bash recipe-arg.sh int TEAMS "{{TEAMS}}"
    # Host admission gate (D-20260818-dev-work-is-admitted-against-a-host-budget).
    # Waits for room on the machine every other agent is also using. $$ is
    # THIS recipe's shell and the lock is stamped with it — a lock stamped
    # with anything shorter-lived is reaped while its job still runs.
    gate="$(bash host-gate.sh acquire heavy 'test-ai-teams' $$)"
    export EDOTMW_GATE_HELD="$gate"
    trap 'bash host-gate.sh release "$gate"' EXIT INT TERM
    mkdir -p "{{artifacts_dir}}"
    log="{{artifacts_dir}}/test-ai-teams.log"
    : > "$log"

    profiles="{{PROFILES}}"
    # How many difficulties were ASKED for, so the verdict can tell "one
    # profile played because one was wanted" from "one played because the
    # rest were lost on the way to a seat".
    wanted_profiles=$(printf '%s' "$profiles" | tr ',' '\n' | grep -c '[^[:space:]]' || true)
    echo "test-ai-teams: {{MATCHES}} matches, {{AI}} AI across {{TEAMS}} teams, scenario={{SCENARIO}}, profiles=${profiles:-<default>}, {{SECONDS}}s cap, map=ladder"
    for i in $(seq 1 {{MATCHES}}); do
        # A different seed per match, for the reason the ladder gives: the
        # same seed every time measures one world repeatedly. Here it is
        # load-bearing rather than hygienic — see the header.
        if [ "{{runtime}}" = "docker" ]; then
            docker compose -p {{compose_project}} run --rm --no-deps server \
                --headless --path . server.tscn -- \
                --map=res://maps/ladder.tres --lobby=0 --players=0 \
                --ai={{AI}} --ai-teams={{TEAMS}} --ai-profiles="$profiles" --scenario={{SCENARIO}} \
                --seed=$i --run-seconds={{SECONDS}} \
                >> "$log" 2>&1 || true
        else
            godot="{{native_godot}}"; [ -x "$godot" ] || godot="{{native_godot}}.exe"
            "$godot" --headless --path . server.tscn -- \
                --map=res://maps/ladder.tres --lobby=0 --players=0 \
                --ai={{AI}} --ai-teams={{TEAMS}} --ai-profiles="$profiles" --scenario={{SCENARIO}} \
                --seed=$i --run-seconds={{SECONDS}} \
                >> "$log" 2>&1 || true
        fi
        printf '.'
    done
    echo

    # Same scan the ladder runs, and for the same reason: an average — or
    # a zero — cannot report a fault, and a push_error nobody reads is how
    # an AI played a whole milestone without ever being told how strong
    # its own squads were.
    if grep -Eq '(^|\| *)(ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING):' "$log"; then
        echo "test-ai-teams: FAILED — engine diagnostics during the match:" >&2
        grep -EIn '(^|\| *)(ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING):' "$log" >&2 | head -20
        exit 1
    fi

    # ASSERT THE MATCHES HAPPENED before reading a statistic off them —
    # the ladder spent three milestones reporting matches that never left
    # the lobby as draws, and every gate below is satisfied vacuously by a
    # match that was never played.
    started=$(grep -c '^server: match started' "$log" || true)
    if [ "$started" -lt "{{MATCHES}}" ]; then
        echo "test-ai-teams: FAILED — only $started of {{MATCHES}} matches left the lobby. See $log." >&2
        exit 1
    fi

    awk -v want_teams={{TEAMS}} -v want_matches={{MATCHES}} -v want_profiles="$wanted_profiles" '
        /SIM_TEAMS/ {
            markers++
            fields = split($0, f, /[ ,]+/)
            for (i = 1; i <= fields; i++) {
                if (f[i] ~ /^[0-9]+=[0-9]+$/) {
                    split(f[i], kv, "=")
                    if (kv[2] + 0 > 0) sides[kv[2]] = 1
                    else teamless_in_sim++
                }
            }
        }
        /AI_STATS/ {
            match($0, /player=([0-9]+)/, p)
            match($0, / team=([0-9]+)/, t)
            match($0, /profile=([a-z_]+)/, pr)
            match($0, /allies_seen=([0-9]+)/, al)
            match($0, /ally_objectives=([0-9]+)/, ao)
            match($0, /attacks=([0-9]+)/, at)
            who = p[1]
            if (!(who in n)) order[++seats] = who
            n[who]++
            team[who] = t[1] + 0
            prof[who] = pr[1]
            if (pr[1] == "") profileless++
            else played_profile[pr[1]] = 1
            allies[who] += al[1]; attacks[who] += at[1]; ally_obj[who] += ao[1]
            if (t[1] + 0 == 0) teamless++
            # Per SEAT PER MATCH, not per seat: an AI that saw an ally in
            # one world and none in another had a world in which its zero
            # proved nothing, and the aggregate would hide it.
            if (al[1] + 0 == 0) blind++
            if (at[1] + 0 == 0) idle++
            ally_obj_total += ao[1]
        }
        END {
            fail = 0
            if (seats == 0) {
                print "  FAILED: no AI_STATS lines — no AI played"
                print "test-ai-teams: FAILED"
                exit 1
            }
            for (i = 1; i <= seats; i++) {
                who = order[i]
                printf "  player %-5s ai=%-11s team=%-2d matches=%-2d allies_seen~%.1f attacks=%-3d ally_objectives=%d\n",
                    who, (prof[who] == "" ? "?" : prof[who]), team[who], n[who],
                    allies[who]/n[who], attacks[who], ally_obj[who]
            }
            side_count = 0
            for (s in sides) side_count++
            if (markers < want_matches) {
                printf "  FAILED: %d of %d matches printed no SIM_TEAMS — the simulation was never handed the seats sides\n", want_matches - markers, want_matches
                fail = 1
            } else if (side_count != want_teams || side_count < 2) {
                printf "  FAILED: the simulation knows %d side(s); %d were asked for, and a teamed match needs at least 2\n", side_count, want_teams
                fail = 1
            } else if (teamless_in_sim > 0) {
                printf "  FAILED: %d seat(s) reached the simulation on team 0, which is FREE-FOR-ALL and not a side\n", teamless_in_sim
                fail = 1
            } else {
                printf "  the simulation knows %d sides, in all %d matches\n", side_count, markers
            }
            if (teamless > 0) {
                printf "  FAILED: %d AI seat-match(es) are on no team — nothing allied was exercised there\n", teamless
                fail = 1
            }
            if (blind > 0) {
                printf "  FAILED: %d AI seat-match(es) never saw an ally — ally_objectives=0 proves nothing there\n", blind
                fail = 1
            }
            if (idle > 0) {
                printf "  FAILED: %d AI seat-match(es) never attacked anything — an AI that picked no objective cannot have picked a bad one\n", idle
                fail = 1
            }
            # A difficulty that is real in a unit test and lost on the way
            # to a seat would leave every profile-shaped assertion in the
            # estate passing while every AI played the same way
            # (D-20260818-ai-profiles-are-data). This is the only place a
            # real match says otherwise.
            if (profileless > 0) {
                printf "  FAILED: %d AI seat-match(es) reported no profile at all — the difficulty never reached the seat\n", profileless
                fail = 1
            }
            distinct = 0
            for (k in played_profile) distinct++
            if (want_profiles > 1 && distinct < 2) {
                printf "  FAILED: %d difficulties were dealt and only %d reached the table — a pairing that never happened\n", want_profiles, distinct
                fail = 1
            } else if (distinct > 0) {
                line = ""
                for (k in played_profile) line = line (line == "" ? "" : ", ") k
                printf "  difficulties that actually played: %s\n", line
            }
            if (ally_obj_total > 0) {
                printf "  FAILED: %d attack objective(s) landed on a friend — #83 is back\n", ally_obj_total
                fail = 1
            }
            if (fail) { print "test-ai-teams: FAILED"; exit 1 }
            printf "test-ai-teams: VERDICT clean over %d matches — every seat teamed, saw an ally, attacked, and aimed at no friend\n", want_matches
        }
    ' "$log"
