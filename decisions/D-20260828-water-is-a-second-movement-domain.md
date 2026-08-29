### D-20260828 · Accepted — water is a second movement domain, with its own budget

**Decision:** `SquadSim._tier` gains a third value. The field keeps its
name so D-076's call sites do not churn; its doc says **domain** and the
constants are `DOMAIN_GROUND` (0), `DOMAIN_WALL_TOP` (1) and
`DOMAIN_WATER` (2). Water gets its own `FlowField` layer —
`_fields_water`, `_pending_fields_water`, `water_field_cells_per_tick` —
with `FlowField` itself unmodified and driven a third time.

Naval stage 2 of #301, implementing `docs/plans/naval.md` §2.2, §2.3 and
§2.4. This entry exists for the two things the plan deliberately left to
be **measured or decided at implementation**: the budget, and whether the
water layer is fogged.

---

**The budget is 24,576 cells per tick, and it is measured.**

§2.3's instruction was explicit — *"the budget must be measured, not
guessed"* — and it named the trap: D-076 set the wall layer to 1,024 and
D-20260818 later took the ground layer to 16,384, and neither number is
about water. `playtest_obs/obs_water_budget.gd` is the harness; it runs
directly and prints every table below.

**How much water there is,** which is what makes this different from the
wall layer at all (shipped presets, seed 1337):

| preset | Skirmish | Standard | Large | Huge |
|---|---|---|---|---|
| `islands` | **70.7%** | **68.1%** | **67.0%** | **67.2%** |
| `continents` | 20.9% | 16.0% | 16.8% | 17.9% |
| `highlands` | 5.4% | 4.0% | 4.6% | 4.2% |
| `plains` | 1.3% | 0.6% | 0.2% | 0.2% |

The design's "65–71% water" is confirmed independently. A wall-top
network is bounded by what a player has built; **water is bounded by the
map**, and on the map this feature exists for it is two thirds of it.

**What one complete field costs** on `islands`: 5,690 cells / 5.0 ms at
Skirmish, **22,149 / 33.2 ms at Standard**, 48,717 / 82.8 ms at Large,
86,989 / 130.3 ms at Huge.

**Ticks a cross-map naval order waits, by candidate budget** — the number
the budget is actually for:

| size | expanded | 1,024 | 4,096 | 16,384 | **24,576** | 32,768 |
|---|---|---|---|---|---|---|
| Skirmish | 5,690 | 6 | 2 | 1 | **1** | 1 |
| **Standard** | 22,149 | **22** | 6 | 2 | **1** | 1 |
| Large | 48,717 | 48 | 12 | 3 | **2** | 2 |
| Huge | 86,989 | 85 | 22 | 6 | **4** | 3 |

**24,576 is the smallest budget that completes a cross-map field on the
SHIPPED DEFAULT map in one tick**, which is precisely the standard
D-20260818 set for the ground layer. D-076's 1,024 would have cost
**22 ticks — 2.2 seconds — on that same map**, which is the mistake §2.3
was written to prevent. Large and Huge stay at 2 and 4 deliberately: the
budget is a constant, not a fraction of the map, for D-040's reason that
worst-tick-flat-in-map-size is worth more than flat latency on two rungs
nobody has played — the identical trade D-20260818 recorded for the
ground layer at 3 and 6.

**Worst tick, through the real `SquadSim.tick()`, quoted with its squad
count** — a fleet on `islands`, every hull ordered somewhere different so
the layer solves many fields rather than sharing one:

| size | hulls | worst | mean | field | waits/40 ticks |
|---|---|---|---|---|---|
| Standard | 8 | 15.9 ms | 2.8 | 1.8 | 23 |
| **Standard** | **32** | **21.4 ms** | 12.0 | 7.9 | 441 |
| Large | 32 | 18.8 ms | 14.6 | 11.3 | 874 |
| Huge | 32 | 41.3 ms | 24.7 | 19.7 | 1,095 |

**Inside D-020's 100 ms at every rung.** Read the waits as the budget
working rather than failing: 32 hulls ordered to 32 *different*
destinations is ~700,000 cells of solving, and spreading it is what
D-040's amortisation is for.

**What this does NOT do is close #105.** That issue records the
1,000-squad sweep already over budget at 204.5 ms, for reasons that
predate ships; nothing here is measured at 1,000 squads and nothing here
improves it. What is claimed is only the water layer's own cost, at the
squad counts above.

**§2.3's "check before writing it, not after" was checked.**
`TorusSpace.neighbor_table()` is memoised per space instance and the sim
holds one, so the water layer inherits D-20260818's 93%-neighbour-lookup
fix for free rather than paying it again. The harness asserts the table
is the same object on a second call.

---

**The water layer is NOT fogged, and that is a decision rather than an
omission.**

D-20260818 made ground pathing solve against what a **side believes**,
because unknown land can hide a lake or a wall, and a squad routed around
terrain nobody has seen is the defect that entry exists to prevent.

Water is not like that **in v1**. `navigable[i]` is exactly
`elevation(i) < sea_level` (§2.1): no building subtracts from it, no ramp
carves it, and §2.1 settles that all water is navigable. So a per-side
belief array would be **identical to the truth array, for every side, on
every tick** — fogging it would be cost with provably no effect, and a
second belief array plus its own discovery feed is a decision-sized
change that stage 2's row does not ask for.

**The premise is asserted, not trusted.**
`test_naval_domain.gd::test_nothing_subtracts_a_cell_from_the_navigable_array`
puts every building in the roster on a water cell and checks the water is
still water. §2.2 names the two cases that would break it — a sea wall, a
floating platform — and if either lands, that test fires and this layer
needs belief **before** it ships.

---

**Orders never choose a domain: the UNIT decides, the cell only decides
legality** (§2.4).

D-076 could infer a tier from the destination because a wall-top cell is
unambiguous. A shore cell is not — it is legal ground for a land squad
AND adjacent to legal water — so `_wanted_domain_for` answers a water
squad's own domain and leaves D-076's inference untouched for everything
else. An order into the wrong domain is **corrected** rather than refused
(`_corrected_destination`), the same shape as `_approachable`, which
D-20260818 deliberately left omniscient precisely because it can only
move an order and never reject one.

**This was measured failing before it passed, and the failure is the one
worth recording.** Without `_wanted_domain_for`, a hull ordered anywhere
fell into `_begin_tier_crossing` looking for an access tower, found none,
and the order was **dropped in silence** — 120 ticks, 0 fields built, a
ship that never moved, and not one thing in the log to say so. It was
found by running it, not by reading it.

---

**Rejected alternatives:**

- *A tri-state `passable` array instead of a second one.* Rejected for
  D-076's own reason, restated in §2.1: every existing caller of
  `_passable` means LAND, and a third value would be read by all of them.
- *Sharing `field_cells_per_tick`.* Rejected for D-076's argument about
  the second layer, which is stronger here: on `islands` both layers run
  constantly, so one counter would have let a naval solve halve
  ground-pathing throughput on most ticks.
- *Copying 1,024 from the wall layer.* Measured: 22 ticks on the shipped
  default map.
- *Making the budget a fraction of the map.* Rejected — see the latency
  table's note; it trades D-040's flat worst tick for flat latency.
- *Fogging the water layer for symmetry with the ground.* Rejected on the
  measurement above: provably no effect in v1, with a test that fires
  when that stops being true.

---

**Consequences:**

- **The stage-2 / stage-4 seam is an ORDERING, and it is guarded.** An
  embark order (naval stage 4) deliberately names a cell in the other
  domain — a land squad ordered onto the water cell a transport sits on —
  and a landing order deliberately names land for a hull. §2.4's
  correction would swallow both if it ran first, so it runs **after** them
  in `order_move`, and
  `test_the_correction_does_not_swallow_an_embark_order` is what stops a
  future edit reversing it. Inverted deliberately, it reds 13 tests. The
  symptom otherwise would be "embarking silently stopped working".
- **`set_navigable` clears the water caches**, for D-040's reason: a
  field still mid-solve holds a reference to the array that just went
  stale. Guarded behaviourally — a hull under way when the channel closes
  must find the remaining gap rather than sail into the new land.
- **Nothing on the wire changed.** A squad's domain rides in
  `SQUAD_INFO`'s existing `tier` byte, which has carried three-valued
  data since D-076 in everything but name.
- **Stages 3, 4 and 6 were built against these signatures before they
  existed** and needed no change when they arrived, which is the one
  claim about the pinned interface that could only be tested by writing
  the implementation last.

**Revisit trigger:** anything that subtracts a cell from `_navigable` — a
sea wall, a floating platform, or shallow/deep draft (§2.1's own named
trigger). Each makes water discoverable, and the first of them makes the
belief question real. Also: if `just profile` is ever extended to sweep a
naval map, its worst tick supersedes the 32-hull figures here, which are
a fleet and not a full army.

---
