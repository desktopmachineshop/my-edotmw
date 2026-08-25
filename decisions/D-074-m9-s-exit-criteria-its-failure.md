### D-074 · 2026-08-04 · Accepted — M9's exit criteria, its failure modes, and the telemetry that catches them
**Decision:** M9 is **"the ladder is real, and a match is worth an
hour."** Written before the code, per the standing rule that produced
D-022, D-026, D-027, D-044 and D-046.

**Exit criteria.** Every one asserts something *happened*, not that
nothing complained — D-022's first rule, bought with M1's vacuous log
grep:

1. `just ai-ladder` decides a **majority of matches in 60–120 minutes**.
2. **Every epoch is entered** in a majority of decided matches. An epoch
   never reached is content nobody has played.
3. **Time-in-epoch** lands within D-068's bands ±50%. Outside that,
   D-068's table is wrong and its numbers get re-derived together — not
   patched one at a time, which is the failure D-056 recorded.
4. `tests/test_civs.gd:43` still green **at six civs**; no script names a
   civ.
5. A sibling test: **no script names an epoch.** The ladder lives in
   `/epochs/*.tres` and nothing may hardcode a rung.
6. Each of `squad_cap_bonus`, `production_speed`, `gather_speed` and the
   new `build_speed` has an **observable effect**, each proved by a test
   watched to fail first.
7. **Upkeep demonstrably happens**: a match reports non-zero upkeep paid,
   and at least one squad routs from starvation. A criterion that could
   pass with upkeep switched off is worthless.
8. **Obsolescence check**: epoch-1 units are still being produced after
   epoch 3 in a measurable fraction of matches. This is the criterion
   that decides whether D-070's replacement model worked.
9. **Tick budget holds**: a 20-player match that reaches epoch 5 reports
   **0 over-budget ticks**, and per-squad cost is re-quoted **with its
   squad count** (CLAUDE.md's standing rule — the figure is meaningless
   without one).

**A prerequisite, and M9 should not start without it.** M6 left the rise
from M4's **40.8 µs/squad at 120 squads** to **~77** unattributed, and
worst-tick figures from that session are known unreliable (a run with
strictly less work reported 146 ms where a fuller run reported 52 ms,
because the host was building containers). **M9 adds load on top of an
unexplained regression.** Attribute it first, or criterion 9's numbers
cannot be interpreted. Where the sweep and a live run disagree, believe
the live run (D-043).

**Failure modes, each paired with the measurement that detects it.**
Naming the detector is the point; a failure mode with no detector is a
worry, not a criterion:

| Failure | What it looks like | Detector |
|---|---|---|
| *Boom-is-always-right* | advancing dominates; nobody fights early | attacks before epoch 3 ≈ 0; advance timestamps near-identical across civs |
| *Turtle-to-last-epoch* | fortify and wait is correct | buildings destroyed ≈ 0 before epoch 4; time-in-epoch-5 > 50% of match |
| *Obsolescence* | epoch-1 units become trash | criterion 8 |
| *Unlock overload* | the UI collapses under ~30 archetypes | count of simultaneously producible archetypes per building at epoch 5; > ~12 means the train UI must become epoch-scoped |

**Telemetry to add to `AI_STATS` / `ai-ladder`**, extending what D-056
already proved the value of — `peak_stockpile`, `afford_refusals` and
`cap_refusals` turned a balance argument into a number:

- `epoch_advance_ticks[]` per player, and `time_in_epoch[5]`
- `army_value_over_time` — summed **V** per D-072's metric
- `resource_idle_time` — stockpile sitting unspent
- `upkeep_paid`, `upkeep_unpaid_ticks`, `routs_from_starvation`
- `produced_by_epoch` histogram, which is criterion 8's evidence

**Also fix, because M9 depends on it:** `test-client`'s casualty gate is
already known to pass without any fighting — founding a town hall reports
through the casualty path (recorded in D-045). M9 changes the opening
again, so a gate that cannot see combat will hide exactly the regressions
this milestone is most likely to cause.

**Revisit trigger:** if criteria 1–3 pass but the match is not *enjoyable*
for an hour, the numbers are right and D-068's phase table is describing
the wrong game. That is a design failure telemetry cannot detect, and the
only instrument for it is playing it.

---

**Amendment, 2026-08-23 — criterion 6 is three-quarters discharged in
advance.** `squad_cap_bonus`, `production_speed` and `gather_speed` each
have an observable effect and each is proved by a test watched to fail
first (`D-20260823-a-civs-knobs-are-read-by-the-simulation.md`, #158).
`build_speed` does not exist yet, so the criterion is not closed — and
the lesson from doing the other three is worth having before writing its
test: a behaviour test that drives the mechanism by hand stays GREEN
while the server ignores the knob entirely. The test has to drive the
server's own order path.
