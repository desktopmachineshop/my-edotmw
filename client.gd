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

## Slack around the viewport, in pixels, when deciding whether a squad is
## worth deriving (D-045). Culling tests a squad's CENTRE, but a squad has
## real extent, so a formation whose centre is just off screen can still
## have soldiers on it. Generous on purpose: the cost of being wrong in
## this direction is a little wasted derivation, and the cost of being
## wrong in the other is soldiers popping in at the screen edge.
const CULL_MARGIN_PIXELS := 192.0

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

## Render LOD tiers (D-045): distance from the camera in world units, and
## the most soldiers a squad past that distance is drawn with.
##
## Tuned against `just bench-render` rather than chosen: at D-018's full
## scale the client was at 17.8 fps with every visible soldier derived,
## and per-soldier derivation was ~96% of the frame.
##
## Nothing here touches `alive`. A thinned squad keeps its true frontage
## because `slot_offset` is still asked for the real size, so this reads
## as a distant formation being sparse rather than as a smaller unit —
## which matters, because unit size is tactical information a player is
## entitled to read off the screen correctly.
const LOD_TIERS := [
	{"distance": 55.0, "soldiers": 1 << 30},
	{"distance": 110.0, "soldiers": 12},
	{"distance": INF, "soldiers": 5},
]


## How many soldiers to draw for a squad at `world` (D-045).
func _detail_for(world: Vector3) -> int:
	if _camera == null:
		return 1 << 30
	var distance := _camera.global_position.distance_to(world)
	for tier in LOD_TIERS:
		if distance < float(tier["distance"]):
			return int(tier["soldiers"])
	return int(LOD_TIERS[LOD_TIERS.size() - 1]["soldiers"])


## Squads derived and drawn this frame, against the number known. Shown in
## the HUD because the gap between them is the whole point of D-045: if
## these two numbers are ever equal at scale, the cull has stopped working
## and the only symptom would be a slow client.
var _visible_squads := 0
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

## When this client first owned a squad it could actually order — see
## _drive_m2_scenario. Negative until then.
var _army_at := -1.0

## When the capture scenario may next order a unit trained. Zero means
## "as soon as the hall is finished".
var _trained_at := 0.0


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
	# Capture-only: seat this many AI so `just lobby-shot` photographs a
	# lobby with something in it rather than one empty seat.
	_lobby_ai_wanted = int(args.get("lobby-ai", 0))
	_lobby_preset_steps = int(args.get("lobby-preset-steps", 0))

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
	_build_lobby_ui()

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

	if _state.welcomed and _state.has_map() and not _terrain_built:
		_build_terrain()
		_terrain_built = true

	_refresh_squads()
	_refresh_buildings()
	_refresh_resource_nodes()
	# After both, so a ring can sit on the position they just set.
	_refresh_selection_rings()
	_update_placement_ghost()
	_update_hud()
	_update_minimap()
	_seat_capture_ai()
	_refresh_chat()
	_refresh_lobby()

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
		# The WORLD has to be there, not just the units standing on it.
		#
		# This capture once passed with no terrain at all — the client was
		# waiting for map settings that a non-lobby server never sent
		# (D-049) — and every other number in this verdict was identical
		# to a healthy run: same soldier count, same distinct colour
		# count, zero desyncs. The frame was background, HUD and a few
		# specks. Only opening the PNG found it, which is the same lesson
		# as the frame that derived every soldier at y=0.
		and _terrain_built
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
	print("client: VERDICT %s — terrain=%s connected=%s squads_drawn=%d live_squads=%d ghosts=%d soldiers=%d curves=%d desyncs=%d distinct_colours=%d casualties_applied=%d conceal_events=%d reveal_events=%d ghosts_peak=%d" % [
		"ok" if ok else "failed",
		str(_terrain_built), str(_state.welcomed), squads_drawn, live_squads, ghosts, soldiers,
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
	# From the SERVER's settings, not local defaults (D-049). The two
	# sides agreeing about where the water is used to rest on both
	# constructing a default TerrainGen — an implicit contract that could
	# not survive terrain becoming tunable.
	var terrain := _state.terrain_from_settings()
	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(space, chunk_size)

	# Stand soldiers ON the terrain rather than at y=0. Without this they
	# derive at sea level and render buried inside every hill — which is
	# how this shipped, because every numeric check (squad count, soldier
	# count, desyncs) passes perfectly while the units are underground.
	# Uses the same TerrainGen instance that built the mesh, so the ground
	# a soldier stands on is the ground that was drawn.
	#
	# Sampled from a precomputed field rather than by calling
	# `elevation_at` per soldier (D-045). This closure runs once per
	# soldier per frame — ~26,600 times a frame at D-018's full scale —
	# and `elevation_at` evaluates 3D simplex noise every call, which the
	# render benchmark measured as the dominant term in a frame that was
	# 97% CPU. The field holds identical values by construction, so this
	# is memoisation and not a change to where anyone stands.
	var elevation := terrain.elevation_field(space)
	_state.terrain_sampler = func(x: float, z: float) -> float:
		var cell := space.world_to_cell(Vector3(x, 0.0, z))
		return elevation[space.index(cell)] * terrain.height_scale

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
	# Now the map's real dimensions are known, give the minimap its shape.
	_layout_minimap(space)

	# Passability from the SAME TerrainGen that built the mesh, which is
	# the same one the server built its own from (both from the settings
	# on the wire, D-049). So the build preview agrees with the server
	# about where the water is by construction rather than by luck.
	_passable = terrain.passability(space)

	_minimap_base = Image.create(space.width, space.height, false, Image.FORMAT_RGBA8)
	for y in range(space.height):
		for x in range(space.width):
			_minimap_base.set_pixel(x, y, terrain.biome_color(space, Vector2i(x, y)))

	# Derived from the SHALLOWER of the two lattice periods, not from
	# width — and this is the fix for "half the screen will not render
	# units as visible".
	#
	# Terrain is drawn nine times (D-035) but every squad, building and
	# resource node is drawn ONCE. So the moment the view spans a second
	# terrain copy, that copy is bare ground: real terrain, no units. It
	# reads exactly like a rendering failure.
	#
	# The old cap took a quarter of the map's WIDTH. A 128x64 map sounds
	# like 2:1 and in WORLD units is 221 x 96 — 2.3:1 — because a hex row
	# is 1.5 deep and a column SQRT_3 ~ 1.73 wide. So the binding
	# dimension is depth and the cap was computed from the other one.
	#
	# Measured, on 128x64 at 1280x720: forward ground reach is about 1.9x
	# camera height, and the camera also sits 0.6h behind its target, so
	# the on-screen z span is roughly 2.6h. The old cap of 55 showed 106
	# units of a 96-unit period — comfortably more than one copy.
	#
	# 0.33 keeps 2.6h inside the period with margin. Raising it back is
	# not a free win: it needs entities drawn at every visible copy, which
	# is up to nine times the per-entity work D-045 exists to cut.
	_camera_max_height = RenderCull.max_camera_height(
		space, CAMERA_MIN_HEIGHT + CAMERA_ZOOM_STEP, CAMERA_MAX_HEIGHT)
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

	_visible_squads = 0
	var offsets := _state.space.lattice_offsets()
	var viewport_size := get_viewport().get_visible_rect().size

	for squad_id in _state.curves:
		# Nothing to draw until the server has said what this squad is.
		# Rendering a guessed strength would put every soldier in the
		# wrong place — see NetProtocol.encode_squad_info.
		if not _state.composition.has(squad_id):
			continue

		var unit := _squad_node(squad_id, String(_state.composition[squad_id]["def_id"]))
		_set_ghost_look(unit, false)

		# Cull BEFORE deriving, not after (D-045). Deriving a squad the
		# camera cannot see costs the same as deriving one it can, and at
		# D-018's full scale almost none of them are on screen: the
		# benchmark measured 1,000 squads at 66 ms a frame, 96% of it
		# derivation, while Godot's own culling had already discarded most
		# of those squads before they reached the GPU. The engine was
		# throwing away work we had just paid for.
		# One curve sample to place the squad, against ~40 to derive its
		# soldiers — so the cheap question is asked first.
		var centre := _state.squad_world_position(squad_id, _now)
		# Every lattice copy, not just the nearest to the look-at point.
		# The torus is shallower in z than it is wide, so more than one
		# copy is routinely on screen and "nearest" picks the wrong one —
		# which showed up in play as half the screen rendering no units.
		var offset = RenderCull.visible_offset(
			_camera, offsets, centre, CULL_MARGIN_PIXELS, viewport_size)
		if offset == null:
			unit.visible = false
			continue
		unit.visible = true
		unit.position = offset
		_visible_squads += 1

		# Render LOD (D-045, permitted camera-keyed by D-012): a squad far
		# from the camera is drawn thinner, never smaller. Per-soldier
		# derivation is ~96% of this client's frame at scale, so this is
		# the only lever that moves the number once culling has taken the
		# off-screen squads out.
		var transforms := _state.soldier_transforms_lod(
			squad_id, _now, _detail_for(centre + offset))
		# Cosmetic decoration is applied on the render path only and is
		# never fed back into anything (D-006 clause 2).
		var decorated := CosmeticOffset.decorate_all(transforms, _now, 1.0)
		unit.set_slot_transforms(decorated)

		# A selection circle under EVERY soldier, from the transforms we
		# just derived — so the highlight follows the formation's real
		# shape as it changes, for free. A single disc could only ever
		# approximate a line, a wedge and a loose scatter with one circle.
		_stamp_selection_discs(squad_id, decorated)

	for squad_id in _state.ghost_squad_ids():
		var ghost := _state.ghost_info(squad_id)
		if ghost.is_empty() or not _state.curves.has(squad_id):
			continue

		var unit := _squad_node(squad_id, String(ghost["def_id"]))
		_set_ghost_look(unit, true)

		# Ghosts need placing and showing exactly as live squads do, and
		# this pass did neither: it reused the shared node from
		# `_squad_node` and left `position` and `visible` at whatever the
		# LIVE pass had last set. A squad culled while visible therefore
		# stayed invisible after it became a ghost, permanently, and a
		# ghost across the seam drew at its canonical position — a whole
		# map away from where the player last saw it.
		var ghost_centre := _state.squad_world_position(squad_id, _now)
		var ghost_offset = RenderCull.visible_offset(
			_camera, offsets, ghost_centre, CULL_MARGIN_PIXELS, viewport_size)
		if ghost_offset == null:
			unit.visible = false
			continue
		unit.visible = true
		unit.position = ghost_offset

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
		unit.rebuild(def if def != null else _unit_def, _owner_colour_of(squad_id))
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
	if not _connected or not _state.welcomed:
		return

	# The opening move first: found the hall, then send scouts out.
	_found_home_town()

	# Training needs a BUILDING, not a squad, so it runs before the "no
	# squads" guard below — the identical fix bot_client.gd needed in M4,
	# for the identical reason, in the other file that scripts a player.
	#
	# Founding a town hall CONSUMES the founding party the instant the
	# order is given (D-031), so a client that makes the correct opening
	# move owns nothing at all a moment later. This function used to
	# return early on `squads.is_empty()`, which meant the scenario went
	# quiet forever the moment it did the one thing it was written to do,
	# and `test-client` reported `soldiers=0` on a frame with a perfectly
	# good town hall in it.
	#
	# It was masked until M5 because the client kept dead squads in its
	# owned list, so the guard stayed false while every order it protected
	# was refused. Making ownership honest (D-045) exposed it — the same
	# sequence, and the same pair of mutually-cancelling defects, as the
	# bots.
	_train_from_home_town()

	if _state.squads.is_empty():
		return

	# Phases are timed from when this client first HAS an army, not from
	# the start of the run.
	#
	# They used to be absolute, which was right when a player started with
	# twelve squads. D-031 changed the opening: the founding party is spent
	# on the town hall, the hall takes 40 s to build, and only then can
	# anything be trained — so by the time this client owned a soldier,
	# every absolute deadline had already passed and all three phases fired
	# in the same frame. The scouts never marched, so nothing was ever
	# concealed, and the verdict said so.
	if _army_at < 0.0:
		_army_at = _now

	if not _rallied and _now >= _army_at + RALLY_AT_SECONDS:
		_issue_scenario_rally()
		_rallied = true

	if _rallied and not _withdrawn and _now >= _army_at + WITHDRAW_AT_SECONDS:
		_issue_scenario_withdraw()
		_withdrawn = true

	if _withdrawn and not _re_rallied and _now >= _army_at + RE_RALLY_AT_SECONDS:
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
		# Biased only slightly toward centre now, not 65% of the way.
		#
		# The heavy bias dates from before terrain tiled across the seams
		# (M3 slice 3): the shot could fall off the mesh into black void,
		# so it was pulled hard toward the middle. The cost of that was a
		# capture looking at ground the player has never explored — no
		# base, no army, no resource nodes, which is most of what the
		# frame exists to show. It was hiding a fog leak in the node
		# rendering for exactly that reason: the leak was only visible
		# BECAUSE nodes were drawn where they should not have been.
		var centre := _state.space.to_world(Vector2i(_state.space.width / 2, _state.space.height / 2))
		_camera_target = rendezvous.lerp(centre, 0.2)
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


## Train a squad at the town hall once it is finished (capture mode only).
##
## Without this the capture run has nothing to draw: the founding party is
## spent on the hall (D-031), and a frame whose whole point is "look at
## the soldiers" would contain none. It also means `test-client` exercises
## the production path in a rendered client rather than leaving it to the
## bots — the frame now shows a town hall AND the troops it made.
func _train_from_home_town() -> void:
	if _trained_at < 0.0 or _now < _trained_at:
		return
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if int(info["owner"]) != _state.player or bool(info["destroyed"]):
			continue
		if float(info["progress"]) < 1.0:
			continue
		_peer.send(0, NetProtocol.encode_order_produce(int(wire_id), "gatherers"),
			ENetPacketPeer.FLAG_RELIABLE)

		# SELECT it, so the capture frame actually contains the selection
		# panel — health, production, queue and action buttons (D-057).
		#
		# Without this the panel renders "Nothing selected" forever and the
		# whole feature is unverified by the one check that looks at the
		# picture. Every counter passed while the panel was empty, which is
		# the failure mode this project keeps rediscovering.
		_selected_building = int(wire_id)

		# ...and its squads, so the per-soldier selection circles appear
		# in the capture frame too. A feature that renders nothing in the
		# one check that looks at the picture is a feature nobody has
		# looked at.
		_selected.clear()
		for owned in _state.squads:
			if _state.curves.has(owned) and _state.alive_of(owned) > 0:
				_selected.append(owned)

		# Space the orders out rather than firing one per frame at a
		# building that can only make one thing at a time.
		_trained_at = _now + 2.0
		return


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
## Bottom-left context panel: what is selected, its state, and what it can
## do as CLICKABLE buttons (D-057).
##
## The HUD was five lines of text including a fixed list of every key in
## the game. That cannot say what a building is producing, how hurt it is,
## or what is queued behind the current unit — and it made the keys look
## like the only way to act.
const PANEL_X := 12.0
const PANEL_Y := 408.0
const PANEL_W := 430.0
const PANEL_H := 300.0
const ACTION_BUTTON_W := 128.0
const ACTION_BUTTON_H := 34.0

var _resource_bar: Panel = null
var _resource_labels: Array[Label] = []
var _selection_panel: Panel = null
var _selection_title: Label = null
var _selection_detail: Label = null
var _health_bar_back: ColorRect = null
var _health_bar_fill: ColorRect = null
var _progress_bar_back: ColorRect = null
var _progress_bar_fill: ColorRect = null
var _progress_caption: Label = null
var _queue_swatches: Array[ColorRect] = []
var _queue_caption: Label = null
var _action_buttons: Array[Button] = []

var _selection_rect: ColorRect = null
## The drag box's four border bars: top, bottom, left, right.
var _selection_edges: Array[ColorRect] = []
const SELECTION_EDGE_PX := 2.0
const MINIMAP_WIDTH_PX := 216.0


## Give the minimap the map's own proportions, once the map is known.
##
## The bounds were fixed at 256x128, written when every shipped map was
## 2:1 in cells. Maps are square in world units now, and a square world
## drawn into a 2:1 box is stretched 3x horizontally against 1.3x
## vertically: distances read wrong and the view-bounds box comes out a
## shape unlike anything you are looking at.
##
## Aspect from the WORLD periods, not the cell counts — a hex column is
## SQRT_3 wide and a row 1.5 deep, the same distinction that let every map
## be oblong without anyone noticing.
##
## `_minimap_bounds` is also the hit-test rect for minimap clicks, and it
## is deliberately the ONE definition: reading the size back off the
## TextureRect once made the whole screen behave as minimap, which killed
## selection and ordering together.
func _layout_minimap(space: TorusSpace) -> void:
	if _minimap_rect == null or space == null:
		return
	var x_period := float(space.width) * space.hex_size * TorusSpace.SQRT_3
	var z_period := float(space.height) * 1.5 * space.hex_size
	if x_period <= 0.0 or z_period <= 0.0:
		return

	_minimap_bounds = Rect2(_minimap_bounds.position,
		Vector2(MINIMAP_WIDTH_PX, MINIMAP_WIDTH_PX * z_period / x_period))
	_minimap_rect.position = _minimap_bounds.position
	_minimap_rect.size = _minimap_bounds.size
	_minimap_rect.custom_minimum_size = _minimap_bounds.size
var _control_groups := {}

var _hud_status: Label = null
var _hud_notice: Label = null
var _notice_seen := 0
var _notice_until := 0.0
var _building_nodes := {}
var _founded := false
var _selected_building := -1

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
## A flat panel with a border, built by hand.
##
## Not a PanelContainer: that overrides its children's anchors, and this
## project has already lost an afternoon to sliders that rendered full
## because their sized children were being re-laid-out underneath them.
## Explicit positions inside a plain Panel do exactly what they say.
func _panel(rect: Rect2, colour: Color) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = Color(0.45, 0.62, 0.8, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


## An outlined label. The map underneath is pale sand and dark forest in
## equal measure, so plain white is unreadable over half of it.
func _hud_label(at: Vector2, size := 15) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A labelled bar. Two sized ColorRects — a back and a fill — for the same
## reason `_panel` is not a PanelContainer.
func _bar(at: Vector2, width: float, colour: Color) -> Array:
	var back := ColorRect.new()
	back.position = at
	back.size = Vector2(width, 12.0)
	back.color = Color(0.08, 0.1, 0.14, 0.9)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.position = at + Vector2(1.0, 1.0)
	fill.size = Vector2(width - 2.0, 10.0)
	fill.color = colour
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return [back, fill]


func _build_selection_panel(layer: CanvasLayer) -> void:
	_selection_panel = _panel(Rect2(PANEL_X, PANEL_Y, PANEL_W, PANEL_H),
		Color(0.05, 0.07, 0.12, 0.86))
	layer.add_child(_selection_panel)

	_selection_title = _hud_label(Vector2(PANEL_X + 12.0, PANEL_Y + 8.0), 18)
	layer.add_child(_selection_title)
	_selection_detail = _hud_label(Vector2(PANEL_X + 12.0, PANEL_Y + 32.0), 13)
	layer.add_child(_selection_detail)

	var health := _bar(Vector2(PANEL_X + 12.0, PANEL_Y + 56.0), PANEL_W - 24.0,
		Color(0.35, 0.85, 0.4))
	_health_bar_back = health[0]
	_health_bar_fill = health[1]
	layer.add_child(_health_bar_back)
	layer.add_child(_health_bar_fill)

	var progress := _bar(Vector2(PANEL_X + 12.0, PANEL_Y + 88.0), PANEL_W - 24.0,
		Color(0.4, 0.7, 1.0))
	_progress_bar_back = progress[0]
	_progress_bar_fill = progress[1]
	layer.add_child(_progress_bar_back)
	layer.add_child(_progress_bar_fill)
	_progress_caption = _hud_label(Vector2(PANEL_X + 12.0, PANEL_Y + 70.0), 12)
	layer.add_child(_progress_caption)

	# The production queue, as one swatch per waiting unit. A count would
	# not show that four spearmen are stacked behind a militia.
	_queue_caption = _hud_label(Vector2(PANEL_X + 12.0, PANEL_Y + 104.0), 12)
	layer.add_child(_queue_caption)
	for i in range(8):
		var swatch := ColorRect.new()
		swatch.position = Vector2(PANEL_X + 12.0 + float(i) * 20.0, PANEL_Y + 126.0)
		swatch.size = Vector2(16.0, 16.0)
		swatch.color = Color(0.55, 0.75, 1.0, 0.9)
		swatch.visible = false
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_queue_swatches.append(swatch)
		layer.add_child(swatch)

	# Action buttons, in a grid. Pooled and relabelled rather than rebuilt,
	# because the selection changes constantly and churning Controls in
	# _process is how a frame budget goes.
	for i in range(9):
		var button := Button.new()
		button.position = Vector2(
			PANEL_X + 12.0 + float(i % 3) * (ACTION_BUTTON_W + 8.0),
			PANEL_Y + 152.0 + float(i / 3) * (ACTION_BUTTON_H + 6.0))
		button.size = Vector2(ACTION_BUTTON_W, ACTION_BUTTON_H)
		button.visible = false
		# Styled rather than left at Godot's default grey, which reads as
		# an unfinished editor widget sitting on top of the game.
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = {
				"normal": Color(0.13, 0.19, 0.29, 0.95),
				"hover": Color(0.22, 0.34, 0.5, 0.98),
				"pressed": Color(0.3, 0.48, 0.68, 1.0),
				"disabled": Color(0.1, 0.12, 0.16, 0.7),
			}[state]
			style.border_color = Color(0.45, 0.62, 0.8, 0.9)
			style.set_border_width_all(1)
			style.set_corner_radius_all(3)
			style.content_margin_left = 8.0
			button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_action_pressed.bind(i))
		_action_buttons.append(button)
		layer.add_child(button)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud_layer = layer
	add_child(layer)

	# A resource STRIP across the top, with a coloured swatch per resource
	# rather than four numbers in a run-on sentence. Same shape every RTS
	# uses, and for the same reason: you read a stockpile a hundred times a
	# match and never want to parse a sentence to do it.
	#
	# Swatch colours come from `_node_colour`, the same function the
	# minimap and the world markers use, so a pink pile on the ground and
	# a pink counter in the bar are the same resource by construction.
	_resource_bar = _panel(Rect2(0.0, 0.0, 1280.0, 34.0), Color(0.05, 0.07, 0.12, 0.82))
	layer.add_child(_resource_bar)
	var kinds := [Economy.ResourceKind.FOOD, Economy.ResourceKind.WOOD,
		Economy.ResourceKind.GOLD, Economy.ResourceKind.STONE]
	var names := ["Food", "Wood", "Gold", "Stone"]
	for i in range(kinds.size()):
		var x := 16.0 + float(i) * 150.0
		var swatch := ColorRect.new()
		swatch.color = _node_colour(kinds[i])
		swatch.position = Vector2(x, 9.0)
		swatch.size = Vector2(16.0, 16.0)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(swatch)

		var value := _hud_label(Vector2(x + 24.0, 6.0))
		value.text = "%s —" % names[i]
		_resource_labels.append(value)
		layer.add_child(value)

	_hud_status = _hud_label(Vector2(700.0, 6.0))
	layer.add_child(_hud_status)

	# Notices sit under the bar, in the middle, where a refusal is
	# actually noticed. In the corner they were routinely missed.
	_hud_notice = _hud_label(Vector2(460.0, 44.0))
	_hud_notice.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	layer.add_child(_hud_notice)

	_build_selection_panel(layer)

	_selection_rect = ColorRect.new()
	_selection_rect.color = Color(0.4, 0.8, 1.0, 0.18)
	_selection_rect.visible = false
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_selection_rect)

	# A bright border, as four thin bars.
	#
	# The box was an 18%-alpha fill and nothing else, which over sand or
	# pale grass is very nearly invisible — reported as it being hard to
	# tell where you are selecting. A border reads against any terrain
	# because it is a hard edge rather than a wash of colour.
	#
	# Four ColorRects rather than a Panel with a StyleBoxFlat, for the
	# reason the HUD sliders learned: a Panel container overrides its
	# children's anchors and the result silently ignores the size you set.
	for _i in range(4):
		var bar := ColorRect.new()
		bar.color = Color(0.55, 0.9, 1.0, 0.95)
		bar.visible = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_selection_edges.append(bar)
		layer.add_child(bar)

	# Hit-testing uses THIS rect, not the Control's reported size.
	#
	# Reading the size back from the node was a real bug: a TextureRect
	# that reports a larger rect than intended swallows every click as a
	# minimap jump, which killed selection AND ordering at once — the
	# whole screen became minimap. Owning the bounds here means the guard
	# can never disagree with what is drawn.
	# Below the text panel, not through it. The selection readout is two
	# lines now (it names what the selection can DO, which is variable
	# length), and at y=96 the minimap was drawn straight over the hint
	# line — visible in the capture frame, invisible to every counter the
	# verdict checks. Left generous room rather than exactly enough, so a
	# longer "can:" line does not put it back.
	#
	# SHAPED FROM THE MAP, not fixed at 256x128. That 2:1 rect was written
	# when every shipped map was 2:1 in cells; the maps are square in world
	# units now (D-056's follow-up) and a square world drawn into a 2:1 box
	# is stretched 3x horizontally against 1.3x vertically. Distances read
	# wrong, and the view-bounds box comes out a shape that is nothing like
	# what you are looking at.
	#
	# Shaped in _layout_minimap once the map is known — the HUD is built
	# in _ready, long before any welcome packet says how big the world is.
	_minimap_bounds = Rect2(12.0, 168.0, MINIMAP_WIDTH_PX, MINIMAP_WIDTH_PX)

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
## Key -> what it does. ONE table, read by both the input handler and the
## HUD, so the keys a player is told about are by construction the keys
## that work. They were previously a `match` statement and a hand-written
## hint string listing the same letters twice.
const BUILD_KEYS := {
	"B": &"town_centre", "N": &"barracks", "H": &"storehouse", "Y": &"tower",
}
const TRAIN_KEYS := {
	"T": &"gatherers", "M": &"militia", "P": &"spearmen",
	"R": &"archers", "C": &"cavalry",
}


func _build_key_for(building_id: StringName) -> String:
	for key in BUILD_KEYS:
		if BUILD_KEYS[key] == building_id:
			return key
	return "?"


func _train_key_for(archetype: StringName) -> String:
	for key in TRAIN_KEYS:
		if TRAIN_KEYS[key] == archetype:
			return key
	return "?"


## wire id -> { "progress": float, "at": float } — the last progress the
## SERVER stated, and when we heard it. See _derived_progress.
var _progress_anchor := {}

## Same trick for the production countdown: wire id -> {remaining, at}.
## The server sends the queue on change, so the head's timer runs down
## locally between messages instead of being streamed (D-003).
var _queue_anchor := {}

## What the visible action buttons currently mean, parallel to
## `_action_buttons`. Read by `_on_action_pressed`.
var _actions: Array = []


## Construction progress, carried forward between messages.
##
## The server replicates a building's progress only when it COMPLETES or
## is destroyed (`BuildingSim.take_dirty` — and rightly, since streaming a
## float every tick for forty seconds is exactly the per-tick snapshot
## D-003 exists to avoid). The consequence on screen was a town hall that
## sat at 0% and then snapped to finished, with nothing in between: no
## sense of progress at all, which is what made building feel dead.
##
## So derive it, the same way a squad's position is derived from a curve
## rather than streamed (D-003). The client knows the last stated progress,
## when it heard it, and `build_time` from the BuildingDef it already
## loads — which is everything needed to draw the forty seconds in between.
##
## Deliberately capped just under 1.0 until the server actually says
## complete. A client that guessed "finished" a moment early would show a
## finished building that cannot yet produce, and "it looks done but the
## button does nothing" is a worse bug than the one being fixed.
func _derived_progress(wire_id: int, info: Dictionary) -> float:
	var stated := float(info["progress"])
	var anchor: Dictionary = _progress_anchor.get(wire_id, {})

	# Re-anchor whenever the server states something new, so this tracks
	# the authority and never drifts away from it.
	#
	# `build_time` is resolved HERE, once per anchor, and never in the
	# per-frame path. `BuildingSim.def_by_id` goes through ResourceLoader,
	# and calling it every frame for every building is the same defect
	# that cost a whole tick budget in D-043 (`UnitRoster.by_id` walking
	# the filesystem per produced squad, 858 ms in one tick) and appeared
	# again in D-055. A def lookup belongs on a state change, not in a
	# loop that runs sixty times a second.
	if anchor.is_empty() or not is_equal_approx(float(anchor["progress"]), stated):
		var def := BuildingSim.def_by_id(StringName(info["def_id"]))
		anchor = {
			"progress": stated, "at": _now,
			"build_time": def.build_time if def != null else 0.0,
		}
		_progress_anchor[wire_id] = anchor

	if stated >= 1.0:
		return 1.0

	var build_time := float(anchor["build_time"])
	if build_time <= 0.0:
		return stated

	var elapsed := _now - float(anchor["at"])
	return minf(stated + elapsed / build_time, 0.99)


var _node_meshes := {}

## The building armed for placement, or "" — a ghost of it follows the
## cursor until you click the ground or cancel.
var _placing: StringName = &""
var _placement_ghost: MeshInstance3D = null

## Terrain passability, derived from the SAME TerrainGen that built the
## mesh, so the build preview agrees with the server about where the water
## is. Advisory only: the server is the authority and re-checks (D-002).
var _passable := PackedByteArray()

## Footprints drawn under selected BUILDINGS. Pooled and reused rather
## than created per frame, because selection changes constantly and
## churning scene nodes in _process is how a frame budget goes.
var _selection_rings: Array[MeshInstance3D] = []

## squad id -> MultiMeshInstance3D of per-soldier selection circles.
var _selection_discs := {}


## A circle under every soldier of a selected squad.
##
## Takes the transforms the render pass HAS ALREADY derived, so marking a
## squad costs a MultiMesh write and no extra derivation — which matters,
## because per-soldier derivation is ~96% of this client's frame at scale
## (D-045) and doing it twice for a selected army would be the single
## most expensive way to draw a highlight.
##
## Per soldier rather than one disc for the squad because the formation
## changes shape — a line, a wedge and a loose scatter are not the same
## outline, and one circle can only approximate all three. This follows
## whatever the formation actually is, including as casualties restamp it
## (D-006 clause 3).
func _stamp_selection_discs(squad_id, transforms: Array[Transform3D]) -> void:
	var marked := _selected.has(squad_id)
	var discs: MultiMeshInstance3D = _selection_discs.get(squad_id, null)

	if not marked:
		if discs != null:
			discs.visible = false
		return

	if discs == null:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.42
		mesh.bottom_radius = 0.42
		mesh.height = 0.03
		mesh.radial_segments = 12
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Over the ground, so a circle on a slope is not half-swallowed.
		material.no_depth_test = true
		material.vertex_color_use_as_albedo = false
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		discs = MultiMeshInstance3D.new()
		discs.multimesh = multi
		discs.material_override = material
		_selection_discs[squad_id] = discs
		add_child(discs)

	var colour := _owner_colour_of(squad_id)
	(discs.material_override as StandardMaterial3D).albedo_color = Color(
		colour.r, colour.g, colour.b, 0.5)

	discs.visible = true
	discs.multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		# Flat on the ground under the soldier, upright regardless of how
		# he is facing — a selection circle should not roll with him.
		var at := transforms[i].origin
		discs.multimesh.set_instance_transform(i,
			Transform3D(Basis.IDENTITY, Vector3(at.x, at.y + 0.05, at.z)))


## A flat, glowing ring on the ground beneath every selected thing.
##
## Until now the only feedback that anything was selected was a line of
## HUD text, so a player could not tell WHICH units they had — reported
## directly. A ground ring is the genre's answer because it reads at any
## zoom and never occludes the unit it marks.
##
## Emissive rather than lit, so it is equally visible on dark forest and
## pale sand — the same reason the HUD labels carry a hard outline.
func _refresh_selection_rings() -> void:
	if _state.space == null:
		return

	# Squads are marked per SOLDIER by _stamp_selection_discs, from the
	# transforms the render pass already derived — a highlight that
	# follows the formation's real shape rather than one circle
	# approximating a line, a wedge and a loose scatter alike. Only
	# buildings are marked with a single footprint here.
	var wanted := []
	# The selected building's rally point, so "where will my troops come
	# out" is answered on the map rather than only by watching them.
	if _selected_building >= 0 and _state.buildings.has(_selected_building) \
			and _state.space != null:
		var selected: Dictionary = _state.buildings[_selected_building]
		if int(selected["owner"]) == _state.player and not bool(selected["destroyed"]):
			var rally := _state.space.to_world(
				_state.space.from_index(int(selected.get("rally", 0))))
			if _state.terrain_sampler.is_valid():
				rally.y = _state.terrain_sampler.call(rally.x, rally.z)
			wanted.append({
				"at": rally + _lattice_offset_for(rally), "radius": 1.1,
				"colour": _state.colour_of(_state.player),
			})

	if _selected_building >= 0 and _state.buildings.has(_selected_building):
		var instance: MeshInstance3D = _building_nodes.get(_selected_building, null)
		if instance != null and instance.visible:
			var info: Dictionary = _state.buildings[_selected_building]
			# On the GROUND under the building, not at its centre — a
			# building's node sits half its height up so the box rests on
			# the terrain, and a footprint placed there is inside the mesh
			# and invisible.
			var ground := instance.position
			if _state.terrain_sampler.is_valid():
				ground.y = _state.terrain_sampler.call(ground.x, ground.z)
			wanted.append({
				"at": ground, "radius": 2.2,
				"colour": _state.colour_of(int(info["owner"])),
			})

	while _selection_rings.size() < wanted.size():
		# A flat disc sitting on the ground, not a torus standing on it.
		# `height` is near-zero so this is a footprint rather than a hoop.
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		mesh.height = 0.04
		mesh.radial_segments = 24
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Drawn over the ground, so a footprint on a slope is not
		# half-swallowed by the terrain it is marking.
		material.no_depth_test = true
		var ring := MeshInstance3D.new()
		ring.mesh = mesh
		ring.material_override = material
		_selection_rings.append(ring)
		add_child(ring)

	for i in range(_selection_rings.size()):
		var ring := _selection_rings[i]
		if i >= wanted.size():
			ring.visible = false
			continue
		var entry: Dictionary = wanted[i]
		var at: Vector3 = entry["at"]
		var radius: float = entry["radius"]
		ring.visible = true
		ring.position = Vector3(at.x, at.y + 0.06, at.z)
		ring.scale = Vector3(radius, 1.0, radius)
		# The OWNER's colour at half transparency (D-052), so a selected
		# ally and a selected enemy are told apart by the same palette
		# their troops wear, and the ground still reads through it.
		var colour: Color = entry["colour"]
		var material := ring.material_override as StandardMaterial3D
		material.albedo_color = Color(colour.r, colour.g, colour.b, 0.5)


## Where to draw a STATIC thing that stands on the tiled world.
##
## Prefers the copy that is genuinely on screen, and falls back to the one
## nearest the camera when none is — a building off screen still needs a
## sensible position, and Godot culls it from there for free.
##
## Buildings and resource nodes were both drawn at canonical coordinates
## only, so anything past the seam appeared a whole map away: the terrain
## tiles nine times (D-035) and the things standing on it did not.
func _lattice_offset_for(world: Vector3) -> Vector3:
	var offsets := _state.space.lattice_offsets()
	var visible = RenderCull.visible_offset(_camera, offsets, world,
		CULL_MARGIN_PIXELS, get_viewport().get_visible_rect().size)
	if visible != null:
		return visible
	return RenderCull.nearest_offset(offsets, world, _camera_target)


## Draw resource nodes IN THE WORLD, not only on the minimap.
##
## They were minimap pixels and nothing else, so on the actual map there
## was no way to tell a forest cell from any other grass — a player was
## asked to send gatherers somewhere they could not see. Reported from a
## real game as "it's impossible to see the resource nodes", which it was.
##
## Colour comes from the same `_node_colour` the minimap uses, so the two
## views cannot disagree about what a node is. Drawn as a squat marker
## rather than anything clever: the mesh pipeline is still at its
## primitive tier (D-011) and jumping ahead of that is explicitly out of
## bounds.
##
## Gated on `_explored`, exactly as the minimap is.
##
## The first version was not, and the capture frame showed every node on
## the map including ground this player had never walked — a fog leak, and
## a worse one than it looks: the minimap deliberately hides those, so the
## two views disagreed about what the player was allowed to know. "Fog
## governs what you know about the map, and that includes what is on it"
## is the minimap's own comment, and it applies identically here.
##
## Once explored, a node stays drawn. That matches the minimap and matches
## buildings (D-030's persistent-explored): you remember where the forest
## was after you walk away from it.
func _refresh_resource_nodes() -> void:
	if _state.space == null:
		return

	for cell in _state.nodes:
		if not _explored.has(cell):
			continue
		var marker: MeshInstance3D = _node_meshes.get(cell, null)
		if marker == null:
			# Big enough to see across a map and to aim at. These were
			# noticeably smaller, which made them both easy to miss when
			# scanning for somewhere to send workers and fiddly to click.
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.7
			mesh.bottom_radius = 1.05
			mesh.height = 1.5
			var material := StandardMaterial3D.new()
			material.albedo_color = _node_colour(int(_state.nodes[cell]))
			material.roughness = 0.75
			# Slight glow so a node reads against terrain of a similar
			# hue — food pink over sand was the worst case.
			material.emission_enabled = true
			material.emission = material.albedo_color * 0.35
			marker = MeshInstance3D.new()
			marker.mesh = mesh
			marker.material_override = material
			_node_meshes[cell] = marker
			add_child(marker)

		var world := _state.space.to_world(_state.space.from_index(int(cell)))
		if _state.terrain_sampler.is_valid():
			world.y = _state.terrain_sampler.call(world.x, world.z)
		world.y += 0.75
		marker.position = world + _lattice_offset_for(world)


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
			# Owner colour, like units (D-052) — a town hall you cannot
			# attribute at a glance is worse than a squad you cannot,
			# because it tells you whose ground you are standing on.
			material.albedo_color = _state.colour_of(int(info["owner"])).lerp(
				def.mesh_color, 0.25)
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

		var progress := clampf(_derived_progress(wire_id, info), 0.15, 1.0)
		instance.scale = Vector3(1.0, progress, 1.0)

		var world := _state.space.to_world(_state.space.from_index(int(info["cell"])))
		if _state.terrain_sampler.is_valid():
			world.y = _state.terrain_sampler.call(world.x, world.z)
		# Sit the box ON the ground rather than half-sunk into it.
		world.y += 1.5 * progress
		# Drawn at the lattice copy the camera can actually see (D-035).
		# Buildings were placed at their canonical position only, so one
		# across the seam appeared a whole map from where it stands —
		# terrain tiles nine times and the things standing on it did not.
		instance.position = world + _lattice_offset_for(world)


func _update_hud() -> void:
	if _hud_status == null:
		return

	_hud_status.text = "%d squads · %d ghosts · %d buildings" % [
		_state.curves.size(), _state.ghost_squad_ids().size(), _state.buildings.size()]

	# Only OUR four. Wallets are private, so the protocol never carries
	# anyone else's (D-028).
	for i in range(_resource_labels.size()):
		var names := ["Food", "Wood", "Gold", "Stone"]
		if _state.wallet.size() > i:
			_resource_labels[i].text = "%s %d" % [names[i], _state.wallet[i]]
		else:
			_resource_labels[i].text = "%s —" % names[i]

	# Show the server's explanation for a few seconds after it arrives.
	# Timed off the COUNTER rather than the string, so two identical
	# refusals in a row still re-show the message.
	if _state.notices_received != _notice_seen:
		_notice_seen = _state.notices_received
		_notice_until = _now + 5.0
	_hud_notice.text = _state.last_notice if _now < _notice_until else ""

	_update_selection_panel()


## Fill the context panel from whatever is selected.
##
## The building branch is the one this was built for: a player selecting a
## barracks wants to know how hurt it is, what it is training, what is
## queued behind that, and what else they can order — and none of that
## could be expressed in the line of text this replaces.
func _update_selection_panel() -> void:
	var actions := []
	_health_bar_back.visible = false
	_health_bar_fill.visible = false
	_progress_bar_back.visible = false
	_progress_bar_fill.visible = false
	_progress_caption.text = ""
	_queue_caption.text = ""
	for swatch in _queue_swatches:
		swatch.visible = false

	if _selected_building >= 0 and _state.buildings.has(_selected_building):
		var info: Dictionary = _state.buildings[_selected_building]
		var def := BuildingSim.def_by_id(StringName(info["def_id"]))
		var progress := _derived_progress(_selected_building, info)
		_selection_title.text = def.display_name if def != null else String(info["def_id"])

		var health := clampf(float(info.get("health_fraction", 1.0)), 0.0, 1.0)
		_selection_detail.text = "Health %d%%%s" % [
			int(health * 100.0),
			"" if int(info["owner"]) == _state.player else "   (not yours)"]
		_set_bar(_health_bar_back, _health_bar_fill, health,
			Color(0.35, 0.85, 0.4) if health > 0.35 else Color(0.9, 0.4, 0.35))

		if progress < 1.0:
			_progress_caption.text = "Under construction"
			_set_bar(_progress_bar_back, _progress_bar_fill, progress,
				Color(0.95, 0.75, 0.3))
		else:
			actions = _building_actions(info, def)
			_show_production(info)
		_set_actions(actions)
		return

	if _selected.is_empty():
		_selection_title.text = "Nothing selected"
		_selection_detail.text = "Click a squad or a building. Drag to box-select."
		_set_actions([])
		return

	var strength := 0
	for squad in _selected:
		strength += _state.alive_of(squad)
	var def_id := StringName(String(_state.composition.get(_selected[0], {}).get("def_id", "")))
	var unit := UnitRoster.by_id(def_id)
	_selection_title.text = "%s  x%d" % [
		unit.display_name if unit != null else String(def_id), _selected.size()]
	_selection_detail.text = "%d soldiers" % strength

	# Strength as a bar too: "84 soldiers" means nothing without knowing
	# what full strength was.
	if unit != null and unit.squad_size > 0:
		var full := unit.squad_size * _selected.size()
		var fraction := clampf(float(strength) / float(full), 0.0, 1.0)
		_set_bar(_health_bar_back, _health_bar_fill, fraction,
			Color(0.35, 0.85, 0.4) if fraction > 0.35 else Color(0.9, 0.4, 0.35))

	_set_actions(_squad_actions(def_id))


func _set_bar(back: ColorRect, fill: ColorRect, fraction: float, colour: Color) -> void:
	back.visible = true
	fill.visible = true
	fill.color = colour
	fill.size = Vector2((back.size.x - 2.0) * clampf(fraction, 0.0, 1.0), fill.size.y)


## What the building is making, and what is waiting behind it.
##
## The head's remaining time counts down LOCALLY between messages, the
## same derivation as construction progress — the server sends the queue
## on change, not a float every tick (D-003).
func _show_production(info: Dictionary) -> void:
	var queue: Array = info.get("queue", [])
	if queue.is_empty():
		_queue_caption.text = "Idle"
		return

	var head := StringName(String(queue[0]))
	var unit := UnitRoster.by_id(head)
	var build_time := unit.build_time if unit != null else 0.0
	var remaining := float(info.get("head_remaining", 0.0))
	# Anchored the same way construction is, so it ticks down smoothly.
	var anchor: Dictionary = _queue_anchor.get(_selected_building, {})
	if anchor.is_empty() or not is_equal_approx(float(anchor["remaining"]), remaining):
		anchor = {"remaining": remaining, "at": _now}
		_queue_anchor[_selected_building] = anchor
	var left := maxf(float(anchor["remaining"]) - (_now - float(anchor["at"])), 0.0)
	var fraction := 1.0 - (left / build_time) if build_time > 0.0 else 0.0

	_progress_caption.text = "Training %s — %.0fs" % [
		unit.display_name if unit != null else String(head), left]
	_set_bar(_progress_bar_back, _progress_bar_fill, fraction, Color(0.4, 0.7, 1.0))

	_queue_caption.text = "Queue (%d)" % queue.size()
	for i in range(_queue_swatches.size()):
		_queue_swatches[i].visible = i < queue.size()


## Actions a BUILDING offers: its `produces` list resolved against this
## player's civ (D-047), so it names your troops and structurally cannot
## name another civ's.
func _building_actions(info: Dictionary, def: BuildingDef) -> Array:
	if def == null or int(info["owner"]) != _state.player:
		return []
	var out := []
	var civ := _state.civ_of(_state.player)
	for archetype in def.produces:
		var unit := UnitRoster.for_civ_archetype(civ, archetype)
		if unit == null:
			continue
		out.append({
			"label": "%s\n%s" % [unit.display_name, _cost_text(
				unit.cost_food, unit.cost_wood, unit.cost_gold, unit.cost_stone)],
			"kind": "train", "id": archetype,
		})
	return out


## Costs with the ZEROES left out. "50 food 0 wood 0 gold 0 stone" is four
## times as much text as the one number that matters, and the noise is
## what stops a price being readable at a glance.
func _cost_text(food: int, wood: int, gold: int, stone: int) -> String:
	var parts := []
	if food > 0:
		parts.append("%d food" % food)
	if wood > 0:
		parts.append("%d wood" % wood)
	if gold > 0:
		parts.append("%d gold" % gold)
	if stone > 0:
		parts.append("%d stone" % stone)
	return "free" if parts.is_empty() else " · ".join(parts)


## Actions SQUADS offer, from their UnitDef and BuildingDef.built_by —
## founders may raise a town hall and nothing else (D-031), gatherers
## gather, line infantry do neither.
func _squad_actions(def_id: StringName) -> Array:
	var out := []
	var def := UnitRoster.by_id(def_id)

	# Formation, for any unit (D-058). First, because it is the thing a
	# player changes most often once they know it exists.
	var current := String(_state.composition.get(_selected[0], {}).get("shape", ""))
	for shape in Formation.PLAYER_SHAPES:
		out.append({
			# The current one is marked rather than hidden: a row of three
			# where one is ticked says "these are your options and this is
			# where you are", which two buttons cannot.
			"label": ("* " if shape == current else "") + String(shape).capitalize(),
			"kind": "formation", "id": StringName(shape),
		})

	out.append({"label": "Stop", "kind": "stop", "id": &""})
	if def != null and def.carry_capacity > 0:
		out.append({"label": "Gather\nor right-click a node", "kind": "gather", "id": &""})
	for building in BuildingSim.all_defs():
		if BuildingSim.can_build(building, def_id):
			out.append({
				"label": "Build %s\n%s" % [building.display_name, _cost_text(
					building.cost_food, building.cost_wood,
					building.cost_gold, building.cost_stone)],
				"kind": "build", "id": building.id,
			})
	return out


## Relabel the pooled buttons. Never creates or frees Controls — selection
## changes constantly and churning nodes in _process is how a frame budget
## goes.
func _set_actions(actions: Array) -> void:
	_actions = actions
	for i in range(_action_buttons.size()):
		var button := _action_buttons[i]
		if i >= actions.size():
			button.visible = false
			continue
		button.visible = true
		button.text = String(actions[i]["label"])


func _on_action_pressed(index: int) -> void:
	if index < 0 or index >= _actions.size():
		return
	var action: Dictionary = _actions[index]
	match String(action["kind"]):
		"train":
			_train_selected(StringName(action["id"]))
		"build":
			_build_selected(String(action["id"]))
		"gather":
			_gather_selected()
		"stop":
			_stop_selected()
		"formation":
			_set_formation(StringName(action["id"]))


## Put every selected squad into a formation (D-058).
##
## Sent per squad rather than as one order for the selection, because the
## server validates ownership per squad — a selection is a client-side
## idea and the authority does not have one.
func _set_formation(shape: StringName) -> void:
	if not _connected or _selected.is_empty():
		return
	for squad in _selected:
		_peer.send(0, NetProtocol.encode_order_formation(int(squad), String(shape)),
			ENetPacketPeer.FLAG_RELIABLE)
	print("client: %d squad(s) to %s formation" % [_selected.size(), shape])


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

	# Resource nodes, but only where this player has actually been. Fog
	# governs what you know about the map, and that includes what is on it.
	for cell in _state.nodes:
		if not _explored.has(cell):
			continue
		var coord := _state.space.from_index(int(cell))
		image.set_pixel(coord.x, coord.y, _node_colour(int(_state.nodes[cell])))

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

	# Allied squads reveal ground too (D-050). Without this the server
	# would gate on the team's shared sight while the client painted fog
	# from its own squads alone — allies' units standing in black,
	# perfectly visible and apparently in the dark.
	for squad in _state.friendly_squads():
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

	# Corners taken from a BOUNDED band of the screen, not its true top.
	#
	# The old version raycast the four literal screen corners to the
	# ground. The top two point at the horizon on a tilted camera, so they
	# either land absurdly far away — wrapping the torus and scrambling the
	# box across the minimap — or miss the ground plane entirely and return
	# (-1,-1), at which point the edge was silently dropped and the box was
	# left open. Reported from a real game as the view box being a weird
	# shape and clipping; both halves of that were this.
	#
	# Sampling at 35% down the screen instead of 0% keeps every ray hitting
	# ground at a sane distance. The box then slightly understates what you
	# can see, which is the honest direction to be wrong in: it never
	# claims you can see somewhere you cannot.
	var view := get_viewport().get_visible_rect().size
	var top := view.y * 0.35
	var corners := [
		_cell_under(Vector2(0.0, top)),
		_cell_under(Vector2(view.x, top)),
		_cell_under(Vector2(view.x, view.y)),
		_cell_under(Vector2(0.0, view.y)),
	]

	# All four or none. A partial box is what "clipping" looked like, and
	# an outline missing one side reads as a rendering fault rather than as
	# the camera pointing somewhere unusual.
	for corner in corners:
		if corner.x < 0:
			return

	var colour := Color(1.0, 1.0, 1.0, 1.0)
	for i in range(4):
		_plot_minimap_segment(image, corners[i], corners[(i + 1) % 4], colour)


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


## Minimap colour per resource, picked to read against the terrain
## underneath rather than to match it: food and wood especially would
## vanish into grassland and forest if they used the obvious colours.
func _node_colour(kind: int) -> Color:
	match kind:
		Economy.ResourceKind.FOOD:
			return Color(1.0, 0.45, 0.55)
		Economy.ResourceKind.WOOD:
			return Color(0.85, 0.5, 0.15)
		Economy.ResourceKind.GOLD:
			return Color(1.0, 0.9, 0.2)
		_:
			return Color(0.8, 0.85, 0.95)  # stone


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
	# The lobby eats input first and exclusively. While it is up there is
	# no world to click on, and letting a stray right-click fall through
	# to "order the selection somewhere" would be ordering an army that
	# does not exist yet.
	if _handle_lobby_input(event):
		return
	if _state.in_lobby():
		return

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
				# A click while a building is armed PLACES it, and does not
				# also start a selection drag.
				if _place_armed_building(event.position):
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
			# Right-click cancels a pending placement rather than ordering
			# the army somewhere — the same escape hatch every RTS has.
			if event.pressed and _placing != &"":
				_cancel_placement()
				return
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
	var showing := rect.size.length() > DRAG_THRESHOLD_PX
	_selection_rect.visible = showing

	if _selection_edges.size() == 4:
		var e := SELECTION_EDGE_PX
		var placements := [
			Rect2(rect.position, Vector2(rect.size.x, e)),                          # top
			Rect2(rect.position + Vector2(0.0, rect.size.y - e),
				Vector2(rect.size.x, e)),                                           # bottom
			Rect2(rect.position, Vector2(e, rect.size.y)),                          # left
			Rect2(rect.position + Vector2(rect.size.x - e, 0.0),
				Vector2(e, rect.size.y)),                                           # right
		]
		for i in range(4):
			_selection_edges[i].position = placements[i].position
			_selection_edges[i].size = placements[i].size
			_selection_edges[i].visible = showing


func _finish_selection(at: Vector2, additive: bool) -> void:
	_dragging = false
	if _selection_rect != null:
		_selection_rect.visible = false
	for bar in _selection_edges:
		bar.visible = false
	if not additive:
		_selected.clear()

	var rect := Rect2(_drag_start, at - _drag_start).abs()
	if rect.size.length() <= DRAG_THRESHOLD_PX:
		_select_nearest(at)
	else:
		_select_within(rect)


## A squad's occupied ground: where its BODY is, and how wide.
##
## Not the same as its curve position. A line formation puts rank r at
## -r * spacing, so the curve point sits at the front rank and the troops
## extend behind it — which is why the selection marker looked offset from
## the squad it marked.
##
## Returns world centre and world radius, both including the lattice
## offset the squad is actually drawn at (D-035).
func _squad_footprint(squad: int) -> Dictionary:
	var centre := _state.squad_world_position(squad, _now)
	var node: PrimitiveUnit = _squad_nodes.get(squad, null)
	if node != null:
		centre += node.position

	var info: Dictionary = _state.composition.get(squad, {})
	var alive := _state.alive_of(squad)
	var shape := String(info.get("shape", "line"))
	var spacing := float(info.get("spacing", 1.0))
	var print := Formation.footprint(shape, alive, spacing)

	# Rotated by the squad's heading exactly as Formation.soldier_transform
	# does it — local +y is forward, which is +z after rotating about UP —
	# so the marker sits on the troops rather than near them.
	var local: Vector2 = print["centre"]
	if _state.curves.has(squad) and _state.space != null:
		var world_dir := _state.space.axial_offset_to_world(
			Formation.heading(_state.curves[squad], _now))
		var angle := atan2(world_dir.x, world_dir.z)
		centre += Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, angle)
	else:
		centre += Vector3(local.x, 0.0, local.y)

	return {"centre": centre, "radius": float(print["radius"])}


## Where a squad appears on screen. Squads behind the camera unproject to
## a meaningless point, so they are pushed far off-screen rather than
## being allowed to match a click.
##
## Uses the position the squad is actually DRAWN at, which on a torus is
## not its canonical position: `_refresh_squads` places the node at a
## lattice offset so a squad past the seam appears near the camera rather
## than a map away (D-035). Selection read the canonical position, so
## clicking a wrapped squad tested a point somewhere else entirely — you
## clicked exactly on a unit and nothing was selected. Reported as
## selection feeling hard to aim.
## A world point in screen pixels, pushed far off screen if it is behind
## the camera (where unproject returns a meaningless answer).
func _screen_of(world: Vector3) -> Vector2:
	if _camera.is_position_behind(world):
		return Vector2(-1e6, -1e6)
	return _camera.unproject_position(world)


## A footprint's radius in SCREEN pixels, by projecting a point on its
## edge. Perspective means a metre is worth more pixels near the camera
## than far from it, so this cannot be a constant.
func _screen_radius_of(print: Dictionary) -> float:
	var centre: Vector3 = print["centre"]
	var edge := centre + Vector3(float(print["radius"]), 0.0, 0.0)
	if _camera.is_position_behind(centre) or _camera.is_position_behind(edge):
		return 0.0
	return _camera.unproject_position(centre).distance_to(
		_camera.unproject_position(edge))


func _squad_screen_position(squad: int) -> Vector2:
	var world := _state.squad_world_position(squad, _now)
	var node: PrimitiveUnit = _squad_nodes.get(squad, null)
	if node != null:
		world += node.position
	if _camera.is_position_behind(world):
		return Vector2(-1e6, -1e6)
	return _camera.unproject_position(world)


func _select_nearest(at: Vector2) -> void:
	var best := -1
	var best_distance := SELECT_CLICK_RADIUS_PX
	for squad in _state.squads:
		if not _state.curves.has(squad):
			continue
		# Against the squad's FOOTPRINT, not a point.
		#
		# This tested the curve position with a fixed 48px radius, so on a
		# forty-man line — many metres across, and drawn well behind the
		# curve point — clicking a soldier you could plainly see selected
		# nothing. Reported as selection being based on one man rather than
		# the squad. The tolerance is now the squad's own on-screen size,
		# so a big formation is a big target and a small one is not.
		var print := _squad_footprint(squad)
		var distance := _screen_of(print["centre"]).distance_to(at)
		var allowance := maxf(_screen_radius_of(print), SELECT_CLICK_RADIUS_PX * 0.35)
		# Ranked by how far INSIDE the footprint the click landed, so two
		# overlapping squads resolve to the one you actually clicked on
		# rather than to whichever has the nearer centre.
		if distance > allowance:
			continue
		if distance - allowance < best_distance:
			best_distance = distance - allowance
			best = squad

	# Buildings are selectable the same way, and compete on the same
	# distance — clicking a town hall should select the hall, not a squad
	# standing behind it.
	var best_building := -1
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if int(info["owner"]) != _state.player or bool(info["destroyed"]):
			continue
		var node: MeshInstance3D = _building_nodes.get(wire_id, null)
		if node == null or _camera.is_position_behind(node.position):
			continue
		var distance := _camera.unproject_position(node.position).distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best_building = int(wire_id)
			best = -1

	if best_building >= 0:
		_selected_building = best_building
		_selected.clear()
		return

	_selected_building = -1
	if best >= 0 and not _selected.has(best):
		_selected.append(best)


func _select_within(rect: Rect2) -> void:
	for squad in _state.squads:
		if not _state.curves.has(squad):
			continue
		# A box that clips any part of the squad takes it, rather than
		# needing to contain one particular point — dragging across the
		# front rank of a line should select that line.
		var print := _squad_footprint(squad)
		var at := _screen_of(print["centre"])
		var reach := _screen_radius_of(print)
		if rect.grow(reach).has_point(at) and not _selected.has(squad):
			_selected.append(squad)


func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_X:
		_stop_selected()
		return

	# Build keys. The server checks everything that matters — who may
	# build what, the ground, the reach, the price — so these just send
	# intent and let the authority answer (and now explain itself).
	#
	# One key per building rather than a menu: with four of them it is the
	# shortest path to something playable, and the hint line can list them
	# all. A build menu is worth having when the roster outgrows a row of
	# keys, not before.
	# Driven from BUILD_KEYS/TRAIN_KEYS rather than a match statement, so
	# the HUD's "can:" line and the keys that actually work are the same
	# table. Which building can make which unit is still decided by
	# BuildingDef.produces on the SERVER — these are only requests, and a
	# wrong one comes back as a refusal that says why (D-034).
	var key := OS.get_keycode_string(event.keycode)
	if BUILD_KEYS.has(key):
		_build_selected(String(BUILD_KEYS[key]))
		return
	if TRAIN_KEYS.has(key):
		_train_selected(TRAIN_KEYS[key])
		return
	if event.keycode == KEY_G:
		_gather_selected()                   # workers, at the cursor's node
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

	# Right-clicking an ENEMY attacks it. No modifier, no separate key.
	#
	# Attack-move was Ctrl+right-click and also the A key — and A is bound
	# to camera pan (WASD), so it could never have worked. The result was a
	# player with no way to attack that they would find. Every RTS since
	# the nineties answers this the same way: right-click means "do the
	# obvious thing to that", which is move for ground and attack for an
	# enemy.
	# With a BUILDING selected, right-click sets its rally point — where
	# what it produces will muster. Same gesture as ordering a squad, and
	# it is what a player will try first.
	if _selected_building >= 0 and _state.buildings.has(_selected_building):
		var info: Dictionary = _state.buildings[_selected_building]
		if int(info["owner"]) == _state.player:
			var rally_cell := _cell_under(screen_position)
			if rally_cell.x >= 0:
				_peer.send(0, NetProtocol.encode_order_rally(
					_selected_building, _state.space.index(rally_cell)),
					ENetPacketPeer.FLAG_RELIABLE)
				print("client: rally point set to %s" % rally_cell)
			return

	var target := _enemy_cell_at(screen_position)

	# Right-clicking a RESOURCE puts workers on it, the same way
	# right-clicking an enemy attacks. Gathering was reachable only
	# through the G key and the Gather button, both of which act on
	# wherever the mouse happens to be — so the obvious gesture did the
	# non-obvious thing and marched your villagers onto the trees to stand
	# there. Enemies win the tie: if a node and an enemy are both under
	# the cursor, the enemy is the more urgent thing you meant.
	if target.x < 0 and _selection_can_gather():
		var node_cell := _resource_cell_at(screen_position)
		if node_cell.x >= 0:
			var sent_gather := 0
			for squad in _selected:
				var gather := _state.encode_gather(squad, node_cell)
				if not gather.is_empty():
					_peer.send(0, gather, ENetPacketPeer.FLAG_RELIABLE)
					sent_gather += 1
			if sent_gather > 0:
				print("client: sent %d squad(s) to gather at %s" % [sent_gather, node_cell])
				return

	var cell := target if target.x >= 0 else _cell_under(screen_position)
	if cell.x < 0:
		return
	var attacking := attack_move or target.x >= 0

	var sent := 0
	for squad in _selected:
		var order := _state.encode_attack_move(squad, cell) if attacking else _state.encode_order(squad, cell)
		if not order.is_empty():
			_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
			sent += 1
	if sent > 0:
		print("client: %s %d squad(s) to cell %s" % [
			"attacked with" if attacking else "ordered", sent, cell])


## The cell of an enemy squad or building under the cursor, or (-1,-1).
##
## Uses the same screen-distance test and the same DRAWN positions as
## selection, so what you can click to attack is what you can see — and a
## wrapped enemy across the seam is clickable where it appears rather than
## where its canonical coordinates say it is.
##
## Buildings are checked too: a town hall is the thing you most want to
## right-click, and it is the only way to win (D-055).
func _enemy_cell_at(screen_position: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := SELECT_CLICK_RADIUS_PX

	for squad in _state.curves:
		if not _state.composition.has(squad):
			continue
		if int(_state.composition[squad].get("owner", 0)) == _state.player:
			continue
		if _state.alive_of(squad) <= 0:
			continue
		var distance := _squad_screen_position(squad).distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best = _state.squad_cell(squad, _now)

	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if int(info["owner"]) == _state.player or bool(info["destroyed"]):
			continue
		var node: MeshInstance3D = _building_nodes.get(wire_id, null)
		if node == null or not node.visible or _camera.is_position_behind(node.position):
			continue
		var distance := _camera.unproject_position(node.position).distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best = _state.space.from_index(int(info["cell"]))

	return best


## Ask the first selected squad to found a building at the cursor.
##
## Only founders may build a town hall, and only a town hall — that rule
## is data on the BuildingDef (D-031) and enforced server-side, so a
## refused order simply does nothing here rather than being second-guessed
## client-side.
## ARM placement rather than building immediately.
##
## Pressing build used to found the building at wherever the mouse
## happened to be, which is fine for a key you press while pointing at a
## spot and wrong for a BUTTON — the mouse is over the button. You now
## pick the building, a ghost of it follows the cursor, and you click the
## ground where you want it.
func _build_selected(def_id: String) -> void:
	if not _connected or _state.space == null or _selected.is_empty():
		return
	_placing = StringName(def_id)
	_update_placement_ghost()


## Place the armed building, or do nothing if none is armed.
## Returns true if the click was consumed by placement.
func _place_armed_building(screen_position: Vector2) -> bool:
	if _placing == &"":
		return false
	var cell := _cell_under(screen_position)
	# Typed explicitly: `_selected` is untyped, so a ternary over it has
	# no inferable type and the whole script fails to parse.
	var squad: int = int(_selected[0]) if not _selected.is_empty() else -1
	var def_id := _placing
	_cancel_placement()
	if cell.x < 0 or squad < 0:
		return true

	var order := _state.encode_build(squad, String(def_id), cell)
	if not order.is_empty():
		_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
		print("client: asked squad %d to found a %s at %s" % [squad, def_id, cell])
	return true


func _cancel_placement() -> void:
	_placing = &""
	if _placement_ghost != null:
		_placement_ghost.visible = false


## Move the ghost to the cell under the cursor, and colour it by whether
## the ground will take it.
##
## Buildability is judged the same way the SERVER judges it (terrain
## passability plus nothing already standing there), so the preview and
## the answer agree. It is still only a preview: the server decides, and a
## refusal comes back as a notice like any other (D-034).
func _update_placement_ghost() -> void:
	if _placing == &"" or _state.space == null:
		return

	if _placement_ghost == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.4, 3.0, 2.4)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_placement_ghost = MeshInstance3D.new()
		_placement_ghost.mesh = mesh
		_placement_ghost.material_override = material
		add_child(_placement_ghost)

	var cell := _cell_under(get_viewport().get_mouse_position())
	if cell.x < 0:
		_placement_ghost.visible = false
		return

	var world := _state.space.to_world(cell)
	if _state.terrain_sampler.is_valid():
		world.y = _state.terrain_sampler.call(world.x, world.z)
	_placement_ghost.visible = true
	_placement_ghost.position = world + Vector3(0.0, 1.5, 0.0) + _lattice_offset_for(world)

	var ok := _can_place_at(cell)
	var material := _placement_ghost.material_override as StandardMaterial3D
	material.albedo_color = Color(0.4, 0.95, 0.5, 0.45) if ok else Color(0.95, 0.35, 0.3, 0.45)


## Whether the ground under the cursor looks buildable from here.
##
## Advisory only — the server is the authority (D-002) and re-checks on
## arrival, since a builder that walks for twenty seconds may find the
## ground taken. This exists so the preview is not misleading, not so the
## client can decide.
func _can_place_at(cell: Vector2i) -> bool:
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if bool(info["destroyed"]):
			continue
		if _state.space.from_index(int(info["cell"])) == cell:
			return false
	if not _passable.is_empty():
		var index := _state.space.index(cell)
		if index < _passable.size() and _passable[index] == 0:
			return false
	return true


## Put the selected workers on the node under the cursor (D-028).
##
## They walk there, fill up, haul to the nearest drop-off, unload and come
## back, on their own — the order is "work this node", not a route.
func _gather_selected() -> void:
	if not _connected or _state.space == null or _selected.is_empty():
		return

	var at := get_viewport().get_mouse_position()
	# The nearest node to the cursor, not the exact hex under it — see
	# _resource_cell_at.
	var cell := _resource_cell_at(at)
	if cell.x < 0:
		cell = _cell_under(at)
	if cell.x < 0:
		return

	for squad in _selected:
		var order := _state.encode_gather(squad, cell)
		if not order.is_empty():
			_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)


## The cell of a resource node near the cursor, or (-1,-1).
##
## Gathering used to require clicking the EXACT hex a node stands on,
## because it took `_cell_under` and nothing else. A hex is a small target
## at any sensible zoom and there is no visual edge to aim at, so ordering
## workers onto a forest was a game of precision clicking. Reported as the
## hitbox feeling tiny, which it was — one cell.
##
## Same screen-distance test as enemies and squads, so everything on the
## map is clicked the same way, and against the DRAWN marker position so a
## node past the seam is clickable where it appears (D-035).
##
## Only explored nodes: fog governs what you know about the map, and that
## includes what is on it (D-004).
func _resource_cell_at(screen_position: Vector2) -> Vector2i:
	if _state.space == null:
		return Vector2i(-1, -1)

	var best := Vector2i(-1, -1)
	var best_distance := SELECT_CLICK_RADIUS_PX
	for cell in _state.nodes:
		if not _explored.has(cell):
			continue
		var marker: MeshInstance3D = _node_meshes.get(cell, null)
		if marker == null or not marker.visible:
			continue
		if _camera.is_position_behind(marker.position):
			continue
		var distance := _camera.unproject_position(marker.position).distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best = _state.space.from_index(int(cell))
	return best


## Whether anything selected can actually gather. Right-clicking a forest
## with SOLDIERS selected should march them there, not silently do
## nothing — the order has to mean something for the unit receiving it.
func _selection_can_gather() -> bool:
	for squad in _selected:
		var def := UnitRoster.by_id(
			StringName(String(_state.composition.get(squad, {}).get("def_id", ""))))
		if def != null and def.carry_capacity > 0:
			return true
	return false


## Train a unit at the selected building (D-028).
##
## Buildings are selected the same way squads are — by clicking near them
## — because a player should not have to learn two selection models to
## use the two kinds of thing on the map.
func _train_selected(archetype: StringName) -> void:
	if not _connected or _selected_building < 0:
		return
	_peer.send(0, NetProtocol.encode_order_produce(_selected_building, archetype),
		ENetPacketPeer.FLAG_RELIABLE)


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


# --- lobby screen (D-048, D-049) --------------------------------------
#
# Laid out the way the genre does it — Age of Empires and Empires: Dawn
# of the Modern World both put a slot table on the left, a MAP PREVIEW
# with the game settings beside it, and a start button under the lot.
# That layout is conventional because it answers the three questions a
# player has before a match: who am I playing, as whom, and where.
#
# All procedural. D-011 puts this project on the primitive art tier, so
# there is no chrome to import: panels are StyleBoxFlat, civ emblems are
# their own colours, bars are drawn, and the map preview is GENERATED
# from the terrain settings rather than being an authored thumbnail.
#
# ## Why this rebuilds on change and not per frame
#
# It used to rebuild every row every frame, which was fine for labels and
# fatal for controls: a dropdown would be freed the instant it opened, so
# nothing could ever be clicked. The screen is rebuilt only when the
# server's description of the lobby actually changes — which is when
# somebody acts, not sixty times a second.

var _hud_layer: CanvasLayer
var _lobby_layer: CanvasLayer
var _lobby_seat_rows: VBoxContainer
var _lobby_title: Label
var _lobby_help: Label
var _map_rows: VBoxContainer
var _map_preview: TextureRect
var _map_blurb: Label
var _start_button: Button
var _add_ai_button: Button

## What the screen was last built from. Rebuilding is what would destroy
## an open dropdown, so it happens only when this changes.
var _lobby_signature := ""

## The settings the map preview was last built from. Regenerating is
## O(cells), so it is separate from the signature above.
var _preview_key := ""

const MAP_OPTIONS := [
	{"key": "preset", "label": "Terrain", "kind": "choice"},
	{"key": "size", "label": "Map size", "kind": "choice"},
	{"key": "player_slots", "label": "Starting positions", "kind": "int", "min": 2, "max": 24},
	{"key": "seed", "label": "Seed", "kind": "int", "min": 0, "max": 999999},
	{"key": "sea_level", "label": "Sea level", "kind": "slider", "min": 0.05, "max": 0.9},
	{"key": "mountain_level", "label": "Mountain line", "kind": "slider", "min": 0.1, "max": 0.98},
	{"key": "elevation_frequency", "label": "Landmass count", "kind": "slider", "min": 0.5, "max": 8.0},
	{"key": "height_scale", "label": "Relief", "kind": "slider", "min": 0.5, "max": 6.0},
]


## A framed panel with a header — the repeated unit of this screen.
func _lobby_panel(title: String, parent: Control) -> VBoxContainer:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 1.0)
	style.border_color = Color(0.28, 0.34, 0.45, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	frame.add_theme_stylebox_override("panel", style)
	parent.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 16)
	header.modulate = Color(0.55, 0.66, 0.85)
	column.add_child(header)

	var rule := ColorRect.new()
	rule.color = Color(0.24, 0.30, 0.40, 1.0)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	column.add_child(rule)
	return column


## Buttons get their own styling because the default Godot theme looks
## nothing like the rest of this screen.
func _styled_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 15)
	button.focus_mode = Control.FOCUS_NONE

	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = accent.darkened(0.55)
		if state == "hover":
			style.bg_color = accent.darkened(0.35)
		elif state == "pressed":
			style.bg_color = accent.darkened(0.2)
		elif state == "disabled":
			style.bg_color = Color(0.14, 0.15, 0.19, 1.0)
		style.border_color = accent if state != "disabled" else Color(0.24, 0.26, 0.30)
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		button.add_theme_stylebox_override(state, style)
	return button


func _build_lobby_ui() -> void:
	_lobby_layer = CanvasLayer.new()
	# Above the HUD, not merely after it: CanvasLayers draw in layer
	# order, so a backdrop on the same layer let the game HUD show
	# straight through the lobby.
	_lobby_layer.layer = 10
	_lobby_layer.visible = false
	add_child(_lobby_layer)

	var backdrop := ColorRect.new()
	# Fully opaque: there is no world behind the lobby yet, because the
	# map is not generated until the match starts (D-049).
	backdrop.color = Color(0.045, 0.055, 0.08, 1.0)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	_lobby_layer.add_child(backdrop)

	var root := VBoxContainer.new()
	root.position = Vector2(40.0, 24.0)
	root.add_theme_constant_override("separation", 12)
	_lobby_layer.add_child(root)

	_lobby_title = Label.new()
	_lobby_title.text = "MULTIPLAYER LOBBY"
	_lobby_title.add_theme_font_size_override("font_size", 28)
	root.add_child(_lobby_title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	root.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(620.0, 0.0)
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	_lobby_seat_rows = _lobby_panel("PLAYERS", left)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	left.add_child(actions)

	_add_ai_button = _styled_button("+  Add AI player", Color(0.55, 0.62, 0.78))
	_add_ai_button.pressed.connect(_on_add_ai_pressed)
	actions.add_child(_add_ai_button)

	_start_button = _styled_button("START MATCH", Color(0.42, 0.78, 0.48))
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.pressed.connect(_on_start_pressed)
	actions.add_child(_start_button)

	_lobby_help = Label.new()
	_lobby_help.add_theme_font_size_override("font_size", 13)
	_lobby_help.modulate = Color(0.55, 0.60, 0.70)
	_lobby_help.custom_minimum_size = Vector2(600.0, 0.0)
	_lobby_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_lobby_help)

	# Chat sits under the player list, where the genre puts it.
	var chat_column := _lobby_panel("CHAT", left)
	_chat_log_label = Label.new()
	_chat_log_label.add_theme_font_size_override("font_size", 14)
	_chat_log_label.custom_minimum_size = Vector2(590.0, 96.0)
	_chat_log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_chat_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_log_label.modulate = Color(0.78, 0.82, 0.88)
	chat_column.add_child(_chat_log_label)

	_chat_entry = LineEdit.new()
	_chat_entry.placeholder_text = "Say something…"
	_chat_entry.add_theme_font_size_override("font_size", 14)
	_chat_entry.max_length = NetProtocol.CHAT_MAX_CHARS
	_chat_entry.custom_minimum_size = Vector2(590.0, 0.0)
	# Submitting is the only way to send: there is no send button, because
	# Enter is what everyone already presses.
	_chat_entry.text_submitted.connect(_on_chat_submitted)
	chat_column.add_child(_chat_entry)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)

	var preview_column := _lobby_panel("MAP", right)
	_map_preview = TextureRect.new()
	_map_preview.custom_minimum_size = Vector2(380.0, 168.0)
	_map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_column.add_child(_map_preview)

	_map_blurb = Label.new()
	_map_blurb.add_theme_font_size_override("font_size", 13)
	_map_blurb.modulate = Color(0.60, 0.68, 0.62)
	_map_blurb.custom_minimum_size = Vector2(380.0, 32.0)
	_map_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_column.add_child(_map_blurb)

	_map_rows = _lobby_panel("GAME SETTINGS", right)


## A coloured block standing in for a civ emblem. The colour comes from
## the CivDef, so a civ added as a .tres arrives with its own identity
## and no script learns its name (D-046 criterion 3).
func _swatch(colour: Color, size: Vector2) -> Control:
	var holder := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(3)
	style.border_color = colour.lightened(0.35)
	style.set_border_width_all(1)
	holder.add_theme_stylebox_override("panel", style)
	holder.custom_minimum_size = size
	return holder


func _civ_colour(civ: String) -> Color:
	if StringName(civ) == CivRoster.RANDOM:
		return Color(0.42, 0.44, 0.52)
	var def := CivRoster.by_id(StringName(civ))
	return def.colour if def != null else Color(0.5, 0.5, 0.5)


func _civ_label(civ: String) -> String:
	if StringName(civ) == CivRoster.RANDOM:
		return "Random"
	var def := CivRoster.by_id(StringName(civ))
	return def.display_name if def != null else civ


## Every civ, plus Random. Read from the roster so a civ added as a .tres
## appears here with no code change (D-046 criterion 3).
func _civ_choices() -> Array:
	var out: Array = [CivRoster.RANDOM]
	for id in CivRoster.ids():
		out.append(id)
	return out


func _refresh_lobby() -> void:
	if _lobby_layer == null:
		return
	var showing := _state.in_lobby()
	if _hud_layer != null:
		_hud_layer.visible = not showing
	_lobby_layer.visible = showing
	if not showing:
		_lobby_signature = ""
		return

	# Rebuilding frees every control, so it happens only when the server's
	# description actually changed. Doing it per frame closed dropdowns
	# faster than anyone could use them.
	var signature := JSON.stringify(_state.lobby) + str(_state.player)
	if signature == _lobby_signature:
		return
	_lobby_signature = signature

	var seats: Array = _state.lobby.get("seats", [])
	for child in _lobby_seat_rows.get_children():
		if child.get_index() > 1:
			child.queue_free()
	for i in range(seats.size()):
		_lobby_seat_rows.add_child(_seat_row(seats[i], i))

	var admin := _state.is_admin()
	_add_ai_button.disabled = not admin
	_start_button.disabled = not admin or seats.size() < 2
	_start_button.text = "START MATCH" if admin else "WAITING FOR HOST"

	if admin:
		_lobby_help.text = "Click a civilisation to change it. Only you can seat AI players and start the match."
	else:
		_lobby_help.text = "Choose your civilisation. The host starts the match."

	_refresh_map_panel()


func _seat_row(seat: Dictionary, index: int) -> Control:
	var mine: bool = String(seat["kind"]) == "human" and int(seat["player"]) == _state.player
	var is_ai: bool = String(seat["kind"]) == "ai"
	var civ := String(seat["civ"])
	# A human owns their own seat; the host also owns the AI seats. The
	# server re-checks this (D-002) — disabling the control here only
	# avoids sending an order we already know is not ours to give.
	var editable: bool = mine or (is_ai and _state.is_admin())

	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.135, 0.155, 0.21, 1.0) if mine else Color(0.115, 0.135, 0.185, 1.0)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if mine:
		style.border_color = Color(0.40, 0.70, 0.48, 1.0)
		style.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	frame.add_child(row)

	# The PLAYER's colour, not the civ's (D-052): twenty players share
	# two civs, so a civ swatch cannot tell them apart — and this is the
	# same colour their army will be on the field.
	row.add_child(_swatch(PlayerColours.of_index(index), Vector2(24.0, 24.0)))

	var kind := Label.new()
	kind.text = "AI" if is_ai else "HUMAN"
	kind.add_theme_font_size_override("font_size", 13)
	kind.modulate = Color(0.74, 0.66, 0.48) if is_ai else Color(0.56, 0.72, 0.92)
	kind.custom_minimum_size = Vector2(56.0, 0.0)
	row.add_child(kind)

	var name_label := Label.new()
	name_label.text = String(seat["name"])
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.custom_minimum_size = Vector2(120.0, 0.0)
	name_label.modulate = Color(0.70, 0.95, 0.75) if mine else Color(0.85, 0.87, 0.92)
	row.add_child(name_label)

	# The civ picker itself — a real dropdown rather than a label you have
	# to know a keyboard shortcut to change.
	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", 15)
	picker.custom_minimum_size = Vector2(160.0, 0.0)
	picker.focus_mode = Control.FOCUS_NONE
	picker.disabled = not editable
	var choices := _civ_choices()
	for c in choices:
		picker.add_item(_civ_label(String(c)))
	picker.selected = maxi(choices.find(StringName(civ)), 0)
	if editable:
		picker.item_selected.connect(_on_civ_picked.bind(index))
	row.add_child(picker)

	# Team, with the same permissions as the civ picker (D-050).
	var team_picker := OptionButton.new()
	team_picker.add_theme_font_size_override("font_size", 14)
	team_picker.custom_minimum_size = Vector2(96.0, 0.0)
	team_picker.focus_mode = Control.FOCUS_NONE
	team_picker.disabled = not editable
	team_picker.add_item("No team")
	for t in range(1, MatchState.MAX_TEAMS + 1):
		team_picker.add_item("Team %d" % t)
	team_picker.selected = clampi(int(seat.get("team", 0)), 0, MatchState.MAX_TEAMS)
	if editable:
		team_picker.item_selected.connect(_on_team_picked.bind(index))
	row.add_child(team_picker)

	var tags := Label.new()
	tags.text = ("HOST" if int(seat["player"]) == int(_state.lobby.get("admin", 0)) else "")
	tags.add_theme_font_size_override("font_size", 13)
	tags.modulate = Color(0.86, 0.76, 0.46)
	tags.custom_minimum_size = Vector2(44.0, 0.0)
	row.add_child(tags)

	# Only AI seats can be removed, and only by the host. A player leaves
	# by disconnecting — eviction is a moderation feature nobody asked for.
	if is_ai and _state.is_admin():
		var remove := _styled_button("Remove", Color(0.78, 0.44, 0.42))
		remove.add_theme_font_size_override("font_size", 13)
		remove.pressed.connect(_on_remove_ai_pressed.bind(index))
		row.add_child(remove)

	return frame


# --- what the controls do ---------------------------------------------

func _on_civ_picked(choice: int, seat_index: int) -> void:
	var choices := _civ_choices()
	if choice < 0 or choice >= choices.size():
		return
	_send_lobby(NetProtocol.LOBBY_SET_CIV, seat_index, String(choices[choice]))


func _on_team_picked(choice: int, seat_index: int) -> void:
	# The team number travels in the command's text field, the same way
	# map options do — one small generic message rather than an opcode per
	# control.
	_send_lobby(NetProtocol.LOBBY_SET_TEAM, seat_index, str(choice))


func _on_add_ai_pressed() -> void:
	_send_lobby(NetProtocol.LOBBY_ADD_AI, 0, String(CivRoster.RANDOM))


func _on_remove_ai_pressed(seat_index: int) -> void:
	_send_lobby(NetProtocol.LOBBY_REMOVE_AI, seat_index, "")


func _on_start_pressed() -> void:
	_send_lobby(NetProtocol.LOBBY_START, 0, "")


func _on_map_choice(choice: int, key: String) -> void:
	_send_lobby(NetProtocol.LOBBY_SET_OPTION, 0, "%s=%d" % [key, choice])


func _on_map_value(value: float, key: String) -> void:
	_send_lobby(NetProtocol.LOBBY_SET_OPTION, 0, "%s=%f" % [key, value])


func _send_lobby(action: int, seat: int, civ: String) -> void:
	if not _connected:
		return
	_peer.send(0, NetProtocol.encode_lobby_command(action, seat, civ),
		ENetPacketPeer.FLAG_RELIABLE)


# --- map preview and settings (D-049) ---------------------------------

## Render the map the settings describe.
##
## Generated from the SAME TerrainGen the match will use, so this is a
## truthful picture rather than decoration — choose islands and you see
## islands. It is emphatically NOT the world: one pixel per cell, no
## simulation behind it, and the playable map is still built only when the
## match starts. A preview is a photograph of a place that does not exist
## yet.
func _rebuild_map_preview(settings: Dictionary) -> void:
	var key := JSON.stringify(settings)
	if key == _preview_key:
		return
	_preview_key = key

	var map := MapSettings.from_dict(settings)
	var space := map.to_space()
	var terrain := map.to_terrain()

	var image := Image.create(space.width, space.height, false, Image.FORMAT_RGBA8)
	for y in range(space.height):
		for x in range(space.width):
			image.set_pixel(x, y, terrain.biome_color(space, Vector2i(x, y)))

	# Where people start, the way a lobby preview shows player positions.
	# MapConfig.spawn_points is the SHARED implementation the server uses
	# (D-039), so this is the same answer rather than a second guess at it.
	var spawn_config := MapConfig.new()
	spawn_config.width = space.width
	spawn_config.height = space.height
	spawn_config.player_slots = map.player_slots
	spawn_config.spawn_seed = map.seed
	for cell in spawn_config.spawn_points(terrain.passability(space)):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				image.set_pixel(
					posmod(cell.x + dx, space.width),
					posmod(cell.y + dy, space.height),
					Color(1.0, 0.93, 0.55))

	_map_preview.texture = ImageTexture.create_from_image(image)


func _size_labels() -> Array:
	var out: Array = []
	for entry in MapSettings.sizes():
		out.append("%s  (%d x %d)" % [entry["name"], entry["width"], entry["height"]])
	return out


func _refresh_map_panel() -> void:
	if _map_rows == null:
		return
	var settings: Dictionary = _state.lobby.get("settings", {})
	if settings.is_empty():
		return

	_rebuild_map_preview(settings)
	var preset := TerrainPresetRoster.by_id(StringName(settings.get("preset", "")))
	_map_blurb.text = preset.summary if preset != null else ""

	for child in _map_rows.get_children():
		if child.get_index() > 1:
			child.queue_free()

	var admin := _state.is_admin()
	for option in MAP_OPTIONS:
		_map_rows.add_child(_map_row(option, settings, admin))

	if not admin:
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 13)
		note.modulate = Color(0.52, 0.55, 0.60)
		note.text = "Only the host can change these."
		_map_rows.add_child(note)


func _map_row(option: Dictionary, settings: Dictionary, admin: bool) -> Control:
	var key := String(option["key"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = String(option["label"])
	label.add_theme_font_size_override("font_size", 14)
	label.custom_minimum_size = Vector2(140.0, 0.0)
	label.modulate = Color(0.70, 0.74, 0.82)
	row.add_child(label)

	match String(option["kind"]):
		"choice":
			var picker := OptionButton.new()
			picker.add_theme_font_size_override("font_size", 14)
			picker.custom_minimum_size = Vector2(212.0, 0.0)
			picker.focus_mode = Control.FOCUS_NONE
			picker.disabled = not admin
			if key == "preset":
				var ids := TerrainPresetRoster.ids()
				for id in ids:
					var def := TerrainPresetRoster.by_id(id)
					picker.add_item(def.display_name if def != null else String(id))
				picker.selected = maxi(ids.find(StringName(settings.get("preset", ""))), 0)
			else:
				var sizes := MapSettings.sizes()
				for text in _size_labels():
					picker.add_item(String(text))
				for i in range(sizes.size()):
					if int(sizes[i]["width"]) == int(settings.get("width", 0)):
						picker.selected = i
						break
			if admin:
				picker.item_selected.connect(_on_map_choice.bind(key))
			row.add_child(picker)

		"int":
			var spin := SpinBox.new()
			spin.min_value = float(option["min"])
			spin.max_value = float(option["max"])
			spin.step = 1.0
			spin.value = float(settings.get(key, 0))
			spin.custom_minimum_size = Vector2(212.0, 0.0)
			spin.editable = admin
			spin.get_line_edit().focus_mode = Control.FOCUS_NONE
			if admin:
				spin.value_changed.connect(_on_map_value.bind(key))
			row.add_child(spin)

		"slider":
			var slider := HSlider.new()
			slider.min_value = float(option["min"])
			slider.max_value = float(option["max"])
			slider.step = 0.01
			slider.value = float(settings.get(key, 0.0))
			slider.custom_minimum_size = Vector2(150.0, 18.0)
			slider.focus_mode = Control.FOCUS_NONE
			slider.editable = admin
			if admin:
				slider.value_changed.connect(_on_map_value.bind(key))
			row.add_child(slider)

			var value := Label.new()
			value.text = "%.2f" % float(settings.get(key, 0.0))
			value.add_theme_font_size_override("font_size", 14)
			value.custom_minimum_size = Vector2(52.0, 0.0)
			value.modulate = Color(0.85, 0.88, 0.94)
			row.add_child(value)

	return row


## Keyboard remains as a fallback for starting, so the screen is usable
## without a mouse. Everything else is now clickable.
func _handle_lobby_input(event: InputEvent) -> bool:
	if not _state.in_lobby():
		return false
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	match (event as InputEventKey).keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_on_start_pressed()
		KEY_A:
			_on_add_ai_pressed()
		_:
			return false
	return true


## Capture-only: how many AI seats to ask for once we are admin, and
## which terrain preset to select. Zero during `run-client`, which is a
## human at the wheel.
var _lobby_ai_wanted := 0
var _lobby_preset_steps := 0
var _lobby_ai_asked := false


func _seat_capture_ai() -> void:
	if _lobby_ai_asked or _lobby_ai_wanted <= 0:
		return
	if not (_state.in_lobby() and _state.is_admin()):
		return
	_lobby_ai_asked = true
	var civs := CivRoster.ids()
	for i in range(_lobby_ai_wanted):
		# Spread the AI across civs rather than leaving them all Random,
		# so the capture shows what a mixed lobby looks like.
		var civ: String = String(civs[i % civs.size()]) if not civs.is_empty() else String(CivRoster.RANDOM)
		_send_lobby(NetProtocol.LOBBY_ADD_AI, 0, civ)
	# An INDEX rather than a name, so this file names no preset and the
	# capture keeps working whatever /terrain holds.
	if _lobby_preset_steps > 0:
		_send_lobby(NetProtocol.LOBBY_SET_OPTION, 0, "preset=%d" % _lobby_preset_steps)

	# Put the capture in a state worth photographing: sides chosen, and
	# something in the chat window. A screenshot of empty controls says
	# nothing about whether they work.
	_send_lobby(NetProtocol.LOBBY_SET_TEAM, 0, "1")
	for i in range(_lobby_ai_wanted):
		_send_lobby(NetProtocol.LOBBY_SET_TEAM, i + 1, str(2 if i == 0 else 1))
	if _connected:
		_peer.send(0, NetProtocol.encode_chat_send("good luck, everyone"),
			ENetPacketPeer.FLAG_RELIABLE)


# --- chat (D-050) -----------------------------------------------------

var _chat_log_label: Label
var _chat_entry: LineEdit

## What the chat panel was last drawn from, so the log is only rebuilt
## when a message actually arrives — the same reason the seat list is not
## rebuilt per frame.
var _chat_shown := 0


func _on_chat_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed == "" or not _connected:
		return
	_peer.send(0, NetProtocol.encode_chat_send(trimmed), ENetPacketPeer.FLAG_RELIABLE)
	_chat_entry.text = ""


## Redraw the backlog if it grew.
##
## Deliberately outside the lobby's change-signature rebuild: a message
## arriving must not rebuild the seat rows, because that would close a
## dropdown somebody had open. Chat is the one part of this screen that
## updates on its own schedule.
func _refresh_chat() -> void:
	if _chat_log_label == null:
		return
	if _state.chat_log.size() == _chat_shown:
		return
	_chat_shown = _state.chat_log.size()

	var lines := []
	for message in _state.chat_log:
		lines.append("%s:  %s" % [message["speaker"], message["text"]])
	# Only the tail fits the panel, and the newest lines are the ones
	# anyone wants.
	if lines.size() > 6:
		lines = lines.slice(lines.size() - 6)
	_chat_log_label.text = "\n".join(lines)


## The colour of whoever owns this squad (D-052). Falls back to a
## neutral tint before composition arrives, rather than guessing an owner.
func _owner_colour_of(squad_id) -> Color:
	var entry: Dictionary = _state.composition.get(squad_id, {})
	if entry.is_empty():
		entry = _state.ghost_info(squad_id)
	if entry.is_empty():
		return Color(0, 0, 0, 0)
	return _state.colour_of(int(entry.get("owner", 0)))
