extends SceneTree

## OBSERVATION HARNESS for playtest ticket #42 (match lifecycle).
##
## Drives the REAL `MatchState.update()` — the function the server calls
## every tick to decide elimination and victory — over a real `SquadSim`
## and `BuildingSim`. So the rule exercised here is the shipped rule, not
## a restatement of it.
##
## What it CANNOT see, and what stays with the owner: the victory and
## defeat SCREENS, the ESC menu's leave-to-lobby button, and whether a
## rematch looks clean on screen. Those are client.gd.
##
## Cross-reference only, never touched: #157 (building desync in the
## second match after returning to the lobby) is owned elsewhere.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_lifecycle.gd

const TICK := 1.0 / 10.0


func _initialize() -> void:
	print("OBS42: begin")
	_elimination_rule()
	_victory_and_standing()
	_lobby_round_trip()
	print("OBS42: end")
	quit()


func _world() -> Dictionary:
	var space := TorusSpace.new(40, 20, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	var m := MatchState.new()
	m.players_expected = 2
	m.add_player(1)
	m.add_player(2)
	m.phase = MatchState.Phase.RUNNING
	return {"space": space, "sim": sim, "buildings": buildings, "match": m}


# --- 1. the elimination rule, in each of its four states ---------------

func _elimination_rule() -> void:
	print("")
	print("OBS42 ELIMINATION - D-033: a player is out when they have NO living")
	print("  squads AND no living buildings. All four combinations, through")
	print("  the real MatchState.update().")
	var unit := UnitRoster.by_id(&"gildedreach_levy")
	var tc := BuildingSim.def_by_id(&"town_centre")
	for has_squad in [true, false]:
		for has_building in [true, false]:
			var w := _world()
			var sim: SquadSim = w["sim"]
			var buildings: BuildingSim = w["buildings"]
			var m: MatchState = w["match"]
			# Player 2 always keeps an army, so the match cannot end for
			# the wrong reason while player 1 is being examined.
			sim.add_squad(unit, 2, Vector2i(30, 10))
			buildings.add_building(tc, 2, Vector2i(32, 10), true)
			if has_squad:
				sim.add_squad(unit, 1, Vector2i(8, 10))
			if has_building:
				buildings.add_building(tc, 1, Vector2i(6, 10), true)
			m.update(sim, buildings)
			print("  squads=%-5s buildings=%-5s -> eliminated=%-5s standing=%s"
				% [has_squad, has_building, m.is_eliminated(1),
				   ["PLAYING", "ELIMINATED", "VICTOR"][m.standing_of(1)]])


# --- 2. victory ---------------------------------------------------------

func _victory_and_standing() -> void:
	print("")
	print("OBS42 VICTORY - one side razed to nothing; who is told what.")
	var w := _world()
	var sim: SquadSim = w["sim"]
	var buildings: BuildingSim = w["buildings"]
	var m: MatchState = w["match"]
	var tc := BuildingSim.def_by_id(&"town_centre")
	var victim_unit := UnitRoster.by_id(&"gildedreach_levy")
	var killer_unit := UnitRoster.by_id(&"stoneblood_heavy")

	var victim_b := buildings.add_building(tc, 1, Vector2i(20, 10), true)
	sim.add_squad(victim_unit, 1, Vector2i(21, 11))
	for i in range(3):
		var s := sim.add_squad(killer_unit, 2, Vector2i(26, 9 + i))
		sim.order_attack_move(s, Vector2i(21, 10))
	buildings.add_building(tc, 2, Vector2i(30, 10), true)

	var events := []
	var t := 0.0
	var finished_at := -1.0
	while t < 400.0:
		sim.tick()
		t += TICK
		var e := m.update(sim, buildings)
		for ev in e:
			events.append("%.1fs %s" % [t, ev])
		if m.phase == MatchState.Phase.FINISHED and finished_at < 0.0:
			finished_at = t
			break
	print("  events: %s" % [events])
	print("  finished at %s, winner=%d, phase=%s"
		% [("%.1fs" % finished_at) if finished_at > 0 else "never",
		   m.winner, ["LOBBY", "RUNNING", "FINISHED"][m.phase]])
	print("  standing: player1=%s player2=%s"
		% [["PLAYING", "ELIMINATED", "VICTOR"][m.standing_of(1)],
		   ["PLAYING", "ELIMINATED", "VICTOR"][m.standing_of(2)]])
	print("  victim building destroyed=%s, victim squads alive=%d"
		% [buildings.is_destroyed(victim_b), sim.living_squad_count(1)])
	print("  scoreboard: %s" % [m.scoreboard()])


# --- 3. back to the lobby and out again --------------------------------

func _lobby_round_trip() -> void:
	print("")
	print("OBS42 LOBBY ROUND TRIP - RUNNING -> FINISHED -> LOBBY -> RUNNING,")
	print("  through MatchState's own transitions.")
	var w := _world()
	var m: MatchState = w["match"]
	var sim: SquadSim = w["sim"]
	var buildings: BuildingSim = w["buildings"]
	print("  start phase=%s players=%d seats=%d admin=%d"
		% [["LOBBY", "RUNNING", "FINISHED"][m.phase], m.player_count(),
		   m.seats.size(), m.admin_player])
	var back := m.return_to_lobby()
	print("  return_to_lobby() -> %s, phase now %s, winner reset to %d"
		% [back, ["LOBBY", "RUNNING", "FINISHED"][m.phase], m.winner])
	var started := m.start_match()
	print("  start_match()     -> %s, phase now %s"
		% [started, ["LOBBY", "RUNNING", "FINISHED"][m.phase]])
	print("  is_running=%s, eliminated flags cleared: p1=%s p2=%s"
		% [m.is_running(), m.is_eliminated(1), m.is_eliminated(2)])
	print("")
	print("  NOTE: what a rematch does to the CLIENT's carried-over state is")
	print("  #157's territory (building desync in the second match, owned")
	print("  elsewhere). Deliberately not investigated here.")
