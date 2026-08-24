# D-20260824-a-supplied-rig-is-animated-against-its-own-bones

**Date:** 2026-08-24 · **Status:** Accepted

From the owner, after the imported dwarf shipped textured but T-posed:
*"time to add in the walking animation. the file should have been uploaded
rigged already."* It was — 41 bones, a full humanoid skeleton, the mesh
skinned to it, and **zero actions**.

Third of the day's trio, after
`D-20260824-a-supplied-model-becomes-an-authored-source` (getting it in)
and `D-20260824-a-textured-model-keeps-its-texture` (making it look
right). This one makes it MOVE.

## Decision

**A supplied rig gets its clips authored against its own bones**
(`art/author_clips.py`, `just author-clips <name>`), matched by NAME, with
every rotation named in WORLD axes and converted into each bone's basis.
The converter **keeps the armature** rather than flattening it away.

`art/clips.py` stays exactly as it is. It animates the generated `Part`
hierarchy and cannot drive an arbitrary armature; teaching it to would
mean one function serving two rigs it cannot both be right about.

Like `import_glb_source.py` and `seed_source.py`, this is a MIGRATION —
it edits the `.blend`, and `build-assets` bakes whatever the `.blend`
says. It is re-runnable and clears the previous animation first, so
tuning a stride is edit-and-rerun.

## Why it works at all, and why that is D-082's doing

Nothing in the engine, the shader, the wire or the simulation was touched.
`blend_source.bake` steps the timeline and flattens through the DEPENDENCY
GRAPH, so bones deform the mesh and the result lands in the VAT with
nothing else told about it — the property D-20260821 already wrote down
and this is the first thing to actually spend.

The converter therefore sets scale and placement on the ARMATURE OBJECT
and leaves them UNAPPLIED. `blend_source` bakes `matrix_world`, so an
object transform is already part of what it reads, while mutating vertex
coordinates — which is what the converter did while it was discarding the
rig — would slide a skinned mesh out from under the bones that drive it.

## Two things that must be MEASURED, not assumed

- **Which way the model faces**, taken from the toe bones. A humanoid in a
  T-pose is symmetric in Y, its spine is vertical and its arms lie along
  X, so nothing else says which way is forward. Guessing makes the cycle
  moonwalk, which reads as a broken cycle rather than a flipped one.
- **A bone's rotation axis.** Local axes depend on the roll an exporter
  chose. "Local X swings the limb" is true of many rigs and false of
  enough that a walk ends up flapping sideways; every rotation here names
  a world axis and `_swing` carries it into the bone's rest basis.

Twist bones are deliberately not driven. They exist to spread a limb's
roll along its length for smooth skinning; rotating them as if they were
the limb corkscrews it.

## The finding worth carrying: animate the SILHOUETTE, not the joint

The first pass used film-plausible angles and was reported from play as
*"arms are down but there is no walking when the units move"*. The arms
being down proved the base pose had baked and the VAT was being read, so
the fault was narrower than "animation is broken".

It was not the clip and not the bake, and both were checked before
anything was tuned: the VAT carried real walk motion (rows 16-31 at
0.13-0.33 against idle's 0.02), and `ClientState.squad_speed` returns
~3.4 off the curve against `client.gd`'s 0.15 threshold, so
`AnimationState.clip_for` had been returning `walk` all along.

What located it was measuring against `militia`, which does read:

| | mean peak displacement | share of vertices moving >0.05 |
|---|---|---|
| militia | 0.108 | 52% |
| dwarf, first pass | 0.064 | **25%** |
| dwarf, shipped | 0.126 | **93%** |

**Only a quarter of the model was moving.** A militia is legs and arms
with a token torso, so a leg swing animates most of its silhouette. This
model is mostly apron, backpack, beard and helmet — and the apron covers
exactly the thighs the motion was in. Three quarters of a shape standing
perfectly still reads as NOT WALKING at thirty pixels.

So the angles go past life-like (stride 24 -> 33 degrees, knee 42 -> 54,
arm 17 -> 34) and, the half that actually mattered, the TRUNK is driven:
waist and chest counter-rotation, a torso pitch, a head counter-rotation
so the head keeps looking where it is going.

> **At soldier scale, what matters is the FRACTION OF THE SILHOUETTE in
> motion, not the realism of any one joint.**

That sentence is at the constants in `author_clips.py`, because it is the
thing a future tuner will otherwise re-derive from a turntable — where
every one of the first-pass angles looked correct.

## And then it STILL read as not walking, for a third reason

Reported again from play, with a video: *"i saw them walk a tiny bit at
one point but not properly."* The video is what settled it, and none of
the three causes was the animation.

**The game camera looks down 59 degrees** (`RenderCull.PITCH_RUN`), and
every judgement above had been made on `gen-unit-shot`, which sat at -6
degrees — roughly eye level. At eye level a leg swing is the most obvious
thing on screen. From overhead it is foreshortened to almost nothing.

Three things hide a walk from that angle, and they compound:

1. **Foreshortening.** Vertical motion is edge-on; the bob is nearly free
   of visual effect. Leg swing survives only as its horizontal component.
2. **This model's apron** covers the thighs — the part that swings most.
3. **The selection disc.** A ground decal under each soldier projects UP
   over the unit's shins in screen space at this pitch. A selected squad
   — which is exactly the squad a player is watching — has its legs
   behind an opaque purple ellipse.

Measured to rule the alternatives out first: the owner-colour mask in the
VAT is `0.0` on every vertex (so the purple is not a team tint on the
model), and at 32 pixels the dwarf changed 63% of its pixels between two
moments against militia's 57% — the animation was never the weaker one.

**So the motion moved to where it can be seen.** `TRUNK_YAW` (22 degrees
of shoulder twist), `PELVIS_YAW` (10, counter) and `SWAY` (a lateral
shift) drive the helmet and backpack — the majority of the silhouette
from above — while the leg swing that a turntable rewards stays as it is.

> **Animate for the camera the game uses.** A cycle tuned at eye level
> spends its whole budget on the one part of the model that camera cannot
> see.

`gen-unit-shot` frames the game's angle by default now, with `--front`
for judging the MODEL, which is what the old view was always good for.
This is the fourth time this project has paid for an instrument aimed
somewhere other than where the question is — after `test-client` pointing
at a spawn (cliffs), `gen-model-preview` framing the whole roster
(forests), and the fog edge.

## Rejected alternatives

- **Teaching `clips.py` to drive arbitrary armatures.** One function
  serving the `Part` hierarchy and a supplied skeleton would be right
  about neither, and D-082's VAT does not care which produced the frames.
- **Retargeting a stock animation library onto the rig.** More faithful
  and needs a bone-mapping layer, a source of clips, and a licence
  question. Worth revisiting when the roster has several rigged models;
  overkill for one.
- **Tuning the amplitude by eye.** Tried first and it is how the first
  pass shipped: on a 1000px turntable the film-plausible angles look
  RIGHT. The comparison against a model known to read is what made it a
  measurement instead of an opinion.
- **Inverse kinematics for foot planting.** The feet slide slightly under
  the body bob. At thirty pixels it is invisible, and IK is a rig feature
  this bake would have to evaluate per frame for no gain.

## Consequences

- `gen-unit-shot` takes `--clip`, because a walk cycle that never ran
  looks exactly like one that did if the shot is always the rest pose.
- Idle, attack and rout are authored too — the T-pose was in every clip,
  not just the walk, and a model that stands in a T-pose while idle is
  the same defect wearing a different name.
- The bob lifts the feet slightly off the floor at the top of its arc.
  Accepted, and named here so it is a known trade rather than a bug
  somebody rediscovers.

## Revisit trigger

- **A second rigged model arrives**, at which point the bone-name map in
  `ROLES` is either general enough or it is not, and a retargeting layer
  becomes worth its cost.
- **A playtest reports the walk as over-animated** — bobbing or wobbling
  rather than walking. The levers are `BOB`, `LEAN` and `COUNTER`, and
  93% of vertices in motion is deliberately past militia's 52%.
- **The stride reading as skating or marching** against the crew's real
  move speed, which is `STRIDE` against `AnimationState.STRIDE_LENGTH`.
