extends GutTest

## Guards D-048 — the lobby: seats, one admin, civ choice, and Random.
##
## All of it lives in MatchState rather than server.gd for the reason that
## file's header gives: rules are exactly the part worth testing, and a
## GUT test cannot stand up an ENet host. "Only the admin may seat AI" is
## a rule, not a UI state.


func _lobby() -> MatchState:
	var m := MatchState.new()
	m.require_admin_start = true
	m.civ_rng.seed = 42
	return m


func _two_humans() -> MatchState:
	var m := _lobby()
	m.add_player(1)
	m.add_player(2)
	return m


# --- seats and admin --------------------------------------------------

func test_the_first_human_to_join_is_admin() -> void:
	var m := _two_humans()
	assert_true(m.is_admin(1), "The first human should hold the lobby")
	assert_false(m.is_admin(2))


func test_joining_seats_a_player_once() -> void:
	var m := _lobby()
	m.add_player(1)
	m.add_player(1)
	assert_eq(m.seats.size(), 1, "Rejoining should not seat the same player twice")


func test_admin_passes_deterministically_when_it_leaves() -> void:
	# Deterministic on purpose: "whoever is next" would make the same
	# disconnection produce different lobbies, and a replay could not
	# reconstruct who was in charge.
	var m := _lobby()
	m.add_player(3)
	m.add_player(1)
	m.add_player(2)
	assert_true(m.is_admin(3), "Player 3 joined first")

	m.remove_human_seat(3)
	assert_true(m.is_admin(1), "The lowest remaining human takes over, not an arbitrary one")


func test_the_last_human_leaving_leaves_nobody_in_charge() -> void:
	var m := _lobby()
	m.add_player(1)
	m.remove_human_seat(1)
	assert_eq(m.admin_player, 0, "An empty lobby should not still name an admin")


# --- who may do what (D-046 criterion 7) ------------------------------

func test_only_the_admin_may_seat_ai() -> void:
	var m := _two_humans()
	assert_eq(m.add_ai(2, CivRoster.ids()[0], 3), -1,
		"A non-admin seated an AI player")
	assert_gte(m.add_ai(1, CivRoster.ids()[0], 3), 0,
		"The admin should be able to seat an AI")


func test_only_the_admin_may_remove_ai() -> void:
	var m := _two_humans()
	var seat := m.add_ai(1, CivRoster.ids()[0], 3)
	assert_false(m.remove_ai(2, seat), "A non-admin removed an AI seat")
	assert_true(m.remove_ai(1, seat))


func test_the_admin_cannot_evict_a_human() -> void:
	# Not a moderation tool. A player leaves by disconnecting.
	var m := _two_humans()
	assert_false(m.remove_ai(1, m.seat_of(2)),
		"remove_ai removed a HUMAN seat")


func test_a_player_may_choose_only_their_own_civ() -> void:
	var m := _two_humans()
	var mine := m.seat_of(2)
	var theirs := m.seat_of(1)
	var civ := CivRoster.ids()[0]

	assert_true(m.set_civ(2, mine, civ), "A player should be able to pick their own civ")
	assert_false(m.set_civ(2, theirs, civ),
		"A player changed somebody else's civ — the client is not trusted (D-002)")


func test_the_admin_may_set_an_ai_civ_but_not_another_humans() -> void:
	var m := _two_humans()
	var ai_seat := m.add_ai(1, CivRoster.RANDOM, 3)
	var civ := CivRoster.ids()[0]

	assert_true(m.set_civ(1, ai_seat, civ), "The admin allocates AI civs")
	assert_false(m.set_civ(1, m.seat_of(2), civ),
		"The admin is not entitled to choose a human's civ for them")


func test_an_unknown_civ_choice_is_refused() -> void:
	var m := _two_humans()
	assert_false(m.set_civ(2, m.seat_of(2), &"not_a_civ"),
		"A client can send anything; the server must not store nonsense")


# --- starting ---------------------------------------------------------

func test_only_the_admin_can_start() -> void:
	var m := _two_humans()
	assert_false(m.request_start(2), "A non-admin started the match")
	assert_eq(m.phase, MatchState.Phase.LOBBY)
	assert_true(m.request_start(1))
	assert_eq(m.phase, MatchState.Phase.RUNNING)


func test_a_lobby_of_one_is_not_a_match() -> void:
	var m := _lobby()
	m.add_player(1)
	assert_false(m.request_start(1), "One seat is not a game")
	assert_eq(m.phase, MatchState.Phase.LOBBY)


func test_an_ai_seat_counts_toward_starting() -> void:
	# The point of seating AI: one human plus AI opponents is a real
	# match, and is how a solo player plays at all.
	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 2)
	assert_true(m.request_start(1), "One human and one AI should be startable")


func test_random_is_still_random_when_the_match_starts() -> void:
	# Resolved at START, not at selection: a player sees "Random" in the
	# lobby and genuinely does not know what they will get.
	var m := _two_humans()
	assert_eq(StringName(m.seats[0]["civ"]), CivRoster.RANDOM,
		"Seats should default to Random")

	m.request_start(1)
	for seat in m.seats:
		assert_not_null(CivRoster.by_id(StringName(seat["civ"])),
			"A seat was left holding '%s' after the match started" % seat["civ"])


func test_an_explicit_choice_survives_the_start() -> void:
	var m := _two_humans()
	var wanted := CivRoster.ids()[0]
	m.set_civ(2, m.seat_of(2), wanted)
	m.request_start(1)
	assert_eq(m.civ_of(2), wanted, "A chosen civ was rerolled at match start")


func test_nothing_can_be_changed_once_the_match_is_running() -> void:
	var m := _two_humans()
	m.request_start(1)
	assert_false(m.set_civ(2, m.seat_of(2), CivRoster.ids()[0]),
		"A civ was changed mid-match")
	assert_eq(m.add_ai(1, CivRoster.ids()[0], 4), -1, "An AI was seated mid-match")
