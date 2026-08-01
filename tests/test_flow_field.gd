extends GutTest

## Guards D-007 (flow field per destination, not per-unit A*) and the
## part of D-008 that bites hardest in pathfinding: a squad must take the
## short way across a seam.
##
## The failure this is written against is subtle — a flow field built on
## a non-wrapping grid still produces perfectly valid-looking paths. It
## just routes squads the long way around the map. So the seam tests
## assert path LENGTH against the wrapped distance, which is the only
## thing that distinguishes the two.

const W := 16
const H := 12


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _field(dest: Vector2i, passable := PackedByteArray()) -> FlowField:
	var f := FlowField.new()
	f.build(_space(), dest, passable)
	return f


# --- basic correctness -----------------------------------------------

func test_destination_has_zero_distance_and_no_direction() -> void:
	var t := _space()
	var dest := Vector2i(5, 5)
	var f := _field(dest)
	assert_eq(f.distance_at(t.index(dest)), 0)
	assert_eq(f.direction_at(t.index(dest)), FlowField.NO_DIRECTION,
		"The destination itself should have no onward direction")


func test_every_cell_is_reachable_on_an_open_map() -> void:
	var t := _space()
	var f := _field(Vector2i(3, 7))
	for i in range(t.cell_count()):
		assert_true(f.is_reachable(i), "Cell %d should be reachable on an open torus" % i)


func test_field_distance_matches_torus_distance_everywhere() -> void:
	# On an open map with uniform cost, the BFS distance must equal the
	# analytic wrapped hex distance. This is the strongest single check
	# that the expansion is wrap-aware: any non-wrapping expansion
	# produces larger distances near the seams.
	var t := _space()
	var dest := Vector2i(2, 2)
	var f := _field(dest)
	for i in range(t.cell_count()):
		var expected := t.distance(t.from_index(i), dest)
		assert_eq(f.distance_at(i), expected,
			"Field distance at %s should match torus distance %d" % [t.from_index(i), expected])


func test_following_the_field_strictly_decreases_distance() -> void:
	var t := _space()
	var f := _field(Vector2i(9, 4))
	for i in range(t.cell_count()):
		if i == f.destination:
			continue
		var next := f.step_from(i)
		assert_eq(f.distance_at(next), f.distance_at(i) - 1,
			"Stepping from cell %d should reduce distance by exactly 1" % i)


func test_path_terminates_at_the_destination_from_every_cell() -> void:
	var t := _space()
	var dest := Vector2i(11, 8)
	var f := _field(dest)
	for i in range(t.cell_count()):
		var path := f.path_from(i)
		assert_gt(path.size(), 0, "Path from %d should not be empty" % i)
		assert_eq(path[path.size() - 1], t.index(dest),
			"Path from cell %d should end at the destination" % i)
		assert_eq(path.size() - 1, t.distance(t.from_index(i), dest),
			"Path from cell %d should be exactly the wrapped distance long" % i)


# --- the seam --------------------------------------------------------

func test_path_across_the_horizontal_seam_takes_the_short_way() -> void:
	var t := _space()
	# Destination one step east of the seam, squad one step west of it.
	var dest := Vector2i(0, 6)
	var start := Vector2i(W - 1, 6)
	var f := _field(dest)

	assert_eq(f.distance_at(t.index(start)), 1,
		"Across the seam should be one step, not %d" % (W - 1))
	var path := f.path_from(t.index(start))
	assert_eq(path.size(), 2, "Path across the seam should be start + destination only")


func test_path_across_the_vertical_seam_takes_the_short_way() -> void:
	var t := _space()
	var dest := Vector2i(7, 0)
	var start := Vector2i(7, H - 1)
	var f := _field(dest)

	assert_eq(f.distance_at(t.index(start)), 1,
		"Across the vertical seam should be one step")
	assert_eq(f.path_from(t.index(start)).size(), 2)


func test_longest_path_respects_the_wrapped_bound() -> void:
	# A non-wrapping field would produce paths up to W+H long. A wrapped
	# one cannot exceed roughly half that.
	var t := _space()
	var f := _field(Vector2i(0, 0))
	var bound := (W / 2) + (H / 2)
	for i in range(t.cell_count()):
		assert_lte(f.distance_at(i), bound,
			"Distance at cell %s exceeds the wrapped bound %d — field is not wrap-aware" % [t.from_index(i), bound])


# --- obstacles -------------------------------------------------------

func _all_passable(t: TorusSpace) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(t.cell_count())
	p.fill(1)
	return p


func test_impassable_cells_are_unreachable_and_routed_around() -> void:
	var t := _space()
	var passable := _all_passable(t)

	# Wall off column 8 entirely, except leave the torus's other side open
	# — so the field must route around the long way rather than through.
	for r in range(H):
		passable[t.index(Vector2i(8, r))] = 0

	var f := _field(Vector2i(10, 5), passable)

	for r in range(H):
		assert_false(f.is_reachable(t.index(Vector2i(8, r))),
			"Walled cell (8,%d) should be unreachable" % r)

	# A cell just west of the wall must still be reachable, by going the
	# other way around the torus.
	var west_of_wall := t.index(Vector2i(7, 5))
	assert_true(f.is_reachable(west_of_wall),
		"A cell west of a full-height wall should still reach the destination around the torus")
	# Direct route would be 3 steps; around the torus is much further.
	assert_gt(f.distance_at(west_of_wall), 3,
		"Routing around the wall should cost more than the blocked direct path")


func test_fully_enclosed_destination_yields_no_reachable_cells() -> void:
	var t := _space()
	var passable := _all_passable(t)
	var dest := Vector2i(4, 4)

	for n in t.neighbors(dest):
		passable[t.index(n)] = 0

	var f := _field(dest, passable)
	assert_eq(f.distance_at(t.index(dest)), 0, "The destination itself is still trivially reachable")
	assert_false(f.is_reachable(t.index(Vector2i(0, 0))),
		"A walled-in destination should leave the rest of the map unreachable")


func test_impassable_destination_produces_an_empty_field_not_a_crash() -> void:
	var t := _space()
	var passable := _all_passable(t)
	var dest := Vector2i(6, 6)
	passable[t.index(dest)] = 0

	var f := _field(dest, passable)
	assert_false(f.is_reachable(t.index(Vector2i(0, 0))),
		"An impassable destination should yield a fully unreachable field")
	assert_eq(f.path_from(t.index(Vector2i(0, 0))).size(), 0,
		"path_from should return empty rather than looping when unreachable")


func test_unreachable_cell_stalls_in_place_rather_than_walking_off() -> void:
	var t := _space()
	var passable := _all_passable(t)
	var dest := Vector2i(4, 4)
	for n in t.neighbors(dest):
		passable[t.index(n)] = 0

	var f := _field(dest, passable)
	var stranded := t.index(Vector2i(0, 0))
	assert_eq(f.step_from(stranded), stranded,
		"Stepping from an unreachable cell should stall in place, not move somewhere arbitrary")


# --- D-007's actual claim --------------------------------------------

func test_one_field_serves_many_squads() -> void:
	# D-007's scaling claim is that cost is per DESTINATION, not per
	# squad. Asserted structurally: many start cells, one build, and
	# every one of them gets a correct path out of the same field.
	var t := _space()
	var dest := Vector2i(1, 1)
	var f := _field(dest)

	var starts := [
		Vector2i(15, 11), Vector2i(0, 0), Vector2i(8, 6),
		Vector2i(15, 0), Vector2i(0, 11), Vector2i(4, 9),
	]
	for s in starts:
		var path := f.path_from(t.index(s))
		assert_eq(path[path.size() - 1], t.index(dest),
			"Squad starting at %s should reach the shared destination" % s)
		assert_eq(path.size() - 1, t.distance(s, dest),
			"Squad starting at %s should take the wrapped-shortest path" % s)


# --- amortised (incremental) building, D-040 --------------------------

func test_a_partial_field_is_correct_wherever_it_is_defined() -> void:
	# The property the whole amortisation rests on: BFS gives a cell its
	# final distance the first time it reaches it, so a half-built field
	# is not an approximation to be corrected later — it is a complete
	# answer over a smaller region.
	#
	# If this were false, squads would path on numbers that changed under
	# them and the bug would look like intermittent bad pathing rather
	# than anything to do with budgeting.
	var t := _space()
	var dest := Vector2i(5, 5)
	var complete := _field(dest)

	var partial := FlowField.new()
	partial.begin(t, dest)
	assert_false(partial.expand(20), "20 cells should not finish a %d-cell map" % t.cell_count())

	var covered := 0
	for cell in range(t.cell_count()):
		if not partial.covers(cell):
			continue
		covered += 1
		assert_eq(partial.distance_at(cell), complete.distance_at(cell),
			"Cell %d has a different distance mid-build than when finished" % cell)
		assert_eq(partial.direction_at(cell), complete.direction_at(cell),
			"Cell %d points somewhere different mid-build than when finished" % cell)

	assert_gt(covered, 0, "Nothing was covered, so the comparison above proves nothing")
	assert_lt(covered, t.cell_count(), "The field finished, so this was not a partial build at all")


func test_expanding_to_completion_matches_a_one_shot_build() -> void:
	# Amortisation must not change the answer, only when it arrives.
	var t := _space()
	var dest := Vector2i(3, 8)
	var passable := _all_passable(t)
	passable[t.index(Vector2i(4, 8))] = 0
	passable[t.index(Vector2i(4, 7))] = 0
	passable[t.index(Vector2i(4, 9))] = 0

	var complete := _field(dest, passable)

	var stepped := FlowField.new()
	stepped.begin(t, dest, passable)
	var rounds := 0
	while not stepped.expand(7):
		rounds += 1
		assert_lt(rounds, 1000, "Incremental expansion never finished")
	assert_gt(rounds, 1, "The budget was so generous this did not actually amortise")

	for cell in range(t.cell_count()):
		assert_eq(stepped.distance_at(cell), complete.distance_at(cell),
			"Cell %d disagrees after incremental expansion" % cell)
		assert_eq(stepped.direction_at(cell), complete.direction_at(cell),
			"Cell %d points elsewhere after incremental expansion" % cell)


func test_an_unfinished_field_does_not_claim_a_cell_is_unreachable() -> void:
	# The one way a caller can misread a partial field: UNREACHABLE means
	# "not yet" mid-build and "no path" once complete. Reading the first
	# as the second cancels perfectly good orders.
	var t := _space()
	var partial := FlowField.new()
	partial.begin(t, Vector2i(0, 0))
	partial.expand(3)

	assert_false(partial.is_complete(), "This test needs an unfinished field")
	var far := t.index(Vector2i(8, 6))
	assert_false(partial.covers(far), "The far corner should not be reached after 3 cells")
	assert_false(partial.is_reachable(far),
		"is_reachable is about coverage, so it is false here — and callers must check is_complete")


func test_a_blocked_destination_is_complete_immediately() -> void:
	# There is nothing to expand, so a caller budgeting work must not be
	# left waiting on a field that will never progress.
	var t := _space()
	var passable := _all_passable(t)
	var dest := Vector2i(2, 2)
	passable[t.index(dest)] = 0

	var f := FlowField.new()
	f.begin(t, dest, passable)
	assert_true(f.is_complete(), "A field with a blocked destination has no frontier to expand")
	assert_eq(f.pending_cells(), 0)
