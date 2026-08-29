extends SceneTree

## OBSERVATION HARNESS for playtest ticket #38, counter half.
##
## obs_combat.gd found one shipped bonus_vs pairing that loses 0/12 to the
## unit it is supposed to counter. This widens that into the full
## missile-vs-infantry matrix and prints D-072's power/cost figures beside
## it, so "the counter is not felt" can be stated as a number rather than
## an impression.
##
## Two views, because they answer different questions:
##   * SQUAD FOR SQUAD  - what the player sees when two squads meet.
##   * PER RESOURCE POINT - D-072's RP = food + wood + 1.5*(gold + stone),
##     which is what a match actually spends. A counter can be real at
##     equal cost and invisible squad-for-squad, or the reverse.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_counters.gd

const TICK := 1.0 / 10.0


func _initialize() -> void:
	print("OBS38C: begin")
	_power_table()
	_matrix()
	print("OBS38C: end")
	quit()


func _rp(d: UnitDef) -> float:
	return float(d.cost_food + d.cost_wood) + 1.5 * float(d.cost_gold + d.cost_stone)


func _squad_dps(d: UnitDef) -> float:
	return float(d.squad_size) * d.damage / maxf(0.01, d.attack_interval)


func _squad_hp(d: UnitDef) -> float:
	return float(d.squad_size) * d.health


func _combat_units() -> Array:
	var out := []
	for d in UnitRoster.load_all():
		if d.is_general or d.gather_rate > 0.0:
			continue
		out.append(d)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out


func _power_table() -> void:
	print("")
	print("OBS38C POWER - D-072's V = sqrt(DPS x EHP) against RP, per squad.")
	print("  %-24s %-9s %5s %8s %8s %8s %7s %7s"
		% ["unit", "class", "size", "sqDPS", "sqHP", "V", "RP", "V/RP"])
	for d in _combat_units():
		var dps := _squad_dps(d)
		var hp := _squad_hp(d)
		var v := sqrt(dps * hp)
		var rp := _rp(d)
		print("  %-24s %-9s %5d %8.1f %8.0f %8.1f %7.1f %7.2f"
			% [d.id, d.armour_class, d.squad_size, dps, hp, v, rp,
			   v / maxf(1.0, rp)])


func _fight(da: UnitDef, db: UnitDef, n_a: int, n_b: int, seed_value: int) -> Dictionary:
	var space := TorusSpace.new(48, 24, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	sim.combat_seed = seed_value

	var a_ids := []
	var b_ids := []
	# Alternate which side is added first so squad id cannot confer an
	# advantage across the sweep (obs_combat.gd measured that it does not,
	# but a matrix that assumed it would be assuming the thing it tests).
	if seed_value % 2 == 0:
		for i in range(n_a):
			a_ids.append(sim.add_squad(da, 1, Vector2i(16, 10 + i * 2)))
		for i in range(n_b):
			b_ids.append(sim.add_squad(db, 2, Vector2i(30, 10 + i * 2)))
	else:
		for i in range(n_b):
			b_ids.append(sim.add_squad(db, 2, Vector2i(30, 10 + i * 2)))
		for i in range(n_a):
			a_ids.append(sim.add_squad(da, 1, Vector2i(16, 10 + i * 2)))
	# Each side is ordered at the OTHER SIDE'S OWN starting cell, never at
	# a point beyond it. Ordering them past each other let two squads
	# cross, separate and walk to opposite corners: the run then reported
	# a huge attrition margin with neither side wiped, which reads exactly
	# like "fights do not resolve" and is entirely the fixture. Same
	# geometry as obs_combat.gd, which decides cleanly.
	var a_front := Vector2i(16, 10)
	var b_front := Vector2i(30, 10)
	var start_a := 0
	var start_b := 0
	for s in a_ids:
		start_a += sim.alive_of(s)
		sim.order_attack_move(s, b_front)
	for s in b_ids:
		start_b += sim.alive_of(s)
		sim.order_attack_move(s, a_front)

	var t := 0.0
	while t < 300.0:
		sim.tick()
		t += TICK
		var la := 0
		var lb := 0
		for s in a_ids:
			la += sim.alive_of(s)
		for s in b_ids:
			lb += sim.alive_of(s)
		if la <= 0 or lb <= 0:
			break
	var la := 0
	var lb := 0
	for s in a_ids:
		la += sim.alive_of(s)
	for s in b_ids:
		lb += sim.alive_of(s)
	var winner := 0
	if la > 0 and lb <= 0:
		winner = 1
	elif lb > 0 and la <= 0:
		winner = 2
	# How far apart the survivors ended. An undecided fight in which the
	# two sides are still adjacent is a genuine stalemate; one in which
	# they are ten cells apart is a fixture that let them walk away, and
	# the two must not be reported as the same thing.
	var gap := 999.0
	for sa in a_ids:
		if sim.alive_of(sa) <= 0:
			continue
		for sb in b_ids:
			if sim.alive_of(sb) <= 0:
				continue
			gap = minf(gap, float(sim.space.distance(sim.cell_of(sa), sim.cell_of(sb))))
	return {
		"winner": winner,
		"frac_a": float(la) / maxf(1.0, float(start_a)),
		"frac_b": float(lb) / maxf(1.0, float(start_b)),
		"seconds": t,
		"gap": gap,
	}


func _series(da: UnitDef, db: UnitDef, n_a: int, n_b: int, seeds: int) -> Dictionary:
	var a_wins := 0
	var b_wins := 0
	var undecided := 0
	var margin := 0.0
	var gap := 0.0
	var gaps := 0
	for s in range(1, seeds + 1):
		var r := _fight(da, db, n_a, n_b, s)
		margin += float(r["frac_a"]) - float(r["frac_b"])
		var w: int = r["winner"]
		if w == 1:
			a_wins += 1
		elif w == 2:
			b_wins += 1
		else:
			undecided += 1
			gap += float(r["gap"])
			gaps += 1
	return {"a": a_wins, "b": b_wins, "u": undecided,
		"margin": margin / float(seeds),
		"gap": gap / maxf(1.0, float(gaps))}


func _matrix() -> void:
	print("")
	print("OBS38C MATRIX - every MISSILE unit that claims a bonus against")
	print("  INFANTRY, against every infantry unit of another civ.")
	print("  'sq' = 1 squad each. 'rp' = squad counts chosen so both sides")
	print("  spend within ~15%% of the same RP (capped at 3 squads a side).")
	var units := _combat_units()
	var shooters := []
	for d in units:
		if d.bonus_vs.has("infantry"):
			shooters.append(d)
	var infantry := []
	for d in units:
		if d.armour_class == "infantry":
			infantry.append(d)
	for a in shooters:
		var mult := float(a.bonus_vs["infantry"])
		print("")
		print("  --- %s (x%.2f vs infantry, RP %.0f, V %.0f)"
			% [a.id, mult, _rp(a), sqrt(_squad_dps(a) * _squad_hp(a))])
		for b in infantry:
			if b.civ == a.civ:
				continue
			var sq := _series(a, b, 1, 1, 8)
			# Equal-RP counts, small integers only.
			var best_a := 1
			var best_b := 1
			var best_err := 1e9
			for na in range(1, 4):
				for nb in range(1, 4):
					var err: float = absf(float(na) * _rp(a) - float(nb) * _rp(b)) \
						/ maxf(1.0, float(nb) * _rp(b))
					if err < best_err:
						best_err = err
						best_a = na
						best_b = nb
			var rp_line := "n/a"
			if best_err <= 0.15:
				var rpr := _series(a, b, best_a, best_b, 6)
				rp_line = "%dv%d shooter=%d/%d margin=%+.2f" \
					% [best_a, best_b, rpr["a"], 6, rpr["margin"]]
			print("    vs %-24s sq shooter=%d/8 target=%d undec=%d(gap %.0f) margin=%+.2f | rp %s"
				% [b.id, sq["a"], sq["b"], sq["u"], sq["gap"], sq["margin"], rp_line])
