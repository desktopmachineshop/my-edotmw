extends GutTest

## Guards `game_browser.gd` — what the pre-lobby's game list says (#187).
##
## The half of a browser with interesting failure modes, and none of them
## need a socket: a row that offers a join the handshake will refuse, a
## listing that never leaves after its host quits, an order that buries
## the joinable game under three that are full, a dedupe that merges two
## neighbours' games into one row. All of those look exactly like a
## working list in a screenshot.


func _listing(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"provider": "lan", "name": "A game", "map": "continents 168x194",
		"players": 1, "seats": 4, "phase": "lobby", "joinable": true,
		"protocol": 1, "build": "0.4.0", "address": "192.168.1.5", "port": 4433,
		"last_seen": 0.0,
	}
	base.merge(overrides, true)
	return base


# --- identity and staleness --------------------------------------------

func test_two_replies_from_one_game_are_one_row() -> void:
	# UDP: a browser asks once a second and every server answers every
	# time, so the SAME game arrives over and over. If that were not
	# deduped the list would grow without bound while nothing changed.
	var seen := [_listing(), _listing({"players": 2})]
	var known := GameBrowser.merge([], seen, 1.0)
	assert_eq(known.size(), 1, "one endpoint is one game")
	assert_eq(int((known[0] as Dictionary)["players"]), 2,
		"and the LATEST answer wins — the point of asking again")


func test_one_game_answering_on_three_interfaces_is_one_row() -> void:
	# FOUND BY RUNNING IT, which is the only way it could have been: a
	# machine answers a broadcast on every interface it has, so the first
	# real end-to-end run listed one server three times — loopback, the
	# LAN address, and a virtual adapter's — each a perfectly good way to
	# reach the same game. Every unit test passed throughout, because
	# every one of them supplied its own listings.
	var seen := [
		_listing({"id": "20308-777", "address": "127.0.0.1"}),
		_listing({"id": "20308-777", "address": "192.168.68.117"}),
		_listing({"id": "20308-777", "address": "172.20.144.1"}),
	]
	var known := GameBrowser.merge([], seen, 1.0)
	assert_eq(known.size(), 1, "one server is one game, however many ways in it has")
	assert_eq(String((known[0] as Dictionary)["address"]), "127.0.0.1",
		"and the endpoint is the one that answered FIRST — every one of them "
		+ "reaches it from here, and a row whose address changes between "
		+ "replies is a row that joins somewhere else than it showed")


func test_two_servers_are_two_rows_even_on_one_machine() -> void:
	# The other half: the token must not collapse games that merely share
	# an address. Two servers on one machine is the dev loop.
	var seen := [
		_listing({"id": "4433-1", "port": 4433}),
		_listing({"id": "4533-2", "port": 4533}),
	]
	assert_eq(GameBrowser.merge([], seen, 1.0).size(), 2)


func test_a_game_that_sends_no_token_is_still_identified() -> void:
	# An older build, or a provider that has no such notion. The endpoint
	# is the fallback, which is what this did before tokens existed.
	var seen := [_listing(), _listing({"players": 3})]
	for entry in seen:
		(entry as Dictionary).erase("id")
	assert_eq(GameBrowser.merge([], seen, 1.0).size(), 1)


func test_two_games_that_share_a_name_are_two_rows() -> void:
	# Names are user-typed and duplicated. Keying on one would merge two
	# neighbours' games into a single row pointing at whichever answered
	# last — D-102's "a name is what a lobby shows, nothing keys on it".
	var seen := [
		_listing({"address": "192.168.1.5"}),
		_listing({"address": "192.168.1.9"}),
	]
	assert_eq(GameBrowser.merge([], seen, 1.0).size(), 2)


func test_the_same_game_on_two_ports_is_two_rows() -> void:
	var seen := [_listing({"port": 4433}), _listing({"port": 4533})]
	assert_eq(GameBrowser.merge([], seen, 1.0).size(), 2,
		"two servers on one machine are two games")


func test_a_game_that_stops_answering_leaves_the_list() -> void:
	var known := GameBrowser.merge([], [_listing()], 10.0)
	assert_eq(GameBrowser.fresh(known, 10.0 + GameBrowser.STALE_AFTER - 0.1).size(), 1,
		"still listed while it is still answering")
	assert_eq(GameBrowser.fresh(known, 10.0 + GameBrowser.STALE_AFTER + 0.1).size(), 0,
		"and gone once it has stopped — the only thing that removes a row")


func test_a_listing_that_keeps_answering_keeps_its_place() -> void:
	# A list that reorders under the cursor is a list that joins the
	# wrong game.
	var known := GameBrowser.merge([], [
		_listing({"address": "10.0.0.1"}),
		_listing({"address": "10.0.0.2"}),
		_listing({"address": "10.0.0.3"}),
	], 1.0)
	var again := GameBrowser.merge(known, [_listing({"address": "10.0.0.1"})], 2.0)
	assert_eq(String((again[0] as Dictionary)["address"]), "10.0.0.1",
		"answering again does not send a game to the bottom")
	assert_eq(again.size(), 3)


# --- can this build join that game -------------------------------------

func test_a_matching_protocol_can_be_joined() -> void:
	assert_true(bool(GameBrowser.can_join(_listing({"protocol": 1}), 1)["ok"]))


func test_an_incompatible_build_is_greyed_out_before_the_join() -> void:
	# #187 asks for exactly this: grey it out BEFORE a doomed join rather
	# than have the handshake refuse after it (#179 is still the
	# authority; this only saves the trip).
	var newer := GameBrowser.can_join(_listing({"protocol": 2}), 1)
	assert_false(bool(newer["ok"]))
	assert_string_contains(String(newer["reason"]), "newer than yours")
	var older := GameBrowser.can_join(_listing({"protocol": 1}), 2)
	assert_false(bool(older["ok"]))
	assert_string_contains(String(older["reason"]), "older than yours")
	# Which way round it is matters to a player: one of them means
	# "update", the other means "wait for them to".


func test_a_game_that_said_nothing_about_its_protocol_is_not_offered() -> void:
	var entry := _listing()
	entry.erase("protocol")
	assert_false(bool(GameBrowser.can_join(entry, 1)["ok"]),
		"unknown is not the same as compatible")


func test_the_host_decides_whether_there_is_room() -> void:
	# Not the counts. A running match with drop-in seats is joinable
	# (D-089/D-090) and a lobby that filled is not, and only the host
	# knows which — a browser working it out from `players` and `seats`
	# would be reimplementing seating rules a network away from the seats.
	var full := GameBrowser.can_join(
		_listing({"joinable": false, "players": 4, "seats": 4}), 1)
	assert_false(bool(full["ok"]))
	assert_string_contains(String(full["reason"]), "full")
	var underway := GameBrowser.can_join(
		_listing({"joinable": false, "phase": "running"}), 1)
	assert_false(bool(underway["ok"]))
	assert_string_contains(String(underway["reason"]), "under way")
	var busy_but_open := GameBrowser.can_join(
		_listing({"joinable": true, "phase": "running", "players": 9, "seats": 4}), 1)
	assert_true(bool(busy_but_open["ok"]),
		"a running game that says it has room is offered, counts notwithstanding")


# --- what the menu draws -----------------------------------------------

func test_a_row_carries_the_endpoint_the_click_connects_to() -> void:
	var rows := GameBrowser.rows([_listing()], 1)
	assert_eq(rows.size(), 1)
	var row: Dictionary = rows[0]
	assert_eq(String(row["address"]), "192.168.1.5")
	assert_eq(int(row["port"]), 4433)
	assert_true(bool(row["joinable"]))
	assert_string_contains(String(row["detail"]), "1/4 players")
	assert_string_contains(String(row["detail"]), "continents")


func test_a_game_with_no_seats_yet_does_not_read_as_broken() -> void:
	# A server with no lobby has no seat list until somebody joins, so it
	# honestly reports 0 of 0 — which in a row reads as a fault rather
	# than as an empty game. Seen in the first real photograph of this
	# list, which is what pictures are for.
	var row: Dictionary = GameBrowser.rows([_listing({"players": 0, "seats": 0})], 1)[0]
	assert_string_contains(String(row["detail"]), "0 players")
	assert_false(String(row["detail"]).contains("0/0"))
	var one: Dictionary = GameBrowser.rows([_listing({"players": 1, "seats": 0})], 1)[0]
	assert_string_contains(String(one["detail"]), "1 player")


func test_a_running_game_says_so() -> void:
	var row: Dictionary = GameBrowser.rows([_listing({"phase": "running"})], 1)[0]
	assert_string_contains(String(row["detail"]), "in progress")


func test_an_unnamed_game_is_drawn_as_its_endpoint() -> void:
	# Rather than dropped, or drawn as a blank row nobody can press: an
	# unnamed game is still a game somebody can join.
	var row: Dictionary = GameBrowser.rows([_listing({"name": ""})], 1)[0]
	assert_eq(String(row["title"]), "192.168.1.5:4433")


func test_joinable_games_come_first() -> void:
	# The list exists to be clicked. Buried under three greyed rows, the
	# one game somebody can join is a list that failed at its job.
	var rows := GameBrowser.rows([
		_listing({"address": "10.0.0.1", "name": "Zed", "joinable": false}),
		_listing({"address": "10.0.0.2", "name": "Older", "protocol": 0}),
		_listing({"address": "10.0.0.3", "name": "Yours"}),
		_listing({"address": "10.0.0.4", "name": "Also yours"}),
	], 1)
	assert_true(bool((rows[0] as Dictionary)["joinable"]))
	assert_true(bool((rows[1] as Dictionary)["joinable"]))
	assert_eq(String((rows[0] as Dictionary)["title"]), "Also yours",
		"and joinable games are in a stable, readable order")
	assert_false(bool((rows[3] as Dictionary)["joinable"]))


func test_the_order_does_not_shuffle_between_refreshes() -> void:
	# Four games, all equal on every visible field but their endpoint.
	# A sort that fell back to dictionary order would reorder the list
	# under the cursor several times a second.
	var listings := []
	for i in range(4):
		listings.append(_listing({"address": "10.0.0.%d" % i, "name": "Game"}))
	var first := GameBrowser.rows(listings, 1)
	listings.reverse()
	var second := GameBrowser.rows(listings, 1)
	for i in range(4):
		assert_eq(String((first[i] as Dictionary)["id"]),
			String((second[i] as Dictionary)["id"]),
			"row %d is the same game whichever order the replies arrived" % i)


# --- the line above the list -------------------------------------------

func test_an_empty_list_says_which_kind_of_empty_it_is() -> void:
	# "No games found" and "I have not looked yet" are different facts,
	# and a list that is simply blank reads as broken — which is the
	# complaint #162 was filed about, one screen over.
	assert_string_contains(GameBrowser.summary([], true), "Looking")
	assert_string_contains(GameBrowser.summary([], false), "No games found")


func test_the_summary_counts_what_can_actually_be_joined() -> void:
	var rows := GameBrowser.rows([
		_listing({"address": "10.0.0.1"}),
		_listing({"address": "10.0.0.2", "protocol": 7}),
	], 1)
	var line := GameBrowser.summary(rows, true)
	assert_string_contains(line, "2 games")
	assert_string_contains(line, "1 joinable")
	assert_eq(GameBrowser.summary(GameBrowser.rows([_listing()], 1), true),
		"1 game on this network.", "and one game is not one games")


# --- the data comes off a socket ---------------------------------------

func test_a_listing_missing_every_field_still_draws() -> void:
	# This is not defensive programming for its own sake: the input is a
	# datagram from a machine nobody controls, and a browser that threw
	# on a missing key could be taken down by a stray packet.
	var rows := GameBrowser.rows([{}], 1)
	assert_eq(rows.size(), 1)
	var row: Dictionary = rows[0]
	assert_false(bool(row["joinable"]), "and it is not offered")
	assert_ne(String(row["title"]), "", "but it is drawn")


# --- the callers exist --------------------------------------------------
#
# D-106's rule, which this project has now paid for five times: every
# other check here can pass while nothing on screen ever calls any of it.
# A browser module with no caller is a game list that does not exist, and
# an announcer nobody polls is a game nobody can find.

func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func test_the_menu_draws_its_list_through_this_module() -> void:
	var client := _read("res://client.gd")
	assert_true(client.contains("GameBrowser.rows("),
		"the menu must take its rows from here, not decide them again where "
		+ "nothing can test them (D-061)")
	assert_true(client.contains("GameBrowser.merge(") and client.contains("GameBrowser.fresh("),
		"and merge and expire through here too, or a row outlives its host")
	assert_true(client.contains("GameBrowser.summary("),
		"including the line that says which kind of empty an empty list is")


func test_the_menu_polls_whatever_providers_it_has() -> void:
	var client := _read("res://client.gd")
	assert_true(client.contains("provider.poll(") and client.contains("provider.take_seen()"),
		"a provider nobody polls finds nothing")
	assert_true(client.contains("LanDiscovery.new()"),
		"the LAN provider is the one that works today and must be built")


func test_the_platform_provider_is_reached_by_path_not_by_name() -> void:
	# D-093/#181: exactly one script may NAME the platform, and the menu
	# is not it. `tests/test_steam_boundary.gd` is what enforces that;
	# this asserts the other half — that the menu asks for one at all,
	# rather than shipping a browser with one source for ever.
	var client := _read("res://client.gd")
	assert_true(client.contains('load("res://platform.gd")'),
		"the menu asks the boundary script for a provider")
	assert_true(client.contains("lobby_provider()"),
		"and adds it when there is one")


func test_the_server_answers_the_browsers() -> void:
	var server := _read("res://server.gd")
	assert_true(server.contains("LanBeacon.new()"), "the server has a beacon")
	assert_true(server.contains("_beacon.begin("), "it starts it")
	assert_true(server.contains("_beacon.poll()"),
		"and POLLS it — a beacon nobody polls answers nothing, which is this "
		+ "project's most-repeated defect wearing a green verdict")
	assert_true(server.contains("_beacon.stop()"),
		"and closes the socket on the way out")
