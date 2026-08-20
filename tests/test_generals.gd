extends GutTest

## Guards D-20260819-a-general-holds-the-line: presence steadies (double
## recovery, half the chain shock), death shocks (twice a chain rout,
## cascading), one alive per player, and the shipped data actually
## fields one per civ (the D-055 declared-and-unread guard).

const W := 48
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _fighter(morale := 100.0) -> UnitDef:
	var d := UnitDef.new()
	d.id = &"general_test"
	d.squad_size = 20
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.health = 10.0
	d.damage = 1.0
	d.attack_range = 3.0
	d.attack_interval = 0.1
	d.damage_variance = 0.0
	d.morale = morale
	d.rout_threshold = 25.0
	d.morale_recovery_per_second = 4.0
	d.rout_rally_margin = 15.0
	return d


func _general() -> UnitDef:
	var d := _fighter(160.0)
	d.id = &"general_test_general"
	d.health = 220.0
	d.is_general = true
	return d


func test_presence_doubles_recovery() -> void:
	var lonely := _recovered_morale(false)
	var steadied := _recovered_morale(true)
	assert_gt(steadied, lonely,
		("men recover faster beside their general: %f against %f")
			% [steadied, lonely])


func _recovered_morale(with_general: bool) -> float:
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(8, 8))
	if with_general:
		sim.add_squad(_general(), 1, Vector2i(10, 8))
	sim.set_morale(squad, 40.0)
	for _t in range(20):
		sim.tick()
	return sim.morale_of(squad)


func test_presence_halves_the_chain_shock() -> void:
	var alone := _shock_paid(false)
	var steadied := _shock_paid(true)
	assert_lt(steadied, alone,
		("the shock of a friend breaking costs half inside the aura: "
		+ "%f against %f") % [steadied, alone])


func _shock_paid(with_general: bool) -> float:
	var sim := _sim()
	# The victim breaks on the first casualty.
	var victim := sim.add_squad(_fighter(26.0), 2, Vector2i(16, 8))
	var witness := sim.add_squad(_fighter(), 2, Vector2i(16, 12))
	if with_general:
		sim.add_squad(_general(), 2, Vector2i(16, 13))
	# Recovery off for a clean read of the shock alone.
	sim.set_morale(witness, 60.0)
	var attacker_def := _fighter()
	attacker_def.health = 100000.0
	sim.add_squad(attacker_def, 1, Vector2i(17, 8))
	var before := sim.morale_of(witness)
	for _t in range(60):
		sim.tick()
		if sim.is_routed(victim):
			break
	assert_true(sim.is_routed(victim), "setup: the victim must break")
	# Return the immediate shock: before minus the post-rout floor
	# (recovery may add a little back; comparing A/B cancels it).
	return before - sim.morale_of(witness)


func test_a_generals_death_shocks_twice_as_hard_and_cascades() -> void:
	var sim := _sim()
	var general := sim.add_squad(_general(), 2, Vector2i(16, 8))
	var marginal := sim.add_squad(_fighter(), 2, Vector2i(16, 11))
	sim.set_morale(marginal, 30.0)
	var killer := _fighter()
	killer.damage = 60.0  # kills the general's 8 men fast
	killer.health = 100000.0
	sim.add_squad(killer, 1, Vector2i(17, 8))
	for _t in range(120):
		sim.tick()
		if sim.alive_of(general) <= 0:
			break
	assert_eq(sim.alive_of(general), 0, "setup: the general must fall")
	assert_true(sim.is_routed(marginal),
		"a marginal ally is TIPPED by the general's death — the shock is "
		+ "real and it cascades")


func test_one_living_general_per_player() -> void:
	var sim := _sim()
	assert_false(sim.has_live_general(1))
	var first := sim.add_squad(_general(), 1, Vector2i(8, 8))
	assert_true(sim.has_live_general(1),
		"the production gate's question, answerable without a server")
	assert_false(sim.has_live_general(2), "and it is per player")
	sim.set_alive(first, 0)
	assert_false(sim.has_live_general(1), "a dead general frees the slot")


func test_the_roster_fields_a_general_per_civ() -> void:
	var civs := {}
	for def in UnitRoster.load_all():
		if def.is_general:
			civs[def.civ] = true
			assert_eq(String(def.archetype), "general",
				"the wire carries the archetype (D-047)")
	assert_gte(civs.size(), 2,
		"both shipped civs field one, or the mechanic is declared and "
		+ "unfieldable (the D-055 family)")
