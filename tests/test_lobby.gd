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


# --- teams (D-050) ----------------------------------------------------

func test_a_player_may_choose_only_their_own_team() -> void:
	var m := _two_humans()
	assert_true(m.set_team(2, m.seat_of(2), 1), "A player should pick their own side")
	assert_false(m.set_team(2, m.seat_of(1), 1),
		"A player changed somebody else's team — the client is not trusted (D-002)")


func test_the_host_allocates_ai_teams() -> void:
	var m := _two_humans()
	var ai_seat := m.add_ai(1, CivRoster.RANDOM, 3)
	assert_true(m.set_team(1, ai_seat, 2), "The host allocates AI teams")
	assert_false(m.set_team(2, ai_seat, 2), "A non-host set an AI's team")


func test_an_out_of_range_team_is_refused() -> void:
	var m := _two_humans()
	assert_false(m.set_team(2, m.seat_of(2), 99), "A client can send anything")
	assert_false(m.set_team(2, m.seat_of(2), -1))


func test_no_team_means_free_for_all_not_one_big_alliance() -> void:
	# The trap: if 0 counted as a team, every player who left the setting
	# alone would be allied with every other, and nobody could ever fight.
	var m := _two_humans()
	assert_false(m.are_allied(1, 2),
		"Two players with no team set should be enemies, not allies")


func test_players_on_the_same_team_are_allied() -> void:
	var m := _two_humans()
	m.set_team(1, m.seat_of(1), 2)
	m.set_team(2, m.seat_of(2), 2)
	assert_true(m.are_allied(1, 2))
	assert_true(m.are_allied(1, 1), "A player is always allied with itself")


func test_a_team_can_win_rather_than_only_a_lone_player() -> void:
	# Without this a 2v2 never ends: two surviving allies are still two
	# active players, so the match would run forever with nobody left to
	# fight.
	var m := _lobby()
	for p in [1, 2, 3]:
		m.add_player(p)
	m.set_team(1, m.seat_of(1), 1)
	m.set_team(2, m.seat_of(2), 1)
	m.set_team(3, m.seat_of(3), 2)
	m.request_start(1)

	var space := TorusSpace.new(24, 12, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := UnitRoster.first()
	sim.add_squad(def, 1, Vector2i(2, 2))
	sim.add_squad(def, 2, Vector2i(6, 2))
	var doomed := sim.add_squad(def, 3, Vector2i(10, 2))

	m.update(sim)
	assert_eq(m.phase, MatchState.Phase.RUNNING, "Everyone is alive; nobody has won")

	sim.consume_squad(doomed)
	m.update(sim)
	assert_eq(m.phase, MatchState.Phase.FINISHED,
		"One team is left standing, so the match is over")


func test_the_team_map_describes_every_seat() -> void:
	var m := _two_humans()
	m.set_team(1, m.seat_of(1), 3)
	var map := m.team_map()
	assert_eq(int(map.get(1, -1)), 3, "The simulation is told player 1's team")
	assert_eq(int(map.get(2, -1)), 0, "…and that player 2 has none")


# --- chat (D-050) -----------------------------------------------------

func test_chat_strips_newlines_so_a_message_cannot_forge_extra_lines() -> void:
	# A message is one line in everyone's window. Without this, "hi\nHost:
	# I surrender" would render as two, one of them attributed to somebody
	# else — putting words in another player's mouth, which is the same
	# untrusted-client rule as orders (D-002).
	var cleaned := NetProtocol.sanitise_chat("hi\nHost:  I surrender")
	assert_false(cleaned.contains("\n"), "A newline survived into a chat message")
	assert_true(cleaned.begins_with("hi"))


func test_chat_is_length_capped() -> void:
	var long_text := "x".repeat(NetProtocol.CHAT_MAX_CHARS * 3)
	assert_eq(NetProtocol.sanitise_chat(long_text).length(), NetProtocol.CHAT_MAX_CHARS,
		"An unbounded message stalls every packet queued behind it (D-042)")


func test_an_empty_message_stays_empty() -> void:
	assert_eq(NetProtocol.sanitise_chat("   \t  "), "",
		"Whitespace-only chat should be dropped, not relayed as a blank line")


func test_chat_roundtrips_with_its_speaker() -> void:
	var decoded := NetProtocol.decode_chat(NetProtocol.encode_chat("Player 2", "well played"))
	assert_eq(String(decoded["speaker"]), "Player 2")
	assert_eq(String(decoded["text"]), "well played")


# --- spawn assignment (D-052's rule, applied where it was missed) ------

func test_a_human_and_an_ai_never_share_a_spawn_point() -> void:
	# Reported from a real game: the player and an AI spawned on top of
	# each other. server.gd used `points[(player - 1) % points.size()]`,
	# and AI players are numbered from 1000 (D-051, sharing the human id
	# space on purpose). With 20 spawn points that is index 0 for player 1
	# and 1000 % 20 = 0 for player 1001 — the same cell.
	#
	# D-052 fixed exactly this for colours, and said in as many words that
	# any modulo of a player id collides once ids start at 1000. Spawn
	# assignment never had the fix applied.
	var m := _lobby()
	m.add_player(1)
	for i in range(8):
		m.add_ai(1, CivRoster.ids()[0], 1000 + i)

	var points := 20
	var taken := {}
	for seat in m.seats:
		var player := int(seat["player"])
		var index := m.spawn_index(player, points)
		assert_false(taken.has(index),
			"players %s and %d both spawn on point %d" % [
				taken.get(index, "?"), player, index])
		taken[index] = player

	# Name the exact pair that was reported, so a regression says so
	# rather than just failing somewhere in the loop above.
	assert_ne(m.spawn_index(1, points), m.spawn_index(1001, points),
		"player 1 and AI 1001 still share a spawn point — the id modulo is back")


func test_spawn_points_are_shared_only_when_there_are_too_few() -> void:
	# The other side of the boundary. Wrapping is the deliberate fallback
	# for a short-seated map (a shared start beats a crash), so this must
	# not be "read as" a bug by a future reader — but it must only happen
	# when seats genuinely outnumber points.
	var m := _lobby()
	m.add_player(1)
	for i in range(5):
		m.add_ai(1, CivRoster.ids()[0], 1000 + i)

	# Six seats, three points: sharing is unavoidable and expected.
	var indices := []
	for seat in m.seats:
		indices.append(m.spawn_index(int(seat["player"]), 3))
	assert_eq(indices, [0, 1, 2, 0, 1, 2],
		"short-seated wrapping should walk the points in seat order")
