### D-108 · 2026-08-16 · Accepted — a node cell is a STAND of trees, not one tree on the lattice point

**Decision:** a resource node is drawn as several trees on their own
offsets inside its cell, and the canopy shrink D-087 introduced to stop
them touching is reversed. Concretely, in `ResourceVisuals`:

1. **A cell grows `tree_count_for` trees, not one.** The count comes from
   a per-biome base (`BASE_TREES`: forest 3.4, grassland 2.4, dry 1.5,
   beach 1.8) swung ±30% by the cell's own moisture, then spread
   **uniformly over a range** around that mean rather than rounded to it —
   never below 1, never above `MAX_PER_CELL` (5). The spread is the point:
   an equal count in every cell is the same lattice at a different
   spacing. Ore is always exactly one seam.
2. **Every tree stands off the cell centre.** Tree *i* of *n* takes sector
   *i* of a ring, wandering within `SECTOR_JITTER` (0.62) of that sector,
   at a radius in `[MIN_OFFSET, MAX_OFFSET]` = [0.34, 0.78] hex_size. At
   n = 1 the sector is the whole circle, so a lone tree still goes
   anywhere — which alone is what breaks the ranks and files.
3. **`MAX_OFFSET` is under a hex's inradius** (sqrt(3)/2 ≈ 0.866), so a
   tree never leaves the cell it belongs to. That is the whole safety
   argument: it cannot drift onto water or over a cliff, and it stays
   nearer its own cell's centre than any other's, which is what the click
   test ranks by. Ore takes a tighter `ORE_MAX_OFFSET` (0.35) because a
   seam is *the* thing a player clicks.
4. **Species, variant, yaw and scale roll PER TREE**, salted with the
   tree's index through `_roll_at(cell, salt, index)` — GroundCover's
   arithmetic, for GroundCover's reason. A cell of four identical models
   at four sizes is a clone stamp, not a stand.
5. **Canopy scale goes back up**: 0.60–0.92 → **0.68–1.10**, so canopies
   are wider than the cell under them and interlock. Ore keeps the old
   0.60–0.92 range; that range was about canopies touching, which a lone
   boulder cannot do.
6. **Rendering only.** A node's *cell* is simulation state — economy
   targeting, gather range, `S2C_NODES_DEPLETED` and its fog gating are
   all per-cell — and none of it moves. The same split D-084/D-096 kept
   for terrain: the picture varies, the simulation stays discrete. The
   client samples ground height **at each tree's own position**, not at
   the cell centre, or a stand on a slope stands in the air.
7. **`just gen-forest-preview` is the instrument.** A rendered wood, from
   a low angle, framed on the densest patch of forest on the map, through
   the real `Economy.generate` → `ResourceVisuals.trees_for` → `UnitMesh`
   → one MultiMesh per model path.

**Rationale:** reported from the #29 lobby playtest (issue #51): a forest
read as ranks and files you could count along. The region-scale outline
was organic — D-087's density field doing its job — and the interior was
unmistakably a hex grid. Two causes, both in the code:

- every tree stood at the exact cell centre, so the only positional
  freedom a tree had was which cell it was in. Placement was at hex
  resolution and the eye read the lattice straight off it;
- canopies had been deliberately shrunk to 0.60–0.92 *so that they could
  not touch*, because at one tree per cell centre full-size canopies
  merged into one undifferentiated blob. The hard gap around every tree
  was the other half of what made it read as artificial.

Those two interlock, which is why the fix is one decision and not two:
**position has to vary before canopies may grow.** Scale alone
reproduces the blob that motivated the shrink; offset alone leaves
placement at hex resolution — dithered rows are still rows, and a wood
still cannot be denser than the node grid allows.

Measured on the shipped Standard map, in `tests/test_resource_visuals.gd`:
**1,438 wood nodes now grow 4,202 trees (2.92 per cell)**, and **99% of
trees have a neighbour inside a canopy width** — 2.15 world units, taken
off the shipped meshes at the middle of the new scale range rather than
written down. Before, every tree had a clear ring around it by
construction.

**Rejected alternatives:**
- **An offset and nothing else** (the issue's step 1 on its own). Breaks
  the ranks and files and leaves the density ceiling exactly where it
  was: one tree per node cell means a wood can never be thicker than
  D-087's placement field, whatever it looks like up close.
- **Raising the canopy scale and nothing else.** This is the change
  D-087 already tried in the other direction and backed out of. On a
  regular lattice it is strictly worse than what shipped.
- **Sub-cell node positions in the simulation** — give the node itself a
  world position instead of a cell. That is the honest version of "trees
  are where they are drawn", and it is a wire, economy, fog and gather
  range change for a cosmetic complaint. D-084/D-096 settled the pattern
  for terrain and it applies unchanged.
- **An RNG, or deriving placement from world position.** Both were named
  out in the issue and both are right to refuse: the module is a pure
  hash of the cell (D-087) so two clients and nine torus copies agree by
  construction, and a world-position derivation would dress each lattice
  copy differently (D-035's reason for cell-derived terrain UVs).
- **A Poisson-disk or blue-noise scatter over the whole map.** Better
  spacing in principle, and not a pure function of one cell — it needs
  global state, so it would have to be replicated or recomputed
  identically everywhere, and it cannot be evaluated per chunk as chunks
  are built. The per-cell ring gets clumping from the count spread
  instead, for one hash per tree.
- **Clamping offsets against passability.** The issue suggested it and it
  is unnecessary once the bound is under the inradius — the tree is on
  its own cell's ground by construction. It would also make a pure module
  read terrain it currently does not need, for a check that can never
  fire.

**Consequences:**
- Wood instances roughly triple (1,438 → 4,202 on the shipped map). They
  are MultiMesh instances built **per chunk on a reveal or a felling**,
  never per frame, which is the budget D-087 set. `bench-render` has not
  been re-run for this; the frame at full scale is CPU-bound on soldier
  derivation, not on static MultiMeshes (D-086/D-096).
- A felling now stands up one instance per tree in the cell, each tipping
  about **its own** axis (`tip_axis_for(cell, index)`) — a stand that all
  went over the same way at the same moment reads as one object breaking.
- `client.gd`'s chunk table keys a cell to a LIST of trees, and
  `_node_placed` keeps the cell's models plus the CELL's own centre.
  `_resource_cell_at` still ranks by that centre: the drawn trees are all
  inside the cell, so the hit test and the picture cannot disagree by more
  than the cell.
- `model_for` gained an `index` parameter (defaulting to 0) and
  `scale_for` became kind-aware. Both are cosmetic entry points with no
  callers outside the client and its tests.
- **A new instrument, because none of the existing ones could see this.**
  `gen-terrain-preview` draws a top-down biome map with no trees in it;
  `test-client` aims its camera at a spawn, which is open ground by
  construction and therefore the one place a wood is least likely to be;
  every assertion in `test_resource_visuals.gd` was about species pools,
  bounds and determinism. This is the third time a defect has been
  invisible to every number and obvious in a picture, and the third time
  the answer has been a recipe that frames the thing on purpose —
  `gen-terrain-shot` (D-096) and `gen-cover-preview` (D-100) are the
  other two.

**Revisit trigger:** `bench-render` showing tree instances as a material
share of the frame at D-018's full scale (they are static geometry today,
and the frame is soldier-derivation bound); or `MAX_PER_CELL` being
raised as a *tuning* lever rather than staying a worst-case bound, which
is how a cap quietly becomes a knob; or trees acquiring any gameplay
meaning at all — sight blocking, cover, movement cost — at which point
where a tree is drawn stops being cosmetic and clause 6 has to be
reopened rather than extended.

**Numbering note:** written as D-101, renumbered to **D-107** at the
rebase onto main, and renumbered again to **D-108** when the merge train
landed — which is exactly the merge step D-098's amendment says is the
right moment to fix a number. Main's D-100 records a coordinator
assigning numbers across seven parallel branches — #68=D-099, #70=D-100,
**#66=D-101**, #76=D-102, #71=D-103, #73=D-104, #75=D-105, #78=D-106 —
and this work (PR #72) is not in that list, so D-101 belongs to somebody
else and the first number clear of the whole assigned block is D-107.
**Reasoning identically, PR #77 also took D-107, and it merged first**,
so this entry moved once more. That is the third instance of the same
trap in one afternoon: picking "the first free number" is safe only
against numbers you can SEE, and a branch you cannot see is exactly what
parallel work consists of. The durable fix is a coordinator assignment
that covers every open branch, not a smarter derivation.
Taking a number *inside* the block and letting the coordinator sort it
out later is the failure D-100's own note is still paying for: two
entries meaning different things under one ID, with code citing both.
This may still need reconciling if #72 is assigned a number of its own.
---
