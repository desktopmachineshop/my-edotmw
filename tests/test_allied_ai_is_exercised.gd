extends GutTest

## Guards D-20260818-allied-ai-is-exercised-by-something (#119), and with
## it the half of #83 that the #83 fix did not close.
##
## #83 was an AI that read "not mine" as "hostile", so an allied AI parked
## its whole army on its teammate's town centre and milled there for the
## rest of the match. It shipped for a milestone. The reason nothing
## caught it is the subject of this file: **allied AI behaviour was
## exercised by nothing**. `just ai-ladder` is a free-for-all,
## `tests/test_ai_player.gd` seated its AI on team 0 — which D-050 says is
## not a team — and the `--lobby=0` path that every headless harness runs
## never handed `SquadSim.teams` over at all, so a teamed seat list would
## have produced a simulation in which nobody was anybody's ally.
##
## The three things that had to exist before a teamed match could be run
## at all, one test group each:
##
## 1. a door to teams with no lobby in it (`--ai-teams`, seated through
##    `MatchState.add_ai_player`)
## 2. the handover to the simulation on BOTH start paths
## 3. an instrument that says an AI marched on a friend, judged from the
##    ground rather than from the filter that chose the target
##
## The load-bearing observation is not in this file, because no unit test
## can make it: `just test-ai-teams` was run with the #83 fix reverted and
## FAILED, then run with it restored and passed. A harness never observed
## to catch the bug it was built for is not evidence of anything
## (CLAUDE.md). The decision entry records both runs.

const W := 48
const H := 24


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _civ() -> StringName:
	return CivRoster.ids()[0]


# --- 1. a door to teams that no lobby is sitting in -------------------
#
# `MatchState.set_team` is lobby-and-admin-only by design, and a headless
# run has no admin, so before #119 there was no way to seat a teamed AI
# from a command line at all. That is why the ladder was a free-for-all:
# not a choice, an absence.


func _match_for(expected: int) -> MatchState:
	var m := MatchState.new()
	m.players_expected = expected
	return m


func test_an_ai_seat_can_be_dealt_a_side_without_a_lobby() -> void:
	var m := _match_for(4)
	m.add_ai_player(1000, _civ(), 1)
	m.add_ai_player(1001, _civ(), 2)
	m.add_ai_player(1002, _civ(), 1)
	var started := m.add_ai_player(1003, _civ(), 2)

	assert_true(started, "Seating the last AI did not start the match")
	assert_eq(m.team_map(), {1000: 1, 1001: 2, 1002: 1, 1003: 2},
		"The sides the seats were dealt are not the sides the match reports")
	assert_true(m.are_allied(1000, 1002), "Two seats on side 1 are not allies")
	assert_false(m.are_allied(1000, 1001), "Two seats on opposite sides are allies")


func test_the_side_is_on_the_seat_before_the_match_starts() -> void:
	# The reason `team` is a parameter of seating rather than a `set_team`
	# call after it: seating the LAST seat is what starts the match, so a
	# side assigned a line later is assigned to a seat whose `team_map()`
	# has already gone to the simulation. This asserts the ordering
	# directly — the map is complete at the instant the start is reported.
	var m := _match_for(2)
	var seen := {}
	m.add_ai_player(1000, _civ(), 1)
	var started := m.add_ai_player(1001, _civ(), 2)
	if started:
		seen = m.team_map()

	assert_eq(seen, {1000: 1, 1001: 2},
		"The match started with a seat whose side had not been set yet")


func test_a_teamless_seat_is_unchanged() -> void:
	# Every ladder number recorded before #119 was measured on a
	# free-for-all, and the default has to keep producing exactly that or
	# none of them are comparable.
	var m := _match_for(2)
	m.add_ai_player(1000, _civ())
	m.add_ai_player(1001, _civ())
	assert_eq(m.team_map(), {1000: 0, 1001: 0}, "A seat dealt no side acquired one")
	assert_false(m.are_allied(1000, 1001),
		"Two seats on team 0 are allies — 0 is FREE-FOR-ALL (D-050)")


func test_a_team_of_survivors_ends_the_match() -> void:
	# The ladder's decided/draw reporting is only honest if a team win is a
	# win. `MatchState._check_victory` has said so since it was written and
	# nothing without a lobby could ever reach it, which is exactly the
	# shape of defect this file exists for.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var def := UnitRoster.first()
	var m := _match_for(3)
	m.add_ai_player(1000, _civ(), 1)
	m.add_ai_player(1001, _civ(), 1)
	m.add_ai_player(1002, _civ(), 2)
	sim.teams = m.team_map()

	var winners_a := sim.add_squad(def, 1000, Vector2i(4, 4))
	sim.add_squad(def, 1001, Vector2i(6, 4))
	var loser := sim.add_squad(def, 1002, Vector2i(20, 12))
	sim.tick()
	m.update(sim)
	assert_eq(int(m.phase), int(MatchState.Phase.RUNNING),
		"Setup: the match was over before anybody lost anything")

	sim.set_alive(loser, 0)
	m.update(sim)
	assert_eq(int(m.phase), int(MatchState.Phase.FINISHED),
		"Two allies left standing did not end the match — a 2v2 reads as a draw")
	assert_eq(m.winner, 1000, "The winner is not a member of the surviving side")
	assert_gt(sim.alive_of(winners_a), 0, "Setup: the winning side is dead too")


# --- 2. the handover to the simulation --------------------------------
#
# Teams reached `SquadSim.teams` in exactly ONE place — inside
# `_on_match_started`, the lobby path. `just ai-ladder`, `just test-load`
# and `just test-scenario` all run `--lobby=0` and go through
# `_note_match_started`, which did not. Dormant rather than broken, since
# nothing without a lobby had ever had a team to hand over; `--ai-teams`
# is precisely what stops it being dormant, and the failure it would
# otherwise have produced is worse than #83's — allies whose alliance the
# simulation never learns shoot each other, while every seat list and
# every client agrees they are friends.
#
# `server.gd` needs a socket and a scene tree, so this asserts the CALLER
# EXISTS by reading the source — the same instrument D-106 built for the
# same class of defect. It is not a proof that the handover works; the
# proof is `just test-ai-teams`, which plays a match and reads the
# simulation's own `SIM_TEAMS` marker back out of the log.


func _server_source() -> String:
	var handle := FileAccess.open("res://server.gd", FileAccess.READ)
	assert_true(handle != null, "server.gd could not be read")
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func _body_of(text: String, function_name: String) -> String:
	var start := text.find("func %s(" % function_name)
	assert_true(start >= 0, "server.gd has no %s()" % function_name)
	if start < 0:
		return ""
	var next := text.find("\nfunc ", start + 1)
	return text.substr(start, (next - start) if next > start else -1)


func test_both_ways_a_match_starts_hand_the_teams_over() -> void:
	var text := _server_source()
	for path in ["_on_match_started", "_note_match_started"]:
		assert_true(_body_of(text, path).contains("_hand_teams_to_sim("),
			"%s() does not hand the seats' teams to the simulation — a match "
			% path + "started this way has allies the sim has never heard of")


func test_the_handover_actually_assigns_the_simulations_teams() -> void:
	# So the test above cannot be satisfied by an empty function.
	assert_true(_body_of(_server_source(), "_hand_teams_to_sim").contains(
		"_sim.teams = _match.team_map()"),
		"_hand_teams_to_sim() does not assign _sim.teams")


func test_the_harness_that_plays_a_teamed_match_is_wired_up() -> void:
	# The recipe is the only thing in the estate that exercises an allied
	# AI, so its absence is the defect returning rather than a missing
	# convenience. Same reasoning as asserting the caller exists.
	var handle := FileAccess.open("res://justfile", FileAccess.READ)
	assert_true(handle != null, "the justfile could not be read")
	if handle == null:
		return
	var text := handle.get_as_text()
	handle.close()

	assert_true(text.contains("test-ai-teams MATCHES"),
		"`just test-ai-teams` is gone — allied AI behaviour is exercised by "
		+ "nothing again, which is the whole of #119")
	assert_true(text.contains("--ai-teams={{TEAMS}}"),
		"a harness recipe stopped passing --ai-teams, so its 'teamed' match is a "
		+ "free-for-all")
	assert_true(text.contains("ally_objectives"),
		"no recipe reads ally_objectives — the finding would go unreported")


# --- 3. the instrument --------------------------------------------------
#
# `ally_objectives` counts attack objectives that landed on a friend. It
# asks what STANDS on the ordered cell rather than re-running the filter
# that chose it: a check that re-ran `_hostile` would be green exactly
# whenever `_hostile` was green, which is the thing under test.


const ALLY := 1001
const FOE := 1002


func _teamed_ai() -> Dictionary:
	var space := _space()
	var spawns := [Vector2i(8, 8), Vector2i(14, 8), Vector2i(36, 8)]
	var spawn_indices := []
	for cell in spawns:
		spawn_indices.append(space.index(cell))

	var ai := AiPlayer.new(1000, _civ())
	var civ := String(ai.civ)
	var seats := [
		{"kind": "ai", "player": 1000, "civ": civ, "team": 1, "name": "AI 1000"},
		{"kind": "ai", "player": ALLY, "civ": civ, "team": 1, "name": "AI 1001"},
		{"kind": "ai", "player": FOE, "civ": civ, "team": 2, "name": "AI 1002"},
	]
	ai.state.handle_packet(NetProtocol.encode_lobby(0, seats, {}, 1))
	ai.state.handle_packet(NetProtocol.encode_welcome(1000, W, H, [], spawn_indices))
	assert_true(ai.state.are_allied(1000, ALLY),
		"Setup: the fixture's teams never reached the AI")
	return {"space": space, "ai": ai, "buildings": BuildingSim.new(space)}


func _tell_about_building(world: Dictionary, owner: int, cell: Vector2i) -> void:
	var buildings: BuildingSim = world["buildings"]
	var id := buildings.add_building(
		BuildingSim.def_by_id(&"town_centre"), owner, cell, true)
	var ai: AiPlayer = world["ai"]
	ai.state.handle_packet(NetProtocol.encode_building_info(
		buildings.info_entries([id])))


func test_a_teammates_town_is_a_friendly_place() -> void:
	var world := _teamed_ai()
	var ai: AiPlayer = world["ai"]
	_tell_about_building(world, ALLY, Vector2i(12, 8))
	assert_true(ai._allies_only_at(Vector2i(12, 8)),
		"An ally's town centre did not read as a friendly objective — the "
		+ "instrument cannot see #83 at all")


func test_its_own_town_is_a_friendly_place_too() -> void:
	# Marching an army onto your own base is the same mistake wearing a
	# different hat, and there is no reason to be able to tell them apart.
	var world := _teamed_ai()
	var ai: AiPlayer = world["ai"]
	_tell_about_building(world, 1000, Vector2i(8, 8))
	assert_true(ai._allies_only_at(Vector2i(8, 8)),
		"The AI's own town did not read as a friendly objective")


func test_an_enemy_town_is_not_a_friendly_place() -> void:
	# Without this the instrument could report every objective as an
	# offence and the harness would fail on a perfectly good AI.
	var world := _teamed_ai()
	var ai: AiPlayer = world["ai"]
	_tell_about_building(world, FOE, Vector2i(36, 8))
	assert_false(ai._allies_only_at(Vector2i(36, 8)),
		"An enemy's town read as a friendly objective")


func test_empty_ground_is_not_a_friendly_place() -> void:
	# The scouting fallback aims at spawn cells, most of which hold
	# nothing. Counting those would drown the signal.
	var world := _teamed_ai()
	var ai: AiPlayer = world["ai"]
	assert_false(ai._allies_only_at(Vector2i(20, 20)),
		"Bare ground read as a friendly objective")


func test_an_ally_standing_on_an_enemy_town_is_not_an_offence() -> void:
	# The "and nothing hostile" half. An ally fighting at the enemy's hall
	# is the AI's army arriving where it was supposed to, and reading that
	# as a friendly-fire objective would make the harness fail on success.
	var world := _teamed_ai()
	var ai: AiPlayer = world["ai"]
	var space: TorusSpace = world["space"]
	_tell_about_building(world, FOE, Vector2i(36, 8))

	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.add_squad(UnitRoster.first(), ALLY, Vector2i(36, 8))
	sim.tick()
	var visible := sim.visible_to(1000)
	ai.state.handle_packet(NetProtocol.encode_squad_info(
		sim.squad_info_entries(visible)))
	for packet in sim.replicator.collect_for_client(1000, sim.time, visible):
		ai.state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))
	ai.set_time(sim.time)

	assert_false(ai._allies_only_at(Vector2i(36, 8)),
		"An enemy hall with an ally standing on it counted as a friendly objective")


func test_the_ally_count_is_the_vacuity_guard_it_claims_to_be() -> void:
	# `ally_objectives=0` says nothing unless the AI had a teammate it
	# could actually have marched on. That is what `allies_seen` is for,
	# and it has to count an ALLY and not an enemy or itself.
	var world := _teamed_ai()
	var ai: AiPlayer = world["ai"]
	_tell_about_building(world, 1000, Vector2i(8, 8))
	_tell_about_building(world, FOE, Vector2i(36, 8))
	ai._record_stats()
	assert_eq(ai.peak_allies_seen, 0,
		"Its own base, or an enemy's, was counted as an ally in sight")

	_tell_about_building(world, ALLY, Vector2i(12, 8))
	ai._record_stats()
	assert_eq(ai.peak_allies_seen, 1,
		"…and a real teammate was then not counted, so the check above is vacuous")


func test_the_stats_line_carries_what_the_harness_reads() -> void:
	# The harness parses this line. A renamed field is a harness that
	# silently measures nothing — the ladder's own history.
	var world := _teamed_ai()
	var ai: AiPlayer = world["ai"]
	var line := ai.stats_line()
	for field in ["team=", "allies_seen=", "ally_objectives=", "attacks="]:
		assert_true(line.contains(field),
			"AI_STATS no longer carries %s, which `just test-ai-teams` gates on" % field)
	assert_true(line.contains("team=1"),
		"The AI does not report the side its own seat list puts it on")
