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
## If any of those three ever stops being true, D-006's revisit trigger
## has fired and this is not a small refactor.
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
	if stored.size() != count:
		# First sight of this squad, or its strength changed. Start from
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

	var out: Array[Transform3D] = []
	out.resize(count)
	for i in range(count):
		var target: Vector3 = transforms[i].origin
		var current: Vector3 = stored[i]
		var eased := target if current.distance_to(target) > SNAP_DISTANCE \
			else current.lerp(target, blend)
		stored[i] = eased
		# Basis is taken from the authoritative transform unchanged: the
		# squad's facing is already smooth because it comes from the
		# curve's own direction, and easing it as well would make troops
		# lag their own feet.
		out[i] = Transform3D(transforms[i].basis, eased)

	_eased[squad_id] = stored
	return out


## Forget a squad's eased state — on conceal, death, or leaving view, so
## the dictionary does not grow for the length of a match.
func forget(squad_id) -> void:
	_eased.erase(squad_id)


## How many squads are being eased. For tests and for anyone checking this
## is not leaking.
func tracked_count() -> int:
	return _eased.size()
