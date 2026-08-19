extends RefCounted
class_name BattleLine

## The drag-order's arithmetic (D-20260819-a-drag-draws-the-battle-line):
## a dragged stroke, a selection, and out come per-squad destinations,
## facings and widths — compiled entirely into the orders workstream 5
## already ships, so the server never learns a new concept.
##
## All-static and pure, the `hud_layout.gd` family: client geometry that
## only lives inside client.gd is client geometry nobody can test
## (the D-061 lesson). client.gd's job is to gather the inputs and send
## what this returns.

## Below this many screen pixels of travel, a "drag" is a click and the
## caller keeps yesterday's click semantics untouched.
const DRAG_ORDER_THRESHOLD_PX := 12.0


## Plan a battle line for `squads` along the world-space stroke
## `from` -> `to`.
##
## `squads` entries: {"id": int, "at": Vector3 (current world position),
## "alive": int, "spacing": float}. Returns one entry per squad, in the
## INPUT's order: {"id": int, "destination": Vector3,
## "facing_quantised": int, "files": int}.
##
## Segments are dealt by each squad's PROJECTION along the stroke — the
## leftmost squad takes the leftmost segment — so lines do not cross
## while forming. Facing is the stroke's perpendicular, signed to point
## away from the selection's current centroid: troops walk up and face
## onward.
static func plan(from: Vector3, to: Vector3, squads: Array) -> Array:
	if squads.is_empty():
		return []
	var stroke := Vector2(to.x - from.x, to.z - from.z)
	if stroke.length_squared() < 0.0001:
		return []
	var direction := stroke.normalized()
	var length := stroke.length()

	# The centroid decides which way the line faces.
	var centroid := Vector3.ZERO
	for squad in squads:
		centroid += squad["at"] as Vector3
	centroid /= float(squads.size())

	var perpendicular := Vector2(direction.y, -direction.x)
	var mid := from + Vector3(stroke.x, 0.0, stroke.y) * 0.5
	var toward_troops := Vector2(centroid.x - mid.x, centroid.z - mid.z)
	if perpendicular.dot(toward_troops) > 0.0:
		perpendicular = -perpendicular
	var facing := quantise_angle(atan2(perpendicular.x, perpendicular.y))

	# Deal segments by projection along the stroke, so squads keep their
	# left-to-right order and never cross while forming.
	var order := []
	for i in range(squads.size()):
		var at: Vector3 = squads[i]["at"]
		order.append({"index": i,
			"along": Vector2(at.x - from.x, at.z - from.z).dot(direction)})
	order.sort_custom(func(a, b): return float(a["along"]) < float(b["along"]))

	var out := []
	out.resize(squads.size())
	var segment := length / float(squads.size())
	for rank in range(order.size()):
		var index := int(order[rank]["index"])
		var squad: Dictionary = squads[index]
		var centre_along := (float(rank) + 0.5) * segment
		var destination := from \
			+ Vector3(direction.x, 0.0, direction.y) * centre_along
		var spacing := maxf(float(squad.get("spacing", 1.0)), 0.01)
		var files := clampi(roundi(segment / spacing), 1,
			maxi(int(squad.get("alive", 1)), 1))
		out[index] = {
			"id": int(squad["id"]),
			"destination": destination,
			"facing_quantised": facing,
			"files": files,
		}
	return out


## One definition of angle -> wire quantisation (1/4096 of a turn),
## shared with the Alt+click facing order so the two ways of saying
## "face there" cannot round differently.
static func quantise_angle(angle: float) -> int:
	return wrapi(roundi(fposmod(angle, TAU) / TAU * 4096.0), 0, 4096)
