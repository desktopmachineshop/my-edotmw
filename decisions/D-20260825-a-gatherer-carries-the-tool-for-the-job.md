# D-20260825-a-gatherer-carries-the-tool-for-the-job

**Date:** 2026-08-25
**Status:** Accepted

## Decision

A gatherer wears an **axe and a pickaxe on its back**, and draws the one the
job calls for:

| node | clip | tool |
|---|---|---|
| wood | `chop` | axe, one big stroke per cycle |
| stone, gold | `mine` | pickaxe, two shorter strokes per cycle |
| food | `forage` | none — stoop, pick, straighten |

The tools are part of the soldier **mesh**, weighted to one bone each, and the
three clips are baked into the same VAT as `idle`/`walk`/`attack`/`rout`.
Nothing reaches the wire, nothing reaches the simulation, and no other model in
the roster changes by a byte.

Three supporting decisions come with it:

1. **`CLIP_ORDER` is a NUMBERING; a model bakes a PREFIX of it.** Most of the
   roster bakes the base four. Only the gatherer bakes seven. Which prefix is
   `art/lib/clips.py`'s `clips_for(archetype)`, and it rides to the client in
   the manifest entry that has carried a per-model `clips` list since M7.
2. **A clip index is resolved per model, on the CPU** — `UnitMesh.clip_index`,
   with a stated fallback per clip (`chop`/`mine` degrade to `attack`, `forage`
   to `idle`).
3. **`art/build.py` refuses a VAT wider than 16,384 pixels.** A model's
   triangle count is a texture width, and this is the first model in the
   project's history to come near the limit.

## Rationale

### The gap

A gatherer crew works four kinds of node and looked identical at all four: the
same lean-and-swing (`CosmeticOffset.work_swing`, D-059) whether it was felling
an oak, cutting a seam or picking fruit. The one unit a player fields most of
was also the one unit whose *job* was invisible.

### Why the tools had to join the mesh

They could not be anything else. A tool has to be in the fist through a swing,
and where the fist is at phase 0.4 of `chop` is a fact that exists **only in the
VAT** (D-082). The CPU does not have it — not the simulation, not the renderer,
not `Formation`, none of which knows anything below squad level. A tool drawn
from its own MultiMesh could be placed at the soldier and never *in his hand*.

Merged into the mesh it costs nothing new: same column layout, same one draw
call per squad, same shader, same wire. The tool is more vertices that the bake
already knows how to move.

### Why a bone per tool, rather than animating the tool

`art/attach_tools.py` gives each tool one bone, weighted 1.0, whose **rest pose
is the tool stowed on the back**. That makes the arrangement free at both ends:

- a clip that does not use the tool keys the socket at identity, and the tool
  rides the pack exactly as a scabbard would;
- a clip that does sets `socket.matrix = hand.matrix @ GRIP`, so the tool is in
  the fist *by construction* rather than by a table of per-frame offsets that
  goes stale the moment a swing is retimed.

The tool is laid out in bone space — grip at the origin, handle along +Y, which
is Blender's own head-to-tail convention — so placing it is one matrix multiply
and the grip offset is a fixed 3.5 cm along the fingers.

### Why the clip index is resolved on the CPU and not in the shader

`shaders/unit_vat.gdshaderinc` finds a row at `clip * frames_per_clip + local`.
That is arithmetic, not a lookup. Asking a four-clip militia for clip 4 is not
an out-of-range error — **row 64 of its VAT is the first NORMALS row**, and the
model would come apart into a cloud of triangles with nothing reporting
anything, anywhere. So the translation happens where "this model has no such
clip" is a question the manifest can answer.

`UnitMesh.death_clip_for` had already established the pattern
(D-20260819-a-casualty-is-visible); this is the same read for a clip that
exists rather than one that does not yet.

### Why the client derives the resource and nothing is sent

A crew rings its node and that shape is replicated (D-058), which is how
`_activity_for` has known a crew is working since D-059. The node's **kind** is
already on the client too: `ClientState.nodes` is fog-gated by the server and
keyed by cell. So the tool follows from data the client already holds — the same
shape as D-052's colour, and for the same reason. The protocol gains nothing.

A crew's centre cell *is* its node's. When that cell holds nothing the answer is
taken from the one neighbour that does: a crew re-targeted to the next tree
(D-087's 8-cell retarget) sits briefly off-centre, and a wood crew flickering to
`forage` for a tick would be worse than the shrug of picking one of two adjacent
trees. The final fallback is `FOOD` — empty hands — because a fogged or
freshly-felled cell is exactly where guessing "axe" would draw a crew swinging
at nothing.

## What was measured, rather than eyeballed

### The poses

Every constant in `author_clips.CHOP`/`MINE` was chosen against a probe that
tracks the tool **head** through the cycle, in the armature's own space. On the
shipped gatherer (0.795 units tall in the file, 1.59 in the game):

| clip | head travels (z) | sweeps across (x) | tops out | strikes |
|---|---|---|---|---|
| `chop` | 0.556 | **0.571** | **0.910** | 0.335 in front, thigh height, once per cycle |
| `mine` | 0.422 | **0.033** | 0.636 | at the feet, twice per cycle |

The two numbers that carry the most are the SWEEP and the TOP. One stroke
crosses the body and the other does not move sideways at all, which is what
tells a player which crew is which; and `chop` tops out **above the helmet**,
which matters because the game camera looks down 59 degrees
(`RenderCull.PITCH_RUN`) and a stroke that stays below the pack is a stroke
nobody sees.

Three things were **rejected on those numbers** rather than on looking:

- a `fold` of 0.30 — the forearm leads so far round the arc that the hand is
  already coming down while the shoulder is still going up, and the axe tops
  out at **0.412**, chest height, invisible from above;
- a `rest` near the middle of the arc, which is where loop continuity alone
  would put it: that is the arm straight out in front, so a crew between
  strokes stands holding its axes at arm's length;
- the whole SAGITTAL formulation these replaced — an angle in the fore-and-aft
  plane plus a lateral offset — which cannot produce a stroke that crosses the
  body at any setting. See "A swing is an ARC" below.

### The atlas

One model gets one albedo image and the shader one sampler
(D-20260824-a-textured-model-keeps-its-texture), so three source textures are
composited into one 4096x2048 atlas with every UV remapped. The result is read
back and compared against its sources — mean drift 0.004 (gatherer), 0.005
(axe), 0.006 (pickaxe) on a 0-1 scale, which is JPEG loss and not a
colour-management shift. D-100's rule, applied to a boundary this build had not
crossed before.

### The cost

- gatherer: **4,824 -> 5,384 triangles** (+11.6%), 14,472 -> 16,152 VAT columns
- VAT: 129 -> 225 rows; the file grows 5.3 MB -> 10.2 MB, the texture 763 KB ->
  1.3 MB
- **every other model in `generated/` is byte-identical**, verified by
  rebuilding the whole tree

`just bench-render` has NOT been re-run for this, and the gatherer already owed
that measurement before this change: `art/build.py`'s own comment says so, since
a 4,824-triangle placeholder is 16x every other model in the roster and
gatherers are the most numerous unit a player fields. This adds 11.6% to a debt
that was already outstanding; it does not create it.

### The grip has to be on the HANDLE, and finding the handle took four goes

Reported by the owner against the first build: *the pickaxe doesn't end up in
his hand*. It did not — the nearest part of it sat **0.103 from the fist**, on
a handle 0.011 thick, so it floated a hand's width away through the whole
stroke.

The cause is one assumption, stated nowhere and false: that a tool's principal
axis runs down its handle. A principal axis is the best-fit line through EVERY
vertex, and a pickaxe's head is a wide double crossbar whose mass pulls that
line off the haft. The axe's head is small and nearly symmetric about its own,
so the axe was fine. **One of two models happening to satisfy an unstated
assumption is not evidence for it.**

What makes this worth a section rather than a line is that **three successive
fixes each moved the number and left the defect in place**, and not one of them
failed anything:

| attempt | how the handle was chosen | result |
|---|---|---|
| 1 | the tool's principal axis, used as the handle | 0.103 from the fist |
| 2 | a thin slab of geometry at grip height, along that axis | 0.046 — a coarse tube has too few vertices in a thin slab for its centroid to mean anything |
| 3 | the lower third, along that axis | grip fine, but for the pickaxe that "third" was not handle, so the fit came back ACROSS the tool: the model shipped with its head along the handle's axis and its handle out of its side |
| 4 | every vertex within a ball of the BUTT TIP | 0.009 |

The fourth works because it stops projecting onto the axis that is itself in
doubt. A ball around the butt contains handle and nothing else — the head is at
the other end — and **a distance from a point does not depend on any axis being
right**. The butt is unambiguous: the extreme vertex on the thin end, and
thin-versus-fat is measured perpendicular to the axis, which survives that axis
being off by a fair angle.

Measured over every frame of the stroke, as the distance from the fist to the
nearest tool vertex: axe **0.033 -> 0.003**, pickaxe **0.103 -> 0.009**. The
pickaxe also stops being the wrong shape: 0.580 across against a 0.370 handle
becomes **0.236 x 0.370 x 0.056**.

### And the roll was applying its correction backwards

Found in the same pass, and it had been there since the first version.
`Matrix.Rotation(a, 4, "Y")` takes a direction at angle phi in the XZ plane to
`phi - a`, so cancelling phi needs `a = +phi`. The code negated it, which takes
phi to **2*phi**.

That is still *an* orientation. The tool was the right size, in the right hand,
with its head on the right end — facing a direction nobody chose. It only
became visible once the handle fit was corrected and the pickaxe's head swung
round to point straight out of the dwarf's back: 0.62 behind a body whose back
is at 0.19.

### So every step now checks its own result

That is the real outcome of this pass, and it is the part worth keeping. Each
measurement is now asserted in the units that measurement is about:

- `_assert_handle_is_the_long_axis` — after alignment the handle runs along Y,
  so Y must be the tool's longest dimension. A hand tool is longer than it is
  wide; attempt 3 was 0.370 along Y and 0.580 across X.
- `_assert_head_faces_x` — the head must end up broadside within 8 degrees.
  Nothing downstream can see a head at the wrong angle.
- `_assert_grip_on_the_handle` — there must be haft beside the fist, within 3
  handle radii, measured **across** the handle over a band of it.

Two of those checks were themselves wrong first, in the same way, and that is
the second lesson:

- the grip check first used a guessed fraction of the tool's LENGTH and failed
  the axe at 0.022 against 0.020 — a correct grip, a hair over an invented
  limit. **A guessed constant that red-flags a good model is worse than no
  check, because the next person raises it until it passes.** It is measured
  against that tool's own handle radius now.
- it then measured the distance to the nearest vertex ANYWHERE, which
  penalises a coarse tube whose nearest ring happens to sit half a band up the
  haft — 0.046 on a placement that was correct. It measures across the handle
  now, which is the question actually being asked.

### A swing is an ARC, and a sagittal angle cannot be one

From the owner's first playtest: *axe hits should come in from above and to the
side slightly diagonally down across the front of the dwarf, pickaxe from above
vertically down. Currently both animations have them just waving the tool by
their sides.*

Both poses were built as an angle in the **sagittal plane** plus a lateral
offset — a fore-and-aft swing with the hands held out to the side. That
formulation cannot produce a stroke that crosses the body, whatever the
numbers, so no amount of tuning was going to fix it. And with only one plane
available, the two clips differed by amplitude and timing alone, which is a
weak difference at thirty pixels.

They are arcs now: two explicit directions in (forward, up, side) with the
upper arm slerped between them, the forearm running the same arc a little
further ahead. That makes the plane of the swing a property anyone can read
off six numbers, and it makes the two strokes structurally different rather
than differently tuned:

| | head travels (z) | sweeps across (x) | tops out |
|---|---|---|---|
| `chop` | 0.556 | **0.571** | 0.910 |
| `mine` | 0.422 | **0.033** | 0.636 |

One crosses the body, the other does not move sideways at all. The model
stands 0.795, so the axe goes over the helmet at the top of the wind-up —
which is what makes a stroke visible from a camera looking down 59 degrees.

**The trap in it was the REST pose.** `drive` now maps onto an arc from
overhead to the ground, so the value the cycle idles at is a position on that
arc — and the loop-continuity value inherited from the old formulation put it
halfway, which is the arm stuck straight out in front. A crew of dwarves
holding their axes at arm's length between strokes. `rest` is per-clip and
near the bottom of the arc now, and `_swing_drive`'s docstring says why it has
two jobs rather than one.

The other trap was `fold`, which trades against height: at 0.30 the forearm
leads so far round the arc that the hand is coming down while the shoulder is
still going up, and the axe tops out at **0.412** — chest height, invisible
from above. Swept to 0.14.

### A man's stroke starts when HE arrives, not on a hash

The first pass at desyncing a crew hashed a phase offset per (squad, slot).
The owner's question was the better one: *rather than forcing the phase offset
can it not be based on when the individual unit arrives at the resource and
starts working?*

It can, and it fixes something the hash could not. `phase = fract(offset +
TIME * rate)` is keyed to the GLOBAL clock, so a crew that has just settled is
already somewhere in the middle of a stroke — a man can be caught with his axe
buried in the tree the instant he stops walking. Anchoring the cycle to the
moment he starts working makes the first thing he does the wind-up.

And it is his ARRIVAL, not the squad's. Those are different moments: the
squad's curve goes quiet when its CENTRE reaches the node, and its men are
still easing into a ring around it afterwards.

Measured twice, and the live number is the larger one. On a headless fixture —
a ring of eight approached from one side — **the crew settles over 0.272 s**
(first at 0.816, last at 1.088), about 17% of a `chop` cycle. In a real match
the client reports **0.59 s and 0.65 s** for a crew of seven, nearer 40% of a
stroke, because a crew arriving at a node in play is not the tidy fixture:
they come off a march, from different distances, into a ring they have to
walk round.

**And once it reported 0.00 s** — a crew that re-entered the clip already
standing still, so every man latched on the same frame. That case is exactly
why the per-man RATE spread stays: arrival alone would have put them in
perfect unison there.

**It is legal because it lives on the render side.** `_man_offsets` has been
per-soldier render state since D-20260824 gave each man his own stride, and
D-006 clause 2 as amended by D-20260819-tier-three-lives-on-the-render-side
permits exactly this: bounded, one-way, outcome-blind. Nothing
simulation-side reads it, two clients may legitimately disagree about where in
his swing a man is, and no outcome depends on the answer.

**The rate spread stays, and 0.272 s is why.** 17% of a cycle is enough to
break unison but not enough to hold it broken: without a per-man rate
difference the crew would keep that spacing forever, and a crew that happened
to arrive together would stay in step for the rest of the match. Arrival
decides where each man starts; `AnimationState.man_rate` keeps them
separating.

The hash offset survives as the fallback for callers with no per-man speeds —
the load-test bots, `model_preview`, `unit_shot`. None of them has a
`SoldierMotion`, and none of them is a player watching a crew.

### The hands had to learn to close

Reported by the owner: *dwarf hands need to actually grip tool handles, not
stay open next to it.* They did not grip, and could not: the supplied rig ends
at `R_Hand` / `L_Hand`, one bone each, **no finger bones at all**. The mitts
are modelled open with four straight splayed fingers, and nothing in the rig
could bend them. A tool placed perfectly in the fist still had a flat open hand
lying beside it.

So the rig grows two joints per hand — knuckles and mid-finger — placed from
the geometry rather than by eye: the knuckle line is the hand bone's TAIL,
which is where the rigger put it and where the hand measures widest (0.137
across, in the band t = 0.08-0.11 on a bone 0.091 long), and the fingers run
on to t = 0.181.

Two joints rather than one, because a single knuckle hinge folds the fingers
as a rigid flap and the tips finish outside a haft 0.03 across instead of round
it. Three or more would be finger-by-finger animation on a soldier thirty
pixels tall.

**The haft runs along the hand bone, and that is right.** At first glance it
looks wrong — the straight fingers point the same way, so they lie along the
haft rather than across it. But that is what a real hand looks like with the
fingers straight, and gripping is precisely what folding them at the knuckles
achieves. After a right-angle fold the fingers cross the haft.

**What was actually misplaced was the haft, by a centimetre.** It sat on the
hand bone's axis, straight out from the wrist — close to the hand's centre
line but not to the space between the curled fingers and the palm. So the fist
closed and the haft lay across the back of it. `GRIP_IN_HAND` is the measured
centre of the hole a closed fist makes — hand-local (0.0299, 0.0756, -0.0138),
the midpoint of the fingertip and knuckle centroids. Fingertip-to-haft-axis
distance went **0.0381 nearest / 0.0660 mean to 0.0040 / 0.0298**, against a
haft about 0.015 across.

### And the check on it was vacuous the first time

Worth recording because it is this project's oldest trap and it caught me
inside one change. The first `_assert_hands_grip` measured the nearest
fingertip to the haft's axis. With the grip moved into the fist's hole, the
haft passes through where the OPEN fingers already are — so an open hand
scored **0.0036** against a closed one's **0.0040**, and zeroing the curl
entirely left the check green.

It was found only by deliberately breaking the feature and watching the guard
not fire, which is the standing rule ("observe every new check fail before
trusting it") earning its keep. The check measures the fold ANGLE now — 175
degrees closed, 0 open, minimum 60 — which an unfolded hand cannot pass by
accident.

### The defect only the picture could show

The first in-engine shot came back with a **bright red axe and a bright red
pickaxe** on a brown dwarf. `bpy.ops.object.join` fills the incoming mesh's
missing colour attribute with opaque white — and COLOR_0's **alpha is the
owner-colour mask** (D-052), so alpha 1.0 means "paint this entirely in the
player's colour".

Everything else was right: the geometry, the weighting, the atlas, the UVs, the
clips, and every count the build printed. Same family as `art/lib/bake.py`'s
note about a MultiMesh overriding COLOR, and D-100's about a colour that
crosses an asset pipeline — a value that is correct on one side of a boundary
and something else on the other. `_clear_owner_mask` zeroes it, because a tool
is wood and steel and belongs to nobody.

`just gen-unit-shot gatherers <clip>` is what found it, and it needed a small
fix of its own: `unit_shot.gd` has accepted a `--clip=` argument since it was
written and the recipe never passed one, so **every shot that recipe has ever
produced was a `walk`** — which for this model is the one framing where both
tools are on the back. The recipe takes a CLIP now.

## Rejected alternatives

- **Drawing the tools from their own MultiMesh.** The reason it cannot work is
  above: the hand's position per frame lives in the VAT and nowhere else.
- **A tool per resource, four models.** Three clips on one model costs 48 VAT
  rows; four models costs four meshes, four textures and four draw calls per
  crew, to say the same thing.
- **Sending the worked resource on the wire.** The client already has it, and
  fog-gated. A new field would be a second source of truth for a fact
  `ClientState.nodes` already holds, which is the D-058/D-065 family waiting to
  happen.
- **Extending `CLIP_ORDER` globally to seven.** Simpler, and it would have baked
  48 frames of frozen `rout` onto all eighteen other models to serve the one
  that swings an axe. Rejected on the VAT rows, not on taste.
- **Keeping the tools at their supplied density.** They arrive at ~4,795
  triangles each — more than the gatherer. Two of them would take the VAT to
  43,000 pixels wide, past every GPU's limit, so the model would not render at
  all. Each is decimated to 280.
- **Hard-coding each tool's orientation.** The axe arrives near-upright and the
  pickaxe leans ~30 degrees off vertical in two axes at once. A magic angle per
  file is wrong the moment somebody supplies a different axe, so the handle
  direction is the mesh's first principal axis and the head is whichever end is
  thicker — measured 0.044 against 0.124 mean perpendicular radius, which is
  not a close call.

## Consequences

- **`generated/` for the gatherer must be rebuilt or the feature is silently
  absent.** This is the declared-and-unread family's exact shape: every rule
  here can be correct while the shipped bake carries four clips, and the only
  symptom is a crew that looks the same at a tree as at a seam — which is what
  it looked like before. `tests/test_gatherer_tools.gd` asks the manifest
  outright rather than asking the code whether it would use them.
- **Both civs' gatherers get this**, because both draw one model. Art is keyed
  by archetype and never by civ (D-046 criterion 3), so a thrall and a colonus
  carry the same kit.
- **`art/attach_tools.py` refuses to run twice.** It edits the `.blend` in
  place, and a second run would attach a second pair of tools. Re-tuning where
  they sit means restoring the source from git first.
- **`author-clips` now refuses a model that bakes a work clip and has no
  socket** — so the middle step of the three cannot silently write a stroke
  onto a model with nothing in its fist.
- **A new resource kind needs a line in `AnimationState.work_clip_for`.** A test
  fails if any `ResourceKind` value resolves to something that is not a work
  clip.
- **`NOT_WORKING` is -1, deliberately.** FOOD is 0, so a caller defaulting the
  argument to zero would put every idle squad in the game into `forage`.

## What is not covered, and how to look at it

Whether a chop *reads* as a chop is not assertable. `just gen-model-preview`
draws every model through the real path (a `UnitDef`, a `PrimitiveUnit`, the
shipping shaders) and `docs/playtest/` holds the pictures — the same split
D-097's cliffs and D-108's forests already live under. The one thing neither a
number nor a still can show is the CADENCE, and that is the owner's playtest.

## Revisit trigger

- **A third tool.** The handle fit assumes a hand tool: a long haft with the
  head at one end and a bare lower third. A shovel or a two-headed implement
  would satisfy that; a hammer whose handle is a third of its length would not,
  and `_assert_grip_on_the_handle` is what says so rather than shipping it
  floating.
- **A second unit gathers.** The fallback path (`chop` -> `attack`) exists and
  is tested, but nothing ships that uses it; a real second gatherer archetype
  should get its own tools rather than degrade.
- **`bench-render` on the gatherer at scale.** If the placeholder's triangle
  debt is ever paid by decimating the dwarf, the 280-triangle tool budget was
  sized against 4,824 and can rise with it.
- **A clip that is not a prefix.** If some model ever wants `forage` without
  `chop`, the prefix rule breaks and the manifest has to carry a row index per
  clip rather than a list. `clips.py::_assert_prefix` fails loudly rather than
  letting that happen quietly.
