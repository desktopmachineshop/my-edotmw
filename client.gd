extends Node3D

## GUI client (`just run-client`).
##
## Native-only by D-014: this is the one piece that genuinely needs a GPU,
## so it is not containerized and is not covered by the headless suite.
## Everything it does that CAN be tested headless lives in ClientState,
## which the load-test bots drive through the same code path — so what is
## untested here is the rendering and input glue, not the protocol or the
## soldier derivation.
##
## What this demonstrates, and what M1 is for: the client receives only
## squad curves. Every soldier it draws is recomputed locally from
## (curve, formation, slot index) — see _refresh_squads (D-006).

const CHANNELS := 2
const DEFAULT_SERVER_ADDRESS := "127.0.0.1"
const DEFAULT_SERVER_PORT := 4433

const CAMERA_PAN_SPEED := 18.0
const CAMERA_ZOOM_STEP := 4.0
const CAMERA_MIN_HEIGHT := 8.0
const CAMERA_MAX_HEIGHT := 90.0

## Distinct colours a genuinely-rendered frame must contain. A blank or
## cleared frame has one; lit terrain plus shaded soldiers has hundreds.
## Set low enough to tolerate a software rasteriser's differences, high
## enough that an empty scene cannot pass.
const MIN_DISTINCT_COLOURS := 24

var _host: ENetConnection
var _peer: ENetPacketPeer
var _state := ClientState.new()
var _connected := false

var _unit_def: UnitDef
var _squad_nodes := {}  # squad id -> PrimitiveUnit
var _terrain_root: Node3D
var _camera: Camera3D
var _camera_target := Vector3.ZERO
var _camera_height := 40.0
var _now := 0.0
var _terrain_built := false

# Capture mode (`just test-client`). The real client renders the real
# scene and screenshots itself, rather than a stand-in doing it — same
# reasoning as ClientState being shared with the bots: a test that
# exercises an imitation can pass while the thing itself is broken.
var _run_seconds := -1.0
var _screenshot_path := ""
var _shot_taken := false
var _verdict_reported := false


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	# Inside the compose network the server is a hostname, not localhost,
	# so the address is overridable by env as well as by flag — same
	# convention as bot_client.gd.
	var default_address := OS.get_environment("EDOTMW_SERVER_ADDRESS")
	if default_address == "":
		default_address = DEFAULT_SERVER_ADDRESS
	var address := String(args.get("address", default_address))
	var port := int(args.get("port", DEFAULT_SERVER_PORT))
	_run_seconds = float(args.get("run-seconds", -1.0))
	_screenshot_path = String(args.get("screenshot", ""))

	_unit_def = UnitRoster.first()

	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_update_camera()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.1
	add_child(light)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.55)
	env.ambient_light_energy = 0.6
	environment.environment = env
	add_child(environment)

	_terrain_root = Node3D.new()
	add_child(_terrain_root)

	_host = ENetConnection.new()
	var err := _host.create_host(1, CHANNELS)
	if err != OK:
		push_error("client: could not create ENet host (error %d)" % err)
		return
	_peer = _host.connect_to_host(address, port, CHANNELS)
	if _peer == null:
		push_error("client: could not reach %s:%d" % [address, port])
		return
	print("client: connecting to %s:%d" % [address, port])


func _exit_tree() -> void:
	if _peer != null and _connected:
		_peer.peer_disconnect_now(0)
	if _host != null:
		_host.destroy()
		_host = null


func _process(delta: float) -> void:
	_now += delta
	_service_network()
	_pan_camera(delta)

	if _state.welcomed and not _terrain_built:
		_build_terrain()
		_terrain_built = true

	_refresh_squads()

	if _run_seconds > 0.0 and _now >= _run_seconds:
		_finish_capture()


## Screenshot, self-assess, report, exit. Mirrors bot_client's verdict
## shape deliberately: an exit code is the machine-readable half, so the
## recipe can fail on it rather than trying to infer success from prose.
func _finish_capture() -> void:
	if _verdict_reported:
		return
	_verdict_reported = true

	var image: Image = null
	if _screenshot_path != "":
		# Wait for the frame to actually be drawn before reading it back,
		# otherwise the capture races rendering and yields an empty image.
		await RenderingServer.frame_post_draw
		image = get_viewport().get_texture().get_image()
		var directory := _screenshot_path.get_base_dir()
		if directory != "" and not DirAccess.dir_exists_absolute(directory):
			DirAccess.make_dir_recursive_absolute(directory)
		if image.save_png(_screenshot_path) == OK:
			print("client: wrote %s (%dx%d)" % [
				_screenshot_path, image.get_width(), image.get_height()])
			_shot_taken = true
		else:
			push_error("client: could not write %s" % _screenshot_path)

	var squads_drawn := _squad_nodes.size()
	var soldiers := _state.derive_all(_now)
	var distinct := _distinct_colours(image)

	# A frame that rendered nothing still saves as a valid PNG — it is
	# just one flat colour. Counting distinct colours is what separates
	# "drew the scene" from "wrote out the clear colour", and it is the
	# assertion that makes this a test rather than a screenshot.
	var ok := (
		_state.welcomed
		and _state.desync_count == 0
		and squads_drawn > 0
		and soldiers > 0
		and (_screenshot_path == "" or (_shot_taken and distinct >= MIN_DISTINCT_COLOURS))
	)

	print("client: VERDICT %s — connected=%s squads_drawn=%d soldiers=%d curves=%d desyncs=%d distinct_colours=%d" % [
		"ok" if ok else "failed",
		str(_state.welcomed), squads_drawn, soldiers,
		_state.curves.size(), _state.desync_count, distinct])

	get_tree().quit(0 if ok else 1)


## Sampled rather than exhaustive — a 1280x720 readback is 921,600 pixels
## and the question is only "is there more than a flat fill here".
func _distinct_colours(image: Image) -> int:
	if image == null:
		return 0
	var seen := {}
	var step := 7
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			seen[image.get_pixel(x, y).to_rgba32()] = true
			if seen.size() > MIN_DISTINCT_COLOURS * 4:
				return seen.size()
	return seen.size()


func _service_network() -> void:
	if _host == null:
		return
	while true:
		var event := _host.service(0)
		var type: int = event[0]
		if type == ENetConnection.EVENT_NONE:
			return
		match type:
			ENetConnection.EVENT_CONNECT:
				_connected = true
				print("client: connected")
			ENetConnection.EVENT_DISCONNECT:
				_connected = false
				print("client: disconnected")
			ENetConnection.EVENT_RECEIVE:
				var from_peer: ENetPacketPeer = event[1]
				while from_peer.get_available_packet_count() > 0:
					_state.handle_packet(from_peer.get_packet())


## Terrain is built once as chunk meshes (D-017) — never one mesh per
## cell. The client generates it locally from the map dimensions rather
## than receiving it, which is why terrain generation has to be
## deterministic for a seed.
func _build_terrain() -> void:
	var space := _state.space
	if space == null:
		return
	var terrain := TerrainGen.new()
	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(space, chunk_size)

	# Stand soldiers ON the terrain rather than at y=0. Without this they
	# derive at sea level and render buried inside every hill — which is
	# how this shipped, because every numeric check (squad count, soldier
	# count, desyncs) passes perfectly while the units are underground.
	# Uses the same TerrainGen instance that built the mesh, so the ground
	# a soldier stands on is the ground that was drawn.
	_state.terrain_sampler = func(x: float, z: float) -> float:
		var cell := space.world_to_cell(Vector3(x, 0.0, z))
		return terrain.elevation_at(space, cell) * terrain.height_scale

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95

	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(cx, cy), chunk_size)
			if mesh == null:
				continue
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			_terrain_root.add_child(instance)

	_camera_target = space.to_world(Vector2i(space.width / 2, space.height / 2))
	_update_camera()
	print("client: built %d terrain chunks" % _terrain_root.get_child_count())


## The D-006 payoff, once per frame: for every squad the client knows
## about, recompute every soldier's transform from the squad's curve and
## push them into one MultiMesh (D-009). No soldier position was received.
func _refresh_squads() -> void:
	if _state.space == null:
		return

	for squad_id in _state.curves:
		# Nothing to draw until the server has said what this squad is.
		# Rendering a guessed strength would put every soldier in the
		# wrong place — see NetProtocol.encode_squad_info.
		if not _state.composition.has(squad_id):
			continue

		var unit: PrimitiveUnit = _squad_nodes.get(squad_id, null)
		if unit == null:
			unit = PrimitiveUnit.new()
			add_child(unit)
			var def := UnitRoster.by_id(StringName(_state.composition[squad_id]["def_id"]))
			unit.rebuild(def if def != null else _unit_def)
			_squad_nodes[squad_id] = unit

		var transforms := _state.soldier_transforms(squad_id, _now)
		# Cosmetic decoration is applied on the render path only and is
		# never fed back into anything (D-006 clause 2).
		unit.set_slot_transforms(CosmeticOffset.decorate_all(transforms, _now, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_camera_height = clampf(_camera_height - CAMERA_ZOOM_STEP, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_camera_height = clampf(_camera_height + CAMERA_ZOOM_STEP, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT)
				_update_camera()
			MOUSE_BUTTON_RIGHT:
				_order_to_screen_point(event.position)


## Right-click orders every owned squad to the clicked cell.
##
## Deliberately crude: per-squad selection is UI work and belongs to M3's
## playable MVP, not to M1's netcode proof. What matters here is that the
## click becomes a CELL and is sent as an order for the server to
## interpret — the client never moves anything itself (D-002).
func _order_to_screen_point(screen_position: Vector2) -> void:
	if not _connected or _state.space == null:
		return

	var from := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return
	var distance := -from.y / direction.y
	if distance <= 0.0:
		return

	var cell := _state.space.world_to_cell(from + direction * distance)
	var sent := 0
	for squad_id in _state.squads:
		var order := _state.encode_order(squad_id, cell)
		if not order.is_empty():
			_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
			sent += 1
	if sent > 0:
		print("client: ordered %d squads to cell %s" % [sent, cell])


func _pan_camera(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if move == Vector3.ZERO:
		return
	_camera_target += move.normalized() * CAMERA_PAN_SPEED * delta
	_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	_camera.position = _camera_target + Vector3(0.0, _camera_height, _camera_height * 0.6)
	_camera.look_at(_camera_target, Vector3.UP)


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
