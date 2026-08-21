#!/usr/bin/env bash
# THE definition of where the Blender APPLICATION is
# (D-20260821-the-blender-gui-is-a-window-on-the-generators).
#
# `instance-id.sh` is the one definition of this checkout's identity and
# `host-budget.sh` the one definition of how much machine dev work may use.
# This is the same shape for a third thing nothing else may re-derive: which
# Blender binary `just blender-gui` launches, and whether it matches the
# `bpy` wheel that actually bakes `generated/`.
#
# ## The wheel and the application are two different programs
#
# `just bootstrap-art` installs `bpy` from PyPI. That is Blender's Python
# module with the window manager compiled out — there is no flag that opens a
# window on it, and `just build-assets` neither needs nor wants one. Seeing the
# GUI needs the real application, which is a separate ~300 MB download that
# `just bootstrap-blender-gui` fetches into tools/.
#
# They must be the SAME version. The mesh API, the glTF exporter and the EXR
# writer all move between releases, so a model shaped in one and baked by the
# other is only accidentally the same model. `check` below is what says so,
# and it warns rather than refusing: looking at a model in the wrong Blender
# is a reasonable thing to do knowingly, and being unable to look at all
# because a point release drifted is not.
#
# ## Resolution order, most explicit first
#
#   1. $EDOTMW_BLENDER          — the owner naming one outright
#   2. tools/blender/blender    — what bootstrap-blender-gui installs
#   3. the platform's usual install locations
#   4. `blender` on PATH
#
# A machine that already has Blender installed should not be made to download
# a second copy, which is why 3 and 4 exist; a worktree that wants a specific
# one must be able to say so, which is why 1 does.
#
# Usage:
#   blender-path.sh find      absolute path of the Blender to launch (exit 1 if none)
#   blender-path.sh version   its version string, e.g. 4.5.12
#   blender-path.sh check     compare that against .blender-version; warns on stderr
#   blender-path.sh asset     the download file name for this platform
#   blender-path.sh url       where bootstrap-blender-gui fetches it from
#   blender-path.sh explain   everything above, for `just doctor`
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pinned="$(tr -d ' \r\n' < "$here/.blender-version")"
# Blender publishes by MINOR series (Blender4.5/) and names the file by the
# full patch version, so both halves of the pin are load-bearing.
series="$(echo "$pinned" | cut -d. -f1,2)"

_candidates() {
    [ -n "${EDOTMW_BLENDER:-}" ] && echo "$EDOTMW_BLENDER"
    echo "$here/tools/blender/blender"
    echo "$here/tools/blender/blender.exe"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            # Git Bash sees the Windows filesystem at /c. Newest first, so a
            # machine with several installed gets the one most likely to match.
            for d in "/c/Program Files/Blender Foundation"/Blender*; do
                echo "$d/blender.exe"
            done | sort -rV
            ;;
        Darwin)
            echo "/Applications/Blender.app/Contents/MacOS/Blender"
            ;;
        *)
            echo "/usr/local/bin/blender"
            echo "/usr/bin/blender"
            echo "/snap/bin/blender"
            ;;
    esac
    command -v blender 2>/dev/null || true
}

_find() {
    while read -r candidate; do
        [ -n "$candidate" ] || continue
        [ -x "$candidate" ] || continue
        # Reject the venv's python-only bpy if someone points EDOTMW_BLENDER at
        # it: it exits 0 on --version and then cannot open a window, which is a
        # confusing way to discover the distinction this file exists to make.
        case "$candidate" in *blender-venv*) continue ;; esac
        echo "$candidate"
        return 0
    done < <(_candidates)
    return 1
}

_version() {
    # `blender --version` prints "Blender 4.5.12 LTS" plus a build block.
    "$1" --version 2>/dev/null | head -n 1 | awk '{print $2}'
}

_asset() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "blender-${pinned}-windows-x64.zip" ;;
        Darwin)
            if [ "$(uname -m)" = "arm64" ]; then
                echo "blender-${pinned}-macos-arm64.dmg"
            else
                echo "blender-${pinned}-macos-x64.dmg"
            fi ;;
        *) echo "blender-${pinned}-linux-x64.tar.xz" ;;
    esac
}

case "${1:-explain}" in
    find)
        if ! _find; then
            cat >&2 <<EOF
FAIL: no Blender application found.

  Looked at: \$EDOTMW_BLENDER, tools/blender/, the usual install
  locations for this platform, and PATH.

  Either:  just bootstrap-blender-gui      (downloads $(_asset))
  or:      export EDOTMW_BLENDER=/path/to/blender

  Note this is NOT the same thing as \`just bootstrap-art\`, which installs
  the bpy wheel. The wheel bakes assets and has no GUI; this needs the
  application. Both should be $pinned.
EOF
            exit 1
        fi ;;
    version)
        _version "$(_find)" ;;
    check)
        path="$(_find)"
        found="$(_version "$path")"
        case "$found" in
            "$series"*) ;;
            *) echo "WARNING: Blender $found at $path, but this project pins" \
                    "$pinned. Shape it here if you like, but BAKE with" \
                    "\`just build-assets\` (bpy $pinned)." >&2 ;;
        esac
        echo "$found" ;;
    asset) _asset ;;
    url)   echo "https://download.blender.org/release/Blender${series}/$(_asset)" ;;
    install-hint)
        # Printed by `just bootstrap-blender-gui` when it will not install
        # unattended. It lives HERE rather than in the recipe because it names
        # a platform install path, and this file is the only one allowed to
        # know where Blender lives — tests/test_blender_gui.gd fails if the
        # justfile learns one.
        case "$(uname -s)" in
            Darwin)
                echo "macOS ships Blender as a .dmg, which this recipe will not mount"
                echo "unattended. Install it from:"
                echo "  https://download.blender.org/release/Blender${series}/$(_asset)"
                echo "then point this checkout at it:"
                echo "  export EDOTMW_BLENDER=/Applications/Blender.app/Contents/MacOS/Blender" ;;
            *)
                echo "Set EDOTMW_BLENDER to a Blender $pinned binary, or unpack one" \
                     "into $here/tools/blender/." ;;
        esac ;;
    unattended)
        # Whether `bootstrap-blender-gui` can install without a human. Only
        # the .dmg cannot.
        case "$(_asset)" in *.dmg) exit 1 ;; *) exit 0 ;; esac ;;
    explain)
        echo "pinned:  $pinned  (.blender-version)"
        if path="$(_find 2>/dev/null)"; then
            echo "app:     $path  ($(_version "$path"))"
        else
            echo "app:     NOT FOUND — just bootstrap-blender-gui"
        fi
        venv="$here/tools/blender-venv"
        py="$venv/bin/python"; [ -x "$py" ] || py="$venv/Scripts/python.exe"
        if [ -x "$py" ]; then
            echo "wheel:   $("$py" -c 'import bpy; print(bpy.app.version_string)' 2>/dev/null || echo 'present, not importable')"
        else
            echo "wheel:   NOT INSTALLED — just bootstrap-art"
        fi
        echo "asset:   $(_asset)"
        ;;
    *)
        echo "usage: blender-path.sh {find|version|check|asset|url|install-hint|unattended|explain}" >&2
        exit 2 ;;
esac
