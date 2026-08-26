**A gatherer carries an axe and a pickaxe on its back, and draws the one the
job calls for** (`D-20260825-a-gatherer-carries-the-tool-for-the-job`,
2026-08-25). Wood is felled with the axe, stone and gold are cut with the
pickaxe, fruit is picked by hand. Before this a crew worked all four kinds of
node with the same lean-and-swing (D-059) — the unit a player fields most of
was the one unit whose job was invisible.

```
just attach-tools            # the tools become part of the mesh, on two bones
just author-clips gatherers  # chop / mine / forage, drawing the right one
just build-assets            # bake it into the game
```

Both civs get it: art is keyed by ARCHETYPE and never by civ (D-046 criterion
3), so a thrall and a colonus carry the same kit.

Six things to know before touching any of it, and most of them are not about
animation:

- **The tools had to become part of the SOLDIER MESH, and that was not a
  choice.** A tool has to be in the fist through a swing, and where the fist
  is at phase 0.4 of `chop` is a fact that exists only in the VAT (D-082).
  Nothing on the CPU has it — not the simulation, not the renderer, not
  `Formation`, none of which knows anything below squad level. A tool drawn
  from its own MultiMesh could be placed at the soldier and never *in his
  hand*. Merged in, it costs nothing new: same column layout, one draw call
  per squad, same shader, same wire.
- **`CLIP_ORDER` is a NUMBERING now, not a list of what a model has.** Most of
  the roster bakes the base four; the gatherer bakes seven. Which prefix comes
  from `clips_for(archetype)` in `art/lib/clips.py` and rides to the client in
  the manifest's per-model `clips` list, which has been there since M7 and was
  read only by the corpse path. **A clip index must be resolved through
  `UnitMesh.clip_index`** — `unit_vat.gdshaderinc` finds a row at
  `clip * frames_per_clip + local`, which is arithmetic and not a lookup, so
  asking a four-clip militia for clip 4 lands on the first NORMALS row and the
  model comes apart into a cloud with nothing reporting anything.
- **Nothing new is on the wire, and nothing needed to be.** A crew rings its
  node (D-058's replicated shape) and `ClientState.nodes` already holds every
  node's kind, fog-gated by the server and keyed by cell. So the tool follows
  from data the client has — the same shape as D-052's colour. A crew's centre
  cell IS its node's; when that cell is empty the kind comes from the one
  neighbour that has one, because a crew re-targeted to the next tree (D-087)
  sits briefly off-centre and a wood crew flickering to empty hands for a tick
  would be worse than picking one of two adjacent trees.
- **A model's triangle count is a TEXTURE WIDTH.** One VAT column per flattened
  vertex, so 5,461 triangles is 16,383 pixels and 16,384 is the 2D limit every
  targeted GPU shares. Over it the texture is not created at all — the squad
  does not render, on somebody else's machine, long after the build said fine.
  The gatherer is the first model in this project's history to come near it
  (16,152 of 16,384), which is why the supplied tools are decimated from ~4,795
  triangles each to 280, and why `art/build.py` now refuses to write a VAT
  wider than the limit.
- **Every pose constant was measured, not eyeballed.** The probe tracks the
  tool HEAD through the cycle. `chop` travels 0.556 vertically, sweeps **0.571
  ACROSS** the body and tops out at **0.910** on a model 0.795 tall; `mine`
  travels 0.422, sweeps **0.033** — straight down — and strikes at the feet
  twice a cycle. The sweep and the top are the two that carry: one stroke
  crosses the body and the other does not move sideways at all, which is what
  tells a player which crew is which, and `chop` clears the helmet, which is
  what the camera at 59 degrees (`RenderCull.PITCH_RUN`) needs — a stroke that
  stays below the pack is a stroke nobody sees. Three settings were rejected on
  those numbers rather than on looking: a `fold` of 0.30 (the axe tops out at
  0.412, chest height, invisible from above), a `rest` mid-arc (the crew stands
  between strokes with its axes held out at arm's length), and the sagittal
  formulation these replaced, which cannot cross the body at any setting.
- **The whole roster rebuilds byte-identical except the gatherer**, verified
  rather than assumed by rebuilding the tree and reading `git status`. That is
  the property that makes an art change reviewable at all when nineteen of the
  twenty source files are binary.

**A crew FACES the node it is working — and that is `main`'s mechanism, not
this branch's.** The owner reported crews "weirdly standing around doing the
motion", which was the facing: every soldier shares the squad's facing, so the
far half of a crew had its back to the tree. This branch first fixed it in
`Formation` with a per-slot inward turn for the ring shape; the merge with
`D-20260820-men-gather-round-what-they-strike` made that redundant and it was
REMOVED. Main deals a working crew's men to perimeter points and `CosmeticDuel`
turns each to face his own mark, which covers a node's ring and a building's
box with one mechanism. Two ways to decide where a working man looks is exactly
the kind of pair that comes to disagree.

**But the merge would have brought the placeholder motion back, and that is
worth knowing.** A working crew goes through the DUEL pipeline now, and
`CosmeticDuel.strike_decorate` applies `CosmeticOffset`'s lunge and sway at the
FIGHTING rate — 5.5 Hz against a 0.62 Hz chop, nine beats a stroke. Silencing
it in `decorate_activity`, which is what this branch did before the merge, no
longer reaches a gatherer at all. `strike_decorate` takes an amplitude now and
the client passes 0 for a model that animates its own work; zero turns the
whole decoration off rather than shrinking it.

**Both hands are on the haft now, solved rather than posed.****Both hands are on the haft now, solved rather than posed.** The first version
swung both arms along the SAME arc with a small lateral nudge, so the off arm
mimed the stroke empty-handed beside a tool only the leading hand held. The off
hand is now placed by a two-bone IK solve onto a point down the haft — which has
to happen in the SECOND pass, because where the haft is depends on where the
leading arm ended up, and that is only real once the action poses it. Same trap
as the tool placement, two files apart.

Two things worth knowing about it. `mine` does NOT fully reach: swept at 0.11 /
0.15 / 0.19 / 0.23 down the haft the off hand settles 0.072 / 0.063 / 0.058 /
0.059 from its axis, so it plateaus — held overhead, a pick's haft is simply
outside a 0.21 arm reaching across 0.26 of shoulder. The solve clamps, leaving
the arm extended POINTING at the haft, which reads as reaching. And the call
site first tested `bone_name` — a leaked loop variable holding whichever socket
came last — so the off hand worked on `mine` and never on `chop`.

**A swing is an ARC, and the first version could not make one.** Both strokes
were an angle in the sagittal plane plus a lateral offset — a fore-and-aft
swing with the hands out at the sides, which the owner reported as "just waving
the tool by their sides". That formulation cannot cross the body whatever the
numbers. They are arcs now, two directions in (forward, up, side) with the arm
slerped between them, and the two strokes are structurally different rather
than differently tuned: the axe head sweeps **0.571 across** the body and tops
out at **0.910** on a model 0.795 tall (over the helmet, which is what the
59-degree camera needs), the pickaxe sweeps **0.033** and comes straight down.
Two traps in it: the REST pose is a position on that arc, so the loop-continuity
value inherited from the old formulation left the crew idling with arms straight
out in front; and `fold` trades against height — at 0.30 the axe tops out at
0.412, chest height, invisible from above.

**A man's stroke starts when HE arrives at the node, not on a hash.** The first
pass hashed a phase offset per (squad, slot); the owner asked whether it could
key off arrival instead, and it both can and fixes something the hash could
not. `phase = fract(offset + TIME * rate)` runs on the GLOBAL clock, so a crew
that has just settled is already mid-stroke — a man caught with his axe buried
in the tree the instant he stops walking. Anchored on arrival, the first thing
he does is the wind-up. And it is HIS arrival, not the squad's: the curve goes
quiet when the CENTRE reaches the node while the men are still easing into a
ring around it. Measured on a ring of eight approached from one side, **a crew
settles over 0.272 s** — about 17% of a `chop` cycle — and a real match reports
**0.59-0.65 s** for a crew of seven, nearer 40%, because men arriving in play
come off a march from different distances. Once it reported **0.00 s**, for a
crew that re-entered the clip already standing still; that case is why the
per-man rate spread stays. Legal because
`_man_offsets` is already per-soldier RENDER state (D-20260824), which D-006
clause 2 permits as amended by D-20260819: bounded, one-way, outcome-blind.

**The per-man rate spread stays, and 0.272 s is why.** 17% of a cycle breaks
unison but does not hold it broken — without a rate difference the crew keeps
that spacing forever, and one that happened to arrive together stays in step
all match. Arrival decides where a man starts; `AnimationState.man_rate` keeps
them separating. The hash survives only as the fallback for callers with no
per-man speeds (the load-test bots, `model_preview`, `unit_shot`), none of
which has a `SoldierMotion` and none of which is a player watching a crew.

**The hands had to learn to close, and that needed new bones.** The supplied
rig ends at one bone per hand — **no fingers** — and the mitts are modelled
open with four straight splayed fingers, so a tool placed perfectly in the fist
still had a flat hand lying beside it. `attach_tools` grows two joints per hand
(knuckles and mid-finger), placed from the geometry: the knuckle line is the
hand bone's TAIL, where the hand measures widest. Two rather than one, because
a single hinge folds the fingers as a rigid flap and the tips finish outside a
haft 0.03 across instead of round it.

**The haft running along the hand bone is correct** — that is what a real hand
looks like with the fingers straight, and folding them at the knuckles is
exactly what turns it into a grip. What was misplaced was the haft by a
centimetre: it sat on the bone's axis out from the wrist rather than in the
space between the curled fingers and the palm, so the fist closed and the haft
lay across the back of it. `GRIP_IN_HAND` is the measured centre of the hole a
closed fist makes. Fingertip-to-haft distance went **0.0381 nearest / 0.0660
mean to 0.0040 / 0.0298**, against a haft about 0.015 across.

**And the check on it was vacuous the first time** — worth knowing because it
is the oldest trap here. It measured the nearest fingertip to the haft axis,
and with the grip in the fist's hole the haft passes through where the OPEN
fingers already are: an open hand scored 0.0036 against a closed one's 0.0040,
so zeroing the curl left it green. Found only by breaking the feature on
purpose and watching the guard not fire. It measures the fold ANGLE now (175
closed, 0 open, minimum 60), which an unfolded hand cannot pass.

**Five defects on the way, none of them about art, all worth knowing:**

- **The grip must sit on the HANDLE, and finding the handle took four goes** —
  reported by the owner as *the pickaxe doesn't end up in his hand*, and it did
  not: its nearest vertex sat **0.103 from the fist** on a handle 0.011 thick.
  A principal axis is the best-fit line through every vertex, and a pickaxe's
  wide double head drags it off the haft; the axe's head is small and nearly
  symmetric about its own, so the axe was fine. **One of two models happening
  to satisfy an unstated assumption is not evidence for it.** What makes it
  worth remembering is that three successive fixes each moved the number and
  left the defect in place — a thin slab at grip height (0.046, too few
  vertices in a coarse tube), then the lower third (grip fine, but for the
  pickaxe that third was not handle, so the model shipped with its handle out
  of its side). What works is a ball around the BUTT TIP: **a distance from a
  point does not depend on any axis being right.** Fist-to-tool after: axe
  0.033 -> **0.003**, pickaxe 0.103 -> **0.009**, and the pickaxe stops being
  0.580 across a 0.370 handle.
- **The roll was applying its correction backwards, and had been all along.**
  `Matrix.Rotation(a, 4, "Y")` takes phi to `phi - a`, so cancelling phi needs
  `a = +phi`; the code negated it and took phi to `2*phi`. Still *an*
  orientation — right size, right hand, head on the right end, facing a
  direction nobody chose — so nothing failed until a picture showed a pickaxe
  growing out of the dwarf's back.
- **So every step asserts its own result now**, and that is the part to keep:
  `_assert_handle_is_the_long_axis`, `_assert_head_faces_x`,
  `_assert_grip_on_the_handle`. Two of those were wrong first, the same way:
  the grip check used a guessed fraction of the tool's LENGTH and failed the
  axe at 0.022 against 0.020 — **a guessed constant that red-flags a good model
  is worse than no check, because the next person raises it until it passes** —
  and then measured to the nearest vertex anywhere, which penalises a coarse
  tube. It measures across the handle against that tool's own radius now.
- **A pose bone's rotation is relative to its PARENT's pose.** Pointing an
  upper arm at a direction and then pointing the forearm the same way leaves
  the forearm carrying the shoulder's rotation twice — the arm folds across
  the chest instead of extending. `_point` returns the world rotation it
  applied so the child can divide it out. The symptom looked like a bad
  animation and was a coordinate-frame bug.
- **A depsgraph read in the middle of authoring returns the ACTION, not the
  pose you just set.** The tool's placement is derived from the hand's pose
  matrix, and asking for that matrix mid-pass means asking the depsgraph to
  evaluate — by which time the armature has an action, because earlier frames
  have been keyed, so what comes back is that action sampled at whatever frame
  the scene is sitting on. Measured: the hand tracked 0.598, 0.647, 0.516,
  0.349, 0.484, 0.668 up and down the chop cycle — the arc of no arm — and the
  axe faithfully followed it. **The socket machinery was right the whole time
  and was being handed the wrong hand.** Tools are keyed in a second pass now,
  after the body, with the scene scrubbed frame by frame so the action itself
  poses the arm.
- **A cycle sampled at 16 frames and looped must END where it BEGAN.** The
  first stroke recovered to neutral and restarted wound-up: 135 degrees of arm
  in one sixteenth of a second, which reads as a twitch rather than a rhythm.
  `_swing_drive`'s `rest` parameter is the fix and the reason it is not zero.
  Worth knowing because **the shipped `attack` clip has the same shape** and
  has since M7 — deliberately not changed here, since it is a different clip
  on every model in the roster.

**And a fourth, which is the one to remember: the tools rendered BRIGHT RED
in the game and nothing anywhere said so.** `bpy.ops.object.join` fills the
incoming mesh's missing colour attribute with opaque white, and COLOR_0's ALPHA
is the owner-colour mask (D-052) — so alpha 1.0 means "paint this entirely in
the player's colour". Geometry, weighting, atlas, UVs, clips and every printed
count were all correct. `just gen-unit-shot gatherers chop` is what found it,
and that recipe needed a fix of its own first: `unit_shot.gd` has taken a
`--clip=` argument since it was written and the recipe never passed one, so
**every shot it has ever produced was a `walk`** — the one framing of this
model where both tools are on the back. It takes a CLIP now.
`docs/playtest/p37-gatherer-tools-ingame.png` is the after.

**And one about the tooling rather than the code: a hand-made `bpy` venv breaks
every Godot import.** `just bootstrap-art` writes a `.gdignore` into `tools/`
because Godot scans every directory under the project and will otherwise walk
~1 GB of Blender's own bundled textures and import them. Creating the venv by
hand skips that, and the symptom is not a slow import — it is 28 unrelated
tests failing on `Condition "err != OK" is true` with no mention of Blender
anywhere. Use the recipe.

**And `gen-model-preview`'s camera framing is DERIVED now**, because widening
the sheet from four clip columns to seven pushed half of it off the edge —
which is the third time that file has had that exact failure, and the second
was already written down in it as a warning. It measures the grid it is about
to draw instead.

**Not covered, and how to look at it:** whether a chop READS as a chop is not
assertable. `just gen-model-preview` draws every model through the real path
and `docs/playtest/` holds the pictures — the same split D-097's cliffs and
D-108's forests live under. The one thing neither a number nor a still can show
is the CADENCE (`AnimationState.CHOP_RATE` and its siblings), and that is the
owner's playtest.

**`just test-client`'s default duration went 60 -> 90, and that IS this
change.** The verdict gates on `conceal_events > 0`, which needs a bot to
wander out of vision — that happens on the MATCH's clock while the capture
window is fixed wall clock, so anything slowing the client's start eats the
margin. There was none: measured A/B on one host, the pre-tools gatherer
passed twice at `conceal_events=1` with 71-72 state-hash checks, and the
tooled gatherer (double the VAT, seven clips instead of four) failed three
times at 0 with 66. Six ticks of window against a gate clearing by exactly one
event. At 90 it clears with room (8-10 conceal, 101-106 checks). Lengthening
the run rather than weakening the check is the honest direction, and it is
CLAUDE.md's "when the opening changes, every timing tuned against the old one
is stale" applied to an ASSET getting heavier.

**Owed, and pre-existing rather than created here:** `just bench-render` on the
gatherer at scale. `art/build.py`'s own comment already said so — a
4,824-triangle placeholder is 16x every other model in the roster and gatherers
are the most numerous unit a player fields. This change adds 11.6% to that
debt; it did not create it.
