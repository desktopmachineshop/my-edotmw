extends GutTest

## Water as a second movement domain
## (`D-20260828-water-is-a-second-movement-domain`, #301 stage 2).
##
## The interface contract these pin is `docs/plans/naval.md` §7.1, which
## three other workers are writing against — so a failure here is a
## contract break, not only a bug.
##
## ## What is being reused rather than built
##
## D-076 already established a per-squad layer with its own passability,
## a second `FlowField` layer with its OWN budget, and an explicit hop
## between layers. Water is a THIRD value of the same field and a third
## drive of the same machinery. So most of what these tests assert is
## that the third layer is genuinely INDEPENDENT of the other two — which
## is the property D-076 says it confirmed by reading the budget
## accounting before writing the second copy, and the one a shared
## counter would silently break.
##
## No `TerrainGen` anywhere in this file, on purpose: stage 2 consumes an
## array and never computes one, which is what lets stage 1 be written by
## somebody else at the same time.

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _unit(domain: String = "land") -> UnitDef:
	var d := UnitDef.new()
	d.id = &"test_unit"
	d.archetype = &"levy"
	d.movement_domain = domain
	d.squad_size = 4
	d.health = 50.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.vision_range = 6.0
	d.move_speed = 4.0
	return d


## A sea across the bottom half, land across the top. Two disjoint fields,
## which is what the domains are supposed to be.
func _coast(sim: SquadSim) -> PackedByteArray:
	var space := sim.space
	var land := PackedByteArray()
	var sea := PackedByteArray()
	land.resize(W * H)
	sea.resize(W * H)
	for y in range(H):
		for x in range(W):
			var i := space.index(Vector2i(x, y))
			var wet := y >= H / 2
			land[i] = 0 if wet else 1
			sea[i] = 1 if wet else 0
	sim.set_passable(land)
	sim.set_navigable(sea)
	return sea


# --- the domain values and the dispatch --------------------------------

## The three domains are distinct values, and `tier_of` returns one.
## Pinned because the contract names them and other stages branch on them.
func test_the_three_domains_are_distinct() -> void:
	assert_ne(SquadSim.DOMAIN_GROUND, SquadSim.DOMAIN_WALL_TOP)
	assert_ne(SquadSim.DOMAIN_GROUND, SquadSim.DOMAIN_WATER)
	assert_ne(SquadSim.DOMAIN_WALL_TOP, SquadSim.DOMAIN_WATER)


## A unit's domain comes from its DEF, once, at `add_squad` — never from
## the order. That is the one place naval departs from D-076, and it is
## why a shore cell can be ambiguous without anything having to resolve
## the ambiguity.
func test_a_squads_domain_comes_from_its_unit() -> void:
	var sim := _sim()
	var lander := sim.add_squad(_unit("land"), 1, Vector2i(4, 2))
	var ship := sim.add_squad(_unit("water"), 1, Vector2i(4, 12))
	assert_eq(sim.tier_of(lander), SquadSim.DOMAIN_GROUND)
	assert_eq(sim.tier_of(ship), SquadSim.DOMAIN_WATER)


## `movement_domain` defaults to land, so every unit that predates this
## feature — the whole shipped roster — is unaffected.
func test_every_existing_unit_is_a_land_unit() -> void:
	assert_eq(UnitDef.new().movement_domain, "land",
		"the default must be land, or the shipped roster becomes a navy")
	for def in UnitRoster.load_all():
		assert_eq(def.movement_domain, "land",
			"%s is not a land unit and nothing has authored a ship yet" % def.id)


## The empty-array default is CLOSED for water and OPEN for ground, and
## the asymmetry is deliberate (see `_navigable`'s doc). Together they
## make the domains disjoint in a terrain-less sim: everything is land,
## nothing is sea.
func test_a_sim_with_no_terrain_is_all_land_and_no_sea() -> void:
	var sim := _sim()
	var cell := Vector2i(3, 3)
	assert_true(sim.is_passable(cell, SquadSim.DOMAIN_GROUND),
		"a bare sim is an open field, unchanged")
	assert_false(sim.is_passable(cell, SquadSim.DOMAIN_WATER),
		"a bare sim has no sea — 'sail anywhere' would float a ship across "
		+ "a test map that is meant to be a field")
	assert_false(sim.is_navigable(cell))


## The dispatch reads the right array for each domain, and the two arrays
## are genuinely independent.
func test_each_domain_reads_its_own_array() -> void:
	var sim := _sim()
	_coast(sim)
	var ashore := Vector2i(4, 2)
	var afloat := Vector2i(4, 12)

	assert_true(sim.is_passable(ashore, SquadSim.DOMAIN_GROUND))
	assert_false(sim.is_passable(ashore, SquadSim.DOMAIN_WATER))
	assert_false(sim.is_passable(afloat, SquadSim.DOMAIN_GROUND))
	assert_true(sim.is_passable(afloat, SquadSim.DOMAIN_WATER))


## The default argument is `DOMAIN_GROUND`, so every pre-existing call
## site — and there are several — keeps asking the question it asked.
func test_the_dispatch_defaults_to_ground() -> void:
	var sim := _sim()
	_coast(sim)
	assert_eq(sim.is_passable(Vector2i(4, 2)),
		sim.is_passable(Vector2i(4, 2), SquadSim.DOMAIN_GROUND))
	assert_eq(sim.is_passable(Vector2i(4, 12)),
		sim.is_passable(Vector2i(4, 12), SquadSim.DOMAIN_GROUND))


# --- the third field layer, and its independence ------------------------

## A ship sails. The bare minimum, and the thing every test below assumes.
func test_a_ship_moves_across_water() -> void:
	var sim := _sim()
	_coast(sim)
	var ship := sim.add_squad(_unit("water"), 1, Vector2i(2, 12))
	var target := Vector2i(24, 12)
	sim.order_move(ship, target)
	for _i in range(400):
		sim.tick()
	assert_eq(sim.cell_of(ship), target,
		"the ship did not reach open water it was ordered to")


## ...and a land squad still walks, with a sea on the same map. Without
## this, "the ship sailed" could be a sim in which everything moves
## everywhere.
func test_a_land_squad_still_walks_with_a_sea_on_the_map() -> void:
	var sim := _sim()
	_coast(sim)
	var foot := sim.add_squad(_unit("land"), 1, Vector2i(2, 2))
	var target := Vector2i(24, 2)
	sim.order_move(foot, target)
	for _i in range(400):
		sim.tick()
	assert_eq(sim.cell_of(foot), target)


## Neither domain crosses the shoreline. A ship ordered inland stops at
## the water's edge; a land squad ordered to sea stops at the coast. The
## order is CORRECTED, never refused — `_approachable` resolves against
## the squad's own domain — so neither ever stands in the wrong element.
func test_neither_domain_crosses_the_shoreline() -> void:
	var sim := _sim()
	_coast(sim)
	var ship := sim.add_squad(_unit("water"), 1, Vector2i(8, 12))
	var foot := sim.add_squad(_unit("land"), 1, Vector2i(8, 2))

	sim.order_move(ship, Vector2i(8, 1))   # inland
	sim.order_move(foot, Vector2i(8, 14))  # out to sea
	for _i in range(400):
		sim.tick()

	assert_true(sim.is_navigable(sim.cell_of(ship)),
		"the ship ended at %s, which is not water" % sim.cell_of(ship))
	assert_true(sim.is_passable(sim.cell_of(foot)),
		"the squad ended at %s, which is not land" % sim.cell_of(foot))


## Being ordered at the sea does not turn a land squad into a ship, and
## vice versa. `_tier_for_destination` is what guarantees it.
func test_an_order_never_changes_a_squads_domain() -> void:
	var sim := _sim()
	_coast(sim)
	var ship := sim.add_squad(_unit("water"), 1, Vector2i(8, 12))
	var foot := sim.add_squad(_unit("land"), 1, Vector2i(8, 2))
	sim.order_move(ship, Vector2i(8, 1))
	sim.order_move(foot, Vector2i(8, 14))
	for _i in range(50):
		sim.tick()
	assert_eq(sim.tier_of(ship), SquadSim.DOMAIN_WATER)
	assert_eq(sim.tier_of(foot), SquadSim.DOMAIN_GROUND)


## The water layer has its OWN cell budget and does not draw on the
## ground layer's. This is the property D-076 says it confirmed by
## reading the budget accounting before writing its second copy, and the
## one a shared counter would silently break — a naval solve halving
## ground-pathing throughput on any tick both run.
##
## Observed to fail: pointing `_field_for_water` at
## `_field_budget_remaining()` (the ground counter) makes the ground
## squad's own field starve and this goes red.
func test_the_water_layer_does_not_spend_the_ground_layers_budget() -> void:
	var sim := _sim()
	_coast(sim)
	# A ground budget just big enough for the land squad's own field and
	# nothing more. If the naval solve is charged to it, the land squad
	# never gets a complete field and never arrives.
	sim.field_cells_per_tick = 64
	sim.water_field_cells_per_tick = 64

	var foot := sim.add_squad(_unit("land"), 1, Vector2i(2, 2))
	var ship := sim.add_squad(_unit("water"), 1, Vector2i(2, 12))
	sim.order_move(foot, Vector2i(28, 2))
	sim.order_move(ship, Vector2i(28, 12))
	for _i in range(900):
		sim.tick()

	assert_eq(sim.cell_of(foot), Vector2i(28, 2),
		"the land squad did not arrive — the naval layer is spending its budget")
	assert_eq(sim.cell_of(ship), Vector2i(28, 12),
		"the ship did not arrive")


## A budget of zero stalls the water layer and NOTHING else. The sharpest
## statement of independence available: one layer switched off, the other
## unaffected.
func test_a_zero_water_budget_stalls_only_the_water_layer() -> void:
	var sim := _sim()
	_coast(sim)
	sim.water_field_cells_per_tick = 0

	var foot := sim.add_squad(_unit("land"), 1, Vector2i(2, 2))
	var ship := sim.add_squad(_unit("water"), 1, Vector2i(2, 12))
	sim.order_move(foot, Vector2i(28, 2))
	sim.order_move(ship, Vector2i(28, 12))
	for _i in range(400):
		sim.tick()

	assert_eq(sim.cell_of(foot), Vector2i(28, 2),
		"the land squad must be unaffected by the naval budget")
	assert_ne(sim.cell_of(ship), Vector2i(28, 12),
		"with no naval budget at all the ship cannot have solved a field")


## Handing over a new water graph drops the naval cache and NOT the
## ground one — `set_passable`'s reason, scoped to the layer that changed.
func test_set_navigable_flushes_only_the_naval_cache() -> void:
	var sim := _sim()
	var sea := _coast(sim)
	var foot := sim.add_squad(_unit("land"), 1, Vector2i(2, 2))
	sim.order_move(foot, Vector2i(28, 2))
	for _i in range(60):
		sim.tick()
	var built_before := sim.fields_built

	sim.set_navigable(sea)
	for _i in range(5):
		sim.tick()
	assert_eq(sim.fields_built, built_before,
		"re-handing the water graph rebuilt a GROUND field — the caches are not separate")


# --- belief: water is fogged, and that is a decision --------------------

## An island squarely on the SHORT way from (2, 12) to (14, 12).
##
## The seam is the trap here and it cost a run: an island at x = 16 with a
## destination at x = 28 is on the long way round, because west across the
## wrap is 6 cells and east is 26 — the ship sailed the other way, never
## saw it, and `route_discoveries` was correctly 0. A fixture on a torus
## has to put the obstacle on the path the mover will actually take
## (`docs/status/formation.md` records the same trap: "a wall of constant
## q does not block a torus at all").
func _island(sim: SquadSim, sea: PackedByteArray) -> PackedByteArray:
	for y in range(10, 16):
		sea[sim.space.index(Vector2i(8, y))] = 0
	sim.set_navigable(sea)
	return sea




## A side plans over what it BELIEVES the sea to be, and unknown reads
## navigable. So a ship ordered past an island it has never seen sets off,
## which is the optimism `D-20260818-pathing-knows-only-what-the-player-
## knows` chose deliberately for land: being wrongly refused is worse than
## finding out by sailing.
func test_an_unseen_island_does_not_refuse_the_order() -> void:
	var sim := _sim()
	# An island the mover has never looked at, straight across its course.
	_island(sim, _coast(sim))

	var ship := sim.add_squad(_unit("water"), 1, Vector2i(2, 12))
	sim.order_move(ship, Vector2i(14, 12))
	sim.tick()
	assert_ne(sim.destination_of(ship), sim.cell_of(ship),
		"the order was given up on before the ship had seen anything")


## And it finds out by sailing: the TOUCH discovery that keeps optimism
## from ever putting a hull inside an island. `route_discoveries` counts
## it, and a match with terrain reporting ZERO of these is one where the
## whole mechanism is dead — this project's most-repeated defect.
##
## The ship is BLIND (`vision_range` 0) on purpose, and finding out why
## was worth the run: with ordinary sight it SEES the island several cells
## out, belief is corrected by `absorb` rather than by touch, and
## `route_discoveries` correctly stays 0. That is the mechanism working
## and it makes the counter the wrong instrument. Blind is what isolates
## the safety net — the same argument `TerrainKnowledge.discover`'s own
## doc makes for land: a unit with no vision at all would otherwise never
## learn anything, and a hull must never end up inside an island however
## optimistic its plan was.
##
## Observed to fail with the water branch of the discovery block removed:
## the count stays at 0 and the ship stalls against the island forever.
func test_a_blind_ship_learns_the_sea_by_sailing_it() -> void:
	var sim := _sim()
	_island(sim, _coast(sim))

	var blind := _unit("water")
	blind.vision_range = 0.0
	var ship := sim.add_squad(blind, 1, Vector2i(2, 12))
	sim.order_move(ship, Vector2i(14, 12))
	for _i in range(600):
		sim.tick()

	assert_gt(sim.route_discoveries, 0,
		"nothing was discovered by touch, so the safety net is not running")
	assert_true(sim.is_navigable(sim.cell_of(ship)),
		"the ship ended at %s, which is land" % sim.cell_of(ship))


## The sighted case, which is the ordinary one: a ship with eyes corrects
## its belief from VISION before it ever touches the island, so the touch
## counter stays at zero and the ship still never sails into land. Without
## this beside the test above, "route_discoveries > 0" would look like the
## only evidence that belief works.
func test_a_ship_with_eyes_learns_the_sea_by_looking_at_it() -> void:
	var sim := _sim()
	_island(sim, _coast(sim))

	var ship := sim.add_squad(_unit("water"), 1, Vector2i(2, 12))
	sim.order_move(ship, Vector2i(14, 12))
	for _i in range(600):
		sim.tick()

	assert_gt(sim.knowledge.discoveries, 0,
		"a ship with sight learned nothing about the sea it sailed through")
	assert_true(sim.is_navigable(sim.cell_of(ship)),
		"the ship ended at %s, which is land" % sim.cell_of(ship))


## Belief is per SIDE, like the ground layer's and unlike D-076's
## wall-top layer. What one side has learned about the sea must not
## appear in another's plan.
func test_water_belief_is_per_side() -> void:
	var knowledge := TerrainKnowledge.new()
	var cells := W * H
	assert_true(knowledge.believes_navigable(1, 5),
		"a side that knows nothing believes everything, at sea too")

	knowledge.discover_navigable(1, 5, false, cells)
	assert_false(knowledge.believes_navigable(1, 5),
		"the side that looked must have learned")
	assert_true(knowledge.believes_navigable(2, 5),
		"a side that did NOT look must not have learned — belief is per side")


## Land belief and water belief are separate arrays. Learning that a cell
## is not sea must not also claim it is not walkable, which is exactly
## what a single tri-state array would have done.
func test_learning_the_sea_says_nothing_about_the_land() -> void:
	var knowledge := TerrainKnowledge.new()
	var cells := W * H
	knowledge.discover_navigable(1, 7, false, cells)
	assert_true(knowledge.believes_passable(1, 7),
		"discovering a cell is not water must not mark it unwalkable")

	knowledge.discover(1, 9, false, cells)
	assert_true(knowledge.believes_navigable(1, 9),
		"discovering a cell is not walkable must not mark it unnavigable")


## A naval field must be solved against the side's WATER belief, not its
## land belief — and this is the test that actually catches the two being
## confused.
##
## Written after a perturbation run showed the belief tests above were
## VACUOUS: pointing `believed_navigable` at the land array left all of
## them green, because a side that has learned nothing has both arrays
## empty and the difference cannot show. What separates them is a side
## that has learned something.
##
## Here a lookout ashore watches the sea and correctly learns that those
## cells are NOT WALKABLE. A ship of the same side must still sail them.
## With the arrays confused, the navy is forbidden from every cell the
## army has discovered is water — which is every cell it could ever use.
func test_a_naval_field_is_not_solved_against_land_belief() -> void:
	var sim := _sim()
	_coast(sim)

	# A lookout with a long sight, standing on the coast, so `absorb`
	# folds the sea in front of it into this side's LAND belief as
	# "blocked" — which is true, and must not reach the navy.
	var lookout := _unit("land")
	lookout.vision_range = 14.0
	sim.add_squad(lookout, 1, Vector2i(8, 7))
	for _i in range(20):
		sim.tick()

	var group := sim.knowledge_group_of(0)
	assert_false(sim.knowledge.believes_passable(group, sim.space.index(Vector2i(8, 10))),
		"the lookout should have learned the sea is not walkable, or this proves nothing")
	assert_true(sim.knowledge.believes_navigable(group, sim.space.index(Vector2i(8, 10))),
		"...and that must not have taught it the sea is unsailable")

	var ship := sim.add_squad(_unit("water"), 1, Vector2i(4, 10))
	var target := Vector2i(12, 10)
	sim.order_move(ship, target)
	for _i in range(400):
		sim.tick()
	assert_eq(sim.cell_of(ship), target,
		"the ship could not sail water its own side had looked at — the naval "
		+ "field is being solved against LAND belief")


## The naval budget is the GROUND budget, and that equality is the
## decision rather than a coincidence: neither layer is privileged over
## the other, and both are bounded identically because neither has a
## measured reason to be larger. A future divergence should be a
## deliberate edit that reds this, not a drift.
##
## `top_field_cells_per_tick` is deliberately NOT equal — a wall-top
## network is bounded by how many segments a player built, where water is
## a region (measured: a Standard `islands` naval field is 22,149 cells).
func test_the_naval_budget_matches_the_ground_budget_by_decision() -> void:
	var sim := _sim()
	assert_eq(sim.water_field_cells_per_tick, sim.field_cells_per_tick,
		"the naval and ground layers are bounded identically on purpose")
	assert_ne(sim.water_field_cells_per_tick, sim.top_field_cells_per_tick,
		"copying the wall-top budget would starve a field that covers a region")
