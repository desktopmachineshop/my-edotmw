# D-20260818 · 2026-08-18 · Accepted — a revealed forest is grown a budgeted slice per frame

**Decision:** the client grows newly revealed resource-node cells through a
**queue with a per-frame budget** (`node_placement.gd`, `NodePlacement.
PER_FRAME` = 24 cells), instead of growing every cell revealed since the
last frame in the frame it arrived. Four clauses:

1. **The budget counts CELLS, not milliseconds.** Same unit choice as
   D-040's flow-field fix, and for a stronger reason here: a wall-clock
   budget makes the amount of world drawn depend on how loaded the host
   is, so two runs of one match draw differently. This project has already
   paid once for gating on time (D-106's amendment — a "cost does not
   scale with the map" test that went red on a loaded host with nothing
   wrong), and the rule that came out of it — **assert WORK, not time** —
   applies to spending it as much as to checking it.
2. **Partial progress is kept.** A half-grown forest is safe to look at;
   it is simply incomplete, and completes over the next few frames. This
   is the property D-038's budget-on-BUILDS lacked and D-040's
   budget-on-CELLS had.
3. **Reveals arrive as NEWS, not as a diff.** `ClientState.revealed` /
   `take_revealed()`, the sibling of `felled`/`take_felled()` that has
   been there since D-087. The client used to find new cells by walking
   all of `nodes` — 7,664 of them on the shipped map — guarded by
   `_state.nodes.size() != _node_placed.size()`, a size comparison
   standing in for set equality. That guard was sound only while drawn
   and known moved together; a budget makes drawn lag known **on
   purpose**, so the guard would be true on every frame spent catching up
   and the scan would run on every one of them.
4. **A cell felled before its turn is dropped from the queue**
   (`NodePlacement.forget`). The server reports a felling once, and it
   reports it for a tree this client had not got round to growing — grown
   afterwards, that stand would stay standing for the rest of the match.

## Rationale

**Measured first, because the issue named two candidate causes and M4's
standing lesson is that every hypothesis formed before instrumenting was
wrong.** Issue #109 filed the playtest report ("forests appear in bulk")
with two live explanations: placement cost causing a frame hitch, or
D-025's reveal pop-in working exactly as designed. Those want opposite
fixes — a budget, or a fade-in.

Placement cost, measured headlessly on the shipped default map
(168 x 194 = 32,592 cells, 7,664 nodes), Godot 4.7.1, native, 2026-08-18:

| | |
|---|---|
| per node cell | **87 us** |
| all 7,664 nodes | **666 ms** |
| trees grown | 20,919 |

That is the real per-cell work `client.gd`'s `_place_node` does: a terrain
height sample, `biome_at`, `moisture_at`, **six** neighbour `biome_at`
calls, then `ResourceVisuals.trees_for` and a further height sample per
tree. It excludes the MultiMesh repack that follows, so it is a floor.

87 us a cell means **192 cells is a dropped frame** at 60 fps, and a squad
walking into unexplored woodland reveals cells by the ring. So candidate 1
is real and is fixed here. Candidate 2 is not thereby disproved — a
truthful pop-in is still a pop-in — but it is now separable, which is what
the instrument below is for.

**24 cells is ~2.1 ms of a 16.7 ms frame** at the measured rate, which
leaves the rest of the frame to the client M10 is trying to make playable
at this map size. A reveal of 300 cells finishes in a fifth of a second
instead of in one 26 ms hitch; the whole map, which no match reveals at
once, would take 5.3 s.

**And an instrument, because the two candidates stay confusable.** The
sandbox panel (D-077) gains a line — `Nodes: N known / M grown / P queued
— worst frame X.X ms` — and the capture verdict gains `nodes_known=`,
`nodes_grown=`, `nodes_queued=`, `node_grow_worst_ms=`. A human watching
trees arrive can now tell "the client is behind" (queued > 0) from "the
server only just said they were there" (queued 0, and they still popped).
Neither is a gate: a run whose squads never reach a wood grows nothing,
the same reason `nodes_felled` is a metric rather than a gate in
`test-load`'s verdict.

## Rejected alternatives

- **A fade-in instead of a budget.** That is candidate 2's fix, and it
  addresses how a pop-in looks, not a dropped frame. The measurement says
  the frame is real. A fade may still be worth having; it is a separate
  decision and does not belong in this diff.
- **A wall-clock budget** ("grow until 2 ms are gone"). See clause 1.
- **Reducing the work per cell** — caching `biome_at` for the six
  neighbours, or growing fewer trees. Both change what the world LOOKS
  like or duplicate a field that already exists; and node density is
  issue #94's question, deliberately not this one.
- **A worker thread.** The samples are pure, so it is possible, but the
  scene-tree half (chunk roots, MultiMeshes) is not, and a budget is a
  dozen lines against a threading model. Left open for #106, which has
  the larger version of the same choice for terrain meshing.
- **Prioritising the queue by camera distance** rather than by reveal
  order. Tempting and untested: reveal order is already roughly
  camera-order, since what a player reveals is what their squads are
  walking into. Not worth the ranking cost without a picture that shows
  the wrong forest arriving first.

## Consequences

- Forests appear over a few frames rather than all at once. That is
  visible and intended; `queued` in the sandbox readout says how far
  behind the world is.
- A chunk whose cells arrive across several frames is repacked on each of
  them (`_rebuild_tree_chunk` rebuilds whole chunks, and only dirty ones).
  Total repack work rises; per-frame work falls, which is the trade being
  made.
- `ClientState` carries one more drain list. It is bounded by the map's
  node count for exactly the reason `felled` is — the server sends a cell
  once — so a headless consumer that never drains it cannot grow without
  limit.
- The size-comparison guard #109 flagged as "one edit away from a bug" is
  gone rather than fixed in place.

## Revisit trigger

- A playtest still reports forests arriving in bulk with
  `nodes_queued = 0` in the sandbox readout. That is candidate 2, and the
  answer is a fade-in, not a smaller budget.
- The per-cell cost moves materially — #94 changes how many nodes exist,
  not what one costs, but a change to `ResourceVisuals.trees_for` or to
  `_place_node`'s sampling would move it, and 24 was chosen against 87 us.
- The client stops being CPU-bound on derivation (M5/D-045), at which
  point the whole budget question is worth re-measuring rather than
  re-tuning.
