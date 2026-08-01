extends GutTest

## Guards D-028 (the gathering economy) and D-037 (biome-derived nodes),
## against D-027's criteria 6, 7 and 8.
##
## The claim under test is D-005's: a gathering economy without per-unit
## anything. A gatherer crew is a SQUAD with a job — one curve, one
## flow-field path, one network entity — so output scales with `alive`,
## casualties cut income with no special case, and every leg of the haul
## is an ordinary move order.

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _gatherer_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"gatherers"
	d.squad_size = 10
	d.health = 30.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.move_speed = 4.0
	d.formation_shape = "loose"
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


## A sim with one gatherer squad, one node under it, and a drop-off two
## cells away — the smallest thing that can complete a round trip.
func _haul_setup() -> Dictionary:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	var economy := Economy.new(space)
	sim.buildings = buildings
	sim.economy = economy

	var node_cell := Vector2i(10, 8)
	economy.nodes[space.index(node_cell)] = {
		"kind": Economy.ResourceKind.WOOD, "remaining": 500,
	}
	buildings.add_building(_drop_off_def(), 1, Vector2i(8, 8), true)
	var squad := sim.add_squad(_gatherer_def(), 1, node_cell)

	return {
		"sim": sim, "buildings": buildings, "economy": economy,
		"squad": squad, "node": space.index(node_cell),
	}


# --- nodes come from terrain (D-037) ----------------------------------

func test_nodes_are_derived_from_biome_and_are_deterministic() -> void:
	var space := _space()
	var terrain := TerrainGen.new()

	var first := Economy.new(space)
	first.generate(terrain)
	var second := Economy.new(space)
	second.generate(terrain)

	assert_gt(first.node_count(), 0, "A generated map should carry resources")
	assert_eq(first.node_count(), second.node_count(),
		"Same terrain, same nodes — replays depend on it (D-016)")
	for cell in first.nodes:
		assert_true(second.nodes.has(cell), "Node placement must be deterministic")
		assert_eq(first.kind_at(cell), second.kind_at(cell))


func test_nodes_never_sit_on_water() -> void:
	# You cannot chop a lake, and a node squads cannot walk to is a node
	# that does nothing but mislead the player.
	var space := _space()
	var terrain := TerrainGen.new()
	var economy := Economy.new(space)
	economy.generate(terrain)

	for cell in economy.nodes:
		var biome := terrain.biome_at(space, space.from_index(cell))
		assert_false(biome == TerrainGen.Biome.WATER or biome == TerrainGen.Biome.DEEP_WATER,
			"A node was placed on water at cell %d" % cell)


func test_every_start_is_guaranteed_a_minimum_of_each_resource() -> void:
	# Fairness used to be exact, because the map was four copies of one
	# quadrant (D-036). That made every match the same map four times, so
	# terrain is generated freely now and fairness is a POST-PASS: nobody
	# is allowed to start with no wood within reach.
	#
	# This is the test that replaces the symmetry one, and it is a weaker
	# guarantee on purpose — "approximately fair" rather than "identical".
	var space := TorusSpace.new(64, 32, 1.0)
	var terrain := TerrainGen.new()  # axis_repeats 1: no symmetry
	var economy := Economy.new(space)
	economy.generate(terrain, 1)

	var spawns := [Vector2i(8, 8), Vector2i(40, 8), Vector2i(8, 24), Vector2i(40, 24)]
	var radius := 12
	var quota := 3
	economy.balance_for_spawns(spawns, terrain.passability(space), radius, quota)

	for spawn in spawns:
		for kind in range(Economy.RESOURCE_COUNT):
			var found := 0
			for offset in TorusSpace.disk_offsets(radius):
				var index := space.index(spawn + offset)
				if economy.nodes.has(index) and economy.kind_at(index) == kind:
					found += 1
			assert_true(found >= quota,
				"Spawn %s has only %d of resource %d within %d cells — a start with no way to get one resource has lost at map-generation time" % [
					spawn, found, kind, radius])


func test_an_unbalanced_map_can_genuinely_be_short() -> void:
	# The counter-test: without the balancing pass, at least one start on
	# at least one seed IS short of something. Otherwise the test above
	# would pass whether or not balance_for_spawns did anything.
	var space := TorusSpace.new(64, 32, 1.0)
	var terrain := TerrainGen.new()
	var economy := Economy.new(space)
	economy.generate(terrain, 1)

	var spawns := [Vector2i(8, 8), Vector2i(40, 8), Vector2i(8, 24), Vector2i(40, 24)]
	var shortfalls := 0
	for spawn in spawns:
		for kind in range(Economy.RESOURCE_COUNT):
			var found := 0
			for offset in TorusSpace.disk_offsets(12):
				var index := space.index(spawn + offset)
				if economy.nodes.has(index) and economy.kind_at(index) == kind:
					found += 1
			if found < 3:
				shortfalls += 1

	assert_gt(shortfalls, 0,
		"Raw generated terrain should be unfair somewhere — if it were not, the balancing pass would be proving nothing")


# --- the haul cycle (D-028) -------------------------------------------

func test_a_gatherer_squad_fills_up_hauls_and_delivers() -> void:
	var setup := _haul_setup()
	var sim: SquadSim = setup["sim"]
	var economy: Economy = setup["economy"]
	var squad: int = setup["squad"]

	assert_true(economy.order_gather(sim, squad, setup["node"]),
		"A gatherer squad standing on a node can work it")

	var delivered := false
	for _i in range(200):
		sim.tick()
		if economy.amount(1, Economy.ResourceKind.WOOD) > 0:
			delivered = true
			break

	assert_true(delivered, "A full crew must eventually deliver its load to the drop-off")
	assert_eq(economy.carrying(squad), 0, "And be empty again afterwards")


func test_gathering_depletes_the_node() -> void:
	var setup := _haul_setup()
	var sim: SquadSim = setup["sim"]
	var economy: Economy = setup["economy"]

	var before := economy.remaining_at(setup["node"])
	economy.order_gather(sim, setup["squad"], setup["node"])
	for _i in range(20):
		sim.tick()

	assert_lt(economy.remaining_at(setup["node"]), before,
		"Nodes are finite — depletion is what pushes armies onto new ground")


func test_income_scales_with_the_surviving_crew() -> void:
	# The reason gatherers are squads at all: casualties cut output with
	# no special case anywhere.
	var full := _haul_setup()
	var full_sim: SquadSim = full["sim"]
	full["economy"].order_gather(full_sim, full["squad"], full["node"])
	for _i in range(10):
		full_sim.tick()
	var full_take: int = 500 - full["economy"].remaining_at(full["node"])

	var halved := _haul_setup()
	var halved_sim: SquadSim = halved["sim"]
	halved_sim.set_alive(halved["squad"], 5)  # half the crew
	halved["economy"].order_gather(halved_sim, halved["squad"], halved["node"])
	for _i in range(10):
		halved_sim.tick()
	var halved_take: int = 500 - halved["economy"].remaining_at(halved["node"])

	assert_lt(halved_take, full_take, "Half a crew must gather less than a whole one")


func test_a_worked_out_node_releases_the_squad() -> void:
	var setup := _haul_setup()
	var sim: SquadSim = setup["sim"]
	var economy: Economy = setup["economy"]
	economy.nodes[setup["node"]]["remaining"] = 1

	economy.order_gather(sim, setup["squad"], setup["node"])
	for _i in range(60):
		sim.tick()

	assert_false(economy.has_node(setup["node"]), "The node should be exhausted")
	assert_false(economy.is_gathering(setup["squad"]),
		"A squad must not stand on an empty patch forever")


func test_a_fighting_unit_cannot_be_told_to_gather() -> void:
	var setup := _haul_setup()
	var sim: SquadSim = setup["sim"]
	var soldier_def := _gatherer_def()
	soldier_def.id = &"militia"
	soldier_def.carry_capacity = 0  # not a gatherer
	var soldier := sim.add_squad(soldier_def, 1, sim.space.from_index(setup["node"]))

	assert_false(setup["economy"].order_gather(sim, soldier, setup["node"]),
		"carry_capacity is what makes a unit a gatherer — there is no second flag")


func test_gathering_an_empty_cell_is_refused() -> void:
	var setup := _haul_setup()
	assert_false(setup["economy"].order_gather(setup["sim"], setup["squad"], 0),
		"There is nothing at cell 0 to work")


# --- wallets (D-028) ---------------------------------------------------

func test_wallets_start_empty_and_are_per_player() -> void:
	var economy := Economy.new(_space())
	assert_eq(economy.amount(1, Economy.ResourceKind.FOOD), 0)

	economy.credit(1, Economy.ResourceKind.FOOD, 100)
	assert_eq(economy.amount(1, Economy.ResourceKind.FOOD), 100)
	assert_eq(economy.amount(2, Economy.ResourceKind.FOOD), 0,
		"One player's income is not another's")
	assert_eq(economy.amount(1, Economy.ResourceKind.WOOD), 0,
		"And food is not wood")


func test_spending_is_all_or_nothing() -> void:
	# A half-paid barracks is worse than a refused one.
	var economy := Economy.new(_space())
	economy.credit(1, Economy.ResourceKind.WOOD, 100)
	economy.credit(1, Economy.ResourceKind.STONE, 10)

	assert_false(economy.try_spend(1, 0, 50, 0, 50), "Cannot afford the stone")
	assert_eq(economy.amount(1, Economy.ResourceKind.WOOD), 100,
		"A refused purchase must not have spent the wood either")

	assert_true(economy.try_spend(1, 0, 50, 0, 10))
	assert_eq(economy.amount(1, Economy.ResourceKind.WOOD), 50)
	assert_eq(economy.amount(1, Economy.ResourceKind.STONE), 0)


# --- production closes the loop (D-028, D-031) ------------------------

func test_a_building_produces_only_what_its_def_lists() -> void:
	var buildings := BuildingSim.new(_space())
	var def := _drop_off_def()
	def.produces = [&"gatherers"] as Array[StringName]
	var hall := buildings.add_building(def, 1, Vector2i(4, 4), true)

	assert_true(buildings.can_produce(hall, &"gatherers"))
	assert_false(buildings.can_produce(hall, &"cavalry"),
		"A town centre does not make horsemen")


func test_a_building_site_cannot_produce() -> void:
	var buildings := BuildingSim.new(_space())
	var def := _drop_off_def()
	def.produces = [&"gatherers"] as Array[StringName]
	var hall := buildings.add_building(def, 1, Vector2i(4, 4), false)
	assert_false(buildings.can_produce(hall, &"gatherers"),
		"You cannot recruit out of a foundation")


func test_production_finishes_and_puts_a_squad_on_the_map() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var def := _drop_off_def()
	def.produces = [&"gatherers"] as Array[StringName]
	var hall := buildings.add_building(def, 1, Vector2i(6, 6), true)

	var unit: UnitDef = UnitRoster.by_id(&"gatherers")
	assert_not_null(unit)
	var before := sim.squad_count()
	buildings.enqueue(hall, unit)
	assert_eq(buildings.queue_length(hall), 1)

	for _i in range(int(unit.build_time * SquadSim.TICK_HZ) + 5):
		sim.tick()

	assert_eq(buildings.queue_length(hall), 0, "The queue should have drained")
	assert_gt(sim.squad_count(), before, "A finished unit must actually appear on the map")
	assert_eq(sim.owner_of(before), 1, "And belong to the building's owner")


func test_wallets_round_trip_and_carry_no_player_id() -> void:
	# The absence is the point: a wallet message is always about the
	# client receiving it, so there is no field a modified client could
	# use to ask about somebody else's (D-028).
	var totals := PackedInt32Array([10, 20, 30, 40])
	var bytes := NetProtocol.encode_wallet(totals)
	assert_eq(NetProtocol.opcode_of(bytes), NetProtocol.S2C_WALLET)

	var decoded := NetProtocol.decode_wallet(bytes)
	assert_eq(decoded.size(), Economy.RESOURCE_COUNT)
	for i in range(Economy.RESOURCE_COUNT):
		assert_eq(decoded[i], totals[i])

	var state := ClientState.new()
	state.handle_packet(bytes)
	assert_eq(state.wallet[Economy.ResourceKind.GOLD], 30)
	assert_eq(state.wallet_updates, 1)


func test_produce_orders_round_trip() -> void:
	var bytes := NetProtocol.encode_order_produce(BuildingSim.wire_id(2), "gatherers")
	assert_eq(NetProtocol.opcode_of(bytes), NetProtocol.C2S_ORDER_PRODUCE)
	var decoded := NetProtocol.decode_order_produce(bytes)
	assert_eq(BuildingSim.local_id(int(decoded["building"])), 2)
	assert_eq(String(decoded["def_id"]), "gatherers")


func test_the_starting_stockpile_covers_a_town_hall_plus_a_few_workers() -> void:
	# The opening has to be *possible*. A player starts with founders and
	# nothing else, so the stockpile must pay for the hall they found AND
	# leave enough to staff it — otherwise founding is a move that strands
	# you with an empty base and no way to begin.
	#
	# Asserted as a RELATIONSHIP rather than against fixed numbers, so
	# retuning any cost cannot quietly make the opening unplayable: that
	# failure would show up as a confusing playtest, not as a red test,
	# which is exactly how the first version of this shipped (a hall
	# costing stone nobody starts with).
	const WORKERS_AFFORDABLE := 3

	var config: MapConfig = load("res://maps/default.tres")
	var hall: BuildingDef = load("res://buildings/town_centre.tres")
	var worker: UnitDef = UnitRoster.by_id(&"gatherers")
	assert_not_null(config)
	assert_not_null(hall)
	assert_not_null(worker)

	var economy := Economy.new(config.to_space())
	economy.credit(1, Economy.ResourceKind.FOOD, config.starting_food)
	economy.credit(1, Economy.ResourceKind.WOOD, config.starting_wood)
	economy.credit(1, Economy.ResourceKind.GOLD, config.starting_gold)
	economy.credit(1, Economy.ResourceKind.STONE, config.starting_stone)

	assert_true(
		economy.try_spend(1, hall.cost_food, hall.cost_wood, hall.cost_gold, hall.cost_stone),
		"A player must be able to afford the town hall they are sent out to found")

	for i in range(WORKERS_AFFORDABLE):
		assert_true(
			economy.try_spend(1, worker.cost_food, worker.cost_wood, worker.cost_gold, worker.cost_stone),
			"And to staff it: worker %d of %d was unaffordable" % [i + 1, WORKERS_AFFORDABLE])


func test_every_building_costs_something() -> void:
	# Same reasoning as the unit version below. A free building makes
	# construction a formality rather than a decision.
	for name in ["town_centre", "barracks", "storehouse", "tower"]:
		var def: BuildingDef = load("res://buildings/%s.tres" % name)
		assert_not_null(def, "buildings/%s.tres should load" % name)
		var total := def.cost_food + def.cost_wood + def.cost_gold + def.cost_stone
		assert_gt(total, 0, "%s is free, which makes construction a formality" % name)


func test_every_producible_unit_costs_something() -> void:
	# A free unit makes the economy decorative, and this is exactly the
	# trap UnitDef.cost fell into: declared, plausible-looking, read by
	# nothing for two milestones.
	# EVERY shipped unit, not a named list. A list would have to be edited
	# whenever a civ is added (D-047), and the one thing D-046 criterion 3
	# is protecting is that adding a civ needs no edits to anything but
	# .tres files — a test that had to be updated would be the same
	# maintenance burden wearing a different hat.
	var checked := 0
	for def in UnitRoster.load_all():
		var total := def.cost_food + def.cost_wood + def.cost_gold + def.cost_stone
		assert_gt(total, 0, "%s is free, which makes the economy decorative" % def.id)
		checked += 1
	assert_gt(checked, 0, "No units were checked, so this proves nothing")


func test_the_shipped_gatherer_can_actually_gather() -> void:
	var def: UnitDef = UnitRoster.by_id(&"gatherers")
	assert_not_null(def, "The roster must ship a 'gatherers' unit")
	assert_gt(def.carry_capacity, 0, "It has to be able to carry something")
	assert_gt(def.gather_rate, 0.0, "And to gather at some rate")

	var founders: UnitDef = UnitRoster.by_id(&"founders")
	assert_eq(founders.carry_capacity, 0,
		"Founders found towns; hauling is the gatherers' job")
