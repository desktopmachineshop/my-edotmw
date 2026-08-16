### D-083 · 2026-08-09 (reconstructed 2026-08-11) · Accepted — terrain texturing: the atlas modulates, biome_color decides

**This entry is a reconstruction — see the editorial note above.**
`CLAUDE.md` cites this work at `D-066`, which collides with the real
D-066 below (building damage scale). This entry gives terrain texturing
its own ID.

**Decision:** Terrain is textured by a per-biome atlas
(`art/terrain/atlas.py`) that **modulates** vertex colour rather than
replacing it. `TerrainGen.biome_color()` stays the single source of
truth for what a biome looks like, read by the 3D mesh, the minimap and
the offline preview PNG alike — the property that keeps all three from
drifting apart without any of them being touched, and the reason
`biome_color()` and the mesher live where they do.

The atlas is `2048x1024` (4 columns x 2 rows of 512px tiles), generated
by periodic (seam-continuous) value noise so every tile wraps exactly —
required because the world tiles nine times (D-035) and a non-periodic
texture would show a seam at every join. Each biome's noise recipe is
its own RNG stream (`SEED + biome_index * 977`), so adding a ninth biome
cannot perturb the existing eight. Every tile is normalised to average
**`NEUTRAL_MEAN = 0.92`** — deliberately short of full white — so that
multiplying it against `biome_color()`'s value darkens the surface only
slightly instead of tinting it; the atlas may add texture, never colour.
Per-cell UV rotation is hashed from the wrapped cell coordinate, so the
hex lattice does not read as an obviously repeating tile.

UVs are derived from the **cell**, never from world position — the same
reason terrain elevation is cell-keyed (D-084) — so all nine torus
copies of a hex agree on their texture by construction rather than by
each copy computing its own answer and hoping they match.

**Rationale:** A single source of truth for colour is what let D-086
re-tune the palette for the new lighting rig by editing eight `Color`
literals in one function, with the minimap and preview PNG updating for
free. Had the atlas carried its own colour independent of
`biome_color()`, that re-tune would have needed a `just build-assets`
rebuild and a `generated/` re-commit on top of the code change, and the
three views (3D, minimap, preview) could have drifted from each other in
the process.

**Rejected alternatives:** Letting the atlas tint the terrain directly
(rejected — see above: it would make the atlas a second source of truth
for colour, defeating the reason `biome_color()` exists as a single
function everything reads).

**Consequences:** Any future palette change touches only
`terrain_gen.gd:biome_color` — confirmed directly by D-086, which did
exactly that and needed no atlas rebuild.

**Revisit trigger:** if a biome ever needs texture variation that
`biome_color()`'s flat per-biome colour cannot express (e.g. patchy dead
grass within GRASSLAND), the "atlas never carries colour" rule would need
an explicit, deliberate exception — not a silent one.

---
