extends SceneTree

## Headless load-test bot (see justfile `run-bots` / `test-load`).
##
## Runs N virtual clients inside a single process rather than N
## processes, per the M0 planning session's memory-budget analysis: on
## the current dev hardware (16 GB RAM), N separate Godot headless
## processes is both slower to spin up and a much heavier footprint than
## N lightweight virtual-client objects sharing one process. Each virtual
## client owns its own ENet host, so the server sees N genuinely
## independent connections rather than one connection pretending to be N.
##
## Beyond "did it crash", these bots assert the thing M1 exists to prove:
## every client derives soldier positions from received squad curves
## (D-006) and never receives a soldier position over the wire.

const DEFAULT_SERVER_ADDRESS := "127.0.0.1"
const DEFAULT_SERVER_PORT := 4433
const CHANNELS := 2

const ORDER_INTERVAL_SECONDS := 3.0
const CONNECT_TIMEOUT_SECONDS := 10.0

# Bots assume a nominal squad strength for derivation. M1 has no
# casualties yet (combat is M2), so this stands in for what the client
# will later learn from combat events.
const NOMINAL_ALIVE := 40


class VirtualClient:
	var index: int
	var server_address: String
	var server_port: int

	var host: ENetConnection
	var peer: ENetPacketPeer
	var connected := false
	# Tracked separately from `connected`, because they answer different
	# questions. At the end of a load test the server is torn down first,
	# so every bot is legitimately disconnected — reporting that as "0
	# connected, something is wrong" is how this originally produced a
	# false failure after a completely successful run.
	var ever_connected := false
	var failed := false

	# The SAME client implementation the GUI client uses, deliberately —
	# a load test against a simplified stand-in could pass while the real
	# client is broken.
	var state := ClientState.new()
	var soldiers_derived := 0

	var _next_order_at := 1.0
	var _rng := RandomNumberGenerator.new()

	func _init(p_index: int, p_address: String, p_port: int) -> void:
		index = p_index
		server_address = p_address
		server_port = p_port
		# Seeded per client so a load test is reproducible — which matters
		# because replays (D-016) are the tool for diagnosing whatever a
		# load test turns up.
		_rng.seed = 0x5EED + p_index

	func start() -> Error:
		host = ENetConnection.new()
		var err := host.create_host(1, CHANNELS)
		if err != OK:
			failed = true
			return err
		peer = host.connect_to_host(server_address, server_port, CHANNELS)
		if peer == null:
			failed = true
			return FAILED
		return OK

	func poll(now: float) -> void:
		if host == null or failed:
			return

		while true:
			var event := host.service(0)
			var type: int = event[0]
			if type == ENetConnection.EVENT_NONE:
				break
			match type:
				ENetConnection.EVENT_CONNECT:
					connected = true
					ever_connected = true
				ENetConnection.EVENT_DISCONNECT:
					connected = false
				ENetConnection.EVENT_RECEIVE:
					_drain(event[1])

		if connected and now >= _next_order_at:
			_issue_order()
			_next_order_at = now + ORDER_INTERVAL_SECONDS

	func _drain(from_peer: ENetPacketPeer) -> void:
		while from_peer.get_available_packet_count() > 0:
			state.handle_packet(from_peer.get_packet())

	## Derive soldier positions from held curves — the client-side half of
	## D-006. Nothing here came off the wire; it is all recomputed.
	func derive_soldiers(now: float) -> int:
		soldiers_derived = state.derive_all(now, NOMINAL_ALIVE, "line", 1.0)
		return soldiers_derived

	func curve_packets_received() -> int:
		return state.curve_packets_received

	func _issue_order() -> void:
		if state.space == null or state.squads.is_empty():
			return
		var squad := state.squads[_rng.randi_range(0, state.squads.size() - 1)]
		var destination := Vector2i(
			_rng.randi_range(0, state.space.width - 1),
			_rng.randi_range(0, state.space.height - 1))

		var order := state.encode_order(squad, destination)
		if not order.is_empty():
			peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)

	## Idempotent. Teardown runs twice — once when _process decides the run
	## is over, and again from _finalize as the SceneTree exits — so this
	## must tolerate being called on an already-stopped client. Destroying
	## the host invalidates `peer` without setting the reference to null,
	## so a second pass would call peer_disconnect_now on a dead peer and
	## log an error for a completely successful run.
	func stop() -> void:
		if host == null:
			return
		if peer != null and connected:
			peer.peer_disconnect_now(0)
		peer = null
		connected = false
		host.destroy()
		host = null


var _clients: Array[VirtualClient] = []
var _elapsed := 0.0
var _duration := -1.0
var _reported := false
var _finished := false


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())

	var client_count: int = int(args.get("clients", 1))
	# Inside the compose network the server is a hostname, not localhost,
	# so the address is overridable by env as well as by flag.
	var default_address := OS.get_environment("EDOTMW_SERVER_ADDRESS")
	if default_address == "":
		default_address = DEFAULT_SERVER_ADDRESS
	var address: String = String(args.get("address", default_address))
	var port: int = int(args.get("port", DEFAULT_SERVER_PORT))
	_duration = float(args.get("duration", -1.0))

	print("bot_client.gd: spawning %d virtual client(s) against %s:%d" % [client_count, address, port])

	for i in range(client_count):
		var vc := VirtualClient.new(i, address, port)
		var err := vc.start()
		if err != OK:
			push_error("bot %d: could not start ENet host (error %d)" % [i, err])
		_clients.append(vc)


func _process(delta: float) -> bool:
	_elapsed += delta

	for vc in _clients:
		vc.poll(_elapsed)

	# Exercise the derived-position path on every client, every frame —
	# this is the cost a real client pays, so a load test that skipped it
	# would be measuring the wrong thing.
	for vc in _clients:
		vc.derive_soldiers(_elapsed)

	# Only a bot that NEVER connected indicates a problem. Losing the
	# connection later is normal — the load test tears the server down
	# first.
	if not _ever_connected_any() and _elapsed > CONNECT_TIMEOUT_SECONDS:
		push_error("bot_client.gd: no client connected within %.0fs — is the server up?" % CONNECT_TIMEOUT_SECONDS)
		_finish()
		return true

	if _duration > 0.0 and _elapsed >= _duration:
		_finish()
		return true

	return false


func _finalize() -> void:
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_report()
	for vc in _clients:
		vc.stop()
	# Exit code is the machine-readable half of the verdict, so
	# `just test-load` can fail on it instead of trying to infer success
	# by grepping prose.
	quit(0 if _verdict_ok() else 1)


func _ever_connected_count() -> int:
	var n := 0
	for vc in _clients:
		if vc.ever_connected:
			n += 1
	return n


func _ever_connected_any() -> bool:
	return _ever_connected_count() > 0


func _packets_received() -> int:
	var n := 0
	for vc in _clients:
		n += vc.curve_packets_received()
	return n


## A run is only a success if every bot connected AND state actually
## replicated. "Didn't crash" is not the bar — a bot that connects and
## receives nothing would mean the netcode is broken while every process
## exits 0.
func _verdict_ok() -> bool:
	if _clients.is_empty():
		return false
	return _ever_connected_count() == _clients.size() and _packets_received() > 0


func _report() -> void:
	if _reported:
		return
	_reported = true

	var soldiers := 0
	var curves := 0
	for vc in _clients:
		soldiers += vc.soldiers_derived
		curves += vc.state.curves.size()

	print("bot_client.gd: VERDICT %s — %d/%d bots connected, %d curve packets received, %d squad curves held, %d soldiers derived client-side" % [
		"ok" if _verdict_ok() else "failed",
		_ever_connected_count(), _clients.size(),
		_packets_received(), curves, soldiers])


## Minimal `--key=value` CLI parser for user args (after `--`).
## Example: godot --headless --script bot_client.gd -- --clients=20 --address=127.0.0.1 --port=4433
func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
