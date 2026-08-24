# D-20260824-a-supplied-model-becomes-an-authored-source

**Date:** 2026-08-24 · **Status:** Provisional (the gatherer model is an
explicit placeholder; the mechanism is Accepted)

From the owner supplying a `.glb` — a Tripo-generated dwarf miner — with
"use this file for all the gatherer units for now".

## Decision

1. **A model that arrives from outside is CONVERTED INTO an authored
   `.blend`, not taught to the bake as a second source format.**
   `art/import_glb_source.py` is the migration —
   `seed_source.py`'s sibling, run once per model, never part of the
   build. After it runs the model is an ordinary authored source
   (D-20260821): `just blender-gui gatherers` opens it, vertex paint edits
   it, `blend_source.bake` owns it. **Nothing downstream learns a new
   word**, which is the whole reason not to add a `.glb` branch to
   `_unit_geometry`.
2. **The dwarf is the gatherer model for every civ.** Both
   `legion_gatherers` and `northmen_gatherers` already carry
   `model_id = &"gatherers"`, so "all the gatherer units" needed no
   `.tres` change at all — one model serves both, and will serve every civ
   the fantasy pivot adds.
3. **It ships over the triangle budget, behind a NAMED exemption.**
   `PLACEHOLDER_TRIANGLE_BUDGET` (6,000) applies to
   `PLACEHOLDER_ARCHETYPES`, today `{"gatherers"}` alone. The set is
   mirrored in `tests/test_art_assets.gd` and **asserted as a set**, not
   just as a ceiling — a budget with an open-ended escape hatch is not a
   budget.
4. **What the placeholder does not have is stated rather than
   discovered:** it does not animate, and it does not carry its owner's
   colour. Both are recorded below with the fix for each.

## What it cost, precisely

| | shipped gatherer | this placeholder |
|---|---|---|
| triangles | 72 | **4,824** (16x the 300 budget; the whole roster is 72-256) |
| vertices | 216 | 3,417 |
| clips | idle, walk, attack, rout | **none — 64 identical frames** |
| owner colour | 36 of 216 vertices at 70% | **none: `COLOR_0` alpha 0 everywhere** |
| colour source | authored per part | sampled from the asset's JPEG into `COLOR_0` |

- **The VAT is the cost nobody would have predicted from the triangle
  count, and it is the bigger one.** `flatten` splits a vertex per CORNER
  (flat shading, one VAT column per corner), so 4,824 triangles became
  **14,472 columns**, not 3,417. The texture is 14,472 x 129 — the file
  went **29.8 KB -> 2.19 MB (73x)** and the model 12 KB -> 725 KB (60x).
  At RGBA half that is roughly **15 MB of VRAM for one archetype**,
  against ~30 KB before. *A triangle budget is not a memory budget, and
  this pipeline's memory cost scales with CORNERS.* If a second placeholder
  is ever added, this is the number to look at first.
- **It will slide, not walk.** `art/clips.py` animates the generated
  `Part` hierarchy and cannot drive an imported armature, so retargeting
  is a modelling job in Blender rather than something a converter can
  fake. The asset arrived with a 43-bone armature and **zero actions**; a
  rig with no actions poses nothing, so it is dropped and the rest pose IS
  the mesh.
- **Its texture cannot be sampled at runtime, so it is baked into
  vertices.** `shaders/unit_anim.gdshader` has exactly one sampler — the
  VAT — and albedo is a baked colour row tinted by team colour. There is
  no texture path for units. The converter samples the basecolor image
  per CORNER through the UVs (14,472 corners), which IS the `COLOR_0`
  contract `blend_source` already reads. A texture becomes vertex colours
  or it becomes nothing.
- **Owner colour is gone for gatherers** until someone paints a mask.
  `COLOR_0` alpha is how much of a vertex takes the player's colour
  (D-052); the converter writes 0, because a uniform tint over a sampled
  texture muddies every colour on the model — which is the failure D-052's
  own comment names. The shipped gatherer tinted 36 of 216 vertices at
  70%. **The fix is now easy in a way it has never been: the source is a
  real `.blend`, so this is vertex paint on one part, not a code change.**

## AMENDED 2026-08-24: its texture is kept, and the reasoning below that
## said otherwise was wrong

This entry originally accepted losing the model's texture, on the grounds
that the unit shader has one sampler and there is "no texture path for
units". True as a description of the code, wrong as a conclusion: the
bake was CHOOSING to discard UV0, and adding the path took six files and
broke nothing. See `D-20260824-a-textured-model-keeps-its-texture`.

The claim that mattered and was never checked is that per-corner colour
is an acceptable substitute for a texture. It is not, at this density —
vertex colour cannot be mipmapped, a 4,824-triangle model covers ~30
pixels at soldier scale, and the result is noise rather than a coarse
dwarf. Everything below about `COLOR_0`, the owner mask and the sampling
still stands; it is now the FALLBACK for models with no texture, which is
every generated one.

## What it looks like — LOOK AT THE PICTURE

`docs/playtest/p34-gatherer-dwarf-placeholder.png`, cropped from
`just gen-model-preview` (the real path: a `UnitDef`, a `PrimitiveUnit`,
the shipping shaders, on real terrain).

**Superseded by the amendment above: the first pictures here were taken
before the texture path existed and show the vertex-colour result.
`docs/playtest/p35-gatherer-textured.png` is what ships.**

**It renders, and it stands in a T-POSE.** Arms straight out, among
soldiers that are walking and swinging. That is the missing-animation
consequence above, confirmed by looking rather than predicted and left —
and it is the single most visible thing about this placeholder, far more
than the triangle count anyone would have worried about first. The
sampled texture reads as mottled brown at soldier scale: recognisably a
figure, not a clean one, because one nearest texel per corner is all a
VAT colour row can carry.

**Posing it is now a two-minute job for a human and was never one for
this converter:** `just blender-gui gatherers`, move the arms down, save,
`just build-assets`. That is exactly the affordance
D-20260821-game-assets-are-files bought, and it is the reason this went
in as a `.blend` rather than as a special case in the renderer.

## Rejected alternatives

- **Decimating to 300 triangles and reusing the existing clips.** Keeps
  the architecture and the walk cycle, and 94% reduction of a character
  sculpt produces something that is not the model the owner supplied.
  Offered as the alternative; `--height` and a decimation pass are one
  command away if the trade is wanted the other way round.
- **A texture sampler in the unit shader, or a skinned render path.** The
  honest way to make this asset look as intended, and a milestone-sized
  change to the renderer and the VAT contract — not a "for now".
- **Teaching `art/build.py` to read `.glb` sources directly.** A second
  source format in the bake, forever, to avoid a one-off conversion. The
  `.blend` is also what makes the model EDITABLE, which is D-20260821's
  whole point.
- **Raising `TRIANGLE_BUDGET` globally.** It would let every future model
  drift up silently. The exemption is a named set for the same reason
  `consumes_builder` is a per-def flag.
- **Baking with the installed Blender 5.2.0 application** (which does run
  headless here). D-081 requires two runs to be byte-identical and the
  pin is 4.5.12; `--only ARCHETYPE` writes `"units": units` wholesale, so
  a single-archetype build DROPS every other unit from the manifest and a
  real bake is always a full one. Using an unpinned toolchain would have
  rewritten every committed binary in `generated/`.

## What was verified rather than assumed

- **`bpy` is NOT blocked on this host any more.** `just bootstrap-art`
  installs the pinned 4.5.12 wheel and it imports.
  `docs/status/rtw-battles.md` records the Windows Application Control
  policy blocking it host-wide on 2026-08-19 and the VAT death clip
  blocked behind it; that is stale, and the death clip is unblocked.
- **The toolchain reproduces the committed assets byte-identically.** A
  full `just build-assets` on unchanged sources left `git status` clean.
  That ran BEFORE any source change on purpose: without it, no diff
  afterwards could be attributed to this change rather than to toolchain
  drift, and D-081's determinism claim would have been an assumption.
- **The converter's first version silently produced the wrong model.**
  Blender's glTF importer adds helper objects the file does not contain —
  this asset declares one mesh and imports as two, the second a 42-vertex
  `Icosphere` — and "join every mesh" made the HELPER the active object.
  It baked a perfectly valid 80-triangle sphere as the gatherer with every
  count downstream agreeing. It now takes the largest mesh and **prints
  what it ignored, with vertex counts**. *A converter that picks silently
  is a converter that can ship the wrong model behind a green build.*

## Consequences

- `art/source/gatherers.glb` is committed beside the `.blend` it produced.
  `.glb` joins `SOURCE_SUFFIXES` in the staleness hash, so editing the
  supplied asset without re-converting is a failing test rather than a
  stale model.
- The seeded `art/source/gatherers.blend` is replaced. It is in git; the
  old generated gatherer is one `git checkout` away.
- **`just bench-render` has NOT been re-run and this owes it.** D-041
  measured the client CPU-bound on soldier derivation, so triangles are
  the half nothing here has measured — and gatherers are the most numerous
  unit a player fields, which makes this the worst place to guess. The
  budget comment says so at the site.

## Revisit trigger

- **The fantasy-civs pivot**, which is what this placeholder is standing
  in for. It reshapes the roster and the per-civ gatherers
  (D-20260823-the-opening-is-a-crew-and-a-general) at the same time.
- **Any second entry in `PLACEHOLDER_ARCHETYPES`.** One over-budget model
  is a placeholder; two is a budget nobody is keeping.
- **A `bench-render` number showing gatherers cost real frame time.** The
  lever is decimation, and the source being a `.blend` means it is a
  modifier rather than a re-import.
- **Anyone wanting gatherers to show their owner's colour again**, which
  is vertex paint on the source and needs no code.
