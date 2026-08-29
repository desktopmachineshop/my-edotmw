extends GutTest

## Guards D-20260828-food-is-grown-not-only-found — the renewable half of
## the economy (#159).
##
## The claim under test is that a match's economy is a RATE and no longer
## only a fixed pile: a field grows food per second forever, an ordinary
## gatherer crew works it through D-028's existing haul cycle, and the
## steady state per field is its own regrow rate however many crews stand
## in it.
##
## Also guards the two structural facts the feature rests on, both of
## which fail silently rather than loudly if they break: a field does not
## block ground movement (`BuildingSim.blocking_cells`) — a crew that
## cannot stand on it can never work it — and the registry is DERIVED from
## the living buildings rather than hooked onto construction, so no path
## that raises a building can forget it (#119's finding).

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _gatherer_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"gatherers"
	d.squad_size = 10
	d.health = 30.0
	d.move_speed = 4.0
	d.formation_shape = "sparse"
	d.formation_spacing = 1.0
	d.morale = 100.0
	d.carry_capacity = 20
	d.gather_rate = 1.0
	return d


func _drop_off_def() -> BuildingDef:
	var d := BuildingDef.new()
	d.id = &"town_centre"
	d.max_health = 500.0
	d.is_drop_off = true
	d.vision_range = 10.0
	return d


## A field that grows 2 food a second into a 40-unit buffer. Deliberately
## not the shipped numbers — this is the MECHANISM, and a fixture pinned
## to shipped values would go red on a balance change that broke nothing.
func _field_def(rate: float = 2.0, capacity: int = 40) -> BuildingDef:
	var d := BuildingDef.new()
	d.id = &"farm"
	d.max_health = 400.0
	d.grows = "food"
	d.grow_capacity = capacity
	d.grow_per_second = rate
	d.blocks_movement = false
	d.vision_range = 4.0
	return d


func _world(rate: float = 2.0, capacity: int = 40) -> Dictionary:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	var economy := Economy.new(space)
	sim.buildings = buildings
	sim.economy = economy

	var field_cell := Vector2i(10, 8)
	buildings.add_building(_field_def(rate, capacity), 1, field_cell, true)
	buildings.add_building(_drop_off_def(), 1, Vector2i(8, 8), true)
	economy.sync_farms(buildings)
	var squad := sim.add_squad(_gatherer_def(), 1, field_cell)

	return {
		"space": space, "sim": sim, "buildings": buildings,
		"economy": economy, "squad": squad,
		"cell": space.index(field_cell),
	}


# --- the schema is read, not merely declared --------------------------

func test_the_shipped_farm_grows_food_and_is_walkable() -> void:
	# The declared-and-unread family (D-055, D-106, #158) is this project's
	# most-repeated defect, so the shipped def is checked against the two
	# readers rather than against itself.
	var def := BuildingSim.def_by_id(&"farm")
	assert_not_null(def, "the roster must ship a farm — #159's whole point")
	assert_eq(Economy.grows_kind(def), Economy.ResourceKind.FOOD,
		"`grows` must resolve to a ResourceKind, or the field grows nothing")
	assert_gt(def.grow_per_second, 0.0, "a field with no rate is not renewable")
	assert_gt(def.grow_capacity, 0, "a field with no buffer yields nothing until it fills")
	assert_false(def.blocks_movement,
		"a crew has to STAND on a field to work it (Economy._gather)")
	assert_gt(def.cost_wood, 0,
		"the farm's whole economic content is converting a finite resource into a rate")


func test_every_other_shipped_building_still_blocks_and_grows_nothing() -> void:
	for def in BuildingSim.all_defs():
		if String(def.id) == "farm":
			continue
		assert_true(def.blocks_movement,
			"%s must keep blocking — the default is the old behaviour" % def.id)
		assert_eq(Economy.grows_kind(def), -1,
			"%s is not a field" % def.id)


func test_a_field_does_not_block_ground_movement() -> void:
	# The one that makes the feature possible at all, and it fails
	# invisibly: a blocking field is a building nobody can ever work, with
	# every other number healthy.
	var w := _world()
	var buildings: BuildingSim = w["buildings"]
	var blocked := buildings.blocking_cells()
	assert_false(Array(blocked).has(int(w["cell"])),
		"a field must not block its own cell")
	assert_true(Array(buildings.occupied_cells()).has(int(w["cell"])),
		"it still OCCUPIES the cell — nothing else may be founded on it")


# --- growth is a rate, capped by a buffer ------------------------------

func test_an_unworked_field_grows_at_its_rate_and_stops_at_capacity() -> void:
	var w := _world(2.0, 40)
	var economy: Economy = w["economy"]
	var sim: SquadSim = w["sim"]
	var cell := int(w["cell"])

	assert_eq(economy.farm_stock(cell), 0, "a fresh field starts empty")
	for i in range(50):  # 5 seconds at the real 10 Hz
		economy.tick(sim, w["buildings"], 0.1)
	# 9 or 10: fifty 0.1 s steps of 2.0 sum to 9.999..., and the stock is
	# floored because `carrying` counts whole things. Asserting 10 exactly
	# would be asserting float addition, not the rate.
	assert_between(economy.farm_stock(cell), 9, 10, "5 s at 2/s is ~10 units")

	for i in range(500):  # far past the buffer
		economy.tick(sim, w["buildings"], 0.1)
	assert_eq(economy.farm_stock(cell), 40,
		"growth stops at capacity — banking must not be a strategy")


func test_a_fresh_field_yields_immediately_rather_than_after_it_fills() -> void:
	# The reason `grow_capacity` is a buffer and not a fill-up: a crew
	# takes whatever has grown. A field that had to fill first would leave
	# a player watching an empty square for two minutes.
	var w := _world(2.0, 40)
	var economy: Economy = w["economy"]
	var sim: SquadSim = w["sim"]
	assert_true(economy.order_gather(sim, int(w["squad"]), int(w["cell"])))
	for i in range(20):  # 2 seconds
		sim.tick()
	assert_gt(economy.carrying(int(w["squad"])), 0,
		"a crew on a brand new field must be carrying something after 2 s")


func test_the_steady_state_is_the_fields_rate_not_the_crews() -> void:
	# THE economic claim. A crew that could take 10/s takes 2/s because
	# that is what the ground grows, so income is raised by owning more
	# fields rather than by piling crews onto one.
	var w := _world(2.0, 40)
	var economy: Economy = w["economy"]
	var sim: SquadSim = w["sim"]
	var squad := int(w["squad"])
	var def := sim.def_of(squad)
	assert_gt(def.gather_rate * float(sim.alive_of(squad)), 2.0,
		"the fixture is vacuous unless the crew could out-take the field")

	assert_true(economy.order_gather(sim, squad, int(w["cell"])))
	# Let the buffer drain first, so what is measured is the STEADY state
	# and not the 40 units that were already in the ground.
	for i in range(600):
		sim.tick()
	var before := economy.amount(1, Economy.ResourceKind.FOOD) \
		+ economy.carrying(squad) + economy.farm_stock(int(w["cell"]))
	for i in range(600):  # 60 s
		sim.tick()
	var after := economy.amount(1, Economy.ResourceKind.FOOD) \
		+ economy.carrying(squad) + economy.farm_stock(int(w["cell"]))

	var gained := after - before
	# 60 s at 2/s is 120. Allowed a unit of slack at each end for the
	# fractional carry, and nothing like the ~600 an unlimited crew would
	# have taken.
	assert_between(gained, 115, 125,
		"a worked field must yield its own rate, not the crew's (got %d)" % gained)


func test_a_field_is_never_worked_out_and_never_reports_a_felling() -> void:
	# The whole point of #159: this is the thing a forest cannot do.
	# `take_depleted` is the wire event that fells a tree, and a farm is a
	# building the client already draws — reporting one would take down a
	# stand that was never there.
	var w := _world(2.0, 40)
	var economy: Economy = w["economy"]
	var sim: SquadSim = w["sim"]
	assert_true(economy.order_gather(sim, int(w["squad"]), int(w["cell"])))
	for i in range(1200):  # 2 minutes
		sim.tick()
	assert_true(economy.has_farm(int(w["cell"])), "the field is still there")
	assert_true(economy.is_work_site(int(w["cell"])), "and still worth working")
	assert_eq(economy.take_depleted().size(), 0,
		"a field must never be reported felled")
	assert_gt(economy.amount(1, Economy.ResourceKind.FOOD), 100,
		"two minutes of a field is a real amount of food")


func test_the_economy_no_longer_has_a_ceiling() -> void:
	# #159 stated as an assertion: with only nodes, total income is bounded
	# by what was placed. With a field it is not.
	var w := _world(2.0, 40)
	var economy: Economy = w["economy"]
	var sim: SquadSim = w["sim"]
	assert_eq(economy.node_count(), 0, "no natural nodes in this world at all")
	assert_true(economy.order_gather(sim, int(w["squad"]), int(w["cell"])))
	for i in range(600):
		sim.tick()
	var first := economy.amount(1, Economy.ResourceKind.FOOD)
	for i in range(600):
		sim.tick()
	assert_gt(economy.amount(1, Economy.ResourceKind.FOOD), first,
		"income must keep arriving on a map with nothing placed on it")


# --- the registry is derived, not accumulated -------------------------

func test_a_razed_field_stops_being_a_work_site() -> void:
	var w := _world()
	var economy: Economy = w["economy"]
	var buildings: BuildingSim = w["buildings"]
	assert_true(economy.has_farm(int(w["cell"])))
	buildings.damage(0, 100000.0)
	economy.sync_farms(buildings)
	assert_false(economy.has_farm(int(w["cell"])),
		"a razed field is not a work site — that is what makes raiding worth it")
	assert_false(economy.is_work_site(int(w["cell"])))


func test_an_unfinished_field_grows_nothing() -> void:
	var space := _space()
	var buildings := BuildingSim.new(space)
	var economy := Economy.new(space)
	buildings.add_building(_field_def(), 1, Vector2i(4, 4), false)
	economy.sync_farms(buildings)
	assert_eq(economy.farm_count(), 0, "a field under construction is a building site")


func test_a_resync_keeps_stock_that_has_already_grown() -> void:
	# A resync happens whenever ANY building is raised or lost, which is
	# constantly. Dropping the stock would make a player's harvest depend
	# on their neighbour's construction schedule.
	var w := _world(2.0, 40)
	var economy: Economy = w["economy"]
	var sim: SquadSim = w["sim"]
	for i in range(50):
		economy.tick(sim, w["buildings"], 0.1)
	var grown := economy.farm_stock(int(w["cell"]))
	assert_gt(grown, 0, "the fixture must have grown something to keep")
	economy.sync_farms(w["buildings"])
	assert_eq(economy.farm_stock(int(w["cell"])), grown,
		"a resync must not throw away a standing field's harvest")


# --- a field belongs to somebody --------------------------------------

func test_an_enemy_may_not_work_your_field() -> void:
	# A node is unowned ground and anyone may work it (D-028, unchanged).
	# A field is a building somebody paid for.
	var w := _world()
	var economy: Economy = w["economy"]
	var sim: SquadSim = w["sim"]
	var space: TorusSpace = w["space"]
	var thief := sim.add_squad(_gatherer_def(), 2, space.from_index(int(w["cell"])))
	assert_false(economy.may_work(sim, thief, int(w["cell"])),
		"an enemy crew may not harvest your fields")
	assert_false(economy.order_gather(sim, thief, int(w["cell"])),
		"and the order must be refused, not merely discouraged")
	assert_true(economy.may_work(sim, int(w["squad"]), int(w["cell"])),
		"the owner may, or the fixture proves nothing")


func test_an_ally_may_work_your_field() -> void:
	# D-050 gives teams a shared front and shared sight; a teammate locked
	# out of your fields would be a worse partner than an enemy.
	var w := _world()
	var economy: Economy = w["economy"]
	var sim: SquadSim = w["sim"]
	var space: TorusSpace = w["space"]
	sim.teams = {1: 1, 2: 1}
	var friend := sim.add_squad(_gatherer_def(), 2, space.from_index(int(w["cell"])))
	assert_true(sim.are_allied(1, 2), "the fixture must actually be an alliance")
	assert_true(economy.may_work(sim, friend, int(w["cell"])))


func test_a_crew_retargets_between_fields_but_never_onto_an_enemys() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	var economy := Economy.new(space)
	sim.buildings = buildings
	sim.economy = economy

	var mine := Vector2i(10, 8)
	var also_mine := Vector2i(12, 8)
	var theirs := Vector2i(11, 8)
	buildings.add_building(_field_def(), 1, mine, true)
	buildings.add_building(_field_def(), 1, also_mine, true)
	buildings.add_building(_field_def(), 2, theirs, true)
	buildings.add_building(_drop_off_def(), 1, Vector2i(8, 8), true)
	economy.sync_farms(buildings)

	var squad := sim.add_squad(_gatherer_def(), 1, mine)
	assert_true(economy.order_gather(sim, squad, space.index(mine)))

	# Raze the one it is working; the crew must step to the other of MINE,
	# which is further away than the enemy's.
	buildings.damage(0, 100000.0)
	economy.sync_farms(buildings)
	for i in range(5):
		sim.tick()
	assert_true(economy.is_gathering(squad),
		"a crew whose field is razed steps to the next one, it does not stand down")
	assert_eq(economy.wallet_of(2).size(), Economy.RESOURCE_COUNT)
	# Whatever it picked, it must not be the enemy's — and `_retarget`
	# walks the disk NEAREST-FIRST, so the enemy's field is the one it
	# would have taken without the ownership guard.
	var working := -1
	for i in range(200):
		sim.tick()
		if sim.cell_index_of(squad) == space.index(also_mine):
			working = space.index(also_mine)
			break
	assert_eq(working, space.index(also_mine),
		"it must have walked to its OWN other field")


# --- what the client derives ------------------------------------------

func test_a_client_derives_its_fields_from_buildings_it_already_knows() -> void:
	# Nothing new is on the wire. A field is a building, and a building is
	# already replicated and already fog-gated knowledge (D-030) — the same
	# shape as D-052's colour and D-20260825's tool choice.
	var state := ClientState.new()
	state.player = 1
	state.buildings[1] = {
		"def_id": "farm", "owner": 1, "cell": 42,
		"progress": 1.0, "destroyed": false,
	}
	state.buildings[2] = {
		"def_id": "farm", "owner": 2, "cell": 43,
		"progress": 1.0, "destroyed": false,
	}
	state.buildings[3] = {
		"def_id": "barracks", "owner": 1, "cell": 44,
		"progress": 1.0, "destroyed": false,
	}
	state.buildings[4] = {
		"def_id": "farm", "owner": 1, "cell": 45,
		"progress": 0.4, "destroyed": false,
	}
	state.buildings[5] = {
		"def_id": "farm", "owner": 1, "cell": 46,
		"progress": 1.0, "destroyed": true,
	}

	var all_fields := state.farm_cells()
	assert_eq(all_fields.size(), 2, "both complete, living farms are KNOWN")
	assert_eq(int(all_fields[42]), Economy.ResourceKind.FOOD)
	assert_eq(state.work_kind_at(44), -1, "a barracks is not worked ground")
	assert_eq(state.work_kind_at(45), -1, "nor is a building site")
	assert_eq(state.work_kind_at(46), -1, "nor is rubble")

	var workable := state.farm_cells(true)
	assert_eq(workable.size(), 1,
		"only my own — offering an enemy's would swallow the move order I meant")
	assert_true(workable.has(42))


func test_a_node_still_wins_over_a_field_the_client_knows_about() -> void:
	# They cannot genuinely overlap (`server._can_build_at` refuses a node's
	# cell), but the tie has to resolve the same way on both sides.
	var state := ClientState.new()
	state.player = 1
	state.nodes[42] = Economy.ResourceKind.WOOD
	state.buildings[1] = {
		"def_id": "farm", "owner": 1, "cell": 42,
		"progress": 1.0, "destroyed": false,
	}
	assert_eq(state.work_kind_at(42), Economy.ResourceKind.WOOD)


# --- the harnesses actually exercise it -------------------------------

func test_a_load_test_bot_wants_several_fields_and_one_of_everything_else() -> void:
	# The "one configuration nothing runs" rule (#119, #123): a renewable
	# economy only a human ever builds is a renewable economy nothing tests.
	var farm := BuildingSim.def_by_id(&"farm")
	var barracks := BuildingSim.def_by_id(&"barracks")
	assert_gt(BotBuildPlan.wanted_count(farm), 1,
		"a field's output is a rate — one of them is not an economy")
	assert_eq(BotBuildPlan.wanted_count(barracks), 1)

	# ONE field first — measured, not preferred: a bot saves for what it
	# wants rather than falling through to something cheaper, and a
	# barracks at 150 wood against a 140-200 `wood_peak` meant a
	# producers-first order reached a field in zero runs.
	var first := BotBuildPlan.wanted_building(["town_centre"], &"gatherers")
	assert_not_null(first)
	assert_eq(String(first.id), "farm",
		"the first field must come before the saving-up starts, or it never happens")

	# Then producers — an economy that never fields an army is not what
	# the load test is for.
	var owned := ["town_centre", "farm"]
	var second := BotBuildPlan.wanted_building(owned, &"gatherers")
	assert_not_null(second)
	assert_false(second.produces.is_empty(),
		"anything that trains soldiers comes before the SECOND field")

	# Then the rest of the fields, stopping at FIELDS_WANTED.
	#
	# HOW MANY producers exist is a property of the ROSTER, not of this
	# rule, so the producers are drained rather than assumed to be one.
	# They were one (the barracks) until naval stage 6 landed a dock that
	# `produces` ships, and a fixture pinned to "the third building" then
	# reads a correct plan as a regression — the same shape as the unit-id
	# lists D-20260828-a-guard-is-written-in-a-vocabulary-that-moves
	# records, arriving in a test rather than in a guard.
	owned.append(String(second.id))
	var next_def := BotBuildPlan.wanted_building(owned, &"gatherers")
	var drained := 0
	while next_def != null and not next_def.produces.is_empty():
		owned.append(String(next_def.id))
		next_def = BotBuildPlan.wanted_building(owned, &"gatherers")
		drained += 1
		assert_true(drained < 12,
			"the producer list never drained — wanted_building is looping")
	assert_not_null(next_def)
	assert_eq(String(next_def.id), "farm",
		"a field is the one support building a bot raises")
	for i in range(BotBuildPlan.FIELDS_WANTED):
		owned.append("farm")
	assert_null(BotBuildPlan.wanted_building(owned, &"gatherers"),
		"and it stops at FIELDS_WANTED rather than paving the map")


func test_an_ai_wants_several_fields_and_only_after_something_that_trains() -> void:
	# `_wanted_count` is the AI's half of the same rule, and it is asked of
	# the DEF rather than of an id so a civ's own field is covered without
	# `ai_player.gd` learning a name (D-046 criterion 3).
	#
	# The AI keeps producers-first, unlike the bots: it saves for what it
	# wants and its matches are long enough to reach a barracks, where a
	# load run is not. That asymmetry is deliberate and is why the two
	# have separate rules rather than one shared one.
	var ai = load("res://ai_player.gd").new()
	ai.profile = AiProfileRoster.default()
	assert_not_null(ai.profile)
	assert_eq(ai._wanted_count(BuildingSim.def_by_id(&"barracks")), 1)
	assert_eq(ai._wanted_count(BuildingSim.def_by_id(&"storehouse")), 1)
	assert_eq(ai._wanted_count(BuildingSim.def_by_id(&"farm")), ai.profile.farms_wanted,
		"an AI wants as many fields as its difficulty says, not one")
	assert_gt(ai.profile.farms_wanted, 1)

	# And the farm has to actually be in the list it walks, or the count
	# above is arithmetic nothing consults.
	var wanted: Array = ai._wanted_buildings()
	var ids := []
	for def in wanted:
		ids.append(String(def.id))
	assert_true(ids.has("farm"), "a field must be something the AI considers at all")
	assert_true(ids.find("barracks") < ids.find("farm"),
		"and it considers what trains soldiers first")


func test_no_shipped_ai_profile_wants_a_negative_number_of_fields() -> void:
	var seen := 0
	for def in AiProfileRoster.load_all():
		assert_eq(def.validate(), "", "%s must be a valid profile" % def.id)
		assert_gt(def.farms_wanted, 0,
			"%s would never build a field, so its economy still ends" % def.id)
		seen += 1
	assert_gt(seen, 0, "there must be profiles to check, or this proves nothing")


# --- the server actually performs the derivation ----------------------

## A headless server, near enough to real to run a build to completion.
##
## "server.gd needs a socket and a scene tree" is true of `_ready()`, not
## of the file (D-075's 2026-08-16 amendment, applied again by #158): a
## Node never added to the tree does not run it, and `LoopbackPeer` is
## already the server's own stand-in for a socket (D-051).
func _server_world() -> Dictionary:
	var server = load("res://server.gd").new()
	var space := TorusSpace.new(W, H, 1.0)

	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy
	server._passable = PackedByteArray()
	server._passable.resize(space.cell_count())
	server._passable.fill(1)
	server._sim.set_passable(server._passable)

	server._match = MatchState.new()
	server._match.add_player(1)
	server._match.phase = MatchState.Phase.RUNNING

	for kind in range(Economy.RESOURCE_COUNT):
		server._economy.credit(1, kind, 100000)

	var peer := LoopbackPeer.new()
	server._ai_clients[peer] = {"player": 1, "visible": {}}
	return {"server": server, "peer": peer, "space": space}


func test_a_farm_the_server_finishes_becomes_a_work_site() -> void:
	# The check that would have caught a perfectly correct `sync_farms`
	# nobody calls — this project's most-repeated defect (D-055, D-106,
	# #158), and the one every behaviour test above passes straight
	# through.
	#
	# Through the ORDINARY construction path: the order commits, the
	# building rises at 0 progress, and the server's own tick notices the
	# completion. A field registered only by the sandbox's instant build
	# would be a field no player could ever raise.
	var w := _server_world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	var def := BuildingSim.def_by_id(&"farm")
	assert_not_null(def)

	var site := Vector2i(6, 6)
	var crew: int = server._sim.add_squad(_gatherer_def(), 1, site)
	server._finish_build(w["peer"], crew, def, site)
	assert_eq(server._buildings.building_count(), 1, "the field was founded")
	assert_false(server._economy.has_farm(space.index(site)),
		"a building SITE is not a field yet — this is what makes the next line mean something")

	server._buildings.advance_construction(def.build_time + 1.0)
	assert_true(server._buildings.is_complete(0), "the fixture must actually finish it")
	# What `server.tick()` does on a tick where something completed.
	server._refresh_passability()

	assert_true(server._economy.has_farm(space.index(site)),
		"and the server derived it into the economy without being told twice")
	assert_true(server._economy.is_work_site(space.index(site)))
	# And it is walkable, all the way through to the passability array the
	# simulation routes on — the property a crew standing in it depends on.
	assert_eq(int(server._passable[space.index(site)]), 1,
		"a field must leave its ground walkable after _refresh_passability")
	server.free()


func test_a_razed_farm_stops_being_a_work_site_on_the_server_too() -> void:
	var w := _server_world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	var site := Vector2i(6, 6)
	var def := BuildingSim.def_by_id(&"farm")
	var crew: int = server._sim.add_squad(_gatherer_def(), 1, site)
	server._finish_build(w["peer"], crew, def, site)
	server._buildings.advance_construction(def.build_time + 1.0)
	server._refresh_passability()
	assert_true(server._economy.has_farm(space.index(site)))

	server._buildings.damage(0, 100000.0)
	server._refresh_passability()
	assert_false(server._economy.has_farm(space.index(site)),
		"burning a field must actually stop the food")
	server.free()
