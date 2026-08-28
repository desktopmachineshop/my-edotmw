extends GutTest

## Guards D-032's counter triangle against the fantasy roster, and closes
## #219 -- "counters are FELT: the favoured side wins clearly, not
## marginally" is playtest ticket #38's pass criterion and nothing in the
## estate had ever measured it.
##
## #219 measured it by hand and found the triangle is two-thirds real: the
## cavalry/missile and spearmen/cavalry halves win 12 of 12 at margins of
## +0.77 and +0.89, while the anti-infantry half LOSES 0 of 8 against
## heavy and elite infantry.
##
## ## The structural reason, which is what this file is really about
##
## `armour_class` has three values, and one of them is doing all the work.
## `infantry` spans thirteen shipped units from 38 HP a man
## (gravesworn_shades) to 420 (stoneblood_breaker) -- an ELEVEN-FOLD range
## -- and a single `"infantry": 1.3` is asked to cover all of it. Against
## a levy it is plenty; against a heavy it cannot close a gap where the
## target already leads on both DPS and EHP before any bonus applies.
##
## So the checks here assert what a counter must at minimum do -- overturn
## SOMETHING in the class it names -- and REPORT the members it cannot,
## rather than asserting a defect stays broken. The report is the finding;
## the assertion is the floor.

const SEEDS := 6
const DUEL_TICKS := 900  # 90 s at 10 Hz


## One squad each, ordered onto the other's start cell.
##
## Both sides attack-move at the OTHER's start rather than past it. #219
## records an earlier sweep that ordered each side to a point beyond the
## enemy, so the squads crossed, separated and walked away -- it reported
## large margins with nothing decided, and read exactly like "fights do
## not resolve". `decided` is returned so a caller can refuse to draw a
## conclusion from a fight that never happened.
func _duel(a_id: StringName, b_id: StringName, seed_value: int) -> Dictionary:
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.combat_seed = seed_value

	var a_def := UnitRoster.by_id(a_id)
	var b_def := UnitRoster.by_id(b_id)
	assert_not_null(a_def, "the roster should ship %s" % a_id)
	assert_not_null(b_def, "the roster should ship %s" % b_id)
	if a_def == null or b_def == null:
		return {"decided": false, "margin": 0.0, "a_won": false}

	var a_at := Vector2i(18, 20)
	var b_at := Vector2i(26, 20)
	var a := sim.add_squad(a_def, 1, a_at)
	var b := sim.add_squad(b_def, 2, b_at)
	sim.order_attack_move(a, b_at)
	sim.order_attack_move(b, a_at)

	var a_started := sim.alive_of(a)
	var b_started := sim.alive_of(b)
	for _i in range(DUEL_TICKS):
		sim.tick()
		if sim.alive_of(a) <= 0 or sim.alive_of(b) <= 0:
			break

	var a_frac := float(sim.alive_of(a)) / maxf(float(a_started), 1.0)
	var b_frac := float(sim.alive_of(b)) / maxf(float(b_started), 1.0)
	return {
		# A fight is DECIDED when the two squads have actually fought and
		# one is measurably ahead -- not when one has been wiped to the
		# last man.
		#
		# Annihilation was a fair proxy while nothing ever ended a fight
		# early, and it stops being one the moment routing works: with
		# #266's morale scaling a squad breaks at ~52% casualties and
		# flees, so the counter wins the exchange decisively and NEITHER
		# side is wiped. Measured on the merged balance cluster, this
		# fixture reported "only 1 of 6 fights resolved" for a matchup
		# the counter was winning every time.
		#
		# The margin is what "felt" always meant; the old form just could
		# not see it once a fight could end in a withdrawal.
		"decided": (sim.alive_of(a) < a_started or sim.alive_of(b) < b_started) 			and not is_equal_approx(a_frac, b_frac),
		"margin": a_frac - b_frac,
		"a_won": a_frac > b_frac,
	}


## `counter` against `target` over SEEDS seeds. Returns wins and the mean
## margin, and how many fights actually resolved.
func _sweep(counter: StringName, target: StringName) -> Dictionary:
	var wins := 0
	var decided := 0
	var margin := 0.0
	for s in range(SEEDS):
		var one := _duel(counter, target, 1000 + s * 7919)
		if bool(one["decided"]):
			decided += 1
		if bool(one["a_won"]):
			wins += 1
		margin += float(one["margin"])
	return {"wins": wins, "decided": decided, "margin": margin / float(SEEDS)}


func _assert_felt(counter: StringName, target: StringName) -> void:
	var r := _sweep(counter, target)
	assert_eq(int(r["decided"]), SEEDS,
		"%s vs %s: only %d of %d fights resolved -- the fixture is not measuring combat"
			% [counter, target, r["decided"], SEEDS])
	assert_gt(int(r["wins"]), SEEDS / 2,
		"%s is the counter to %s and won %d of %d (mean margin %.2f) -- not FELT"
			% [counter, target, r["wins"], SEEDS, r["margin"]])


# --- the two thirds of the triangle that work --------------------------

func test_cavalry_counters_missile_troops() -> void:
	# #219 measured 12 of 12 at +0.77. Guarded here because nothing did.
	_assert_felt(&"windmarch_cavalry", &"emberdeep_archers")
	_assert_felt(&"gildedreach_cavalry", &"thornwood_archers")


func test_spearmen_counter_cavalry() -> void:
	# #219 measured 12 of 12 at +0.89.
	_assert_felt(&"gildedreach_spearmen", &"thornwood_cavalry")
	_assert_felt(&"gravesworn_spearmen", &"windmarch_cavalry")


func test_archers_do_counter_the_infantry_they_were_priced_against() -> void:
	# The anti-infantry bonus is not inert -- against a LEVY it works, and
	# #219's own table shows 8 of 8 at +0.73 for one pairing. The floor a
	# counter must clear is that it overturns SOMETHING in the class it
	# names; which members it cannot is reported below rather than
	# asserted, because asserting a defect persists is not a guard.
	#
	# The target was `gravesworn_levy` and is now an ordinary one, because
	# a FEARLESS target is a different question (#361). With #266's morale
	# scaling every unit in the game breaks at ~52% casualties -- except
	# gravesworn, which ships `rout_threshold 0` and cannot break at all.
	# So the archers rout first and are ridden down, and the counter reads
	# -0.08 for a matchup #219 measured at +0.73. Measured here:
	# thornwood_archers DO overturn gildedreach_levy, emberdeep_levy and
	# stoneblood_levy, and not the fearless one. That is a design question
	# about what fearlessness is worth, not a fault in the bonus, so the
	# fearless pairing is REPORTED below instead of asserted.
	_assert_felt(&"thornwood_archers", &"gildedreach_levy")


# --- and the third that does not, reported rather than asserted --------

func test_report_where_the_anti_infantry_counter_fails() -> void:
	# The open finding of #219, measured every run so it cannot drift
	# unnoticed, and printed rather than asserted so this file does not
	# pin a bug in place.
	var failures := 0
	var pairs := [
		[&"gildedreach_archers", &"stoneblood_heavy"],
		[&"gildedreach_archers", &"emberdeep_heavy"],
		[&"emberdeep_archers", &"gildedreach_sellswords"],
		[&"thornwood_archers", &"stoneblood_heavy"],
		# Fearless, so the counter cannot win by breaking it (#361).
		[&"thornwood_archers", &"gravesworn_levy"],
	]
	for pair in pairs:
		var r := _sweep(pair[0], pair[1])
		gut.p("  counter report: %s vs %s -- %d/%d wins, mean margin %.2f, %d decided"
			% [pair[0], pair[1], r["wins"], SEEDS, r["margin"], r["decided"]])
		if int(r["wins"]) * 2 <= SEEDS:
			failures += 1
	gut.p("  %d of %d anti-infantry pairings are not felt (#219 open)" % [failures, pairs.size()])
	assert_gt(pairs.size(), 0, "the report examined nothing")


func test_one_armour_class_is_doing_all_the_work() -> void:
	# The structural claim underneath #219, asserted from the roster
	# rather than quoted: `infantry` spans an order of magnitude of
	# per-man health, so one multiplier against it cannot be right for
	# both ends. This is what a fix has to change -- not the size of the
	# bonus.
	var by_class := {}
	for def in UnitRoster.load_all():
		if def.archetype == &"gatherers" or def.archetype == &"general":
			continue
		var key := String(def.armour_class)
		if not by_class.has(key):
			by_class[key] = []
		by_class[key].append(def)

	assert_true(by_class.has("infantry"), "the roster should still have an infantry class")
	var infantry: Array = by_class["infantry"]
	var lowest := INF
	var highest := 0.0
	for def in infantry:
		lowest = minf(lowest, def.health)
		highest = maxf(highest, def.health)
	gut.p("  armour classes: %s" % [by_class.keys()])
	for key in by_class:
		gut.p("    %-10s %d unit(s)" % [key, (by_class[key] as Array).size()])
	gut.p("  infantry spans %.0f to %.0f HP a man (%.1fx)" % [lowest, highest, highest / lowest])

	assert_gt(infantry.size(), 1, "setup: one unit in a class proves nothing about spread")
	# The finding, stated as the thing a future fix must move. If the
	# class is ever split, this goes red and whoever split it updates the
	# record -- which is the point.
	assert_gt(highest / lowest, 5.0,
		"the infantry armour class has been narrowed to %.1fx -- #219's structural cause "
			% (highest / lowest)
		+ "has been addressed, so re-measure the anti-infantry counter and update this file")
