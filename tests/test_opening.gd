extends GutTest

## Guards D-20260823-the-opening-is-a-crew-and-a-general (issue #190),
## which supersedes D-031's founding party.
##
## Three claims, none of which any existing check could make:
##
##  1. A player opens with ONE gatherer crew and ONE general, and no base.
##  2. Founding a town hall SPENDS the crew; every other building costs its
##     builder nothing. The rule is `BuildingDef.consumes_builder` — data,
##     so it cannot widen to a building nobody meant it for, which is
##     exactly how `_finish_build` once ate every gatherer that finished a
##     wall (the M7 playtest fix).
##  3. The general is an escort: it may build nothing at all, and its death
##     is a morale event rather than a defeat.
##
## `server.gd` is a Node with no scene-tree dependency in the two functions
## under test, so it is instantiated directly and its state set by hand —
## the same technique `test_buildings.gd` uses for `_is_buildable`. That
## matters: `_finish_build` is the ONLY place consumption happens, and a
## test that called `SquadSim.consume_squad` itself would prove the sim
## works while saying nothing about who it is called for.


const W := 48
const H := 32


## A peer that records rather than sends. `_finish_build` notifies and
## sends a wallet; neither is what this file is about, but both are called
## unconditionally, so they have to land somewhere.
class FakePeer extends RefCounted:
	var packets: Array = []

	func send(_channel: int, bytes: PackedByteArray, _flags: int) -> int:
		packets.append(bytes)
		return 0


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


## A server with just enough world attached to commit a build.
func _server(space: TorusSpace):
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var server = load("res://server.gd").new()
	server._sim = sim
	server._buildings = buildings
	server._economy = Economy.new(space)
	server._match = MatchState.new()
	server._passable = PackedByteArray()  # empty means "fully open"
	return server


func _civ() -> StringName:
	return CivRoster.ids()[0]


func _crew() -> UnitDef:
	return UnitRoster.for_civ_archetype(_civ(), &"gatherers")


func _general() -> UnitDef:
	return UnitRoster.for_civ_archetype(_civ(), &"general")


# --- the opening itself -----------------------------------------------

func test_a_player_opens_with_a_crew_and_a_general_and_no_base() -> void:
	var space := _space()
	var server = _server(space)
	server._spawn_points = [Vector2i(10, 10), Vector2i(30, 20)] as Array[Vector2i]
	server._civs[1] = _civ()
	server._match.add_player(1)

	var ids: Array = server._spawn_squads_for(1)
	assert_eq(ids.size(), 2,
		"the opening is exactly two squads — a settler and its escort")

	var archetypes := []
	for squad in ids:
		archetypes.append(String(server._sim.def_of(int(squad)).archetype))
	archetypes.sort()
	assert_eq(archetypes, ["gatherers", "general"],
		"the opening spawned %s" % str(archetypes))

	assert_eq(server._buildings.building_count(), 0,
		"and no base: where to settle is still the first decision of a match")

	# Not on top of each other. Two squads dealt one cell would separate
	# on the first tick anyway, but the spawn should not require it.
	assert_ne(server._sim.cell_of(int(ids[0])), server._sim.cell_of(int(ids[1])),
		"the escort stands BESIDE the crew, not inside it")

	server.free()


func test_every_civ_can_actually_open() -> void:
	# The one way per-civ gatherers can go wrong silently: a civ whose
	# `.tres` is missing or misnamed has no settler, so its seat spawns
	# nothing and the player is eliminated the first time elimination is
	# evaluated. `_spawn_squads_for` push_errors, which no verdict reads.
	for civ in CivRoster.ids():
		assert_not_null(UnitRoster.for_civ_archetype(civ, &"gatherers"),
			"civ %s has no settler, so it cannot open at all" % civ)
		assert_not_null(UnitRoster.for_civ_archetype(civ, &"general"),
			"civ %s has no general, so its opening has no escort" % civ)


func test_the_civs_gatherers_are_actually_different_troops() -> void:
	# The point of per-civ gatherers (D-047's rule, applied to the unit
	# every player fields most of). Two identical `.tres` files would pass
	# every other check here while the feature was absent — the shape this
	# project keeps rediscovering.
	var seen := {}
	for civ in CivRoster.ids():
		var def := UnitRoster.for_civ_archetype(civ, &"gatherers")
		if def == null:
			continue
		seen[civ] = [def.squad_size, def.health, def.carry_capacity,
			def.gather_rate, def.cost_food]
	assert_gt(seen.size(), 1, "fewer than two civs — this check is vacuous")

	var distinct := {}
	for civ in seen:
		distinct[str(seen[civ])] = true
	assert_eq(distinct.size(), seen.size(),
		"two civs field statistically identical gatherers: %s" % str(seen))


# --- who is spent, and who is not -------------------------------------

func test_founding_a_town_hall_spends_the_crew() -> void:
	var space := _space()
	var server = _server(space)
	var peer := FakePeer.new()
	server._economy.credit(1, Economy.ResourceKind.WOOD, 9999)

	var crew: int = server._sim.add_squad(_crew(), 1, Vector2i(12, 8))
	var hall := BuildingSim.def_by_id(&"town_centre")
	assert_true(hall.consumes_builder,
		"setup: the town centre is the def that costs its founder")

	server._finish_build(peer, crew, hall, Vector2i(12, 8))

	assert_eq(server._buildings.building_count(), 1, "the hall went up")
	assert_eq(server._sim.alive_of(crew), 0,
		"the crew becomes the settlement — one crew, one town")
	assert_gt(server._pending_events.size(), 0,
		"and says so on the wire, as an ordinary casualty event")

	server.free()


func test_a_crew_finishing_anything_else_walks_away_free() -> void:
	# The half that was a live bug for four milestones: `_finish_build` is
	# shared by every building type and consumed the builder with no check
	# on WHAT was being built, so every gatherer that finished a storehouse,
	# a tower or a wall silently vanished. Nothing failed — the buildings
	# genuinely went up.
	#
	# The town centre is named here as THE exception rather than skipped by
	# reading `consumes_builder`, and the difference is the whole test. The
	# first version filtered on the flag, which meant setting it on the
	# barracks removed the barracks from this loop instead of reding it: a
	# check that consults the thing it is checking cannot see that thing go
	# wrong. Observed — perturbing the barracks def left this green, and it
	# reds now.
	const SPENDS_ITS_BUILDER := &"town_centre"

	var space := _space()
	var server = _server(space)
	var peer := FakePeer.new()
	server._economy.credit(1, Economy.ResourceKind.FOOD, 9999)
	server._economy.credit(1, Economy.ResourceKind.WOOD, 9999)
	server._economy.credit(1, Economy.ResourceKind.GOLD, 9999)
	server._economy.credit(1, Economy.ResourceKind.STONE, 9999)

	var checked := 0
	for def in BuildingSim.all_defs():
		if def.id == SPENDS_ITS_BUILDER:
			continue
		if not BuildingSim.can_build(def, &"gatherers"):
			continue
		var crew: int = server._sim.add_squad(_crew(), 1, Vector2i(4 + checked * 3, 20))
		server._finish_build(peer, crew, def, Vector2i(4 + checked * 3, 20))
		assert_gt(server._sim.alive_of(crew), 0,
			"the crew that raised a %s was eaten by it" % def.id)
		checked += 1

	assert_gt(checked, 0, "no ordinary buildings were checked, so this proves nothing")
	server.free()


func test_exactly_one_shipped_building_costs_its_builder() -> void:
	# The scope, stated as a count. A second `consumes_builder` def is a
	# design decision (see the entry's revisit trigger), not something that
	# should arrive as a quiet .tres edit.
	var spenders := []
	for def in BuildingSim.all_defs():
		if def.consumes_builder:
			spenders.append(String(def.id))
	assert_eq(spenders, ["town_centre"],
		"these buildings spend their builder: %s" % str(spenders))


func test_a_general_may_build_nothing_and_is_never_spent() -> void:
	var space := _space()
	var server = _server(space)
	for def in BuildingSim.all_defs():
		assert_false(BuildingSim.can_build(def, &"general"),
			"a general may raise a %s — the escort is not a builder" % def.id)

	# And if one somehow reached `_finish_build` (a future caller, a cheat),
	# it walks away — see the pair test below for the town-centre case,
	# which is the one that could actually have spent it.
	var peer := FakePeer.new()
	server._economy.credit(1, Economy.ResourceKind.WOOD, 9999)
	var boss: int = server._sim.add_squad(_general(), 1, Vector2i(20, 12))
	server._finish_build(peer, boss, BuildingSim.def_by_id(&"barracks"), Vector2i(20, 12))
	assert_gt(server._sim.alive_of(boss), 0, "the escort walked away")

	server.free()


func test_a_squad_that_may_not_build_it_is_never_spent_by_it() -> void:
	# The consume rule is the PAIR — a builder `built_by` admits, founding a
	# def that `consumes_builder` — not the building alone.
	#
	# Scoping it to the def alone was the first version here, and it left a
	# hole this test was written to expose: `_finish_build` would spend
	# WHOEVER it was handed at a town centre, general included. `built_by`
	# refuses that at the order gate, so nothing shipped could reach it —
	# which is exactly the argument that let `_finish_build` consume ANY
	# builder for four milestones, and it was wrong then too. Every other
	# rule in `_finish_build` is re-checked on arrival (ground, claims,
	# footprints, cost) for the same reason: a builder walks, and the
	# world moves while it does.
	var space := _space()
	var server = _server(space)
	var peer := FakePeer.new()
	server._economy.credit(1, Economy.ResourceKind.WOOD, 9999)

	var hall := BuildingSim.def_by_id(&"town_centre")
	var boss: int = server._sim.add_squad(_general(), 1, Vector2i(14, 16))
	assert_false(BuildingSim.can_build(hall, _general().archetype),
		"setup: a general may not found a town hall")

	server._finish_build(peer, boss, hall, Vector2i(14, 16))
	assert_gt(server._sim.alive_of(boss), 0,
		"a squad that may not build a town hall was spent founding one")

	server.free()


func test_a_dead_general_is_not_a_defeat() -> void:
	# What the issue asked to be decided and written down: a general's
	# death is a MORALE event (combat.gd's chain shock), never elimination.
	# Defeat has one definition (D-033) and it does not know what a general
	# is — which is exactly why this can be asserted rather than trusted.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	var state := MatchState.new()
	state.require_admin_start = false
	state.add_player(1)
	state.add_player(2)
	state.start_match()

	sim.add_squad(_crew(), 1, Vector2i(6, 6))
	var boss := sim.add_squad(_general(), 1, Vector2i(8, 6))
	sim.add_squad(_general(), 2, Vector2i(30, 20))

	sim.consume_squad(boss)  # the general dies; the crew lives
	assert_eq(state.update(sim, buildings), [],
		"losing a general eliminated its owner — defeat is squads AND buildings")
	assert_false(state.is_finished())


func test_every_civs_crew_gets_a_build_menu() -> void:
	# Reported from play: "the thralls cant build the town halls and other
	# buildings". The build MENU intersected actions over the selection's
	# DEF IDS while `built_by` holds ARCHETYPES — indistinguishable while
	# the neutral gatherer's id equalled its archetype, and split apart by
	# the per-civ gatherers (D-20260823). The server's own gate resolves
	# the archetype, so the refusal lived only in the UI: the crew COULD
	# build and was never offered the buttons.
	#
	# client.gd is instantiated but never added to the tree, so _ready()
	# does not run — the test_return_to_lobby pattern: menu derivation is
	# LOGIC, not pixels.
	var client = load("res://client.gd").new()
	for civ in CivRoster.ids():
		var crew := UnitRoster.for_civ_archetype(civ, &"gatherers")
		assert_not_null(crew, "setup: civ '%s' fields no crew" % civ)
		var actions: Array = client._squad_build_actions(crew.id)
		assert_gt(actions.size(), 0,
			"civ '%s' crew (%s) is offered NO build menu — its id is not "
			% [civ, crew.id]
			+ "its archetype, and built_by holds archetypes")
	client.free()
