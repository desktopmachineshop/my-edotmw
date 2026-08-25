# D-20260821 · 2026-08-21 · Accepted — the Blender GUI is a window on the generators, not a second place assets come from

**Decision:** `just blender-gui [TARGET]` opens the **real Blender
application** on this project's own generators. `art/gui.py` builds the scene
by calling the same `art/` code `art/build.py` calls, installs an N-panel that
reloads those generators and rebuilds on a button, maps Blender's **timeline
onto the VAT** so the animation can be scrubbed, and bakes only by invoking
`art/build.py`. Five clauses:

1. **The GUI owns no geometry.** `art/gui.py` contains no `box()`, no
   `prism()`, no `Model`/`Part` construction and no vertex literal.
   `tests/test_blender_gui.gd` fails if any appears. This is the whole point
   of the entry: D-081 committed `generated/` as a build product reproducible
   from `art/`, and the manifest hashes art/'s **sources**, so a shape
   authored in a GUI session would be invisible to every existing check while
   making `generated/` unreproducible.
2. **What you look at is what bakes.** The mesh is built from
   `bake.flatten(model)` — the same split-vertex array whose ORDER is the
   contract between the mesh and the VAT column — and the timeline is
   `bake.bake_frames`, so frame *N* in the viewport is row *N* of
   `generated/vat/<archetype>.exr`. Rebuilding either here would be a second
   implementation of a contract free to drift, and the drift shows as a model
   that previews correctly and animates wrong.
3. **Only the viewing transform is a lie.** `geom.py` authors in Y-up to match
   Godot and `bake.py` exports `export_yup=False` deliberately, so the
   authored coordinates lay a soldier flat on Blender's Z-up floor. The
   **object** is rotated; the mesh data is not. The vertices selected in the
   viewport are the numbers that go into the glTF.
4. **The wheel and the application are two programs, and only the wheel is
   this repo's business.** `just bootstrap-art` installs `bpy` from PyPI —
   Blender with the window manager compiled out, no flag opens a window on it
   — and it stays pinned, because it bakes `generated/` and D-081 requires two
   runs to be byte-identical. The **application is an ordinary desktop
   install**: nothing downloads it, nothing pins it, there is no bootstrap
   recipe for it. `blender-path.sh` FINDS one, in the same role
   `instance-id.sh` holds for instance identity, and reports a version
   difference rather than refusing. The GUI opens with the owner's own
   preferences, add-ons and keymap.
5. **Baking goes through `art/build.py`.** The Bake button calls
   `art.build.main()`, which is what applies the triangle budgets, writes the
   manifest and re-imports. Calling `write_glb`/`write_vat` directly would
   skip all three, and the test forbids it.

**Rationale:** the owner asked to see the GUI, and the honest first answer is
that the pipeline never had one to see — `bpy` is a library, not an
application. What the GUI genuinely buys, that headless `bpy` cannot:

- **An angle you chose.** `art/preview.py` renders one fixed three-quarter
  view and `just gen-model-preview` frames the shipping path its own way.
  Neither lets you get under a shield to check whether a spear passes through
  the man holding it. This project has paid three times for defects that were
  invisible to every number and visible in a picture (M7's inside-out `box()`,
  M7's black soldiers, D-097's honeycomb ground) — and in each case the
  instrument that finally caught it was a picture framed *deliberately*.
- **Scrubbing.** D-082's animation is a texture of baked vertex positions.
  Until now the only way to inspect a clip was four sampled stills per clip in
  a contact sheet. The timeline is a row browser over that texture.
- **A loop measured in seconds.** Edit `art/units/__init__.py`, press Rebuild,
  look. No process restart, no `--import`, no engine.

**Rejected alternatives:**

- **Hand-authoring in the GUI and committing `.blend` files** (rejected — this
  is exactly what D-081 rejected, and its reason is unchanged: the project's
  premise, stated in `CLAUDE.md`'s "What this project is", is that plain-text
  scriptable assets keep it editable by Claude Code. Clause 1 is what stops
  this entry becoming that by accident).
- **Round-tripping GUI edits back into the generators** (rejected for now —
  the only honest version writes a `.blend` or a `.glb` that `art/` then reads,
  which is clause 1 with extra steps. If hero assets ever justify it, it needs
  its own decision, and `CLAUDE.md`'s standing rule applies: a forced
  binary-only step is flagged as an exception, never the default path).
- **Porting `world_look.gd`'s rig into the GUI** (rejected — that rig is
  defined in Godot terms and a hand-copy would be a fourth set of the numbers
  D-086 exists to be the single definition of, drifting in a file no Godot
  test can scan. `art/gui.py`'s docstring states what it is *not* the
  authority on instead).
- **Taking the exclusive `gpu` gate slot** (rejected — `gpu` is exclusive
  because two simultaneous render *measurements* on one integrated GPU are
  "two useless measurements". This measures nothing. Holding the slot would
  stop the owner comparing a model against the running game, and would let
  another agent's `bench-render` lock them out of looking at art at all. It
  takes `medium`: gated, because it is ~1.3 GB on a laptop that rarely has
  2.4 GB free, but not exclusive).

**Consequences:**

- There is still one bootstrap (`bootstrap-art`, the wheel). `just doctor`
  prints `blender-path.sh explain`, which names the wheel pin, the installed
  application and the wheel separately, and says how to install Blender when
  there is none.
- **Neither is required to play, test or ship.** `generated/` is committed
  (D-081), so a clone with no Blender at all is a working game. The test file
  needs neither.
- `art/gui.py --check` builds the scene, asserts the timeline moves and exits,
  with no GUI. That is what makes the script testable at all; it needs the
  wheel, so it is not run by `just test-unit`.

**A hazard found while building it, which is not about the GUI:** a
`frame_change_post` handler left registered makes the **bpy wheel hang forever
at interpreter shutdown**. Measured at 4.5.12: the same script exits in 1 s
with no handler and never exits with one, printing "Not freed memory blocks"
and then spinning in Blender's leak detector. Everything had already printed
by then, so the symptom is a script that completes its whole job and refuses
to end — which reads as a slow build, not as a leak. The real application does
not do this; it unregisters handlers on a normal quit. `art/gui.py` therefore
has `detach()`, `--check` calls it, and the test asserts both.

**Observed to fail before being trusted** (the standing rule from D-022's
audit block): `--check`'s "the timeline is live" assertion was perturbed by
detaching the handler before the scrub, and reported
`scrubbing to frame 20 (mid-walk) moved no vertex of militia`. Without that
step it would have been a check that a scene *built*, which is a thing that
passes with the animation entirely dead.

**Also observed, and left alone:** `generated/` is byte-identical between two
runs *on one platform* and is **not** byte-identical across platforms — the
committed Windows VATs and a Linux rebuild of the same sources differ by ~31
bytes of EXR header on every archetype, with the manifest and every triangle
count identical. D-081's determinism requirement is therefore a per-platform
one, and the staleness test cannot see the difference because it hashes
sources rather than outputs. Nothing here changes it and no `generated/` churn
is committed with this entry; it is written down because the next person to
rebuild assets on a different machine will otherwise read it as a real diff.

**Amended 2026-08-21, same day, by the owner:** the first version of this
entry had `just bootstrap-blender-gui` download a pinned Blender into `tools/`
and launch it with `--factory-startup`, and took the `medium` host-gate slot.
All three are removed. The owner's reasoning, which is right: Blender is a
standard desktop tool, the models are rebuilt rarely, and none of that
isolation is worth its cost.

Taken one at a time, because each was wrong for its own reason:

- **The download.** A repo-managed private copy of a desktop application buys
  reproducibility that only the *wheel* actually needs — the wheel is what
  bakes, and it is still pinned. The application only has to open a mesh.
  `blender-path.sh` already resolved an installed Blender ahead of the
  downloaded one, so removing the fetch changed the common path not at all.
- **`--factory-startup`.** Justified as stopping an add-on from making the GUI
  disagree with the bake. But the bake does not run in this session unless the
  Bake button is pressed, and that button shells into `art/build.py`, which
  uses the *wheel*, not the running application. So the flag was protecting
  against a path that does not exist, at the cost of throwing away the owner's
  preferences, add-ons and keymap on every launch — for a tool whose entire
  value is being comfortable to sit in.
- **The host gate.** Every other heavy recipe is admitted against the machine
  budget (D-20260818) because it is agent work competing with other agents.
  This is the owner opening their own modelling application, which they can
  equally launch from the desktop with no queue at all — so the gate protected
  nothing and only put a wait in front of a double-click. Note
  `test_host_budget.gd`'s rule does not fire on it either way: it flags bodies
  that start docker or Godot, and this starts neither.

The rule worth carrying: **isolation has to be paid for by somebody, and the
someone here was the only human who uses the tool.** Clause 1 — the GUI owns
no geometry — is the isolation that actually protects `generated/`, and it is
enforced by a test rather than by a flag.

**Revisit trigger:** the GUI acquiring any ability to change what ships —
a round-trip importer, a `.blend` under `art/`, or a bake path that does not
go through `art/build.py`. Any of those makes clause 1 false and needs this
entry reopened rather than quietly extended.
