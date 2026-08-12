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
		{"id": 0, "def_id": "legion_militia", "alive": 30, "shape": "line", "owner": 1},
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
		{"kind": "human", "player": 1, "civ": "legion", "team": 0, "name": "Player 1"},
		{"kind": "ai", "player": 2, "civ": "northmen", "team": 0, "name": "AI 2"},
	], {}, int(MatchState.Phase.LOBBY)))

	state.leave_match()
	assert_true(state.in_lobby(), "The client should be showing the lobby again")
	assert_eq(state.lobby.get("seats", []).size(), 2, "The seat list belongs to the lobby, not the match")
	assert_eq(state.player, 1, "The server does not reissue player ids")
