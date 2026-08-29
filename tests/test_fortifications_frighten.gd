extends GutTest

## Guards #218 — a fortification must be able to BREAK a squad, not only
## kill it.
##
## `Combat._shoot_squad` calls `_break_squad` and has carried this comment
## since D-20260819-morale-reads-the-fight:
##
##   > Being shelled by a fortification breaks a squad the same way being
##   > beaten by another squad does — through the same `_break_squad`, so
##   > a tower-driven rout shocks nearby allies exactly like a melee one.
##
## The mechanism was correct and, at the shipped numbers, unreachable. A
## squad parked in a town centre's reach was shot to the last man with its
## morale never below ~94 of 100 against a rout threshold of 25.
##
## The cause was not the building's damage. `morale_recovery_per_second`
## was restored EVERY TICK with no condition, so it acted as a floor on
## how fast anything could frighten anybody: it is 2.0 on every shipped
## def, and a town centre's morale pressure on a levy squad is 1.4–1.9 a
## second. The net was POSITIVE — morale rising while the squad was
## annihilated.
##
## This is the D-055 / D-066 family: mechanism correct, shipped numbers do
## nothing. So every check here plays a WHOLE ENCOUNTER with shipped defs
## and asserts the outcome, rather than proving `_shoot_squad` can rout a
## squad with a tuned one — which passed throughout.

const TICKS := 900  # 90 s at 10 Hz


func _shelled(building_id: StringName, unit_id: StringName) -> Dictionary:
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var def := BuildingSim.def_by_id(building_id)
	assert_not_null(def, "buildings/%s.tres is missing" % building_id)
	var unit := UnitRoster.by_id(unit_id)
	assert_not_null(unit, "the roster should ship %s" % unit_id)

	buildings.add_building(def, 1, Vector2i(20, 20), true)
	# Parked in reach with no orders: this is about what the BUILDING can
	# do, so the squad is not attacking back and not being helped.
	var squad := sim.add_squad(unit, 2, Vector2i(23, 20))

	var routed := false
	var lowest := unit.morale
	var died_at := -1
	for i in range(TICKS):
		sim.tick()
		lowest = minf(lowest, sim.morale_of(squad))
		if sim.is_routed(squad):
			routed = true
		if sim.alive_of(squad) <= 0:
			died_at = i
			break
	return {
		"routed": routed, "lowest": lowest,
		"alive": sim.alive_of(squad), "started": unit.squad_size,
		"died_at": (died_at + 1) / 10.0 if died_at >= 0 else -1.0,
		"threshold": unit.rout_threshold,
	}


# --- the thing that was impossible -------------------------------------

func test_a_tower_breaks_a_levy_squad() -> void:
	for unit_id in [&"emberdeep_levy", &"gildedreach_levy", &"thornwood_levy"]:
		var result := _shelled(&"tower", unit_id)
		assert_true(bool(result["routed"]),
			"a tower shot %s to %d of %d men and never broke it — lowest morale %.1f against a threshold of %.1f"
				% [unit_id, result["alive"], result["started"],
					result["lowest"], result["threshold"]])


func test_a_town_centre_breaks_a_levy_squad() -> void:
	# The harder half, and the one the issue measured as flatly impossible:
	# against a town centre the net morale change was POSITIVE for every
	# levy in the roster, so no duration whatever could have routed one.
	for unit_id in [&"emberdeep_levy", &"gildedreach_levy", &"thornwood_levy"]:
		var result := _shelled(&"town_centre", unit_id)
		assert_true(bool(result["routed"]),
			"a town centre shot %s to %d of %d men and never broke it — lowest morale %.1f against a threshold of %.1f"
				% [unit_id, result["alive"], result["started"],
					result["lowest"], result["threshold"]])


func test_morale_actually_falls_under_fire_rather_than_merely_dipping() -> void:
	# The number the issue reports, asserted directly: ~94 of 100 while
	# being annihilated. A squad under a building's fire must lose most of
	# its nerve, not a rounding error's worth.
	var result := _shelled(&"town_centre", &"gildedreach_levy")
	assert_lt(float(result["lowest"]), 25.0,
		"lowest morale under a town centre's fire was %.1f — the squad was killed without being frightened"
			% result["lowest"])


# --- and the clauses that keep the fix from being a blunt instrument ---

func test_the_fearless_are_still_fearless() -> void:
	# Gravesworn ship `rout_threshold 0` and `morale_loss_per_casualty 0`
	# and are fearless BY DESIGN (#191, tests/test_fearless.gd). A change
	# to how morale recovers must not reach them.
	for unit_id in [&"gravesworn_levy", &"gravesworn_spearmen"]:
		var result := _shelled(&"tower", unit_id)
		assert_false(bool(result["routed"]),
			"a tower broke %s, which is fearless by design" % unit_id)


func test_a_squad_that_breaks_contact_still_recovers() -> void:
	# The clause that makes the suppression a WINDOW rather than a rule
	# that morale never returns. D-019's whole loop is flee, recover,
	# rally — a squad that can never recover can never rally, and a rout
	# stops being a setback and becomes a death sentence.
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var unit := UnitRoster.by_id(&"gildedreach_levy")
	buildings.add_building(BuildingSim.def_by_id(&"tower"), 1, Vector2i(20, 20), true)
	var squad := sim.add_squad(unit, 2, Vector2i(23, 20))

	var broke := false
	for i in range(600):
		sim.tick()
		if sim.is_routed(squad):
			broke = true
			break
	assert_true(broke, "setup: the tower must break the squad before recovery can be tested")
	var at_break := sim.morale_of(squad)

	# Out of reach, nothing shooting: morale must come back.
	sim.order_move(squad, Vector2i(34, 20))
	for i in range(400):
		sim.tick()
	assert_gt(sim.morale_of(squad), at_break,
		"a squad that broke contact recovered nothing (%.1f, was %.1f at the break) — "
			% [sim.morale_of(squad), at_break]
		+ "suppression must be a window, or a rout can never rally")


func test_the_suppression_window_is_shorter_than_a_rally() -> void:
	# Pins the relationship rather than the constant: the window has to be
	# short enough that a squad which has broken contact starts recovering
	# well before it would have rallied anyway, or the two rules are
	# fighting each other.
	assert_lt(Combat.MORALE_SUPPRESSED_TICKS, int(SquadSim.TICK_HZ) * 5,
		"the recovery suppression window is longer than five seconds, which is long enough "
		+ "to stop a routed squad rallying rather than merely to stop it steadying under fire")
