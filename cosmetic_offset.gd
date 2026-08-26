extends RefCounted
class_name CosmeticOffset

## Client-only visual offsets for individual soldiers (D-006 clause 2).
##
## ## Why this is a separate file
##
## D-006 permits cosmetic per-soldier motion — idle sway, footfall bob,
## breathing — precisely because it is ONE-WAY: the render path may read
## it, and the simulation may never read it back. Keeping it in its own
## class rather than as a Formation method makes that boundary structural
## instead of a comment someone can miss. Nothing in the sim, the
## replicator, or Formation imports this file, and a test asserts that
## authoritative transforms are unaffected by it.
##
## If simulation ever needs to consult one of these values, that is not a
## small refactor — it means soldiers have acquired their own state and
## D-006's revisit trigger has fired.
##
## These offsets are also why the formation restamping on casualties
## (clause 3) doesn't have to look robotic: the authoritative slot snaps,
## and the render layer is free to ease toward it.

## Small horizontal sway, cycling per soldier. Pure in (slot, time) so it
## is stable across frames rather than jittering randomly, but it is NOT
## required to match between machines — nothing depends on it agreeing.
static func idle_sway(slot: int, time: float, amplitude: float = 0.04) -> Vector3:
	var phase := float(slot) * 0.7391
	return Vector3(
		sin(time * 1.3 + phase) * amplitude,
		0.0,
		cos(time * 1.1 + phase) * amplitude
	)


## Vertical bob suggesting footfalls while moving. `speed` scales both
## rate and amplitude so a stationary squad stops bobbing.
static func footfall_bob(slot: int, time: float, speed: float, amplitude: float = 0.03) -> float:
	if speed <= 0.001:
		return 0.0
	var phase := float(slot) * 2.399
	return absf(sin(time * (4.0 + speed) + phase)) * amplitude * minf(speed, 1.0)


## Apply cosmetic offsets to an authoritative transform, returning a new
## one. The input is never mutated — the caller keeps the authoritative
## value and renders the returned one.
static func decorate(authoritative: Transform3D, slot: int, time: float, speed: float) -> Transform3D:
	var decorated := authoritative
	decorated.origin += idle_sway(slot, time)
	decorated.origin.y += footfall_bob(slot, time, speed)
	return decorated


## Convenience for the render path: decorate a whole squad at once.
static func decorate_all(transforms: Array[Transform3D], time: float, speed: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for slot in range(transforms.size()):
		out.append(decorate(transforms[slot], slot, time, speed))
	return out


## What a squad is visibly DOING, for the render path only (D-059).
enum Activity { IDLE, WORKING, FIGHTING }


## How far a working or fighting soldier leans, for a model whose own
## animation shows none of it.
const SWING_AMPLITUDE := 0.34

## The same, for a model that animates the work ITSELF: NOTHING.
##
## This whole mechanism is a placeholder that predates having any animation
## at all — a lunge toward the thing being worked, plus `idle_sway`, to say
## "something is happening here" on a model that could not say it otherwise.
## The gatherer draws a real axe stroke now
## (`D-20260825-a-gatherer-carries-the-tool-for-the-job`), and the owner's
## playtest reported the leftover as the crew "bobbing around, floating side
## to side".
##
## It is not a matter of amplitude. A 3 Hz lunge against a 0.62 Hz chop beats
## against it about five times per stroke, so ANY non-zero value is two
## mechanisms doing one job at different rhythms — which is how a correct
## animation ends up looking broken. It went 0.34 -> 0.11 -> 0.
##
## `decorate_activity` skips the idle sway as well when this is zero, because
## halving one placeholder and leaving the other is not a decision anybody
## made on purpose.
const ANIMATED_SWING_AMPLITUDE := 0.0


## Lean and swing toward a point — chopping at a tree, striking at an
## enemy. Returns an offset to add to the soldier's position.
##
## The whole point is that a squad standing perfectly still while its
## strength drains looks broken. This costs nothing in the simulation:
## casualties, gathering and combat all resolve exactly as before, and
## this only decides where the man is drawn while it happens.
##
## Pure in (slot, time, toward) and stateless like everything else here.
## Soldiers are deliberately out of phase with each other — a squad
## swinging in perfect unison reads as a machine, not a crew.
static func work_swing(slot: int, time: float, toward: Vector3,
		activity: int, amplitude: float = SWING_AMPLITUDE) -> Vector3:
	if activity == Activity.IDLE:
		return Vector3.ZERO

	var direction := toward
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	direction = direction.normalized()

	# Fighting is sharper and faster than working: a strike snaps out and
	# recovers, a woodcutter swings in a rhythm.
	var rate := 5.5 if activity == Activity.FIGHTING else 3.0
	var phase := float(slot) * 1.6180  # golden-ish, so no two share a beat
	var swing := sin(time * rate + phase)
	# Squared toward the far end so the motion has a bite to it rather
	# than being a smooth sine slide.
	var reach := swing * absf(swing)
	return direction * reach * amplitude


## Decorate a whole squad that is working or fighting, leaning toward
## `toward` in WORLD space. `toward` is the thing being worked or fought:
## the resource under them, or the enemy squad they are engaging.
static func decorate_activity(transforms: Array[Transform3D], time: float,
		speed: float, activity: int, toward: Vector3,
		amplitude: float = SWING_AMPLITUDE) -> Array[Transform3D]:
	if activity == Activity.IDLE:
		return decorate_all(transforms, time, speed)

	# A model that animates its own work takes NO cosmetic motion at all —
	# not the swing and not the sway. Both are placeholders for an animation
	# that now exists; see `ANIMATED_SWING_AMPLITUDE`.
	if amplitude <= 0.0:
		return transforms.duplicate()

	var out: Array[Transform3D] = []
	for slot in range(transforms.size()):
		var decorated := decorate(transforms[slot], slot, time, speed)
		# Each soldier leans toward the target from where HE stands, so a
		# ring around a tree all face inward and a line facing an enemy
		# all lean the same way — without any of them being told which.
		decorated.origin += work_swing(
			slot, time, toward - transforms[slot].origin, activity, amplitude)
		out.append(decorated)
	return out
