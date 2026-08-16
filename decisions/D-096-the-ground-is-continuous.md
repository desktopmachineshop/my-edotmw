### D-096 · 2026-08-15 · Accepted — the ground is continuous

**Decision:** the ground stops being a honeycomb of flat hexes. Three
separate causes, all fixed, none of which any number could see:

1. **Vertex colour is per VERTEX.** A shared corner takes the mean of the
   three cells meeting there — exactly the trick D-084 already used for
   heights — and a centre keeps its own. `TerrainGen.biome_color()`
   remains the single source of truth (D-083): the blend is DERIVED from
   it, and the minimap and the terrain preview PNG still read it per
   cell. The preview PNG is byte-identical before and after, which is the
   check that the small picture and the big one cannot have drifted.
2. **The pillow is a tunable**, `TerrainGen.pillow`, shipping at 0.15
   against the old implicit 1.0. The centre vertex now sits at
   `lerp(mean of its own six corners, own elevation, pillow)`. The
   comment that used to live in `surface_field` called the resulting dome
   a feature — "keeps the hex grid faintly readable" — and that
   readability is precisely what the owner asked to be rid of.
   `height_at` reads the same array, so the ground sampler follows and
   cannot disagree with the mesh.
3. **UVs are continuous across cells**, and still derived from the CELL
   rather than from world position — the D-035 rule that makes the nine
   lattice copies agree. Each hex used to be inscribed in its biome's
   atlas tile with a 6% inset and a hashed rotation, so the texture
   restarted at every edge.

**`shaders/terrain.gdshader` is the project's first terrain shader**, and
(3) is why one was needed: a continuous coordinate over an eight-tile
atlas walks out of one biome's tile into its neighbour's, and wrapping it
back into the right tile is a per-fragment decision with no
fixed-function expression. Each cell carries three tile indices, constant
over the cell so interpolation is a no-op — an interpolated INDEX would
ask for tile 4.7 — and each vertex carries its weights over them, which
do interpolate. The fragment samples three times with **explicit
gradients**, because `fract` tears the derivative once per repeat and an
implicit-derivative sample draws a bright seam every few hexes in a
ruler-straight line.

**Two arithmetic details are load-bearing, not fussiness:**

- **`TerrainGen.corner_cells` returns the three owners SORTED.** Float
  addition is not associative, so three owners summing the same triple in
  three different orders can differ in the last bit. Sorting makes
  watertightness a property of the arithmetic rather than of a tolerance.
- **`TerrainChunk.uv_scale` is arithmetic, not a constant.** The texture
  meets itself across the seam only if `scale.x * width`,
  `scale.x * height/2` AND `scale.y * height` are all whole numbers of
  repeats — the middle one because stepping `height` in r moves world x
  as well as z. A scale that only divides the width tears along the
  diagonal seams, which is a defect that looks like a noise bug.
  `vertex_uv` evaluates the coordinate as an integer numerator over a
  fixed denominator so two cells reaching a corner by different
  arithmetic land on the same UV exactly.

**The measurement that chose route B.** The plan offered a single neutral
detail texture (free) against per-biome tiles blended three ways, and
said the decision would be made with a `bench-render` number rather than
an opinion. On **Intel(R) Iris(R) Xe Graphics**, 84x96 map, 200 measured
frames, before and after in one session:

| | terrain only | 1,000 squads / 27,300 soldiers |
|---|---|---|
| before | 4.15 ms | 52.07 ms |
| after (3 taps) | 4.26 ms | 51.98 ms |

**+0.11 ms** on the terrain-only row and a difference at 1,000 squads
that is inside run-to-run noise, against a 2 ms budget. The frame is CPU
bound on soldier derivation — 48 ms of 52 — so two more ground taps are
very nearly free, and the fallback was not needed.

**Rejected alternatives:** bigger or denser atlas tiles (the island seam
is the problem, not the tile size); per-vertex tile indices with `flat`
interpolation (the provoking vertex's biomes would paint the whole
triangle); eight per-biome weights so no index needs interpolating
(eight taps per fragment); de-indexing the fan so each triangle can carry
its own four-biome set (exact, and 2.5x the vertex count for a
difference measured at 0.09% of corners).

**Consequences:**

- **Three tile slots per cell is not always enough**, and the test
  MEASURES that rather than assuming it: a cell whose six neighbours span
  more than three biomes drops the least demanded, and its neighbour may
  drop a different one, so the texture DETAIL can differ across that one
  edge. On the shipped map it is **45 of 48,384 corners, 0.09%**. Colour
  is exact everywhere and carried separately.
- `TerrainGen.build_fields` and `TerrainFields` replace three separate
  O(cells) walks over the same noise. Heights, colours, biomes and
  passability are built together because they are indexed identically and
  share one corner-sharing rule — passing them separately lets a caller
  pair this build's surface with that build's colours, which nothing
  would report.
- Terrain meshing for the standard map costs more at client start:
  **~600 ms to ~1,100 ms** for all 36 chunks, once per match. Two extra
  four-float vertex channels and the per-corner class resolution account
  for it. A fast path for the 99% of corners whose three owners share a
  class is in `corner_heights` and pays for itself; an equivalent fast
  path in `cell_tiles` measured no gain and was removed rather than kept
  on the strength of the argument for it.

**Amendment, 2026-08-15 (same day), on the owner's report that the
transitions were still hard hex-shaped edges.** D-096 as written above
fixes the low-contrast boundaries and does not fix the high-contrast
one, and the distinction is the whole content of this amendment.

**What was wrong.** A mean-of-three corner blend makes every transition
exactly ONE CELL wide. Where the two colours are close — grass to dry
grass, sand to grass — that reads as soft. At sand against water, the
highest contrast on the map, one cell is one HEX: the 50% contour runs
along the hex edges, because that is precisely where the three weights
are equal, and the eye reads the resulting chain of arcs as a scalloped
lattice. An isolated sand cell in open water rendered as a clean
six-pointed STAR, which is the same fact stated at its most obvious.

Feathering harder does not help. A wider soft band centred on the same
contour is still centred on the lattice.

**Two changes, and both were needed — the first alone was measured and
found insufficient.**

1. **The contour moves off the lattice.** Each corner's three weights
   are skewed by a low-frequency periodic noise field sampled at the
   corner's own position (`blend_warp`, `blend_warp_frequency`). The
   boundary meanders across cells instead of along them. Unwarped it
   returns exact thirds, so D-096's original blend is recovered rather
   than approximated.
2. **The band widens past one cell.** A cell's CENTRE takes some of its
   own six (already blended) corners (`centre_bleed`, 0.45). Because a
   corner already carries a third of each of its three owners, averaging
   the six of them reaches the neighbours' neighbours — a roughly
   two-cell transition for three lines of arithmetic and no extra
   sampling.

**The invariant that changed, stated plainly.** D-096 said the centre
vertex carries `biome_color` EXACTLY. That now holds for every cell
whose six neighbours share its biome — most of any map — and is
deliberately relaxed at boundaries, where the point is that the colour
is on its way to being the neighbour's. `biome_color` is still the only
source of colour and the minimap still reads it per cell; the test
asserts the interior case exactly rather than loosening to a tolerance
everywhere, so what survives is a real invariant and not a weaker one
wearing the same name.

**Three things the pictures found that no count could.**

- **The warp alone changed almost nothing.** Its first version moved the
  blend by at most 19/255 — the rendered coastline was pixel-for-pixel
  the same scallop. `FastNoiseLite` rarely approaches ±1, so an
  amplitude that reads as "most of a hex" displaces about a third of
  that. Shipped at 2.0 for that reason, and there is now a test that
  asserts the mean skew on the SHIPPED map rather than that the
  mechanism exists.
- **Pushed harder, black blots appeared along the coast.** Where the
  warp clamps every weight in a cliff group to zero, the blend divided
  near-nothing by near-nothing. It falls back to the unweighted mean of
  the group now.
- **The per-corner sampling was untested and a perturbation proved it.**
  Sampling the warp at the calling CELL instead — which skews every
  corner of a cell the same way and gives a corner's three owners three
  different answers — left the entire suite green, because
  `build_fields` computes each corner once and hands the same cached
  triple to all three owners. The cache made the mesh watertight however
  wrong the arithmetic was. Only calling the function from each of the
  three sides can see it, and a test now does.

**Cost:** ~0.25 s of terrain build at client start on the standard map
(1.47–1.65 s to 1.70–2.20 s, three paired runs), and nothing per frame —
the weights are baked into vertex colours and the shader's existing tile
channel. Every hex corner is computed once and looked up twice more
(a hex lattice has two corners per cell), which is the same
compute-once-index-after shape as `TorusSpace.disk_offsets` and
`elevation_field`; without it the warp's two noise samples per corner
cost a second of build on their own. `TorusSpace.delta` was in the first
draft of the weight function and cost five seconds — the
`distance()`-per-candidate defect in its sixth outfit, and caught by
watching the build time rather than by reading the code.

**What this does NOT fix, deliberately.** The cliff skirts are still
hard-edged and hexagonal in plan, because a cliff IS the passability
boundary and that boundary is per-cell (D-097). Feathering a cliff would
be drawing something the simulation does not have.

**Revisit trigger:** a map whose width and height/2 are coprime, where
`uv_scale`'s granularity forces the repeat count to the full map width
and the texture stretches; or a biome roster large enough that corner
truncation rises out of the tenths of a percent.

---
