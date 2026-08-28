extends GutTest

## Guards #337's geometry: WHERE a wall goes.
##
## `static_defence.gd` decides whether to fortify and is shared with naval
## stage 7; this is the half that knows what a wall is. All-static and
## pure, so the part with the interesting failure mode — a screen laid
## across the seam, a wall that walls its owner in — is testable without a
## server.

const W := 48
const H := 24


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


# --- a screen faces the threat -----------------------------------------


func test_a_screen_stands_between_home_and_the_threat() -> void:
	var space := _space()
	var home := Vector2i(10, 10)
	var threat := Vector2i(22, 10)
	var cells := WallPlan.screen(space, home, threat)
	assert_eq(cells.size(), WallPlan.SEGMENTS, "a screen is its full width")

	# Every segment stands at the standoff, and nearer the threat than
	# home is — which is what "between" means on a grid with no angles.
	for cell in cells:
		assert_eq(space.distance(home, cell), WallPlan.STANDOFF_CELLS,
			"%s is not on the standoff ring" % cell)
		assert_lt(space.distance(threat, cell), space.distance(threat, home),
			"%s is not between home and the threat" % cell)


func test_the_screen_is_built_from_the_middle_outward() -> void:
	# An AI raises one segment per think and can be interrupted by
	# anything, so a half-built screen has to be a screen with short ends
	# rather than a fence with a hole in the middle of the road.
	var space := _space()
	var home := Vector2i(10, 10)
	var threat := Vector2i(22, 10)
	var cells := WallPlan.screen(space, home, threat)
	var previous := -1
	for i in range(cells.size()):
		var away := space.distance(threat, cells[i])
		if previous >= 0:
			assert_gte(away, previous,
				"segment %d is nearer the threat line than the one before it" % i)
		previous = away
	assert_eq(WallPlan.gate_index(cells), 0,
		"the gate is the cell squarely on the approach, which is the first one")


func test_a_screen_faces_the_short_way_round_the_torus() -> void:
	# The recurring torus tax (D-008). A bearing computed on raw axial
	# numbers would take the LONG way round the seam and put the wall on
	# the far side of the town from the enemy — which is worse than no
	# wall, because it is paid for.
	var space := _space()
	var home := Vector2i(2, 10)
	# Four cells west of home, the short way, which is +44 in raw q.
	var threat := space.normalize(Vector2i(-6, 10))
	assert_eq(space.distance(home, threat), 8, "Setup: the short way is 8 cells")
	var cells := WallPlan.screen(space, home, threat)
	assert_false(cells.is_empty(), "Setup: a screen was planned")
	for cell in cells:
		assert_lt(space.distance(threat, cell), space.distance(threat, home),
			"%s is on the wrong side of the seam" % cell)


func test_a_screen_with_no_threat_is_no_screen() -> void:
	var space := _space()
	assert_eq(WallPlan.screen(space, Vector2i(5, 5), Vector2i(5, 5)).size(), 0,
		"nothing to face means nothing to build")
	assert_eq(WallPlan.screen(null, Vector2i(5, 5), Vector2i(9, 5)).size(), 0)


func test_blocked_ground_is_skipped_rather_than_shifting_the_arc() -> void:
	# A wall that stops at a cliff is a wall that reaches the cliff.
	# Impassable ground was already doing the wall's job, and sliding the
	# arc sideways to keep the count would put segments off the approach.
	var space := _space()
	var home := Vector2i(10, 10)
	var threat := Vector2i(22, 10)
	var open := WallPlan.screen(space, home, threat)
	assert_gt(open.size(), 1, "Setup: there is a screen to block")

	var blocked := {space.index(open[0]): true}
	var around := WallPlan.screen(space, home, threat, blocked)
	for cell in around:
		assert_ne(cell, open[0], "the blocked cell must not be planned")
	for cell in around:
		assert_eq(space.distance(home, cell), WallPlan.STANDOFF_CELLS,
			"and the rest of the arc must not move to compensate")


# --- what a screen costs, before it is started -------------------------


func test_the_whole_screen_is_priced_before_the_first_segment() -> void:
	# An AI that could afford segment one and not segment two would leave
	# the worst object on the map: a wall short enough to walk round,
	# bought with the wood that would have trained soldiers.
	var wall := WallPlan.cheapest_wall(false)
	var gate := WallPlan.cheapest_wall(true)
	assert_not_null(wall, "the shipped roster has a wall")
	assert_not_null(gate, "and a gate")
	if wall == null or gate == null:
		return
	var total := WallPlan.cost_of_screen(wall, gate)
	var expected_wood := gate.cost_wood + wall.cost_wood * (WallPlan.SEGMENTS - 1)
	assert_eq(total[Economy.ResourceKind.WOOD], expected_wood,
		"one gate and the rest walls")
	gut.p("screen of %d: %d food, %d wood, %d gold, %d stone" % [
		WallPlan.SEGMENTS, total[0], total[1], total[2], total[3]])


func test_a_ring_would_be_unaffordable_which_is_why_it_is_an_arc() -> void:
	# The arithmetic behind the design, pinned so that a future roster
	# whose walls got cheap re-opens the question rather than leaving the
	# arc in place out of habit. A ring at the standoff is 6 x radius
	# cells on a hex grid.
	var wall := WallPlan.cheapest_wall(false)
	if wall == null:
		return
	var ring_cells := 6 * WallPlan.STANDOFF_CELLS
	var ring_wood := wall.cost_wood * ring_cells
	var ring_stone := wall.cost_stone * ring_cells
	assert_gt(ring_wood + ring_stone,
		WallPlan.cost_of_screen(wall, wall)[Economy.ResourceKind.WOOD] * 4,
		"an enclosure is meant to be far out of reach of a match this length")
	gut.p("a ring at %d cells would be %d wood and %d stone" % [
		ring_cells, ring_wood, ring_stone])


# --- found by rule, never by id ----------------------------------------


func test_a_wall_and_a_gate_are_found_by_their_fields() -> void:
	# D-076 ships five members of the wall family and a civ may ship more.
	# Naming `wall` and `gate` here is the hardcoded list D-047 and
	# `bot_build_plan.gd`'s own header both forbid.
	var wall := WallPlan.cheapest_wall(false)
	var gate := WallPlan.cheapest_wall(true)
	assert_not_null(wall)
	assert_not_null(gate)
	if wall == null or gate == null:
		return
	assert_false(wall.is_gate, "the wall is not a gate")
	assert_true(gate.is_gate, "and the gate is")
	for def in [wall, gate]:
		assert_true(def.produces.is_empty(), "%s trains something" % def.id)
		assert_eq(def.damage, 0.0, "%s shoots, so it is a tower" % def.id)
		assert_false(def.is_access_tower, "%s is a door, not a wall" % def.id)


func test_the_cheapest_is_actually_the_cheapest_by_d072s_rate() -> void:
	var wall := WallPlan.cheapest_wall(false)
	if wall == null:
		return
	var mine := wall.cost_food + wall.cost_wood + 1.5 * (wall.cost_gold + wall.cost_stone)
	for def in BuildingSim.all_defs():
		if def.is_gate or not WallPlan.is_wall_like(def):
			continue
		var theirs: float = def.cost_food + def.cost_wood \
			+ 1.5 * (def.cost_gold + def.cost_stone)
		assert_lte(mine, theirs, "%s is cheaper than the one chosen" % def.id)


func test_a_defensive_tower_is_the_one_that_shoots() -> void:
	# The first thing worth buying with defensive money, because unlike a
	# wall it does something to an attacker who is already inside. D-066
	# is the standing warning about a defence whose numbers do nothing.
	var tower := WallPlan.cheapest_defensive_tower(&"gatherers")
	assert_not_null(tower, "the shipped roster has something that shoots")
	if tower == null:
		return
	assert_gt(tower.damage, 0.0)
	assert_gt(tower.attack_range, 0.0)
	assert_false(WallPlan.is_wall_like(tower),
		"a tower is not a wall segment, and the two are told apart by fields")


func test_no_script_in_this_pair_names_a_shipped_building() -> void:
	# The same rule D-046 criterion 3 applies to civs, applied to the wall
	# family: `wall_plan.gd` and `static_defence.gd` decide by FIELD, so a
	# civ shipping its own rampart is picked up with no edit.
	for path in ["res://wall_plan.gd", "res://static_defence.gd"]:
		var handle := FileAccess.open(path, FileAccess.READ)
		assert_not_null(handle, "%s must be readable" % path)
		if handle == null:
			continue
		var code := ""
		for line in handle.get_as_text().split("\n"):
			if not String(line).strip_edges().begins_with("#"):
				code += line + "\n"
		handle.close()
		for def in BuildingSim.all_defs():
			assert_false(code.contains('&"%s"' % def.id),
				"%s names the shipped building %s" % [path, def.id])
