### D-20260828 · 2026-08-28 · Accepted — a squad looks up its buildings, it does not walk the match

**Decision:** the client's two building lookups —
`_nearby_building_boxes` (which men are pushed out of) and
`_building_box_near` (which enemy building a melee squad wraps) — take
their candidates from `WorldIndex`, a coarse world grid rebuilt with the
building scan once per frame. Each then applies **exactly the test it
always applied**, so the set is unchanged and only how it is found
differs.

`bench_render.gd` indexes identically, because #240's whole point is that
the benchmark runs the client's code rather than a copy of it.

## What it cost, and the knob that showed it

Continuing the standing performance directive after
`D-20260828-inside-the-derive-phase`. The decoration phase is the
frame's largest, so it was attributed the same way — and its `gather`
half split into parts:

| at 1,000 squads / 630 drawn | ms/frame |
|---|---|
| tree discs | 22.22 |
| **building boxes** | **15.57** |
| jostle | 11.53 |
| opponent derivation | 10.75 |
| activity + speed (residual) | 7.10 |

The boxes line looked ordinary until the benchmark was given a
`--buildings=` knob and asked how it SCALES. On the shipped map, Intel
Iris Xe, 60 frames:

| buildings | 12 | 60 | 200 |
|---|---|---|---|
| box lookup | 12.94 ms | 59.50 ms | **199.19 ms** |
| per building | 1.08 | 0.99 | 1.00 |

**One millisecond per building per frame**, dead linear, while every
other part of the gather stayed flat (enemy 9.0 → 9.9, discs 18.3 → 20.4,
jostle 9.6 → 11.1).

That is worse than #262's jostle, because **buildings are the one thing
in a match that only ever accumulates**: D-030 makes a building known
forever once seen, a wall is one building PER CELL (D-076), and nothing
is ever removed from `_building_scan`. Two hundred buildings — an
ordinary count once anyone builds a wall — spent more of the frame
finding buildings than doing everything else put together.

## What it costs now

Interleaved, same instrument, same session, 200 buildings, 1,000 squads:

| pass | walk | index | |
|---|---|---|---|
| 1 | 265.85 ms | **36.48 ms** | **7.3x** |
| 2 | 250.35 ms | **40.90 ms** | **6.1x** |

`discs` — the control, untouched — stayed at 28.28 → 21.98 and
25.48 → 25.14 across the same pairs. And the scaling is no longer linear:
12.94 / 59.50 / 199.19 becomes **6.75 / 9.01 / 17.07** at 12 / 60 / 200,
so the twelve-building case is *cheaper* too.

## Why a world grid and NOT `TorusSpace.disk_offsets` — measured, not argued

The standing rule is to reach for `disk_offsets` before `distance()`, and
**a cell-disk index was written first**, on exactly that reasoning: a
building is at a cell, the client already derives its position from
`space.from_index(info.cell)`, so the cell is the natural key and the
seam handles itself.

**It measured ten times worse than the walk it replaced** — 12.94 ms to
131.82 ms at twelve buildings. The reason is arithmetic. The query reach
is `SQUAD_CULL_RADIUS + 6` plus the widest building, about fourteen world
units, and a cell is 1.73 across: that is a disk of **469 cells** scanned
per squad per frame to find twelve buildings.

So the rule earns a boundary, and it is worth stating plainly:

> **`disk_offsets` is for avoiding a `distance()` per candidate over a
> radius of a FEW CELLS. It is not for finding sparse things over a
> radius of many.**

It remains right for `_nearby_node_discs` (radius 4, and node cells are
dense enough that most of the disk hits). It is wrong here, and the
bucket width in `WorldIndex` is chosen from the query's own reach so a
lookup is a 3x3 neighbourhood whatever the radius — which is what
`drawn_index.gd` does, one phase over, for the same reason.

This is the third index in three changes and they do not share code on
purpose: `DrawnIndex` holds per-soldier positions in lattice-copy space
and does the per-man test itself; `WorldIndex` holds payloads and only
narrows. The shape is the same; the contents, the coordinate systems and
the callers are not.

## Two bugs the test caught before the measurement did

Both in the first `WorldIndex`, both found by comparing against the walk
rather than by looking at the answer:

- **Entering a thing into every bucket it reaches into returns it
  several times**, when the query's neighbourhood overlaps more than one
  of them. The big-building case reported `[0, 0, 0, 0, 0, 0]` against
  `[0]`.
- **And it does not help anyway.** The caller's test is "within my search
  plus ITS extent", which is a question about the CENTRE — so the query
  has to widen by the widest entry's reach regardless. One bucket per
  entry, `_widest` remembered, span widened at query time.

## Consequences

- **`_building_box_near` is indexed too.** It walked the same scan, once
  per squad looking for a target, and the same argument applies. Its test
  is a strict subset of the same superset property, and the nearest-wins
  tiebreak is untouched because the test is untouched.
- **Nothing a player sees changes.** Same buildings, same order of
  preference, same push-outs. `tests/test_world_index.gd` asserts the set
  against a reimplementation of the walk over three spreads and 900
  probes, with a vacuity check that somebody is in range.
- **The costs are counted, not timed** — candidates returned per query
  (28 of 60 buildings, 34 of 240) and per frame (849 / 3,924 / 12,820 at
  12 / 60 / 200 against the walk's 2,400 / 12,000 / 40,000). A wall-clock
  assertion on a shared host goes red with nothing wrong (D-106's
  amendment); the milliseconds above are quoted from interleaved pairs
  and gate nothing.
- **`bench-render` gained `--buildings=` and `--nodes=`**, defaulting to
  what it dressed the ground with before, so every earlier number stays
  comparable. They exist because "how does this scale with what a match
  has built" is a question only the benchmark can answer, and it is the
  question that turned an ordinary-looking 15 ms line into a 200 ms one.

## Revisit trigger

The `discs` line, which is now the largest in the gather at 22 ms and is
a 61-cell disk scan per drawn squad — the case where `disk_offsets` is
still the right table, so the lever there is the scan's own constant
rather than its shape. And the opponent derivation at 10.75 ms, which is
a second full derivation of a squad usually derived already this frame;
memoising it per frame is a candidate, and it is a cache of a pure
function within one pass rather than state that survives frames.

---

**Amendment, 2026-08-28 — the revisit trigger, both halves, one taken and
one refused.**

This entry closed naming two things left in the gather. Both were tried;
they came out opposite ways, and the one that failed is the more useful
of the two.

**The tree discs: taken, 26%.** `_nearby_node_discs` walks a disk of
cells around a squad and asked `space.index(centre_cell + offset)` for
each one — sixty-one calls per drawn squad per frame at the radius it
uses. `D-20260828-inside-the-derive-phase` had already priced a GDScript
call at **0.174 us against 0.095 us for the wrap arithmetic inside it**,
so that was most of the cost of the scan and none of its work.
`TorusSpace.disk_indices` answers the whole disk in one call, with the
wrap staying exactly where D-008 requires. Interleaved, 1,000 squads:

| pass | per-cell call | one call | |
|---|---|---|---|
| 1 | 20.05 ms | **14.96 ms** | −25.4% |
| 2 | 21.97 ms | **15.92 ms** | −27.5% |

`jostle`, untouched, was the control: 10.49 → 10.59 and 11.52 → 11.70.
Same cells in the same order, pinned against `disk_offsets` +
`index()` over every cell of a test map at four radii.

**The opponent derivation: tried, measured at a 6% hit rate, reverted.**
A squad in a melee is derived twice a frame — once as itself, once as
somebody's opponent — so memoising the derivation for the frame looks
free: it is a cache of a pure function keyed by its own arguments, it
survives no frame, and there is no invalidation to get wrong.

It was written, tested (identical answers, a copy on the way out because
the render pipeline writes back into the array it is handed, and nothing
outliving `now`), and then measured: **63,270 derivations, 4,050 served —
6.0%**. Deriving 6% less while paying an array copy and a dictionary
write on the other 94% measured *slightly worse*, and the interleaved
pairs said so (enemy 9.76 → 10.15 and 8.50 → 10.66 ms).

**The reason is a rule this project already had, pointing the other way.**
The client derives an opponent at the ASKING squad's detail tier, not the
opponent's own, and `client.gd` says why in as many words: *"pairing
against men the enemy is not drawing would aim strikes at empty
ground."* Two callers asking about the same squad therefore usually ask
DIFFERENT questions, and a memo keyed on the answer cannot merge them.
Making them agree would mean pairing against men nobody drew.

So the duplicate derivation is not duplicate work — it is two different
answers that happen to be about one squad. Recorded rather than dropped,
because "derive each squad once per frame" is the obvious next idea and
this is the measurement that says what it is worth.

---

**Second amendment, 2026-08-28 — inside `pipeline`, so "what remains is a
design call" is a measurement.**

The gather is attributed and levered; `pipeline` — `SquadRender.frame`
itself — is the other half of the phase and was the largest single line
left in the frame. Attributed by the same ablation method: nothing
restructured, nothing shipped touched, only the INPUTS varied, two
passes.

Per squad of **12 drawn men**, at the mix the benchmark measures being
handed to the pipeline at 1,000 squads (**0.2 boxes, 0.4 discs and 2.5
foreign men per drawn squad** — the obstacle figures below are for a
squad that HAS one of each):

| part | us per squad | share of a melee |
|---|---|---|
| duel pass — pairing, seam alignment, stepping into contact | 45.1 / 40.8 | **~40%** |
| survivor easing and the jostle it applies | 37.5 / 36.3 | **~34%** |
| decoration — strike, sway, footfall | 12 to 20 | ~13% |
| the floor — the call, the drawn-men copy, the clip, the plumbing | 10.4 / 10.1 | ~9% |
| push-outs, when a box and a disc are near | 15.0 / 16.7 | (~4 amortised) |

Decoration is quoted as a range because it genuinely is one: an IDLE
squad takes `decorate_all` (~12 us) and a WORKING one the activity path
(~20 us).

**Every line of that is D-006 clause 2 render work — it is the feature.**
The duel pass is Tier 1 of the RTW programme (each man paired, faced and
stepped into contact); the easing is what stops a restamped formation
snapping; the decoration is the sway and footfall that make a standing
squad look alive. There is no lookup to index, no invariant to hoist and
no delegation to collapse: it is per-man work whose cost is the
per-operation cost of GDScript, the same finding
`D-20260828-inside-the-derive-phase` reached one phase over.

**So the claim that what remains is #315 or #316 is now a measurement
rather than a judgement**, and this table is the evidence page appended
to both. #315 (a lower derive cadence for distant squads) would cut the
duel pass and the easing together, because a squad not re-derived is not
re-paired either; #316 (D-021's hatch) would cut all of it. Nothing else
would.
