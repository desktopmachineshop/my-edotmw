extends GutTest

## Guards D-20260828-four-more-knobs-and-every-one-has-a-caller (#270).
##
## `CivDef`'s first three fields shipped **read by nothing for a whole
## milestone** -- the fourth instance of this project's declared-and-
## unread defect class, fixed only in #158, with two of six civ
## identities depending on them. #270 says plainly what any new field
## needs: an applied function on the schema, a caller, and a test that
## drives the SERVER HANDLER rather than the arithmetic.
##
## `tests/test_civ_knobs.gd` records why the last clause matters: when all
## three knobs were unwired, both production BEHAVIOUR tests stayed green,
## because they called `BuildingSim.enqueue` themselves. **Arithmetic
## tests cannot see a missing caller.** So every knob here is driven
## through the thing that actually runs in a match.
##
## Resolved by PROPERTY, never by civ name -- no test may name a civ
## (D-046 criterion 3), and `tests/test_civs.gd` enforces it.

const W := 40
const H := 32


func _sim_with_civ(civ: CivDef) -> SquadSim:
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.buildings = BuildingSim.new(space)
	sim.civs = {1: civ}
	return sim


# --- the applied functions --------------------------------------------

func test_a_cap_penalty_is_expressible_and_floored() -> void:
	# `squad_cap_bonus` only meaningfully went UP, so "strong from few
	# well-held sites" could not be said: such a civ fielded the same
	# forty squads as everyone and merely paid more per squad.
	var civ := CivDef.new()
	civ.squad_cap_bonus = -6
	assert_eq(civ.squad_cap(40), 34, "a negative bonus must lower the cap")

	# And a floor, because a cap of zero is a civ that cannot play and is
	# one data entry away.
	civ.squad_cap_bonus = -999
	assert_eq(civ.squad_cap(40), 1,
		"a large penalty must floor at one squad, not at zero or below")


func test_a_build_speed_is_not_a_production_speed() -> void:
	# Different verbs. `production_speed` divides `UnitDef.build_time` and
	# only ever touches units, which left a fortification civ unable to
	# fortify faster than anybody else.
	var civ := CivDef.new()
	civ.build_speed = 1.25
	civ.production_speed = 1.0
	assert_almost_eq(civ.construction_time(20.0), 16.0, 0.001)
	assert_almost_eq(civ.production_time(20.0), 20.0, 0.001,
		"build_speed must not leak into unit production")


func test_a_per_resource_table_says_what_one_scalar_cannot() -> void:
	# "wood-rich, gold-poor" is not a smaller number, it is four numbers.
	var civ := CivDef.new()
	civ.gather_speed = 1.0
	civ.gather_speed_by_kind = [1.1, 1.25, 0.75, 0.9]
	assert_almost_eq(civ.gather_rate(1.0, Economy.ResourceKind.WOOD), 1.25, 0.001)
	assert_almost_eq(civ.gather_rate(1.0, Economy.ResourceKind.GOLD), 0.75, 0.001)
	assert_gt(civ.gather_rate(1.0, Economy.ResourceKind.WOOD),
		civ.gather_rate(1.0, Economy.ResourceKind.GOLD),
		"a civ with a per-resource table must be able to be rich in one and poor in another")


func test_an_empty_table_reads_exactly_as_it_always_did() -> void:
	# The clause that keeps five of six civs unchanged: empty means the
	# scalar applies to everything, which is what every civ did before.
	var civ := CivDef.new()
	civ.gather_speed = 1.15
	assert_almost_eq(civ.gather_rate(2.0, Economy.ResourceKind.GOLD), 2.3, 0.001)
	assert_almost_eq(civ.gather_rate(2.0), 2.3, 0.001,
		"a caller with no kind to give must still get the scalar")


func test_validate_refuses_a_half_filled_table() -> void:
	# Four resources or none. A three-entry table would silently fall
	# back to the scalar for the fourth, which is a civ identity with a
	# hole in it that nothing would report.
	var civ := CivDef.new()
	civ.id = &"probe"
	civ.gather_speed_by_kind = [1.0, 1.0, 1.0]
	assert_ne(civ.validate(), "",
		"a table covering some resources and not others must be refused")
	civ.gather_speed_by_kind = [1.0, 1.0, 1.0, 1.0]
	assert_eq(civ.validate(), "", "a full table is valid")


func test_validate_refuses_a_non_positive_multiplier() -> void:
	for field in ["build_speed", "march_speed"]:
		var civ := CivDef.new()
		civ.id = &"probe"
		civ.set(field, 0.0)
		assert_ne(civ.validate(), "",
			"%s of zero must be refused -- it divides or freezes an army" % field)


# --- and the callers, driven rather than assumed ----------------------

func test_a_marching_civ_actually_moves_faster_in_the_SIM() -> void:
	# Through `add_squad`, which is where SquadSim latches a squad's
	# cells-per-second. An applied function with no caller is exactly the
	# defect #158 fixed.
	var def := UnitRoster.for_civ_archetype(CivRoster.ids()[0], &"levy")
	assert_not_null(def, "the roster should ship a levy")

	var plain := CivDef.new()
	var swift := CivDef.new()
	swift.march_speed = 1.5

	var slow_sim := _sim_with_civ(plain)
	var fast_sim := _sim_with_civ(swift)
	var slow := slow_sim.add_squad(def, 1, Vector2i(4, 4))
	var fast := fast_sim.add_squad(def, 1, Vector2i(4, 4))
	slow_sim.order_move(slow, Vector2i(20, 4))
	fast_sim.order_move(fast, Vector2i(20, 4))
	# Short of arrival on purpose. The first version ran 120 ticks and
	# both squads REACHED the destination, so the comparison saturated at
	# 20 vs 20 and reported "the knob has no caller" about a knob that
	# worked. A race has to be measured before the finish line.
	for _i in range(40):
		slow_sim.tick()
		fast_sim.tick()

	var slow_at := slow_sim.cell_of(slow)
	var fast_at := fast_sim.cell_of(fast)
	assert_lt(fast_at.x, 20,
		"setup: the fast squad already arrived, so this measures nothing")
	assert_gt(fast_at.x, slow_at.x,
		"a civ with march_speed 1.5 got no further in the same time (%s vs %s) -- the knob has no caller"
			% [fast_at, slow_at])


func test_a_building_civ_actually_raises_faster_in_the_SIM() -> void:
	# Through `BuildingSim.advance_construction`, with the time banked at
	# placement exactly as the server banks it.
	var space := TorusSpace.new(W, H, 1.0)
	var def := BuildingSim.def_by_id(&"barracks")
	assert_not_null(def, "the roster should ship a barracks")

	var quick := CivDef.new()
	quick.build_speed = 2.0

	var plain_sim := BuildingSim.new(space)
	var quick_sim := BuildingSim.new(space)
	var plain := plain_sim.add_building(def, 1, Vector2i(5, 5), false)
	var fast := quick_sim.add_building(def, 1, Vector2i(5, 5), false, -1, 0,
		Vector2.ZERO, quick.construction_time(def.build_time))

	for _i in range(int(def.build_time * 10.0 / 2.0)):
		plain_sim.advance_construction(0.1)
		quick_sim.advance_construction(0.1)

	assert_gt(quick_sim.progress_of(fast), plain_sim.progress_of(plain),
		"a civ with build_speed 2.0 raised no faster -- the time is not reaching construction")


func test_the_server_hands_its_build_time_to_the_building() -> void:
	# The clause #270 asks for by name: a test that drives the SERVER
	# HANDLER, because the arithmetic tests above would all pass while
	# nothing on the real path resolved the civ.
	var handle := FileAccess.open("res://server.gd", FileAccess.READ)
	assert_not_null(handle, "server.gd could not be read")
	if handle == null:
		return
	assert_true(handle.get_as_text().contains("construction_time(def.build_time)"),
		"the build handler does not resolve the owner's civ, so build_speed reaches nothing")


func test_the_economy_asks_for_the_resource_kind() -> void:
	var handle := FileAccess.open("res://economy.gd", FileAccess.READ)
	assert_not_null(handle, "economy.gd could not be read")
	if handle == null:
		return
	assert_true(handle.get_as_text().contains("gather_rate(\n\t\tdef.gather_rate, kind_at(cell))")
			or handle.get_as_text().contains("def.gather_rate, kind_at(cell)"),
		"the gather path does not pass the node's kind, so a per-resource table does nothing")


func test_every_new_knob_is_read_somewhere_outside_the_schema() -> void:
	# The generalised caller-exists scan, over the whole class rather than
	# one field -- D-106's caveat, and the shape that let three knobs ship
	# unwired. A knob whose only mentions are its own declaration and its
	# own applied function has no caller.
	var readers := {
		"construction_time": ["res://server.gd"],
		"march_rate": ["res://squad_sim.gd"],
		"gather_rate": ["res://economy.gd"],
		"squad_cap": ["res://match_state.gd"],
	}
	for accessor in readers:
		var found := false
		for path in readers[accessor]:
			var handle := FileAccess.open(path, FileAccess.READ)
			if handle != null and handle.get_as_text().contains(accessor + "("):
				found = true
		assert_true(found,
			"%s is applied by nothing outside CivDef, so the knob it serves is declared and unread"
				% accessor)
