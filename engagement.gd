extends RefCounted
class_name Engagement

## THE definition of who fights whom at soldier granularity
## (D-20260819-only-men-in-contact-fight — Tier 2 of the RTW formations
## decision).
##
## All-static and pure, the Formation family: no instance state, same
## inputs, same answer, forever. That purity is not style — it is the
## whole legal basis. D-006's confirmation block permits the server to
## compute soldier positions "whenever combat needs it and still send
## nothing" precisely BECAUSE the computation is a pure function of
## replicated squad state; and the three-tier decision's collapse trigger
## says that the moment a pairing needs to be REMEMBERED across ticks,
## Tier 2 has failed and the design reopens. A cache of last tick's
## pairing does not belong here and never will.
##
## ## One definition, two readers
##
## `combat.gd` (server) multiplies damage by `contact_count`;
## the Tier 1 duel layer (client) draws each man against `opponents`' pick.
## Sharing the function is what makes the fight a player SEES the fight
## that RESOLVES — two implementations would drift at every corner case
## and quietly reopen the gap this tier exists to close.
##
## ## The reach model
##
## A man fights what he could step up to and hit: his squad's
## `attack_range` plus the step BOTH duellists visibly take
## (2 × MAX_STEP). Without the slack, two ENGAGED front ranks a cell
## apart (~1.73 world units) exceed a melee reach of 1.5 and the contact
## count is zero — engagement saying "fight" while contact says "cannot",
## the same opposed-arithmetic failure D-067's amendment records for
## separation. The decision entry has the numbers.

## How far short of his opponent a drawn man stands (Tier 1). Roughly two
## capsule radii — close enough to read as contact, far enough that
## authored models do not embed in each other when both sides step in.
const CONTACT_GAP := 0.7

## The farthest a drawn man may be displaced from his authoritative slot
## (Tier 1), and — doubled, since both sides pay it — the slack a man's
## fighting reach gets over his weapon's (Tier 2). One constant on
## purpose: the reach a man fights at IS the reach he is drawn at.
const MAX_STEP := 1.1


## The reach a soldier's contact test uses, from his squad's attack range.
static func contact_reach(attack_range: float) -> float:
	return attack_range + 2.0 * MAX_STEP


## Where a blow came from, for the morale shock terms
## (D-20260819-morale-reads-the-fight). Front and rear are ~70° cones
## (|dot| ≥ FRONT_DOT); everything between is flank.
const ASPECT_FRONT := 0
const ASPECT_FLANK := 1
const ASPECT_REAR := 2
const FRONT_DOT := 0.34


## Classify an attacker's direction against the defender's facing. Both
## positions must be in the SAME lattice frame — the caller pays the
## torus tax with `aligning_offset`, exactly as contact does; classified
## on canonical coordinates, an attacker across the seam would read as
## charging from a map away in the wrong direction. Degenerate inputs
## (no facing, same position) read as frontal: shock is a bonus for
## outmanoeuvring someone, and unknowable geometry must never award it.
static func aspect(facing: Vector3, defender_pos: Vector3,
		attacker_pos: Vector3) -> int:
	var face := Vector2(facing.x, facing.z)
	var toward := Vector2(attacker_pos.x - defender_pos.x,
		attacker_pos.z - defender_pos.z)
	if face.length_squared() < 0.000001 or toward.length_squared() < 0.000001:
		return ASPECT_FRONT
	var dot := face.normalized().dot(toward.normalized())
	if dot >= FRONT_DOT:
		return ASPECT_FRONT
	if dot <= -FRONT_DOT:
		return ASPECT_REAR
	return ASPECT_FLANK


## The lattice offset that brings `other` to its copy nearest `anchor` —
## the torus tax, paid here once so nothing below needs to know the world
## wraps. Two engaged squads' canonical positions can legitimately sit a
## whole map apart across a seam; measured raw, their contact count would
## be zero and a seam battle would resolve no damage while the cell-based
## engagement scan (already wrap-aware) says they are fighting.
## `offsets` is `TorusSpace.lattice_offsets()` from either side's space —
## they are the same space.
static func aligning_offset(anchor: Vector3, other: Vector3,
		offsets: Array[Vector3]) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for offset in offsets:
		var d := Vector2(other.x + offset.x - anchor.x,
			other.z + offset.z - anchor.z).length_squared()
		if d < best_d:
			best_d = d
			best = offset
	return best


## `transforms` translated by `offset`. The ZERO fast path returns the
## input array itself — the overwhelmingly common mid-map case costs one
## comparison.
static func shifted(transforms: Array[Transform3D],
		offset: Vector3) -> Array[Transform3D]:
	if offset == Vector3.ZERO:
		return transforms
	var out: Array[Transform3D] = []
	out.resize(transforms.size())
	for i in range(transforms.size()):
		var moved := transforms[i]
		moved.origin += offset
		out[i] = moved
	return out


## `count` points evenly around a circle — the stand-ins the duel
## pipeline uses for a STATIC target's "defenders"
## (D-20260820-men-gather-round-what-they-strike). Pure and phase-fixed,
## so every frame deals the same ring and nothing jitters.
static func ring_points(centre: Vector3, radius: float,
		count: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var n := maxi(count, 1)
	out.resize(n)
	for i in range(n):
		var angle := TAU * float(i) / float(n)
		out[i] = Transform3D(Basis(),
			centre + Vector3(sin(angle) * radius, 0.0, cos(angle) * radius))
	return out


## `count` points evenly (by arc length) around a RECTANGLE's perimeter —
## the stand-ins for a BOX-shaped static target
## (D-20260820-men-gather-round-what-they-strike, second amendment: a
## building is a box, and men lining a box stand on its faces, not on a
## circle through its corners). `half` is the half-extents in the box's
## own frame, `yaw` its world rotation. Pure and phase-fixed.
static func rect_points(centre: Vector3, half: Vector2, yaw: float,
		count: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var n := maxi(count, 1)
	out.resize(n)
	var hx := maxf(half.x, 0.01)
	var hz := maxf(half.y, 0.01)
	var perimeter := 4.0 * (hx + hz)
	for i in range(n):
		var t := perimeter * float(i) / float(n)
		var local := Vector2.ZERO
		if t < 2.0 * hx:                      # front face, +z, right to left
			local = Vector2(hx - t, hz)
		elif t < 2.0 * (hx + hz):             # left face, -x
			local = Vector2(-hx, hz - (t - 2.0 * hx))
		elif t < 4.0 * hx + 2.0 * hz:         # back face, -z, left to right
			local = Vector2(-hx + (t - 2.0 * hx - 2.0 * hz), -hz)
		else:                                  # right face, +x
			local = Vector2(hx, -hz + (t - 4.0 * hx - 2.0 * hz))
		var turned := local.rotated(-yaw)
		out[i] = Transform3D(Basis(),
			centre + Vector3(turned.x, 0.0, turned.y))
	return out


## A drawn man never stands INSIDE a building
## (D-20260820, third amendment): a position inside the box is projected
## to its nearest face, margin included. Pure; the caller decides which
## boxes are near enough to test. This exists because formation slots
## clamp against TERRAIN passability by design (the building-stamped
## array is the sim's own and cannot be reproduced under fog), so a
## line's slots can legitimately land inside a footprint — and the
## owner's screenshots showed exactly that, twice.
static func push_out_of_box(position: Vector3, centre: Vector3,
		half: Vector2, yaw: float, margin: float = 0.35) -> Vector3:
	var local := Vector2(position.x - centre.x, position.z - centre.z).rotated(yaw)
	var hx := half.x + margin
	var hz := half.y + margin
	if absf(local.x) >= hx or absf(local.y) >= hz:
		return position
	# Inside: exit through the nearest face.
	var out := local
	if hx - absf(local.x) <= hz - absf(local.y):
		out.x = hx if local.x >= 0.0 else -hx
	else:
		out.y = hz if local.y >= 0.0 else -hz
	var turned := out.rotated(-yaw)
	return Vector3(centre.x + turned.x, position.y, centre.z + turned.y)


## The box rule's round sibling (D-20260821, amended): a drawn man
## inside a tree's disc steps out to its rim. Pure.
static func push_out_of_disc(position: Vector3, centre: Vector3,
		radius: float) -> Vector3:
	var flat := Vector2(position.x - centre.x, position.z - centre.z)
	var d := flat.length()
	if d >= radius:
		return position
	if d < 0.0001:
		flat = Vector2(radius, 0.0)
	else:
		flat = flat / d * radius
	return Vector3(centre.x + flat.x, position.y, centre.z + flat.y)


## For each attacker transform, the index of the nearest defender
## transform (horizontal distance; first-found wins ties, so the answer is
## deterministic for identical inputs). O(attackers × defenders), paid
## only by squads in a melee.
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


## How many attackers stand within `reach` of their nearest defender —
## the men actually fighting, and the multiplier D-024's damage output
## now takes instead of the squad's whole strength.
##
## Deliberately does not reuse `opponents()`: the count needs only the
## nearest DISTANCE, and early-exiting a row the moment any defender is
## inside reach makes the common case (a wide line squarely engaged)
## cheaper than deriving the full pairing.
static func contact_count(attackers: Array[Transform3D],
		defenders: Array[Transform3D], reach: float) -> int:
	if defenders.is_empty():
		return 0
	var reach_sq := reach * reach
	var count := 0
	for i in range(attackers.size()):
		var here := attackers[i].origin
		for j in range(defenders.size()):
			var d := Vector2(defenders[j].origin.x - here.x,
				defenders[j].origin.z - here.z).length_squared()
			if d <= reach_sq:
				count += 1
				break
	return count
