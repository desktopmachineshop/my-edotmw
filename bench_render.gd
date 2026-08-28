extends Node3D

## Client render benchmark (D-044 criteria 1-3) — the measurement Q15
## deferred and M4 never took.
##
## D-041 measured what it costs to *derive* soldier positions. Nothing had
## ever been drawn: no draw-call count, no frame time, no GPU named. That
## left D-012's rendering LOD tiers unsized, which Q15 predicted in as
## many words and made the trigger for M5.
##
## ## What this measures, and what it deliberately does not
##
## It drives a REAL `SquadSim` through the REAL `CurveReplicator` and
## `NetProtocol` into a REAL `ClientState`, then renders with the REAL
## `PrimitiveUnit` — the same classes `client.gd` uses. A lookalike
## harness would measure a lookalike, and M4 already paid for that lesson
## once: `just profile` reported ~29 ms for code that spent 866 ms in a
## live server, because the harness resolved its UnitDefs once at setup
## and the live client did not (D-043 criterion 11).
##
## **The simulation is ticked before measurement and then stopped.** A
## real client never runs `SquadSim`, so ticking it inside a measured
## frame would charge server work to a client number. Curves are
## generated up front; the measured frames only sample them, which is
## exactly what a client does between updates.
##
## ## HOST MODE (`--host=1`), and why it is a different question (#339)
##
## Everything above measures a CLIENT. `D-088` makes the host a PLAYER:
## it runs the authoritative simulation **in-process** inside its own
## client, so a hosting machine pays the tick budget and the frame budget
## out of the same second. Nothing had ever measured the combination —
## every figure this project has is one or the other, taken alone, in its
## own process.
##
## `--host=1` therefore does the thing the paragraph above forbids, on
## purpose: it ticks the simulation INSIDE the measured frames, at
## `SquadSim.TICK_HZ`, and reports what the two together consume out of
## each wall-clock second. It also builds the world the SERVER builds —
## teams, civs, economy, buildings, research — because a host runs a
## match and not a squad soup, and the client-only rows deliberately do
## not.
##
## The client-only rows are unchanged and remain the default, so
## `just bench-render` measures exactly what it measured yesterday.
##
## ## Why this cannot be `just test-client`
##
## `test-client` renders through Mesa's software rasteriser in docker
## (D-014's 2026-07-29 amendment). That is the right tool for "is the
## picture correct" and useless for "how fast is it" — software rendering
## measures the CPU, not the GPU anyone will play on. This recipe is
## native, and prints the adapter it ran on, because a frame time with no
## hardware attached is not a number anyone can use (D-044 criterion 2).

const DEFAULT_COUNTS := "0,100,250,500,1000"
const DEFAULT_FRAMES := 120
const DEFAULT_WARMUP := 30

## Ticks of simulation run before measuring, to give every squad a curve
## that is actually going somewhere. Idle squads would understate the
## cost: a stationary curve still derives, but its keyframe search is the
## easy case.
const SETUP_TICKS := 12

enum Phase { SETUP, WARMUP, MEASURE, DONE }

var _counts: Array = []
var _frames_to_measure := DEFAULT_FRAMES
var _warmup_frames := DEFAULT_WARMUP
var _with_terrain := true

var _phase: int = Phase.SETUP
var _index := 0
var _frames_seen := 0

var _frame_usec: Array = []
var _draw_calls: Array = []
var _process_usec: Array = []

var _camera: Camera3D
var _terrain_root: Node3D
var _squad_root: Node3D
var _squad_nodes := {}
var _visible_squads := 0
var _camera_target := Vector3.ZERO

## Camera height, matching client.gd's `_camera_height` default. Exposed
## because how much of the map is on screen is the whole question a
## culling measurement asks, and the client lets a player change it.
var _camera_height := 40.0

var _space: TorusSpace
var _sim: SquadSim
var _state: ClientState
var _now := 0.0
var _config: MapConfig
var _terrain_sampler := Callable()
## The passability half of the terrain sample (#97). Held beside the
## sampler because a benchmark that skipped the clamp would price a
## derivation the client does not run.
var _terrain_passable := PackedByteArray()

## HOST mode (#339): the sim ticks inside the measured frames.
var _host_mode := false
## Terrain preset to build the world on, or empty for the map's own.
## `islands` is the worst honest case for a host — the water layer is a
## third field layer and `islands` is ~68% sea.
var _preset := &""
var _hulls := 0
var _tick_accumulator := 0.0
var _sim_usec: Array = []
var _ticks_run := 0
var _navigable := PackedByteArray()


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_counts = String(args.get("counts", DEFAULT_COUNTS)).split(",", false)
	_frames_to_measure = int(args.get("frames", DEFAULT_FRAMES))
	_warmup_frames = int(args.get("warmup", DEFAULT_WARMUP))
	_with_terrain = int(args.get("terrain", 1)) != 0
	_camera_height = float(args.get("height", 40.0))
	_host_mode = int(args.get("host", 0)) != 0
	_preset = StringName(String(args.get("preset", "")))
	_hulls = int(args.get("hulls", 0))

	# Vsync would cap every measurement at the refresh rate and report a
	# uniform 16.7 ms whether the frame cost 2 ms or 16 — which reads as
	# "comfortably at 60" for a client that is actually on the edge.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_config = load("res://maps/default.tres") as MapConfig
	if _config == null:
		push_error("bench: could not load maps/default.tres")
		get_tree().quit(1)
		return
	_space = _config.to_space()

	print("bench: GPU — %s | %s | Godot %s" % [
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
		Engine.get_version_info().get("string", "?")])
	print("bench: map %dx%d (%d cells), %d measured frames per count, terrain=%s" % [
		_space.width, _space.height, _space.cell_count(),
		_frames_to_measure, "on" if _with_terrain else "off"])
	if _host_mode:
		print("bench: HOST mode — the simulation ticks inside the measured frames (#339)")
		print("bench: squads,soldiers,ms_mean,fps_mean,client_ms,sim_ms_per_tick,sim_ms_per_s,client_ms_per_s,TOTAL_ms_per_s")
	else:
		print("bench: squads,soldiers,ms_mean,ms_worst,fps_mean,draw_calls,cpu_ms_mean,squads_drawn")

	_build_scene()


func _build_scene() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	# EXACTLY client.gd's _update_camera, not an approximation of it. The
	# first version of this used a plausible-looking -45 degrees and a
	# different offset, which changed how much of the map was on screen —
	# and "how much is on screen" is the entire quantity a culling
	# measurement is about. A benchmark camera that is merely similar
	# measures a similar game.
	_camera_target = Vector3(
		float(_space.width) * 0.5 * _space.hex_size * TorusSpace.SQRT_3,
		0.0,
		float(_space.height) * 0.5 * 1.5 * _space.hex_size)
	_camera.position = _camera_target + Vector3(0.0, _camera_height, _camera_height * 0.6)
	_camera.look_at(_camera_target, Vector3.UP)

	add_child(WorldLook.make_sun())

	var environment := WorldEnvironment.new()
	environment.environment = WorldLook.make_environment()
	add_child(environment)

	_terrain_root = Node3D.new()
	add_child(_terrain_root)
	_squad_root = Node3D.new()
	add_child(_squad_root)

	if _with_terrain:
		_build_terrain()


## The same nine-copy tiling client.gd does (D-035), because it is part of
## a real frame's draw-call count and leaving it out would flatter the
## result.
func _build_terrain() -> void:
	var terrain := TerrainGen.new()
	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(_space, chunk_size)

	# Soldiers stand ON the terrain, as in client.gd — deriving at y=0
	# would put them inside every hill AND skip the sampler call, which is
	# part of the per-soldier cost this is measuring.
	# The same continuous surface the client uses (D-067), through the same
	# helper — a benchmark that sampled the ground differently would be pricing
	# something the game does not do.
	var fields := terrain.build_fields(_space)
	var surface := fields.surface
	_terrain_sampler = func(x: float, z: float) -> float:
		return TerrainChunk.height_at(_space, surface, x, z)
	_terrain_passable = fields.passable

	# One shared definition (D-066), so the benchmark renders what the game
	# renders. Textured when generated/ has been built, vertex colour alone
	# when it has not.
	var material := TerrainChunk.make_material()

	var meshes: Array = []
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(_space, terrain, Vector2i(cx, cy), chunk_size, fields)
			if mesh != null:
				meshes.append(mesh)

	# `lattice_steps()`, matching client.gd — this benchmark exists to
	# reproduce the client's draw-call count, so a private copy of the
	# tiling arithmetic is the one thing it must not have.
	var steps := _space.lattice_steps()
	var step_q := steps[0]
	var step_r := steps[1]

	for i in [-1, 0, 1]:
		for j in [-1, 0, 1]:
			var tile := Node3D.new()
			tile.position = step_q * float(i) + step_r * float(j)
			for mesh in meshes:
				var instance := MeshInstance3D.new()
				instance.mesh = mesh
				instance.material_override = material
				tile.add_child(instance)
			_terrain_root.add_child(tile)


## Build `count` squads and get their curves into a real ClientState the
## way the wire would.
func _setup_count(count: int) -> void:
	for node in _squad_nodes.values():
		node.queue_free()
	_squad_nodes.clear()

	_sim = SquadSim.new(_space, CurveReplicator.new())
	_sim.set_passable(_bench_terrain().passability(_space))
	if _host_mode:
		_build_host_world()
	_state = ClientState.new()
	_state.terrain_sampler = _terrain_sampler
	_state.terrain_passable = _terrain_passable
	_now = 0.0

	if count <= 0:
		# The terrain-only row. Makes the fixed cost explicit instead of
		# leaving every squad figure carrying an unstated constant.
		_state.handle_packet(NetProtocol.encode_welcome(1, _space.width, _space.height, []))
		return

	var defs := UnitRoster.load_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBEEF

	# Hulls REPLACE ground squads rather than adding to them: a fleet is a
	# share of an army, and holding the total fixed is what makes the row
	# comparable with the client-only rows above.
	var placed := 0
	if _hulls > 0 and not _navigable.is_empty():
		var hull: UnitDef = null
		for def in defs:
			if def.get("movement_domain") == "water":
				hull = def
				break
		var water := []
		for index in range(_space.cell_count()):
			if _navigable[index] != 0:
				water.append(index)
		if hull != null and not water.is_empty():
			for n in range(mini(_hulls, count)):
				_sim.add_squad(hull, 1 + (n % 4) if _host_mode else 1,
					_space.from_index(int(water[(n * 97) % water.size()])))
				placed += 1

	for i in range(count - placed):
		# Four owners in host mode, so combat and teams have sides to be
		# about; one in client mode, which is what those rows have always
		# measured (`visible_to` then returns every squad).
		_sim.add_squad(defs[i % defs.size()], 1 + (i % 4) if _host_mode else 1, Vector2i(
			rng.randi_range(0, _space.width - 1),
			rng.randi_range(0, _space.height - 1)))
	for squad in range(_sim.squad_count()):
		_sim.order_move(squad, Vector2i(
			rng.randi_range(0, _space.width - 1),
			rng.randi_range(0, _space.height - 1)))

	# Everything is one player's, so `visible_to` returns all of them and
	# the benchmark measures the full set rather than a fogged subset.
	var visible := _sim.visible_to(1)
	_state.handle_packet(NetProtocol.encode_welcome(1, _space.width, _space.height, visible))
	_state.handle_packet(NetProtocol.encode_squad_info(_sim.squad_info_entries(visible)))
	for _i in range(SETUP_TICKS):
		_sim.tick()
		for packet in _sim.replicator.collect_for_client(1, _sim.time, _sim.visible_to(1)):
			_state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))
	_now = _sim.time


## The terrain the benchmark builds its world on — the map's own, or the
## `--preset` one. One definition, so the ground the camera sees and the
## ground the simulation paths on cannot come from two different
## generators (the D-096 shared-arithmetic rule).
func _bench_terrain() -> TerrainGen:
	if _preset == &"":
		return TerrainGen.new()
	var settings := MapSettings.from_map(_config)
	var preset := TerrainPresetRoster.by_id(_preset)
	if preset == null:
		push_error("bench: no terrain preset '%s'" % _preset)
		return TerrainGen.new()
	settings.preset = _preset
	settings.apply_preset(preset)
	settings.pin_seed(1337)
	return settings.to_terrain()


## What the SERVER builds, which the client-only rows deliberately do not
## (#339). A host runs a match: four sides, an economy, buildings, the
## civ knobs and the research state. Measuring a host against a squad
## soup would understate the half of the second it actually spends.
func _build_host_world() -> void:
	var terrain := _bench_terrain()
	_sim.buildings = BuildingSim.new(_space)
	var economy := Economy.new(_space)
	economy.generate(terrain, 1)
	_sim.economy = economy
	var civ_ids := CivRoster.ids()
	for player in range(1, 5):
		_sim.teams[player] = 1 + (player % 2)
		if not civ_ids.is_empty():
			_sim.civs[player] = CivRoster.effects_of(civ_ids[(player - 1) % civ_ids.size()])
	_sim.research = ResearchState.new()
	# The water layer, when this tree has one (naval stage 2). Guarded, so
	# the harness runs on a tree without naval and simply reports no hulls.
	if _hulls > 0 and terrain.has_method("navigability") \
			and _sim.has_method("set_navigable"):
		_navigable = terrain.call("navigability", _space)
		_sim.call("set_navigable", _navigable)


## A formation's own on-screen extent, in world units, for the cull test —
## the client takes it from `Formation.footprint`, and one number close to
## a shipped squad's radius is enough here because what is being measured
## is the cost of the copies, not the exactness of the cull.
const SQUAD_CULL_RADIUS := 4.0


## Exactly what client.gd's _refresh_squads does, minus the ghost pass
## (this harness never conceals anything).
func _refresh_squads() -> void:
	_visible_squads = 0
	var offsets := _space.lattice_offsets()
	var viewport_size := get_viewport().get_visible_rect().size
	var target := _camera_target

	for squad_id in _state.live_squad_ids():
		var entry: Dictionary = _state.composition.get(squad_id, {})
		if entry.is_empty():
			continue
		var unit: PrimitiveUnit = _squad_nodes.get(squad_id, null)
		if unit == null:
			unit = PrimitiveUnit.new()
			_squad_root.add_child(unit)
			var def := UnitRoster.by_id(StringName(entry["def_id"]))
			if def != null:
				unit.rebuild(def)
			_squad_nodes[squad_id] = unit

		# Same cull-before-derive the client does (D-045), so this measures
		# the client's real cost rather than a version of it without the
		# one optimisation that matters.
		var centre := _state.squad_world_position(squad_id, _now)
		# Every visible lattice copy, exactly as the client draws it
		# (D-20260818-entities-are-drawn-at-every-visible-copy). The whole
		# claim of that change is that extra copies cost draw calls and
		# not derivation, so a benchmark that still drew one of them would
		# be measuring the version of the client that does not ship.
		var drawn := RenderCull.visible_offsets_of_extent(
			_camera, offsets, centre, SQUAD_CULL_RADIUS, 192.0, viewport_size)
		unit.set_lattice_offsets(drawn)
		if drawn.is_empty():
			continue
		_visible_squads += 1
		var offset := RenderCull.nearest_offset(drawn, centre, target)
		unit.set_slot_transforms(_state.soldier_transforms_lod(
			squad_id, _now, _detail_for(centre + offset)))


## Mirrors client.gd's `_detail_for` and its LOD_TIERS. Duplicated
## knowingly and narrowly: the benchmark exists to measure the client, and
## a benchmark that skipped the client's LOD would report a cost the
## client does not pay. If the tiers are retuned, both move.
func _detail_for(world: Vector3) -> int:
	var distance := _camera.global_position.distance_to(world)
	if distance < 55.0:
		return 1 << 30
	if distance < 110.0:
		return 12
	return 5


func _process(delta: float) -> void:
	if _phase == Phase.DONE:
		return

	if _phase == Phase.SETUP:
		_setup_count(int(_counts[_index]))
		_frames_seen = 0
		_frame_usec.clear()
		_draw_calls.clear()
		_process_usec.clear()
		_sim_usec.clear()
		_ticks_run = 0
		_tick_accumulator = 0.0
		_phase = Phase.WARMUP
		return

	_now += delta

	# THE host measurement (#339): the authoritative tick, inside the
	# frame, at D-020's rate. A host pays this out of the same second it
	# pays the frame out of.
	var sim_cost := 0
	if _host_mode and _sim != null and _sim.squad_count() > 0:
		_tick_accumulator += delta
		var step := 1.0 / float(SquadSim.TICK_HZ)
		while _tick_accumulator >= step:
			_tick_accumulator -= step
			var tick_began := Time.get_ticks_usec()
			_sim.tick()
			# The host's own client still receives its state over the
			# loopback peer (D-051/D-088), so the encode and decode are
			# part of what a host pays and are timed with the tick.
			for packet in _sim.replicator.collect_for_client(1, _sim.time, _sim.visible_to(1)):
				_state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))
			sim_cost += Time.get_ticks_usec() - tick_began
			_ticks_run += 1
		_now = _sim.time

	var started := Time.get_ticks_usec()
	_refresh_squads()
	var cpu := Time.get_ticks_usec() - started

	if _phase == Phase.WARMUP:
		_frames_seen += 1
		if _frames_seen >= _warmup_frames:
			_phase = Phase.MEASURE
			_frames_seen = 0
			# Ticks run during warm-up too — the sim cannot be paused and
			# resumed without changing what it is doing — but they must
			# not land in the measured denominator. Caught by the two
			# reported figures disagreeing by 3x: `sim_ms_per_tick` was
			# measured-microseconds over warmup-plus-measured ticks, which
			# understates a tick by exactly the warm-up's share.
			_ticks_run = 0
		return

	# `delta` is the true frame period with vsync disabled, so it is the
	# number that decides whether this hits 60 fps. `cpu` is our own
	# per-frame work inside it — the two together say whether a shortfall
	# is derivation or the GPU.
	_frame_usec.append(int(delta * 1_000_000.0))
	_process_usec.append(cpu)
	if _host_mode:
		_sim_usec.append(sim_cost)
	_draw_calls.append(int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))

	_frames_seen += 1
	if _frames_seen >= _frames_to_measure:
		_report(int(_counts[_index]))
		_index += 1
		if _index >= _counts.size():
			_phase = Phase.DONE
			get_tree().quit(0)
		else:
			_phase = Phase.SETUP


func _report(count: int) -> void:
	var total := 0
	var worst := 0
	for usec in _frame_usec:
		total += usec
		worst = maxi(worst, usec)
	var mean := float(total) / float(maxi(_frame_usec.size(), 1))

	var cpu_total := 0
	for usec in _process_usec:
		cpu_total += usec

	var calls := 0
	for c in _draw_calls:
		calls = maxi(calls, c)

	var soldiers := 0
	for squad_id in _state.live_squad_ids():
		soldiers += _state.alive_of(squad_id)

	if _host_mode:
		# THE number #339 asks for: milliseconds of CPU consumed per
		# wall-clock SECOND, by each half and together, against 1,000.
		# Not per frame and not per tick — those are two different
		# denominators, and adding them is the mistake that makes a host
		# look affordable.
		var sim_total := 0
		for usec in _sim_usec:
			sim_total += usec
		var seconds := float(total) / 1_000_000.0
		var fps := 1_000_000.0 / maxf(mean, 1.0)
		var client_ms := float(cpu_total) / float(maxi(_process_usec.size(), 1)) / 1000.0
		var sim_ms_per_tick := float(sim_total) / float(maxi(_ticks_run, 1)) / 1000.0
		var sim_ms_per_s := float(sim_total) / 1000.0 / maxf(seconds, 0.001)
		var client_ms_per_s := float(cpu_total) / 1000.0 / maxf(seconds, 0.001)
		print("bench: %d,%d,%.2f,%.1f,%.2f,%.2f,%.1f,%.1f,%.1f" % [
			count, soldiers, mean / 1000.0, fps, client_ms,
			sim_ms_per_tick, sim_ms_per_s, client_ms_per_s,
			sim_ms_per_s + client_ms_per_s,
		])
		return

	print("bench: %d,%d,%.2f,%.2f,%.1f,%d,%.2f,%d" % [
		count, soldiers,
		mean / 1000.0,
		float(worst) / 1000.0,
		1_000_000.0 / maxf(mean, 1.0),
		calls,
		float(cpu_total) / float(maxi(_process_usec.size(), 1)) / 1000.0,
		_visible_squads,
	])


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in raw_args:
		var text := String(arg)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = true
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out
