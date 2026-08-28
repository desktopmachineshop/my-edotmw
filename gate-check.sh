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
#   bash gate-check.sh handshake  BOTS_LOG SERVER_LOG
#   bash gate-check.sh naval      SERVER_LOG
#
# Exit 0 and print what it proved; exit 1 naming what it could not; exit
# 2 on a misuse of this script itself.
set -euo pipefail

usage() {
    echo "usage: gate-check.sh fog-squads|fog-nodes|handshake BOTS_LOG SERVER_LOG" >&2
    echo "       gate-check.sh civs SERVER_LOG" >&2
    echo "       gate-check.sh naval SERVER_LOG" >&2
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

# The LARGEST value of a key across the whole log, for keys that are
# reported PER SEAT.
#
# `marker` takes the last occurrence, which is right for a marker printed
# once a match and silently wrong for one printed once a player: it reads
# whichever seat happened to print last. Measured on a real isles run —
# seat 1000 reported `wants_navy=1` and seat 1001 `wants_navy=0`, and the
# gate declared that no seat wanted a navy, which would have masked the
# dock failure underneath it with a #351 report that was not true.
#
# The naval legs all ask "did ANY seat get this far", so the max is the
# question. A per-seat gate is a different and harder one — a seat that
# sailed while another never launched is not a failure, it is one AI
# playing better than the other.
marker_max() {
    grep -oE "$1=[0-9]+" "$2" 2>/dev/null | cut -d= -f2         | sort -n | tail -1 || true
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
    # Naval cut-list stage 7's gate (#301, naval plan section 6.2): a run
    # on a map with water must contain a LANDING, or the whole feature is
    # shipped and unexercised — which is D-076's gap, which is why
    # section 6 exists, and which is why this is a gate rather than a
    # metric.
    #
    # ORDERED VACUITY GUARDS, and they are the point. `landings=0` is
    # what a land map, an unplayed match, a missing dock, an untrained
    # transport and a broken disembark ALL report. So the failure is
    # reported at the FIRST leg that is missing, and a zero says WHICH
    # rather than that something did.
    #
    # Skipped entirely when no AI ever wanted a navy: on a map where
    # every enemy is walkable the correct number of landings is zero, and
    # a gate that failed there would fail every ordinary run. `wants_navy`
    # is that distinction, which is why the AI reports it.
    naval)
        [ "$#" -eq 1 ] || usage
        wanted="$(marker_max wants_navy "$1")"
        if [ -z "$wanted" ]; then
            echo "gate-check(naval): no AI reported wants_navy — no seat ran the naval question at all" >&2
            exit 1
        fi
        # WHY THE SKIP KEYS ON THE MAP AND NOT ON `wants_navy`.
        #
        # Two runs report `wants_navy=0`: one where every enemy was
        # walkable, which is correct, and one on an archipelago, which is
        # #351 — the defect this gate exists to catch. Skipping on the
        # AI's own answer lets the thing under test excuse itself, and a
        # gate that cannot fail is not a gate.
        #
        # So the map decides. SPAWN_LANDMASSES is topology: one means no
        # crossing was ever available and a skip is honest; more than one
        # means the crossing was there and declining it is a finding.
        islands="$(marker SPAWN_LANDMASSES "$1")"
        if [ -z "$islands" ]; then
            echo "gate-check(naval): the server log has no SPAWN_LANDMASSES — cannot tell a land map from an archipelago, so a skip here would be unearned" >&2
            exit 1
        fi
        if [ "$wanted" -eq 0 ]; then
            if [ "$islands" -le 1 ]; then
                echo "gate-check(naval): skipped — the starts share one landmass, so no crossing was available and zero landings is correct"
                exit 0
            fi
            echo "gate-check(naval): the starts span $islands landmasses and NO seat wanted a navy — an AI that cannot walk to its enemy declined to sail (#351)" >&2
            exit 1
        fi
        for leg in "docks:no dock was ever built"                    "ships_peak:a dock stood but no hull was ever trained"                    "embarks:a hull existed but nobody ever boarded"                    "landings:an army sailed and never got ashore"; do
            key="${leg%%:*}"
            why="${leg#*:}"
            got="$(marker_max "$key" "$1")"
            if [ -z "$got" ]; then
                echo "gate-check(naval): the server log has no $key at all — the AI is not reporting its naval legs" >&2
                exit 1
            fi
            if [ "$got" -eq 0 ]; then
                echo "gate-check(naval): $why ($key=0)" >&2
                exit 1
            fi
        done
        echo "gate-check(naval): a landing happened — docks=$(marker_max docks "$1") ships_peak=$(marker_max ships_peak "$1") embarks=$(marker_max embarks "$1") landings=$(marker_max landings "$1")"
        exit 0
        ;;

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

    # Every client that joined did so through the protocol version
    # handshake, and none was refused (#179, D-094 criterion 3).
    #
    # It reads ACCEPTED rather than "refused=0", because zero refusals is
    # what a working run, a run where nobody connected, and a handshake
    # that is not wired up at all ALL report — the vacuous-pass shape
    # this whole file exists to refuse. The accepted count can only be
    # raised by a real socket client completing a real exchange.
    #
    # It is also compared against the bots' OWN count of who connected,
    # rather than merely being positive: a server that admitted three of
    # four bots and silently dropped the fourth would otherwise pass.
    handshake)
        [ "$#" -eq 2 ] || usage
        connected="$(grep -oE '[0-9]+/[0-9]+ bots connected' "$1" 2>/dev/null | tail -1 | cut -d/ -f1 || true)"
        accepted="$(marker 'HANDSHAKE accepted' "$2")"
        require_both "$accepted" "$connected" "HANDSHAKE accepted= (server log)" "'N/M bots connected' (bots log)"
        refused="$(marker refused "$1")"
        if [ "$accepted" -lt "$connected" ]; then
            echo "gate-check(handshake): the server accepted $accepted handshakes but $connected clients connected — somebody joined without one" >&2
            exit 1
        fi
        if [ -n "$refused" ] && [ "$refused" -gt 0 ]; then
            echo "gate-check(handshake): $refused client(s) were REFUSED — this run was played by mixed builds" >&2
            exit 1
        fi
        echo "gate-check(handshake): all $accepted client(s) joined through the protocol handshake, none refused"
        ;;

    *)
        usage
        ;;
esac
