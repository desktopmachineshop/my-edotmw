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
## This file used to duplicate server.gd's spawn formula so the scenario
## could guess where a neighbour started, with a comment arguing the
## coupling was acceptable because it only shaped a scenario and would
## fail loudly if the formula changed. It did change — M3 moved spawns
## into map data (D-036) — and it did fail loudly, exactly as predicted:
## the scouts marched at empty ground and the verdict's casualty and fog
## counters fell to zero. Spawn points now arrive in the welcome message,
## so there is one definition of where a player starts and nothing here
## to go stale.
const SCOUT_COUNT := 4
## Scenario timings, in seconds of run time.
##
## Retuned for the 128x64 map (D-036). They used to be 1 / 9 / 14, which
## worked when players spawned close enough to meet almost at once. On a
## quadrant-symmetric map the contested middle is roughly 25 seconds of
## marching away, so withdrawing at 9s pulled the scouts back before they
## had ever seen anyone — the run produced a conceal and no reveal, and
## the verdict said so. The sequence has to be: march, make contact, break
## contact (a conceal), then return (a reveal).
const RALLY_AT_SECONDS := 1.0
const WITHDRAW_AT_SECONDS := 30.0
const RE_RALLY_AT_SECONDS := 40.0

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

## Zoom ceiling, derived from the map rather than fixed. Terrain is tiled
## in every direction so the world has no edge (D-035) — but zoom out far
## enough and you start seeing the SAME map repeated, which reads as a
## rendering bug rather than a torus. Capping the view at roughly half the
## map keeps the illusion intact.
var _camera_max_height := CAMERA_MAX_HEIGHT

## Cells this player has ever seen. Fog of war on the client side: the map
## starts black and is revealed by line of sight, and once revealed stays
## revealed (terrain does not move). Derived locally from our own squads'
## vision_range rather than replicated — the client already knows where
## its squads are and what they are, so the server would be sending
## something the client can compute (D-006's derivation principle applied
## to vision rather than to soldiers).
var _explored := {}
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

	_build_hud()

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
	_refresh_buildings()
	_update_hud()
	_update_minimap()

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
	# verdict looks (D-026 criterion 9).
	#
	# `reveal_events` is REPORTED but deliberately not gated, and that
	# distinction is worth spelling out, because relaxing a check is
	# normally the wrong move. A reveal means "a squad that was a ghost
	# came back into vision", which needs an opponent to wander back
	# inside a bounded capture run. On the 128x64 map that is luck:
	# consecutive runs of this recipe produced 3 and then 0 with nothing
	# else changed. A gate that fails good runs gets muted — the exact
	# failure the justfile records from the "0 desyncs" scan.
	#
	# It stays gated where it is reliable: `just test-load` runs four
	# mutually-converging armies and sees reveals in the tens every run,
	# so the property is genuinely covered, just not by this recipe —
	# whose job is the picture.
	var ok := (
		_state.welcomed
		and _state.desync_count == 0
		and squads_drawn > 0
		and soldiers > 0
		and (_screenshot_path == "" or (_shot_taken and distinct >= MIN_DISTINCT_COLOURS))
		and _state.casualties_applied > 0
		and _state.conceal_events > 0
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

	var meshes := []
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(cx, cy), chunk_size)
			if mesh != null:
				meshes.append(mesh)

	# The world is a torus, so it must not visibly END (D-035). Draw the
	# whole chunk set nine times — the centre copy plus its eight
	# neighbours across both seams — sharing the SAME Mesh resources, so
	# this costs draw calls rather than memory. Before this, panning far
	# enough left the meshed ground behind and stared into the void, and a
	# squad mid-seam-crossing drew outside the map entirely.
	#
	# The two lattice vectors come straight from TorusSpace.to_world, and
	# they are NOT axis-aligned. Stepping `width` in q moves world x by
	# width*SQRT_3*hex_size. Stepping `height` in r moves z by
	# height*1.5*hex_size *and* x by height/2*SQRT_3*hex_size, because x
	# depends on r/2. Offsetting by (x, 0, z) rectangles instead would look
	# correct straight ahead and tear at the diagonal seams.
	var step_q := Vector3(float(space.width) * space.hex_size * TorusSpace.SQRT_3, 0.0, 0.0)
	var step_r := Vector3(
		float(space.height) * 0.5 * space.hex_size * TorusSpace.SQRT_3,
		0.0,
		float(space.height) * 1.5 * space.hex_size)

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

	# Minimap base: one pixel per cell, painted from the same biome
	# classification the mesh used (D-037), so the small picture and the
	# big one cannot disagree about where the water is.
	_minimap_base = Image.create(space.width, space.height, false, Image.FORMAT_RGBA8)
	for y in range(space.height):
		for x in range(space.width):
			_minimap_base.set_pixel(x, y, terrain.biome_color(space, Vector2i(x, y)))

	# Half the map's width, converted to a camera height that shows about
	# that much ground. Beyond this the tiled copies become visible.
	_camera_max_height = clampf(
		float(space.width) * space.hex_size * TorusSpace.SQRT_3 * 0.25,
		CAMERA_MIN_HEIGHT + CAMERA_ZOOM_STEP, CAMERA_MAX_HEIGHT)
	_camera_height = minf(_camera_height, _camera_max_height)

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

	# The opening move first: found the hall, then send scouts out.
	_found_home_town()

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
		if not _scout_home.has(squad):
			continue
		# Pull back far enough to break vision, not all the way home.
		# Vision reaches ~7 cells (D-025), while home is most of a quadrant
		# away on the 128x64 map — a full round trip out, back and out
		# again takes longer than the entire capture run, which is why the
		# scenario used to produce a conceal and never a reveal. A quarter
		# of the way home is ~12 cells: enough to lose sight of the enemy,
		# short enough to return within the run.
		var here := _state.squad_cell(squad, _now)
		var toward_home := _state.space.delta(here, _scout_home[squad])
		_send_order(squad, _state.space.normalize(here + toward_home / 4))


## The player id(s) most likely to be an actual opponent — see the header
## comment on _issue_scenario_rally for why both are targeted.
func _neighbor_player_candidates() -> Array:
	var out := []
	if _state.player > 1:
		out.append(_state.player - 1)
	out.append(_state.player + 1)
	return out


## Where the scenario sends its scouts to find a fight: the middle of the
## map, not the neighbour's camp.
##
## Marching on a neighbour's spawn stopped working when the map grew
## (D-036). Quadrant symmetry puts every player a full quadrant from
## every other — 64 cells, about 32 seconds of walking — which is further
## than a capture run lasts, so the scouts arrived nowhere and the
## verdict's casualty and fog counters sat at zero. The centre is
## equidistant-ish for everyone and is where bot_client.gd sends its own
## squads, so both sides converge on one place instead of missing each
## other in open country.
##
## `target_player` is still taken (and still used to look up a real spawn
## when one is known) so the caller's shape does not change, and so a
## future scenario can march on a specific opponent once travel time
## stops being the binding constraint.
## Capture mode plays the real opening: found a town hall at the spawn,
## and look at it.
##
## Without this the frame proves nothing about slice 4 — the client owns
## no building and sees none, so `buildings=0` and a rendering bug would
## be invisible. It also points the camera at the player's own base
## rather than the middle of the map, which is where a player actually
## starts looking.
func _found_home_town() -> void:
	if _founded or not _state.welcomed or _state.squads.is_empty():
		return
	_founded = true

	var home := _state.spawn_cell_of(_state.player)
	if home.x < 0:
		home = _state.squad_cell(_state.squads[0], _now)

	var order := _state.encode_build(_state.squads[0], "town_centre", home)
	if not order.is_empty():
		_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
		print("client: founding a town hall at %s" % home)

	_camera_target = _state.space.to_world(home)
	_update_camera()


func _estimated_neighbor_cell(target_player: int) -> Vector2i:
	var centre := Vector2i(_state.space.width / 2, _state.space.height / 2)
	var spawn := _state.spawn_cell_of(target_player)
	if spawn.x < 0:
		return centre
	# Bias slightly toward the neighbour so the two scout groups do not
	# stack on the exact same cell, while staying in the contested middle.
	return _state.space.normalize((centre + spawn) / 2)


func _send_order(squad: int, destination: Vector2i) -> void:
	var order := _state.encode_order(squad, destination)
	if not order.is_empty():
		_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)


# --- selection, commands and HUD (D-034, D-027 criteria 3-5) ----------
#
# Right-click used to order EVERY squad this client owned, with a comment
# saying per-squad selection was M3's job rather than M1's. This is that
# job. Selection is entirely client-side — the wire carries orders for
# squads, never a "selection", because the server has no reason to know
# what a player has highlighted (D-002).

## A click within this many pixels of a squad's centre selects it. Squads
## draw as loose clusters of soldiers rather than one sprite, so a click
## almost never lands exactly on the centre.
const SELECT_CLICK_RADIUS_PX := 48.0

## Drags shorter than this are clicks, not boxes.
const DRAG_THRESHOLD_PX := 8.0

var _selected: Array = []
var _dragging := false
var _drag_start := Vector2.ZERO
var _selection_rect: ColorRect = null
var _control_groups := {}

var _hud_status: Label = null
var _hud_selection: Label = null
var _hud_resources: Label = null
var _building_nodes := {}
var _founded := false

## Minimap (D-027 criterion 5). Wrap-awareness is free here in a way it
## is nowhere else in this project: the minimap IS the whole torus, so a
## cell maps to a pixel directly and there is no seam to handle.
const MINIMAP_INTERVAL := 0.25
var _minimap_rect: TextureRect = null
var _minimap_bounds := Rect2()
var _minimap_base: Image = null
var _minimap_texture: ImageTexture = null
var _minimap_updated_at := -1.0


## client.tscn is a bare Node3D, so every node is built in code — the HUD
## included. A CanvasLayer puts it in screen space above the 3D view.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := VBoxContainer.new()
	panel.position = Vector2(12.0, 10.0)
	layer.add_child(panel)

	_hud_status = Label.new()
	_hud_resources = Label.new()
	_hud_selection = Label.new()
	var hint := Label.new()
	hint.text = "LMB select · click minimap to jump · RMB move · Ctrl+RMB attack-move · B found town hall · X stop · Ctrl+1-9 group"

	# Outlined text because the map underneath is light sand and dark
	# forest in equal measure; plain white is unreadable over half of it.
	for label in [_hud_status, _hud_resources, _hud_selection, hint]:
		label.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		label.add_theme_constant_override("outline_size", 5)
		panel.add_child(label)

	_selection_rect = ColorRect.new()
	_selection_rect.color = Color(0.4, 0.8, 1.0, 0.18)
	_selection_rect.visible = false
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_selection_rect)

	# Hit-testing uses THIS rect, not the Control's reported size.
	#
	# Reading the size back from the node was a real bug: a TextureRect
	# that reports a larger rect than intended swallows every click as a
	# minimap jump, which killed selection AND ordering at once — the
	# whole screen became minimap. Owning the bounds here means the guard
	# can never disagree with what is drawn.
	_minimap_bounds = Rect2(12.0, 96.0, 256.0, 128.0)

	_minimap_rect = TextureRect.new()
	_minimap_rect.position = _minimap_bounds.position
	_minimap_rect.size = _minimap_bounds.size
	_minimap_rect.custom_minimum_size = _minimap_bounds.size
	_minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Nearest-neighbour: one cell is one pixel, and smoothing it would
	# blur the squad dots into the terrain they sit on.
	_minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_minimap_rect)


## Draw the buildings this client knows about (D-029).
##
## Without this a player founds a town hall and watches nothing happen —
## the server knew about it, the wire carried it, `ClientState` held it,
## and every numeric check passed. That is the same shape as M1's frame
## with no soldiers in it, which is why this landed before anyone was
## asked to sit down and play.
##
## A building under construction is drawn SHORT, rising as it completes,
## so progress is visible in the world rather than only in a number.
func _refresh_buildings() -> void:
	if _state.space == null:
		return

	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		var instance: MeshInstance3D = _building_nodes.get(wire_id, null)

		if instance == null:
			var def := BuildingSim.def_by_id(StringName(info["def_id"]))
			if def == null:
				continue
			var mesh := BoxMesh.new()
			mesh.size = Vector3(2.4, 3.0, 2.4)
			var material := StandardMaterial3D.new()
			material.albedo_color = def.mesh_color
			material.roughness = 0.9
			instance = MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			_building_nodes[wire_id] = instance
			add_child(instance)

		if bool(info["destroyed"]):
			instance.visible = false
			continue
		instance.visible = true

		var progress := clampf(float(info["progress"]), 0.15, 1.0)
		instance.scale = Vector3(1.0, progress, 1.0)

		var world := _state.space.to_world(_state.space.from_index(int(info["cell"])))
		if _state.terrain_sampler.is_valid():
			world.y = _state.terrain_sampler.call(world.x, world.z)
		# Sit the box ON the ground rather than half-sunk into it.
		world.y += 1.5 * progress
		instance.position = world


func _update_hud() -> void:
	if _hud_status == null:
		return

	_hud_status.text = "player %d · %d squads known · %d ghosts · %d buildings" % [
		_state.player, _state.curves.size(), _state.ghost_squad_ids().size(),
		_state.buildings.size()]

	# The four resource readouts D-027 criterion 5 asks for. Only ours
	# exist to show: wallets are private, so the protocol never carries
	# anyone else's (D-028).
	if _state.wallet.size() >= 4:
		_hud_resources.text = "food %d · wood %d · gold %d · stone %d" % [
			_state.wallet[0], _state.wallet[1], _state.wallet[2], _state.wallet[3]]
	else:
		_hud_resources.text = "food — · wood — · gold — · stone —"

	if _selected.is_empty():
		_hud_selection.text = "nothing selected"
		return

	var strength := 0
	for squad in _selected:
		strength += _state.alive_of(squad)
	var kind: String = String(_state.composition.get(_selected[0], {}).get("def_id", "?"))
	_hud_selection.text = "%d selected · %s · %d soldiers" % [_selected.size(), kind, strength]


## Repaint the minimap a few times a second rather than every frame:
## it is a whole-image copy plus a dot per known squad, which is cheap but
## not free, and nothing on it moves fast enough at 10 Hz (D-020) to need
## more.
func _update_minimap() -> void:
	if _minimap_base == null or _minimap_rect == null:
		return
	if _minimap_updated_at >= 0.0 and _now - _minimap_updated_at < MINIMAP_INTERVAL:
		return
	_minimap_updated_at = _now

	_update_explored()

	var image: Image = _minimap_base.duplicate()

	# Unexplored ground is black. This is the client half of fog of war
	# (D-004): the server already refuses to send anything outside vision,
	# so the map a player has never walked past is genuinely unknown — it
	# should look it, rather than showing terrain nobody has scouted.
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if not _explored.has(_state.space.index(Vector2i(x, y))):
				image.set_pixel(x, y, Color(0.02, 0.02, 0.04))
	for squad in _state.curves:
		var colour := Color(0.35, 0.95, 1.0) if _state.owns(squad) else Color(1.0, 0.35, 0.28)
		# Ghosts are last-known information, so they are drawn dimmer —
		# the same distinction the 3D view makes by fading them (D-025).
		if _state.is_ghost(squad):
			colour = colour.darkened(0.45)
		_plot_minimap(image, _state.squad_cell(squad, _now), colour)

	_plot_view_bounds(image)

	if _minimap_texture == null:
		_minimap_texture = ImageTexture.create_from_image(image)
		_minimap_rect.texture = _minimap_texture
	else:
		_minimap_texture.update(image)


## Extend the explored set from what this player can currently see.
##
## Computed locally rather than replicated. The client knows where its own
## squads are and what kind they are, so it can derive its own vision the
## same way the server does — sending it would be sending something the
## receiver could work out, which is the same argument D-006 makes about
## soldier positions.
##
## Buildings see too, and a town hall sees a long way, so a base lights up
## a useful area around itself.
func _update_explored() -> void:
	if _state.space == null:
		return

	var hex_width := _state.space.hex_size * TorusSpace.SQRT_3
	if hex_width <= 0.0:
		return

	for squad in _state.squads:
		if not _state.curves.has(squad) or not _state.composition.has(squad):
			continue
		if _state.alive_of(squad) <= 0:
			continue
		var def := UnitRoster.by_id(StringName(_state.composition[squad]["def_id"]))
		if def == null:
			continue
		_reveal_around(_state.squad_cell(squad, _now), floori(def.vision_range / hex_width))

	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if int(info["owner"]) != _state.player or bool(info["destroyed"]):
			continue
		var building_def := BuildingSim.def_by_id(StringName(info["def_id"]))
		if building_def == null:
			continue
		_reveal_around(_state.space.from_index(int(info["cell"])),
			floori(building_def.vision_range / hex_width))


func _reveal_around(centre: Vector2i, radius: int) -> void:
	for offset in TorusSpace.disk_offsets(maxi(radius, 0)):
		_explored[_state.space.index(centre + offset)] = true


## Outline what the camera is currently looking at.
##
## The corners are found by casting the four screen corners onto the
## ground with the same `_cell_under` the right-click order uses, so the
## box is what the player can actually see rather than an estimate from
## camera height. A corner that misses the ground (sky above the horizon)
## simply drops that edge, leaving a partial box rather than a wrong one.
##
## This matters more on a torus than it would on a flat map: with terrain
## tiled in every direction and no edges to orient by, the minimap is the
## only thing that answers "where am I?".
func _plot_view_bounds(image: Image) -> void:
	if _camera == null or _state.space == null:
		return

	var view := get_viewport().get_visible_rect().size
	var corners := [
		_cell_under(Vector2(0.0, 0.0)),
		_cell_under(Vector2(view.x, 0.0)),
		_cell_under(Vector2(view.x, view.y)),
		_cell_under(Vector2(0.0, view.y)),
	]

	var colour := Color(1.0, 1.0, 1.0, 1.0)
	for i in range(4):
		var from: Vector2i = corners[i]
		var to: Vector2i = corners[(i + 1) % 4]
		if from.x < 0 or to.x < 0:
			continue
		_plot_minimap_segment(image, from, to, colour)


## A line between two cells, taken the SHORT way around the torus — the
## view box straddles the seam as readily as anything else here, and
## drawing it the long way would smear a line across the whole minimap.
func _plot_minimap_segment(image: Image, from: Vector2i, to: Vector2i, colour: Color) -> void:
	var span := _state.space.delta(from, to)
	var steps := maxi(absi(span.x), absi(span.y))
	if steps <= 0:
		return
	steps = mini(steps, 512)

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		image.set_pixel(
			posmod(from.x + roundi(float(span.x) * t), image.get_width()),
			posmod(from.y + roundi(float(span.y) * t), image.get_height()),
			colour)


## A 2x2 blob rather than a single pixel, so a squad is visible at one
## pixel per cell. Wrapped with posmod because a blob on the right edge
## belongs on the left one — the torus tax, cheap for once.
func _plot_minimap(image: Image, cell: Vector2i, colour: Color) -> void:
	for dy in range(2):
		for dx in range(2):
			image.set_pixel(
				posmod(cell.x + dx, image.get_width()),
				posmod(cell.y + dy, image.get_height()),
				colour)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		_update_selection_rect(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_camera_height = clampf(_camera_height - CAMERA_ZOOM_STEP, CAMERA_MIN_HEIGHT, _camera_max_height)
				_update_camera()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_camera_height = clampf(_camera_height + CAMERA_ZOOM_STEP, CAMERA_MIN_HEIGHT, _camera_max_height)
				_update_camera()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				# A click on the minimap jumps the view there instead of
				# selecting. Deliberately does NOT start a drag, so the
				# release below leaves the current selection alone — a
				# minimap click that silently deselected your army would
				# be worse than no minimap click at all.
				var jump := _minimap_cell_at(event.position)
				if jump.x >= 0:
					_jump_camera_to(jump)
					return
				_dragging = true
				_drag_start = event.position
			elif _dragging:
				_finish_selection(event.position, event.shift_pressed)
		MOUSE_BUTTON_RIGHT:
			# Right-clicking the minimap does nothing rather than ordering
			# the selection to whatever the ray happens to hit behind it.
			# Sending an army somewhere random on a misclick is the kind of
			# thing a player never forgives.
			if event.pressed and _minimap_cell_at(event.position).x < 0:
				_order_selected(event.position, event.ctrl_pressed)


## Which cell a screen position corresponds to on the minimap, or
## (-1, -1) if the position is not over it.
##
## The minimap is one pixel per cell covering the whole torus, so this is
## a straight proportional mapping with no camera involved — which is
## exactly why it can jump anywhere, including ground the player has
## never seen.
func _minimap_cell_at(screen_position: Vector2) -> Vector2i:
	if _minimap_rect == null or _state.space == null:
		return Vector2i(-1, -1)

	if _minimap_bounds.size.x <= 0.0 or not _minimap_bounds.has_point(screen_position):
		return Vector2i(-1, -1)

	var local := (screen_position - _minimap_bounds.position) / _minimap_bounds.size
	return Vector2i(
		clampi(int(local.x * float(_state.space.width)), 0, _state.space.width - 1),
		clampi(int(local.y * float(_state.space.height)), 0, _state.space.height - 1))


## Centre the view on a cell, leaving the zoom exactly as it was.
##
## Height is untouched on purpose: a minimap click moves you, it does not
## re-frame you. Having to re-zoom after every jump is the fastest way to
## make a minimap something players stop touching.
func _jump_camera_to(cell: Vector2i) -> void:
	var world := _state.space.to_world(cell)
	_camera_target.x = world.x
	_camera_target.z = world.z
	_wrap_camera_target()
	_update_camera()


func _update_selection_rect(to: Vector2) -> void:
	if _selection_rect == null:
		return
	var rect := Rect2(_drag_start, to - _drag_start).abs()
	_selection_rect.position = rect.position
	_selection_rect.size = rect.size
	_selection_rect.visible = rect.size.length() > DRAG_THRESHOLD_PX


func _finish_selection(at: Vector2, additive: bool) -> void:
	_dragging = false
	if _selection_rect != null:
		_selection_rect.visible = false
	if not additive:
		_selected.clear()

	var rect := Rect2(_drag_start, at - _drag_start).abs()
	if rect.size.length() <= DRAG_THRESHOLD_PX:
		_select_nearest(at)
	else:
		_select_within(rect)


## Where a squad appears on screen. Squads behind the camera unproject to
## a meaningless point, so they are pushed far off-screen rather than
## being allowed to match a click.
func _squad_screen_position(squad: int) -> Vector2:
	var world := _state.squad_world_position(squad, _now)
	if _camera.is_position_behind(world):
		return Vector2(-1e6, -1e6)
	return _camera.unproject_position(world)


func _select_nearest(at: Vector2) -> void:
	var best := -1
	var best_distance := SELECT_CLICK_RADIUS_PX
	for squad in _state.squads:
		if not _state.curves.has(squad):
			continue
		var distance := _squad_screen_position(squad).distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = squad
	if best >= 0 and not _selected.has(best):
		_selected.append(best)


func _select_within(rect: Rect2) -> void:
	for squad in _state.squads:
		if not _state.curves.has(squad):
			continue
		if rect.has_point(_squad_screen_position(squad)) and not _selected.has(squad):
			_selected.append(squad)


func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_X:
		_stop_selected()
		return

	# B founds a town hall at the mouse cursor (D-031). The server checks
	# everything that matters — that the squad may build this, that the
	# ground takes a foundation, and that the builder is within reach —
	# so this just sends the intent and lets the authority answer.
	if event.keycode == KEY_B:
		_build_selected("town_centre")
		return

	# Control groups: Ctrl+N stores the selection, N recalls it.
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var group: int = event.keycode - KEY_0
		if event.ctrl_pressed:
			_control_groups[group] = _selected.duplicate()
			print("client: control group %d = %d squad(s)" % [group, _selected.size()])
		else:
			_selected = (_control_groups.get(group, []) as Array).duplicate()


## Screen point to torus cell. Returns (-1, -1) when the ray never meets
## the ground plane. The click becomes a CELL and is sent as an order for
## the server to interpret — the client never moves anything itself
## (D-002).
func _cell_under(screen_position: Vector2) -> Vector2i:
	var from := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return Vector2i(-1, -1)
	var distance := -from.y / direction.y
	if distance <= 0.0:
		return Vector2i(-1, -1)
	return _state.space.world_to_cell(from + direction * distance)


## Right-click orders the SELECTION, not everything owned (D-027
## criterion 3). With nothing selected it does nothing: quietly marching
## an army the player never chose is worse than ignoring the click.
func _order_selected(screen_position: Vector2, attack_move: bool) -> void:
	if not _connected or _state.space == null or _selected.is_empty():
		return

	var cell := _cell_under(screen_position)
	if cell.x < 0:
		return

	var sent := 0
	for squad in _selected:
		var order := _state.encode_attack_move(squad, cell) if attack_move else _state.encode_order(squad, cell)
		if not order.is_empty():
			_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
			sent += 1
	if sent > 0:
		print("client: %s %d squad(s) to cell %s" % [
			"attack-moved" if attack_move else "ordered", sent, cell])


## Ask the first selected squad to found a building at the cursor.
##
## Only founders may build a town hall, and only a town hall — that rule
## is data on the BuildingDef (D-031) and enforced server-side, so a
## refused order simply does nothing here rather than being second-guessed
## client-side.
func _build_selected(def_id: String) -> void:
	if not _connected or _state.space == null or _selected.is_empty():
		return

	var cell := _cell_under(get_viewport().get_mouse_position())
	if cell.x < 0:
		return

	var order := _state.encode_build(_selected[0], def_id, cell)
	if not order.is_empty():
		_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
		print("client: asked squad %d to found a %s at %s" % [_selected[0], def_id, cell])


func _stop_selected() -> void:
	var sent := 0
	for squad in _selected:
		var order := _state.encode_stop(squad)
		if not order.is_empty():
			_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
			sent += 1
	if sent > 0:
		print("client: stopped %d squad(s)" % sent)


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
	_wrap_camera_target()
	_update_camera()


## Fold the camera back into the map's own domain (D-035).
##
## Done in CONTINUOUS lattice coordinates rather than by round-tripping
## through world_to_cell: that would snap the camera to the nearest cell
## centre and turn smooth panning into a stutter. Inverting to_world's
## arithmetic and taking it modulo the map keeps the motion continuous,
## and because the terrain is tiled in every direction the player never
## sees the fold happen — they simply come back around.
func _wrap_camera_target() -> void:
	var space := _state.space
	if space == null or space.hex_size <= 0.0:
		return

	var r := _camera_target.z / (1.5 * space.hex_size)
	var q := _camera_target.x / (TorusSpace.SQRT_3 * space.hex_size) - r * 0.5

	q = fposmod(q, float(space.width))
	r = fposmod(r, float(space.height))

	_camera_target.x = TorusSpace.SQRT_3 * space.hex_size * (q + r * 0.5)
	_camera_target.z = 1.5 * space.hex_size * r


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
