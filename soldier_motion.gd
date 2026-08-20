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
const MAX_RENDER_DRIFT := 1.5

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
func ease(squad_id, transforms: Array[Transform3D], delta: float) -> Array[Transform3D]:
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

	# Exponential smoothing, so the rate is independent of framerate: at
	# any dt the soldier covers the same FRACTION of the remaining gap per
	# unit time. A plain lerp(a, b, k * dt) is not, and would make troops
	# visibly slower on a slow machine.
	var blend := 1.0 - exp(-EASE_RATE * maxf(delta, 0.0))

	for i in range(count):
		var target: Vector3 = transforms[i].origin
		var current: Vector3 = stored[i]
		stored[i] = target if current.distance_to(target) > SNAP_DISTANCE \
			else current.lerp(target, blend)

	# Tier 3 (D-006 as amended): the scrum breathes. Fed BACK into the
	# stored positions — genuine per-soldier integration, which is
	# exactly what the amendment legalises here and nowhere else.
	stored = jostle(stored, transforms)
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
	return out


## One relaxation pass: overlapping drawn men of a squad push apart,
## each clamped to MAX_RENDER_DRIFT of his own authoritative anchor —
## the amendment's bound, enforced where the drift is made. PURE.
static func jostle(positions: PackedVector3Array,
		anchors: Array[Transform3D]) -> PackedVector3Array:
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
			out[i] = Vector3(anchor.x + clamped.x, out[i].y, anchor.z + clamped.y)
	return out


## Forget a squad's eased state — on conceal, death, or leaving view, so
## the dictionary does not grow for the length of a match.
func forget(squad_id) -> void:
	_eased.erase(squad_id)


## How many squads are being eased. For tests and for anyone checking this
## is not leaking.
func tracked_count() -> int:
	return _eased.size()
