extends RefCounted
class_name CosmeticDuel

## Cosmetic melee duels — Tier 1 of
## D-20260818-rome-total-war-formations-in-three-tiers, under
## D-20260818-battle-quality-outranks-player-count.
##
## During a melee the render layer pairs each man with an opponent, turns
## him to face it, steps him into contact and strikes at it. Outcomes,
## wire and server are untouched: this is D-006 clause 2 territory
## ("cosmetic offsets are one-way"), the same legal ground
## `cosmetic_offset.gd` and `soldier_motion.gd` already stand on.
##
## ## Why this is all-static and pure
##
## The same structural reason `Formation`, `CosmeticOffset` and
## `AnimationState` are: there is nowhere to put per-soldier state, so
## D-006 clause 1 is enforced by the shape of the code. A man's opponent
## is recomputed every frame from where both squads' men currently
## stand — he keeps his opponent because the answer comes out the same,
## not because anyone remembered it. That is deliberately the same trick
## as `AnimationState.phase_offset`, and it is also the early test of the
## three-tier decision's collapse trigger: if this ever needs a man to
## REMEMBER last tick's opponent to avoid visible re-targeting, Tier 2 is
## not expressible as a pure function and the decision says to stop and
## re-decide, not to add a cache.
##
## ## What keeps the retargeting invisible without memory
##
## Pairing is nearest-opponent over the two squads' derived positions.
## Those positions only move on curve keyframes, casualties and formation
## changes — so the pairing is stable between those events by
## construction, and when it does jump, `SoldierMotion.ease` (which runs
## AFTER `engage`) glides the men to their new opponents instead of
## snapping them.
##
## ## Nothing here is ever read by simulation
##
## One-way (D-006 clause 2). No value produced here reaches
## `composition_hash()`, the wire, or any tick. Two clients may pair the
## same melee differently for a frame near a casualty and that is not a
## desync — the OUTCOME arithmetic never reads any of this.
## `tests/test_cosmetic_duel.gd` scans the sources to keep it that way.

## How far short of his opponent a man stands, in world units. Roughly
## two capsule radii — close enough to read as contact, far enough that
## authored models do not embed in each other when both sides step in.
const CONTACT_GAP := 0.7

## The farthest a man may be drawn from his authoritative slot, in world
## units. Front ranks reach contact inside this; rear ranks lean toward
## the fight and hold their place, which is what a queued-up melee looks
## like. Bounded so the duel can never scatter a formation — the squad's
## true footprint (selection, culling, separation) is still the derived
## one.
const MAX_STEP := 1.1

## Opponents farther than this from a man's slot are not worth stepping
## toward at all — the squad is "fighting" because ONE end of its line is
## in range, and the far end walking MAX_STEP sideways at nothing reads
## as the formation dissolving. Such men still face and strike (a line
## braced toward the enemy), they just hold formation exactly.
const ENGAGE_RANGE := 6.0

## A man who cannot actually REACH contact — even with both sides paying
## half the gap — takes this short lean-in instead of his full step. The
## first preview picture showed why the full step is wrong for him: a
## second-rank man walking MAX_STEP forward arrives inside his own front
## rank, and two squads read as one blob. Rear ranks queue behind the
## fight; they do not pile into it.
const REAR_LEAN := 0.3


## For each attacker transform, the index of the nearest defender
## transform (horizontal distance; first-found wins ties, so the answer
## is deterministic for identical inputs). O(attackers × defenders), paid
## only by squads in a melee — measured by `gen-duel-preview`, quoted
## with its squad sizes.
static func opponents(attackers: Array[Transform3D],
		defenders: Array[Transform3D]) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(attackers.size())
	if defenders.is_empty():
		out.fill(-1)
		return out
	for i in range(attackers.size()):
		var here := attackers[i].origin
		var best := 0
		var best_d := INF
		for j in range(defenders.size()):
			var d := Vector2(defenders[j].origin.x - here.x,
				defenders[j].origin.z - here.z).length_squared()
			if d < best_d:
				best_d = d
				best = j
		out[i] = best
	return out


## Face each man at his opponent and step him toward contact. Returns a
## new array; the authoritative input is never mutated (clause 2's
## one-way rule, structurally).
##
## `terrain_sampler` is optional and, as in `Formation`, must itself be
## pure — a stepped man takes the height of the ground he steps onto.
## Without one his own slot height is kept, which over a step of at most
## MAX_STEP is a smaller error than the sway already applied on top.
static func engage(attackers: Array[Transform3D],
		defenders: Array[Transform3D], paired: PackedInt32Array,
		terrain_sampler := Callable()) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(attackers.size())
	var sample := terrain_sampler.is_valid()
	for i in range(attackers.size()):
		var mine := attackers[i]
		var j := paired[i] if i < paired.size() else -1
		if j < 0 or j >= defenders.size():
			out[i] = mine
			continue
		var target := defenders[j].origin
		var toward := Vector2(target.x - mine.origin.x, target.z - mine.origin.z)
		var gap := toward.length()
		if gap < 0.001:
			out[i] = mine
			continue

		# Face him: formation-local forward is +z (see
		# Formation.soldier_transform), so this basis points the man's
		# chest at his opponent.
		var basis := Basis(Vector3.UP, atan2(toward.x, toward.y))

		var origin := mine.origin
		if gap <= ENGAGE_RANGE:
			# Close HALF the excess gap, moving at most MAX_STEP from the
			# slot. Half, because the other side is running this same
			# function toward THIS man's authoritative slot — each pays
			# half and two mutually paired men meet exactly CONTACT_GAP
			# apart. Closing the full gap would double-count the approach
			# and stand them inside each other. A man already too close
			# steps back — men fight toe to toe, not model-in-model.
			var step := clampf((gap - CONTACT_GAP) / 2.0, -MAX_STEP, MAX_STEP)
			# A man whose half-share cannot reach contact takes REAR_LEAN
			# instead: he is a rear rank queued behind the fight, and his
			# full step would put him inside his own front rank.
			if gap - 2.0 * MAX_STEP > CONTACT_GAP:
				step = REAR_LEAN
			var direction := toward / gap
			origin.x += direction.x * step
			origin.z += direction.y * step
			if sample:
				origin.y = terrain_sampler.call(origin.x, origin.z)
		out[i] = Transform3D(basis, origin)
	return out


## Sway, footfall and a strike at each man's OWN opponent — the dueling
## replacement for `CosmeticOffset.decorate_activity`, which leans a
## whole squad at one squad-level point. Runs after `SoldierMotion.ease`,
## exactly where decorate_activity ran.
static func strike_decorate(eased: Array[Transform3D],
		defenders: Array[Transform3D], paired: PackedInt32Array,
		time: float, speed: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(eased.size())
	for i in range(eased.size()):
		var decorated := CosmeticOffset.decorate(eased[i], i, time, speed)
		var j := paired[i] if i < paired.size() else -1
		if j >= 0 and j < defenders.size():
			decorated.origin += CosmeticOffset.work_swing(i, time,
				defenders[j].origin - eased[i].origin,
				CosmeticOffset.Activity.FIGHTING)
		out[i] = decorated
	return out
