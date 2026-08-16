### D-087 · 2026-08-14 · Accepted — forests are made of trees: biome-density nodes, 1-minute trees, authored variants, fellings on the wire

**Decision:** Resource nodes stop being a uniform sprinkle of rich markers
and become terrain-shaped vegetation, with everything downstream of that
adjusted to match. Six coupled parts:

1. **Placement is a density field, not a stride.** `Economy.generate`
   rolls each cell against per-biome densities shaped by the SAME
   moisture field `biome_at` classifies with (`TerrainGen.MOISTURE_DRY` /
   `MOISTURE_FOREST` are constants now so the two cannot drift): forest
   cells are 65–98% trees riding moisture, grassland carries groves that
   thicken toward the forest line plus orchards in the mid-moisture band,
   dry grassland gets sparse hardy trees and its old gold cadence, and
   beaches grow the odd palm. The per-cell roll is an FNV hash of the
   quadrant-local index and the terrain seed (Combat's `_roll_unit`
   idiom), so placement stays deterministic and inherits map symmetry by
   construction. Measured on the Standard 84×96 map: **1,920 natural
   nodes vs ~134 before — 14x** (the goal said "target 15x"), one tree
   per ~4 cells, total map stock 334k vs ~322k before.

2. **Trees are small and quick; ore stays rich and held.** Per-kind
   stock: `TREE_STOCK` 105 for wood/food — sized so one shipped gatherer
   squad (5 × 0.35/s) works a tree out in **~60 s**, pinned against the
   shipped def by a test (D-066's lesson) — and `RICH_STOCK` 2400 for
   gold/stone, which keep the "place worth holding" economics (D-039).

3. **Stone moved to the mountain FOOT.** The old generator put stone ON
   mountain/peak cells, which `passability()` marks unwalkable — every
   naturally placed stone node was unreachable scenery, and the AI's
   whole give-up-on-unreachable-nodes mechanism (D-034's amendment) was
   built against exactly these. A foot cell (walkable, bordering
   mountain) is reachable by construction; a test now asserts every
   natural stone node sits on passable ground.

4. **A worked-out tree retargets its crew.** With trees a minute deep a
   crew retires one per haul cycle; making the player re-issue the order
   per tree would be micro tax, so `Economy._retarget` walks
   `TorusSpace.disk_offsets(RETARGET_RADIUS=8)` (nearest-first since
   D-067) for the closest surviving node of the SAME kind — never
   substituting kinds, which was the AI's own old bug — and releases the
   crew if none stands. Deterministic, server-side, replay-safe.

5. **Fellings are a wire event** (`S2C_NODES_DEPLETED`), fog-gated per
   client exactly as reveals are (D-025's shape): sent when a client that
   KNOWS the node can SEE the cell — immediately for whoever is standing
   there, on next sight for a player behind the fog, never for one who
   never returns, whose client keeps drawing the tree (a building
   ghost's staleness, D-030). The fresh-node scan skips already-dry
   nodes, so a late scout is never told a stump is a resource. The
   client erases the node on receipt (AI targeting and the minimap read
   `nodes`) and queues the felling for the renderer.

6. **The client draws forests, not markers.** 50 authored tree models —
   10 species × 5 variants, split from the hand-authored
   `tree-variants.glb` by the same `split_markers.gd` pipeline (groups
   discovered, not listed) — are picked per cell by `ResourceVisuals`,
   a new all-static pure class (the RenderCull/SelectionPick split):
   species pools follow biome and moisture (wet forest swaps toward
   willow/cypress), boundary cells borrow a neighbour's pool 35% of the
   time so treelines fray instead of snapping along the noise threshold,
   and yaw/scale jitter comes from per-cell hashes. Trees batch into one
   MultiMesh per (16-cell chunk, model) — thousands of trees cannot be
   thousands of Node3Ds — with the torus tax paid per CHUNK per frame
   (D-035). A felled tree leaves its chunk and becomes a short-lived
   individual instance playing `fall_pose`: an accelerating tip about
   its base, then a sink; ore sinks without tipping. Trees stand at
   0.60–0.92 of authored size because the source canopies (~2.5 world
   units) are wider than a cell and full-size dense forest merged into
   a single blob on screen.

**Rationale:** The goal was visual (forests that look like forests,
aligned to the ground, with variety and a felling animation) but the
honest version demanded economy changes: many small nodes is a different
resource model from few rich ones, and a felling animation needs the
client to LEARN of depletion, which nothing on the wire carried — stock
was deliberately never replicated (D-028). Fog-gating the new event per
client rather than broadcasting keeps D-025's "you learn what you can
see" intact for the map itself.

**Rejected alternatives:** Replicating remaining stock per node
(constantly changing state on the wire for a number the client only needs
one bit of); client-side depletion inference from gather traffic (bots
and fog make it unknowable); one MeshInstance3D per tree (the M4 `by_id`
shape: thousands of scene nodes for things that never individually move);
per-tree lattice-offset updates (torus tax per tree per frame — paid per
chunk instead); trees as passability obstacles (a forest you cannot walk
through changes flow fields and D-007's sharing claim — explicitly out of
scope); gating the load-test verdict on `nodes_felled > 0` (a felling
needs hall + crew + 60 s of gathering, so the gate would pin every run to
~3 minutes — the exact stale-timing trap D-031 set for `test-load 4 40`;
it is a printed metric instead, asserted by running long and reading it).

**Consequences:** Bots now put produced gatherers to work (they had
produced and never ORDERED them for two milestones, so the whole haul
cycle ran under the load test for the first time) and report
`nodes_felled` in the verdict line. Total map resource dropped ~0% on
Standard but the map's WOOD is now ~1,438 trees × 105 rather than ~30
nodes × 2400 — armies chew through a forest front visibly. The
`_explored` client-side gate on node drawing was removed: the server has
fog-gated node knowledge since D-061, and double-gating hid nodes
revealed by an ally's shared vision (D-050). `test_economy`'s density
guards inverted for trees only (dense woods asserted, scarce ore still
asserted).

**Revisit trigger:** If gatherer stats change, `TREE_STOCK` must move
with them (a test pins the ~60 s relationship). If tree counts grow past
~8k (Huge maps) and chunk rebuilds or the per-node placement pass show up
in a frame profile, promote placement to a bulk pass. If forests ever
gain gameplay meaning (concealment, passability), that is a new decision
— this one is explicitly cosmetic-plus-economy.

**Amendment, 2026-08-16 (D-108):** clause 6's last sentence — one tree
per cell at 0.60–0.92 of authored size so canopies could not touch — is
**superseded by D-108**. A playtest found that a wood read as ranks and
files: the region-scale outline this decision's density field produces
was organic, and its interior was the hex lattice, because the only
positional freedom a tree had was which cell it stood in. A cell now
grows a hash-chosen STAND of trees on their own bounded offsets, and the
canopy shrink is reversed. Everything else here stands unchanged,
including the per-cell purity, the chunked batching and the felling
path — a felling now plays one instance per tree in the cell. Note the
consequences paragraph above already quoted **1,438 wood nodes**; the
same map now draws **4,202 trees** on them.
