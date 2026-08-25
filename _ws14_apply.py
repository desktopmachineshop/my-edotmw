# --- sim: ally separation reverts to the one-cell centre rule ---------
p = 'squad_sim.gd'; s = open(p, encoding='utf-8').read()
old = '''## Allies keep out of each other's formations: the sum of the ground the
## two of them cover, which for a pair of lines is very nearly shoulder
## to shoulder.
##
## ENEMIES keep D-060's original ONE cell, and that distinction is not a
## nicety. A melee squad's `attack_range` is under two world units — a
## little over one cell — so separating a squad from its opponent by its
## own footprint would shove every engagement out of its own reach and no
## melee could ever land. Interpenetrating enemies is what a fight looks
## like; combat (D-024) is what resolves it, not spacing.
func _clearance(asking: int, other: int) -> int:
	if not are_allied(_owner[asking], _owner[other]):
		return 1
	return footprint_cells(asking) + footprint_cells(other)'''
new = '''## EVERYONE keeps D-060's original ONE cell since
## D-20260821-a-fight-loosens-a-formation (the owner's call, reverting
## #104's ally half): displacing a whole ALLIED squad by two footprints
## was exactly the "whole squad snaps or moves" a player sees, and
## overlap is resolved at the individual drawn man now — the
## cross-squad jostle — not by teleporting forty men sideways. Enemies
## were always here: interpenetrating enemies is what a fight looks
## like; combat (D-024) resolves it, not spacing.
func _clearance(_asking: int, _other: int) -> int:
	return 1'''
assert old in s; s = s.replace(old, new)
open(p, 'w', encoding='utf-8', newline='\n').write(s)

# --- render: walk transitions, cross-squad jostle ----------------------
p = 'soldier_motion.gd'; s = open(p, encoding='utf-8').read()
old = '''const SNAP_DISTANCE := 6.0'''
new = '''## Raised 6 -> 12 by D-20260821-a-fight-loosens-a-formation: a new
## engagement's far-side mark used to clear the old threshold and men
## BLINKED there. Every legitimate retarget walks now; the seam jump
## this guards (a whole map width in one frame, D-035) is still a
## hundred times the threshold.
const SNAP_DISTANCE := 12.0'''
assert old in s; s = s.replace(old, new)

old = '''func ease(squad_id, transforms: Array[Transform3D], delta: float) -> Array[Transform3D]:'''
new = '''## `others` — drawn men of OVERLAPPING squads (previous frame's, one
## frame of lag) — lets the jostle work ACROSS squads
## (D-20260821-a-fight-loosens-a-formation): squads may stand on each
## other, and their men sort it out individually instead of a whole
## squad snapping away.
func ease(squad_id, transforms: Array[Transform3D], delta: float,
		others: PackedVector3Array = PackedVector3Array()) -> Array[Transform3D]:'''
assert old in s; s = s.replace(old, new)

old = '''	# Tier 3 (D-006 as amended): the scrum breathes. Fed BACK into the
	# stored positions — genuine per-soldier integration, which is
	# exactly what the amendment legalises here and nowhere else.
	stored = jostle(stored, transforms)'''
new = '''	# Tier 3 (D-006 as amended): the scrum breathes. Fed BACK into the
	# stored positions — genuine per-soldier integration, which is
	# exactly what the amendment legalises here and nowhere else.
	stored = jostle(stored, transforms, others)'''
assert old in s; s = s.replace(old, new)

old = '''static func jostle(positions: PackedVector3Array,
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
			out[j] += Vector3(direction.x * push, 0.0, direction.y * push)'''
new = '''static func jostle(positions: PackedVector3Array,
		anchors: Array[Transform3D],
		others: PackedVector3Array = PackedVector3Array()) -> PackedVector3Array:
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
	# Foreign men push OUR men only (theirs move in their own pass, so
	# nobody is displaced twice) — the cross-squad half of D-20260821.
	for i in range(n):
		for k in range(others.size()):
			var between := Vector2(others[k].x - out[i].x, others[k].z - out[i].z)
			var d := between.length()
			if d >= JOSTLE_RADIUS or d < 0.0001:
				continue
			var direction := between / d
			var push := JOSTLE_RADIUS - d
			out[i] += Vector3(-direction.x * push, 0.0, -direction.y * push)'''
assert old in s; s = s.replace(old, new)
open(p, 'w', encoding='utf-8', newline='\n').write(s)

# --- client: sticky deals, neighbour gather, drawn cache ---------------
p = 'client.gd'; s = open(p, encoding='utf-8').read()

old = '''const SURROUND_STEP := 4.0'''
new = '''const SURROUND_STEP := 4.0

# The static-target deal, CACHED per squad (D-20260821): recomputed only
# when the target or the strength changes, so a man's mark holds instead
# of hopping along the wall as his slot drifts. Per-soldier render
# memory — the amendment's territory. squad -> {"key", "count", "paired"}
var _static_deal := {}
# Last frame's drawn men per squad, for the cross-squad jostle:
# squad -> {"men": PackedVector3Array, "centre": Vector3, "radius": float}
var _drawn_cache := {}'''
assert old in s; s = s.replace(old, new)

old = '''			var ring_positions := PackedVector3Array()
			ring_positions.resize(ring.size())
			for i in range(ring.size()):
				ring_positions[i] = ring[i].origin
			paired = SoldierMotion.assign(ring_positions, transforms)
			enemy_transforms = ring
			dueling = true'''
new = '''			# The deal HOLDS while the target and the strength hold
			# (D-20260821): recomputing it every frame hopped every
			# man's mark along the wall as his slot drifted.
			var deal_key: String = str(doing.get("target_key", "")) \\
				+ "|" + str(transforms.size())
			var cached: Dictionary = _static_deal.get(squad_id, {})
			if String(cached.get("key", "")) == deal_key:
				paired = cached["paired"]
			else:
				var ring_positions := PackedVector3Array()
				ring_positions.resize(ring.size())
				for i in range(ring.size()):
					ring_positions[i] = ring[i].origin
				paired = SoldierMotion.assign(ring_positions, transforms)
				_static_deal[squad_id] = {"key": deal_key, "paired": paired}
			enemy_transforms = ring
			dueling = true'''
assert old in s; s = s.replace(old, new)

# Target keys from the activity dicts.
old = '''					"rect_centre": box["centre"], "rect_half": box["half"],
					"rect_yaw": box["yaw"],
				}'''
new = '''					"rect_centre": box["centre"], "rect_half": box["half"],
					"rect_yaw": box["yaw"],
					"target_key": "b:%d" % int(box.get("id", -1)),
				}'''
assert old in s; s = s.replace(old, new)

old = '''			"ring_centre": node_at, "ring_radius": 0.9,
		}'''
new = '''			"ring_centre": node_at, "ring_radius": 0.9,
			"target_key": "n:%d" % crew_cell,
		}'''
assert old in s; s = s.replace(old, new)

# node branch defines crew_cell? ensure name matches: it computes crew_cell above.

# Building id into the box dict.
old = '''		if d - maxf(half.x, half.y) <= reach and d < best_d:
			best_d = d
			best = {"centre": centre, "half": half, "yaw": entry["yaw"]}
	return best'''
new = '''		if d - maxf(half.x, half.y) <= reach and d < best_d:
			best_d = d
			best = {"centre": centre, "half": half, "yaw": entry["yaw"],
				"id": entry["id"]}
	return best'''
assert old in s; s = s.replace(old, new)

old = '''		_building_scan.append({
			"at": _state.space.to_world(
				_state.space.from_index(int(info.get("cell", 0)))),'''
new = '''		_building_scan.append({
			"id": int(id),
			"at": _state.space.to_world(
				_state.space.from_index(int(info.get("cell", 0)))),'''
assert old in s; s = s.replace(old, new)

# Neighbour gather + cache write around the ease call.
old = '''		var eased := _motion.ease(squad_id, transforms, _frame_delta)'''
new = '''		# Foreign drawn men within overlap range (previous frame's — one
		# frame of lag), so OUR men adjust to THEIRS individually
		# (D-20260821) instead of squads snapping apart.
		var neighbours := PackedVector3Array()
		for other_id in _drawn_cache:
			if other_id == squad_id:
				continue
			var record: Dictionary = _drawn_cache[other_id]
			if (record["centre"] as Vector3).distance_to(centre + offset) \\
					<= world_radius + float(record["radius"]) + 1.0:
				neighbours.append_array(record["men"])
		var eased := _motion.ease(squad_id, transforms, _frame_delta, neighbours)
		var drawn_men := PackedVector3Array()
		drawn_men.resize(eased.size())
		for i in range(eased.size()):
			drawn_men[i] = eased[i].origin
		_drawn_cache[squad_id] = {"men": drawn_men,
			"centre": centre + offset, "radius": world_radius}'''
assert old in s; s = s.replace(old, new)

# Teardown clears the new render state.
old = '''	if _order_drag_line != null:
		_order_drag_line.queue_free()
		_order_drag_line = null
	_order_press = Vector2.INF'''
new = '''	if _order_drag_line != null:
		_order_drag_line.queue_free()
		_order_drag_line = null
	_order_press = Vector2.INF
	_static_deal.clear()
	_drawn_cache.clear()'''
assert old in s; s = s.replace(old, new)
open(p, 'w', encoding='utf-8', newline='\n').write(s)

# --- the #104 amendment ------------------------------------------------
p = 'decisions/D-20260818-squads-separate-by-their-footprints.md'
s = open(p, encoding='utf-8').read()
s += '''

**Amended 2026-08-21 (D-20260821-a-fight-loosens-a-formation, the
owner's call):** the ALLY half of this rule is reverted — allies keep
D-060's original one-cell centre rule again, like enemies always did.
Displacing a whole allied squad by two footprints was exactly the
"whole squad snaps or moves" a player sees from above; overlap is
resolved at the individual DRAWN man now (the cross-squad jostle, D-006
as amended), which is where the owner asked for it. The engagement and
gathering exemptions in `_separate_arrivals` stand unchanged, and this
file keeps the record of why the footprint number exists — the marker
lesson above is still true even though the sim no longer enforces it.
'''
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("all applied")
