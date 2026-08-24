# D-20260824-a-textured-model-keeps-its-texture

**Date:** 2026-08-24 · **Status:** Accepted

From the owner, on seeing an imported model render as brown noise: *"why
has it turned to pixel soup instead of the authored model as is???"*

Amends **D-081**'s pipeline and D-082's VAT contract by adding one
optional channel. Sibling of
`D-20260824-a-supplied-model-becomes-an-authored-source`, which brought
the model in; this one is about what the renderer does with it.

## Decision

**A model that arrives with a texture keeps it.** `UV0` carries the
model's own texture coordinates through the bake, the image is written to
`generated/textures/<archetype>` and recorded in the manifest, `UnitMesh`
binds it, and `unit_anim`/`unit_corpse` sample it.

**It is OFF by default and nothing else changes.** `use_albedo_tex`
defaults `false`; a model with no texture records `"texture": ""` and
takes the vertex-colour path it always has. Every generated model in the
roster is bit-for-bit unaffected.

## Why — and it is not "textures look nicer"

**Vertex colour cannot be mipmapped, and that is the whole finding.**

Before this, `write_glb` wrote `uv0 = (0, 0)` under the comment *"UV0 is
unused at this tier (units are vertex-coloured, not textured)"*. True of
every model this project generated, and it forces any incoming texture to
be crushed onto vertices. At soldier scale that fails badly and for a
reason no amount of care in the sampling can fix:

- one dwarf covers roughly **30 pixels** of a 1400x900 frame;
- the model carries **4,824 triangles**, so each triangle is about
  **0.2 pixels**;
- each pixel therefore takes ONE arbitrary facet's colour, and adjacent
  facets sample unrelated texels of a 2048x2048 atlas.

The result is noise — `docs/playtest/p35-gatherer-vertex-colour-soup.png`.
A texture gets a **mip chain**, so the GPU resolves those thousands of
sub-pixel facets to the right average colour in hardware, for free:
`docs/playtest/p35-gatherer-textured.png`, same model, same frame, same
camera. Cream helmet, orange beard, belted leather coat, boots.

`filter_linear_mipmap` on the sampler and `mipmaps/generate=true` in
`ALBEDO_PARAMS` are therefore the load-bearing lines, not decoration.

**It also makes the triangle budget negotiable again.** While colour lives
on vertices, detail REQUIRES triangles — which is the real reason that
model needed 4,824 of them. With detail in the texture the mesh can be
decimated hard and still read as a dwarf, which is the route to deleting
`PLACEHOLDER_ARCHETYPES` rather than living with it.

## Three faults found on the way, all the same shape

Each was invisible to every count and visible only on the far side of a
boundary. This project's standing rule — *assert the value after the
conversion, not that the conversion ran* — earned its keep three times in
one sitting.

1. **A double-flipped V.** glTF's UV origin is top-left, so "flip V when
   reading a glTF UV" is the reflex; Blender's importer has already
   flipped it and `image.pixels` starts at the bottom row, so flipping
   again double-flips. It does not look like a mirrored texture — on a
   fragmented atlas it deals every body part somebody else's colours.
   Measured: head vs feet `0.316/0.284` (no contrast at all) against
   `0.635/0.237` correct.
2. **A dangling UV reference.** UV maps ARE attributes, so
   `mesh.color_attributes.new()` can reallocate the mesh's attribute
   storage and invalidate a `uv_layer` fetched beforehand. Reading it
   afterwards does not error and does not return zeroes — it returns
   plausible garbage. The tell was reading `COLOR_0` straight back and
   getting values that did not match what the sampler returned for the
   same corner.
3. **A JPEG named `.png`.** `image.file_format = "PNG"; image.save()`
   does NOT re-encode a packed image — it writes the source bytes and
   ignores the format. Godot marked the import `valid=false` and the only
   symptom anywhere was one `Failed loading resource` line in a render
   log, while the model went on drawing with its fallback colours. It now
   writes the packed bytes verbatim with the extension they actually are,
   which is also better than re-encoding: no second lossy pass, no
   colour-space round trip (the D-100 family), and byte-identical
   rebuilds for free.

**And a fourth that is about the harness, not the assets:** the texture
imported into `.godot-container/` while the preview rendered natively off
`.godot/`, so it failed to load with everything on disk correct. `_import`
follows `EDOTMW_RUNTIME` (docker by default) and `gen-model-preview` runs
native — the split CLAUDE.md already documents for `run-client`, meeting a
recipe nobody had pointed it at. Reproduce with
`EDOTMW_RUNTIME=native EDOTMW_FORCE_IMPORT=1`.

## Rejected alternatives

- **Leaving it on vertex colours and tuning the sampling.** Cannot work:
  the failure is sub-pixel facet aliasing, and no choice of texel per
  corner changes that. Three rounds of fixing the sampling were measured
  to change the picture not at all, which is what identified the real
  cause.
- **Decimating the model until vertex colour is adequate.** That is a
  ~94% reduction of a character sculpt, and it throws away the detail the
  owner supplied to solve a problem the texture path solves outright.
  Worth doing AFTER this, for cost, not instead of it.
- **A skinned/PBR render path.** Still rejected, still milestone-sized,
  and now unnecessary for this: albedo is what a stylised roster reads.

## Consequences

- One more sampler on the unit shader, taken only by models that have a
  texture. The atlas tap D-096 measured as "nearly free" at this scale is
  the precedent; **this has not been measured** and joins the
  `bench-render` debt the sibling entry already records.
- `generated/textures/` now holds unit albedo beside the terrain atlas.
- The bake writes UV0 for every model; models without UVs still get
  `(0, 0)`, so their `.glb` is unchanged.

## Revisit trigger

- **A second textured model**, at which point decimation should be
  measured against it — the texture is what makes that cheap.
- **`bench-render` showing the extra tap or the texture memory costs real
  frame time** on the integrated-GPU target.
- Any model wanting more than albedo (normal, roughness), which is the
  PBR path this deliberately does not open.
