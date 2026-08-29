extends GutTest

## Guards D-20260819-morale-reads-the-fight: flank/rear shock, chain
## rout, and pursuit — each with a whole-encounter test that goes red if
## its term is removed (the decision's exit criteria 1–4).

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


## A steady attacker: deterministic damage, reliable casualties per hit,
## unbreakable itself.
func _attacker_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"morale_test_attacker"
	d.squad_size = 20
	d.health = 1000.0
	d.damage = 3.0
	d.attack_range = 3.0
	d.attack_interval = 0.1
	d.damage_variance = 0.0
	d.morale = 100000.0
	d.rout_threshold = 0.0
	return d


## A defender that cannot hurt anyone (so nothing but the term under
## test differentiates two runs) and breaks after a known morale spend.
func _defender_def(morale: float = 100.0) -> UnitDef:
	var d := _attacker_def()
	d.id = &"morale_test_defender"
	d.damage = 0.0
	d.health = 10.0
	d.morale = morale
	d.rout_threshold = 25.0
	d.morale_loss_per_casualty = 4.0
	d.morale_recovery_per_second = 0.0
	return d


# --- the aspect itself (pure) -----------------------------------------

func test_aspect_classifies_front_flank_rear() -> void:
	var facing := Vector3(0, 0, 1)
	var me := Vector3.ZERO
	assert_eq(Engagement.aspect(facing, me, Vector3(0, 0, 5)),
		Engagement.ASPECT_FRONT, "dead ahead is frontal")
	assert_eq(Engagement.aspect(facing, me, Vector3(0, 0, -5)),
		Engagement.ASPECT_REAR, "dead behind is rear")
	assert_eq(Engagement.aspect(facing, me, Vector3(5, 0, 0)),
		Engagement.ASPECT_FLANK, "square on the side is flank")
	assert_eq(Engagement.aspect(Vector3.ZERO, me, Vector3(0, 0, -5)),
		Engagement.ASPECT_FRONT,
		"unknowable geometry must never award the shock bonus")
	assert_eq(Engagement.aspect(facing, me, Vector3(0, 0, 5)),
		Engagement.aspect(facing, me, Vector3(0, 0, 5)),
		"pure: nothing remembered between calls")


# --- exit criterion 1: rear breaks sooner than frontal ----------------

## The defender walks north to establish its facing, then is attacked
## from dead ahead in one run and dead behind in the other. Same defs,
## same seed, same tick of first contact — only the geometry differs.
func _ticks_until_rout(attacker_behind: bool) -> int:
	var sim := _sim()
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(16, 8))
	# March one cell north (-r is "up" in axial; direction only matters
	# for symmetry) so the heading — the facing the soldiers are drawn
	# with — points somewhere definite.
	sim.order_move(defender, Vector2i(16, 6))
	for _i in range(40):
		sim.tick()
	# THE SAME DISTANCE either side, which this fixture did not have: the
	# defender halts at (16, 6), so (16, 4) was two cells ahead against
	# (16, 9) three cells behind. That asymmetry was noise while a squad
	# needed ~19 casualties to break, and it INVERTED the result the
	# moment breaking got quicker
	# (D-20260828-morale-is-a-fraction-of-the-squad): the rear attacker
	# spent its extra cell of approach and reported 8 ticks against the
	# frontal 4.
	#
	# The function's own contract is that "nothing but the term under test
	# differentiates two runs", and a cell of travel is something else.
	# Another instance of the standing rule: a timing tuned against the
	# old behaviour is stale when the behaviour moves.
	var facing_cell := Vector2i(16, 3)
	var behind_cell := Vector2i(16, 9)
	var attacker := sim.add_squad(_attacker_def(), 1,
		behind_cell if attacker_behind else facing_cell)
	for t in range(400):
		sim.tick()
		if sim.is_routed(defender):
			return t
	return 400


func test_a_rear_attack_breaks_a_squad_sooner_than_a_frontal_one() -> void:
	var frontal := _ticks_until_rout(false)
	var rear := _ticks_until_rout(true)
	assert_lt(rear, frontal,
		("the same blows from behind must break the same squad sooner "
		+ "(rear %d ticks vs frontal %d) — remove the aspect term and "
		+ "these are equal") % [rear, frontal])


# --- exit criterion 2: chain rout -------------------------------------

func test_a_breaking_squad_shocks_nearby_allies_and_can_tip_them() -> void:
	var sim := _sim()
	# The victim: breaks on the first casualty (morale 26, threshold 25).
	var victim := sim.add_squad(_defender_def(26.0), 2, Vector2i(16, 8))
	# A steady ally nearby, a marginal ally nearby, a distant ally.
	var steady := sim.add_squad(_defender_def(100.0), 2, Vector2i(16, 12))
	var marginal := sim.add_squad(_defender_def(100.0), 2, Vector2i(12, 8))
	var distant := sim.add_squad(_defender_def(100.0), 2, Vector2i(0, 0))
	sim.set_morale(marginal, 30.0)
	var attacker := sim.add_squad(_attacker_def(), 1, Vector2i(17, 8))

	var steady_before := sim.morale_of(steady)
	var distant_before := sim.morale_of(distant)
	for _i in range(100):
		sim.tick()
		if sim.is_routed(victim):
			break
	assert_true(sim.is_routed(victim), "the victim must actually break")
	assert_lte(sim.morale_of(steady),
		steady_before - Combat.CHAIN_ROUT_MORALE_LOSS,
		"an ally within the radius pays the chain loss")
	assert_true(sim.is_routed(marginal),
		"a marginal ally is TIPPED by the shock — the cascade is real")
	assert_almost_eq(sim.morale_of(distant), distant_before, 0.001,
		"an ally beyond the radius hears nothing")


# --- exit criterion 3: pursuit ----------------------------------------

func test_a_routed_squad_is_cut_down_faster() -> void:
	var fighting := _survivors_after(false)
	var fleeing := _survivors_after(true)
	assert_gt(fighting, 0,
		"the window must end before the fighting squad is wiped, or the "
		+ "comparison is 0 vs 0 and proves nothing")
	assert_lt(fleeing, fighting,
		("the same blows on a broken squad must kill more of it "
		+ "(%d left fleeing vs %d fighting) — remove PURSUIT_DAMAGE_MULT "
		+ "and these are equal") % [fleeing, fighting])


func _survivors_after(routed: bool) -> int:
	var sim := _sim()
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(16, 8))
	# Weak enough that neither run wipes inside the window — the first
	# version dealt 6 casualties a tick and compared 0 survivors to 0.
	var chaser := _attacker_def()
	chaser.damage = 0.5
	sim.add_squad(chaser, 1, Vector2i(17, 8))
	if routed:
		# Broken before the first blow, morale too low to rally inside
		# the window. The defender deals no damage in either run, so the
		# ONLY difference between the two is what fleeing costs.
		sim.set_morale(defender, 0.0)
		sim.set_routed(defender, true)
	for _i in range(8):
		sim.tick()
	return sim.alive_of(defender)
