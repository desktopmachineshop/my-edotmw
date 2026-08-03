extends GutTest

## Guards D-006's three binding clauses, which are the keystone the whole
## netcode budget rests on:
##
##   1. Purity — soldier position is a pure function of (squad curve,
##      formation shape, slot index, terrain sample), with no per-soldier
##      integration state.
##   2. Cosmetic offsets are one-way — the render layer may decorate,
##      simulation may never read it back.
##   3. Casualty reassignment is deterministic — the formation restamps,
##      soldiers do not walk into a dead man's slot.
##
## Clause 1 is the one worth testing hardest, because breaking it is
## silent: everything still looks fine locally and only diverges between
## client and server under load.

const W := 32
const H := 16
const SHAPES := ["line", "column", "wedge", "loose"]


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _march(space: TorusSpace, from: Vector2i, steps: int) -> StateCurve:
	var c := StateCurve.new()
	for i in range(steps):
		c.append_cell(float(i), Vector2i(from.x + i, from.y), space)
	return c


# --- clause 1: purity -------------------------------------------------

func test_same_inputs_always_give_the_same_output() -> void:
	var t := _space()
	var curve := _march(t, Vector2i(4, 4), 8)

	for shape in SHAPES:
		for slot in [0, 1, 7, 23]:
			var a := Formation.soldier_transform(curve, 3.5, slot, 40, shape, 1.0, t)
			var b := Formation.soldier_transform(curve, 3.5, slot, 40, shape, 1.0, t)
			assert_eq(a, b, "%s slot %d is not deterministic" % [shape, slot])


func test_evaluation_order_does_not_affect_results() -> void:
	# The sharpest test for hidden state: if anything were accumulating
	# between calls, evaluating slots backwards would disagree with
	# evaluating them forwards.
	var t := _space()
	var curve := _march(t, Vector2i(2, 6), 6)

	for shape in SHAPES:
		var forward: Array[Transform3D] = []
		for slot in range(30):
			forward.append(Formation.soldier_transform(curve, 2.5, slot, 30, shape, 1.0, t))

		var backward := {}
		for slot in range(29, -1, -1):
			backward[slot] = Formation.soldier_transform(curve, 2.5, slot, 30, shape, 1.0, t)

		for slot in range(30):
			assert_eq(forward[slot], backward[slot],
				"%s slot %d differs by evaluation order — Formation is carrying state" % [shape, slot])


func test_revisiting_an_earlier_time_reproduces_the_earlier_result() -> void:
	# Time-travel test: sample late, then early, then late again. Any
	# integration state (velocity, smoothing, easing) would make the third
	# sample differ from the first.
	var t := _space()
	var curve := _march(t, Vector2i(0, 3), 10)

	var early_first := Formation.soldier_transform(curve, 1.0, 5, 40, "line", 1.0, t)
	var _late := Formation.soldier_transform(curve, 8.0, 5, 40, "line", 1.0, t)
	var early_again := Formation.soldier_transform(curve, 1.0, 5, 40, "line", 1.0, t)

	assert_eq(early_first, early_again,
		"Sampling a past time gave a different answer the second time — Formation is stateful")


func test_two_independent_evaluators_agree() -> void:
	# Stands in for client vs server: the same inputs evaluated by two
	# callers that share nothing must produce identical output. This is
	# what lets D-006 network zero soldier positions.
	var t_server := TorusSpace.new(W, H, 1.0)
	var t_client := TorusSpace.new(W, H, 1.0)

	var server_curve := _march(t_server, Vector2i(7, 7), 5)
	# The client's copy arrives over the wire, so rebuild it that way.
	var client_curve := StateCurve.from_bytes(server_curve.to_bytes())

	for shape in SHAPES:
		var server_side := Formation.soldier_transforms(server_curve, 2.25, 24, shape, 1.0, t_server)
		var client_side := Formation.soldier_transforms(client_curve, 2.25, 24, shape, 1.0, t_client)
		assert_eq(server_side.size(), client_side.size())
		for i in range(server_side.size()):
			assert_almost_eq(server_side[i].origin.x, client_side[i].origin.x, 0.0001,
				"%s slot %d diverges between server and client in x" % [shape, i])
			assert_almost_eq(server_side[i].origin.z, client_side[i].origin.z, 0.0001,
				"%s slot %d diverges between server and client in z" % [shape, i])


func test_loose_scatter_is_hashed_not_random() -> void:
	# "loose" is the one shape with scatter, and the obvious
	# implementation — an RNG — would desync client from server.
	var t := _space()
	var curve := _march(t, Vector2i(5, 5), 4)

	var first := Formation.soldier_transforms(curve, 1.0, 40, "loose", 1.0, t)
	var second := Formation.soldier_transforms(curve, 1.0, 40, "loose", 1.0, t)
	for i in range(first.size()):
		assert_eq(first[i], second[i], "loose slot %d scattered differently on a second call" % i)

	# ...and the scatter must actually be doing something.
	var grid := Formation.soldier_transforms(curve, 1.0, 40, "line", 1.0, t)
	var any_different := false
	for i in range(first.size()):
		if not first[i].origin.is_equal_approx(grid[i].origin):
			any_different = true
			break
	assert_true(any_different, "loose formation should differ from line")


func test_facing_is_derived_from_the_curve_not_stored() -> void:
	var t := _space()
	var moving := _march(t, Vector2i(0, 5), 6)

	# While moving east, heading should point along +q.
	var h := Formation.heading(moving, 2.0)
	assert_gt(h.x, 0.5, "A squad marching +q should face +q")

	# After the march ends, facing is retained — derived by scanning back
	# through the curve rather than by storing it anywhere.
	var after := Formation.heading(moving, 99.0)
	assert_almost_eq(after.x, h.x, 0.0001, "A stopped squad should keep its arrival facing")


func test_stationary_squad_has_a_deterministic_default_facing() -> void:
	var t := _space()
	var parked := StateCurve.new()
	parked.append_cell(0.0, Vector2i(3, 3), t)

	var a := Formation.heading(parked, 0.0)
	var b := Formation.heading(parked, 50.0)
	assert_eq(a, b, "A never-moved squad must face a fixed direction, not an arbitrary one")
	assert_eq(a, Formation.DEFAULT_HEADING)


func test_terrain_sampler_is_the_only_source_of_height() -> void:
	var t := _space()
	var curve := _march(t, Vector2i(1, 1), 4)

	var flat := Formation.soldier_transforms(curve, 1.0, 12, "line", 1.0, t)
	for tr in flat:
		assert_almost_eq(tr.origin.y, 0.0, 0.0001, "Without a sampler, soldiers sit at y=0")

	var sloped := Formation.soldier_transforms(curve, 1.0, 12, "line", 1.0, t,
		func(x: float, _z: float) -> float: return x * 0.25)
	for i in range(sloped.size()):
		assert_almost_eq(sloped[i].origin.y, sloped[i].origin.x * 0.25, 0.0001,
			"Soldier %d should sit on the sampled terrain height" % i)


# --- clause 3: casualty restamp ---------------------------------------

func test_formation_restamps_when_a_soldier_dies() -> void:
	var t := _space()
	var curve := _march(t, Vector2i(6, 6), 4)

	var full := Formation.soldier_transforms(curve, 1.0, 40, "line", 1.0, t)
	var reduced := Formation.soldier_transforms(curve, 1.0, 39, "line", 1.0, t)

	assert_eq(full.size(), 40)
	assert_eq(reduced.size(), 39, "Losing a soldier should produce one fewer slot")

	# The restamp is the point: at least some surviving slots move,
	# because the formation is recomputed for the new count rather than
	# leaving a hole.
	var any_moved := false
	for i in range(reduced.size()):
		if not reduced[i].origin.is_equal_approx(full[i].origin):
			any_moved = true
			break
	assert_true(any_moved,
		"The formation should restamp for the new count, not leave a gap where the casualty was")


func test_casualty_restamp_is_deterministic() -> void:
	var t := _space()
	var curve := _march(t, Vector2i(6, 6), 4)
	for alive in [40, 39, 25, 7, 1]:
		var a := Formation.soldier_transforms(curve, 1.0, alive, "wedge", 1.0, t)
		var b := Formation.soldier_transforms(curve, 1.0, alive, "wedge", 1.0, t)
		assert_eq(a, b, "Restamp at alive=%d is not deterministic" % alive)


func test_slot_count_always_matches_alive_count() -> void:
	var t := _space()
	var curve := _march(t, Vector2i(0, 0), 3)
	for shape in SHAPES:
		for alive in [1, 2, 5, 17, 40, 120]:
			var transforms := Formation.soldier_transforms(curve, 0.5, alive, shape, 1.0, t)
			assert_eq(transforms.size(), alive,
				"%s at alive=%d produced %d transforms" % [shape, alive, transforms.size()])


func test_zero_or_negative_alive_produces_no_soldiers() -> void:
	var t := _space()
	var curve := _march(t, Vector2i(0, 0), 3)
	assert_eq(Formation.soldier_transforms(curve, 0.0, 0, "line", 1.0, t).size(), 0)
	assert_eq(Formation.soldier_transforms(curve, 0.0, -5, "line", 1.0, t).size(), 0)


# --- formation geometry sanity ---------------------------------------

func test_soldiers_do_not_share_a_position() -> void:
	# Overlapping slots would look like half the squad is missing.
	var t := _space()
	var curve := _march(t, Vector2i(8, 8), 3)
	for shape in SHAPES:
		var transforms := Formation.soldier_transforms(curve, 1.0, 40, shape, 1.0, t)
		var seen := {}
		for tr in transforms:
			var key := "%.3f,%.3f" % [tr.origin.x, tr.origin.z]
			assert_false(seen.has(key), "%s has two soldiers at %s" % [shape, key])
			seen[key] = true


func test_line_is_wider_and_shallower_than_column() -> void:
	# Guards against the two grid shapes silently collapsing into each
	# other, which would make formation_shape meaningless.
	#
	# Measured in formation-LOCAL space deliberately. In world space both
	# shapes are rotated to face travel, so comparing world x-extent
	# measures the width of one and the depth of the other and gives the
	# confidently wrong answer.
	assert_gt(_local_extent("line", 40).x, _local_extent("column", 40).x,
		"A line formation should present a wider front than a column")
	assert_gt(_local_extent("column", 40).y, _local_extent("line", 40).y,
		"A column should be deeper than a line")


## Width (x) and depth (y) of a formation in formation-local space.
func _local_extent(shape: String, alive: int) -> Vector2:
	var min_o := Vector2(INF, INF)
	var max_o := Vector2(-INF, -INF)
	for slot in range(alive):
		var o := Formation.slot_offset(shape, slot, alive, 1.0)
		min_o = Vector2(minf(min_o.x, o.x), minf(min_o.y, o.y))
		max_o = Vector2(maxf(max_o.x, o.x), maxf(max_o.y, o.y))
	return max_o - min_o


func test_crossing_a_seam_is_one_hex_of_travel_not_a_lap() -> void:
	var t := _space()
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(W - 1, 4), t)
	curve.append_cell(1.0, Vector2i(0, 4), t)

	# In continuous axial space — the space the curve actually integrates
	# in — the squad moved exactly one hex. This is the property that
	# matters, and the one a non-wrapping implementation gets wrong.
	var moved := curve.sample_axial(1.0) - curve.sample_axial(0.0)
	assert_almost_eq(moved.length(), 1.0, 0.0001,
		"Crossing the seam should be one hex of travel, not a lap of the map")


func test_world_positions_wrap_into_the_map_rectangle_at_the_seam() -> void:
	# World coordinates DO jump when the seam is crossed, and that is
	# correct: the torus is presented as a bounded rectangle, so leaving
	# the east edge means re-entering at the west. Asserting continuity
	# here would be asserting the map is infinite.
	#
	# The practical consequence is for the renderer, not the sim: drawing
	# a squad that straddles a seam needs ghost copies either side rather
	# than one continuous position. That is D-008's tax landing on the
	# client, and it is why this is called out rather than hidden.
	var t := _space()
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(W - 1, 4), t)
	curve.append_cell(1.0, Vector2i(0, 4), t)

	var before := curve.sample_world(0.0, t)
	var after := curve.sample_world(1.0, t)
	assert_gt(before.x, after.x, "Crossing the east seam should re-enter at the west")

	var max_x := t.hex_size * TorusSpace.SQRT_3 * (float(W) + float(H) * 0.5)
	for p in [before, after]:
		assert_between(p.x, 0.0, max_x, "Sampled world position escaped the map rectangle")


func test_formation_geometry_does_not_undo_seam_handling() -> void:
	# Soldier offsets are applied around the squad centre, so whatever the
	# centre does at a seam, the squad should do together — no soldier
	# should end up displaced from its neighbours by a map-sized jump.
	var t := _space()
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(W - 1, 4), t)
	curve.append_cell(1.0, Vector2i(0, 4), t)

	for at in [0.0, 1.0]:
		var transforms := Formation.soldier_transforms(curve, at, 8, "line", 1.0, t)
		var centre := curve.sample_world(at, t)
		for i in range(transforms.size()):
			assert_lt(transforms[i].origin.distance_to(centre), 8.0 * t.hex_size,
				"Soldier %d is detached from its squad centre at t=%f" % [i, at])


# --- clause 2: cosmetic offsets are one-way ---------------------------

func test_cosmetic_offsets_do_not_change_authoritative_transforms() -> void:
	var t := _space()
	var curve := _march(t, Vector2i(3, 3), 5)

	var authoritative := Formation.soldier_transforms(curve, 2.0, 20, "line", 1.0, t)
	var snapshot := authoritative.duplicate()

	var _decorated := CosmeticOffset.decorate_all(authoritative, 2.0, 1.0)

	assert_eq(authoritative, snapshot,
		"decorate_all mutated the authoritative transforms — clause 2 requires one-way decoration")


func test_cosmetic_decoration_actually_moves_the_render_transform() -> void:
	var t := _space()
	var curve := _march(t, Vector2i(3, 3), 5)
	var authoritative := Formation.soldier_transforms(curve, 2.0, 20, "line", 1.0, t)
	var decorated := CosmeticOffset.decorate_all(authoritative, 2.0, 1.0)

	var any_moved := false
	for i in range(authoritative.size()):
		if not authoritative[i].origin.is_equal_approx(decorated[i].origin):
			any_moved = true
			break
	assert_true(any_moved, "Cosmetic decoration should visibly move soldiers")


func test_authoritative_positions_are_independent_of_cosmetic_time() -> void:
	# If sim ever read cosmetic offsets back, authoritative positions
	# would start varying with render time. They must not.
	var t := _space()
	var curve := _march(t, Vector2i(3, 3), 5)

	var at_sim_time := Formation.soldier_transforms(curve, 2.0, 20, "line", 1.0, t)
	for render_time in [0.0, 1.7, 55.5]:
		var _ignored := CosmeticOffset.decorate_all(at_sim_time, render_time, 1.0)
		var recomputed := Formation.soldier_transforms(curve, 2.0, 20, "line", 1.0, t)
		assert_eq(recomputed, at_sim_time,
			"Authoritative transforms changed after decorating at render time %f" % render_time)


func test_stationary_squads_do_not_bob() -> void:
	assert_eq(CosmeticOffset.footfall_bob(3, 1.0, 0.0), 0.0,
		"A stationary soldier should not have a footfall bob")
	assert_gt(CosmeticOffset.footfall_bob(3, 1.0, 1.0), 0.0,
		"A moving soldier should bob")


func test_bulk_derivation_matches_the_single_soldier_path() -> void:
	# soldier_transforms() hoists the squad-wide parts of
	# soldier_transform() out of its loop, for a ~3x saving on a path that
	# runs every frame for every soldier on screen.
	#
	# The two MUST agree exactly. The client derives in bulk and anything
	# checking one soldier derives singly, so a divergence here is a
	# client and a server disagreeing about where a man is standing —
	# precisely the failure D-006's purity clause exists to prevent, and
	# one no bandwidth measurement would ever notice.
	var space := TorusSpace.new(32, 16, 1.0)
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(2, 3), space)
	curve.append_cell(1.0, Vector2i(9, 7), space)
	curve.append_cell(2.0, Vector2i(20, 12), space)

	for shape in ["line", "column", "wedge", "loose"]:
		for alive in [1, 7, 12, 40]:
			for t in [0.0, 0.35, 1.4, 2.0]:
				var bulk := Formation.soldier_transforms(
					curve, t, alive, shape, 1.0, space)
				assert_eq(bulk.size(), alive,
					"%s/%d at t=%.2f produced %d transforms" % [shape, alive, t, bulk.size()])
				for slot in range(alive):
					var single := Formation.soldier_transform(
						curve, t, slot, alive, shape, 1.0, space, 0.0)
					assert_eq(bulk[slot], single,
						"%s slot %d of %d at t=%.2f differs between bulk and single derivation" % [
							shape, slot, alive, t])


func test_bulk_derivation_applies_the_terrain_sampler_per_soldier() -> void:
	# The sampler is D-006's fourth input and takes the SOLDIER's position,
	# not the squad's — hoisting the squad-wide work must not accidentally
	# hoist this too, which would flatten a formation onto one height.
	var space := TorusSpace.new(32, 16, 1.0)
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(4, 4), space)
	curve.append_cell(1.0, Vector2i(14, 9), space)

	var sampler := func(x: float, z: float) -> float: return x * 0.25 + z * 0.5
	var bulk := Formation.soldier_transforms(curve, 0.4, 12, "line", 1.0, space, sampler)

	var heights := {}
	for t in bulk:
		assert_almost_eq(t.origin.y, t.origin.x * 0.25 + t.origin.z * 0.5, 0.0001,
			"A soldier's height should come from ITS OWN position")
		heights[snappedf(t.origin.y, 0.001)] = true
	assert_gt(heights.size(), 1,
		"Every soldier got the same height — the sampler was hoisted out of the loop")


# --- footprint (selection, D-057) --------------------------------------

func test_a_squads_footprint_covers_every_soldier_in_it() -> void:
	# Selection tested the squad's CURVE position against a fixed pixel
	# radius, so on a wide formation clicking a soldier you could plainly
	# see selected nothing — the hit test was aimed at one point inside a
	# body many metres across. Reported from a real game as selection
	# being based on one man rather than the squad.
	for shape in ["line", "column", "wedge", "loose"]:
		var alive := 40
		var spacing := 1.2
		var print := Formation.footprint(shape, alive, spacing)
		var centre: Vector2 = print["centre"]
		var radius: float = print["radius"]

		for slot in range(alive):
			var at := Formation.slot_offset(shape, slot, alive, spacing)
			assert_lte(at.distance_to(centre), radius,
				"%s: soldier %d sits outside the squad's own footprint" % [shape, slot])


func test_the_footprint_is_centred_on_the_body_not_the_curve_point() -> void:
	# A line puts rank r at -r * spacing, so the curve point is at the
	# FRONT rank and the troops extend behind it. A marker drawn at the
	# curve point is visibly offset from the squad it marks — which is
	# exactly how the first selection ring looked.
	var print := Formation.footprint("line", 40, 1.2)
	var centre: Vector2 = print["centre"]
	assert_lt(centre.y, -0.1,
		"a line formation's body sits behind its curve point, so the footprint "
		+ "centre must too — otherwise the marker floats off the front rank")


func test_the_footprint_grows_with_the_squad() -> void:
	# The other side: a radius that ignored headcount would be wrong for
	# either a big squad or a small one, and "big target for a big
	# formation" is the whole point of using it for hit-testing.
	var small := Formation.footprint("line", 6, 1.2)
	var large := Formation.footprint("line", 60, 1.2)
	assert_gt(float(large["radius"]), float(small["radius"]),
		"a sixty-man formation should present a bigger target than a six-man one")
