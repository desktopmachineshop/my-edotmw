### D-20260818 · 2026-08-18 · Accepted — the flow-field solver was 93% neighbour lookup, and the latency budget was spending the difference

**Decision:** `TorusSpace` gains **`neighbor_table()`** — the six
neighbours of every cell, flat, stride 6, built once and cached for the
life of the space — and `FlowField.expand()` reads it instead of calling
`TorusSpace.neighbor_index()` six times per cell. With the solver 21x
cheaper per cell, **`SquadSim.DEFAULT_FIELD_CELLS_PER_TICK` rises 4,096 ->
16,384**, which is what a player actually feels.

D-040 is otherwise untouched and still in force: fields are still one per
destination and shared (D-007), still spread across ticks under a
per-tick CELL budget, still FIFO, and a partial field is still correct
wherever it is defined. Only the constant and the cost per cell change.

Closes #107 (M10 workstream 2). Discharges
`D-20260817-m10-scale-optimisation` criterion 3.

---

**Rationale.** The issue reported `field_waits=2,968` over a 3,005-tick
run and framed the fix as spending D-040's trade back: raise the budget
against the worst tick's ~55 ms of headroom, or build a coarse field. Both
took the per-cell cost as given. It was not given.

Measured on the shipped 168x194 map (26,719 passable cells), native Godot
4.7.1 on this host:

| | full field | per cell |
|---|---|---|
| `neighbor_index()` x6 per cell | **228.2 ms** | 8.54 µs |
| `neighbor_table()` lookup | **10.4 ms** | 0.40 µs |

`neighbor_index(i, dir)` is `index(from_index(i) + DIRECTIONS[posmod(dir,
6)])` — a method dispatch, a posmod, an integer division, a Vector2i, an
add and two more posmods — and the BFS did it six times per cell for
nothing: the answer depends only on the lattice, which does not change
during a match. **This is the fifth instance of one defect in this
project** (vision's `distance()` per candidate cell, `UnitRoster.by_id`
per produced squad, terrain noise per soldier per frame, the per-squad
building scan), and it is filed with them rather than as a pathfinding
curiosity, because the pattern is now the most reliable optimisation lead
here: *a hot loop recomputing a wrap-aware derivation per element.*

**What the budget buys now.** Latency is not `cells / budget` — a BFS from
the destination reaches a squad after covering only the cells CLOSER than
it — so it was measured directly, over 114 spawn-to-spawn orders on the
shipped map, counting the ticks a squad stands still:

| budget | worst wait | mean wait |
|---|---|---|
| 4,096 (shipped) | **6 ticks (0.6 s)** | 2.58 |
| 16,384 | **1 tick (0.1 s)** | 0.31 |

And the per-tick expansion bound — the number D-040's budget exists to
cap — falls at the same time, because 4x the cells at 1/21 the price is
still a fifth of the bill:

| | cells/tick | µs/cell | bound |
|---|---|---|---|
| before | 4,096 | 8.54 | **35 ms** |
| after | 16,384 | 0.40 | **6.6 ms** |

So this is not the trade the issue described. The budget does four times
the work for a fifth of the cost, and no headroom was spent.

**A/B at 1,000 squads on the default map**, 200 ticks, 8 rally points,
one process per column (a scratch harness modelled on `profile_sweep`):

| budget | before: µs/field | after | before: worst tick | after |
|---|---|---|---|---|
| 4,096 | 17,500 | 1,220 | 342.9 ms | **204.5 ms** |
| 8,192 | 32,158 | 2,351 | 327.7 ms | 259.1 ms |
| 16,384 | 116,102 | 4,074 | 1,544.6 ms | **207.5 ms** |
| 32,768 | 429,271 | 7,299 | 2,618.7 ms | 228.3 ms |

Two things to read out of it. **Raising the budget was not available
before this change** — at 16,384 the worst tick was 1.5 seconds — so the
issue's lever 1 could not have been pulled on its own. And `field_waits`
is *identical* before and after at every budget (173,953 / 168,084 /
160,207 / 156,564), which is the check that this is a speed change and
nothing else: the same cells are expanded in the same order, only faster.

That sweep's absolute worst tick is over D-020's 100 ms budget both
before and after, and **that is not this change** — it is 1,000 squads on
a map four times the old area, with the per-squad rise #105 exists to
attribute. This change improves it by 40% and does not close it.

---

**The ladder, and why the constant is flat.** At 16,384:

| map | cells | table | full field | worst wait | mean |
|---|---|---|---|---|---|
| Skirmish 84x96 | 8,064 | 189 KB | 2.3 ms | **0 ticks** | 0.00 |
| Standard 168x194 | 32,592 | 764 KB | 10.4 ms | **1 tick** | 0.14 |
| Large 252x290 | 73,080 | 1.7 MB | 28.6 ms | 3 ticks | 1.43 |
| Huge 336x388 | 130,368 | 3.0 MB | 49.9 ms | 6 ticks | 3.24 |

**The budget stays a constant rather than becoming a fraction of the
map, on purpose.** D-040's stated property is that the worst tick is FLAT
in map size, and a budget of `cell_count / 2` would trade that away to buy
flat latency instead — 40 ms of every Huge tick spent on BFS. The price of
keeping it is the top two rungs: 0.3 s on Large and 0.6 s on Huge, against
1.8 s and 3.2 s before. Both are stated rather than hidden, per criterion
3's own wording.

Raising it again is now one number: at 32,768 the ladder reads 0 / 0 / 1 /
3 ticks, for a 13 ms per-tick bound — still under half what shipped. It is
not raised today because 0.1 s on the DEFAULT map is what was asked for,
and a bigger constant buys only the two sizes nobody has played.

**Rejected alternatives.**

- **Coarse-to-fine fields** (the issue's lever 2). A real design, and now
  unnecessary: it answers "which way, roughly, in one tick", and one tick
  is what the default map already costs. It would also need a second
  resolution of passability, a fine-cell walk guided by a coarse
  direction, and a second answer to "is this cell covered" — a subsystem,
  against a 60-line table.
- **Steering the BFS toward waiting squads** (A* with a toroidal
  heuristic). Would cut cells expanded roughly in half, and breaks the one
  property everything here rests on: BFS finalises a cell on DISCOVERY, A*
  only on POP, so `covers()` would stop meaning "has a final answer" and
  D-040's give-up rule would start cancelling live orders. Rejected on
  risk, not on cost.
- **Building the table by looping over `neighbor_index`** — one definition
  of a neighbour, no new arithmetic. 341.5 ms against 14.7 ms row-wise,
  which is the difference between a lazy first build being invisible and
  being a dropped tick. Taken instead: the row-wise build, plus a test
  that asserts the table equals `neighbor_index` for **every cell and
  every direction** on two shapes including an odd width. `neighbor_index`
  stays the definition of record; the table is a memoisation held to it.
- **Caching the table statically, like `disk_offsets`.** A disk offset is
  translation-invariant and independent of width and height; a neighbour
  index is neither. Per instance, with the dimensions it was built for
  remembered — `width`/`height` are `@export`, so a 64x64 space reshaped
  to 32x128 keeps its cell count and would otherwise keep a wrong table.
  There is a test for exactly that.

**Consequences.**

- **Memory: 764 KB per `TorusSpace` on the shipped map, 3.0 MB at Huge**,
  and the client builds one too. Against #111's 43.3 MB server this is
  small, but it is new and belongs in that issue's accounting.
- **Build cost is 14.7 ms (shipped) / 46.9 ms (Huge), once, lazily** on
  the first field of a match. It is inside a tick at every ladder size, so
  it is left lazy rather than warmed at setup; if #111 or #106 wants it
  moved, `TorusSpace.neighbor_table()` is idempotent and calling it at
  world build is a one-liner.
- **The wall-top layer (D-076) gets the same speed-up for free**, since
  `_field_for_top` builds an ordinary `FlowField`.
- **Nothing about the wire, the sim's outputs or determinism changes.**
  Same cells, same order, same distances — asserted against an
  independent BFS written through `neighbor_index`.

**What this implies for per-squad destinations (#120's explore command).**
D-007's sharing claim is that one field serves every squad heading
somewhere, and an explore order is the case it cannot help with: N squads,
N frontier cells, N fields. The 1,000-squad sweep above already exercises
that shape by accident — arrival separation (D-060) gives each arrived
squad its own free cell, so 8 rally points produced **518 field builds**,
not 8. What changed is the price of one: **228 ms -> 10.4 ms on the
shipped map**, so a wave of 20 explore orders is 0.2 s of solver work
instead of 4.6 s, and the per-tick budget spreads even that across two
ticks. **The remaining bound is memory, not time:** `SquadSim._fields` is
never evicted, so 20 unique destinations cost 20 x 163 KB of cached field
for the life of the match, and a per-squad explore order makes that grow
with orders given rather than with places worth going. An explore command
should be built against that bound; an LRU eviction on `_fields` is the
obvious answer if it bites, and it belongs to #111.

**Revisit trigger:** if a played match on Large or Huge reports pathing
that feels slow, raise the constant (the numbers are above) rather than
building coarse-to-fine. If the per-tick expansion bound ever shows up in
a phase breakdown of an over-budget tick, the budget is finally binding on
cost rather than on latency, and D-040's trade is being spent for the
first time.
