### D-084 · 2026-08-10 (reconstructed 2026-08-11) · Accepted — a watertight hex surface, and the simulation untouched

**This entry is a reconstruction — see the editorial note above.**
`CLAUDE.md` cites this work at `D-067`, which collides with the real
D-067 below (squad shoving / one-squad-cannot-raze-a-base). This entry
gives the terrain-surface work its own ID.

**Decision:** Gaps between hexes — pre-existing, but invisible until
textured ground made them the most obvious thing on screen — are closed
by making each hex corner take the mean elevation of the three cells
meeting there, so neighbouring hexes agree on their shared corner and the
surface is watertight. The centre vertex keeps its own cell's elevation,
which leaves each hex a shallow pillow rather than a flat tile. Normals
are derived from the resulting surface instead of hardcoded
`Vector3.UP`, so slopes finally shade instead of lighting flat regardless
of grade.

`TerrainGen.surface_field` is one array of 7 heights per cell (6 corners
+ centre), read by BOTH the mesher (`terrain_chunk.gd`) and the client's
ground sampler (`TerrainChunk.height_at`) — deliberately the same file,
because a sampler that only matched the mesh by being written correctly
twice would eventually drift, and the symptom of that drift is an army
floating with every other number green.

**Rationale — the simulation must not change, and does not.**
`TerrainGen.elevation_at` stays discrete per cell and `passability` still
thresholds it; only the picture interpolates between corners. That split
is what makes this a rendering-only change with no desync surface: the
server's notion of a cell's elevation and passability is byte-identical
before and after. It stops being free the moment elevation acquires
tactical meaning (terrain-occluded line of sight is still an open
question, not decided here).

**Consequences:** `TerrainChunk.height_at` is a hot path — called once
per soldier per frame by the client's ground sampler, no longer a single
array index. Its cost on real hardware was, at the time this landed,
unmeasured; D-086's `bench-render` numbers are the first real measurement
of the full render path including this sampler, since `bench_render.gd`
explicitly samples through the same `TerrainChunk.height_at` the client
uses rather than deriving at a fixed height.

**Revisit trigger:** if terrain elevation is ever given tactical meaning
(occlusion, high ground combat bonuses), the discrete-vs-interpolated
split this entry relies on needs to be revisited explicitly — the
simulation's answer and the picture's answer would need to agree again,
the same way they were kept apart on purpose here.

---
