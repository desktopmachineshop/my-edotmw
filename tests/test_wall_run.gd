extends GutTest

## Guards D-096 — continuous wall placement and the rasterised occupancy
## that keeps it honest.
##
## The headline test here is `test_a_run_at_an_arbitrary_angle_leaves_no_gap`.
## D-096 names one failure mode it must not have: a wall that LOOKS solid
## and has a hole units walk through. That cannot be caught by looking at a
## picture (the mesh is continuous either way) and it cannot be caught by
## counting buildings (the right number exist). It only shows up as a cell
## along the run that nothing blocks, which is exactly what this asserts.

const W := 64
const H := 32


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _wall() -> BuildingDef:
	return BuildingSim.def_by_id(&"wall")


# --- laying a run ------------------------------------------------------

func test_a_click_rather_than_a_drag_places_one_segment_where_it_was_put() -> void:
	# The case that makes a SINGLE wall freely placed. Before D-096 this
	# snapped back to its cell's centre, which is what read as "walls are
	# still locked to tiles".
	var space := _space()
	var at := space.to_world(Vector2i(10, 8)) + Vector3(0.4, 0.0, -0.3)
	var run := WallRun.segments(space, _wall(), at, at)

	assert_eq(run.size(), 1, "a click should lay exactly one segment")
	var offset: Vector2 = run[0]["offset"]
	assert_gt(offset.length(), 0.1,
		"the segment must stand where it was clicked, not at its cell's centre")


func test_a_dragged_run_lays_segments_along_the_whole_line() -> void:
	var space := _space()
	var from := space.to_world(Vector2i(6, 8))
	var to := space.to_world(Vector2i(16, 8))
	var run := WallRun.segments(space, _wall(), from, to)

	var expected := int(round((to - from).length() / _wall().mesh_size.x))
	assert_eq(run.size(), expected,
		"a run should hold as many segments as its length divided by the segment length")
	assert_gt(run.size(), 5, "setup: this run should be long enough to be interesting")


func test_consecutive_segments_are_exactly_one_segment_apart() -> void:
	# Reported from play as segments "spaced rather than fixed spacing".
	# The run used to spread its segments evenly across the dragged length,
	# so the spacing was `length / count` — equal to a segment length only
	# when the drag divided evenly, and slightly stretched every other time.
	#
	# Swept across many lengths, deliberately including ones that divide
	# badly: the old behaviour was CORRECT for a run that happened to
	# divide evenly, so a single well-chosen length would have passed.
	var space := _space()
	var def := _wall()
	var from := space.to_world(Vector2i(8, 8))
	var direction := Vector3(0.77, 0.0, -0.64).normalized()

	for tenths in range(25, 90):
		var length := float(tenths) * 0.4
		var run := WallRun.segments(space, def, from, from + direction * length)
		for i in range(1, run.size()):
			var a := space.to_world(run[i - 1]["cell"]) \
				+ Vector3(run[i - 1]["offset"].x, 0.0, run[i - 1]["offset"].y)
			var b := space.to_world(run[i]["cell"]) \
				+ Vector3(run[i]["offset"].x, 0.0, run[i]["offset"].y)
			var gap := WallRun.shortest_delta(space, a, b)
			gap.y = 0.0
			assert_almost_eq(gap.length(), def.mesh_size.x, 0.02,
				"length %.1f: segments %d and %d are not one segment apart" % [length, i - 1, i])


func test_a_run_always_covers_the_line_that_was_drawn() -> void:
	# The other half of the spacing rule: fixed spacing means the run ends
	# where the arithmetic puts it, not where the mouse came up, so it must
	# round UP. Rounding down would leave the last stretch of the drag with
	# no wall on it — a hole exactly where the player last aimed.
	var space := _space()
	var def := _wall()
	var from := space.to_world(Vector2i(8, 8))
	var direction := Vector3(0.31, 0.0, -0.95).normalized()

	for tenths in range(25, 90):
		var length := float(tenths) * 0.4
		var run := WallRun.segments(space, def, from, from + direction * length)
		assert_gte(float(run.size()) * def.mesh_size.x, length - 0.02,
			"length %.1f: the run is shorter than the line drawn" % length)


func test_every_segment_of_a_run_shares_the_runs_angle() -> void:
	var space := _space()
	var run := WallRun.segments(space, _wall(),
		space.to_world(Vector2i(6, 6)), space.to_world(Vector2i(15, 12)))

	assert_gt(run.size(), 1, "setup: needs several segments")
	var first := int(run[0]["facing"])
	for segment in run:
		assert_eq(int(segment["facing"]), first,
			"a straight run must not kink — every segment carries the line's own angle")


func test_the_angle_is_not_snapped_to_one_of_six_directions() -> void:
	# The other half of the original complaint. Six hex directions are
	# multiples of 256/6 ~= 42.67 in byte space; an arbitrary line should
	# generally land somewhere else entirely.
	var space := _space()
	var run := WallRun.segments(space, _wall(),
		space.to_world(Vector2i(6, 6)), space.to_world(Vector2i(19, 11)))
	var facing := int(run[0]["facing"])

	var nearest_sixth: float = round(float(facing) / (256.0 / 6.0)) * (256.0 / 6.0)
	assert_gt(absf(float(facing) - nearest_sixth), 2.0,
		"this line's angle should not coincidentally be one of the six hex directions")


# --- the one that matters ---------------------------------------------

func test_a_run_at_an_arbitrary_angle_leaves_no_gap() -> void:
	# D-096's named failure mode. Build the run the client would send, then
	# walk the line the player actually drew and demand that EVERY cell it
	# passes through is blocked by something.
	var space := _space()
	var buildings := BuildingSim.new(space)
	var def := _wall()

	var from := space.to_world(Vector2i(8, 6))
	var to := space.to_world(Vector2i(23, 15))
	for segment in WallRun.segments(space, def, from, to):
		var id := buildings.add_building(def, 1, segment["cell"], true, -1,
			int(segment["facing"]), segment["offset"])
		assert_true(id >= 0, "setup: every segment should have been added")

	var blocked := {}
	for index in buildings.blocking_cells():
		blocked[index] = true

	# Walk the drawn line densely — much finer than a cell — and require
	# cover the whole way. Sampling the line rather than the segments is
	# deliberate: it asks the player's question ("can anything get through
	# where I drew a wall?") rather than the implementation's.
	#
	# The SHORTEST delta, not the raw difference. This test's first version
	# used `to - from` and failed against a perfectly good implementation,
	# because a run is laid along the wrap-aware short way (D-008) and on
	# this map these endpoints wrap: it was walking one line and blocking
	# another. A wrap tax paid in the wrong place looks exactly like a
	# gameplay bug.
	var delta := WallRun.shortest_delta(space, from, to)
	delta.y = 0.0
	var steps := int(delta.length() / (space.hex_size * 0.1))
	var missing := []
	for i in range(steps + 1):
		var point := from + delta * (float(i) / float(steps))
		var index := space.index(space.world_to_cell(point))
		if not blocked.has(index) and not missing.has(index):
			missing.append(index)

	assert_eq(missing.size(), 0,
		"cells along the drawn run that nothing blocks — a hole to walk through: %s" % [missing])


func test_a_completed_run_blocks_more_cells_than_it_has_segments() -> void:
	# A segment is longer than a hex is wide, so an angled run must cover
	# more cells than it has pieces. If this ever came out equal it would
	# mean occupancy had quietly gone back to one-cell-per-building and the
	# gap test above was passing for the wrong reason.
	var space := _space()
	var buildings := BuildingSim.new(space)
	var def := _wall()
	var run := WallRun.segments(space, def,
		space.to_world(Vector2i(8, 6)), space.to_world(Vector2i(23, 15)))
	for segment in run:
		buildings.add_building(def, 1, segment["cell"], true, -1,
			int(segment["facing"]), segment["offset"])

	var distinct := {}
	for index in buildings.blocking_cells():
		distinct[index] = true
	assert_gt(distinct.size(), run.size(),
		"an angled run should cover more cells than it has segments")


# --- placing walls one click at a time ---------------------------------
#
# Reported three times from play as "angled walls are still broken", and
# guessed at twice from screenshots before this existed. The snap decision
# used to live in client.gd where nothing headless could reach it; these
# assert the thing the player actually does.

const SNAP := 2.2


func _walls_from(entries: Array, def: BuildingDef, space: TorusSpace) -> Array:
	# The same shape client.gd's `_existing_wall_segments` builds, so these
	# tests exercise the real input rather than an idealised one.
	var out := []
	for e in entries:
		out.append({
			"pos": space.to_world(e["cell"]) + Vector3(e["offset"].x, 0.0, e["offset"].y),
			"angle": PlacementJitter.radians_of_byte(int(e["facing"])),
			"length": def.mesh_size.x,
		})
	return out


func test_a_second_wall_clicked_beyond_the_first_continues_it_exactly() -> void:
	var space := _space()
	var def := _wall()

	# One wall running east, placed on open ground.
	var first := WallRun.place_single(space, def, [], space.to_world(Vector2i(10, 8)), 0, SNAP)
	assert_false(bool(first["snapped"]), "setup: nothing to snap to yet")

	# Now click a bit further east — roughly where a player reaching along
	# the run would put the cursor.
	var walls := _walls_from([first], def, space)
	var first_pos: Vector3 = walls[0]["pos"]
	var cursor := first_pos + Vector3(def.mesh_size.x * 0.9, 0.0, 0.0)
	var second := WallRun.place_single(space, def, walls, cursor, -1, SNAP)

	assert_true(bool(second["snapped"]), "the second wall should have snapped to the first")
	assert_eq(int(second["facing"]), int(first["facing"]),
		"a wall snapped to a run must CONTINUE it, not point somewhere else")

	# And it must sit exactly one segment along, so the two meet end to end
	# rather than overlapping or leaving a gap.
	var second_pos := space.to_world(second["cell"]) \
		+ Vector3(second["offset"].x, 0.0, second["offset"].y)
	var gap := WallRun.shortest_delta(space, first_pos, second_pos)
	gap.y = 0.0
	assert_almost_eq(gap.length(), def.mesh_size.x, 0.05,
		"consecutive walls should sit exactly one segment length apart")
	assert_almost_eq(absf(gap.z), 0.0, 0.05,
		"a wall continuing an east-west run must not drift sideways — that is the staircase")


func test_clicking_along_a_diagonal_builds_a_straight_wall_not_a_staircase() -> void:
	# THE reported failure. Walk a cursor along a diagonal, clicking each
	# time, exactly as a player laying a wall by hand does. Every segment
	# must come out collinear with the first — a staircase means each one
	# ignored the run it attached to.
	var space := _space()
	var def := _wall()
	var direction := Vector3(0.83, 0.0, -0.56).normalized()  # a genuinely odd angle
	var start := space.to_world(Vector2i(12, 10))

	var placed := [WallRun.place_single(space, def, [], start,
		PlacementJitter.byte_of_radians(atan2(-direction.z, direction.x)), SNAP)]
	var facing := int(placed[0]["facing"])

	for step in range(1, 6):
		var walls := _walls_from(placed, def, space)
		# Deliberately imprecise, like a real cursor: aim a bit past where
		# the next segment belongs rather than exactly on it.
		var cursor := start + direction * (def.mesh_size.x * (float(step) + 0.35))
		placed.append(WallRun.place_single(space, def, walls, cursor, -1, SNAP))

	for i in range(placed.size()):
		assert_eq(int(placed[i]["facing"]), facing,
			"segment %d turned away from the run — this is the staircase" % i)

	# Collinear: every centre must lie on the line the first one defines.
	var first_pos := space.to_world(placed[0]["cell"]) \
		+ Vector3(placed[0]["offset"].x, 0.0, placed[0]["offset"].y)
	for i in range(1, placed.size()):
		var pos := space.to_world(placed[i]["cell"]) \
			+ Vector3(placed[i]["offset"].x, 0.0, placed[i]["offset"].y)
		var delta := WallRun.shortest_delta(space, first_pos, pos)
		delta.y = 0.0
		var sideways := absf(delta.x * -direction.z + delta.z * direction.x)
		assert_lt(sideways, 0.25,
			"segment %d sits %.2f off the run's own line" % [i, sideways])


func test_a_wall_snapped_to_a_run_never_lies_back_on_top_of_it() -> void:
	var space := _space()
	var def := _wall()
	var first := WallRun.place_single(space, def, [], space.to_world(Vector2i(10, 8)), 0, SNAP)
	var walls := _walls_from([first], def, space)
	var first_pos: Vector3 = walls[0]["pos"]

	# Reaching WEST this time: the new wall must extend west, not double
	# back east over the wall it attached to.
	var cursor := first_pos - Vector3(def.mesh_size.x * 0.9, 0.0, 0.0)
	var second := WallRun.place_single(space, def, walls, cursor, -1, SNAP)
	var second_pos := space.to_world(second["cell"]) \
		+ Vector3(second["offset"].x, 0.0, second["offset"].y)
	var delta := WallRun.shortest_delta(space, first_pos, second_pos)
	assert_lt(delta.x, -0.5, "the new wall should have extended toward the cursor, not over the old one")


# --- the facing byte survives the wire ---------------------------------

func test_every_facing_byte_survives_a_build_order_round_trip() -> void:
	# The bug this exists for: `facing` was written with `put_8`, a SIGNED
	# byte, so anything from 128 up came back as a negative — half of every
	# possible angle. One call site compensated by folding values negative
	# before sending and the other did not, so a wall previewed at one angle
	# and built at another, seemingly at random. Reported from play as walls
	# not following their footprint.
	#
	# Every value, not a sample: the failure was confined to exactly half the
	# range, which a spot check of a few small numbers would sail straight
	# past.
	for facing in range(256):
		var packet := NetProtocol.encode_order_build(7, "wall", 42, facing, Vector2(0.25, -0.5))
		var decoded := NetProtocol.decode_order_build(packet)
		assert_eq(int(decoded["facing"]), facing,
			"facing %d did not survive the wire" % facing)


func test_the_queue_variant_encodes_facing_the_same_way() -> void:
	# The drag path sends one ORDER_BUILD then ORDER_BUILD_QUEUE for every
	# further segment. If the two disagreed about the encoding, a run would
	# build with its first segment straight and the rest skewed.
	for facing in [0, 1, 127, 128, 200, 255]:
		var first := NetProtocol.decode_order_build(
			NetProtocol.encode_order_build(7, "wall", 42, facing))
		var rest := NetProtocol.decode_order_build(
			NetProtocol.encode_order_build_queue(7, "wall", 42, facing))
		assert_eq(int(rest["facing"]), int(first["facing"]),
			"the queue variant encoded facing %d differently from the first order" % facing)


func test_the_sub_cell_offset_survives_the_wire() -> void:
	var packet := NetProtocol.encode_order_build(3, "wall", 9, 64, Vector2(0.4, -0.75))
	var decoded := NetProtocol.decode_order_build(packet)
	assert_almost_eq(float(decoded["offset_x"]), 0.4, 0.001)
	assert_almost_eq(float(decoded["offset_z"]), -0.75, 0.001)


# --- the pose reaches the CLIENT, not just the wire ---------------------

func test_a_walls_pose_survives_all_the_way_into_client_state() -> void:
	# The bug this exists for, and the reason it tests ClientState rather
	# than NetProtocol: the wire was carrying `facing` and the sub-cell
	# offset correctly the whole time, and `ClientState` — which rebuilds
	# its building dictionary field by field — simply never copied them
	# across. The renderer then read its defaults (facing 0, offset zero)
	# for every building ever built.
	#
	# The visible result was walls standing at their cell CENTRES, which
	# along a diagonal is a staircase, while the placement ghost looked
	# perfect because it never crosses the wire. Encoder-and-decoder tests
	# all passed. Only a test that ends where the RENDERER reads can catch
	# this, so this one deliberately goes one step further than the wire.
	var space := TorusSpace.new(W, H, 1.0)
	var buildings := BuildingSim.new(space)
	var def := _wall()
	var cell := Vector2i(9, 7)
	var offset := Vector2(0.42, -0.31)
	var id := buildings.add_building(def, 1, cell, true, -1, 200, offset)

	var state := ClientState.new()
	state.space = space
	state.player = 1
	# `info_entries` takes LOCAL ids and emits wire ids — see its own doc.
	state._handle_building_info(
		NetProtocol.encode_building_info(buildings.info_entries([id])))

	var info: Dictionary = state.buildings[buildings.wire_id(id)]
	assert_eq(int(info.get("facing", -1)), 200,
		"facing never reached ClientState — every wall would draw at angle 0")
	assert_almost_eq(float(info.get("offset_x", 0.0)), offset.x, 0.01,
		"the sub-cell offset never reached ClientState — walls would sit at cell centres")
	assert_almost_eq(float(info.get("offset_z", 0.0)), offset.y, 0.01,
		"the sub-cell offset never reached ClientState — walls would sit at cell centres")


# --- wrap-awareness (D-008's standing tax) -----------------------------

func test_a_run_across_the_seam_does_not_span_the_whole_map() -> void:
	var space := _space()
	# Two points a few cells apart, but on opposite sides of the wrap.
	var from := space.to_world(Vector2i(W - 2, 8))
	var to := space.to_world(Vector2i(2, 8))
	var run := WallRun.segments(space, _wall(), from, to)

	assert_lt(run.size(), 8,
		"a seam-crossing run took the long way round the world instead of the short way")
	assert_gt(run.size(), 1, "setup: it should still be a real run of several segments")


func test_offsets_stay_sub_cell_even_across_the_seam() -> void:
	var space := _space()
	var run := WallRun.segments(space, _wall(),
		space.to_world(Vector2i(W - 3, 8)), space.to_world(Vector2i(3, 8)))
	for segment in run:
		var offset: Vector2 = segment["offset"]
		assert_lt(offset.length(), space.hex_size * TorusSpace.SQRT_3,
			"an offset larger than a cell means the seam was measured through, not across")
