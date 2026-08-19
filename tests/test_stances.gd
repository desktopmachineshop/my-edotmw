extends GutTest

## Guards D-20260819-stances-are-standing-orders: guard holds position,
## skirmish keeps the distance, hold fire holds until released by an
## explicit attack order — each observed red with its rule removed.

const W := 48
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _fighter(ranged := false) -> UnitDef:
	var d := UnitDef.new()
	d.id = &"stance_test"
	d.squad_size = 12
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.health = 1000.0
	d.damage = 2.0
	d.attack_range = 8.0 if ranged else 3.0
	d.attack_interval = 0.1
	d.damage_variance = 0.0
	d.vision_range = 12.0
	d.morale = 100000.0
	d.rout_threshold = 0.0
	if ranged:
		d.armour_class = "missile"
	return d


func test_guard_holds_position_while_default_pursues() -> void:
	var chased := _moved_toward_enemy(0)
	var guarded := _moved_toward_enemy(SquadSim.STANCE_GUARD)
	assert_true(chased, "the default stance pursues (the pre-stance rule)")
	assert_false(guarded, "a guarding squad stands where it was put")


func _moved_toward_enemy(stance: int) -> bool:
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(8, 8))
	sim.set_stance(squad, stance)
	# In vision (12) but outside attack range: pursuit bait.
	sim.add_squad(_fighter(), 2, Vector2i(14, 8))
	var start := sim.cell_of(squad)
	for _t in range(40):
		sim.tick()
	return sim.cell_of(squad) != start


func test_hold_fire_holds_until_an_attack_order_releases_it() -> void:
	var sim := _sim()
	var holder := sim.add_squad(_fighter(), 1, Vector2i(8, 8))
	# Fragile, so a landed blow is COUNTABLE — the tanky-fixture trap for
	# the third time: at health 1000 ten blows live in the accumulator
	# and the release assert reads 12 == 12.
	var brittle := _fighter()
	brittle.health = 10.0
	var victim := sim.add_squad(brittle, 2, Vector2i(9, 8))
	sim.set_stance(holder, SquadSim.STANCE_HOLD_FIRE)
	sim.set_stance(victim, SquadSim.STANCE_HOLD_FIRE)

	var before := sim.alive_of(victim)
	for _t in range(10):
		sim.tick()
	assert_eq(sim.alive_of(victim), before,
		"two held squads standing in reach draw no blood")

	# Weapons-free: the explicit attack order RELEASES the hold — gated
	# on the attack-move flag it would fire once and fall silent, because
	# D-034's halt spends that flag on contact.
	sim.order_attack_move(holder, sim.cell_of(victim))
	assert_false(sim.has_stance(holder, SquadSim.STANCE_HOLD_FIRE),
		"an attack order is weapons-free")
	for _t in range(10):
		sim.tick()
	assert_lt(sim.alive_of(victim), before, "and the attack actually lands")


func test_a_skirmisher_steps_back_and_a_plain_archer_stands() -> void:
	var stood := _skirmisher_final_distance(0)
	var kept := _skirmisher_final_distance(SquadSim.STANCE_SKIRMISH)
	assert_gt(kept, stood,
		("the skirmish stance opens the range (%d cells vs %d) when an "
		+ "enemy closes in") % [kept, stood])


func _skirmisher_final_distance(stance: int) -> int:
	var sim := _sim()
	var archer := sim.add_squad(_fighter(true), 1, Vector2i(8, 8))
	# GUARD alongside, so the no-stance control does not walk TOWARD the
	# threat via idle pursuit and muddy the comparison.
	sim.set_stance(archer, stance | SquadSim.STANCE_GUARD)
	var wolf := sim.add_squad(_fighter(), 2, Vector2i(11, 8))
	for _t in range(60):
		sim.tick()
	return sim.space.distance(sim.cell_of(archer), sim.cell_of(wolf))


func test_the_wire_carries_the_byte_and_the_panel_reads_it() -> void:
	var order := NetProtocol.decode_order_stance(
		NetProtocol.encode_order_stance(3, SquadSim.STANCE_GUARD | SquadSim.STANCE_HOLD_FIRE))
	assert_eq(int(order["squad"]), 3)
	assert_eq(int(order["stance"]), SquadSim.STANCE_GUARD | SquadSim.STANCE_HOLD_FIRE)

	var entries := NetProtocol.decode_squad_info(NetProtocol.encode_squad_info([
		{"id": 1, "def_id": "x", "alive": 10, "shape": "line",
			"stance": SquadSim.STANCE_SKIRMISH},
	]))
	assert_eq(int(entries[0]["stance"]), SquadSim.STANCE_SKIRMISH,
		"the panel's pressed state is the wire's own byte")
