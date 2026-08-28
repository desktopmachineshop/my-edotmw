extends GutTest

## Guards that an attack-move RESUMES once the thing it halted for is dead
## (#249).
##
## D-034 halts an attack-move on contact, and that halt is right: an army
## ordered onto a town should stop and fight what it meets rather than
## walking through. What was wrong is that the halt was PERMANENT.
## `Combat.resolve` called `sim.stop()`, which clears the attack-move
## flag, and **nothing ever set it again** — so a squad that halted three
## cells short of its objective, killed the screen in front of it, and
## went idle would stand there for the rest of the match.
##
## Measured in #249 over 22 line-troop/building combinations: with one
## attack-move order, **0 of 22** scratched the building; re-issuing the
## identical order every 5 s razed 6 outright. Nothing else differed.
##
## `assign_idle_engagements` did not cover it — it pursues nearby enemy
## SQUADS and skips anything still attack-moving, so it has no answer for
## "finish the errand you were sent on".

const WIDTH := 32
const HEIGHT := 16

## Attacker, screen, objective — and the geometry is load-bearing.
##
## The objective must be reached by walking THROUGH the screen the SHORT
## way round the torus. The first version of this fixture put it at
## (24, 8): from q=4 that is 20 cells to the right and only 12 to the
## LEFT, so every squad walked away from the screen and arrived without
## ever meeting it. Same trap `docs/status/formation.md` records — "a wall
## of constant q does not block a torus at all, so the first corner
## fixture had the squad walk the other way round the world".
const START := Vector2i(4, 8)
const SCREEN := Vector2i(8, 8)
const OBJECTIVE := Vector2i(12, 8)


func _space() -> TorusSpace:
	return TorusSpace.new(WIDTH, HEIGHT, 1.0)


func _sim() -> SquadSim:
	var s := SquadSim.new()
	s.space = _space()
	return s


## A deliberate fixture, not "whatever sorts first" in the roster — the
## opening docs record five tests that broke on a roster change because
## they took the first def they were handed.
func _trooper(id: StringName, damage: float) -> UnitDef:
	var d := UnitDef.new()
	d.id = id
	d.archetype = &"levy"
	d.squad_size = 20
	d.health = 60.0
	d.damage = damage
	d.move_speed = 5.0
	d.attack_range = 1.9
	d.attack_interval = 1.0
	d.armour_class = "infantry"
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	d.morale = 1000.0            # no routing: this is about ORDERS, not nerve
	d.rout_threshold = 0.0
	d.morale_loss_per_casualty = 0.0
	d.vision_range = 6.0
	return d


func test_a_squad_that_wins_its_fight_finishes_its_errand() -> void:
	# THE defect. A screen stands between the squad and where it was sent;
	# the squad halts, kills it, and must then carry on.
	var sim := _sim()
	var attacker := sim.add_squad(_trooper(&"t_attacker", 12.0), 1, START)
	var screen := sim.add_squad(_trooper(&"t_screen", 0.5), 2, SCREEN)
	
	sim.order_attack_move(attacker, OBJECTIVE)
	assert_true(sim.is_attack_moving(attacker), "setup: the order was taken")

	# Walk into the screen and let the halt happen.
	#
	# "Idle while the screen lives" is NOT enough to call it a halt: a
	# squad that walked straight past and ARRIVED is idle too, and the
	# first version of this fixture passed on the unfixed code for exactly
	# that reason — it proved nothing and looked green. The halt has to be
	# SHORT of the objective.
	var halt_cell := Vector2i(-1, -1)
	for _i in range(120):
		sim.tick()
		if sim.alive_of(screen) > 0 and sim.is_idle(attacker):
			halt_cell = sim.cell_of(attacker)
			break
	assert_ne(halt_cell, Vector2i(-1, -1),
		"setup: the squad must actually be stopped by the screen")
	assert_ne(halt_cell, OBJECTIVE,
		"setup: the halt must happen SHORT of the objective, or this test "
		+ "proves nothing about resuming")

	# The screen dies — by the fight, or helped along so the test does not
	# depend on how long a kill takes.
	sim.set_alive(screen, 0)

	for _i in range(200):
		sim.tick()
		if sim.cell_of(attacker) == OBJECTIVE:
			break

	assert_eq(sim.cell_of(attacker), OBJECTIVE,
		"the squad stood at %s instead of finishing its errand at %s"
			% [sim.cell_of(attacker), OBJECTIVE])


func test_the_halt_itself_is_unchanged() -> void:
	# D-034's halt is correct and must survive the fix: an army ordered
	# onto a town stops and fights what it meets rather than walking
	# through. A "fix" that simply stopped halting would pass the test
	# above and delete the rule.
	var sim := _sim()
	var attacker := sim.add_squad(_trooper(&"t_attacker", 1.0), 1, START)
	var screen := sim.add_squad(_trooper(&"t_screen", 1.0), 2, SCREEN)
	sim.order_attack_move(attacker, OBJECTIVE)

	for _i in range(120):
		sim.tick()
		if sim.is_idle(attacker) and sim.alive_of(screen) > 0:
			pass_test("the squad halted on contact, as D-034 requires")
			return
	fail_test("the squad never halted on contact — D-034's rule is gone")


func test_a_player_stop_is_not_resumed() -> void:
	# The rule that keeps the fix from taking the squad away from its
	# owner. Stop must mean stop — if the remembered objective survived an
	# explicit halt, a player could not park a squad in front of an enemy
	# at all.
	var sim := _sim()
	var attacker := sim.add_squad(_trooper(&"t_attacker", 12.0), 1, START)
	var screen := sim.add_squad(_trooper(&"t_screen", 0.5), 2, SCREEN)
	sim.order_attack_move(attacker, OBJECTIVE)

	for _i in range(120):
		sim.tick()
		if sim.is_idle(attacker) and sim.alive_of(screen) > 0:
			break
	sim.stop(attacker)                     # the player says: stay here
	var parked := sim.cell_of(attacker)
	assert_ne(parked, OBJECTIVE, "setup: parked short of the objective")
	sim.set_alive(screen, 0)

	for _i in range(100):
		sim.tick()
	assert_eq(sim.cell_of(attacker), parked,
		"an explicit Stop must not be undone by the resume")


func test_a_new_order_replaces_the_remembered_one() -> void:
	# Same family: ordering the squad somewhere else must not leave the old
	# objective waiting to reassert itself later.
	var sim := _sim()
	var attacker := sim.add_squad(_trooper(&"t_attacker", 12.0), 1, START)
	var screen := sim.add_squad(_trooper(&"t_screen", 0.5), 2, SCREEN)
	sim.order_attack_move(attacker, OBJECTIVE)
	for _i in range(120):
		sim.tick()
		if sim.is_idle(attacker) and sim.alive_of(screen) > 0:
			break

	assert_ne(sim.cell_of(attacker), OBJECTIVE,
		"setup: halted short of the objective")
	var elsewhere := Vector2i(4, 2)
	sim.order_move(attacker, elsewhere)
	sim.set_alive(screen, 0)
	for _i in range(200):
		sim.tick()
		if sim.cell_of(attacker) == elsewhere:
			break
	assert_eq(sim.cell_of(attacker), elsewhere,
		"the squad must go where it was last told, not where it was told before")


func test_a_squad_still_fighting_is_not_dragged_off_its_fight() -> void:
	# The resume must wait for the fight to be OVER. Pulling a squad
	# onward while it is still in contact would turn D-034's halt into a
	# stutter and hand every defender a free back.
	var sim := _sim()
	var attacker := sim.add_squad(_trooper(&"t_attacker", 0.1), 1, START)
	var screen := sim.add_squad(_trooper(&"t_screen", 0.1), 2, SCREEN)
	sim.order_attack_move(attacker, OBJECTIVE)

	var contact := Vector2i(-1, -1)
	for _i in range(120):
		sim.tick()
		if sim.is_idle(attacker) and sim.alive_of(screen) > 0:
			contact = sim.cell_of(attacker)
			break
	assert_ne(contact, Vector2i(-1, -1), "setup: contact must happen")
	assert_ne(contact, OBJECTIVE,
		"setup: contact must be SHORT of the objective — see the note above")

	# Both sides are feeble, so the fight is still going 60 ticks later.
	for _i in range(60):
		sim.tick()
	assert_gt(sim.alive_of(screen), 0, "setup: the screen must still be alive")
	assert_eq(sim.cell_of(attacker), contact,
		"a squad still in contact must hold its ground, not walk on")
