**Naval stage 1 — the water graph — is built
(D-20260828-the-water-graph-is-the-inverse-of-the-ground, #301,
`docs/plans/naval.md` §7 row 1).** Water has a field, shores have a
predicate, and water components come out of the walk the map already
uses. **Nothing in the simulation changed**, which is what that row asks
for: this is the base every other naval stage builds on, so its answers
are pinned before anything depends on them.

```gdscript
var navigable := terrain.navigability(space)          # 1 iff below sea level
TerrainGen.is_shore(space, passable, navigable, i)    # static, both fields in
MapConfig.walkable_components(space, navigable)       # water bodies, no new walk
```

Four things to know before building stage 2 or 3 on it:

- **`navigability` is a SEPARATE array, not a third value in
  `passability`.** D-076's reasoning for keeping its wall-top field
  cache separate, reused: `_passable` has many readers and every one of
  them means LAND. A tri-state array would be read by all of them, and
  the ones that never learned the third value would not fail — they
  would treat open water as walkable ground.
- **The cut-list's "disjoint and cover the map" is half right, and the
  half that is wrong is load-bearing.** Disjoint: yes, on every preset,
  after ramp carving. Cover: **preset-dependent** — land too steep to
  walk is in neither field. Measured at 48x24, seed 1337: `plains`,
  `highlands` and `islands` are fully covered; `continents` leaves
  **91 of 1152 cells (7.9%)** in neither. What partitions the map is the
  DOMAIN — navigable is the water half, its complement the land half —
  and passability is a rule WITHIN land. Stage 2 dispatches on domain
  and stage 9 places spawns over these fields; a reader who believed the
  slogan would write `if not navigable then walkable` and put an army on
  a cliff.
- **`highlands` could not demonstrate that gap**, which is worth knowing
  because it is the preset anybody would reach for: D-20260826 opened it
  up completely ("44.1% dead space … fully open now"), and the same
  change gave `continents` real walls. The test measures the whole
  ladder and prints the table rather than asserting on one preset.
- **`is_shore` takes both fields as ARGUMENTS**, because which
  passability a caller means is a real question: `TerrainGen.passability`
  is the ground, `SquadSim._passable` has living buildings stamped out.
  A dock placement asks the first, a squad asks the second. It also
  explicitly refuses a navigable cell — not defensive, since the two
  arrays have the same shape and opposite meanings, and passing one
  twice would otherwise offer the open sea as dock sites.

**Measured, for the stages that will need it:** `continents` at 64x32 has
**164 shore cells**, so stage 3's dock has somewhere to stand; `islands`
at 64x32 has a largest connected sea of **1,565 cells**, which is what
stage 9 reasons about when deciding whether two starts can reach each
other.

**One naming wart, flagged and not churned:**
`MapConfig.walkable_components` is domain-agnostic and its name is not —
every naval stage will call it with a navigability field. It belongs to
an unmerged PR (#216); raised there rather than edited here.
