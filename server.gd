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
# ENetPacketPeer -> { "player": int, "squads": Array[int],
# "visible": Dictionary[int, bool] }. "visible" is this client's
# reveal/conceal baseline — the squad ids it was visible to as of the
# last tick this server diffed against (D-025 part 2/3) — kept here,
# per-client, rather than in SquadSim: the simulation has no notion of
# "client", only of players and their vision, and per-client delivery
# bookkeeping belongs with the other per-client state (CurveReplicator's
# own delivery records live the same way, keyed by player id).
var _clients := {}
var _next_player := 1

var _config: MapConfig
var _sim: SquadSim
var _replay: ReplayLog

var _match: MatchState

## Casualty/rout events produced OUTSIDE a tick — currently only a
## disconnecting player's army being wiped (D-033). They cannot simply be
## appended to `_sim.last_combat_events`, because the next tick overwrites
## that; they wait here until the next `_replicate()` sends them.
var _pending_events: Array = []
var _reported_match_end := false

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

	# Match lifecycle (D-033). Defaults to 1 so the single-client
	# development flows (`run-client`, `test-client`) behave exactly as
	# they did before matches existed: the match starts on the first join
	# and the victory rule never fires with fewer than two players.
	_match = MatchState.new()
	_match.players_expected = maxi(1, int(args.get("players", 1)))

	# Combat's RNG must be seeded from map configuration, never wall-clock
	# (D-024) — MapConfig has no dedicated seed field, so this derives one
	# deterministically from fields it already has. Same map, same seed,
	# every run: that is what lets a replay reproduce the exact battle
	# that happened rather than a different one (D-016).
	_sim.combat_seed = NetProtocol.seed_from(String(_config.id), _config.width, _config.height)

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
		_advance_match()
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
	# us/squad is meaningless without its squad count (CLAUDE.md) — always
	# printed alongside it, never bare. Vision and combat are broken out as
	# their own components of that same figure (D-026 criterion 10, D-012)
	# rather than folded into one number, so a reviewer can see which phase
	# a budget overrun would come from.
	print("server: final (%s) — ticks=%d time=%.1fs squads=%d bytes=%d packets=%d fields=%d curves_rebuilt=%d dropped_ticks=%d us/squad=%.2f (vision=%.3f combat=%.3f) vision_rebuilds=%d" % [
		reason, _sim.tick_count, _sim.time, _sim.squad_count(),
		_sim.replicator.bytes_sent_total, _sim.replicator.packets_sent_total,
		_sim.fields_built, _sim.curves_rebuilt, _ticks_dropped,
		_sim.mean_usec_per_squad_update(),
		_sim.mean_vision_usec_per_squad_update(),
		_sim.mean_combat_usec_per_squad_update(),
		_sim.vision_rebuilds,
	])

	# A distinct, structured marker — not a substring of the line above —
	# for `just test-load` to compare against the bots' collectively-known
	# squad count (D-026 criterion 6's load half: fog must be shown gating
	# a real multi-client run, not just a test fixture). Squad count is
	# fixed once spawned (casualties zero a squad's `alive`, they never
	# remove the row — D-024), so this is stable for the whole run and safe
	# to read from any point in the log, including the periodic status
	# line below.
	print("server: FOG_TOTAL_SQUADS=%d" % _sim.squad_count())


func _print_status() -> void:
	# Deliberately avoids the words this project's log scanners look for
	# (`just test-load` greps for warning/desync), so routine status can
	# never be mistaken for a fault.
	print("server: tick=%d time=%.1fs squads=%d clients=%d sent=%dB fields=%d us/squad=%.2f (vision=%.3f combat=%.3f)" % [
		_sim.tick_count, _sim.time, _sim.squad_count(), _clients.size(),
		_sim.replicator.bytes_sent_total, _sim.fields_built,
		_sim.mean_usec_per_squad_update(),
		_sim.mean_vision_usec_per_squad_update(),
		_sim.mean_combat_usec_per_squad_update(),
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
	_clients[peer] = {"player": player, "squads": squads, "visible": {}}

	# The new player's own squads need a vision stamp before anything asks
	# visible_to() about them — own squads are always visible regardless
	# (SquadSim.visible_to's owner check), but without this the joiner
	# would see nothing OF OTHERS until the next scheduled tick-driven
	# rebuild (vision_recompute_every_ticks), which reads as "fog is broken
	# for one tick after joining" rather than a real gap. A join is rare
	# enough that paying a full rebuild here is not a real cost concern.
	_sim.recompute_vision_now()

	peer.send(0, NetProtocol.encode_welcome(player, _config.width, _config.height, squads),
		ENetPacketPeer.FLAG_RELIABLE)

	# Composition for everything each client can see, not just what it
	# owns — clients derive soldiers for other players' squads too, and
	# without composition they would have to guess.
	#
	# Broadcast rather than sent only to the joiner: this player's squads
	# have just come into existence, and every ALREADY-connected client can
	# see them (if in vision). Sending only to the newcomer leaves everyone
	# else receiving curves for squads they were never told about — which
	# is exactly what the desync check caught the first time it ran.
	_broadcast_squad_info()

	# Seed ONLY the new client's reveal/conceal baseline (D-025 parts 2/3)
	# to what it was just told is visible, so its first _replicate() tick
	# reports genuinely new reveals rather than re-announcing everything
	# _broadcast_squad_info just sent. Deliberately not touched for
	# already-connected peers here: their baseline is owned exclusively by
	# _replicate()'s own diff, and this join's recompute_vision_now() call
	# could in principle shift an existing client's coverage slightly.
	# Bypassing the diff to "silently" update their baseline would skip
	# the reveal/conceal messages that shift is supposed to produce; at
	# worst, leaving it alone means their next tick re-announces a squad
	# that only just became visible via this broadcast — redundant, never
	# a leak, and self-correcting within one tick.
	_clients[peer]["visible"] = _dict_from_ids(_sim.visible_to(player))

	if _match.add_player(player):
		print("server: MATCH_START — %s" % _match.describe())

	print("server: player %d joined with %d squads (%d connected) — match %s" % [
		player, squads.size(), _clients.size(), _match.describe()])


func _send_squad_info(peer: ENetPacketPeer, player: int) -> void:
	var entries := _sim.squad_info_entries(_sim.visible_to(player))
	if entries.is_empty():
		return
	peer.send(0, NetProtocol.encode_squad_info(entries), ENetPacketPeer.FLAG_RELIABLE)


## Turn an Array of squad ids into a Dictionary(id -> true) — the shape
## both the reveal/conceal diff and CurveReplicator's own visible-set
## lookup want, and cheaper to test membership in than scanning an Array
## per squad per client per tick.
func _dict_from_ids(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[int(id)] = true
	return out


## Tell every connected client about a composition change. Also logs the
## FULL, unfiltered composition to the replay (not any one client's
## visible_to() subset) — the replay is deliberately unclipped ground
## truth, "what fog hid from every client" (D-026 criterion 11), and this
## is what lets replay-info report a final strength for a squad that
## never fought and so never appears in a SQUAD_COMBAT event.
func _broadcast_squad_info() -> void:
	for peer in _clients:
		_send_squad_info(peer, int(_clients[peer]["player"]))

	if _replay != null and _replay.is_open():
		var entries := _sim.squad_info_entries(_all_squad_ids())
		if not entries.is_empty():
			_replay.record_squad_info(_sim.time, NetProtocol.encode_squad_info(entries))


func _all_squad_ids() -> Array:
	var ids := []
	for i in range(_sim.squad_count()):
		ids.append(i)
	return ids


func _on_disconnect(peer: ENetPacketPeer) -> void:
	var record = _clients.get(peer, null)
	if record != null:
		var player := int(record["player"])
		_sim.replicator.forget_client(player)

		# An abandoned army does not get to keep standing on the field
		# (D-033). Wiping it is the *cause* of defeat; MatchState's
		# ordinary "no living squads" rule notices the effect on the next
		# tick, so "defeated" keeps exactly one definition. The wipe comes
		# back as casualty events, which replicate through the path
		# clients already understand.
		_match.mark_disconnected(player)
		_pending_events.append_array(_sim.eliminate_player(player))

		print("server: player %d left (%d connected)" % [player, _clients.size() - 1])
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
			NetProtocol.C2S_ORDER_STOP:
				_handle_order_stop(peer, data)
			NetProtocol.C2S_ORDER_ATTACK_MOVE:
				_handle_order_attack_move(peer, data)
			_:
				push_error("server: unknown opcode %d from a client" % opcode)


## Shared validation for every squad order (D-002, D-034). Returns the
## squad id, or -1 if the order must be dropped.
##
## Factored out rather than repeated per handler: the checks ARE the
## authority, and three copies is how one of them eventually loses one.
## A client may only order squads it owns, only squads that exist, and
## only while a match is actually running (D-033) — none of which is
## trusted from the client, because the client is not trusted.
func _validated_squad(peer: ENetPacketPeer, squad: int) -> int:
	var record = _clients.get(peer, null)
	if record == null:
		return -1
	if not _match.is_running():
		return -1
	if not (record["squads"] as Array).has(squad):
		push_error("server: player %d tried to order squad %d it does not own" % [record["player"], squad])
		return -1
	if squad < 0 or squad >= _sim.squad_count():
		return -1
	return squad


func _handle_order_move(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_move(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return
	# from_index normalises, so a nonsense destination wraps into the map
	# rather than going out of bounds (D-008).
	_sim.order_move(squad, _sim.space.from_index(int(order["destination"])))


func _handle_order_attack_move(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_attack_move(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return
	_sim.order_attack_move(squad, _sim.space.from_index(int(order["destination"])))


func _handle_order_stop(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_stop(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return
	_sim.stop(squad)


func _spawn_squads_for(player: int) -> Array:
	var def := _pick_unit_def()
	var ids := []

	# Spawn points come from the map now, not from a formula here (D-036).
	# The old version computed lanes from `player * 7` and `player * 5 + i
	# * 2`, which had two problems: the constants were invisible to anyone
	# balancing a map, and client.gd had duplicated the whole formula to
	# *guess* where a neighbour spawned, with a comment noting the guess
	# would go stale if this ever changed. Deriving spawns from
	# MapConfig.spawn_points() makes them data, and makes them provably
	# fair — every point is the same offset into a quadrant, and the
	# quadrants are bit-identical terrain (D-036).
	var points := _config.spawn_points()

	# Players are numbered from 1, spawn points from 0. Wrapping rather
	# than refusing keeps an extra connection working on a full map: the
	# player cap belongs to the match lifecycle (D-033), which is not built
	# yet, so sharing a start is a better failure than crashing.
	var origin: Vector2i = points[(player - 1) % points.size()]

	for i in range(_config.squads_per_player):
		ids.append(_sim.add_squad(def, player, _starting_cell(origin, i)))
	return ids


## Where a player's i-th starting squad stands, relative to its spawn.
##
## Compact so an army starts together rather than smeared across its
## quadrant, and a pure function of (origin, index) so replays reproduce
## the opening position exactly (D-016). add_squad normalises through
## TorusSpace, so a spawn near a seam wraps rather than going out of
## bounds (D-008).
func _starting_cell(origin: Vector2i, index: int) -> Vector2i:
	const PER_ROW := 4
	return origin + Vector2i(index % PER_ROW, index / PER_ROW)


func _pick_unit_def() -> UnitDef:
	# Data-driven roster (D-010), discovered the same way everywhere.
	return UnitRoster.first()


## Per-client message order within a tick is load-bearing (D-025, D-026
## criterion 7/8): revealed squads' composition -> conceal events ->
## curves -> combat events -> state hash. ENet channel 0 is reliable and
## ordered, so this ordering holds on the wire exactly as sent.
##
##  - Reveal composition must precede curves: a client cannot derive
##    soldiers for a squad it was never described (D-006's protocol
##    obligation), so if a squad's first curve for this client arrived
##    before its SQUAD_INFO, the client would have a curve for a squad it
##    knows nothing about (squads_awaiting_composition() would flag it,
##    correctly, as a gap — reveal ordering is what keeps that count at
##    zero on a healthy run).
##  - Conceal must be explicit and precede the state hash: without it a
##    client cannot tell "out of vision" from "late update", and the
##    server's hash (over visible_to(player)) would compare a different
##    set than the client's own composition_hash() (over live squads only)
##    the instant a squad is hidden — D-026 criterion 8.
##  - Combat events stay gated by the SAME visible set the curves use and
##    sent before the hash, so a client's composition is current by the
##    time it checks itself (D-026 criterion 3) — unchanged from M2's
##    combat-only shape, just now sharing `visible` with the fog gate
##    rather than a stub that returned everything.
## Drive the match rules once per tick and announce what they decide
## (D-033).
##
## The announcements are structured markers, not prose — `just test-load`
## scans for exactly these, and the justfile's own comment records why
## scanning for scary words instead once failed a good run by matching its
## own success line.
func _advance_match() -> void:
	for player in _match.update(_sim):
		print("server: MATCH_ELIMINATED player=%d" % player)
	if _match.is_finished() and not _reported_match_end:
		_reported_match_end = true
		print("server: MATCH_OVER winner=%d" % _match.winner)


func _replicate() -> void:
	var send_hash := _sim.tick_count % STATE_HASH_EVERY_TICKS == 0

	# This tick's combat, plus anything produced outside a tick (a
	# disconnecting player's army being wiped). Merged rather than sent
	# separately so a client applies both in one message and the
	# composition hash that follows is already current.
	var combat_events := _sim.last_combat_events
	if not _pending_events.is_empty():
		combat_events = combat_events + _pending_events

	for peer in _clients:
		var record = _clients[peer]
		var player := int(record["player"])
		var visible := _sim.visible_to(player)
		var visible_set := _dict_from_ids(visible)
		var previous_visible: Dictionary = record.get("visible", {})

		# Reveal (D-025 part 2): composition for anything newly visible.
		# The curve resend itself needs no extra work here — CurveReplicator
		# already resends a curve, clipped to [now, now + horizon] like any
		# other, the moment an id it wasn't tracking for this client
		# reappears in `visible` (see collect_for_client's own comment).
		var revealed_ids := []
		for id in visible_set:
			if not previous_visible.has(id):
				revealed_ids.append(id)
		if not revealed_ids.is_empty():
			var reveal_entries := _sim.squad_info_entries(revealed_ids)
			if not reveal_entries.is_empty():
				peer.send(0, NetProtocol.encode_squad_info(reveal_entries),
					ENetPacketPeer.FLAG_RELIABLE)

		# Conceal (D-025 part 3): anything that WAS visible last tick and
		# is not anymore, as an explicit event rather than silence.
		var concealed_ids := []
		for id in previous_visible:
			if not visible_set.has(id):
				concealed_ids.append(id)
		if not concealed_ids.is_empty():
			peer.send(0, NetProtocol.encode_squad_conceal(_sim.tick_count, concealed_ids),
				ENetPacketPeer.FLAG_RELIABLE)

		record["visible"] = visible_set

		var packets := _sim.replicator.collect_for_client(player, _sim.time, visible)
		for packet in packets:
			peer.send(0, NetProtocol.encode_curve(packet["bytes"]), ENetPacketPeer.FLAG_RELIABLE)

		# Casualty/rout events (D-024), gated by the same visible set the
		# curves use. Sent reliably, before the hash, so a client's
		# composition is current by the time it checks itself (D-026
		# criterion 3), and skipped ENTIRELY when nothing in this client's
		# visible set changed — a quiet tick costs zero bytes here, same as
		# an idle squad costs zero curve bytes (D-003).
		if not combat_events.is_empty():
			var visible_events := []
			for event in combat_events:
				if visible_set.has(int(event["id"])):
					visible_events.append(event)
			if not visible_events.is_empty():
				peer.send(0, NetProtocol.encode_squad_combat(_sim.tick_count, visible_events),
					ENetPacketPeer.FLAG_RELIABLE)

		# Hashed over this client's visible set, so client and server
		# always compare the same set even though it now differs per
		# client (D-004/D-025). Last, per the ordering above.
		if send_hash:
			peer.send(0,
				NetProtocol.encode_state_hash(_sim.tick_count, _sim.composition_hash(visible)),
				ENetPacketPeer.FLAG_RELIABLE)

	# Delivered to every client above, so they are no longer pending.
	_pending_events.clear()


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
