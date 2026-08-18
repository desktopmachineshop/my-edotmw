extends GutTest

## Guards the tick's phase accounting (D-20260818, issue #105).
##
## The defect these were written against was not a slow phase — it was a
## phase nobody could see. A run reported `us/squad=167.72 (vision=13.000
## combat=32.681)` and those were the only two phases the simulation
## timed, so 122 of the 167.7 belonged to nothing and the rise could not
## be attributed to anything. Worse, the two that WERE reported overlapped
## the rest: `combat` ran from the start of combat to the end of hauling,
## so it also carried buildings, production and the economy.
##
## So the property under test is not "a phase is fast". It is that the
## phases PARTITION the tick: every microsecond lands on a named phase or
## visibly on the residual, and the parts sum to the whole. A measurement
## nobody can decompose is what M4, M6 and M10 each had to pay for after
## the fact.
##
## Both checks were observed to fail before being trusted, each against
## the perturbation it exists for: with the field-expansion phase's
## accumulation removed — the state the code was in before this change —
## the second goes red at `fields=0.00`; with the curves phase's removed,
## the first goes red at `other` = 28.0% of the tick.


## Bigger than `field_cells_per_tick` (4,096 cells) on purpose: on a
## smaller map every flow field finishes inside the tick that starts it,
## so the expansion phase — the one this issue was about — would be timing
## nothing and the check would pass vacuously.
const W := 96
const H := 64

## The residual is allowed to be small but not free. It is not zero even
## in principle: `Time.get_ticks_usec()` truncates, and seven phase
## measurements per tick each shed up to a microsecond into the gap
## between them. In practice this fixture measures 0.03%, and leaving a
## whole phase untimed puts it at 28% — so 15% is comfortably clear of
## the noise and comfortably below the thing it is looking for.
const MAX_RESIDUAL_FRACTION := 0.15


## A world with something happening in every phase: real terrain (so the
## flow-field solver has obstacles to route around), buildings producing
## against a full wallet, gatherers hauling, and two armies ordered at
## each other so curves rebuild and combat resolves.
func _busy_world() -> ScenarioWorld:
	var w := ScenarioWorld.build("developed", 2, W, H, false)
	for player in [1, 2]:
		var enemy := 2 if player == 1 else 1
		var enemies := w.squads_of(enemy)
		if enemies.is_empty():
			continue
		var target := w.sim.cell_of(enemies[0])
		for squad in w.squads_of(player):
			w.sim.order_move(squad, target)
	w.tick(6.0)
	return w


func test_every_microsecond_of_the_tick_lands_on_a_phase() -> void:
	var w := _busy_world()
	var phases := w.sim.phase_usec_per_squad_update()
	var total := w.sim.mean_usec_per_squad_update()
	assert_gt(total, 0.0, "the world did not tick at all")

	# `production` is a slice of `buildings`, so it is reported alongside
	# rather than added — summing it would double-count it.
	var summed := 0.0
	for phase in phases:
		if phase != "production":
			summed += phases[phase]
	assert_almost_eq(summed, total, total * 0.001,
		"the phases do not add up to the figure they decompose")

	var residual: float = phases["other"] / total
	gut.p("us/squad=%.2f at %d squads — %s (residual %.1f%%)" % [
		total, w.sim.squad_count(), _line(phases), residual * 100.0])
	assert_lt(residual, MAX_RESIDUAL_FRACTION,
		"%.1f%% of the tick is attributed to no phase — something in tick() is untimed" % [
			residual * 100.0])


## The specific gap this issue found: the flow-field expansion slice
## (D-040) runs at the top of every tick against a per-TICK cell budget,
## and was charged to no phase at all. It is the one phase whose cost does
## not divide down as squads are added, so it is the one most likely to be
## behind a per-squad figure that rose while its named parts fell.
func test_the_field_expansion_phase_is_counted() -> void:
	var w := _busy_world()
	assert_gt(w.sim.fields_built, 0, "no flow field was ever built")
	var phases := w.sim.phase_usec_per_squad_update()
	assert_gt(phases["fields"], 0.0,
		"fields were solved but the expansion phase reported nothing: %s" % _line(phases))


func _line(phases: Dictionary) -> String:
	var parts := []
	for phase in phases:
		parts.append("%s=%.2f" % [phase, phases[phase]])
	return " ".join(parts)
