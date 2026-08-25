# D-20260821 · 2026-08-21 · Accepted — game assets are files, not a generation pipeline

**Supersedes D-081** for units and buildings. D-081's *pipeline* (Blender via
`bpy`, committed `generated/`, enforced triangle budgets, generated import
settings) survives intact; what changes is what feeds it.

**Decision:** `art/source/<name>.blend` is the source of truth for every unit
and building. It is an ordinary Blender file — you open it in your own Blender,
model, rig, animate and save it exactly as you would for any other game — and
`just build-assets` bakes it into the `.glb` and VAT the client already
consumes. Five clauses:

1. **The bake evaluates the file, not a description of it.**
   `art/lib/blend_source.py` steps the timeline through
   `FRAMES_PER_CLIP × len(CLIP_ORDER)` frames and flattens each through
   Blender's dependency graph. Whatever produced the deformation — an
   armature, shape keys, parented objects, a modifier stack — is the artist's
   business and invisible to the bake. **Nothing in the engine, the shader,
   the wire or the simulation changes**, because D-082's VAT stores final
   vertex positions and has never had an opinion about how they were produced.
2. **Vertex order is the contract, and it is enforced rather than hoped for.**
   Objects are visited in NAME order so adding one cannot renumber the columns
   of the others, and the topology is asserted constant across every frame. A
   generative modifier whose output varies with the pose (Remesh, Decimate on
   a driven ratio, Boolean against a moving object) breaks the mesh/VAT column
   contract, and it breaks it *quietly* — the bake would succeed and the model
   would come apart at one frame in sixty-four.
3. **`.blend` is in the staleness hash.** `SOURCE_SUFFIXES` in `art/build.py`,
   mirrored in `tests/test_art_assets.gd`. This is the clause the whole
   arrangement stands on: `generated/` is committed and nothing at runtime
   reads a `.blend`, so the hash is the only thing between "I edited the
   model" and "the game still draws the old one".
4. **Props and the terrain atlas stay generated**, and that is not a
   transitional state. Eighteen interchangeable ground-cover clumps and an
   eight-biome texture atlas are cases where a script genuinely is the better
   authoring tool — `art/scatter/props.py` fails its own build on an
   inside-out part or one tall enough to hide a soldier, which is a check no
   file can carry. Generation was never wrong; it was wrong *for characters*.
5. **The legacy generators survive as a fallback and as the seeder.**
   `art/seed_source.py` wrote the initial nineteen files, so opening
   `militia.blend` gives the militia that is in the game rather than an empty
   scene, and a new archetype can still be generated and then hand-finished.
   `build.py` prefers an authored source and records which one ran in the
   manifest.

**Rationale:** the owner asked whether assets should be treated as files
rather than a generation pipeline, and observed that this is the industry
norm. **It is** — art is authored in a DCC tool, versioned as files, and
exported to engine formats; procedural generation is normal for environments,
foliage and materials and essentially unheard of for characters.

D-081 had a project-specific counter-argument, and it deserves a straight
answer rather than a defence, because it is the reason this was built the
other way: `CLAUDE.md`'s "Built in Godot specifically because its plain-text
asset formats make the project directly editable by Claude Code — that's a
design constraint, not an afterthought."

That constraint is real and is **not** weakened here, because it was never
about meshes. What it buys is a game whose *rules* are editable: unit stats,
civ configs, terrain parameters, formations, AI profiles — `.tres` and `.gd`,
all untouched by this entry. A soldier's silhouette is the one kind of asset
where the constraint pays nothing: judging whether a shape reads as a man at
twelve pixels is not work that a text diff supports, and
`D-20260821-the-soldiers-are-blocky-in-the-silhouette-not-the-edges` is the
measured evidence — the generated roster hit a ceiling (`Part` has one pivot,
so it cannot express a knee) that no amount of scriptability was going to lift.

The repo had also already conceded the point twice: `art/resources/source/`
has held hand-authored `tree-variants.glb` and `resource-markers.glb` since
M7, ~1.2 MB of binary source, documented in `CLAUDE.md` as "a deliberate
exception to the parametric art/ pipeline". The exception was the right call
and it was the general case wearing a special-case label.

**Verified rather than asserted.** The migration is provably lossless:
baking `militia.blend` back reproduces the generated model to **2 × 10⁻⁷ world
units** on positions, normals and colour across all 64 frames — float32
precision. Every triangle count, vertex count and VAT dimension in
`generated/manifest.json` is **unchanged** by the migration; the only new
field is `source`. And `just gen-model-preview` renders the authored `.glb` +
VAT through the shipping path with `VERDICT: ok` — real owner colours, real
animation, nothing inside out.

**Rejected alternatives:**

- **Keeping the generators as the source with Blender as a viewer** (rejected
  — this was the arrangement built earlier the same day, in
  `D-20260821-the-blender-gui-is-a-window-on-the-generators`. It is coherent
  and it answers the wrong question: it lets you *look* at a model you can
  only change by editing Python, which is the constraint the owner was asking
  to remove. `art/gui.py` and its no-geometry test are deleted rather than
  left dormant.)
- **Git LFS for the `.blend` files** (rejected for now — the nineteen sources
  total ~2 MB, the repo already commits ~1.2 MB of binary `.glb` source and
  ~460 KB of VATs without it, and LFS adds a setup step to a repo that
  promises a fresh clone works from `./bootstrap.ps1`. Revisit if a single
  source passes ~10 MB or the roster reaches D-070's 90–130 models.)
- **Deleting the generators outright** (rejected — clause 5. They cost
  nothing, they seed a new archetype's starting point, and the fallback means
  a clone that has authored nothing still builds.)

**Consequences, including the ones that cost something:**

- **A model is no longer editable by Claude Code in any meaningful way.**
  This is the real price and it should not be glossed: I can bake a `.blend`,
  check it, measure it and render it, but I cannot shape it. Adding an
  archetype now means opening Blender, where before it was a few numbers in
  `art/units/__init__.py`. The seeder softens the second half of that and not
  the first.
- **Model diffs are opaque.** `git diff` on a `.blend` says "binary files
  differ". The manifest's triangle and vertex counts are the reviewable
  surface, and the pictures under `docs/playtest/` are the rest.
- **`.blend` is marked binary in `.gitattributes`**, first on the list of
  things that matter: the dev machine has `core.autocrlf=true` (#118), and a
  CRLF substitution inside a build product is recoverable by rebuilding while
  the same substitution inside a source destroys the original.
- **`just blender-gui <name>` opens the file and nothing else** — no wrapper
  script, no generated scene, no custom panel. Your Blender, your file.
- The triangle budgets, the import-settings generation, the committed
  `generated/`, the byte-identical requirement and the manifest all still
  apply, unchanged, to both sources.

**Amended 2026-08-23 — the sources are Z-UP, and the first version was not.**
Found by installing a real Blender and *looking*, which is the one check this
whole entry could not do on the day it landed.

`geom.py` authors Y-up to match Godot and `bake.py` exports `export_yup=False`,
both unambiguously right while a Python generator wrote every vertex and nobody
opened the result. The first seeded files inherited that convention, so **every
soldier lay on its back in Blender** — measured on militia: 1.68 units "deep"
along Y against 0.37 "tall" along Z. For a file somebody MODELS in that is not
cosmetic: the floor grid is a wall, front and side ortho views are swapped, a
mirror modifier reflects the wrong axis, gravity points sideways, and every
rigging tool Blender has assumes Z-up.

`art/source/*.blend` is Blender-native Z-up now, and the conversion happens at
the bake boundary (`blend_source._to_engine`, the inverse of
`seed_source._to_blender`) — which is what every glTF exporter does, and the
reason `export_yup=False` can stay: by the time `write_glb` sees the arrays
they are already in the engine's space. `docs/playtest/p33-blender-gui-militia.png`
is the picture.

**The interesting half is the bug inside the fix.** A clip's rotations are
named in Y-up terms, so the pose has to be CONJUGATED into the new basis
rather than relabelled — and the basis quaternion was written at -90 degrees
when `_to_blender` is +90. That failure is the nasty kind: **a basis that is
the inverse of the vertex transform still stands the model up correctly in the
viewport**, because the rest pose is carried by the vertices. Only the
ANIMATION comes out rotated — invisible in Blender, wrong in the game. The
round-trip check caught it (0.32 world units against an expected 1e-7), which
is exactly what that check is for, and `tests/test_authored_assets.gd` pins
both the sign and the conjugation now.

Re-verified after the change: equivalence back to **2.1 x 10^-7**, every
triangle/vertex/VAT count in the manifest **unchanged**, and
`just gen-model-preview` still `VERDICT: ok`.

**Revisit trigger:** a single source exceeding ~10 MB or the roster reaching
D-070's 90–130 models, either of which makes the LFS question live again. Also
if the topology-stability assertion in clause 2 starts firing on legitimate
work — that would mean an artist wants a workflow the VAT cannot express, and
the answer is a conversation about the VAT rather than a looser check.
