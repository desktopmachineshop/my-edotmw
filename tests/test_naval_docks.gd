extends GutTest

## Guards naval stage 3 — docks (#301, `docs/plans/naval.md` §4).
##
## Three things, and the third is the one that fails silently:
##
## 1. a dock refuses inland ground and accepts a shore;
## 2. a dock gets its own WATER CELL, per instance, at placement;
## 3. a hull produced there appears in WATER.
##
## Everything is driven through `server._build_refusal` and
## `server._finish_build` over a `LoopbackPeer` — the pattern
## `tests/test_civ_knobs.gd` established and #158's own finding demands:
## a Node never added to the tree does not run `_ready()`, so no socket is
## needed, and a rule proven only against the arithmetic says nothing
## about whether the server performs it.
##
## The water cell is the part with the handover risk. `add_building` does
## not compute it — `BuildingSim` has no terrain — so `server` sets it
## afterwards, and a caller that forgot would leave a dock that builds
## fine and launches nothing. #119's finding is that the handover nothing
## performs is the dangerous half, so it is asserted through the real
## build path rather than by calling the setter here.

const W := 24
const H := 12


## A world that is land on the left and water on the right, so a shore is
## a column and there is no doubt which side of it a cell is on.
##
## Hand-built rather than generated: `TerrainGen` on a toy map is mostly
## one biome (D-105 — a Skirmish map is a corner of a world), and a
## fixture whose coastline depends on a seed is a fixture that proves
## something different next year.
func _world() -> Dictionary:
	var space := TorusSpace.new(W, H, 1.0)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var wet := coord.x >= 12 and coord.x < 20
		passable[index] = 0 if wet else 1
		navigable[index] = 1 if wet else 0

	var server = load("res://server.gd").new()
	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy
	server._passable = passable
	server._navigable = navigable
	server._sim.set_passable(passable)
	server._sim.set_navigable(navigable)

	server._match = MatchState.new()
	server._match.add_player(1)
	server._match.phase = MatchState.Phase.RUNNING
	for kind in range(Economy.RESOURCE_COUNT):
		server._economy.credit(1, kind, 100000)

	var peer := LoopbackPeer.new()
	server._ai_clients[peer] = {"player": 1, "visible": {}}
	return {"server": server, "peer": peer, "space": space,
		"passable": passable, "navigable": navigable}


func _gatherer() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"gatherers"
	d.squad_size = 7
	d.health = 30.0
	d.move_speed = 3.5
	d.morale = 100.0
	d.carry_capacity = 45
	d.gather_rate = 0.28
	return d


# --- the fixture is what it says it is --------------------------------

func test_the_fixture_actually_has_a_coastline() -> void:
	# A land-only fixture would pass every refusal test below by accident,
	# which is the vacuous pass D-022's audit block is about.
	var w := _world()
	var space: TorusSpace = w["space"]
	var shores := 0
	for index in range(space.cell_count()):
		if TerrainGen.is_shore(space, w["passable"], w["navigable"], index):
			shores += 1
	assert_gt(shores, 0, "the fixture must have a shore to build on")
	(w["server"] as Node).free()


# --- 1. the refusal ---------------------------------------------------

func test_a_dock_is_refused_inland() -> void:
	var w := _world()
	var server = w["server"]
	var dock := BuildingSim.def_by_id(&"dock")
	assert_not_null(dock, "the roster must ship a dock")
	assert_true(dock.needs_shore, "and it must be the thing that needs a shore")

	var refusal: String = server._build_refusal(Vector2i(4, 4), dock, 1)
	assert_ne(refusal, "", "a dock on inland ground must be refused")
	assert_true(refusal.contains("shore"),
		"and the refusal must say why: %s" % refusal)
	server.free()


func test_a_dock_is_accepted_on_a_shore() -> void:
	var w := _world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	var dock := BuildingSim.def_by_id(&"dock")

	# x = 11 is the last land column before the water starts at 12.
	var shore := Vector2i(11, 4)
	assert_true(TerrainGen.is_shore(space, w["passable"], w["navigable"], space.index(shore)),
		"Setup: that cell must actually be a shore")
	assert_eq(server._build_refusal(shore, dock, 1), "",
		"a dock on the shore must be accepted")
	server.free()


func test_a_dock_is_refused_in_the_water_like_anything_else() -> void:
	# The shore rule must not accidentally EXCUSE a building from the
	# water rule that already existed — "needs a shore" and "may stand in
	# the sea" are different claims and only the first is true.
	var w := _world()
	var server = w["server"]
	var dock := BuildingSim.def_by_id(&"dock")
	var refusal: String = server._build_refusal(Vector2i(15, 4), dock, 1)
	assert_ne(refusal, "", "a dock in open water must still be refused")
	assert_false(refusal.contains("shore"),
		"and for the water reason, which comes first: %s" % refusal)
	server.free()


func test_every_other_building_is_unaffected_by_the_shore_rule() -> void:
	# `needs_shore` defaults false and the refusal reads it, so an inland
	# barracks must be exactly as buildable as it was.
	var w := _world()
	var server = w["server"]
	var checked := 0
	for def in BuildingSim.all_defs():
		if def.needs_shore:
			continue
		checked += 1
		assert_eq(server._build_refusal(Vector2i(4, 4), def, 1), "",
			"%s is not a shore building and must still build inland" % def.id)
	assert_gt(checked, 5, "Setup: there must be inland buildings to check")
	server.free()


func test_a_server_with_no_world_refuses_nothing_for_want_of_a_coastline() -> void:
	# The tests that drive handlers directly leave `_navigable` empty, and
	# so does a server whose world was never built. Refusing every dock in
	# that state would be a rule firing on an absence of information.
	var w := _world()
	var server = w["server"]
	server._navigable = PackedByteArray()
	assert_eq(server._build_refusal(Vector2i(4, 4), BuildingSim.def_by_id(&"dock"), 1), "",
		"with no coastline known, the shore rule must abstain")
	server.free()


# --- 2. the water cell, through the real build path -------------------

func test_a_finished_dock_gets_its_own_water_cell() -> void:
	# THE handover check. `add_building` cannot compute this — BuildingSim
	# has no terrain — so a caller that forgot would leave a dock that
	# builds perfectly and launches nothing, with no failure anywhere.
	var w := _world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	var dock := BuildingSim.def_by_id(&"dock")
	var shore := Vector2i(11, 4)
	var crew: int = server._sim.add_squad(_gatherer(), 1, shore)
	server._finish_build(w["peer"], crew, dock, shore)

	assert_eq(server._buildings.building_count(), 1, "the dock was raised")
	var water: int = server._buildings.water_cell_of(0)
	assert_gte(water, 0, "a dock must be given a water cell at placement")
	assert_true(server._sim.is_navigable(space.from_index(water)),
		"and that cell must actually be water")
	assert_lte(space.distance(shore, space.from_index(water)), 2,
		"and it must be beside the dock, not somewhere else on the coast")
	server.free()


func test_two_docks_on_one_coast_get_different_water_cells() -> void:
	# The reason this is per INSTANCE and not on the def: a shared water
	# side would give every dock on the map the same one.
	var w := _world()
	var server = w["server"]
	var dock := BuildingSim.def_by_id(&"dock")
	for y in [2, 8]:
		var at := Vector2i(11, y)
		var crew: int = server._sim.add_squad(_gatherer(), 1, at)
		server._finish_build(w["peer"], crew, dock, at)
	assert_eq(server._buildings.building_count(), 2, "Setup: two docks")
	assert_ne(server._buildings.water_cell_of(0), server._buildings.water_cell_of(1),
		"two docks must not share a water cell")
	server.free()


func test_a_building_that_does_not_need_a_shore_has_no_water_cell() -> void:
	# The field cannot quietly acquire a second meaning: `set_water_cell`
	# refuses a def that did not ask for one.
	var w := _world()
	var server = w["server"]
	var barracks := BuildingSim.def_by_id(&"barracks")
	var at := Vector2i(4, 4)
	var crew: int = server._sim.add_squad(_gatherer(), 1, at)
	server._finish_build(w["peer"], crew, barracks, at)
	assert_eq(server._buildings.water_cell_of(0), -1,
		"a barracks has no water side")
	server._buildings.set_water_cell(0, 5)
	assert_eq(server._buildings.water_cell_of(0), -1,
		"and cannot be given one")
	server.free()


# --- 3. a hull appears in water ---------------------------------------

func test_a_hull_produced_at_a_dock_is_launched_into_water() -> void:
	var w := _world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	var dock := BuildingSim.def_by_id(&"dock")
	var shore := Vector2i(11, 4)
	var crew: int = server._sim.add_squad(_gatherer(), 1, shore)
	server._finish_build(w["peer"], crew, dock, shore)
	var before: int = server._sim.squad_count()

	var hull := UnitRoster.for_civ_archetype(&"gravesworn", &"warship")
	assert_not_null(hull, "Setup: a civ fields a warship")
	assert_eq(hull.movement_domain, "water", "Setup: and it is a water unit")
	server._buildings.enqueue(0, hull, true)
	server._sim.tick()

	assert_eq(server._sim.squad_count(), before + 1, "the hull was produced")
	var launched: int = server._sim.squad_count() - 1
	var at: Vector2i = server._sim.cell_of(launched)
	assert_true(server._sim.is_navigable(at),
		"a hull must be launched into water, not onto the quay (%s)" % at)
	server.free()


func test_a_land_unit_from_the_same_dock_is_not_launched_into_water() -> void:
	# The dispatch is on the DEF's domain, so the same building producing
	# a land unit still uses the land walk. Nothing ships that way today,
	# which is exactly why it is worth pinning before something does.
	var w := _world()
	var server = w["server"]
	var dock := BuildingSim.def_by_id(&"dock")
	var shore := Vector2i(11, 4)
	var crew: int = server._sim.add_squad(_gatherer(), 1, shore)
	server._finish_build(w["peer"], crew, dock, shore)
	var before: int = server._sim.squad_count()

	var land := UnitRoster.for_civ_archetype(&"gravesworn", &"levy")
	assert_not_null(land)
	assert_eq(land.movement_domain, "ground", "Setup: a land unit")
	server._buildings.enqueue(0, land, true)
	server._sim.tick()

	assert_eq(server._sim.squad_count(), before + 1, "it was produced")
	var at: Vector2i = server._sim.cell_of(server._sim.squad_count() - 1)
	assert_false(server._sim.is_navigable(at),
		"a land unit must not be put in the sea (%s)" % at)
	server.free()


func test_two_hulls_launched_together_do_not_stack() -> void:
	var w := _world()
	var server = w["server"]
	var dock := BuildingSim.def_by_id(&"dock")
	var shore := Vector2i(11, 4)
	var crew: int = server._sim.add_squad(_gatherer(), 1, shore)
	server._finish_build(w["peer"], crew, dock, shore)

	var hull := UnitRoster.for_civ_archetype(&"gravesworn", &"warship")
	var cells := {}
	for i in range(3):
		server._buildings.enqueue(0, hull, true)
		server._sim.tick()
		var at: Vector2i = server._sim.cell_of(server._sim.squad_count() - 1)
		assert_true(server._sim.is_navigable(at), "hull %d is afloat" % i)
		cells[server._sim.space.index(at)] = true
	assert_eq(cells.size(), 3, "three hulls must be launched to three berths")
	server.free()


func test_a_dock_with_no_water_beside_it_launches_onto_land_rather_than_nowhere() -> void:
	# Reachable through the sandbox's instant building spawn (D-077),
	# which places a building without asking `_build_refusal`. Losing a
	# hull somebody paid for is worse than putting it on the quay, which
	# is the same call the land path already makes when it is hemmed in.
	var w := _world()
	var server = w["server"]
	var dock := BuildingSim.def_by_id(&"dock")
	var inland := Vector2i(4, 4)
	server._buildings.add_building(dock, 1, inland, true)
	assert_eq(server._buildings.water_cell_of(0), -1, "Setup: no water side")

	var hull := UnitRoster.for_civ_archetype(&"gravesworn", &"warship")
	server._buildings.enqueue(0, hull, true)
	server._sim.tick()
	assert_eq(server._sim.squad_count(), 1, "the hull still exists")
	server.free()
