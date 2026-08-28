# D-20260828 · Host-quit is priced against a match length nobody has measured

**Date:** 2026-08-28
**Status:** Accepted (the M8 conclusion). The M9 direction in
"Recommendation" is the owner's call and is marked as such.
**Issue:** #289, from the gap assessment (`docs/plans/gap-assessment.md` §4.1)
**Revisits:** D-088 (host-quit kills the match; no host migration),
D-092 (no mid-match saves). **Neither is overturned.**

## Decision

**No host migration and no saves in M8.** D-092's own revisit trigger
asks for *"M9's real 1–2 hour matches showing abandonment pain that
repossession doesn't cover — **measured by playtest, not assumed**"*, and
that measurement does not exist. This entry does not pretend it does.

What this entry does instead:

1. **Corrects the record on why migration was rejected.** One of D-088's
   two grounds is weaker than it reads; the other stands.
2. **Names what genuinely changed** since 2026-08-14, which is not the
   match length and not the architecture.
3. **Names the measurement that decides it**, so the trigger can fire on
   evidence rather than on the next person who notices.
4. **Recommends** three cheap measures that bound the exposure without
   fixing it, and one direction for M9. Neither is built here — #289's
   deliverable is a decision entry, and the measures are proposed
   follow-ups rather than smuggled code.

## Rationale

### The trigger has not fired on its own terms, and saying so is the point

D-056 set 1–2 hours on 2026-08-14. D-088 and D-092 were taken **the same
day**, against the same target. So "the target is 1–2 hours" is not new
information and cannot on its own reopen either decision — which is what
#289's framing ("priced against ~3-minute matches") gets slightly wrong,
and worth correcting rather than accepting.

What *is* true is that **nobody knows how long a match lasts now**, and
that is a different and worse position than either 3 minutes or 2 hours.
Measured on this tree, 2026-08-28, five all-AI matches on `maps/ladder.tres`:

| run | seats | cap | outcome |
|---|---|---|---|
| seed 11 | 4 | 200 s | no elimination, no winner |
| seed 23 | 4 | 200 s | no elimination, no winner |
| seed 42 | 4 | 200 s | one elimination, no winner |
| seed 99 | 4 | 200 s | no elimination, no winner |
| seed 7 | 4 | 300 s | decided — and one of its three eliminations was seat 1002, which never founded (#247), so the decision is partly an artefact |

D-056 records matches deciding at **~200–230 s**. **Four of five do not
decide at 200–300 s now**, and none was run to a natural conclusion. The
RTW battle programme, the map ladder's quadrupling (2026-08-17) and
D-067's building rules have each lengthened matches since D-056 was
written, and nothing has re-measured. So the honest statement is: match
length is **longer than 300 s and otherwise unknown**, and the cost of
host-quit is unknown with it.

### What actually changed, and it is not the architecture

D-088 and D-092 were written when every player was the owner, on one
machine, in sessions the owner started and ended. **The alpha
distribution loop (#183, PR #258) changes who is in the room**: a
stranger hosting for strangers, none of whom knows the others, none of
whom can restart the session by walking to the next desk.

That converts host-quit from a *documented property of unranked play*
into a *support burden* — and the same PR stack contains the reason it
will be invisible: an alpha tester has no way to send a log back
(gap assessment §4.1). A match that died to a host quitting and a match
that died to a bug produce the same report, which is none.

This is the change worth recording, and neither D-088 nor D-092 could
have anticipated it because the alpha loop did not exist.

### Correcting D-088's rejection of host migration

D-088 rejected migration on two grounds. Re-examined:

**"Authoritative-state handoff is a milestone of its own." — STANDS.**
The bytes are cheap; D-092 says so outright (*"packed arrays serialize
cleanly… the cost is the ceremony and the versioning, not the bytes"*).
The expensive parts are electing a successor deterministically,
transferring state to a machine that has only ever held a fog-gated view,
re-establishing 19 connections, and resuming the tick without a desync —
and doing all of it under D-042's reliable-ordered contract with curve
packets that carry no sequence number. That is a real workstream.

**"Whoever inherits the server inherits omniscience." — WEAKER THAN IT
READS, and the record should say so.** The host **already** has
omniscience: D-088 states it plainly (*"the host is trusted — they hold
the whole truth and the authority"*) and D-091 accepts it for unranked
play, gating ranked on dedicated servers. Migration does not create a new
class of trust problem; it widens the set of people who could exploit it
from "the host" to "whoever the election picks". That is a real
difference and a smaller one than "a fresh cheating surface" implies —
and it is *already* the situation under D-090, where a disconnected human
hands their seat to an AI on the host's machine.

So migration is expensive, not dangerous. That reordering matters,
because it moves the decision from "never, on principle" to "not yet, on
cost" — and cost is a thing a milestone can buy.

### And D-092's rationale does not transfer to migration at all

Worth separating, because #289 groups them. D-092 rejected saves because
of the **ceremony**: all N players agree to stop, all N return later, for
an event lobby-discovered matches essentially never produce.

**Host migration has no ceremony.** Every participant is already
connected and already wants to continue; nobody has to be re-assembled.
So D-092 is not an argument against migration, and anyone reading the two
entries together should not treat it as one.

## Rejected alternatives

- **Build host migration in M8.** Rejected on the standing half of
  D-088's argument. It is a workstream, M8's exit criteria (D-094) are
  ten items of which none is complete on `main`, and the exposure during
  M8 is at its *lowest* — matches are short precisely because #159
  (farms) and #206 (tech tree) are unmerged, so there is not yet an hour
  of game to lose.
- **Dedicated-server-first for long matches.** The correct end state, and
  D-088/D-091 already name it as the eventual fix. Rejected as an M8
  answer because dedicated servers are explicitly post-M8 and standing
  infrastructure is exactly the cost D-088's owner call declined.
- **A rejoinable replay checkpoint.** Attractive, and it looked nearly
  free — replays are already the curve log, byte-identical to the wire
  (D-016), and D-025's reveal semantics make a fresh join cheap. It is
  not free: **the curve log is what was SENT, not what the simulation
  IS.** Morale, fatigue, wallets, build queues, node stocks, no-build
  claims and vision history are none of them in it, so resuming from a
  replay means adding a state snapshot — which is D-092's rejected
  alternative arriving under a different name. Recorded because it is the
  idea a reader will have next, and it is worth knowing why it does not
  work.
- **Reverse D-092 and ship saves.** Its trigger is unfired and its
  reasoning is untouched by anything here.

## Recommendation (the owner's call, not decided here)

**M9, not M8, and migration rather than saves.** When #159 and #206 land
and a match is genuinely an hour long, the loss becomes real and the
trigger becomes measurable in the same milestone. Migration is the fix
whose cost is a workstream and whose danger is already accepted;
dedicated servers remain the end state that retires the question.

**Three measures that bound the exposure now and are not fixes.** Cheap,
honest, and each one makes a killed match legible instead of mysterious:

1. **The host cannot quit silently.** A confirmation naming how many
   players it ends the match for. The server already knows the count.
2. **The lobby says who is hosting**, and that the match ends if they
   leave. It is a property of unranked play; a player who is told it is
   not surprised by it.
3. **Every participant writes the replay, not only the host.** D-016's
   log is already byte-identical to the wire, so each client has the
   material; a match that dies to a host quitting is then at least
   reviewable, and — with #183's alpha loop — attachable to a report.

None is built here. Each is a small proposed ticket.

## Consequences

- **D-088 and D-092 stand unamended.** This entry is a revisit that
  concluded "not yet", with the record corrected; it changes no
  behaviour and no code.
- **D-088's revisit trigger gains a clause**: migration is rejected on
  COST, not on the cheating surface, and a milestone that can afford the
  workstream may take it without re-arguing trust.
- **D-092's trigger is unchanged and still unfired.** It asks for a
  measurement; §"the trigger has not fired" above says what that
  measurement is and that nobody has taken it.
- **The alpha loop (#183) inherits a known, unmitigated property.**
  Whoever writes the tester runbook should state it in the runbook.

## Revisit trigger

**The measurement, stated so it can actually be taken:** once #159 and
#206 have merged, run a match to a natural conclusion — no
`--run-seconds` cap — and record its wall-clock length. That single
number decides this: under ~15 minutes and host-quit is an annoyance and
D-088 stands as written; over an hour and migration is a funded
workstream. `just ai-ladder` with no cap is the cheapest instrument, and
its result must be quoted **with its cap** (the standing rule) — which
here means "uncapped", because a truncated match reads as a draw and
would answer the wrong question.

**And a second, independent of length:** the first alpha playtest in
which a host quits and a tester reports it. That is D-092's *"abandonment
pain measured by playtest, not assumed"*, and #183 is what makes it
possible to observe at all.
