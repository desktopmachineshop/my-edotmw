extends GutTest

## Guards #182 and D-088: the host runs the authoritative server inside
## its own client, reached through the loopback peer D-051's AI seats
## already use.
##
## **What this file proves and what it cannot.** The seam is here — the
## third client dictionary, the peer that is not a socket, the D-075 rule
## that must not end a host's process. Those are drivable without a tree,
## by the technique `test_civ_knobs.gd` and `test_handshake.gd` use:
## instantiate `server.gd` and never add it, so `_ready()` (which binds a
## socket and generates a world) does not run.
##
## What that CANNOT show is the two halves agreeing in a real match, and
## nothing in a unit test can. `just test-host` does: a real hosting
## client, headless, with real bots joining it over a real socket, and
## the state-hash machinery read on both sides. This file is the fast
## half; that recipe is the one that would notice.


func _server() -> Object:
	return load("res://server.gd").new()


## A server with just enough state to seat somebody, in the shape
## `_ready()` would have left it — the lobby phase, because that is where
## a host lands and where `seat_local_client` is called from.
func _lobby_server() -> Object:
	var server := _server()
	server._sim = SquadSim.new(TorusSpace.new(16, 8, 1.0), CurveReplicator.new())
	server._match = MatchState.new()
	server._match.require_admin_start = true
	server._settings = server._match.map_settings
	var no_spawns: Array[Vector2i] = []
	server._spawn_points = no_spawns
	return server


# --- the peer that is not a socket -------------------------------------

func test_the_host_is_seated_through_the_loopback_not_a_socket() -> void:
	var server := _lobby_server()
	var state := ClientState.new()
	var link: Variant = server.seat_local_client(state)
	server._seat_pending_local_player()

	assert_not_null(link, "seating must hand back the object orders travel through")
	assert_eq(server._local_clients.size(), 1, "the host is a client of its own server")
	assert_eq(server._clients.size(), 0,
		"and NOT in _clients — several places there cast a peer to ENetPacketPeer")
	assert_eq(server._ai_clients.size(), 0,
		"nor in _ai_clients — the host is a human, and calling it an AI is a lie")
	server.free()


func test_the_host_receives_state_like_anybody_else() -> void:
	# D-051's guarantee, extended: one definition of who "everybody" is.
	# `_recipients()` is that definition, and a host missing from it would
	# be a player whose own world never updates.
	var server := _lobby_server()
	var state := ClientState.new()
	server.seat_local_client(state)
	server._seat_pending_local_player()
	assert_eq(server._recipients().size(), 1,
		"the host must be among the peers that receive simulation state")
	server.free()


func test_the_host_is_welcomed_into_the_lobby() -> void:
	var server := _lobby_server()
	var state := ClientState.new()
	server.seat_local_client(state)
	server._seat_pending_local_player()
	# Delivery is synchronous through the loopback, so the client's own
	# state is already true by the time seating returns.
	assert_true(state.welcomed, "the host must be welcomed, or it never leaves the menu")
	assert_eq(state.player, 1, "and know which player it is")
	assert_true(state.is_admin(),
		"the host holds the lobby: it is their match, and nobody else can start it")
	server.free()


func test_the_host_is_found_by_player_id() -> void:
	# `_peer_of` used to be declared `-> ENetPacketPeer`, which would have
	# made the host the one player `_on_match_started` cannot admit — and
	# it would have done it by returning NULL, so the symptom would have
	# been a host who starts a match and is not in it.
	var server := _lobby_server()
	server.seat_local_client(ClientState.new())
	server._seat_pending_local_player()
	assert_not_null(server._peer_of(1), "the host's peer must be findable by player id")
	assert_null(server._peer_of(99), "and an absent player still answers null")
	server.free()


func test_the_hosts_orders_take_the_same_path_a_guests_do() -> void:
	# The whole reason the link is duck-typed to ENetPacketPeer.send: the
	# ~30 ordering sites in client.gd are the same code either way, so a
	# host cannot be handed a rule a guest does not have. Here the order
	# is REFUSED — there is no such squad — and being refused through the
	# ordinary dispatcher is exactly the point.
	var server := _lobby_server()
	var state := ClientState.new()
	var link: Variant = server.seat_local_client(state)
	server._seat_pending_local_player()
	# A chat message: it reaches a handler, needs no simulation, and its
	# effect is observable on the sender's own ClientState.
	link.send(0, NetProtocol.encode_chat_send("hello from the host"), 0)
	assert_gt(state.chat_log.size(), 0,
		"an order sent through the host link must reach the server's dispatcher")
	server.free()


# --- the rule that must not end a host's process -----------------------

func test_a_remote_client_leaving_does_not_end_an_embedded_server() -> void:
	# D-075 ends a server when the last human client leaves, and the host
	# is not in `_clients` — so without the embedded guard the rule reads
	# "everybody left" the moment the last REMOTE player disconnects, and
	# quits the host's own game underneath them.
	var server := _lobby_server()
	server._embedded = true
	server.seat_local_client(ClientState.new())
	server._seat_pending_local_player()

	var remote := RefCounted.new()
	server._clients[remote] = {"player": 2, "visible": {}}
	server._on_disconnect(remote)

	assert_false(server._shutting_down,
		"the host is still playing — a remote player leaving is not everybody leaving")
	assert_eq(server._local_clients.size(), 1, "and the host is still seated")
	server.free()


func test_a_dedicated_server_still_ends_when_everybody_leaves() -> void:
	# The other half, and the reason the guard is on `_embedded` rather
	# than on "is there a local client": D-075 exists because an all-AI
	# server held a port for six hours, and un-fixing it here would be a
	# silent regression in the docker estate.
	var server := _lobby_server()
	assert_false(server._embedded, "Setup: a dedicated server is not embedded")
	assert_eq(server._local_clients.size(), 0, "Setup: and has no local client")
	# Not driven through `_on_disconnect`, which calls `get_tree().quit()`
	# on this path and would take the test runner with it. The guard is
	# what is under test, and it is readable in the source.
	var source := _read("res://server.gd")
	assert_true(source.contains("if _embedded:"),
		"the no-humans-no-server rule must be gated on _embedded, not removed")
	assert_true(source.contains("last human client left — shutting down"),
		"and must still fire for a dedicated server (D-075)")
	server.free()


# --- one simulation, not two -------------------------------------------

func test_there_is_no_second_server_implementation() -> void:
	# #182's own first condition. A host-only variant would be `just
	# profile`'s blind spot with a new name: a workload with its own bugs,
	# green while the shipped one is broken.
	var client := _read("res://client.gd")
	assert_true(client.contains('load("res://server.gd")'),
		"the host must run the SAME server.gd the dedicated build runs")
	assert_true(client.contains("seat_local_client("),
		"and join it through the seating API rather than reaching into it")


func test_an_embedded_server_is_configured_by_its_client_not_the_command_line() -> void:
	# The client's own arguments are not the server's, and one of them
	# overlaps outright: `--port` means "connect to" on a client and
	# "bind" on a server, so a host launched to join port N would have
	# silently bound N instead.
	var source := _read("res://server.gd")
	assert_true(source.contains("var args := boot if _embedded else CmdArgs.parse("),
		"an embedded server must read `boot`, never the process command line")
	var client := _read("res://client.gd")
	assert_true(client.contains("server.boot = {"),
		"and the client must be the thing that fills it")


func test_hosting_ends_with_the_connection() -> void:
	# D-088 accepts this with eyes open: host-quit kills the match for
	# everyone. What must not happen is the server outliving the client's
	# connection and holding the UDP port against the next Host.
	var client := _read("res://client.gd")
	assert_true(client.contains("_hosted_server.free()"),
		"leaving must free the embedded server")
	assert_true(client.contains("if _host == null and _hosted_server == null:"),
		"and a hosting client must not be mistaken for a disconnected one — "
		+ "read as 'is there a socket', a host ticks its server and renders nothing")


func test_the_recipe_binds_this_instances_port() -> void:
	# D-095: two agents running `just test-host` on one laptop must not
	# find each other's match. A player never passes it; the recipe must.
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("--host-port={{port}}"),
		"test-host must bind this instance's derived port, never the shared default")


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text
