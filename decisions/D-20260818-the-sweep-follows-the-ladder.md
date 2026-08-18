# D-20260818 · 2026-08-18 · Accepted — `just profile` sweeps the shipped ladder, and follows it

**Decision:** the map-size sweep in `profile_sweep.gd` takes its sizes
from **`MapSettings.sizes()`** — the one definition of what the game
ships — instead of from a list of its own. Three clauses:

1. **The sweep follows the ladder; it does not keep a copy of it.** A
   rung added to `MapSettings.sizes()` is a row added to the sweep, with
   nothing to remember. `tests/test_profile_sweep.gd` fails if any
   shipped size goes unswept, so the two cannot drift apart again.
2. **The sweep's job reversed direction, and the file now says so.** Ship
   map size was an OUTPUT of this sweep when D-021 named the flow-field
   solver as the thing that would bound a map. D-040 amortised field
   building, worst tick went flat in map size, and the ladder is set by
   the zoom cap instead
   (D-20260817-the-zoom-cap-was-modelling-the-wrong-axis). The sweep is
   downstream of the ladder now, and what it checks is whether the
   flatness Q8 was closed on still holds where players actually play.
3. **The warning travels with the numbers.** A green `just profile` is
   not a green server. Not a caveat added for symmetry: this sweep once
   reported a healthy ~29 ms worst tick for code that spent **866 ms** in
   a live tick, because a sweep resolves its `UnitDef`s once at setup and
   structurally cannot see a per-call filesystem walk (D-038's
   amendment). This change makes the sweep *able* to see the shipped
   sizes; it does not make it sufficient. **Where the sweep and a live
   run disagree, believe the live run.**

Issue #108, M10 workstream 4 of 8. Discharges exit criterion 5 of
`D-20260817-m10-scale-optimisation`: the sweep runs 8,064 to 130,368
cells, and the worst-tick curve **is** flat.

## Rationale

The sweep is this project's **only** authority on how the simulation
scales. A live match cannot reach D-018's ~1,000 squads — squad count in
a real game is whatever production happens to produce, a few dozen — so
every scaling claim in `docs/status/m4.md` comes from here.

It swept 2,048 to 32,768 cells. The ladder moved underneath it twice, and
after 2026-08-17 the shipped sizes were 8,064 / 32,592 / 73,080 /
130,368. So the sweep's **largest** map was the **default** one every
match is now played on, its smallest was a quarter of the smallest
shipped size, and three quarters of the ladder had never been swept at
all.

**Nothing failed, and that is the whole shape of it.** The sweep stayed
green throughout, printing a tidy curve about maps nobody plays. This is
CLAUDE.md's declared-and-unread family — one rule written down twice and
allowed to disagree — applied to an **instrument** rather than to a
mechanic, which is worse, because the instrument is what the project uses
to check its other claims. `MapSettings.sizes()` was already the single
definition every other caller reads (`client.gd`, `match_state.gd` and
five test files); `profile_sweep.gd` held the last hardcoded copy.

## Measurement — the curve, 8,064 to 130,368 cells

Taken 2026-08-18 on this change: 250 squads held fixed, 200 ticks per
size, eight shared rally points re-ordered every 40 ticks.

**Two runs, because one is not a measurement** — this project's own
standing rule, and it earned its keep here. Run A is the docker runtime
on a host running **eleven** other agents' containers (two full
`test-load` server+bot pairs, six Godot suites, several over 130% CPU).
Run B is the native runtime, taken after Docker Desktop fell over
host-wide and that load drained. Same commit, same seeds.

### Amortised — the shipping configuration (D-040 on)

| cells | fields built | squad waits | µs/squad A / B | **worst tick A / B** |
|---|---|---|---|---|
| 8,064 (Skirmish) | 165 | 29,709 | 149.9 / 197.7 | 115.6 / **84.8** |
| 32,592 (Standard, the default) | 78 | 41,830 | 204.3 / 205.5 | 128.8 / **90.8** |
| 73,080 (Large) | 55 | 47,480 | 259.3 / 221.2 | 146.4 / **93.9** |
| 130,368 (Huge) | 45 | 48,426 | 181.6 / 216.4 | 105.8 / **96.1** |

**The curve is flat.** On the quiet run a **16x** increase in map area
costs **13%** of worst tick — 84.8 to 96.1 ms — and every rung stays
inside D-020's 100 ms budget. `µs/squad` moves 197.7 to 216.4 over the
same range, flat to within its own run-to-run spread. D-040's claim that
worst tick is flat in map size, taken at 2,048–32,768 cells and
extrapolated past it by
`D-20260817-the-zoom-cap-was-modelling-the-wrong-axis`, now holds
**measured** across the whole shipped ladder.

### Unamortised — the D-040 control arm, not a shipping configuration

| cells | fields built | µs/squad A / B | worst tick A / B |
|---|---|---|---|
| 8,064 | 246 | 310.7 / 280.0 | 1,255.9 / 1,166.6 |
| 32,592 | 162 | 722.2 / 642.5 | 3,106.4 / 3,595.7 |
| 73,080 | 128 | 4,215.2 / 1,123.4 | 25,120.1 / 5,884.5 |
| 130,368 | 121 | 4,285.2 / 1,634.0 | 28,972.6 / 11,523.5 |

Worst tick rises **10x for 16x the cells** with the budget off — roughly
linear in map size, which is the whole reason D-040 exists. Amortisation
is not an optimisation on this ladder; it is what makes it playable.

## Two things the pair of runs proves that neither could alone

**1. Everything in this sweep except the microsecond counters is
deterministic, and the counts are the trustworthy columns.**
`fields_built` and `squad_waits` are **identical to the unit** across
both runs — 165 / 78 / 55 / 45 and 29,709 / 41,830 / 47,480 / 48,426 —
on a different runtime, a different OS kernel, and a host load an order
of magnitude apart. Field building is budgeted in CELLS rather than in
time (D-040), so the simulation cannot hear the host. This is D-106's
amendment arriving on its own: **a "cost does not scale with the map"
claim must assert WORK, not milliseconds.**

**2. This sweep measures the same workload twice, and on a loaded host it
disagrees with itself by 2.4x.** The count sweep at 250 squads and the
map sweep at 32,592 cells are the same 250 squads on the same map with
the same seed — the sweep says so itself by reporting exactly 78 fields
built for both, and exactly 162 for both in the unamortised arm. Their
worst ticks on run A were **53.6 ms and 128.8 ms**. Anyone reading run
A's map sweep alone would have reported a curve rising 115.6 to 146.4 ms
and a breach of D-020's budget; the tell that no map-size effect can
produce is the largest map returning the LOWEST worst tick of the four
(105.8 ms against 146.4 at half its size). **A `just profile` absolute
taken while the host is busy is not a number, and this instrument now has
a built-in duplicate pair that says so.**

## What the sweep can resolve, and what it hands to #107

The cost of a bigger map is **pathing latency, not tick spikes**, and the
sweep can put a number on it for the first time:

- **Fields completed within 200 ticks falls 165 → 78 → 55 → 45.** A field
  is a BFS over every cell against a flat 4,096-cell-per-tick budget, so
  a 16x map takes 16x the ticks to finish one.
- **`squad_waits` rises 29,709 → 41,830 → 47,480 → 48,426**, against a
  ceiling of 50,000 (200 ticks x 250 squads). On the Huge map **97% of
  squad-ticks are spent waiting for a path that has not reached the squad
  yet**; on the default map it is 84%.
- **`builds_deferred` is 0 at every size.** The per-tick FIELD-COUNT cap
  never binds; the per-tick CELL budget does.

That is D-040's trade — map size costs latency rather than a spike —
being spent nearly to exhaustion at the top of the shipped ladder. It is
issue **#107**'s number, and this is the first time the sweep could
produce it, because the sizes it needed were the ones it did not have.
**The tick budget is not what the enlarged ladder threatens;
responsiveness is.**

## Consequences

- The sweep covers about 4x the cells it did — 244,104 across the four
  sizes against 61,376 — and takes correspondingly longer: **15m20s
  native on a quiet host, 17m34s in docker on a loaded one.** That lands
  on issue #112's pile deliberately rather than being hidden by keeping
  the sweep small; `just profile` was never in the per-change loop.
- The count sweep is untouched. It already ran on `maps/default.tres`,
  which is the shipped default, so it was the half of this instrument
  that had not drifted.
- `MAP_SIZES` is gone as a constant. Nothing outside this file read it.

## Rejected alternatives

- **Update the hardcoded list to the current four sizes.** One line, and
  exactly what was done the last two times the ladder moved — which is
  how the list came to be three quarters wrong while looking maintained.
  The defect is two lists, not the values in them.
- **Sweep a size range independent of the ladder** (powers of two
  spanning it, say). Defensible for curve-fitting and wrong for this
  project: the question a reader brings to `just profile` is "what does
  the map I ship cost", and an answer at 65,536 cells requires
  interpolating to a size nobody plays.
- **Keep the old small sizes as extra rows, for continuity with M4's
  published numbers.** Rejected: those were taken before D-105 made map
  size an EXTENT rather than a resolution, so a 2,048-cell map is not the
  world it was when they were taken, and the continuity would be
  fictional.
- **Drop the unamortised arm at the two largest sizes to save eight
  minutes.** Rejected: it is the arm that shows worst tick going linear
  in map size, and it is the only thing in this file that makes the
  amortised arm's flatness mean anything.

## Revisit trigger

If the sweep's wall clock makes it something nobody runs, cut `TICKS` or
`MAP_SWEEP_SQUADS` — never the size list. A sweep that skips the sizes
players use is the defect this entry exists to close.
