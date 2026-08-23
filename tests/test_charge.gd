extends GutTest

## Guards D-20260819-a-charge-is-spent-on-its-impact: the sprint, the one
## impact blow, and every guard rule — point-blank degradation, expiry,
## cancellation — each observed red with its rule removed.

const W := 48
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _fighter(damage := 1.0) -> UnitDef:
	var d := UnitDef.new()
	d.id = &"charge_test"
	d.squad_size = 20
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.health = 1000.0
	d.damage = damage
	d.attack_range = 3.0
	d.attack_interval = 0.1
	d.damage_variance = 0.0
	d.morale = 100000.0
	d.rout_threshold = 0.0
	d.morale_recovery_per_second = 0.0
	return d


func test_a_charging_squad_closes_faster() -> void:
	var plain := _arrival_ticks(false)
	var charged := _arrival_ticks(true)
	assert_lt(charged, plain,
		"the sprint is real: charge %d ticks vs march %d" % [charged, plain])


func _arrival_ticks(charge: bool) -> int:
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(4, 8))
	var goal := Vector2i(24, 8)
	if charge:
		sim.order_charge(squad, goal)
	else:
		sim.order_attack_move(squad, goal)
	for t in range(600):
		sim.tick()
		if sim.cell_of(squad) == goal:
			return t
	return 600


func test_the_impact_lands_once_and_hits_harder() -> void:
	# Two identical engagements, same seed geometry; one arrives charging.
	# The impact blow must cost the defender more, and the SECOND
	# exchange must cost the same in both — the charge is one blow.
	var plain := _casualties_by_exchange(false)
	var charged := _casualties_by_exchange(true)
	assert_gte(charged[0], plain[0] * 2,
		"the impact blow hits harder (%d vs %d men)" % [charged[0], plain[0]])
	assert_lt(charged[1], charged[0],
		"and is spent: the follow-up exchange is an ordinary one, not a "
		+ "second impact (%d after %d)" % [charged[1], charged[0]])


## Casualties the defender takes on the impact exchange and on one later
## exchange. The attacker walks in from MIN_CHARGE_CELLS away so both
## runs share the arrival geometry.
func _casualties_by_exchange(charge: bool) -> Array:
	var sim := _sim()
	var attacker := sim.add_squad(_fighter(1.0), 1, Vector2i(8, 8))
	# Fragile on purpose: with a tanky defender the x3 lands in the
	# fractional accumulator and shows up as an EARLIER first casualty of
	# the same size — this test needs the blow itself to be countable.
	var brittle := _fighter(0.0)
	brittle.health = 10.0
	var defender := sim.add_squad(brittle, 2, Vector2i(16, 8))
	var goal := Vector2i(15, 8)
	if charge:
		sim.order_charge(attacker, goal)
	else:
		sim.order_attack_move(attacker, goal)

	var before := sim.alive_of(defender)
	var first := -1
	for _t in range(300):
		sim.tick()
		if first < 0 and sim.alive_of(defender) < before:
			first = before - sim.alive_of(defender)
			before = sim.alive_of(defender)
			# Let exactly ONE more blow land (attack_interval is one
			# tick) — a wider window would sum several ordinary blows
			# into something the size of the impact and prove nothing.
			sim.tick()
			return [first, before - sim.alive_of(defender)]
	return [0, 0]


func test_a_point_blank_charge_is_an_attack_move() -> void:
	var sim := _sim()
	var attacker := sim.add_squad(_fighter(), 1, Vector2i(8, 8))
	sim.order_charge(attacker, Vector2i(9, 8))  # inside MIN_CHARGE_CELLS
	assert_false(sim.is_charging(attacker),
		"re-clicking Charge on the man in front of you must not be a "
		+ "free impact — the order degrades to attack-move")
	assert_true(sim.is_attack_moving(attacker), "but it still attacks")


func test_a_charge_ends_when_the_legs_give_out() -> void:
	# The tick deadline is GONE (D-20260819-tired-men-fight-uphill):
	# fatigue is what ends a sprint now, and the cost lingers.
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(4, 8))
	sim.order_charge(squad, Vector2i(40, 8))  # farther than the legs allow
	assert_true(sim.is_charging(squad))
	var lasted := 0
	for _t in range(300):
		sim.tick()
		if not sim.is_charging(squad):
			break
		lasted += 1
	assert_false(sim.is_charging(squad),
		"an unending sprint would make Charge the strictly better move "
		+ "order everywhere")
	assert_between(lasted, 30, 100,
		"the sprint lasts what the fatigue economy prices, not forever "
		+ "and not an instant")
	assert_lte(sim.fatigue_of(squad), SquadSim.CHARGE_EXHAUST_FLOOR + 1.0,
		"and what ended it was the legs")


func test_an_exhausted_squad_cannot_charge_at_all() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(4, 8))
	sim.set_fatigue(squad, SquadSim.CHARGE_MIN_FATIGUE - 5.0)
	sim.order_charge(squad, Vector2i(24, 8))
	assert_false(sim.is_charging(squad),
		"too spent: the order degrades to an honest attack-move")
	assert_true(sim.is_attack_moving(squad))


func test_a_plain_move_or_a_rout_cancels_a_charge() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(4, 8))
	sim.order_charge(squad, Vector2i(24, 8))
	assert_true(sim.is_charging(squad))
	sim.order_move(squad, Vector2i(10, 8))
	assert_false(sim.is_charging(squad),
		"walking somewhere must not carry a three-times blow from an "
		+ "order somebody changed their mind about")

	sim.order_charge(squad, Vector2i(24, 8))
	assert_true(sim.is_charging(squad))
	sim.flee_move(squad, Vector2i(2, 8))
	assert_false(sim.is_charging(squad),
		"a broken squad is not charging anything — without this a routed "
		+ "ex-charger flees at sprint speed")


func test_the_wire_carries_a_charge() -> void:
	var order := NetProtocol.decode_order_charge(
		NetProtocol.encode_order_charge(5, 1234))
	assert_eq(int(order["squad"]), 5)
	assert_eq(int(order["destination"]), 1234)
