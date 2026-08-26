# D-20260826-the-dwarf-roster-wears-supplied-models

**Date:** 2026-08-26 · **Status:** Accepted

From the owner supplying nineteen `.glb` files — four rigged/unrigged
dwarf bodies, a wooden cannon, a crossbow, axes, shields, a spear, a
banner and sundries — with *"here are all the authored mesh files for the
rest of the dwarf units & weapons"*, plus two composition rules: the hero
squad is one general and a few dwarfs with mixed weapons, and the cannon
is one gun with three tenders wearing the crossbow unit's body.

## Decision

1. **Five supplied models become authored sources** through
   `import_glb_source.py`, exactly as the gatherer did (D-20260824):
   `militia` (the shieldwarden body + hand axe + round shield), `spearmen`
   (the plate knight + spear + kite shield), `archers` (the kettle-helm
   crossbow body + crossbow), `general` (the thane + runed axe + back
   banner) and `cannon` (the gun carriage, rig-less). The model ids keep
   the archetype-flavoured names the pipeline already used; with the
   fantasy pivot (D-20260818/#191) they are worn by the EMBERDEEP roster's
   defs and by nothing else — `model_id` was always a per-def field, so
   per-civ looks are data, and no script learns a civ id (D-046 criterion
   3 untouched).
2. **Fighting kit is merged into the body and skinned 1.0 to an existing
   bone** (`art/attach_kit.py`): weapon to `R_Hand`, shield to
   `L_Forearm`, standard to `Spine02`. No sockets, no clip edits — a
   soldier's kit never stows, so it needs none of the gatherer's two-pass
   machinery, and it follows whatever `author_clips.py` does to the arm.
3. **The converter grew three things the batch demanded:** `--decimate`
   (every body arrives at ~9,600–10,300 triangles against a VAT width
   ceiling of 5,461 for the whole model), `--yaw` applied to the DATA
   (bones + vertices, never the object — see below), and a toe-direction
   assertion so a body that does not face -Y refuses to convert.
4. **An unrigged body borrows the family skeleton**
   (`art/transplant_rig.py`): the supplied bodies that are rigged all
   carry the identical 41-bone Tripo skeleton, so the bare dwarf knight
   was bound to the militia's armature with automatic weights.
5. **`PLACEHOLDER_ARCHETYPES` grows to the six supplied models**, firing
   D-20260824's "any second entry" trigger deliberately: the owner is
   supplying the roster's look for the pivot, and the binding budget for
   these is the VAT width check, which decimation at import satisfies.
   The `bench-render` debt recorded there now covers six models.

## What it cost to learn, in the order it was paid

- **A yaw parked on the OBJECT poisons the clips.** `author_clips.py`
  poses bones in armature space and measures forward from the toes in
  that space; an object-level rotation leaves local forward sideways, so
  every clip would bake marching at 90 degrees to the face. The yaw goes
  into bone rest data and mesh vertices (`Armature.transform` /
  `Mesh.transform`), keeping local == world.
- **`Matrix.Rotation(-90°, X)` maps +Y to -Z.** The first standard was
  planted flag-down under the general's feet — `attach_tools`' roll-sign
  lesson on a different axis, found by a probe printing each joined kit
  range against its bone, not by the render that had looked merely odd.
- **A transplanted skeleton's hand bones end past the mitt.** Bone heat
  dealt the knight's whole mitt to the forearm, `R_Hand` bound nothing,
  and a weapon anchored on the bone floated detached beyond the fist.
  Kit is anchored on the MESH now — the weighted centroid of the bone's
  vertices, or the arm-tip slab when the bone binds none.
- **The butt-ball handle fit refuses a spear and a banner, correctly.**
  A wide blade or a flag drags the fit off the haft exactly as the
  pickaxe's head did (D-20260825); both get the pole normalisation
  (principal axis up, cloth-end measured, no head assertions), the spear
  held mid-shaft.
- **`ensure_import_params`' new-file stub said `importer="texture"`.**
  Every model before this batch had been imported by Godot at least once
  before the params patcher touched its `.import`, so the stub's importer
  line had never been read. The first never-imported `.glb` was stamped
  as a texture, failed to import on every scan, and loaded as a red
  capsule with one error line in a build log. The stub now matches the
  asset kind (`_SCENE_STUB` for `.glb`/`.gltf`).

## Rejected alternatives

- **Finger bones and a curled grip on the fighting bodies** (the
  gatherer's machinery). At 30 pixels a fist that visibly closes is spent
  where the camera cannot see it; the haft crossing the palm reads. The
  machinery exists in `attach_tools` if a playtest says otherwise.
- **One neutral cannon unit shared by every civ.** Superseded by the
  pivot landing in the same change: the gun is the Emberdeep bombard's
  slot-0 model (D-20260826-a-squad-wears-more-than-one-model), and a
  civ-less siege unit would shadow nothing but confuse everything.
- **Re-scaling the transplant skeleton per limb.** Height-matched uniform
  scale plus mesh-anchored kit placement gets the same picture for a
  fraction of the machinery; per-limb fitting is a real retargeting
  layer, which D-20260824 already deferred until the rig family stops
  being uniform.

## Consequences

- `art/source/` gains `militia|spearmen|archers|general|cannon.glb`
  (supplied) and their `.blend` sources; the old generated human militia,
  spearmen and archers survive only in git history. `hand_axe`,
  `round_shield`, `kite_shield`, `spear`, `runed_axe`, `banner` and
  `crossbow` `.glb`s are committed beside them, hashed as sources.
- Unused from the batch, deliberately: the second battle axe (a long
  polearm), the dagger, one duplicate shield pair, the vegetable basket
  and the stylised ELF — the elf is presumably a Thornwood body and
  arrives with no rig, so it waits for its own pass rather than shipping
  as a second T-posing placeholder.
- `just gen-unit-shot` resolves a model through `slot_models`/`model_mix`
  too, and pins its throwaway def to the requested model — a leader model
  was unfindable and unrenderable before.

## Revisit trigger

- The owner supplying bodies for a second civ — at that point
  `attach_kit.py`'s KITS table gains a per-civ dimension and the "one
  skeleton family" assumption of `transplant_rig.py` gets its first real
  test.
- A `bench-render` number showing the six placeholder-density models cost
  real frame time at scale; the lever is deeper decimation, which is one
  `--decimate` argument per model.
