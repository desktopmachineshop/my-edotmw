#!/usr/bin/env bash
# THE definition of how much of this machine dev work may use
# (D-20260818-dev-work-is-admitted-against-a-host-budget).
#
# instance-id.sh answers "which instance am I?" so two agents cannot
# COLLIDE. This script answers "is there room for me right now?" so two
# agents cannot STARVE each other. It is the same rule and the same
# reason: ONE definition, and nothing anywhere may re-derive it.
#
# Why memory and not cores. Profiled 2026-08-18 on the owner's laptop
# (i5-13500H, 12C/16T, 15.6 GB) with 22 agent sessions live:
#
#   activity                 CPU mean/max     WSL VM growth
#   baseline (no dev work)     14% / 28%           -
#   test-unit (890 tests)      14% / 41%       +1,246 MB
#   test-load 4 60             18% / 98%       +1,240 MB
#   gen-terrain-preview        13% / 41%         +586 MB
#
# Only one activity ever approached the CPU ceiling, and it did so for
# seconds. Meanwhile free memory sat between 1.5 and 2.4 GB for the whole
# session — 85-90% utilised BEFORE any recipe runs — so ~1.25 GB per
# concurrent docker recipe is the number that decides whether the host
# thrashes. A gate on load average would admit exactly the jobs that then
# swap. GATE ON MEMORY.
#
# Note the two docker rows cost almost the SAME memory despite very
# different CPU and duration. The classes below therefore differ mostly
# in DURATION and in what they contend for (the single GPU), not in
# megabytes — which is why the per-class costs are close together and
# why `gpu` is exclusive rather than merely expensive.
#
# Overrides, for the one case the budget is deliberately broken — the
# human wanting a big run to go now:
#   EDOTMW_HOST_BUDGET_MB=<mb>   pretend this much memory is free
#   EDOTMW_HOST_RESERVE_MB=<mb>  change what is held back for the OS
#   EDOTMW_NO_GATE=1             admit everything, always (host-gate.sh)
set -euo pipefail

# --- what a class of work is expected to need ------------------------
#
# Rounded UP from the measurements above, because being wrong high costs
# a wait and being wrong low costs the whole machine.
#
#   gpu     a native GUI client or render benchmark. EXCLUSIVE machine-
#           wide: there is one integrated GPU (D-014/D-086), so two at
#           once is not a slowdown, it is two useless measurements.
#           The megabyte figure is an ESTIMATE, not a measurement —
#           profiling it would mean launching the game unprompted.
#   heavy   a long docker sim run: test-load, test-scenario, ai-ladder,
#           test-client, profile.
#   medium  a shorter docker run: test-unit, the gen-* previews,
#           build-assets.
#   free    costs nothing and is never gated. A teardown that queues
#           behind the thing it is tearing down is a deadlock wearing a
#           progress message.
cost_of() {
    case "${1:-}" in
        gpu)    echo 1500 ;;
        heavy)  echo 1500 ;;
        medium) echo 1300 ;;
        free)   echo 0 ;;
        *)      echo "host-budget.sh: unknown class '${1:-}' (want: gpu heavy medium free)" >&2; return 2 ;;
    esac
}

# Held back for Windows, the desktop and the agent sessions themselves.
# Swap was already 1.58 GB deep at rest when this was written, so the
# machine is not merely full, it is paging — do not spend the last of it.
reserve_mb() { echo "${EDOTMW_HOST_RESERVE_MB:-768}"; }

# --- reading the machine ---------------------------------------------
#
# /proc/meminfo exists under MSYS2 (Git Bash), which is how this repo is
# driven on Windows, and reads in ~18 ms — cheap enough for the gate to
# poll. Linux and MSYS2 disagree about what MemFree MEANS, so prefer
# MemAvailable wherever the kernel publishes it and fall back otherwise:
# under MSYS2 there is no MemAvailable and MemFree is already Windows'
# available-physical figure (verified against Win32_OperatingSystem's
# FreePhysicalMemory, 2,433 MB vs 2,489 MB one second apart).
meminfo_kb() {
    local key="$1"
    awk -v k="$key:" '$1 == k { print $2; found = 1; exit } END { if (!found) print "" }' /proc/meminfo 2>/dev/null
}

total_mb() {
    local kb; kb="$(meminfo_kb MemTotal)"
    if [ -n "$kb" ]; then echo $(( kb / 1024 )); else echo 0; fi
}

free_mb() {
    if [ -n "${EDOTMW_HOST_BUDGET_MB:-}" ]; then
        echo "$EDOTMW_HOST_BUDGET_MB"
        return 0
    fi
    local kb
    kb="$(meminfo_kb MemAvailable)"
    [ -n "$kb" ] || kb="$(meminfo_kb MemFree)"
    if [ -n "$kb" ]; then echo $(( kb / 1024 )); else echo 0; fi
}

swap_used_mb() {
    local t f; t="$(meminfo_kb SwapTotal)"; f="$(meminfo_kb SwapFree)"
    if [ -n "$t" ] && [ -n "$f" ]; then echo $(( (t - f) / 1024 )); else echo 0; fi
}

cpus() { grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1; }

# --- the admission rule ----------------------------------------------
#
# fits <class> <charged_mb>   — 0 if there is room, 1 if there is not.
#
# `charged_mb` is the declared cost of every gate holder currently alive
# (host-gate.sh supplies it). The pool is reconstructed rather than read,
# which is the whole point of the adaptive form:
#
#   pool = free_mb + charged_mb      what WOULD be free if no dev work ran
#   need = charged_mb + cost(class)  what would be held if I am admitted
#   admit iff pool - reserve >= need
#
# Reconstructing is what makes this safe against two agents arriving in
# the same second: a job that has been admitted but has not yet grown
# into its memory is still charged in full, so the second arrival cannot
# be fooled by memory the first has not claimed yet.
#
# And it is what makes the rule ADAPTIVE rather than a job count. The
# resident floor moved 1.2 GB inside the profiling hour (29 -> 22 claude
# processes) while free memory fell ANYWAY, because the WSL VM absorbed
# what was freed. Freed memory never became headroom. Any fixed "max N
# jobs" would have been sized against a floor that does not hold still;
# this recomputes it on every poll.
fits() {
    local class="$1" charged="${2:-0}" cost pool need
    cost="$(cost_of "$class")" || return 2
    [ "$cost" -eq 0 ] && return 0
    pool=$(( $(free_mb) + charged ))
    need=$(( charged + cost ))
    [ $(( pool - $(reserve_mb) )) -ge "$need" ]
}

# Why a request was refused, in the terms the gate prints to a human.
#
# `available` is THE number `fits` compares - free + charged MINUS the
# reserve. It used to print `pool`, which is that sum WITHOUT the reserve
# taken off, so a refusal read, verbatim:
#
#   not enough memory: free=2268MB charged=4100MB reserve=768MB
#                      pool=6370MB need=5600MB
#
# `pool=6370` against `need=5600` says there is room and the gate refused
# anyway. The real comparison is 6370 - 768 = 5602 >= 5600, which passes
# by 2 MB. The message was RIGHT and its presentation was not, and it
# cost a reader a whole diagnosis concluding the gate was broken (#254).
#
# free/charged/reserve stay beside it deliberately: `available` alone
# would hide WHY, and the reserve is precisely the term that was
# invisible in the comparison. The parts are shown AND the total that is
# actually tested.
explain() {
    local class="$1" charged="${2:-0}"
    printf 'free=%sMB charged=%sMB reserve=%sMB available=%sMB need=%sMB' \
        "$(free_mb)" "$charged" "$(reserve_mb)" \
        "$(( $(free_mb) + charged - $(reserve_mb) ))" \
        "$(( charged + $(cost_of "$class") ))"
}

report() {
    local t f r
    t="$(total_mb)"; f="$(free_mb)"; r="$(reserve_mb)"
    echo "host-budget: ${t} MB total, ${f} MB free, ${r} MB reserved, $(cpus) cpus"
    echo "host-budget: swap in use $(swap_used_mb) MB"
    echo "host-budget: class costs — gpu $(cost_of gpu) MB (exclusive), heavy $(cost_of heavy) MB, medium $(cost_of medium) MB, free 0 MB"
    if [ -n "${EDOTMW_HOST_BUDGET_MB:-}" ]; then
        echo "host-budget: WARNING EDOTMW_HOST_BUDGET_MB=${EDOTMW_HOST_BUDGET_MB} is overriding the measured figure"
    fi
}

case "${1:-report}" in
    total)      total_mb ;;
    free)       free_mb ;;
    reserve)    reserve_mb ;;
    swap-used)  swap_used_mb ;;
    cpus)       cpus ;;
    cost)       cost_of "${2:-}" ;;
    classes)    echo "gpu heavy medium free" ;;
    fits)       fits "${2:-}" "${3:-0}" ;;
    explain)    explain "${2:-}" "${3:-0}" ;;
    report)     report ;;
    *)
        echo "usage: host-budget.sh {total|free|reserve|swap-used|cpus|cost CLASS|classes|fits CLASS CHARGED|explain CLASS CHARGED|report}" >&2
        exit 2 ;;
esac
