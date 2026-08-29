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
#   host-gate.sh reap                  drop holders whose work is gone
#   host-gate.sh occupancy             what is RUNNING, and who is charged
#
# Environment:
#   EDOTMW_NO_GATE=1        admit everything immediately (documented off
#                           switch; `just doctor` reports when it is set)
#   EDOTMW_GATE_DIR=<dir>   where the locks live
#   EDOTMW_GATE_TIMEOUT=<s> how long to wait before failing LOUDLY
#   EDOTMW_GATE_HELD=<tok>  set automatically; see re-entrancy below
#   EDOTMW_GATE_DOCKER_TIMEOUT=<s>  how long to wait on `docker ps`
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

# --- reconciling the ledger with the machine (#153) -------------------
#
# The gate's accounting unit is a PID. The thing that actually occupies
# this host is a CONTAINER, and the two part company: a launcher exits,
# the reaper drops its slot, and the container it started carries on.
# Measured 2026-08-18 — `edotmw-ao-my-edotmw-10-root-quick-test` Up 2
# hours against `host-gate: 0 holder(s), 0 MB charged` on a machine with
# 733 MB free and 2.9 GB of swap already in use.
#
# That failure INVERTS the feature rather than merely weakening it.
# Before the gate an overloaded host was obvious; now a stale container
# makes the ledger read empty, so the machine looks quiet at exactly the
# moment it is not. It is silent, too — everything then crawls instead of
# queueing, which reads as "the agents are stalled", and on the day it
# was found two sessions were misread as dead and one was killed
# mid-rebase.
#
# So: the reaper asks docker before it drops a dead holder's slot, and
# `occupancy` lists what is running beside what is charged, so a
# disagreement is LOUD. The invariant is the issue's own words — the
# gate's accounting and the machine's actual occupancy must be
# reconcilable.
#
# READ-ONLY, ALWAYS, and that is what keeps this inside D-095. `docker
# ps` is the only docker verb in this file; `test_host_budget.gd` fails
# if another one appears. Listing is not touching — `just reap-orphans`
# already reads exactly this list — and reconciling REQUIRES seeing every
# instance's containers, because the holder whose launcher died may
# belong to any of them. Nothing here removes, stops or restarts a
# container, this instance's included: telling a human which worktree to
# run `just down` in is as far as it goes.
#
# And it FAILS OPEN. No docker on PATH, a stopped daemon, a query that
# hangs: every one answers "nothing is running", so the gate degrades to
# exactly the behaviour it had before this existed. Wedging the whole
# machine because `docker ps` was slow would be a worse bug than the one
# being fixed.

docker_timeout_s="${EDOTMW_GATE_DOCKER_TIMEOUT:-10}"

_containers_cache=""
_containers_read=0

## Every RUNNING container this repo's recipes create, across all
## instances. One `docker ps` (~0.4 s measured) per reconciliation rather
## than per holder, so the cache is dropped at the top of each `reap` and
## each `occupancy` and never lives longer than one pass.
containers() {
    if [ "$_containers_read" -eq 0 ]; then
        _containers_read=1
        _containers_cache=""
        if command -v docker >/dev/null 2>&1; then
            if command -v timeout >/dev/null 2>&1; then
                _containers_cache="$(timeout "$docker_timeout_s" docker ps \
                    --filter 'name=^edotmw-' --format '{{.Names}}' 2>/dev/null | tr '\n' ' ' || true)"
            else
                _containers_cache="$(docker ps \
                    --filter 'name=^edotmw-' --format '{{.Names}}' 2>/dev/null | tr '\n' ' ' || true)"
            fi
        fi
    fi
    printf '%s' "$_containers_cache"
}

forget_containers() { _containers_read=0; }

## The running containers belonging to ONE instance.
##
## An exact name PREFIX, not the service-suffix regex `just reap-orphans`
## strips. Container names are `edotmw-<instance>-<whatever>` by
## construction, so the prefix is exact and cannot drift; the suffix list
## over there is already incomplete — the container in #153's own
## evidence ends `-quick-test`, which it does not name — and D-095's line
## is that a matching rule which can be wrong must not be the one that
## runs. `edotmw-a-b` does not match instance `a`, because what follows
## the prefix must be end-of-name or a dash.
containers_of() {
    local inst="$1" n
    for n in $(containers); do
        case "$n" in
            "edotmw-$inst"|"edotmw-$inst-"*) printf '%s ' "$n" ;;
        esac
    done
}

## Whether any holder's instance owns this container name.
held_by_a_holder() {
    local name="$1" f inst
    for f in $(holder_files); do
        inst="$(field "$f" instance)"
        [ -n "$inst" ] || continue
        case "$name" in
            "edotmw-$inst"|"edotmw-$inst-"*) return 0 ;;
        esac
    done
    return 1
}

# Drop holders whose process is gone. This is the failure mode that would
# otherwise wedge the whole machine: an agent killed mid-run leaves a
# lock nobody will ever release. The same shape is already visible on
# this host in another form — five containers from other instances found
# sitting Exited for up to 42 hours, despite a teardown-scoped design.
reap() {
    local f pid inst started age left
    forget_containers
    for f in $(holder_files); do
        pid="$(field "$f" pid)"
        inst="$(field "$f" instance)"
        started="$(field "$f" started)"
        age=$(( $(now) - ${started:-0} ))

        # The backstop first, and it still fires unconditionally: a slot
        # that can be held for ever is a machine nothing else can use.
        # What changed is that it may no longer go QUIET — a backstop
        # reap over a live container is the same under-count #153 is
        # about, arriving two hours later instead of immediately.
        if [ "${started:-0}" -gt 0 ] && [ "$age" -gt "$max_hold_s" ]; then
            left="$(containers_of "$inst")"
            rm -f "$f"
            if [ -n "$left" ]; then
                echo "host-gate: reaped $(basename "$f") — held ${age}s, past the ${max_hold_s}s backstop," >&2
                echo "host-gate:   AND $inst is still running: $left" >&2
                echo "host-gate:   the ledger now UNDER-COUNTS this machine. Stop it with 'just down' in THAT worktree (D-095: never from here)." >&2
            else
                echo "host-gate: reaped $(basename "$f") — held ${age}s, past the ${max_hold_s}s backstop" >&2
            fi
            continue
        fi

        alive "$pid" && continue

        # #153: the launcher is gone and its WORK is not. Keep charging —
        # the memory is still resident whatever the process table says —
        # and say so once rather than every poll.
        left="$(containers_of "$inst")"
        if [ -n "$left" ]; then
            if [ "$(field "$f" orphaned)" != "1" ]; then
                echo "orphaned=1" >> "$f"
                echo "host-gate: $(basename "$f") — pid $pid is gone but $inst is still running: $left" >&2
                echo "host-gate:   keeping the slot charged; it is released when the container is." >&2
            fi
            continue
        fi

        rm -f "$f"
        echo "host-gate: reaped $(basename "$f") — pid $pid is gone, and $inst runs nothing" >&2
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

    # The other half of #153, and the cheap half. A recipe that hands its
    # slot back while its OWN containers are still up has just made the
    # ledger disagree with the machine, and the reaper above will never
    # see it — there is no holder left to reconcile.
    #
    # A REPORT, never a refusal: `just up` leaves a server running on
    # purpose and is paired with `just down`, so this is a true statement
    # about the host rather than a complaint about the recipe. Silent in
    # the ordinary case, because a recipe that tore its containers down
    # has nothing to list.
    forget_containers
    local left; left="$(containers_of "$instance")"
    if [ -n "$left" ]; then
        echo "host-gate: slot released, but $instance is still running: $left" >&2
        echo "host-gate:   the gate no longer counts it — 'just down' here when you are finished (#153)." >&2
    fi
    return 0
}


## What is RUNNING, and whether the ledger accounts for it (#153).
##
## Printed by `status`, and therefore by `just doctor` and
## `just host-status`, which is where people already look. A container
## with no holder is not necessarily wrong — `just up` leaves one on
## purpose — but it IS memory the admission rule cannot see, so it is
## said out loud instead of being discovered by a machine that crawls.
occupancy() {
    forget_containers
    local names; names="$(containers)"
    local n loose=0 total=0
    for n in $names; do
        total=$((total + 1))
        if held_by_a_holder "$n"; then
            echo "host-gate: RUNNING $n — charged to a holder"
        else
            echo "host-gate: RUNNING $n — NOT charged to any holder"
            loose=$((loose + 1))
        fi
    done
    if [ "$total" -eq 0 ]; then
        echo "host-gate: no edotmw containers running — the ledger and the machine agree"
        return 0
    fi
    if [ "$loose" -gt 0 ]; then
        echo "host-gate: WARNING $loose of $total running container(s) are charged to nobody — the budget is" >&2
        echo "host-gate:   reading this machine as emptier than it is (#153). Each belongs to a worktree;" >&2
        echo "host-gate:   'just down' THERE is what stops it. Never from here (D-095)." >&2
    fi
    return 0
}

status() {
    mkdir -p "$gate_dir"
    reap
    bash "$budget" report
    local f n=0 note=
    for f in $(holder_files); do
        n=$((n + 1))
        note=""
        [ "$(field "$f" orphaned)" = "1" ] && note="  ORPHANED — launcher gone, container still up (#153)"
        printf 'host-gate: HELD %-6s %-32s %-24s pid=%-8s %ss%s\n' \
            "$(field "$f" class)" "$(field "$f" instance)" "$(field "$f" label)" \
            "$(field "$f" pid)" "$(( $(now) - $(field "$f" started) ))" "$note"
    done
    echo "host-gate: $n holder(s), $(charged_mb) MB charged, dir $gate_dir"
    occupancy
    if [ "${EDOTMW_NO_GATE:-0}" = "1" ]; then
        echo "host-gate: WARNING EDOTMW_NO_GATE=1 — nothing is being gated"
    fi
}

case "${1:-status}" in
    acquire) shift; acquire "$@" ;;
    release) shift; release "$@" ;;
    reap)      mkdir -p "$gate_dir"; reap ;;
    occupancy) mkdir -p "$gate_dir"; occupancy ;;
    charged) mkdir -p "$gate_dir"; reap; charged_mb ;;
    status)  status ;;
    *)
        echo "usage: host-gate.sh {acquire CLASS LABEL|release TOKEN|status|reap|occupancy|charged}" >&2
        exit 2 ;;
esac
