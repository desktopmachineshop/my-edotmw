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

## Per-frame phase breakdown of `_refresh_squads`, with a computed
## residual (#229). The same discipline
## D-20260818-every-microsecond-of-a-tick-has-a-phase imposed on the
## server's tick, for the same reason: this frame reported ONE number, so
## a cost that moved into it could not be attributed to anything and "the
## client got slower" stayed a sentence rather than a finding.
var _cull_usec: Array = []
var _derive_usec: Array = []
var _upload_usec: Array = []
var _soldiers_drawn: Array = []
var _frame_cull := 0
var _frame_derive := 0
var _frame_upload := 0
var _frame_soldiers := 0

## How long the curves being sampled are.
##
## Every per-frame sample of a squad's position, heading and facing walks
## its keyframes, so this is the LENGTH of that loop — and the loop looks
## exactly like this project's most-repeated defect, which is why it is
## printed rather than argued about. The answer it gave: **1.3 keyframes
## mean, 16 worst** per drawn squad at 1,000 squads on the shipped map,
## because D-003 clips a client's copy to a horizon. A bisection over 1.3
## elements is not an optimisation, and this number is what said so
## (D-20260828-every-microsecond-of-a-frame-has-a-phase).
var _keys_total := 0
var _keys_worst := 0

## The phases of the WORST frame, kept beside the means. A mean of 110 ms
## with a 600 ms worst is two different questions, and the second one is
## the visible freeze.
var _worst_cpu := 0
var _worst_split := [0, 0, 0, 0]
## The frame delta the render passes ease against — the client hands
## `SoldierMotion` its own `_frame_delta` and a benchmark that passed a
## constant would price a different walk.
var _last_delta := 0.016

## The RTW render passes, the activity mix that gives them something to
## work on, and the caches the client keeps for them (#240).
var _decorate := true
var _motion := SoldierMotion.new()
var _static_deal := {}
var _drawn := DrawnIndex.new()
## squad -> "fight" | "work" | "march", decided once at setup. A frame
## with nothing fighting and nothing working runs the decoration passes
## over an empty world and prices none of them — the "mechanism correct,
## shipped numbers do nothing" family, applied to a benchmark.
var _doing_kind := {}
var _buildings := 12
var _node_cells_wanted := 48
var _boxes: Array = []
var _building_index := WorldIndex.new()
var _node_cells: Array = []
var _node_lookup := {}
var _node_disc_cache := {}
var _decorate_usec: Array = []
var _gather_usec: Array = []
var _jostle_usec: Array = []
var _enemy_usec: Array = []
var _boxes_usec: Array = []
var _discs_usec: Array = []
var _frame_decorate := 0
var _frame_gather := 0
var _frame_jostle := 0
var _frame_enemy := 0
## What the pipeline is actually handed, per drawn squad. The ablation
## that prices `SquadRender.frame` has to use the real mix or it prices a
## different battle (#315/#316's evidence page).
var _frame_boxes_n := 0
var _frame_discs_n := 0
var _frame_neighbours_n := 0
var _frame_pipeline_squads := 0
var _frame_boxes := 0
var _frame_discs := 0
var _mix := [0, 0, 0]

## Where to write the machine-readable record of this run, for
## `BenchBaseline` to compare against what was recorded (#286). The
## printed lines stay exactly as they were: a human reads those, and a
## check reads this.
var _json_path := ""
var _rows := {}

## Attribution knobs — see `_ready`. Shipping defaults.
var _clamp_to_ground := true
var _sample_terrain := true
var _draw_every_copy := true
var _width_override := 0
var _height_override := 0

var _camera: Camera3D
var _terrain_root: Node3D
var _squad_root: Node3D
var _squad_nodes := {}
## The one-int-per-squad LOD memory the client keeps (#155). Cleared with
## the squads in `_setup_count`, because a rung of the sweep re-uses squad
## ids for a different number of squads at a different spread.
var _lod_tier := {}
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
## The surface field, handed to `ClientState` so per-man derivation takes
## the one-cell path the client takes (#245).
var _terrain_surface := PackedFloat32Array()

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
	# Attribution knobs (#229). Every one defaults to what the client
	# ships, so an invocation naming none measures exactly what it
	# measured yesterday — the rule `--ai-profiles` already follows. They
	# exist because "the frame tripled and four things changed" is not an
	# attribution: the only honest way to separate four candidates is to
	# turn each off in an interleaved A/B, which is the shape
	# D-20260818-every-microsecond-of-a-tick-has-a-phase used on the
	# server's own unexplained per-squad rise.
	_clamp_to_ground = int(args.get("clamp", 1)) != 0
	_sample_terrain = int(args.get("sampler", 1)) != 0
	_draw_every_copy = int(args.get("copies", 1)) != 0
	# The RTW render passes (#240). ON by default, because they are what
	# the client runs: every frame time recorded before this existed was a
	# floor for a client nobody was timing. `--decorate=0` is the old bare
	# pipeline, kept for the A/B and for reading a historical number in
	# the terms it was taken in.
	_decorate = int(args.get("decorate", 1)) != 0
	# How much the ground is dressed with. The client's own box and disc
	# lookups are per drawn squad, so how they SCALE with what a match has
	# built is a question this benchmark can answer and nothing else can.
	_buildings = int(args.get("buildings", BENCH_BUILDINGS))
	_node_cells_wanted = int(args.get("nodes", BENCH_NODE_CELLS))
	_width_override = int(args.get("cells_wide", 0))
	_height_override = int(args.get("cells_high", 0))
	# Where to write this run as data (#286). Empty means "print only",
	# which is every invocation this recipe had before a baseline existed.
	_json_path = String(args.get("json", ""))
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
	if _width_override > 0 or _height_override > 0:
		# Duplicated, never mutated in place: the shipped .tres is what
		# every other recipe loads, and a benchmark that edited it would
		# be `just profile`'s own blind spot with a new door.
		_config = _config.duplicate() as MapConfig
		if _width_override > 0:
			_config.width = _width_override
		if _height_override > 0:
			_config.height = _height_override
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
	_dress_the_ground()


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
	_terrain_surface = surface

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
	_lod_tier.clear()

	_sim = SquadSim.new(_space, CurveReplicator.new())
	_sim.set_passable(_bench_terrain().passability(_space))
	if _host_mode:
		_build_host_world()
	_state = ClientState.new()
	if _sample_terrain:
		_state.terrain_sampler = _terrain_sampler
		_state.terrain_surface = _terrain_surface
	if _clamp_to_ground:
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

	# One squad in six fights (paired with its neighbour), one in six works
	# a node, the rest march — a mix with something in every branch of the
	# render pipeline, which is what stops the decoration passes being
	# present and never exercised.
	_doing_kind = {}
	_mix = [0, 0, 0]
	for squad in range(_sim.squad_count()):
		match squad % 6:
			0:
				_doing_kind[squad] = "fight"
				_doing_kind["enemy:%d" % squad] = (squad + 1) % _sim.squad_count()
				_mix[0] += 1
			1:
				_doing_kind[squad] = "work"
				_mix[1] += 1
			_:
				_doing_kind[squad] = "march"
				_mix[2] += 1

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


## Buildings and woodland near the camera, so the push-out passes have
## something to push out of (#240).
##
## Synthesised rather than simulated: `client.gd` resolves these from
## `ClientState`'s known buildings and revealed nodes into exactly this
## shape — {centre, half, yaw} and a cell id — and what is being measured
## is the per-MAN cost of testing a man against them, not the per-frame
## cost of building the list. The counts are printed so a reader knows
## what mix produced the number.
const BENCH_BUILDINGS := 12
const BENCH_NODE_CELLS := 48


func _dress_the_ground() -> void:
	_boxes = []
	_node_cells = []
	_node_lookup = {}
	_node_disc_cache = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD0E5
	_building_index.begin()
	for i in range(_buildings):
		var at := _camera_target + Vector3(
			rng.randf_range(-60.0, 60.0), 0.0, rng.randf_range(-40.0, 40.0))
		if _terrain_sampler.is_valid():
			at.y = _terrain_sampler.call(at.x, at.z)
		var half := Vector2(rng.randf_range(1.2, 3.0), rng.randf_range(1.2, 3.0))
		_boxes.append({"centre": at, "half": half,
			"yaw": rng.randf_range(0.0, TAU),
			"reach": maxf(half.x, half.y)})
		# Bucketed exactly as the client buckets its own (#325) — the
		# benchmark measures the client, so it indexes like the client.
		_building_index.put(at, _boxes.size() - 1, maxf(half.x, half.y))
	for i in range(_node_cells_wanted):
		var cell := _space.world_to_cell(_camera_target + Vector3(
			rng.randf_range(-70.0, 70.0), 0.0, rng.randf_range(-50.0, 50.0)))
		var index := _space.index(cell)
		_node_cells.append(index)
		_node_lookup[index] = true


## What this squad is visibly doing, in `client.gd`'s own `_activity_for`
## shape. Assigned at setup rather than resolved from the world: the
## resolver needs a real economy and real enemies, and what this
## benchmark is pricing is the pipeline the answer feeds, not the answer.
func _doing_for(squad_id) -> Dictionary:
	var kind: String = _doing_kind.get(squad_id, "march")
	if kind == "work":
		var at := _state.squad_world_position(squad_id, _now)
		var node_at := _space.to_world(_space.world_to_cell(at))
		return {
			"activity": CosmeticOffset.Activity.WORKING, "toward": node_at,
			"working": 0, "swing": CosmeticOffset.SWING_AMPLITUDE,
			"is_ranged": false, "interval": 0.0, "enemy_squad": -1,
			"ring_centre": node_at, "ring_radius": 0.9,
			"target_key": "n:%d" % _space.index(_space.world_to_cell(at)),
		}
	if kind == "fight":
		return {
			"activity": CosmeticOffset.Activity.FIGHTING,
			"toward": _state.squad_world_position(squad_id, _now),
			"working": AnimationState.NOT_WORKING,
			"swing": CosmeticOffset.SWING_AMPLITUDE,
			"is_ranged": false, "interval": 1.0,
			"enemy_squad": int(_doing_kind.get("enemy:%d" % int(squad_id), -1)),
		}
	return {
		"activity": CosmeticOffset.Activity.IDLE, "toward": Vector3.ZERO,
		"working": AnimationState.NOT_WORKING,
		"swing": CosmeticOffset.SWING_AMPLITUDE,
		"is_ranged": false, "interval": 0.0, "enemy_squad": -1,
	}


## The client's own `_nearby_building_boxes` filter, over the synthesised
## list — including the torus tax, which is per squad per building and is
## part of what is being priced.
func _boxes_near(centre: Vector3, search: float, offsets: Array[Vector3]) -> Array:
	var out := []
	for which in _building_index.near(centre, search + 4.0):
		var entry: Dictionary = _boxes[which]
		var at: Vector3 = entry["centre"]
		at += Engagement.aligning_offset(centre, at, offsets)
		if Vector2(at.x - centre.x, at.z - centre.z).length() <= search + 4.0:
			out.append({"centre": at, "half": entry["half"], "yaw": entry["yaw"]})
	return out


## The client's own `_nearby_node_discs`, structured the way the client
## structures it: a bounded disk of CELLS around the squad, the torus tax
## paid only for cells that actually hold a node, and the per-cell disc
## list CACHED — `ResourceVisuals.clearance_discs` places a whole stand of
## trees and would otherwise be re-rolled per squad per frame, which is a
## cost the client does not pay and a benchmark must not invent.
func _discs_near(centre: Vector3, radius: float, offsets: Array[Vector3]) -> Array:
	var out := []
	if _node_cells.is_empty():
		return out
	var centre_cell := _space.world_to_cell(centre)
	var cells := ceili(radius / (_space.hex_size * TorusSpace.SQRT_3)) + 1
	# One call for the whole disk, exactly as the client does it (#325).
	for cell in _space.disk_indices(_space.index(centre_cell), mini(cells, 6)):
		if not _node_lookup.has(cell):
			continue
		var at := _space.to_world(_space.from_index(cell))
		at += Engagement.aligning_offset(centre, at, offsets)
		for disc in _cell_discs(cell):
			out.append({"centre": at + (disc["offset"] as Vector3),
				"radius": float(disc["radius"])})
	return out


## `client.gd`'s `_node_cell_discs`: the stand a cell grows, resolved once
## and kept. Same call, same cache shape.
func _cell_discs(cell: int) -> Array:
	var cached = _node_disc_cache.get(cell)
	if cached != null:
		return cached
	var discs := ResourceVisuals.clearance_discs(
		0, TerrainGen.Biome.FOREST, [], 0.6, cell, _space.hex_size)
	_node_disc_cache[cell] = discs
	return discs


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


## What client.gd's _refresh_squads does — cull, derive, upload — minus
## the ghost pass (this harness never conceals anything) and minus every
## RENDER PASS the RTW battle programme added.
##
## That second omission is a defect in this file and is filed as #240: the
## client also runs the cosmetic duels, the corpse layer, the survivor
## easing in `soldier_motion.gd`, the neighbour jostle and the
## building/tree push-outs, all per drawn man, and none of them are here.
## (Named by FILE rather than by class on purpose: `test_tier_three.gd`
## scans every script for the class's identifier and this one is not on
## its list, which is the guard working.) So every
## number this benchmark prints is a FLOOR for the shipped client, and
## this comment says so rather than claiming the equality it used to
## claim. Fixing it changes what every previously recorded number means,
## which is why it is an issue and not a patch.
func _refresh_squads() -> void:
	_drawn.begin()
	_visible_squads = 0
	_frame_cull = 0
	_frame_derive = 0
	_frame_upload = 0
	_frame_decorate = 0
	_frame_gather = 0
	_frame_jostle = 0
	_frame_enemy = 0
	_frame_boxes_n = 0
	_frame_discs_n = 0
	_frame_neighbours_n = 0
	_frame_pipeline_squads = 0
	_frame_boxes = 0
	_frame_discs = 0
	_frame_soldiers = 0
	var offsets := _space.lattice_offsets()
	var viewport_size := get_viewport().get_visible_rect().size
	# Hoisted out of the per-squad loop, which is #263's own change and
	# was lost in the merge — the two `nearest_offset` call sites below
	# read it, and without the declaration the file PARSES and does not
	# COMPILE. `tests/test_scripts_parse.gd` is what found it, which is
	# the guard 87 added for exactly this: GUT skips a script that fails
	# to compile and reports success with its assertions gone.
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
		var cull_at := Time.get_ticks_usec()
		var centre := _state.squad_world_position(squad_id, _now)
		# Every visible lattice copy, exactly as the client draws it
		# (D-20260818-entities-are-drawn-at-every-visible-copy). The whole
		# claim of that change is that extra copies cost draw calls and
		# not derivation, so a benchmark that still drew one of them would
		# be measuring the version of the client that does not ship.
		var drawn := RenderCull.visible_offsets_of_extent(
			_camera, offsets, centre, SQUAD_CULL_RADIUS, 192.0, viewport_size)
		if not _draw_every_copy and drawn.size() > 1:
			# The pre-D-20260818 client, for the A/B only: ONE copy drawn,
			# whichever the old rule picked. Never a default — that client
			# had armies vanishing at the seam, and the point here is to
			# price the copies, not to bring the bug back.
			var one: Array[Vector3] = [RenderCull.nearest_offset(drawn, centre, target)]
			drawn = one
		_frame_cull += Time.get_ticks_usec() - cull_at

		var upload_at := Time.get_ticks_usec()
		unit.set_lattice_offsets(drawn)
		_frame_upload += Time.get_ticks_usec() - upload_at
		if drawn.is_empty():
			continue
		_visible_squads += 1
		var offset := RenderCull.nearest_offset(drawn, centre, target)
		var curve: StateCurve = _state.curves.get(squad_id, null)
		if curve != null:
			_keys_total += curve.key_count()
			_keys_worst = maxi(_keys_worst, curve.key_count())

		# DERIVE and UPLOAD are timed apart, which is the whole of #229:
		# the frame was one number before this, so a tripling had nowhere
		# to be attributed. `_detail_for` carries the squad id and the
		# drawn offsets because the LOD ladder is hysteretic now (#155,
		# #221) — it keeps one int per squad, so a benchmark that asked
		# for a tier by world position alone would re-derive on flips the
		# shipping client no longer has. #263 kept THIS call and not its
		# own older one: a benchmark that runs the client's pipeline and
		# then prices a ladder the client retired is the drift this whole
		# PR exists to close.
		var derive_at := Time.get_ticks_usec()
		var transforms := _state.soldier_transforms_lod(
			squad_id, _now, _detail_for(squad_id, drawn, centre))
		_frame_derive += Time.get_ticks_usec() - derive_at
		_frame_soldiers += transforms.size()

		# The RENDER PASSES, through the same `SquadRender.frame` the
		# client runs (#240). Without them this benchmark measured a
		# client missing its duels, its corpses, its easing, its jostle
		# and its building/tree push-outs, while its own comment claimed
		# otherwise — the `just profile`-vs-live-server lesson (D-043
		# criterion 11) in instrument form.
		var decorate_at := Time.get_ticks_usec()
		var clip := 0
		if _decorate:
			# GATHERING is the client's half — what the squad is doing,
			# which enemy men to pair against, which boxes and discs and
			# foreign men are near. Timed apart from the pipeline because
			# a 200 ms phase with one number is the very complaint #240
			# is about, one level down.
			var gather_at := Time.get_ticks_usec()
			var doing := _doing_for(squad_id)
			# The OPPONENT's drawn men, which is a second full derivation
			# of a squad that was very likely derived already this frame
			# (#317's attribution said derivation is the expensive
			# arithmetic, so deriving one twice is worth knowing about).
			var enemy_at := Time.get_ticks_usec()
			var enemy: Array[Transform3D] = []
			if int(doing.get("enemy_squad", -1)) >= 0:
				enemy = _state.soldier_transforms_lod(
					int(doing["enemy_squad"]), _now,
					_detail_for(int(doing["enemy_squad"]), drawn, centre))
			_frame_enemy += Time.get_ticks_usec() - enemy_at
			var speed := _state.squad_speed(squad_id, _now)
			var neighbours := PackedVector3Array()
			# The cross-squad JOSTLE gather, timed on its own because it
			# was the one part of a frame that was QUADRATIC in drawn
			# squads (#262). Through `DrawnIndex` now, exactly as the
			# client does it — the whole point of #240 is that this
			# benchmark runs the client's code rather than a copy of it.
			var jostle_at := Time.get_ticks_usec()
			if speed <= SquadRender.MOVING_SPEED_EPSILON:
				neighbours = _drawn.neighbours_of(
					squad_id, centre + offset, SQUAD_CULL_RADIUS)
			_frame_jostle += Time.get_ticks_usec() - jostle_at
			var boxes_at := Time.get_ticks_usec()
			var boxes := _boxes_near(centre, SQUAD_CULL_RADIUS + 6.0, offsets)
			_frame_boxes += Time.get_ticks_usec() - boxes_at
			var discs_at := Time.get_ticks_usec()
			var discs := _discs_near(centre, SQUAD_CULL_RADIUS, offsets)
			_frame_discs += Time.get_ticks_usec() - discs_at
			_frame_gather += Time.get_ticks_usec() - gather_at

			_frame_boxes_n += boxes.size()
			_frame_discs_n += discs.size()
			_frame_neighbours_n += neighbours.size()
			_frame_pipeline_squads += 1
			var rendered := SquadRender.frame({
				"transforms": transforms,
				"doing": doing,
				"enemy_transforms": enemy,
				"deal": _static_deal.get(squad_id, {}),
				"offsets": offsets,
				"boxes": boxes,
				"discs": discs,
				"terrain_sampler": _state.terrain_sampler,
				"motion": _motion,
				"squad_id": squad_id,
				"delta": _last_delta,
				"now": _now,
				"speed": speed,
				"pursuit_speed": 1.35,
				"neighbours": neighbours,
				"routed": false,
				"model_id": &"",
			})
			transforms = rendered["transforms"]
			clip = int(rendered["clip"])
			_static_deal[squad_id] = rendered["deal"]
			_drawn.put(squad_id, centre + offset, SQUAD_CULL_RADIUS,
				rendered["drawn_men"])
		_frame_decorate += Time.get_ticks_usec() - decorate_at

		upload_at = Time.get_ticks_usec()
		unit.set_slot_transforms(transforms)
		if _decorate:
			unit.set_clip_data(int(squad_id), clip,
				_state.squad_speed(squad_id, _now), _motion.speeds(squad_id))
		_frame_upload += Time.get_ticks_usec() - upload_at


## The client's own LOD, through the client's own arithmetic. This used to
## be a hand-copy of the three tier numbers under a comment reading "if the
## tiers are retuned, both move"; they live in `RenderCull` now, so it
## cannot fail to. What is still duplicated is the one-int-per-squad memory
## the hysteresis band needs (#155) — the benchmark exists to measure the
## client, and a benchmark that ran a MEMORYLESS ladder would re-derive on
## tier flips the shipping client no longer has.
func _detail_for(squad_id, offsets: Array[Vector3], centre: Vector3) -> int:
	var tier := RenderCull.detail_tier(
		RenderCull.lod_distance(offsets, centre, _camera.global_position),
		int(_lod_tier.get(squad_id, -1)))
	_lod_tier[squad_id] = tier
	return RenderCull.lod_soldiers(tier)


func _process(delta: float) -> void:
	if _phase == Phase.DONE:
		return

	if _phase == Phase.SETUP:
		_setup_count(int(_counts[_index]))
		_frames_seen = 0
		_frame_usec.clear()
		_draw_calls.clear()
		_process_usec.clear()
		_cull_usec.clear()
		_derive_usec.clear()
		_upload_usec.clear()
		_soldiers_drawn.clear()
		_decorate_usec.clear()
		_gather_usec.clear()
		_jostle_usec.clear()
		_enemy_usec.clear()
		_boxes_usec.clear()
		_discs_usec.clear()
		_motion = SoldierMotion.new()
		_static_deal = {}
		_drawn = DrawnIndex.new()
		_keys_total = 0
		_keys_worst = 0
		_worst_cpu = 0
		_worst_split = [0, 0, 0, 0]
		_sim_usec.clear()
		_ticks_run = 0
		_tick_accumulator = 0.0
		_phase = Phase.WARMUP
		return

	_now += delta
	_last_delta = delta

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
	_cull_usec.append(_frame_cull)
	_derive_usec.append(_frame_derive)
	_upload_usec.append(_frame_upload)
	_soldiers_drawn.append(_frame_soldiers)
	_decorate_usec.append(_frame_decorate)
	_gather_usec.append(_frame_gather)
	_jostle_usec.append(_frame_jostle)
	_enemy_usec.append(_frame_enemy)
	_boxes_usec.append(_frame_boxes)
	_discs_usec.append(_frame_discs)
	if cpu > _worst_cpu:
		_worst_cpu = cpu
		_worst_split = [_frame_cull, _frame_derive, _frame_upload, _frame_decorate]
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
			_write_json()
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
	# The breakdown, on its own line so the CSV keeps the shape every
	# previous run was quoted in. `other` is the RESIDUAL — the part of
	# our own per-frame work none of the three phases claimed — printed
	# rather than left implicit, because a breakdown whose parts do not
	# add up to the whole is a breakdown that can hide the thing being
	# looked for.
	var cull := _mean(_cull_usec)
	var derive := _mean(_derive_usec)
	var upload := _mean(_upload_usec)
	var cpu_mean := float(cpu_total) / float(maxi(_process_usec.size(), 1))
	var derived := _mean(_soldiers_drawn)
	var decorate := _mean(_decorate_usec)
	var gather := _mean(_gather_usec)
	var jostle := _mean(_jostle_usec)
	var enemy := _mean(_enemy_usec)
	var boxes := _mean(_boxes_usec)
	var discs := _mean(_discs_usec)
	print("bench: phases squads=%d cpu=%.2f cull=%.2f derive=%.2f decorate=%.2f upload=%.2f other=%.2f ms/frame; drawn=%.0f soldiers/frame at %.2f us each; clamp=%d sampler=%d copies=%d decorate=%d" % [
		count, cpu_mean / 1000.0, cull / 1000.0, derive / 1000.0,
		decorate / 1000.0, upload / 1000.0,
		(cpu_mean - cull - derive - decorate - upload) / 1000.0,
		derived, (derive + decorate) / maxf(derived, 1.0),
		1 if _clamp_to_ground else 0,
		1 if _sample_terrain else 0,
		1 if _draw_every_copy else 0,
		1 if _decorate else 0])
	if _decorate:
		# The MIX, because the decoration passes cost what the world gives
		# them: a frame with nothing fighting prices no duels. A number
		# quoted without this is a number about a different battle.
		print("bench: mix squads=%d fighting=%d working=%d marching=%d; %d buildings, %d node cells near the camera" % [
			count, _mix[0], _mix[1], _mix[2], _boxes.size(), _node_cells.size()])
		print("bench: decorate squads=%d gather=%.2f (jostle %.2f) pipeline=%.2f ms/frame (%.2f us per drawn man)" % [
			count, gather / 1000.0, jostle / 1000.0,
			(decorate - gather) / 1000.0, decorate / maxf(derived, 1.0)])
		# Inside the gather. `rest` is the residual — activity resolution
		# and the squad's own speed — printed rather than left implicit,
		# for the same reason every other phase line here carries one.
		print("bench: handed squads=%d %.1f boxes, %.1f discs, %.1f foreign men per drawn squad (%d squads through the pipeline)" % [
			count,
			float(_frame_boxes_n) / maxf(float(_frame_pipeline_squads), 1.0),
			float(_frame_discs_n) / maxf(float(_frame_pipeline_squads), 1.0),
			float(_frame_neighbours_n) / maxf(float(_frame_pipeline_squads), 1.0),
			_frame_pipeline_squads])
		print("bench: gather squads=%d enemy=%.2f boxes=%.2f discs=%.2f jostle=%.2f rest=%.2f ms/frame" % [
			count, enemy / 1000.0, boxes / 1000.0, discs / 1000.0,
			jostle / 1000.0,
			(gather - enemy - boxes - discs - jostle) / 1000.0])
	var frames := float(maxi(_cull_usec.size(), 1))
	var keys_per_squad := float(_keys_total) / frames 		/ maxf(float(_visible_squads), 1.0)
	print("bench: curves squads=%d keys_mean=%.1f keys_worst=%d per drawn squad" % [
		count, keys_per_squad, _keys_worst])
	print("bench: worst-frame squads=%d cpu=%.2f cull=%.2f derive=%.2f decorate=%.2f upload=%.2f other=%.2f ms" % [
		count, float(_worst_cpu) / 1000.0,
		float(_worst_split[0]) / 1000.0, float(_worst_split[1]) / 1000.0,
		float(_worst_split[3]) / 1000.0, float(_worst_split[2]) / 1000.0,
		float(_worst_cpu - _worst_split[0] - _worst_split[1]
			- _worst_split[2] - _worst_split[3]) / 1000.0])

	_rows[str(count)] = {
		"soldiers": soldiers,
		"drawn": int(round(derived)),
		"squads_drawn": _visible_squads,
		"draw_calls": calls,
		"keys_worst": _keys_worst,
		"fighting": _mix[0],
		"working": _mix[1],
		"marching": _mix[2],
		"cpu_ms": cpu_mean / 1000.0,
		"wall_ms": mean / 1000.0,
		"worst_ms": float(worst) / 1000.0,
		"cull_ms": cull / 1000.0,
		"derive_ms": derive / 1000.0,
		"decorate_ms": decorate / 1000.0,
		"upload_ms": upload / 1000.0,
		"jostle_ms": jostle / 1000.0,
	}

	print("bench: %d,%d,%.2f,%.2f,%.1f,%d,%.2f,%d" % [
		count, soldiers,
		mean / 1000.0,
		float(worst) / 1000.0,
		1_000_000.0 / maxf(mean, 1.0),
		calls,
		float(cpu_total) / float(maxi(_process_usec.size(), 1)) / 1000.0,
		_visible_squads,
	])


## This run, as data: what it counted, what it timed, and what it was
## measured against. The FINGERPRINT rides along because a number without
## the tree it was taken on is the thing #286 is about — a recorded
## figure nobody can tell is stale.
func _write_json() -> void:
	if _json_path == "":
		return
	var record := {
		"version": BenchBaseline.VERSION,
		"recorded": Time.get_date_string_from_system(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"headless": DisplayServer.get_name() == "headless",
		# The CULL reads the viewport, so every drawn count is a count AT
		# THIS SIZE. Recorded so a comparison can refuse rather than blame
		# the renderer for a runner with a different window.
		"viewport": "%dx%d" % [
			get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y],
		"frames": _frames_to_measure,
		"camera_height": _camera_height,
		"knobs": {
			"clamp": 1 if _clamp_to_ground else 0,
			"sampler": 1 if _sample_terrain else 0,
			"copies": 1 if _draw_every_copy else 0,
			"decorate": 1 if _decorate else 0,
		},
		"fingerprint": BenchBaseline.fingerprint(),
		"rows": _rows,
	}
	var path := _json_path
	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		push_error("bench: could not write %s" % path)
		return
	handle.store_string(JSON.stringify(record, "\t", true))
	handle.close()
	print("bench: wrote %s" % path)


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


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
