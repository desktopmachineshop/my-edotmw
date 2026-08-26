extends GutTest

## Guards D-075 — leaving a match returns to the lobby instead of
## disconnecting, and a second match starts clean.
##
## The phase machine had run one way only (LOBBY -> RUNNING -> FINISHED)
## since D-033, so every rule here is about the edge that did not exist:
## what a match writes on the lobby, and what therefore has to be undone
## before the next one. The interesting failures are all "match two
## silently inherits match one", which no smoke run would notice — a
## second match with the first one's civs looks completely normal.
##
## The client half lives in ClientState for the reason MatchState's own
## header gives: it is the part that can be tested without a socket or a
## GPU, and the bots run the same class.


func _lobby() -> MatchState:
	var m := MatchState.new()
	m.require_admin_start = true
	m.civ_rng.seed = 42
	return m


func _running_match() -> MatchState:
	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 2)
	assert_true(m.request_start(1), "Setup: the admin should be able to start")
	assert_eq(m.phase, MatchState.Phase.RUNNING, "Setup: the match should be running")
	return m


# --- the transition itself --------------------------------------------

func test_leaving_a_match_returns_to_the_lobby() -> void:
	var m := _running_match()
	assert_true(m.return_to_lobby(), "Leaving a running match should report that it left one")
	assert_eq(m.phase, MatchState.Phase.LOBBY, "The server should be back in the lobby")


func test_returning_from_a_lobby_is_a_no_op() -> void:
	# The caller uses the return value to decide whether to tear a world
	# down. Reporting true here would drop a world that was never built.
	var m := _lobby()
	m.add_player(1)
	assert_false(m.return_to_lobby(), "A lobby that never started has no match to leave")


func test_the_seats_survive_so_the_next_match_is_one_click_away() -> void:
	var m := _running_match()
	m.return_to_lobby()
	assert_eq(m.seats.size(), 2, "Leaving should not evict anybody from the lobby")
	assert_true(m.is_admin(1), "The admin should still be the admin")


func test_a_second_match_can_be_started() -> void:
	var m := _running_match()
	m.return_to_lobby()
	assert_true(m.request_start(1), "The admin should be able to start again")
	assert_eq(m.phase, MatchState.Phase.RUNNING)


# --- the session a human actually plays (#92) --------------------------
#
# `quick-test` and `run-server AI=3` are no-lobby starts: the AI seats are
# created from the command line before anybody connects, and the match
# begins the moment the human arrives. That is the session this whole
# feature exists to serve, and it was the one session leave-to-lobby did
# not work in — see the AI-never-holds-the-lobby section of test_lobby.gd
# for why.


## A `--players=1 --ai=3` server, seated exactly as server.gd seats one.
func _command_line_ai_match() -> MatchState:
	var m := MatchState.new()
	m.require_admin_start = false
	m.civ_rng.seed = 42
	m.players_expected = 4
	var civs := CivRoster.ids()
	for i in range(3):
		m.add_ai_player(1000 + i, civs[i % civs.size()])
	m.add_player(1)
	assert_eq(m.phase, MatchState.Phase.RUNNING,
		"Setup: the human's arrival should have started the match")
	return m


func test_a_human_can_start_the_second_match_of_an_ai_session() -> void:
	# The reported symptom: ESC -> leave to lobby, and the start button
	# reads "Waiting for host" with the Admin badge on an AI.
	var m := _command_line_ai_match()
	assert_true(m.is_admin(1), "The human should hold the lobby, not an AI")

	assert_true(m.return_to_lobby())
	assert_true(m.request_start(1),
		"The human could never start another match — the admin was a computer")
	assert_eq(m.phase, MatchState.Phase.RUNNING)


func test_the_ai_seats_of_that_session_are_still_ai_in_the_second_match() -> void:
	# `_return_to_lobby` drops every brain on purpose and `_on_match_started`
	# rebuilds them from the seats whose kind is "ai". A seat mislabelled
	# "human" takes the `_peer_of` branch instead, finds no socket and is
	# skipped — leaving a player that still counts for elimination and
	# victory (D-033) and can never be defeated by anything but the cap.
	var m := _command_line_ai_match()
	m.return_to_lobby()

	var ai_seats := 0
	for seat in m.seats:
		if String(seat["kind"]) == "ai":
			ai_seats += 1
	assert_eq(ai_seats, 3,
		"The next match would seat no AI brains at all — three inert players")


# --- what a match writes on the lobby, and must not keep ---------------

func test_a_random_seat_draws_again_for_the_second_match() -> void:
	# start_match RESOLVES Random in place, overwriting the choice. Without
	# restoring it, "Random" would mean "random once, ever" and every
	# subsequent match on this server would field the first draw — which
	# looks entirely normal from the outside.
	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 2)
	assert_true(m.request_start(1))
	var first_draw := StringName(m.seats[0]["civ"])
	assert_ne(String(first_draw), String(CivRoster.RANDOM),
		"Setup: starting should have resolved Random to a real civ")

	m.return_to_lobby()
	assert_eq(String(m.seats[0]["civ"]), String(CivRoster.RANDOM),
		"The seat chose Random, so it should say Random again in the lobby")


func test_a_deliberate_civ_choice_is_kept_across_a_match() -> void:
	# The mirror of the test above: restoring the CHOICE must not undo a
	# choice somebody actually made.
	var ids := CivRoster.ids()
	assert_gt(ids.size(), 0, "Setup: there should be civs to choose from")
	var chosen: StringName = ids[0]

	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 2)
	assert_true(m.set_civ(1, 0, chosen), "Setup: a player may set their own civ")
	assert_true(m.request_start(1))
	m.return_to_lobby()

	assert_eq(String(m.seats[0]["civ"]), String(chosen),
		"A civ the player picked should still be picked after the match")


func test_the_loser_of_one_match_does_not_start_the_next_eliminated() -> void:
	# Registration is per-match. Carrying it over would bring an
	# `eliminated` flag into a match its player has not played yet, and the
	# victory rule would end match two before anybody moved.
	var m := _running_match()
	var space := TorusSpace.new(16, 8)
	var sim := SquadSim.new(space, CurveReplicator.new())
	# Neither player has a squad or a building, so both are eliminated.
	m.update(sim, null)
	assert_true(m.is_eliminated(1), "Setup: a player with nothing left is out")

	m.return_to_lobby()
	assert_false(m.is_eliminated(1),
		"A new match must not begin with the last match's defeat still attached")
	assert_eq(m.player_count(), 0,
		"Registration is per-match — server.gd re-registers every seat at start")


func test_a_finished_match_can_also_be_left() -> void:
	# Leaving is offered from the game menu, which is reachable after a
	# match has been won as well as during one. Refusing here would strand
	# a finished match on screen with no way back.
	var m := _running_match()
	m.phase = MatchState.Phase.FINISHED
	m.winner = 1
	assert_true(m.return_to_lobby(), "A finished match should be leavable too")
	assert_eq(m.phase, MatchState.Phase.LOBBY)
	assert_eq(m.winner, -1, "The next lobby should not still name a winner")


# --- the client half --------------------------------------------------

func _client_in_a_match() -> ClientState:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(
		1, 16, 8, PackedInt32Array([0, 1]), [], 40, 0))
	state.handle_packet(NetProtocol.encode_squad_info([
		{"id": 0, "def_id": "gildedreach_levy", "alive": 30, "shape": "line", "owner": 1},
	]))
	return state


func test_a_client_forgets_the_match_it_left() -> void:
	var state := _client_in_a_match()
	assert_true(state.welcomed, "Setup: the client should be in a match")
	assert_gt(state.squads.size(), 0, "Setup: the client should know some squads")

	state.leave_match()
	assert_eq(state.squads.size(), 0, "Squad ids restart next match — keeping them draws the dead match")
	assert_false(state.welcomed)
	assert_null(state.space, "The next match may not even be the same size (D-049)")
	assert_false(state.terrain_sampler.is_valid(),
		"The sampler closes over chunks the client frees — it must not outlive them")


func test_leaving_keeps_the_counters_the_test_harness_reads() -> void:
	# test-load and test-client read these as run totals. Zeroing them
	# would make a busy client report a quiet one, which is the shape of
	# vacuous pass CLAUDE.md's audit rule exists to prevent.
	var state := _client_in_a_match()
	state.casualties_applied = 7
	state.desync_count = 0
	state.state_hash_checks = 12

	state.leave_match()
	assert_eq(state.casualties_applied, 7, "Casualties are a session total, not a match total")
	assert_eq(state.state_hash_checks, 12, "Hash comparisons are a session total")


func test_a_client_stays_in_its_seat_when_it_leaves_a_match() -> void:
	# The whole point of D-075: leaving is not a disconnect, so the lobby
	# the client returns to is the one it was already sitting in.
	var state := _client_in_a_match()
	state.handle_packet(NetProtocol.encode_lobby(1, [
		{"kind": "human", "player": 1, "civ": "stoneblood", "team": 0, "name": "Player 1"},
		{"kind": "ai", "player": 2, "civ": "gravesworn", "team": 0, "name": "AI 2"},
	], {}, int(MatchState.Phase.LOBBY)))

	state.leave_match()
	assert_true(state.in_lobby(), "The client should be showing the lobby again")
	assert_eq(state.lobby.get("seats", []).size(), 2, "The seat list belongs to the lobby, not the match")
	assert_eq(state.player, 1, "The server does not reissue player ids")


# --- the ground the SECOND match stands on ----------------------------
#
# `client.gd` is native-only (D-014) and this file's header says so: what
# is testable headless lives in ClientState. That is true of everything
# the client DRAWS — and it left the client's node LIFETIME untested, so
# `_teardown_match()` freed `_terrain_root` and nothing ever built it
# again. Every match after a return to the lobby rendered squads and
# forests standing on nothing, with every number green: the chunk meshes
# really were built, they were just parented to a null instance.
#
# The lifetime half needs no GPU and no window. `_build_terrain()` and
# `_teardown_match()` null-guard every node they touch (`_camera`,
# `_minimap_rect`, `_world_environment`), so the real script can be
# instantiated and driven directly. Instantiated, never added to the
# tree — `_ready()` opens a socket, and not running it is also the point
# of the first test below.


## The real `client.gd`, one match's worth of world already known to it.
## Freed by GUT rather than by hand: the terrain roots below are its
## children and go with it.
func _client_with_a_map() -> Node3D:
	var settings := MapSettings.new()
	settings.width = 16
	settings.height = 8
	settings.seed = 7
	var state := _client_in_a_match()
	state.handle_packet(NetProtocol.encode_map_settings(settings.to_dict()))
	assert_true(state.has_map(), "Setup: the client should have the map settings (D-049)")

	var client: Node3D = autofree(load("res://client.gd").new())
	client._state = state
	return client


## Nine, because the world is a torus and the chunk set is drawn at every
## lattice offset (D-035) — one Node3D per copy, under the terrain root.
func _terrain_tiles(client: Node3D) -> int:
	if client._terrain_root == null:
		return -1
	return client._terrain_root.get_child_count()


func test_building_terrain_does_not_depend_on_having_started_up() -> void:
	# `_build_terrain()` has to be self-sufficient rather than rely on an
	# initialisation that ran an unknown number of matches ago — which is
	# what made this fail: the root was constructed once in `_ready()`.
	var client := _client_with_a_map()
	client._build_terrain()
	assert_eq(_terrain_tiles(client), 9,
		"_build_terrain() must construct its own root, not inherit one from _ready()")


func test_a_second_match_draws_terrain_again() -> void:
	# The reported bug, in sequence: play a match, return to the lobby,
	# start another. Set up exactly as startup used to leave it, so this
	# fails for the reason the playtest saw rather than for the one above.
	var client := _client_with_a_map()
	var startup_root := Node3D.new()
	client._terrain_root = startup_root
	client.add_child(startup_root)

	client._build_terrain()
	assert_eq(_terrain_tiles(client), 9, "Setup: the first match should draw its ground")

	client._teardown_match()
	assert_null(client._terrain_root,
		"The mesh must go: the lobby can change size, seed and preset before the next match (D-049)")

	# The second match. `_terrain_built` is false again, so the client
	# rebuilds — and the ground has to come back with it.
	client._state.handle_packet(NetProtocol.encode_welcome(
		1, 16, 8, PackedInt32Array([0, 1]), [], 40, 0))
	var settings := MapSettings.new()
	settings.width = 16
	settings.height = 8
	settings.seed = 9
	client._state.handle_packet(NetProtocol.encode_map_settings(settings.to_dict()))

	assert_false(client._terrain_built, "Setup: the client should know it owes itself a terrain")
	client._build_terrain()
	assert_eq(_terrain_tiles(client), 9,
		"The second match renders squads and forests standing on nothing without this")


# --- restarting after a real win or a real loss ------------------------
#
# Everything above reaches FINISHED either by leaving mid-match or by
# ASSIGNING `phase`/`winner` directly. That is enough to test the
# transition itself and is not enough to test the transition it is
# actually used for: a match that ended because somebody WON, through
# `_check_victory`, with a victor and a loser both recorded.
#
# The distinction matters because the state a real ending leaves behind
# is strictly larger than the state a hand-set `phase` leaves behind —
# `winner`, per-player `eliminated`, and the registration that produced
# them all get written by the victory path and by nothing else. A test
# that sets `phase` itself is testing the cleanup of a world that never
# existed.
#
# Reported from a playtest as "lots of strange bugs on restarting a game
# from lobby", after a match had been decided.

## Two seats, one of which is about to lose everything.
##
## `winner_owns_a_squad` decides which way the match goes, so the same
## fixture drives both a win and a loss without a second copy of it.
func _decided_match(winner: int, loser: int) -> Dictionary:
	var m := _lobby()
	m.add_player(winner)
	m.add_player(loser)
	assert_true(m.request_start(winner), "Setup: the admin should be able to start")

	var space := TorusSpace.new(16, 8)
	var sim := SquadSim.new(space, CurveReplicator.new())
	# Only the winner has anything left to fight with, so `update` should
	# eliminate the loser and `_check_victory` should end the match.
	sim.add_squad(_squad_def(), winner, Vector2i(4, 4))

	var out := m.update(sim, null)
	return {"match": m, "sim": sim, "eliminated": out}


## A minimal real UnitDef, borrowed from the roster so the shape and
## spacing are a shipped unit's rather than invented.
func _squad_def() -> UnitDef:
	var real := UnitRoster.first()
	var d := UnitDef.new()
	d.id = real.id
	d.formation_shape = real.formation_shape
	d.formation_spacing = real.formation_spacing
	d.squad_size = 8
	d.health = 50.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.vision_range = 6.0
	return d


func test_a_real_victory_actually_finishes_the_match() -> void:
	# The fixture the rest of this section leans on. If this stops
	# decribing a genuine win, every test below it silently starts
	# testing nothing, exactly as a hand-set `phase` does.
	var world := _decided_match(1, 2)
	var m: MatchState = world["match"]
	assert_eq(m.phase, MatchState.Phase.FINISHED,
		"A player with nothing left should end the match")
	assert_eq(m.winner, 1, "The survivor should be the winner")
	assert_true(m.is_eliminated(2), "The player with nothing left is out")
	assert_false(m.is_eliminated(1), "The survivor is not")


func test_the_lobby_after_a_won_match_names_no_winner() -> void:
	var m: MatchState = _decided_match(1, 2)["match"]
	assert_true(m.return_to_lobby(), "A decided match should be leavable")
	assert_eq(m.phase, MatchState.Phase.LOBBY)
	assert_eq(m.winner, -1,
		"A lobby showing the last match's victor is showing a result for a match nobody is playing")


func test_the_victor_of_one_match_does_not_start_the_next_still_winning() -> void:
	var m: MatchState = _decided_match(1, 2)["match"]
	m.return_to_lobby()

	# Registration is per-match (see the loser test above), so the server
	# re-seats everyone at start.
	m.add_player(1)
	m.add_player(2)
	assert_true(m.request_start(1), "The admin should be able to start the next match")
	assert_eq(m.phase, MatchState.Phase.RUNNING,
		"The second match should run, not open already finished")
	assert_eq(m.winner, -1, "The second match has not been won by anybody yet")


func test_the_loser_of_a_real_defeat_plays_the_next_match_alive() -> void:
	# The existing loser test drives a match in which BOTH players are
	# eliminated, which never reaches `_check_victory`'s winner branch.
	# This is the asymmetric case: a real defeat, with somebody else
	# recorded as having won it.
	var m: MatchState = _decided_match(1, 2)["match"]
	assert_true(m.is_eliminated(2), "Setup: player 2 lost")

	m.return_to_lobby()
	m.add_player(1)
	m.add_player(2)

	assert_false(m.is_eliminated(2),
		"Losing one match must not carry a defeat into the next one")
	assert_false(m.is_eliminated(1), "And the winner starts level too")


func test_a_second_match_does_not_end_the_instant_it_starts() -> void:
	# The failure this exists for: victory state surviving the return to
	# the lobby, so `update`'s first call in match two re-decides match
	# one. It would present as a match ending before anybody moved, which
	# is what D-055 records as having gone unnoticed for two milestones
	# when nothing could destroy a building.
	var m: MatchState = _decided_match(1, 2)["match"]
	m.return_to_lobby()
	m.add_player(1)
	m.add_player(2)
	assert_true(m.request_start(1), "Setup: the second match should start")

	# Both players hold ground this time, so nobody is eliminated and the
	# match must keep running.
	var space := TorusSpace.new(16, 8)
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.add_squad(_squad_def(), 1, Vector2i(4, 4))
	sim.add_squad(_squad_def(), 2, Vector2i(12, 4))

	var newly := m.update(sim, null)
	assert_eq(newly.size(), 0, "Nobody has lost anything in the second match")
	assert_eq(m.phase, MatchState.Phase.RUNNING,
		"The second match must not inherit the first one's ending")
	assert_eq(m.winner, -1, "Nor its winner")


func test_the_server_drops_its_building_reveal_baseline_with_the_match() -> void:
	# Found in a playtest log: 106 building desyncs over one session that
	# used the sandbox Regen button. `_return_to_lobby` cleared each
	# client's `visible` baseline under a comment saying none of them may
	# keep a reveal baseline from the old match — and left
	# `known_buildings` (D-030's ever-revealed set, which the server
	# HASHES) untouched beside it. Building ids restart at 0 in the next
	# match, so the server hashed stale entries against a client that had
	# torn its world down.
	#
	# A source scan, the idiom this project already uses for rules that
	# live where GUT cannot reach (test_terrain_fog's caller check):
	# server.gd needs a live ENetConnection to instantiate at all.
	var source := FileAccess.get_file_as_string("res://server.gd")
	assert_false(source.is_empty(), "server.gd must be readable")
	var start := source.find("func _return_to_lobby")
	assert_gt(start, 0, "there must be a _return_to_lobby to scan")
	var body := source.substr(start, source.find("\nfunc ", start + 10) - start)
	assert_true(body.contains("known_buildings"),
		"_return_to_lobby must drop the building reveal baseline too, "
		+ "or the next match's hash compares against the last match's set")
