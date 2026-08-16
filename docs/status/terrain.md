**The ground is continuous, and cliffs are drawn (D-096/D-097,
2026-08-15).** The owner's complaint was that the ground read as a
honeycomb of flat hexes and no cliff was visible anywhere. Four causes,
all in the code, none visible to any number:

- vertex colour was one flat value per cell, so it stepped at every
  boundary. A shared corner now takes the mean of its three cells — the
  same trick D-084 used for heights — and `biome_color()` stays the
  single source of truth, so the minimap and the preview PNG cannot
  drift. The preview PNG is byte-identical before and after, which is how
  that is checked;
- the centre vertex sat at the cell's own elevation and domed each hex.
  That is `TerrainGen.pillow` now, shipping at 0.15 against the old
  implicit 1.0. `height_at` reads the same array, so the sampler follows;
- each hex sampled its own inset, hash-rotated atlas tile. UVs are
  continuous across cells now and still CELL-derived, never from world
  position (D-035). `TerrainChunk.uv_scale` is arithmetic rather than a
  constant: the texture meets itself across the seam only if the map
  period is a whole number of repeats on BOTH axes, and stepping `height`
  in r moves world x as well as z;
- `surface_field` averaged corners across the passability boundary, so a
  mountain was a smooth ramp that happened to be grey. Corners now
  average WITHIN a passability class and step between them, and a rock
  skirt fills the step.

**`shaders/terrain.gdshader` is the project's first terrain shader**, and
continuous UVs are why: a continuous coordinate over an eight-tile atlas
walks out of one biome's tile into its neighbour's, and wrapping it back
is a per-fragment decision. Each cell carries three tile indices,
constant over the cell (an interpolated INDEX would ask for tile 4.7),
and each vertex its weights over them. The fragment samples with
**explicit gradients**, because `fract` tears the derivative once per
repeat and the implicit version draws a bright seam every few hexes in a
ruler-straight line. Cost, measured before deciding, on Intel Iris Xe:
**+0.11 ms terrain-only and nothing resolvable at 1,000 squads /
27,300 soldiers** against a 2 ms budget — the frame is CPU-bound on
soldier derivation, 48 ms of 52, so two more ground taps are nearly free.

**A one-cell blend is not enough at high contrast, and that took a second
pass to learn.** Blending a corner over its three cells makes every
transition exactly ONE CELL wide. At grass-to-sand that reads as soft; at
sand-against-water — the strongest contrast on the map — one cell is one
HEX, the 50% contour runs along the hex edges because that is where the
three weights are equal, and the shoreline comes out visibly scalloped.
An isolated sand cell in open water rendered as a clean six-pointed STAR.
So two more things: the contour is pushed off the lattice by a
low-frequency periodic warp of the corner weights (`blend_warp`, sampled
at the CORNER so all three owners agree), and the band is widened past
one cell by letting a centre take some of its own already-blended corners
(`centre_bleed`). **Warping alone was measured and was not enough** — its
first version moved the rendered picture by at most 19/255, because
`FastNoiseLite` rarely approaches ±1 and an amplitude that reads as "most
of a hex" displaces about a third of that.

The centre-vertex invariant changed with it and the new one is narrower
but still real: **a cell whose six neighbours share its biome carries
`biome_color` at every vertex exactly**; boundary cells deliberately do
not, because that is the feathering. The test asserts the interior case
exactly rather than loosening to a tolerance everywhere.

**And a perturbation the suite failed.** Sampling the warp at the calling
CELL rather than at the corner — which gives a corner's three owners
three different answers — left every test green, because `build_fields`
computes each corner once and hands the same cached triple to all three.
**The cache made the mesh watertight however wrong the arithmetic was.**
Only calling the function from each of the three sides can see it. When
an optimisation makes a property hold structurally, the test for that
property has to bypass the optimisation.

**The finding worth carrying forward: a truthful drawing of the
passability boundary draws nothing.** The natural height step where two
classes meet on the shipped map has a **median of 0.20 world units along
the coast and 0.66 at a mountain foot**, because elevation is smooth
noise and `passability` is a level set on it — so the boundary can never
fall where the ground is already steep. Drawn faithfully it produced
**87 rock faces on the whole 8,064-cell map**, which is this project's
"mechanism correct, shipped numbers do nothing" failure wearing a green
verdict. Mountains are therefore LIFTED onto their own tier
(`cliff_rise`, 2.0 world units): the wall still stands exactly where
`passability` changes, and the lift only makes it tall enough to see.
363 faces now.

**And a related fact about the shipped map that is not a rendering
matter:** 21.7% of its cells are impassable and 20.9% are water, which
leaves roughly **66 mountain cells and 80 land/mountain edges** on 8,064.
Cliffs there are mostly coastal. If more rock is wanted the lever is
`mountain_level` and the `/terrain` presets.

**Map size is EXTENT now, not resolution (D-105, 2026-08-16).** Feature
size is a number of cells, not a fraction of the map: `_sample_at`
multiplies any frequency it is handed by `space.width / REFERENCE_WIDTH`
(84, the Standard size) before embedding, so a landmass is ~34 cells
across on every map and a bigger map holds proportionally more of them.
Before it, a Huge map was **the same two landmasses as a Skirmish map,
each 16x larger** — 39.1%/39.2%/39.1% of the map at Standard/Large/Huge,
constant to a tenth of a percent, which is the signature of a field
defined over the unit torus. Four things to carry forward:

- **The reference width is the Standard map's, and a test pins it.** Every
  `/terrain` preset was tuned there, so Standard is *byte-identical*
  before and after — that is how the claim is checked, not by argument.
- **The size term lives in ONE function** (`TerrainGen.effective_frequency`),
  so elevation, moisture and the blend warp all get it. Applied per field
  it would have left biomes map-sized while landmasses went cell-sized.
- **A Skirmish map is now a corner of a world, not a whole one**, and it
  no longer matches the field's global statistics — water fell 20.5% →
  14.6% at seed 1337. Small-map numbers moving is this decision working.
  Toy maps in tests are genuinely flat as a result: two D-097 cliff tests
  correctly reported proving nothing on 16x8 and now ask for toy features
  explicitly.
- **Resource density stopped drifting with map size** as a side effect,
  because stone sits at the mountain FOOT and ore therefore follows the
  mountain PERIMETER — which used to be a fixed count of ranges whatever
  the map size. One ore node per 101/144/219/340 cells before, 92/144/
  152/145 after.

**`just gen-terrain-shot` is the new recipe, and it exists because the
old instruments structurally could not see any of this.**
`gen-terrain-preview` draws a top-down biome map from `biome_color` and
reports chunk counts — every number healthy throughout. `test-client`
renders the real thing and points its camera at a spawn, which is
walkable ground by construction and therefore the one place a cliff
cannot be. The new recipe frames the terrain on the longest run of
passability boundary on the map, from a shallow angle, in the SHIPPING
lighting rig. **Look at `artifacts/terrain-3d.png`.**

Three smaller things bought the same way. The rock face's normal is
tilted ~27 degrees up while its geometry stays vertical, because D-086's
rig has no shadows and a truly vertical normal drew mountain walls at
sRGB 0.09 — dark enough to read as holes cut in the world. Colour steps
with the height at a cliff, or a mountain plateau is painted in the
colours of the valley below it. And `TerrainGen.corner_cells` returns its
three owners SORTED, because float addition is not associative and three
owners summing one triple in three orders can differ in the last bit —
which makes watertightness a property of the arithmetic rather than of a
tolerance.

Terrain meshing for the standard map costs **~600 ms to ~1,100 ms** at
client start as a result, once per match. Frame cost of the whole change,
terrain only, on Intel Iris Xe: **3.97 ms to 4.05 ms**.

**And a warning about the numbers, which cost an hour to work out.** The
1,000-squad `bench-render` absolutes from that session are junk: the same
unchanged build measured **52.1 ms early and 181.1 ms three hours later**,
after continuous GPU benchmarking, with worst frames near 900 ms. The A/B
deltas taken from interleaved pairs are still sound — that is what
interleaving is for — but any absolute quoted from a long benchmarking
session should be checked against a fresh one. This is the same lesson as
M6's worst-tick figures taken while the host was building containers.
