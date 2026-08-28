extends GutTest

## Guards seat identity and reconnection-as-repossession (#186, D-090).
##
## THE rule, and it is a structural one rather than a feature: **a seat is
## bound to WHO holds it, never to a connection.** D-038 is this project's
## own precedent for getting that wrong — ownership was read from a
## per-connection list written once at join, so every squad a player
## PRODUCED was refused as one they did not own. 2,700 refusals in one
## 20-player run, reported as "zero movement".
##
## The three legs D-090 defines:
##
##   drop-out   a disconnected human's seat passes to an AI within a
##              tick; the army STANDS (superseding D-033's wipe for
##              humans). No grace-period limbo — the AI IS the grace.
##   rejoin     the same IDENTITY reclaims the seat mid-match, with no
##              timeout after which return is refused.
##   drop-in    a new human may take a seat an AI holds (D-089).
##
## Driven without a scene tree: a Node that is never added does not run
## `_ready()`, so no socket is opened — the `test_civ_knobs.gd` discipline
## and D-075's amendment ("needs a socket and a scene tree" is true of
## `_ready()`, not of the file).


class FakePeer:
	extends RefCounted
	var sent := []
	func send(_channel: int, packet: PackedByteArray, _flags: int = 0) -> int:
		sent.append(packet)
		return 0


func _server():
	var script: GDScript = load("res://server.gd")
	var server = script.new()
	server._settings = MapSettings.new()
	server._settings.width = 42
	server._settings.height = 48
	server._settings.seed = 1
	server._config = MapConfig.new()
	server._match = MatchState.new()
	server._match.map_settings = server._settings
	server._match.players_expected = 2
	return server


# --- the identity token itself -----------------------------------------

func test_an_identity_is_not_a_connection() -> void:
	# The property the whole design rests on. Stated as a test because
	# D-038's cache was a copy of the DATA rather than of a check, and
	# nothing failed when it drifted.
	var a := PlayerIdentity.local_token("player-one")
	var b := PlayerIdentity.local_token("player-one")
	var c := PlayerIdentity.local_token("player-two")
	assert_eq(a, b, "the same seed is the same player, across runs and sockets")
	assert_ne(a, c, "different people are different tokens")
	assert_true(PlayerIdentity.same(a, b))
	assert_false(PlayerIdentity.same(a, c))


func test_the_token_carries_nothing_about_the_machine() -> void:
	# An identity is OPAQUE. A token that embedded a username would leak
	# one, and a token that could be parsed would eventually be parsed.
	var token := PlayerIdentity.local_token("dave@example.com")
	assert_false(token.contains("dave"), "the seed must not survive into the token")
	assert_false(token.contains("@"))
	assert_eq(token.length(), 32, "128 bits of hex, and readable in a log line")


func test_two_anonymous_clients_are_not_the_same_player() -> void:
	# The dangerous default. Treating two un-identified clients as one
	# would hand a stranger somebody's army the moment a bot reconnected.
	assert_false(PlayerIdentity.same("", ""), "anonymous never matches anonymous")
	assert_false(PlayerIdentity.same(PlayerIdentity.ANONYMOUS, "abc"))
	assert_true(PlayerIdentity.is_anonymous("   "))


func test_a_hostile_token_is_refused_rather_than_stored() -> void:
	# It arrives from an untrusted client (D-002) and is echoed into logs
	# and compared against every seat.
	assert_eq(PlayerIdentity.normalise("a".repeat(PlayerIdentity.MAX_LENGTH + 1)),
		PlayerIdentity.ANONYMOUS, "over-long tokens are refused")
	assert_eq(PlayerIdentity.normalise("has space"), PlayerIdentity.ANONYMOUS)
	assert_eq(PlayerIdentity.normalise("semi;colon"), PlayerIdentity.ANONYMOUS)
	assert_ne(PlayerIdentity.normalise("76561198000000000"), PlayerIdentity.ANONYMOUS,
		"a platform id in decimal must be accepted")


func test_the_identity_round_trips_the_wire() -> void:
	var token := PlayerIdentity.local_token("wire")
	var decoded := NetProtocol.decode_identify(NetProtocol.encode_identify(token))
	assert_eq(String(decoded["token"]), token)
	assert_eq(NetProtocol.encode_identify(token)[0], NetProtocol.C2S_IDENTIFY)


# --- binding, on MatchState --------------------------------------------

func test_a_seat_remembers_who_holds_it() -> void:
	var state := MatchState.new()
	state.map_settings = MapSettings.new()
	state.add_player(1)
	state.add_player(2)
	var token := PlayerIdentity.local_token("one")
	state.bind_identity(1, token)
	assert_eq(state.seat_for_identity(token), 1)
	assert_eq(state.seat_for_identity(PlayerIdentity.local_token("nobody")), -1)


func test_an_anonymous_client_binds_nothing() -> void:
	# Every load-test bot is in this case, and that is deliberate:
	# identity had to be addable without changing what the existing
	# estate does.
	var state := MatchState.new()
	state.map_settings = MapSettings.new()
	state.add_player(1)
	state.bind_identity(1, "")
	assert_eq(state.identity_of(1), PlayerIdentity.ANONYMOUS)
	assert_eq(state.seat_for_identity(""), -1, "and cannot be reclaimed by anybody")


func test_an_occupied_seat_is_not_reclaimable() -> void:
	var state := MatchState.new()
	state.map_settings = MapSettings.new()
	state.add_player(1)
	assert_false(state.seat_is_reclaimable(1),
		"somebody is sitting there — an identity is not a password")
	state.mark_disconnected(1)
	assert_true(state.seat_is_reclaimable(1), "and once they drop, it is")


func test_the_ai_keeps_the_seats_civ_and_team() -> void:
	# #186 names this as the mislabel one wrong writer away, and it is the
	# D-20260817-an-ai-never-holds-the-lobby family: an AI that inherited
	# a seat and changed its civ would field another civilisation's troops
	# mid-match with nothing failing.
	var state := MatchState.new()
	state.map_settings = MapSettings.new()
	state.add_player(1)
	var index: int = state.seat_of(1)
	state.seats[index]["civ"] = &"emberdeep"
	state.seats[index]["team"] = 2
	assert_true(state.hand_seat_to_ai(1))
	assert_eq(String(state.seats[index]["civ"]), "emberdeep", "the civ is untouched")
	assert_eq(int(state.seats[index]["team"]), 2, "and so is the team")
	assert_eq(String(state.seats[index]["kind"]), "ai", "but the seat is an AI's now")


func test_an_ai_never_keeps_the_admin_badge() -> void:
	# D-20260817-an-ai-never-holds-the-lobby: an admin seat held by a
	# computer is a lobby no human can start a second match from.
	var state := MatchState.new()
	state.map_settings = MapSettings.new()
	state.add_player(1)
	state.add_player(2)
	state.admin_player = 1
	state.hand_seat_to_ai(1)
	assert_ne(state.admin_player, 1, "the badge must leave the AI's seat")
	assert_eq(state.admin_player, 2, "and go to a connected human")


func test_reclaiming_puts_a_human_back_in_the_chair() -> void:
	var state := MatchState.new()
	state.map_settings = MapSettings.new()
	state.add_player(1)
	state.hand_seat_to_ai(1)
	assert_true(state.seat_is_held_for_human(1))
	assert_true(state.reclaim_seat(1))
	assert_eq(String(state.seats[state.seat_of(1)]["kind"]), "human")
	assert_false(state.seat_is_held_for_human(1))
	assert_false(state.reclaim_seat(1), "a seat nobody is holding cannot be reclaimed")


# --- the legs, through the server --------------------------------------

func test_a_dropped_human_does_not_lose_their_army() -> void:
	# THE behavioural change, and the one D-033 used to forbid. Wiping was
	# brutal to the dropped player's TEAM — D-050 makes allies share
	# vision, so armies are interdependent — and for D-056's eventual
	# 1-2 hour matches one dropped connection would decide a team game.
	var server = _server()
	server._build_world()
	server._match.phase = MatchState.Phase.RUNNING
	var peer := FakePeer.new()
	server._clients[peer] = {"player": 1, "visible": {}}
	server._match.add_player(1)
	# A second human stays connected. Not incidental: with nobody left,
	# `_on_disconnect` correctly reaches D-075's "no humans, no server"
	# shutdown — and repossession is a MULTIPLAYER concern, so the
	# realistic fixture is the one where the match carries on without the
	# player who dropped.
	var other := FakePeer.new()
	server._clients[other] = {"player": 2, "visible": {}}
	server._match.add_player(2)

	var def: UnitDef = UnitRoster.for_civ_archetype(&"emberdeep", &"levy")
	assert_not_null(def, "setup: a shipped def to give the player an army")
	server._sim.add_squad(def, 1, Vector2i(5, 5))
	var before: int = server._sim.alive_of(0)
	assert_gt(before, 0, "setup: the army exists")

	server._on_disconnect(peer)

	assert_eq(server._sim.alive_of(0), before,
		"the army must STAND — an AI holds the seat (D-090), it is not wiped")
	assert_true(server._match.seat_is_held_for_human(1),
		"and the seat is marked as being held for its owner")
	server.free()


func test_the_same_identity_reclaims_its_seat() -> void:
	# Repossession, end to end: drop, an AI holds, the SAME identity comes
	# back on a NEW connection and gets the same seat and the same army.
	var server = _server()
	server._build_world()
	server._match.phase = MatchState.Phase.RUNNING
	var token := PlayerIdentity.local_token("returning-player")

	var first := FakePeer.new()
	server._clients[first] = {"player": 1, "visible": {}}
	server._match.add_player(1)
	# Somebody else stays for the whole match — see the note above.
	var bystander := FakePeer.new()
	server._clients[bystander] = {"player": 2, "visible": {}}
	server._match.add_player(2)
	server._handle_identify(first, NetProtocol.encode_identify(token))
	assert_eq(server._match.seat_for_identity(token), 1, "setup: bound to seat 1")

	var def: UnitDef = UnitRoster.for_civ_archetype(&"emberdeep", &"levy")
	server._sim.add_squad(def, 1, Vector2i(5, 5))
	server._on_disconnect(first)

	# A NEW connection, given a NEW provisional seat, as the real one is.
	var second := FakePeer.new()
	server._clients[second] = {"player": 7, "visible": {}}
	server._match.add_player(7)
	server._handle_identify(second, NetProtocol.encode_identify(token))

	assert_eq(int(server._clients[second]["player"]), 1,
		"the returning connection must be pointed at the seat its IDENTITY holds, "
		+ "not at the provisional one its socket was given")
	assert_false(server._match.seat_is_held_for_human(1), "the AI has stood down")
	assert_gt(server._sim.alive_of(0), 0, "and the army is still theirs")
	server.free()


func test_a_different_identity_cannot_take_an_occupied_seat() -> void:
	# An identity is not a password: it arrives from an untrusted client
	# (D-002). Handing over an OCCUPIED seat on the strength of one would
	# be an impersonation bug rather than a reconnection feature.
	var server = _server()
	server._build_world()
	server._match.phase = MatchState.Phase.RUNNING
	var token := PlayerIdentity.local_token("the-owner")

	var owner := FakePeer.new()
	server._clients[owner] = {"player": 1, "visible": {}}
	server._match.add_player(1)
	server._handle_identify(owner, NetProtocol.encode_identify(token))

	var impostor := FakePeer.new()
	server._clients[impostor] = {"player": 2, "visible": {}}
	server._match.add_player(2)
	server._handle_identify(impostor, NetProtocol.encode_identify(token))

	assert_eq(int(server._clients[impostor]["player"]), 2,
		"the seat is in use — the impostor keeps their own")
	assert_eq(int(server._clients[owner]["player"]), 1, "and the owner keeps theirs")
	server.free()


func test_an_anonymous_client_changes_nothing() -> void:
	# The compatibility claim, asserted rather than assumed: every
	# load-test bot never sends IDENTIFY, and a match of anonymous peers
	# must behave exactly as it did before identity existed.
	var server = _server()
	server._build_world()
	server._match.phase = MatchState.Phase.RUNNING
	var peer := FakePeer.new()
	server._clients[peer] = {"player": 1, "visible": {}}
	server._match.add_player(1)
	server._handle_identify(peer, NetProtocol.encode_identify(""))
	assert_eq(int(server._clients[peer]["player"]), 1, "still their own seat")
	assert_eq(server._match.identity_of(1), PlayerIdentity.ANONYMOUS, "and bound to nothing")
	server.free()
