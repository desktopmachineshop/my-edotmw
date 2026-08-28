extends GutTest

## Guards that a world is generated for the players who will be IN it,
## on the `--lobby=0` path too (#276).
##
## `D-20260817-starting-positions-follow-the-seats` (#103) made
## `MapSettings.player_slots` a DERIVED value: *"a map is generated for
## the players who are actually in the lobby, not for a number somebody
## set."* That held on the lobby path and not on `--lobby=0` — which is
## the path `just ai-ladder`, `just quick-test` and `just run-server N`
## all use.
##
## `server._ready()` called `_build_world()` and sampled the spawn points
## from the map file's AUTHORED `player_slots`; the `--ai=N` seating loop
## ran afterwards, and `_seats_changed()` then updated `player_slots` on
## the same object — after the world built from it. So the seats never
## reached the generator, and any seat past the authored count was placed
## on another seat's start by `MatchState.spawn_index_in`'s
## `index % point_count`.
##
## Measured in #276: `just ai-ladder 3 600 6 0` on `maps/ladder.tres`
## (authored `player_slots` 4) logged *"4 spawn points"* for six players,
## with **no warning**. Seats 4 and 5 landed on seats 0 and 1.
##
## `server.gd` is driven here WITHOUT a scene tree — a Node that is never
## added does not run `_ready()`, so its socket is never opened. Same
## discipline as `test_civ_knobs.gd`, and the same correction D-075's
## amendment had to make for `client.gd`: "needs a socket and a scene
## tree" is true of `_ready()`, not of the file.

const SMALL_SLOTS := 4


func _settings_for(slots: int) -> MapSettings:
	var s := MapSettings.new()
	s.width = 42
	s.height = 48
	s.player_slots = slots
	s.seed = 1
	return s


## A server instance that has NOT been added to the tree, so `_ready()`
## has not run and nothing is listening on a socket.
func _server(expected: int, slots: int):
	var script: GDScript = load("res://server.gd")
	var server = script.new()
	server._settings = _settings_for(slots)
	# `_build_world` reads the MapConfig for the resource fairness pass
	# (D-104); a default one is all this fixture needs.
	server._config = MapConfig.new()
	server._match = MatchState.new()
	server._match.map_settings = server._settings
	server._match.players_expected = expected
	return server


func test_a_lobbyless_world_has_a_start_for_every_expected_seat() -> void:
	# THE defect. Six expected players against a map authored for four.
	var server = _server(6, SMALL_SLOTS)
	assert_eq(server._settings.player_slots, SMALL_SLOTS,
		"setup: the map is authored for %d" % SMALL_SLOTS)

	server._build_world()
	var points: int = server._spawn_points.size()
	server.free()

	assert_gte(points, 6,
		("a world built for 6 expected players produced %d starting positions — "
		+ "seats past that share another seat's start by spawn_index_in's modulo") % points)


func test_two_seats_never_share_a_start() -> void:
	# The consequence, stated as the thing a player would notice, rather
	# than as a count. This is what "4 spawn points, 6 players" MEANS.
	var server = _server(6, SMALL_SLOTS)
	server._build_world()
	var points: int = server._spawn_points.size()
	var used := {}
	var shared := []
	for seat in range(6):
		var index := MatchState.spawn_index_in([], seat + 1, points)
		if used.has(index):
			shared.append("seat %d shares seat %d's start" % [seat, used[index]])
		used[index] = seat
	server.free()
	assert_eq(shared.size(), 0, str(shared))


func test_the_authored_count_is_still_a_floor_not_a_ceiling() -> void:
	# A map authored for MORE starts than there are players must keep
	# them: `player_slots` is what the map asks for, and a single-player
	# dev run must not regenerate the shipped map into a two-start one.
	var server = _server(2, 8)
	server._build_world()
	var points: int = server._spawn_points.size()
	server.free()
	assert_gte(points, 8,
		"a map authored for 8 starts kept %d — the derivation must not SHRINK it" % points)


func test_ensure_seats_fit_never_shrinks_below_what_is_seated() -> void:
	# The two rules share their mechanics but not their contract:
	# `_seats_changed()` is EXACT (a leaving seat gives its start back,
	# D-20260817) while this one only RAISES. Neither may undercut the
	# other.
	var match_state := MatchState.new()
	match_state.map_settings = _settings_for(SMALL_SLOTS)
	match_state.add_player(1)
	match_state.add_player(2)
	match_state.add_player(3)
	var seated := match_state.seats.size()
	assert_gt(seated, 0, "setup: somebody is seated")

	# A smaller expectation must not undercut the people actually there.
	match_state.ensure_seats_fit(1)
	assert_gte(match_state.map_settings.player_slots, seated,
		"ensure_seats_fit(1) dropped the map below the %d seats that exist" % seated)


func test_ensure_seats_fit_respects_the_bounds() -> void:
	var match_state := MatchState.new()
	match_state.map_settings = _settings_for(SMALL_SLOTS)
	match_state.ensure_seats_fit(1000)
	assert_lte(match_state.map_settings.player_slots, MatchState.MAX_PLAYER_SLOTS,
		"a map has at most %d starts" % MatchState.MAX_PLAYER_SLOTS)
	match_state.ensure_seats_fit(0)
	assert_gte(match_state.map_settings.player_slots, MatchState.MIN_PLAYER_SLOTS,
		"and at least %d" % MatchState.MIN_PLAYER_SLOTS)
