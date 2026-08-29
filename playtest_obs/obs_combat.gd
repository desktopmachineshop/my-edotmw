extends SceneTree

## OBSERVATION HARNESS for playtest ticket #38 (field combat).
##
## Not a fix and not a test: it stages fights through the SIMULATION'S OWN
## path (TorusSpace + SquadSim + Combat, the same objects server.gd wires
## up) and prints what happened, so the parts of #38 that are numbers
## rather than feel can be discharged without a human at a keyboard.
##
## What it deliberately cannot see: how a rout LOOKS, whether a counter is
## FELT on screen, whether casualties read as orderly. Those stay with the
## owner — see docs/playtests/38-bot-findings.md.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_combat.gd

const W := 40
const H := 20
const TICK := 1.0 / 10.0


func _initialize() -> void:
	print("OBS38: begin")
	_mirror_fairness()
	_counter_matrix()
	_rout_watch()
	_casualty_integrity()
	_big_engagement()
	print("OBS38: end")
	quit()


# --- world ------------------------------------------------------------

func _sim(seed_value: int) -> SquadSim:
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	sim.combat_seed = seed_value
	return sim


## One fight, on flat equal ground, both squads ordered into each other.
## `a_first` controls which squad gets id 0 — that is the lower-id
## advantage #38 asks about, and it can only be seen by swapping it.
func _fight(a_id: StringName, b_id: StringName, seed_value: int,
		a_first: bool, max_seconds: float = 180.0) -> Dictionary:
	var sim := _sim(seed_value)
	var da := UnitRoster.by_id(a_id)
	var db := UnitRoster.by_id(b_id)
	if da == null or db == null:
		return {"error": "missing def"}
	var cell_a := Vector2i(14, 10)
	var cell_b := Vector2i(20, 10)
	var sa := -1
	var sb := -1
	if a_first:
		sa = sim.add_squad(da, 1, cell_a)
		sb = sim.add_squad(db, 2, cell_b)
	else:
		sb = sim.add_squad(db, 2, cell_b)
		sa = sim.add_squad(da, 1, cell_a)
	var start_a := sim.alive_of(sa)
	var start_b := sim.alive_of(sb)
	sim.order_attack_move(sa, cell_b)
	sim.order_attack_move(sb, cell_a)

	var t := 0.0
	var routed_a_at := -1.0
	var routed_b_at := -1.0
	var first_blood := -1.0
	while t < max_seconds:
		sim.tick()
		t += TICK
		if first_blood < 0.0 and (sim.alive_of(sa) < start_a or sim.alive_of(sb) < start_b):
			first_blood = t
		if routed_a_at < 0.0 and sim.is_routed(sa):
			routed_a_at = t
		if routed_b_at < 0.0 and sim.is_routed(sb):
			routed_b_at = t
		if sim.alive_of(sa) <= 0 or sim.alive_of(sb) <= 0:
			break

	var alive_a := sim.alive_of(sa)
	var alive_b := sim.alive_of(sb)
	var winner := 0
	if alive_a > 0 and alive_b <= 0:
		winner = 1
	elif alive_b > 0 and alive_a <= 0:
		winner = 2
	return {
		"winner": winner,  # 0 = undecided at the cap
		"alive_a": alive_a, "alive_b": alive_b,
		"start_a": start_a, "start_b": start_b,
		"frac_a": float(alive_a) / maxf(1.0, float(start_a)),
		"frac_b": float(alive_b) / maxf(1.0, float(start_b)),
		"seconds": t,
		"first_blood": first_blood,
		"routed_a": routed_a_at, "routed_b": routed_b_at,
		"id_a": sa, "id_b": sb,
	}


# --- 1. mirror fairness ------------------------------------------------

func _mirror_fairness() -> void:
	print("")
	print("OBS38 MIRROR - identical squads, equal ground, both ordered in.")
	print("  Each seed is played TWICE: once with player 1's squad as id 0,")
	print("  once with player 2's. A systematic bias shows as a lopsided")
	print("  tally in either the owner column or the id column.")
	var picks: Array[StringName] = [
		&"emberdeep_levy", &"gildedreach_spearmen", &"thornwood_levy",
		&"stoneblood_heavy", &"windmarch_cavalry",
	]
	for who in picks:
		var p1 := 0
		var p2 := 0
		var undecided := 0
		var id0_wins := 0
		var id1_wins := 0
		var secs := 0.0
		var n := 0
		for s in range(1, 25):
			for a_first in [true, false]:
				var r := _fight(who, who, s, a_first)
				if r.has("error"):
					continue
				n += 1
				secs += r["seconds"]
				var w: int = r["winner"]
				if w == 0:
					undecided += 1
					continue
				if w == 1:
					p1 += 1
				else:
					p2 += 1
				var winner_squad: int = r["id_a"] if w == 1 else r["id_b"]
				if winner_squad == 0:
					id0_wins += 1
				else:
					id1_wins += 1
		print("  %-22s n=%d  owner p1=%d p2=%d undecided=%d | id0=%d id1=%d | mean %.1fs"
			% [who, n, p1, p2, undecided, id0_wins, id1_wins, secs / maxf(1.0, float(n))])


# --- 2. counter triangle ----------------------------------------------

func _counter_matrix() -> void:
	print("")
	print("OBS38 COUNTERS - every shipped bonus_vs pairing, played both ways.")
	print("  'margin' is A's surviving fraction minus B's, averaged over 12")
	print("  seeds; a counter that is FELT should win most seeds AND leave a")
	print("  wide margin, not squeak home.")
	var defs := UnitRoster.load_all()
	var pairs := []
	for a in defs:
		if a.bonus_vs.is_empty():
			continue
		for target_class in a.bonus_vs.keys():
			for b in defs:
				if b.armour_class != String(target_class):
					continue
				if b.is_general or b.gather_rate > 0.0:
					continue
				if b.civ == a.civ:
					continue
				pairs.append([a, b, float(a.bonus_vs[target_class])])
	var seen := {}
	var chosen := []
	for pr in pairs:
		var key := "%s/%s" % [pr[0].id, pr[1].armour_class]
		if seen.has(key):
			continue
		seen[key] = true
		chosen.append(pr)
	for pr in chosen:
		var a: UnitDef = pr[0]
		var b: UnitDef = pr[1]
		var mult: float = pr[2]
		var a_wins := 0
		var b_wins := 0
		var undecided := 0
		var margin := 0.0
		var n := 0
		for s in range(1, 13):
			var r := _fight(a.id, b.id, s, s % 2 == 0)
			if r.has("error"):
				continue
			n += 1
			margin += float(r["frac_a"]) - float(r["frac_b"])
			var w: int = r["winner"]
			if w == 1:
				a_wins += 1
			elif w == 2:
				b_wins += 1
			else:
				undecided += 1
		print("  %-22s (x%.2f vs %-8s) vs %-22s favoured=%d/%d other=%d undecided=%d margin=%+.2f"
			% [a.id, mult, b.armour_class, b.id, a_wins, n, b_wins, undecided,
			   margin / maxf(1.0, float(n))])


# --- 3. rout ----------------------------------------------------------

func _rout_watch() -> void:
	print("")
	print("OBS38 ROUT - an outmatched squad pushed until it breaks, then watched.")
	print("  A rout must (a) happen, (b) move the squad AWAY, (c) either")
	print("  rally or die. A squad that routs and then stands still is the")
	print("  bug this looks for.")
	for pair in [[&"stoneblood_heavy", &"gildedreach_levy"],
				 [&"emberdeep_heavy", &"thornwood_levy"]]:
		var sim := _sim(7)
		var strong := UnitRoster.by_id(pair[0])
		var weak := UnitRoster.by_id(pair[1])
		if strong == null or weak == null:
			continue
		var s_cell := Vector2i(14, 10)
		var w_cell := Vector2i(18, 10)
		var ss := sim.add_squad(strong, 1, s_cell)
		var ws := sim.add_squad(weak, 2, w_cell)
		sim.order_attack_move(ss, w_cell)
		sim.order_attack_move(ws, s_cell)
		var t := 0.0
		var rout_at := -1.0
		var rout_cell := Vector2i.ZERO
		var moved_after := 0
		var rallied_at := -1.0
		var died_at := -1.0
		var morale_at_rout := -1.0
		while t < 180.0:
			sim.tick()
			t += TICK
			if rout_at < 0.0 and sim.is_routed(ws):
				rout_at = t
				rout_cell = sim.cell_of(ws)
				morale_at_rout = sim.morale_of(ws)
			elif rout_at > 0.0:
				if sim.is_routed(ws):
					var d := sim.space.distance(rout_cell, sim.cell_of(ws))
					moved_after = maxi(moved_after, int(d))
				elif rallied_at < 0.0 and sim.alive_of(ws) > 0:
					rallied_at = t
			if sim.alive_of(ws) <= 0:
				died_at = t
				break
		print("  %-20s vs %-20s: routed %s (morale %.1f), fled %d cells, rallied %s, wiped %s, alive %d/%d"
			% [pair[0], pair[1],
			   ("at %.1fs" % rout_at) if rout_at > 0 else "never",
			   morale_at_rout, moved_after,
			   ("at %.1fs" % rallied_at) if rallied_at > 0 else "no",
			   ("at %.1fs" % died_at) if died_at > 0 else "no",
			   sim.alive_of(ws), weak.squad_size])


# --- 4. casualty integrity --------------------------------------------

func _casualty_integrity() -> void:
	print("")
	print("OBS38 CASUALTIES - every alive[] change over a whole fight.")
	print("  Checks D-024's integer-decrement rule and looks for an")
	print("  'immortal last man' (alive stuck at 1 while still in contact).")
	var sim := _sim(11)
	var a := UnitRoster.by_id(&"emberdeep_levy")
	var b := UnitRoster.by_id(&"gildedreach_spearmen")
	var sa := sim.add_squad(a, 1, Vector2i(14, 10))
	var sb := sim.add_squad(b, 2, Vector2i(18, 10))
	sim.order_attack_move(sa, Vector2i(18, 10))
	sim.order_attack_move(sb, Vector2i(14, 10))
	var prev_a := sim.alive_of(sa)
	var prev_b := sim.alive_of(sb)
	var steps_a := []
	var steps_b := []
	var increases := 0
	var t := 0.0
	var stuck_at_one := 0.0
	while t < 180.0:
		sim.tick()
		t += TICK
		var na := sim.alive_of(sa)
		var nb := sim.alive_of(sb)
		if na != prev_a:
			if na > prev_a:
				increases += 1
			else:
				steps_a.append(prev_a - na)
			prev_a = na
		if nb != prev_b:
			if nb > prev_b:
				increases += 1
			else:
				steps_b.append(prev_b - nb)
			prev_b = nb
		if na == 1 or nb == 1:
			stuck_at_one += TICK
		if na <= 0 or nb <= 0:
			break
	print("  fight ran %.1fs; A %d->%d in %d decrements, B %d->%d in %d decrements"
		% [t, a.squad_size, prev_a, steps_a.size(), b.squad_size, prev_b, steps_b.size()])
	print("  decrement sizes A=%s" % [steps_a])
	print("  decrement sizes B=%s" % [steps_b])
	print("  alive INCREASED %d times (must be 0); time with a lone survivor still fighting: %.1fs"
		% [increases, stuck_at_one])


# --- 5. big engagement ------------------------------------------------

func _big_engagement() -> void:
	print("")
	print("OBS38 BIG ENGAGEMENT - 6 squads a side, mixed arms, attack-move in.")
	var sim := _sim(3)
	var left: Array[StringName] = [&"emberdeep_levy", &"emberdeep_levy", &"emberdeep_heavy",
		&"emberdeep_archers", &"emberdeep_archers", &"emberdeep_general"]
	var right: Array[StringName] = [&"gildedreach_levy", &"gildedreach_spearmen",
		&"gildedreach_sellswords", &"gildedreach_archers", &"gildedreach_cavalry",
		&"gildedreach_general"]
	var l_ids := []
	var r_ids := []
	for i in range(left.size()):
		var d := UnitRoster.by_id(left[i])
		if d != null:
			l_ids.append(sim.add_squad(d, 1, Vector2i(12, 8 + i)))
	for i in range(right.size()):
		var d := UnitRoster.by_id(right[i])
		if d != null:
			r_ids.append(sim.add_squad(d, 2, Vector2i(24, 8 + i)))
	var l_start := 0
	var r_start := 0
	for s in l_ids:
		l_start += sim.alive_of(s)
	for s in r_ids:
		r_start += sim.alive_of(s)
	for s in l_ids:
		sim.order_attack_move(s, Vector2i(24, 10))
	for s in r_ids:
		sim.order_attack_move(s, Vector2i(12, 10))
	var t := 0.0
	var routs := 0
	var was_routed := {}
	while t < 240.0:
		sim.tick()
		t += TICK
		for s in l_ids + r_ids:
			var r := sim.is_routed(s)
			if r and not was_routed.get(s, false):
				routs += 1
			was_routed[s] = r
		var la := 0
		var ra := 0
		for s in l_ids:
			la += sim.alive_of(s)
		for s in r_ids:
			ra += sim.alive_of(s)
		if la <= 0 or ra <= 0:
			break
	var la := 0
	var ra := 0
	var l_live := 0
	var r_live := 0
	for s in l_ids:
		la += sim.alive_of(s)
		if sim.alive_of(s) > 0:
			l_live += 1
	for s in r_ids:
		ra += sim.alive_of(s)
		if sim.alive_of(s) > 0:
			r_live += 1
	print("  %.1fs: emberdeep %d/%d men in %d/%d squads | gildedreach %d/%d men in %d/%d squads | %d rout events"
		% [t, la, l_start, l_live, l_ids.size(), ra, r_start, r_live, r_ids.size(), routs])
	print("  per-squad cost this run: %.1f us/squad-update over %d ticks"
		% [sim.mean_usec_per_squad_update(), sim.tick_count])
