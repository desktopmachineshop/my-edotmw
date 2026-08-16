### D-040 · 2026-08-01 · Accepted — amortised flow-field builds, and the tick budget met
**Decision:** A flow-field BFS is spread across ticks under a shared
per-tick cell budget (`SquadSim.field_cells_per_tick`, 4,096) instead of
being solved in one slice. Fields still build one-per-destination and are
still shared by every squad heading there (D-007 unchanged) — only *when*
the work happens changes.

Three parts:

1. **`FlowField` splits `build()` into `begin()` + `expand(budget)`.** The
   property this rests on is that **a partially expanded field is correct
   wherever it is defined**: BFS assigns a cell its final distance the
   first time it reaches it, so a partial field is not an approximation to
   be corrected later, it is a complete answer over a smaller region.
2. **Squads wait rather than path on incomplete data.** A squad the
   wavefront has not reached keeps moving on the curve it already had and
   retries next tick. The one thing a caller must not do is read
   UNREACHABLE as "no path" while the field is unfinished — mid-build it
   means "not reached yet", and those are opposite instructions. Getting
   that check in the wrong order would silently cancel every order in a
   wave, which is what `test_an_order_wave_under_a_tight_budget_still_arrives`
   exists to catch.
3. **The queue is FIFO**, so the first group ordered moves first and the
   worst wait is bounded.

**Measured, A/B in the same process** (250 squads, group ordering, worst
tick in ms):

| cells | amortised | not |
|---|---|---|
| 2,048 | 29.1 | 92.7 |
| 8,192 | **28.6** | **344.1** |
| 18,432 | 28.6 | 412.7 |
| 32,768 | 28.9 | 853.4 |

And by squad count on the ship map:

| squads | amortised | not |
|---|---|---|
| 100 | 20.8 | 196.0 |
| 250 | 34.5 | 345.0 |
| 500 | 42.6 | 617.4 |
| 1,000 | **73.4** | **1,210.7** |

**The worst tick is now flat in map size** — ~29 ms whether the map is
2,048 cells or 32,768 — which is the signature of a budget that actually
binds. It costs about 9% on average tick time, which is the right way
round: what blew the budget was always a latency spike, never throughput.

**Consequences, and they are large:**

- **D-020's tick budget is met at D-018's full scale.** 73.4 ms at 1,000
  squads inside 100 ms, with ~27% headroom.
- **D-021's GDExtension hatch stays shut, and its named candidate is
  retired.** The flow-field solver was the one kernel D-021 nominated.
  It did not need native code; it needed to stop doing a whole solve in
  one slice. A constant factor would not have fixed a structural problem.
- **Q8 is answered differently than D-038 answered it.** Map size is no
  longer bounded by the flow-field spike at all — 32,768 cells now has
  the same worst tick as 2,048. The remaining bound on map size is
  per-squad cost, which is a throughput question and a different
  conversation. D-038's "keep the ship map at or below ~8,192 cells
  unless field building is amortised" had its condition met.
- `destination_quantum` and `fields_per_tick` both remain, disabled. The
  profiling sweep no longer re-runs the quantisation A/B every time,
  because D-038 already settled it and paying for a written-down answer
  every run is waste.

**Rejected alternatives:** Letting a squad path greedily toward its
destination on an unfinished field (rejected — BFS expands from the
destination outward, so a distant squad is reached last and the fallback
would become the primary behaviour, not an edge case; and it would walk
squads into terrain the field exists to route around). Building fields on
a worker thread (rejected — the sim is deliberately single-threaded and
deterministic for D-016's replays; a completion racing the tick boundary
would make replays non-reproducible). GDExtension (rejected on evidence,
above). A cap on *builds* per tick rather than cells — this was actually
tried in D-038 and made things worse, because a deferred squad retries
every tick and the throttle cost more than the work it throttled;
budgeting **cells** works where budgeting **builds** failed, because
partial progress is kept rather than discarded.

**Revisit trigger:** If `field_waits` climbs to where squads visibly
hesitate after an order, lower the ambition rather than the budget —
raise `field_cells_per_tick` and accept a larger spike, since the
headroom now exists.

---

**Amendment, same day — the profile sweep was measuring the wrong thing
twice, and both were found only by disagreeing with a live run.**

Two defects came out of taking a 20-player match seriously after the
sweep said everything was fine. Both are the same shape: **a workload
that never exercises what production does.**

**1. The count sweep still used the discredited workload.** D-038's
correction established that giving every squad its own random destination
defeats D-007's sharing and measures a case the design explicitly does
not optimise for. That correction was applied to the map sweep and *not*
to the count sweep, so the published per-squad table kept measuring the
flawed case for another milestone. Numbers from before this are not
comparable to numbers after it. The lesson: a correction applied to one
call site is not a correction.

**2. The unit roster was re-scanned from disk on every lookup.**
`UnitRoster.by_id` called `load_all`, which opened `/units` and re-loaded
every `.tres`, every call — and `SquadSim.tick` calls it once per squad a
building finishes. A tick in which twenty players each completed a unit
spent **858 ms inside a filesystem walk**, more than eight whole tick
budgets, with combat at 0.0 ms and hauling at 0.0 ms.

`just profile` reported a healthy ~29 ms worst tick for that same code,
because a sweep resolves its UnitDefs once at setup. **Only a live server
ever calls `by_id` at 10 Hz.** The sweep was not wrong about what it
measured; it simply could not see this, and a green sweep read as "the
simulation is fine".

It was found by instrumenting rather than theorising: the live server now
reports its worst tick, when it happened, and a per-phase breakdown on
any tick over budget. Three rounds of that narrowed 866 ms → the
buildings block → production → `by_id`. Every hypothesis formed before
the instrumentation was wrong, including two of mine.

Live 20-player result after the fix: **0 ticks over budget out of 1,304,
worst tick 38.1 ms**, verdict green, 0 desyncs.

The general rule this earns, alongside D-038's "read the server log":
**a profiling harness is a workload, and a workload has blind spots.**
Where the sweep and a live run disagree, the live run is the one
describing the game.

---
