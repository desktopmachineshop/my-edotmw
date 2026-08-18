#!/usr/bin/env bash
# The cross-worktree admission gate
# (D-20260818-dev-work-is-admitted-against-a-host-budget).
#
# Every agent's heavy recipe passes through here before it runs, and
# waits if the machine has no room. host-budget.sh decides whether there
# is room; this script decides who is holding what, waits, and cleans up
# after holders that died.
#
# WHERE THE STATE LIVES, and why that is not a D-095 breach. The lock
# directory is OUTSIDE every worktree (~/.edotmw/gate), because it is the
# one piece of state that must be shared by construction — a per-worktree
# gate would gate nothing. D-095 forbids a worktree touching another
# INSTANCE'S CONTAINERS; this touches nobody's containers, and its
# reaper keys on process liveness alone. It cannot stop, remove or even
# name another agent's docker objects.
#
#   host-gate.sh acquire CLASS LABEL   block until admitted; print token
#   host-gate.sh release TOKEN         give the slot back (idempotent)
#   host-gate.sh status                who holds what, right now
#   host-gate.sh reap                  drop holders whose process is gone
#
# Environment:
#   EDOTMW_NO_GATE=1        admit everything immediately (documented off
#                           switch; `just doctor` reports when it is set)
#   EDOTMW_GATE_DIR=<dir>   where the locks live
#   EDOTMW_GATE_TIMEOUT=<s> how long to wait before failing LOUDLY
#   EDOTMW_GATE_HELD=<tok>  set automatically; see re-entrancy below
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
budget="$here/host-budget.sh"

gate_dir="${EDOTMW_GATE_DIR:-$HOME/.edotmw/gate}"
mutex="$gate_dir/.admit"
poll_s="${EDOTMW_GATE_POLL:-5}"
say_every="${EDOTMW_GATE_SAY_EVERY:-15}"
timeout_s="${EDOTMW_GATE_TIMEOUT:-1800}"
# A holder older than this is reaped even if its pid still looks alive.
# Purely a backstop against a pid the reaper cannot see across MSYS
# installs — generous on purpose, and it always prints when it fires.
max_hold_s="${EDOTMW_GATE_MAX_HOLD:-7200}"

instance="$(bash "$here/instance-id.sh" name 2>/dev/null || echo unknown)"

now() { date +%s; }

# --- holders ----------------------------------------------------------
# One file per holder: <class>.<pid>.<instance>.lock, key=value inside.
# The filename carries the class and pid so a reap needs no parsing to
# find candidates, and the body carries everything a human wants to read
# when they are told what they are waiting for.

holder_files() { ls "$gate_dir"/*.lock 2>/dev/null || true; }

field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

alive() {
    local pid="$1"
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null
}

# Drop holders whose process is gone. This is the failure mode that would
# otherwise wedge the whole machine: an agent killed mid-run leaves a
# lock nobody will ever release. The same shape is already visible on
# this host in another form — five containers from other instances found
# sitting Exited for up to 42 hours, despite a teardown-scoped design.
reap() {
    local f pid started age reaped=0
    for f in $(holder_files); do
        pid="$(field "$f" pid)"
        started="$(field "$f" started)"
        age=$(( $(now) - ${started:-0} ))
        if ! alive "$pid"; then
            rm -f "$f"
            echo "host-gate: reaped $(basename "$f") — pid $pid is gone" >&2
            reaped=$((reaped + 1))
        elif [ "${started:-0}" -gt 0 ] && [ "$age" -gt "$max_hold_s" ]; then
            rm -f "$f"
            echo "host-gate: reaped $(basename "$f") — held ${age}s, past the ${max_hold_s}s backstop" >&2
            reaped=$((reaped + 1))
        fi
    done
    # The admission mutex is a directory, so it can be stranded the same
    # way. It is only ever held for milliseconds; a minute is already
    # pathological.
    if [ -d "$mutex" ]; then
        local m; m="$(cat "$mutex/at" 2>/dev/null || echo 0)"
        if [ $(( $(now) - m )) -gt 60 ]; then
            rm -rf "$mutex"
            echo "host-gate: broke a stranded admission mutex" >&2
        fi
    fi
    return 0
}

charged_mb() {
    local f total=0 c
    for f in $(holder_files); do
        c="$(field "$f" cost_mb)"
        total=$(( total + ${c:-0} ))
    done
    echo "$total"
}

gpu_held_by() {
    local f
    for f in $(holder_files); do
        if [ "$(field "$f" class)" = "gpu" ]; then
            echo "$(field "$f" instance) ($(field "$f" label))"
            return 0
        fi
    done
    return 1
}

# Who to name when we tell a human why they are waiting. The longest-held
# job is the one they actually care about.
blocking_holder() {
    local f best="" best_started=""
    for f in $(holder_files); do
        local s; s="$(field "$f" started)"
        if [ -z "$best_started" ] || [ "${s:-0}" -lt "$best_started" ]; then
            best_started="${s:-0}"; best="$f"
        fi
    done
    [ -n "$best" ] || return 1
    echo "$(field "$best" class) job in $(field "$best" instance) ($(field "$best" label))"
}

# --- the admission mutex ---------------------------------------------
# mkdir is the portable atomic test-and-set, and unlike flock it works
# the same on the Windows filesystem this repo is actually driven from.
enter() {
    local waited=0
    while ! mkdir "$mutex" 2>/dev/null; do
        sleep 0.2
        waited=$((waited + 1))
        if [ "$waited" -gt 150 ]; then reap; waited=0; fi
    done
    now > "$mutex/at" 2>/dev/null || true
}

leave() { rm -rf "$mutex" 2>/dev/null || true; }

# --- acquire ----------------------------------------------------------
#
# OWNER_PID is the process the slot belongs to — the RECIPE's shell, not
# this script's. Getting that wrong is not a small bug: `acquire` exits
# the instant it returns a token, so a lock stamped with this script's
# own $$ is stamped with a pid that is already dead, and the very next
# reap deletes a live holder. Recipes pass their own $$; $PPID is only a
# fallback for a caller that forgot, and command substitution makes it
# unreliable enough that the justfile always passes it explicitly.
acquire() {
    local class="${1:-}" label="${2:-unlabelled}" owner="${3:-${EDOTMW_GATE_OWNER_PID:-$PPID}}"
    [ -n "$class" ] || { echo "host-gate: acquire needs a class" >&2; return 2; }
    bash "$budget" cost "$class" >/dev/null || return 2

    if [ "$class" = "free" ] || [ "${EDOTMW_NO_GATE:-0}" = "1" ]; then
        echo "ungated"
        return 0
    fi

    # RE-ENTRANCY. Recipes call each other — test-load calls up, then
    # run-bots — and each would otherwise queue behind the gate its own
    # parent is holding, which is a deadlock the parent can never clear.
    # A child inherits EDOTMW_GATE_HELD through the environment and takes
    # the slot its ancestor already paid for.
    if [ -n "${EDOTMW_GATE_HELD:-}" ]; then
        echo "inherited"
        return 0
    fi

    mkdir -p "$gate_dir"
    local token="$gate_dir/$class.$owner.$instance.lock"
    local start; start="$(now)"
    local last_said=0

    while :; do
        enter
        reap
        local charged; charged="$(charged_mb)"
        local why=""

        if [ "$class" = "gpu" ] && gpu_held_by >/dev/null; then
            why="the GPU is held by $(gpu_held_by) — there is only one"
        elif ! bash "$budget" fits "$class" "$charged"; then
            why="not enough memory: $(bash "$budget" explain "$class" "$charged")"
        fi

        if [ -z "$why" ]; then
            {
                echo "pid=$owner"
                echo "class=$class"
                echo "cost_mb=$(bash "$budget" cost "$class")"
                echo "instance=$instance"
                echo "label=$label"
                echo "started=$(now)"
            } > "$token"
            leave
            local waited=$(( $(now) - start ))
            if [ "$waited" -gt 0 ]; then
                echo "host-gate: admitted $class ($label) after ${waited}s" >&2
            fi
            echo "$token"
            return 0
        fi
        leave

        local waited=$(( $(now) - start ))
        if [ "$waited" -ge "$timeout_s" ]; then
            # Fail LOUDLY rather than proceeding anyway. CLAUDE.md's
            # oldest rule is that a recipe must never report success for
            # something that did not run — and quietly ignoring the gate
            # under load is the version of that which breaks the host.
            echo "host-gate: TIMEOUT after ${waited}s waiting for a $class slot — $why" >&2
            echo "host-gate: nothing was run. Re-run when the host is quieter, or set EDOTMW_NO_GATE=1 to override deliberately." >&2
            return 1
        fi
        if [ $(( waited - last_said )) -ge "$say_every" ] || [ "$last_said" -eq 0 ]; then
            # A silent wait is indistinguishable from a hang — which is
            # exactly how M10's five seconds of terrain meshing got
            # reported as a dead server. Say what we are waiting for.
            local blocker; blocker="$(blocking_holder || echo 'nothing — the machine itself is short')"
            echo "host-gate: waiting ${waited}s for a $class slot ($label) — $why; behind $blocker" >&2
            last_said="$waited"
        fi
        sleep "$poll_s"
    done
}

release() {
    local token="${1:-}"
    case "$token" in
        ""|ungated|inherited) return 0 ;;
    esac
    rm -f "$token" 2>/dev/null || true
    return 0
}

status() {
    mkdir -p "$gate_dir"
    reap
    bash "$budget" report
    local f n=0
    for f in $(holder_files); do
        n=$((n + 1))
        printf 'host-gate: HELD %-6s %-32s %-24s pid=%-8s %ss\n' \
            "$(field "$f" class)" "$(field "$f" instance)" "$(field "$f" label)" \
            "$(field "$f" pid)" "$(( $(now) - $(field "$f" started) ))"
    done
    echo "host-gate: $n holder(s), $(charged_mb) MB charged, dir $gate_dir"
    if [ "${EDOTMW_NO_GATE:-0}" = "1" ]; then
        echo "host-gate: WARNING EDOTMW_NO_GATE=1 — nothing is being gated"
    fi
}

case "${1:-status}" in
    acquire) shift; acquire "$@" ;;
    release) shift; release "$@" ;;
    reap)    mkdir -p "$gate_dir"; reap ;;
    charged) mkdir -p "$gate_dir"; reap; charged_mb ;;
    status)  status ;;
    *)
        echo "usage: host-gate.sh {acquire CLASS LABEL|release TOKEN|status|reap|charged}" >&2
        exit 2 ;;
esac
