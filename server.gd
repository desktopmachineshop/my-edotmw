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

## LoopbackPeer -> the same record shape as _clients, for AI seats
## (D-051). Kept OUT of _clients on purpose: several places legitimately
## treat that dictionary's keys as real sockets (ENet statistics, the
## lobby broadcast), and a duck-typed impostor there would be a null cast
## waiting to happen.
var _ai_clients := {}
var _ai_players: Array = []


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

## How many matches this server has finished with. Only a replay filename
## reads it, and only so that returning to the lobby and starting again
## (D-075) does not overwrite the previous match's log — a replay IS the
## curve log (D-016), so silently truncating one is losing the match.
var _matches_played := 0

var _match: MatchState
var _buildings: BuildingSim
var _economy: Economy

## Every node that has run dry this match (cell index -> true). The
## match-lifetime union of Economy.take_depleted()'s per-tick drains, kept
## because depletion is told to each client on ITS schedule — when that
## client can see the cell — not on the tick it happened.
var _depleted_nodes := {}
var _passable := PackedByteArray()

## Sampled once at map load and never recomputed — see the note where it
## is filled in.
var _spawn_points: Array[Vector2i] = []

## The scenario this server is playing, or null for a real opening
## (D-098). Everything about it is decided at startup: which one, where
## each seat's home is, and which cells are already taken.
var _scenario: ScenarioDef = null
## Home cell per SEAT INDEX, not per player id — the same keying as spawn
## assignment and colours, for the same reason (D-052: any modulo of a
## player id collides once AI ids start at 1000).
var _scenario_homes: Array[Vector2i] = []
## Cells already used by scenario placement, shared across every player so
## two seats' armies can never be dealt the same cell.
var _scenario_taken := {}

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

## squad -> Array[{ "def_id": StringName, "cell": Vector2i, "peer": ...,
## "facing": int }], FRONT of the array first.
##
## A QUEUE, not a single site (D-076 amendment) — the drag-to-build-a-line
## tool assigns one squad a whole run of segments, and it works through
## them one at a time rather than only ever remembering the last one
## asked for. An ordinary single build order (`C2S_ORDER_BUILD`) still
## REPLACES the whole queue with just itself; `C2S_ORDER_BUILD_QUEUE`
## appends instead — see `_enqueue_build`.
##
## Whichever site is at the front: if out of reach, the squad walks to it
## and `_advance_pending_builds` finishes the job on arrival, then starts
## the squad toward whatever is next in its queue. Cleared entirely the
## moment the player orders that squad anywhere else, because a builder
## told to go somewhere has been told to stop building.
var _pending_builds := {}
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

	# --scenario=<id> starts the match MID-GAME instead of playing the
	# opening (D-098). Bases already standing, armies already in reach.
	#
	# Loaded and validated HERE, before a socket exists, so a typo is a
	# refusal to start rather than a server that comes up and quietly
	# gives every player nothing. A scenario run that silently degraded to
	# an ordinary one would be the worst outcome: the test would pass, on
	# a world nobody asked for.
	var scenario_id := StringName(args.get("scenario", ""))
	if scenario_id != &"":
		_scenario = Scenario.by_id(scenario_id)
		if _scenario == null:
			push_error("server: no scenario '%s' under res://scenarios" % scenario_id)
			get_tree().quit(1)
			return
		var bad := _scenario.validate()
		if bad != "":
			push_error("server: scenario '%s' is invalid: %s" % [scenario_id, bad])
			get_tree().quit(1)
			return

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
	# --seed PINS the world; without it the default stands here and a
	# lobby rolls over it a few lines below (D-100). Every seedless
	# headless flow — bots, scenarios, test-load, test-client — takes this
	# branch and keeps the one reproducible map it has always run on.
	if args.has("seed"):
		_settings.pin_seed(int(args["seed"]))
	# Overridable from the command line for a no-lobby quick start (D-049
	# normally only reaches these through the lobby UI's sliders). Mirrors
	# --ai/--map/--seed above.
	if args.has("preset"):
		_settings.preset = StringName(args["preset"])
	_settings.apply_preset(TerrainPresetRoster.by_id(_settings.preset))
	if args.has("height_scale"):
		_settings.height_scale = float(args["height_scale"])

	# AI seats are registered through the same `add_player` path a human
	# join uses (D-051), which is what lets `_start_if_ready` auto-start a
	# no-lobby match the moment enough participants are in. Counted into
	# `players_expected` up front so seating the FIRST ai does not start
	# the match early — before the rest of the AIs, or the human,
	# have joined and had their `Random` civ resolved. A seat added after
	# the match is already RUNNING never gets its civ resolved at all: it
	# keeps the literal string "random", which matches no unit's `civ`
	# field, so every civ-specific building (a barracks, never a neutral
	# one like the town centre) offers nothing to train.
	var ai_wanted := int(args.get("ai", 0))

	_match = MatchState.new()
	# `maxi` around the SUM, not around the human count alone.
	#
	# It used to be `maxi(1, players) + ai_wanted`, which cannot express "no
	# humans at all": `just ai-ladder` asked for `--players=1 --ai=2`, so the
	# server expected three participants, two arrived, and every ladder match
	# stayed in Phase.LOBBY for its whole cap while the recipe reported the
	# resulting nothing as a draw and blamed the AI. `--players=0 --ai=2` is
	# a real two-computer match now, and the default (1 human, no AI) is
	# unchanged.
	_match.players_expected = maxi(1, int(args.get("players", 1)) + ai_wanted)
	_match.require_admin_start = int(args.get("lobby", 0)) != 0
	_match.squad_cap = _config.squad_cap
	_match.map_settings = _settings

	# A LOBBY match rolls its map (D-100), so two matches on the same
	# settings are two different places — which is what MapSettings.seed
	# has claimed since D-049 and nothing did. Only the lobby rolls: a
	# no-lobby start is a test harness or a dev launch, and those want the
	# same world every run. The admin can pin any seed from the spinner,
	# which is how a good map is played twice on purpose.
	if _match.require_admin_start and not _settings.seed_pinned:
		print("server: lobby rolled map seed %d" % _settings.roll_seed())

	# The civ draw follows the MAP seed, so a pinned seed reproduces the
	# whole match setup and not merely the terrain (D-100). It has to come
	# after the roll above, or every lobby would draw from the same
	# sequence regardless of where it was being played.
	_match.civ_seed_base = hash(_config.id)
	_match.reseed_civ_rng()
	# Dev-testing cheats (C2S_CHEAT_*) are refused unless this is set, either
	# here or later by the lobby admin toggling it live — see MatchState.
	# sandbox's own doc for why that stays legal mid-match.
	_match.sandbox = int(args.get("sandbox", 0)) != 0

	# In lobby mode the world does NOT exist yet, and cannot: its size,
	# seed and shape are all still being chosen (D-049). This is why
	# terrain generation moved out of startup — the old code built a map
	# the moment the server booted, which was before anybody had asked for
	# one, and the client did the same on connect. The lobby has nothing
	# behind it because there is genuinely nothing there yet.
	if not _match.require_admin_start:
		_build_world()
		# AI opponents without a lobby, so `run-client` and the load test can
		# have real opposition (D-051). `ai_wanted` is computed above, not
		# here, so it can also fold into `players_expected`.
		#
		# --random-civs=1 draws every seat's civ from the same
		# CivRoster.resolve(RANDOM, ...) the lobby uses instead of the
		# default round-robin, and reuses civ_rng so a rerun with the same
		# --seed reproduces the same draw (D-047's replay obligation). Off
		# by default: round-robin is what guarantees test-load's "both civs
		# fielded" check (D-046 criterion 10) without depending on a coin
		# flip.
		var random_civs := int(args.get("random-civs", 0)) != 0
		var civs := CivRoster.ids()
		for i in range(ai_wanted):
			var ai_civ: StringName = CivRoster.resolve(CivRoster.RANDOM, _match.civ_rng) \
				if random_civs \
				else (civs[i % maxi(civs.size(), 1)] if not civs.is_empty() else &"")
			_seat_ai(1000 + i, ai_civ)

		# Human seats aren't known by id until they connect (`_next_player`
		# hands them out in `_on_connect`), but the expected COUNT is —
		# `--players` — and nothing accepts a connection until the ENet host
		# below is bound. Pre-drawing here means `_civ_of`'s lookup finds a
		# cached entry the moment a human is admitted, rather than falling
		# back to round-robin only for AI seats to have been randomised.
		if random_civs:
			var human_players := maxi(1, int(args.get("players", 1)))
			for p in range(1, human_players + 1):
				_civs[p] = CivRoster.resolve(CivRoster.RANDOM, _match.civ_rng)

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
	_depleted_nodes.clear()
	_economy.generate(terrain, 1)
	# Fairness on an asymmetric map is a post-pass now, not a property of
	# the generator (D-036 revised): every start is guaranteed a minimum
	# of each resource within reach.
	_economy.balance_for_spawns(_spawn_points, _passable,
		_config.fairness_radius, _config.fairness_quota)
	_sim.economy = _economy
	print("server: %d resource nodes generated" % _economy.node_count())

	# Scenario homes, once, now that spawn points and passability exist
	# (D-098). Computed for every SEAT rather than lazily per join, because
	# `separation` places seats relative to one another and the second
	# player's home is not a function of the second player alone.
	#
	# Printed as a structured marker, not prose: a scenario run must be
	# identifiable in a log without anyone having to know what a normal
	# opening looks like. `test-scenario` greps for exactly this, so a run
	# that silently played the ordinary opening fails rather than passing
	# as a very fast scenario.
	if _scenario != null:
		# Enough homes for every seat the MAP can hold, not just the
		# players announced at startup.
		#
		# This was `players_expected`, which defaults to 1 and is not
		# raised by `just up` — so a four-bot scenario run computed ONE
		# home, every seat indexed into it, and four armies spawned in a
		# pile ten cells from where the scenario said. It still looked
		# healthy: bots connected, combat happened, casualties were high
		# BECAUSE everyone started on top of each other. Sizing on the
		# map's own seat count makes the number of joiners irrelevant
		# rather than load-bearing.
		var seats: int = maxi(maxi(1, _match.players_expected), _spawn_points.size())
		_scenario_homes = Scenario.homes(_scenario, seats, space,
			_passable, _spawn_points)
		print("server: SCENARIO id=%s seats=%d separation=%d squads_each=%d buildings_each=%d" % [
			_scenario.id, seats, _scenario.separation,
			_scenario.squad_count(), _scenario.buildings.size()])


	# Combat's RNG must be seeded from map configuration, never wall-clock
	# (D-024) — MapConfig has no dedicated seed field, so this derives one
	# deterministically from fields it already has. Same map, same seed,
	# every run: that is what lets a replay reproduce the exact battle
	# that happened rather than a different one (D-016).
	_sim.combat_seed = NetProtocol.seed_from(String(_config.id), _settings.width, _settings.height) + _settings.seed

	_replay = ReplayLog.new()
	# Replays are the curve log (D-016), written from M1 onward.
	# The match counter keeps a second match on the same server from
	# overwriting the first one's log (D-075); the first match still writes
	# the plain per-port name every existing recipe and doc expects.
	var replay_path := "res://artifacts/replay-%d.edmw" % _port
	if _matches_played > 0:
		replay_path = "res://artifacts/replay-%d-match%d.edmw" % [_port, _matches_played + 1]
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
		# Rubble is walkable again. Cheap to check — the list is empty on
		# almost every tick — and skipping it would leave an invisible wall
		# where a razed town hall used to be.
		if not _sim.destroyed_buildings.is_empty():
			_refresh_passability()
		# Playtest fix: a wall-family building only blocks ground movement
		# once complete (BuildingSim.blocking_cells) — an unfinished
		# segment doesn't yet, so a builder walking a drag-built chain
		# can't be sealed into a pocket by its own still-under-
		# construction wall. That makes completion, not just placement or
		# destruction, a passability-changing event; without this refresh
		# the flow field would keep treating a just-finished wall as open
		# until some unrelated building change happened to touch it.
		if not _sim.completed_buildings.is_empty():
			_refresh_passability()
		_update_auto_gates()
		_advance_pending_builds()
		_advance_match()
		# AI seats think on the server's clock, after the world has moved
		# but before it is replicated, so they act on the same tick a human
		# would be reacting to (D-051).
		for brain in _ai_players:
			brain.set_time(_sim.time)
			brain.update(_sim.time)
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

	var fielded := _civs_fielded()
	var civ_parts := []
	for civ in fielded:
		civ_parts.append("%s=%d" % [civ, fielded[civ]])
	civ_parts.sort()
	# A structured marker, not prose: `just test-load` fails the run if
	# fewer than two civs ever fielded a squad (D-046 criterion 10).
	print("server: CIVS_FIELDED %d of %d — %s" % [
		fielded.size(), CivRoster.ids().size(), ", ".join(civ_parts)])

	for brain in _ai_players:
		print("server: %s" % brain.stats_line())
	print("server: MATCH_RESULT winner=%d phase=%d" % [
		_match.winner, int(_match.phase)])

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
	# The same shape for resources (D-061): the best-informed client must
	# know FEWER nodes than exist, or positions are not being gated.
	print("server: FOG_TOTAL_NODES=%d" % (_economy.node_count() if _economy != null else 0))


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
		# Re-checked every iteration, not just on entry. Handling an event
		# can end the server from inside this loop: since D-075 the last
		# client disconnecting calls `_shutdown()`, which destroys the host
		# and nulls it — and the next `service()` was then made on nothing.
		if _shutting_down or _host == null:
			return
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
	var started := _match.add_player(player)
	if _match.phase == MatchState.Phase.LOBBY:
		_broadcast_lobby()
		# Tick 0 while still in the lobby: the match has not begun, so
		# there is no elapsed time to report and the HUD's clock stays at
		# zero rather than counting how long people have been sitting in
		# the seat-picking screen.
		peer.send(0, NetProtocol.encode_welcome(player, _settings.width, _settings.height,
			PackedInt32Array(), _spawn_cell_indices(), _match.squad_cap, 0),
			ENetPacketPeer.FLAG_RELIABLE)
		_peak_clients = maxi(_peak_clients, _clients.size())
		return

	# The returned ids go to the client so it knows what it starts with.
	# They are deliberately NOT cached on the connection record: ownership
	# lives in the sim (see _validated_squad), and a second copy here is
	# what silently stopped every produced squad from taking orders.
	_peak_clients = maxi(_peak_clients, _clients.size())
	if started:
		_note_match_started()
	_admit_player(peer, player)


## Give a player their opening — squads, stockpile, and everything a
## client needs to draw the world.
##
## Shared by the two ways a match can begin: joining an already-running
## server, and the admin starting a lobby (D-048). It has to be one
## function, because "what a player starts with" is exactly the kind of
## thing that drifts when written twice — the same reasoning that made
## ownership read from the sim rather than a per-connection copy.
## `peer` is deliberately untyped: it is an ENetPacketPeer for a human
## and a LoopbackPeer for an AI seat (D-051), and both answer send().
func _admit_player(peer, player: int) -> void:
	# The world's concrete numbers FIRST, because the client cannot build
	# terrain without them (D-049) and will sit on an empty scene until
	# they arrive.
	#
	# Sent here rather than only at match start: a match begins two ways —
	# an admin pressing start in a lobby, or a player connecting to a
	# server that has no lobby — and hanging this off the first meant
	# every non-lobby client drew no terrain at all. Every counter still
	# passed (squads drawn, soldiers derived, zero desyncs, colours in the
	# frame) because the HUD and the soldiers were fine. Only the world
	# was missing, and only looking at the picture found it.
	# The seat list too, so the client knows every player's colour
	# (D-052) whichever way the match began. Small, and sent once.
	# Playtest fix: this call omitted sandbox/instant_build/ai_economy_only,
	# which default to false in `encode_lobby` — so a player joining a
	# --lobby=0 match (every quick-test) always saw sandbox mode reported
	# OFF regardless of the launch flag, and the debug panel never opened.
	# `_broadcast_lobby` (the actual lobby phase) already passed these
	# correctly; this direct-join path just never got them.
	peer.send(0, NetProtocol.encode_lobby(_match.admin_player, _match.seats,
		_settings.to_dict(), int(_match.phase),
		_match.sandbox, _match.instant_build, _match.ai_economy_only), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, NetProtocol.encode_map_settings(_settings.to_dict()),
		ENetPacketPeer.FLAG_RELIABLE)

	var squads := _spawn_squads_for(player)

	# The new player's own squads need a vision stamp before anything asks
	# visible_to() about them — own squads are always visible regardless
	# (SquadSim.visible_to's owner check), but without this the joiner
	# would see nothing OF OTHERS until the next scheduled tick-driven
	# rebuild (vision_recompute_every_ticks), which reads as "fog is broken
	# for one tick after joining" rather than a real gap. A join is rare
	# enough that paying a full rebuild here is not a real cost concern.
	_sim.recompute_vision_now()

	# The cap and the clock, so a client joining a match already in
	# progress starts its HUD at the right numbers rather than at zero and
	# counting up from whenever IT arrived.
	peer.send(0, NetProtocol.encode_welcome(player, _config.width, _config.height, squads,
		_spawn_cell_indices(), _match.squad_cap, _sim.tick_count),
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
	_record_for(peer)["visible"] = _dict_from_ids(_sim.visible_to(player))

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
	# Only the resources this player can currently SEE (D-061).
	#
	# This used to send every node on the map, once, to everybody — the
	# comment said "a player cannot be asked to send workers to a node
	# they have no way of finding", which is true and was solved the wrong
	# way. Knowing every resource position from the moment you join tells
	# you where an opponent must expand and where to raid, without
	# scouting for any of it, and a modified client could read it straight
	# out. That is precisely the class of knowledge D-004's curve gating
	# and D-025's fog exist to withhold.
	#
	# The rest arrive as they are revealed, in `_replicate`.
	_send_visible_nodes(peer, player, _record_for(peer))

	# Registration happened at the top of _on_connect, before the lobby
	# branch — a player has to be seated before anyone can decide whether
	# there is a lobby to wait in.
	print("server: player %d joined with %d squads (%d connected) — match %s" % [
		player, squads.size(), _clients.size(), _match.describe()])


func _send_squad_info(peer, player: int) -> void:
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
	var recipients := _recipients()
	for peer in recipients:
		_send_squad_info(peer, int(recipients[peer]["player"]))

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
	var record = _record_for(peer)
	if record != null:
		var player := int(record["player"])

		# There may be no world to leave. Since D-075 a client spends real
		# time in the lobby — arriving before the first match and returning
		# between matches — and `_sim` does not exist in either. This used
		# to be unconditional, which was survivable only because leaving
		# always meant a disconnect from a RUNNING match.
		if _sim != null:
			_sim.replicator.forget_client(player)

			# An abandoned army does not get to keep standing on the field
			# (D-033). Wiping it is the *cause* of defeat; MatchState's
			# ordinary "no living squads" rule notices the effect on the next
			# tick, so "defeated" keeps exactly one definition. The wipe comes
			# back as casualty events, which replicate through the path
			# clients already understand.
			_match.mark_disconnected(player)
			_pending_events.append_array(_sim.eliminate_player(player))
		else:
			# Gone from the lobby, so the seat goes too — otherwise it sits
			# there forever as a player who will never arrive, and the admin
			# role never passes on. `remove_human_seat` had been written for
			# this and never called from anywhere but its own test.
			_match.remove_human_seat(player)

		print("server: player %d left (%d connected)" % [player, _clients.size() - 1])
	_clients.erase(peer)
	if _clients.is_empty() and _sim != null and _sim.squad_count() > 0:
		_print_summary("last client left")

	# No humans, no server (D-075).
	#
	# AI seats deliberately do not count: they live in `_ai_clients` and
	# have no socket to disconnect (D-051), so a match of nothing but
	# computers would otherwise hold the port forever. That is not
	# hypothetical — this session began by clearing a server that had been
	# ticking an empty world for six hours with `clients=0`.
	#
	# Reached only from a disconnect, so it cannot fire on a server that
	# nobody has connected to yet: `just lobby` waits as long as you like.
	if _clients.is_empty():
		print("server: last human client left — shutting down")
		_shutdown()
		get_tree().quit(0)


func _on_receive(peer: ENetPacketPeer) -> void:
	while peer.get_available_packet_count() > 0:
		var data := peer.get_packet()
		if data.size() < 1:
			continue
		_dispatch(peer, data)


## One place a command is acted on, whether it arrived over a socket or
## came from an AI player sitting in this process (D-051).
##
## AI orders go through the SAME handlers and therefore the same checks:
## ownership read from the sim, the squad cap, affordability, the match
## actually running. An AI that reached into SquadSim directly could do
## things no human could, and the difference would stay invisible until
## somebody wondered why it never ran out of food.
func _dispatch(peer, data: PackedByteArray) -> void:
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
			NetProtocol.C2S_ORDER_BUILD_QUEUE:
				_handle_order_build_queue(peer, data)
			NetProtocol.C2S_CHEAT_ADD_RESOURCES:
				_handle_cheat_add_resources(peer, data)
			NetProtocol.C2S_CHEAT_SPAWN_UNIT:
				_handle_cheat_spawn_unit(peer, data)
			NetProtocol.C2S_CHEAT_SPAWN_BUILDING:
				_handle_cheat_spawn_building(peer, data)
			NetProtocol.C2S_ORDER_PRODUCE:
				_handle_order_produce(peer, data)
			NetProtocol.C2S_ORDER_GATHER:
				_handle_order_gather(peer, data)
			NetProtocol.C2S_ORDER_RALLY:
				_handle_order_rally(peer, data)
			NetProtocol.C2S_ORDER_BUILDING_TARGET:
				_handle_order_building_target(peer, data)
			NetProtocol.C2S_ORDER_FORMATION:
				_handle_order_formation(peer, data)
			NetProtocol.C2S_ORDER_GATE_STATE:
				_handle_order_gate_state(peer, data)
			NetProtocol.C2S_ORDER_GATE_MODE:
				_handle_order_gate_mode(peer, data)
			NetProtocol.C2S_CHAT:
				_handle_chat(peer, data)
			NetProtocol.C2S_LOBBY:
				_handle_lobby_command(peer, data)
			NetProtocol.C2S_LEAVE_MATCH:
				_handle_leave_match(peer)
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
func _validated_squad(peer, squad: int) -> int:
	var record = _record_for(peer)
	if record == null:
		return -1
	if not _match.is_running():
		# SAY SO. This dropped the order without a word for four milestones,
		# and the silence is most of what made the AI's lost founding order
		# so hard to find: a well-formed order, sent, accepted by the socket,
		# and gone. D-034's rule is that a refused order tells the player
		# why; there is no reason for this one to be the exception.
		_notify(peer, "The match has not started")
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


func _handle_order_move(peer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_move(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return
	# A builder told to go somewhere has been told to stop building.
	_pending_builds.erase(squad)
	# from_index normalises, so a nonsense destination wraps into the map
	# rather than going out of bounds (D-008).
	_sim.order_move(squad, _sim.space.from_index(int(order["destination"])))


func _handle_order_attack_move(peer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_attack_move(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return
	_pending_builds.erase(squad)
	_sim.order_attack_move(squad, _sim.space.from_index(int(order["destination"])))


## Change a squad's formation (D-058).
##
## The shape is checked against the offered set here rather than trusted:
## an unknown one would fall through `Formation.slot_offset`'s default and
## silently stack the squad into a line, with only a push_error nobody
## reads — and a client is not the authority on what formations exist.
func _handle_order_formation(peer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_formation(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return

	var shape := String(order["shape"])
	# Against the OFFERED set from /formations (D-058), not a list here.
	# A formation a player is not offered is not one they may order, and
	# an unknown one would fall through to a line with only a push_error
	# nobody reads.
	if not FormationRoster.offered_ids().has(StringName(shape)):
		_notify(peer, "No such formation")
		return
	_sim.set_shape(squad, shape)


## Set where a building sends what it produces.
##
## Ownership is checked here like every other order (D-002): a client that
## could set an opponent's rally point could walk their army off a cliff.
func _handle_order_rally(peer, data: PackedByteArray) -> void:
	var record = _record_for(peer)
	if record == null or not _match.is_running():
		return

	var order := NetProtocol.decode_order_rally(data)
	var building := BuildingSim.local_id(int(order["building"]))
	if building < 0 or building >= _buildings.building_count():
		return
	if _buildings.owner_of(building) != int(record["player"]):
		_notify(peer, "That is not yours to give orders to")
		return

	var cell := _sim.space.from_index(int(order["cell"]))
	_buildings.set_rally(building, cell)
	_notify(peer, "Rally point set")


## Focus-fire an armed building on one enemy squad (D-032's manual half —
## `Combat.resolve_buildings` otherwise always picks the nearest enemy
## itself). Ownership and "is this building even armed" are checked here
## the same as every other order (D-002); `target == -1` clears it back to
## automatic. Nothing else validates the target every tick after this —
## `resolve_buildings` clears it itself the moment the squad dies, so a
## stale id can never be silently reused for a different squad later.
func _handle_order_building_target(peer, data: PackedByteArray) -> void:
	var record = _record_for(peer)
	if record == null or not _match.is_running():
		return

	var order := NetProtocol.decode_order_building_target(data)
	var building := BuildingSim.local_id(int(order["building"]))
	if building < 0 or building >= _buildings.building_count():
		return
	if _buildings.owner_of(building) != int(record["player"]):
		_notify(peer, "That is not yours to give orders to")
		return

	var target := int(order["target"])
	if target == -1:
		_buildings.set_forced_target(building, -1)
		_notify(peer, "Target cleared")
		return

	var def := _buildings.def_of(building)
	if def == null or def.damage <= 0.0:
		_notify(peer, "That building cannot be given a target")
		return
	if target < 0 or target >= _sim.squad_count() or _sim.alive_of(target) <= 0:
		return
	if _sim.are_allied(_sim.owner_of(target), int(record["player"])):
		_notify(peer, "That is not an enemy")
		return

	_buildings.set_forced_target(building, target)
	_notify(peer, "Target set")


## Shared validation for a building order this player must own (D-076).
## Mirrors `_validated_squad`'s shape and reasoning: one owner of the check
## rather than a copy per handler. Returns the local building id, or -1 if
## the order must be dropped.
func _validated_building(peer, building_wire_id: int) -> int:
	var record = _record_for(peer)
	if record == null or not _match.is_running():
		return -1
	var building := BuildingSim.local_id(building_wire_id)
	if building < 0 or building >= _buildings.building_count():
		return -1
	if _buildings.owner_of(building) != int(record["player"]):
		_notify(peer, "That is not yours to give orders to")
		return -1
	return building


## ORDER_GATE_STATE: open or close a gate directly (D-076). Only honored
## in manual mode — an auto-mode gate keeps deciding for itself, so a
## stray click cannot fight the automation every check cycle.
func _handle_order_gate_state(peer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_gate_state(data)
	var building := _validated_building(peer, int(order["building"]))
	if building < 0:
		return
	if not _buildings.def_of(building).is_gate:
		_notify(peer, "That is not a gate")
		return
	if _buildings.gate_mode(building) != BuildingSim.GATE_MODE_MANUAL:
		_notify(peer, "Switch to manual mode first")
		return
	_buildings.set_gate_open(building, bool(order["open"]))
	_refresh_passability()


## ORDER_GATE_MODE: switch a gate between manual and automatic control
## (D-076).
func _handle_order_gate_mode(peer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_gate_mode(data)
	var building := _validated_building(peer, int(order["building"]))
	if building < 0:
		return
	if not _buildings.def_of(building).is_gate:
		_notify(peer, "That is not a gate")
		return
	var mode := int(order["mode"])
	if mode != BuildingSim.GATE_MODE_MANUAL and mode != BuildingSim.GATE_MODE_AUTO:
		return
	_buildings.set_gate_mode(building, mode)


## Tell a client about resource nodes it can see and has not been told
## about yet (D-061).
##
## PERSISTENT-EXPLORED, exactly like buildings (D-030): once you have seen
## a forest you remember where it was, and a node cannot be un-known. So
## the per-client set only ever grows, and a node already sent is never
## resent — an explored map costs nothing per tick.
##
## Nodes are static, so this needs no conceal event and no ghost: unlike a
## squad, a forest does not move away while you are not looking.
func _send_visible_nodes(peer, player: int, record) -> void:
	if record == null or _economy == null or _sim == null:
		return
	var known: Dictionary = record.get("nodes_known", {})
	var fresh := []
	for cell in _economy.nodes:
		if known.has(cell):
			continue
		# A worked-out node stays in the dictionary (that is how depletion
		# is remembered) but it is not news: a scout arriving AFTER the
		# felling must not be told a stump is a resource — it was never
		# known here, so it needs no depletion event either.
		if _depleted_nodes.has(cell):
			continue
		if not _sim.vision.is_visible(player, int(cell)):
			continue
		known[cell] = true
		fresh.append(cell)
	record["nodes_known"] = known

	if not fresh.is_empty():
		peer.send(0, NetProtocol.encode_nodes(_economy.node_entries(fresh)),
			ENetPacketPeer.FLAG_RELIABLE)

	# Fellings, on this client's schedule: a known node that has run dry is
	# reported when the client can SEE the cell — immediately for whoever
	# is standing there, on next sight for a player behind the fog, never
	# for one who never returns (their client keeps drawing the tree, the
	# same staleness a building ghost has, D-030). `told` only ever grows,
	# so an explored, worked-out map costs nothing per tick.
	var told: Dictionary = record.get("nodes_depleted_told", {})
	var felled := []
	for cell in _depleted_nodes:
		if told.has(cell) or not known.has(cell):
			continue
		if not _sim.vision.is_visible(player, int(cell)):
			continue
		told[cell] = true
		felled.append(cell)
	record["nodes_depleted_told"] = told

	if not felled.is_empty():
		peer.send(0, NetProtocol.encode_nodes_depleted(felled),
			ENetPacketPeer.FLAG_RELIABLE)


## Terrain passability with living buildings stamped out of it, so squads
## walk AROUND a town hall instead of through it (D-007).
##
## Rebuilt wholesale from `_passable` rather than edited in place, because
## a destroyed building has to give its ground back and an in-place edit
## would need to remember what the terrain said underneath. Called only
## when the set of buildings changes — raising one, losing one — never per
## tick, and `SquadSim.set_passable` discards cached flow fields, which is
## exactly right: a field solved before a wall existed routes through it.
func _refresh_passability() -> void:
	if _sim == null:
		return
	var blocked := _passable.duplicate()
	# blocking_cells(), not occupied_cells(): an OPEN gate still stands
	# (still occupies its cell for placement/combat purposes) but is
	# passable while open (D-076), so its cell must not be blocked here
	# even though the building itself is still very much there.
	# Where living squads are standing RIGHT NOW, so a building completing
	# around one cannot seal it in.
	#
	# Playtest fix, and a direct consequence of D-096. A wall used to block
	# exactly its own cell, so a builder standing beside the segment it had
	# just finished was safe. A wall now blocks every cell its body crosses
	# — a band, not a point — and the crew that raised it is frequently
	# inside that band when it completes. Reported as gatherers stuck in
	# garrison walls and towers during building.
	#
	# It cannot be fixed by ordering them out afterwards: a squad standing
	# on an impassable cell has no flow-field value to follow (D-040 — an
	# unreachable cell reads as "no path"), so the order is cancelled and
	# the squad stays exactly where it is. The cell has to REMAIN passable
	# until they are actually out of it.
	var occupied := {}
	for squad in range(_sim.squad_count()):
		if _sim.alive_of(squad) > 0:
			occupied[_sim.space.index(_sim.cell_of(squad))] = squad

	var trapped := []
	for index in _buildings.blocking_cells():
		if index >= blocked.size():
			continue
		if occupied.has(index):
			# Left passable this pass, and the squad shoved clear. The cell
			# blocks on the next refresh once nobody is standing in it, so
			# this is a brief hole rather than a permanent one — a squad
			# cannot idle inside a wall to keep it open, because it is being
			# actively walked out.
			trapped.append(occupied[index])
			continue
		blocked[index] = 0
	_sim.set_passable(blocked)

	for squad in trapped:
		var out_cell := _nearest_open_cell(_sim.cell_of(squad), blocked)
		if out_cell != _sim.cell_of(squad):
			_sim.force_move(squad, out_cell)


## The closest cell to `from` that `passable` says is open, or `from` itself
## if nothing near enough is.
##
## `disk_offsets` is sorted nearest-first (D-067), so the first open cell it
## finds IS the closest — this is the "walk outward until you find one"
## the standing rule explicitly permits, rather than a `distance()` scan.
func _nearest_open_cell(from: Vector2i, passable: PackedByteArray) -> Vector2i:
	for offset in TorusSpace.disk_offsets(NEAREST_OPEN_CELL_RADIUS):
		var candidate := _sim.space.normalize(from + offset)
		var index := _sim.space.index(candidate)
		if index < passable.size() and passable[index] != 0:
			return candidate
	return from


## How far to look for open ground when shoving a squad out of a building
## that completed around it. A wall band is one or two cells thick, so this
## only has to clear that plus a margin — searching further would mean
## teleporting a squad somewhere it never chose to be.
const NEAREST_OPEN_CELL_RADIUS := 4


## How many ticks pass between looks at auto-mode gates (D-076). Every
## tick would work but is not needed — a gate opening or closing triggers
## SquadSim.set_passable's documented full flow-field flush, so this bounds
## how often that can happen, the same way D-040 bounds flow-field work
## with a per-tick CELL budget rather than solving fields unbounded.
const AUTO_GATE_CHECK_TICKS := 3

## How close (in cells) an owner's own squad has to stand to hold an
## auto-mode gate open (D-076).
const AUTO_GATE_RADIUS := 2


## Open or close every auto-mode gate, based on whether its owner has a
## living squad nearby. Bounded to run every AUTO_GATE_CHECK_TICKS ticks —
## see that constant's doc for why — and costs nothing at all when no gate
## is in auto mode.
func _update_auto_gates() -> void:
	if _sim.tick_count % AUTO_GATE_CHECK_TICKS != 0:
		return

	var gates := []
	for i in range(_buildings.building_count()):
		var def := _buildings.def_of(i)
		if def.is_gate and not _buildings.is_destroyed(i) and _buildings.is_complete(i) \
				and _buildings.gate_mode(i) == BuildingSim.GATE_MODE_AUTO:
			gates.append(i)
	if gates.is_empty():
		return

	# One bucket pass over living squads, reused for every gate checked
	# this cycle, instead of a fresh distance scan per gate — the standing
	# "reach for a shared scan, don't repeat a distance test per candidate"
	# rule TorusSpace.disk_offsets and its callers already follow.
	var buckets := {}
	for squad in range(_sim.squad_count()):
		if _sim.alive_of(squad) <= 0:
			continue
		var index := _sim.space.index(_sim.cell_of(squad))
		if not buckets.has(index):
			buckets[index] = []
		(buckets[index] as Array).append(squad)

	var changed := false
	for i in gates:
		var owner := _buildings.owner_of(i)
		var gate_cell := _buildings.cell_of(i)
		var near_owner := false
		for offset in TorusSpace.disk_offsets(AUTO_GATE_RADIUS):
			var neighbor := _sim.space.index(gate_cell + offset)
			for squad in buckets.get(neighbor, []):
				if _sim.owner_of(squad) == owner:
					near_owner = true
					break
			if near_owner:
				break
		if _buildings.is_gate_open(i) != near_owner:
			_buildings.set_gate_open(i, near_owner)
			changed = true

	if changed:
		_refresh_passability()


## Finish any build whose builder has now walked into reach.
##
## Runs once per tick, over a dictionary that is empty in the ordinary
## case, so it costs nothing when nobody is walking to a building site.
##
## Every rule is re-checked on arrival rather than trusted from when the
## order was given: the ground may have been built on by someone else
## while the builder walked, and the wallet may have been spent. Checking
## at order time and committing at arrival would be a way to buy a
## building with money you no longer have.
func _advance_pending_builds() -> void:
	if _pending_builds.is_empty():
		return
	for squad in _pending_builds.keys():
		var queue: Array = _pending_builds[squad]
		if queue.is_empty():
			_pending_builds.erase(squad)
			continue

		# A builder that died on the way is not building anything — the
		# rest of its queue lapses with it.
		if squad >= _sim.squad_count() or _sim.alive_of(squad) <= 0:
			_pending_builds.erase(squad)
			continue

		var intent: Dictionary = queue[0]
		var cell: Vector2i = intent["cell"]
		if _sim.space.distance(_sim.cell_of(squad), cell) > BUILD_REACH_CELLS:
			continue

		queue.pop_front()
		if queue.is_empty():
			_pending_builds.erase(squad)
		else:
			_pending_builds[squad] = queue

		_finish_build(intent["peer"], squad,
			BuildingSim.def_by_id(StringName(intent["def_id"])), cell,
			int(intent.get("facing", 0)), intent.get("offset", Vector2.ZERO))

		# Straight on to the next queued segment (D-076's drag-line tool),
		# rather than waiting for the player to click again — the whole
		# point of queueing several sites is that one order covers all of
		# them. A dead or otherwise-invalidated squad was already handled
		# above and never reaches this line.
		if not queue.is_empty() and _sim.alive_of(squad) > 0:
			_sim.order_move(squad, queue[0]["cell"])


## Found a building (D-031). Every rule is enforced here rather than
## trusted from the client (D-002): who owns the squad, whether that KIND
## of squad may build this kind of building, whether the ground takes a
## foundation, and whether the builder is anywhere near the site.
##
## An ordinary single order (as opposed to `_handle_order_build_queue`)
## REPLACES the squad's whole pending queue with just this one site — the
## existing "click somewhere else to change your mind" behaviour, now
## expressed as "start a fresh one-item queue" rather than as its own code
## path.
func _handle_order_build(peer, data: PackedByteArray) -> void:
	_do_order_build(peer, data, true)


## Same validation as `_handle_order_build`, but APPENDS to the squad's
## existing queue instead of replacing it (D-076's drag-to-build-a-line
## tool). The client sends one plain ORDER_BUILD to start a squad's
## assigned run, then ORDER_BUILD_QUEUE for every further segment in it.
func _handle_order_build_queue(peer, data: PackedByteArray) -> void:
	_do_order_build(peer, data, false)


func _do_order_build(peer, data: PackedByteArray, replace: bool) -> void:
	var order := NetProtocol.decode_order_build(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return

	var def := BuildingSim.def_by_id(StringName(order["def_id"]))
	if def == null:
		push_error("server: client asked for unknown building '%s'" % order["def_id"])
		return

	# D-076: every building carries a facing; wrapped rather than trusted,
	# since the client is not (D-002). Only into a generic safe byte range
	# here — the real wrap (0-5 for a wall/access-tower's hex direction, or
	# 0-255 for a freestanding building's continuous cosmetic angle) is
	# `def`-dependent, and `BuildingSim.add_building` already has `def` and
	# decides it there, once, rather than this duplicating that judgement
	# and risking disagreeing with it.
	var facing := posmod(int(order.get("facing", 0)), 256)

	# Every refusal below tells the player WHY. Silence made a refused
	# order indistinguishable from a broken key during the first playtest.
	if not BuildingSim.can_build(def, _sim.def_of(squad).archetype):
		_notify(peer, "%s cannot build a %s" % [_sim.def_id_of(squad), def.display_name])
		return

	var cell := _sim.space.from_index(int(order["cell"]))
	if not _is_buildable(cell, def, _sim.owner_of(squad)):
		_notify(peer, "Cannot build there — water, mountain, or already occupied")
		return

	# Somebody else's ground (D-062). Refused up front as well as on
	# arrival, so a player is told immediately rather than watching a
	# builder walk twenty seconds to be turned away.
	var claimed := _claimed_against(cell, _sim.owner_of(squad))
	if claimed >= 0:
		_notify(peer, "Too close to an enemy %s" % _buildings.def_of(claimed).display_name)
		return

	# Another building's footprint, complete or still only pending (see
	# _footprint_conflict) — checked up front so a second builder is told
	# immediately rather than walking all the way there to be turned away.
	if _footprint_conflict(cell, def.footprint_radius, squad):
		_notify(peer, "Too close to another building")
		return

	# Sub-cell offset (D-096), clamped rather than trusted: the client picks
	# where along a dragged line each segment sits, and an unclamped value
	# would let a crafted packet plant a wall an arbitrary distance from the
	# cell whose buildability was just checked above. One hex's width is the
	# most any legitimate offset can be.
	var reach := _sim.space.hex_size * TorusSpace.SQRT_3
	var offset := Vector2(
		clampf(float(order.get("offset_x", 0.0)), -reach, reach),
		clampf(float(order.get("offset_z", 0.0)), -reach, reach))

	_enqueue_build(squad, {
		"def_id": def.id, "cell": cell, "peer": peer, "facing": facing,
		"offset": offset,
	}, replace)
	_notify(peer, "Moving to build a %s" % def.display_name)


## Add one site to a squad's build queue (D-076 amendment), starting it
## walking (or building immediately, if already in reach) when it becomes
## the front of an otherwise-idle queue. `replace` clears whatever was
## queued before appending — see `_handle_order_build`'s doc for why that
## is still the right default for an ordinary single click.
##
## "Too far? WALK THERE. Do not refuse." still holds: this never rejects
## on distance, it only decides whether to build now or queue the walk —
## the server telling the player to move closer by hand would be doing by
## request what it can already do itself (the mistake this replaced).
func _enqueue_build(squad: int, intent: Dictionary, replace: bool) -> void:
	var queue: Array = [] if replace else _pending_builds.get(squad, [])
	var was_empty := queue.is_empty()
	queue.append(intent)
	_pending_builds[squad] = queue

	if not was_empty:
		return  # something else is already in progress; this waits its turn

	var cell: Vector2i = intent["cell"]
	if _sim.space.distance(_sim.cell_of(squad), cell) <= BUILD_REACH_CELLS:
		queue.pop_front()
		if queue.is_empty():
			_pending_builds.erase(squad)
		else:
			_pending_builds[squad] = queue
		# Cost is charged on arrival (inside _finish_build), not here — a
		# squad already standing on the site still pays only once it is
		# actually committed, same as the walked-there path.
		_finish_build(intent["peer"], squad,
			BuildingSim.def_by_id(StringName(intent["def_id"])), cell,
			int(intent.get("facing", 0)), intent.get("offset", Vector2.ZERO))
		if not queue.is_empty() and _sim.alive_of(squad) > 0:
			_sim.order_move(squad, queue[0]["cell"])
	else:
		_sim.order_move(squad, cell)


## Commit a build: charge for it, raise the site, consume the founders.
##
## Shared by the in-reach path above and the walked-there path in
## `_advance_pending_builds`, so "what founding a building does" has one
## implementation rather than two that can drift — the same reason
## `_admit_player` is shared by joining and by starting a match.
func _finish_build(peer, squad: int, def: BuildingDef, cell: Vector2i,
		facing: int = 0, offset: Vector2 = Vector2.ZERO) -> void:
	if def == null:
		return
	var owner := _sim.owner_of(squad)
	# Re-checked here, not just at order time: a builder that walked for
	# twenty seconds may arrive to find the ground taken. `owner` also
	# makes this the upgrade-aware check (see _is_buildable/
	# _upgrade_target_at) — an upgrade target might have been destroyed
	# (or captured) out from under the order while the builder walked, the
	# same "recheck on arrival" reasoning as every rule below it.
	if not _is_buildable(cell, def, owner):
		_notify(peer, "Cannot build there — water, mountain, or already occupied")
		return

	# Re-checked on ARRIVAL too: a builder ordered from out of reach walks
	# for twenty seconds, and an opponent may have planted something in
	# the meantime. Checking only at order time would let a slow walk beat
	# the rule.
	var blocked := _claimed_against(cell, owner)
	if blocked >= 0:
		_notify(peer, "Too close to an enemy %s" % _buildings.def_of(blocked).display_name)
		return

	# Re-checked on arrival too — a second squad may have been ordered to
	# found something nearby (or the very same site) while this one was
	# still walking, and only this recheck catches it if that order landed
	# after this squad's own order-time check already passed.
	if _footprint_conflict(cell, def.footprint_radius, squad):
		_notify(peer, "Too close to another building")
		return

	# Construction costs resources (D-028). This was missing, so
	# BuildingDef's cost table was declared and unread — the same trap
	# UnitDef.cost fell into for two milestones. Charged before anything
	# is committed, and all-or-nothing, so a refused build never leaves a
	# part-spent wallet.
	if not _economy.try_spend(owner, def.cost_food, def.cost_wood, def.cost_gold, def.cost_stone):
		_notify(peer, "Cannot afford a %s" % def.display_name)
		return

	# Playtest fix: raising a compatible upgrade (e.g. a wall_tower) in
	# place of an existing building consumes it — the whole point is not
	# needing a separate delete-then-rebuild trip. No partial refund (the
	# economy has no mechanism to refund INTO, the same as any other
	# cancelled or overwritten order); the player pays the new building's
	# full cost, same as any other build. Reusing `damage()` rather than
	# a bespoke removal keeps this on the exact same path a real
	# destruction takes (dirty flag, wall-top network recomputed by the
	# `_refresh_passability()` below) instead of a second one to keep in
	# sync with it.
	var upgraded_from := _upgrade_target_at(cell, def, owner)
	if upgraded_from >= 0:
		_buildings.damage(upgraded_from, _buildings.health_of(upgraded_from))

	# Sandbox's instant_build (dev testing only): raised already complete
	# rather than at 0 progress. Cost is still charged above — instant
	# build skips the WAIT, not the economy, so it stays useful for
	# testing the economy itself.
	var built := _buildings.add_building(def, owner, cell, _match.instant_build, squad, facing, offset)
	_send_wallet(peer, owner)
	_refresh_passability()

	# The founding party becomes the settlement, here and now (D-031) — but
	# ONLY founders, and only because they are founding a TOWN. Every other
	# builder (a gatherer raising a barracks, a tower, a wall segment...)
	# walks away free once construction finishes, the same as any other RTS
	# villager.
	#
	# This used to consume ANY builder unconditionally: `_finish_build` is
	# shared by every building type, and `consume_squad` was called here
	# with no check on who was building what. A gatherer sent to raise a
	# storehouse or a tower has therefore been silently vanishing the
	# moment it finished for as long as this function has existed — nothing
	# failed loudly, because `built_by` empty/gatherers-only buildings
	# genuinely do get built, just at the cost of the builder every time.
	# Walls and gates, buildable in numbers a session actually produces,
	# finally made it something a player noticed rather than a one-off
	# oddity easy to misread as "that gatherer must have died in a fight".
	if _sim.def_of(squad).archetype == &"founders":
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
func _handle_order_produce(peer, data: PackedByteArray) -> void:
	var record = _record_for(peer)
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

	_buildings.enqueue(building, def, _match.instant_build)
	_send_wallet(peer, player)


## Put a gatherer squad to work (D-028). The economy decides whether the
## squad can gather and whether the cell holds anything; this only checks
## that the order is the player's to give.
func _handle_order_gather(peer, data: PackedByteArray) -> void:
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
func _notify(peer, text: String) -> void:
	peer.send(0, NetProtocol.encode_notice(text), ENetPacketPeer.FLAG_RELIABLE)


## Wallets go to their owner and nobody else (D-028).
func _send_wallet(peer, player: int) -> void:
	peer.send(0, NetProtocol.encode_wallet(_economy.wallet_of(player)),
		ENetPacketPeer.FLAG_RELIABLE)


# --- sandbox mode cheats, for dev testing -------------------------------

## Flat grant per CHEAT_ADD_RESOURCES call. A round, generous number
## rather than anything tuned — this is a dev tool, not balance data.
const CHEAT_RESOURCE_GRANT := 1000

## How many squads one CHEAT_SPAWN_UNIT call may raise at once. Bounded
## for the same reason BUILD_REACH_CELLS exists: a cheat command is still
## a message from a client, and an unbounded count is an unbounded
## amount of work done on its say-so.
const CHEAT_SPAWN_MAX_COUNT := 20


## Shared guard for every C2S_CHEAT_* handler: the match must be RUNNING
## and MatchState.sandbox must be on for this match. Mirrors
## `_validated_squad`'s shape and reasoning — one owner of the check
## rather than a copy per handler. Returns the caller's record, or an
## empty Dictionary if the cheat must be refused.
func _validated_cheat(peer):
	var record = _record_for(peer)
	if record == null or not _match.is_running():
		return null
	if not _match.sandbox:
		_notify(peer, "Sandbox mode is off — ask the lobby admin to enable it")
		return null
	return record


## CHEAT_ADD_RESOURCES: credit the sender a flat amount of every resource
## (D-028's four). Repeatable — there is no cooldown, because refusing to
## trust a client's own economy testing is not what sandbox mode is for.
func _handle_cheat_add_resources(peer, data: PackedByteArray) -> void:
	var record = _validated_cheat(peer)
	if record == null:
		return
	var player := int(record["player"])
	for kind in range(Economy.RESOURCE_COUNT):
		_economy.credit(player, kind, CHEAT_RESOURCE_GRANT)
	_send_wallet(peer, player)
	_notify(peer, "Cheat: +%d of every resource" % CHEAT_RESOURCE_GRANT)


## CHEAT_SPAWN_UNIT: raise full-strength squads directly, bypassing cost
## and the squad cap entirely — a sandbox is for testing what an army
## DOES, not for re-proving it can be paid for. `archetype` resolves
## against the sender's own civ (D-047), exactly as C2S_ORDER_PRODUCE
## does, so a client still cannot name another civ's unit.
func _handle_cheat_spawn_unit(peer, data: PackedByteArray) -> void:
	var record = _validated_cheat(peer)
	if record == null:
		return
	var order := NetProtocol.decode_cheat_spawn_unit(data)
	var player := int(record["player"])
	var def := UnitRoster.for_civ_archetype(_civ_of(player), StringName(order["archetype"]))
	if def == null:
		_notify(peer, "Your people do not field %s" % order["archetype"])
		return

	var cell := _sim.space.from_index(int(order["cell"]))
	var count := clampi(int(order["count"]), 1, CHEAT_SPAWN_MAX_COUNT)
	for _i in range(count):
		_sim.add_squad(def, player, cell)
	_notify(peer, "Cheat: spawned %d x %s" % [count, order["archetype"]])


## CHEAT_SPAWN_BUILDING: raise a COMPLETE building instantly, bypassing
## cost, footprint and the no-build claim. The one rule still enforced is
## `_is_buildable` — physically buildable ground — so a spawned building
## never looks broken even though every game-balance rule around it is
## skipped.
func _handle_cheat_spawn_building(peer, data: PackedByteArray) -> void:
	var record = _validated_cheat(peer)
	if record == null:
		return
	var order := NetProtocol.decode_cheat_spawn_building(data)
	var def := BuildingSim.def_by_id(StringName(order["def_id"]))
	if def == null:
		_notify(peer, "No such building '%s'" % order["def_id"])
		return

	var cell := _sim.space.from_index(int(order["cell"]))
	if not _is_buildable(cell):
		_notify(peer, "Cannot spawn there — water, mountain, or already occupied")
		return

	var player := int(record["player"])
	# Same generic safety wrap as `_do_order_build` — `add_building` is the
	# one place that knows whether `def` wants a 6-way hex direction or a
	# continuous byte.
	var facing := posmod(int(order.get("facing", 0)), 256)
	_buildings.add_building(def, player, cell, true, -1, facing)
	_refresh_passability()
	_notify(peer, "Cheat: spawned a %s" % def.display_name)


## Buildable ground: passable terrain (no lakes, no mountains) with
## nothing already standing on it — UNLESS `def`/`owner` name a compatible
## in-place upgrade (playtest fix, D.upgrade_from) for whatever is already
## there, which is the one deliberate exception.
func _is_buildable(cell: Vector2i, def: BuildingDef = null, owner: int = -1) -> bool:
	var index := _sim.space.index(cell)
	if index < _passable.size() and _passable[index] == 0:
		return false
	# Resource nodes are ground you cannot build on (playtest fix). Nothing
	# checked this before, so a town centre could be founded straight on top
	# of a forest — the node stayed gatherable underneath and the building
	# stood in the middle of it, which looks broken and quietly denies the
	# node to the gatherers who need to stand there.
	#
	# Guarded on null because `_is_buildable` is exercised directly by tests
	# that stand up a server with only `_sim`/`_buildings`/`_passable` set;
	# an economy-less server simply has no nodes to collide with.
	if _economy != null and _economy.has_node(index):
		return false

	var upgrade_target := _upgrade_target_at(cell, def, owner) if def != null else -1
	for i in range(_buildings.building_count()):
		if _buildings.cell_index_of(i) != index or _buildings.is_destroyed(i) \
				or i == upgrade_target:
			continue
		# D-096: for the wall family a cell is an ANCHOR, not an exclusive
		# slot. Segments of a continuously-placed run sit WALL_LENGTH
		# (~1.77) apart while a hex is ~1.73 across, so two consecutive
		# segments occasionally round into the same anchor cell — refusing
		# the second would silently drop it and leave a hole in a wall the
		# player watched themselves draw. Both sides must be wall family:
		# a wall still may not share a cell with a town hall, and the
		# access tower stays exclusive (it is a point structure with a
		# door — see BuildingSim.span_cells).
		var other_def := _buildings.def_of(i)
		if def != null and other_def != null \
				and def.footprint_radius == 0 and not def.is_access_tower \
				and other_def.footprint_radius == 0 and not other_def.is_access_tower:
			continue
		return false
	return true


## The living building at `cell` that `def` would upgrade in place
## (playtest fix), or -1 if none qualifies. Only the OWNER'S OWN, COMPLETE
## building counts — an enemy's wall is not `owner`'s to upgrade, and a
## still-under-construction one has nothing finished to replace yet
## (queue behind it, or wait).
func _upgrade_target_at(cell: Vector2i, def: BuildingDef, owner: int) -> int:
	if def == null or def.upgrade_from.is_empty():
		return -1
	var index := _sim.space.index(cell)
	for i in range(_buildings.building_count()):
		if _buildings.is_destroyed(i) or _buildings.cell_index_of(i) != index:
			continue
		if _buildings.owner_of(i) != owner or not _buildings.is_complete(i):
			continue
		if def.upgrade_from.has(_buildings.def_of(i).id):
			return i
	return -1


## The hostile building whose claimed ground covers `cell`, or -1 (D-062).
##
## Each building denies a radius to players it is not allied with, so
## nobody can wall a town in by planting towers against its walls, and a
## settlement means something on the map rather than being a dot others
## can crowd.
##
## Allies are exempt: D-050 gives teams a shared front, and a teammate
## unable to build beside your hall would be a worse partner than an
## enemy.
##
## Scans buildings directly rather than maintaining a claimed-cell map:
## there are orders of magnitude fewer buildings than cells, and a map
## would be a second source of truth to keep in step with `_cell` — the
## same reasoning `BuildingSim.building_at` gives.
func _claimed_against(cell: Vector2i, player: int) -> int:
	for i in range(_buildings.building_count()):
		if _buildings.is_destroyed(i):
			continue
		if _sim.are_allied(_buildings.owner_of(i), player):
			continue
		var def := _buildings.def_of(i)
		if def == null or def.no_build_radius <= 0:
			continue
		if _sim.space.distance(cell, _buildings.cell_of(i)) <= def.no_build_radius:
			return i
	return -1


## Whether founding a `radius`-footprint building at `cell` would overlap
## another building's own footprint — a completed one, OR one only pending
## (a squad still walking to its site).
##
## `BuildingDef.footprint_radius` was declared in the schema and given real
## per-building values (town_centre 2, everything else 1) but read by
## nothing at all — the same "declared and unread" defect `UnitDef.cost`,
## `BuildingDef.cost` and `BuildingSim.damage()` each cost a milestone
## before someone noticed (see CLAUDE.md's running list). Without it,
## `_is_buildable` only ever reserved the single CELL a building was
## founded on, never the ground its mesh actually covers — irrelevant once
## a real footprint (2 to 4.6 world units, D-064) is several times wider
## than one hex (~1.7). Two buildings on merely ADJACENT cells could
## already render on top of each other, and — the reported bug — a second
## squad could be sent to found a building at the very same site as a
## first squad still walking there, because nothing reserved a cell a
## build was only PENDING at. Checked at order time below and re-checked
## on arrival in `_finish_build`, the same two-checkpoint shape
## `_claimed_against` uses for the identical reason: a slow walk should
## not be able to beat a rule that a fast one would have failed.
func _footprint_conflict(cell: Vector2i, radius: int, exclude_squad: int = -1) -> bool:
	for i in range(_buildings.building_count()):
		if _buildings.is_destroyed(i):
			continue
		var other_def := _buildings.def_of(i)
		if other_def == null:
			continue
		if _sim.space.distance(cell, _buildings.cell_of(i)) < radius + other_def.footprint_radius:
			return true
	for squad in _pending_builds:
		if squad == exclude_squad:
			continue
		# A whole QUEUE per squad now (D-076 amendment) — every site still
		# waiting its turn counts, not just the front of the line.
		for intent in _pending_builds[squad]:
			var other_def := BuildingSim.def_by_id(StringName(intent["def_id"]))
			if other_def == null:
				continue
			if _sim.space.distance(cell, intent["cell"]) < radius + other_def.footprint_radius:
				return true
	return false


func _handle_order_stop(peer, data: PackedByteArray) -> void:
	var order := NetProtocol.decode_order_stop(data)
	var squad := _validated_squad(peer, int(order["squad"]))
	if squad < 0:
		return
	_sim.stop(squad)


func _spawn_squads_for(player: int) -> Array:
	var ids := []

	# A scenario replaces the opening entirely (D-098): this player gets
	# the loadout the scenario describes, at its seat's home, instead of
	# one founding party. Applied through `Scenario.apply_player`, which is
	# the SAME call the headless test fixture uses — one placement
	# implementation, so a scenario cannot mean one thing in a unit test
	# and another on a live server.
	if _scenario != null and not _scenario_homes.is_empty():
		var seat := _match.spawn_index(player, _scenario_homes.size())
		var placement := Scenario.apply_player(_scenario, player,
			_civ_of(player), _scenario_homes[seat], _sim, _buildings,
			_economy, _passable, _scenario_taken)
		for problem in placement.skipped:
			# Loud, never swallowed. An army that quietly failed to place
			# looks exactly like one the simulation lost.
			push_warning("server: scenario '%s' player %d: %s" % [
				_scenario.id, player, problem])
			print("server: SCENARIO_SKIPPED player=%d %s" % [player, problem])
		print("server: scenario '%s' seated player %d — %d squads, %d buildings" % [
			_scenario.id, player, placement.squads.size(),
			placement.buildings.size()])
		return placement.squads

	# Spawn points come from the map now, not from a formula here (D-036).
	# The old version computed lanes from `player * 7` and `player * 5 + i
	# * 2`, which had two problems: the constants were invisible to anyone
	# balancing a map, and client.gd had duplicated the whole formula to
	# *guess* where a neighbour spawned, with a comment noting the guess
	# would go stale if this ever changed. Deriving spawns from
	# MapConfig.spawn_points() makes them data — randomly scattered with a
	# guaranteed minimum spacing as of D-039, and sampled once at startup.
	var points := _spawn_points

	# Keyed on SEAT INDEX, not player id — the same rule and the same
	# reason as D-052's colours.
	#
	# This was `points[(player - 1) % points.size()]`, and AI players are
	# numbered from 1000 (D-051, deliberately sharing the human id space).
	# With 20 spawn points that put player 1 at index 0 and player 1001 at
	# 1000 % 20 = 0 as well: a human and an AI spawned on the SAME cell.
	# Reported from an actual game, where they landed on top of each other.
	#
	# D-052 fixed exactly this for colours and said so in as many words —
	# "any modulo of a player id would give" collisions once ids start at
	# 1000. Spawn assignment simply never had the fix applied. Seats are
	# numbered 0..n-1 contiguously however players are numbered, so keying
	# on them makes the collision unrepresentable rather than unlikely.
	#
	# The fallback keeps a player with no seat (nothing does this today,
	# but a reconnect path might) working rather than crashing.
	var origin: Vector2i = points[_match.spawn_index(player, points.size())]

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
	_record_seats_once()
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
	# Taken once, out here, because take_shape_dirty() CLEARS — reading it
	# inside the per-client loop would tell the first client and nobody
	# else, and the rest would silently hold a stale formation.
	var shape_changes := _sim.take_shape_dirty()
	var wallet_changes := {}
	for player in _sim.last_wallet_changes:
		wallet_changes[player] = true

	# Trees that came down this tick. Taken once, out here, because
	# take_depleted() clears — then folded into the match-lifetime set so
	# the per-client pass below can tell each player when THEY can see the
	# stump, which for a player behind the fog may be minutes from now.
	if _economy != null:
		for cell in _economy.take_depleted():
			_depleted_nodes[cell] = true

	# AI seats are fed through the SAME loop as humans (D-051). They hold a
	# LoopbackPeer whose send() hands bytes to a ClientState, so an AI
	# receives byte-identical packets through byte-identical code — and its
	# knowledge is a subset of its vision by construction rather than by
	# promise. Giving the AI privileged access to SquadSim would have been
	# less code and impossible to trust.
	var recipients := _recipients()
	for peer in recipients:
		var record = recipients[peer]
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

		# Resources come into view like anything else (D-061). Cheap: the
		# scan skips cells already known, and once a player has explored
		# their surroundings it finds nothing and sends nothing.
		_send_visible_nodes(peer, player, record)

		# Squads whose FORMATION changed this tick (D-058), for the ones
		# this client can see.
		#
		# Shape is in `composition_hash` and is what `Formation` derives
		# every soldier's position from, so a client that missed a change
		# would draw the squad in the wrong shape AND report a desync. Sent
		# as ordinary SQUAD_INFO — the message that already carries shape —
		# rather than inventing a second one, and only for squads that
		# actually changed, so a formation nobody touched costs nothing
		# (D-003).
		#
		# Filtered against `visible_set`, so this leaks no more than a
		# reveal does: you are told what an enemy squad looks like exactly
		# when you can see it.
		if not shape_changes.is_empty():
			var changed_visible := []
			for id in shape_changes:
				if visible_set.has(int(id)):
					changed_visible.append(int(id))
			if not changed_visible.is_empty():
				var shape_entries := _sim.squad_info_entries(changed_visible)
				if not shape_entries.is_empty():
					peer.send(0, NetProtocol.encode_squad_info(shape_entries),
						ENetPacketPeer.FLAG_RELIABLE)

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


func _handle_lobby_command(peer, data: PackedByteArray) -> void:
	var record = _record_for(peer)
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
				# Dev-testing flags are a distinct key namespace from
				# MapSettings — tried first, since they parse their value
				# as a bool rather than a float and MUST NOT fall through
				# to set_map_option's float() cast on something like "1"
				# meant as true.
				if ["sandbox", "instant_build", "ai_economy_only"].has(parts[0]):
					ok = _match.set_sandbox_option(player, parts[0], parts[1] != "0")
					if ok and parts[0] == "ai_economy_only":
						for brain in _ai_players:
							brain.economy_only = _match.ai_economy_only
				else:
					ok = _match.set_map_option(player, parts[0], float(parts[1]))
			if not ok:
				_notify(peer, "Only the admin can change that setting, and not to an unplayable one")
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


## A player asked to leave the match (D-075).
##
## Only a socket may do this. An AI seat reaches `_dispatch` through the
## same path a human does (D-051), which is the point — but "end the match
## everyone is playing" is not an order about its own army, and an AI
## deciding it has had enough would be a rule nobody wrote.
func _handle_leave_match(peer) -> void:
	if not _clients.has(peer):
		return
	if _match.phase == MatchState.Phase.LOBBY:
		return
	print("server: player %d left the match — returning to the lobby" % [
		int(_clients[peer]["player"])])
	_return_to_lobby()


## Put the server back in the seat-picking screen it started in (D-075).
##
## The exact inverse of `_on_match_started`, and deliberately written
## beside it: anything that function builds, this one has to drop, or the
## next match inherits the last one's world. `_build_world` guards on
## `_sim != null` and would otherwise return without building anything,
## leaving a second match running on the first one's terrain — with the
## first one's spawn points, resource nodes and combat seed.
##
## For now this returns the WHOLE match, not just the leaver. That is
## right for the solo-versus-AI session this exists to serve and wrong for
## several humans, where one person leaving would evict everybody; the
## limitation is recorded in D-075 rather than hidden here.
func _return_to_lobby() -> void:
	if not _match.return_to_lobby():
		return

	# The replay belongs to the MATCH (D-016). Closing it here is what
	# makes the next one open its own file rather than appending a second
	# match's curves onto the first's log.
	if _replay != null and _replay.is_open():
		print("server: wrote %d replay records" % _replay.records_written)
		_replay.close()
	_replay = null
	_matches_played += 1

	_sim = null
	_buildings = null
	_economy = null
	_passable = PackedByteArray()
	_spawn_points = []
	_pending_events.clear()
	_pending_builds.clear()
	_civs.clear()

	# AI seats are re-created from the seat list by the next
	# `_on_match_started`, so the brains go with the world. Keeping them
	# would leave `_ai_players` thinking about a simulation that no longer
	# exists, on the very next tick.
	_ai_players.clear()
	_ai_clients.clear()

	# Every client is about to be told the match is over; none of them may
	# keep a reveal baseline from it. Leaving these populated would make
	# the next match's first reveal diff find "nothing new" for everything
	# the player could already see — the same defect `_recipients` records.
	for peer in _clients:
		_clients[peer]["visible"] = {}

	# `return_to_lobby` rolls the next match's map unless the seed is
	# pinned (D-100), so the seed is worth naming here: it is the one
	# thing about the lobby that changed without anybody touching it.
	print("server: returned to the lobby — %d seat(s) held, next map seed %d%s" % [
		_match.seats.size(), _match.map_settings.seed,
		" (pinned)" if _match.map_settings.seed_pinned else ""])
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
		if String(seat["kind"]) == "ai":
			_seat_ai(player, StringName(seat["civ"]))
			continue
		var peer := _peer_of(player)
		if peer == null:
			continue
		# Register humans HERE, not only at connect. Registration is
		# per-match and `return_to_lobby` clears it (D-075), so a second
		# match on this server would otherwise count only its AI seats —
		# elimination and victory would ignore every human in it.
		# `add_player` is idempotent, so the first match is unaffected.
		_match.add_player(player)
		_admit_player(peer, player)


## Bring an AI seat to life (D-051).
##
## It is admitted through exactly the same `_admit_player` a human goes
## through — same spawn, same opening stockpile, same welcome packet —
## because "what a player starts with" must not have two implementations.
func _seat_ai(player: int, civ: StringName) -> void:
	var brain := AiPlayer.new(player, civ)
	# Whatever the admin already had toggled before this AI was seated —
	# a live toggle afterward updates every brain directly (see
	# _handle_lobby_command's LOBBY_SET_OPTION case).
	brain.economy_only = _match.ai_economy_only
	var peer := LoopbackPeer.new(brain.state)
	# Its orders take the identical path a human's do, validation and all.
	brain.send = func(packet: PackedByteArray) -> void:
		_dispatch(peer, packet)

	# The civ this seat was DEALT, recorded where the rest of the server
	# reads civs from. Without it `_civ_of` fell through to its round-robin
	# fallback, `all[(player - 1) % all.size()]` — and an AI's player id is
	# 1000-odd (D-051), so the modulo answered a different civ from the one
	# the brain was constructed with. The AI reported one civilisation in
	# AI_STATS and fielded another's troops for the whole match.
	_civs[player] = civ

	# Registered with the match like any player, so elimination and
	# victory count an AI exactly as they count a human (D-033).
	var started := _match.add_player(player)
	_ai_clients[peer] = {"player": player, "visible": {}}
	_ai_players.append(brain)
	_admit_player(peer, player)
	print("server: AI seated as player %d (%s)" % [player, civ])
	# An all-AI match (`--players=0 --ai=n`) begins the moment the last seat
	# is filled, with nobody left to connect and trigger the path above.
	if started:
		_note_match_started()


## The match has just left the lobby on the NO-LOBBY path (`--lobby=0`),
## where nobody presses start and `_on_match_started` never runs.
##
## Deliberately small: on this path the world was built at boot, seats were
## filled as they arrived and everyone was admitted on the way in, so the
## only thing the transition still owes anybody is the NEWS of it.
##
## And the news matters. `_broadcast_lobby` is how a client learns the
## phase (D-048), and an AI seat is a client (D-051) that will not act
## until it hears the match is running — so an AI seated while the phase
## was still LOBBY would otherwise wait for a message that never came.
## The same print the lobby path emits, so "did a match actually start"
## has one marker in the log however it started; `just ai-ladder` fails on
## its absence rather than reporting a match that never happened as a draw.
func _note_match_started() -> void:
	print("server: match started — %s" % _seat_summary())
	_broadcast_lobby()


## EVERY peer that receives simulation state — sockets and AI seats alike.
##
## D-051 says an AI receives byte-identical packets through byte-identical
## code, and that guarantee only holds if there is ONE definition of who
## "everybody" is. There were two: `_replicate` merged in `_ai_clients`,
## `_broadcast_squad_info` iterated `_clients` alone. So an AI was never
## sent composition for its own starting squads — and `_admit_player`
## then seeded its reveal baseline to "already knows everything visible",
## which meant the next tick's reveal diff found nothing new to send and
## the gap never healed.
##
## It surfaced only when the founding party was consumed by the town it
## founded (D-031): a casualty event arrived for a squad the AI had never
## been described, and ClientState said so. Nothing else complained,
## because an AI orders squads by the ids in its WELCOME packet and those
## were fine — it simply had no idea how strong anything was, including
## its own army, for the entire match.
func _recipients() -> Dictionary:
	var out := _clients.duplicate()
	out.merge(_ai_clients)
	return out


## A client record, whether the sender is a socket or an AI seat in this
## process (D-051).
func _record_for(peer):
	if _clients.has(peer):
		return _clients[peer]
	return _ai_clients.get(peer, null)


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
	var packet := NetProtocol.encode_lobby(_match.admin_player, _match.seats,
		_settings.to_dict(), int(_match.phase),
		_match.sandbox, _match.instant_build, _match.ai_economy_only)
	# `_recipients()`, not `_clients` — the third time this exact drift has
	# been found, and see that function's own doc for the first two. An AI
	# seat is a client (D-051), it is told the lobby once at admission, and
	# it was then never told again: it could not learn that the match had
	# started, which seat list it was in, or who its teammates were. The
	# peers are deliberately untyped here for the same reason `_replicate`
	# does not cast — a LoopbackPeer answers send() and is not an ENet one.
	for peer in _recipients():
		peer.send(0, packet, ENetPacketPeer.FLAG_RELIABLE)


## Relay a chat message (D-050).
##
## The speaker is attached HERE, from the connection the message arrived
## on. A client sends text and nothing else — letting it name its own
## speaker would let it put words in another player's mouth, which is the
## same untrusted-client rule as orders (D-002), just less obvious when
## the payload is prose.
func _handle_chat(peer, data: PackedByteArray) -> void:
	var record = _record_for(peer)
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


## Write who played as whom into the replay, once (D-046 criterion 11).
##
## Guarded and driven from the tick rather than hung off one start path,
## because a match can begin two ways: an admin pressing start in a lobby
## (D-048), or a player simply connecting to a server that has no lobby.
## Hanging it off the first would have recorded nothing for every load
## test, which is exactly where a replay is most useful.
##
## Civ comes from `_civ_of`, the same authority production uses, rather
## than the seat's own field — a seat may have said "Random" until the
## moment it started, and the replay should record what was PLAYED.
var _seats_recorded := false


func _record_seats_once() -> void:
	if _seats_recorded or _replay == null or _match == null:
		return
	if _match.phase != MatchState.Phase.RUNNING:
		return
	_seats_recorded = true

	var seats := []
	for seat in _match.seats:
		var player := int(seat["player"])
		seats.append({
			"player": player,
			"team": int(seat.get("team", 0)),
			"civ": String(_civ_of(player)),
			"name": String(seat["name"]),
		})
	_replay.record_seats(_sim.time, seats)


## Which civs actually put a squad on the field this match (D-046
## criterion 10).
##
## Counted from the SIM rather than from the lobby's seat list: a seat
## says who intended to play a civ, and this says who actually fielded
## one. A match where a civ was chosen and then never produced anything
## would satisfy the first and prove nothing about the second — which is
## the whole failure mode M6's verdict is meant to catch, since the point
## of two civs is that BOTH are exercised.
func _civs_fielded() -> Dictionary:
	var out := {}
	if _sim == null:
		return out
	for squad in range(_sim.squad_count()):
		var civ := _civ_of(_sim.owner_of(squad))
		if civ != &"":
			out[String(civ)] = int(out.get(String(civ), 0)) + 1
	return out
