extends RefCounted
class_name SoldierMotion

## Client-only easing of soldiers toward their authoritative slots
## (D-006 clause 2, D-059).
##
## ## What this fixes
##
## A soldier's position is a pure function of the squad's curve and its
## formation (clause 1), so when a squad turns, every slot rotates in the
## same instant and the whole block SNAPS round. Nothing is wrong with the
## simulation — that is exactly the authoritative answer — but no army has
## ever moved like that.
##
## ## Why this is allowed, and precisely where the line is
##
## D-006 clause 2 permits client-side visual offsets that are never read
## back by simulation, and `cosmetic_offset.gd`'s own header names this
## case: "the authoritative slot snaps, and the render layer is free to
## ease toward it."
##
## So this holds per-soldier state — which clause 1 forbids in the
## SIMULATION and clause 2 permits on the render path. The distinction is
## not a technicality:
##
##   * The authoritative transform is unchanged. Selection, footprints,
##     combat, vision and the composition hash all read the derived value,
##     never this one.
##   * It is CLIENT-ONLY. The server does not run it, two clients may
##     disagree about a soldier's eased position, and nothing anywhere
##     notices.
##   * It is one-way. Nothing reads back out of here.
##
## Since D-006's 2026-08-19 amendment
## (D-20260819-tier-three-lives-on-the-render-side) this file is also
## where Tier 3 lives: survivors WALK into restamped slots instead of
## teleport-shuffling, and drawn men JOSTLE apart instead of
## interpenetrating. Both are per-soldier integration state — now
## explicitly legal here under the amendment's three conditions, each of
## which is a test: one-way (nothing simulation-side reads this file),
## bounded (MAX_RENDER_DRIFT), outcome-blind (no outcome consumes a
## rendered position).
##
## Kept in its own file rather than added to `CosmeticOffset` because that
## class is deliberately pure and static — it has nowhere to put state,
## which is what makes its own boundary structural. Mixing state into it
## would quietly remove that property.

## How fast a soldier closes the gap to his slot, as a rate constant.
## Higher is snappier. Framerate-independent via the exponential below, so
## a slow machine does not get slower-moving troops.
const EASE_RATE := 7.0

## Past this far from his slot a soldier SNAPS rather than easing.
##
## Without it, a squad that was just revealed, teleported by a seam
## crossing, or restamped by heavy casualties would have its soldiers
## visibly fly across the map to their new places. The seam case is the
## one that matters: a wrapped squad legitimately jumps a whole map width
## in one frame (D-035), and easing that would be a stream of soldiers
## crossing the entire world.
const SNAP_DISTANCE := 6.0

## The amendment's bound (D-006, 2026-08-19): a drawn man never strays
## farther than this from his authoritative slot, so selection, culling
## and every screen-space read built on authoritative data stays valid.
## Raised 1.5 -> 3.5 with the pursuit speed cap in ease(): a man now
## WALKS to a slot that swept away from him (a direction change rotates
## the whole lattice about the squad centre), and a 1.5 bound yanked him
## along the arc before his own feet could cover it — which is exactly
## the "movement feels driven by squad centre, not individual flow" the
## owner reported. Still bounded, one-way and outcome-blind;
## Engagement.MAX_STEP (1.1) still fits inside it, which the tier-three
## test continues to assert.
const MAX_RENDER_DRIFT := 3.5

## Mean target displacement, in ONE frame, past which the whole squad is
## re-dealt to its new slots rather than each man chasing his old label.
## Comfortably above anything continuous motion produces per frame
## (a sprinting squad moves ~0.1/frame) and far below a facing flip.
const REDEAL_DISTANCE := 1.0

## Two drawn men of one squad closer than this push apart — the melee
## scrum breathes instead of interpenetrating.
const JOSTLE_RADIUS := 0.45

# squad id -> PackedVector3Array of eased render positions, parallel to
# the transforms handed in. Client-side render state, nothing more.
var _eased := {}


## Ease `transforms` toward their authoritative values and return the
## render-ready set. The input is not mutated.
##
## `alive` may shrink between calls (casualties) or grow (a reveal), so
## the stored array is resized rather than assumed — a formation restamp
## after losses re-slots everyone, and the eased positions simply follow.
## `max_step_speed` caps how fast a drawn man may chase his slot, in
## world units per second — a man is not dragged by the lattice, he
## WALKS after it. 0.0 means uncapped (the legacy behaviour). The cap
## only ever binds on transients: at a steady march the slot moves at
## squad speed and the pursuit keeps up with slack to spare; on a
## direction change the lattice rotates faster than anyone can walk,
## and the cap is what turns "swept sideways in an arc" into "each man
## cuts the corner at his own pace".
func ease(squad_id, transforms: Array[Transform3D], delta: float,
		max_step_speed: float = 0.0) -> Array[Transform3D]:
	if transforms.is_empty():
		_eased.erase(squad_id)
		return transforms

	var stored: PackedVector3Array = _eased.get(squad_id, PackedVector3Array())
	var count := transforms.size()
	if stored.size() > count and count > 0:
		# Tier 3 (D-006 as amended): a casualty restamp no longer
		# teleport-shuffles the line. Survivors are DEALT to the new
		# slots by nearest-match and walk in — including into the slots
		# the dead vacated, which is the behaviour the original revisit
		# trigger named first.
		var deal := assign(stored, transforms)
		var walked := PackedVector3Array()
		walked.resize(count)
		for i in range(count):
			walked[i] = stored[deal[i]]
		stored = walked
	elif stored.size() != count:
		# First sight of this squad, or a reveal grew it. Start from
		# the authoritative positions so nobody eases in from the origin.
		stored = PackedVector3Array()
		stored.resize(count)
		for i in range(count):
			stored[i] = transforms[i].origin
	elif count > 0:
		# A formation-wide coherent jump at the SAME size is a restamp in
		# all but name, and gets the same deal. The measured case: a squad
		# ordered to REVERSE flips its derived facing 180 degrees in one
		# frame, rotating every slot about the centre — the flank man's
		# target moves twice his distance from it (5.1 units on a 12-man
		# line, past MAX_RENDER_DRIFT's clamp; a 36-man line clears
		# SNAP_DISTANCE outright and teleports, which is what was reported
		# from play). Slots are anonymous (D-024), so nothing requires the
		# man who held slot i to chase it across the formation: deal the
		# drawn men to the NEAREST new slots and a mirrored formation is
		# taken over mostly in place — the rear rank simply becomes the
		# front rank, which is what turning a block around means.
		var total := 0.0
		for i in range(count):
			total += (transforms[i].origin - stored[i]).length()
		if total / float(count) > REDEAL_DISTANCE:
			var deal := assign(stored, transforms)
			var dealt := PackedVector3Array()
			dealt.resize(count)
			for i in range(count):
				dealt[i] = stored[deal[i]]
			stored = dealt

	# Exponential smoothing, so the rate is independent of framerate: at
	# any dt the soldier covers the same FRACTION of the remaining gap per
	# unit time. A plain lerp(a, b, k * dt) is not, and would make troops
	# visibly slower on a slow machine.
	var blend := 1.0 - exp(-EASE_RATE * maxf(delta, 0.0))

	var max_step := max_step_speed * maxf(delta, 0.0)
	for i in range(count):
		var target: Vector3 = transforms[i].origin
		var current: Vector3 = stored[i]
		# The hard snap serves only the UNCAPPED path. Under a speed cap,
		# walking the whole way is the point: geometry guarantees a
		# formation-wide rotation hands somebody a 6-8 unit leg (no
		# assignment can beat it — the man at one end of a turning line
		# must reach the other axis), and a snap on exactly those men is
		# the "driven by the squad centre" jump the cap exists to remove.
		# Reveals never reach here at all: conceal calls forget(), so a
		# revealed squad starts drawn ON its slots — the truthful pop-in
		# (D-025) does not depend on this branch.
		if max_step <= 0.0 and current.distance_to(target) > SNAP_DISTANCE:
			stored[i] = target
			continue
		var eased_point := current.lerp(target, blend)
		if max_step > 0.0:
			var step := eased_point - current
			if step.length() > max_step:
				eased_point = current + step.normalized() * max_step
		stored[i] = eased_point

	# Tier 3 (D-006 as amended): the scrum breathes. Fed BACK into the
	# stored positions — genuine per-soldier integration, which is
	# exactly what the amendment legalises here and nowhere else.
	stored = jostle(stored, transforms,
		max_step if max_step > 0.0 else 1e9)
	_eased[squad_id] = stored

	var out: Array[Transform3D] = []
	out.resize(count)
	for i in range(count):
		# Basis is taken from the authoritative transform unchanged: the
		# squad's facing is already smooth because it comes from the
		# curve's own direction, and easing it as well would make troops
		# lag their own feet.
		out[i] = Transform3D(transforms[i].basis, stored[i])
	return out


## Deal survivors to the new slots by nearest-match: result[i] is the
## index into `old` whose man walks to slot i, each used at most once,
## the leftovers being the dead. Greedy in slot order — deterministic,
## O(n^2) only on the casualty event itself, and PURE, so the interesting
## half of the walk-in is testable headless.
static func assign(old: PackedVector3Array,
		targets: Array[Transform3D]) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(targets.size())
	var used := {}
	for i in range(targets.size()):
		var slot: Vector3 = targets[i].origin
		var best := -1
		var best_d := INF
		for j in range(old.size()):
			if used.has(j):
				continue
			var d := slot.distance_squared_to(old[j])
			if d < best_d:
				best_d = d
				best = j
		if best < 0:
			best = i % maxi(old.size(), 1)
		used[best] = true
		out[i] = best

	# 2-opt improvement over the greedy deal. Greedy in slot order leaves
	# its LAST slots whatever men remain, and on a formation-wide rotation
	# those leftovers can be far enough away to clear SNAP_DISTANCE — at
	# which point the man teleports and no downstream speed cap can save
	# him (measured: a 90-degree turn of a 24-man line, visible jump
	# 2.9 units in one frame, identical with the pursuit capped and not,
	# which is what said the fault was HERE). Swapping any pair whose
	# exchange shortens their combined legs until no swap helps removes
	# exactly those pathological legs; a few passes over n<=40 men on a
	# deal event costs nothing a frame notices.
	for _pass in range(4):
		var improved := false
		for i in range(targets.size()):
			for j in range(i + 1, targets.size()):
				var a: Vector3 = targets[i].origin
				var b: Vector3 = targets[j].origin
				var keep := a.distance_to(old[out[i]]) + b.distance_to(old[out[j]])
				var swap := a.distance_to(old[out[j]]) + b.distance_to(old[out[i]])
				if swap < keep - 0.001:
					var held := out[i]
					out[i] = out[j]
					out[j] = held
					improved = true
		if not improved:
			break
	return out


## One relaxation pass: overlapping drawn men of a squad push apart,
## each clamped to MAX_RENDER_DRIFT of his own authoritative anchor —
## the amendment's bound, enforced where the drift is made. PURE.
## `max_correction` bounds how far the DRIFT CLAMP itself may move a man
## in one call. Uncapped (the default, and every direct caller), the
## clamp is instantaneous — which is right for the jitter it was built
## for and was measured teleporting men 2.9 units in one frame when a
## direction change rotated the whole slot lattice past the bound: the
## capped pursuit walked them, and the clamp then yanked them the rest.
## With a cap, an over-drifted man WALKS back inside the bound at the
## same pace he chases his slot; the bound becomes "converged to within
## a few frames" rather than "held per frame", and SNAP_DISTANCE still
## hard-bounds the total.
static func jostle(positions: PackedVector3Array,
		anchors: Array[Transform3D],
		max_correction: float = 1e9) -> PackedVector3Array:
	var out := positions.duplicate()
	var n := out.size()
	for i in range(n):
		for j in range(i + 1, n):
			var between := Vector2(out[j].x - out[i].x, out[j].z - out[i].z)
			var d := between.length()
			if d >= JOSTLE_RADIUS or d < 0.0001:
				continue
			var push := (JOSTLE_RADIUS - d) * 0.5
			var direction := between / d
			out[i] += Vector3(-direction.x * push, 0.0, -direction.y * push)
			out[j] += Vector3(direction.x * push, 0.0, direction.y * push)
	for i in range(n):
		var anchor: Vector3 = anchors[i].origin
		var drift := out[i] - anchor
		var flat := Vector2(drift.x, drift.z)
		if flat.length() > MAX_RENDER_DRIFT:
			var clamped := flat.normalized() * MAX_RENDER_DRIFT
			var clamp_target := Vector3(
				anchor.x + clamped.x, out[i].y, anchor.z + clamped.y)
			var correction := clamp_target - out[i]
			if correction.length() > max_correction:
				correction = correction.normalized() * max_correction
			out[i] += correction
	return out


## Forget a squad's eased state — on conceal, death, or leaving view, so
## the dictionary does not grow for the length of a match.
func forget(squad_id) -> void:
	_eased.erase(squad_id)


## How many squads are being eased. For tests and for anyone checking this
## is not leaking.
func tracked_count() -> int:
	return _eased.size()
