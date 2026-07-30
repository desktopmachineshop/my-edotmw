extends Node

## Headless authoritative server (D-002).
##
## Owns the simulation, accepts client connections, receives input, and
## replicates curve state. Clients never send positions and never receive
## soldier positions — only squad curves, clipped per client (D-003/D-006).
##
## The tick is driven by an explicit accumulator here rather than
## `_physics_process` (D-023), so the simulation advances at a fixed 10 Hz
## (D-020) regardless of how often `_process` happens to run.
##
## Transport is raw ENet rather than Godot's high-level multiplayer. The
## protocol is a handful of byte opcodes carrying curve payloads, which
## the high-level RPC layer would only get in the way of — and raw ENet is
## what lets bot_client.gd run N virtual clients in one process (D-018).

const DEFAULT_PORT := 4433
const MAX_CLIENTS := 32
const CHANNELS := 2

const DEFAULT_MAP := "res://maps/default.tres"

## Ticks the server will run in one frame to catch up before giving up and
## discarding the backlog. Bounded so a stalled server cannot enter a
## death spiral of ever-growing catch-up work.
const MAX_CATCHUP_TICKS := 10

## How often the server publishes its composition hash for clients to
## check themselves against. Every tick would be wasteful; this is often
## enough that a desync is caught within a second.
const STATE_HASH_EVERY_TICKS := 10

var _host: ENetConnection
var _clients := {}  # ENetPacketPeer -> { "player": int, "squads": Array[int] }
var _next_player := 1

var _config: MapConfig
var _sim: SquadSim
var _replay: ReplayLog

var _accumulator := 0.0
var _port := DEFAULT_PORT
var _run_seconds := -1.0  # negative = run until stopped
var _status_every_ticks := 100
var _shutting_down := false
var _ticks_dropped := 0
var _reported_drop := false


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_port = int(args.get("port", DEFAULT_PORT))
	_run_seconds = float(args.get("run-seconds", -1.0))
	var map_path := String(args.get("map", DEFAULT_MAP))

	_config = load(map_path) as MapConfig
	if _config == null:
		push_error("server: could not load MapConfig from %s" % map_path)
		get_tree().quit(1)
		return

	var invalid := _config.validate()
	if invalid != "":
		push_error("server: map %s is invalid: %s" % [map_path, invalid])
		get_tree().quit(1)
		return

	var space := _config.to_space()
	_sim = SquadSim.new(space, CurveReplicator.new())

	_replay = ReplayLog.new()
	# Replays are the curve log (D-016), written from M1 onward.
	var replay_path := "res://artifacts/replay-%d.edmw" % _port
	if _replay.open_for_write(replay_path, SquadSim.TICK_HZ, space) == OK:
		_sim.replay = _replay
		print("server: recording replay to %s" % replay_path)

	_host = ENetConnection.new()
	var err := _host.create_host_bound("0.0.0.0", _port, MAX_CLIENTS, CHANNELS)
	if err != OK:
		push_error("server: could not bind UDP %d (error %d)" % [_port, err])
		get_tree().quit(1)
		return

	print("server: listening on 0.0.0.0:%d — map %s (%dx%d), tick %d Hz" % [
		_port, _config.id, _config.width, _config.height, int(SquadSim.TICK_HZ)])
	if _run_seconds > 0.0:
		print("server: will stop after %.1f simulated seconds" % _run_seconds)


func _exit_tree() -> void:
	_shutdown()


func _shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true

	_print_summary("shutdown")

	if _replay != null and _replay.is_open():
		print("server: wrote %d replay records" % _replay.records_written)
		_replay.close()
	if _host != null:
		_host.destroy()
		_host = null


func _process(delta: float) -> void:
	if _shutting_down:
		return

	_service_network()

	# Fixed-timestep accumulator (D-023). Whole ticks are consumed and the
	# remainder carried, so the sim rate is independent of frame rate.
	var step := 1.0 / SquadSim.TICK_HZ
	_accumulator += delta
	var guard := 0
	while _accumulator >= step and guard < MAX_CATCHUP_TICKS:
		_accumulator -= step
		guard += 1
		_sim.tick()
		_replicate()

		if _sim.tick_count % _status_every_ticks == 0:
			_print_status()

	# If the backlog still exceeds a tick, the catch-up bound just threw
	# simulation time away. Dropping ticks is the right call — the
	# alternative is a death spiral — but doing it silently means a server
	# falling behind looks identical to one keeping up. Count it, and say
	# so once rather than every frame.
	if _accumulator >= step:
		var dropped := int(_accumulator / step)
		_ticks_dropped += dropped
		_accumulator -= float(dropped) * step
		if not _reported_drop:
			_reported_drop = true
			push_error("server: dropped %d simulation tick(s) catching up — the sim is falling behind wall-clock (total is in the final summary)" % dropped)

	if _run_seconds > 0.0 and _sim.time >= _run_seconds:
		print("server: reached %.1fs, stopping" % _run_seconds)
		_shutdown()
		get_tree().quit(0)


## Totals for the run so far.
##
## Emitted when the last client leaves as well as at shutdown, because
## shutdown is not reliably reached: `docker compose stop` sends SIGTERM
## and Godot headless does not run `_exit_tree` for it, so a summary
## printed only there never reaches the log a load test collects. The
## last-client-leaves moment always happens and always happens in time.
func _print_summary(reason: String) -> void:
	if _sim == null:
		return
	print("server: final (%s) — ticks=%d time=%.1fs squads=%d bytes=%d packets=%d fields=%d curves_rebuilt=%d dropped_ticks=%d us/squad=%.2f" % [
		reason, _sim.tick_count, _sim.time, _sim.squad_count(),
		_sim.replicator.bytes_sent_total, _sim.replicator.packets_sent_total,
		_sim.fields_built, _sim.curves_rebuilt, _ticks_dropped,
		_sim.mean_usec_per_squad_update(),
	])


func _print_status() -> void:
	# Deliberately avoids the words this project's log scanners look for
	# (`just test-load` greps for warning/desync), so routine status can
	# never be mistaken for a fault.
	print("server: tick=%d time=%.1fs squads=%d clients=%d sent=%dB fields=%d us/squad=%.2f" % [
		_sim.tick_count, _sim.time, _sim.squad_count(), _clients.size(),
		_sim.replicator.bytes_sent_total, _sim.fields_built,
		_sim.mean_usec_per_squad_update(),
	])


func _service_network() -> void:
	if _host == null:
		return
	while true:
		var event := _host.service(0)
		var type: int = event[0]
		if type == ENetConnection.EVENT_NONE:
			return
		var peer: ENetPacketPeer = event[1]
		match type:
			ENetConnection.EVENT_CONNECT:
				_on_connect(peer)
			ENetConnection.EVENT_DISCONNECT:
				_on_disconnect(peer)
			ENetConnection.EVENT_RECEIVE:
				_on_receive(peer)
			ENetConnection.EVENT_ERROR:
				push_error("server: ENet reported a host error")
				return


func _on_connect(peer: ENetPacketPeer) -> void:
	var player := _next_player
	_next_player += 1

	var squads := _spawn_squads_for(player)
	_clients[peer] = {"player": player, "squads": squads}

	peer.send(0, NetProtocol.encode_welcome(player, _config.width, _config.height, squads),
		ENetPacketPeer.FLAG_RELIABLE)

	# Composition for everything each client can see, not just what it
	# owns — clients derive soldiers for other players' squads too, and
	# without composition they would have to guess.
	#
	# Broadcast rather than sent only to the joiner: this player's squads
	# have just come into existence, and every ALREADY-connected client can
	# see them. Sending only to the newcomer leaves everyone else receiving
	# curves for squads they were never told about — which is exactly what
	# the desync check caught the first time it ran.
	_broadcast_squad_info()

	print("server: player %d joined with %d squads (%d connected)" % [
		player, squads.size(), _clients.size()])


func _send_squad_info(peer: ENetPacketPeer, player: int) -> void:
	var entries := _sim.squad_info_entries(_sim.visible_to(player))
	if entries.is_empty():
		return
	peer.send(0, NetProtocol.encode_squad_info(entries), ENetPacketPeer.FLAG_RELIABLE)


## Tell every connected client about a composition change. M1 never calls
## this — nothing changes a squad's strength until combat lands in M2 —
## but the path exists so casualties do not arrive as a protocol gap.
func _broadcast_squad_info() -> void:
	for peer in _clients:
		_send_squad_info(peer, int(_clients[peer]["player"]))


func _on_disconnect(peer: ENetPacketPeer) -> void:
	var record = _clients.get(peer, null)
	if record != null:
		_sim.replicator.forget_client(int(record["player"]))
		print("server: player %d left (%d connected)" % [record["player"], _clients.size() - 1])
	_clients.erase(peer)
	if _clients.is_empty() and _sim != null and _sim.squad_count() > 0:
		_print_summary("last client left")


func _on_receive(peer: ENetPacketPeer) -> void:
	while peer.get_available_packet_count() > 0:
		var data := peer.get_packet()
		if data.size() < 1:
			continue
		var opcode := NetProtocol.opcode_of(data)
		match opcode:
			NetProtocol.C2S_ORDER_MOVE:
				_handle_order_move(peer, data)
			_:
				push_error("server: unknown opcode %d from a client" % opcode)


func _handle_order_move(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var record = _clients.get(peer, null)
	if record == null:
		return
	var order := NetProtocol.decode_order_move(data)
	var squad := int(order["squad"])
	var destination := int(order["destination"])

	# Authoritative server (D-002): a client may only order its own
	# squads, and only to a cell that exists. Both are enforced here
	# rather than trusted, because the client is not trusted.
	if not (record["squads"] as Array).has(squad):
		push_error("server: player %d tried to order squad %d it does not own" % [record["player"], squad])
		return
	if squad < 0 or squad >= _sim.squad_count():
		return

	_sim.order_move(squad, _sim.space.from_index(destination))


func _spawn_squads_for(player: int) -> Array:
	var def := _pick_unit_def()
	var ids := []
	# Spread players around the torus so they don't spawn on top of each
	# other. Deterministic in `player`, so a replay reproduces spawns.
	var lane := (player * 7) % _config.height
	for i in range(_config.squads_per_player):
		var cell := Vector2i((player * 5 + i * 2) % _config.width, (lane + i) % _config.height)
		ids.append(_sim.add_squad(def, player, cell))
	return ids


func _pick_unit_def() -> UnitDef:
	# Data-driven roster (D-010), discovered the same way everywhere.
	return UnitRoster.first()


func _replicate() -> void:
	var send_hash := _sim.tick_count % STATE_HASH_EVERY_TICKS == 0

	for peer in _clients:
		var record = _clients[peer]
		var player := int(record["player"])
		var visible := _sim.visible_to(player)

		var packets := _sim.replicator.collect_for_client(player, _sim.time, visible)
		for packet in packets:
			peer.send(0, NetProtocol.encode_curve(packet["bytes"]), ENetPacketPeer.FLAG_RELIABLE)

		# Hashed over this client's visible set, so it stays correct once
		# fog of war makes that set differ per client (D-004, M2).
		if send_hash:
			peer.send(0,
				NetProtocol.encode_state_hash(_sim.tick_count, _sim.composition_hash(visible)),
				ENetPacketPeer.FLAG_RELIABLE)


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
