### D-038 · 2026-08-01 · Accepted — M4's first measurements
**Decision:** Record what the scale sweep actually measured, and what it
settles. Three things were being taken on faith and are now numbers:
whether simulation cost is linear in squad count, where the flow-field
solver breaks (Q8), and whether any kernel needs GDExtension (D-021).

Measured by `just profile` — the simulation driven directly at chosen
counts rather than played, because squad count in a real match is
whatever production produces and D-018 targets ~1,000.

**1. Cost is linear in squad count.** 128x64 map, 200 ticks:

| squads | µs/squad | vision | combat | ms/tick |
|---|---|---|---|---|
| 100 | 74.8 | 13.3 | 59.8 | 7.5 |
| 250 | 79.7 | 11.3 | 66.9 | 19.9 |
| 500 | 80.5 | 10.4 | 68.5 | 40.3 |
| 1000 | 74.1 | 9.6 | 62.9 | 74.1 |

Tenfold more squads, no per-squad growth. **At D-018's full scale that
is 74 ms inside a 100 ms tick** — it fits, with ~26% headroom, and
D-020's revisit trigger is not tripped. Vision cost per squad *falls* as
count rises (13.3 → 9.6) because the per-player coverage field is stamped
once and shared however many squads read it, which is D-025 part 1's
argument paying off. Combat is ~85% of the tick.

**2. Q8 — ship map size. The flow-field solver is linear in cells, and
that is not the problem.** 250 squads, varying map:

| cells | µs per field build | µs/squad |
|---|---|---|
| 2,048 | 4,146 | 31.7 |
| 8,192 | 16,818 | 81.6 |
| 18,432 | 37,169 | 103.7 |
| 32,768 | 67,434 | 156.4 |

Almost exactly 2 µs per cell at every size — no cliff, no bend. D-021
guessed at a threshold "over 10,000+ cells"; there isn't one, because
nothing about the algorithm degrades.

**The real constraint is spike size against the tick.** ONE field build
at 32,768 cells costs 67 ms — two thirds of an entire 100 ms tick, for a
single squad choosing a new destination. At the current 8,192 it is
16.8 ms, or 17% of a tick, and D-003 already warns that a large
engagement re-paths many squads at once. That is an invalidation storm
with a hard number attached.

**Q8's answer: keep the ship map at or below ~8,192 cells** unless field
building is amortised. This is a budget bounded by latency spikes, not by
average throughput — average tick cost at 32,768 cells is a comfortable
39 ms, which is exactly why measuring only the average would have missed
it.

**3. D-021 — no kernel needs GDExtension yet, and the cheap fix comes
first.** The flow-field solver is the named candidate and it *is* the
thing exceeding budget, but not because GDScript is too slow per cell:
2 µs/cell over 32,768 cells would be a big number in any language. The
problem is doing it all inside one tick.

The GDScript-level fixes are untried and obvious: amortise a build across
several ticks (a squad already tolerates a tick of latency before its
curve is extended), or widen destination sharing so fewer distinct fields
are built at all — the sweep shows 1,112 builds for 250 squads, which is
far more re-pathing than D-007's per-destination sharing should require.
Per M4's fix policy, those come before the native escape hatch.

**Rationale:** All three were assumptions load-bearing enough to appear
in other decisions. D-018's target assumed linearity, Q8 assumed a
threshold existed, and D-021 assumed the flow field would be the kernel
that broke. Two of three survived contact; the third was right about
*which* kernel and wrong about *why*.

**Rejected alternatives:** Measuring only at 1,000 squads (rejected — a
single point gives pass/fail without saying whether anything is
accidentally quadratic, which is the defect class already found twice
here). Measuring average tick cost alone (rejected — it hides exactly the
spike that bounds map size).

**Consequences:** Q8 is answered pending the amortisation work. D-021
stays unexercised, deliberately. D-012's LOD tiers gain their first
evidence: combat dominates at every scale, so combat resolution is where
LOD has something to save.

**Revisit trigger:** If amortising field builds does not bring the spike
under a tick at the chosen map size, revisit GDExtension for that kernel
specifically — and only that kernel.

**Corrected 2026-08-01, same day.** The map sweep above used a workload
that defeated the thing it was measuring, and the correction makes the
finding worse rather than better. Recorded in full because the mistake is
instructive.

**The flawed workload.** Every squad was ordered to its own random
destination. D-007's entire scaling claim is that ONE field serves every
squad heading to the same place — so giving 250 squads 250 destinations
measured a case the design explicitly does not optimise for, and the
"1,112 builds for 250 squads" figure was an artifact of the harness, not
a finding about the game. Players order groups.

**Re-measured with group ordering** (250 squads, 8 shared rally points):

| cells | µs per field | fields built | ms avg tick | **ms WORST tick** |
|---|---|---|---|---|
| 2,048 | 4,323 | 215 | 8.6 | **127.5** |
| 8,192 | 18,492 | 186 | 20.1 | **437.0** |
| 18,432 | 37,653 | 142 | 26.6 | **393.1** |
| 32,768 | 70,595 | 125 | 155.5 | **905.5** |

Sharing works — builds fall by more than half. **And the worst tick is
catastrophic anyway**: 437 ms at the current map size, against a 100 ms
budget. An order wave creates several NEW destinations at once, so
several full BFS solves land in the same tick. This is D-003's
invalidation storm, and it is 4.4x over budget on the map being shipped.

The average hid it completely — 20 ms — which is the second time in this
milestone that measuring the average alone would have produced a
comfortable and wrong conclusion.

**A budget on builds-per-tick was tried and made things worse.** Capped
at 2, deferred squads retried on every following tick: 31,413 deferrals
and a worst tick that went UP. A throttle that costs more than the work
it throttles. It survives as `SquadSim.fields_per_tick`, defaulting to 0
(unlimited), because it is the right shape for a genuine storm and the
wrong default.

**So D-021's trigger is now armed with evidence, and the flow-field
solver is the kernel.** But the fix to try first is still algorithmic
rather than native: a single build is ~2 µs/cell in GDScript, and no
language makes 32,768 cells free — the problem is doing a whole solve
inside one tick. Incremental solving (spread one BFS over several ticks,
serve squads the partial field) attacks the actual shape of the problem.
GDExtension would buy a constant factor against a cost that is
structurally too large in one slice.

**Consequently Q8's answer stands but for a sharper reason:** map size is
bounded by how much BFS lands in one tick, and at every size measured
that already exceeds the budget under a realistic order wave. Map size
is not the dial that fixes this — amortisation is.

**Routing was the hidden source of field builds, and fixing it is the
first real win.** Quantising player orders bought only 18% and cost exact
arrival, so it was backed out — but the build count barely moving was the
clue. The sweep issues 8 destinations per wave over 5 waves: at most 40
distinct fields, and 186 were built.

`Combat._check_rout` sent every broken squad fleeing to its own computed
cell, so **a rout produced one full BFS solve per squad** — during
precisely the large engagements that are already re-pathing everyone.
D-007's sharing cannot help a destination nobody else shares.

The fix is that a rout has no exact destination worth preserving. A squad
is running away; where it stops is a detail nobody chose. Snapping flee
destinations coarsely (`rout_quantum`, 8 cells) makes a whole routing
army share a handful of fields:

| cells | fields before | after | µs/squad before | after | worst tick |
|---|---|---|---|---|---|
| 2,048 | 215 | **57** | 33.5 | **22.1** | 130 → **88 ms** |
| 8,192 | 186 | **123** | 80.5 | **53.5** | 457 → **323 ms** |
| 32,768 | 125 | **110** | 151.9 | **135.7** | 903 → **844 ms** |

A third off per-squad cost at the shipped map size, and a third off the
worst tick, from one line about where cowards run to.

**It is not enough on its own.** 323 ms is still 3.2x over a 100 ms
budget, and the remaining spike is what it always was: several whole BFS
solves landing in one tick. Amortisation remains the next move; this
simply removed a large multiplier in front of it.

The general lesson is worth keeping: the expensive pattern was not the
one anybody designed. Player orders were carefully shared; the cost came
from an emergency behaviour written for correctness with no thought about
how many destinations it minted.

**Amended 2026-08-01 — the 20-player live measurements.** The sweep above
drives the simulation directly. This is the same scale played through the
real server, the real protocol and the real client code: 20 bots, 120
seconds, `just test-load 20 120`, verdict green.

| measurement | result | against |
|---|---|---|
| bandwidth | **595 B/client/s** | budget_overruns=0 |
| server memory | **42.5 MB** at 120 squads | — |
| client memory | **28.4 MB** for 20 virtual clients (~1.4 MB each) | D-018's N-in-one-process budget |
| per-squad cost | **40.8 µs** at 120 squads | D-020's ~50 µs |

Bandwidth is the headline and it is not close: 0.6 KB/s per client, from
curve-based sync doing what D-003 said it would. Nothing about this
number is at risk at 20 players.

**The per-squad figure needs its caveat read.** 40.8 µs at 120 squads is
under budget, and CLAUDE.md's standing warning applies in the flattering
direction here — per-tick fixed overhead is divided across more squads
than M2's 48, so this is not directly comparable to the 53.5 µs above.
The sweep, not the match, remains the authority on scaling; a live match
cannot reach 1,000 squads.

**None of it was measurable until a two-line ownership bug was found**,
and the way it hid is the part worth keeping. The first 20-player run
reported "zero movement" — a symptom that invited theories about spawn
stacking and vision. The actual cause was in the server log: 2,700
refusals of the form "player N tried to order squad M it does not own",
because per-connection ownership was cached at join and every *produced*
squad was rejected. The measurement was not wrong, it was measuring a
match in which nothing happened.

Then fixing it exposed two more bugs stacked behind it, one of which had
been *cancelling* another: the client never dropped dead squads from its
owned list, which kept a bot's "do I have squads?" guard true, which was
the only reason its production code was still being reached after its
founding party was consumed. Making the client honest broke the bots. Two
defects whose symptoms had been hiding each other for the whole of M3.

The lesson generalises past this instance: **an anomalous measurement is
a bug report about the harness first and the system second.** Three
sessions of theorising about spawn placement would not have found this;
reading the server's own error log did, immediately.

---
