extends GutTest

## Guards naval stage 2 — the water domain (#301, `docs/plans/naval.md`
## §2.2, §2.3, §2.4).
##
## Stage 2's done-when is "a water squad paths", plus a MEASURED budget
## and worst tick. The measurement is `playtest_obs/obs_water_budget.gd`
## and its table is in the decision entry; this file guards the rules the
## measurement rests on, and the seams that fail silently.
##
## ## The seam that matters most
##
## Naval stage 4 shipped before this, against pinned signatures, and its
## embark trigger is an order that DELIBERATELY names a cell in the other
## domain. §2.4's correction — "a land squad ordered to a water cell is
## corrected to the nearest passable land cell" — would swallow every one
## of them if it ran first. The ordering inside `order_move` is the whole
## interlock between the two stages, and
## `test_the_correction_does_not_swallow_an_embark_order` is what stops a
## future edit reversing it. Without that test the symptom would be
## "embarking silently stopped working", with nothing failing.

const W := 24
const H := 12


## A channel: land, then a wide strip of water, then land. Wide enough
## that a crossing is a real solve rather than one step.
func _world() -> Dictionary:
	var space := TorusSpace.new(W, H, 1.0)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var wet := coord.x >= 4 and coord.x < 20
		passable[index] = 0 if wet else 1
		navigable[index] = 1 if wet else 0
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.buildings = BuildingSim.new(space)
	sim.set_passable(passable)
	sim.set_navigable(navigable)
	return {"sim": sim, "space": space, "passable": passable, "navigable": navigable}


func _hull() -> UnitDef:
	var d := UnitRoster.for_civ_archetype(&"gravesworn", &"warship")
	assert_not_null(d, "Setup: a civ fields a warship")
	return d


func _transport() -> UnitDef:
	return UnitRoster.for_civ_archetype(&"gravesworn", &"transport")


func _land_unit() -> UnitDef:
	return UnitRoster.for_civ_archetype(&"gravesworn", &"levy")


# --- the fixture ------------------------------------------------------

func test_the_fixture_is_a_channel_with_land_on_both_sides() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	assert_true(sim.is_passable(Vector2i(2, 6)), "land to the west")
	assert_true(sim.is_navigable(Vector2i(12, 6)), "water in the middle")
	assert_true(sim.is_passable(Vector2i(22, 6)), "land to the east")
	assert_false(sim.is_navigable(Vector2i(2, 6)), "and the two are disjoint")


# --- 1. THE exit criterion: a water squad paths ------------------------

func test_a_water_squad_paths_across_water() -> void:
	# Stage 2's done-when, and it was measured failing before it passed:
	# a hull ordered anywhere fell into `_begin_tier_crossing` looking for
	# an access tower, found none, and the order was dropped in silence —
	# 120 ticks, 0 fields built, a ship that never moved.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var start := Vector2i(5, 6)
	var target := Vector2i(18, 6)
	var hull := sim.add_squad(_hull(), 1, start)

	sim.order_move(hull, target)
	for _t in range(200):
		sim.tick()
		if sim.cell_of(hull) == target:
			break

	assert_eq(sim.cell_of(hull), target, "the hull sailed to where it was sent")
	assert_gt(sim.fields_built, 0, "and a field was actually solved for it")


func test_a_hull_sails_around_an_obstacle_rather_than_through_it() -> void:
	# A field, not a straight line. Without this a "path" that is really a
	# lerp would pass the test above.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var navigable: PackedByteArray = w["navigable"]
	var space: TorusSpace = w["space"]
	# A wall of land across the channel, with one gap at the top.
	for y in range(2, H):
		navigable[space.index(Vector2i(12, y))] = 0
	sim.set_navigable(navigable)

	var hull := sim.add_squad(_hull(), 1, Vector2i(6, 8))
	sim.order_move(hull, Vector2i(18, 8))
	for _t in range(400):
		sim.tick()
		if sim.cell_of(hull) == Vector2i(18, 8):
			break
	assert_eq(sim.cell_of(hull), Vector2i(18, 8), "it found the gap")


# --- 2. the domain a unit lives in -------------------------------------

func test_a_hull_begins_in_the_water_domain_and_a_land_unit_does_not() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_hull(), 1, Vector2i(6, 6))
	var foot := sim.add_squad(_land_unit(), 1, Vector2i(2, 6))
	assert_eq(sim.tier_of(hull), SquadSim.DOMAIN_WATER)
	assert_eq(sim.tier_of(foot), SquadSim.DOMAIN_GROUND)


func test_every_land_unit_in_the_shipped_roster_stays_on_the_ground() -> void:
	# The domain comes from the def, so a mislabelled `.tres` would put a
	# levy in the sea. Cheap to assert over the whole roster and the only
	# thing that would notice.
	var w := _world()
	var sim: SquadSim = w["sim"]
	for def in UnitRoster.load_all():
		var at := Vector2i(2, 6) if def.movement_domain == "ground" else Vector2i(6, 6)
		var id := sim.add_squad(def, 1, at)
		var want := SquadSim.DOMAIN_WATER if def.movement_domain == "water" \
			else SquadSim.DOMAIN_GROUND
		assert_eq(sim.tier_of(id), want, "%s is in the wrong domain" % def.id)


func test_is_passable_dispatches_on_the_domain() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	var sea := Vector2i(12, 6)
	var shore := Vector2i(3, 6)
	assert_false(sim.is_passable(sea, SquadSim.DOMAIN_GROUND), "a foot cannot walk the sea")
	assert_true(sim.is_passable(sea, SquadSim.DOMAIN_WATER), "a hull can sail it")
	assert_true(sim.is_passable(shore, SquadSim.DOMAIN_GROUND), "a foot can walk the shore")
	assert_false(sim.is_passable(shore, SquadSim.DOMAIN_WATER), "a hull cannot sail it")


# --- 3. the layer has its OWN budget -----------------------------------

func test_the_water_budget_is_not_a_copy_of_the_wall_layers() -> void:
	# D-076's 1,024 is right for a network bounded by what a player built.
	# Water is bounded by the MAP, and `islands` is ~68% of it — measured
	# in `playtest_obs/obs_water_budget.gd`, where 1,024 costs 22 ticks on
	# the shipped default map against 24,576's one.
	var sim := SquadSim.new(TorusSpace.new(W, H, 1.0), CurveReplicator.new())
	assert_ne(sim.water_field_cells_per_tick, sim.top_field_cells_per_tick,
		"the water layer must not inherit the wall layer's budget")
	assert_gt(sim.water_field_cells_per_tick, sim.field_cells_per_tick,
		"a water field is larger than a ground field on the maps this is for")


func test_starving_the_water_layer_does_not_starve_the_ground() -> void:
	# The whole reason for a third counter (D-076's own argument about the
	# second): one shared budget would let a naval solve silently halve
	# ground-pathing throughput on any tick both run — and on the maps
	# this feature exists for, both run constantly.
	var w := _world()
	var sim: SquadSim = w["sim"]
	sim.water_field_cells_per_tick = 1  # effectively frozen

	var foot := sim.add_squad(_land_unit(), 1, Vector2i(1, 6))
	sim.order_move(foot, Vector2i(3, 8))
	var hull := sim.add_squad(_hull(), 1, Vector2i(6, 6))
	sim.order_move(hull, Vector2i(18, 6))
	for _t in range(120):
		sim.tick()

	assert_eq(sim.cell_of(foot), Vector2i(3, 8),
		"the land squad arrives however starved the water layer is")
	assert_ne(sim.cell_of(hull), Vector2i(18, 6),
		"Setup: and the hull really was starved, or this proves nothing")


func test_starving_the_ground_layer_does_not_starve_the_water() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	sim.field_cells_per_tick = 1

	var hull := sim.add_squad(_hull(), 1, Vector2i(5, 6))
	sim.order_move(hull, Vector2i(18, 6))
	for _t in range(200):
		sim.tick()
		if sim.cell_of(hull) == Vector2i(18, 6):
			break
	assert_eq(sim.cell_of(hull), Vector2i(18, 6),
		"the hull sails however starved the ground layer is")


func test_changing_the_sea_re_routes_a_hull_already_under_way() -> void:
	# `set_passable` clears the ground caches for this reason (D-040): a
	# field still mid-solve holds a reference to the array that just went
	# stale, and a completed one describes a world that no longer exists.
	#
	# Asserted through BEHAVIOUR rather than by reaching into the cache: a
	# hull under way has the old field, the channel closes behind it, and
	# the question is whether it finds the remaining gap or sails into the
	# new land. A cache test would pass with the hull doing either.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var space: TorusSpace = w["space"]
	var navigable: PackedByteArray = w["navigable"]
	var target := Vector2i(18, 2)
	var hull := sim.add_squad(_hull(), 1, Vector2i(6, 8))
	sim.order_move(hull, target)
	for _t in range(10):
		sim.tick()
	assert_gt(sim.fields_built, 0, "Setup: it is under way on a solved field")
	assert_ne(sim.cell_of(hull), target, "Setup: and has not arrived yet")

	# Close the channel except for one row, well away from the route it
	# was taking.
	for y in range(3, H):
		navigable[space.index(Vector2i(12, y))] = 0
	sim.set_navigable(navigable)

	for _t in range(400):
		sim.tick()
		if sim.cell_of(hull) == target:
			break
	assert_eq(sim.cell_of(hull), target,
		"it re-routed through the remaining gap rather than following a stale field")
	assert_true(sim.is_navigable(sim.cell_of(hull)),
		"and never sailed onto the new land")


# --- 4. the order correction (§2.4) ------------------------------------

func test_a_land_squad_ordered_into_the_sea_walks_to_the_shore() -> void:
	# Corrected, never refused — the same shape as `_approachable`, which
	# D-20260818 deliberately left omniscient because it can only move an
	# order and never reject one.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var foot := sim.add_squad(_land_unit(), 1, Vector2i(1, 6))
	sim.order_move(foot, Vector2i(6, 6))  # open water
	for _t in range(120):
		sim.tick()
	assert_true(sim.is_passable(sim.cell_of(foot)),
		"it ended up on land, not in the sea")
	assert_gt(sim.space.distance(sim.cell_of(foot), Vector2i(1, 6)), 0,
		"and it did move toward where it was sent")


func test_a_hull_ordered_inland_stops_at_the_water() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_hull(), 1, Vector2i(12, 6))
	sim.order_move(hull, Vector2i(1, 6))  # dry land
	for _t in range(200):
		sim.tick()
	assert_true(sim.is_navigable(sim.cell_of(hull)),
		"a hull stays afloat however it is ordered")


func test_a_squad_ordered_within_its_own_domain_is_not_corrected() -> void:
	# The correction must be inert for every order that predates ships,
	# which is every order in the game.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var foot := sim.add_squad(_land_unit(), 1, Vector2i(1, 4))
	sim.order_move(foot, Vector2i(2, 8))
	for _t in range(120):
		sim.tick()
	assert_eq(sim.cell_of(foot), Vector2i(2, 8),
		"an ordinary land order arrives exactly where it was sent")


# --- 5. THE SEAM with stage 4 ------------------------------------------

func test_the_correction_does_not_swallow_an_embark_order() -> void:
	# THE interlock between stages 2 and 4, and the reason this test
	# exists rather than a comment.
	#
	# An embark order deliberately names a cell in the OTHER domain: a
	# land squad is ordered onto the water cell a transport is sitting on.
	# §2.4's correction would send it to the beach instead, and the
	# symptom would be "embarking silently stopped working" with nothing
	# failing anywhere.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var buildings: BuildingSim = sim.buildings
	var quay := Vector2i(3, 6)
	var water := Vector2i(4, 6)
	assert_true(sim.is_passable(quay) and sim.is_navigable(water),
		"Setup: a quay beside water")
	var dock: int = buildings.add_building(BuildingSim.def_by_id(&"dock"), 1, quay, true)
	buildings.set_water_cell(dock, sim.space.index(water))

	var hull := sim.add_squad(_transport(), 1, water)
	var foot := sim.add_squad(_land_unit(), 1, Vector2i(1, 6))
	sim.order_move(foot, water)  # the embark order
	for _t in range(120):
		sim.tick()
		if sim.alive_of(foot) <= 0:
			break

	assert_eq(sim.cargo_of(hull).size(), 1,
		"the squad boarded — the correction must not turn an embark into a walk")


func test_a_landing_order_is_not_corrected_into_the_sea() -> void:
	# The other half of the same seam: a laden hull is ordered at LAND on
	# purpose, and correcting that back into the water would mean cargo
	# could never be put ashore.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var buildings: BuildingSim = sim.buildings
	var quay := Vector2i(3, 6)
	var water := Vector2i(4, 6)
	var dock: int = buildings.add_building(BuildingSim.def_by_id(&"dock"), 1, quay, true)
	buildings.set_water_cell(dock, sim.space.index(water))
	var hull := sim.add_squad(_transport(), 1, water)
	var foot := sim.add_squad(_land_unit(), 1, quay)
	sim.order_move(foot, water)
	for _t in range(60):
		sim.tick()
		if sim.alive_of(foot) <= 0:
			break
	assert_eq(sim.cargo_of(hull).size(), 1, "Setup: laden")

	sim.order_move(hull, quay)
	for _t in range(60):
		sim.tick()
		if sim.cargo_of(hull).is_empty():
			break
	assert_eq(sim.cargo_of(hull).size(), 0, "the cargo went ashore")


# --- 6. the premise behind not fogging the water -----------------------

func test_nothing_subtracts_a_cell_from_the_navigable_array() -> void:
	# The water layer solves against the TRUTH, not against what a side
	# believes, unlike ground pathing since D-20260818. The argument is
	# that in v1 there is nothing about water to discover: navigability is
	# exactly "below sea level" (§2.1), no building subtracts from it and
	# no ramp carves it, so a per-side belief array would be identical to
	# the truth array for every side on every tick.
	#
	# This asserts the PREMISE rather than trusting it. §2.2 names a sea
	# wall and a floating platform as the cases that would break it; if
	# either lands, this fires and the layer needs belief before it ships.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var space: TorusSpace = w["space"]
	var before := sim.is_navigable(Vector2i(12, 6))
	assert_true(before, "Setup: open water")

	# Put every kind of building the roster has on that cell and check the
	# water is still water.
	for def in BuildingSim.all_defs():
		var buildings := BuildingSim.new(space)
		buildings.add_building(def, 1, Vector2i(12, 6), true)
		var fresh := SquadSim.new(space, CurveReplicator.new())
		fresh.buildings = buildings
		fresh.set_navigable(w["navigable"])
		assert_true(fresh.is_navigable(Vector2i(12, 6)),
			"%s subtracts from the navigable array — the water layer now needs belief" % def.id)
