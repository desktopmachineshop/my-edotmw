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

---

**Naval stage 8 — presentation — is built
(D-20260828-a-hull-is-drawn-on-the-sea, #301, `docs/plans/naval.md` §7
row 8).** A ship's men derive at the sea plane, inshore as well as out;
the minimap and selection needed nothing and are asserted rather than
assumed; and there is a rendered frame of ships on water to look at.

```
just gen-naval-shot          # artifacts/naval-godot.png — LOOK AT IT
just gen-naval-shot 9 1      # ...the same frame with hulls on the seabed
```

Four things to know:

- **The drawn sea was ALREADY FLAT, so most of this stage was a test
  rather than a change.** `build_fields` clamps every vertex of a water
  cell up to `sea_level`, so a hull in open water was always at the right
  height through the ordinary sampler. §6.4 expected `PrimitiveUnit` to
  need a domain-aware height; what actually needed one is the SHORE,
  where a water cell borrows its corners from the land and lifts a hull
  **0.055 world units** up the beach — on exactly the cells every landing
  happens on.
- **`water_height` is an ARGUMENT to the pure derivation, NAN meaning
  "not a ship"** — D-006 clause 1 untouched, the same shape as #97's
  passability clamp and D-076's walkway bump. It also skips the land
  clamp, because that array describes ground a hull is floating over
  rather than standing on.
- **`ClientState.DOMAIN_*` alias `SquadSim`'s.** The tier byte on the
  wire is what makes them one definition rather than two, and a
  source-scanning test asserts the alias — a copy with the right value
  passes every value comparison there is.
- **The picture cannot show the shore lift, and the recipe says so.**
  0.055 units on a hull 0.6 thick is a number; `--seabed=1` prints it
  (1.120..1.175 against the plane's 1.120) and the two frames look
  identical. The shot's job is "ships are on the water", framed on
  purpose because every other rendered instrument in the repo points
  somewhere a hull cannot be.

**Not this stage, and deliberately:** authored ship models. The hulls
render at the primitive tier (`mesh_primitive = "hull"`), which is D-064's
designed degradation — a `.blend` under `art/source/` is what upgrades
them, with no code change.
