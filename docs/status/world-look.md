**D-086 (2026-08-11): the lighting layer M7's art never had.** The
"low poly vs cartoon vs current" style question turned out to have a
false premise — the game was already low poly at the extreme end (two
primitives, 72-256 tris/soldier against a 300 budget); what actually
separated the three options was lighting, and the project had almost
none (one `DirectionalLight3D`, a flat navy `BG_COLOR`, no shadows, no
sky, no tonemap, no fog, duplicated by hand across three files). Chose
**polished low poly**: `world_look.gd` is now the one definition of the
rig (guarded by a test that scans every other script for a stray
`DirectionalLight3D`/`Environment` construction); sky, sky-sourced
ambient, ACES tonemap and depth fog replaced the flat void at a measured
cost of essentially zero (54.26 ms vs 53.93 ms mean at 1,000 squads); the
8-colour terrain palette was re-tuned for the new tonemap. **Shadows were
evaluated against the bench-render number above and explicitly deferred**
— at 1,000 squads the frame was already 3.2x a 60 fps budget before
spending anything on a shadow pass; 250 squads (76.6 fps) has headroom
for a future squad-count-gated version. Cartoon/toon shading was rejected
for the same reason: its outline pass would double the per-soldier vertex
shader (including the VAT's three `texelFetch`es) and cannot be verified
by `test-client`'s software rasteriser at all (Forward+-only
`CompositorEffect`).

**The gaps between hexes are fixed (D-084).** They were pre-existing
rather than M7's, but textured ground made them the most obvious thing on
screen. Each hex corner now takes the mean of the three cells meeting
there, so neighbours agree and the surface is watertight; the centre
vertex keeps its own elevation, which leaves each hex a very shallow
pillow. Normals are derived instead of hardcoded `Vector3.UP`, so slopes
finally shade.

**The simulation did not change and must not.** `elevation_at` stays
discrete per cell and `passability` still thresholds it — only the
picture interpolates. That split is what made this a rendering change
with no desync surface, and **it stops being free the moment elevation
acquires tactical meaning** (terrain-occluded line of sight is still
open).

`TerrainGen.surface_field` is one array of 7 heights per cell, read by
BOTH the mesher and the client's ground sampler
(`TerrainChunk.height_at`), which is why they live in the same file. A
sampler that matched the mesh only by being written correctly twice would
eventually drift, and the symptom is an army floating with every number
green. The sampler is also a hot path — once per soldier per frame — and
is no longer a single array index. **Its cost on real hardware is
measured now**: 22-29% of the client's whole derivation phase at 1,000
squads, ~4.5 us per drawn man on Intel Iris Xe — see
`docs/status/client-render.md` and
`D-20260828-every-microsecond-of-a-frame-has-a-phase`.
