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
# ENetPacketPeer -> { "player": int,
# "visible": Dictionary[int, bool] }. "visible" is this client's
# reveal/conceal baseline — the squad ids it was visible to as of the
# last tick this server diffed against (D-025 part 2/3) — kept here,
# per-client, rather than in SquadSim: the simulation has no notion of
# "client", only of players and their vision, and per-client delivery
# bookkeeping belongs with the other per-client state (CurveReplicator's
# own delivery records live the same way, keyed by player id).
var _clients := {}
var _next_player := 1
var _peak_clients := 0

## player id -> civ id (D-047).
##
## Assigned round-robin at join for now, so a mixed match is the default
## rather than a coincidence — D-046 criterion 10 fails a load test in
## which one civ never fielded anything, and that must be a real finding
## rather than an artifact of everyone drawing the same civ.
##
## D-048's lobby replaces this with seats and player choice; the shape of
## the lookup does not change, only who decides.
var _civs := {}


## This player's civ. Never a hardcoded id — the roster is the authority,
## and no script may name a civ (D-046 criterion 3).
func _civ_of(player: int) -> StringName:
	if _civs.has(player):
		return _civs[player]
	var all := CivRoster.ids()
	if all.is_empty():
		return &""
	return all[(player - 1) % all.size()]

var _config: MapConfig
var _sim: SquadSim
var _replay: ReplayLog

var _match: MatchState
var _buildings: BuildingSim
var _economy: Economy
var _passable := PackedByteArray()

## Sampled once at map load and never recomputed — see the note where it
## is filled in.
var _spawn_points: Array[Vector2i] = []

## What the world is, or will be once the lobby settles (D-049).
var _settings: MapSettings

## How near a squad must be to found a building, in cells. A player
## should not be able to plant a town hall across the map from the
## founders who are supposedly building it.
const BUILD_REACH_CELLS := 3

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
var _worst_tick_usec := 0
var _worst_tick_index := 0
var _ticks_over_budget := 0

## ENet's own view of the link, sampled periodically (M4's transport
## question). Reliability is not free — a lost packet costs a round trip
## and, on an ordered channel, blocks everything behind it — so "is
## reliable delivery adequate?" needs the measured loss and RTT rather
## than an argument about it.
var _peak_rtt_ms := 0.0
var _peak_loss_fraction := 0.0
var _min_throttle := 1e9


## ENet reports packet loss as a fixed-point fraction of this scale.
const ENET_PACKET_LOSS_SCALE := 65536.0

## Full throttle — ENet sends everything it is given. It backs this off
## when it detects loss, so a value below the limit is congestion control
## actually engaging rather than a theory about it.
const ENET_THROTTLE_SCALE := 32.0


func _sample_transport_stats() -> void:
	# Peaks, not means. Reliability's cost is a tail phenomenon: the
	# question is whether ANY client ever saw loss worth reengineering the
	# transport for, and an average across twenty healthy links would bury
	# exactly that.
	for peer in _clients:
		var p := peer as ENetPacketPeer
		if p == null:
			continue
		_peak_rtt_ms = maxf(_peak_rtt_ms,
			p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		_peak_loss_fraction = maxf(_peak_loss_fraction,
			p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / ENET_PACKET_LOSS_SCALE)
		_min_throttle = minf(_min_throttle,
			p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE) / ENET_THROTTLE_SCALE)

## D-020's 100 ms tick, in microseconds.
const TICK_BUDGET_USEC := 100_000
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

	# What the world WILL be. Seeded from the map file, then edited in the
	# lobby (D-049).
	_settings = MapSettings.new()
	_settings.width = _config.width
	_settings.height = _config.height
	_settings.player_slots = _config.player_slots
	_settings.seed = int(args.get("seed", 1337))
	_settings.apply_preset(TerrainPresetRoster.by_id(_settings.preset))

	_match = MatchState.new()
	_match.players_expected = maxi(1, int(args.get("players", 1)))
	_match.require_admin_start = int(args.get("lobby", 0)) != 0
	_match.civ_rng.seed = hash(_config.id) + int(args.get("seed", 0))
	_match.squad_cap = _config.squad_cap
	_match.map_settings = _settings

	# In lobby mode the world does NOT exist yet, and cannot: its size,
	# seed and shape are all still being chosen (D-049). This is why
	# terrain generation moved out of startup — the old code built a map
	# the moment the server booted, which was before anybody had asked for
	# one, and the client did the same on connect. The lobby has nothing
	# behind it because there is genuinely nothing there yet.
	if not _match.require_admin_start:
		_build_world()

	_host = ENetConnection.new()
	var err := _host.create_host_bound("0.0.0.0", _port, MAX_CLIENTS, CHANNELS)
	if err != OK:
		push_error("server: could not bind UDP %d (error %d)" % [_port, err])
		get_tree().quit(1)
		return

	print("server: listening on 0.0.0.0:%d — map %s, tick %d Hz%s" % [
		_port, _config.id, int(SquadSim.TICK_HZ),
		" (lobby)" if _match.require_admin_start else ""])
	if _run_seconds > 0.0:
		print("server: will stop after %.1f simulated seconds" % _run_seconds)


## Generate the world the settings describe. Called at startup when there
## is no lobby, and when the admin starts a match when there is (D-049).
func _build_world() -> void:
	if _sim != null:
		return
	var space := _settings.to_space()
	_sim = SquadSim.new(space, CurveReplicator.new())

	# Terrain is real to the SIMULATION, not just to the renderer.
	#
	# M1 left the sim's passability empty on purpose — terrain generation
	# was out of scope — and nothing since put it back. The visible result
	# only became obvious on the 128x64 map: the first capture frame after
	# the map grew showed a squad standing in the middle of a lake. Water
	# and mountains are impassable per TerrainGen.passability, and the flow
	# field (D-007) already knows how to route around an impassable cell;
	# it was simply never told.
	#
	# The client builds its mesh from a default TerrainGen (client.gd's
	# _build_terrain), so the server builds passability from the same
	# defaults and the two agree about where the water is BY CONSTRUCTION.
	# That contract is implicit and worth stating: the moment terrain
	# parameters become tunable they have to become map data and travel on
	# the wire, or the two sides will quietly disagree about which cells a
	# squad may enter — the same class of divergence D-006's composition
	# obligation exists to prevent.
	# One TerrainGen for the whole server: passability, and the resource
	# field derived from the same biomes (D-037). Two instances would be
	# two sources of truth about the same ground.
	var terrain := _settings.to_terrain()
	_passable = terrain.passability(space)
	_sim.set_passable(_passable)

	# Spawns are scattered randomly with a minimum spacing (D-039), so they
	# are sampled ONCE here and reused. Two reasons that matters: sampling
	# is rejection-based and no longer free, and every consumer — spawning,
	# resource fairness, the welcome message — must agree on the same
	# points. Recomputing is deterministic and would agree anyway, but only
	# as long as nobody passes a different `passable`, which is exactly the
	# kind of drift that is cheaper to make impossible.
	# Spawn placement follows the LOBBY's chosen slot count and map size
	# (D-049), not the map file's — the file is only the starting point
	# those settings were seeded from.
	var spawn_config := MapConfig.new()
	spawn_config.width = _settings.width
	spawn_config.height = _settings.height
	spawn_config.player_slots = _settings.player_slots
	spawn_config.min_spawn_spacing = _config.min_spawn_spacing
	spawn_config.spawn_seed = _config.spawn_seed + _settings.seed
	_spawn_points = spawn_config.spawn_points(_passable)

	var seating := spawn_config.validate_spawns(_passable)
	if seating != "":
		# Not fatal: a short-seated map still plays, players just share
		# starts. Fatal would take down a running server over a map tuning
		# mistake. But it must be said out loud — silently seating twenty
		# players on four points is precisely the failure this run is
		# meant to be measuring.
		push_warning("server: %s" % seating)
		print("server: WARNING — %s" % seating)
	print("server: world %dx%d, preset %s, seed %d — %d spawn points" % [
		_settings.width, _settings.height, _settings.preset, _settings.seed,
		_spawn_points.size()])

	# Buildings (D-029). Owned by the server and handed to the sim, which
	# advances construction and lets armed ones shoot as part of its tick.
	_buildings = BuildingSim.new(space)
	_sim.buildings = _buildings

	# The economy (D-028). Nodes are derived from the same terrain, with
	# the map's symmetry order, so all four starts hold equal resources
	# without anything here reasoning about fairness (D-036).
	_economy = Economy.new(space)
	_economy.generate(terrain, 1)
	# Fairness on an asymmetric map is a post-pass now, not a property of
	# the generator (D-036 revised): every start is guaranteed a minimum
	# of each resource within reach.
	_economy.balance_for_spawns(_spawn_points, _passable,
		_config.fairness_radius, _config.fairness_quota)
	_sim.economy = _economy
	print("server: %d resource nodes generated" % _economy.node_count())


	# Combat's RNG must be seeded from map configuration, never wall-clock
	# (D-024) — MapConfig has no dedicated seed field, so this derives one
	# deterministically from fields it already has. Same map, same seed,
	# every run: that is what lets a replay reproduce the exact battle
	# that happened rather than a different one (D-016).
	_sim.combat_seed = NetProtocol.seed_from(String(_config.id), _settings.width, _settings.height) + _settings.seed

	_replay = ReplayLog.new()
	# Replays are the curve log (D-016), written from M1 onward.
	var replay_path := "res://artifacts/replay-%d.edmw" % _port
	if _replay.open_for_write(replay_path, SquadSim.TICK_HZ, space) == OK:
		_sim.replay = _replay
		print("server: recording replay to %s" % replay_path)


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

	# No world, no ticks. In lobby mode the simulation does not exist yet
	# (D-049), and everything below this line assumes it does.
	if _sim == null:
		return

	# Fixed-timestep accumulator (D-023). Whole ticks are consumed and the
	# remainder carried, so the sim rate is independent of frame rate.
	var step := 1.0 / SquadSim.TICK_HZ
	_accumulator += delta
	var guard := 0
	while _accumulator >= step and guard < MAX_CATCHUP_TICKS:
		_accumulator -= step
		guard += 1
		_sim.tick()
		# The WORST tick, not just the mean. D-038 measured an order wave at
		# 323 ms against a 100 ms budget while the average sat at a
		# comfortable 20 ms — twice in this project the average alone would
		# have given a confident wrong answer, so the live server reports
		# both or neither.
		if _sim.last_tick_usec > _worst_tick_usec:
			_worst_tick_usec = _sim.last_tick_usec
			_worst_tick_index = _sim.tick_count
		# Say WHEN, not just how bad. A worst-tick number with no context
		# is a number to theorise about; the profile sweep shows ~29-73 ms
		# for this workload, so a live spike an order of magnitude larger
		# is happening for a reason that is not the order wave, and the
		# only way to tell which is to see what else was going on.
		if _sim.last_tick_usec > TICK_BUDGET_USEC:
			_ticks_over_budget += 1
			if _ticks_over_budget <= 8:
				print("server: TICK OVER BUDGET — tick=%d %.1fms squads=%d clients=%d fields=%d waits=%d | curves=%.1fms vision=%.1fms combat=%.1fms buildings=%.1fms (production=%.1fms) eco=%.1fms" % [
					_sim.tick_count, float(_sim.last_tick_usec) / 1000.0,
					_sim.squad_count(), _clients.size(),
					_sim.fields_built, _sim.field_waits,
					float(_sim.last_curves_usec) / 1000.0,
					float(_sim.last_vision_usec) / 1000.0,
					float(_sim.last_squad_combat_usec) / 1000.0,
					float(_sim.last_buildings_usec) / 1000.0,
					float(_sim.last_production_usec) / 1000.0,
					float(_sim.last_economy_usec) / 1000.0])
		_advance_match()
		_replicate()

		if _sim.tick_count % _status_every_ticks == 0:
			_sample_transport_stats()
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
	# Bandwidth per client per second and peak memory (M4). D-003's whole
	# claim is about bytes, so a total is not enough — the number that
	# matters is what one client costs per second, because that is what
	# multiplies by player count.
	# PEAK clients, not current. The summary prints when the last client
	# leaves, so dividing by _clients.size() divides by 1 no matter how
	# many played — the first run of this reported "11 B/client/s over 1
	# client(s)" for a twenty-player test.
	var clients := maxi(_peak_clients, 1)
	var seconds := maxf(_sim.time, 0.001)
	print("server: bandwidth — %.0f B/client/s over %d client(s), budget_overruns=%d, mem=%.1f MB" % [
		float(_sim.replicator.bytes_sent_total) / float(clients) / seconds,
		clients,
		_sim.replicator.budget_overruns,
		float(OS.get_static_memory_usage()) / 1048576.0,
	])

	print("server: final (%s) — ticks=%d time=%.1fs squads=%d bytes=%d packets=%d fields=%d curves_rebuilt=%d dropped_ticks=%d us/squad=%.2f (vision=%.3f combat=%.3f) vision_rebuilds=%d worst_tick=%.1fms field_waits=%d" % [
		reason, _sim.tick_count, _sim.time, _sim.squad_count(),
		_sim.replicator.bytes_sent_total, _sim.replicator.packets_sent_total,
		_sim.fields_built, _sim.curves_rebuilt, _ticks_dropped,
		_sim.mean_usec_per_squad_update(),
		_sim.mean_vision_usec_per_squad_update(),
		_sim.mean_combat_usec_per_squad_update(),
		_sim.vision_rebuilds,
		float(_worst_tick_usec) / 1000.0,
		_sim.field_waits,
	])
	print("server: transport — peak RTT %.1fms, peak loss %.3f%%, min throttle %.2f of 1.00, all reliable on channel 0" % [
		_peak_rtt_ms, _peak_loss_fraction * 100.0,
		_min_throttle if _min_throttle < 1e8 else 1.0])

	print("server: ticks over D-020's %dms budget: %d of %d, worst %.1fms at tick %d" % [
		TICK_BUDGET_USEC / 1000, _ticks_over_budget, _sim.tick_count,
		float(_worst_tick_usec) / 1000.0, _worst_tick_index])

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

	# In lobby mode nothing is spawned yet, because nothing CAN be: a seat
	# may still say "Random", so this player has no civ, no roster and no
	# opening stockpile until the admin starts (D-048). Spawning first and
	# correcting later would mean a founding party existing before the
	# civilisation that raised it.
	_clients[peer] = {"player": player, "visible": {}}
	_match.add_player(player)
	if _match.phase == MatchState.Phase.LOBBY:
		_broadcast_lobby()
		peer.send(0, NetProtocol.encode_welcome(player, _settings.width, _settings.height,
			PackedInt32Array(), _spawn_cell_indices()), ENetPacketPeer.FLAG_RELIABLE)
		_peak_clients = maxi(_peak_clients, _clients.size())
		return

	# The returned ids go to the client so it knows what it starts with.
	# They are deliberately NOT cached on the connection record: ownership
	# lives in the sim (see _validated_squad), and a second copy here is
	# what silently stopped every produced squad from taking orders.
	_peak_clients = maxi(_peak_clients, _clients.size())
	_admit_player(peer, player)


## Give a player their opening — squads, stockpile, and everything a
## client needs to draw the world.
##
## Shared by the two ways a match can begin: joining an already-running
## server, and the admin starting a lobby (D-048). It has to be one
## function, because "what a player starts with" is exactly the kind of
## thing that drifts when written twice — the same reasoning that made
## ownership read from the sim rather than a per-connection copy.
func _admit_player(peer: ENetPacketPeer, player: int) -> void:
	var squads := _spawn_squads_for(player)

	# The new player's own squads need a vision stamp before anything asks
	# visible_to() about them — own squads are always visible regardless
	# (SquadSim.visible_to's owner check), but without this the joiner
	# would see nothing OF OTHERS until the next scheduled tick-driven
	# rebuild (vision_recompute_every_ticks), which reads as "fog is broken
	# for one tick after joining" rather than a real gap. A join is rare
	# enough that paying a full rebuild here is not a real cost concern.
	_sim.recompute_vision_now()

	peer.send(0, NetProtocol.encode_welcome(player, _config.width, _config.height, squads,
		_spawn_cell_indices()), ENetPacketPeer.FLAG_RELIABLE)

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

	# Starting stockpile (D-028): gatherers cost food and food comes from
	# gatherers, so a player starting empty could never begin.
	#
	# From the CIV, falling back to the map (D-047). A civ built on cheap
	# numbers wants a different opening bank than one built on expensive
	# quality, and that is civ-level data rather than a map property.
	var civ := CivRoster.by_id(_civ_of(player))
	_economy.credit(player, Economy.ResourceKind.FOOD,
		civ.starting_food if civ != null else _config.starting_food)
	_economy.credit(player, Economy.ResourceKind.WOOD,
		civ.starting_wood if civ != null else _config.starting_wood)
	_economy.credit(player, Economy.ResourceKind.GOLD,
		civ.starting_gold if civ != null else _config.starting_gold)
	_economy.credit(player, Economy.ResourceKind.STONE,
		civ.starting_stone if civ != null else _config.starting_stone)
	_send_wallet(peer, player)
	# Where the resources are, once. A player cannot be asked to send
	# workers to a node they have no way of finding.
	peer.send(0, NetProtocol.encode_nodes(_economy.node_entries()),
		ENetPacketPeer.FLAG_RELIABLE)

	# Registration happened at the top of _on_connect, before the lobby
	# branch — a player has to be seated before anyone can decide whether
	# there is a lobby to wait in.
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


## The map's spawn points as cell indices, for the welcome message
## (D-036). Sent so no client has to reimplement spawn placement to know
## where anyone starts.
func _spawn_cell_indices() -> Array:
	if _sim == null:
		return []
	var out := []
	for point in _spawn_points:
		out.append(_sim.space.index(point))
	return out


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
			NetProtocol.C2S_ORDER_BUILD:
				_handle_order_build(peer, data)
			NetProtocol.C2S_ORDER_PRODUCE:
				_handle_order_produce(peer, data)
			NetProtocol.C2S_ORDER_GATHER:
				_handle_order_gather(peer, data)
			NetProtocol.C2S_CHAT:
				_handle_chat(peer, data)
			NetProtocol.C2S_LOBBY:
				_handle_lobby_command(peer, data)
			_:
				push_error("server: unknown opcode %d from a client" % opcode)


## Shared validation for every squad order (D-002, D-034). Returns the
## squad id, or -1 if the order must be dropped.
##
## Factored out rather than repeated per handler: the checks ARE the
## authority, and three copies is how one of them eventually loses one.
## A client may only order squads it owns, only squads that exist and are
## still alive, and only while a match is actually running (D-033) — none
## of which is trusted from the client, because the client is not trusted.
##
## Ownership is read from the SIM, not from a list cached per connection.
## The cached list was written once at join and never again, so every
## squad a player *produced* was refused as one it did not own — the
## founding party got spent on a town hall, and from then on nothing that
## player built could be given an order. It cost a whole 20-player run,
## which reported the interesting-looking "zero movement" while the real
## story was 2,700 refusals in the server log.
##
## That is the failure this function's own comment predicted, one line
## up, about three copies of a check. The lesson is narrower than the
## comment: it was not a copy of the *check* that drifted, it was a copy
## of the *data*. There is one owner of ownership now.
func _validated_squad(peer: ENetPacketPeer, squad: int) -> int:
	var record = _clients.get(peer, null)
	if record == null:
		return -1
	if not _match.is_running():
		return -1
	# Bounds first: owner_of/alive_of index packed arrays directly.
	if squad < 0 or squad >= _sim.squad_count():
		return -1
	if _sim.owner_of(squad) != int(record["player"]):
		push_error("server: player %d tried to order squad %d it does not own" % [record["player"], squad])
		return -1
	if _sim.alive_of(squad) <= 0:
		# Not an error: a squad can die between a client deciding to order
		# it and the order arriving. Dropping it silently is correct —
		# logging would make ordinary lag look like a fault.
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


## Found a building (D-031). Every rule is enforced here rather than
## trusted from the client (D-002): who owns the squad, whether that KIND
## of squad may build this kind of building, whether the ground takes a
## foundation, and whether the builder is anywhere near the site.
func _handle_order_build(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_build(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return

	var def := BuildingSim.def_by_id(StringName(order["def_id"]))
	if def == null:
		push_error("server: client asked for unknown building '%s'" % order["def_id"])
		return

	# Every refusal below tells the player WHY. Silence made a refused
	# order indistinguishable from a broken key during the first playtest.
	if not BuildingSim.can_build(def, _sim.def_of(squad).archetype):
		_notify(peer, "%s cannot build a %s" % [_sim.def_id_of(squad), def.display_name])
		return

	var cell := _sim.space.from_index(int(order["cell"]))
	if not _is_buildable(cell):
		_notify(peer, "Cannot build there — water, mountain, or already occupied")
		return
	var reach := _sim.space.distance(_sim.cell_of(squad), cell)
	if reach > BUILD_REACH_CELLS:
		_notify(peer, "Too far — move closer (%d cells away, reach is %d)" % [reach, BUILD_REACH_CELLS])
		return

	# Construction costs resources (D-028). This was missing, so
	# BuildingDef's cost table was declared and unread — the same trap
	# UnitDef.cost fell into for two milestones. Charged before anything
	# is committed, and all-or-nothing, so a refused build never leaves a
	# part-spent wallet.
	var owner := _sim.owner_of(squad)
	if not _economy.try_spend(owner, def.cost_food, def.cost_wood, def.cost_gold, def.cost_stone):
		_notify(peer, "Cannot afford a %s" % def.display_name)
		return

	var built := _buildings.add_building(def, owner, cell, false, squad)
	_send_wallet(peer, owner)

	# The founding party becomes the settlement, here and now (D-031).
	# Consuming them at completion instead left them free to queue another
	# hall, and another, for the length of the build — the first playtest
	# founded three in a row. This is what makes one founding party mean
	# one town, and it is why founding is a real decision about WHERE.
	_pending_events.append_array(_sim.consume_squad(squad))

	# Ground truth into the replay (D-016, D-027 criterion 18): the full
	# unfiltered view, not any one client's, so a replay can explain what
	# was built even where fog hid it from everybody.
	if _replay != null and _replay.is_open():
		_replay.record_building_info(_sim.time,
			NetProtocol.encode_building_info(_buildings.info_entries([built])))

	print("server: player %d began %s at %s" % [_sim.owner_of(squad), def.id, cell])


## Produce a squad at a building (D-028/D-031). Four gates, all enforced
## here because the client is not trusted (D-002): the player owns the
## building, the building makes that kind of unit, the player is under the
## squad cap, and the player can pay. Payment is last and is all-or-
## nothing, so a refused order never leaves a part-spent wallet.
func _handle_order_produce(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var record = _clients.get(peer, null)
	if record == null or not _match.is_running():
		return

	var order := NetProtocol.decode_order_produce(data)
	var building := BuildingSim.local_id(int(order["building"]))
	if building < 0 or building >= _buildings.building_count():
		return

	var player := int(record["player"])
	if _buildings.owner_of(building) != player:
		push_error("server: player %d tried to produce at a building it does not own" % player)
		return

	# The wire carries an ARCHETYPE, not a unit id (D-047), and the server
	# resolves it against this player's civ. A client therefore cannot
	# name another civ's unit at all — D-046 criterion 4 is structural
	# here rather than a check somebody has to remember to write.
	var archetype := StringName(order["def_id"])
	if not _buildings.can_produce(building, archetype):
		_notify(peer, "That building cannot train %s yet — is it still under construction?" % archetype)
		return
	var def := UnitRoster.for_civ_archetype(_civ_of(player), archetype)
	if def == null:
		_notify(peer, "Your people do not field %s" % archetype)
		return

	# ONE cap covering military and gatherers alike (D-033): every
	# villager crew is an army slot not spent.
	if not _match.has_squad_capacity(_sim, player):
		_notify(peer, "At the squad cap (%d) — gatherers count too" % _match.squad_cap)
		return
	if not _economy.try_spend(player, def.cost_food, def.cost_wood, def.cost_gold, def.cost_stone):
		_notify(peer, "Cannot afford %s" % def.display_name)
		return

	_buildings.enqueue(building, def)
	_send_wallet(peer, player)


## Put a gatherer squad to work (D-028). The economy decides whether the
## squad can gather and whether the cell holds anything; this only checks
## that the order is the player's to give.
func _handle_order_gather(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_gather(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return

	var cell_index := int(order["cell"])
	if not _economy.has_node(cell_index):
		_notify(peer, "Nothing to gather there")
		return
	if not _economy.order_gather(_sim, squad, cell_index):
		_notify(peer, "%s cannot gather — send workers" % _sim.def_id_of(squad))
		return


## Tell one player why something did not happen. The server owns the
## rules, so it owns the explanation too — a client inventing its own
## refusal messages would be a second copy of those rules, free to drift.
func _notify(peer: ENetPacketPeer, text: String) -> void:
	peer.send(0, NetProtocol.encode_notice(text), ENetPacketPeer.FLAG_RELIABLE)


## Wallets go to their owner and nobody else (D-028).
func _send_wallet(peer: ENetPacketPeer, player: int) -> void:
	peer.send(0, NetProtocol.encode_wallet(_economy.wallet_of(player)),
		ENetPacketPeer.FLAG_RELIABLE)


## Buildable ground: passable terrain (no lakes, no mountains) with
## nothing already standing on it.
func _is_buildable(cell: Vector2i) -> bool:
	var index := _sim.space.index(cell)
	if index < _passable.size() and _passable[index] == 0:
		return false
	for i in range(_buildings.building_count()):
		if _buildings.cell_index_of(i) == index and not _buildings.is_destroyed(i):
			return false
	return true


func _handle_order_stop(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_stop(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return
	_sim.stop(squad)


func _spawn_squads_for(player: int) -> Array:
	var ids := []

	# Spawn points come from the map now, not from a formula here (D-036).
	# The old version computed lanes from `player * 7` and `player * 5 + i
	# * 2`, which had two problems: the constants were invisible to anyone
	# balancing a map, and client.gd had duplicated the whole formula to
	# *guess* where a neighbour spawned, with a comment noting the guess
	# would go stale if this ever changed. Deriving spawns from
	# MapConfig.spawn_points() makes them data — randomly scattered with a
	# guaranteed minimum spacing as of D-039, and sampled once at startup.
	var points := _spawn_points

	# Players are numbered from 1, spawn points from 0. Wrapping rather
	# than refusing keeps an extra connection working on a full map: the
	# player cap belongs to the match lifecycle (D-033), which is not built
	# yet, so sharing a start is a better failure than crashing.
	var origin: Vector2i = points[(player - 1) % points.size()]

	# A player starts with ONE founding party and nothing else (D-031).
	#
	# No prebuilt base: where to settle is the first decision of the
	# match, not something the server makes on the player's behalf. The
	# founders can fight — better man for man than line infantry — so the
	# opening is a genuine choice between pressing an early advantage and
	# planting a town hall somewhere defensible.
	#
	# `squads_per_player` no longer describes the opening; it survives as
	# the sizing note D-015 and D-018 reason about, while `squad_cap` is
	# what actually binds once production exists.
	var founders := UnitRoster.for_civ_archetype(_civ_of(player), &"founders")
	if founders == null:
		push_error("server: no 'founders' unit in the roster — a player has nothing to start with")
		return ids

	ids.append(_sim.add_squad(founders, player, origin))
	return ids


# `_starting_cell` and `_pick_unit_def` lived here to lay out a
# twelve-squad opening army from the roster's first unit. Both went when
# the opening became a single founding party — a spawn needs no layout,
# and the starting unit is named rather than whichever .tres sorts first.


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
	for player in _match.update(_sim, _buildings):
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

	# Buildings whose replicated state changed this tick. Taken once, out
	# here, because take_dirty() clears — reading it inside the per-client
	# loop would hand the change to the first client and nobody else.
	var dirty_buildings := _buildings.take_dirty()
	var wallet_changes := {}
	for player in _sim.last_wallet_changes:
		wallet_changes[player] = true

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
		# Buildings (D-029/D-030). Persistent-explored: a client is told
		# about a building once, when it first comes into view, and keeps
		# it forever. `known` therefore only ever grows — and the hash
		# below is computed over exactly that growing set, because the
		# client hashes everything it has been shown. Hashing the
		# currently-visible set here instead would compare
		# differently-shaped sets and fire on a healthy system.
		# Income reaches only the player who earned it (D-028).
		if wallet_changes.has(player):
			_send_wallet(peer, player)

		var known: Dictionary = record.get("known_buildings", {})
		var to_send := []
		for id in _buildings.visible_to(player, _sim.vision):
			if not known.has(id):
				known[id] = true
				to_send.append(id)
		# Plus anything already known whose state changed — otherwise a
		# destruction would never reach a client that had walked away.
		for id in dirty_buildings:
			if known.has(id) and not to_send.has(id):
				to_send.append(id)
		record["known_buildings"] = known

		if not to_send.is_empty():
			peer.send(0, NetProtocol.encode_building_info(_buildings.info_entries(to_send)),
				ENetPacketPeer.FLAG_RELIABLE)

		if send_hash:
			peer.send(0,
				NetProtocol.encode_state_hash(_sim.tick_count, _sim.composition_hash(visible)),
				ENetPacketPeer.FLAG_RELIABLE)
			# Its own message, deliberately: the two hashes cover
			# differently-shaped sets, and one combined number would make a
			# mismatch undiagnosable.
			peer.send(0,
				NetProtocol.encode_building_state_hash(
					_sim.tick_count, _buildings.composition_hash(known.keys())),
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


# --- lobby (D-048) ----------------------------------------------------

## Next player id handed to an AI seat. AI players occupy the same id
## space as humans deliberately: everything downstream — ownership,
## vision, the economy, elimination — already reasons about "a player",
## and giving AI a parallel identity would mean teaching all of it a
## second concept.
var _next_ai_player := 1000


func _handle_lobby_command(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var record = _clients.get(peer, null)
	if record == null:
		return
	var player := int(record["player"])
	var command := NetProtocol.decode_lobby_command(data)
	var action := int(command["action"])
	var ok := false

	match action:
		NetProtocol.LOBBY_SET_CIV:
			ok = _match.set_civ(player, int(command["seat"]), StringName(command["civ"]))
			if not ok:
				_notify(peer, "You cannot choose that seat's civilisation")
		NetProtocol.LOBBY_ADD_AI:
			var seat := _match.add_ai(player, StringName(command["civ"]), _next_ai_player)
			ok = seat >= 0
			if ok:
				_next_ai_player += 1
			else:
				_notify(peer, "Only the lobby admin can add AI players")
		NetProtocol.LOBBY_REMOVE_AI:
			ok = _match.remove_ai(player, int(command["seat"]))
			if not ok:
				_notify(peer, "Only the lobby admin can remove AI players")
		NetProtocol.LOBBY_SET_TEAM:
			ok = _match.set_team(player, int(command["seat"]), int(String(command["civ"])))
			if not ok:
				_notify(peer, "You cannot choose that seat's team")
		NetProtocol.LOBBY_SET_OPTION:
			# The civ field carries "key=value" — the lobby command is a
			# tiny generic message rather than one opcode per slider, so a
			# new setting is a new key rather than a new packet type.
			var parts := String(command["civ"]).split("=", true, 1)
			if parts.size() == 2:
				ok = _match.set_map_option(player, parts[0], float(parts[1]))
			if not ok:
				_notify(peer, "Only the admin can change map settings, and not to an unplayable one")
		NetProtocol.LOBBY_START:
			ok = _match.request_start(player)
			if not ok:
				_notify(peer, "Only the admin can start, and a lobby of one is not a match")
			else:
				_on_match_started()
		_:
			push_error("server: unknown lobby action %d" % action)

	if ok:
		_broadcast_lobby()


## Everything that has to happen once the seats are final.
##
## Civs are only real at this point: a seat may have said "Random" right
## up until the start (D-048), so nothing that depends on a civ — the
## roster a player may build from, their opening stockpile — can be
## settled before now.
func _on_match_started() -> void:
	# The world is generated HERE, from the settings the lobby settled on
	# (D-049). Nothing before this point could have built it: the size,
	# seed and shape were still being chosen.
	_build_world()

	# Civs are only real now — a seat could have said "Random" a moment
	# ago — so this has to happen before anything that reads a roster or
	# an opening stockpile.
	for seat in _match.seats:
		_civs[int(seat["player"])] = StringName(seat["civ"])
	# Teams reach the simulation here, because combat needs them every
	# round and nothing before this point could have known them (D-050).
	_sim.teams = _match.team_map()
	print("server: match started — %s" % _seat_summary())

	# The world's concrete numbers, before anybody is admitted: a client
	# has to be able to generate the SAME terrain, and it cannot do that
	# from a preset name (D-049).
	var settings_packet := NetProtocol.encode_map_settings(_settings.to_dict())
	for peer in _clients:
		(peer as ENetPacketPeer).send(0, settings_packet, ENetPacketPeer.FLAG_RELIABLE)

	for seat in _match.seats:
		var player := int(seat["player"])
		var peer := _peer_of(player)
		if peer != null:
			_admit_player(peer, player)


func _peer_of(player: int) -> ENetPacketPeer:
	for peer in _clients:
		if int(_clients[peer]["player"]) == player:
			return peer
	return null


func _seat_summary() -> String:
	var parts := []
	for seat in _match.seats:
		parts.append("%s=%s%s" % [
			seat["name"], seat["civ"],
			" (admin)" if int(seat["player"]) == _match.admin_player else ""])
	return ", ".join(parts)


func _broadcast_lobby() -> void:
	# The lobby is the authority on settings while it is up, so the
	# server mirrors its choices before describing them.
	_settings = _match.map_settings
	var packet := NetProtocol.encode_lobby(_match.admin_player, _match.seats, _settings.to_dict())
	for peer in _clients:
		(peer as ENetPacketPeer).send(0, packet, ENetPacketPeer.FLAG_RELIABLE)


## Relay a chat message (D-050).
##
## The speaker is attached HERE, from the connection the message arrived
## on. A client sends text and nothing else — letting it name its own
## speaker would let it put words in another player's mouth, which is the
## same untrusted-client rule as orders (D-002), just less obvious when
## the payload is prose.
func _handle_chat(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var record = _clients.get(peer, null)
	if record == null:
		return
	var text := NetProtocol.sanitise_chat(NetProtocol.decode_chat_send(data))
	if text == "":
		return

	var player := int(record["player"])
	var speaker := "Player %d" % player
	if _match != null:
		var seat := _match.seat_of(player)
		if seat >= 0:
			speaker = String(_match.seats[seat]["name"])

	var packet := NetProtocol.encode_chat(speaker, text)
	for other in _clients:
		(other as ENetPacketPeer).send(0, packet, ENetPacketPeer.FLAG_RELIABLE)
	print("server: chat <%s> %s" % [speaker, text])
