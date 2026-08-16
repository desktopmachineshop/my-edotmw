### D-086 · 2026-08-11 · Accepted — polished low poly: the lighting layer the game never had

**Decision:** The art style question ("low poly vs cartoon vs the current
method") had a false premise — `art/lib/geom.py` exposes exactly two
primitives (`box`, `prism`), every shipped model runs 72-256 triangles
against a 300/460/400 budget (D-081), and the shading is already flat
Lambert with no specular. The game is already low poly, at the extreme
end. Nothing about it is geometry-limited.

What separated "low poly", "cartoon" and "the current method" turned out
to be the lighting layer, and the project had almost none: one
`DirectionalLight3D`, a flat `BG_COLOR` navy void, a constant blue-grey
ambient, no shadows, no sky, no tonemap, no fog, no post-processing —
duplicated by hand across `client.gd`, `bench_render.gd` and
`model_preview.gd`. The chosen direction is **polished low poly**
(Northgard / Bad North) over cartoon/toon, because the entire cost is in
that lighting layer plus a palette re-tune — it needs no change to the
asset pipeline, unlike toon's outline pass (see Rejected alternatives).

**What shipped:**

1. **`world_look.gd`** (`class_name WorldLook`, all-static, the same
   convention as `render_cull.gd`/`formation.gd`/`hud_layout.gd`) — the
   one definition of the rig, replacing three hand-copies. Guarded by
   `tests/test_world_look_is_the_only_light.gd`, which scans every script
   outside `world_look.gd` for a direct `DirectionalLight3D.new()` or
   `Environment.new()`. Observed failing before trusting it, per this
   project's standing rule: a stray construction was added to
   `hud_layout.gd`, the test caught it, then it was removed and the test
   passed again.
2. **Sky, sky-sourced ambient, ACES tonemap, depth fog** — `BG_SKY` with
   a `ProceduralSkyMaterial` replaces the navy void; ambient now samples
   the sky (`AMBIENT_SOURCE_SKY`) instead of a constant colour, which is
   the change that does most of the work, because flat-shaded geometry
   lit by a single hard light plus a flat ambient term reads as
   cardboard; `TONE_MAPPER_ACES` replaces no tonemap at all; depth fog
   ties its colour to the sky horizon for aerial perspective at RTS zoom
   (camera height 8-31 on the shipped map). Measured cost: negligible —
   54.26 ms mean at 1,000 squads against 53.93 ms before, on the same
   hardware, same run shape.
3. **Terrain palette re-tuned** (`terrain_gen.gd:biome_color`) — ACES
   compresses highlights and desaturates midtones, and sky ambient pushes
   everything cooler, so the pre-existing 8 biome colours read muddier
   than authored. The two darkest biomes (deep water, forest) were lifted
   the most since they were closest to crushing toward black; land biomes
   were warmed slightly to offset the sky tint. Relative ordering
   (deep water darker than water, forest darker than grassland) was kept
   on purpose — that hierarchy is what a player reads at a glance.
   `biome_at()`, which actually gates passability, is untouched.
4. **Shadows were evaluated and explicitly deferred**, not shipped — see
   Rejected alternatives.

**Measurement, taken before spending anything (Step 0 of this work):**
`just bench-render` on Intel Iris Xe, native, Forward+, through the same
cull+LOD path `client.gd` uses (`bench_render.gd` mirrors
`RenderCull`/`_detail_for`):

| squads | soldiers | ms mean | ms worst | fps mean | squads drawn |
|---|---|---|---|---|---|
| 0 | 0 | 2.09 | 3.22 | 477.8 | 0 |
| 100 | 2,730 | 5.48 | 7.85 | 182.5 | 64 |
| 250 | 6,825 | 13.06 | 14.29 | 76.6 | 183 |
| 500 | 13,650 | 26.97 | 36.34 | 37.1 | 363 |
| 1,000 | 27,300 | 53.93 | 54.55 | **18.5** | 741 |

This discharges D-085 criterion 11 (partially — see Rejected
alternatives on the discrete-GPU point) and answers M7's open question
about the real cost of VAT-animated authored models: **M5's 35.66 ms /
28 fps at 1,000 squads on this same Iris Xe was measured with primitive
capsules, before authored models landed.** The authored-model number is
53.93-54.26 ms / 18.4-18.5 fps — **51% slower at full scale**, not the
several-fold-*under*-stated figure CLAUDE.md's M4 section warns about for
the unrelated 0.72 µs/soldier derivation figure. The animated-vertex cost
is real, and it was unmeasured until this decision.

**Rationale:** A presentation pass is style-neutral and is a prerequisite
for either "polished low poly" or "cartoon" to look intentional rather
than unfinished — building it first, then judging the two options with a
picture in hand, is cheaper than judging them in the abstract and
possibly re-doing the judgement. Once built, the picture matched
"polished low poly" well enough (see `artifacts/client-frame.png`,
D-086) that committing further to toon was not worth its cost (below).

**Rejected alternatives:**
- **Cartoon / toon shading** (`diffuse_toon` + rim light + outline).
  Rejected for now, not permanently. The diffuse/rim half is nearly free
  — a token change in three shaders and some parameters in
  `SoldierParams`. The outline half is not: an inverted-hull outline
  doubles the vertex shader over every soldier, **including the VAT's
  three `texelFetch`es per vertex**, and a screen-space edge pass needs a
  Forward+ `CompositorEffect` that `test-client`'s Mesa software
  rasteriser (`gl_compatibility`) cannot run at all — the automated
  visual check would go blind to it. Given Step 0's number, spending
  that on top of an already over-budget frame at full scale was not
  justified without a stronger reason to prefer it over polished low
  poly.
- **Shadows.** Evaluated against Step 0's own stated gate ("if the
  current frame is already at or over budget on this hardware, shadows
  come out of scope... decide this from the number, not in advance"). At
  1,000 squads the frame was already 53.93-54.26 ms — 3.2x a 60 fps
  budget and under 20 fps outright — before spending anything on a
  second render pass per shadow cascade. Deferred, not rejected outright:
  250 squads (76.6 fps) has real headroom, so a squad-count-gated shadow
  pass is a reasonable future revisit, not ruled out here.
- **Full re-author of the unit/terrain palette from scratch.** Rejected
  in favour of re-tuning the existing 8 terrain colours and leaving
  `SoldierParams` colours alone. A `SoldierParams` change requires
  `just build-assets` and a re-commit of the hash-gated `generated/`
  tree (D-081); the lighting change alone got most of the visual delta,
  so that cost was not spent.

**Consequences:** `client.gd`, `bench_render.gd` and `model_preview.gd`
no longer construct their own lighting; both the shipping rig and the
benchmark rig are now structurally guaranteed to match, closing the gap
`bench_render.gd`'s own header warns about ("a benchmark camera that is
merely similar measures a similar game"). `terrain_gen.gd:biome_color`
carries a comment explaining why its 8 colours no longer match their
pre-D-086 values. D-085 criterion 14 (a human plays a match with the new
art) is **still open** — nothing in this decision involved a human
playing, only automated headless-ish verification
(`bench-render`, `test-unit`, `test-client`, `gen-terrain-preview`,
`test-load`), consistent with the standing rule against launching the
game unprompted.

**Revisit trigger:** shadows, if a squad-count-gated version is ever
built, or if a discrete GPU becomes available to re-measure Step 0's
number and shadows fit inside it at full scale. SSAO, if it ships despite
being invisible to the `gl_compatibility` verification path — that gap
would need to be stated wherever SSAO is decided, the same way it is
flagged here as a reason it was not attempted. Toon/outline, if
playtesting after D-085 criterion 14 is finally discharged says
readability at zoom is the binding problem polished low poly did not
solve.

---
