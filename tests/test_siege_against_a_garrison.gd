extends GutTest

## Guards `D-20260828-d067-is-a-rush-rule-and-a-rush-has-no-garrison`
## (#227) — the half of D-067 that had never been measured.
##
## `tests/test_buildings.gd::_rush_cost` places a building and the
## attackers, and nothing else. So "defended" in D-067's own test names
## means only *the building shoots back*, while in a real match it also
## means *somebody is standing there* — and under the second reading the
## rule reverses.
##
## This file measures the second reading, and pins what was decided about
## it: the PAIR rule is a rush rule and a rush is against a base with no
## troops in it; a garrison is a defender defending, and it is supposed to
## work. What a garrison may NOT do is make a base invulnerable.
##
## Every number in the decision came from this fixture.

## The cheapest line troop in the roster. The finding is sharp because of
## the price, not the strength: ~45 RP of screen against several hundred
## RP of attacker.
const SCREEN := &"gildedreach_levy"

## Line troops (the same population D-067's pair rule is asked of). Kept
## here rather than imported so that `test_buildings.gd` and this file can
## be edited independently — they are guarding different claims, and #152
## is a live example of one list being carried somewhere it did not fit.
const LINE_TROOPS := [
	&"stoneblood_levy", &"stoneblood_heavy",
	&"gravesworn_levy", &"gravesworn_spearmen",
	&"thornwood_levy", &"windmarch_levy",
	&"gildedreach_levy", &"gildedreach_spearmen", &"gildedreach_sellswords",
	&"emberdeep_levy", &"emberdeep_heavy",
]


## One siege, with an optional garrison and an optional re-order cadence.
##
## `behind` puts the garrison off the attackers' approach, which is the
## control that separates INTERCEPTION from damage. `reorder_every` is a
## player (or the AI, which re-issues objectives on a cooldown) telling a
## halted squad to carry on — D-034 stops an attack-move on contact and
## nothing resumes it (#249), so without this the measurement is of a
## single order rather than of a siege.
func _siege(building_id: StringName, unit_id: StringName, squad_count: int,
		screens: int, behind := false, reorder_every := 0.0) -> Dictionary:
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var def := BuildingSim.def_by_id(building_id)
	assert_not_null(def, "buildings/%s.tres is missing, so nothing was tested" % building_id)
	var unit := UnitRoster.by_id(unit_id)
	assert_not_null(unit, "the roster should ship %s" % unit_id)
	var screen_def := UnitRoster.by_id(SCREEN)
	assert_not_null(screen_def, "the roster should ship %s" % SCREEN)

	var target := buildings.add_building(def, 1, Vector2i(20, 20), true)
	var defenders := []
	for i in range(screens):
		defenders.append(sim.add_squad(screen_def, 1,
			Vector2i(14, 20 + i) if behind else Vector2i(21, 21 + i)))

	var squads := []
	var started := 0
	for i in range(squad_count):
		var squad := sim.add_squad(unit, 2, Vector2i(26, 20 + i * 2))
		sim.order_attack_move(squad, Vector2i(21, 20))
		squads.append(squad)
		started += sim.alive_of(squad)

	var razed_at := -1
	var reorder_ticks := int(reorder_every * 10.0)
	for i in range(3000):
		sim.tick()
		if reorder_ticks > 0 and i % reorder_ticks == 0:
			for squad in squads:
				if sim.alive_of(squad) > 0:
					sim.order_attack_move(squad, Vector2i(21, 20))
		var alive := 0
		for squad in squads:
			alive += sim.alive_of(squad)
		if buildings.is_destroyed(target):
			razed_at = i
			break
		if alive <= 0:
			break

	var left := 0
	for squad in squads:
		left += sim.alive_of(squad)
	var defenders_left := 0
	for squad in defenders:
		defenders_left += sim.alive_of(squad)
	return {
		"razed": razed_at >= 0,
		"seconds": (razed_at + 1) / 10.0,
		"health": buildings.health_of(target),
		"left": left, "started": started, "defenders_left": defenders_left,
	}


# --- what a garrison actually does -------------------------------------

func test_a_screen_intercepts_rather_than_adds_damage() -> void:
	# THE control, and the reason this is about position rather than
	# strength. The same defending squad placed BEHIND the building — off
	# the approach — leaves the undefended outcome untouched, for every
	# line troop and both buildings. Measured 22 of 22.
	#
	# Without this, "a garrison beats two squads" would be indistinguishable
	# from "the defender simply had more army", and the two want completely
	# different fixes.
	for building in [&"town_centre", &"tower"]:
		for unit_id in LINE_TROOPS:
			var behind := _siege(building, unit_id, 2, 1, true)
			assert_true(bool(behind["razed"]),
				"two squads of %s could not take a %s with a defender standing BEHIND it "
				% [unit_id, building]
				+ "(%.0f HP left) — then the garrison is adding damage, not intercepting"
					% behind["health"])


func test_a_garrisoned_base_is_not_invulnerable() -> void:
	# The clause that keeps the decision honest. D-067's pair rule is
	# scoped to an UNGARRISONED base, and a defender who invests in troops
	# is supposed to be rewarded — but "rewarded" must not mean "cannot be
	# attacked at all".
	#
	# Asked of the roster's heavy line troops, which is where the answer
	# is stable: with the attack re-tasked as a player or the AI would,
	# stoneblood_heavy and emberdeep_heavy take BOTH buildings through a
	# screen. Deliberately not asked of every troop — most line pairs do
	# real damage and still lose, which is the design working.
	for building in [&"town_centre", &"tower"]:
		var took := []
		for unit_id in [&"stoneblood_heavy", &"emberdeep_heavy", &"stoneblood_levy"]:
			var result := _siege(building, unit_id, 2, 1, false, 5.0)
			if bool(result["razed"]):
				took.append(unit_id)
		assert_gt(took.size(), 0,
			"no heavy line pair could take a garrisoned %s even when re-tasked — "
				% building
			+ "a single screening squad has made the base invulnerable, not merely defended")


func test_the_solo_rush_rule_survives_a_garrison() -> void:
	# D-067's other half, which a garrison can only make MORE true. Cheap,
	# and it is the assertion that would catch a future change making
	# garrisons somehow help an attacker.
	for building in [&"town_centre", &"tower"]:
		for unit_id in [&"stoneblood_heavy", &"gravesworn_levy"]:
			var result := _siege(building, unit_id, 1, 1, false, 5.0)
			assert_false(bool(result["razed"]),
				"one squad of %s razed a GARRISONED %s in %.0fs"
					% [unit_id, building, result["seconds"]])


func test_the_pair_rule_is_measured_against_no_garrison_on_purpose() -> void:
	# The scoping itself, stated as an executable claim rather than left
	# in prose: the same pair that takes an ungarrisoned base does NOT
	# take a garrisoned one, for the troops in the middle of the roster.
	# If this ever goes green, the rule and its numbers have drifted into
	# each other and D-067's two halves need re-deriving together.
	var bare := _siege(&"town_centre", &"thornwood_levy", 2, 0)
	assert_true(bool(bare["razed"]),
		"setup: two thornwood_levy squads must take an UNGARRISONED town centre "
		+ "(%.0f HP left) — that is D-067's pair rule and PR #222's numbers"
			% bare["health"])
	var garrisoned := _siege(&"town_centre", &"thornwood_levy", 2, 1, false, 5.0)
	assert_false(bool(garrisoned["razed"]),
		"two thornwood_levy squads took a GARRISONED town centre — the pair rule and the "
		+ "garrison case have converged, so D-067's scope needs re-deriving")
