### D-105 · 2026-08-16 · Accepted — map size is extent, not resolution

**Decision:** terrain feature size is a number of **cells**, not a
fraction of the map. `TerrainGen._sample_at` multiplies whatever
frequency it is handed by `space.width / REFERENCE_WIDTH` (84, the
Standard lobby size) before converting it to noise-space units, so a
landmass, a biome patch and a warped shoreline all come out the same size
in cells at every map size, and a bigger map holds proportionally more of
them.

Three clauses:

1. **One place, all fields.** The size term lives in
   `TerrainGen.effective_frequency`, called once by `_sample_at`, so
   elevation, moisture and the blend warp are treated alike by
   construction. Applying it per field would have left biome patches
   map-sized while landmasses became cell-sized, which is half a fix.
2. **It composes with `axis_repeats`, it does not replace it.** D-036's
   repeat count still divides the scale, so symmetry and feature size
   stay independent knobs, exactly as before.
3. **`REFERENCE_WIDTH` is the Standard map's width**, pinned by a test.
   Every `/terrain` preset was tuned at Standard, so the size term is
   exactly 1 there and no `.tres` needed re-tuning. The standard map's
   preview PNG is **byte-identical** before and after this change, which
   is how that is checked.

**Rationale.** The generator normalises the cell coordinate by the map's
dimensions before embedding it on the sampling torus, so before this
`elevation_frequency` meant "features across the map" — a count per map.
That is a coherent definition, and it made **Map size a resolution
control**: the same world drawn with more hexes. Measured on
`continents`/1337, flood-filling connected passable regions:

| size | cells | water | landmasses | mean / total | largest / total |
|---|---|---|---|---|---|
| Skirmish 42x48 | 2,016 | 21.3% | 1 | 78.3% | 78.3% |
| Standard 84x96 | 8,064 | 21.7% | 2 | 39.1% | 78.0% |
| Large 126x146 | 18,396 | 21.7% | 2 | 39.2% | 78.0% |
| Huge 168x194 | 32,592 | 21.7% | **2** | 39.1% | 78.0% |

A 16x increase in area bought **zero** additional landmasses, and every
landmass was a fixed fraction of the map to a tenth of a percent. Those
constants are the signature of a field defined over the unit torus. The
lobby said so out loud: its slider was labelled "Landmass count" and read
2.50 at every size.

Feature size, measured directly as the mean absolute elevation change
between cells a fixed number of cells apart — which is what "how big is a
landmass" means without any flood-fill heuristic — walked **0.0854 →
0.0311** across the four sizes at a 4-cell separation, a 2.75x spread. It
is flat to within 1.06x now, and `tests/test_terrain.gd` asserts under
1.25x at three separations.

**Rejected alternatives:**

- **Per-size seeds.** Fixes the symptom in the screenshots — two sizes
  looking like the same place — and none of the problem: Huge would get a
  *different* two landmasses, each still 78% of the map. The scaling gets
  the different-layout benefit for free, since it also changes where the
  field is sampled.
- **Re-tuning each preset per size**, i.e. a table of frequencies. Four
  presets x four sizes of hand-tuned numbers that must be kept in step,
  to express one proportionality. A custom size would have no entry.
- **Scaling by area (`sqrt(w*h)`) rather than width.** Identical on every
  shipped size, because `MapSettings.sizes()` holds the aspect ratio
  fixed at ~1.155 by design. Width is the axis the minor radius already
  tracks (`_sample_at`), so scaling by it keeps horizontal and vertical
  feature size in cells equal, which is the property that comment exists
  to preserve.
- **Clamping the size term below**, so a small map keeps some variety.
  A fudge with no principle behind it, and it would reintroduce exactly
  the bug at the small end.

**Consequences:**

- **A Skirmish map is now a CORNER of a world, not a whole one.** At
  42 cells wide and 33.6-cell landmasses it holds a little over one, and
  it samples a small enough patch of the field that its statistics no
  longer match the global ones — water fell from 20.5% to 14.6% at seed
  1337. That is correct under this decision and worth knowing before
  reading a small-map number as a regression. If Skirmish reads as too
  bland, the lever is a per-size default `elevation_frequency`, which is
  a lobby matter and not this entry.
- **Resource density stopped drifting with map size, which is a fix
  nobody asked for.** Stone sits at the mountain FOOT, so a map's ore
  count follows the LENGTH of its mountain perimeter — which used to be a
  fixed number of ranges however big the map was. One ore node per
  **101 / 144 / 219 / 340** cells across the four sizes before; **92 /
  144 / 152 / 145** after. `tests/test_economy.gd`'s scarcity bound moves
  from 100 to 80 for the smallest map and gains an explicit assertion on
  the ore-to-tree ratio, which is the property that entry actually
  protects.
- **Toy maps in tests are genuinely flat now**, and two D-097 cliff tests
  correctly reported proving nothing on a 16x8 map. They ask for toy
  features explicitly (`_toy_terrain`). The `cliff_rise` test moved to
  the Skirmish size at shipped tuning instead, because whether the rise
  adds anything depends on the natural gradient at a boundary, and a toy
  map's gradient clears `cliff_min_step` on its own.
- **The lobby slider is relabelled "Landmass size" and reads in cells**
  (`TerrainGen.feature_cells`). "Landmass count" stopped being a property
  of the parameter the moment the parameter stopped depending on the map.
- **`blend_warp_frequency` is correct at every size for the first time.**
  It was documented as "the boundary wanders every few hexes" — a
  cell-relative intent in map-relative units — so at Huge it wandered
  every ~7.6 cells against Standard's ~3.8, and the scalloped shoreline
  D-096's amendment exists to remove came back at exactly the sizes
  nobody had looked at.
- **Periodicity is untouched**, and this is the load-bearing claim.
  `u` and `v` are angles; the size term scales the embedded torus
  uniformly in noise space and cannot move where the field meets itself.
  D-008's wrap guarantees hold for any real frequency, and a seam test at
  the Huge size asserts it rather than trusting the argument.
- **Nothing new goes on the wire and nothing desyncs.** `MapSettings`
  already carries width, height and both frequencies (D-049), and both
  sides derive the effective value from the same two numbers.
- Huge draws **1,896 cliff faces against 280** and is 18.0% impassable
  against 21.7% — the same country, more of it.

**Revisit trigger:** a map size whose aspect ratio departs from
`MapSettings.sizes()`' ~1.155, at which point width and `sqrt(area)` stop
agreeing and the choice in the rejected list needs re-making. Also
revisit if Skirmish is judged too featureless in play — the answer there
is a per-size default, not a return to map-relative features.
