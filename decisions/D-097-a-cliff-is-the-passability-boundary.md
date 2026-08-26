### D-097 · 2026-08-15 · Accepted — a cliff is the passability boundary, drawn

**Decision:** the rendered surface **steps** where `passability` changes,
and a vertical rock skirt fills the step. The step is generated from the
same predicate the flow field routes around — never from a second,
prettier notion of steepness — and lives entirely on the rendering side:
`elevation_at` stays discrete per cell, `passability` still thresholds
it, and nothing new goes on the wire.

Four pieces:

1. **`TerrainGen.CliffClass`** — `passability` split by WHICH of its two
   reasons applies: WATER, LAND, HIGH. `passable[i] == 1` exactly when
   the class is LAND, asserted cell by cell on the shipped map. Water and
   mountain need separate classes even though both are impassable, or a
   corner where a lake meets a peak averages sea level with rock and
   hangs the surface halfway up the mountainside.
2. **Corner heights average within a class** (`TerrainGen.corner_heights`),
   so a corner where classes meet resolves to two or three heights
   instead of one. Groups whose means differ by less than
   `cliff_min_step` MERGE, which is what gives beaches and sea cliffs
   from one mechanism: a shore that rises gently keeps D-084's smooth
   blend, a shore that rises sharply steps.
3. **A skirt per stepped edge**, emitted into the chunk's own ArrayMesh
   as a second surface — so it inherits D-035's nine-copy tiling, adds no
   draw-call structure, and needs no material plumbing (it wears the same
   shader, with all three of D-096's tile slots pointing at MOUNTAIN, so
   the face gets the atlas's rock strata). Each cell emits for three of
   its six directions, so every shared edge is drawn exactly once.
4. **`cliff_rise`** — the impassable HIGH class is DRAWN 2.0 world units
   above its own elevation.

**Why (4) exists, which the plan did not anticipate.** The plan assumed a
truthful drawing of the class boundary would produce a visible wall. It
does not, and the measurement says so plainly. On the shipped map the
natural height step where two classes meet has a **median of 0.20 world
units along the coast (p90 0.65) and 0.66 at a mountain foot** — under
half a hex's width. The reason is structural rather than a matter of
tuning: elevation is smooth noise and `passability` is a level set on it,
so the boundary can never fall anywhere the ground is already steep. The
first implementation drew **87 rock faces on the whole 8,064-cell map**,
which is the "mechanism correct, shipped numbers do nothing" failure this
project has hit repeatedly — and it looked like success in every other
line of output.

So mountains are lifted onto their own tier. The wall still stands
exactly where `passability` changes, which is the part that is not
negotiable; the lift only makes it tall enough to see. With
`cliff_rise` 2.0 and `cliff_min_step` 0.4 the shipped map draws **363
rock faces**: every land/mountain edge, and roughly a quarter of the
coastline, with the rest of the coast keeping its beach.

**Rejected alternatives:** slope-based rock shading alone (tracks slope,
not passability, so it lies exactly at the boundary — kept as a possible
complement, not as the mechanism); authored cliff prop models along the
boundary (many instances, hard to keep watertight, placement fiddly);
marking cliff-adjacent cells impassable so the sim and picture agree
trivially (deletes visibly flat walkable ground); a `shore_drop` that
pushes the sea below the land (an extra knob, when the land's own height
above sea level already varies the drop naturally and gives the
beach-versus-sea-cliff split for free).

**Consequences and the risk this buys:**

- **`height_at` now has a discontinuity**, and soldiers spill slightly
  outside their squad's cell. The mitigation is structural: the passable
  side's corner heights stay flat and the wall sits exactly on the shared
  edge, so a sampler call near the edge lands on the passable plateau.
  Bounded by a test — for every passable cell, `height_at` at the centre
  and at all six edge midpoints stays inside that cell's own drawn range,
  and never within half a `cliff_rise` of the mountain tier beside it.
  The first version of that test used the cell's CENTRE height as the
  datum and failed on ordinary hillsides, because a hex edge is already
  half a world unit off its centre on a slope; it was measuring the
  terrain, not the hazard.
- **Colour steps with the height.** A corner blends only over the owners
  on its own side of the step. Without that, a mountain plateau is
  painted in the colours of the valley it towers over — rock walls with
  grassland on top, which is what the first render actually showed.
- **The rock face's normal is tilted ~27 degrees up** (`SKIRT_NORMAL_LIFT`)
  while the geometry stays vertical. D-086's rig is one directional sun
  with sky ambient and no shadows, so a truly vertical normal catches
  almost nothing: the first render drew mountain walls at sRGB 0.09, dark
  enough to read as holes cut in the world. This is the same class of
  choice as D-045's "distant squads draw thinner, never smaller" — the
  shading is adjusted so a player can read the picture, and nothing moves.
- **The shipped default map has almost no mountains.** 21.7% of its cells
  are impassable and 20.9% are water, which leaves roughly 66 mountain
  cells and 80 land/mountain edges on an 8,064-cell map. Cliffs are
  therefore mostly a coastal feature there. That is a terrain-generation
  fact, not a rendering one: the lever is `mountain_level` and the
  `/terrain` presets, and it is worth the owner's attention separately.
- Geometry cost is perimeter-sized, as predicted: **57,900 vertices and
  49,110 triangles against 56,448 and 48,384** on the standard map,
  +2.6% and +1.5%. Frame cost on Intel(R) Iris(R) Xe Graphics, terrain
  only: **3.97 ms before all three slices, 4.05 ms after** — against the
  0.5 ms this slice was budgeted.
- **The 1,000-squad absolutes from this session are not usable, and that
  is a host problem rather than a code one.** Four interleaved A/B pairs
  put the difference between −9 and +10 ms, inside a band where the SAME
  code varied by 30 ms run to run; and the unchanged slice-2 build
  measured 52.1 ms early in the session and 181.1 ms three hours later,
  after continuous GPU benchmarking. The delta is therefore reported as
  unresolvable rather than as zero, and the terrain-only row above is the
  figure that means anything. CLAUDE.md's M6 note about worst ticks
  measured while the host was building containers is the same lesson.

**Amendment, 2026-08-18 (#97): the clause that made the lift free was
not true.** The consequences list above justified `cliff_rise` as
rendering only with "`build_fields` is the sole reader, `passability`
still thresholds the unscaled elevation, and nothing stands on impassable
ground for the offset to disagree with" — the same wording as
`TerrainGen.cliff_rise`'s own doc comment. Soldiers stood on impassable
ground the whole time: D-006's slot offsets are pure geometry and
passability was never one of their inputs, so a squad on a beach stamped
part of its formation onto the shelf behind it and a slot crossing the
boundary jumped `cliff_rise` PLUS the natural step, which reads as
popping rather than as a slope. The simulation half of the claim survives
untouched — `passability` still thresholds the unscaled elevation and the
wall still stands exactly where it changes — and the "soldiers spill
slightly outside their squad's cell" consequence above was the near miss:
it bounded `height_at` near an edge and did not ask what happens to a man
a whole formation-width away. Fixed by
`D-20260818-a-soldier-stands-where-his-squad-could-walk`, which makes
passability the second half of the terrain sample. This is the D-058/D-065
family again: a decision entry asserting an invariant is not evidence that
the invariant holds.

**Revisit trigger:** elevation acquiring tactical meaning. D-084 noted
that the rendering/simulation split "stops being free the moment
elevation acquires tactical meaning", and per-edge blocking (the plan's
slice 4, its own decision) is exactly that moment — at which point
`cliff_rise` becomes a thing the simulation can see and this entry needs
re-reading. Also revisit if a terrain preset ever makes mountains common
enough that 2.0 units reads as a mesa rather than a cliff.

**Amendment, 2026-08-26: the revisit trigger fired, and pieces (1) and
(4) are superseded by
`D-20260826-passable-means-flat-enough-to-cross`.** Passability is a
slope rule now — land blocks for standing more than `max_slope` (0.8)
world units above a neighbour, never for being high — so:

- **`CliffClass` derives from the predicate, not the biome.**
  `cliff_class_of(biome)` is deleted; a biome no longer knows whether it
  is walkable. The invariant this entry stated — `passable[i] == 1`
  exactly when the class is LAND — survives verbatim, and the tests that
  pin it are unchanged.
- **`cliff_rise` is deleted.** The problem it solved cannot occur under a
  slope rule: a blocked cell has a step of at least `max_slope` — twice
  `cliff_min_step` — to some neighbour, so the truthful drawing is
  visible by construction. Kept, the lift would stand a blocked rim
  ABOVE the walkable plateau behind it (plateau tops are LAND now) and
  every mountain would read as a crater.

Pieces (2) and (3) — within-class corner averaging with `cliff_min_step`
merging, and the skirt per stepped edge — are unchanged and are what
draws the new boundary. The core rule of this entry, that the wall is a
DRAWING of the predicate the flow field routes around, is exactly what
the successor preserves.

---
