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

**And growing a revealed forest was unbudgeted
(D-20260818-node-placement-is-budgeted, 2026-08-18, issue #109).** Every
node cell the server had revealed since the last frame was grown in the
frame it arrived. Measured on the shipped map: **87 us a cell, 666 ms for
all 7,664 of them** — a terrain height sample, `biome_at`, `moisture_at`,
six neighbour `biome_at` calls, then `trees_for` with a further sample per
tree, and that is before the MultiMesh repack. So **192 revealed cells is
a dropped frame**, and a squad walking into unexplored woodland reveals
cells by the ring. `NodePlacement` is a queue with a per-frame budget
(24 cells, ~2.1 ms), the same shape as D-040's flow-field fix: budget the
work unit, keep partial progress.

Three things worth carrying:

- **The issue was filed with two candidate causes and the instrument that
  could tell them apart did not exist.** A placement hitch and D-025's
  truthful pop-in produce the same complaint — "the forests arrived all at
  once" — and want opposite fixes, a budget or a fade-in. The measurement
  says the hitch is real; the sandbox panel now reports `known / grown /
  queued` and the worst frame so the other one stays separable. **A report
  still arriving with `queued = 0` is the pop-in, and a smaller budget
  would do nothing for it.**
- **A budget makes drawn lag known ON PURPOSE, which retired a guard that
  was sound until it wasn't.** The client found new cells by comparing
  `_state.nodes.size()` with `_node_placed.size()` — a size comparison
  standing in for set equality, harmless while the two moved together, and
  a full 7,664-entry rescan on every frame spent catching up once they do
  not. Reveals arrive as news on `ClientState.take_revealed()` now, the
  sibling of the `felled` drain D-087 already had.
- **Being deliberately behind creates a state that did not exist before:**
  a node felled between the packet that revealed it and the frame that
  would have grown it. The server reports that felling once, for a tree
  this client never drew, so the queued cell has to be dropped or the
  stand grows on a stump and nothing ever takes it down.
