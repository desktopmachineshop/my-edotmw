**There is a Blender GUI now, and there was not one for two milestones
because `bpy` is a library** (D-20260821-the-blender-gui-is-a-window-on-the-generators,
2026-08-21). `just bootstrap-art` installs Blender's Python module with the
window manager compiled out — no flag opens a window on it, which is why
D-081's pipeline is described as "headless as a library" and why nobody had
ever *looked* at these models from an angle they chose.

`just blender-gui [TARGET]` opens the **real Blender application** on this
project's own generators — **your own local install**, with your preferences
and add-ons. This repo does not download, pin or manage it: install Blender the
way you install anything else and `blender-path.sh` finds it
(`EDOTMW_BLENDER` names one if you keep several). It is THE definition of where
Blender is, in the same role `instance-id.sh` holds for instance identity, and
`just doctor` prints the wheel pin, the installed application and the wheel
separately because the two programs are easy to confuse.

**Only the WHEEL is pinned**, because it bakes `generated/` and D-081 requires
two runs to be byte-identical. The application's version is reported, not
enforced — a difference is a reason to bake with `just build-assets`, not a
reason to refuse to open a model.

What it buys that headless `bpy` cannot: an angle you chose, a **scrubbable**
animation, and a change-look-change loop measured in seconds (edit
`art/units/`, press Rebuild in the N-panel, look — no restart, no `--import`,
no engine).

Four things to know before touching it:

- **The GUI owns no geometry, and a test enforces that.** `art/gui.py` has no
  `box()`, no `prism()`, no `Model`/`Part` construction, and never binds
  `art.lib.geom`; it bakes only by calling `art/build.py`.
  `tests/test_blender_gui.gd` fails if any of that changes. Without the rule
  `generated/` gets a second source of truth that the manifest — which hashes
  art/'s **sources** — structurally cannot see.
- **The timeline IS the VAT.** The mesh comes from `bake.flatten` and the
  frames from `bake.bake_frames`, so viewport frame *N* is row *N* of
  `generated/vat/<archetype>.exr`. Anything that rebuilt either here would be
  a second implementation of the mesh/VAT column contract, free to drift, and
  the drift shows as a model that previews right and animates wrong.
- **Only the viewing transform is a lie.** `geom.py` authors Y-up to match
  Godot, so the authored coordinates lay a soldier flat on Blender's Z-up
  floor. The OBJECT is rotated; the mesh data is not.
- **It is not the authority on appearance.** No VAT sampling, no
  `world_look.gd` rig, no tonemap. `just gen-model-preview` and
  `just test-client` still answer "is the picture right"; this answers "is the
  SHAPE right", which nothing else did well.
- **It is not host-gated and does not start from factory settings**, unlike
  every other heavy recipe. Both were in the first version and both came out
  the same day: a gate cannot protect a binary the owner can launch from the
  desktop, and `--factory-startup` was guarding the bake — which does not run
  in this session, and uses the wheel when it does. See the decision entry's
  amendment; the rule it leaves behind is that **isolation has to be paid for
  by somebody, and here that was the only human who uses the tool.**

**A hazard found building it, which is not about the GUI: a
`frame_change_post` handler left registered makes the bpy WHEEL hang forever
at interpreter shutdown.** Measured at 4.5.12 — the same script exits in 1 s
without one and never exits with one, printing "Not freed memory blocks" and
then spinning in the leak detector. Everything has already printed by then, so
the symptom is a script that completes its whole job and refuses to end, which
reads as a slow build rather than a leak. `art/gui.py` has `detach()` and
`--check` calls it. The real application unregisters handlers on quit and does
not do this, so it is a hazard of the headless path — and therefore of
anything that ever tests this file.

**Two things about `generated/` that were true before this and are now written
down:**

- **It is byte-identical between two runs on ONE platform and not across
  platforms.** The committed VATs are Windows-built; a Linux rebuild of the
  same sources differs by ~31 bytes of EXR header on every archetype, with
  every `.glb`, every triangle count and every VAT dimension identical.
  D-081's determinism requirement is therefore per-platform, and the staleness
  test cannot see the difference because it hashes sources rather than
  outputs. Rebuild assets on one machine and say which.
- **`art/build.py` now excludes non-generators from the staleness hash**
  (`NOT_A_GENERATOR`, currently just `gui.py`, mirrored in
  `tests/test_art_assets.gd`). Hashing a viewer would mark `generated/` stale
  over an edit to a panel label and demand a rebuild producing identical
  output — and a staleness signal that cries wolf stops being read. What makes
  the exclusion safe rather than convenient is the no-geometry test above.
  **Do not add a generator to that list to avoid a rebuild.**

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
