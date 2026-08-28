extends SceneTree

## Diagnostic for one thing obs_lifecycle.gd and obs_siege.gd both hit:
## three squads sent at a town centre that ALSO has a defending squad did
## not raze it in 400 s, while tests/test_buildings.gd asserts that TWO
## squads of any line troop take an UNDEFENDED-by-troops town centre.
##
## Written to tell a fixture mistake from a real finding, by printing what
## every participant is doing rather than only the outcome.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_siege_diag.gd

const TICK := 1.0 / 10.0


func _initialize() -> void:
	print("OBS-SIEGE-DIAG: begin")
	for defenders in [0, 1]:
		for attackers in [2, 3]:
			_run(&"stoneblood_heavy", attackers, defenders)
	_run(&"emberdeep_levy", 2, 0)
	_run(&"emberdeep_levy", 2, 1)
	print("  --- control: the same defender placed BEHIND the building,")
	print("      off the attackers' approach, to separate 'a screen denies")
	print("      the building' from 'the defence is simply stronger'.")
	_run(&"stoneblood_heavy", 2, 1, true)
	_run(&"emberdeep_levy", 2, 1, true)
	print("OBS-SIEGE-DIAG: end")
	quit()


func _run(attacker_id: StringName, attacker_squads: int, defender_squads: int,
		defender_behind: bool = false) -> void:
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	sim.combat_seed = 5

	var tc := BuildingSim.def_by_id(&"town_centre")
	var target := buildings.add_building(tc, 1, Vector2i(20, 20), true)
	var defender_unit := UnitRoster.by_id(&"gildedreach_levy")
	var defs := []
	for i in range(defender_squads):
		# In front of the building on the attackers' approach (the default),
		# or behind it on the far side (the control).
		var where := Vector2i(21, 21 + i) if not defender_behind 			else Vector2i(14, 20 + i)
		defs.append(sim.add_squad(defender_unit, 1, where))

	var unit := UnitRoster.by_id(attacker_id)
	var atk := []
	var started := 0
	# Same geometry as tests/test_buildings.gd's _rush_cost.
	for i in range(attacker_squads):
		var s := sim.add_squad(unit, 2, Vector2i(26, 20 + i * 2))
		sim.order_attack_move(s, Vector2i(21, 20))
		atk.append(s)
		started += sim.alive_of(s)

	var razed_at := -1.0
	var t := 0.0
	var closest_ever := 99
	while t < 400.0:
		sim.tick()
		t += TICK
		for s in atk:
			if sim.alive_of(s) > 0:
				closest_ever = mini(closest_ever,
					sim.space.distance(sim.cell_of(s), Vector2i(20, 20)))
		if buildings.is_destroyed(target):
			razed_at = t
			break
		var alive := 0
		for s in atk:
			alive += sim.alive_of(s)
		if alive <= 0:
			break

	var left := 0
	var in_reach := 0
	for s in atk:
		left += sim.alive_of(s)
		if sim.alive_of(s) > 0 \
				and sim.space.distance(sim.cell_of(s), Vector2i(20, 20)) <= 2:
			in_reach += 1
	var def_left := 0
	for s in defs:
		def_left += sim.alive_of(s)
	print("  %-20s x%d vs town centre + %d defender squad(s)%s: razed=%-5s at %-8s "
			% [attacker_id, attacker_squads, defender_squads,
			   " BEHIND" if defender_behind else "       ",
			   razed_at > 0, ("%.1fs" % razed_at) if razed_at > 0 else "-"]
		+ "building %.0f/%.0f hp | attackers %d/%d left, %d of %d in reach, closest ever %d cells | defenders %d left"
			% [maxf(0.0, buildings.health_of(target)), tc.max_health, left, started,
			   in_reach, atk.size(), closest_ever, def_left])
