### D-20260828-the-m6-rise-has-a-name · 2026-08-28 · Accepted — the M6 per-squad rise, attributed at a matched squad count and a matched map

**Decision:** CLAUDE.md's oldest open perf debt is closed by measurement.
`just profile ladder` is a **steady-state per-phase tick ladder at a fixed
120 squads** with a knob per suspect and a **control row that states its
own noise floor** — the server's equivalent of what PR #250 gave the
client. Issue #304.

**The answer is not the one the debt assumed.** M6's rise was recorded as
unattributed "to whichever of civs/teams/economy caused it". Measured, at
120 squads, **none of them costs anything** — every one of them is inside
the instrument's own error bar. The cost is in **combat and separation**,
and most of what dominates the tick today was added *after* M6.

One thing is recovered outright, with no behaviour change: **the
separation pass was scanning a disk sized for a clearance rule that had
been deleted.**

---

#### Why `just profile` could not already answer this

`_run` — the count sweep — builds a **bare** simulation: no `teams`, no
`civs`, no `economy`, no `buildings`, no `research`. Every one of those is
a thing M6 or later added, and a harness cannot measure a system it never
instantiates.

That is not a flaw in the sweep. It isolates simulation cost on purpose,
and the published count table's meaning depends on it not changing. But it
is a sharper statement of CLAUDE.md's standing warning that *"a green
`just profile` is not a green server"*: the sweep is green **partly
because half the server is absent from it**.

Hence a separate section, with every knob defaulting to ON, so a bare
`just profile` measures the shipped configuration and the count table is
untouched.

#### The instrument, and its error bar

120 squads, 4 players, shipped defs, 200 measured ticks after a 120-tick
warm-up, best of 7 interleaved passes.

Three things about it are load-bearing, and each was bought by a wrong
answer first:

- **Steady state.** The first ticks of any run are dominated by
  flow-field construction, which #105 already attributed a whole 84
  µs/squad rise to. Counters are snapshotted after the warm-up.
- **A representative rally spread.** The count sweep uses 8 rally points
  at any count; at 120 squads that is fifteen squads on one cell, and
  separation then spends its entire budget shoving them past each other —
  **51–70 µs/squad against the 5–8 a real `test-load` run reports.** The
  ladder uses one rally per five squads.
- **A `control` row: the shipped configuration, run twice, under two
  labels.** It is the most important row in the table, because it is the
  smallest difference the table can resolve. The first version had no
  control and reported **209.81 and 272.23 µs/squad for the same
  configuration** — a 30% spread, wider than every effect it was looking
  for, with knobs turned OFF reading as slower. Any knob nearer to
  `as shipped` than `control` is not measurably anything.

**This host cannot resolve small effects, and the table says so rather
than pretending otherwise.** Absolutes drift by up to 2× between runs
minutes apart, which is `docs/status/terrain.md`'s bench-render lesson
again. Every claim below is either a within-run interleaved comparison or
a difference far larger than the control gap.

#### The attribution

**At 120 squads on M4's own 8,192-cell map** — matched count, matched map,
so the comparison is honest in both dimensions:

| | µs/squad | fields | curves | vision | combat | buildings | separation |
|---|---|---|---|---|---|---|---|
| M4 (recorded 2026-07) | **40.8** | — | — | — | — | — | — |
| today, before the fix | **277.7** | 1.8 | 22.7 | 34.5 | **110.0** | 12.4 | **95.3** |

Two of the six phases are 74% of the tick. Repeatable: an independent run
minutes earlier read 277.35 on the same configuration.

**The map is not the explanation, and it was the obvious suspect.** The
shipped 32,592-cell map costs 328–399 against 8,192's 277 — real, and
mostly `fields` (1.8 → 70.7, which is #105/#107's flow-field expansion,
already attributed and owned). It is nowhere near a 6.8× rise.

**And the named suspects cost nothing.** The bisection, shipped map, 120
squads, best of 7 interleaved passes:

| config | µs/squad | vs shipped | combat | separation |
|---|---|---|---|---|
| as shipped | 222.10 | — | 88.13 | 3.47 |
| **control** (shipped again) | **222.71** | **+0.6** | 88.46 | 3.57 |
| teams off | 253.16 | **+31.1** | 97.56 | 3.51 |
| economy off | 236.49 | **+14.4** | 94.40 | 3.63 |
| civ-knobs off | 227.56 | +5.5 | 90.75 | 3.63 |
| research off | 214.97 | −7.1 | 84.81 | 3.43 |
| buildings off | 196.43 | **−25.7** | 81.76 | 3.29 |

**Not one of the accused is a cost.** Three of them measure *slower*
switched off, which is not a cost being removed — it is the knob changing
the WORKLOAD as well as the work. Turning teams off makes all four
players mutual enemies, so there is more fighting: combat 88.1 → 97.6.
The economy blocks ground with nodes, so removing it changes pathing and
contact the same way. **A feature whose removal makes the tick more
expensive cannot be the source of a rise**, and that is the whole answer
to the bisection this issue asked for.

**Read the noise floor as ~7 µs/squad (≈3%), not as the control row's
0.6.** The control gap is the best agreement two labels reach when
best-of-7 happens to sample the same host conditions; it is a LOWER bound.
The `research` row is what calibrates it honestly: `TechEffects` early-
returns on an empty tech list and nothing in the ladder researches
anything, so research provably does **no per-tick work here** — its −7.1
is therefore noise, by construction, and tells us what noise looks like.
Only `buildings` (−25.7) and the two workload effects are outside it.
`civ-knobs` at +5.5 is inside, and is not a measurement of anything.

So the honest attribution is that the rise is **combat and separation**,
and the changes that put it there are almost all *later* than M6 and each
was priced when it landed:

- **`D-20260819-only-men-in-contact-fight`** — the contact set derives
  both squads' soldier transforms and counts pairs. Its own entry
  measured and accepted **combat 9.59 → 33.19 µs/squad at 24 squads**, a
  3.5× rise, in exchange for frontage and envelopment being real. That is
  the single largest named change and it matches the magnitude.
- **`D-20260818-a-squad-wheels-it-does-not-snap`** — path smoothing, in
  `curves`.
- **`D-20260818`'s separation pass**, below.
- **#105's flow-field expansion**, on the bigger map only.

**What this deliberately does NOT claim** is a decomposition of M4's 40.8
into today's phases. M4 printed no breakdown, so any such split would be
invented — the same refusal
`D-20260818-every-microsecond-of-a-tick-has-a-phase` made, for the same
reason. What can be said, and now is, is what the tick costs **today** at
a matched count and map, and which of the suspects is responsible.

#### The one thing recovered

**`SquadSim._crowded` was scanning a disk sized for a clearance rule that
no longer exists.**

Separation gained footprint-based clearance in #104, and the scans were
sized to match: `disk_offsets(footprint_cells(asking) + widest)`. Then
`D-20260821-a-fight-loosens-a-formation` reverted clearance to D-060's
flat **one cell** — and the radii derived from it were not re-read. A
squad can only be blocked by something within `_clearance` of it, so at
clearance 1 exactly **seven** offsets can matter; the pass was walking
about **469**, per settled squad, per tick. `_free_cell_near`'s
neighbour-gather had the same shape.

Both radii come from `_clearance_bound()` now, so the scan is derived
from the rule rather than from a footprint that stopped being relevant.
**The answer is bit-for-bit unchanged** — an over-scan was never wrong,
only expensive — which is why nothing failed and no test caught it.

Measured, same instrument, 120 squads, best of 7:

| map | separation before | after | |
|---|---|---|---|
| 8,192 cells | **95.30** µs/squad | **8.80** | **10.8×** |
| 32,592 cells | **50.75** | **6.06** | **8.4×** |

Separation goes from **34% of the tick to 3%** on M4's map size. Quote
the PHASE and not the total: the totals in the same pair read 277.7 → 258.9
and 398.8 → 318.0, and part of that is host drift — combat happened to
measure higher in the after run than the before one, which is the same 2×
absolute noise the control row exists to expose. The separation column is
a within-phase measurement of identical work and it moved by an order of
magnitude in both rows, which no plausible noise accounts for.

This is this project's most-repeated defect wearing yet another hat: *a
rule that was correct when written, depending on something that later
changed, with nothing failing.* `tests/test_separation_scan.gd` guards
the relationship rather than the behaviour, because the behaviour is what
did not change: it asserts `_clearance_bound()` bounds `_clearance()` over
the shipped roster, so making clearance variable again cannot silently
under-scan — which *would* be a correctness bug, not a slow one.

#### Rejected alternatives

- **Attribute M6's rise by reading the diff between M4 and M6.** Rejected
  — that is exactly the invented attribution
  `D-20260818-every-microsecond-of-a-tick-has-a-phase` refused, and this
  entry is not entitled to it either just because the debt is old.
- **Report the ladder's absolutes as the answer.** Rejected — they move
  by up to 2× on this host between runs minutes apart. Only matched,
  interleaved comparisons are quoted, and the control row is printed so a
  reader can see the floor rather than take it on trust.
- **Optimise combat's contact set.** Rejected as out of scope and
  probably wrong: it is a *priced design trade*, recorded and accepted in
  its own entry, and the issue's own instruction is that a design trade
  gets filed rather than fixed. It is now the largest single phase and
  that is worth knowing; whether frontage is worth 110 µs/squad is a
  question for whoever owns D-018's successor number (#287).
- **Extend the count sweep instead of adding a section.** Rejected — it
  would change what the published count table measures, and that table's
  value is that it has meant one thing since M4.

#### Consequences

- **#304 closes and #287 unblocks.** D-018's successor number can be
  derived from a tick whose phases are named, at a squad count that is
  quoted with it.
- **M9's tick budget can be interpreted.** The rise is combat and
  separation; a rung of the ladder that adds troops adds combat, which is
  now a number rather than a suspicion.
- **CLAUDE.md's "unattributed 40.8 → ~77" debt is discharged**, and the
  replacement statement is narrower and true: *the M6 feature set is not
  measurable at 120 squads; the tick is combat and separation.*
- **A tick phase that grows can now be seen growing.** `just profile
  ladder` is cheap to re-run and prints every phase with a residual.

#### Revisit trigger

**A phase crossing the control row's spread against a previous run** —
that is the ladder doing its job. And the specific one: **if combat is
still the largest phase when #287 picks D-018's successor player count**,
the frontage trade should be re-priced deliberately rather than inherited.

---
