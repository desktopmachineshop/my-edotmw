extends GutTest

## Guards #179 / D-094 criterion 3 and
## `decisions/D-20260827-the-join-flow-carries-a-protocol-version.md`:
## the join flow carries a protocol version, and a mismatched client is
## refused with a message a player can act on.
##
## **What this file can and cannot prove, said out loud.** The REFUSAL
## path is driven here for real — a fake peer through `server._handle_hello`
## — because it is the half with the interesting failure mode and it needs
## no world. The ACCEPT path is driven here too, but only as far as the
## LOBBY phase, where admission is a seat and a welcome rather than a
## whole opening.
##
## Neither of those is what makes the accept path trustworthy. That is
## `gate-check.sh handshake`, run by BOTH `just test-load` and
## `just test-scenario`, which fails a run in which the server accepted
## fewer handshakes than there were clients connected — a real server,
## real sockets, every run. And the refusal is re-proved end to end by
## `just test-handshake`, which presents a deliberately wrong protocol
## over a real socket. This is D-020's own lesson from the civ knobs
## (#158): a unit test proves the arithmetic and says nothing about
## whether the server performs it.


const WRONG := NetProtocol.PROTOCOL_VERSION + 1


## A peer that is not a socket. Duck-typed to what the server actually
## uses — `send` and `peer_disconnect_later` — exactly as LoopbackPeer is
## (D-051), and for the same reason: a path only reachable through a real
## UDP connection is a path nothing tests.
class FakePeer extends RefCounted:
	var packets: Array = []
	var disconnect_requested := false

	func send(_channel: int, packet: PackedByteArray, _flags: int = 0) -> int:
		packets.append(packet)
		return OK

	func peer_disconnect_later(_data: int = 0) -> void:
		disconnect_requested = true

	## The first packet of the given opcode, or an empty array.
	func first(opcode: int) -> PackedByteArray:
		for packet in packets:
			if NetProtocol.opcode_of(packet) == opcode:
				return packet
		return PackedByteArray()


# --- the wire itself ---------------------------------------------------

func test_hello_round_trips() -> void:
	var decoded := NetProtocol.decode_hello(
		NetProtocol.encode_hello(7, "9.9.9-test"))
	assert_eq(int(decoded["protocol"]), 7)
	assert_eq(str(decoded["build"]), "9.9.9-test")


func test_a_refusal_round_trips() -> void:
	var decoded := NetProtocol.decode_refused(
		NetProtocol.encode_refused(NetProtocol.REFUSED_PROTOCOL, 3, "0.2.0"))
	assert_eq(int(decoded["reason"]), NetProtocol.REFUSED_PROTOCOL)
	assert_eq(int(decoded["protocol"]), 3)
	assert_eq(str(decoded["build"]), "0.2.0")


func test_the_new_opcodes_collide_with_nothing() -> void:
	# The one defect a wire protocol cannot recover from. Two opcodes
	# sharing a number is a packet silently routed to the wrong handler,
	# and net_protocol.gd's own header says the whole file exists so the
	# two ends cannot drift — a collision drifts them inside one file.
	var seen := {}
	var script := load("res://net_protocol.gd") as GDScript
	for name in script.get_script_constant_map():
		if not (name.begins_with("C2S_") or name.begins_with("S2C_")):
			continue
		var value: int = script.get_script_constant_map()[name]
		assert_false(seen.has(value),
			"opcode %d is used by both %s and %s" % [value, seen.get(value, ""), name])
		seen[value] = name
	assert_true(seen.values().has("C2S_HELLO"), "the hello opcode must exist")
	assert_true(seen.values().has("S2C_REFUSED"), "the refusal opcode must exist")


func test_the_protocol_version_is_its_own_number() -> void:
	# Not the build version. Two builds can differ in art, balance or a
	# bug fix and still speak the same wire; refusing those would make
	# every hotfix a flag day.
	assert_gt(NetProtocol.PROTOCOL_VERSION, 0,
		"the protocol version must be a real number")
	assert_ne(str(NetProtocol.PROTOCOL_VERSION), BuildVersion.string(),
		"the protocol version and the build version are different things")


# --- the message a player reads ---------------------------------------

func test_a_refusal_names_both_builds_and_what_to_do() -> void:
	var text := NetProtocol.refusal_text(NetProtocol.REFUSED_PROTOCOL,
		4, "0.9.0-server", "0.1.0-mine", 2)
	assert_true(text.contains("0.1.0-mine"), "must name the player's build: %s" % text)
	assert_true(text.contains("0.9.0-server"), "must name the server's build: %s" % text)
	assert_true(text.contains("2"), "must name the player's protocol: %s" % text)
	assert_true(text.contains("4"), "must name the server's protocol: %s" % text)
	# "Version mismatch" is a message a player cannot act on. The issue
	# asks for one they can.
	assert_true(text.to_lower().contains("update"),
		"must say what to do about it: %s" % text)


func test_an_unknown_reason_still_says_something_useful() -> void:
	# A newer server refusing for a reason this build has never heard of
	# is exactly the situation a version handshake creates. Falling
	# through to an empty string would put a blank dialog on screen.
	var text := NetProtocol.refusal_text(99, 4, "0.9.0", "0.1.0", 2)
	assert_false(text.strip_edges().is_empty(), "an unknown reason still needs words")
	assert_true(text.contains("0.9.0"), "and must still name the server's build: %s" % text)


func test_the_client_composes_the_refusal_from_both_ends() -> void:
	# The wire carries the SERVER's numbers only; the sentence is
	# assembled where both halves are known, so it cannot be half a build
	# old the way a sentence composed on the far side can.
	var state := ClientState.new()
	assert_true(state.refusal.is_empty(), "a fresh client has not been refused")
	state.handle_packet(NetProtocol.encode_refused(
		NetProtocol.REFUSED_PROTOCOL, 42, "0.9.9-elsewhere"))
	assert_false(state.refusal.is_empty(), "the client must record a refusal")
	var text := str(state.refusal["text"])
	assert_true(text.contains("0.9.9-elsewhere"), "the server's build: %s" % text)
	assert_true(text.contains(BuildVersion.string()), "and this build: %s" % text)


# --- the server actually doing it -------------------------------------

func _server() -> Object:
	# Never added to the tree, so `_ready()` — which opens a socket and
	# generates a world — does not run. The same technique
	# test_civ_knobs.gd uses, for the same reason: "server.gd needs a
	# socket and a scene tree" is true of `_ready()`, not of the file.
	return load("res://server.gd").new()


func test_a_wrong_protocol_is_refused_and_dropped() -> void:
	var server := _server()
	var peer := FakePeer.new()
	server._pending[peer] = Time.get_ticks_msec()

	server._handle_hello(peer, NetProtocol.encode_hello(WRONG, "0.0.1-stale"))

	var packet := peer.first(NetProtocol.S2C_REFUSED)
	assert_gt(packet.size(), 0, "the server must SAY it refused, not merely drop the peer")
	var refusal := NetProtocol.decode_refused(packet)
	assert_eq(int(refusal["reason"]), NetProtocol.REFUSED_PROTOCOL)
	assert_eq(int(refusal["protocol"]), NetProtocol.PROTOCOL_VERSION,
		"the refusal carries the server's own protocol so the client can name it")
	assert_true(peer.disconnect_requested, "and must then drop the connection")
	assert_false(server._pending.has(peer), "a refused peer stops being pending")
	assert_eq(server._handshakes_refused, 1)
	assert_eq(server._handshakes_accepted, 0)
	assert_eq(server._clients.size(), 0,
		"a refused peer must never become a client — no player id, no seat")
	server.free()


func test_a_refused_peer_never_became_a_client_so_no_welcome_was_sent() -> void:
	# The ordering claim, tested rather than asserted in a comment: the
	# alternative shape (admit, then check) would spend a player id, a
	# seat and a lobby broadcast on somebody about to be thrown out.
	var server := _server()
	var peer := FakePeer.new()
	server._pending[peer] = Time.get_ticks_msec()
	server._handle_hello(peer, NetProtocol.encode_hello(WRONG, "0.0.1-stale"))
	assert_eq(peer.first(NetProtocol.S2C_WELCOME).size(), 0,
		"a refused client must not have been welcomed first")
	assert_eq(peer.first(NetProtocol.S2C_LOBBY).size(), 0,
		"nor told about the lobby")
	server.free()


func test_a_matched_protocol_is_admitted() -> void:
	var server := _matched_server()
	var peer: FakePeer = server.get_meta("peer")
	assert_eq(server._handshakes_accepted, 1, "a matching build is accepted")
	assert_eq(server._handshakes_refused, 0)
	assert_false(server._pending.has(peer), "and stops being pending")
	assert_eq(server._clients.size(), 1, "and becomes a client")
	assert_gt(peer.first(NetProtocol.S2C_WELCOME).size(), 0,
		"and is welcomed")
	server.free()


func test_a_second_hello_does_not_admit_the_same_peer_twice() -> void:
	# Re-running admission would spawn a second opening for a player who
	# already has one — and a client is free to send whatever it likes,
	# which is D-002's whole premise.
	var server := _matched_server()
	var peer: FakePeer = server.get_meta("peer")
	server._handle_hello(peer, NetProtocol.encode_hello(
		NetProtocol.PROTOCOL_VERSION, BuildVersion.string()))
	assert_eq(server._handshakes_accepted, 1, "the second hello changes nothing")
	assert_eq(server._clients.size(), 1, "and does not seat a second player")
	server.free()


func test_nothing_but_a_hello_is_heard_from_a_peer_that_has_not_said_one() -> void:
	# A build on the wrong protocol may be sending perfectly well-formed
	# packets of a shape this one does not have. Acting on any of them
	# before the version is known is exactly the mixed-build behaviour
	# this ticket exists to replace with one sentence.
	var server := _server()
	var peer := FakePeer.new()
	server._pending[peer] = Time.get_ticks_msec()
	# An order that would otherwise reach a handler and push_error about
	# a null simulation.
	server._dispatch(peer, NetProtocol.encode_order_stop(0))
	assert_eq(peer.packets.size(), 0, "a pending peer is answered by nothing")
	assert_true(server._pending.has(peer), "and is still waiting to say hello")
	server.free()


func test_a_peer_that_never_says_hello_is_refused_rather_than_left_hanging() -> void:
	# The one client this exists for: a build made before this handshake
	# did, which will never send HELLO. Without the sweep it sits
	# connected forever, admitted to nothing, with nothing anywhere
	# saying why — which is #162's reported symptom arriving by a second
	# door.
	var server := _server()
	var fresh := FakePeer.new()
	var stale := FakePeer.new()
	server._pending[fresh] = Time.get_ticks_msec()
	server._pending[stale] = Time.get_ticks_msec() - int(
		(NetProtocol.HELLO_TIMEOUT_SECONDS + 1.0) * 1000.0)

	server._sweep_silent_peers()

	assert_true(stale.disconnect_requested, "the silent peer is dropped")
	var packet := stale.first(NetProtocol.S2C_REFUSED)
	assert_gt(packet.size(), 0, "and told why, for a client new enough to understand")
	assert_eq(int(NetProtocol.decode_refused(packet)["reason"]), NetProtocol.REFUSED_SILENT)
	assert_false(fresh.disconnect_requested,
		"a peer still inside the window is left alone")
	assert_true(server._pending.has(fresh))
	server.free()


func test_a_refused_peer_cannot_shut_the_server_down_on_its_way_out() -> void:
	# Found while writing `just test-handshake`, and it is the reason the
	# disconnect path grew a guard: D-075 ends a server when the last
	# HUMAN CLIENT leaves, and before this a refused peer was reaching
	# that rule. One connection from a stale zip would have ended a
	# match anybody could have been in — a server anybody could stop by
	# double-clicking the wrong build.
	var server := _server()
	var peer := FakePeer.new()
	server._pending[peer] = Time.get_ticks_msec()
	server._handle_hello(peer, NetProtocol.encode_hello(WRONG, "0.0.1-stale"))
	# `_on_disconnect` is what ENet calls next. It must return before
	# D-075's rule; `_shutting_down` is the observable that says it did.
	server._on_disconnect(peer)
	assert_false(server._shutting_down,
		"a peer that was never admitted is not a client leaving")
	server.free()


# --- everybody who connects performs it -------------------------------

func test_both_clients_send_a_hello_the_moment_they_connect() -> void:
	# The caller-exists check (D-106's rule as a test). The server admits
	# nobody without one, so a binary that does not send it does not
	# work at all — but "does not work at all" is what a broken server
	# looks like too, and this says which.
	for path in ["res://client.gd", "res://bot_client.gd"]:
		assert_true(_read(path).contains("NetProtocol.encode_hello("),
			"%s must send a version handshake on connect" % path)
	assert_true(_read("res://client.gd").contains("NetProtocol.S2C_REFUSED")
			or _read("res://client_state.gd").contains("NetProtocol.S2C_REFUSED"),
		"somebody on the client side must handle a refusal")


func test_the_gate_reads_the_handshake_on_every_real_run() -> void:
	# `gate-check.sh handshake` is what makes the ACCEPT path
	# non-vacuous, and `tests/test_gate_checks.gd` separately fails if
	# the fast loop does not make every check the gate makes.
	assert_true(_read("res://gate-check.sh").contains("HANDSHAKE accepted"),
		"gate-check.sh must be the one place the handshake marker is read")
	assert_true(_read("res://server.gd").contains("server: HANDSHAKE accepted="),
		"the server must print the marker the gate reads")


# --- helpers -----------------------------------------------------------

## A server with just enough world to admit somebody into a LOBBY, plus
## one peer that has already handshaken successfully. The lobby phase on
## purpose: admission there is a seat and a welcome, where admission into
## a running match is a whole opening — and the opening is not what this
## file is about.
func _matched_server() -> Object:
	var server := _server()
	server._sim = SquadSim.new(TorusSpace.new(16, 8, 1.0), CurveReplicator.new())
	server._match = MatchState.new()
	# A real lobby, waiting for an admin to press start (D-048) — not a
	# phase poked into place. `add_player` STARTS a match the moment the
	# seats it expects are filled, so a fixture that merely set the phase
	# would find itself in a running match with no world, and read as this
	# test being wrong about admission rather than about its own setup.
	server._match.require_admin_start = true
	server._settings = server._match.map_settings
	var no_spawns: Array[Vector2i] = []
	server._spawn_points = no_spawns

	var peer := FakePeer.new()
	server._pending[peer] = Time.get_ticks_msec()
	server._handle_hello(peer, NetProtocol.encode_hello(
		NetProtocol.PROTOCOL_VERSION, BuildVersion.string()))
	server.set_meta("peer", peer)
	return server


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text
