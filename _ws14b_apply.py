import sys

p = 'client.gd'; s = open(p, encoding='utf-8').read()
applied = []

def rep(name, old, new):
    global s
    if old not in s:
        print("MISS:", name); sys.exit(1)
    s = s.replace(old, new)
    applied.append(name)

rep("vars", '''const SURROUND_STEP := 4.0''',
'''const SURROUND_STEP := 4.0

# The static-target deal, CACHED per squad (D-20260821): recomputed only
# when the target or the strength changes, so a man's mark holds instead
# of hopping along the wall as his slot drifts. Per-soldier render
# memory — the amendment's territory. squad -> {"key", "paired"}
var _static_deal := {}
# Last frame's drawn men per squad, for the cross-squad jostle:
# squad -> {"men": PackedVector3Array, "centre": Vector3, "radius": float}
var _drawn_cache := {}''')

rep("sticky-deal", '''			var ring_positions := PackedVector3Array()
			ring_positions.resize(ring.size())
			for i in range(ring.size()):
				ring_positions[i] = ring[i].origin
			paired = SoldierMotion.assign(ring_positions, transforms)
			enemy_transforms = ring
			dueling = true''',
'''			# The deal HOLDS while the target and the strength hold
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
			dueling = true''')

rep("rect-key", '''					"rect_centre": box["centre"], "rect_half": box["half"],
					"rect_yaw": box["yaw"],
				}''',
'''					"rect_centre": box["centre"], "rect_half": box["half"],
					"rect_yaw": box["yaw"],
					"target_key": "b:%d" % int(box.get("id", -1)),
				}''')

rep("node-key", '''			"ring_centre": node_at, "ring_radius": 0.9,
		}''',
'''			"ring_centre": node_at, "ring_radius": 0.9,
			"target_key": "n:%d" % crew_cell,
		}''')

rep("box-id", '''		if d - maxf(half.x, half.y) <= reach and d < best_d:
			best_d = d
			best = {"centre": centre, "half": half, "yaw": entry["yaw"]}
	return best''',
'''		if d - maxf(half.x, half.y) <= reach and d < best_d:
			best_d = d
			best = {"centre": centre, "half": half, "yaw": entry["yaw"],
				"id": entry["id"]}
	return best''')

rep("scan-id", '''		_building_scan.append({
			"at": _state.space.to_world(''',
'''		_building_scan.append({
			"id": int(id),
			"at": _state.space.to_world(''')

rep("ease-neighbours", '''		var eased := _motion.ease(squad_id, transforms, _frame_delta)''',
'''		# Foreign drawn men within overlap range (previous frame's — one
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
			"centre": centre + offset, "radius": world_radius}''')

rep("teardown", '''	_order_press = Vector2.INF
	_terrain_built = false''',
'''	_order_press = Vector2.INF
	_static_deal.clear()
	_drawn_cache.clear()
	_terrain_built = false''')

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("client ok:", applied)

p = 'decisions/D-20260818-squads-separate-by-their-footprints.md'
s = open(p, encoding='utf-8').read()
if 'Amended 2026-08-21' not in s:
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
print("amendment ok")
