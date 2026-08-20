extends GutTest

## Guards D-20260819-tired-men-fight-uphill: the fatigue economy (spend
## sprinting and fighting, recover resting, and the cost LINGERS), its
## two effects (soft blows, refused charges), the run stance it finally
## prices, and the slope's say in a fight — each observed red with its
## term removed.

const W := 48
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _fighter() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"fatigue_test"
	d.squad_size = 20
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.health = 10.0
	d.damage = 1.0
	d.attack_range = 3.0
	d.attack_interval = 0.1
	d.damage_variance = 0.0
	d.morale = 100000.0
	d.rout_threshold = 0.0
	return d


func test_sprinting_spends_and_resting_recovers() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(4, 8))
	sim.order_charge(squad, Vector2i(30, 8))
	for _t in range(20):
		sim.tick()
	var after_sprint := sim.fatigue_of(squad)
	assert_lt(after_sprint, 100.0, "two seconds of sprint cost something")

	sim.stop(squad)
	for _t in range(20):
		sim.tick()
	assert_gt(sim.fatigue_of(squad), after_sprint,
		"and standing still buys it back — slower than it was spent")


func test_tired_men_hit_softer() -> void:
	var fresh := _casualties_with_fatigue(100.0)
	var spent := _casualties_with_fatigue(10.0)
	assert_lt(spent, fresh,
		("an exhausted squad fights at half strength: %d casualties "
		+ "against %d fresh") % [spent, fresh])


func _casualties_with_fatigue(fatigue: float) -> int:
	var sim := _sim()
	var attacker := sim.add_squad(_fighter(), 1, Vector2i(8, 8))
	var brittle := _fighter()
	brittle.damage = 0.0
	var defender := sim.add_squad(brittle, 2, Vector2i(9, 8))
	var before := sim.alive_of(defender)
	sim.set_fatigue(attacker, fatigue)
	for _t in range(6):
		sim.tick()
	return before - sim.alive_of(defender)


func test_run_is_faster_while_fresh_and_costs() -> void:
	var walking := _arrival(0)
	var running := _arrival(SquadSim.STANCE_RUN)
	assert_lt(running["ticks"], walking["ticks"],
		("run is real: %d ticks against %d") % [running["ticks"], walking["ticks"]])
	assert_lt(running["fatigue"], walking["fatigue"],
		"and it spends what walking does not")


func _arrival(stance: int) -> Dictionary:
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(4, 8))
	sim.set_stance(squad, stance)
	sim.order_move(squad, Vector2i(24, 8))
	for t in range(600):
		sim.tick()
		if sim.cell_of(squad) == Vector2i(24, 8):
			return {"ticks": t, "fatigue": sim.fatigue_of(squad)}
	return {"ticks": 600, "fatigue": sim.fatigue_of(squad)}


func test_the_slope_has_a_say() -> void:
	var flat := _casualties_on_slope(0.0, 0.0)
	var downhill := _casualties_on_slope(1.0, 0.0)
	var uphill := _casualties_on_slope(0.0, 1.0)
	assert_gt(downhill, flat, "attacking downhill hits harder")
	assert_lt(uphill, flat, "and uphill softer")


func _casualties_on_slope(attacker_elev: float, defender_elev: float) -> int:
	var sim := _sim()
	var attacker := sim.add_squad(_fighter(), 1, Vector2i(8, 8))
	var brittle := _fighter()
	brittle.damage = 0.0
	var defender := sim.add_squad(brittle, 2, Vector2i(9, 8))
	# A hand-built elevation field: empty means flat everywhere, so bare
	# sims never pay this; here the two cells get their own heights.
	var field := PackedFloat32Array()
	field.resize(sim.space.cell_count())
	field.fill(0.0)
	field[sim.cell_index_of(attacker)] = attacker_elev
	field[sim.cell_index_of(defender)] = defender_elev
	sim.elevation = field
	var before := sim.alive_of(defender)
	for _t in range(6):
		sim.tick()
	return before - sim.alive_of(defender)
