extends GutTest

## Guards D-033 (match lifecycle, elimination and victory) and D-027's
## criteria 1 and 2.
##
## These rules are the ones a smoke run cannot check. "The server didn't
## crash" is true of a match that never starts, one that declares a winner
## the instant it begins, and one that never ends at all — so each of
## those is a test here rather than something noticed during a playtest.

const W := 32
const H := 16


func _sim() -> SquadSim:
	return SquadSim.new(TorusSpace.new(W, H, 1.0), CurveReplicator.new())


## Harmless by default: no damage and no range, so nothing dies unless a
## test kills it deliberately. Elimination is the subject here, and a
## stray engagement would make these tests pass or fail for the wrong
## reason.
func _def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"match_test_unit"
	d.squad_size = 10
	d.health = 50.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.move_speed = 3.0
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	d.morale = 100.0
	return d


func _match_with(sim: SquadSim, player_count: int, squads_each: int = 2) -> MatchState:
	var state := MatchState.new()
	state.players_expected = player_count
	var def := _def()
	for player in range(1, player_count + 1):
		for i in range(squads_each):
			sim.add_squad(def, player, Vector2i(player * 6, i * 2))
		state.add_player(player)
	return state


# --- lobby and start ---------------------------------------------------

func test_match_waits_in_lobby_until_enough_players_join() -> void:
	var state := MatchState.new()
	state.players_expected = 3

	assert_eq(state.phase, MatchState.Phase.LOBBY)
	assert_false(state.add_player(1), "One of three players must not start the match")
	assert_false(state.add_player(2), "Two of three players must not start the match")
	assert_eq(state.phase, MatchState.Phase.LOBBY)

	assert_true(state.add_player(3), "The last expected player starts the match")
	assert_true(state.is_running())


func test_lobby_does_not_eliminate_players_who_have_not_spawned() -> void:
	# A registered player holds zero squads until the server spawns them.
	# Running the elimination rule during the lobby would knock everyone
	# out before the match began.
	var sim := _sim()
	var state := MatchState.new()
	state.players_expected = 4
	state.add_player(1)
	state.add_player(2)

	assert_eq(state.update(sim), [], "Nobody is eliminated while still in the lobby")
	assert_false(state.is_finished())


# --- elimination -------------------------------------------------------

func test_a_player_with_no_living_squads_is_eliminated() -> void:
	var sim := _sim()
	var state := _match_with(sim, 2)
	assert_true(state.is_running())

	assert_eq(state.update(sim), [], "Nobody is out while both players have squads")

	sim.eliminate_player(2)
	assert_eq(state.update(sim), [2], "A player with nothing left alive is eliminated")
	assert_true(state.is_eliminated(2))
	assert_false(state.is_eliminated(1))


func test_elimination_is_reported_once_not_every_tick() -> void:
	# The caller announces whatever update() returns, so repeating a
	# player would spam the log and, worse, announce a defeat twice.
	var sim := _sim()
	var state := _match_with(sim, 3)
	sim.eliminate_player(3)

	assert_eq(state.update(sim), [3])
	assert_eq(state.update(sim), [], "An already-eliminated player is not reported again")


func test_eliminate_player_wipes_squads_and_describes_it_as_casualties() -> void:
	var sim := _sim()
	_match_with(sim, 2, 3)

	var events := sim.eliminate_player(1)
	assert_eq(events.size(), 3, "One event per squad that was still alive")
	for event in events:
		assert_eq(int(event["alive"]), 0)
		assert_eq(sim.alive_of(int(event["id"])), 0)

	assert_eq(sim.living_squad_count(1), 0)
	assert_eq(sim.living_squad_count(2), 3, "Only the named player's army is wiped")

	assert_eq(sim.eliminate_player(1), [],
		"Wiping an already-wiped player produces no further events")


# --- victory -----------------------------------------------------------

func test_last_player_standing_wins() -> void:
	var sim := _sim()
	var state := _match_with(sim, 3)

	sim.eliminate_player(1)
	state.update(sim)
	assert_false(state.is_finished(), "Two players left is not a victory")

	sim.eliminate_player(3)
	state.update(sim)

	assert_true(state.is_finished(), "One player left ends the match")
	assert_eq(state.winner, 2)


func test_a_solo_session_never_declares_a_winner() -> void:
	# run-client and test-client both connect a single player. Declaring
	# them the winner the moment they arrive would be absurd, and would
	# break both development flows.
	var sim := _sim()
	var state := _match_with(sim, 1)

	assert_true(state.is_running(), "A one-player session still starts")
	state.update(sim)
	assert_false(state.is_finished(), "Beating nobody is not winning")
	assert_eq(state.winner, -1)


func test_disconnect_leads_to_elimination_through_the_normal_rule() -> void:
	# Disconnect is a CAUSE of defeat, not a second definition of it: the
	# server wipes the army and the ordinary rule notices.
	var sim := _sim()
	var state := _match_with(sim, 2)

	state.mark_disconnected(2)
	assert_false(state.is_eliminated(2), "Losing a connection alone does not end a match")

	sim.eliminate_player(2)
	assert_eq(state.update(sim), [2])
	assert_true(state.is_finished())
	assert_eq(state.winner, 1)


func test_a_finished_match_stops_evaluating() -> void:
	var sim := _sim()
	var state := _match_with(sim, 2)
	sim.eliminate_player(2)
	state.update(sim)
	assert_true(state.is_finished())

	sim.eliminate_player(1)
	assert_eq(state.update(sim), [], "A finished match does not keep eliminating people")
	assert_eq(state.winner, 1, "The winner does not change after the match ends")
