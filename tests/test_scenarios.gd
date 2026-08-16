extends GutTest

## Guards the scenario framework itself (D-096).
##
## A fixture that silently builds the wrong world is worse than no
## fixture: every test written on top of it passes while testing
## something else. So this file asserts the framework's own promises —
## that a scenario places what it says it places, near where it says, for
## every civ, deterministically, and that it fails LOUDLY when it cannot.
##
## Each check here was observed to fail before being trusted, per the
## standing rule (see the report accompanying this change).


const W := 32
const H := 16


# --- the shipped scenarios are real -----------------------------------

## Every .tres under /scenarios loads and validates. A broken scenario
## file must fail here rather than at 3am inside a load test, where a
## half-built world looks exactly like a simulation bug.
func test_every_shipped_scenario_validates() -> void:
	var all := Scenario.load_all()
	assert_gt(all.size(), 0, "no scenarios found under res://scenarios")
	for def in all:
		assert_eq(def.validate(), "",
			"scenario '%s' does not validate" % def.id)


## …and each is reachable by the id the --scenario flag would name. An id
## that does not match its filename would make `--scenario=x` fail with
## "no such scenario" while the file sits right there.
func test_every_scenario_is_reachable_by_its_id() -> void:
	for def in Scenario.load_all():
		assert_not_null(Scenario.by_id(def.id),
			"Scenario.by_id('%s') found nothing" % def.id)


func test_an_unknown_scenario_id_returns_null_rather_than_erroring() -> void:
	assert_null(Scenario.by_id(&"no_such_scenario"))


# --- placement --------------------------------------------------------

## The headline promise: things land NEAR each other, on demand. This is
## the whole reason the framework exists — real spawns are scattered far
## apart (D-039), so two armies need a minute of walking before anything
## interesting happens.
## Built on 64x32, NOT the 32x16 the rest of this file uses, and the size
## is the whole point of the test.
##
## The first version asserted `gap < 20` on 32x16, where the maximum
## representable distance between any two cells is 16 — so it could not
## fail however broken placement was, and it duly passed with the
## separation logic deliberately sabotaged. That is the vacuous-pass shape
## this project keeps paying for (the "0 desyncs" scan, the log grep for a
## word no code printed). A distance bound is only a check on a map where
## exceeding it is possible: max distance is 32 here, against a bound of
## 14.
func test_separation_puts_two_players_within_reach() -> void:
	var def := Scenario.by_id(&"clash")
	var w := ScenarioWorld.build(def, 2, 64, 32)
	assert_not_null(w)
	var a := w.squads_of(1)
	var b := w.squads_of(2)
	assert_gt(a.size(), 0, "player 1 got no squads")
	assert_gt(b.size(), 0, "player 2 got no squads")

	# Tied to what the scenario ASKED for, plus the slack placement is
	# allowed to nudge things by — not a magic number that would drift out
	# of relation to the file the moment separation changed.
	var bound: int = def.separation + def.placement_slack
	var gap := w.space.distance(w.sim.cell_of(a[0]), w.sim.cell_of(b[0]))
	assert_lte(gap, bound,
		"armies %d cells apart, scenario asked for %d (+%d slack) — too far to meet quickly"
			% [gap, def.separation, def.placement_slack])


func test_squads_do_not_stack_on_one_cell() -> void:
	var w := ScenarioWorld.build("clash", 2, W, H)
	var seen := {}
	for id in range(w.sim.squad_count()):
		var idx := w.space.index(w.sim.cell_of(id))
		assert_false(seen.has(idx),
			"squad %d shares a cell with squad %s" % [id, seen.get(idx, -1)])
		seen[idx] = id


## Nothing may be dropped in silence. A scenario that quietly failed to
## place half an army would look identical to a simulation that lost it.
func test_a_clean_placement_reports_nothing_skipped() -> void:
	var w := ScenarioWorld.build("clash", 2, W, H)
	assert_eq(w.skipped(), [], "placement skipped entries")


## …and when it genuinely cannot place something, it SAYS so. Zero slack
## on a fully impassable map is the cheapest way to make placement fail.
func test_an_impossible_placement_is_reported_not_swallowed() -> void:
	var def := ScenarioDef.new()
	def.id = &"unplaceable"
	def.placement_slack = 0
	var entry := ScenarioSquad.new()
	entry.archetype = &"militia"
	entry.count = 2
	def.squads = [entry]

	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var blocked := PackedByteArray()
	blocked.resize(space.cell_count())
	blocked.fill(0)  # nothing passable anywhere

	var civs := CivRoster.load_all()
	var placement := Scenario.apply_player(def, 1, civs[0].id,
		Vector2i(4, 4), sim, BuildingSim.new(space), null, blocked, {})

	assert_eq(placement.squads.size(), 0, "placed a squad on impassable ground")
	assert_gt(placement.skipped.size(), 0,
		"placement failed silently — nothing reported in skipped")


# --- it must be the world the simulation actually uses -----------------

## The blind-spot guard. A fixture that stamps its OWN Vision, or builds
## its own anything, tests an object the real game never reads. This
## asserts the world's vision IS the sim's vision — the same object, not
## an equal one.
func test_the_worlds_vision_is_the_sims_own() -> void:
	var w := ScenarioWorld.build("clash", 2, W, H)
	assert_true(w.vision == w.sim.vision,
		"ScenarioWorld exposes a Vision the simulation does not tick")


## Squads spawned by a scenario are ordinary squads: they replicate.
## add_squad registers a curve with the replicator, and a scenario that
## bypassed it would produce armies no client could ever see.
func test_scenario_squads_are_replicated_like_any_other() -> void:
	var w := ScenarioWorld.build("clash", 2, W, H)
	for id in w.squads_of(1):
		assert_true(w.replicator.has_object(id),
			"squad %d is not registered with the replicator — it would be invisible to every client" % id)
		assert_not_null(w.replicator.get_curve(id),
			"squad %d has no curve" % id)


# --- determinism ------------------------------------------------------

## Same scenario, same seed, same world. A fixture that varied run to run
## would make every test built on it flaky, and for the same reason
## combat is seeded rather than wall-clock (D-024).
func test_the_same_scenario_builds_the_same_world_twice() -> void:
	var a := ScenarioWorld.build("clash", 2, W, H)
	var b := ScenarioWorld.build("clash", 2, W, H)
	assert_eq(a.sim.squad_count(), b.sim.squad_count())
	for id in range(a.sim.squad_count()):
		assert_eq(a.sim.cell_of(id), b.sim.cell_of(id),
			"squad %d landed on a different cell the second time" % id)


# --- civ neutrality ---------------------------------------------------

## A scenario names an ARCHETYPE, so it plays for every civ. This is what
## keeps scenarios out of the "no .gd names a civ" rule and stops a
## fixture from quietly exercising one roster (the same trap D-046
## criterion 10 guards the load test against).
func test_a_scenario_fields_troops_for_every_civ() -> void:
	var def := Scenario.by_id(&"clash")
	var space := TorusSpace.new(W, H, 1.0)
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)

	for civ in CivRoster.load_all():
		var sim := SquadSim.new(space, CurveReplicator.new())
		var placement := Scenario.apply_player(def, 1, civ.id, Vector2i(4, 4),
			sim, BuildingSim.new(space), null, passable, {})
		assert_eq(placement.squads.size(), def.squad_count(),
			"civ '%s' fielded %d of %d squads" % [
				civ.id, placement.squads.size(), def.squad_count()])
		assert_eq(placement.skipped, [],
			"civ '%s' could not field part of the scenario" % civ.id)
