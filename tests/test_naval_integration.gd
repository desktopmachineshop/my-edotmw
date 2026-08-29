extends GutTest

## Naval integration verification (#301): the seams BETWEEN the nine
## stages, which four workers built against interfaces that moved while
## they were building them.
##
## Every stage tested itself. What nobody owned is the joins — and this
## project's own history says that is where things are found: D-058's
## formation field was correct on the server, correct on the client, and
## absent from the wire between them for a milestone, with every
## stage-local test green.
##
## So everything here crosses a boundary on purpose. Nothing is asserted
## about a function that one stage owns alone.


const W := 32
const H := 16
const SEA_FROM := 8
const SEA_TO := 16
const SEA2_FROM := 24
const SEA2_TO := 32


func _is_sea(x: int) -> bool:
	if x >= SEA_FROM and x < SEA_TO:
		return true
	return x >= SEA2_FROM and x < SEA2_TO


## A server mid-match with one client on a LoopbackPeer, over an
## archipelago. Two channels, because one does not separate anything on a
## torus — the trap the stage 7 landing fixture was caught by.
func _wired_world() -> Dictionary:
	var server = load("res://server.gd").new()
	var space := TorusSpace.new(W, H, 1.0)

	server._match = MatchState.new()
	server._match.require_admin_start = false
	server._settings = server._match.map_settings
	server._match.add_player(1)
	server._match.phase = MatchState.Phase.RUNNING

	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	for index in range(space.cell_count()):
		var wet := _is_sea(space.from_index(index).x)
		passable[index] = 0 if wet else 1
		navigable[index] = 1 if wet else 0
	sim.set_passable(passable)
	sim.set_navigable(navigable)

	server._sim = sim
	server._buildings = buildings
	server._economy = Economy.new(space)
	server._passable = passable

	var state := ClientState.new()
	var peer := LoopbackPeer.new(state)
	# The record shape this branch's `_on_connect` mints. (#226 replaces
	# it with `_fresh_record`, and is not in the naval chain's ancestry —
	# whichever lands second, this line follows it.)
	server._clients[peer] = {"player": 1, "visible": {}}

	return {"server": server, "sim": sim, "buildings": buildings,
		"space": space, "state": state, "peer": peer}


func _def(archetype: StringName) -> UnitDef:
	var d := UnitRoster.for_civ_archetype(&"gravesworn", archetype)
	assert_not_null(d, "setup: a civ must field a %s" % archetype)
	return d


func _dock(w: Dictionary, at: Vector2i) -> int:
	var buildings: BuildingSim = w["buildings"]
	var def := BuildingSim.def_by_id(&"dock")
	var id: int = buildings.add_building(def, 1, at, true)
	buildings.set_water_cell(id, (w["space"] as TorusSpace).index(at + Vector2i(1, 0)))
	return id


func _tick(w: Dictionary, seconds: float) -> void:
	for _i in range(int(seconds * SquadSim.TICK_HZ)):
		(w["sim"] as SquadSim).tick()


## Push the squads this client can see over the wire, the way `_replicate`
## does, and hand it the hash to check itself against.
func _replicate(w: Dictionary) -> void:
	var sim: SquadSim = w["sim"]
	var peer = w["peer"]
	var visible := sim.visible_to(1)
	peer.send(0, NetProtocol.encode_squad_info(sim.squad_info_entries(visible)), 0)
	peer.send(0, NetProtocol.encode_state_hash(
		sim.tick_count, sim.composition_hash(visible)), 0)


# --- stage 4 x the wire: the hash with cargo aboard ---------------------

func test_the_composition_hash_agrees_with_a_squad_aboard_a_ship() -> void:
	# Stage 4's own exit criterion, checked where it can actually fail:
	# ACROSS the wire. An embarked squad is `alive = 0` and stays in the
	# server's visible set, so a client that pruned it — the way it prunes
	# a dead squad out of `squads` — would hash a strictly smaller set and
	# desync on a perfectly healthy system. That is D-025 part 3's trap
	# with a boat in it.
	var w := _wired_world()
	var sim: SquadSim = w["sim"]
	var state: ClientState = w["state"]

	var quay := Vector2i(SEA_FROM - 1, 8)
	_dock(w, quay)
	var hull := sim.add_squad(_def(&"transport"), 1, quay + Vector2i(1, 0))
	var army := sim.add_squad(_def(&"levy"), 1, quay - Vector2i(2, 0))
	_replicate(w)
	assert_eq(state.desync_count, 0, "setup: the two agree before anybody sails")

	sim.order_move(army, sim.cell_of(hull))
	_tick(w, 20.0)
	assert_eq((sim.cargo_of(hull) as Array).size(), 1, "setup: the party is aboard")

	_replicate(w)
	assert_eq(state.desync_count, 0,
		"client and server must hash the same set with a squad aboard a hull — "
		+ "%s" % state.last_desync)


func test_the_hash_agrees_again_after_the_army_lands() -> void:
	# The other end of the crossing. Landing MINTS squads, and a new id
	# arriving on the client through `SQUAD_INFO` rather than through
	# whatever produced it is exactly where an entity class has gone wrong
	# in this project before (D-029's two id spaces).
	var w := _wired_world()
	var sim: SquadSim = w["sim"]
	var state: ClientState = w["state"]

	var quay := Vector2i(SEA_FROM - 1, 8)
	_dock(w, quay)
	var hull := sim.add_squad(_def(&"transport"), 1, quay + Vector2i(1, 0))
	var army := sim.add_squad(_def(&"levy"), 1, quay - Vector2i(2, 0))
	sim.order_move(army, sim.cell_of(hull))
	_tick(w, 20.0)
	sim.order_move(hull, Vector2i(SEA_TO, 8))
	_tick(w, 60.0)
	assert_eq((sim.cargo_of(hull) as Array).size(), 0, "setup: the army is ashore")

	_replicate(w)
	assert_eq(state.desync_count, 0,
		"client and server must agree after a landing mints new squads — %s"
		% state.last_desync)


func test_a_client_is_told_what_a_hull_is_carrying() -> void:
	# Stage 4 puts cargo on SQUAD_INFO for the selection panel. It is not
	# in the HASH (neither side hashes it), so nothing would fail if it
	# stopped arriving — the declared-and-unread shape, one wire field
	# along.
	var w := _wired_world()
	var sim: SquadSim = w["sim"]
	var state: ClientState = w["state"]

	var quay := Vector2i(SEA_FROM - 1, 8)
	_dock(w, quay)
	var hull := sim.add_squad(_def(&"transport"), 1, quay + Vector2i(1, 0))
	var army := sim.add_squad(_def(&"levy"), 1, quay - Vector2i(2, 0))
	sim.order_move(army, sim.cell_of(hull))
	_tick(w, 20.0)
	_replicate(w)

	var carried: Array = state.composition[hull].get("cargo", [])
	assert_eq(carried.size(), 1, "the client must be told the hull has somebody aboard")
	assert_gt(int(carried[0].get("alive", 0)), 0, "and how many of them there are")


# --- stage 1 x stage 2: the fields the sim is handed --------------------

func test_the_two_domains_the_sim_is_handed_do_not_overlap() -> void:
	# Stage 1 produces the arrays, stage 2 dispatches on them, and nothing
	# between them checks that what was handed over is coherent. A cell
	# both passable and navigable would let a land squad and a hull stand
	# in the same place, each believing the other could not be there.
	var w := _wired_world()
	var sim: SquadSim = w["sim"]
	var space: TorusSpace = w["space"]
	for index in range(space.cell_count()):
		var cell := space.from_index(index)
		var land := sim.is_passable(cell, SquadSim.DOMAIN_GROUND)
		var water := sim.is_passable(cell, SquadSim.DOMAIN_WATER)
		assert_false(land and water,
			"cell %s is in both domains once the sim has the arrays" % cell)


func test_a_hull_and_a_levy_disagree_about_every_cell() -> void:
	# The same fact from the units' side, which is what actually decides
	# where they may go: on this map every cell admits exactly one of them.
	var w := _wired_world()
	var sim: SquadSim = w["sim"]
	var space: TorusSpace = w["space"]
	var both := 0
	var neither := 0
	for index in range(space.cell_count()):
		var cell := space.from_index(index)
		var land := sim.is_passable(cell, SquadSim.DOMAIN_GROUND)
		var water := sim.is_passable(cell, SquadSim.DOMAIN_WATER)
		if land and water:
			both += 1
		if not land and not water:
			neither += 1
	assert_eq(both, 0, "no cell may take both")
	assert_eq(neither, 0,
		"and on a map that is only sea and flat land, none may take neither — "
		+ "%d cells are closed to everything" % neither)


# --- stage 5 x stage 2: the domains combat dispatches on ---------------

func test_combat_and_the_sim_agree_about_what_a_hull_is() -> void:
	# Stage 5 refuses melee across a domain boundary by reading
	# `sim.tier_of`. Stage 2 sets that from `UnitDef.movement_domain`.
	# Two stages, one integer, and a mismatch would silently make every
	# ship meleeable from the beach.
	var w := _wired_world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_def(&"transport"), 1, Vector2i(SEA_FROM + 1, 8))
	var levy := sim.add_squad(_def(&"levy"), 1, Vector2i(SEA_FROM - 1, 8))

	assert_eq(sim.tier_of(hull), SquadSim.DOMAIN_WATER,
		"a water-domain def must put its squad in the water domain")
	assert_eq(sim.tier_of(levy), SquadSim.DOMAIN_GROUND)
	assert_false(Combat._can_reach_domain(sim.tier_of(levy), "shock", sim.tier_of(hull)),
		"a levy on the beach must not be able to melee a hull offshore")
	assert_true(Combat._can_reach_domain(sim.tier_of(levy), "missile", sim.tier_of(hull)),
		"archers on the beach must be able to shoot it")


# --- stage 3 x stage 1: the shore a dock stands on ---------------------

func test_a_dock_stands_where_stage_one_says_a_shore_is() -> void:
	# Stage 1 defines a shore, stage 3 refuses a dock that is not on one.
	# Verified against the arrays the SIM holds rather than against a
	# freshly generated terrain, because the sim's passability has
	# buildings stamped out of it and that is the array a placement is
	# really judged by.
	var w := _wired_world()
	var space: TorusSpace = w["space"]
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	for index in range(space.cell_count()):
		var wet := _is_sea(space.from_index(index).x)
		passable[index] = 0 if wet else 1
		navigable[index] = 1 if wet else 0

	var quay := space.index(Vector2i(SEA_FROM - 1, 8))
	assert_true(TerrainGen.is_shore(space, passable, navigable, quay),
		"the cell a dock is placed on in every naval test must actually be a shore")
	var inland := space.index(Vector2i(SEA_FROM - 5, 8))
	assert_false(TerrainGen.is_shore(space, passable, navigable, inland),
		"and a cell five from the water must not be")


# --- the harness seam --------------------------------------------------

func test_the_estate_can_ask_for_a_map_with_water_on_it() -> void:
	# The seam this verification could not start without. `--preset` has
	# existed on the server since D-049 and no harness could pass one, so
	# every automated run in the repository happened on land — which is
	# why nothing naval had ever been exercised end to end.
	#
	# The same shape as #111's `EDOTMW_MAP`, which existed because the top
	# rung of the map ladder had never been measured for exactly this
	# reason: the server could do it and no recipe could ask.
	var compose := FileAccess.get_file_as_string("res://docker-compose.yml")
	assert_false(compose.is_empty(), "could not read docker-compose.yml")
	assert_true(compose.contains("EDOTMW_PRESET"),
		"a harness must be able to ask for a terrain preset, or the naval estate "
		+ "can only ever be run on land")

	# And the empty case must mean "whatever the MapConfig chose" rather
	# than a preset named "", which resolves to null and would generate
	# `continents`' numbers under a blank name in every log line.
	var server := FileAccess.get_file_as_string("res://server.gd")
	assert_true(server.contains('String(args.get("preset", "")) != ""'),
		"an empty --preset must be ignored, not applied")
