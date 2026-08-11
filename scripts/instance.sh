# THE definition of what an "instance" is (D-075). Sourced, not executed:
# every justfile recipe that touches docker starts by sourcing this, so
# there is exactly one place that decides which compose project and which
# host port a command belongs to.
#
# Why this exists: every recipe used to pin `-p edotmw` and port 4433, so
# two checkouts fought. `just down` in one worktree removed another's
# containers, a second `just up` could not bind the port, and — the
# expensive one — a run in worktree A silently reached a server started
# by worktree B while its own instrumentation printed nothing.
#
# An instance resolves to TWO things and deliberately no more:
#
#   EDOTMW_PROJECT   the compose project name  (container/network scoping)
#   EDOTMW_PORT      the published HOST udp port
#
# The container-INTERNAL port stays 4433 for everyone. Bots and the
# containerised client reach `server:4433` over their own project's
# network, so nothing inside the compose file needs to know about
# instances. Only the host publish and the native GUI client do.
#
# NOT scoped per instance: the import cache, artifacts/, replay files.
# Each worktree already has its own copy of those, and scoping them would
# move every documented path (artifacts/client-frame.png and friends) for
# no gain.

# Identity comes from the CHECKOUT, not from a flag someone has to
# remember. An agent working in a worktree is isolated whether it knows
# about any of this or not, which is the whole point: the failure mode
# being removed is precisely "forgot to pass the isolating argument".
#
# EDOTMW_INSTANCE overrides. Whether it was set is itself load-bearing —
# `down` and `nuke` refuse to tear down `dev` unless it was named
# EXPLICITLY, so a bare `just down` in the main checkout cannot kill the
# human's game.
if [ -n "${EDOTMW_INSTANCE:-}" ]; then
    EDOTMW_INSTANCE_EXPLICIT=1
else
    EDOTMW_INSTANCE_EXPLICIT=0
    _edotmw_dir="$(pwd)"
    case "$_edotmw_dir" in
        */.claude/worktrees/*)
            # .../.claude/worktrees/<name>[/...] -> test-<name>
            _edotmw_wt="${_edotmw_dir##*/.claude/worktrees/}"
            _edotmw_wt="${_edotmw_wt%%/*}"
            EDOTMW_INSTANCE="test-${_edotmw_wt}"
            ;;
        *)
            EDOTMW_INSTANCE="dev"
            ;;
    esac
    unset _edotmw_dir _edotmw_wt
fi

# A compose project name must be lowercase alphanumeric, dash or
# underscore. A worktree directory is not obliged to be any of those, so
# sanitise rather than emit an invalid project name later, far from here.
EDOTMW_INSTANCE="$(printf '%s' "$EDOTMW_INSTANCE" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
if [ -z "$EDOTMW_INSTANCE" ]; then
    echo "instance: could not derive a usable instance name from $(pwd)" >&2
    exit 1
fi

EDOTMW_PROJECT="edotmw-${EDOTMW_INSTANCE}"

# --- port registry ----------------------------------------------------
#
# Lives in $HOME, NOT in the repo. A registry inside a worktree cannot
# prevent a collision with a different worktree, which is the only
# collision that matters — so it has to be the one thing every checkout
# on this machine shares.
#
# dev is pinned to 4433: it is the port a human types, the one in every
# doc, and the default in client.gd and server.gd.
EDOTMW_PORT_BASE="${EDOTMW_PORT_BASE:-4434}"
EDOTMW_PORT_LAST="${EDOTMW_PORT_LAST:-4499}"
EDOTMW_REGISTRY="${EDOTMW_REGISTRY:-$HOME/.edotmw/ports}"

edotmw_port_of() {
    # Echo the port claimed by instance $1, or nothing if it has none.
    # Always succeeds: recipes run under `set -e`, where a function that
    # returns non-zero from inside a command substitution aborts the
    # whole recipe. "No claim yet" is an ordinary answer, not a failure.
    if [ -f "$EDOTMW_REGISTRY/by-name/$1" ]; then
        cat "$EDOTMW_REGISTRY/by-name/$1"
    fi
    return 0
}

edotmw_release_port() {
    # Drop instance $1's claim. Safe to call when it holds none.
    local name="$1" port
    port="$(edotmw_port_of "$name")"
    if [ -n "$port" ]; then
        rm -f "$EDOTMW_REGISTRY/by-port/$port"
    fi
    rm -f "$EDOTMW_REGISTRY/by-name/$name"
}

edotmw_claim_port() {
    # Reuse this instance's existing claim, or take the lowest free port.
    local name="$1" port p
    mkdir -p "$EDOTMW_REGISTRY/by-name" "$EDOTMW_REGISTRY/by-port"

    port="$(edotmw_port_of "$name")"
    if [ -n "$port" ]; then
        # Re-assert ownership of the by-port side. It can be missing if
        # somebody pruned the registry by hand, and a name claim with no
        # matching port claim would let a second instance take the same
        # port later.
        printf '%s\t%s\n' "$name" "$(pwd)" > "$EDOTMW_REGISTRY/by-port/$port"
        printf '%s' "$port"
        return 0
    fi

    for p in $(seq "$EDOTMW_PORT_BASE" "$EDOTMW_PORT_LAST"); do
        # noclobber makes create-if-absent atomic, which is the whole
        # concurrency story: two agents claiming at the same moment
        # cannot both win the same file, so they cannot both win the same
        # port. A lock file plus a check would have a window; this does
        # not.
        if ( set -o noclobber
             printf '%s\t%s\n' "$name" "$(pwd)" > "$EDOTMW_REGISTRY/by-port/$p"
           ) 2>/dev/null; then
            printf '%s' "$p" > "$EDOTMW_REGISTRY/by-name/$name"
            printf '%s' "$p"
            return 0
        fi
    done

    echo "instance: no free port in ${EDOTMW_PORT_BASE}-${EDOTMW_PORT_LAST}" >&2
    echo "          run 'just instances' — stale claims can be dropped with 'just instance-free <name>'" >&2
    return 1
}

if [ "$EDOTMW_INSTANCE" = "dev" ]; then
    EDOTMW_PORT=4433
else
    EDOTMW_PORT="$(edotmw_claim_port "$EDOTMW_INSTANCE")"
fi

export EDOTMW_INSTANCE EDOTMW_PROJECT EDOTMW_PORT EDOTMW_INSTANCE_EXPLICIT

# Auto-derivation trades away visibility; this line buys it back. Every
# recipe announces which instance it resolved BEFORE it does anything, so
# "which server was I even talking to" is never a question again — the
# question that cost a session to answer the last time it came up.
if [ "${EDOTMW_QUIET:-0}" != "1" ]; then
    echo "instance=$EDOTMW_INSTANCE project=$EDOTMW_PROJECT port=$EDOTMW_PORT"
fi
