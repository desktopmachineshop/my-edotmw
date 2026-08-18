#!/usr/bin/env bash
# THE comparisons a real multi-client run must survive
# (D-20260818-the-fast-loop-carries-the-gate, #112).
#
# `just test-load` is the gate a change passes before it is called done,
# and on the current default map it costs five minutes a run — so the
# loop anybody actually iterates in is `just test-scenario` (D-098), at
# roughly twenty-five seconds. That division of labour only works if the
# fast loop proves what the gate proves MINUS the opening it deliberately
# skips.
#
# It did not. `test-scenario`'s own header says "the checks follow
# test-load's shape", and of test-load's four it had copied one. Fog
# gating of squads, fog gating of resource positions, and both
# civilisations having fielded something were asserted by the five-minute
# recipe alone — that is, in practice, by nothing anybody ran between
# gate runs. Not a weaker check: an absent one.
#
# So a check lives HERE, once, and both recipes call it. The two cannot
# drift again by omission, because `tests/test_gate_checks.gd` fails if a
# check the gate makes is one the fast loop does not. Same reasoning as
# recipe-arg.sh and instance-id.sh, including the shape: a plain script
# is something a GUT test can execute and watch REJECT a bad run, where a
# `just` recipe body is unreachable from the test estate.
#
# Every check compares two STRUCTURED key=value markers, one from each
# log, and treats a MISSING marker as a failure. A comparison that
# silently skips because it found nothing to compare cannot be
# distinguished from one that passed, which is exactly the vacuous pass
# D-022's audit block was written against.
#
#   bash gate-check.sh fog-squads BOTS_LOG SERVER_LOG
#   bash gate-check.sh fog-nodes  BOTS_LOG SERVER_LOG
#   bash gate-check.sh civs       SERVER_LOG
#
# Exit 0 and print what it proved; exit 1 naming what it could not; exit
# 2 on a misuse of this script itself.
set -euo pipefail

usage() {
    echo "usage: gate-check.sh fog-squads|fog-nodes BOTS_LOG SERVER_LOG" >&2
    echo "       gate-check.sh civs SERVER_LOG" >&2
    exit 2
}

[ "$#" -ge 2 ] || usage
check="$1"
shift

# The LAST occurrence of `<key>=<number>` in a log. Last, not first:
# every one of these is a running total reported repeatedly, and the
# final report is the one describing the whole run.
marker() {
    grep -oE "$1=[0-9]+" "$2" 2>/dev/null | tail -1 | cut -d= -f2 || true
}

# Two markers had to be found for a comparison to have happened at all.
# Names the one that is missing rather than both candidates: a marker
# absent from the SERVER log and one absent from the clients' log are
# different faults, and the reader is usually chasing whichever it is.
require_both() {
    missing=""
    [ -n "$1" ] || missing="$3"
    [ -n "$2" ] || missing="${missing:+$missing and }$4"
    if [ -n "$missing" ]; then
        echo "gate-check($check): could not find $missing — the comparison did not run, so it proves nothing" >&2
        exit 1
    fi
}

case "$check" in
    # D-026 criterion 6's load half: fog must be shown gating a REAL
    # multi-client run, not a test fixture — even the single
    # MOST-INFORMED client must know FEWER squads than the server
    # actually simulated.
    #
    # Deliberately per-client, not a sum/union: every squad belongs to
    # exactly one connected player and an owner always sees its own, so a
    # union across all bots equals the server's total on every run
    # whether fog gates anything or not. See bot_client.gd's
    # `_max_known_squads()` for the long version.
    fog-squads)
        [ "$#" -eq 2 ] || usage
        known="$(marker known_squads_max "$1")"
        total="$(marker FOG_TOTAL_SQUADS "$2")"
        require_both "$known" "$total" "known_squads_max (bots log)" "FOG_TOTAL_SQUADS (server log)"
        if [ "$known" -ge "$total" ]; then
            echo "gate-check(fog-squads): fog did not gate anything — the most-informed client knew $known of $total simulated squads (expected fewer)" >&2
            exit 1
        fi
        echo "gate-check(fog-squads): fog gated at least $((total - known)) of $total simulated squads even from the most-informed client (known_squads_max=$known)"
        ;;

    # The same check for RESOURCE POSITIONS (D-061). Every node on the
    # map used to be sent to every client at join, so a player knew where
    # each opponent had to expand without scouting for any of it, and a
    # modified client could read it straight out of the packet.
    #
    # Checked against a live run rather than only in a unit test because
    # a per-client filter can be correct in isolation and still be
    # bypassed by some other send path — only real clients exercise all
    # of them.
    fog-nodes)
        [ "$#" -eq 2 ] || usage
        known="$(marker nodes_known_max "$1")"
        total="$(marker FOG_TOTAL_NODES "$2")"
        require_both "$known" "$total" "nodes_known_max (bots log)" "FOG_TOTAL_NODES (server log)"
        if [ "$known" -ge "$total" ]; then
            echo "gate-check(fog-nodes): resource positions are NOT gated — the most-informed client knew $known of $total nodes (expected fewer)" >&2
            exit 1
        fi
        echo "gate-check(fog-nodes): fog gated $((total - known)) of $total resource nodes from the most-informed client (nodes_known_max=$known)"
        ;;

    # Both civilisations must actually have fielded something (D-046
    # criterion 10). A run where everyone happened to draw the same civ
    # exercises half the roster and proves nothing about the other half —
    # and it would pass every other check here, which is the vacuous-pass
    # shape again.
    civs)
        [ "$#" -eq 1 ] || usage
        line="$(grep -oE 'CIVS_FIELDED [0-9]+ of [0-9]+' "$1" 2>/dev/null | tail -1 || true)"
        if [ -z "$line" ]; then
            echo "gate-check(civs): no CIVS_FIELDED marker in $1 — can't check both civs played" >&2
            exit 1
        fi
        fielded="$(echo "$line" | awk '{print $2}')"
        total="$(echo "$line" | awk '{print $4}')"
        if [ "$fielded" -lt 2 ]; then
            echo "gate-check(civs): only $fielded of $total civilisations ever fielded a squad — the match exercised one roster (D-046 criterion 10)" >&2
            exit 1
        fi
        echo "gate-check(civs): $fielded of $total civilisations fielded squads"
        ;;

    *)
        usage
        ;;
esac
