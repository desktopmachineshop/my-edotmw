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

## M2 capture-mode scenario (`just test-client`) — see _drive_m2_scenario().
##
## Active ONLY when _run_seconds > 0.0 (i.e. never during `just run-client`,
## which is a human at the wheel and must never have its squads hijacked).
## A single client with no opponent cannot exercise combat or fog at all —
## every squad is at full strength and ghosts=0 no matter how correct the
## rendering is (this is exactly the M1-era gap this scenario closes: see
## CLAUDE.md's account of the first frame that ever rendered no soldiers,
## and this file's own note on ghosts below). So the recipe now also brings
## up load-test bots, and this scenario sends a handful of this client's
## squads toward a neighbouring player's estimated spawn — mirroring
## bot_client.gd's own rally/recall scripting and for the identical reason
## documented there: two players' squads meeting inside a short run is
## mostly luck (D-024/D-025's attack/vision ranges are short relative to
## the deliberate per-player spread in server.gd's _spawn_squads_for), so
## leaving contact to chance would make the verdict conditions below flaky
## rather than a real check.
##
## NEIGHBOR_SPAWN_*_STEP duplicate server.gd's _spawn_squads_for formula
## (lane = (player * 7) % height, x = (player * 5 + i * 2) % width) — the
## same deliberate, documented coupling bot_client.gd already has, extended
## to a second file for the same reason: it only shapes a scenario (where
## to send scouts), never a correctness assertion. If server.gd's spawn
## formula ever changes, this rendezvous goes stale — which shows up as
## casualties_applied/conceal_events/reveal_events falling to zero and the
## verdict going red, loudly, not silently.
const NEIGHBOR_SPAWN_X_STEP := 5
const NEIGHBOR_SPAWN_Y_STEP := 7
const SCOUT_COUNT := 4
const RALLY_AT_SECONDS := 1.0
const WITHDRAW_AT_SECONDS := 9.0
const RE_RALLY_AT_SECONDS := 14.0

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

# M2 scenario scripting state (see the constants above). `_scout_squads` and
# `_scout_home` are populated once, on the first rally, so withdraw/re-rally
# act on the same squads and can send them back to where they actually
# started rather than a freshly-sampled (by then, mid-march) position.
var _scout_squads: Array = []
var _scout_home := {}
var _rallied := false
var _withdrawn := false
var _re_rallied := false


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

	if _run_seconds > 0.0:
		_drive_m2_scenario()
		if _now >= _run_seconds:
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
	var live_squads := _state.live_squad_ids().size()
	var ghosts := _state.ghost_squad_ids().size()

	# A frame that rendered nothing still saves as a valid PNG — it is
	# just one flat colour. Counting distinct colours is what separates
	# "drew the scene" from "wrote out the clear colour", and it is the
	# assertion that makes this a test rather than a screenshot.
	# M2 observation counters, same fields and same reasoning as
	# bot_client.gd's _verdict_ok(): a run in which nobody ever died proves
	# nothing about combat, and a run in which nothing was ever hidden or
	# re-shown proves nothing about fog, however clean the rest of the
	# verdict looks (D-026 criterion 9). Requiring all three here is what
	# makes `just test-client` verify M2 rather than only re-verifying M1's
	# rendering with a livelier-looking scene — see _drive_m2_scenario()
	# for how contact is made reliable rather than left to chance.
	var ok := (
		_state.welcomed
		and _state.desync_count == 0
		and squads_drawn > 0
		and soldiers > 0
		and (_screenshot_path == "" or (_shot_taken and distinct >= MIN_DISTINCT_COLOURS))
		and _state.casualties_applied > 0
		and _state.conceal_events > 0
		and _state.reveal_events > 0
	)

	# live_squads/ghosts/soldiers make D-026 criterion 11's visual half
	# checkable from the log, not only by eye: soldiers should visibly fall
	# as casualties land (this same number is what a human looking at
	# client-frame.png should be able to count), and ghosts should be
	# rendered distinctly rather than as though still live (see
	# _set_ghost_look) — neither of which the pre-M2 verdict could say
	# anything about at all.
	print("client: VERDICT %s — connected=%s squads_drawn=%d live_squads=%d ghosts=%d soldiers=%d curves=%d desyncs=%d distinct_colours=%d casualties_applied=%d conceal_events=%d reveal_events=%d ghosts_peak=%d" % [
		"ok" if ok else "failed",
		str(_state.welcomed), squads_drawn, live_squads, ghosts, soldiers,
		_state.curves.size(), _state.desync_count, distinct,
		_state.casualties_applied, _state.conceal_events, _state.reveal_events, _state.ghosts_peak])

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
##
## Ghosts (D-025 part 3) get their own pass below rather than falling
## through this loop unchanged. Before this existed, a concealed squad's
## node simply stopped being touched here — since it wasn't in
## `composition` it hit the `continue` below and kept whatever transforms
## it had at the instant of conceal, forever, with no visual difference
## from a squad that is still live and simply idle. That is exactly "drawn
## as though it were live", which D-026 criterion 11 rules out: a ghost is
## last-known information, not a soldier still standing there.
func _refresh_squads() -> void:
	if _state.space == null:
		return

	for squad_id in _state.curves:
		# Nothing to draw until the server has said what this squad is.
		# Rendering a guessed strength would put every soldier in the
		# wrong place — see NetProtocol.encode_squad_info.
		if not _state.composition.has(squad_id):
			continue

		var unit := _squad_node(squad_id, String(_state.composition[squad_id]["def_id"]))
		_set_ghost_look(unit, false)

		var transforms := _state.soldier_transforms(squad_id, _now)
		# Cosmetic decoration is applied on the render path only and is
		# never fed back into anything (D-006 clause 2).
		unit.set_slot_transforms(CosmeticOffset.decorate_all(transforms, _now, 1.0))

	for squad_id in _state.ghost_squad_ids():
		var ghost := _state.ghost_info(squad_id)
		if ghost.is_empty() or not _state.curves.has(squad_id):
			continue

		var unit := _squad_node(squad_id, String(ghost["def_id"]))
		_set_ghost_look(unit, true)

		# Derived straight from Formation, like ClientState.soldier_transforms
		# does for a live squad — but reading the GHOST's last-known alive/
		# shape/spacing (D-025 part 3), not `composition`, which no longer
		# has an entry for this id at all. The curve itself was left
		# untouched on conceal (ClientState._handle_squad_conceal's own
		# comment) and StateCurve holds at its last keyframe past its end
		# time, so this samples exactly the frozen last-known position —
		# not a guess, not an extrapolation.
		var transforms := Formation.soldier_transforms(
			_state.curves[squad_id], _now, int(ghost["alive"]), String(ghost["shape"]),
			float(ghost["spacing"]), _state.space, _state.terrain_sampler)
		unit.set_slot_transforms(transforms)


## Find-or-build the PrimitiveUnit for a squad id, shared by the live and
## ghost passes above so a squad concealed and later revealed (or vice
## versa) reuses the same node rather than flashing a fresh one.
func _squad_node(squad_id, def_id: String) -> PrimitiveUnit:
	var unit: PrimitiveUnit = _squad_nodes.get(squad_id, null)
	if unit == null:
		unit = PrimitiveUnit.new()
		add_child(unit)
		var def := UnitRoster.by_id(StringName(def_id))
		unit.rebuild(def if def != null else _unit_def)
		_squad_nodes[squad_id] = unit
	return unit


## Visually distinguish a ghost from a live squad (D-026 criterion 11).
## Looked up by type rather than an index PrimitiveUnit doesn't publish, so
## this keeps working even if PrimitiveUnit's own child layout changes.
##
## GeometryInstance3D.transparency (tried first, and left as the doc
## comment's cautionary tale) is per-instance and does not touch
## PrimitiveUnit's own material — which sounded like exactly the right
## layering, since PrimitiveUnit is combat/vision's file to rebuild from
## UnitDef, not this one's to change. It also does not render as
## translucent at all under the `gl_compatibility` rendering method,
## which is the ONLY renderer `just test-client` can use (Mesa ships
## software OpenGL, not software Vulkan — see D-014's 2026-07-29
## amendment). Confirmed by turning it up to 0.95 and finding the frame
## from `just test-client` pixel-identical to 0.6: a property this test's
## own renderer silently ignores is worse than no ghost styling at all,
## since it would look correct on a native `run-client` GPU and invisible
## in the one place D-026 criterion 11 requires it to actually be checked.
##
## So this instead toggles the MATERIAL's own alpha blending — a
## StandardMaterial3D `material_override` PrimitiveUnit already attaches
## to this exact node (see primitive_unit.gd's rebuild()), reached via its
## public property, not by reconstructing or replacing it. Alpha blending
## is a baseline feature of every rendering method this project uses, so
## unlike the instance shortcut this actually shows up in a screenshot.
func _set_ghost_look(unit: PrimitiveUnit, is_ghost: bool) -> void:
	for child in unit.get_children():
		if child is MultiMeshInstance3D:
			var material := (child as MultiMeshInstance3D).material_override
			if material is StandardMaterial3D:
				var mat := material as StandardMaterial3D
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if is_ghost else BaseMaterial3D.TRANSPARENCY_DISABLED
				var albedo := mat.albedo_color
				albedo.a = 0.35 if is_ghost else 1.0
				mat.albedo_color = albedo
			return


## Capture-mode-only scripted maneuver (see the constants above this file).
## Rallies a handful of squads toward a neighbouring player's estimated
## spawn, then withdraws them, then sends them out again — giving this
## client an actual reveal -> conceal -> reveal cycle to observe, rather
## than hoping idle squads happen to wander into contact. Each phase fires
## exactly once (guarded by the _rallied/_withdrawn/_re_rallied flags), on
## whichever frame first reaches its time.
func _drive_m2_scenario() -> void:
	if not _connected or not _state.welcomed or _state.squads.is_empty():
		return

	if not _rallied and _now >= RALLY_AT_SECONDS:
		_issue_scenario_rally()
		_rallied = true

	if _rallied and not _withdrawn and _now >= WITHDRAW_AT_SECONDS:
		_issue_scenario_withdraw()
		_withdrawn = true

	if _withdrawn and not _re_rallied and _now >= RE_RALLY_AT_SECONDS:
		_issue_scenario_rally()
		_re_rallied = true


## Send up to SCOUT_COUNT squads toward a neighbouring player's estimated
## spawn cell. Picks the scouts and records their home cells the FIRST time
## only, so a later call (the re-rally) sends the same squads back out
## rather than picking a fresh set.
##
## Targets BOTH id-1 and id+1: with exactly one client and N bots, player
## ids are assigned 1..(N+1) in join order with no gaps, so whichever id
## this client was given, at least one of its numeric neighbours is
## guaranteed to be an actual bot (the other, if out of [1, N+1], is simply
## a cell nobody occupies — harmless, not an error). This makes the
## scenario independent of connection-order races between the client
## container and the bots container.
func _issue_scenario_rally() -> void:
	if _state.space == null:
		return
	var first_rally := _scout_squads.is_empty()
	if first_rally:
		var count := mini(SCOUT_COUNT, _state.squads.size())
		for i in range(count):
			var squad: int = _state.squads[i]
			_scout_squads.append(squad)
			_scout_home[squad] = _state.squad_cell(squad, _now)

	var candidates := _neighbor_player_candidates()
	for i in range(_scout_squads.size()):
		var squad: int = _scout_squads[i]
		var target_player: int = candidates[i % candidates.size()]
		_send_order(squad, _estimated_neighbor_cell(target_player))

	# _build_terrain() points the camera at the map centre, which is
	# usually nowhere near where two adjacent player ids actually spawn
	# (server.gd spreads players by id, not around the middle of the map).
	# Left alone, the screenshot this scenario exists to produce would
	# frame an empty stretch of terrain while the only interesting thing
	# happening is off in a corner — exactly the kind of frame that passes
	# every numeric check while showing nothing, which is what
	# `just test-client` exists to catch (see CLAUDE.md's account of the
	# first frame that ever rendered no soldiers). Re-centre on the actual
	# rendezvous the first time scouts are sent, so the encounter this
	# scenario stages is the encounter the screenshot shows.
	if first_rally and not candidates.is_empty():
		var home: Vector2i = _scout_home.get(_scout_squads[0], Vector2i.ZERO)
		var target_cell := _estimated_neighbor_cell(candidates[0])
		var offset := _state.space.world_delta(home, target_cell)
		var rendezvous := _state.space.to_world(home) + offset * 0.5
		# Low player ids (as this scenario's targets always are — see the
		# header comment on _neighbor_player_candidates) spawn near the
		# torus's coordinate origin by construction (server.gd's
		# _spawn_squads_for scales both lane and x from player id starting
		# at zero), which is also a corner of the FINITE chunked mesh this
		# client actually builds (D-017 — terrain is chunked over the
		# map's real extent, not rendered as seamlessly wrapping). Framing
		# the camera tight on the rendezvous put much of the shot outside
		# the mesh entirely: black void, not terrain. Blending most of the
		# way toward the map's true centre keeps the camera comfortably
		# over rendered ground no matter which corner the encounter falls
		# near, while still biasing the shot toward the actual action
		# rather than ignoring it outright.
		var centre := _state.space.to_world(Vector2i(_state.space.width / 2, _state.space.height / 2))
		_camera_target = rendezvous.lerp(centre, 0.65)
		_camera_height = clampf(42.0, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT)
		_update_camera()


## Call the scouts back to where they started. A scout that routed during
## the encounter ignores this — SquadSim.order_move refuses PLAYER orders
## while routed (D-024) and it keeps fleeing under its own steam instead,
## which is also a legitimate way to leave this client's vision and produce
## a conceal, exactly as bot_client.gd's own recall comment notes.
func _issue_scenario_withdraw() -> void:
	for squad in _scout_squads:
		if _scout_home.has(squad):
			_send_order(squad, _scout_home[squad])


## The player id(s) most likely to be an actual opponent — see the header
## comment on _issue_scenario_rally for why both are targeted.
func _neighbor_player_candidates() -> Array:
	var out := []
	if _state.player > 1:
		out.append(_state.player - 1)
	out.append(_state.player + 1)
	return out


## Mirrors server.gd's _spawn_squads_for formula for i=0 (see the constants
## above this file for why duplicating it here is acceptable).
func _estimated_neighbor_cell(target_player: int) -> Vector2i:
	var lane := (target_player * NEIGHBOR_SPAWN_Y_STEP) % _state.space.height
	var x := (target_player * NEIGHBOR_SPAWN_X_STEP) % _state.space.width
	return Vector2i(x, lane)


func _send_order(squad: int, destination: Vector2i) -> void:
	var order := _state.encode_order(squad, destination)
	if not order.is_empty():
		_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)


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
