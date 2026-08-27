extends SceneTree

## OBSERVATION HARNESS for playtest ticket #39 (siege).
##
## D-067's headline rule ("one squad cannot raze a defended building, two
## can") is ALREADY guarded by tests/test_buildings.gd against the fantasy
## roster, so this does not re-litigate it. It observes the parts of #39
## that no standing test covers:
##
##   * what defensive fire actually COSTS a squad standing in range
##     (#39 step 4 / D-066's "not the old 4-men-per-engagement joke");
##   * whether a building's health_fraction moves LIVE on the wire path
##     (#39 step 5 — the regression where it was stuck at 1.0 because
##     damage never marked the building dirty);
##   * whether the SECOND squad finds a fighting position in reach
##     (#39's unsorted-disk_offsets regression);
##   * what a tower upgrade costs and changes (#39 step 6);
##   * whether razing everything triggers elimination (#39 step 7).
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_siege.gd

const TICK := 1.0 / 10.0


func _initialize() -> void:
	print("OBS39: begin")
	_defensive_fire_price()
	_health_fraction_is_live()
	_second_squad_is_in_reach()
	_upgrade_paths()
	_elimination_on_razing()
	print("OBS39: end")
	quit()


func _world() -> Dictionary:
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	sim.combat_seed = 5
	return {"space": space, "sim": sim, "buildings": buildings}


# --- 1. what standing in range costs ----------------------------------

func _defensive_fire_price() -> void:
	print("")
	print("OBS39 DEFENSIVE FIRE - a squad parked in range, not attacking back.")
	print("  D-066's finding was that a town centre cost a squad 4 men out of")
	print("  36 over a whole engagement. These are the numbers as they now")
	print("  ship: men lost per 30s of standing in reach.")
	for building_id in [&"town_centre", &"tower"]:
		var bdef := BuildingSim.def_by_id(building_id)
		if bdef == null:
			continue
		for unit_id in [&"emberdeep_levy", &"gildedreach_levy", &"stoneblood_heavy",
				&"windmarch_skirmishers"]:
			var unit := UnitRoster.by_id(unit_id)
			if unit == null:
				continue
			var w := _world()
			var sim: SquadSim = w["sim"]
			var buildings: BuildingSim = w["buildings"]
			buildings.add_building(bdef, 1, Vector2i(20, 20), true)
			# Adjacent to the building, held there with a plain move so it
			# is being shot at rather than trading.
			var squad := sim.add_squad(unit, 2, Vector2i(22, 20))
			var start := sim.alive_of(squad)
			var at30 := -1
			var at60 := -1
			var routed_at := -1.0
			var t := 0.0
			while t < 60.0:
				sim.tick()
				t += TICK
				if routed_at < 0.0 and sim.is_routed(squad):
					routed_at = t
				if at30 < 0 and t >= 30.0:
					at30 = sim.alive_of(squad)
				if sim.alive_of(squad) <= 0:
					break
			at60 = sim.alive_of(squad)
			print("  %-12s shooting %-22s: %d men -> %d at 30s -> %d at 60s (lost %d/%d = %.0f%%), routed %s"
				% [building_id, unit_id, start, at30, at60, start - at60, start,
				   100.0 * float(start - at60) / maxf(1.0, float(start)),
				   ("at %.1fs" % routed_at) if routed_at > 0 else "no"])


# --- 2. health_fraction on the wire path ------------------------------

func _health_fraction_is_live() -> void:
	print("")
	print("OBS39 HEALTH UI - does a besieged building report falling health?")
	print("  Read through BuildingSim.info_entries() / take_dirty(), which")
	print("  is the path the wire and the HUD panel use - NOT health_of(),")
	print("  which would pass even with the D-061 dirty-flag bug present.")
	var w := _world()
	var sim: SquadSim = w["sim"]
	var buildings: BuildingSim = w["buildings"]
	var bdef := BuildingSim.def_by_id(&"town_centre")
	var target := buildings.add_building(bdef, 1, Vector2i(20, 20), true)
	var unit := UnitRoster.by_id(&"stoneblood_heavy")
	for i in range(2):
		var s := sim.add_squad(unit, 2, Vector2i(26, 20 + i * 2))
		sim.order_attack_move(s, Vector2i(21, 20))
	buildings.take_dirty()  # drain the construction-time dirt first

	var fractions := []
	var dirty_ticks := 0
	var t := 0.0
	while t < 200.0:
		sim.tick()
		t += TICK
		var dirty := buildings.take_dirty()
		if not dirty.is_empty():
			dirty_ticks += 1
		var info := buildings.info_entries([target])
		if not info.is_empty():
			var e = info[0]
			var frac := -1.0
			if e is Dictionary and e.has("health_fraction"):
				frac = float(e["health_fraction"])
			elif e is Dictionary and e.has("health"):
				frac = float(e["health"]) / maxf(1.0, bdef.max_health)
			if frac >= 0.0 and (fractions.is_empty() or absf(float(fractions[-1]) - frac) > 0.01):
				fractions.append(snappedf(frac, 0.01))
		if buildings.is_destroyed(target):
			break
	print("  town centre health_fraction over the siege (distinct steps): %s" % [fractions])
	print("  ticks on which the building was marked dirty: %d over %.1fs; destroyed=%s"
		% [dirty_ticks, t, buildings.is_destroyed(target)])
	if fractions.size() <= 1:
		print("  >>> SUSPECT: health_fraction never moved. That is the D-061 regression.")


# --- 3. the second squad must be in reach -----------------------------

func _second_squad_is_in_reach() -> void:
	print("")
	print("OBS39 SECOND SQUAD - both besiegers must be fighting, not shoved off.")
	print("  The regression (unsorted TorusSpace.disk_offsets) parked the")
	print("  second squad outside its own reach: two squads then dealt barely")
	print("  more damage than one. Measured as damage dealt, 1 squad vs 2.")
	for unit_id in [&"emberdeep_levy", &"stoneblood_heavy", &"gildedreach_spearmen"]:
		var one := _siege_damage(unit_id, 1)
		var two := _siege_damage(unit_id, 2)
		var ratio := float(two["damage"]) / maxf(1.0, float(one["damage"]))
		var verdict := "ok" if ratio >= 1.6 else "SUSPECT - second squad barely contributing"
		print("  %-22s 1 squad dealt %.0f, 2 squads dealt %.0f (x%.2f) %s | both engaged: %s"
			% [unit_id, one["damage"], two["damage"], ratio, verdict, two["all_engaged"]])


func _siege_damage(unit_id: StringName, squad_count: int) -> Dictionary:
	var w := _world()
	var sim: SquadSim = w["sim"]
	var buildings: BuildingSim = w["buildings"]
	var bdef := BuildingSim.def_by_id(&"town_centre")
	var target := buildings.add_building(bdef, 1, Vector2i(20, 20), true)
	var unit := UnitRoster.by_id(unit_id)
	var squads := []
	for i in range(squad_count):
		var s := sim.add_squad(unit, 2, Vector2i(26, 20 + i * 2))
		sim.order_attack_move(s, Vector2i(21, 20))
		squads.append(s)
	# A fixed window, so "damage dealt" is comparable between 1 and 2.
	var all_engaged := false
	for i in range(600):
		sim.tick()
		if i > 300:
			var engaged := 0
			for s in squads:
				var d := sim.space.distance(sim.cell_of(s), Vector2i(20, 20))
				if d <= 2:
					engaged += 1
			if engaged == squads.size():
				all_engaged = true
		if buildings.is_destroyed(target):
			break
	var dealt: float = bdef.max_health - maxf(0.0, buildings.health_of(target))
	return {"damage": dealt, "all_engaged": all_engaged}


# --- 4. upgrades ------------------------------------------------------

func _upgrade_paths() -> void:
	print("")
	print("OBS39 UPGRADES - what upgrade_from actually ships (#39 step 6).")
	for d in BuildingSim.all_defs():
		if d.upgrade_from.is_empty():
			continue
		print("  %-16s upgrades from %s | cost f%d w%d g%d s%d | hp %.0f dmg %.1f range %.1f"
			% [d.id, d.upgrade_from, d.cost_food, d.cost_wood, d.cost_gold,
			   d.cost_stone, d.max_health, d.damage, d.attack_range])
	var towerish := []
	for d in BuildingSim.all_defs():
		if d.damage > 0.0 or d.is_access_tower or String(d.id).contains("tower"):
			towerish.append("%s(hp %.0f dmg %.1f rng %.1f upg_from=%s)"
				% [d.id, d.max_health, d.damage, d.attack_range, d.upgrade_from])
	print("  tower-like buildings in the roster: %s" % [towerish])


# --- 5. elimination ---------------------------------------------------

func _elimination_on_razing() -> void:
	print("")
	print("OBS39 ELIMINATION - raze everything a player owns and check the rule.")
	print("  D-033: defeat is no living squads AND no living buildings.")
	var w := _world()
	var sim: SquadSim = w["sim"]
	var buildings: BuildingSim = w["buildings"]
	var bdef := BuildingSim.def_by_id(&"town_centre")
	var victim_building := buildings.add_building(bdef, 1, Vector2i(20, 20), true)
	var victim_def := UnitRoster.by_id(&"gildedreach_levy")
	var victim_squad := sim.add_squad(victim_def, 1, Vector2i(21, 21))
	var attacker := UnitRoster.by_id(&"stoneblood_heavy")
	for i in range(3):
		var s := sim.add_squad(attacker, 2, Vector2i(26, 20 + i * 2))
		sim.order_attack_move(s, Vector2i(21, 20))

	var squad_gone_at := -1.0
	var building_gone_at := -1.0
	var t := 0.0
	while t < 400.0:
		sim.tick()
		t += TICK
		if squad_gone_at < 0.0 and sim.living_squad_count(1) == 0:
			squad_gone_at = t
		if building_gone_at < 0.0 and buildings.living_building_count(1) == 0:
			building_gone_at = t
		if squad_gone_at > 0.0 and building_gone_at > 0.0:
			break
	print("  victim's last squad died %s; last building fell %s"
		% [("at %.1fs" % squad_gone_at) if squad_gone_at > 0 else "never (still alive)",
		   ("at %.1fs" % building_gone_at) if building_gone_at > 0 else "never (still standing)"])
	print("  living_squad_count(1)=%d living_building_count(1)=%d -> eliminated by D-033 = %s"
		% [sim.living_squad_count(1), buildings.living_building_count(1),
		   sim.living_squad_count(1) == 0 and buildings.living_building_count(1) == 0])
	print("  (note: the RULE is evaluated by MatchState on the server, not here;")
	print("   this only shows the two counts it reads both reach zero.)")
