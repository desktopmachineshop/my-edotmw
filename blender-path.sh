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
# GUI needs the real application.
#
# **This repo does not install that application and does not manage it.** It is
# an ordinary desktop program: install it from blender.org, winget, brew or
# your package manager, exactly as you would if this project did not exist.
# Nothing is downloaded into tools/ and there is no bootstrap recipe. Models
# are rebuilt rarely, and a standard desktop tool does not want a
# repo-pinned private copy of itself.
#
# The version is therefore only CHECKED, never enforced. `check` warns when the
# installed Blender is a different series from the `bpy` wheel that bakes,
# because the mesh API and the glTF exporter do move between releases — but it
# warns and continues, since looking at a model in the Blender you happen to
# have is a perfectly reasonable thing to do.
#
# ## Resolution order, most explicit first
#
#   1. $EDOTMW_BLENDER          — the owner naming one outright
#   2. the platform's usual install locations
#   3. `blender` on PATH
#   4. tools/blender/blender    — a portable build, if you chose to drop one
#                                 there yourself; nothing here creates it
#
# 2 and 3 are the normal case: an ordinary install, found without configuring
# anything. 1 exists for a machine with several Blenders on it.
#
# Usage:
#   blender-path.sh find      absolute path of the Blender to launch (exit 1 if none)
#   blender-path.sh version   its version string, e.g. 4.5.12
#   blender-path.sh check     compare that against .blender-version; warns on stderr
#   blender-path.sh explain   everything above, for `just doctor`
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pinned="$(tr -d ' \r\n' < "$here/.blender-version")"
# Blender publishes by MINOR series (Blender4.5/) and names the file by the
# full patch version, so both halves of the pin are load-bearing.
series="$(echo "$pinned" | cut -d. -f1,2)"

_candidates() {
    [ -n "${EDOTMW_BLENDER:-}" ] && echo "$EDOTMW_BLENDER"
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
    # Last, and only if someone unpacked one here by hand. Nothing in this
    # repo puts a Blender in tools/.
    echo "$here/tools/blender/blender"
    echo "$here/tools/blender/blender.exe"
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

_install_hint() {
    # Where a person gets Blender on this platform. Guidance only — nothing
    # here downloads or installs anything, by design (see the header).
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            echo "  winget install BlenderFoundation.Blender"
            echo "  or the installer from https://www.blender.org/download/" ;;
        Darwin)
            echo "  brew install --cask blender"
            echo "  or the .dmg from https://www.blender.org/download/" ;;
        *)
            echo "  your package manager (apt/dnf/pacman), or:"
            echo "  snap install blender --classic"
            echo "  or the tarball from https://www.blender.org/download/" ;;
    esac
    echo
    echo "  Blender $pinned matches the bpy wheel that bakes generated/, but any"
    echo "  recent 4.x opens the models fine — the version is checked, not enforced."
    echo "  If you keep several, name one: export EDOTMW_BLENDER=/path/to/blender"
}

case "${1:-explain}" in
    find)
        if ! _find; then
            cat >&2 <<EOF
FAIL: no Blender application found.

  Looked at: \$EDOTMW_BLENDER, this platform's usual install locations,
  PATH, and tools/blender/.

  Blender is an ordinary desktop application and this repo deliberately
  does not install or manage one. Install it however you normally would:

$(_install_hint)

  Note this is NOT \`just bootstrap-art\`, which installs the bpy WHEEL.
  The wheel bakes assets and has no window; this needs the application.
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
            *) echo "NOTE: Blender $found at $path; the bpy wheel that bakes is" \
                    "$pinned. Fine for looking and shaping — but BAKE with" \
                    "\`just build-assets\`, not from a different Blender." >&2 ;;
        esac
        echo "$found" ;;
    install-hint) _install_hint ;;
    explain)
        echo "wheel pin: $pinned  (.blender-version) — what bakes generated/"
        if path="$(_find 2>/dev/null)"; then
            echo "app:       $path  ($(_version "$path"))"
        else
            echo "app:       NOT FOUND — install Blender normally; see 'install-hint'"
        fi
        venv="$here/tools/blender-venv"
        py="$venv/bin/python"; [ -x "$py" ] || py="$venv/Scripts/python.exe"
        if [ -x "$py" ]; then
            echo "wheel:     $("$py" -c 'import bpy; print(bpy.app.version_string)' 2>/dev/null || echo 'present, not importable')"
        else
            echo "wheel:     NOT INSTALLED — just bootstrap-art (only asset builds need it)"
        fi
        ;;
    *)
        echo "usage: blender-path.sh {find|version|check|install-hint|explain}" >&2
        exit 2 ;;
esac
