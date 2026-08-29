extends GutTest

## Guards D-20260828-a-levy-is-a-sidegrade-and-a-duel-is-not-the-test
## (issue #267): every civ's levy was strictly ranked, 14 of 15 pairings
## 6-0.
##
## These assert the PROPERTY, never the shipped numbers, so they survive
## #266 (morale scales with squad size) and #218 (morale suppression)
## landing on top of them: what must stay true is that no levy is a tier,
## not that emberdeep's levy deals 8.2.
##
## The band constants below are MEASURED, not chosen — see the decision
## entry's probe table. A 5% edge in V is already a clean sweep (12-0),
## and no other field in UnitDef is worth 8% of V, so 8% is where a
## difference stops being an identity and becomes a rank.

## The V edge at which a duel becomes a certain sweep. Measured: damage
## x1.10 (V x1.05) scored 12-0 with +82 men of 24; the reach probes show
## nothing else in the schema buys 8% back.
const SWEEP_THRESHOLD := 0.08

const LEVY := &"levy"


func _levies() -> Array[UnitDef]:
	var out: Array[UnitDef] = []
	for def in UnitRoster.load_all():
		if def.archetype == LEVY:
			out.append(def)
	return out


## D-072's power number. For a melee in which every man is engaged — which
## is what a levy fight is, measured at 100% of the squad in contact up to
## n=40 — V squared is exactly Lanchester's square-law strength, which is
## why it predicts these duels and why the band below is drawn on it.
func _power(def: UnitDef) -> float:
	return float(def.squad_size) * sqrt(
		(def.damage / def.attack_interval) * def.health)


## D-072's resource number.
func _price(def: UnitDef) -> float:
	return float(def.cost_food + def.cost_wood) \
		+ 1.5 * float(def.cost_gold + def.cost_stone)


func _spread(values: Array[float]) -> float:
	var lo: float = values[0]
	var hi: float = values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi / lo - 1.0


func test_the_roster_ships_a_levy_for_every_civ() -> void:
	# Without this the rest of the file can pass by measuring one unit.
	var levies := _levies()
	var civs := {}
	for def in levies:
		civs[def.civ] = true
	assert_gt(civs.size(), 3,
		"fewer than four civs field a levy — the comparison below is vacuous")
	assert_eq(levies.size(), civs.size(),
		"a civ fields two levies; the pairwise checks would compare a civ to itself")


func test_no_levy_is_a_tier() -> void:
	# Squad power inside the band at which a duel stops being decided by
	# the roster. Above it the stronger levy simply wins, every seed.
	var powers: Array[float] = []
	for def in _levies():
		powers.append(_power(def))
	var spread := _spread(powers)
	gut.p("levy V spread %.1f%% (threshold %.0f%%)" % [
		100.0 * spread, 100.0 * SWEEP_THRESHOLD])
	assert_lt(spread, SWEEP_THRESHOLD,
		"a levy is more than a sweep-threshold stronger than another, " +
		"which makes the roster a tier list — see #267")


func test_no_levy_is_a_bargain() -> void:
	# Equal power at unequal price is the same defect one step removed:
	# the cheap one is strictly better per resource. Gravesworn's levy
	# cost 32 against everyone else's 38-50 and led efficiency by 50%.
	var rates: Array[float] = []
	for def in _levies():
		rates.append(_power(def) / _price(def))
	var spread := _spread(rates)
	gut.p("levy V/RP spread %.1f%% (threshold %.0f%%)" % [
		100.0 * spread, 100.0 * SWEEP_THRESHOLD])
	assert_lt(spread, SWEEP_THRESHOLD,
		"one civ's levy buys materially more power per resource than " +
		"another's — quantity must mean bodies per squad, not a discount")


func test_no_levy_is_dominated_on_both_axes() -> void:
	# D-072's standing rule, applied within one archetype: a unit that is
	# beaten on power AND on cost-efficiency has no reason to be fielded.
	var levies := _levies()
	for a in levies:
		var beaten_by: Array[String] = []
		for b in levies:
			if a.civ == b.civ:
				continue
			var stronger := _power(b) > _power(a) * (1.0 + SWEEP_THRESHOLD)
			var cheaper := _power(b) / _price(b) \
				> _power(a) / _price(a) * (1.0 + SWEEP_THRESHOLD)
			if stronger and cheaper:
				beaten_by.append(String(b.civ))
		assert_eq(beaten_by, [] as Array[String],
			"%s's levy is beaten on power AND efficiency by %s" % [
				a.civ, ", ".join(beaten_by)])


func test_every_pair_of_levies_differs_where_a_duel_cannot_see() -> void:
	# Equal power is only half the decision. If the levies were also
	# identically shaped, priced and paced they would be one unit in six
	# colours — which is the other way to satisfy the bands above.
	#
	# Every axis here was measured to be worth less than the sweep
	# threshold in a stand-up duel, which is exactly why it is safe to
	# carry identity: move_speed scored 6-6 doubled, reach 4-4 at +0.2.
	var levies := _levies()
	for i in range(levies.size()):
		for j in range(i + 1, levies.size()):
			var a := levies[i]
			var b := levies[j]
			var differs: Array[String] = []
			if a.squad_size != b.squad_size:
				differs.append("squad_size")
			if not is_equal_approx(a.move_speed, b.move_speed):
				differs.append("move_speed")
			if not is_equal_approx(a.attack_range, b.attack_range):
				differs.append("attack_range")
			if a.formation_shape != b.formation_shape:
				differs.append("formation_shape")
			if not is_equal_approx(a.formation_spacing, b.formation_spacing):
				differs.append("formation_spacing")
			if not is_equal_approx(a.build_time, b.build_time):
				differs.append("build_time")
			if not is_equal_approx(a.rout_threshold, b.rout_threshold):
				differs.append("rout_threshold")
			assert_gt(differs.size(), 1,
				"%s's and %s's levies differ on %d axis/axes a duel " % [
					a.civ, b.civ, differs.size()] +
				"cannot see (%s) — at equal power that makes them one unit" % [
					", ".join(differs)])


func test_a_levy_pairing_is_not_a_sweep_when_it_is_actually_played() -> void:
	# The bands above are arithmetic over the roster, and arithmetic can
	# be true of a model that does not describe the game. One pairing is
	# played through the real sim so the paper cannot pass alone.
	#
	# ONE pairing rather than the full 15: the matrix is minutes of
	# simulation. This is the pair #267 put at opposite ends of its
	# ranking — gildedreach near the top, windmarch at the bottom.
	#
	# The CONTROL below is not decoration. This fixture was observed to
	# stay green with one side given a 20% damage edge — a cross-civ
	# pairing carries position effects a mirror match does not, so it
	# catches a gross imbalance and not a fine one. Without a positive
	# control there is no way to tell "these levies are even" from "this
	# fixture stopped resolving", which is the vacuous-pass shape D-022's
	# audit block was written against.
	# A SIDE THAT BREAKS HAS LOST, and scoring by surviving fraction said
	# the opposite (#396's sibling, traced in
	# D-20260829-a-routed-squad-is-not-the-winner).
	#
	# Measured at seed 11 before this changed: the two squads closed, the
	# WINDMARCH levy broke at t=6 and withdrew to eight cells, gildedreach
	# did not pursue, and both sides sat frozen at exactly 20 men for the
	# remaining fourteen seconds. Gildedreach had lost 10 of 30 and
	# windmarch 8 of 28 — so the fraction was 0.67 against 0.71 and the
	# fixture crowned THE SIDE THAT RAN. Routing preserves your fraction,
	# because a fleeing squad stops taking casualties and nothing chases
	# it.
	#
	# That also inverted the control: doubling gildedreach's damage breaks
	# windmarch SOONER, so it flees with MORE men and the buff moves the
	# fraction the wrong way. The control was not insensitive, it was
	# pointed backwards — which is why it could not see a doubled stat.
	#
	# So the engagement is decided by who broke first, which is D-019's own
	# premise and what `docs/status/rtw-battles.md` already says in words:
	# "a rout is a defeat rather than a pause". Surviving fraction remains
	# the tie-break for fights where neither side breaks.
	var even := _play_pairing(0.0)
	gut.p("played gildedreach %d - %d windmarch (of 6)" % [even[0], even[1]])
	assert_gt(even[0] + even[1], 0,
		"every fight drew — the fixture never resolved, so it proves nothing")
	assert_gt(even[0], 0, "windmarch's levy swept gildedreach's in every fight")
	assert_gt(even[1], 0, "gildedreach's levy swept windmarch's in every fight")

	var rigged := _play_pairing(1.0)
	gut.p("control: gildedreach at double damage %d - %d (of 6)" % [
		rigged[0], rigged[1]])
	assert_eq(rigged[1], 0,
		"CONTROL FAILED: doubling one levy's damage did not sweep, so this " +
		"fixture cannot see an imbalance and the even result above is worth " +
		"nothing")


## Plays gildedreach's levy against windmarch's, three seeds, both sides,
## and returns [gildedreach wins, windmarch wins]. `buff` adds that
## fraction to gildedreach's damage — 0.0 for the shipped defs.
func _play_pairing(buff: float) -> Array[int]:
	var wins := 0
	var losses := 0
	for seed_value in [11, 2029, 7919]:
		for swap in [false, true]:
			var gilded_def := UnitRoster.for_civ_archetype(&"gildedreach", LEVY)
			if buff > 0.0:
				gilded_def = gilded_def.duplicate()
				gilded_def.damage *= (1.0 + buff)
			var wind_def := UnitRoster.for_civ_archetype(&"windmarch", LEVY)
			var first: UnitDef = wind_def if swap else gilded_def
			var second: UnitDef = gilded_def if swap else wind_def
			var outcome := _play(first, second, seed_value)
			var gilded: float = outcome[1] if swap else outcome[0]
			var wind: float = outcome[0] if swap else outcome[1]
			var broke: int = int(outcome[2])
			var gilded_broke := broke == (2 if swap else 1)
			var wind_broke := broke == (1 if swap else 2)
			# ANNIHILATION OUTRANKS BREAKING (#406). A rout is not final:
			# a broken squad can rally (D-019) and go on to destroy the
			# side that held. Scoring by who broke first alone credited
			# gildedreach a win in a fight it ended at 0.00 — wiped, after
			# windmarch broke and came back. A squad reduced to nothing has
			# lost, whatever the morale ledger says, so the wipe is read
			# first and first-to-break decides only among survivors.
			var decided := true
			if gilded <= 0.0 and wind > 0.0:
				losses += 1
			elif wind <= 0.0 and gilded > 0.0:
				wins += 1
			elif gilded_broke:
				losses += 1
			elif wind_broke:
				wins += 1
			elif gilded > wind:
				wins += 1
			elif wind > gilded:
				losses += 1
			else:
				decided = false
			gut.p("    seed %-5d swap=%-5s  gilded %.2f  wind %.2f  broke=%-6s %s"
				% [seed_value, str(swap), gilded, wind,
					"gilded" if gilded_broke else ("wind" if wind_broke else "-"),
					"" if decided else "(undecided)"])
	return [wins, losses] as Array[int]


func _play(a_def: UnitDef, b_def: UnitDef, seed_value: int = 11) -> Array:
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
	assert_gt(a_start, 0, "one side fielded nobody")
	assert_gt(b_start, 0, "one side fielded nobody")
	sim.order_attack_move(a, b_at)
	sim.order_attack_move(b, a_at)
	var joined := false
	var broke := 0  # 0 nobody, 1 the first squad, 2 the second
	for _i in range(1500):
		sim.tick()
		if sim.alive_of(a) < a_start or sim.alive_of(b) < b_start:
			joined = true
		if broke == 0:
			# FIRST to break, latched. A squad can rally afterwards
			# (D-019), so "is routed at the end" is not the same question
			# and would score a fight by whether the loser had recovered
			# yet.
			if sim.is_routed(a):
				broke = 1
			elif sim.is_routed(b):
				broke = 2
		if sim.alive_of(a) <= 0 or sim.alive_of(b) <= 0:
			break
	assert_true(joined,
		"the two squads never traded a casualty — they never met, so the " +
		"result says nothing about the levies")
	return [float(sim.alive_of(a)) / a_start, float(sim.alive_of(b)) / b_start, broke]


## TEMPORARY (#406) — measures which buff factor actually sweeps under the
## corrected metric, so the control is calibrated rather than guessed.
## Deleted in the same PR once the number is recorded.
func test_TEMP_which_factor_sweeps() -> void:
	for buff in [2.0, 3.0, 4.0, 6.0]:
		var r := _play_pairing(buff)
		gut.p("FACTOR x%.1f -> gilded %d - %d wind  (sweep needs wind = 0)"
			% [1.0 + buff, r[0], r[1]])
	assert_true(true)
