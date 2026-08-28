extends GutTest

## Guards D-20260819-a-formation-is-a-fighting-style: the knobs default
## to no-ops, a shield wall halves frontal damage in a whole encounter, a
## testudo shrugs arrows, protection costs pace, and a granted formation
## reaches the squad while an ungranted one exists but is not offered.

const W := 48
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _fighter(ranged := false) -> UnitDef:
	var d := UnitDef.new()
	d.id = &"style_test"
	d.squad_size = 20
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.health = 10.0
	d.damage = 1.0
	d.attack_range = 8.0 if ranged else 3.0
	d.attack_interval = 0.1
	d.damage_variance = 0.0
	d.morale = 100000.0
	d.rout_threshold = 0.0
	if ranged:
		d.armour_class = "missile"
	return d


func test_the_knobs_default_to_a_no_op() -> void:
	for id in [&"line", &"column", &"tight", &"sparse", &"wedge", &"ring"]:
		var def := FormationRoster.by_id(id)
		if def == null:
			continue
		assert_eq(def.taken_front, 1.0, "%s taken_front" % id)
		assert_eq(def.missile_taken, 1.0, "%s missile_taken" % id)
		assert_eq(def.pace_scale, 1.0,
			("%s pace_scale — a formation that predates the knobs must be "
			+ "bit-for-bit unchanged") % id)


func _frontal_casualties(shape: String) -> int:
	var sim := _sim()
	var attacker := sim.add_squad(_fighter(), 1, Vector2i(8, 8))
	var defender_def := _fighter()
	defender_def.damage = 0.0
	var defender := sim.add_squad(defender_def, 2, Vector2i(9, 8))
	sim.set_shape(defender, shape)
	# Face the attacker so the blow is FRONTAL — the wall's strong arc.
	sim.set_facing(defender, BattleLine.quantise_angle(
		atan2(-1.73, 0.0)))
	var before := sim.alive_of(defender)
	# Eight ticks: long enough for several exchanges, short enough that
	# the WALLED squad is not also wiped — a window that kills both reads
	# 20 == 20 and proves nothing (the wiped-window trap, again).
	for _t in range(8):
		sim.tick()
	return before - sim.alive_of(defender)


func test_a_shield_wall_blunts_a_frontal_assault() -> void:
	var open_order := _frontal_casualties("line")
	var walled := _frontal_casualties("shield_wall")
	assert_lt(walled, open_order,
		("the wall pays in blood saved: %d casualties against %d in line")
			% [walled, open_order])


func test_a_testudo_shrugs_arrows() -> void:
	var in_line := _arrow_casualties("line")
	var in_testudo := _arrow_casualties("testudo")
	assert_lt(in_testudo, in_line,
		("missile_taken is real: %d casualties under arrows against %d")
			% [in_testudo, in_line])


func _arrow_casualties(shape: String) -> int:
	var sim := _sim()
	sim.add_squad(_fighter(true), 1, Vector2i(8, 8))
	var defender_def := _fighter()
	defender_def.damage = 0.0
	var defender := sim.add_squad(defender_def, 2, Vector2i(11, 8))
	sim.set_shape(defender, shape)
	var before := sim.alive_of(defender)
	for _t in range(8):
		sim.tick()
	return before - sim.alive_of(defender)


func test_protection_costs_pace() -> void:
	var marching := _arrival_ticks("line")
	var crawling := _arrival_ticks("testudo")
	assert_gt(crawling, marching,
		("a testudo crawls: %d ticks against %d — or the strongest wall "
		+ "is simply the best button") % [crawling, marching])


func _arrival_ticks(shape: String) -> int:
	var sim := _sim()
	var squad := sim.add_squad(_fighter(), 1, Vector2i(4, 8))
	sim.set_shape(squad, shape)
	sim.order_move(squad, Vector2i(24, 8))
	for t in range(900):
		sim.tick()
		if sim.cell_of(squad) == Vector2i(24, 8):
			return t
	return 900


func test_granted_formations_exist_and_are_not_globally_offered() -> void:
	# EVERY non-offered formation, not just the one this test used to
	# name (#309). It asked about `shield_wall` alone, so when the roster
	# rewrite (af9c3f4, #191) replaced all 43 unit files and carried no
	# `formations` grant across, `testudo` became unreachable in the
	# shipped game with nothing going red — and `shield_wall` only went
	# red because this test happened to name it.
	#
	# That is D-106's caveat in its most literal form: a caller-exists
	# test only covers the caller it names. A formation that is not
	# offered and not granted is a `.tres` file no player can reach, which
	# is the D-055 family in its data half.
	var ungranted := PackedStringArray()
	var checked := 0
	for formation in FormationRoster.load_all():
		if formation.offered:
			continue
		checked += 1
		var grants := 0
		for def in UnitRoster.load_all():
			if def.formations.has(formation.id):
				grants += 1
		if grants == 0:
			ungranted.append(String(formation.id))
	assert_gt(checked, 0,
		"no shipped formation is granted-only, so this check is vacuous — "
		+ "either they all became offered or the roster stopped loading")
	assert_eq(ungranted.size(), 0,
		"granted-only formation(s) that no shipped unit knows, so no player can ever order them: %s"
			% ", ".join(ungranted))


func test_a_granted_formation_reaches_a_real_squad() -> void:
	# The other half, and the one a data scan cannot see: a grant is only
	# worth something if the unit holding it is one a player can field.
	# Asserted through the ROSTER rather than a list of ids, so a future
	# regrant is covered.
	for formation in FormationRoster.load_all():
		if formation.offered:
			continue
		var civs := {}
		for def in UnitRoster.load_all():
			if def.formations.has(formation.id):
				civs[def.civ] = true
		assert_gt(civs.size(), 0,
			"%s is granted to nobody" % formation.id)
