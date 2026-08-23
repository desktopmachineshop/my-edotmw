**Game assets are FILES now** (D-20260821-game-assets-are-files, 2026-08-21).
`art/source/<name>.blend` is the source of truth for every unit and building —
an ordinary Blender file you open, model, rig, animate and save, which
`just build-assets` bakes into the same `.glb` + VAT the client already
consumes. This supersedes D-081's generated roster; D-081's *pipeline* (bpy,
committed `generated/`, enforced triangle budgets, generated import settings)
is unchanged.

```
just blender-gui              # what is authored
just blender-gui militia      # open it in YOUR Blender
#   ... model, Ctrl-S ...
just build-assets militia     # bake it into the game
```

**Nothing in the engine, shader, wire or simulation changed**, and that is the
fact that made this cheap: D-082's VAT stores final vertex positions and has
never had an opinion about how they were produced. The bake steps the file's
timeline and flattens each frame through the dependency graph, so an armature,
shape keys, parented objects or a modifier stack are all equally invisible to
it.

Six things to know before touching it:

- **Vertex order is the mesh/VAT column contract, and it is enforced.** Objects
  are visited in NAME order, so adding one cannot renumber the columns of the
  others; and the topology is asserted constant across all 64 frames. A
  generative modifier whose output varies with the pose — Remesh, Decimate on a
  driven ratio, Boolean against a moving object — breaks the contract *quietly*:
  the bake succeeds and the model comes apart at one frame in sixty-four.
- **`.blend` is in the staleness hash** (`SOURCE_SUFFIXES` in `art/build.py`,
  mirrored in `tests/test_art_assets.gd`). This is the clause the arrangement
  stands on: `generated/` is committed and nothing at runtime reads a `.blend`,
  so the hash is the only thing between "I edited the model" and "the game
  still draws the old one".
- **Props and the terrain atlas stay GENERATED, permanently.** Eighteen
  interchangeable ground-cover clumps and an eight-biome atlas are cases where
  a script is genuinely the better authoring tool — `art/scatter/props.py`
  fails its own build on an inside-out part or one tall enough to hide a
  soldier, a check no file can carry. Generation was never wrong; it was wrong
  *for characters*.
- **The legacy generators survive as a fallback and as the seeder.**
  `just seed-art-source` wrote the initial nineteen files from them, so opening
  `militia.blend` gives the militia that is in the game rather than an empty
  scene. It refuses to overwrite an existing source — that file is an artist's
  work now. A new archetype can still be generated and then hand-finished.
- **The migration is provably lossless, and was checked rather than asserted.**
  Baking `militia.blend` back reproduces the generated model to **2 x 10^-7
  world units** across all 64 frames — float32 precision. Every triangle count,
  vertex count and VAT dimension in the manifest is unchanged; the only new
  field is `source`, which records which path produced each model.
- **A model is no longer editable by Claude Code**, and that is the real price.
  It can be baked, measured, rendered and checked; it cannot be shaped. Adding
  an archetype means opening Blender where it used to be a few numbers in
  `art/units/__init__.py`. `git diff` on a `.blend` says "binary files differ",
  so the manifest's counts and the pictures in `docs/playtest/` are the
  reviewable surface.

**Blender itself is a normal desktop install this repo does not manage.**
Install it however you normally would and `blender-path.sh` finds it
(`EDOTMW_BLENDER` names one if you keep several); there is no bootstrap recipe
and nothing is downloaded into `tools/`. It opens with YOUR preferences and
add-ons — no `--factory-startup`, no host gate. Both were in the first version
of this work and both came out the same day: a gate cannot protect a binary the
owner can launch from the desktop, and factory startup was guarding a bake that
does not run in that session. **Isolation has to be paid for by somebody, and
here that was the only human who uses the tool.**

Only the `bpy` WHEEL is pinned (`.blender-version`), because it is what bakes
and D-081 requires two runs to be byte-identical. The application's version is
reported, never enforced — a difference is a reason to bake with
`just build-assets`, not a reason to refuse to open a model. `just doctor`
prints all three.

**A hazard found on the way, which is not about assets at all: a
`frame_change_post` handler left registered makes the bpy WHEEL hang forever at
interpreter shutdown.** Measured at 4.5.12 — the same script exits in 1 s
without one and never exits with one, printing "Not freed memory blocks" and
then spinning in the leak detector. Everything has already printed by then, so
the symptom is a script that completes its whole job and refuses to end, which
reads as a slow build rather than a leak. The real application unregisters
handlers on quit and does not do this, so it is a hazard of the headless path
— and therefore of anything that ever scripts `bpy`.

**And one thing about `generated/` that was true before this and is now written
down: it is byte-identical between two runs on ONE platform and not across
platforms.** The committed VATs are Windows-built; a Linux rebuild of the same
sources differs by ~31 bytes of EXR header on every archetype, with every
`.glb`, every triangle count and every VAT dimension identical. D-081's
determinism requirement is therefore per-platform, and the staleness test
cannot see the difference because it hashes sources rather than outputs.
Rebuild assets on one machine and say which.

---

**The soldiers are blocky in the SILHOUETTE, not the edges, and smoothing them
buys nothing** (D-20260821-the-soldiers-are-blocky-in-the-silhouette-not-the-edges).
From the owner asking whether the project can have proper game assets rather
than blocky units made from primitives. Nothing shipped changed; this is a
measurement and a proposal.

Three pictures, all in `docs/playtest/`:

- `p32-roster-as-shipped.png` — what ships. A leg is ONE box hip to floor, an
  arm ONE box shoulder to hand, a head a cube. In `walk` and `rout` the leg
  swings as a rigid plank and reads as a log lying beside the man.
- `p32-bevel-buys-nothing.png` — every rigid part bevelled. **132 → 756 tris
  at one segment (5.7x), 1,716 at two (13x), 3,132 at three (23.7x)** on
  militia. **The four columns are not distinguishable.** Correct mechanism,
  invisible result — the "shipped numbers do nothing" family applied to
  geometry.
- `p32-articulation-vs-shipped.png` — thigh + shin, upper arm + forearm,
  pelvis, chest with pauldrons, boots, a tapered head. **288 tris against the
  300 budget** (shipped militia: 132), with knee and elbow bend *derived* from
  the hip and shoulder swing the clips already carry, so `clips.py` gains no
  keyframes.

The conclusions worth carrying, none of which are about art:

- **The ceiling is not the triangle budget and not the runtime.** D-082's VAT
  stores final vertex positions and has no opinion about how they were
  produced — `geom.py`'s header says so while arguing the other way. Read
  forwards, it means the client can already display arbitrarily articulated,
  skinned, subdivided animation at the cost it pays now. **Nothing in the
  engine, shader, wire or simulation has to change to fix how these look.**
- **The ceiling is `Part`.** One pivot, one group, so a shin cannot both
  follow the hip and bend at the knee. Articulation needs a parent chain, and
  that is confined to `geom.py` and `clips.py`.
- **Beyond that it is LOD, which does not exist.** `MODEL_PARAMS` disables
  Godot's LOD generation, so one mesh serves every distance and the single
  budget must cover D-018's 40,000-visible worst case. Until a generated LOD
  chain exists, 300 is the right number and "proper assets" means better
  shapes at 300, not more triangles.

**Nothing is wired up.** If the direction is wanted the decision entry lists
the three steps in order, the first of which (a parent chain on `Part`) is
small and touches no shipped output.
