extends RefCounted
class_name AnimationState

## Which clip a soldier plays, and at what phase (D-065).
##
## All-static and pure, in its own file, for the same structural reason
## `Formation`, `CosmeticOffset` and `SoldierMotion` are: there is nowhere to
## put per-soldier state, so D-006 clause 1 is enforced by the shape of the code
## rather than by a comment asking nicely.
##
## ## The rule this file exists to keep
##
## D-006 clause 1 forbids per-soldier integration state — "no velocity, no
## accumulated offset, no history carried across ticks" — and its revisit
## trigger names animation's usual implementation directly. So phase is DERIVED,
## never advanced:
##
##     phase(slot, t) = fract(t * rate + hash(slot))
##
## Every input is something both sides already hold. Nothing is stored, nothing
## is summed, and asking for the phase at time t does not require having asked
## for it at t - 1. In practice the shader does the `fract` from `TIME`; what
## this file computes is the constant part, which is why it can be written into
## MultiMesh custom data once per clip change instead of once per frame.
##
## ## What would break it
##
## A phase counter advanced by delta time. A blend weight carried between
## frames. A footfall that depends on where this soldier was last frame. All
## three are the same defect wearing different clothes, and all three would make
## a soldier's position depend on its own history — which is exactly what lets
## client and server currently agree on 40,000 soldiers without sending any of
## them.
##
## ## Nothing here is ever read by simulation
##
## This is one-way (D-006 clause 2). No value produced here reaches
## `composition_hash()`, the wire, or any tick. Two clients may legitimately
## draw the same squad mid-stride at different phases, and that is not a desync
## — it is the same freedom `CosmeticOffset` already has.

## Clip indices. MUST match CLIP_ORDER in art/lib/clips.py — the shader picks a
## row block by this number, so a disagreement paints the wrong animation with
## no error anywhere. A test asserts the two lists agree.
const CLIP_IDLE := 0
const CLIP_WALK := 1
const CLIP_ATTACK := 2
const CLIP_ROUT := 3

const CLIP_NAMES := ["idle", "walk", "attack", "rout"]

## Metres of ground covered by one full walk cycle (two steps). Sets the
## relationship between move speed and playback rate, which is the difference
## between soldiers walking and soldiers skating.
##
## 1.45 was the shipped guess — and a guess is all it could ever be, because
## the render clock defect (D-20260824-the-client-renders-on-the-servers-
## clock) meant the walk clip never actually played in a live client, so
## nobody had ever SEEN this number. The first session in which it played,
## the owner read the cadence as far too fast for the ground covered;
## raised until footfall matches travel. Judged by eye against the shipped
## roster in play — the only instrument there is for "do the feet grip".
const STRIDE_LENGTH := 2.6

## Cadences for the clips that do not derive their rate from movement.
const IDLE_RATE := 0.28
const ROUT_RATE_SCALE := 1.6
const MIN_WALK_RATE := 0.35


## Which clip a squad's soldiers should play.
##
## Ordered by what a player most needs to see. Routing outranks fighting
## because a broken squad that still swings reads as a squad that is fine —
## and D-019's rout has been invisible on screen since M2, which is criterion 7
## of D-063.
static func clip_for(routing: bool, fighting: bool, moving: bool) -> int:
	if routing:
		return CLIP_ROUT
	if fighting:
		return CLIP_ATTACK
	if moving:
		return CLIP_WALK
	return CLIP_IDLE


## Playback rate in cycles per second.
##
## Walk and rout are tied to actual ground speed so footfalls match travel.
## `MIN_WALK_RATE` keeps a very slow squad from appearing frozen mid-step.
static func rate_for(clip: int, speed: float) -> float:
	match clip:
		CLIP_WALK:
			return maxf(absf(speed) / STRIDE_LENGTH, MIN_WALK_RATE)
		CLIP_ROUT:
			return maxf(absf(speed) / STRIDE_LENGTH, MIN_WALK_RATE) * ROUT_RATE_SCALE
		CLIP_ATTACK:
			return 1.0
		_:
			return IDLE_RATE


## A stable per-soldier phase offset in [0, 1).
##
## Without this every soldier in a squad is on the same foot, which reads as a
## chorus line rather than a body of troops. With it, a rank looks like men
## walking near each other.
##
## Derived from (squad, slot) rather than randomised, so it is stable across
## frames without being stored anywhere — a soldier keeps his offset because it
## is recomputed to the same value, not because anyone remembered it. That is
## the whole trick, and it is why this is D-006-safe.
static func phase_offset(squad_id: int, slot: int) -> float:
	# A cheap integer hash. Quality matters only in that neighbouring slots
	# must not land on neighbouring phases, which is what the mixing achieves.
	var h := int(squad_id) * 73856093 + int(slot) * 19349663
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


## Everything the shader needs for one soldier, packed for MultiMesh custom
## data: (clip, phase offset, rate, spare).
##
## Written on clip CHANGE, not per frame — see `PrimitiveUnit.set_clip_data`.
## The per-frame hot loop stays transforms only, because D-045 measured the
## client frame at 97% CPU in derivation and this is that same loop.
static func custom_data(squad_id: int, slot: int, clip: int, speed: float) -> Color:
	return Color(float(clip), phase_offset(squad_id, slot), rate_for(clip, speed), 0.0)
