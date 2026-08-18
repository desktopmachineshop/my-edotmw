extends GutTest

## Guards D-20260818-server-memory-is-quoted-with-its-conditions (#111):
## the server's memory figure must carry the conditions it was taken
## under — players, squads and CELLS — the way this project has always
## quoted us/squad with a squad count.
##
## The number that prompted it: `mem=43.3 MB` on the new default map with
## FOUR squads alive, against M4's 42.5 MB at 120 squads on a map a
## quarter the size. Printed bare, those two read as "memory is flat";
## printed with their conditions they say the map now dominates and the
## armies do not. Nothing failed, and nothing could — the line was
## correct, it just could not be compared with anything.
##
## server.gd is a Node but needs no scene tree for this, so it is
## instantiated directly and its state set by hand, exactly as
## test_buildings.gd does for `_is_buildable`.


func _server_with(squads: int, width: int, height: int) -> Node:
	var space := TorusSpace.new(width, height, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var roster := UnitRoster.load_all()
	for i in range(squads):
		sim.add_squad(roster[0], 1, Vector2i(i * 2, 2))
	var server = load("res://server.gd").new()
	server._sim = sim
	return server


func test_a_memory_figure_names_its_players_squads_and_cells() -> void:
	var server := _server_with(7, 84, 96)
	server._peak_clients = 20

	# Bytes in, mebibytes out — the unit every other figure in this
	# project's logs is quoted in.
	var line: String = server._memory_line(43 * 1048576, 45 * 1048576)

	assert_true(line.contains("43.0 MB"),
		"the static figure itself must survive: %s" % line)
	assert_true(line.contains("20 player"),
		"a memory figure without its player count is D-018's target unmeasured: %s" % line)
	assert_true(line.contains("7 squad"),
		"and without its squad count it cannot be compared with M4's 42.5 MB at 120: %s" % line)
	assert_true(line.contains("8064 cells") and line.contains("84x96"),
		"the map is now the dominant allocator, so its size is a condition too: %s" % line)
	server.free()


func test_the_marker_is_structured_and_the_peak_is_reported() -> void:
	# A structured key the log scans can find, never prose containing a
	# scary word — the standing rule the load test's verdict follows.
	var server := _server_with(3, 168, 194)
	var line: String = server._memory_line(43 * 1048576, 61 * 1048576 + 838861)

	assert_true(line.begins_with("server: MEMORY "),
		"the line needs a marker a recipe can grep for: %s" % line)
	assert_true(line.contains("61.8 MB peak"),
		"peak matters as much as final: a match that spiked and freed is not a match that never spiked: %s" % line)
	assert_true(line.contains("32592 cells"),
		"the default map's own cell count, from the sim's space rather than a constant: %s" % line)
	server.free()


func test_the_player_count_is_a_peak_not_whoever_is_still_connected() -> void:
	# The bandwidth line learned this the hard way — a twenty-player run
	# reported "11 B/client/s over 1 client(s)" because the summary prints
	# when the LAST client leaves. Memory is printed from the same place
	# and would report "1 player" for the same reason.
	var server := _server_with(5, 84, 96)
	server._peak_clients = 20
	server._clients = {}

	var line: String = server._memory_line(10_000_000, 10_000_000)
	assert_true(line.contains("20 player"),
		"peak players, not the zero still connected at shutdown: %s" % line)
	server.free()


func test_an_all_ai_server_reports_its_seats() -> void:
	# `just ai-ladder` runs `--players=0`, so `_peak_clients` is 0 and the
	# only participants are seats with no socket (D-051). A memory line
	# saying "0 players" there would be true of the sockets and false of
	# everything anyone wants to know.
	var server := _server_with(4, 84, 96)
	var match_state := MatchState.new()
	match_state.players_expected = 4
	match_state.add_ai_player(1, &"legion")
	match_state.add_ai_player(2, &"northmen")
	server._match = match_state

	var line: String = server._memory_line(10_000_000, 10_000_000)
	assert_true(line.contains("2 player"),
		"AI seats are players for every purpose except owning a socket: %s" % line)
	server.free()


func test_the_summary_actually_prints_it() -> void:
	# The "assert the caller exists" check (D-106). Every other assertion
	# here can pass while nothing ever prints the line — which is this
	# project's oldest defect family, and the exact shape #111 is about:
	# a correct mechanism nobody reads.
	var source := FileAccess.get_file_as_string("res://server.gd")
	assert_true(source.contains("_print_summary"),
		"setup: server.gd should still have a summary printer")
	# Deliberately `print(_memory_line(` and not just the name: a doc
	# comment mentioning the function would satisfy a looser scan, and a
	# check that its own documentation can pass is no check at all.
	assert_gt(source.count("print(_memory_line("), 0,
		"_memory_line is defined and never printed — the summary must print it")
