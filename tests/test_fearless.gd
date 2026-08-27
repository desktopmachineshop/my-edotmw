extends GutTest

## Guards the "fearless" semantics the Gravesworn identity is built on
## (D-20260818-fantasy-civs-supersede-the-historical-frame, issue #191):
## a squad with `rout_threshold 0` must NEVER rout, however hard it is
## hit and whatever breaks beside it.
##
## #191 flagged this as an assumption to verify, not to assume: fearless
## holds only if morale can never fall strictly below zero, and the
## rally-hysteresis path had never been exercised at threshold 0. The
## structural facts this pins: `Combat` clamps morale at `maxf(_, 0.0)`
## on every subtraction (the casualty path AND the chain-shock path), and
## every rout comparison is STRICT (`morale < rout_threshold`), so
## threshold 0 is unreachable by construction. If either clamp or either
## comparison is loosened, the dead start running and this file says so.
##
## Every test here was observed to fail before being trusted (D-022's
## audit rule): asserted with `rout_threshold 0.1` on the fearless def —
## red on both the beating and the chain-shock cases — then restored.

const W := 32
const H := 16


func _sim() -> SquadSim:
	return SquadSim.new(TorusSpace.new(W, H, 1.0), CurveReplicator.new())


## Hits hard, takes nothing back, never routs itself.
func _hammer() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"fearless_test_hammer"
	d.squad_size = 30
	d.health = 10000.0
	# Gentle on purpose: ~3 casualties a round against the victims' 5 HP.
	# At damage 8 the first version wiped all 40 men in ONE round, and a
	# squad that dies in a single blow never reaches the rout check at all
	# (`alive <= 0` returns first) — the control passed via death and the
	# chain-shock fixture never delivered a shock.
	d.damage = 0.5
	d.attack_range = 3.0
	d.attack_interval = 0.1
	d.damage_variance = 0.0
	d.morale = 100.0
	d.rout_threshold = 0.0
	d.morale_loss_per_casualty = 0.0
	return d


## The Gravesworn shape: brittle, heavy morale loss per casualty on
## paper — and a threshold of zero, which is what "fearless" means in
## data. `morale_loss_per_casualty` is deliberately NON-zero here, unlike
## the shipped defs: the shipped pair (threshold 0, loss 0) would let a
## broken clamp hide behind the zero loss, and this test exists to catch
## the broken clamp.
func _fearless() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"fearless_test_dead"
	d.squad_size = 40
	d.health = 5.0
	d.damage = 0.0
	d.attack_range = 3.0
	d.attack_interval = 0.1
	d.damage_variance = 0.0
	d.morale = 20.0
	d.rout_threshold = 0.0
	d.morale_loss_per_casualty = 50.0
	d.morale_recovery_per_second = 0.0
	return d


## Same unit with an ordinary threshold — the CONTROL. It proves the
## fixture actually reaches the rout machinery, so the fearless asserts
## below cannot pass vacuously on a fight that never threatened anyone.
func _mortal() -> UnitDef:
	var d := _fearless()
	d.id = &"fearless_test_mortal"
	d.rout_threshold = 25.0
	return d


func test_the_control_with_a_normal_threshold_breaks_under_this_beating() -> void:
	var sim := _sim()
	sim.add_squad(_hammer(), 1, Vector2i(5, 5))
	var victim := sim.add_squad(_mortal(), 2, Vector2i(6, 5))
	for _i in range(20):
		sim.tick()
		if sim.alive_of(victim) <= 0:
			break
	assert_true(sim.is_routed(victim),
		"setup is not a beating: a normal-threshold squad never ROUTED "
		+ "under it, so the fearless asserts below would prove nothing")


func test_a_threshold_zero_squad_is_beaten_to_death_without_ever_routing() -> void:
	var sim := _sim()
	sim.add_squad(_hammer(), 1, Vector2i(5, 5))
	var victim := sim.add_squad(_fearless(), 2, Vector2i(6, 5))
	var ever_routed := false
	for _i in range(60):
		sim.tick()
		ever_routed = ever_routed or sim.is_routed(victim)
		assert_gte(sim.morale_of(victim), 0.0,
			"morale fell below zero — the maxf clamp is gone, and with it "
			+ "the whole fearless identity")
		if sim.alive_of(victim) <= 0:
			break
	assert_eq(sim.alive_of(victim), 0,
		"setup: the squad should be wiped out inside the tick budget")
	assert_false(ever_routed,
		"a rout_threshold 0 squad routed — 'fights to the last' is the "
		+ "one property the Gravesworn pay for with the worst per-soldier "
		+ "stats in the game")


func test_chain_shock_from_a_breaking_ally_cannot_rout_the_fearless() -> void:
	# The other door into _break_squad: watching an allied squad break
	# costs CHAIN_ROUT_MORALE_LOSS and cascades through the same strict
	# comparison. Put a fearless squad at zero morale beside a mortal ally
	# that is about to break, and the shock must still not flip it.
	var sim := _sim()
	sim.add_squad(_hammer(), 1, Vector2i(5, 5))
	var mortal := sim.add_squad(_mortal(), 2, Vector2i(6, 5))
	# Six cells out: past the two squads' combined FOOTPRINT (the ally
	# separation pass shoved an adjacent witness — and the mortal with it —
	# out of the hammer's reach, and the vacuity guard below caught it),
	# and inside Combat.CHAIN_ROUT_RADIUS_CELLS of the squad about to
	# break, which is the half that matters here.
	var fearless := sim.add_squad(_fearless(), 2, Vector2i(12, 5))
	sim.set_morale(fearless, 0.0)

	var mortal_broke := false
	for _i in range(20):
		sim.tick()
		mortal_broke = mortal_broke or sim.is_routed(mortal)
		assert_false(sim.is_routed(fearless),
			"chain shock routed a rout_threshold 0 squad — the cascade "
			+ "path compares differently from the casualty path")
		if mortal_broke:
			break
	assert_true(mortal_broke,
		"setup: the mortal ally never broke, so no chain shock was ever "
		+ "delivered and the assert above was vacuous")


func test_the_shipped_gravesworn_defs_are_fearless_in_data() -> void:
	# The identity is data (D-047); pin the data. Every gravesworn def —
	# gatherers and general included — carries threshold 0 and loss 0, so
	# nothing the civ fields can be made to run.
	var found := 0
	for def in UnitRoster.load_all():
		if def.civ != &"gravesworn":
			continue
		found += 1
		assert_eq(def.rout_threshold, 0.0,
			"%s has a nonzero rout threshold — the dead do not run" % def.id)
		assert_eq(def.morale_loss_per_casualty, 0.0,
			"%s mourns its casualties — nothing to lose means zero loss" % def.id)
	assert_gt(found, 3, "the gravesworn roster should ship more than three defs")
