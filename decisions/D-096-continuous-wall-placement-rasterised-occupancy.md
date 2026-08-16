### D-096 · 2026-08-14 · Accepted — continuous wall placement, rasterised occupancy

**Decision:** A wall-family structure (`footprint_radius == 0` — wall, gate,
garrison wall, garrison gate, access tower) stops being "one building that
owns one hex cell". It gains a continuous world position and a continuous
rotation, and the cells it blocks — and the cells that carry its tier-1
walkway — are **derived by rasterising its swept rectangle**, rather than
being the one cell it was placed on.

Concretely:

- `BuildingSim` keeps `_cell` as the **anchor** (the cell the structure's
  centre falls in). Everything that buckets by cell — combat targeting,
  vision stamping, the minimap, selection — keeps working untouched.
- It gains `_offset`, a sub-cell continuous displacement in world units, and
  `_facing` becomes a continuous angle for the wall family instead of one of
  six directions. True position is `space.to_world(cell) + offset`.
- `occupied_cells()` / `blocking_cells()` rasterise the rotated
  `mesh_size.x × mesh_size.z` rectangle centred on that true position.
- A placement drag lays segments **end to end along the true dragged line**
  at exact `WALL_LENGTH` spacing, each rotated to the line's real angle —
  not one segment per hex cell.

**Rationale:** Grid-locked walls were the most-reported visual problem in
playtesting, and every symptom traced to the same root. Segments snapped to
cell centres and to one of six angles cannot follow a shoreline, a ridge, or
any line a player actually wants to hold. A bend left a gap that had to be
plugged with a cylindrical post. A gatehouse drawn wider than one cell was
overlapped by the very walls meant to meet it, because it occupied one cell
while spanning two.

The insight is that the hex grid was never load-bearing for a wall's
*appearance* — only for its *effect*. **D-008 is untouched**: cells remain
the simulation's spatial index, and flow fields, vision and combat all still
work on them. What changes is only how a wall's occupancy is *computed*.

**The failure mode this must not have** is a wall that looks solid and has a
pathing hole units walk through. Deriving blocked cells from a segment's true
swept span, rather than from its centre cell, is precisely what prevents it:
a segment that visually crosses three cells blocks three cells. This is the
"looks fine, quietly wrong" class this project keeps getting bitten by, so it
gets an explicit test — a run dragged at an arbitrary angle must leave **no**
unblocked cell along its length, and that test must be observed to fail
before it is trusted.

**Rejected alternatives:**

- *Keep cell placement, render continuously* (rejected — the picture and the
  simulation would disagree about where a wall stands. A player would aim at
  a wall that blocked somewhere else, which is worse than an ugly wall.)
- *Drop the hex grid for a square one* (rejected — costed at the same time.
  `TorusSpace` is load-bearing under ~15 files, and hex's isotropy is what
  makes vision and combat disks clean, per the standing `disk_offsets` rule.
  The grid was never the problem; the one-cell-per-wall model was.)
- *One cell per segment, tolerating duplicates and skips* (rejected —
  `WALL_LENGTH` (~1.77) and hex spacing (~1.73) are close but NOT equal, so a
  run at an arbitrary angle silently skips cells. That is exactly the
  walk-through-a-solid-wall bug above, arrived at by accident.)

**Consequences:**

- The wire carries a continuous offset and rotation per building.
- `_footprint_conflict` becomes a span-overlap test for the wall family
  rather than a cell-equality test.
- The cylindrical joint post is **replaced by an authored round bastion**,
  generated per wall style in `art/buildings/` so a stake fence gets a
  palisade roundel and a stone wall gets a stone drum. Its radius comes from
  the incoming segments' real angles, so one shape serves a corner, a T and a
  four-way junction alike. The post it replaces was a `StandardMaterial3D`
  tinted with `mesh_color` — the *primitive fallback* colour, which the
  authored wall never renders — which is why it read as a differently
  coloured spike rather than part of the wall.
- The garrison gate becomes an exact multiple of `WALL_LENGTH`, and a wall
  run snaps to its true edge instead of into its middle.
- This is **not** a step toward continuous-space simulation. Squads still
  move on flow fields over cells, elevation still does not occlude, and the
  tick still advances on cells. Any proposal to make combat or pathing
  continuous is a separate decision and does not inherit this one's rationale.

**Revisit trigger:** If per-segment rasterisation shows up in tick profiling
at D-018's full scale, or if any system starts needing a wall's continuous
position for a *simulation* answer rather than a rendering one — the latter
would mean the discrete/continuous split this decision depends on has leaked.

---
