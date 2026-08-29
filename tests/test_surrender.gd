extends GutTest

## Guards D-20260828-a-player-may-concede (#279).
##
## Elimination was the only exit (D-033), so at D-056's 1-2 hour target a
## player who had lost had no honest way to stop and every playtest ran to
## the bitter end.
##
## The design claim these tests exist to hold is narrow and is the whole
## point: **surrender is a CAUSE of defeat, not a second definition of
## it.** It razes what a player owns and D-033's ordinary rule notices.
## Nothing downstream -- standing, the scoreboard, victory, the team
## clause, the log markers, the ladder -- learns a new concept, and the
## tests below check exactly that by asserting on the ORDINARY machinery
## rather than on anything surrender-shaped.
##
## Driven through `server._handle_surrender` itself rather than through a
## re-implementation of it. "server.gd needs a socket and a scene tree" is
## true of `_ready()`, not of the file (docs/status/civ-knobs.md), and a
## test that called `eliminate_player` directly would prove the wipe works
## while saying nothing about whether the command reaches it -- which is
## the gap that let a knob ship wired to nothing for a milestone.

const LEVY := &"gildedreach_levy"


## A running two-player match with a real server object behind it.
##
## The peer is a LoopbackPeer, which is the server's own stand-in for a
## socket (D-051) -- the same thing an AI client connects through.
func _world(team_a := 0, team_b := 0) -> Dictionary:
	var server = load("res://server.gd").new()
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var match_state := MatchState.new()
	match_state.players_expected = 2
	match_state.add_player(1)
	match_state.add_player(2)
	match_state.seats = [
		{"player": 1, "kind": "human", "civ": &"gildedreach", "team": team_a},
		{"player": 2, "kind": "human", "civ": &"gildedreach", "team": team_b},
	]
	match_state.phase = MatchState.Phase.RUNNING

	server._sim = sim
	server._buildings = buildings
	server._match = match_state

	# A real ClientState behind each peer, so the REFUSAL notices are
	# readable. A refused command must say why (D-034), and "the button
	# did nothing" is the interface defect family D-061 exists about --
	# asserting the silence is absent is worth more than asserting the
	# state is unchanged, because unchanged state is also what a dropped
	# packet looks like.
	var peers := {}
	for player in [1, 2]:
		var peer := LoopbackPeer.new(ClientState.new())
		server._clients[peer] = {"player": player}
		peers[player] = peer
	return {"server": server, "sim": sim, "buildings": buildings,
		"match": match_state, "peers": peers}


func _give(world: Dictionary, player: int, with_building := true) -> void:
	var sim: SquadSim = world["sim"]
	var buildings: BuildingSim = world["buildings"]
	sim.add_squad(UnitRoster.by_id(LEVY), player, Vector2i(10 * player, 10))
	if with_building:
		buildings.add_building(BuildingSim.def_by_id(&"town_centre"), player,
			Vector2i(10 * player, 13), true)


func _surrender(world: Dictionary, player: int) -> void:
	world["server"]._handle_surrender(world["peers"][player])


# --- the ordinary rule notices, and nothing new is invented ------------

func test_a_conceding_player_is_eliminated_by_the_ORDINARY_rule() -> void:
	# The load-bearing assertion. `MatchState.update` is D-033's rule and
	# knows nothing about surrender; if it eliminates the player, then
	# surrender added a cause and not a definition.
	var world := _world()
	_give(world, 1)
	_give(world, 2)
	var match_state: MatchState = world["match"]

	assert_false(match_state.is_eliminated(2), "setup: player 2 is in the match")
	_surrender(world, 2)
	assert_false(match_state.is_eliminated(2),
		"surrender must not mark elimination itself -- that would be a second definition")

	match_state.update(world["sim"], world["buildings"])
	assert_true(match_state.is_eliminated(2),
		"D-033's ordinary rule did not notice the concession")


func test_the_base_goes_too_or_the_surrender_does_nothing() -> void:
	# D-033's rule is an AND, so razing only the army leaves a conceding
	# player standing with a town centre and the match unable to end. That
	# is exactly the gap the disconnect path has today (#292), measured:
	# `squads=0 buildings=1 eliminated=false phase=RUNNING`.
	var world := _world()
	_give(world, 1)
	_give(world, 2)
	var sim: SquadSim = world["sim"]
	var buildings: BuildingSim = world["buildings"]

	assert_gt(buildings.living_building_count(2), 0, "setup: player 2 has a base")
	_surrender(world, 2)
	assert_eq(sim.living_squad_count(2), 0, "a conceding player keeps no army")
	assert_eq(buildings.living_building_count(2), 0,
		"a conceding player kept a building, so the ordinary rule can never eliminate them")


func test_conceding_ends_the_match_and_names_the_winner() -> void:
	var world := _world()
	_give(world, 1)
	_give(world, 2)
	var match_state: MatchState = world["match"]

	_surrender(world, 2)
	match_state.update(world["sim"], world["buildings"])

	assert_eq(match_state.phase, MatchState.Phase.FINISHED,
		"the match did not end when the only opponent conceded")
	assert_eq(match_state.winner, 1, "the wrong player won a conceded match")
	assert_eq(match_state.standing_of(1), MatchState.Standing.VICTOR)
	assert_eq(match_state.standing_of(2), MatchState.Standing.ELIMINATED)


func test_a_player_concedes_only_for_themselves() -> void:
	# A 2v2: one ally conceding must not end their partner's match. The
	# team clause in `_check_victory` (D-050) already handles this and is
	# the reason surrender needs no team logic of its own -- but a rule
	# nothing exercises is a rule waiting to be broken, and #119's whole
	# finding is that the allied configuration is the one nothing runs.
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var match_state := MatchState.new()
	match_state.players_expected = 4
	for player in [1, 2, 3, 4]:
		match_state.add_player(player)
	match_state.seats = [
		{"player": 1, "kind": "human", "civ": &"gildedreach", "team": 1},
		{"player": 2, "kind": "human", "civ": &"gildedreach", "team": 1},
		{"player": 3, "kind": "human", "civ": &"gildedreach", "team": 2},
		{"player": 4, "kind": "human", "civ": &"gildedreach", "team": 2},
	]
	match_state.phase = MatchState.Phase.RUNNING

	var server = load("res://server.gd").new()
	server._sim = sim
	server._buildings = buildings
	server._match = match_state
	var peers := {}
	for player in [1, 2, 3, 4]:
		sim.add_squad(UnitRoster.by_id(LEVY), player, Vector2i(6 * player, 10))
		var peer := LoopbackPeer.new()
		server._clients[peer] = {"player": player}
		peers[player] = peer

	server._handle_surrender(peers[1])
	match_state.update(sim, buildings)

	assert_true(match_state.is_eliminated(1), "the conceding player is out")
	assert_false(match_state.is_eliminated(2),
		"a player conceded and took their ALLY out of the match with them")
	assert_eq(match_state.phase, MatchState.Phase.RUNNING,
		"one of four players conceding ended the whole match")
	assert_gt(sim.living_squad_count(2), 0, "the ally's army was razed by their partner")


func test_the_last_of_a_side_conceding_ends_it() -> void:
	# The other half of the team clause: once nobody on a side is left,
	# the ordinary victory rule fires exactly as it does for annihilation.
	var world := _world(1, 2)
	_give(world, 1)
	_give(world, 2)
	var match_state: MatchState = world["match"]

	_surrender(world, 2)
	match_state.update(world["sim"], world["buildings"])
	assert_eq(match_state.phase, MatchState.Phase.FINISHED)
	assert_eq(match_state.winner, 1)


# --- what it refuses --------------------------------------------------

func test_surrender_is_refused_outside_a_running_match() -> void:
	var world := _world()
	_give(world, 1)
	_give(world, 2)
	var match_state: MatchState = world["match"]
	match_state.phase = MatchState.Phase.LOBBY

	_surrender(world, 2)
	assert_gt((world["sim"] as SquadSim).living_squad_count(2), 0,
		"a surrender in the lobby razed an army")
	var state: ClientState = (world["peers"][2] as LoopbackPeer).state
	assert_true(state.last_notice.contains("no match"),
		"a refused surrender said nothing: %s" % state.last_notice)


func test_conceding_twice_is_a_no_op_and_says_so() -> void:
	# In a 2v2, because that is the only shape in which the guard is
	# REACHABLE: a concession that ends the match leaves the phase
	# FINISHED, so a second press is refused by the not-running clause and
	# the already-out clause never runs. Written as a 1v1 first, and the
	# refusal came back "There is no match to surrender" -- correct, and
	# testing a different branch than the one intended.
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var match_state := MatchState.new()
	match_state.players_expected = 4
	for player in [1, 2, 3, 4]:
		match_state.add_player(player)
	match_state.seats = [
		{"player": 1, "kind": "human", "civ": &"gildedreach", "team": 1},
		{"player": 2, "kind": "human", "civ": &"gildedreach", "team": 1},
		{"player": 3, "kind": "human", "civ": &"gildedreach", "team": 2},
		{"player": 4, "kind": "human", "civ": &"gildedreach", "team": 2},
	]
	match_state.phase = MatchState.Phase.RUNNING

	var server = load("res://server.gd").new()
	server._sim = sim
	server._buildings = buildings
	server._match = match_state
	var peers := {}
	for player in [1, 2, 3, 4]:
		sim.add_squad(UnitRoster.by_id(LEVY), player, Vector2i(6 * player, 10))
		var peer := LoopbackPeer.new(ClientState.new())
		server._clients[peer] = {"player": player}
		peers[player] = peer

	server._handle_surrender(peers[1])
	match_state.update(sim, buildings)
	assert_true(match_state.is_eliminated(1), "setup: player 1 conceded")
	assert_eq(match_state.phase, MatchState.Phase.RUNNING,
		"setup: the match must still be running, or this tests the wrong branch")

	var state: ClientState = (peers[1] as LoopbackPeer).state
	var before := state.notices_received
	server._handle_surrender(peers[1])

	# The guard has to be OBSERVABLE, or "it did nothing" and "it was
	# refused" are the same run. A player already out who presses it again
	# is told why, and a harness counting MATCH_SURRENDER markers does not
	# double-count one concession.
	assert_gt(state.notices_received, before,
		"a second concession was swallowed without a word")
	assert_true(state.last_notice.contains("already out"),
		"the refusal did not say the player is already out: %s" % state.last_notice)
	assert_eq(match_state.phase, MatchState.Phase.RUNNING,
		"a repeated concession from an eliminated player changed the match")


func test_an_unknown_connection_cannot_concede() -> void:
	# Who is conceding is read from the connection, never from the packet.
	# A peer the server does not know is not a player.
	var world := _world()
	_give(world, 1)
	_give(world, 2)
	var stranger := LoopbackPeer.new()
	world["server"]._handle_surrender(stranger)
	assert_gt((world["sim"] as SquadSim).living_squad_count(2), 0,
		"an unknown connection surrendered on somebody's behalf")


# --- the wire, and the marker a harness reads -------------------------

func test_the_command_carries_no_player_id() -> void:
	# The security property, asserted on the encoding rather than trusted:
	# a payload that named a player would let a client concede for
	# somebody else. One byte, the opcode, exactly as C2S_LEAVE_MATCH.
	var data := NetProtocol.encode_surrender()
	assert_eq(data.size(), 1,
		"the surrender packet carries a payload, which is somewhere a player id could hide")
	assert_eq(int(data[0]), NetProtocol.C2S_SURRENDER)


func test_surrender_is_not_the_same_opcode_as_leaving() -> void:
	# D-075's leave-to-lobby is "I am done with this match"; this is "I
	# have lost it". Folding them together would mean the only way to
	# concede is to stop watching.
	assert_ne(NetProtocol.C2S_SURRENDER, NetProtocol.C2S_LEAVE_MATCH)


func test_the_server_announces_a_concession_as_a_structured_marker() -> void:
	# A harness must be able to tell a conceded match from a fought-out
	# one. Scanned for by grep, so it is asserted as a source fact the way
	# the other markers are -- the alternative is capturing stdout, which
	# no test here does.
	var handle := FileAccess.open("res://server.gd", FileAccess.READ)
	assert_not_null(handle, "server.gd could not be read")
	if handle == null:
		return
	assert_true(handle.get_as_text().contains("server: MATCH_SURRENDER player=%d"),
		"a concession must be announced as a structured marker, not as prose")


func test_the_client_can_actually_reach_it() -> void:
	# The declared-and-unread guard (D-055): a surrender nothing can send
	# is a mechanic that does not exist. This project has shipped that
	# exact shape four times, so the caller is asserted rather than
	# assumed.
	var handle := FileAccess.open("res://client.gd", FileAccess.READ)
	assert_not_null(handle, "client.gd could not be read")
	if handle == null:
		return
	var source := handle.get_as_text()
	assert_true(source.contains("NetProtocol.encode_surrender()"),
		"nothing in the client ever sends a surrender")
	assert_true(source.contains('_styled_button("Surrender"'),
		"there is no way for a player to find it")
	# The CONNECTION, not the function's existence. A first version of
	# this asserted the name appeared in the file, and a perturbation that
	# rewired the button to close the menu instead left it green -- the
	# defect being asserted about is precisely a control wired to the
	# wrong thing.
	assert_true(source.contains("_surrender_confirm.pressed.connect(_on_surrender_confirmed)"),
		"the confirmation button is not wired to the thing that sends the surrender")
	assert_true(source.contains("func _on_surrender_confirmed"),
		"surrender must ask before it sends -- it is one misclick from Resume")
