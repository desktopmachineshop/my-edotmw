extends GutTest

## Guards #180 and
## `decisions/D-20260827-a-client-starts-before-it-connects.md`: the
## client has a state in which it is NOT connected, and every way a
## session ends short of quitting lands there with a message.
##
## Two halves, and the second is the one that has broken silently before.
##
## The ARITHMETIC — which endpoint a launch means, how a typed address
## parses, what the title says — is `main_menu.gd`, all-static and pure,
## driven directly. The autoconnect rule in particular is the kind that
## is wrong in a way nothing notices: get it backwards and the menu
## appears in front of `just test-client` and photographs itself, or
## never appears at all and the whole feature is absent while every test
## stays green.
##
## The LIFETIME is `client.gd`, instantiated and NEVER ADDED TO THE TREE
## so `_ready()` does not run — the technique D-075's 2026-08-16
## amendment established, and it exists because that is exactly where
## this client breaks quietly: `_terrain_root` was built in `_ready()`
## and freed by `_teardown_match()`, so every match after the first
## rendered squads and forests standing on nothing, for a milestone, with
## every counter green.


# --- which endpoint a launch means -------------------------------------

func test_a_bare_launch_shows_the_menu() -> void:
	# The exported build, double-clicked. This is the entire reason the
	# screen exists: before it, a tester who installed a build had no way
	# to reach a server at all.
	var target := MainMenu.autoconnect({}, "", "127.0.0.1", 4433)
	assert_false(bool(target["connect"]), "a launch with no arguments must stop at the menu")


func test_the_recipes_still_connect_unattended() -> void:
	# #180's own condition. `just run-client` and `just test-client` pass
	# --address and --port; a menu in front of either is a recipe that
	# hangs or a screenshot of a menu.
	assert_true(bool(MainMenu.autoconnect({"address": "127.0.0.1", "port": "24395"},
		"", "127.0.0.1", 4433)["connect"]), "--address must connect straight away")
	assert_true(bool(MainMenu.autoconnect({"port": "24395"}, "", "127.0.0.1", 4433)["connect"]),
		"--port alone must connect straight away")
	# Capture mode on its own: a headless screenshot has nobody to press
	# Join, and the menu would be the thing photographed.
	assert_true(bool(MainMenu.autoconnect({"run-seconds": "90"}, "", "127.0.0.1", 4433)["connect"]),
		"capture mode must never stop at the menu")
	# Inside the compose network the server is a hostname, and that env
	# var is how test-client reaches it.
	assert_true(bool(MainMenu.autoconnect({}, "server", "127.0.0.1", 4433)["connect"]),
		"EDOTMW_SERVER_ADDRESS must count as being pointed at a server")


func test_the_menu_can_be_forced_for_the_instrument_that_photographs_it() -> void:
	# `just menu-shot` needs capture mode without capture mode's
	# autoconnect. It is spelled `--menu=1` and not `--menu`, because
	# CmdArgs only records `--key=value` and silently drops the rest —
	# the bare version rendered a menu carrying "could not reach
	# server:4433" and every check passed.
	assert_false(bool(MainMenu.autoconnect({"menu": "1", "run-seconds": "4"},
		"server", "127.0.0.1", 4433)["connect"]),
		"--menu=1 must beat both capture mode and the env address")
	assert_true(bool(MainMenu.autoconnect({"menu": "0", "run-seconds": "4"},
		"", "127.0.0.1", 4433)["connect"]),
		"--menu=0 is not a request for the menu")


func test_the_rule_is_asked_for_not_defaulted() -> void:
	# The trap this whole function exists to avoid: --address has
	# DEFAULTED to 127.0.0.1 since client.gd existed, so a rule reading
	# the resolved value would autoconnect every launch and the menu
	# would be unreachable — a feature that is entirely absent while
	# nothing fails.
	var bare := MainMenu.autoconnect({}, "", "127.0.0.1", 4433)
	assert_false(bool(bare["connect"]))
	assert_eq(String(bare["address"]), "127.0.0.1",
		"the default is still what Join starts from, it just does not fire on its own")
	assert_eq(int(bare["port"]), 4433)


func test_the_env_address_wins_over_the_default() -> void:
	var target := MainMenu.autoconnect({}, "server", "127.0.0.1", 4433)
	assert_eq(String(target["address"]), "server")


func test_an_explicit_address_wins_over_the_env() -> void:
	var target := MainMenu.autoconnect({"address": "10.0.0.2"}, "server", "127.0.0.1", 4433)
	assert_eq(String(target["address"]), "10.0.0.2")


# --- what a player types -----------------------------------------------

func test_a_bare_host_takes_the_default_port() -> void:
	var parsed := MainMenu.parse_endpoint("example.com", 4433)
	assert_true(bool(parsed["ok"]), String(parsed["error"]))
	assert_eq(String(parsed["address"]), "example.com")
	assert_eq(int(parsed["port"]), 4433)


func test_host_and_port() -> void:
	var parsed := MainMenu.parse_endpoint("  127.0.0.1:24395  ", 4433)
	assert_true(bool(parsed["ok"]), String(parsed["error"]))
	assert_eq(String(parsed["address"]), "127.0.0.1")
	assert_eq(int(parsed["port"]), 24395)


func test_a_port_that_is_not_a_number_is_refused_rather_than_stripped() -> void:
	# GDScript's int() STRIPS non-digits rather than failing, so
	# "24395x" would otherwise be a plausible, entirely wrong port and
	# nothing would say so — D-20260817-recipe-args-are-positional's
	# whole lesson, arriving through a text box this time.
	var parsed := MainMenu.parse_endpoint("127.0.0.1:24395x", 4433)
	assert_false(bool(parsed["ok"]), "a port with letters in it is not a port")
	assert_false(String(parsed["error"]).is_empty(), "and the player must be told why")


func test_a_port_outside_the_range_is_refused() -> void:
	assert_false(bool(MainMenu.parse_endpoint("127.0.0.1:0", 4433)["ok"]))
	assert_false(bool(MainMenu.parse_endpoint("127.0.0.1:70000", 4433)["ok"]))


func test_an_empty_box_says_what_to_type() -> void:
	var parsed := MainMenu.parse_endpoint("   ", 4433)
	assert_false(bool(parsed["ok"]))
	assert_true(String(parsed["error"]).contains("4433"),
		"the message must show the shape of an answer: %s" % parsed["error"])


func test_a_bare_ipv6_literal_is_not_cut_at_its_last_colon() -> void:
	# An IPv6 address is mostly colons. Splitting from the right
	# unconditionally turns "::1" into host "::" port "1" — a plausible
	# and entirely wrong endpoint, which is the same failure as the
	# stripped port above wearing a different hat.
	var parsed := MainMenu.parse_endpoint("::1", 4433)
	assert_true(bool(parsed["ok"]), String(parsed["error"]))
	assert_eq(String(parsed["address"]), "::1")
	assert_eq(int(parsed["port"]), 4433)


func test_a_bracketed_ipv6_can_carry_a_port() -> void:
	var parsed := MainMenu.parse_endpoint("[::1]:24395", 4433)
	assert_true(bool(parsed["ok"]), String(parsed["error"]))
	assert_eq(String(parsed["address"]), "::1")
	assert_eq(int(parsed["port"]), 24395)

	var no_port := MainMenu.parse_endpoint("[fe80::1]", 4433)
	assert_true(bool(no_port["ok"]), String(no_port["error"]))
	assert_eq(String(no_port["address"]), "fe80::1")
	assert_eq(int(no_port["port"]), 4433)


func test_a_malformed_bracket_is_refused_rather_than_guessed() -> void:
	assert_false(bool(MainMenu.parse_endpoint("[::1", 4433)["ok"]))
	assert_false(bool(MainMenu.parse_endpoint("[]:24395", 4433)["ok"]))
	assert_false(bool(MainMenu.parse_endpoint("[::1]24395", 4433)["ok"]))
	assert_false(bool(MainMenu.parse_endpoint(":24395", 4433)["ok"]))


func test_what_is_remembered_always_carries_a_port() -> void:
	# An address remembered without one reconnects somewhere else the day
	# the port changes, and D-095 gives every worktree its own.
	assert_eq(MainMenu.format_endpoint("127.0.0.1", 24395), "127.0.0.1:24395")
	assert_eq(MainMenu.format_endpoint("::1", 24395), "[::1]:24395")
	# And it round-trips: what the menu writes down, the menu can read.
	var again := MainMenu.parse_endpoint(MainMenu.format_endpoint("::1", 24395), 4433)
	assert_true(bool(again["ok"]), String(again["error"]))
	assert_eq(String(again["address"]), "::1")
	assert_eq(int(again["port"]), 24395)


func test_the_default_port_agrees_with_the_client() -> void:
	# Two constants for one number is the drift this project keeps
	# paying for. main_menu.gd keeps its own so the file loads on its
	# own; this is what stops them disagreeing.
	var client_script := load("res://client.gd") as GDScript
	assert_eq(MainMenu.DEFAULT_PORT,
		int(client_script.get_script_constant_map()["DEFAULT_SERVER_PORT"]),
		"the menu and the client must mean the same port by a bare hostname")


func test_the_title_says_which_instance_and_whether_it_is_connected() -> void:
	# D-095: several agents run clients on one desktop, and the title is
	# how the human tells two identical windows apart. "not connected" is
	# the new half — before #180 there was no such state to name.
	var connected := MainMenu.window_title("claude-79", "127.0.0.1:24395")
	assert_true(connected.contains("claude-79"), connected)
	assert_true(connected.contains("127.0.0.1:24395"), connected)
	var idle := MainMenu.window_title("claude-79", "")
	assert_true(idle.contains("not connected"), idle)
	assert_false(MainMenu.window_title("", "127.0.0.1:1").contains("—"),
		"no instance means no dash")


# --- the client's lifetime ---------------------------------------------

func _client() -> Node:
	# NEVER added to the tree: `_ready()` opens a socket and builds the
	# whole HUD. Everything below is lifetime, which needs neither.
	return autofree(load("res://client.gd").new())


## The same, already told about a world — the shape
## `tests/test_return_to_lobby.gd` established, because `_build_terrain()`
## draws nothing without the replicated MapSettings D-049 puts on the
## wire, and a fixture that skipped them would assert against a client
## that had simply not been asked to build anything.
func _client_with_a_map() -> Node:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(
		1, 16, 8, PackedInt32Array([0, 1]), [], 40, 0))
	var settings := MapSettings.new()
	settings.width = 16
	settings.height = 8
	settings.seed = 7
	state.handle_packet(NetProtocol.encode_map_settings(settings.to_dict()))
	assert_true(state.has_map(), "Setup: the client must have the map settings (D-049)")
	var client := _client()
	client._state = state
	return client


func test_the_menu_is_built_and_shown_without_a_connection() -> void:
	var client := _client()
	client._build_main_menu()
	assert_not_null(client._menu_layer, "the menu must build itself, not inherit one from _ready()")
	assert_false(client._menu_layer.visible, "and start hidden — _ready() decides")
	client._show_main_menu("Refused: your build is too old.")
	assert_true(client._menu_layer.visible)
	assert_eq(client._menu_status.text, "Refused: your build is too old.",
		"the reason a player is looking at this screen must be ON it")


func test_returning_to_the_menu_tears_the_world_down_and_can_build_another() -> void:
	# The D-075 amendment's bug class, one door further out: a second
	# CONNECTION must be able to build a world, exactly as a second match
	# must. Nothing about that needs a GPU.
	var client := _client_with_a_map()
	client._build_main_menu()
	client._build_terrain()
	assert_not_null(client._terrain_root, "Setup: a world was built")
	client._in_match = true

	client._return_to_menu("The server closed the connection.")

	assert_null(client._terrain_root, "the world must go with the connection")
	assert_false(client._in_match)
	assert_true(client._menu_layer.visible, "and the menu is where a player lands")
	assert_eq(client._menu_status.text, "The server closed the connection.")

	# A SECOND connection, told about its own world exactly as the first
	# was — `_return_to_menu` drops everything the last server said, which
	# is the point, so the client has to be welcomed again before it can
	# draw anything.
	client._state.handle_packet(NetProtocol.encode_welcome(
		1, 16, 8, PackedInt32Array([0, 1]), [], 40, 0))
	var settings := MapSettings.new()
	settings.width = 16
	settings.height = 8
	settings.seed = 9
	client._state.handle_packet(NetProtocol.encode_map_settings(settings.to_dict()))
	assert_false(client._terrain_built, "Setup: the client knows it owes itself a terrain")

	client._build_terrain()
	assert_not_null(client._terrain_root,
		"a second connection must be able to build a world (D-075's amendment)")


func test_a_disconnect_forgets_the_ever_revealed_buildings() -> void:
	# The trap `docs/status/sandbox.md` records: `_return_to_lobby`
	# dropped the visible baseline and NOT `known_buildings`, and a
	# playtest reported 106 building desyncs in 55,239 checks. D-030's
	# ever-revealed set is what the server hashes, and the next server's
	# building ids start at 0.
	var state := ClientState.new()
	state.buildings[7] = {"owner": 1, "destroyed": false}
	state.player = 3
	state.lobby = {"seats": [{"player": 3}]}
	state.chat_log = ["hello"]
	state.refusal = {"reason": 1}
	state.welcomed = true

	state.disconnected()

	assert_eq(state.buildings.size(), 0,
		"the ever-revealed building set must not cross a disconnect")
	assert_eq(state.player, -1, "nor this client's player number")
	assert_eq(state.lobby.size(), 0, "nor the seat list")
	assert_eq(state.chat_log.size(), 0, "nor the chat")
	assert_eq(state.refusal.size(), 0, "nor a refusal that has been acted on")
	assert_false(state.welcomed)


func test_a_disconnect_keeps_the_session_counters() -> void:
	# Deliberate: `desync_summary()` is printed once when the PROCESS
	# ends, and a session that played on two servers should report what
	# the session did rather than what its last connection did.
	var state := ClientState.new()
	state.desync_count = 2
	state.state_hash_checks = 90
	state.disconnected()
	assert_eq(state.desync_count, 2)
	assert_eq(state.state_hash_checks, 90)


func test_the_refusal_lands_on_the_menu_rather_than_a_screen_of_its_own() -> void:
	# #179 shipped a refusal screen with a Quit button because there was
	# nowhere else for the message to go, and said in its own decision
	# entry that the menu was where it belonged. This is that.
	var source := _read("res://client.gd")
	assert_true(source.contains("_return_to_menu(text)"),
		"a refusal must send the player to the menu, with the address still in the box")
	assert_false(source.contains("func _build_refusal_screen("),
		"and the standalone refusal screen goes with it — two destinations drift")


func test_a_doomed_connection_ends_rather_than_hanging() -> void:
	# ENet never reports "there is nothing at that address"; it stays
	# silent. Without a deadline a typo is a client that sits forever
	# showing nothing, which is exactly how #162 was reported.
	var client := _client()
	client._build_main_menu()
	client._connect_started_at = 0.0
	client._wall_now = 1.0
	client._check_connect_timeout()
	assert_false(client._menu_layer.visible, "still inside the window, still trying")

	client._wall_now = client.CONNECT_TIMEOUT_SECONDS + 1.0
	client._check_connect_timeout()
	assert_true(client._menu_layer.visible, "past the deadline, the player is told")
	assert_true(client._menu_status.text.to_lower().contains("no answer"),
		"and told what happened: %s" % client._menu_status.text)


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text
