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


# --- a whole match, actually fought (D-027 criterion 2) ---------------

## Two sides that can genuinely kill each other, unlike _def() above.
## Asymmetric on purpose: one side must actually win, and two identical
## armies now resolve simultaneously (D-024) and can grind to mutual
## destruction, which would end the match with no winner at all.
func _fighter_def(strong: bool) -> UnitDef:
	var d := UnitDef.new()
	d.id = &"match_test_fighter"
	# The two sides differ only in NUMBERS, not in per-soldier quality.
	# The first version made the weak side hit softly as well as being
	# outnumbered, and it died before landing a single casualty — so the
	# match ended with the winner untouched, and "the winner took losses
	# too" failed. Equal damage means the smaller army still bloodies the
	# larger one on its way down, which is what makes this a fight rather
	# than an execution.
	d.squad_size = 20 if strong else 8
	d.health = 40.0
	d.damage = 12.0
	d.attack_range = 3.0          # ~1.7 cells: reaches an adjacent squad
	d.attack_interval = 0.1       # every tick, so a test-length match ends
	d.move_speed = 3.0
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	d.morale = 100.0
	d.rout_threshold = 0.0        # nobody routs away; this is a fight to a finish
	d.morale_loss_per_casualty = 0.0
	d.damage_variance = 0.0
	return d


func test_a_match_played_to_completion_produces_exactly_one_winner() -> void:
	# Every other victory test in this file calls eliminate_player()
	# directly, which proves the RULE but never the SYSTEM: no match had
	# ever actually been fought to a finish. This one runs the real loop —
	# combat resolving each tick, strengths falling, elimination noticed
	# by the ordinary rule — and asserts a single winner comes out.
	var sim := _sim()
	var state := MatchState.new()
	state.players_expected = 2

	var strong := sim.add_squad(_fighter_def(true), 1, Vector2i(8, 8))
	var weak := sim.add_squad(_fighter_def(false), 2, Vector2i(9, 8))
	state.add_player(1)
	state.add_player(2)
	assert_true(state.is_running(), "Both players present, so the match starts")

	var eliminated := []
	var ticks := 0
	while not state.is_finished() and ticks < 600:
		sim.tick()
		eliminated.append_array(state.update(sim))
		ticks += 1

	assert_true(state.is_finished(),
		"A real fight must end the match, not run forever (stopped after %d ticks)" % ticks)
	assert_eq(state.winner, 1, "The stronger army should be the one left standing")
	assert_eq(eliminated, [2], "The loser is reported exactly once, as it falls")

	assert_eq(sim.alive_of(weak), 0, "The losing squad is actually dead, not merely declared so")
	assert_gt(sim.alive_of(strong), 0, "And the winner survived it")
	assert_lt(sim.alive_of(strong), 20,
		"The winner took losses too — a match decided without a shot fired would prove nothing")

	assert_eq(state.active_players(), [1])


# --- squad cap (D-033) -------------------------------------------------

## A gatherer crew is a squad like any other (D-028) — this is just a
## UnitDef with a different id, which is exactly the point being tested.
func _gatherer_def() -> UnitDef:
	var d := _def()
	d.id = &"match_test_gatherers"
	return d


func test_one_cap_covers_military_and_gatherer_squads_alike() -> void:
	# The decision this guards: gatherers count towards the same total.
	# If each kind had its own ceiling, or if only one production path
	# checked, a player could field twice the intended army by making half
	# of it villagers — and the economy-versus-army trade would evaporate.
	var sim := _sim()
	var state := MatchState.new()
	state.squad_cap = 4
	state.players_expected = 1
	state.add_player(1)

	var military := _def()
	var gatherers := _gatherer_def()

	sim.add_squad(military, 1, Vector2i(1, 1))
	sim.add_squad(military, 1, Vector2i(2, 1))
	assert_true(state.has_squad_capacity(sim, 1), "Two of four used")

	sim.add_squad(gatherers, 1, Vector2i(3, 1))
	assert_true(state.has_squad_capacity(sim, 1), "Three of four used")

	sim.add_squad(gatherers, 1, Vector2i(4, 1))
	assert_false(state.has_squad_capacity(sim, 1),
		"Four squads is the cap regardless of how many are gatherers")


func test_the_cap_is_per_player() -> void:
	var sim := _sim()
	var state := MatchState.new()
	state.squad_cap = 2
	state.players_expected = 2
	state.add_player(1)
	state.add_player(2)

	sim.add_squad(_def(), 1, Vector2i(1, 1))
	sim.add_squad(_gatherer_def(), 1, Vector2i(2, 1))

	assert_false(state.has_squad_capacity(sim, 1), "Player 1 is full")
	assert_true(state.has_squad_capacity(sim, 2), "Player 2 is untouched by player 1's army")


func test_losing_squads_frees_capacity() -> void:
	# The cap is a ceiling on what stands on the map, not a lifetime
	# quota — otherwise a player who lost a battle could never rebuild.
	var sim := _sim()
	var state := MatchState.new()
	state.squad_cap = 2
	state.players_expected = 1
	state.add_player(1)

	sim.add_squad(_def(), 1, Vector2i(1, 1))
	var doomed := sim.add_squad(_gatherer_def(), 1, Vector2i(2, 1))
	assert_false(state.has_squad_capacity(sim, 1))

	sim.set_alive(doomed, 0)
	assert_true(state.has_squad_capacity(sim, 1), "A destroyed squad frees its slot")


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
