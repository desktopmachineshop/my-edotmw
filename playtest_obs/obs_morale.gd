extends SceneTree

## OBSERVATION HARNESS for playtest #38/#39: does morale read BUILDING fire?
##
## obs_siege.gd found that a squad shot to death by a town centre or a
## tower never routs — `routed no` in 8 of 8 runs, including squads wiped
## to the last man. `Combat._shoot_squad` explicitly calls `_break_squad`
## and carries a comment saying a fortification breaks a squad "the same
## way being beaten by another squad does", so the mechanism is there.
##
## This measures whether the shipped NUMBERS can ever reach it, by tracing
## morale second by second. `Combat._recover_morale_and_check_rally`
## restores `morale_recovery_per_second` every tick UNCONDITIONALLY —
## there is no "under fire" suppression — so the question is simply
## whether a building's casualty RATE times `morale_loss_per_casualty`
## beats that recovery.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_morale.gd

const TICK := 1.0 / 10.0


func _initialize() -> void:
	print("OBS-MORALE: begin")
	_arithmetic()
	_traces()
	_melee_control()
	print("OBS-MORALE: end")
	quit()


## The rate question, before any simulation: how fast does a building kill,
## and what is that worth in morale per second against recovery?
func _arithmetic() -> void:
	print("")
	print("MORALE ARITHMETIC - morale lost per second under building fire")
	print("  vs morale recovered per second. Recovery is unconditional")
	print("  (Combat._recover_morale_and_check_rally), so a negative net")
	print("  means the squad can never be broken by that building at all.")
	print("  %-14s %-24s %8s %8s %8s %8s %9s"
		% ["building", "unit", "kills/s", "loss/s", "recov/s", "net/s", "canrout"])
	for bid in [&"town_centre", &"tower"]:
		var b := BuildingSim.def_by_id(bid)
		if b == null:
			continue
		for uid in [&"emberdeep_levy", &"gildedreach_levy", &"stoneblood_heavy",
				&"windmarch_skirmishers", &"thornwood_levy", &"gravesworn_levy"]:
			var u := UnitRoster.by_id(uid)
			if u == null:
				continue
			# One shot every attack_interval, each doing `damage` to a pool
			# where one man is `health`.
			var kills_per_second := (b.damage / maxf(0.001, u.health)) \
				/ maxf(0.001, b.attack_interval)
			var loss := kills_per_second * u.morale_loss_per_casualty
			var recov := u.morale_recovery_per_second
			var net := loss - recov
			print("  %-14s %-24s %8.3f %8.3f %8.3f %+8.3f %9s"
				% [bid, uid, kills_per_second, loss, recov, -net,
				   "yes" if net > 0.0 else "NO"])


func _traces() -> void:
	print("")
	print("MORALE TRACE - a squad parked in a building's reach, morale each 10s.")
	print("  (rout_threshold is %s by default; a squad that dies at morale"
		% UnitDef.new().rout_threshold)
	print("  100 died without its men ever wavering.)")
	for bid in [&"town_centre", &"tower"]:
		for uid in [&"emberdeep_levy", &"gildedreach_levy", &"thornwood_levy"]:
			var b := BuildingSim.def_by_id(bid)
			var u := UnitRoster.by_id(uid)
			if b == null or u == null:
				continue
			var space := TorusSpace.new(42, 48, 1.0)
			var sim := SquadSim.new(space, CurveReplicator.new())
			var buildings := BuildingSim.new(space)
			sim.buildings = buildings
			var p := PackedByteArray()
			p.resize(space.cell_count())
			p.fill(1)
			sim.set_passable(p)
			sim.combat_seed = 5
			buildings.add_building(b, 1, Vector2i(20, 20), true)
			var squad := sim.add_squad(u, 2, Vector2i(22, 20))
			var trace := []
			var min_morale := 999.0
			var routed := false
			var t := 0.0
			while t < 90.0:
				sim.tick()
				t += TICK
				min_morale = minf(min_morale, sim.morale_of(squad))
				if sim.is_routed(squad):
					routed = true
				if int(round(t * 10.0)) % 100 == 0:
					trace.append("%.0fs:%d/%d men m=%.0f"
						% [t, sim.alive_of(squad), u.squad_size, sim.morale_of(squad)])
				if sim.alive_of(squad) <= 0:
					break
			print("  %-12s vs %-22s %s"
				% [bid, uid, " | ".join(trace)])
			print("      -> died at %.1fs, lowest morale seen %.1f (threshold %.0f), ever routed: %s"
				% [t, min_morale, u.rout_threshold, routed])


func _melee_control() -> void:
	print("")
	print("MELEE CONTROL - the same squads beaten by another SQUAD instead.")
	print("  This is the comparison that shows the mechanism works and only")
	print("  the building path cannot reach it.")
	for uid in [&"emberdeep_levy", &"gildedreach_levy", &"thornwood_levy"]:
		var u := UnitRoster.by_id(uid)
		var killer := UnitRoster.by_id(&"stoneblood_heavy")
		if u == null or killer == null:
			continue
		var space := TorusSpace.new(42, 48, 1.0)
		var sim := SquadSim.new(space, CurveReplicator.new())
		var p := PackedByteArray()
		p.resize(space.cell_count())
		p.fill(1)
		sim.set_passable(p)
		sim.combat_seed = 5
		var a := sim.add_squad(killer, 1, Vector2i(20, 20))
		var d := sim.add_squad(u, 2, Vector2i(22, 20))
		sim.order_attack_move(a, Vector2i(22, 20))
		var routed_at := -1.0
		var min_morale := 999.0
		var t := 0.0
		while t < 90.0:
			sim.tick()
			t += TICK
			min_morale = minf(min_morale, sim.morale_of(d))
			if routed_at < 0.0 and sim.is_routed(d):
				routed_at = t
			if sim.alive_of(d) <= 0:
				break
		print("  %-22s beaten by stoneblood_heavy: routed %s, lowest morale %.1f"
			% [uid, ("at %.1fs" % routed_at) if routed_at > 0 else "NEVER", min_morale])
