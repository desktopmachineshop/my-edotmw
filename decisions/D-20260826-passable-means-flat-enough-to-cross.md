### D-20260826 · 2026-08-26 · Accepted — passable means flat enough to cross

**Decision:** land is impassable for being **steep**, never for being
high. A cell cannot be walked on or built on when it stands more than
**`max_slope`** — 0.8 world units — above any of its six neighbours, with
both elevations clamped up to sea level first, so a seabed's depth never
counts against its beach. Water (`e < sea_level`) is unchanged.
`mountain_level` stops being a passability threshold and is purely a
biome threshold from here on: a flat plateau above it is ordinary
walkable, buildable ground that happens to be rock, and a steep hillside
below it is a wall that happens to be grass.

Supersedes the passability half of the elevation-threshold rule
(`e < sea_level or e >= mountain_level`, in force since M1); D-097's
mechanism (classes, within-class corner averaging, the skirt per stepped
edge) is untouched, but its **`cliff_rise` tier is deleted** and
`CliffClass` now derives from this predicate rather than from the biome —
resolving D-097's own revisit trigger ("elevation acquiring tactical
meaning ... at which point `cliff_rise` becomes a thing the simulation
can see and this entry needs re-reading"). From issue #129, raised in a
lobby playtest: "if the plateau is flat enough then building should be
allowed."

Six pieces:

1. **The slope is measured in WORLD units**, `Δe × height_scale` per
   neighbour step, so `height_scale` is now a simulation input.
   Deliberate, and the point of the whole change: the complaint is ground
   that LOOKS walkable and is not, so the rules must read the same number
   the picture is drawn from. On `plains` (height_scale 1.2) nothing on
   land can exceed 0.8 and the preset is open country wall to wall —
   which is what a map drawn nearly flat honestly is. This is the moment
   D-084 said "stops being free"; `terrain_preset.gd`'s claim that
   height_scale is "visual and tactical rather than structural" is
   amended with it.
2. **0.8 is a soldier's own height** (the authored models stand 0.795).
   The rule a player can read off the screen: a rise taller than the man
   walking it, inside one hex step, cannot be walked up.
   **The rule is one-sided — the LIP of a cliff is blocked, the flat
   ground at its base is not.** A symmetric |Δe| was prototyped first and
   fences off the valley floor one cell out from every wall, and the
   valley is where the game is played. One side blocked is enough to stop
   a crossing: any single hex step rising more than `max_slope` lands ON
   a blocked cell.
3. **`CliffClass` derives from the predicate**: WATER below sea level,
   HIGH for land this rule blocks, LAND otherwise. `cliff_class_of(biome)`
   is gone — a biome no longer knows whether it is walkable, so a class
   derived from it would be a second spelling free to drift. The
   "passable exactly when LAND" invariant D-097's tests pin survives
   verbatim.
4. **`cliff_rise` is deleted, not set to zero.** The lift existed because
   a level set on smooth noise can never fall where the ground is already
   steep, so the truthful drawing of the old boundary was a truthful
   drawing of nothing (87 faces, D-097). Under a slope rule that is
   impossible by construction — a blocked cell HAS a ≥ 0.8 step to some
   neighbour, twice `cliff_min_step`, so the wall is there to draw.
   Keeping the lift would also now invert: a blocked rim drawn 2.0 above
   its own height stands ABOVE the walkable plateau behind it, and every
   mountain reads as a crater. Shipping the knob at 0.0 instead of
   deleting it would be this project's declared-and-unread defect, made
   deliberately.
5. **An enclosed pocket gets a ramp 60% of the time** (`ramp_chance`,
   owner's directive during implementation: "make ramps to plateaus
   happen on average 60% of the time"). The slope rule strands walkable
   pockets by construction — a mesa whose every approach is steep. After
   the per-cell rule, each pocket rolls once against the chance, seeded
   and keyed on its lowest cell index so both sides of the wire roll
   identically; a winner gets the shortest LAND path to the
   already-connected world marked walkable (`TerrainGen._carve_ramps`,
   breadth-first, deterministic by construction — expansion in queue
   order, neighbours in direction order). Water is never carved: a pocket
   ringed by sea is an island, not a plateau. A carved cell becomes LAND,
   so the mesher blends it smooth instead of skirting it — the ramp is
   DRAWN as a ramp, and the visual language stays honest: skirted step =
   wall, smooth slope = ground you can walk. On the shipped map this
   carves 24 cells and takes the walkable ground from 37 components to
   17.
6. **Walkable high ground grows stone** (`Economy._bands`): MOUNTAIN/PEAK
   cells that pass this predicate carry a stone band at 0.08. D-087 moved
   stone off mountain cells because they were unreachable scenery; the
   reachable ones no longer are, and reachable-but-bare ground would be
   the same dead space #129 complains about with the fence removed. The
   mountain-foot band (0.25, one ring) is unchanged.

**Why, with the measurements** (probe on `maps/default.tres`, 168×194 =
32,592 cells, seed 1337, per preset, shipped rule — one-sided at 0.8 with
ramps at 0.6):

| preset (height_scale) | blocked land, old rule | shipped rule | high ground opened |
|---|---|---|---|
| continents (15.0) | 645 (2.0%) | 2,292 (7.0%) | 483 |
| highlands (3.4) | 14,368 (**44.1%**) | 0 | 14,368 |
| islands (2.0) | 12 | 0 | 12 |
| plains (1.2) | 0 | 0 | 0 |

`highlands` is the headline: **44% of that map was dead space drawn as
gentle hills** — at height_scale 3.4 the whole elevation range is 3.4
world units, so nothing on it comes near a 0.8 step. That is #129's exact
complaint, at preset scale. `continents` moves the other way: steep
hillsides at every altitude become real walls (2.0% → 7.0% of the map),
which is terrain acquiring tactical shape rather than a regression — and
the walls now stand where the drawn ground is genuinely steep instead of
along an invisible contour.

**Why 0.8 and not the sweep's neighbours** (one-sided rule, ramps off,
continents on the default map): 0.5 blocks 21.1% of the map across 152
walkable components; 0.6 blocks 14.6% across 101; 0.8 blocks 7.1% across
37; 1.2 blocks 1.6% across 5 and the opened plateaus stop having edges.
0.8 sits where the map gains real tactical shape without fracturing, its
largest stranded pocket (53 cells; 33 after ramps) stays under
`min_spawn_landmass` (96) so no spawn can seat on ground no army can
reach, and it equals the soldier's height, which makes the rule legible
rather than tuned.

**Rejected alternatives:**

- **Slope in raw elevation units** (preset-independent): leaves `plains`
  and `islands` with flat-looking impassable rock, which is the reported
  defect restated. The preset knob acquiring tactical meaning is the
  honest version.
- **Slope test only above `mountain_level`**: opens plateaus but keeps
  two ladders (a steep grass hillside stays magically walkable), and
  flatness is still not a thing the rules can see below the line.
- **Keeping `cliff_rise` for the blocked band**: the crater inversion
  above, measured against nothing it still fixes.
- **Slope on the interpolated surface** (D-084's corner-averaged mesh):
  would make the simulation read the mesher's smoothing. Cell-centre to
  cell-centre is the simulation's own resolution, and the surface is
  derived FROM those centres, so the two agree where it matters.
- **Per-edge blocking** (block the crossing, not the cell): truer to
  "cliff edges block" but a different flow-field data model — fields are
  over cells. A cell-based rule reaches the same play experience for a
  band one to two cells wide, and nothing downstream changes shape.

**Consequences:**

- **One predicate, spelled once.** `TerrainGen` computes it in one place
  for the field builders (`passability()`, `fields_step`) and exposes
  `passable_at(space, cell)` for sparse callers
  (`MapSettings.walkable_fraction`, `Economy._bands`).
  `test_map_slider_ranges` already pins the sparse spelling against the
  array one.
- **`walkable_fraction` costs ~7× its old sampling** (each lattice point
  now reads its six neighbours' elevations too). It runs on lobby slider
  ticks, never in a match tick.
- **Stranded pockets still exist, at the dice's discretion** — the ~40%
  of pockets whose ramp roll misses, plus true islands. 80 cells in 16
  pockets on the shipped map after ramps, all under the spawn floor at
  this seed; the flood fill D-104 added rejects any that grow past it on
  another seed. Stone rolled on a stranded plateau is scenery, exactly
  as every mountain node was before D-087; the AI's give-up mechanism
  and belief-based refusal both already handle a node that cannot be
  reached.
- **Every timing and count tuned against the old map is stale where the
  ground changed** — the standing rule. `continents` marches lengthen
  (more walls to round); `highlands` marches shorten (44% of the map
  stops deflecting flow fields). Fog-gate counters in `test-load` move
  with both.
- **#97's clamp keeps working and the pop it bounds shrinks** from
  `cliff_rise` + natural step (2.0+) to the natural step alone.
- **`_build_refusal`'s "that is a mountain" becomes "too steep"** — the
  old sentence names the biome, and the biome no longer decides.
- The old rule's numbers in D-097 and `docs/status/terrain.md` (66
  mountain cells, 21.7% impassable, 363 faces) describe a build this
  supersedes; `terrain.md` carries the update.

**Revisit trigger:** a playtest reading the blocked band as arbitrary —
walls where the drawn slope looks scrambleable — is a `max_slope` tuning
question first and a per-preset `max_slope` (TerrainPreset field +
MapSettings + wire, all three together per D-049) second. If the AI is
observed marching crews at stranded-plateau stone and burning its give-up
timer repeatedly, gate the band on reachability rather than passability.
And if elevation ever occludes vision (the open question D-025 left), the
"world units are now simulation data" clause here is the precedent to
cite, not a new argument.
