#!/usr/bin/env bash
# The ONE definition of this checkout's dev-instance identity (D-095).
#
# Several Claude Code agents work this repo in parallel, each in its own
# git worktree, and each launches its own server and clients for the
# human to look at. Before D-095 they all shared one compose project
# name ("edotmw") and one UDP port (4433) — so any agent's `just down`
# removed every agent's containers, and a client could silently connect
# to whichever agent's server happened to hold 4433 (CLAUDE.md records a
# whole debugging session lost to exactly that).
#
# So: identity is derived from the git BRANCH (agent worktree branches
# are unique per session; the main checkout gets "main"), and the port
# is a stable hash of that identity into 20000-29999 — deliberately
# nowhere near the in-container default of 4433, so a hardcoded 4433
# that sneaks back in fails to connect instead of connecting to the
# wrong server.
#
# The justfile evaluates this script for its `instance`, `port` and
# `agent` values; nothing else may re-derive any of them. Overrides exist
# for the one case the isolation is deliberately broken — the human
# asking two checkouts to talk to each other:
#   EDOTMW_INSTANCE=<name>   share/override the instance name
#   EDOTMW_PORT=<port>       share/override the UDP port
#   EDOTMW_AGENT=0|1         override "is this an agent's worktree?"
set -euo pipefail

raw="${EDOTMW_INSTANCE:-}"
if [ -z "$raw" ]; then
    raw="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi
# Detached HEAD (or no git at all) falls back to the directory name,
# which for an agent worktree is still unique per session.
if [ -z "$raw" ] || [ "$raw" = "HEAD" ]; then
    raw="$(basename "$(pwd)")"
fi

# Sanitise into a valid docker compose project fragment: lowercase
# alphanumerics and single dashes, no leading/trailing dash. A branch
# like "claude/multi-agent-dev-isolation-d3c28e" becomes
# "claude-multi-agent-dev-isolation-d3c28e".
name="$(printf '%s' "$raw" \
    | tr 'A-Z' 'a-z' \
    | tr -c 'a-z0-9' '-' \
    | sed 's/--*/-/g; s/^-//; s/-$//')"
if [ -z "$name" ]; then
    echo "instance-id.sh: could not derive an instance name" >&2
    exit 1
fi

case "${1:-name}" in
    name)
        printf '%s\n' "$name"
        ;;
    port)
        if [ -n "${EDOTMW_PORT:-}" ]; then
            printf '%s\n' "$EDOTMW_PORT"
        else
            # cksum, not md5/sha: POSIX, present in Git Bash, and stable
            # across runs (bash's $RANDOM obviously is not, and hashing
            # must be deterministic so a client started tomorrow finds
            # the server started today).
            sum="$(printf '%s' "$name" | cksum | cut -d' ' -f1)"
            printf '%s\n' "$(( 20000 + (sum % 10000) ))"
        fi
        ;;
    agent)
        # Is this checkout a disposable AGENT worktree, or the human's
        # own? `quick-test` reads this to decide whether to launch the
        # dev build — D-077's sandbox mode with its cheats panel — since
        # an agent going straight into a quick launch is always
        # dev-testing and should not have to remember to ask.
        #
        # Stated as "which checkouts are NOT an agent's", deliberately.
        # This used to be a whitelist of agent branch prefixes
        # (claude-*) living in the justfile, and when the harness started
        # branching `ao/<project>/<session>` every agent worktree
        # silently resolved to "the human" and lost its dev tools with no
        # error at all (#89, D-20260817-recipe-args-are-positional). The
        # human's own checkout sits on the default branch: that set is
        # small, known, and does not change when a new agent harness
        # appears. A human working on a feature branch in their own
        # checkout gets the dev build too — visible, and one positional
        # argument to turn off, where the old failure was neither.
        if [ -n "${EDOTMW_AGENT:-}" ]; then
            if [ "$EDOTMW_AGENT" = "0" ]; then printf '0\n'; else printf '1\n'; fi
        else
            case "$name" in
                main|master) printf '0\n' ;;
                *)           printf '1\n' ;;
            esac
        fi
        ;;
    *)
        echo "usage: instance-id.sh [name|port|agent]" >&2
        exit 2
        ;;
esac
