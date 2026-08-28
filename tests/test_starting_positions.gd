extends GutTest

## Guards D-20260817-starting-positions-follow-the-seats (#103) — the map
## is generated for the players who are in the lobby, and neither the
## number nor the seed is a control anybody has to answer.
##
## The rules live in `MatchState` for the reason that file's header gives:
## a rule is exactly the part worth testing, and a GUT test cannot stand up
## an ENet host. "Starting positions are not a setting" is a rule, not a UI
## state — so it is asserted on the server's own object, and the row's
## absence from the client is asserted against `client.gd`'s constant
## rather than a screenshot.


func _lobby() -> MatchState:
	var m := MatchState.new()
	m.require_admin_start = true
	m.civ_rng.seed = 42
	return m


func _slots(m: MatchState) -> int:
	return m.map_settings.player_slots


# --- the derivation ----------------------------------------------------

func test_starting_positions_follow_the_seat_count() -> void:
	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 1000)
	assert_eq(_slots(m), 2, "two seats, two starting positions")
	m.add_ai(1, CivRoster.RANDOM, 1001)
	assert_eq(_slots(m), 3, "seating an AI adds a start")
	m.add_player(2)
	assert_eq(_slots(m), 4, "so does a human joining")


func test_a_command_line_ai_seat_asks_for_a_start_too() -> void:
	# The OTHER door onto AI seating (D-20260817-an-ai-never-holds-the-
	# lobby): `--ai=N` seats its brains through `add_ai_player` before any
	# human connects, where the lobby's "Add AI player" button goes through
	# `add_ai`. Both are one `_seat_ai` underneath precisely so a rule like
	# this one cannot hold on a door somebody remembered and not on the
	# other — every test above uses the lobby door alone.
	var m := MatchState.new()
	m.require_admin_start = false
	m.players_expected = 4
	for i in range(3):
		m.add_ai_player(1000 + i, CivRoster.ids()[0])
	assert_eq(_slots(m), 3, "three command-line AI seats, three starting positions")

	m.add_player(1)
	assert_eq(_slots(m), 4, "and the human who joins them gets one")


func test_a_leaving_seat_gives_its_start_back() -> void:
	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 1000)
	m.add_ai(1, CivRoster.RANDOM, 1001)
	m.add_player(2)
	assert_eq(_slots(m), 4, "Setup: four seats")

	assert_true(m.remove_ai(1, 1), "Setup: the admin may unseat an AI")
	assert_eq(_slots(m), 3, "unseating an AI drops a start")

	m.remove_human_seat(2)
	assert_eq(_slots(m), 2, "a human disconnecting in the lobby drops one too")


func test_a_lobby_of_one_still_asks_for_two_starts() -> void:
	# `MapSettings.validate` refuses fewer than two, and a one-seat lobby
	# is an ordinary state on the way to a match rather than an error. The
	# floor is why this is a clamp and not an assignment.
	var m := _lobby()
	m.add_player(1)
	assert_eq(m.seats.size(), 1, "Setup: one seat")
	assert_eq(_slots(m), MatchState.MIN_PLAYER_SLOTS,
		"one seat still generates a map two players could start on")
	assert_true(m.map_settings.is_valid(),
		"and the settings it leaves behind must be generateable")


func test_the_map_a_lobby_generates_has_a_start_per_seat() -> void:
	# The mechanism being right says nothing about whether the shipped
	# numbers do anything (D-066), so this walks the real derivation the
	# server and the lobby preview both use (D-104) and counts what comes
	# out on a real map.
	var m := _lobby()
	m.add_player(1)
	for i in range(3):
		m.add_ai(1, CivRoster.RANDOM, 1000 + i)
	assert_eq(m.seats.size(), 4, "Setup: four seats")

	var settings := m.map_settings
	var config := settings.to_spawn_config()
	assert_eq(config.player_slots, 4, "the spawn config carries the seat count")
	var points := config.spawn_points(settings.to_terrain().passability(settings.to_space()))
	assert_eq(points.size(), 4,
		"four seats should get four starting positions, not the map's old default")


# --- what is no longer a control ---------------------------------------

func test_starting_positions_cannot_be_set_by_hand() -> void:
	# A setter here would be a knob whose value the next join silently
	# overwrote — the declared-and-unread family with the reads and writes
	# swapped, and the reason the option is gone rather than merely hidden.
	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 1000)
	assert_false(m.set_map_option(1, "player_slots", 12.0),
		"the server must refuse a setting that no longer exists")
	assert_eq(_slots(m), 2, "and must not have applied it on the way")


func test_the_lobby_offers_neither_a_slots_row_nor_a_seed_row() -> void:
	# Against `client.gd`'s own constant, not a screenshot: the client
	# needs a GPU (D-014), the list of rows it builds does not.
	var options: Array = load("res://client.gd").get_script_constant_map()["MAP_OPTIONS"]
	var keys: Array = []
	for option in options:
		keys.append(String(option["key"]))
	assert_false(keys.has("player_slots"),
		"starting positions are derived from the seats — there is nothing to show")
	assert_false(keys.has("seed"),
		"the seed number is a dev handle (--seed), not a lobby control")
	assert_true(keys.has(MatchState.REROLL_OPTION),
		"asking for a DIFFERENT map is still a thing a player wants")


func test_the_seed_is_still_pinnable_by_the_server_that_owns_it() -> void:
	# The row went; the mechanism did not. `--seed` and the replay path
	# (D-100) still pin, and removing the option here would have taken
	# them with it.
	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 1000)
	assert_true(m.set_map_option(1, "seed", 4242.0), "the server may still pin a seed")
	assert_eq(m.map_settings.seed, 4242, "and it takes")


# --- the derivation cannot be forgotten at a future seat site ----------

func test_every_seat_mutation_re_derives_the_starting_positions() -> void:
	# The one thing the behavioural tests above cannot cover: a FIFTH
	# place that appends to `seats`, added later, with no sync beside it.
	# Nothing would fail — the lobby would simply generate a map for the
	# wrong number of players, which is the shape of every defect
	# CLAUDE.md's "grep for uncalled members" rule is about.
	var source := FileAccess.get_file_as_string("res://match_state.gd")
	assert_ne(source, "", "Setup: match_state.gd should be readable")

	# CODE lines only. Counting raw occurrences let a COMMENT mentioning
	# `_seats_changed()` stand in for a call — so a fifth mutation site
	# added alongside a sentence about the rule would satisfy this guard
	# while the defect it exists for was live. That is the vacuous pass
	# D-022's audit block is about, in the guard rather than in the code.
	var mutations := 0
	var syncs := 0
	for raw in source.split("
"):
		var line := String(raw).strip_edges()
		if line.begins_with("#"):
			continue
		mutations += line.count("seats.append(") + line.count("seats.remove_at(")
		syncs += line.count("_seats_changed()")
	# One of these is the declaration, which is not a call site.
	syncs -= 1
	assert_eq(syncs, mutations,
		"every site that adds or removes a seat must re-derive the starting positions")
