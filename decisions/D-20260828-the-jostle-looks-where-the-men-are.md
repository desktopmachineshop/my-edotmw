### D-20260828 · 2026-08-28 · Accepted — the jostle looks where the men are

**Decision:** the cross-squad jostle finds its neighbours through
`DrawnIndex` — a uniform grid over the men each squad was DRAWN at last
frame — instead of walking every squad the match has ever drawn. Same
predicate, same men, and the per-squad work stops growing with the number
of squads on screen. The index is also PRUNED each frame: a squad nobody
is drawing has no men on screen for anyone to jostle against.

From #262, which came out of #240 the moment the benchmark started
running the client's own render passes.

## What it cost

`client.gd` held the previous frame's drawn men in a plain dictionary and,
for every STANDING squad, walked all of it:

```gdscript
for other_id in _drawn_cache:      # every squad ever drawn
    ...distance test...
    for k in range(men.size()):    # ...and each of its men
```

Measured on the shipped 168x194 map, native, **Intel(R) Iris(R) Xe
Graphics**, 90 frames per row, camera height 40:

| squads | drawn squads | jostle before | jostle after | frame cpu before | after |
|---|---|---|---|---|---|
| 100 | 63 | 1.75 ms | **0.29 ms** | 27.98 | 12.26 |
| 250 | 155 | 8.99 ms | **0.91 ms** | 65.92 | 29.75 |
| 500 | 321 | 30.22 ms | **2.33 ms** | 126.72 | 62.65 |
| 1000 | 630 | 152.43 ms | **6.10 ms** | 387.51 | 118.65 |

**25x at 630 drawn squads**, and the frame went 2.3 fps to 8.3.

## Read the ratio, not the absolutes

Those two ladders were taken on the same machine hours apart, and the
host was quieter for the second: `derive`, which this change does not
touch, fell 71.33 -> 30.31 ms on its own. Quoting 387 -> 119 as if it
were all this change would be the wall-clock mistake this project keeps
paying for.

So the honest measure is the jostle expressed against a phase that did
NOT change, which cancels the host:

| drawn squads | jostle / derive BEFORE | AFTER | |
|---|---|---|---|
| 63 | 0.21 | 0.088 | 2.4x |
| 155 | 0.51 | 0.116 | 4.4x |
| 321 | 1.00 | 0.141 | 7.1x |
| 630 | **2.14** | **0.201** | **10.6x** |

**The shape is the result.** Before, that ratio DOUBLED with every rung —
a quadratic pass measured against a linear one. After, it is nearly flat
(0.088 -> 0.201), drifting up only because a fixed camera holding more
squads genuinely puts more men near each other, which is the work the
feature is defined as. The pathological term is gone; what is left is
proportional to how many men are actually nearby.

## The same men, proved by the mechanism from two PRs ago

`just bench-check` reports **`STALE  render_path`** and **no COUNT
lines**: every gated count — soldiers, drawn men, drawn squads, draw
calls, the activity mix — is identical across the change. The render path
moved, which is exactly what the fingerprint is for, and nothing about
what is DRAWN did. That is
`D-20260828-render-cost-has-a-recorded-baseline` doing the job it was
built for, on the first real change after it landed.

`tests/test_drawn_index.gd` asserts the same thing directly, against a
reimplementation of the walk it replaces, over four spacings — including
the vacuity check that at those spacings somebody actually has
neighbours.

## Why a world grid and not `TorusSpace.disk_offsets`

This project's standing rule is to reach for `disk_offsets` before
`distance()`, and it is the right rule for anything indexed by CELL. It
is the wrong table here, and the reason is D-20260818: these are the
positions squads were DRAWN at, which is a LATTICE COPY. Two squads a map
apart in canonical space can be adjacent on screen, and two copies of one
squad are legitimately a map apart in this space. Normalising them onto
the torus would merge what the renderer deliberately keeps separate and
change which men jostle. The grid indexes exactly the space the predicate
is written in, which is what makes the result provably identical rather
than approximately so.

**And `combat.gd`'s bucket map was checked before this was written, as
asked.** It is `cell index -> squad ids` over a `SquadSim`, rebuilt per
combat round, on the SERVER (D-024, server-only). This holds per-soldier
DRAWN positions on the client, one frame stale, in lattice-copy space.
They share a shape and nothing else — no data, no side of the wire, no
coordinate system — and sharing nine lines of dictionary-building would
couple a server file to the render path for no saving.

## D-006 is untouched

`DrawnIndex` holds per-soldier render state, which clause 2 as amended by
D-20260819 permits when it is bounded, one-way and outcome-blind. All
three hold and two are now structural: it is bounded by the squads DRAWN
(`begin` empties it every frame, which the old dictionary never did), it
is written only by a drawing surface, and
`test_nothing_simulation_side_reads_the_drawn_index` scans every script
to keep it that way — the same guard `test_tier_three.gd` runs for
`SoldierMotion`. Cosmetic offsets are still never read back.

## Two things that changed behaviour on purpose

- **Stale squads are dropped.** The old dictionary was never pruned, so a
  squad culled, concealed or killed went on shoving its neighbours with
  the men it had when last drawn. Now only squads drawn this frame
  contribute. This is a visible change and it is the right one.
- **The order is deterministic.** The walk iterated a dictionary, so
  neighbours arrived in whatever order squads were first drawn — a thing
  two clients can disagree about. The index returns ascending squad id.
  Nothing downstream reads the order (`SoldierMotion.ease` sums a
  repulsion per man and skips anything past `JOSTLE_RADIUS`), so this
  changes no picture; it removes a way for two machines to differ.

## The mistake in the middle, because it is the interesting one

The first version sized buckets from the widest formation in the index,
which is only known after the last `put` — so it deferred bucketing to
the first QUERY. The caller interleaves puts and queries as it walks its
squads, so that re-bucketed every record on every query: **the quadratic
rebuilt inside its own fix.** It measured worse than the walk it replaced
(jostle 152 -> 188 ms at 630 drawn squads) and the ladder is what said
so. Buckets are a constant width and filled incrementally now, and
`neighbours_of` widens its own span when a formation is wider than one —
slower for a wide formation, never wrong.

## Revisit trigger

The remaining growth is local density: a fixed camera holding more squads
puts more men near each other. If that ever dominates again the lever is
the per-MAN loop rather than the search — `SoldierMotion.ease` discards
everything past `JOSTLE_RADIUS` (0.45) while the gather hands it
everything within `world_radius + 1.0`, so a tighter hand-off is available
and is provably equivalent. Not taken here: it is a smaller win than this
one and it wants its own measurement.
