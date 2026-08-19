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
