extends GutTest

## Guards D-076's walkable wall-top tier: a real second FlowField layer,
## reached ONLY through a single access-tower door (never from any other
## cell adjacent to a wall segment), not ownership-gated, tier-aware
## combat targeting (melee cannot reach the wall-top; ranged attackers and
## buildings can), the height range bonus, and eviction on destruction.
##
## Ground-level walls/gates are covered by tests/test_buildings.gd; this
## file is Phase B only.

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var buildings := BuildingSim.new(sim.space)
	sim.buildings = buildings
	return sim


func _tower(sim: SquadSim, at: Vector2i, direction: int) -> int:
	return sim.buildings.add_building(
		BuildingSim.def_by_id(&"wall_tower"), 1, at, true, -1, direction)


func _unit_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"test_climber"
	d.squad_size = 10
	d.health = 50.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	return d


## A target that cannot rout or fight back, so a test measuring whether it
## was HIT is not confused by it fleeing or by return fire. Health stays
## ordinary (NOT inflated) — casualties are a fractional-damage
## accumulator (D-024), so a huge health value would make a real hit
## invisible for the same reason a huge one would make it un-routable, and
## that would be the wrong way to prevent routing.
func _passive_unit_def() -> UnitDef:
	var d := _unit_def()
	d.id = &"test_target"
	d.health = 20.0
	d.morale = 100000.0
	d.rout_threshold = -1.0
	return d


# --- climbing is geometric, door-only, and not ownership-gated ---------

func test_a_squad_at_the_door_climbs_onto_the_tower() -> void:
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)  # door faces DIRECTIONS[0] (east)
	var door_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[0])

	var squad := sim.add_squad(_unit_def(), 1, door_cell)
	sim.order_move(squad, tower_cell)
	sim.tick()

	assert_eq(sim.tier_of(squad), 1, "the squad should have climbed")
	assert_eq(sim.cell_of(squad), tower_cell, "and be standing on the tower's own cell")


func test_a_squad_on_the_wrong_side_cannot_climb_directly() -> void:
	# The defect this heads off: every cell adjacent to a walkable_top
	# structure being climbable would make the wall's line pointless.
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)
	var wrong_side := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[3])  # opposite side

	var squad := sim.add_squad(_unit_def(), 1, wrong_side)
	sim.order_move(squad, tower_cell)
	sim.tick()

	assert_eq(sim.tier_of(squad), 0,
		"standing right next to the tower on the WRONG side must not climb it in one tick")


func test_a_squad_on_the_wrong_side_walks_around_to_the_door_and_climbs() -> void:
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)
	var wrong_side := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[3])

	var squad := sim.add_squad(_unit_def(), 1, wrong_side)
	sim.order_move(squad, tower_cell)
	for _i in range(200):
		sim.tick()
		if sim.tier_of(squad) == 1:
			break

	assert_eq(sim.tier_of(squad), 1,
		"routed to the door via ordinary ground movement, it should eventually climb")


func test_no_tower_anywhere_means_no_climb_at_all() -> void:
	var sim := _sim()
	var wall_cell := Vector2i(10, 8)
	sim.buildings.add_building(BuildingSim.def_by_id(&"garrison_wall"), 1, wall_cell, true)

	var squad := sim.add_squad(_unit_def(), 1, sim.space.normalize(wall_cell + Vector2i(1, 0)))
	sim.order_move(squad, wall_cell)
	for _i in range(200):
		sim.tick()

	assert_eq(sim.tier_of(squad), 0,
		"a garrison_wall segment with no tower in the match must never be climbable — "
		+ "only a tower's own door is an access point")


func test_climbing_is_not_ownership_gated() -> void:
	# D-076's deliberate choice: access is pure geometry. An enemy squad
	# that reaches the door climbs exactly the same as the owner's would.
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)  # built by player 1
	var door_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[0])

	var enemy := sim.add_squad(_unit_def(), 2, door_cell)
	sim.order_move(enemy, tower_cell)
	sim.tick()

	assert_eq(sim.tier_of(enemy), 1, "an enemy squad standing at the door must be able to climb")


# --- descending, and walking a connected run ----------------------------

func test_a_squad_can_descend_back_through_the_same_door() -> void:
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)
	var door_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[0])

	var squad := sim.add_squad(_unit_def(), 1, door_cell)
	sim.order_move(squad, tower_cell)
	sim.tick()
	assert_eq(sim.tier_of(squad), 1, "setup: climbed")

	sim.order_move(squad, door_cell)
	sim.tick()

	assert_eq(sim.tier_of(squad), 0, "the squad should have descended")
	assert_eq(sim.cell_of(squad), door_cell)


func test_tier_1_movement_walks_a_connected_run_and_stays_at_tier_1() -> void:
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)
	var wall_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[1])
	sim.buildings.add_building(BuildingSim.def_by_id(&"garrison_wall"), 1, wall_cell, true)
	var door_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[0])

	var squad := sim.add_squad(_unit_def(), 1, door_cell)
	sim.order_move(squad, tower_cell)
	sim.tick()
	assert_eq(sim.tier_of(squad), 1, "setup: climbed")

	sim.order_move(squad, wall_cell)
	for _i in range(50):
		sim.tick()
		if sim.cell_of(squad) == wall_cell:
			break

	assert_eq(sim.cell_of(squad), wall_cell,
		"the squad should walk along the connected wall-top to an adjacent segment")
	assert_eq(sim.tier_of(squad), 1, "and stay at tier 1 the whole way — no ground detour")


# --- destruction evicts, it does not kill or strand ----------------------

func test_destroying_a_tower_drops_its_occupant_to_the_ground() -> void:
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	var tower := _tower(sim, tower_cell, 0)
	var door_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[0])

	var squad := sim.add_squad(_unit_def(), 1, door_cell)
	sim.order_move(squad, tower_cell)
	sim.tick()
	assert_eq(sim.tier_of(squad), 1, "setup: climbed")

	# Brought to the edge of destruction directly, then finished off by a
	# real attacker — SquadSim's eviction hook only fires off the tick
	# `Combat.resolve_squads_vs_buildings` itself reports a destruction, so
	# the finishing blow has to actually go through combat, not a second
	# direct damage() call that would destroy it outside that path.
	sim.buildings.damage(tower, 999.0)
	assert_false(sim.buildings.is_destroyed(tower), "setup: standing, one hit from rubble")

	# No move order at all: the attacker is already within melee range of
	# the tower from `door_cell`, and besieging does not require an order
	# (`resolve_squads_vs_buildings` runs every tick for any non-engaged,
	# damage-capable squad in range). Deliberately NOT ordered onto
	# `tower_cell` — that cell is walkable_top, so an order there would
	# make the attacker climb too (D-076's tier inference applies to
	# EVERY move order) and melee the defender on top of the tower
	# instead of sieging the building from the ground, which is a real
	# and interesting mechanic but not the one this test is isolating.
	var attacker := sim.add_squad(UnitRoster.by_id(&"legion_militia"), 2, door_cell)
	for _i in range(50):
		sim.tick()
		if sim.buildings.is_destroyed(tower):
			break

	assert_true(sim.buildings.is_destroyed(tower), "setup: the attacker finished it off")
	assert_ne(sim.tier_of(squad), 1,
		"a squad cannot still be at tier 1 once its tower is rubble")
	assert_gt(sim.alive_of(squad), 0, "eviction must not kill the squad")


# --- tier-aware combat targeting (D-076's one new combat rule) ----------

func test_a_melee_squad_cannot_hit_a_tier_1_defender_even_when_adjacent() -> void:
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)
	var door_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[0])

	var defender := sim.add_squad(UnitRoster.by_id(&"legion_archers"), 1, door_cell)
	sim.order_move(defender, tower_cell)
	sim.tick()
	assert_eq(sim.tier_of(defender), 1, "setup: defender climbed")

	var attacker := sim.add_squad(UnitRoster.by_id(&"legion_militia"), 2, door_cell)
	var defender_before := sim.alive_of(defender)
	var attacker_before := sim.alive_of(attacker)
	for _i in range(50):
		sim.tick()

	assert_eq(sim.alive_of(defender), defender_before,
		"a melee squad standing right at the door must never land a hit on the wall-top defender")
	assert_lt(sim.alive_of(attacker), attacker_before,
		"the elevated defender should be shooting back just fine — this isn't a stalemate, "
		+ "one side simply cannot reach the other")


func test_a_ranged_squad_can_hit_a_tier_1_defender() -> void:
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)
	var door_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[0])

	var defender := sim.add_squad(UnitRoster.by_id(&"legion_archers"), 1, door_cell)
	sim.order_move(defender, tower_cell)
	sim.tick()
	assert_eq(sim.tier_of(defender), 1, "setup: defender climbed")

	var attacker := sim.add_squad(UnitRoster.by_id(&"northmen_skirmishers"), 2, door_cell)
	var before := sim.alive_of(defender)
	for _i in range(100):
		sim.tick()

	assert_lt(sim.alive_of(defender), before,
		"a ranged attacker (arrows arcing up) must be able to hit a wall-top defender")


## Both this test and its control below check after exactly ONE tick,
## not a longer run. Longer, and `Combat.assign_idle_engagements` (idle
## squads chase a nearby enemy within VISION range, not attack range)
## confounds the result: a stationary ground archer given enough ticks
## walks into real range on its own, hitting the target for an entirely
## mundane reason and making the control pass for the wrong reason. Tick
## 1 is provably safe from that confound: a squad's cell for a given tick
## is derived from its curve at the START of tick() — before
## `assign_idle_engagements` (which runs after combat) has had any chance
## to issue an order — so no chase-induced movement can have happened
## yet, while the defender's climb (`_advance_tier_transitions`) already
## runs BEFORE combat within that same first tick, so the boosted-range
## hit is still fully exercised.
const _SHORT_WINDOW_TICKS := 1


func test_the_height_bonus_extends_a_defenders_effective_range() -> void:
	var sim := _sim()
	var tower_cell := Vector2i(10, 8)
	_tower(sim, tower_cell, 0)
	var door_cell := sim.space.normalize(tower_cell + TorusSpace.DIRECTIONS[0])

	var archer_def: UnitDef = UnitRoster.by_id(&"legion_archers")
	assert_not_null(archer_def)
	var hex_width := sim.space.hex_size * TorusSpace.SQRT_3
	var base_range_cells := floori(archer_def.attack_range / hex_width)

	# One cell beyond the archer's own base range — reachable only with
	# the tower's top_range_bonus added on top.
	var target_cell := sim.space.normalize(tower_cell + Vector2i(base_range_cells + 1, 0))
	var target := sim.add_squad(_passive_unit_def(), 2, target_cell)
	var before := sim.alive_of(target)

	var defender := sim.add_squad(archer_def, 1, door_cell)
	sim.order_move(defender, tower_cell)

	for _i in range(_SHORT_WINDOW_TICKS):
		sim.tick()

	assert_eq(sim.tier_of(defender), 1, "setup: defender climbed")
	assert_lt(sim.alive_of(target), before,
		"a defender on the tower should reach a target one cell beyond its own base range, "
		+ "quickly — it needs no approach, it is already in boosted range from where it stands")


func test_the_same_archer_at_ground_level_cannot_reach_that_far() -> void:
	# The control for the test above: without the tower, the identical
	# archer squad at the identical distance does not land a hit within
	# the same short window — proving the extra reach came from the
	# height bonus, not from the archer's own stats alone.
	var sim := _sim()
	var origin := Vector2i(10, 8)
	var archer_def: UnitDef = UnitRoster.by_id(&"legion_archers")
	var hex_width := sim.space.hex_size * TorusSpace.SQRT_3
	var base_range_cells := floori(archer_def.attack_range / hex_width)
	var target_cell := sim.space.normalize(origin + Vector2i(base_range_cells + 1, 0))

	var target := sim.add_squad(_passive_unit_def(), 2, target_cell)
	var before := sim.alive_of(target)
	sim.add_squad(archer_def, 1, origin)

	for _i in range(_SHORT_WINDOW_TICKS):
		sim.tick()

	assert_eq(sim.alive_of(target), before,
		"a GROUND-level archer at the same distance should not reach a target one cell "
		+ "beyond its own base range within the same short window")
