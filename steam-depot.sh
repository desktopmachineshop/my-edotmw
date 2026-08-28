#!/usr/bin/env bash
# THE definition of what this game uploads to Steam, and where steamcmd is
# (D-20260828-a-depot-upload-is-validated-before-it-is-authenticated,
# #185, D-094 criterion 2).
#
# `instance-id.sh` is the one definition of this checkout's identity,
# `host-budget.sh` of how much machine dev work may use, `blender-path.sh`
# of where the Blender application is. This is the same shape for a fourth
# thing nothing else may re-derive: which files become which depot, which
# branch they go live on, and which steamcmd pushes them.
#
# ## Why a script and not a recipe body
#
# The same reason `recipe-arg.sh`, `instance-id.sh` and `gate-check.sh` are
# scripts: the test estate cannot reach a recipe body at all. Every rule
# here — a depot id that is not a number, a branch that would publish to
# the world, a build output that was never exported — is a rule that has
# to be watched failing before it is trusted, and `tests/test_steam_depot.gd`
# executes this file to do it.
#
# ## The credential seam, which is where this deliberately stops
#
# Nothing here has a Steam app id, a depot id or a login, because none of
# those exists yet: the app id comes from a Steamworks partner account and
# the app fee, and the depot ids are minted on the partner site (see
# `docs/status/m8-steam-depot.md` for the owner's one-time setup). They are
# read from the environment and refused loudly when absent or unusable,
# the way `cmd_args.gd` refuses an argument it cannot use.
#
# So the split this file is built around:
#
#   IDENTITY   app id, depot ids, branch. Not secret, but not known yet —
#              environment, validated here, printed in every plan.
#   CREDENTIAL the steamcmd login. Secret, never read by this file at all:
#              `validate`, `vdf` and `plan` are complete without one, and
#              only the `live` half of `just steam-upload` ever needs it.
#
# That split is the whole point. A dry run proves everything a real upload
# does except that Steam accepted it, so the first authenticated run is the
# only step that has not already been rehearsed.
#
# ## Resolution order for steamcmd, most explicit first
#
#   1. $EDOTMW_STEAMCMD    — the owner naming one outright
#   2. `steamcmd` on PATH
#   3. the platform's usual install locations
#   4. tools/steamcmd/steamcmd — a copy you dropped there yourself
#
# Like Blender (D-20260821), steamcmd is an ordinary tool this repo does
# NOT install: it self-updates on every run, it is licensed separately, and
# a repo-pinned private copy of a self-updating downloader is worse than
# none. `bootstrap.ps1`'s promise that a fresh clone installs nothing
# system-wide is unaffected — nothing here downloads anything.
#
# Usage:
#   steam-depot.sh validate            every rule, without auth; exit 1 and say why
#   steam-depot.sh vdf OUTDIR          write the app/depot VDFs; print their paths
#   steam-depot.sh plan                what a live upload would do, in full
#   steam-depot.sh find-steamcmd       absolute path (exit 1 if none)
#   steam-depot.sh explain             all of the above, for `just doctor`
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- the depot layout, which IS the committed part --------------------
#
# One row per depot: <key> <build subdirectory> <human description>. The
# subdirectory is `just export`'s own output path and nothing here may
# invent a second one — the two disagreeing would upload a stale binary
# with every number healthy, which is this project's most-repeated defect
# wearing a shipping label.
#
# WINDOWS CLIENT IS THE ONLY REQUIRED DEPOT, and that is D-088 rather than
# a simplification: the host runs the authoritative simulation in-process,
# so a tester installs a client and nothing else. The Linux server depot
# is included only when its id is set — opt-in, because `just export`
# already produces the binary and D-088's official-dedicated-later will
# want it, and because a depot nothing installs is the declared-and-unread
# family with an upload attached.
depot_keys() { echo "windows linux-server"; }

depot_subdir() {
    case "$1" in
        windows)      echo "windows" ;;
        linux-server) echo "linux-server" ;;
        *) return 1 ;;
    esac
}

depot_desc() {
    case "$1" in
        windows)      echo "Windows client" ;;
        linux-server) echo "Linux headless server" ;;
        *) return 1 ;;
    esac
}

depot_required() {
    case "$1" in
        windows) return 0 ;;
        *) return 1 ;;
    esac
}

## The environment variable holding a depot's id. Named per depot rather
## than indexed, so adding one is a visible edit here and in the docs
## instead of a number nobody can grep for.
depot_env() {
    case "$1" in
        windows)      echo "EDOTMW_STEAM_DEPOT_WINDOWS" ;;
        linux-server) echo "EDOTMW_STEAM_DEPOT_LINUX_SERVER" ;;
        *) return 1 ;;
    esac
}

depot_id() {
    local var; var="$(depot_env "$1")" || return 1
    eval "printf '%s' \"\${$var:-}\""
}

# --- the rest of the configuration ------------------------------------

build_dir="${EDOTMW_BUILD_DIR:-$here/build}"

app_id() { printf '%s' "${EDOTMW_STEAM_APP_ID:-}"; }

## The branch a build goes live on.
##
## `alpha` by default and NEVER `default`. On Steam, `default` is the
## branch every owner of the app gets automatically — setting a build live
## there is publishing, and D-087 is explicit that M8 is Steam-READY and
## not launched. That is a rule rather than a warning because the mistake
## is one word long, irreversible from here, and would be made by a person
## typing a branch name at midnight.
branch() { printf '%s' "${EDOTMW_STEAM_BRANCH:-alpha}"; }

## THE build version, read from the one place it is written down
## (project.godot's application/config/version — see build_version.gd and
## D-20260827-the-build-is-exported-from-one-version). Nothing here may
## compute a version of its own; the upload's description carries this so
## that "the installed build prints the version the recipe uploaded" is a
## comparison rather than a hope.
build_version() {
    grep -m1 '^config/version=' "$here/project.godot" 2>/dev/null | cut -d'"' -f2
}

is_number() {
    case "${1:-}" in
        ""|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# --- steamcmd ---------------------------------------------------------

_steamcmd_candidates() {
    [ -n "${EDOTMW_STEAMCMD:-}" ] && echo "$EDOTMW_STEAMCMD"
    command -v steamcmd 2>/dev/null || true
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            echo "/c/steamcmd/steamcmd.exe"
            echo "/c/Program Files (x86)/Steam/steamcmd.exe"
            ;;
        Darwin)
            echo "$HOME/Library/Application Support/Steam/steamcmd.sh"
            echo "/usr/local/bin/steamcmd"
            ;;
        *)
            echo "/usr/games/steamcmd"
            echo "$HOME/steamcmd/steamcmd.sh"
            ;;
    esac
    echo "$here/tools/steamcmd/steamcmd.sh"
    echo "$here/tools/steamcmd/steamcmd.exe"
}

find_steamcmd() {
    local c
    while read -r c; do
        [ -n "$c" ] || continue
        [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
    done <<EOF
$(_steamcmd_candidates)
EOF
    return 1
}

# --- validation -------------------------------------------------------
#
# Every rule a live upload depends on, checked WITHOUT authenticating and
# without steamcmd. Collected rather than short-circuited: an owner
# setting this up for the first time should learn everything that is
# wrong in one run, not one thing per run.

problems=""
note() { problems="${problems}  - $1
"; }

validate() {
    problems=""

    local app; app="$(app_id)"
    if [ -z "$app" ]; then
        note "EDOTMW_STEAM_APP_ID is not set. It is the app id from the Steamworks partner site (see docs/status/m8-steam-depot.md)."
    elif ! is_number "$app"; then
        note "EDOTMW_STEAM_APP_ID is \"$app\", which is not a number. Steam app ids are numeric, and a non-numeric one would be uploaded to app 0."
    fi

    local br; br="$(branch)"
    if [ -z "$br" ]; then
        note "EDOTMW_STEAM_BRANCH is empty. Set a branch, or leave it unset for the default 'alpha'."
    fi
    case "$br" in
        default|public|Default|Public)
            note "EDOTMW_STEAM_BRANCH is \"$br\", which is the branch EVERY owner of the app receives. D-087 says M8 is Steam-ready and NOT launched; use a private, password-protected branch."
            ;;
    esac

    local ver; ver="$(build_version)"
    if [ -z "$ver" ]; then
        note "project.godot has no application/config/version, so an upload could not be identified afterwards (see build_version.gd)."
    fi

    local key id sub any=0
    for key in $(depot_keys); do
        id="$(depot_id "$key")"
        sub="$(depot_subdir "$key")"
        if [ -z "$id" ]; then
            if depot_required "$key"; then
                note "$(depot_env "$key") is not set, and the $(depot_desc "$key") depot is the one a tester installs."
            fi
            continue
        fi
        if ! is_number "$id"; then
            note "$(depot_env "$key") is \"$id\", which is not a number."
            continue
        fi
        any=1
        if [ ! -d "$build_dir/$sub" ]; then
            note "$(depot_desc "$key") depot $id has no content: $build_dir/$sub does not exist. Run 'just export' first."
        elif [ -z "$(find "$build_dir/$sub" -type f -print -quit 2>/dev/null)" ]; then
            note "$(depot_desc "$key") depot $id has no content: $build_dir/$sub is empty. Run 'just export' first."
        fi
    done
    if [ "$any" -eq 0 ] && [ -n "$app" ]; then
        note "No depot ids are set at all, so there is nothing to upload."
    fi

    if [ -n "$problems" ]; then
        echo "steam-depot: this configuration cannot be uploaded:" >&2
        printf '%s' "$problems" >&2
        echo "steam-depot: nothing was sent. See docs/status/m8-steam-depot.md for the one-time setup." >&2
        return 1
    fi
    echo "steam-depot: OK — app $(app_id), branch $(branch), version $(build_version), $(_configured_depots | wc -w) depot(s)"
    return 0
}

_configured_depots() {
    local key
    for key in $(depot_keys); do
        [ -n "$(depot_id "$key")" ] && printf '%s ' "$key"
    done
}

# --- VDF generation ---------------------------------------------------
#
# Generated, not committed, and that is the one place this ticket departs
# from #185's wording ("app_build/depot_build VDF scripts, committed").
# A committed VDF has the app id and every depot id baked into it — which
# is precisely the identity that does not exist yet, so committing one
# would mean committing placeholders that a real run must remember to
# replace. The LAYOUT is committed, in this file, and the ids arrive from
# the environment at generation time. See the decision entry.
#
# Paths written into a VDF are absolute: steamcmd resolves a relative
# ContentRoot against its OWN working directory, which is wherever
# steamcmd happens to live rather than this repo.

## Windows steamcmd needs Windows paths. Git Bash gives us /c/... and
## `cygpath` is present in exactly the environment where that matters.
_native_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

vdf() {
    local outdir="${1:-}"
    [ -n "$outdir" ] || { echo "steam-depot: vdf needs an output directory" >&2; return 2; }
    validate >/dev/null || return 1

    mkdir -p "$outdir"
    local app ver br
    app="$(app_id)"; ver="$(build_version)"; br="$(branch)"

    local depots_block="" key id sub depot_file
    for key in $(_configured_depots); do
        id="$(depot_id "$key")"
        sub="$(depot_subdir "$key")"
        depot_file="$outdir/depot_build_$id.vdf"
        {
            echo '"DepotBuildConfig"'
            echo '{'
            echo "	\"DepotID\" \"$id\""
            echo "	\"ContentRoot\" \"$(_native_path "$build_dir/$sub")\""
            echo '	"FileMapping"'
            echo '	{'
            echo '		"LocalPath" "*"'
            echo '		"DepotPath" "."'
            echo '		"recursive" "1"'
            echo '	}'
            # Godot writes no .pdb, but an export template that ever does
            # would ship a debug database to players. Excluded by name so
            # it is a decision rather than an accident of what Godot
            # happens to emit this release.
            echo '	"FileExclusion" "*.pdb"'
            echo '	"FileExclusion" "*.debug"'
            echo '}'
        } > "$depot_file"
        depots_block="$depots_block		\"$id\" \"$(_native_path "$depot_file")\"
"
        # Progress on stderr, deliberately: STDOUT is the app_build path
        # and nothing else, so a caller can write
        # `app="$(steam-depot.sh vdf DIR)"` and hand it straight to
        # steamcmd. A helper that prints several paths to stdout is a
        # helper whose caller parses.
        echo "steam-depot: wrote $depot_file" >&2
    done

    local app_file="$outdir/app_build_$app.vdf"
    {
        echo '"appbuild"'
        echo '{'
        echo "	\"appid\" \"$app\""
        # The version, so a build on the partner site can be matched
        # against the binary a player is running. This is the ONE place
        # the two are tied together.
        echo "	\"desc\" \"my-edotmw $ver\""
        echo "	\"buildoutput\" \"$(_native_path "$outdir/output")\""
        echo "	\"contentroot\" \"$(_native_path "$build_dir")\""
        echo "	\"setlive\" \"$br\""
        # `preview 1` makes steamcmd do everything except transmit — the
        # STEAM-SIDE dry run, which still needs a login and is therefore
        # not what `just steam-upload dry` is. Left at 0 and named here so
        # the owner knows it exists once they have credentials.
        echo '	"preview" "0"'
        echo '	"local" ""'
        echo '	"depots"'
        echo '	{'
        printf '%s' "$depots_block"
        echo '	}'
        echo '}'
    } > "$app_file"
    mkdir -p "$outdir/output"
    printf '%s\n' "$app_file"
}

# --- the plan ---------------------------------------------------------

plan() {
    local app ver br key id sub
    app="$(app_id)"; ver="$(build_version)"; br="$(branch)"
    echo "steam-depot: my-edotmw ${ver:-<no version>}"
    echo "  app id   ${app:-<unset: EDOTMW_STEAM_APP_ID>}"
    echo "  branch   ${br} (private; never 'default' — D-087)"
    for key in $(depot_keys); do
        id="$(depot_id "$key")"
        sub="$(depot_subdir "$key")"
        if [ -z "$id" ]; then
            if depot_required "$key"; then
                printf '  depot    %-22s <unset: %s>\n' "$(depot_desc "$key")" "$(depot_env "$key")"
            else
                printf '  depot    %-22s not configured (optional)\n' "$(depot_desc "$key")"
            fi
            continue
        fi
        printf '  depot %-8s %-22s %s\n' "$id" "$(depot_desc "$key")" "$build_dir/$sub"
    done
    if steamcmd_path="$(find_steamcmd)"; then
        echo "  steamcmd $steamcmd_path"
    else
        echo "  steamcmd NOT FOUND — needed only for a live upload; set EDOTMW_STEAMCMD or put it on PATH"
    fi
    echo "  login    ${EDOTMW_STEAM_USER:-<unset: EDOTMW_STEAM_USER>} (live upload only; never read by this script)"
}

explain() {
    plan
    echo
    if validate; then
        echo "steam-depot: a live upload would run:"
        echo "    steamcmd +login \$EDOTMW_STEAM_USER +run_app_build <app_build.vdf> +quit"
    fi
}

case "${1:-explain}" in
    validate)      validate ;;
    vdf)           shift; vdf "$@" ;;
    plan)          plan ;;
    find-steamcmd) find_steamcmd ;;
    explain)       explain ;;
    *)
        echo "usage: steam-depot.sh {validate|vdf OUTDIR|plan|find-steamcmd|explain}" >&2
        exit 2 ;;
esac
