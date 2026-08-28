**The scale TARGET is measured as of 2026-08-28**
(`decisions/D-20260828-the-shipping-scale.md`, #287), and it re-scopes
everything on this page: **~200 squads / ~3,100 soldiers**, recommended
as 8 players x 25 squads, superseding D-018's 1,000 / 40,000. Both
budgets land there from opposite directions — D-020's 100 ms **worst**
tick crosses between 180 and 240 squads (`just profile scale`), and
30 fps on Intel Iris Xe crosses at ~200 (`just bench-render`, two
passes). **The budget is a TOTAL**, so `squad_cap` should be derived from
the seat count rather than being 40 for everybody; at 40 the lobby's own
24-seat ceiling is 960 squads, nearly five times what the tick holds.

Two consequences for what is written below. **The 1,000-squad sweep being
over budget (204.5 ms) stops being a shipping problem** and becomes a
headroom question, because nothing ships at 1,000 squads — #105's
attribution stands, its urgency does not. And **the host pays BOTH
budgets** (D-088 runs the server in-process inside a player's client),
which nothing has ever measured; that is #339 and it may be the binding
constraint.

## M10 (scale optimisation) — PLANNED, not built

The map ladder moved up a rung on 2026-08-17 so the zoom cap could stop
showing the same ground twice
(`decisions/D-20260817-the-zoom-cap-was-modelling-the-wrong-axis.md`).
The default map is **168 x 194 = 32,592 cells**, four times its old area,
and the owner has confirmed the scale is wanted.

**M10 is the work that makes that shippable, and it runs BEFORE M8.**
Exit criteria are `decisions/D-20260817-m10-scale-optimisation.md`,
written before any of the code. Every item is independently tackleable
and independently measurable; they are filed as **issues #105-#112**
against the `M10 — scale optimisation` milestone.

**What it costs today, measured rather than feared:**

| | measured | how |
|---|---|---|
| terrain meshing at client start | **5,071 ms**, 143 chunks — *sliced, see below* | `just gen-terrain-preview` |
| flow-field waits | **2,968 of 3,005 ticks** — *fixed, see below* | `just test-load 4 300` |
| per-squad update | **167.7 µs at 48 squads** (was ~83 at 28) | same run |
| worst tick | 44.9 ms, **0 dropped** | same run |
| server memory | 43.3 MB with **4** squads | `quick-test` |
| resource nodes | 7,694 (was 1,958) | same |

The **server is fine** — the tick budget is met with 55 ms of headroom.
What is not fine is the **client**: five seconds of blocking terrain
meshing before a match is playable. That is the one a player feels first,
and it was found by a human closing the window and asking whether the
server was down. **That freeze is gone (#106, done)** — see the bullet
below.

**Three things to know before picking up any of it:**

- **Attribute the per-squad rise first (#105).** 83 -> 167.7 µs while vision and
  combat both *fell*, so the cost moved somewhere unnamed. Until that is
  explained no other optimisation here can be shown to have worked — and
  M6's older, still-unattributed 40.8 -> ~77 rise is the standing proof
  that unexplained numbers do not explain themselves later.
- **`just profile` sweeps the shipped ladder now (#108, done).** It topped out
  at 32,768 cells, which is the *default* map; it runs 8,064 to 130,368
  from `MapSettings.sizes()` — the ladder's own definition, so the two
  cannot drift apart again. The re-taken curve is **flat**: 16x the map
  area costs 13% of worst tick (84.8 -> 96.1 ms), all inside D-020's
  budget. What the bigger map really costs is PATHING LATENCY — 97% of
  squad-ticks wait on an unfinished field at the top of the ladder, which
  is #107's number and the sweep's first sight of it. Both runs, and the
  reason the deterministic COUNTS are the trustworthy columns, are in
  `decisions/D-20260818-the-sweep-follows-the-ladder.md`. Read the
  standing warning with it: **a green sweep is not a green server**, and
  where the two disagree the live run wins.
- **The per-squad rise is attributed (#105, done):** it is the
  **flow-field expansion slice** (D-040), and the reason no reported phase
  moved is that the tick had only two reported phases. Every region of
  `SquadSim.tick()` is timed and printed now, with a computed residual —
  `decisions/D-20260818-every-microsecond-of-a-tick-has-a-phase.md` has
  the A/B (same squads, same orders, only the map changes: field expansion
  52.5 -> 453.1 µs/squad on 4x the cells, every other phase FELL, residual
  0.03%). The mechanism is a per-TICK cell budget divided by a squad
  count, which is D-040 working as designed — spending it better is #107,
  not this. **M6's older 40.8 -> ~77 rise is declared SEPARATE** in the
  same entry: those two numbers were taken at 120 and ~52 squads on builds
  with no breakdown, so no attribution can be recovered from them, only
  invented.
- **`just profile` currently cannot see the shipped ladder (#108).** Its sweep
  tops out at 32,768 cells, which is now the *default* map; the largest
  size is 130,368. The sweep is this project's authority on scaling, so
  re-basing it is a prerequisite for trusting anything it says.
- **The client's start-up freeze is gone (#106, done).** The ground is built
  in slices budgeted in CELLS — D-040's flow-field amortisation pointed at
  the other side of the wire — and the player watches a **loading bar** until
  the last chunk is in the tree.
  `decisions/D-20260818-terrain-builds-a-slice-at-a-time.md` has the
  measurements. Three of them are worth knowing before touching this again:
  slicing costs **nothing** (streamed vs one pass, same process, same host:
  41.4 s vs ~41.0 s on a badly loaded host); **D-017's chunk size survives its
  own re-measurement**, because total meshing cost is FLAT in chunk size and
  the knob only buys granularity; and the accepted budget is now the owner's
  **30 seconds behind a bar**, which `client.gd` warns about exceeding rather
  than merely quoting. The remaining lever is a worker thread — it is the only
  one that reduces total wall clock rather than spreading it.
- **The biggest item (#110) is the one twice rejected on scope**: drawing
  entities at every visible lattice copy. It deletes the recurring
  copy-choice bug class (armies vanishing at the seam, "half the screen
  renders no units", click-selects-nothing, forests snapping a map period
  sideways), fixes two known live bugs for free, and would let the zoom
  cap rise instead of the map ladder having to carry it.

**What is NOT in M10:** the zoom cap itself is fixed and its bug class is
closed. Culling has been cleared twice by measurement — 0 wrongly-culled
chunks in 36,288 tests on the old map and 41,184 on the new one — so a
report of forests popping is not a culling fault and should not be
diagnosed as one.

## Landed

**Workstream 2, flow-field latency (#107), 2026-08-18 — criterion 3
discharged.** A cross-map move order on the default map waited **6 ticks
(0.6 s)** and now waits **1 (0.1 s)**, and the per-tick cost of the budget
that bounds it FELL, from ~35 ms to ~6.6 ms. Full entry, with the ladder
and the A/B, in
`decisions/D-20260818-the-flow-field-solver-was-93-percent-neighbour-lookup.md`.

The lever was not the one the issue named. Raising `field_cells_per_tick`
was measured to be unavailable on its own — at 16,384 the worst tick was
**1.5 seconds** — because the solver was spending **93% of its time in six
`TorusSpace.neighbor_index()` calls per cell**, recomputing a wrap-aware
derivation that depends only on the lattice. `TorusSpace.neighbor_table()`
memoises it (764 KB on the shipped map, 3.0 MB at Huge), a full field went
**228 ms -> 10.4 ms**, and the budget could then go 4,096 -> 16,384 for a
fifth of the old cost. **Fifth instance of the same defect** after vision's
`distance()` per cell, `UnitRoster.by_id` per produced squad, terrain noise
per soldier per frame and the per-squad building scan — so before reaching
for a design (coarse-to-fine fields, in this case), price the loop first.

Two things left open on purpose. **Large and Huge still wait 3 and 6 ticks**
(0.3 s / 0.6 s, against 1.8 s / 3.2 s): the budget is deliberately a
constant, not a fraction of the map, because D-040's worst-tick-flat-in-map-size
property is worth more than flat latency on two rungs nobody has played —
raising it to 32,768 takes the ladder to 0/0/1/3 ticks and is one number
away. And the 1,000-squad sweep is still **over** D-020's 100 ms tick both
before (342.9 ms) and after (204.5 ms); that is **#105's** unattributed
per-squad rise, not this, and it is not closed.
