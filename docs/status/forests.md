**Resource nodes are forests now (D-087, 2026-08-14).** Placement is a
per-biome density field riding the same moisture noise `biome_at`
classifies with — dense forest hearts, groves thickening toward the
treeline, orchards mid-moisture, arid trees and palms on dry ground and
beaches, stone at the mountain FOOT (its old MOUNTAIN-cell placement was
unreachable scenery; the AI's give-up mechanism existed because of it).
Standard map: **1,920 natural nodes vs ~134 before (~14x)**. Trees
(wood/food) carry `TREE_STOCK` 105 — one shipped gatherer crew works one
out in **~60 s**, pinned by a test against the shipped def — while
gold/stone keep 2400. A worked-out tree auto-retargets its crew to the
nearest surviving node of the SAME kind within 8 cells (never
substituting kinds). Depletion is a fog-gated wire event
(`S2C_NODES_DEPLETED`): told when the knower can SEE the cell, stale
ghost-tree otherwise; the client fells it with a tip-and-sink animation.
Rendering is 50 authored variants (10 species × 5, split from
`tree-variants.glb` by `split_markers.gd`) picked per cell by
`resource_visuals.gd` (pure/static — species by biome+moisture, 35%
boundary borrowing so treelines fray, hash yaw/scale), batched into one
MultiMesh per (16-cell chunk, model) with the torus tax paid per chunk.
Bots finally ORDER the gatherers they produce — the haul cycle had never
run under `test-load`'s wire before — and report `nodes_felled` in the
verdict (a metric, not a gate: a felling needs ~3 minutes of match, and
gating would re-set D-031's stale-timing trap).

**And a forest was still a grid until D-108 (2026-08-16).** A playtest
reported ranks and files you could count along. The blob-scale outline
was organic — the density field above doing its job — and the interior
was the hex lattice, because **a tree's only positional freedom was which
cell it stood in**: one tree per node cell, drawn at the exact cell
centre. Compounding it, canopies had been deliberately shrunk (0.60–0.92)
*so that they could not touch*, because at one tree per centre full-size
canopies merged into one blob — so every tree also had a hard gap around
it. A node cell now grows a hash-chosen STAND (1–5, mean ~2.9 in forest)
on jittered ring offsets, and the canopy shrink is reversed. **1,438 wood
nodes now draw 4,202 trees, and 99% of them touch a neighbour's canopy.**

Three things to carry forward. **The two causes interlock, so the fix is
one change**: scale alone reproduces the blob that motivated the shrink,
and offset alone leaves placement at hex resolution — dithered rows are
still rows, and a wood still cannot be denser than the node grid. **The
offset bound is what makes it safe without a passability test**: it is
under a hex's inradius (sqrt(3)/2), so a tree cannot leave its own cell,
drift onto water or stand nearer someone else's centre — and it stays a
rendering-only change, D-084/D-096's split again (the node's CELL is
still what the economy, the wire and the fog mean). And **no number could
see any of this**: node counts, chunk counts and frame times were healthy
throughout, `gen-terrain-preview` draws a top-down map with no trees in
it, and `test-client` aims its camera at a spawn — open ground by
construction, the one place a wood cannot be. `just gen-forest-preview`
is the instrument that can, and it frames the densest wood on the map
from a low angle for exactly that reason.

**And there were too many of them (D-20260818, 2026-08-18).** Playtest #30
read the standard map as woodland with clearings rather than open country
with woods in it, and issue #94 asked for ~40% less wood. Every WOOD band
in `Economy._bands` is scaled by **0.60** now (forest `lerpf(0.65, 0.98, f)`
-> `lerpf(0.39, 0.59, f)`, and so on for grassland, dry grassland and
beach): **wood nodes 5,553 -> 3,413 on the shipped map, open walkable
ground 71.3% -> 79.3%, forest biome 70.2% -> 43.9% wooded.** Scaling both
ENDPOINTS is what keeps D-087's shape and D-108's stands intact — a flat
subtraction erases the dry edge first, a stride puts the lattice back.

Three things to carry forward:

- **The 98% wet heart in the report was never actually paid.** `f` reaches
  1 only where moisture does, and over six seeds the wettest single forest
  cell on the shipped map measured f = 0.57-0.73 — so the realised band was
  the FLOOR (median forest cell 0.69), and lowering only the ceiling would
  have changed almost nothing. **An interpolation's endpoints are not its
  outputs**, and the alarming one may be the one nothing reaches.
- **The number being complained about had no instrument.**
  `gen-terrain-preview` reported chunks, water and impassability and no
  resources at all; `gen-forest-preview` shows one wood and cannot say how
  much of the map is wood. The recipe prints node counts by kind, the
  **share of walkable cells that hold no node**, and the forest biome's own
  share — the last because a whole-map average is dominated by open
  grassland and stayed healthy-looking throughout.
- **The instrument that could see it was the picture, again.**
  `docs/playtest/p30-wood-density-{before,after}.png`, both from
  `gen-forest-preview`. The BEFORE shot does not contain the squad that
  recipe deliberately stands in the wood for scale — the canopy closes over
  it completely. Same window, 336 nodes / 935 trees before and 226 / 614
  after at an unchanged ~2.7 trees per node, so D-108's stands survived and
  only their number moved.
- **What was checked before picking 0.60, rather than after.** `TREE_STOCK`
  stays 105 and total wood falls with the count (358,365 over 20 seats is
  ~119 barracks each, from natural nodes alone); `RETARGET_RADIUS` stays 8
  because **0 of 3,413** wood nodes have no wood neighbour within 8 cells,
  and 0.50 is where the first isolated one appears; the D-104 fairness pass
  still tops up no wood anywhere, the worst-off start keeping 4 wood nodes
  in reach against 13. Issue #55's "nodes block 30% of walkable cells" is
  28.7% -> **20.7%** and should be re-read off the recipe, not assumed.
