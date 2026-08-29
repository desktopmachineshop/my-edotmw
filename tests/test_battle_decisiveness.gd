extends GutTest

## The instrument for D-20260828-a-fight-is-decided-by-two-percent (#346).
##
## How big an edge does one side need before an engagement stops being a
## fight and starts being a foregone conclusion? Everything else in the
## estate measures whether combat is CORRECT; nothing measured whether it
## is DECIDABLE, and #267's levy tier list turned out to be a symptom of
## that rather than a roster fault.
##
## **There is deliberately no threshold assertion here.** A guard on "a 5%
## edge must not win everything" was written, run, and REMOVED: at a sample
## small enough to belong in the suite it reports 4-0 on the current tree,
## so it would have shipped red. The number it would guard is the one #346
## exists to change, and the right place for a tight bound is alongside
## #328/#257 once those land and the curve has moved.
##
## **This is an instrument, not a gate**, in the style of
## `just bench-render` and `just gen-terrain-shot`: it PRINTS the
## decisiveness curve and asserts only the properties that must hold
## whatever the numbers are. A threshold assertion would be wrong here on
## purpose — the number is expected to MOVE when #328 (morale scales with
## squad size) and #257 (no morale recovery under fire) land, and the
## decision entry records what it should move to.
##
## Read the printed curve, not just the pass.

## Damage advantages given to one side, as a fraction.
const EDGES := [0.0, 0.05, 0.20]
## Two seeds, and each fought BOTH ways round, so a position advantage
## cancels instead of being read as a unit advantage. That correction is
## load-bearing: an early version of this measurement ran one way round
## and reported a side effect as a roster ranking.
const SEEDS := [11, 2029]
## Long enough that a duel of these squads reaches a conclusion; the
## fixture asserts it actually did rather than trusting the cap.
const MAX_TICKS := 2400


func _levy() -> UnitDef:
	return UnitRoster.for_civ_archetype(&"stoneblood", &"levy")


## One duel. Returns
## [a survivors, b survivors, a start, b start, ticks, ended_in_a_wipe].
func _duel(a_def: UnitDef, b_def: UnitDef, seed_value: int) -> Array:
	var space := TorusSpace.new(40, 32, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.buildings = BuildingSim.new(space)
	sim.combat_seed = seed_value
	var a_at := Vector2i(14, 16)
	var b_at := Vector2i(24, 16)
	var a := sim.add_squad(a_def, 1, a_at)
	var b := sim.add_squad(b_def, 2, b_at)
	var a_start := sim.alive_of(a)
	var b_start := sim.alive_of(b)
	sim.order_attack_move(a, b_at)
	sim.order_attack_move(b, a_at)
	var ticks := 0
	var wiped := false
	for _i in range(MAX_TICKS):
		sim.tick()
		ticks += 1
		if sim.alive_of(a) <= 0 or sim.alive_of(b) <= 0:
			wiped = true
			break
	return [sim.alive_of(a), sim.alive_of(b), a_start, b_start, ticks, wiped]


## Plays `edge` both ways round over every seed and returns
## [stronger side's wins, weaker side's wins, fights that ended in a wipe].
func _score(edge: float) -> Array[int]:
	var strong := 0
	var weak := 0
	var wipes := 0
	for seed_value in SEEDS:
		for swap in [false, true]:
			var buffed: UnitDef = _levy().duplicate()
			buffed.damage = _levy().damage * (1.0 + edge)
			var stock := _levy()
			var r := _duel(stock if swap else buffed, buffed if swap else stock,
				seed_value)
			var s_frac := float(r[1] if swap else r[0]) / float(r[3] if swap else r[2])
			var w_frac := float(r[0] if swap else r[1]) / float(r[2] if swap else r[3])
			if s_frac > w_frac:
				strong += 1
			elif w_frac > s_frac:
				weak += 1
			if r[5]:
				wipes += 1
	return [strong, weak, wipes] as Array[int]


func test_the_decisiveness_curve_is_printed_and_the_fixture_resolves() -> void:
	var fights_per_edge := SEEDS.size() * 2
	var total_wipes := 0
	var results := {}
	gut.p("edge  stronger-weaker (of %d)  fights that ended in a wipe"
		% fights_per_edge)
	for edge in EDGES:
		var s := _score(edge)
		results[edge] = s
		total_wipes += s[2]
		gut.p("%4.0f%%  %2d-%-2d                    %d" % [
			100.0 * edge, s[0], s[1], s[2]])

	# Vacuity guards first: every number above is worthless if the duels
	# did not actually happen. A fixture that never resolved would report
	# a tidy 0-0 at every edge and read as perfect balance.
	for edge in EDGES:
		var s: Array[int] = results[edge]
		assert_eq(s[0] + s[1], fights_per_edge,
			"at edge %.2f, %d of %d fights drew — the squads never met, so the "
			% [edge, fights_per_edge - s[0] - s[1], fights_per_edge]
			+ "curve above measures nothing")
	assert_gt(total_wipes, 0,
		"no fight anywhere reached a conclusion inside MAX_TICKS — the cap is "
		+ "too short and every row above is a timeout, not a result")


func test_how_much_of_a_mirror_match_is_decided_by_POSITION() -> void:
	# Identical squads, identical orders, symmetric positions: anything
	# that decides this is not the troops.
	#
	# Counted by POSITION, which is the correction that makes it mean
	# anything. The curve above counts by which DEF was buffed and plays
	# both ways round, so a side bias cancels out of it exactly — the
	# first version of this test reused that scoring and was observed NOT
	# to fail when combat.gd was perturbed to give squad 0 a flat 25%
	# damage bonus. It reported a tidy 2-2 throughout.
	#
	# Measured, not gated, and deliberately so: on the current tree some
	# mirrors ARE decided by position (over six seeds, emberdeep's levy
	# went 0-6 and windmarch's 0-6, while gravesworn's went 5-1). That is
	# a finding recorded in the decision entry, not something this file
	# can assert away.
	var first := 0
	var second := 0
	var drew := 0
	for seed_value in SEEDS:
		var r := _duel(_levy(), _levy(), seed_value)
		var a_frac := float(r[0]) / float(r[2])
		var b_frac := float(r[1]) / float(r[3])
		if a_frac > b_frac:
			first += 1
		elif b_frac > a_frac:
			second += 1
		else:
			drew += 1
	gut.p("mirror by position: first-placed %d, second-placed %d, drew %d (of %d)"
		% [first, second, drew, SEEDS.size()])
	assert_eq(first + second + drew, SEEDS.size(),
		"a mirror fight was not scored at all")
	assert_gt(first + second, 0,
		"every mirror fight drew — the squads never met, so this measures nothing")
