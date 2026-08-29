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
var _worst_split := [0, 0, 0]

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
	_width_override = int(args.get("cells_wide", 0))
	_height_override = int(args.get("cells_high", 0))

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
	_lod_tier.clear()

	_sim = SquadSim.new(_space, CurveReplicator.new())
	_sim.set_passable(TerrainGen.new().passability(_space))
	_state = ClientState.new()
	if _sample_terrain:
		_state.terrain_sampler = _terrain_sampler
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
	for i in range(count):
		_sim.add_squad(defs[i % defs.size()], 1, Vector2i(
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
	_visible_squads = 0
	_frame_cull = 0
	_frame_derive = 0
	_frame_upload = 0
	_frame_soldiers = 0
	var offsets := _space.lattice_offsets()
	var viewport_size := get_viewport().get_visible_rect().size

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
			var one: Array[Vector3] = [RenderCull.nearest_offset(drawn, centre, _camera_target)]
			drawn = one
		_frame_cull += Time.get_ticks_usec() - cull_at

		var upload_at := Time.get_ticks_usec()
		unit.set_lattice_offsets(drawn)
		_frame_upload += Time.get_ticks_usec() - upload_at
		if drawn.is_empty():
			continue
		_visible_squads += 1
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
		# shipping client no longer has.
		var derive_at := Time.get_ticks_usec()
		var transforms := _state.soldier_transforms_lod(
			squad_id, _now, _detail_for(squad_id, drawn, centre))
		_frame_derive += Time.get_ticks_usec() - derive_at
		_frame_soldiers += transforms.size()

		upload_at = Time.get_ticks_usec()
		unit.set_slot_transforms(transforms)
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
		_keys_total = 0
		_keys_worst = 0
		_worst_cpu = 0
		_worst_split = [0, 0, 0]
		_phase = Phase.WARMUP
		return

	_now += delta

	var started := Time.get_ticks_usec()
	_refresh_squads()
	var cpu := Time.get_ticks_usec() - started

	if _phase == Phase.WARMUP:
		_frames_seen += 1
		if _frames_seen >= _warmup_frames:
			_phase = Phase.MEASURE
			_frames_seen = 0
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
	if cpu > _worst_cpu:
		_worst_cpu = cpu
		_worst_split = [_frame_cull, _frame_derive, _frame_upload]
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
	print("bench: phases squads=%d cpu=%.2f cull=%.2f derive=%.2f upload=%.2f other=%.2f ms/frame; drawn=%.0f soldiers/frame at %.2f us each; clamp=%d sampler=%d copies=%d" % [
		count, cpu_mean / 1000.0, cull / 1000.0, derive / 1000.0,
		upload / 1000.0, (cpu_mean - cull - derive - upload) / 1000.0,
		derived, derive / maxf(derived, 1.0),
		1 if _clamp_to_ground else 0,
		1 if _sample_terrain else 0,
		1 if _draw_every_copy else 0])
	var frames := float(maxi(_cull_usec.size(), 1))
	var keys_per_squad := float(_keys_total) / frames 		/ maxf(float(_visible_squads), 1.0)
	print("bench: curves squads=%d keys_mean=%.1f keys_worst=%d per drawn squad" % [
		count, keys_per_squad, _keys_worst])
	print("bench: worst-frame squads=%d cpu=%.2f cull=%.2f derive=%.2f upload=%.2f other=%.2f ms" % [
		count, float(_worst_cpu) / 1000.0,
		float(_worst_split[0]) / 1000.0, float(_worst_split[1]) / 1000.0,
		float(_worst_split[2]) / 1000.0,
		float(_worst_cpu - _worst_split[0] - _worst_split[1] - _worst_split[2]) / 1000.0])

	print("bench: %d,%d,%.2f,%.2f,%.1f,%d,%.2f,%d" % [
		count, soldiers,
		mean / 1000.0,
		float(worst) / 1000.0,
		1_000_000.0 / maxf(mean, 1.0),
		calls,
		float(cpu_total) / float(maxi(_process_usec.size(), 1)) / 1000.0,
		_visible_squads,
	])


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
