extends GutTest

## Guards D-20260828-a-vein-runs-deep-it-does-not-run-out (#277).
##
## Gold and stone deplete forever, so a match's metal budget was fixed at
## generation. Measured on the shipped map at seed 1337: **48 gold nodes
## on 32,592 cells**, one per 679, sitting on the mountain perimeter
## (D-087) which is the contested ground. One vein at a shipped crew's
## ~1.96/s is worked out in roughly twenty minutes -- a wall inside the
## first third of a 1-2 hour match (D-056).
##
## A worked-out vein now regrows toward a small tail capacity at a slow
## permanent rate. Three properties carry the design and each has a test:
##
##   - the tail is a FLOOR, not a refill: a live seam is untouched, so the
##     opening is still a race for rich ground;
##   - a vein is never DEPLETED, so no felling is sent for it and the
##     client's tree animation (D-087) is not reinterpreted -- the one
##     player-visible thing #277's brief said must not be compromised;
##   - trees are untouched entirely.

const TICK := 0.1


func _world() -> Dictionary:
	var space := TorusSpace.new(24, 24, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var economy := Economy.new(space)
	economy.space = space
	return {"space": space, "sim": sim, "buildings": buildings, "economy": economy}


func _put(world: Dictionary, cell: Vector2i, kind: int, remaining: int) -> int:
	var space: TorusSpace = world["space"]
	var economy: Economy = world["economy"]
	var index := space.index(cell)
	economy.nodes[index] = {"kind": kind, "remaining": remaining}
	return index


func _run(world: Dictionary, seconds: float) -> void:
	var economy: Economy = world["economy"]
	for _i in range(int(seconds / TICK)):
		economy.tick(world["sim"], world["buildings"], TICK)


# --- the tail is a floor ----------------------------------------------

func test_a_worked_out_vein_comes_back_to_its_tail() -> void:
	# The whole point: a spent gold seam is not dead ground.
	var world := _world()
	var index := _put(world, Vector2i(5, 5), Economy.ResourceKind.GOLD, 0)
	var economy: Economy = world["economy"]
	economy._deep_veins[index] = true

	_run(world, 120.0)
	assert_gt(economy.remaining_at(index), 0,
		"a worked-out gold vein stayed at zero -- the map's metal budget is still fixed")
	assert_almost_eq(float(economy.remaining_at(index)), 30.0, 2.0,
		"two minutes at 0.25/s should be about 30 gold, got %d"
			% economy.remaining_at(index))


func test_the_tail_stops_at_its_capacity() -> void:
	# Capacity BUFFERS; the rate is the income. Without a cap, "leave it
	# alone all match" becomes a strategy -- the same thing
	# `grow_capacity` stops a field doing.
	var world := _world()
	var index := _put(world, Vector2i(5, 5), Economy.ResourceKind.GOLD, 0)
	var economy: Economy = world["economy"]
	economy._deep_veins[index] = true

	_run(world, 3600.0)
	assert_eq(economy.remaining_at(index),
		int(Economy.DEEP_MINE_CAPACITY[Economy.ResourceKind.GOLD]),
		"an hour of regrowth passed the tail capacity")


func test_a_LIVE_seam_is_untouched() -> void:
	# The property that keeps the opening a race for rich ground. A fresh
	# 2,400 node must not tick upward at all -- the tail is a floor under a
	# spent vein, not a slow refill of a rich one.
	var world := _world()
	var index := _put(world, Vector2i(5, 5), Economy.ResourceKind.GOLD,
		Economy.RICH_STOCK)
	var economy: Economy = world["economy"]
	economy._deep_veins[index] = true

	_run(world, 600.0)
	assert_eq(economy.remaining_at(index), Economy.RICH_STOCK,
		"a live seam regrew, so the opening is no longer a race for rich ground")


func test_a_part_dug_vein_above_the_tail_does_not_refill() -> void:
	var world := _world()
	var gold := Economy.ResourceKind.GOLD
	var above := int(Economy.DEEP_MINE_CAPACITY[gold]) + 50
	var index := _put(world, Vector2i(5, 5), gold, above)
	var economy: Economy = world["economy"]
	economy._deep_veins[index] = true

	_run(world, 300.0)
	assert_eq(economy.remaining_at(index), above,
		"a vein above its tail capacity regrew back toward full")


func test_the_fraction_is_carried_or_the_tail_is_nothing() -> void:
	# 0.25/s at a 0.1 s tick is 0.025 a tick. An integer-only version adds
	# floor(0.025) = 0 forever: the mechanism correct and the shipped
	# numbers doing nothing, which is D-055/D-066's family. One tick must
	# yield nothing and forty must yield one.
	var world := _world()
	var index := _put(world, Vector2i(5, 5), Economy.ResourceKind.GOLD, 0)
	var economy: Economy = world["economy"]
	economy._deep_veins[index] = true

	_run(world, TICK)
	assert_eq(economy.remaining_at(index), 0, "a single tick produced a whole unit of gold")
	_run(world, 4.0)
	assert_gt(economy.remaining_at(index), 0,
		"four seconds at 0.25/s produced nothing -- the fraction is being rounded away")


func test_stone_runs_faster_than_gold() -> void:
	# The two rates are derived from what they buy (a 30-gold heavy squad
	# every two minutes; a 120-stone tower every five), so gold must be the
	# scarcer trickle. Asserted as the RELATIONSHIP rather than the
	# numbers, which are the decision's to change.
	assert_gt(float(Economy.DEEP_MINE_PER_SECOND[Economy.ResourceKind.STONE]),
		float(Economy.DEEP_MINE_PER_SECOND[Economy.ResourceKind.GOLD]),
		"gold is the scarcer metal on the map and must be the slower tail")


func test_every_tail_is_far_below_a_live_seam() -> void:
	# The gap is the design. A shipped gatherer crew takes ~1.96/s; a tail
	# anywhere near that would make holding fresh ground pointless.
	for kind in Economy.DEEP_MINE_PER_SECOND:
		assert_lt(float(Economy.DEEP_MINE_PER_SECOND[kind]), 0.5,
			"a tail rate has crept up to a crew's own gathering speed")


# --- what it must not disturb -----------------------------------------

func test_a_vein_is_never_reported_as_depleted() -> void:
	# The client fells a depleted node with a tip-and-sink animation
	# (D-087). A vein must never enter that path, because it has not gone
	# anywhere -- and NOT touching the felling is how #277's "the client
	# animation must stay truthful" is kept.
	var world := _world()
	var economy: Economy = world["economy"]
	var index := _put(world, Vector2i(5, 5), Economy.ResourceKind.GOLD, 0)
	economy._deep_veins[index] = true

	_run(world, 60.0)
	assert_eq(economy.take_depleted().size(), 0,
		"a vein was reported depleted, so the client would fell an outcrop that is still there")


func test_a_tree_still_dies_and_is_still_reported() -> void:
	# The other half, and the one that would break silently: D-087's
	# felling must be untouched. A wood node at zero is depleted, felled
	# and retargeted exactly as before.
	var world := _world()
	var economy: Economy = world["economy"]
	assert_false(Economy.is_vein(Economy.ResourceKind.WOOD),
		"wood became a vein, so trees would stop being felled")
	assert_false(Economy.is_vein(Economy.ResourceKind.FOOD),
		"food became a vein")
	assert_true(Economy.is_vein(Economy.ResourceKind.GOLD))
	assert_true(Economy.is_vein(Economy.ResourceKind.STONE))

	# And a tree does not regrow, whatever else is in the registry.
	var index := _put(world, Vector2i(7, 7), Economy.ResourceKind.WOOD, 0)
	economy._deep_veins[index] = true
	_run(world, 300.0)
	assert_eq(economy.remaining_at(index), 0,
		"a felled tree regrew, which would need a wire event and an animation nobody wrote")


func test_an_untouched_vein_does_not_start_regrowing() -> void:
	# A node nobody has ever dug is not a deep mine. Without this the
	# registry would be every mineral on the map and the per-tick loop
	# would walk 185 entries on the shipped map for nothing.
	var world := _world()
	var economy: Economy = world["economy"]
	var index := _put(world, Vector2i(5, 5), Economy.ResourceKind.GOLD, 10)
	_run(world, 300.0)
	assert_eq(economy.remaining_at(index), 10,
		"a vein no crew has ever worked started regrowing on its own")

# --- through the REAL gather path -------------------------------------

## A crew standing on a vein, ordered to work it, exactly as the economy
## does it in a match. Everything above sets `_deep_veins` by hand and so
## proves the regrowth arithmetic while saying nothing about whether a
## crew working a seam ever REGISTERS one -- which is the wiring, and the
## gap this project keeps finding (a knob wired to nothing, a check whose
## caller is missing).
func _crew_on_a_vein(kind: int, remaining: int) -> Dictionary:
	var space := TorusSpace.new(24, 24, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	var economy := Economy.new(space)
	sim.buildings = buildings
	sim.economy = economy

	var cell := Vector2i(10, 8)
	var index := space.index(cell)
	economy.nodes[index] = {"kind": kind, "remaining": remaining}

	var hall: BuildingDef = BuildingSim.def_by_id(&"town_centre").duplicate()
	hall.build_time = 0.0
	buildings.add_building(hall, 1, Vector2i(8, 8), true)

	var crew: UnitDef = UnitRoster.for_civ_archetype(&"gildedreach", &"gatherers")
	var squad := sim.add_squad(crew, 1, cell)
	assert_true(economy.order_gather(sim, squad, index),
		"setup: a crew standing on a vein must be able to work it")
	return {"sim": sim, "economy": economy, "index": index, "squad": squad}


func test_working_a_vein_out_makes_it_a_deep_mine() -> void:
	# The wiring, driven rather than assumed: a crew empties a small seam
	# and the vein must end up in the regrowing set.
	var world := _crew_on_a_vein(Economy.ResourceKind.GOLD, 8)
	var economy: Economy = world["economy"]
	var sim: SquadSim = world["sim"]
	for _i in range(400):
		sim.tick()
		if economy.remaining_at(world["index"]) <= 0:
			break
	assert_eq(economy.remaining_at(world["index"]), 0,
		"setup: the crew did not work the seam out, so nothing below is tested")
	assert_true(economy._deep_veins.has(world["index"]),
		"a crew worked a gold seam to nothing and it did not become a deep mine")


func test_a_worked_out_vein_is_not_felled_by_the_real_path() -> void:
	# #277's one hard constraint: the client fells a depleted node with a
	# tip-and-sink animation (D-087), and a vein has not gone anywhere. The
	# perturbation that matters here is removing the `is_vein` branch in
	# `_gather` -- which the hand-built tests above cannot see, because
	# they never call it.
	var world := _crew_on_a_vein(Economy.ResourceKind.GOLD, 8)
	var economy: Economy = world["economy"]
	var sim: SquadSim = world["sim"]
	var felled := 0
	for _i in range(400):
		sim.tick()
		felled += economy.take_depleted().size()
	assert_eq(felled, 0,
		"a worked-out gold vein was reported depleted %d time(s), so the client would fell an outcrop that is still standing"
			% felled)


func test_a_worked_out_TREE_is_still_felled_by_the_real_path() -> void:
	# The control, and the assertion that keeps the scoping honest: the
	# same journey through the same code must still fell a tree. If this
	# ever goes quiet, `is_vein` has grown to cover wood and D-087's
	# felling has been deleted by accident.
	var world := _crew_on_a_vein(Economy.ResourceKind.WOOD, 8)
	var economy: Economy = world["economy"]
	var sim: SquadSim = world["sim"]
	var felled := 0
	for _i in range(400):
		sim.tick()
		felled += economy.take_depleted().size()
	assert_gt(felled, 0,
		"a worked-out tree was never reported depleted, so nothing would fell it")
