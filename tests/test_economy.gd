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


func test_a_finished_tree_sends_the_crew_to_the_next_one() -> void:
	# With trees a minute deep, "node ran out" happens every haul cycle or
	# so — making the player re-issue the same order per tree would be pure
	# micro tax. The crew walks itself to the nearest surviving node of the
	# same kind within Economy.RETARGET_RADIUS instead.
	var setup := _haul_setup()
	var sim: SquadSim = setup["sim"]
	var economy: Economy = setup["economy"]
	var space: TorusSpace = sim.space
	economy.nodes[setup["node"]]["remaining"] = 3

	var next_cell := space.index(Vector2i(12, 8))  # two cells east, in radius
	economy.nodes[next_cell] = {"kind": Economy.ResourceKind.WOOD, "remaining": 500}

	economy.order_gather(sim, setup["squad"], setup["node"])
	for _i in range(120):
		sim.tick()

	assert_false(economy.has_node(setup["node"]), "The first tree should be gone")
	assert_true(economy.is_gathering(setup["squad"]),
		"The crew should still be employed, on the next tree over")
	assert_lt(economy.remaining_at(next_cell), 500,
		"…and to have actually taken something out of it")


func test_retargeting_never_switches_resource_kind() -> void:
	# "Chop wood" silently becoming "pick apples" is the substitution bug
	# the AI already had fixed once (_nearest_node_of_kind's header). A
	# crew whose tree runs out with only OTHER kinds nearby is released.
	var setup := _haul_setup()
	var sim: SquadSim = setup["sim"]
	var economy: Economy = setup["economy"]
	var space: TorusSpace = sim.space
	economy.nodes[setup["node"]]["remaining"] = 3

	var food_cell := space.index(Vector2i(11, 8))
	economy.nodes[food_cell] = {"kind": Economy.ResourceKind.FOOD, "remaining": 500}

	economy.order_gather(sim, setup["squad"], setup["node"])
	for _i in range(120):
		sim.tick()

	assert_false(economy.is_gathering(setup["squad"]),
		"No wood left in reach — the crew must stop, not start picking apples")
	assert_eq(economy.remaining_at(food_cell), 500,
		"The food node must be untouched")


func test_depletion_is_reported_once_for_the_wire() -> void:
	# The client draws a tree where the server said a node is; when the
	# node runs dry the server has to say so or the tree stands forever.
	# take_depleted() drains — the same event must not replay next tick.
	var setup := _haul_setup()
	var sim: SquadSim = setup["sim"]
	var economy: Economy = setup["economy"]
	economy.nodes[setup["node"]]["remaining"] = 3

	economy.order_gather(sim, setup["squad"], setup["node"])
	for _i in range(60):
		sim.tick()

	assert_false(economy.has_node(setup["node"]), "The node should be exhausted")
	var events := economy.take_depleted()
	assert_has(events, setup["node"], "The felling must be reported")
	assert_eq(economy.take_depleted().size(), 0,
		"Draining hands ownership to the caller — no replay next tick")


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


# --- node density (playtest feedback) ----------------------------------

## The map as a PLAYER gets it: generated, then topped up for fairness.
##
## The first version of these guards measured `generate()` alone and
## reported one node per 68 cells while the shipped map had one per 39.
## `balance_for_spawns` guarantees every spawn a quota of each resource
## within reach, and on a small map that nearly DOUBLES the count — so
## measuring before it is measuring a map nobody plays.
func _generated_map(width: int, height: int) -> Economy:
	var settings := MapSettings.new()
	settings.width = width
	settings.height = height
	var space := settings.to_space()
	var terrain := settings.to_terrain()
	var economy := Economy.new(space)
	economy.generate(terrain, 1)

	var config := load("res://maps/default.tres") as MapConfig
	var passable := terrain.passability(space)
	var spawn_config := MapConfig.new()
	spawn_config.width = width
	spawn_config.height = height
	spawn_config.player_slots = config.player_slots
	spawn_config.min_spawn_spacing = config.min_spawn_spacing
	economy.balance_for_spawns(spawn_config.spawn_points(passable), passable,
		config.fairness_radius, config.fairness_quota)
	return economy


func test_trees_are_abundant_and_ore_stays_scarce() -> void:
	# The forest rework inverted the old "sparse on purpose" rule FOR
	# TREES ONLY: wood and food are many small nodes now (a forest is made
	# of trees, roughly 15x the old node count), while gold and stone keep
	# the old economics — few, rich, worth holding. Bounds rather than
	# exact figures: tuning somebody should be free to move. What must not
	# drift is the SPLIT, which is the design: dense woods, scarce ore.
	for size in MapSettings.sizes():
		var economy := _generated_map(int(size["width"]), int(size["height"]))
		var cells := int(size["width"]) * int(size["height"])
		var trees := 0
		var ore := 0
		for cell in economy.nodes:
			var kind := economy.kind_at(cell)
			if kind == Economy.ResourceKind.WOOD or kind == Economy.ResourceKind.FOOD:
				trees += 1
			else:
				ore += 1
		var per_tree := float(cells) / maxf(float(trees), 1.0)
		assert_lt(per_tree, 8.0,
			"%s: one tree per %.0f cells — that is a prairie with markers, not forests" % [
				size["name"], per_tree])
		assert_gt(per_tree, 2.0,
			"%s: one tree per %.0f cells — a solid lawn leaves nowhere to walk or build" % [
				size["name"], per_tree])
		var per_ore := float(cells) / maxf(float(ore), 1.0)
		assert_gt(per_ore, 100.0,
			"%s: one ore node per %.0f cells — gold and stone are supposed to be places worth fighting over" % [
				size["name"], per_ore])


func test_forests_are_dense_and_open_ground_is_not() -> void:
	# The point of the rework: tree density has to FOLLOW the biome, or the
	# map is back to being a uniform sprinkle with better meshes. Forest
	# cells should mostly carry a tree; grassland mostly should not.
	var space := TorusSpace.new(84, 96, 1.0)
	var terrain := TerrainGen.new()
	var economy := Economy.new(space)
	economy.generate(terrain, 1)

	var forest_cells := 0
	var forest_trees := 0
	var grass_cells := 0
	var grass_trees := 0
	for i in range(space.cell_count()):
		var biome := terrain.biome_at(space, space.from_index(i))
		var wooded := economy.nodes.has(i) \
			and economy.kind_at(i) != Economy.ResourceKind.GOLD \
			and economy.kind_at(i) != Economy.ResourceKind.STONE
		if biome == TerrainGen.Biome.FOREST:
			forest_cells += 1
			if wooded:
				forest_trees += 1
		elif biome == TerrainGen.Biome.GRASSLAND:
			grass_cells += 1
			if wooded:
				grass_trees += 1

	var forest_fill := float(forest_trees) / maxf(float(forest_cells), 1.0)
	var grass_fill := float(grass_trees) / maxf(float(grass_cells), 1.0)
	assert_gt(forest_fill, 0.5,
		"only %.0f%% of forest cells carry a tree — a forest should read as one" % (forest_fill * 100.0))
	assert_lt(grass_fill, 0.35,
		"%.0f%% of grassland carries trees — open ground should stay open" % (grass_fill * 100.0))
	assert_gt(forest_fill, grass_fill * 2.0,
		"forest is barely denser than prairie — density is not following biome")


func test_natural_stone_sits_on_walkable_ground() -> void:
	# The old generator put stone ON mountain cells, which passability()
	# marks unwalkable — so every naturally placed stone node was scenery a
	# crew would march at and stall against (the AI grew its give-up
	# mechanism against exactly these). Stone lives at the mountain FOOT
	# now, which is walkable by construction. This guards the fix.
	var space := TorusSpace.new(84, 96, 1.0)
	var terrain := TerrainGen.new()
	var economy := Economy.new(space)
	economy.generate(terrain, 1)

	var passable := terrain.passability(space)
	var stone := 0
	for cell in economy.nodes:
		if economy.kind_at(cell) != Economy.ResourceKind.STONE:
			continue
		stone += 1
		assert_eq(int(passable[cell]), 1,
			"stone node at cell %d is on impassable ground — unreachable scenery" % cell)
	assert_gt(stone, 0, "the map should grow SOME natural stone at the mountain foot")


func test_a_tree_lasts_about_a_minute_under_one_crew() -> void:
	# The design number: a single shipped gatherer squad works one tree out
	# in roughly a minute. Pinned against the SHIPPED def, not a caricature
	# (D-066's lesson): if squad_size or gather_rate moves, TREE_STOCK has
	# to move with it or every forest quietly changes meaning.
	var def: UnitDef = UnitRoster.by_id(&"gatherers")
	var per_second := float(def.squad_size) * def.gather_rate
	var seconds := float(Economy.TREE_STOCK) / per_second
	assert_between(seconds, 45.0, 75.0,
		"a full crew empties a tree in %.0f s — the design says about a minute" % seconds)


func test_small_maps_are_not_far_denser_than_large_ones() -> void:
	# The specific complaint. Node COUNT scaled with map size correctly all
	# along; the fairness pass did not, so the smallest map came out at one
	# node per 37 cells against one per 57 on the largest — and the small
	# map is the one people test on.
	#
	# Some spread is correct and should not be tuned away: a small map has
	# to seat nearly as many players, and each of them still needs a start.
	var sizes := MapSettings.sizes()
	var smallest := _generated_map(int(sizes[0]["width"]), int(sizes[0]["height"]))
	var largest := _generated_map(int(sizes[-1]["width"]), int(sizes[-1]["height"]))

	var small_per := float(int(sizes[0]["width"]) * int(sizes[0]["height"])) \
		/ maxf(float(smallest.node_count()), 1.0)
	var large_per := float(int(sizes[-1]["width"]) * int(sizes[-1]["height"])) \
		/ maxf(float(largest.node_count()), 1.0)

	assert_lt(large_per / small_per, 2.5,
		"the largest map is %.1fx sparser than the smallest — the fairness "
		% (large_per / small_per) + "top-up is not scaling with the map")


func test_thinning_the_nodes_did_not_starve_the_map() -> void:
	# The change that could quietly ruin every match: NODE_STOCK is raised
	# in step with NODE_EVERY so the map's TOTAL resource stays roughly
	# constant. Fewer, richer nodes is a different map, not a poorer one —
	# cutting the count alone would leave the same armies with a fraction
	# of the economy, and with a 1-2 hour target stripping the map bare is
	# the specific failure to avoid.
	var economy := _generated_map(84, 96)
	var total := 0
	for cell in economy.nodes:
		total += int(economy.nodes[cell]["remaining"])
	assert_gt(total, 250000,
		"only %d resource on the standard map — an hour-long match would strip it bare" % total)


func test_a_depletion_event_round_trips_and_fells_the_client_tree() -> void:
	# The wire half of the felling: NODES tells a client something exists,
	# NODES_DEPLETED tells it that thing no longer does. The client must
	# drop the node immediately (the AI and the minimap read `nodes`) while
	# queueing the felling — WITH its last known kind — for the renderer.
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_nodes([
		{"cell": 42, "kind": Economy.ResourceKind.WOOD},
		{"cell": 77, "kind": Economy.ResourceKind.FOOD},
	]))
	assert_eq(state.nodes.size(), 2)

	state.handle_packet(NetProtocol.encode_nodes_depleted([42]))
	assert_false(state.nodes.has(42), "A felled tree is not a gather target")
	assert_true(state.nodes.has(77), "The other node must be untouched")

	var felled: Array = state.take_felled()
	assert_eq(felled.size(), 1)
	assert_eq(int(felled[0]["cell"]), 42)
	assert_eq(int(felled[0]["kind"]), Economy.ResourceKind.WOOD,
		"The felling must carry the kind — `nodes` no longer knows it")
	assert_eq(state.take_felled().size(), 0, "Draining hands ownership to the caller")


func test_a_depletion_event_for_an_unknown_node_is_ignored() -> void:
	# Fog gating means a client can in principle hear about a cell it was
	# never told carried a node (a server bug, a stale packet after a match
	# reset). That must not fabricate a felling out of nothing.
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_nodes_depleted([13]))
	assert_eq(state.take_felled().size(), 0,
		"No known node at that cell — nothing to fell")


# --- formations (D-058) ------------------------------------------------

func test_a_crew_rings_the_node_it_works_and_spreads_out_to_walk() -> void:
	# A gathering crew standing in walking order looked like a squad that
	# happened to be near a resource rather than one working it. Shape is
	# replicated state, so the SIM owns this — the client cannot infer it,
	# because the haul phase is not on the wire.
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var economy := Economy.new(space)
	sim.economy = economy
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var def := UnitRoster.by_id(&"gatherers")
	assert_not_null(def, "the roster should ship gatherers")
	var node_cell := Vector2i(9, 8)
	economy.nodes[space.index(node_cell)] = {
		"kind": Economy.ResourceKind.FOOD, "remaining": 5000,
	}

	# Ordered from a distance: walking, so spread out.
	var squad := sim.add_squad(def, 1, Vector2i(2, 8))
	economy.order_gather(sim, squad, space.index(node_cell))
	sim.tick()
	assert_eq(sim.shape_of(squad), "sparse",
		"a crew on the road should walk in open order, not ringed around nothing")

	# Now let them arrive.
	for _i in range(400):
		sim.tick()
		if sim.shape_of(squad) == "ring":
			break

	assert_eq(sim.shape_of(squad), "ring",
		"a crew standing on its node should work AROUND it")


func test_a_player_ordered_formation_is_not_overwritten_by_the_economy() -> void:
	# The economy asserts a crew's shape on EVERY tick, so a player who
	# pressed a formation button on gatherers had his choice undone within
	# 100 ms and the button looked broken. A player order latches: the
	# automatic switch is a default, not an override.
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var economy := Economy.new(space)
	sim.economy = economy
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var def := UnitRoster.by_id(&"gatherers")
	assert_not_null(def, "the roster should ship gatherers")
	var node_cell := Vector2i(9, 8)
	economy.nodes[space.index(node_cell)] = {
		"kind": Economy.ResourceKind.FOOD, "remaining": 5000,
	}

	var squad := sim.add_squad(def, 1, Vector2i(2, 8))
	economy.order_gather(sim, squad, space.index(node_cell))
	sim.set_shape(squad, "tight")

	# Long enough to walk there and start working — every tick of which the
	# economy would otherwise have re-asserted "sparse" then "ring".
	for _i in range(400):
		sim.tick()
	assert_eq(sim.shape_of(squad), "tight",
		"the economy overwrote a formation the player chose")


func test_a_crew_the_player_has_never_touched_still_switches_itself() -> void:
	# The other half of the same rule: latching must not disable the
	# automatic switch for everybody else. Guards against "fixing" the test
	# above by simply deleting the economy's shape control.
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var economy := Economy.new(space)
	sim.economy = economy
	sim.buildings = BuildingSim.new(space)

	var node_cell := Vector2i(9, 8)
	economy.nodes[space.index(node_cell)] = {
		"kind": Economy.ResourceKind.FOOD, "remaining": 5000,
	}
	var squad := sim.add_squad(UnitRoster.by_id(&"gatherers"), 1, Vector2i(2, 8))
	economy.order_gather(sim, squad, space.index(node_cell))

	for _i in range(400):
		sim.tick()
		if sim.shape_of(squad) == "ring":
			break
	assert_eq(sim.shape_of(squad), "ring",
		"an untouched crew should still ring the node it works")


func test_a_shape_change_is_offered_to_the_server_exactly_once() -> void:
	# The replication contract. `set_shape` ignores a no-op, which is what
	# lets the economy call it every tick without generating wire traffic —
	# and without that, a gathering crew would resend SQUAD_INFO to every
	# client that can see it ten times a second.
	var space := TorusSpace.new(16, 8, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var squad := sim.add_squad(UnitRoster.first(), 1, Vector2i(2, 2))
	sim.take_shape_dirty()  # clear whatever spawning left

	sim.set_shape(squad, "tight")
	assert_eq(sim.take_shape_dirty(), [squad], "the change was not offered to clients")

	sim.set_shape(squad, "tight")
	assert_eq(sim.take_shape_dirty(), [],
		"setting the same shape again queued a pointless resend")


func test_separating_squads_does_not_evict_crews_from_the_node_they_work() -> void:
	# D-060 pushes arrived squads off each other's cell so armies do not
	# heap. Gathering requires standing ON the node (D-028), and several
	# crews working one node is normal — so separating them meant a
	# displaced crew could never reach the gathering phase and hauled
	# nothing, forever.
	#
	# The ladder showed it as 22 gatherer squads with a stockpile that
	# never rose above the starting 480: an economy fully staffed and
	# producing literally nothing. Nothing in the suite would have caught
	# it, because each feature was correct on its own.
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var economy := Economy.new(space)
	sim.economy = economy
	sim.buildings = BuildingSim.new(space)

	var def := UnitRoster.by_id(&"gatherers")
	var node_cell := Vector2i(10, 8)
	economy.nodes[space.index(node_cell)] = {
		"kind": Economy.ResourceKind.FOOD, "remaining": 9000,
	}

	var crews := []
	for i in range(3):
		var squad := sim.add_squad(def, 1, Vector2i(4 + i, 8))
		economy.order_gather(sim, squad, space.index(node_cell))
		crews.append(squad)

	for _i in range(600):
		sim.tick()

	var working := 0
	for squad in crews:
		if sim.cell_index_of(squad) == space.index(node_cell):
			working += 1
	assert_gt(working, 1,
		"only %d of 3 crews reached the node — separation is evicting them from their work"
		% working)


# --- resource positions are fog-gated (D-061) --------------------------

func test_node_entries_can_be_restricted_to_what_a_player_has_seen() -> void:
	# `node_entries()` sent EVERY node on the map to every client once, at
	# join. Knowing where every resource sits from the moment you connect
	# tells you where an opponent must expand and where to raid, without
	# scouting for any of it — and a modified client could read it
	# straight out of the packet. That is the class of knowledge D-004's
	# curve gating and D-025's fog exist to withhold.
	#
	# It also hid a real AI bug for a whole session: "the AI cannot find
	# wood" was diagnosed as fog when the AI in fact knew every node, and
	# the true fault was reachability.
	var space := TorusSpace.new(32, 16, 1.0)
	var economy := Economy.new(space)
	for cell in [10, 40, 90, 150]:
		economy.nodes[cell] = {"kind": Economy.ResourceKind.WOOD, "remaining": 100}

	assert_eq(economy.node_entries().size(), 4,
		"unrestricted, every node should still be listed — that is what the "
		+ "server needs for its own bookkeeping")

	var seen := economy.node_entries([10, 90])
	assert_eq(seen.size(), 2, "a restricted list should contain only what was asked for")
	var cells := []
	for entry in seen:
		cells.append(int(entry["cell"]))
	cells.sort()
	assert_eq(cells, [10, 90], "the restricted list named the wrong nodes")


func test_asking_for_a_node_that_does_not_exist_yields_nothing() -> void:
	# The boundary: a client that asked about a cell with no node must not
	# get a phantom entry, or "is there a resource here?" becomes
	# answerable for any cell on the map — the leak again, one cell at a
	# time.
	var economy := Economy.new(TorusSpace.new(16, 8, 1.0))
	economy.nodes[5] = {"kind": Economy.ResourceKind.FOOD, "remaining": 10}
	assert_eq(economy.node_entries([99]).size(), 0,
		"a node was invented for a cell that has none")


func test_a_guaranteed_resource_is_one_the_spawn_can_walk_to() -> void:
	# `balance_for_spawns` placed on any PASSABLE cell in range, which on a
	# map with water is not the same as reachable. A spawn behind a channel
	# got its guarantee on the far bank.
	#
	# One AI seat in a 700 s ladder match gathered NOTHING — food and wood
	# still at their starting 220 each — while running 13 worker crews and
	# giving up on 43 nodes it could not walk to. Same defect as the AI's
	# own node choice: distance mistaken for reachability.
	var space := TorusSpace.new(24, 12, 1.0)
	var economy := Economy.new(space)

	# An island: the spawn's column and the one beside it, walled off by
	# water from everything else.
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(0)
	var spawn := Vector2i(4, 4)
	var island := [spawn, Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5), Vector2i(3, 4)]
	for cell in island:
		passable[space.index(cell)] = 1

	economy.balance_for_spawns([spawn], passable, 8, 1)

	for cell_index in economy.nodes:
		var at := space.from_index(int(cell_index))
		assert_true(island.has(at),
			"a guaranteed resource was placed at %s, which the spawn cannot walk to" % at)

	assert_gt(economy.nodes.size(), 0,
		"nothing was placed at all — the fill found no reachable ground, which "
		+ "would starve the spawn just as surely")


# --- fairness top-ups land on ground that grows them (D-104) -----------

func test_a_stone_top_up_goes_to_the_mountain_foot_when_there_is_one() -> void:
	# D-087 moved stone to the mountain FOOT so a node reads as belonging
	# to the ground it sits on, and noted that its old mountain-cell
	# placement was unreachable scenery. The fairness pass then put stone
	# outcrops on grass and sand anyway, because it picked cells by
	# passability alone — the mechanism was right and the post-pass walked
	# straight past it.
	var settings := MapSettings.new()
	settings.width = 84
	settings.height = 96
	settings.seed = 1337
	settings.apply_preset(TerrainPresetRoster.by_id(&"highlands"))
	var space := settings.to_space()
	var terrain := settings.to_terrain()
	var passable := terrain.passability(space)

	# A start with rock in reach: the case where "prefer suitable ground"
	# has an answer to give.
	var spawn := Vector2i(-1, -1)
	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		if passable[index] == 0:
			continue
		if _mountain_foot(space, terrain, coord):
			spawn = coord
			break
	assert_ne(spawn, Vector2i(-1, -1), "No mountain foot on a highlands map — the fixture is wrong, not the code")

	var economy := Economy.new(space)
	economy.generate(terrain, 1)
	# Every quota short, so every kind is placed by the pass under test.
	economy.nodes.clear()
	economy.balance_for_spawns([spawn], passable, 9, 1)

	var stone_cells: Array[Vector2i] = []
	for cell_index in economy.nodes:
		if int(economy.nodes[cell_index]["kind"]) == Economy.ResourceKind.STONE:
			stone_cells.append(space.from_index(int(cell_index)))
	assert_eq(stone_cells.size(), 1, "the pass should have placed exactly one stone node")
	assert_true(_mountain_foot(space, terrain, stone_cells[0]),
		"stone was topped up at %s, which does not border the mountains — an outcrop on open grass" % stone_cells[0])


func test_no_top_up_lands_on_a_beach_while_better_ground_is_free() -> void:
	# What the P01 screenshot was actually showing. A beach cell borders
	# water by definition and the authored node models overhang the cell
	# they sit on, so a rock dropped there reads as standing in the sea.
	#
	# The biome-blind arm is the counter-test: without it this passes just
	# as happily on a map with no beaches at all.
	var settings := MapSettings.new()
	settings.width = 84
	settings.height = 96
	settings.player_slots = 20
	settings.seed = 424242
	settings.apply_preset(TerrainPresetRoster.by_id(&"islands"))
	var space := settings.to_space()
	var terrain := settings.to_terrain()
	var passable := terrain.passability(space)
	var spawns := settings.to_spawn_config().spawn_points(passable)
	assert_gt(spawns.size(), 0, "no spawns, so nothing below proves anything")

	var aware := _top_ups_on_beach(settings, spawns, false)
	var blind := _top_ups_on_beach(settings, spawns, true)

	assert_gt(blind, 0,
		"picking cells by passability alone should still strand top-ups on the shoreline — if it does not, the check below is vacuous")
	assert_eq(aware, 0,
		"%d fairness top-ups were placed on beach cells with other walkable ground free" % aware)


## Does this cell border the mountains? The test's OWN definition, not a
## call into the code under test — a check that asks the implementation
## for its own answer cannot see it being wrong (D-022's audit).
func _mountain_foot(space: TorusSpace, terrain: TerrainGen, coord: Vector2i) -> bool:
	var biome := terrain.biome_at(space, coord)
	if biome == TerrainGen.Biome.MOUNTAIN or biome == TerrainGen.Biome.PEAK \
			or biome == TerrainGen.Biome.WATER or biome == TerrainGen.Biome.DEEP_WATER:
		return false
	for neighbour in space.neighbors(coord):
		var b := terrain.biome_at(space, neighbour)
		if b == TerrainGen.Biome.MOUNTAIN or b == TerrainGen.Biome.PEAK:
			return true
	return false


## How many nodes the fairness pass adds on beach cells. Nulling
## `Economy.terrain` after generation reproduces the old biome-blind pass
## exactly, so both arms run the same code over the same world.
func _top_ups_on_beach(settings: MapSettings, spawns: Array, blind: bool) -> int:
	var space := settings.to_space()
	var terrain := settings.to_terrain()
	var passable := terrain.passability(space)

	var economy := Economy.new(space)
	economy.generate(terrain, 1)
	var before := {}
	for cell in economy.nodes:
		before[cell] = true
	if blind:
		economy.terrain = null
	economy.balance_for_spawns(spawns, passable, 9, 1)

	var beached := 0
	for cell in economy.nodes:
		if before.has(cell):
			continue
		if terrain.biome_at(space, space.from_index(int(cell))) == TerrainGen.Biome.BEACH:
			beached += 1
	return beached
