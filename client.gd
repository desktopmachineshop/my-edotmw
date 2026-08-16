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

## How fast Q/E turn the view while held, in radians/second — continuous,
## the same as WASD panning, rather than a fixed step per keypress. A full
## turn in four seconds: fast enough that turning around does not feel
## like a chore, slow enough to aim a formation along a ridge without
## overshooting it.
const CAMERA_YAW_RATE := deg_to_rad(90.0)
## Ctrl+wheel turns by this much per notch. Finer than Q/E, because a
## wheel invites small adjustments.
const CAMERA_YAW_WHEEL_STEP := deg_to_rad(7.5)

## Slack around the viewport, in pixels, when deciding whether a squad is
## worth deriving (D-045). Culling tests a squad's CENTRE, but a squad has
## real extent, so a formation whose centre is just off screen can still
## have soldiers on it. Generous on purpose: the cost of being wrong in
## this direction is a little wasted derivation, and the cost of being
## wrong in the other is soldiers popping in at the screen edge.
const CULL_MARGIN_PIXELS := 192.0

## Cosmetic placement variation (see `placement_jitter.gd`), as a fraction
## of `TorusSpace.hex_size`. Kept well under 0.5 (the distance to a cell
## edge at hex_size 1.0) so a jittered building or node still visibly
## stands on the cell the simulation says it occupies, never drifting into
## a neighbour's.
## How far from an existing wall a new one still snaps to it, in hex widths.
## Generous enough that you do not have to aim, tight enough that a wall
## started deliberately clear of a run stays where you put it.
const WALL_SNAP_CELLS := 2.2

const BUILDING_JITTER_FRACTION := 0.35
const RESOURCE_NODE_JITTER_FRACTION := 0.4

## One scroll notch's worth of continuous rotation while a freestanding
## building's ghost is armed (16/256 of a turn, 22.5 degrees) — coarse
## enough that a couple of notches reads as a deliberate turn, fine enough
## that 256 notches don't feel like 6 all over again.
const FREE_FACING_WHEEL_STEP := 16

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
## Which way the view is turned, in radians about UP. 0 is north-up, which
## is the orientation every map, minimap and spawn diagram is drawn in —
## hence the compass snapping back to exactly this.
var _camera_yaw := 0.0

## Settings the player has chosen (D-063), loaded from disk at startup.
## `_hud_scale_override` of 0 means "scale automatically with the window",
## which is the default and what HudLayout works out for itself.
var _pan_speed := CAMERA_PAN_SPEED
var _hud_scale_override := 0.0

## Zoom ceiling, derived from the map rather than fixed. Terrain is tiled
## in every direction so the world has no edge (D-035) — but zoom out far
## enough and you start seeing the SAME map repeated, which reads as a
## rendering bug rather than a torus. Capping the view at roughly half the
## map keeps the illusion intact.
var _camera_max_height := CAMERA_MAX_HEIGHT

## Playtest fix: WorldLook's depth fog is tuned against a camera height
## range, and `_camera_max_height` is only known once terrain is built —
## kept so `_build_terrain()` can re-derive the fog density for THIS map's
## actual camera ceiling (see `fog_density_for`'s doc) instead of the
## Standard-map default baked into the Environment built at startup.
var _world_environment: WorldEnvironment = null

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
## Below this ground speed a squad is standing still as far as animation is
## concerned. Not zero: a curve sampled either side of a keyframe produces a
## little numerical drift, and a squad that flickered between idle and walk on
## that drift would twitch.
const MOVING_SPEED_EPSILON := 0.15

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

## Whether a match is currently being drawn, so the edge into and out of
## one can be noticed (D-075). Derived from the server's phase every
## frame, never set by a button.
var _in_match := false

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
	# Which dev instance (agent worktree / branch) launched this client
	# (D-095). Several agents run servers and clients on one desktop in
	# parallel, so the title bar names the instance and the endpoint —
	# otherwise two identical windows are only tellable apart by clicking
	# around in them, and the human tests the wrong agent's build.
	var instance := String(args.get("instance", ""))
	var window_title := "eDotMW"
	if instance != "":
		window_title += " — %s" % instance
	window_title += "  [%s:%d]" % [address, port]
	get_window().title = window_title
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

	add_child(WorldLook.make_sun())

	_world_environment = WorldEnvironment.new()
	_world_environment.environment = WorldLook.make_environment()
	add_child(_world_environment)

	_terrain_root = Node3D.new()
	add_child(_terrain_root)

	# Not in capture mode: a headless render is given its resolution on the
	# command line (see `_run_seconds`'s own doc comment above), and a
	# minimum that fought a smaller requested size would make screenshots
	# depend on this constant rather than on what was asked for.
	if _run_seconds <= 0.0:
		get_window().min_size = HudLayout.min_window_size()

	# Settings first: the HUD reads `_hud_scale_override` while laying
	# itself out, so loading them afterwards would build the HUD once at
	# the wrong scale and only correct it on the first resize.
	_load_settings()
	_build_hud()
	_build_game_menu()
	_build_lobby_ui()
	_build_debug_panel()
	_build_defeat_screen()

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
	_frame_delta = delta
	_service_network()
	# Before anything reads the world: a return to the lobby (D-075)
	# invalidates every id below this line, and refreshing squads against
	# a torn-down match would draw one frame of the dead one.
	_sync_match_lifecycle()
	_pan_camera(delta)

	if _state.welcomed and _state.has_map() and not _terrain_built:
		_build_terrain()
		_terrain_built = true

	_refresh_squads()
	_refresh_buildings()
	_update_missiles()
	_refresh_resource_nodes()
	# After both, so a ring can sit on the position they just set.
	_refresh_selection_rings()
	_refresh_build_markers()
	_update_placement_ghost()
	_update_hud()
	_update_minimap()
	# Every frame, NOT throttled with the rest of the minimap (see
	# `_update_minimap`'s own MINIMAP_INTERVAL comment — fog and squad dots
	# genuinely do not need more than 4 Hz). The camera-follow point does:
	# it tracks continuous WASD/Q-E motion, and updating it at the same
	# throttled rate made the whole ring visibly jump every 250ms instead
	# of panning smoothly — reported as the minimap being "jerky". Cheap
	# on its own (one shader uniform, no image work), so it does not need
	# the throttle the expensive per-pixel redraw exists for.
	_centre_minimap_crop_on_camera()
	_seat_capture_ai()
	_refresh_chat()
	_refresh_lobby()
	_refresh_debug_panel()
	_refresh_defeat()

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
	_terrain_gen = terrain
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
	#
	# Since D-067 the ground is a continuous surface rather than one flat
	# height per cell, so this interpolates within the hex — through the SAME
	# array the chunks below are built from, and the same code the mesher
	# uses. That sharing is the point: a sampler that agreed with the mesh
	# only by construction-in-two-places is a sampler that will eventually
	# disagree, and the symptom is a floating army with every number green.
	#
	# One `build_fields` call rather than a surface call, a colour call and a
	# passability call: they are all O(cells) over the same noise, and pairing
	# heights from one build with colours from another is a mistake nothing
	# would report (D-096).
	var fields := terrain.build_fields(space)
	var surface := fields.surface
	_state.terrain_sampler = func(x: float, z: float) -> float:
		return TerrainChunk.height_at(space, surface, x, z)

	# One shared definition (D-066), so the benchmark renders what the game
	# renders. Textured when generated/ has been built, vertex colour alone
	# when it has not.
	var material := TerrainChunk.make_material()

	var meshes := []
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(cx, cy), chunk_size, fields)
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
	_passable = fields.passable

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

	# Playtest fix: WorldLook's depth fog was tuned once, against the
	# Standard map's ~31-unit max_camera_height, and never revisited once
	# _camera_max_height became per-map. A Huge map reaches D-045's 90-unit
	# ceiling, and the SAME density at that height fogs out most of the
	# view — reported as "just a grey landscape". Re-derived here, now that
	# THIS map's actual ceiling is known, rather than the startup default.
	if _world_environment != null and _world_environment.environment != null:
		_world_environment.environment.fog_density = \
			WorldLook.fog_density_for(_camera_max_height)

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
		#
		# Terrain-corrected: `squad_world_position` always answers at
		# y=0 (see `_squad_footprint`'s own comment on the same gap), and
		# the cull test below projects THIS point to screen space to
		# decide on/off screen. On flat ground that is invisible; on a
		# hill the y=0 point can project to a screen position well away
		# from where the (correctly elevated) soldiers actually render,
		# culling a squad that is still visibly on screen or keeping one
		# that is not — reported as units vanishing well inside the
		# viewport rather than at its edge.
		var centre := _state.squad_world_position(squad_id, _now)
		if _state.terrain_sampler.is_valid():
			centre.y = _state.terrain_sampler.call(centre.x, centre.z)

		# Playtest fix: the margin was a flat CULL_MARGIN_PIXELS tested
		# against the squad's single anchor point — the same defect
		# `_select_nearest`'s own fix describes ("a forty-man line... many
		# metres across... clicking a soldier you could plainly see
		# selected nothing"), but here it hides soldiers who are still
		# genuinely on screen the instant the anchor crosses the margin, a
		# formation's own true size never entering into it. Reported as
		# units vanishing before they finish leaving the viewport. Grown
		# by the formation's own on-screen radius, exactly the fix
		# selection already got (see `_screen_radius_of`) — a wide "Sparse"
		# or "Ring" formation is a wide target for culling too, not just
		# for a click.
		var cull_margin := CULL_MARGIN_PIXELS
		if not _camera.is_position_behind(centre):
			var comp_info: Dictionary = _state.composition.get(squad_id, {})
			var world_radius: float = Formation.footprint(
				String(comp_info.get("shape", "line")), _state.alive_of(squad_id),
				float(comp_info.get("spacing", 1.0)))["radius"]
			var edge := centre + Vector3(world_radius, 0.0, 0.0)
			if world_radius > 0.0 and not _camera.is_position_behind(edge):
				cull_margin += _camera.unproject_position(centre).distance_to(
					_camera.unproject_position(edge))

		# Every lattice copy, not just the nearest to the look-at point.
		# The torus is shallower in z than it is wide, so more than one
		# copy is routinely on screen and "nearest" picks the wrong one —
		# which showed up in play as half the screen rendering no units.
		var offset = RenderCull.visible_offset(
			_camera, offsets, centre, cull_margin, viewport_size)
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
		#
		# Eased FIRST, so soldiers walk to their slots when the squad turns
		# instead of the whole block snapping round (D-059), then decorated
		# with sway, footfall and whatever the squad is visibly doing.
		var eased := _motion.ease(squad_id, transforms, _frame_delta)
		var doing := _activity_for(squad_id)
		var decorated := CosmeticOffset.decorate_activity(
			eased, _now, 1.0, int(doing["activity"]), doing["toward"])
		unit.set_slot_transforms(decorated)

		# Which clip these soldiers play (D-065). Derived from state the
		# client already holds — the curve gives speed, `_activity_for` gives
		# fighting, `routed_of` gives the rout — so nothing is sent for it and
		# every client agrees by construction, the same shape as D-052's
		# colour. Writes into the MultiMesh only when the clip or the rate
		# actually changes; the per-frame cost here is a comparison.
		var speed := _state.squad_speed(squad_id, _now)
		var clip := AnimationState.clip_for(
			_state.routed_of(squad_id),
			int(doing["activity"]) == CosmeticOffset.Activity.FIGHTING,
			speed > MOVING_SPEED_EPSILON)
		unit.set_clip_data(int(squad_id), clip, speed)

		if int(doing["activity"]) == CosmeticOffset.Activity.FIGHTING \
				and bool(doing["is_ranged"]):
			var launch := _missile_ground(centre + offset, MISSILE_RELEASE_HEIGHT)
			var landing := _missile_ground(
				_missile_landing(centre + offset, centre, doing["toward"]),
				MISSILE_IMPACT_HEIGHT)
			_maybe_launch_missile(
				"squad:%d" % int(squad_id), launch, landing, float(doing["interval"]))

		# A selection circle under EVERY soldier, from the transforms we
		# just derived — so the highlight follows the formation's real
		# shape as it changes, for free. A single disc could only ever
		# approximate a line, a wedge and a loose scatter with one circle.
		_stamp_selection_discs(squad_id, decorated)

	# Squad ghosts are hidden rather than drawn — a deliberate visual choice
	# (units ghost only as a rendering concept; buildings' persistent-
	# explored fog already never un-knows a building without any fade at
	# all, and that stays exactly as it is). This is a display decision
	# only: `_state.ghost_squad_ids()`/`ghost_info()` are untouched, so the
	# protocol, the composition hash and D-025's conceal/reveal wire events
	# still work precisely as documented — nothing here is skipped, only
	# what happens on screen with a squad once it has one.
	#
	# Explicitly hidden rather than merely left unwritten: doing nothing
	# would leave the node showing whatever transforms the LIVE pass above
	# last gave it, frozen but still fully opaque — exactly the "drawn as
	# though it were live" state D-026 criterion 11 was written to rule
	# out, just reached by a different route (never touching it again,
	# rather than rendering it wrong).
	for squad_id in _state.ghost_squad_ids():
		var unit: PrimitiveUnit = _squad_nodes.get(squad_id, null)
		if unit != null:
			unit.visible = false


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
## So this instead toggles the MATERIAL's own alpha blending. Alpha blending
## is a baseline feature of every rendering method this project uses, so
## unlike the instance shortcut this actually shows up in a screenshot.
##
## Since M7 the mechanism differs by which path a squad renders on — a
## primitive mutates its StandardMaterial3D's alpha, an authored model swaps
## to a different shader program, because whether a material is transparent is
## decided at shader COMPILE time (see unit_vat.gdshaderinc). PrimitiveUnit
## owns that choice; this function exists only so the call site above reads the
## same as it did before.
func _set_ghost_look(unit: PrimitiveUnit, is_ghost: bool) -> void:
	unit.set_ghost(is_ghost)


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
##
## Its geometry — and every other HUD element's — comes from `HudLayout`
## against the CURRENT window, not from constants written for one window
## size. See that file for what the literals used to be and what they cost.
var _resource_bar: Panel = null
var _resource_labels: Array[Label] = []
## The four resource swatches, kept so they can be re-placed on a resize.
var _resource_swatches: Array[ColorRect] = []
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
## Formation/behaviour — the actions column's top segment.
var _action_buttons: Array[Button] = []
## Building — the actions column's bottom segment, visually split from
## `_action_buttons` by `_build_actions_divider`/`_build_actions_caption`
## (see `HudLayout.BUILD_DIVIDER_Y`'s doc comment for why). Buildings
## themselves never populate this — a building's own "what can I build"
## question is answered by the chip strip's Train tiles instead (see
## `_show_train_chips`), not by this segment.
var _build_action_buttons: Array[Button] = []
var _build_actions: Array = []
var _build_actions_divider: ColorRect = null
var _build_actions_caption: Label = null

## Chips: one per squad, or — past `HudLayout.CHIP_COLLAPSE_THRESHOLD` — one
## per ARCHETYPE, in the middle of the wide selection panel (the reference
## design's synthesis, "chips ... in the live view"). Also doubles as the
## building-selected panel's "Train" tile row, which is the same shape of
## information (a name, a count/cost, a fraction) wearing a different
## label — see `_show_chips`.
const CHIP_POOL_SIZE := 16
var _chip_panels: Array[Panel] = []
var _chip_names: Array[Label] = []
var _chip_counts: Array[Label] = []
var _chip_bar_backs: Array[ColorRect] = []
var _chip_bar_fills: Array[ColorRect] = []
## Chip index -> archetype id, set only in "Train" mode (`_show_train_chips`)
## and empty otherwise, so `_on_chip_input` knows both WHETHER a click
## should do anything and WHAT it trains. Kept separate from the composition
## chips' own data because those are informational only — see `_show_chips`.
var _chip_train_ids: Array = []
## Shared between every chip — see `_build_chip_pool`'s doc comment on why
## a Panel needs this done by hand.
var _chip_style_normal: StyleBoxFlat = null
var _chip_style_hover: StyleBoxFlat = null
## Re-derived every resize by `_layout_chips`; read every frame by
## `_show_chips` to decide how many of the pool to show and where.
var _panel_rect := Rect2()
var _chip_strip_rect := Rect2()
var _chip_columns := 1

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

	# Size only. WHERE it goes is `_layout_hud`'s business, so there is one
	# answer to that question rather than two that have to agree.
	_minimap_size = Vector2(MINIMAP_WIDTH_PX, MINIMAP_WIDTH_PX * z_period / x_period)
	_layout_hud()
var _control_groups := {}

## The HUD's magnification (see `HudLayout.scale_for`). Applied as the
## CanvasLayer's transform, so anything drawn in the HUD from a MOUSE
## position — which arrives in real screen pixels — has to be divided by
## it first. `_to_hud` is that conversion and the only place it happens.
var _hud_scale := 1.0

var _hud_status: Label = null
var _hud_notice: Label = null
## The compass dial and the top bar's Menu button (D-063).
## The nav ring (compass + minimap merged — see `_build_nav_ring`): a
## backdrop disc, the minimap texture, and a frame drawn over both.
var _nav_ring_back: Control = null
var _nav_ring_frame: Control = null
## Absolute HUD-space bounds of the ring, the same convention
## `_minimap_bounds` uses — owned here rather than read off a Control's
## reported size, for the reason `_minimap_bounds` itself is (see its own
## doc comment).
var _nav_ring_bounds := Rect2()
## Crops `_minimap_rect`'s texture to a circle (see `_build_nav_ring`);
## its uniforms are kept in sync with the ring's geometry in `_layout_hud`.
var _minimap_crop_material: ShaderMaterial = null
var _menu_button: Button = null
## The in-game menu, and the settings pane inside it. Its own CanvasLayer
## above the HUD — and it never pauses anything, see `_toggle_game_menu`.
var _game_menu_layer: CanvasLayer = null
var _settings_panel: Control = null
## The defeat screen (see `_build_defeat_screen`/`_refresh_defeat`).
var _defeat_layer: CanvasLayer = null
var _defeat_time_label: Label = null
## Whether this player has ever had a living squad or building since the
## match left the lobby — guards against the one-frame race at match
## start, before the founding party's squad has arrived over the wire.
var _ever_had_army := false
var _defeated := false
var _defeat_time_held := 0.0
var _notice_seen := 0
var _notice_until := 0.0
var _building_nodes := {}
## wire id -> BuildingDef, cached alongside _building_nodes so the missile
## visual (see _refresh_buildings) doesn't re-load one from disk per frame.
var _building_defs := {}
## wire id -> float, how far to lift the mesh above the sampled ground so its
## base (not its centre) rests on it. 0.0 for an authored model, half the
## mesh's own height for the centred primitive fallback. See _refresh_buildings.
var _building_ground_lift := {}
## wire id -> float, how far ABOVE `instance.position` (already ground-lifted)
## the mesh's own top sits once fully grown — the mesh's full height for an
## authored model (position is its base), or half its height for the centred
## primitive fallback (position is already its centre). Used to float the
## health bar just above the roof regardless of which kind of mesh this is.
var _building_top_offset := {}
## Playtest fix (D-076 follow-up): "wire_id_a|wire_id_b" (sorted) -> a small
## vertical post MeshInstance3D bridging the visible gap where two adjacent
## wall-family segments meet at anything other than a straight 180-degree
## run. A single segment is a rigid straight prism (D-076) and cannot itself
## point at two neighbours that aren't opposite each other, so the joint is
## a separate piece rather than something either segment's own rotation can
## fix. Entries are only ever added, matching `_building_nodes`'s own
## never-freed-per-entry lifetime (see `_free_nodes` for the one place
## everything is torn down together).
var _wall_joint_nodes := {}
## wire id -> float in [0,1], the SHADER-FACING gate-open fraction, smoothed
## client-side toward the server's boolean `gate_open` at GATE_SWING_SECONDS
## — see the doc where this is written for why a boolean drove the shader
## directly before and read as the door not animating at all.
var _gate_visual_open := {}
const GATE_SWING_SECONDS := 0.8
## wire id -> { "back": MeshInstance3D, "fill": MeshInstance3D,
## "fraction": float } — the health bar drawn OVER a damaged building.
var _health_bars := {}
## A shade wider than the 2.4-wide box, so the bar reads as belonging to
## the building rather than as part of its roof.
const HEALTH_BAR_SIZE := Vector2(2.8, 0.34)
var _founded := false
var _selected_building := -1

## Playtest fix: the build menu's roster outgrew a flat list of buttons
## once D-076 added five wall-family defs to the three that existed
## before, so it now shows BuildingDef.category's tiers one at a time.
## "" means the category picker; otherwise one of BUILD_CATEGORIES' ids —
## see `_squad_build_actions`. Reset whenever the SELECTION changes (not
## every panel refresh, which runs every frame — see where
## `_build_menu_selection_key` is compared) so browsing "Defensive" for
## one squad doesn't silently carry over to an unrelated later selection.
var _build_menu_category: String = ""

## Sub-group within `_build_menu_category` (playtest fix): "" is that
## category's group picker, otherwise one of `_build_menu_group_of`'s ids.
## Cleared whenever the category changes, so backing out of "defensive"
## and into it again starts at the group picker rather than wherever you
## happened to be last time.
var _build_menu_group: String = ""
var _build_menu_selection_key: String = ""

## Minimap (D-027 criterion 5). Wrap-awareness is free here in a way it
## is nowhere else in this project: the minimap IS the whole torus, so a
## cell maps to a pixel directly and there is no seam to handle.
const MINIMAP_INTERVAL := 0.25
var _minimap_rect: TextureRect = null
## The minimap's SHAPE, from the map's proportions (see `_layout_minimap`).
## Its position comes from `_layout_hud` and lands in `_minimap_bounds`.
var _minimap_size := Vector2(MINIMAP_WIDTH_PX, MINIMAP_WIDTH_PX)
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
func _panel(rect: Rect2, colour: Color = HudTheme.BG_PANEL) -> Panel:
	var panel := Panel.new()
	var style := HudTheme.stylebox(colour, HudTheme.accent_border(0.45), 1, HudTheme.RADIUS_LG)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


## An outlined label. The map underneath is pale sand and dark forest in
## equal measure, so plain white is unreadable over half of it.
func _hud_label(at: Vector2, size := HudTheme.BODY_SIZE, colour := HudTheme.TEXT) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A labelled bar. Two sized ColorRects — a back and a fill — for the same
## reason `_panel` is not a PanelContainer.
func _bar(at: Vector2, width: float, colour: Color, height := 5.0) -> Array:
	var back := ColorRect.new()
	back.position = at
	back.size = Vector2(width, height)
	back.color = HudTheme.BORDER
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.position = at + Vector2(1.0, 1.0)
	fill.size = Vector2(width - 2.0, height - 2.0)
	fill.color = colour
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return [back, fill]


## Build the panel's children. Positions are placeholders — `_layout_hud`
## sets them all against the real window, and does so again on every
## resize.
func _build_selection_panel(layer: CanvasLayer) -> void:
	_selection_panel = _panel(Rect2(Vector2.ZERO, Vector2(HudLayout.REFERENCE.x, HudLayout.PANEL_HEIGHT)))
	layer.add_child(_selection_panel)

	_selection_title = _hud_label(Vector2.ZERO, HudTheme.TITLE_SIZE, HudTheme.TEXT_BRIGHT)
	layer.add_child(_selection_title)
	_selection_detail = _hud_label(Vector2.ZERO, HudTheme.MONO_SIZE, HudTheme.TEXT_FAINT)
	layer.add_child(_selection_detail)

	var bar_width := HudLayout.TITLE_COLUMN_WIDTH - HudLayout.PANEL_PAD * 2.0
	var health := _bar(Vector2.ZERO, bar_width, HudTheme.GOOD)
	_health_bar_back = health[0]
	_health_bar_fill = health[1]
	layer.add_child(_health_bar_back)
	layer.add_child(_health_bar_fill)

	var progress := _bar(Vector2.ZERO, bar_width, HudTheme.ACCENT_BRIGHT)
	_progress_bar_back = progress[0]
	_progress_bar_fill = progress[1]
	layer.add_child(_progress_bar_back)
	layer.add_child(_progress_bar_fill)
	_progress_caption = _hud_label(Vector2.ZERO, HudTheme.CAPTION_SIZE, HudTheme.TEXT_DIM)
	layer.add_child(_progress_caption)

	# The production queue, as one swatch per waiting unit. A count would
	# not show that four spearmen are stacked behind a militia.
	_queue_caption = _hud_label(Vector2.ZERO, HudTheme.CAPTION_SIZE, HudTheme.TEXT_GHOST)
	layer.add_child(_queue_caption)
	for i in range(8):
		var swatch := ColorRect.new()
		swatch.size = Vector2(14.0, 14.0)
		swatch.color = HudTheme.accent_wash(0.9)
		swatch.visible = false
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_queue_swatches.append(swatch)
		layer.add_child(swatch)

	_build_chip_pool(layer)

	# Two pools, not one: formation/behaviour (control) and building are
	# visually separate segments of the actions column (see
	# `HudLayout.BUILD_DIVIDER_Y`'s doc comment), each with its own
	# pooled, relabelled-not-rebuilt buttons for the reason every pool in
	# this HUD is — the selection changes constantly and churning Controls
	# in _process is how a frame budget goes.
	for i in range(6):
		var button := _build_action_button(i, _on_action_pressed)
		_action_buttons.append(button)
		layer.add_child(button)

	_build_actions_divider = ColorRect.new()
	_build_actions_divider.color = HudTheme.RULE
	_build_actions_divider.visible = false
	_build_actions_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_build_actions_divider)

	_build_actions_caption = _hud_label(Vector2.ZERO, HudTheme.CAPTION_SIZE - 1, HudTheme.TEXT_GHOST)
	_build_actions_caption.text = "BUILD"
	_build_actions_caption.visible = false
	layer.add_child(_build_actions_caption)

	# Playtest fix: sized to HudLayout.BUILD_ACTION_ROWS x ACTION_COLUMNS
	# (was a hardcoded 6 — one row short of what even the OLD flat build
	# list needed once D-076 added five wall-family defs, and PANEL_HEIGHT
	# didn't have room for a second row anyway). Now tiered by category
	# (see _squad_build_actions), so this is headroom over the actual
	# per-screen worst case, not a tight fit.
	for i in range(HudLayout.BUILD_ACTION_ROWS * HudLayout.ACTION_COLUMNS):
		var button := _build_action_button(i, _on_build_action_pressed)
		_build_action_buttons.append(button)
		layer.add_child(button)


## One action button — a formation/behaviour button and a build button are
## the same widget with a different click target, so this is the one place
## either pool's styling is written.
func _build_action_button(index: int, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.size = HudLayout.ACTION_BUTTON
	button.visible = false
	# Styled rather than left at Godot's default grey, which reads as
	# an unfinished editor widget sitting on top of the game.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = {
			"normal": Color(0.0, 0.0, 0.0, 0.0),
			"hover": HudTheme.accent_wash(0.16),
			"pressed": HudTheme.accent_wash(0.28),
			"disabled": Color(0.0, 0.0, 0.0, 0.0),
		}[state]
		style.border_color = HudTheme.accent_border(0.5) if state != "disabled" \
			else HudTheme.BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(HudTheme.RADIUS_SM)
		style.content_margin_left = 9.0
		style.content_margin_right = 4.0
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", HudTheme.TEXT_MUTED)
	button.add_theme_color_override("font_disabled_color", HudTheme.TEXT_DISABLED)
	button.add_theme_font_size_override("font_size", HudTheme.BODY_SIZE - 1)
	button.pressed.connect(on_pressed.bind(index))
	return button


## The chip pool — pooled and relabelled for the same reason the action
## buttons are (see above): a selection can change every tick, and a chip
## is common enough on screen (up to `CHIP_POOL_SIZE` of them, redrawn
## every frame the selection is non-empty) that churning Controls for it
## would be a real cost, not a theoretical one.
func _build_chip_pool(layer: CanvasLayer) -> void:
	# A Panel has no built-in hover state the way Button does — its
	# StyleBoxFlat is one fixed look regardless of the mouse. Making chips
	# clickable (see `_on_chip_input`) without also giving them a hover
	# response reads as a broken button: a control that takes clicks but
	# never visibly reacts to the cursor sitting over it. Swapped by hand
	# on `mouse_entered`/`mouse_exited` instead, and only while the chip is
	# actually clickable — a composition chip hovering into the accent
	# colour would promise an action that does not exist.
	_chip_style_normal = HudTheme.stylebox(
		HudTheme.BG_VOID.lightened(0.02), HudTheme.BORDER, 1, HudTheme.RADIUS_SM)
	_chip_style_hover = HudTheme.stylebox(
		HudTheme.accent_wash(0.14), HudTheme.accent_border(0.7), 1, HudTheme.RADIUS_SM)

	for i in range(CHIP_POOL_SIZE):
		var chip := Panel.new()
		chip.size = HudLayout.CHIP_SIZE
		chip.visible = false
		# STOP rather than IGNORE, and always connected: a chip only ever
		# receives a click while it is actually visible (a hidden Control
		# does not participate in hit-testing), and whether that click DOES
		# anything is gated by `_chip_train_ids` inside the handler, not by
		# swapping the filter per selection state.
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.gui_input.connect(_on_chip_input.bind(i))
		chip.mouse_entered.connect(_on_chip_hover.bind(i, true))
		chip.mouse_exited.connect(_on_chip_hover.bind(i, false))
		chip.add_theme_stylebox_override("panel", _chip_style_normal)
		_chip_panels.append(chip)
		layer.add_child(chip)

		var name_label := _hud_label(Vector2.ZERO, HudTheme.BODY_SIZE - 1, HudTheme.TEXT)
		name_label.clip_text = true
		# A long name ("Founding Party") hard-clipped mid-word read as a
		# broken/misaligned label rather than as a name that just didn't
		# fit — an ellipsis is the honest version of the same truncation.
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_chip_names.append(name_label)
		layer.add_child(name_label)

		var count_label := _hud_label(Vector2.ZERO, HudTheme.CAPTION_SIZE, HudTheme.TEXT_DIM)
		_chip_counts.append(count_label)
		layer.add_child(count_label)

		var chip_bar := _bar(Vector2.ZERO, HudLayout.CHIP_SIZE.x - 18.0, HudTheme.GOOD, 4.0)
		_chip_bar_backs.append(chip_bar[0])
		_chip_bar_fills.append(chip_bar[1])
		layer.add_child(chip_bar[0])
		layer.add_child(chip_bar[1])


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
	_resource_bar = _panel(Rect2(0.0, 0.0, HudLayout.REFERENCE.x, HudLayout.BAR_HEIGHT),
		HudTheme.BG_PANEL_SOFT)
	layer.add_child(_resource_bar)
	var kinds := [Economy.ResourceKind.FOOD, Economy.ResourceKind.WOOD,
		Economy.ResourceKind.GOLD, Economy.ResourceKind.STONE]
	var names := ["Food", "Wood", "Gold", "Stone"]
	for i in range(kinds.size()):
		var swatch := ColorRect.new()
		swatch.color = _node_colour(kinds[i])
		swatch.size = Vector2(HudLayout.RESOURCE_SWATCH_SIZE, HudLayout.RESOURCE_SWATCH_SIZE)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resource_swatches.append(swatch)
		layer.add_child(swatch)

		var value := _hud_label(Vector2.ZERO, HudTheme.BODY_SIZE, HudTheme.TEXT)
		value.text = "%s —" % names[i]
		_resource_labels.append(value)
		layer.add_child(value)

	# Right-aligned against the window's edge rather than left at a fixed
	# x, so it neither collides with the stone count on a narrow window nor
	# strands itself mid-bar on a wide one.
	_hud_status = _hud_label(Vector2.ZERO, HudTheme.MONO_SIZE, HudTheme.TEXT_MUTED)
	_hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(_hud_status)

	# Notices sit under the bar, in the middle, where a refusal is
	# actually noticed. In the corner they were routinely missed. Centred
	# by spanning the window and centring the text — the previous fixed x
	# was only centred on the one window size it was written for.
	_hud_notice = _hud_label(Vector2.ZERO, HudTheme.BODY_SIZE, HudTheme.WARNING)
	_hud_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hud_notice)

	_build_selection_panel(layer)

	_selection_rect = ColorRect.new()
	_selection_rect.color = HudTheme.accent_wash(0.18)
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
		bar.color = HudTheme.ACCENT_BRIGHT
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
	_minimap_rect = TextureRect.new()
	_minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Nearest-neighbour: one cell is one pixel, and smoothing it would
	# blur the squad dots into the terrain they sit on.
	_minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_nav_ring(layer)
	_build_menu_button(layer)

	# Place everything against the real window, and keep doing so. Without
	# the signal the HUD is correct exactly until someone presses F11.
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()


## The nav ring: the compass dial and the minimap MERGED into one widget
## (the reference design's chosen synthesis — "compass on the minimap
## ring"), which used to be two unrelated Controls in two different
## corners.
##
## Drawn in three layers, added as siblings in this exact order so Godot's
## draw order (parent, then children/later-siblings, on top) does what a
## painter would: a dark disc backdrop, the minimap's own texture over
## that (visually CROPPED to a circle by `_minimap_crop_material`, so it
## reads as sitting inside the ring rather than a rectangle floating
## behind it), and the rim + cardinal letters + needle over both.
##
## The crop is a MASK, not a squash: `shaders/circular_crop.gdshader`
## hides pixels outside a circle at the map's own unchanged scale, rather
## than stretching a non-square map to fill one — the distortion this
## project already spent an afternoon fixing once elsewhere stays fixed.
## What is lost is peripheral map content the circle doesn't reach, which
## is the trade a player explicitly asked for over the alternative (a
## rectangular minimap poking past its own frame).
##
## Input is handled the same way the minimap's always has been — a raw
## screen-position check against a stored bounds Rect2 in
## `_handle_mouse_button`, not Godot's gui_input routing — because the two
## widgets' hit regions now overlap (the rim surrounds the minimap) and a
## `MOUSE_FILTER_STOP` control covering both would swallow minimap clicks
## meant to jump the camera. See `_clicked_ring_rim`. The click hit-test
## still uses `_minimap_bounds` (the map's own rect) unchanged — the crop
## is cosmetic and does not shrink the clickable/jump-to area.
func _build_nav_ring(layer: CanvasLayer) -> void:
	_nav_ring_back = Control.new()
	_nav_ring_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav_ring_back.draw.connect(_draw_nav_ring_back)
	layer.add_child(_nav_ring_back)

	_minimap_crop_material = ShaderMaterial.new()
	_minimap_crop_material.shader = preload("res://shaders/circular_crop.gdshader")
	_minimap_rect.material = _minimap_crop_material
	layer.add_child(_minimap_rect)

	_nav_ring_frame = Control.new()
	_nav_ring_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav_ring_frame.draw.connect(_draw_nav_ring_frame)
	layer.add_child(_nav_ring_frame)


## The dark disc the minimap and its rim sit on. Its own draw call (rather
## than just letting the 3D view show through) because a map that does not
## fill a full circle — true of most maps, which are wider than they are
## tall — would otherwise leave the ring looking like a rendering bug
## rather than a frame.
func _draw_nav_ring_back() -> void:
	var r := _nav_ring_back.size.x * 0.5
	_nav_ring_back.draw_circle(Vector2(r, r), r, HudTheme.BG_PANEL)


## The border band and the cardinal letters. The ring TURNS and the
## cardinal letters with it — "up the screen" is always the direction the
## camera is currently facing, and the letters swing around that fixed
## point rather than the other way round.
##
## That is the correct way round and worth stating, because the other way
## is an easy mistake to make and looks almost right: a compass answers
## "which way am I facing", so the WORLD's north moves around the dial
## while the direction you are looking stays fixed at the top. A dial with
## fixed letters and a spinning needle instead is a magnetic compass,
## which is a different instrument answering a different question — this
## one used to also draw that needle (a fixed vertical line, since "up the
## screen" never moves) alongside the turning letters, and dropped it on
## request; the letters alone already carry the same information.
##
## The band is a thick coloured arc, not a hairline — its INNER edge is
## exactly `HudLayout.ring_crop_radius`, the same radius the minimap is
## cropped to (see `_build_nav_ring`), so the map and its frame meet with
## no gap and no overlap. The cardinal letters sit at the band's own
## midline, inside that coloured ring rather than floating over whatever
## happens to be behind them.
func _draw_nav_ring_frame() -> void:
	var r := _nav_ring_frame.size.x * 0.5
	var centre := Vector2(r, r)
	var crop_r := HudLayout.ring_crop_radius(_nav_ring_frame.size.x)
	var band_width := (r - 1.0) - crop_r
	var band_radius := crop_r + band_width * 0.5

	_nav_ring_frame.draw_arc(centre, band_radius, 0.0, TAU, 96,
		HudTheme.accent_wash(0.92), band_width, true)
	_nav_ring_frame.draw_arc(centre, r - 1.0, 0.0, TAU, 96,
		HudTheme.ACCENT_BRIGHT, 1.5, true)

	# North on the dial. Screen y grows downward while world +z does too,
	# and the camera sits at +z looking back toward its target — so the
	# world direction the player is facing appears UP the screen, and north
	# lands at -yaw from vertical.
	var font := ThemeDB.fallback_font
	var size := HudTheme.TITLE_SIZE - 3
	for i in range(4):
		var label: String = ["N", "E", "S", "W"][i]
		var at := centre + HudLayout.compass_offset(_camera_yaw, i, band_radius)
		var measured := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		# Dark on the band's own warm colour, not light — the band reads as
		# a solid amber ring, and the light tint every other label on this
		# HUD uses would wash out against it. North stays picked out bright
		# so it is still the one letter that reads at a glance.
		var tint := HudTheme.TEXT_BRIGHT if label == "N" else HudTheme.BG_VOID
		_nav_ring_frame.draw_string(font, at - Vector2(measured.x * 0.5, -measured.y * 0.35),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)


## Whether a screen position landed on the ring's decorative rim — inside
## its circle, but outside the minimap rect it frames. Kept separate from
## `_minimap_cell_at` so the two hit regions, which now overlap, cannot be
## confused for one another (see `_build_nav_ring`'s doc comment).
func _clicked_ring_rim(screen_position: Vector2) -> bool:
	if _nav_ring_bounds.size.x <= 0.0:
		return false
	var at := _to_hud(screen_position)
	var centre := _nav_ring_bounds.position + _nav_ring_bounds.size * 0.5
	if at.distance_to(centre) > _nav_ring_bounds.size.x * 0.5:
		return false
	return not _minimap_bounds.has_point(at)


## The Menu button, at the right end of the top bar.
func _build_menu_button(layer: CanvasLayer) -> void:
	_menu_button = _styled_button("Menu", HudTheme.NEUTRAL)
	_menu_button.add_theme_font_size_override("font_size", 13)
	_menu_button.pressed.connect(_toggle_game_menu)
	layer.add_child(_menu_button)


## Place every HUD element against the CURRENT window.
##
## Called on build and on every resize. The arithmetic lives in
## `HudLayout`, which is pure and tested; this function only reads the
## viewport and assigns what comes back.
##
## Scale is applied as the CanvasLayer's TRANSFORM rather than by adjusting
## font sizes and widths one at a time — one multiplication carries the
## borders, the fonts, the button padding and the bar thicknesses together,
## and none of them can be forgotten.
func _layout_hud() -> void:
	if _hud_layer == null or _resource_bar == null:
		return

	var viewport := get_viewport().get_visible_rect().size
	# A player's explicit choice wins over the automatic fit (D-063). Zero
	# means they never made one.
	_hud_scale = _hud_scale_override if _hud_scale_override > 0.0 \
		else HudLayout.scale_for(viewport)
	_hud_layer.transform = Transform2D().scaled(Vector2(_hud_scale, _hud_scale))
	if _lobby_layer != null:
		_lobby_layer.transform = _hud_layer.transform

	# Design space is the window divided by the scale ACTUALLY applied
	# above, not by the automatic one — with an override in force those two
	# differ, and using the automatic figure would lay the HUD out for a
	# window shape that is not on screen.
	var design := Vector2(maxf(viewport.x, 1.0), maxf(viewport.y, 1.0)) / _hud_scale
	_layout_lobby(design)
	var at := HudLayout.compute(design, _minimap_size)

	var bar: Rect2 = at["resource_bar"]
	_resource_bar.position = bar.position
	_resource_bar.size = bar.size
	# Centred on the font's own measured height, not a hand-tuned pixel
	# offset — a magic number here is exactly what went stale and read as
	# "header items not aligned" the last time BODY_SIZE changed and
	# nothing here followed it.
	var label_height := ThemeDB.fallback_font.get_height(HudTheme.BODY_SIZE)
	for i in range(_resource_swatches.size()):
		var slot := HudLayout.resource_slot(i)
		_resource_swatches[i].position = slot
		_resource_labels[i].position = Vector2(
			slot.x + HudLayout.RESOURCE_SWATCH_SIZE + 8.0,
			slot.y + HudLayout.RESOURCE_SWATCH_SIZE * 0.5 - label_height * 0.5)

	var status: Rect2 = at["status"]
	_hud_status.position = status.position
	_hud_status.size = status.size

	var menu: Rect2 = at["menu_button"]
	_menu_button.position = menu.position
	_menu_button.size = menu.size

	# `_nav_ring_bounds` stays the ONE definition of where the ring is, the
	# same reason `_minimap_bounds` is (see its doc comment) — it is also
	# the hit-test rect `_clicked_ring_rim` reads.
	_nav_ring_bounds = at["ring"]
	_nav_ring_back.position = _nav_ring_bounds.position
	_nav_ring_back.size = _nav_ring_bounds.size
	_nav_ring_back.queue_redraw()
	_nav_ring_frame.position = _nav_ring_bounds.position
	_nav_ring_frame.size = _nav_ring_bounds.size
	_nav_ring_frame.queue_redraw()

	var notice: Rect2 = at["notice"]
	_hud_notice.position = notice.position
	_hud_notice.size = notice.size

	_panel_rect = at["panel"]
	_selection_panel.position = _panel_rect.position
	_selection_panel.size = _panel_rect.size

	var title_col := HudLayout.title_column_rect(_panel_rect)
	var pad := title_col.position + Vector2(HudLayout.PANEL_PAD, 0.0)
	_selection_title.position = pad + Vector2(0.0, HudLayout.TITLE_Y)
	_selection_title.size = Vector2(title_col.size.x - HudLayout.PANEL_PAD * 2.0, 20.0)
	_selection_detail.position = pad + Vector2(0.0, HudLayout.DETAIL_Y)
	_selection_detail.size = _selection_title.size
	_place_bar(_health_bar_back, _health_bar_fill, pad + Vector2(0.0, HudLayout.HEALTH_Y))
	_place_bar(_progress_bar_back, _progress_bar_fill, pad + Vector2(0.0, HudLayout.PROGRESS_Y))
	_progress_caption.position = pad + Vector2(0.0, HudLayout.PROGRESS_CAPTION_Y)
	_queue_caption.position = pad + Vector2(0.0, HudLayout.QUEUE_CAPTION_Y)
	for i in range(_queue_swatches.size()):
		# To the right of the queue caption's own text, not below it — the
		# title column has no spare row left underneath (see the const's
		# neighbouring comment in hud_layout.gd for the budget this fits).
		_queue_swatches[i].position = pad + Vector2(
			70.0 + float(i) * HudLayout.QUEUE_SWATCH_PITCH, HudLayout.QUEUE_SWATCH_Y - 1.0)

	var actions_col := HudLayout.actions_column_rect(_panel_rect)
	for i in range(_action_buttons.size()):
		_action_buttons[i].position = actions_col.position + HudLayout.action_slot(i)

	var divider := HudLayout.build_divider_rect()
	_build_actions_divider.position = actions_col.position + divider.position
	_build_actions_divider.size = divider.size
	_build_actions_caption.position = actions_col.position \
		+ Vector2(HudLayout.PANEL_PAD, HudLayout.BUILD_CAPTION_Y)
	for i in range(_build_action_buttons.size()):
		_build_action_buttons[i].position = actions_col.position + HudLayout.build_slot(i)

	_layout_chips()

	# `_minimap_bounds` stays the ONE definition of where the minimap is,
	# because it is also the hit-test rect — reading the size back off the
	# TextureRect once made the whole screen behave as minimap. The crop
	# shader is purely cosmetic and does not touch this rect, so clicking
	# still works out to the map's full (uncropped) extent.
	_minimap_bounds = at["minimap"]
	_minimap_rect.position = _minimap_bounds.position
	_minimap_rect.size = _minimap_bounds.size
	_minimap_rect.custom_minimum_size = _minimap_bounds.size

	if _minimap_crop_material != null:
		var crop_r := HudLayout.ring_crop_radius(_nav_ring_bounds.size.x)
		var ring_centre := _nav_ring_bounds.position + _nav_ring_bounds.size * 0.5
		_minimap_crop_material.set_shader_parameter("rect_size", _minimap_bounds.size)
		_minimap_crop_material.set_shader_parameter("centre_px",
			ring_centre - _minimap_bounds.position)
		_minimap_crop_material.set_shader_parameter("radius_px", crop_r)


## Size the lobby to fill the design-space rect, explicitly — NOT with
## anchors.
##
## Anchors on a Control with no Control ancestor resolve against the real,
## UNSCALED viewport rect. `_lobby_layer` then scales everything inside it
## again on top of that (the same transform `_hud_layer` gets, synced
## above). Anchoring `_lobby_root` to "fill the parent" therefore sizes it
## to the real window, and the CanvasLayer's transform shrinks that
## AGAIN — so it only happens to reach the window's true edges when the
## scale is exactly 1.0 (a 1280x720 window), and falls short at every
## other size. Explicit position/size against `design` — the same
## viewport-divided-by-scale space `HudLayout.compute` already lays the
## HUD out against — is what makes the two scalings cancel out instead of
## compounding.
func _layout_lobby(design: Vector2) -> void:
	if _lobby_backdrop == null:
		return
	_lobby_backdrop.size = design
	_lobby_root.position = LOBBY_MARGIN
	_lobby_root.size = Vector2(
		maxf(design.x - LOBBY_MARGIN.x * 2.0, 0.0),
		maxf(design.y - LOBBY_MARGIN.y * 2.0, 0.0))


## Where the chip strip (see `_build_chip_pool`) sits, and how many columns
## it has — both re-derived on every resize, since the strip's width (and
## therefore its column count) depends on the window.
func _layout_chips() -> void:
	_chip_strip_rect = HudLayout.chip_strip_rect(_panel_rect)
	_chip_columns = HudLayout.chip_columns(_chip_strip_rect.size.x)
	var label_width := HudLayout.CHIP_SIZE.x - 16.0
	# Measured from the font's own metrics, not hand-tuned pixel offsets —
	# CHIP_SIZE grew when the fonts did (task 12) and this did not follow,
	# which is what read as "alignment on the button is bad": the name
	# label's box was shorter than its own 15px font's line height, so
	# `clip_text` was cutting it. The resource bar had the identical bug
	# for the identical reason; this is the same fix.
	var name_height := ThemeDB.fallback_font.get_height(HudTheme.BODY_SIZE - 1)
	var count_height := ThemeDB.fallback_font.get_height(HudTheme.CAPTION_SIZE)
	var name_y := 8.0
	var count_y := name_y + name_height + 2.0
	var bar_y := count_y + count_height + 5.0
	for i in range(_chip_panels.size()):
		var chip_at := _chip_strip_rect.position + HudLayout.chip_slot(i, _chip_columns)
		_chip_panels[i].position = chip_at
		_chip_panels[i].size = HudLayout.CHIP_SIZE
		_chip_names[i].position = chip_at + Vector2(8.0, name_y)
		# `clip_text` needs an explicit size to clip TO — without one a
		# Label defaults to zero-size and clips its text to nothing, which
		# read as a chip with a cost or count on it but no name at all.
		_chip_names[i].size = Vector2(label_width, name_height)
		_chip_counts[i].position = chip_at + Vector2(8.0, count_y)
		_chip_counts[i].size = Vector2(label_width, count_height)
		_place_bar(_chip_bar_backs[i], _chip_bar_fills[i], chip_at + Vector2(8.0, bar_y))


## Move a two-piece bar, keeping the fill's 1px inset. Its WIDTH is set by
## `_set_bar` from whatever fraction it is showing, so this must not touch
## it — doing so would silently reset every bar to full on a resize.
func _place_bar(back: ColorRect, fill: ColorRect, at: Vector2) -> void:
	back.position = at
	fill.position = at + Vector2(1.0, 1.0)


## A real screen position in HUD coordinates.
##
## Godot routes input through a CanvasLayer's transform for Controls by
## itself, so buttons need none of this. It is only for the places that do
## their own pixel arithmetic against HUD geometry — the minimap hit-test
## and the drag box — which the engine cannot know about.
func _to_hud(at: Vector2) -> Vector2:
	return at / maxf(_hud_scale, 0.0001)


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
	# D-076. L/K/G/F/U avoid WASD (camera pan), Q/E (camera yaw) and every
	# existing BUILD_KEYS/TRAIN_KEYS letter.
	"L": &"wall", "K": &"gate", "G": &"garrison_wall", "F": &"garrison_gate",
	"U": &"wall_tower",
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


# --- resource nodes as forests --------------------------------------

## Cells per side of a tree chunk. With trees at roughly one per four
## cells (Economy's forest densities), one MeshInstance3D per tree would
## put thousands of Node3Ds in the scene — so trees batch into one
## MultiMesh per (chunk, model) instead, the same instancing idea
## PrimitiveUnit uses per squad (D-009), chunked so Godot's frustum
## culling still discards the forests behind the camera.
const NODE_CHUNK := 16

## chunk key (cell region) -> { "root": Node3D, "centre": Vector3,
##   "multis": {model_id: MultiMeshInstance3D},
##   "cells": {cell: {"model": StringName, "xform": Transform3D}},
##   "dirty": bool }
## The root is repositioned every frame to the lattice copy nearest the
## camera (D-035) — per CHUNK, not per tree, which is what keeps the
## torus tax off the per-tree path.
var _tree_chunks := {}

## cell -> {"chunk": Vector2i, "world": Vector3, "model": StringName,
## "kind": int} — the reverse index the click test and the felling read.
var _node_placed := {}

## Fellings mid-animation: {"node": MeshInstance3D, "kind": int,
## "cell": int, "age": float, "base": Transform3D}. A felled tree leaves
## its chunk's MultiMesh and becomes a short-lived individual instance —
## the one moment a tree is worth a node of its own.
var _fallings := []

## kind -> the primitive stand-in mesh used when the art build is missing
## (model_id resolves to no file). Cached: one mesh per kind serves every
## such node through the MultiMesh path.
var _node_fallback_meshes := {}

## The generator the terrain meshes were built from, kept so tree species
## can follow the same ground (ResourceVisuals reads biome and moisture
## from it). Same instance, so the dressing cannot disagree with the
## drawn terrain.
var _terrain_gen: TerrainGen = null

## Per-soldier render easing (D-059). Client-only, one-way, never read
## back by anything authoritative — see soldier_motion.gd's header for
## exactly where that line sits.
var _motion := SoldierMotion.new()

## This frame's delta, so the render path can ease at a framerate-
## independent rate without every function taking a delta parameter.
var _frame_delta := 0.0


## Every live squad's position and owner, rebuilt ONCE per frame.
##
## The first version scanned `_state.composition` inside a per-squad
## helper, and called that helper twice per visible squad — so a hundred
## visible squads against a thousand known ones was 200,000 dictionary
## walks and curve samples a frame, to decide an animation.
##
## That is the fifth appearance of one defect in this project: a lookup
## that belongs outside a loop, sitting inside it. After `distance()` per
## cell in vision (232 -> 15 µs/squad), `UnitRoster.by_id` per produced
## squad (858 ms in one tick), terrain noise per soldier per frame, and a
## BuildingDef resolved per building per frame. Hoisting it is the fix
## every time.
var _enemy_scan: Array = []
var _enemy_scan_at := -1.0


func _refresh_enemy_scan() -> void:
	if is_equal_approx(_enemy_scan_at, _now):
		return
	_enemy_scan_at = _now
	_enemy_scan = []
	for id in _state.composition:
		if _state.alive_of(id) <= 0 or not _state.curves.has(id):
			continue
		_enemy_scan.append({
			"owner": int(_state.composition[id].get("owner", -2)),
			"at": _state.squad_world_position(id, _now),
		})


## What a squad is visibly DOING and what it is leaning toward, from state
## the client already has (D-059).
##
## No new protocol: `shape` is replicated and tells us a crew is working a
## node (D-058), and enemy squads in vision tell us who is fighting.
## Returned together because finding the enemy is the expensive half and
## asking twice was doing it twice.
func _activity_for(squad_id) -> Dictionary:
	var idle := {
		"activity": CosmeticOffset.Activity.IDLE, "toward": Vector3.ZERO,
		"is_ranged": false, "interval": 0.0,
	}
	var info: Dictionary = _state.composition.get(squad_id, {})
	if info.is_empty() or _state.space == null:
		return idle

	# A gathering crew rings its node, and that shape reaches us over the
	# wire — so "is this crew working?" needs nothing new. The node is
	# under the crew's own centre, so leaning inward IS leaning at it.
	if String(info.get("shape", "")) == "ring":
		return {
			"activity": CosmeticOffset.Activity.WORKING,
			"toward": _state.squad_world_position(squad_id, _now),
			"is_ranged": false, "interval": 0.0,
		}

	var def := UnitRoster.by_id(StringName(String(info.get("def_id", ""))))
	if def == null or def.damage <= 0.0:
		return idle

	_refresh_enemy_scan()
	var here := _state.squad_world_position(squad_id, _now)
	var mine := int(info.get("owner", -1))
	var best_distance := def.attack_range
	var toward := Vector3.ZERO
	for entry in _enemy_scan:
		if int(entry["owner"]) == mine:
			continue
		var d := here.distance_to(entry["at"])
		if d < best_distance:
			best_distance = d
			toward = entry["at"]
	if toward == Vector3.ZERO:
		return idle
	# `armour_class == "missile"` is the shipped-data gate for "ranged" —
	# see UnitDef's header on the field: a squad's cadence toward the arrow
	# visual is its own attack_interval, the same value the server gates
	# real shots on, even though the shot itself is never named on the wire.
	return {
		"activity": CosmeticOffset.Activity.FIGHTING, "toward": toward,
		"is_ranged": def.armour_class == "missile", "interval": def.attack_interval,
	}


## Arrow visuals for ranged attacks (squads and buildings alike). Purely
## cosmetic and entirely client-inferred, the same way `_activity_for`
## above infers "fighting" with zero protocol changes: combat.gd never
## names an individual shot (see its header — `resolve()` returns only a
## squad-level alive/routed diff), so there is no wire event to draw one
## from. Instead each ranged attacker gets an arrow launched at its own
## attack_interval while it has a target in range, which tracks the real
## firing rate without claiming to reproduce it exactly.

## Each entry: {"node": MeshInstance3D, "from": Vector3, "to": Vector3,
## "start": float, "duration": float}.
var _missiles: Array = []
## Source key ("squad:<id>" / "building:<wire id>") -> the `_now` before
## which another launch from that key is suppressed.
var _missile_next_launch := {}
var _arrow_mesh: Mesh = null
var _arrow_material: Material = null

const MISSILE_SPEED := 16.0
const MISSILE_ARC_HEIGHT := 1.4
const MISSILE_RELEASE_HEIGHT := 1.6
const MISSILE_IMPACT_HEIGHT := 0.8


## Where an arrow leaves or lands: sampled terrain height (the same
## sampler buildings use to sit on the ground rather than float or sink)
## plus a fixed release/impact height so it reads as chest-height, not
## ankle-height.
func _missile_ground(world: Vector3, extra_height: float) -> Vector3:
	var out := world
	if _state.terrain_sampler.is_valid():
		out.y = _state.terrain_sampler.call(world.x, world.z)
	out.y += extra_height
	return out


## The on-screen landing point for a shot toward `to_canonical`, given the
## shooter's own canonical position `from_canonical` and its already-chosen
## render position `from_render` (D-045's per-frame lattice-copy pick).
##
## Squads and buildings near a seam can be geometrically close while
## numerically far apart in canonical (wrapped) world space — D-008's
## recurring wrap tax. `TorusSpace.world_delta` gives the shortest vector
## between the two CELLS, which is short whenever the shot itself is
## (every shipped attack_range is under ten world units), so adding it to
## the shooter's render position keeps the arrow on the same lattice copy
## the shooter is drawn at instead of flying off toward a different one.
func _missile_landing(from_render: Vector3, from_canonical: Vector3, to_canonical: Vector3) -> Vector3:
	var space := _state.space
	var wrap_delta := space.world_delta(
		space.world_to_cell(from_canonical), space.world_to_cell(to_canonical))
	return from_render + wrap_delta


## Built once and reused (the usual reason, D-045: rebuilding a mesh per
## shot is a per-frame cost for an effect that fires far less than once a
## frame). Flat and pointing +Z at rest, so it can be yawed exactly the way
## `formation.gd` yaws a soldier to face its heading: `angle =
## atan2(dir.x, dir.z)` into `Basis(Vector3.UP, angle)` / `rotation.y`.
func _arrow_visual() -> Array:
	if _arrow_mesh == null:
		const HALF_WIDTH := 0.05
		const HEAD_HALF_WIDTH := 0.16
		const SHAFT_END := 0.15
		const TIP := 0.5
		const TAIL := -0.5

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(-HALF_WIDTH, 0.0, TAIL)
		var b := Vector3(HALF_WIDTH, 0.0, TAIL)
		var c := Vector3(HALF_WIDTH, 0.0, SHAFT_END)
		var d := Vector3(-HALF_WIDTH, 0.0, SHAFT_END)
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
		var head_left := Vector3(-HEAD_HALF_WIDTH, 0.0, SHAFT_END)
		var head_right := Vector3(HEAD_HALF_WIDTH, 0.0, SHAFT_END)
		var tip := Vector3(0.0, 0.0, TIP)
		st.add_vertex(head_left); st.add_vertex(tip); st.add_vertex(head_right)
		st.generate_normals()
		_arrow_mesh = st.commit()

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.82, 0.68, 0.36)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_arrow_material = material
	return [_arrow_mesh, _arrow_material]


## Launches an arrow flying from `from` to `to`, unless `key` already fired
## within its own `interval` — the client's only substitute for a real
## per-shot event (see the header comment above `_missiles`).
func _maybe_launch_missile(key: String, from: Vector3, to: Vector3, interval: float) -> void:
	var next := float(_missile_next_launch.get(key, 0.0))
	if _now < next:
		return
	_missile_next_launch[key] = _now + maxf(interval, 0.1)

	var visual := _arrow_visual()
	var instance := MeshInstance3D.new()
	instance.mesh = visual[0]
	instance.material_override = visual[1]
	add_child(instance)

	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() > 0.0001:
		instance.rotation.y = atan2(flat.x, flat.z)

	var duration := maxf(from.distance_to(to) / MISSILE_SPEED, 0.1)
	_missiles.append({
		"node": instance, "from": from, "to": to,
		"start": _now, "duration": duration,
	})


## Advances every in-flight arrow and frees the ones that have landed. The
## parabolic height bump is not a real trajectory, just decoration — but a
## straight slide along the ground reads as sliding, not flying.
func _update_missiles() -> void:
	var i := _missiles.size() - 1
	while i >= 0:
		var shot: Dictionary = _missiles[i]
		var node: MeshInstance3D = shot["node"]
		var t := (_now - float(shot["start"])) / float(shot["duration"])
		if t >= 1.0:
			node.queue_free()
			_missiles.remove_at(i)
			i -= 1
			continue
		var from: Vector3 = shot["from"]
		var to: Vector3 = shot["to"]
		var pos := from.lerp(to, t)
		pos.y += sin(t * PI) * MISSILE_ARC_HEIGHT
		node.position = pos
		i -= 1


## The building armed for placement, or "" — a ghost of it follows the
## cursor until you click the ground or cancel.
var _placing: StringName = &""
var _placement_ghost: MeshInstance3D = null

## Pool of ghost boxes previewing a drag-to-build-a-line's whole line
## (D-076 amendment), one per cell it will actually build. A pool rather
## than freeing/recreating each frame: the line's length changes every
## frame the mouse moves, and churning nodes at that rate is exactly the
## "rebuild every frame" cost `_refresh_lobby`'s own signature-hash guard
## exists to avoid elsewhere.
var _drag_ghost_pool: Array[MeshInstance3D] = []

## Facing for the armed placement (D-076 amendment) — one of
## `TorusSpace.DIRECTIONS`' 6 indices, cycled with the rotate key for
## ANY building, not just an access tower's door. Purely cosmetic mesh
## rotation for most buildings; mechanically the door direction for
## `wall_tower` specifically.
var _placing_facing: int = 0
var _door_marker: MeshInstance3D = null

## Continuous facing (0-255, see `PlacementJitter.yaw_byte`/`radians_of_byte`)
## for a FREESTANDING building's placement — the scroll-wheel-controlled
## counterpart to `_placing_facing` above, which stays 6-way for a wall
## segment or the access tower. -1 means "the player hasn't scrolled yet
## this placement" — the ghost and the eventual build order both fall back
## to `PlacementJitter.yaw_byte` of the target cell in that case, so a
## player who never touches the wheel still gets a building that isn't
## dead-on one of 6 angles, just an automatic one instead of a chosen one.
## Reset to -1 whenever a fresh placement is armed (`_build_selected`) or
## cancelled (`_cancel_placement`).
var _placing_free_facing: int = -1

## Snap state for a wall-family placement (D-076 amendment): the cell the
## ghost last snapped to, so `_placing_facing` is only auto-set the moment
## the snap target CHANGES rather than every single frame — otherwise it
## would fight a manual V-key rotation on the very next frame. Reset to
## (-1,-1) whenever nothing is currently snapped, or a fresh placement is
## armed.
var _last_snap_cell := Vector2i(-1, -1)

## Click-drag-to-build-a-line state (D-076 amendment). A wall-family
## building (`footprint_radius == 0`) starts a drag on mouse-down instead
## of placing immediately; release decides whether it was a click (one
## segment, at the drag START cell) or a genuine drag (the whole line
## from start to release, split across every eligible selected squad).
var _placing_drag := false
var _placing_drag_start := Vector2i(-1, -1)

## The drag's start in WORLD space (D-096). `_placing_drag_start` above is
## still the cell it fell in — the snap logic and a few UI checks want that
## — but a wall run is laid between two continuous points now, and rounding
## the start to a cell centre first would throw away the sub-cell precision
## free placement is entirely about. Non-finite while no drag is active.
var _placing_drag_start_world := Vector3.INF

## An armed building (wire id, or -1) waiting for a click to name its
## focus-fire target — the "Target" button's arming half, mirroring
## `_placing` above. Shift+right-click on an enemy with the building
## already selected skips this entirely and sends the order directly
## (see `_order_selected`); this is only for the button-driven path.
var _targeting_building := -1

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
## How long a confirmed build site stays marked. Long enough to watch a
## builder set off toward it, short enough that a drag-built wall run does
## not leave a trail of discs across the map for the rest of the match.
const BUILD_MARKER_SECONDS := 9.0

## Sites this client has ASKED for: [{"pos": Vector3, "radius": float,
## "at": float}]. Client-only and advisory — the server may refuse any of
## them (D-002), which is precisely why they expire on a timer rather than
## waiting for a confirmation that may never come.
var _build_markers: Array = []
var _build_marker_nodes: Array[MeshInstance3D] = []


## Remember that a build was requested here, so the ground shows it.
##
## The gap this closes: a build order is silent until the builder arrives
## and the foundation appears, which for a distant site is many seconds of
## nothing happening — indistinguishable from a misclick. Marking the spot
## at the moment the order goes out makes "I asked for that" visible
## immediately.
##
## Deliberately recorded when the order is SENT rather than when the server
## acknowledges: this is feedback about the player's own input, and input
## that waits for a round trip before acknowledging itself feels broken
## even when it is working.
func _note_build_site(cell: Vector2i, offset: Vector2, def: BuildingDef,
		angle: float) -> void:
	if _state.space == null:
		return
	var world := _state.space.to_world(cell) + Vector3(offset.x, 0.0, offset.y)
	if _state.terrain_sampler.is_valid():
		world.y = _state.terrain_sampler.call(world.x, world.z)
	# The building's REAL footprint — its own length and depth, at its own
	# angle, on the exact spot it will stand. A generic disc on the cell
	# was the first version and it was close to useless: a wall run marked
	# with circles told you neither which way the wall would run nor that
	# the gate was wider than its neighbours, which is most of what you
	# want to check BEFORE committing a line of them.
	var size := Vector2(1.8, 1.8)
	if def != null:
		if def.mesh_size != Vector3.ZERO:
			size = Vector2(def.mesh_size.x, def.mesh_size.z)
		else:
			# The primitive-tier defs carry no mesh_size; footprint_radius
			# is what the no-build claim uses, so it is the honest stand-in.
			var span := maxf(1.0, float(def.footprint_radius)) * 1.9
			size = Vector2(span, span)
	_build_markers.append({"pos": world, "size": size, "angle": angle, "at": _now})


## Draw and expire the build-site marks. Same pooled-node lifetime as the
## selection rings above (never freed per entry, only hidden), and the same
## flat-disc-on-the-ground look so the two read as one visual language.
func _refresh_build_markers() -> void:
	# Drop expired entries first, so the pool below only ever sees live
	# ones and the array cannot grow without bound over a long match.
	var live := []
	for marker in _build_markers:
		if _now - float(marker["at"]) < BUILD_MARKER_SECONDS:
			live.append(marker)
	_build_markers = live

	while _build_marker_nodes.size() < _build_markers.size():
		# A flat SLAB, not a disc: it stands in for a rectangular building,
		# so it has to be able to be longer than it is wide and to point
		# somewhere. Unit-sized and scaled per marker below, so one mesh
		# serves every footprint.
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, 0.04, 1.0)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = material
		_build_marker_nodes.append(node)
		add_child(node)

	for i in range(_build_marker_nodes.size()):
		var node := _build_marker_nodes[i]
		if i >= _build_markers.size():
			node.visible = false
			continue
		var marker: Dictionary = _build_markers[i]
		var world: Vector3 = marker["pos"]
		var size: Vector2 = marker["size"]
		node.visible = true
		node.position = world + Vector3(0.0, 0.05, 0.0) + _lattice_offset_for(world)
		# x is the building's LENGTH along its own local +X, matching the
		# mesh convention every wall and building already uses, so the mark
		# and the thing that replaces it are the same shape pointing the
		# same way.
		node.scale = Vector3(size.x, 1.0, size.y)
		node.rotation.y = float(marker["angle"])
		# Fades out over its life rather than vanishing, so the mark reads
		# as expiring rather than as the order being cancelled.
		var age := (_now - float(marker["at"])) / BUILD_MARKER_SECONDS
		var material := node.material_override as StandardMaterial3D
		material.albedo_color = Color(0.45, 0.85, 1.0, 0.5 * (1.0 - age))


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


## Draw resource nodes IN THE WORLD as forests — many small trees whose
## species follow the ground (ResourceVisuals), batched into chunked
## MultiMeshes, felled with a tip-and-sink when the server reports a node
## worked out.
##
## Fog gating lives on the SERVER now (D-061's `_send_visible_nodes`):
## everything in `_state.nodes` was earned by vision, so there is no
## client-side `_explored` check here — the old one predated the server
## gate, and double-gating hid nodes revealed by an ally's vision (D-050)
## that this player's own units had never walked to.
##
## Once known, a node stays drawn until reported felled — the minimap's
## persistent-explored rule (D-030). A known node felled OUT of sight
## stays standing here, deliberately: the server withholds the felling
## until this player can see the cell, the same staleness a building
## ghost has.
func _refresh_resource_nodes() -> void:
	if _state.space == null:
		return

	# Fellings first: the felled cell leaves its chunk in the same frame
	# the wire said so, whether or not anything new arrived.
	for felled in _state.take_felled():
		_begin_felling(felled)

	# Place nodes the server newly revealed. Additions only — the diff is
	# cheap because both sides shrink together on a felling.
	if _state.nodes.size() != _node_placed.size():
		for cell in _state.nodes:
			if not _node_placed.has(cell):
				_place_node(int(cell), int(_state.nodes[cell]))

	# Rebuild only chunks whose membership changed, then swing every chunk
	# to its lattice copy — per chunk, never per tree (D-035's tax, paid
	# wholesale).
	for key in _tree_chunks:
		var chunk: Dictionary = _tree_chunks[key]
		if bool(chunk["dirty"]):
			_rebuild_tree_chunk(chunk)
		(chunk["root"] as Node3D).position = _lattice_offset_for(chunk["centre"])

	_advance_fallings()


## One node enters the world: pick its model from the ground it stands on,
## pose it, and file it in its chunk.
func _place_node(cell: int, kind: int) -> void:
	var space := _state.space
	var coord := space.from_index(cell)
	var world := space.to_world(coord)
	if _state.terrain_sampler.is_valid():
		world.y = _state.terrain_sampler.call(world.x, world.z)

	var model := _node_model_for(cell, coord, kind)
	# The authored models are grounded at y=0 (split_markers bakes them
	# so); the primitive fallback is a centred cylinder and needs lifting
	# onto its base.
	var lift := 0.0 if UnitMesh.mesh_for(model) != null else 0.75
	var basis := Basis(Vector3.UP, ResourceVisuals.yaw_for(cell)) \
		.scaled(Vector3.ONE * ResourceVisuals.scale_for(cell))
	var xform := Transform3D(basis, world + Vector3(0.0, lift, 0.0))

	var key := Vector2i(coord.x / NODE_CHUNK, coord.y / NODE_CHUNK)
	var chunk: Dictionary = _tree_chunks.get(key, {})
	if chunk.is_empty():
		var root := Node3D.new()
		add_child(root)
		var centre_cell := Vector2i(key.x * NODE_CHUNK + NODE_CHUNK / 2,
			key.y * NODE_CHUNK + NODE_CHUNK / 2)
		chunk = {"root": root, "centre": space.to_world(centre_cell),
			"multis": {}, "cells": {}, "dirty": true}
		_tree_chunks[key] = chunk
	chunk["cells"][cell] = {"model": model, "xform": xform}
	chunk["dirty"] = true
	_node_placed[cell] = {"chunk": key, "world": world, "model": model, "kind": kind}


## The model a node wears — species from the same TerrainGen the ground
## was meshed from, so a desert grows arid types and a treeline frays into
## its neighbour region's species (ResourceVisuals's job; this is just the
## plumbing that feeds it terrain samples).
func _node_model_for(cell: int, coord: Vector2i, kind: int) -> StringName:
	var biome := TerrainGen.Biome.GRASSLAND
	var moisture := 0.5
	var neighbours := []
	if _terrain_gen != null:
		biome = _terrain_gen.biome_at(_state.space, coord)
		moisture = _terrain_gen.moisture_at(_state.space, coord)
		for neighbour in _state.space.neighbors(coord):
			neighbours.append(_terrain_gen.biome_at(_state.space, neighbour))
	return ResourceVisuals.model_for(kind, biome, neighbours, moisture, cell)


## The mesh behind a model id, or the per-kind primitive stand-in when the
## art build is missing. The stand-in keeps the old marker's readability
## rules: node colour from the same table as the minimap, slight emission
## so it reads against similar-hued terrain.
func _node_mesh_for(model: StringName, kind: int) -> Mesh:
	var authored: Mesh = UnitMesh.mesh_for(model)
	if authored != null:
		return authored
	var cached: Mesh = _node_fallback_meshes.get(kind, null)
	if cached != null:
		return cached
	var primitive := CylinderMesh.new()
	primitive.top_radius = 0.7
	primitive.bottom_radius = 1.05
	primitive.height = 1.5
	var material := StandardMaterial3D.new()
	material.albedo_color = _node_colour(kind)
	material.roughness = 0.75
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.35
	primitive.material = material
	_node_fallback_meshes[kind] = primitive
	return primitive


## Repack one chunk's trees into its MultiMeshes: one per model actually
## present, instance transforms straight from the placement table. Runs
## only when membership changed (a reveal or a felling), so a settled
## forest costs nothing here.
func _rebuild_tree_chunk(chunk: Dictionary) -> void:
	var groups := {}
	for cell in chunk["cells"]:
		var entry: Dictionary = chunk["cells"][cell]
		var model: StringName = entry["model"]
		if not groups.has(model):
			groups[model] = []
		groups[model].append(entry["xform"])

	var multis: Dictionary = chunk["multis"]
	for model in multis.keys():
		if not groups.has(model):
			(multis[model] as MultiMeshInstance3D).queue_free()
			multis.erase(model)

	for model in groups:
		var instance: MultiMeshInstance3D = multis.get(model, null)
		if instance == null:
			instance = MultiMeshInstance3D.new()
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			var kind := Economy.ResourceKind.WOOD
			for cell in chunk["cells"]:
				if chunk["cells"][cell]["model"] == model:
					kind = int(_node_placed[cell]["kind"])
					break
			multimesh.mesh = _node_mesh_for(model, kind)
			instance.multimesh = multimesh
			(chunk["root"] as Node3D).add_child(instance)
			multis[model] = instance
		var transforms: Array = groups[model]
		instance.multimesh.instance_count = transforms.size()
		for i in range(transforms.size()):
			instance.multimesh.set_instance_transform(i, transforms[i])
	chunk["dirty"] = false


## A node the server reported worked out: pull it from its chunk and stand
## up a short-lived individual instance to play the fall.
func _begin_felling(felled: Dictionary) -> void:
	var cell := int(felled["cell"])
	var placed: Dictionary = _node_placed.get(cell, {})
	if placed.is_empty():
		return  # never drawn (revealed and felled between frames)
	_node_placed.erase(cell)

	var chunk: Dictionary = _tree_chunks.get(placed["chunk"], {})
	var xform := Transform3D()
	if not chunk.is_empty() and chunk["cells"].has(cell):
		xform = chunk["cells"][cell]["xform"]
		chunk["cells"].erase(cell)
		chunk["dirty"] = true

	var kind := int(felled["kind"])
	var instance := MeshInstance3D.new()
	instance.mesh = _node_mesh_for(placed["model"], kind)
	add_child(instance)
	_fallings.append({"node": instance, "kind": kind, "cell": cell,
		"age": 0.0, "base": xform})


## Advance every mid-animation felling: trees tip about their base with an
## accelerating crash, then sink; ore just sinks. Pure pose math lives in
## ResourceVisuals.fall_pose, so this is only scene-tree application.
func _advance_fallings() -> void:
	if _fallings.is_empty():
		return
	var kept := []
	for fall in _fallings:
		fall["age"] = float(fall["age"]) + _frame_delta
		var pose: Dictionary = ResourceVisuals.fall_pose(int(fall["kind"]), float(fall["age"]))
		if bool(pose["done"]):
			(fall["node"] as MeshInstance3D).queue_free()
			continue
		var base: Transform3D = fall["base"]
		var tip := Basis(ResourceVisuals.tip_axis_for(int(fall["cell"])),
			float(pose["angle"]))
		var origin := base.origin + Vector3(0.0, -float(pose["sink"]), 0.0)
		(fall["node"] as MeshInstance3D).transform = Transform3D(
			tip * base.basis, origin + _lattice_offset_for(base.origin))
		kept.append(fall)
	_fallings = kept


## The placeholder mesh for a building whose authored model is missing.
##
## Sized so the four shapes read differently from each other at a glance, which
## is the entire reason `BuildingDef.mesh_primitive` exists. It carried no
## meaning at all until M7 because nothing read it.
func _building_primitive(def: BuildingDef) -> Mesh:
	# D-076: mesh_size overrides the hardcoded per-primitive dimensions
	# below when set, so a wall segment renders thin and long instead of
	# every other primitive's square footprint. Zero (every pre-existing
	# def) leaves the old hardcoded sizes exactly as they were.
	var override := def.mesh_size != Vector3.ZERO
	match def.mesh_primitive:
		"cylinder":
			var cylinder := CylinderMesh.new()
			if override:
				cylinder.top_radius = def.mesh_size.x / 2.0
				cylinder.bottom_radius = def.mesh_size.z / 2.0
				cylinder.height = def.mesh_size.y
			else:
				cylinder.top_radius = 1.0
				cylinder.bottom_radius = 1.2
				cylinder.height = 3.0
			return cylinder
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = def.mesh_size.x / 2.0 if override else 1.1
			capsule.height = def.mesh_size.y if override else 3.4
			return capsule
		"hull":
			var hull := BoxMesh.new()
			hull.size = def.mesh_size if override else Vector3(3.6, 2.0, 2.4)
			return hull
		_:
			var box := BoxMesh.new()
			box.size = def.mesh_size if override else Vector3(2.4, 3.0, 2.4)
			return box


func _refresh_buildings() -> void:
	if _state.space == null:
		return

	# Playtest fix: wall-family cells, gathered up front so each segment's
	# rotation below can see its ACTUAL current neighbours rather than
	# only the one `facing` chosen at placement. `_building_defs` rather
	# than a fresh BuildingSim.def_by_id() per building — cheap, and a
	# brand new building simply not counting as a neighbour for the one
	# frame before its own def gets cached is a self-correcting non-issue,
	# not the M4 disk-load-per-call defect this avoids repeating.
	var wall_family_cells := {}
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if bool(info.get("destroyed", false)):
			continue
		var def: BuildingDef = _building_defs.get(wire_id, null)
		if def == null or def.footprint_radius != 0 or def.is_access_tower:
			continue
		wall_family_cells[_state.space.from_index(int(info["cell"]))] = int(wire_id)

	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		var instance: MeshInstance3D = _building_nodes.get(wire_id, null)

		if instance == null:
			var def := BuildingSim.def_by_id(StringName(info["def_id"]))
			if def == null:
				continue
			# Owner colour, like units (D-052) — a town hall you cannot
			# attribute at a glance is worse than a squad you cannot,
			# because it tells you whose ground you are standing on.
			var owner_colour := _state.colour_of(int(info["owner"]))
			var mesh: Mesh = null
			var material: Material = null

			var authored := false
			if def.model_id != &"":
				mesh = UnitMesh.mesh_for(def.model_id)
			if mesh != null:
				# Authored model (D-064). The owner-colour mask is baked into
				# vertex alpha, so the shader mixes rather than tinting the
				# whole structure one colour.
				material = UnitMesh.static_material_for(owner_colour)
				authored = true
			else:
				# The primitive, which now actually reads `mesh_primitive`.
				# It had no readers at all until M7 — every building on the
				# map was a hardcoded box while the field sat in the schema
				# looking authoritative.
				mesh = _building_primitive(def)
				var standard := StandardMaterial3D.new()
				standard.albedo_color = owner_colour.lerp(def.mesh_color, 0.25)
				standard.roughness = 0.9
				material = standard

			instance = MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			_building_nodes[wire_id] = instance
			# Cached alongside the node rather than re-resolved every frame:
			# BuildingSim.def_by_id() loads from disk, the same cost shape as
			# M4's UnitRoster.by_id defect, and this loop already runs once
			# per building per frame.
			_building_defs[wire_id] = def
			# How far to lift the mesh so its BASE sits on the ground, not its
			# centre. Authored building models (art/buildings, D-064) are built
			# with their origin already at the base — `box(..., centre=(0,
			# height/2, 0))` spans y=0 to y=height — so an authored mesh needs
			# no lift at all. The primitive fallback (BoxMesh, CylinderMesh, ...)
			# is centred on its own origin instead, so it needs to rise by half
			# its own height. A single hardcoded "1.5" here used to assume every
			# building was the centred primitive; once authored models landed
			# in M7 every building was lifted 1.5 units into the air on top of
			# already sitting on the ground — the floating-buildings bug.
			var mesh_height := mesh.get_aabb().size.y
			var lift := 0.0 if authored else mesh_height / 2.0
			_building_ground_lift[wire_id] = lift
			_building_top_offset[wire_id] = mesh_height - lift
			add_child(instance)
			# Freestanding building: `facing` is REPLICATED continuous state
			# now (see building_sim.gd's add_building doc and the
			# scroll-to-rotate control in `_place_armed_building`) — either
			# what the player chose, or the automatic default their client
			# sent if they never touched the wheel — so every client decodes
			# the exact same angle rather than each computing its own guess.
			# Set once here since nothing recomputes it later — a building's
			# rotation doesn't change after it's founded. Wall-family
			# segments and the access tower are left at the identity
			# rotation here; the per-frame wall-rotation block below (same
			# loop, runs unconditionally) sets theirs on this very frame
			# anyway, from their real neighbours, so setting it twice would
			# just be dead weight.
			if def.footprint_radius != 0 and not def.is_access_tower:
				instance.rotation.y = PlacementJitter.radians_of_byte(int(info.get("facing", 0)))

		if bool(info["destroyed"]):
			instance.visible = false
			# And its health bar, which this loop would otherwise never
			# reach again — the update below is past this `continue`. The
			# bar would hang in the air over the rubble showing the last
			# health the building had, and it would do so EVERY time one
			# died, since a destroyed building is by definition one that
			# took damage and therefore had a bar.
			_hide_building_health_bar(int(wire_id))
			continue
		instance.visible = true

		var progress := clampf(_derived_progress(wire_id, info), 0.15, 1.0)
		instance.scale = Vector3(1.0, progress, 1.0)

		var world := _state.space.to_world(_state.space.from_index(int(info["cell"])))
		# Where the building actually stands, as opposed to which cell it is
		# filed under. Two different sources, deliberately:
		#
		# - A WALL-FAMILY segment reads the REPLICATED offset (D-096). Its
		#   position was chosen by whoever dragged the run out, so no other
		#   client could recompute it, and two clients disagreeing about
		#   where a wall stands is a desync a player would see by walking
		#   through it.
		# - A FREESTANDING building derives its own jitter from the cell.
		#   Nobody chose it, every client computes the same value, and
		#   keeping it off the wire costs nothing.
		#
		# The access tower gets neither: it is a point structure whose door
		# opens onto a specific neighbouring cell, so it stands dead centre.
		var building_def: BuildingDef = _building_defs.get(wire_id, null)
		if building_def != null and not building_def.is_access_tower:
			if building_def.footprint_radius == 0:
				world += Vector3(
					float(info.get("offset_x", 0.0)), 0.0, float(info.get("offset_z", 0.0)))
			else:
				world += PlacementJitter.position_offset(int(info["cell"]),
					_state.space.hex_size * BUILDING_JITTER_FRACTION)
		if _state.terrain_sampler.is_valid():
			world.y = _state.terrain_sampler.call(world.x, world.z)
		# Sit the mesh ON the ground rather than half-sunk into it (zero for an
		# authored, base-pivoted model — see _building_ground_lift above).
		world.y += float(_building_ground_lift.get(wire_id, 0.0)) * progress
		# Drawn at the lattice copy the camera can actually see (D-035).
		# Buildings were placed at their canonical position only, so one
		# across the seam appeared a whole map from where it stands —
		# terrain tiles nine times and the things standing on it did not.
		instance.position = world + _lattice_offset_for(world)

		# Playtest fix, REVISED: an earlier pass here tilted a wall segment
		# to follow the terrain between its own two ends. Rejected on
		# review — a leaning wall reads as broken/toppling, not as
		# following the ground, and a real wall's COURSES stay vertical
		# even where the ground under them doesn't (they're built in
		# level-ish steps, or the footing is simply cut into the slope).
		# The actual fix is in the mesh itself: art/buildings/__init__.py
		# extends every wall-family body well below y=0 (a buried skirt),
		# so broken ground is hidden by depth instead of by leaning the
		# whole segment.
		#
		# What DOES still belong here: playtest fix, second issue — a
		# segment's rotation was set ONCE at placement from the single
		# `facing` chosen then, which only ever matched ONE of up to two
		# actual connections. Built as a sequence of individual clicks
		# (not one continuous drag) rather than a straight drag, each new
		# segment snapped to face whichever neighbour existed AT THAT
		# MOMENT — so the FIRST segment in a bending run kept its
		# placement-time facing forever, visibly unaligned with a bend
		# that only took shape afterward. Recomputed every frame instead,
		# from the buildings that actually exist right now.
		# D-096: a segment's rotation is now its OWN — chosen when the run
		# was dragged out, and replicated with it — rather than inferred
		# every frame from whichever neighbours happen to exist.
		#
		# The neighbour-bisection this replaces was a workaround for a
		# 6-way facing that could not express the angle a run actually ran
		# at: it had to guess a segment's direction from its company. A
		# continuous facing states it outright, so a segment points exactly
		# where it was laid, a bend needs no guessing, and a lone segment
		# is no longer stuck pointing at whatever it first snapped to.
		var rotating_wall_def: BuildingDef = _building_defs.get(wire_id, null)
		if rotating_wall_def != null and rotating_wall_def.footprint_radius == 0 \
				and not rotating_wall_def.is_access_tower:
			instance.rotation.y = PlacementJitter.radians_of_byte(int(info.get("facing", 0)))

		_update_building_health_bar(int(wire_id), instance, progress,
			clampf(float(info.get("health_fraction", 1.0)), 0.0, 1.0))

		# D-076: a gate's own colour tells you whether it is currently
		# passable, without needing it selected. Two material types need
		# two mechanisms — the primitive path's StandardMaterial3D gets
		# recoloured directly; an authored gate model (gate/garrison_gate,
		# D-076's follow-up art pass) uses building_static.gdshader's own
		# `gate_open` uniform instead, since ShaderMaterial has no
		# `albedo_color` to lerp.
		var gate_def: BuildingDef = _building_defs.get(wire_id, null)
		if gate_def != null and gate_def.is_gate:
			var open := bool(info.get("gate_open", false))
			if instance.material_override is StandardMaterial3D:
				var gate_material := instance.material_override as StandardMaterial3D
				var owner_colour := _state.colour_of(int(info["owner"]))
				var base_colour := gate_def.mesh_color.lightened(0.5) if open else gate_def.mesh_color
				gate_material.albedo_color = owner_colour.lerp(base_colour, 0.75)
			elif instance.material_override is ShaderMaterial:
				# Playtest fix: `gate_open` is a server-replicated BOOLEAN
				# (D-076), and the shader used to read it directly — so the
				# leaf snapped instantly between fully closed and fully
				# open in one frame instead of swinging, which read as "the
				# door doesn't seem to animate" even though the shader math
				# was correct (confirmed by rendering both states directly:
				# the leaf really does move). Smoothed here, client-side
				# only — this is cosmetic interpolation toward a value the
				# server owns, the same one-way relationship
				# cosmetic_offset.gd's whole file exists to keep (D-006
				# clause 2), not a second source of truth for gate state.
				var target := 1.0 if open else 0.0
				var current: float = _gate_visual_open.get(wire_id, target)
				current = move_toward(current, target, _frame_delta / GATE_SWING_SECONDS)
				_gate_visual_open[wire_id] = current
				(instance.material_override as ShaderMaterial).set_shader_parameter(
					"gate_open", current)

		# Armed and complete (a half-built town centre has no garrison to
		# fire from). Same client-inferred approach as `_activity_for`:
		# nearest enemy squad within range, using the enemy scan squads
		# already refresh once a frame — no separate wire event exists for
		# a building's shot either (Combat.resolve_buildings() returns only
		# a squad-level alive/routed diff, same as the squad path).
		var def: BuildingDef = _building_defs.get(wire_id, null)
		if def != null and def.damage > 0.0 and progress >= 0.999:
			_refresh_enemy_scan()
			var mine := int(info["owner"])
			var best_distance := def.attack_range
			var target := Vector3.ZERO
			for entry in _enemy_scan:
				if int(entry["owner"]) == mine:
					continue
				var d := world.distance_to(entry["at"])
				if d < best_distance:
					best_distance = d
					target = entry["at"]
			if target != Vector3.ZERO:
				var launch := _missile_ground(instance.position, MISSILE_RELEASE_HEIGHT)
				var landing := _missile_ground(
					_missile_landing(instance.position, world, target),
					MISSILE_IMPACT_HEIGHT)
				_maybe_launch_missile(
					"building:%d" % int(wire_id), launch, landing, def.attack_interval)

	_refresh_wall_joints(wall_family_cells)


## Which of `TorusSpace.DIRECTIONS`' 6 indices actually have a living
## wall-family neighbour right now (playtest fix) — the shared basis for
## both a segment's rendered rotation (`_wall_segment_yaw`) and whether a
## junction still needs a post (`_wall_segment_is_flush`), so the two can
## never disagree about what is actually connected to what.
func _wall_segment_neighbour_dirs(wall_family_cells: Dictionary, cell: Vector2i) -> Array:
	var dirs := []
	for i in range(TorusSpace.DIRECTIONS.size()):
		if wall_family_cells.has(_state.space.normalize(cell + TorusSpace.DIRECTIONS[i])):
			dirs.append(i)
	return dirs


## A wall-family segment's rendered yaw (playtest fix), from its ACTUAL
## current neighbours rather than the single `facing` chosen once at
## placement:
##
## - 0 neighbours: nothing to align to — the stored facing, unchanged.
## - 1 neighbour (a wall's dead end): point straight at it. Symmetric box,
##   so facing it or its opposite reads identically — no reason to prefer
##   the stored facing over the connection that actually exists.
## - 2 neighbours: bisect. A mitred corner — the segment's axis pointing
##   halfway between its two connections — reads far better than a
##   segment aimed squarely at only one side of a bend, and for a
##   perfectly STRAIGHT run (the two neighbours opposite each other) the
##   vector sum below degenerates toward zero, so that case is handled
##   separately by picking either neighbour (the box is symmetric, so
##   which one cannot matter).
## - 3+ neighbours (a T or 4-way junction): no single axis can bisect a
##   junction meaningfully. Falls back to the stored facing and leans on
##   the joint post instead, same as before this fix existed.
func _wall_segment_yaw(neighbour_dirs: Array, stored_facing: int) -> float:
	if neighbour_dirs.size() != 2:
		return _facing_rotation_y(stored_facing if neighbour_dirs.is_empty() else neighbour_dirs[0])

	var a := _state.space.axial_offset_to_world(Vector2(TorusSpace.DIRECTIONS[neighbour_dirs[0]]))
	var b := _state.space.axial_offset_to_world(Vector2(TorusSpace.DIRECTIONS[neighbour_dirs[1]]))
	var bisector := a.normalized() + b.normalized()
	if bisector.length_squared() < 0.01:
		return _facing_rotation_y(neighbour_dirs[0])
	return atan2(-bisector.z, bisector.x)


## Whether a wall-family segment's OWN rendered rotation already reaches
## flush toward every one of its current neighbours, with no gap for a
## post to cover (playtest fix — see `_wall_segment_yaw`'s doc for why
## each case below aligns exactly the way it claims to).
func _wall_segment_is_flush(neighbour_dirs: Array) -> bool:
	if neighbour_dirs.size() <= 1:
		return true
	if neighbour_dirs.size() == 2:
		return (int(neighbour_dirs[0]) + 3) % 6 == int(neighbour_dirs[1])
	return false


## Playtest fix (D-076 follow-up): a vertical post at every wall-family-to-
## wall-family adjacency that ISN'T already flush (`_wall_segment_is_flush`
## — a straight run or a dead end need none), bridging the gap a T or
## 4-way junction's rigid geometry can never close on its own, and topping
## up whatever a genuine bend's bisected rotation (`_wall_segment_yaw`)
## doesn't quite reach.
##
## `wall_family_cells` is `_refresh_buildings`' own map, passed in rather
## than rebuilt — the two already have to agree on who is a wall-family
## neighbour of whom, so computing it twice would just be two chances to
## disagree.
##
## O(buildings * 6) via the cell -> wire_id lookup, not a pairwise
## building x building scan — the same shape as the standing "disk_offsets/
## bucket map before distance()" rule elsewhere in this project (vision,
## combat, production), just for the wall network instead of a radius scan.
func _refresh_wall_joints(wall_family_cells: Dictionary) -> void:
	if _state.space == null:
		return

	for cell in wall_family_cells:
		var wire_id: int = wall_family_cells[cell]
		for i in range(TorusSpace.DIRECTIONS.size()):
			var neighbour_cell: Vector2i = _state.space.normalize(cell + TorusSpace.DIRECTIONS[i])
			if not wall_family_cells.has(neighbour_cell):
				continue
			var other_id: int = wall_family_cells[neighbour_cell]
			if other_id <= wire_id:
				continue  # each unordered pair handled once
			_update_wall_joint(wire_id, other_id, cell, neighbour_cell,
				_wall_segment_neighbour_dirs(wall_family_cells, cell),
				_wall_segment_neighbour_dirs(wall_family_cells, neighbour_cell))


## How many tread blocks a stair connector between two differently-tall
## walkway segments gets. Fixed rather than scaled to the height
## difference — the rig's children are allocated once and only resized/
## hidden after, matching every other pooled-node pattern in this file
## (health bars, action buttons).
const WALL_STAIR_STEPS := 4
## Below this height difference between two walkway tops, a stair would be
## a cosmetic ripple, not a readable feature — the plain angle post (or
## nothing, if the run is flush) is enough.
const WALL_STAIR_THRESHOLD := 0.2

## The angle-post's true minimum radius — see the derivation where it's
## used, in `_update_wall_joint`. Half the hex spacing minus how far a
## wall segment's own half-thickness (1.0/2, every wall-family def) puts
## its edge from centre at the one angle (60 degrees) that ever matters.
const WALL_JOINT_HALF_SPACING := 0.8660254037844386  # sqrt(3)/2 * hex_size
const WALL_JOINT_HALF_THICKNESS := 0.5
const WALL_JOINT_MIN_RADIUS := WALL_JOINT_HALF_SPACING \
	- WALL_JOINT_HALF_THICKNESS / 0.8660254037844386  # sin(60 degrees)


## Which authored bastion (D-096) matches the wall meeting this junction.
##
## Derived from DATA the def already carries, not from its id — the same
## discipline that keeps `client.gd` from naming a civ. `walkable_top`
## separates the cheap palisade tier from the garrison tier, and `is_gate`
## picks timber over stone within it, which reproduces exactly the three
## styles `art/buildings` actually models. A new wall def gets a sensible
## bastion for free, and adding a fourth style means adding a case here
## rather than a lookup table of ids to maintain in parallel.
func _bastion_model_for(def: BuildingDef) -> StringName:
	if def == null or not def.walkable_top:
		return &"bastion_stake"
	if def.is_gate:
		return &"bastion_timber"
	return &"bastion_stone"


## One joint RIG for the (a_id, b_id) pair — a corner post (angle gaps,
## D-076 follow-up) plus a fixed pool of stair treads (walkway height
## mismatches, playtest follow-up) — created once and thereafter only
## moved/resized/hidden, the same never-freed-per-entry lifetime as
## `_building_nodes` (see `_free_nodes` for the one place everything is
## torn down together, on disconnect).
##
## `a_dirs`/`b_dirs` are each segment's full neighbour-direction list
## (`_wall_segment_neighbour_dirs`) — the caller already has both from its
## own scan, and this needs the FULL list (not just the direction to the
## other side) to ask `_wall_segment_is_flush` whether either segment's
## own bisected rotation already reaches this junction with no gap.
func _update_wall_joint(a_id: int, b_id: int, a_cell: Vector2i, b_cell: Vector2i,
		a_dirs: Array, b_dirs: Array) -> void:
	var key := "%d|%d" % [a_id, b_id]
	var rig: Node3D = _wall_joint_nodes.get(key, null)
	if rig == null:
		rig = Node3D.new()
		add_child(rig)

		# D-096: an AUTHORED round bastion, styled to the wall it joins,
		# rather than the bare cylinder this replaces.
		#
		# The cylinder was wrong in two independent ways and both are worth
		# remembering. Its SIZE went through three passes (too small, then
		# too big and blobbing into itself along a winding run, then a
		# derived radius) — all of them trying to plug a gap that only
		# existed because a 6-way facing could not express the angle a run
		# actually ran at. And its COLOUR came from `def.mesh_color`, the
		# PRIMITIVE FALLBACK colour, which the authored wall never renders
		# — so it was painted a shade found nowhere else on screen. That is
		# the same defect class as the stair treads below.
		#
		# A round drum is what makes one shape serve every junction: a
		# corner, a T and a four-way crossing present the same silhouette
		# in every direction, so nothing needs authoring per angle. The
		# mesh carries its own materials (art/buildings/_build_bastion), so
		# there is no tint to get wrong here at all.
		var post := MeshInstance3D.new()
		post.mesh = UnitMesh.mesh_for(_bastion_model_for(_building_defs.get(a_id, null)))
		# Recorded as rig METADATA rather than re-derived per frame from
		# `material_override == null`: the authored branch assigns a
		# material on its first update, so that test would answer "authored"
		# once and "primitive" every frame after — silently switching a
		# bastion to the fallback's cylinder maths a frame after it appeared.
		var authored_post := post.mesh != null
		if authored_post:
			# The authored mesh carries its own per-part materials and bakes
			# the owner-colour mask into vertex alpha, exactly like the walls
			# it joins — which is precisely why it matches them and the old
			# `mesh_color`-tinted cylinder did not.
			post.material_override = UnitMesh.static_material_for(
				_state.colour_of(int(_state.buildings.get(a_id, {}).get("owner", 0))))
		else:
			# The art build has not run, or the model failed to load. Same
			# contract as every other authored model in this project
			# (D-081): a missing mesh costs fidelity, not the game.
			var fallback := CylinderMesh.new()
			fallback.top_radius = WALL_JOINT_MIN_RADIUS + 0.03
			fallback.bottom_radius = WALL_JOINT_MIN_RADIUS + 0.13
			fallback.height = 1.0
			post.mesh = fallback
			var post_material := StandardMaterial3D.new()
			post_material.roughness = 0.9
			post.material_override = post_material
		rig.set_meta("authored_post", authored_post)
		rig.add_child(post)

		var steps: Array = []
		for _i in range(WALL_STAIR_STEPS):
			var step_mesh := BoxMesh.new()
			var step_material := StandardMaterial3D.new()
			step_material.roughness = 0.9
			var step := MeshInstance3D.new()
			step.mesh = step_mesh
			step.material_override = step_material
			step.visible = false
			rig.add_child(step)
			steps.append(step)

		rig.set_meta("post", post)
		rig.set_meta("steps", steps)
		_wall_joint_nodes[key] = rig

	var post: MeshInstance3D = rig.get_meta("post")
	var steps: Array = rig.get_meta("steps")

	var a_info: Dictionary = _state.buildings.get(a_id, {})
	var b_info: Dictionary = _state.buildings.get(b_id, {})
	var a_def: BuildingDef = _building_defs.get(a_id, null)
	var b_def: BuildingDef = _building_defs.get(b_id, null)
	if a_info.is_empty() or b_info.is_empty() or a_def == null or b_def == null \
			or bool(a_info.get("destroyed", false)) or bool(b_info.get("destroyed", false)):
		rig.visible = false
		return
	rig.visible = true

	var a_progress := clampf(_derived_progress(a_id, a_info), 0.15, 1.0)
	var b_progress := clampf(_derived_progress(b_id, b_info), 0.15, 1.0)
	var progress := minf(a_progress, b_progress)

	# The two segments join at the midpoint between their cells — exactly
	# where a straight run's own two ends already meet (see the WALL_LENGTH
	# note in art/buildings/__init__.py). world_delta rather than a raw
	# position difference, so a junction across the torus seam still lands
	# at the true midpoint instead of jumping a whole map.
	var a_world := _state.space.to_world(a_cell)
	var to_b := _state.space.world_delta(a_cell, b_cell)
	var mid := a_world + to_b / 2.0
	var a_ground := a_world.y
	var b_ground := (a_world + to_b).y
	if _state.terrain_sampler.is_valid():
		a_ground = _state.terrain_sampler.call(a_world.x, a_world.z)
		b_ground = _state.terrain_sampler.call(a_world.x + to_b.x, a_world.z + to_b.z)
		mid.y = _state.terrain_sampler.call(mid.x, mid.z)

	# --- the bastion: a round corner where runs meet (D-096) -------------
	#
	# Shown wherever two runs actually MEET AT AN ANGLE. A straight run or a
	# dead end closes on its own — segments are laid end to end now — and
	# studding every junction of a straight wall with drums read as
	# decoration rather than structure.
	#
	# `_wall_segment_is_flush` still answers "does this segment's own
	# geometry already reach its neighbour", which under D-096's continuous
	# placement is true far more often than it used to be: a run laid along
	# one line has every segment pointing along it, so only genuine corners
	# raise a bastion at all.
	var a_flush := _wall_segment_is_flush(a_dirs)
	var b_flush := _wall_segment_is_flush(b_dirs)
	var post_height := minf(a_def.mesh_size.y, b_def.mesh_size.y) * progress
	if (a_flush and b_flush) or post_height <= 0.01:
		post.visible = false
	else:
		post.visible = true
		if bool(rig.get_meta("authored_post", false)):
			# Base-pivoted, like every authored structure here
			# (art/buildings spans y=0 upward), so it sits on the ground and
			# grows with construction by scaling Y alone. Its material and
			# colour were settled once at creation — nothing to tint per
			# frame, which is the point of it being authored.
			post.position = mid + _lattice_offset_for(mid)
			post.scale = Vector3(1.0, clampf(progress, 0.15, 1.0), 1.0)
		else:
			# Primitive fallback: centred on its own origin, so it needs
			# lifting by half its height and resizing rather than scaling.
			(post.mesh as CylinderMesh).height = post_height
			post.position = mid + Vector3(0.0, post_height / 2.0, 0.0) + _lattice_offset_for(mid)
			var owner_colour := _state.colour_of(int(a_info["owner"]))
			(post.material_override as StandardMaterial3D).albedo_color = \
				owner_colour.lerp(a_def.mesh_color, 0.9)

	# --- the stair: covers a vertical gap between two walkway tops -------
	#
	# Blocks stay vertical (the tilt this replaced read as toppling, not
	# as following the ground — see the note where it used to be built),
	# so two garrison-tier segments on sloped ground can now sit at
	# genuinely different absolute heights even on a straight, flush run.
	# A run of small vertical blocks climbing between the two walkway tops
	# reads as a real stair rather than either a floating ledge or a cliff
	# face — each buried well below its own tread the same way the wall
	# bodies themselves are (see SKIRT_DEPTH), so the run below it is
	# never visibly hollow either.
	var wants_stairs := a_def.walkable_top and b_def.walkable_top and progress >= 0.999
	var a_top := a_ground + a_def.top_height
	var b_top := b_ground + b_def.top_height
	if wants_stairs and absf(a_top - b_top) > WALL_STAIR_THRESHOLD:
		var run_len := to_b.length()
		var dir := to_b / run_len if run_len > 0.0 else Vector3.FORWARD
		var yaw := atan2(dir.x, dir.z)
		var tread_depth := run_len / float(WALL_STAIR_STEPS)
		var base_y := minf(a_ground, b_ground) - 1.0
		for i in range(WALL_STAIR_STEPS):
			var t_hi := float(i + 1) / float(WALL_STAIR_STEPS)
			var t_mid := (float(i) + 0.5) / float(WALL_STAIR_STEPS)
			var tread_y := lerpf(a_top, b_top, t_hi)
			var step_height := maxf(0.2, tread_y - base_y)
			var step: MeshInstance3D = steps[i]
			step.visible = true
			(step.mesh as BoxMesh).size = Vector3(1.0, step_height, tread_depth * 1.05)
			var pos := a_world + dir * (run_len * t_mid)
			pos.y = base_y + step_height / 2.0
			step.position = pos + _lattice_offset_for(pos)
			step.rotation.y = yaw
			var owner_colour := _state.colour_of(int(a_info["owner"]))
			(step.material_override as StandardMaterial3D).albedo_color = \
				owner_colour.lerp(a_def.mesh_color, 0.9)
	else:
		for step in steps:
			(step as MeshInstance3D).visible = false


## Health, over the building itself.
##
## The selection panel has drawn a building's health for a while, and it
## was the only place that did — so seeing a town centre come under attack
## required already having it selected, which nobody does until they
## already know. In the world it is the thing that TELLS you: a bar
## appearing over a distant barracks is how a player finds out a raid is
## happening at all.
##
## Shown only below full health, so an untouched base is not fenced in
## green bars. Same two colours as the panel's bar, from the same
## threshold, because a building at 20% should not read as one colour up
## close and another across the map.
##
## Bars are pooled per building and hidden rather than freed — a besieged
## base flickers between damaged and destroyed, and churning meshes on
## that edge is how a frame budget goes (the same reason the action
## buttons are pooled).
func _update_building_health_bar(wire_id: int, building: MeshInstance3D,
		progress: float, fraction: float) -> void:
	if not building.visible or fraction >= 0.999:
		_hide_building_health_bar(wire_id)
		return
	var bar: Dictionary = _health_bars.get(wire_id, {})

	if bar.is_empty():
		bar = {
			"back": _health_bar_quad(Color(0.06, 0.07, 0.1, 0.85), HEALTH_BAR_SIZE, 0),
			"fill": _health_bar_quad(Color(0.35, 0.85, 0.4), HEALTH_BAR_SIZE, 1),
			"fraction": -1.0,
		}
		_health_bars[wire_id] = bar
		add_child(bar["back"])
		add_child(bar["fill"])

	var back: MeshInstance3D = bar["back"]
	var fill: MeshInstance3D = bar["fill"]
	back.visible = true
	fill.visible = true

	# Above the box, which is drawn short while it is still going up — so
	# the bar rises with it rather than hanging in the air over a
	# foundation. `building.position` is already ground-lifted (see
	# _building_ground_lift); `_building_top_offset` is the remaining
	# distance up to the mesh's own top at full progress.
	var top_offset := float(_building_top_offset.get(wire_id, 1.5))
	var above := building.position + Vector3(0.0, top_offset * progress + 0.9, 0.0)
	back.position = above
	fill.position = above

	# Only when it actually changed. Health replicates in steps (see
	# BuildingSim.HEALTH_REPLICATION_STEPS), so this is a handful of
	# rebuilds across a whole siege rather than one per frame.
	if is_equal_approx(float(bar["fraction"]), fraction):
		return
	bar["fraction"] = fraction

	# Grown from the LEFT edge via the mesh's own offset. A quad scaled
	# about its centre would empty from both ends at once, which reads as
	# the bar shrinking rather than as health being lost.
	var mesh := fill.mesh as QuadMesh
	mesh.size = Vector2(HEALTH_BAR_SIZE.x * fraction, HEALTH_BAR_SIZE.y * 0.72)
	mesh.center_offset = Vector3(
		-HEALTH_BAR_SIZE.x * (1.0 - fraction) * 0.5, 0.0, 0.0)
	var material := fill.material_override as StandardMaterial3D
	material.albedo_color = Color(0.35, 0.85, 0.4) if fraction > 0.35 \
		else Color(0.9, 0.4, 0.35)


## Hide a building's health bar, if it has one. Kept rather than freed —
## see the pooling note above.
func _hide_building_health_bar(wire_id: int) -> void:
	var bar: Dictionary = _health_bars.get(wire_id, {})
	if bar.is_empty():
		return
	bar["back"].visible = false
	bar["fill"].visible = false


## One billboarded, unshaded quad for a health bar.
##
## Billboarded so it faces the player at any camera angle, and depth-test
## free so it is not swallowed by the building it is describing — the same
## treatment the selection footprints get, and for the same reason.
func _health_bar_quad(colour: Color, size: Vector2, priority: int) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.render_priority = priority
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _update_hud() -> void:
	if _hud_status == null:
		return

	# What a player can ACT on: how much army they are allowed to have left
	# to build, and how long the match has run.
	#
	# The ghost count that used to sit here was diagnostic — it measured
	# fog of war working, which is worth tracking and is not worth a slot
	# in the one line a player reads at a glance. It is still counted, and
	# still asserted on, in the capture verdict (`ghosts` and
	# `ghosts_peak`), which is where a measurement belongs.
	#
	# Squads counted the same way the SERVER counts them for the cap: this
	# player's living squads, gatherers included. `_state.curves` would
	# have counted every squad on screen including other players' — a
	# number that has nothing to do with the ceiling it is printed beside.
	_hud_status.text = "%s  ·  %s" % [
		HudLayout.squad_count_text(_state.living_squad_count(), _state.squad_cap),
		HudLayout.clock_text(_state.match_elapsed())]

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
			HudTheme.GOOD if health > 0.35 else HudTheme.BAD)

		# A building never offers anything for the BUILD segment — it is
		# not itself buildable-from — so that segment stays hidden and the
		# whole "Target" action (the one thing a building does offer)
		# lives in the control segment instead.
		_set_build_actions([])
		if progress < 1.0:
			_hide_chips()
			_progress_caption.text = "Under construction"
			_set_bar(_progress_bar_back, _progress_bar_fill, progress, HudTheme.ACCENT_BRIGHT)
		else:
			actions = _building_actions(info, def)
			# Playtest fix: this used to call _show_production
			# unconditionally, so a wall, gate or tower — nothing in
			# `produces`, nothing it could EVER train — showed "Idle" and
			# an empty queue caption anyway, like it was a barracks
			# between orders. A building that cannot produce has no
			# production state to report at all, so it gets none, rather
			# than a permanently-empty one.
			if not def.produces.is_empty():
				_show_production(info)
			# What the strip shows for a squad selection (each entry's own
			# name and a fraction bar) does not fit what a building offers
			# (a name and a COST) — same pool of Controls, different fields
			# populated, rather than leaving the strip a dead gap in the
			# middle of the panel.
			_show_train_chips(def)
			# "train" actions are dropped here, not merely duplicated —
			# `_show_train_chips` just made the chips themselves clickable
			# for exactly this order (see `_on_chip_input`), so keeping the
			# equivalent action buttons around was two controls doing the
			# same job side by side (reported as "two buttons for
			# Gatherers"). Anything else the building offers (Target) stays.
			actions = actions.filter(func(a): return String(a.get("kind", "")) != "train")
		_set_actions(actions)
		return

	if _selected.is_empty():
		_hide_chips()
		_selection_title.text = "Nothing selected"
		_selection_detail.text = "Click a squad or a building. Drag to box-select."
		_set_actions([])
		_set_build_actions([])
		return

	# A MIXED selection is named for what it contains, not for whichever
	# squad happened to be clicked first — see `_show_chips`, which is what
	# actually names each archetype now. This just counts.
	var counts := {}
	var strength := 0
	for squad in _selected:
		strength += _state.alive_of(squad)
		var id := StringName(String(_state.composition.get(squad, {}).get("def_id", "")))
		counts[id] = int(counts.get(id, 0)) + 1

	_selection_title.text = "%d squad%s" % [_selected.size(), "" if _selected.size() == 1 else "s"]
	_selection_detail.text = "%d soldiers" % strength

	_show_chips(counts)

	# The build menu's category drill-down (playtest fix, see
	# _build_menu_category's doc) is client state that outlives one panel
	# refresh, so a NEW selection has to reset it explicitly — otherwise
	# selecting a fresh squad after browsing "Defensive" would silently
	# keep showing "Defensive" for it too. Keyed off a SORTED copy of
	# `_selected`: the array's own order can change release to release
	# (a squad dying and the array compacting) without the selection
	# meaning anything different.
	var sorted_selection := _selected.duplicate()
	sorted_selection.sort()
	var selection_key := str(sorted_selection)
	if selection_key != _build_menu_selection_key:
		_build_menu_selection_key = selection_key
		_build_menu_category = ""
		_build_menu_group = ""

	# Actions offered are the ones EVERY selected squad can do. Offering a
	# build button because one founder is in the box would produce an
	# order most of the selection must refuse. Control and build are two
	# separate intersections (and two separate segments — see
	# `HudLayout.BUILD_DIVIDER_Y`'s doc comment), not one list split
	# afterward, so a founder mixed with line infantry correctly loses
	# Build entirely rather than showing a button only part of the
	# selection can act on.
	_set_actions(_shared_squad_actions(counts.keys(), _squad_control_actions))
	_set_build_actions(_shared_squad_actions(counts.keys(), _squad_build_actions))


## Populate the chip strip: one chip per SQUAD up to the collapse
## threshold, one per ARCHETYPE past it (the reference design's own
## behaviour going from 4 to 20 selected squads — see
## `HudLayout.CHIP_COLLAPSE_THRESHOLD`'s doc comment for why a chip per
## individual squad stops being legible at that point).
func _show_chips(counts: Dictionary) -> void:
	# Informational only in this mode — see `_on_chip_input`.
	_chip_train_ids.clear()
	var per_squad := _selected.size() <= HudLayout.CHIP_COLLAPSE_THRESHOLD
	var entries := []
	if per_squad:
		for squad in _selected:
			var id := StringName(String(_state.composition.get(squad, {}).get("def_id", "")))
			var unit := UnitRoster.by_id(id)
			entries.append({
				"name": unit.display_name if unit != null else String(id),
				"alive": _state.alive_of(squad),
				"total": unit.squad_size if unit != null else 0,
			})
	else:
		for id in counts.keys():
			var unit := UnitRoster.by_id(StringName(String(id)))
			var alive := 0
			var total := 0
			for squad in _selected:
				var this_id := StringName(String(_state.composition.get(squad, {}).get("def_id", "")))
				if this_id == StringName(String(id)):
					alive += _state.alive_of(squad)
					total += unit.squad_size if unit != null else 0
			entries.append({
				"name": "%s  ×%d" % [unit.display_name if unit != null else String(id), int(counts[id])],
				"alive": alive, "total": total,
			})
		# Strongest archetype first — the same "commonest reads first"
		# ordering the old text-only detail line used to give.
		entries.sort_custom(func(a, b): return int(a["alive"]) > int(b["alive"]))

	for i in range(_chip_panels.size()):
		var showing := i < entries.size()
		_chip_panels[i].visible = showing
		_chip_panels[i].tooltip_text = ""
		_chip_names[i].visible = showing
		_chip_counts[i].visible = showing
		_chip_bar_backs[i].visible = showing
		_chip_bar_fills[i].visible = showing
		if not showing:
			continue
		var entry: Dictionary = entries[i]
		_chip_names[i].text = String(entry["name"])
		var total := int(entry["total"])
		var alive := int(entry["alive"])
		_chip_counts[i].text = "%d/%d" % [alive, total] if total > 0 else "—"
		var fraction := float(alive) / float(total) if total > 0 else 0.0
		_set_bar(_chip_bar_backs[i], _chip_bar_fills[i], fraction,
			HudTheme.GOOD if fraction > 0.35 else HudTheme.BAD)


## The chip strip for a built, owned building: one chip per unit it can
## train, in the CIV's own version of that archetype (D-047) — the same
## roster `_building_actions` resolves against for the archetype id, so a
## chip and the order it sends can never name two different units.
##
## These chips ARE the train controls, not a picture of them next to the
## real ones — `_update_selection_panel` drops "train" out of the actions
## column for exactly this reason (see its own comment). Two clickable
## things doing the same job side by side is what got reported as "why
## are there two buttons for Gatherers".
func _show_train_chips(def: BuildingDef) -> void:
	var entries := []
	_chip_train_ids.clear()
	if def != null:
		var civ := _state.civ_of(_state.player)
		for archetype in def.produces:
			var unit := UnitRoster.for_civ_archetype(civ, archetype)
			if unit != null:
				entries.append({
					"name": unit.display_name,
					"cost": _cost_text(unit.cost_food, unit.cost_wood, unit.cost_gold, unit.cost_stone),
					"affordable": _can_afford(unit.cost_food, unit.cost_wood,
						unit.cost_gold, unit.cost_stone),
				})
				_chip_train_ids.append(archetype)

	for i in range(_chip_panels.size()):
		var showing := i < entries.size()
		_chip_panels[i].visible = showing
		_chip_panels[i].tooltip_text = "Click to train" if showing else ""
		_chip_names[i].visible = showing
		_chip_counts[i].visible = showing
		# No bar: a cost is not a fraction of anything, and a bar drawn at
		# a fixed length would read as a fraction regardless.
		_chip_bar_backs[i].visible = false
		_chip_bar_fills[i].visible = false
		if not showing:
			continue
		_chip_names[i].text = String(entries[i]["name"])
		_chip_counts[i].text = String(entries[i]["cost"])
		# Greyed when unaffordable, and its click refused in
		# `_on_chip_input`. These chips ARE the train control (not a picture
		# of one), so they need the same affordability gate the build list
		# has — it was added there first and missed here, which left the
		# most-used button in the game looking available and then bouncing.
		var affordable := bool(entries[i].get("affordable", true))
		_chip_panels[i].modulate = Color(1, 1, 1, 1) if affordable else Color(1, 1, 1, 0.45)
		_chip_panels[i].tooltip_text = "Click to train" if affordable \
			else "Not enough resources"


func _hide_chips() -> void:
	_chip_train_ids.clear()
	for i in range(_chip_panels.size()):
		_chip_panels[i].visible = false
		_chip_panels[i].tooltip_text = ""
		_chip_names[i].visible = false
		_chip_counts[i].visible = false
		_chip_bar_backs[i].visible = false
		_chip_bar_fills[i].visible = false


## A chip's own click, when it is standing in for a train button (see
## `_show_train_chips`). Composition chips leave `_chip_train_ids` empty,
## so a click on one of those falls through and does nothing — they are
## informational, not (yet) a control.
func _on_chip_input(event: InputEvent, index: int) -> void:
	if index >= _chip_train_ids.size():
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var archetype := StringName(String(_chip_train_ids[index]))
		# Refused here as well as greyed in `_show_train_chips` — a chip is
		# a Panel, not a Button, so dimming it is purely cosmetic and does
		# nothing to the click. Re-derived rather than cached alongside the
		# chip: the wallet moves every tick, and a flag captured when the
		# panel was last relabelled would go stale between refreshes.
		var unit := UnitRoster.for_civ_archetype(_state.civ_of(_state.player), archetype)
		if unit != null and not _can_afford(unit.cost_food, unit.cost_wood,
				unit.cost_gold, unit.cost_stone):
			return
		_train_selected(archetype)


## Swaps a chip's own stylebox on hover — see `_build_chip_pool`'s doc
## comment on why this is done by hand rather than via Button's built-in
## states. Gated on `_chip_train_ids`, the same guard `_on_chip_input`
## uses, so a composition chip (informational only) never lights up as if
## it were about to do something on click.
func _on_chip_hover(index: int, entered: bool) -> void:
	if index >= _chip_panels.size():
		return
	var clickable := index < _chip_train_ids.size()
	_chip_panels[index].add_theme_stylebox_override("panel",
		_chip_style_hover if (entered and clickable) else _chip_style_normal)


## The actions common to every unit type in the selection, from whichever
## per-def-id generator is passed in — `_squad_control_actions` for the
## top segment, `_squad_build_actions` for the bottom one (see
## `HudLayout.BUILD_DIVIDER_Y`'s doc comment for why those are two
## generators and two segments rather than one list).
##
## Intersection rather than union: a button that most of the selection
## would refuse is worse than an absent one, because the refusal arrives
## as a notice per squad and reads as the game being broken.
func _shared_squad_actions(def_ids: Array, actions_for: Callable) -> Array:
	if def_ids.is_empty():
		return []
	var shared: Array = actions_for.call(StringName(String(def_ids[0])))
	for i in range(1, def_ids.size()):
		var theirs := {}
		for action in actions_for.call(StringName(String(def_ids[i]))):
			theirs[_action_key(action)] = true
		var kept := []
		for action in shared:
			if theirs.has(_action_key(action)):
				kept.append(action)
		shared = kept
	return shared


## What makes two offered actions the same action.
##
## Kind and id, NOT the label: the formation entries mark the current one
## with a leading asterisk, so two squads in different formations would
## have every formation button "differ" and a mixed selection would be
## offered no formations at all.
func _action_key(action: Dictionary) -> String:
	return "%s/%s" % [String(action.get("kind", "")), String(action.get("id", ""))]


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
	_set_bar(_progress_bar_back, _progress_bar_fill, fraction, HudTheme.ACCENT_BRIGHT)

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
			# Same affordability gate as the build list. Missing here at
			# first, which left the most-used button in the game — training
			# — looking available and then being refused server-side, while
			# buildings greyed out properly.
			"enabled": _can_afford(unit.cost_food, unit.cost_wood,
				unit.cost_gold, unit.cost_stone),
		})
	# Only an ARMED building offers this (D-032's `damage` gate, the same
	# one Combat.resolve_buildings itself checks) — a storehouse has
	# nothing to focus-fire with.
	if def.damage > 0.0:
		out.append({
			"label": "Target\nShift+Right-click an enemy",
			"kind": "target_select", "id": &"",
		})
	# Playtest fix: explicit Auto/Locked/Open modes, one button each,
	# rather than a "Mode: Auto"<->"Manual" toggle plus a SEPARATE
	# Open/Close button that only appeared once already in Manual —
	# reaching "always open" from Auto took two clicks, and nothing on
	# screen named the Manual+closed state "Locked" at all. The active
	# mode is marked "* ", the same convention `_squad_control_actions`
	# already uses for the current formation.
	if def.is_gate:
		var gate_mode := int(info.get("gate_mode", BuildingSim.GATE_MODE_AUTO))
		var gate_open := bool(info.get("gate_open", false))
		var current_key := "auto"
		if gate_mode == BuildingSim.GATE_MODE_MANUAL:
			current_key = "open" if gate_open else "locked"
		for mode_entry in GATE_MODE_BUTTONS:
			out.append({
				"label": ("* " if String(mode_entry["key"]) == current_key else "") \
					+ String(mode_entry["label"]),
				"kind": "gate_set", "id": mode_entry["key"],
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


## Formation and behaviour SQUADS offer, from their UnitDef — the actions
## column's TOP segment (see `HudLayout.BUILD_DIVIDER_Y`'s doc comment for
## why building is a separate segment below it, not appended to this list).
func _squad_control_actions(def_id: StringName) -> Array:
	var out := []
	var def := UnitRoster.by_id(def_id)

	# Formation, for any unit (D-058). First, because it is the thing a
	# player changes most often once they know it exists.
	var current := String(_state.composition.get(_selected[0], {}).get("shape", ""))
	for formation in FormationRoster.offered():
		out.append({
			# The current one is marked rather than hidden: a row where one
			# is ticked says "these are your options and this is where you
			# are", which hiding it cannot.
			"label": ("* " if String(formation.id) == current else "") + formation.display_name,
			"kind": "formation", "id": formation.id,
		})

	out.append({"label": "Stop", "kind": "stop", "id": &""})
	if def != null and def.carry_capacity > 0:
		out.append({"label": "Gather\nor right-click a node", "kind": "gather", "id": &""})
	return out


## The three explicit gate modes offered in the selection panel (playtest
## fix) — see the `def.is_gate` branch of `_building_actions` below for
## why this replaced a Mode toggle plus a separate Open/Close button.
## "locked"/"open" both mean GATE_MODE_MANUAL server-side; the key here is
## client-only vocabulary that also tells the two apart.
const GATE_MODE_BUTTONS := [
	{"key": "auto", "label": "Auto"},
	{"key": "locked", "label": "Locked"},
	{"key": "open", "label": "Open"},
]


## Category display order and labels for the build menu (playtest fix) —
## fixed rather than derived from whichever defs happen to exist, so the
## menu's shape does not reshuffle depending on what a civ ships.
const BUILD_CATEGORIES := [
	{"id": "civic", "label": "Civic"},
	{"id": "military", "label": "Military"},
	{"id": "defensive", "label": "Defensive"},
]


## Building SQUADS offer, from `BuildingDef.built_by` — founders may raise
## a town hall and nothing else (D-031), gatherers and line infantry
## build nothing at all, so this comes back empty for them and the build
## segment simply does not show (see `_update_selection_panel`). The
## actions column's BOTTOM segment.
##
## Playtest fix, tiered: a flat list of every buildable def stopped fitting
## the button pool once D-076 added five wall-family defs to the three
## that existed before (six silently meant "the rest are unreachable").
## `_build_menu_category` empty returns one button per CATEGORY that has
## at least one def this squad can build; set, it returns that category's
## defs plus a Back button. `BuildingSim.can_build` still gates both
## levels, so a category with nothing this squad can build never appears,
## and drilling into one never offers a def this squad cannot build.
func _squad_build_actions(def_id: StringName) -> Array:
	var by_category := {}
	for building in BuildingSim.all_defs():
		if not BuildingSim.can_build(building, def_id):
			continue
		var category := building.category
		if not by_category.has(category):
			by_category[category] = []
		(by_category[category] as Array).append(building)

	if _build_menu_category == "" or not by_category.has(_build_menu_category):
		var out := []
		for entry in BUILD_CATEGORIES:
			if by_category.has(entry["id"]):
				out.append({
					"label": String(entry["label"]),
					"kind": "build_category", "id": entry["id"],
				})
		return out

	# Within a category, defs that fall into named GROUPS get one more level
	# (playtest fix). "Defensive" had eight entries once the wall family
	# grew, and the two tiers — a cheap palisade you throw up early and the
	# garrison wall you actually garrison — are different decisions that
	# were sitting in one undifferentiated list.
	#
	# Grouped by DATA (`walkable_top`), not by naming the defs, for the same
	# reason `_bastion_model_for` derives its answer that way: a new wall
	# def lands in the right group without this function learning its name.
	var groups := {}
	for building in by_category[_build_menu_category]:
		var group := _build_menu_group_of(building)
		if not groups.has(group):
			groups[group] = []
		(groups[group] as Array).append(building)

	# Only interpose the extra level when there is genuinely more than one
	# group to choose between — a category with a single group would
	# otherwise cost a pointless click on the way to the same list.
	var grouped: Array = groups.keys().filter(func(g): return g != "")
	grouped.sort()
	if grouped.size() > 1 and _build_menu_group == "":
		var picker := [{"label": "< Back", "kind": "build_category", "id": ""}]
		for group in grouped:
			picker.append({
				"label": BUILD_GROUP_LABELS.get(group, group),
				"kind": "build_group", "id": group,
			})
		# Anything ungrouped in this category still lists directly, so a
		# stray def can never become unreachable by not having a group.
		for building in groups.get("", []):
			picker.append(_build_action_for(building))
		return picker

	var listing: Array = groups.get(_build_menu_group, by_category[_build_menu_category]) \
		if _build_menu_group != "" else by_category[_build_menu_category]
	var out := [{
		"label": "< Back",
		"kind": "build_group" if _build_menu_group != "" else "build_category",
		"id": "",
	}]
	for building in listing:
		out.append(_build_action_for(building))
	return out


## Which sub-group of its category a def belongs to, or "" for none.
##
## `walkable_top` is the real dividing line in the wall family: the cheap
## palisade tier is a pure blocker, the garrison tier is a second elevation
## layer you put soldiers on (D-076). That is exactly the distinction worth
## a menu level, and it is already in the data.
func _build_menu_group_of(def: BuildingDef) -> String:
	if def.footprint_radius != 0:
		return ""
	return "garrison" if def.walkable_top else "palisade"


const BUILD_GROUP_LABELS := {
	"palisade": "Palisade\nwall & gate",
	"garrison": "Garrison\nwall, gate & tower",
}


## One build button, shared by the grouped and ungrouped paths so a def's
## label and its affordability cannot differ depending on how you reached it.
func _build_action_for(building: BuildingDef) -> Dictionary:
	return {
		"label": "Build %s\n%s" % [building.display_name, _cost_text(
			building.cost_food, building.cost_wood,
			building.cost_gold, building.cost_stone)],
		"kind": "build", "id": building.id,
		"enabled": _can_afford(building.cost_food, building.cost_wood,
			building.cost_gold, building.cost_stone),
	}


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
		# Playtest fix: something you cannot afford is greyed and
		# unpressable, rather than looking available and being silently
		# refused by the server on click. The server still re-checks (D-002)
		# — this only decides what the button LOOKS like, exactly as
		# `_can_place_at` only decides what the ghost looks like.
		button.disabled = not bool(actions[i].get("enabled", true))


## Whether this player's wallet currently covers a cost. All four
## resources or none, matching `Economy.try_spend`'s all-or-nothing rule
## (D-028) — a button that lit up when you could afford three quarters of
## something would be a worse lie than no button state at all.
##
## Advisory: the wallet is replicated and the server charges for real.
func _can_afford(food: int, wood: int, gold: int, stone: int) -> bool:
	var purse := _state.wallet
	if purse.size() < 4:
		return true  # not told yet; do not grey out the whole menu on a cold start
	return purse[Economy.ResourceKind.FOOD] >= food \
		and purse[Economy.ResourceKind.WOOD] >= wood \
		and purse[Economy.ResourceKind.GOLD] >= gold \
		and purse[Economy.ResourceKind.STONE] >= stone


func _on_action_pressed(index: int) -> void:
	if index < 0 or index >= _actions.size():
		return
	var action: Dictionary = _actions[index]
	match String(action["kind"]):
		"train":
			_train_selected(StringName(action["id"]))
		"build":
			_build_selected(String(action["id"]))
		"build_group":
			_build_menu_group = String(action["id"])
			_update_selection_panel()
		"gather":
			_gather_selected()
		"stop":
			_stop_selected()
		"formation":
			_set_formation(StringName(action["id"]))
		"target_select":
			# Arms the pick — the actual order goes out on the next
			# right-click, handled in `_handle_mouse_button` /
			# `_finish_target_pick`, mirroring `_placing`'s ghost-follows-
			# cursor arm/click split for building placement.
			_targeting_building = _selected_building
		"gate_set":
			_set_gate(String(action["id"]))


## Playtest fix: switch the selected gate directly to one of
## GATE_MODE_BUTTONS' three modes, replacing a separate mode-toggle and
## open/close-toggle that took two clicks to reach "always open" and never
## named "manual and closed" as its own state ("Locked").
##
## "locked"/"open" both mean GATE_MODE_MANUAL server-side, so switching to
## either sends BOTH the mode order (skipped if already manual) and the
## state order — reliable and on one channel, so the server sees mode
## before state whenever both are sent. `_handle_order_gate_state` only
## takes effect in manual mode (see server.gd), which is exactly why mode
## has to land first rather than being a fire-and-forget pair.
func _set_gate(mode_key: String) -> void:
	if not _connected or _selected_building < 0:
		return
	var info: Dictionary = _state.buildings.get(_selected_building, {})
	var wanted_mode := BuildingSim.GATE_MODE_AUTO if mode_key == "auto" \
		else BuildingSim.GATE_MODE_MANUAL
	var current_mode := int(info.get("gate_mode", BuildingSim.GATE_MODE_AUTO))
	if current_mode != wanted_mode:
		_peer.send(0, NetProtocol.encode_order_gate_mode(_selected_building, wanted_mode),
			ENetPacketPeer.FLAG_RELIABLE)
	if wanted_mode == BuildingSim.GATE_MODE_MANUAL:
		_peer.send(0, NetProtocol.encode_order_gate_state(
				_selected_building, mode_key == "open"),
			ENetPacketPeer.FLAG_RELIABLE)


## The build segment's own version of `_set_actions` — see
## `HudLayout.BUILD_DIVIDER_Y`'s doc comment for why this is a second pool
## rather than the first one's actions continuing past a fixed index. The
## divider and its caption follow the same visibility: empty (a building
## selected, or a squad that cannot build anything) hides the whole
## segment rather than showing a divider over nothing.
func _set_build_actions(actions: Array) -> void:
	_build_actions = actions
	_build_actions_divider.visible = not actions.is_empty()
	_build_actions_caption.visible = not actions.is_empty()
	for i in range(_build_action_buttons.size()):
		var button := _build_action_buttons[i]
		if i >= actions.size():
			button.visible = false
			continue
		button.visible = true
		button.text = String(actions[i]["label"])


func _on_build_action_pressed(index: int) -> void:
	if index < 0 or index >= _build_actions.size():
		return
	var action: Dictionary = _build_actions[index]
	if String(action["kind"]) == "build_category":
		# Drill into a category, or Back out of one (empty id) — see
		# _build_menu_category's doc. Refreshed immediately rather than
		# waiting for next frame's automatic pass so a click feels instant.
		_build_menu_category = String(action["id"])
		# Changing category always drops the sub-group, so backing out of
		# "defensive" and into it again starts at its group picker instead
		# of silently resuming wherever you were last time.
		_build_menu_group = ""
		_update_selection_panel()
		return
	if String(action["kind"]) == "build_group":
		_build_menu_group = String(action["id"])
		_update_selection_panel()
		return
	_build_selected(String(action["id"]))


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
				image.set_pixel(x, y, HudTheme.BG_VOID.darkened(0.5))
	for squad in _state.curves:
		# Ghosted squads are not drawn at all here either — the same
		# decision `_refresh_squads` makes for the 3D view (see its own
		# comment): units ghost as a display concept only for buildings
		# now, not squads. The underlying ghost data/hash mechanism (D-025)
		# is untouched; this just stops painting a dot for it.
		if _state.is_ghost(squad):
			continue
		var colour := Color(0.35, 0.95, 1.0) if _state.owns(squad) else Color(1.0, 0.35, 0.28)
		_plot_minimap(image, _state.squad_cell(squad, _now), colour)

	# Resource nodes, but only where this player has actually been. Fog
	# governs what you know about the map, and that includes what is on it.
	for cell in _state.nodes:
		if not _explored.has(cell):
			continue
		var coord := _state.space.from_index(int(cell))
		image.set_pixel(coord.x, coord.y, _node_colour(int(_state.nodes[cell])))

	if _minimap_texture == null:
		_minimap_texture = ImageTexture.create_from_image(image)
		_minimap_rect.texture = _minimap_texture
	else:
		_minimap_texture.update(image)


## Pans the circular crop (see `_build_nav_ring`) across the whole-map
## minimap image to keep it centred on wherever the camera currently is,
## rather than on the image's own fixed geometric centre — the ring answers
## "where am I", and a crop that always showed the same arbitrary patch of
## the torus regardless of where the player had gone could easily show
## neither the player's base nor the camera at all.
##
## Sets `focus_uv`, not `centre_px`: the crop CIRCLE stays put on screen
## (`centre_px`, set once per resize in `_layout_hud`, geometry only) —
## what moves is which part of the TEXTURE is sampled there. Wrap-aware
## (`fract()` in the shader), because the camera can be anywhere on the
## TORUS this minimap represents, including right at the flat image's own
## seam — see the shader's own comment for what going through `centre_px`
## instead looked like there.
##
## Reuses `_camera_target`, the same world point every other camera-follow
## calculation in this file already treats as "where the player is looking"
## (see `_jump_camera_to`). `_state.space.world_to_cell` is the one
## definition of world-to-cell, the same conversion `_cell_under` uses for
## clicks, so this cannot quietly drift from what a click on this same spot
## would resolve to.
func _centre_minimap_crop_on_camera() -> void:
	if _minimap_crop_material == null or _state.space == null:
		return
	if _state.space.width <= 0 or _state.space.height <= 0:
		return
	var cell := _state.space.world_to_cell(_camera_target)
	var focus := Vector2(
		(float(cell.x) + 0.5) / float(_state.space.width),
		(float(cell.y) + 0.5) / float(_state.space.height))
	_minimap_crop_material.set_shader_parameter("focus_uv", focus)


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


## Minimap colour per resource, picked to read against the terrain
## underneath rather than to match it: food and wood especially would
## vanish into grassland and forest if they used the obvious colours.
func _node_colour(kind: int) -> Color:
	match kind:
		Economy.ResourceKind.FOOD:
			return HudTheme.RESOURCE_FOOD
		Economy.ResourceKind.WOOD:
			return HudTheme.RESOURCE_WOOD
		Economy.ResourceKind.GOLD:
			return HudTheme.RESOURCE_GOLD
		_:
			return HudTheme.RESOURCE_STONE


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
		# Ctrl+wheel TURNS, plain wheel zooms. Zoom keeps the bare gesture
		# because it is the one used constantly; rotation is occasional and
		# can afford a modifier.
		#
		# Third meaning, highest priority of the three: while a FREESTANDING
		# building's ghost is live, plain wheel rotates IT instead of
		# zooming — the continuous, player-driven counterpart to the V key's
		# 6-way snap, which stays V-only for a wall/access-tower piece
		# (see `_free_rotating_armed_def`'s doc for why those can't be free).
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				if event.ctrl_pressed:
					_set_camera_yaw(_camera_yaw + CAMERA_YAW_WHEEL_STEP)
				elif _free_rotating_armed_def() != null:
					_placing_free_facing = posmod(
						_current_free_facing_byte() + FREE_FACING_WHEEL_STEP, 256)
				else:
					_camera_height = clampf(_camera_height - CAMERA_ZOOM_STEP, CAMERA_MIN_HEIGHT, _camera_max_height)
					_update_camera()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				if event.ctrl_pressed:
					_set_camera_yaw(_camera_yaw - CAMERA_YAW_WHEEL_STEP)
				elif _free_rotating_armed_def() != null:
					_placing_free_facing = posmod(
						_current_free_facing_byte() - FREE_FACING_WHEEL_STEP, 256)
				else:
					_camera_height = clampf(_camera_height + CAMERA_ZOOM_STEP, CAMERA_MIN_HEIGHT, _camera_max_height)
					_update_camera()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				# The ring's rim, checked before the minimap it surrounds
				# (see `_clicked_ring_rim`) — clicking it faces north rather
				# than jumping the camera or starting a drag.
				if _clicked_ring_rim(event.position):
					_set_camera_yaw(0.0)
					return
				# A click on the minimap jumps the view there instead of
				# selecting. Deliberately does NOT start a drag, so the
				# release below leaves the current selection alone — a
				# minimap click that silently deselected your army would
				# be worse than no minimap click at all.
				var jump := _minimap_cell_at(event.position)
				if jump.x >= 0:
					_jump_camera_to(jump)
					return
				# An armed sandbox cheat fires on the click and stays armed
				# (D-0xx) — repeated spawns should not mean re-opening the
				# picker every time. Checked before ordinary placement so it
				# cannot be shadowed by a building also being armed.
				if _cheat_arm_kind != "" and _fire_armed_cheat(event.position):
					return
				# A click while a building is armed PLACES it, and does not
				# also start a selection drag.
				#
				# D-076 amendment: a WALL-FAMILY piece is the one exception —
				# it starts a placement DRAG instead of placing immediately,
				# so a genuine drag can lay down a whole line (see
				# `_finish_placement_drag`). Release decides whether it was
				# actually a drag or just a click.
				if _placing != &"":
					var armed_def := BuildingSim.def_by_id(_placing)
					if armed_def != null and armed_def.footprint_radius == 0:
						_placing_drag = true
						_placing_drag_start = _snapped_placement_cell(event.position)
						# The SNAPPED start, not the raw cursor point. A run
						# dragged off an existing wall has to begin flush
						# against it, and this is also half of why a plain
						# click used to build somewhere other than where the
						# ghost showed — see `_finish_placement_drag`.
						_placing_drag_start_world = _wall_attach_world(event.position, armed_def)
						return
					if _place_armed_building(event.position):
						return
				# A left-click while target-picking is armed abandons it
				# rather than leaving the mode stuck armed under a
				# selection the player has visibly moved on from.
				_targeting_building = -1
				_dragging = true
				_drag_start = event.position
			elif _placing_drag:
				_placing_drag = false
				_finish_placement_drag(event.position)
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
			if event.pressed and _cheat_arm_kind != "":
				_on_cheat_cancel_pressed()
				return
			# The "Target" button's arming half: this click, hit or miss,
			# is spent on picking (or cancelling) a focus-fire target and
			# never falls through to an ordinary order.
			if event.pressed and _targeting_building >= 0:
				_finish_target_pick(event.position)
				return
			if event.pressed and _minimap_cell_at(event.position).x < 0:
				_order_selected(event.position, event.ctrl_pressed, event.shift_pressed)


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

	# In HUD space, because `_minimap_bounds` is. A raw mouse position
	# compared against a scaled HUD's rect is off by the scale factor, and
	# the failure is silent: the minimap simply stops answering clicks over
	# part of itself and starts answering them over the map beside it.
	var at := _to_hud(screen_position)
	if _minimap_bounds.size.x <= 0.0 or not _minimap_bounds.has_point(at):
		return Vector2i(-1, -1)

	var local := (at - _minimap_bounds.position) / _minimap_bounds.size
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


## Draw the drag box. Both corners are converted into HUD space: the box
## is a HUD child and the mouse is not, so on a scaled HUD an unconverted
## rect is drawn somewhere the player is not dragging.
##
## Only the DRAWING converts. `_finish_selection` keeps working in real
## pixels, because what it compares against — projected world positions —
## are real pixels too.
func _update_selection_rect(to: Vector2) -> void:
	if _selection_rect == null:
		return
	var rect := Rect2(_to_hud(_drag_start), _to_hud(to) - _to_hud(_drag_start)).abs()
	_selection_rect.position = rect.position
	_selection_rect.size = rect.size
	# Tested in REAL pixels, so the threshold that decides click-versus-drag
	# is the same gesture on every window — and the same one
	# `_finish_selection` applies. Measuring the scaled rect instead would
	# make a drag count as a click on a big monitor and not on a small one.
	var showing := (to - _drag_start).length() > DRAG_THRESHOLD_PX
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
## offset the squad is actually drawn at (D-035), and the squad's actual
## TERRAIN HEIGHT — `ClientState.squad_world_position` always answers at
## y=0 (`StateCurve.sample_world`'s height parameter defaults to 0 and
## nothing here supplied one), while the soldiers themselves are drawn at
## their true elevation via `Formation.soldier_transforms`'s own terrain
## sampling. On flat ground that gap is invisible; on a hill the point this
## function hands back for screen-projection is not where the troops
## visibly are, which is what was reported as unit selection itself being
## off — the same flat-plane-vs-real-terrain mismatch `_cell_under` had,
## in the function selection is actually built on.
func _squad_footprint(squad: int) -> Dictionary:
	var centre := _state.squad_world_position(squad, _now)
	var node: PrimitiveUnit = _squad_nodes.get(squad, null)
	if node != null:
		centre += node.position
	if _state.terrain_sampler.is_valid():
		centre.y = _state.terrain_sampler.call(centre.x, centre.z)

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
	# Terrain-corrected for the same reason `_squad_footprint` is — this
	# feeds `_enemy_squad_at`/`_enemy_cell_at` (target-picking and
	# attack-click hit-testing), which had the identical flat-plane-vs-
	# real-terrain gap.
	if _state.terrain_sampler.is_valid():
		world.y = _state.terrain_sampler.call(world.x, world.z)
	if _camera.is_position_behind(world):
		return Vector2(-1e6, -1e6)
	return _camera.unproject_position(world)


## What a click selected. Gathers every candidate's screen geometry and
## hands the RANKING to SelectionPick, which is pure and tested — the
## comparison is where this went wrong before, not the projection.
func _select_nearest(at: Vector2) -> void:
	var squads := []
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
		squads.append({
			"id": squad,
			"distance": _screen_of(print["centre"]).distance_to(at),
			"allowance": maxf(_screen_radius_of(print), SELECT_CLICK_RADIUS_PX * 0.35),
		})

	# Buildings compete on the same NORMALISED scale (see SelectionPick).
	# They were compared in raw pixels against the squads' "how far inside
	# the footprint" score, which is negative — so a building standing in
	# the middle of its own garrison could not win a click at all.
	var buildings := []
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if int(info["owner"]) != _state.player or bool(info["destroyed"]):
			continue
		var node: MeshInstance3D = _building_nodes.get(wire_id, null)
		if node == null or _camera.is_position_behind(node.position):
			continue
		buildings.append({
			"id": int(wire_id),
			"distance": _camera.unproject_position(node.position).distance_to(at),
			"allowance": _building_screen_radius(node),
		})

	var picked := SelectionPick.choose(squads, buildings)
	var best_building := int(picked["building"])
	if best_building >= 0:
		_selected_building = best_building
		_selected.clear()
		return

	_selected_building = -1
	var best := int(picked["squad"])
	if best >= 0 and not _selected.has(best):
		_selected.append(best)


## A building's clickable radius in SCREEN pixels.
##
## Measured across the drawn box rather than assumed, so the target
## matches what is on screen at any zoom — the same reason a squad's
## allowance is its projected footprint and not a constant.
func _building_screen_radius(node: MeshInstance3D) -> float:
	var mesh := node.mesh as BoxMesh
	var half := 1.2 if mesh == null else mesh.size.x * 0.5
	var edge := node.position + Vector3(half, 0.0, 0.0)
	if _camera.is_position_behind(node.position) or _camera.is_position_behind(edge):
		return 0.0
	return _camera.unproject_position(node.position).distance_to(
		_camera.unproject_position(edge))


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

	# Q/E turn the view continuously while held — see `_pan_camera`, which
	# polls them the same way it polls WASD. ESC opens and closes the game
	# menu.
	#
	# Deliberately BEFORE the build/train tables below, and worth knowing
	# why: those are driven by `OS.get_keycode_string`, so a letter added
	# to BUILD_KEYS or TRAIN_KEYS silently steals it from here. Q and E are
	# not in either table today — this ordering is what keeps that a
	# deliberate choice rather than a race between two lookups.
	if event.keycode == KEY_ESCAPE:
		# A pending building placement is what ESC cancels FIRST. Opening a
		# menu while the player is mid-gesture, and leaving the ghost armed
		# underneath it, is the kind of thing that gets a town centre put
		# somewhere nobody meant.
		if _placing != &"":
			_cancel_placement()
		else:
			_toggle_game_menu()
		return

	# D-076 (amendment): while ANY building is armed for placement, V
	# cycles which of the 6 hex sides it faces — the ghost rotates to show
	# the result before you commit, and a wall_tower's door marker moves
	# with it. Cosmetic for most buildings, mechanical for the tower's
	# door; this has to come before the build/train tables can steal V for
	# something else in the future.
	if event.keycode == KEY_V and _placing != &"":
		_placing_facing = (_placing_facing + 1) % 6
		_update_placement_ghost()
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
## the ground. The click becomes a CELL and is sent as an order for the
## server to interpret — the client never moves anything itself (D-002).
##
## Solved against the ACTUAL terrain surface, not a flat plane at y=0.
## Terrain has had real elevation since M7 (`TerrainGen.surface_field`,
## sampled here through the same `terrain_sampler` the placement ghost and
## rally markers already use) — a flat-plane ray is only correct on dead
## flat ground, and on a hill it intersects y=0 at a world position that
## is nowhere near where the terrain the player is looking at actually
## is. At a shallow camera angle that error is large: a few units of
## height miscalculation moves the ray's ground intersection by many
## cells, which is what was reported as clicks landing "8 grid spaces"
## from the cursor and selection "feeling broken" — the ray was correct
## for a world that stopped existing once hills were textured in.
##
## Fixed-point iteration rather than a closed-form solve: the intersection
## height depends on where along the ray you are, which depends on the
## height, so there is no single algebraic answer. A few passes converge
## quickly because terrain relief is small relative to how far the camera
## sits back — each pass re-solves the flat-plane formula against the
## PREVIOUS pass's height estimate instead of 0, and the estimate settles
## once resampling stops moving it. Falls back to the original flat-plane
## behaviour if no sampler is available yet (terrain not built).
## The WORLD point under the cursor, or a non-finite vector on a miss.
##
## Split out from `_cell_under` for D-096: continuous wall placement needs
## where on the ground the player is actually pointing, not merely which
## cell contains it, and rounding to a cell first would throw away exactly
## the sub-cell precision the whole change exists to keep.
func _world_under(screen_position: Vector2) -> Vector3:
	var from := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return Vector3.INF

	var height := 0.0
	var distance := 0.0
	var iterations := 4 if _state.terrain_sampler.is_valid() else 1
	for i in range(iterations):
		distance = (height - from.y) / direction.y
		if distance <= 0.0:
			return Vector3.INF
		if i < iterations - 1:
			var probe := from + direction * distance
			height = _state.terrain_sampler.call(probe.x, probe.z)

	return from + direction * distance


func _cell_under(screen_position: Vector2) -> Vector2i:
	var world := _world_under(screen_position)
	if not world.is_finite():
		return Vector2i(-1, -1)
	return _state.space.world_to_cell(world)


## Right-click orders the SELECTION, not everything owned (D-027
## criterion 3). With nothing selected it does nothing: quietly marching
## an army the player never chose is worse than ignoring the click.
func _order_selected(screen_position: Vector2, attack_move: bool, shift: bool = false) -> void:
	if not _connected or _state.space == null:
		return

	# The BUILDING branch comes before the empty-selection guard, and that
	# ordering is the whole of it.
	#
	# Selecting a building CLEARS `_selected` (a building and a squad are
	# not selected together), so with a barracks selected `_selected` is
	# always empty — and the guard that turns a stray right-click on empty
	# ground into a no-op was also swallowing every rally-point order ever
	# issued. Nothing failed: the click was read, the branch below was
	# simply never reached, and the marker on the ground stayed where it
	# was. Reported as right-click not moving the muster point, which is
	# exactly what it did.
	if _selected_building >= 0 and _state.buildings.has(_selected_building):
		var info: Dictionary = _state.buildings[_selected_building]
		if int(info["owner"]) == _state.player:
			# Shift+right-click on an enemy focus-fires an armed building on
			# it — the direct hotkey path, no "Target" button press needed.
			# A shift-held click that misses an enemy falls through to the
			# ordinary rally-point branch below rather than eating the click
			# on nothing, since a miss should still do SOMETHING useful.
			if shift:
				var def := BuildingSim.def_by_id(StringName(info["def_id"]))
				if def != null and def.damage > 0.0:
					var enemy := _enemy_squad_at(screen_position)
					if enemy >= 0:
						_peer.send(0, NetProtocol.encode_order_building_target(
							_selected_building, enemy), ENetPacketPeer.FLAG_RELIABLE)
						print("client: building %d targeting squad %d" % [_selected_building, enemy])
						return
			var rally_cell := _cell_under(screen_position)
			if rally_cell.x >= 0:
				_peer.send(0, NetProtocol.encode_order_rally(
					_selected_building, _state.space.index(rally_cell)),
					ENetPacketPeer.FLAG_RELIABLE)
				print("client: rally point set to %s" % rally_cell)
			return

	if _selected.is_empty():
		return

	# Right-clicking an ENEMY attacks it. No modifier, no separate key.
	#
	# Attack-move was Ctrl+right-click and also the A key — and A is bound
	# to camera pan (WASD), so it could never have worked. The result was a
	# player with no way to attack that they would find. Every RTS since
	# the nineties answers this the same way: right-click means "do the
	# obvious thing to that", which is move for ground and attack for an
	# enemy.
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


## The enemy SQUAD id under the cursor, or -1 — the squad half of
## `_enemy_cell_at` below, kept separate because a building's focus-fire
## target is named by squad id (so it can be tracked as it moves), not by
## the cell it happened to be standing on at click time. Buildings are not
## valid targets here: `Combat.resolve_buildings` only ever fires at
## squads (see its own `_find_squad_near` call), so offering a building
## would let a player arm a target the server can never actually use.
func _enemy_squad_at(screen_position: Vector2) -> int:
	var best := -1
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
			best = squad
	return best


## The "Target" button's landing click: assigns whatever enemy squad is
## under the cursor as the armed building's focus-fire target, or does
## nothing on a miss. Either way the arm-mode is spent — see the call site
## in `_handle_mouse_button`.
func _finish_target_pick(screen_position: Vector2) -> void:
	var building := _targeting_building
	_targeting_building = -1
	if not _connected or building < 0 or not _state.buildings.has(building):
		return
	var enemy := _enemy_squad_at(screen_position)
	if enemy < 0:
		print("client: no enemy under the cursor to target")
		return
	_peer.send(0, NetProtocol.encode_order_building_target(building, enemy),
		ENetPacketPeer.FLAG_RELIABLE)
	print("client: building %d targeting squad %d" % [building, enemy])


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
	_placing_facing = 0
	_placing_free_facing = -1
	_last_snap_cell = Vector2i(-1, -1)
	_update_placement_ghost()


## The armed def, if one is armed that turns FREELY and we are not mid-drag.
##
## As of D-096 that is everything except the access tower. Walls used to be
## excluded here — their rotation was mechanically load-bearing for joint
## alignment — but a segment now carries its own continuous angle and the
## joints are derived from real geometry, so nothing depends on a wall
## being one of six directions any more.
##
## The access tower is still out: its door has to open onto an actual
## neighbouring cell, so it keeps the 6-way V-controlled `_placing_facing`.
##
## Mid-drag returns null because a dragged run takes its angle from the
## line, not from the wheel — see `_update_drag_line_ghosts`.
func _free_rotating_armed_def() -> BuildingDef:
	if _placing == &"" or _placing_drag:
		return null
	var def := BuildingSim.def_by_id(_placing)
	if def == null or def.is_access_tower:
		return null
	return def


## The facing byte ([0, 256)) a freestanding placement would use RIGHT NOW
## — the player's scroll-chosen value if they've touched the wheel this
## placement, else the automatic default for the cell under the cursor.
## Shared by the ghost preview, the wheel handler (so the first notch turns
## FROM whatever's currently showing rather than jumping from a hardcoded
## 0) and the eventual build order, so the three can never disagree.
func _current_free_facing_byte() -> int:
	if _placing_free_facing >= 0:
		return _placing_free_facing
	var cell := _snapped_placement_cell(get_viewport().get_mouse_position())
	if cell.x < 0 or _state.space == null:
		return 0
	return PlacementJitter.yaw_byte(_state.space.index(cell))


## Snap the cursor's cell to the nearest cell adjacent to an EXISTING
## wall-family building, so a chain always lands truly connected instead
## of depending on pixel-perfect cursor placement (D-076 amendment). Only
## applies while a wall-family piece is armed (`footprint_radius == 0` —
## the same data-driven signal that already lets those defs chain without
## `_footprint_conflict` rejecting each other); every other building is
## returned unsnapped.
##
## Side effect: sets `_placing_facing` to face back toward the neighbour
## it snapped to, but ONLY the moment the snapped cell actually changes —
## see `_last_snap_cell`'s doc for why it isn't reset every frame.
func _snapped_placement_cell(screen_position: Vector2) -> Vector2i:
	var raw := _cell_under(screen_position)
	if raw.x < 0 or _state.space == null:
		return raw

	var def := BuildingSim.def_by_id(_placing)
	if def == null or def.footprint_radius != 0:
		_last_snap_cell = Vector2i(-1, -1)
		return raw

	# Playtest fix: hovering directly over a compatible upgrade target
	# (BuildingDef.upgrade_from — e.g. an existing wall segment, arming a
	# wall_tower) must land exactly there, not get pulled to a
	# neighbouring EMPTY cell by the snap-to-a-wall's-neighbour logic
	# below. That logic exists to CHAIN a new segment onto an existing
	# one — the opposite of what an upgrade wants, and without this a
	# player could never actually click the segment they meant to upgrade.
	if _upgrade_target_at(raw, def) >= 0:
		_last_snap_cell = Vector2i(-1, -1)
		return raw

	var best_cell := raw
	var best_distance := 999999
	var best_facing := 0
	var found := false
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if bool(info.get("destroyed", false)):
			continue
		var other_def := BuildingSim.def_by_id(StringName(info["def_id"]))
		if other_def == null or other_def.footprint_radius != 0:
			continue
		var other_cell := _state.space.from_index(int(info["cell"]))
		for i in range(TorusSpace.DIRECTIONS.size()):
			var candidate := _state.space.normalize(other_cell + TorusSpace.DIRECTIONS[i])
			var d := _state.space.distance(candidate, raw)
			if d < best_distance:
				best_distance = d
				best_cell = candidate
				# Opposite of "which side of the neighbour this candidate
				# sits on" — DIRECTIONS' negation is always the entry 3
				# slots further round the same 6-direction list.
				best_facing = (i + 3) % 6
				found = true

	# Only snap within a couple of cells of the actual cursor position —
	# otherwise one distant wall would keep pulling every placement
	# toward it regardless of where the player is actually pointing.
	if not found or best_distance > 2:
		_last_snap_cell = Vector2i(-1, -1)
		return raw

	if best_cell != _last_snap_cell:
		_placing_facing = best_facing
		_last_snap_cell = best_cell
	return best_cell


## Place the armed building, or do nothing if none is armed.
## Returns true if the click was consumed by placement.
func _place_armed_building(screen_position: Vector2) -> bool:
	if _placing == &"":
		return false
	# Typed explicitly: `_selected` is untyped, so a ternary over it has
	# no inferable type and the whole script fails to parse.
	var squad: int = int(_selected[0]) if not _selected.is_empty() else -1
	var def_id := _placing
	var free_def := _free_rotating_armed_def()
	var pose := _armed_pose(screen_position, free_def)
	_cancel_placement()
	var cell: Vector2i = pose["cell"]
	if cell.x < 0 or squad < 0:
		return true

	# No signed-range dance any more: `facing` is an UNSIGNED 0-255 byte on
	# the wire (NetProtocol's `put_u8`). It was `put_8`, and this call site
	# compensated by folding values >= 128 negative while the drag path did
	# not — so every angle in the upper half of the circle built rotated
	# differently from the ghost that aimed it. Making the field unsigned
	# fixes both paths at once and removes the thing there was to forget.
	var facing: int = int(pose["facing"])
	var order := _state.encode_build(squad, String(def_id), cell, facing, pose["offset"])
	if not order.is_empty():
		_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
		_note_build_site(cell, pose["offset"], BuildingSim.def_by_id(def_id), float(pose["angle"]))
		print("client: asked squad %d to found a %s at %s" % [squad, def_id, cell])
	return true


## Where an armed building would actually stand, and how it would be
## turned, for the point the cursor is over. THE one answer, shared by the
## placement ghost and the click that commits it (D-096).
##
## Sharing it is the whole point. The ghost and the build order used to
## compute their own answers, and when those two drifted apart the ghost
## promised one thing and the build delivered another — reported as a wall
## previewing correctly and then building in the wrong orientation.
##
## `free_def` is `_free_rotating_armed_def()`, passed in rather than
## re-derived so the caller's decision and this one cannot disagree either.
## Returns cell (-1,-1) when the cursor is not over the ground.
func _armed_pose(screen_position: Vector2, free_def: BuildingDef) -> Dictionary:
	var miss := {"cell": Vector2i(-1, -1), "facing": 0, "offset": Vector2.ZERO, "angle": 0.0}
	if _state.space == null:
		return miss

	# `facing` is the WIRE value and `angle` is radians for drawing. They
	# are not the same scale and must not be conflated: the access tower's
	# facing is one of 6 hex directions, everything else's is a 0-255 byte.
	# Returning both means no caller has to know which rule applies, and a
	# caller that guessed would silently draw a tower at ~1 degree instead
	# of pointing its door.
	#
	# The access tower also still SNAPS to its cell centre: its door opens
	# onto a neighbouring cell, so standing it off-centre would aim the
	# door at something that is not a cell boundary at all.
	if free_def == null:
		var snapped := _snapped_placement_cell(screen_position)
		if snapped.x < 0:
			return miss
		return {
			"cell": snapped, "facing": _placing_facing, "offset": Vector2.ZERO,
			"angle": _facing_rotation_y(_placing_facing),
		}

	var world := _world_under(screen_position)
	if not world.is_finite():
		return miss

	# A wall snaps to whatever wall is already there and pivots about that
	# join; everything else stands where the cursor is.
	#
	# The arithmetic lives in `WallRun.place_single` — deliberately NOT
	# here. An earlier version of this function had its own inline copy,
	# which meant the snap behaviour could only be checked by playing the
	# game, and it shipped wrong three times running. It is now a pure
	# function with tests that lay walls along a diagonal and assert they
	# come out collinear, so "what happens when I click" is something that
	# fails in CI rather than in a screenshot.
	if free_def.footprint_radius == 0:
		return WallRun.place_single(
			_state.space, free_def, _existing_wall_segments(), world,
			_placing_free_facing, _state.space.hex_size * WALL_SNAP_CELLS)

	var facing := _current_free_facing_byte()
	var entry := WallRun.entry(_state.space, world, 0.0)
	entry["facing"] = facing
	entry["angle"] = PlacementJitter.radians_of_byte(facing)
	return entry


## The world point a wall being placed here should attach to — the snap
## point if one is in reach, otherwise the raw ground point under the
## cursor. The one definition, so the ghost, the drag's start and the
## committed build all snap to the same place.
func _wall_attach_world(screen_position: Vector2, def: BuildingDef) -> Vector3:
	var world := _world_under(screen_position)
	if not world.is_finite() or def == null or def.footprint_radius != 0 \
			or def.is_access_tower or _state.space == null:
		return world
	var attach := WallRun.nearest_attach(
		_state.space, _existing_wall_segments(), world,
		_state.space.hex_size * WALL_SNAP_CELLS)
	return attach["point"] if bool(attach["found"]) else world


## Every wall-family segment this client knows about, in the shape
## `WallRun.nearest_attach` wants: true world centre, real angle, real
## length. Built from replicated state (D-096's pose), so it is the same
## geometry the renderer draws — snapping to a wall that is drawn somewhere
## else would be worse than not snapping at all.
func _existing_wall_segments() -> Array:
	var out := []
	if _state.space == null:
		return out
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if bool(info.get("destroyed", false)):
			continue
		var def: BuildingDef = _building_defs.get(wire_id, null)
		if def == null or def.footprint_radius != 0 or def.is_access_tower:
			continue
		var pos := _state.space.to_world(_state.space.from_index(int(info["cell"]))) \
			+ Vector3(float(info.get("offset_x", 0.0)), 0.0, float(info.get("offset_z", 0.0)))
		out.append({
			"pos": pos,
			"angle": PlacementJitter.radians_of_byte(int(info.get("facing", 0))),
			"length": def.mesh_size.x,
		})
	return out


## Finish a wall-family placement drag (D-076 amendment): a straight click
## (start == release cell) behaves exactly like an ordinary single
## placement; a genuine drag lays down the whole hex line from
## `_placing_drag_start` to the release point, round-robinned as a QUEUE
## across every currently-selected squad that can build this def — one
## squad alone still builds the whole run, just one segment after
## another, via `C2S_ORDER_BUILD_QUEUE`.
func _finish_placement_drag(end_screen_position: Vector2) -> void:
	var def_id := _placing
	var def := BuildingSim.def_by_id(def_id)
	var start_world := _placing_drag_start_world
	var end_world := _world_under(end_screen_position)
	# Captured BEFORE `_cancel_placement`, which clears `_placing` and the
	# scroll-chosen `_placing_free_facing` this depends on. Reading it after
	# would silently fall back to the default angle and throw away whatever
	# the player had aimed — the click would build at a different rotation
	# than the ghost it was aimed with.
	var click_pose := _armed_pose(end_screen_position, _free_rotating_armed_def())
	_cancel_placement()
	if def == null or _state.space == null \
			or not start_world.is_finite() or not end_world.is_finite():
		return

	var builders := _eligible_builders(def_id)
	if builders.is_empty():
		_notify_line_needs_a_builder()
		return

	# D-096: the run is laid along the TRUE dragged line — segments end to
	# end at the def's own length, each turned to the line's real angle —
	# rather than one segment per hex cell snapped to six directions.
	# `WallRun` owns that arithmetic (and its wrap-awareness) so it can be
	# tested without a client.
	var run := WallRun.segments(_state.space, def, start_world, end_world)

	# A CLICK, not a drag: take the pose straight from `_armed_pose`, which
	# is the exact thing the ghost was drawing a frame ago.
	#
	# This is the fix for a real bug. A wall click starts a drag (every
	# wall-family piece does), so it never went through
	# `_place_armed_building` and never saw the snap — the ghost showed a
	# wall attached to its neighbour and the build put one at the raw cursor
	# point instead. Deriving the single-segment case from the same function
	# the ghost uses is what makes "what you see is what you build" true for
	# walls too, rather than only for everything else.
	if run.size() <= 1 and click_pose["cell"].x >= 0:
		run = [{
			"cell": click_pose["cell"],
			"facing": int(click_pose["facing"]),
			"offset": click_pose["offset"],
		}]
	if run.is_empty():
		return

	var queues := {}
	for i in range(run.size()):
		var squad: int = builders[i % builders.size()]
		if not queues.has(squad):
			queues[squad] = []
		(queues[squad] as Array).append(run[i])

	for squad in queues:
		var mine: Array = queues[squad]
		var first := true
		for segment in mine:
			var cell: Vector2i = segment["cell"]
			var facing: int = int(segment["facing"])
			var offset: Vector2 = segment["offset"]
			var order := _state.encode_build(squad, String(def_id), cell, facing, offset) \
				if first else _state.encode_build_queue(squad, String(def_id), cell, facing, offset)
			first = false
			if not order.is_empty():
				_peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)
				_note_build_site(cell, offset, def, PlacementJitter.radians_of_byte(facing))
	print("client: drew a %d-segment %s run across %d squad(s)" % [run.size(), def_id, builders.size()])


## Nothing to build a drag-line with — silent would look like the drag
## itself did nothing (D-034's whole reason for the notice channel).
func _notify_line_needs_a_builder() -> void:
	print("client: select a squad that can build this before dragging a line")


## Which currently-selected squads can build `def_id` at all, mirroring
## `BuildingSim.can_build` client-side — the server re-checks everything
## regardless (D-002), this only decides how a drag's cells are split.
func _eligible_builders(def_id: StringName) -> Array:
	var def := BuildingSim.def_by_id(def_id)
	if def == null:
		return []
	var out := []
	for squad in _selected:
		var unit_def_id := StringName(String(_state.composition.get(squad, {}).get("def_id", "")))
		var unit := UnitRoster.by_id(unit_def_id)
		if unit != null and BuildingSim.can_build(def, unit.archetype):
			out.append(int(squad))
	return out


## The hex cells on a straight line from `a` to `b`, inclusive of both
## ends (D-076's drag-to-build-a-line tool). Standard cube-coordinate
## line-draw (lerp in cube space, round each step) over `space.delta`'s
## shortest wrapped vector — drag distances are at most a few dozen
## cells, so working in one unwrapped local frame around `a` needs no
## further wrap-awareness of its own.
func _hex_line(a: Vector2i, b: Vector2i) -> Array:
	var space := _state.space
	var delta := space.delta(a, b)
	var n := TorusSpace.hex_length(delta)
	var out := []
	if n <= 0:
		out.append(space.normalize(a))
		return out
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append(space.normalize(_round_axial(
			float(a.x) + float(delta.x) * t,
			float(a.y) + float(delta.y) * t)))
	return out


## Cube-coordinate rounding for `_hex_line`: the standard "round each of
## the three cube coordinates, then fix up whichever one drifted furthest
## from the constraint x+y+z=0" algorithm.
func _round_axial(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


func _cancel_placement() -> void:
	_placing = &""
	_placing_drag = false
	_placing_free_facing = -1
	if _placement_ghost != null:
		_placement_ghost.visible = false
	if _door_marker != null:
		_door_marker.visible = false
	_hide_drag_line_ghosts()


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

	# D-076: a wall/gate segment previews at its own thin/long size rather
	# than the square building box every other primitive used to force on
	# it — mesh_size zero (every pre-existing def) falls back to the old
	# hardcoded box exactly as before.
	var def := BuildingSim.def_by_id(_placing)
	var size := Vector3(2.4, 3.0, 2.4)
	if def != null and def.mesh_size != Vector3.ZERO:
		size = def.mesh_size

	# Mid-drag, the WHOLE line previews (one ghost box per cell it will
	# actually build), not just the single cell under the cursor — the
	# gap this closes: there was previously no way to see what a drag was
	# about to build before releasing the mouse.
	if _placing_drag:
		if _placement_ghost != null:
			_placement_ghost.visible = false
		if _door_marker != null:
			_door_marker.visible = false
		_update_drag_line_ghosts(size)
		return
	_hide_drag_line_ghosts()

	if _placement_ghost == null:
		var mesh := BoxMesh.new()
		mesh.size = size
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_placement_ghost = MeshInstance3D.new()
		_placement_ghost.mesh = mesh
		_placement_ghost.material_override = material
		add_child(_placement_ghost)
	else:
		(_placement_ghost.mesh as BoxMesh).size = size

	# THE SAME `_armed_pose` the click will commit (D-096). Previously the
	# ghost worked out its own position and angle and the build order
	# worked out another, and the two drifting apart is exactly what was
	# reported as a wall previewing correctly and then building rotated.
	# One function, one answer, no opportunity to disagree.
	var pose := _armed_pose(get_viewport().get_mouse_position(), _free_rotating_armed_def())
	var cell: Vector2i = pose["cell"]
	if cell.x < 0:
		_placement_ghost.visible = false
		if _door_marker != null:
			_door_marker.visible = false
		return

	var offset: Vector2 = pose["offset"]
	var world := _state.space.to_world(cell) + Vector3(offset.x, 0.0, offset.y)
	if _state.terrain_sampler.is_valid():
		world.y = _state.terrain_sampler.call(world.x, world.z)
	_placement_ghost.visible = true
	_placement_ghost.position = world + Vector3(0.0, 1.5, 0.0) + _lattice_offset_for(world)
	_placement_ghost.rotation.y = float(pose["angle"])

	var ok := _can_place_at(cell)
	var material := _placement_ghost.material_override as StandardMaterial3D
	material.albedo_color = Color(0.4, 0.95, 0.5, 0.45) if ok else Color(0.95, 0.35, 0.3, 0.45)

	# D-076: a bright marker toward the chosen door side, so placing a
	# wall_tower shows which cell will actually let a squad climb — the
	# whole point of confining access to one side rather than the whole
	# structure.
	if def != null and def.is_access_tower:
		if _door_marker == null:
			var marker_mesh := SphereMesh.new()
			marker_mesh.radius = 0.4
			marker_mesh.height = 0.8
			var marker_material := StandardMaterial3D.new()
			marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			marker_material.albedo_color = Color(1.0, 0.9, 0.2, 0.9)
			_door_marker = MeshInstance3D.new()
			_door_marker.mesh = marker_mesh
			_door_marker.material_override = marker_material
			add_child(_door_marker)
		var direction := Vector2(TorusSpace.DIRECTIONS[_placing_facing])
		var door_offset := _state.space.axial_offset_to_world(direction) * 0.75
		_door_marker.visible = true
		_door_marker.position = _placement_ghost.position + door_offset
	elif _door_marker != null:
		_door_marker.visible = false


## Y-axis rotation (radians) that turns a building's long/forward axis
## (local +X, per its BoxMesh) to point along hex `facing` (D-076
## amendment, generalised from the access-tower-only door marker). Used
## for both the placement ghost and every placed building's mesh, so a
## rotated wall segment reads the same way while you're aiming it as it
## does once it's built.
func _facing_rotation_y(facing: int) -> float:
	return _angle_of_offset(Vector2(TorusSpace.DIRECTIONS[posmod(facing, 6)]))


## Shared math behind `_facing_rotation_y`, taking an arbitrary axial
## offset rather than one of the 6 canonical directions — what
## `_direction_index_of` below needs to compare a multi-cell drag's real
## direction against each of the 6.
func _angle_of_offset(offset: Vector2) -> float:
	if _state.space == null:
		return 0.0
	var world_offset := _state.space.axial_offset_to_world(offset)
	return atan2(-world_offset.z, world_offset.x)


## Which of `TorusSpace.DIRECTIONS`' 6 canonical facings a (possibly
## multi-cell) axial delta most closely points along — the fix for a real
## bug: a drag-built line was sending every segment at whatever
## `_placing_facing` happened to be left over from BEFORE the drag
## started (a stale V-key rotation, or the snap that ran only on the
## START cell), not the direction the line actually runs. Compared by
## world-space angle, not by axial coordinates directly, because axial
## axes are not orthogonal and a naive component comparison picks the
## wrong neighbour close to the diagonals.
func _direction_index_of(delta: Vector2i) -> int:
	if delta == Vector2i.ZERO:
		return _placing_facing
	var target := _angle_of_offset(Vector2(delta))
	var best := 0
	var best_diff := INF
	for i in range(TorusSpace.DIRECTIONS.size()):
		var diff := absf(wrapf(_facing_rotation_y(i) - target, -PI, PI))
		if diff < best_diff:
			best_diff = diff
			best = i
	return best


## Preview the whole line a drag-to-build-a-line would actually build
## (D-076 amendment) — one ghost box per cell from `_placing_drag_start`
## to wherever the cursor is now, oriented and coloured exactly the way
## `_finish_placement_drag` will build it, so nothing about the release
## is a surprise.
func _update_drag_line_ghosts(size: Vector3) -> void:
	var def := BuildingSim.def_by_id(_placing)
	var end_world := _world_under(get_viewport().get_mouse_position())
	if def == null or not end_world.is_finite() or not _placing_drag_start_world.is_finite():
		_hide_drag_line_ghosts()
		return

	# D-096: preview the run through the SAME `WallRun.segments` that
	# `_finish_placement_drag` builds it with, so the boxes you are looking
	# at are the segments you will get — same count, same continuous
	# positions, same angle. The old version previewed one box per hex cell
	# at six possible angles while the build did something else entirely.
	var line := WallRun.segments(_state.space, def, _placing_drag_start_world, end_world)

	while _drag_ghost_pool.size() < line.size():
		var mesh := BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		add_child(instance)
		_drag_ghost_pool.append(instance)

	for i in range(_drag_ghost_pool.size()):
		var instance := _drag_ghost_pool[i]
		if i >= line.size():
			instance.visible = false
			continue
		var segment: Dictionary = line[i]
		var cell: Vector2i = segment["cell"]
		var offset: Vector2 = segment["offset"]
		(instance.mesh as BoxMesh).size = size
		var world := _state.space.to_world(cell) + Vector3(offset.x, 0.0, offset.y)
		if _state.terrain_sampler.is_valid():
			world.y = _state.terrain_sampler.call(world.x, world.z)
		instance.position = world + Vector3(0.0, 1.5, 0.0) + _lattice_offset_for(world)
		instance.rotation.y = PlacementJitter.radians_of_byte(int(segment["facing"]))
		instance.visible = true
		var ok := _can_place_at(cell)
		var material := instance.material_override as StandardMaterial3D
		material.albedo_color = Color(0.4, 0.95, 0.5, 0.45) if ok else Color(0.95, 0.35, 0.3, 0.45)


func _hide_drag_line_ghosts() -> void:
	for instance in _drag_ghost_pool:
		instance.visible = false


## The living building at `cell` that `def` would upgrade in place
## (playtest fix — see BuildingDef.upgrade_from's doc), or -1 if none
## qualifies. Mirrors server.gd's `_upgrade_target_at` exactly (own,
## complete, compatible) so the client only ever previews what the server
## would actually accept — advisory only, like everything else client-side
## about a placement; the server re-checks all three on arrival regardless.
func _upgrade_target_at(cell: Vector2i, def: BuildingDef) -> int:
	if def == null or def.upgrade_from.is_empty():
		return -1
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if bool(info.get("destroyed", false)):
			continue
		if _state.space.from_index(int(info["cell"])) != cell:
			continue
		if int(info["owner"]) != _state.player:
			continue
		if _derived_progress(int(wire_id), info) < 1.0:
			continue
		var existing_def := BuildingSim.def_by_id(StringName(info["def_id"]))
		if existing_def != null and def.upgrade_from.has(existing_def.id):
			return int(wire_id)
	return -1


## Whether the ground under the cursor looks buildable from here.
##
## Advisory only — the server is the authority (D-002) and re-checks on
## arrival, since a builder that walks for twenty seconds may find the
## ground taken. This exists so the preview is not misleading, not so the
## client can decide.
func _can_place_at(cell: Vector2i) -> bool:
	var placing_def := BuildingSim.def_by_id(_placing)
	var upgrade_target := _upgrade_target_at(cell, placing_def)
	for wire_id in _state.buildings:
		var info: Dictionary = _state.buildings[wire_id]
		if bool(info["destroyed"]):
			continue
		var at := _state.space.from_index(int(info["cell"]))
		if at == cell:
			# Playtest fix: a compatible in-place upgrade (BuildingDef.
			# upgrade_from — e.g. a wall_tower raised on an existing wall
			# segment) is the one exception to "occupied ground refuses a
			# build".
			if int(wire_id) != upgrade_target:
				return false

		# Ground claimed by somebody else's building (D-062). Shown here so
		# the ghost turns red before you click, rather than the order being
		# refused after a walk — but ADVISORY only, like everything else in
		# this preview: the server decides, and re-checks on arrival.
		#
		# Only buildings this client has been SHOWN are considered, so this
		# leaks nothing: an unexplored enemy town still refuses the build,
		# and finding out that way is scouting the hard way.
		if int(info["owner"]) != _state.player and not _state.are_allied(
				int(info["owner"]), _state.player):
			var def := BuildingSim.def_by_id(StringName(info["def_id"]))
			if def != null and def.no_build_radius > 0 \
					and _state.space.distance(cell, at) <= def.no_build_radius:
				return false
	if not _passable.is_empty():
		var index := _state.space.index(cell)
		if index < _passable.size() and _passable[index] == 0:
			return false
	# A resource node is ground you cannot build on, mirroring the server's
	# own check in `_is_buildable` so the ghost turns red before the click
	# rather than the order being refused after a twenty-second walk.
	#
	# `_state.nodes` is already fog-gated (it only holds what this client has
	# been shown), so this leaks nothing about unexplored ground — the same
	# reasoning as the enemy-claim check above.
	if _state.nodes.has(_state.space.index(cell)):
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
## map is clicked the same way, and against the DRAWN position — the
## placement table plus the same lattice offset the chunks use — so a
## node past the seam is clickable where it appears (D-035).
##
## Only known nodes can be here at all: the server fog-gates what
## `_state.nodes` (and so `_node_placed`) ever learns (D-061).
func _resource_cell_at(screen_position: Vector2) -> Vector2i:
	if _state.space == null:
		return Vector2i(-1, -1)

	var best := Vector2i(-1, -1)
	var best_distance := SELECT_CLICK_RADIUS_PX
	for cell in _node_placed:
		var world: Vector3 = _node_placed[cell]["world"]
		var drawn := world + _lattice_offset_for(world)
		if _camera.is_position_behind(drawn):
			continue
		var distance := _camera.unproject_position(drawn).distance_to(screen_position)
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


## WASD pans relative to WHERE THE CAMERA IS LOOKING, not to world axes.
##
## Once the view can rotate this is the only defensible reading of "W":
## the player means "up the screen", and after a 90-degree turn the world
## axis that used to mean up-screen means right-screen. Panning in world
## space with a rotated camera makes the keys feel like they have been
## shuffled, which is the standard complaint about RTS cameras that get
## this wrong.
func _pan_camera(delta: float) -> void:
	# Q/E turn continuously while held, polled the same way WASD is —
	# checked first and independently of movement, so turning and panning
	# at once (aiming while sliding along a ridge) both apply in the same
	# frame rather than one blocking the other via an early return.
	var turn := 0.0
	if Input.is_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_key_pressed(KEY_E):
		turn -= 1.0
	if turn != 0.0:
		_set_camera_yaw(_camera_yaw + turn * CAMERA_YAW_RATE * delta)

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
	_camera_target += move.normalized().rotated(Vector3.UP, _camera_yaw) \
		* _pan_speed * delta
	_wrap_camera_target()
	_update_camera()


## Turn the view. `to` is absolute radians; the compass calls this with 0.
##
## Normalised so the stored yaw can never wander off after a few hundred
## turns and so the compass has one canonical value to draw.
func _set_camera_yaw(to: float) -> void:
	_camera_yaw = fposmod(to, TAU)
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


## Place the camera behind and above its target, spun by `_camera_yaw`.
##
## The offset is the same one this always used; it is simply rotated about
## UP now. Everything that reads the camera back — ray-picking a cell,
## projecting a squad's footprint for selection, choosing which lattice
## copy of a thing to draw (D-035/D-045) — goes through `project_ray_*` or
## `unproject_position` and therefore follows the rotation for free. That
## is the whole reason rotation could be added without touching selection,
## culling or terrain tiling: none of them ever assumed a fixed heading.
func _update_camera() -> void:
	if _camera == null:
		return
	var offset := Vector3(0.0, _camera_height, _camera_height * 0.6) \
		.rotated(Vector3.UP, _camera_yaw)
	_camera.position = _camera_target + offset
	_camera.look_at(_camera_target, Vector3.UP)
	if _nav_ring_frame != null:
		_nav_ring_frame.queue_redraw()


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
## Sized explicitly by `_layout_lobby` (see its doc comment for why this
## cannot be done with anchors), the same reason `_hud_layer`'s own
## children are.
var _lobby_backdrop: ColorRect
var _lobby_root: VBoxContainer
var _lobby_seat_rows: VBoxContainer
## The seat rows scroll independently of the header/rule above them (see
## `_build_lobby_ui`) — a lobby of 20 seats must not push the actions row
## and the chat panel below it off the bottom of the screen.
var _lobby_seat_list: VBoxContainer
var _lobby_title: Label
var _lobby_help: Label
var _map_rows: VBoxContainer
var _map_preview: TextureRect
var _map_blurb: Label
var _start_button: Button
var _add_ai_button: Button

## Dev-testing sandbox toggles (D-0xx), same rebuild-on-change shape as
## the map settings panel just above.
var _sandbox_rows: VBoxContainer

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
	# `max` comes from MapSettings so the spinner can always show a rolled
	# seed (D-100), and `reroll` puts a button beside it — the server draws
	# the number, this only asks for one.
	{"key": "seed", "label": "Seed", "kind": "int",
		"min": 0, "max": MapSettings.SEED_MAX, "reroll": true},
	{"key": "sea_level", "label": "Sea level", "kind": "slider", "min": 0.05, "max": 0.9},
	{"key": "mountain_level", "label": "Mountain line", "kind": "slider", "min": 0.1, "max": 0.98},
	# Reads in CELLS, not as the raw parameter (D-101). "Landmass count"
	# was the bug stated out loud: it sat at 2.50 on every map size
	# because the terrain was defined in fractions of the map, so picking
	# a bigger map bought a higher-resolution drawing of the same world.
	# Now the parameter is a density and the readout is the size it
	# produces — the same at every size, which is the fix made visible.
	{"key": "elevation_frequency", "label": "Landmass size", "kind": "slider",
		"min": 0.5, "max": 8.0, "readout": "cells"},
	{"key": "height_scale", "label": "Relief", "kind": "slider", "min": 0.5, "max": 20.0},
]


## A framed panel with a header — the repeated unit of this screen.
## `expand`: whether this panel should absorb whatever vertical space its
## siblings in a VBoxContainer leave over (the chat log, the map-generation
## settings), versus sizing to its own content (the seat list, the map
## preview). Without this every panel sized to content, and the lobby's
## own outer VBoxContainer had nothing left inside it to stretch — which is
## the actual cause of a lobby that filled a fraction of a wide window and
## left the rest bare: nothing in the tree ever claimed the leftover space,
## Containers only ever shrink to fit unless told otherwise.
func _lobby_panel(title: String, parent: Control, expand := false) -> VBoxContainer:
	var frame := PanelContainer.new()
	var style := HudTheme.stylebox(HudTheme.BG_SOLID, HudTheme.BORDER, 1, HudTheme.RADIUS_LG)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	frame.add_theme_stylebox_override("panel", style)
	if expand:
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	if expand:
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(column)

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE)
	header.modulate = HudTheme.ACCENT_BRIGHT
	column.add_child(header)

	var rule := ColorRect.new()
	rule.color = HudTheme.RULE
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	column.add_child(rule)
	return column


## Buttons get their own styling because the default Godot theme looks
## nothing like the rest of this screen. Pill-shaped, per the reference
## design's buttons throughout (the lobby's "Start match", the defeat
## screen's "Back to lobby") — one shared shape rather than the game-menu's
## flatter list rows, which is a deliberate simplification: this project
## has one button widget, and giving the menu a second, un-pooled row
## style would be a second thing to keep in sync with this one for no
## visible-elsewhere benefit.
func _styled_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", HudTheme.BODY_SIZE + 1)
	button.focus_mode = Control.FOCUS_NONE

	var font_colour_keys := {
		"normal": "font_color", "hover": "font_hover_color",
		"pressed": "font_pressed_color", "disabled": "font_disabled_color",
	}
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = accent.darkened(0.72)
		var text_colour := HudTheme.TEXT_BRIGHT
		if state == "hover":
			style.bg_color = accent.darkened(0.55)
		elif state == "pressed":
			style.bg_color = accent.darkened(0.35)
		elif state == "disabled":
			style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
			text_colour = HudTheme.TEXT_DISABLED
		style.border_color = accent if state != "disabled" else HudTheme.BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(HudTheme.RADIUS_PILL)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override(font_colour_keys[state], text_colour)
	return button


# --- in-game menu (D-063) ---------------------------------------------
#
# ## It does not pause, and that is not a shortcut
#
# The server is the authority and runs its own clock (D-002/D-020). A
# client cannot pause a match any more than it can move a squad — and in
# a multiplayer game it must not, because "pause" would either stop
# everyone else's game or, worse, stop only this player's view while their
# army kept being attacked. So the menu is an overlay over a running
# match, and the world keeps moving behind it. That is the honest
# behaviour rather than a missing feature, which is why the menu says so
# on its face.
#
# The one real consequence: the menu must never swallow the whole screen's
# input, or a player could not react to what they can see happening behind
# it. Only the panel itself takes clicks; the backdrop is deliberately
# thin and non-blocking.


## Settings the client can actually honour today.
##
## Deliberately short. Everything here maps to a real knob that exists —
## anything else would be a control that appears to do something and does
## not, which is worse than an absent option. Graphics quality, resolution
## and keybind remapping are all missing for the same reason: there is no
## LOD toggle to bind, no resolution list, and no keybind indirection to
## rewrite (the keys are read straight from the event in `_handle_key`).
const SETTINGS_PATH := "user://settings.cfg"

## The margin between the lobby's edge panels and the window's own edge,
## in design-space units (so it scales with everything else — see
## `_build_lobby_ui`).
const LOBBY_MARGIN := Vector2(40.0, 24.0)
## The right-hand column's width (map preview + generation settings).
## Fixed, not proportional — the reference design's own
## `grid-template-columns:1fr 400px`, so growing the window gives the
## seat list and chat more room rather than stretching a terrain preview
## into something blurrier.
const LOBBY_RIGHT_COLUMN_WIDTH := 400.0

## One seat row plus its separation — how tall the seat list's scroll
## window is sized against (see `_build_lobby_ui`), so "how many rows show
## before it scrolls" is one number rather than a viewport height nobody
## chose on purpose.
const SEAT_ROW_HEIGHT := 44.0


func _build_game_menu() -> void:
	_game_menu_layer = CanvasLayer.new()
	# Above the HUD (0) but BELOW the lobby (10): the lobby is a screen
	# that replaces the world, and the in-game menu is an overlay on it.
	_game_menu_layer.layer = 5
	_game_menu_layer.visible = false
	add_child(_game_menu_layer)

	# A dim wash rather than an opaque backdrop, and one that does NOT
	# take mouse input — see the note above about not blindfolding a
	# player whose base is being attacked while they read a menu.
	var backdrop := ColorRect.new()
	backdrop.color = HudTheme.BG_VOID.darkened(0.3)
	backdrop.color.a = 0.5
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_menu_layer.add_child(backdrop)

	var centre := CenterContainer.new()
	centre.anchor_right = 1.0
	centre.anchor_bottom = 1.0
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_menu_layer.add_child(centre)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	centre.add_child(row)

	var column := _lobby_panel("GAME MENU", row)
	column.custom_minimum_size = Vector2(300.0, 0.0)

	var running := Label.new()
	running.text = "The match keeps running while this is open."
	running.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE + 1)
	running.modulate = HudTheme.TEXT_FAINT
	running.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	running.custom_minimum_size = Vector2(280.0, 0.0)
	column.add_child(running)

	var resume := _styled_button("Resume", HudTheme.ACCENT)
	resume.pressed.connect(_toggle_game_menu)
	column.add_child(resume)

	var settings := _styled_button("Settings", HudTheme.NEUTRAL)
	settings.pressed.connect(_toggle_settings)
	column.add_child(settings)

	# Disabled, and it says why rather than pretending to be busy. There is
	# no save system: the authority is the server, so a save is a snapshot
	# of ITS sims (squads, buildings, economy, match state, RNG position
	# and tick), and none of that is serialised anywhere yet. A button that
	# silently did nothing would be the declared-and-unread shape this
	# project keeps meeting (D-061), built on purpose.
	var save := _styled_button("Save game", HudTheme.NEUTRAL)
	save.disabled = true
	save.tooltip_text = "Not yet implemented — saves need server-side state serialisation"
	column.add_child(save)

	var to_lobby := _styled_button("Leave match", HudTheme.NEUTRAL)
	to_lobby.tooltip_text = "End the match and return everyone to the lobby."
	to_lobby.pressed.connect(_on_leave_match_pressed)
	column.add_child(to_lobby)

	var quit := _styled_button("Exit game", HudTheme.DANGER)
	quit.pressed.connect(_on_quit_pressed)
	column.add_child(quit)

	_settings_panel = _build_settings_panel(row)
	_settings_panel.visible = false


## The settings pane, opened beside the menu rather than replacing it, so
## a player can see what they are leaving.
func _build_settings_panel(parent: Control) -> Control:
	var frame := VBoxContainer.new()
	parent.add_child(frame)
	var column := _lobby_panel("SETTINGS", frame)
	column.custom_minimum_size = Vector2(320.0, 0.0)

	var fullscreen := CheckBox.new()
	fullscreen.text = "Fullscreen"
	fullscreen.focus_mode = Control.FOCUS_NONE
	fullscreen.button_pressed = DisplayServer.window_get_mode() in [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	fullscreen.toggled.connect(_on_fullscreen_toggled)
	column.add_child(fullscreen)

	column.add_child(_settings_slider("Camera pan speed", 6.0, 48.0,
		_pan_speed, _on_pan_speed_changed))
	column.add_child(_settings_slider("HUD scale", HudLayout.MIN_SCALE,
		HudLayout.MAX_SCALE, _hud_scale_override if _hud_scale_override > 0.0 else 1.0,
		_on_hud_scale_changed))

	var auto_hud := CheckBox.new()
	auto_hud.text = "Scale HUD to window automatically"
	auto_hud.focus_mode = Control.FOCUS_NONE
	auto_hud.button_pressed = _hud_scale_override <= 0.0
	auto_hud.toggled.connect(_on_hud_auto_toggled)
	column.add_child(auto_hud)

	var close := _styled_button("Back", HudTheme.NEUTRAL)
	close.pressed.connect(_toggle_settings)
	column.add_child(close)
	return frame


## A labelled slider that shows its own value. Its own function because
## three of them differing only in range is exactly the kind of thing that
## drifts when copy-pasted.
func _settings_slider(label_text: String, low: float, high: float, value: float,
		on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "%s: %.1f" % [label_text, value]
	label.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE + 2)
	label.modulate = HudTheme.TEXT
	box.add_child(label)

	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.1
	slider.value = value
	slider.custom_minimum_size = Vector2(280.0, 0.0)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void:
		label.text = "%s: %.1f" % [label_text, v]
		on_change.call(v))
	box.add_child(slider)
	return box


func _toggle_game_menu() -> void:
	if _game_menu_layer == null:
		return
	_game_menu_layer.visible = not _game_menu_layer.visible
	if not _game_menu_layer.visible and _settings_panel != null:
		_settings_panel.visible = false


func _toggle_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = not _settings_panel.visible


func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on
		else DisplayServer.WINDOW_MODE_WINDOWED)
	# The HUD re-lays-out from the viewport's own size_changed signal, so
	# nothing else is needed here.
	_save_settings()


func _on_pan_speed_changed(value: float) -> void:
	_pan_speed = value
	_save_settings()


func _on_hud_scale_changed(value: float) -> void:
	_hud_scale_override = value
	_layout_hud()
	_save_settings()


func _on_hud_auto_toggled(automatic: bool) -> void:
	_hud_scale_override = 0.0 if automatic else _hud_scale
	_layout_hud()
	_save_settings()


## Leave the match and go back to the lobby screen (D-075).
##
## This used to disconnect, and the doc comment above it claimed it went
## "back to the lobby screen" — it could not. A disconnect tears the seat
## down, so there was nothing to return to and the player sat looking at
## a dead match until they closed the window.
##
## So it asks instead, and stays connected. The server decides: it ends
## the match, drops the world and re-broadcasts the seats, and the lobby
## reappears because `_state.in_lobby()` is true again. Nothing here has
## to draw a lobby, and nothing here decides a match is over — a client
## that could would be a client that decides for everyone (D-002).
func _on_leave_match_pressed() -> void:
	_toggle_game_menu()
	print("client: leaving match")
	if _peer != null and _connected:
		_peer.send(0, NetProtocol.encode_leave_match(), ENetPacketPeer.FLAG_RELIABLE)


func _on_quit_pressed() -> void:
	# `_connected` as well as the peer: `_peer` is the wrapper object and
	# is never nulled, so a peer that has already gone away still passes a
	# null check and `peer_disconnect` reports `Parameter "peer" is null`.
	# Line 262 has always had this right.
	if _peer != null and _connected:
		_peer.peer_disconnect()
	get_tree().quit(0)


## Drop everything drawn for a match that has ended (D-075).
##
## The client's visuals are keyed by entity id, and ids RESTART: both sims
## mint them from an array length, so the next match's squad 0 would find
## the last match's MultiMesh sitting under its id and inherit its unit
## type, colour and soldier count.
##
## Terrain goes too, rather than being kept as an optimisation. The lobby
## can change the map's size, seed and preset between matches (D-049), so
## a kept mesh is only correct until somebody moves a slider — and the
## failure would be a world that renders perfectly while squads walk
## through hills that are not there.
func _teardown_match() -> void:
	print("client: match over — back to the lobby")
	_free_nodes(_squad_nodes)
	_free_nodes(_building_nodes)
	_free_nodes(_wall_joint_nodes)
	_free_nodes(_health_bars)
	# Tree chunks: freeing each chunk root takes its MultiMeshes with it.
	for key in _tree_chunks:
		(_tree_chunks[key]["root"] as Node3D).queue_free()
	_tree_chunks.clear()
	_node_placed.clear()
	for fall in _fallings:
		(fall["node"] as MeshInstance3D).queue_free()
	_fallings.clear()
	_terrain_gen = null
	_free_nodes(_selection_discs)
	_free_nodes(_progress_anchor)
	_free_nodes(_queue_anchor)

	if _terrain_root != null:
		_terrain_root.queue_free()
		_terrain_root = null
	_terrain_built = false

	_explored.clear()
	_scout_home.clear()
	_control_groups.clear()
	_building_defs.clear()
	_building_ground_lift.clear()
	_building_top_offset.clear()
	_gate_visual_open.clear()
	_missile_next_launch.clear()
	_selected = []
	_selected_building = -1

	_state.leave_match()


## Free any Node held in a lookup, then empty it. The stores this runs
## over hold a mix of nodes and plain values, so it checks rather than
## assuming — a `queue_free()` on a Vector3 is a crash, and a node left
## unfreed is a leak that only shows up after several matches.
func _free_nodes(store: Dictionary) -> void:
	for key in store:
		var held = store[key]
		if held is Node:
			held.queue_free()
	store.clear()


## Notice the match starting and ending. The server is the authority on
## both (D-002); this only reacts to the phase it is told.
func _sync_match_lifecycle() -> void:
	var running: bool = _state.welcomed and not _state.in_lobby()
	if _in_match and not running:
		_teardown_match()
	_in_match = running


## Settings persist to `user://settings.cfg` — a plain ConfigFile, because
## it is three values and a text format that a human can read and delete
## is worth more here than anything cleverer.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("client", "pan_speed", _pan_speed)
	config.set_value("client", "hud_scale_override", _hud_scale_override)
	config.set_value("client", "fullscreen",
		DisplayServer.window_get_mode() in [
			DisplayServer.WINDOW_MODE_FULLSCREEN,
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_pan_speed = clampf(float(config.get_value("client", "pan_speed", CAMERA_PAN_SPEED)),
		6.0, 48.0)
	_hud_scale_override = float(config.get_value("client", "hud_scale_override", 0.0))
	if _hud_scale_override > 0.0:
		_hud_scale_override = clampf(_hud_scale_override,
			HudLayout.MIN_SCALE, HudLayout.MAX_SCALE)
	# Fullscreen is NOT restored in capture mode: a headless render is
	# given its resolution on the command line, and a saved preference
	# fighting that would make screenshots depend on whoever ran last.
	if _run_seconds <= 0.0 and bool(config.get_value("client", "fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# --- defeat screen ------------------------------------------------------
#
# ## Why this only shows ONE stat, and no roster
#
# The reference design's defeat screen names an epoch reached, men lost,
# buildings razed, and every other player's fighting/eliminated status.
# None of that is honest to build yet: epochs are M9 design, not shipped
# code (see CLAUDE.md); nothing counts a player's own losses or razed
# buildings anywhere in this project; and fog of war means this client
# only ever receives OTHER players' squads and buildings it can currently
# see, so it structurally cannot know whether hjalmar is still fighting or
# already out — showing a guess dressed as a fact is exactly the kind of
# "numbers all correct while the picture is wrong" defect CLAUDE.md's own
# history is full of. So this screen shows only what is actually true: how
# long THIS player's own army lasted, derived from the same match clock
# the top bar already reads.
#
# ## What "defeated" means here
#
# Mirrors `MatchState.update`'s own rule exactly (defeated = zero living
# squads AND zero living buildings) rather than inventing a client-side
# approximation, because a client that disagreed with the server about
# who is defeated would eventually show this screen to a player who was
# not, or never show it to one who was. `_ever_had_army` exists so the
# check cannot fire in the one frame after a match starts and before the
# founding party's squad has arrived over the wire — a real race, since
# RUNNING begins the instant the lobby starts, not once the first curve
# lands.
func _build_defeat_screen() -> void:
	_defeat_layer = CanvasLayer.new()
	# Above the HUD and the in-game menu, below the lobby (which replaces
	# the world entirely and always wins).
	_defeat_layer.layer = 7
	_defeat_layer.visible = false
	add_child(_defeat_layer)

	var backdrop := ColorRect.new()
	backdrop.color = HudTheme.BG_VOID
	backdrop.color.a = 0.66
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	# The match keeps running for everyone else — the same reason the
	# in-game menu's backdrop does not block input, though a defeated
	# player has no army left to give orders to either way.
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_defeat_layer.add_child(backdrop)

	var centre := CenterContainer.new()
	centre.anchor_right = 1.0
	centre.anchor_bottom = 1.0
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_defeat_layer.add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(360.0, 0.0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = "ELIMINATED"
	eyebrow.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE)
	eyebrow.modulate = HudTheme.ACCENT
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(eyebrow)

	var headline := Label.new()
	headline.text = "Defeated"
	headline.add_theme_font_size_override("font_size", HudTheme.DISPLAY_SIZE + 24)
	headline.modulate = HudTheme.TEXT_BRIGHT
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(headline)

	var sub := Label.new()
	sub.text = "Your last squad and building are gone. The match continues without you."
	sub.add_theme_font_size_override("font_size", HudTheme.BODY_SIZE)
	sub.modulate = HudTheme.TEXT_DIM
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(360.0, 0.0)
	column.add_child(sub)

	_defeat_time_label = Label.new()
	_defeat_time_label.add_theme_font_size_override("font_size", HudTheme.DISPLAY_SIZE)
	_defeat_time_label.modulate = HudTheme.TEXT_BRIGHT
	_defeat_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_defeat_time_label)

	var time_caption := Label.new()
	time_caption.text = "TIME HELD"
	time_caption.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE - 1)
	time_caption.modulate = HudTheme.TEXT_GHOST
	time_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(time_caption)

	var button_row := CenterContainer.new()
	button_row.mouse_filter = Control.MOUSE_FILTER_STOP
	var leave := _styled_button("Leave match", HudTheme.NEUTRAL)
	leave.pressed.connect(_on_leave_match_pressed)
	button_row.add_child(leave)
	column.add_child(button_row)


## Whether THIS player owns a building that is not destroyed — the other
## half of `MatchState`'s own elimination test (squads alone is not the
## rule: a founder spent on a town hall has zero squads for a moment and
## must not read as defeated while that hall stands — see D-055's history
## in CLAUDE.md).
##
## Judged on `"destroyed"`, not `health_fraction`. The latter is explicitly
## EXCLUDED from `building_hash()` (see that function's own comment) for
## the same reason it is the wrong field here: it varies continuously and
## a client legitimately lags a tick, so a just-destroyed building could
## still be carrying its last nonzero health here — which silently kept
## `_ever_had_army` true forever, and was the actual cause of a player
## whose last building fell never seeing the defeat screen.
func _owned_living_building_count() -> int:
	var n := 0
	for id in _state.buildings:
		var info: Dictionary = _state.buildings[id]
		if int(info.get("owner", -1)) == _state.player \
				and not bool(info.get("destroyed", false)):
			n += 1
	return n


func _refresh_defeat() -> void:
	if _defeat_layer == null:
		return
	if not _connected or _state.in_lobby():
		_defeat_layer.visible = false
		_ever_had_army = false
		_defeated = false
		return

	var has_army := _state.living_squad_count() > 0 or _owned_living_building_count() > 0
	if has_army:
		_ever_had_army = true
		_defeated = false
		_defeat_layer.visible = false
		return

	if _ever_had_army and not _defeated:
		_defeated = true
		_defeat_time_held = _state.match_elapsed()
	_defeat_layer.visible = _defeated
	if _defeated:
		_defeat_time_label.text = HudLayout.clock_text(_defeat_time_held)


func _build_lobby_ui() -> void:
	_lobby_layer = CanvasLayer.new()
	# Above the HUD, not merely after it: CanvasLayers draw in layer
	# order, so a backdrop on the same layer let the game HUD show
	# straight through the lobby.
	_lobby_layer.layer = 10
	_lobby_layer.visible = false
	add_child(_lobby_layer)
	# Scaled with the HUD, and built after it — so it takes the scale here
	# rather than waiting for the first resize to be laid out correctly.
	_lobby_layer.transform = Transform2D().scaled(Vector2(_hud_scale, _hud_scale))

	_lobby_backdrop = ColorRect.new()
	# Fully opaque: there is no world behind the lobby yet, because the
	# map is not generated until the match starts (D-049). Sized by
	# `_layout_lobby`, not anchors — see that function's doc comment.
	_lobby_backdrop.color = HudTheme.BG_VOID
	_lobby_layer.add_child(_lobby_backdrop)

	# `_layout_lobby` positions and sizes this against the design-space
	# rect with a fixed margin, the same reason the HUD proper is laid out
	# in code rather than with anchors (see `hud_layout.gd`'s header
	# comment on scale vs. anchoring) — anchors on a Control with no
	# Control ancestor resolve against the real, UNSCALED viewport, and
	# `_lobby_layer`'s own transform then scales the result again on top of
	# that, so an anchored fill only happens to reach the window's edges
	# when the HUD's scale is exactly 1.0. Below or above that the anchored
	# rect and the real window disagree by exactly the scale factor — which
	# is invisible at the one size (1280x720) this was first tried at, and
	# a visible gap or overflow at every other one.
	_lobby_root = VBoxContainer.new()
	_lobby_root.add_theme_constant_override("separation", 12)
	_lobby_layer.add_child(_lobby_root)

	_lobby_title = Label.new()
	_lobby_title.text = "Multiplayer lobby"
	_lobby_title.add_theme_font_size_override("font_size", HudTheme.DISPLAY_SIZE + 10)
	_lobby_title.modulate = HudTheme.TEXT_BRIGHT
	_lobby_root.add_child(_lobby_title)

	# Fills whatever height the title leaves — the reference design's
	# `grid-template-columns:1fr 400px` row, made of two VBoxContainers
	# instead of a CSS grid: `left` expands to take the leftover WIDTH,
	# `right` stays at its own minimum (see below), and both expand to
	# fill the leftover HEIGHT so their own inner panels have something to
	# stretch into in turn.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby_root.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560.0, 0.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	# Expands the same way the chat panel below it does, so the two split
	# `left`'s leftover height evenly (VBoxContainer gives equal-ratio
	# expand children equal shares by default) rather than PLAYERS sitting
	# at a minimum height with chat absorbing everything else.
	_lobby_seat_rows = _lobby_panel("PLAYERS", left, true)

	# Seats scroll on their own past a handful of rows, rather than the
	# panel growing to fit up to twenty of them (D-018) and pushing the
	# actions row and chat off the bottom of the screen. `custom_minimum_size`
	# is the floor for a short window; SIZE_EXPAND_FILL is what lets it
	# actually grow to match chat's height on a tall one, the same pairing
	# every other expanding panel here uses.
	var seat_scroll := ScrollContainer.new()
	seat_scroll.custom_minimum_size = Vector2(0.0, SEAT_ROW_HEIGHT * 4.5)
	seat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	seat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lobby_seat_rows.add_child(seat_scroll)
	_lobby_seat_list = VBoxContainer.new()
	_lobby_seat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_seat_list.add_theme_constant_override("separation", 6)
	seat_scroll.add_child(_lobby_seat_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	left.add_child(actions)

	_add_ai_button = _styled_button("+  Add AI player", HudTheme.NEUTRAL)
	_add_ai_button.pressed.connect(_on_add_ai_pressed)
	actions.add_child(_add_ai_button)

	_start_button = _styled_button("Start match", HudTheme.ACCENT)
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.pressed.connect(_on_start_pressed)
	actions.add_child(_start_button)

	_lobby_help = Label.new()
	_lobby_help.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE + 1)
	_lobby_help.modulate = HudTheme.TEXT_GHOST
	_lobby_help.custom_minimum_size = Vector2(600.0, 0.0)
	_lobby_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_lobby_help)

	# Chat sits under the player list, where the genre puts it — and is the
	# one panel on the left that should EXPAND, so the seat list stays
	# sized to its own rows instead of stretching gaps between them.
	var chat_column := _lobby_panel("Chat", left, true)
	_chat_log_label = Label.new()
	_chat_log_label.add_theme_font_size_override("font_size", HudTheme.BODY_SIZE + 1)
	_chat_log_label.custom_minimum_size = Vector2(0.0, 96.0)
	_chat_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_chat_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_log_label.modulate = HudTheme.TEXT_MUTED
	chat_column.add_child(_chat_log_label)

	_chat_entry = LineEdit.new()
	_chat_entry.placeholder_text = "Say something…"
	_chat_entry.add_theme_font_size_override("font_size", 14)
	_chat_entry.max_length = NetProtocol.CHAT_MAX_CHARS
	# No minimum width of its own: it fills whatever width `left` has,
	# which is the whole point of `left` expanding in the first place.
	_chat_entry.text_submitted.connect(_on_chat_submitted)
	chat_column.add_child(_chat_entry)

	# Fixed width (see `LOBBY_RIGHT_COLUMN_WIDTH`'s doc comment) — no
	# horizontal expand flag, so `left` absorbs every pixel a wider window
	# adds instead of the two splitting it.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(LOBBY_RIGHT_COLUMN_WIDTH, 0.0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)

	var preview_column := _lobby_panel("MAP", right)
	_map_preview = TextureRect.new()
	_map_preview.custom_minimum_size = Vector2(0.0, 168.0)
	_map_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_column.add_child(_map_preview)

	_map_blurb = Label.new()
	_map_blurb.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE + 1)
	_map_blurb.modulate = HudTheme.TEXT_FAINT
	_map_blurb.custom_minimum_size = Vector2(0.0, 32.0)
	_map_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_column.add_child(_map_blurb)

	# The one panel on the right that should EXPAND — see the doc comment
	# on `chat_column` above for the same reasoning mirrored.
	_map_rows = _lobby_panel("GAME SETTINGS", right, true)
	_sandbox_rows = _lobby_panel("SANDBOX (dev testing)", right)

	# Laid out once against the CURRENT window immediately, rather than
	# waiting for the first resize signal — without this the lobby sits at
	# whatever size a freshly-built, never-laid-out Control defaults to
	# (effectively unsized) until a player happens to resize the window.
	_layout_hud()


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
		return HudTheme.NEUTRAL
	var def := CivRoster.by_id(StringName(civ))
	return def.colour if def != null else HudTheme.TEXT_DIM


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
	for child in _lobby_seat_list.get_children():
		child.queue_free()
	for i in range(seats.size()):
		_lobby_seat_list.add_child(_seat_row(seats[i], i))

	var admin := _state.is_admin()
	_add_ai_button.disabled = not admin
	_start_button.disabled = not admin or seats.size() < 2
	_start_button.text = "Start match" if admin else "Waiting for host"

	if admin:
		_lobby_help.text = "Click a civilisation to change it. Only you can seat AI players and start the match."
	else:
		_lobby_help.text = "Choose your civilisation. The host starts the match."

	_refresh_map_panel()
	_refresh_sandbox_panel()


## Three admin-only checkboxes over `_state.lobby`'s `sandbox`/
## `instant_build`/`ai_economy_only` fields (D-0xx) — same rebuild-on-
## change shape `_refresh_map_panel` uses just above, and the same
## `LOBBY_SET_OPTION` channel a map slider sends through (a "key=value"
## pair, not one opcode per flag). Visible to everyone so a non-admin can
## at least see the flags a host has enabled; only the admin can flip them.
const SANDBOX_OPTIONS := [
	{"key": "sandbox", "label": "Sandbox mode (enables cheats below)"},
	{"key": "instant_build", "label": "Instant construction & production"},
	{"key": "ai_economy_only", "label": "AI civs: economy only, never attack"},
]


func _refresh_sandbox_panel() -> void:
	if _sandbox_rows == null:
		return
	for child in _sandbox_rows.get_children():
		if child.get_index() > 1:
			child.queue_free()

	var admin := _state.is_admin()
	for option in SANDBOX_OPTIONS:
		var key := String(option["key"])
		var box := CheckBox.new()
		box.text = String(option["label"])
		box.add_theme_font_size_override("font_size", 14)
		box.button_pressed = bool(_state.lobby.get(key, false))
		box.disabled = not admin
		box.toggled.connect(_on_sandbox_option_toggled.bind(key))
		_sandbox_rows.add_child(box)

	if not admin:
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 13)
		note.modulate = Color(0.52, 0.55, 0.60)
		note.text = "Only the host can change these."
		_sandbox_rows.add_child(note)


func _on_sandbox_option_toggled(pressed: bool, key: String) -> void:
	_send_lobby(NetProtocol.LOBBY_SET_OPTION, 0, "%s=%d" % [key, 1 if pressed else 0])


# --- in-match sandbox debug panel (D-0xx) --------------------------------
#
# A dev tool, not a player feature: only ever visible when the server says
# sandbox mode is on for this match, and built once like every other HUD
# layer rather than per frame.

const SANDBOX_RESOURCE_GRANT_LABEL := 1000  # mirrors server.gd's CHEAT_RESOURCE_GRANT

## A real separate OS window (not a CanvasLayer overlay) — it used to sit
## on top of the game HUD and could overlap the selection panel, the
## minimap, or anything else already anchored to a screen corner. A
## `Window` node opens as its own native window instead, movable and
## closable independently of the main one, so it can never collide with
## in-game UI again.
var _debug_window: Window
var _debug_status_label: Label
var _debug_visible_last := false

## "" (off), "unit", or "building" — which cheat, if any, the next left
## click on the ground fires. Stays armed after firing (does not clear
## itself), so spawning several waves or several buildings in a row does
## not mean re-opening a picker each time; a right-click or the Cancel
## button disarms it, mirroring how `_placing`'s escape hatch already
## works for ordinary building placement.
var _cheat_arm_kind: String = ""
var _cheat_arm_id: String = ""
var _cheat_arm_count: int = 1


func _build_debug_panel() -> void:
	_debug_window = Window.new()
	_debug_window.title = "Sandbox — Dev Tools"
	_debug_window.size = Vector2i(300, 440)
	# Near the main window rather than wherever the OS defaults to, so it
	# does not open off-screen or stacked exactly on top of the game.
	_debug_window.position = DisplayServer.window_get_position() + Vector2i(40, 60)
	_debug_window.visible = false
	# The window's own close button hides it rather than freeing it (there
	# is only ever one; freeing would mean rebuilding the whole panel to
	# get it back) — and drops whatever cheat was armed, the same as
	# right-clicking the game world already does, so a closed panel can
	# never leave a spawn mode silently active.
	_debug_window.close_requested.connect(func():
		_debug_window.hide()
		_on_cheat_cancel_pressed())
	add_child(_debug_window)

	var col := VBoxContainer.new()
	col.position = Vector2(12.0, 10.0)
	col.custom_minimum_size = Vector2(272.0, 0.0)
	col.add_theme_constant_override("separation", 6)
	_debug_window.add_child(col)

	var title := Label.new()
	title.text = "SANDBOX"
	title.add_theme_font_size_override("font_size", 16)
	col.add_child(title)

	var resources_button := _styled_button(
		"+%d all resources" % SANDBOX_RESOURCE_GRANT_LABEL, Color(0.55, 0.7, 0.5))
	resources_button.pressed.connect(_on_cheat_add_resources_pressed)
	col.add_child(resources_button)

	col.add_child(HSeparator.new())

	var unit_label := Label.new()
	unit_label.text = "Spawn units — arm, then click the ground:"
	unit_label.add_theme_font_size_override("font_size", 13)
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(unit_label)

	var unit_row := HBoxContainer.new()
	unit_row.add_theme_constant_override("separation", 6)
	col.add_child(unit_row)
	var unit_picker := OptionButton.new()
	for archetype in TRAIN_KEYS.values():
		unit_picker.add_item(String(archetype))
	unit_row.add_child(unit_picker)
	var count_box := SpinBox.new()
	count_box.min_value = 1
	count_box.max_value = CHEAT_SPAWN_MAX_COUNT_LABEL
	count_box.value = 1
	count_box.custom_minimum_size = Vector2(56.0, 0.0)
	unit_row.add_child(count_box)
	var unit_arm_button := _styled_button("Arm", Color(0.6, 0.6, 0.8))
	unit_arm_button.pressed.connect(func():
		if unit_picker.selected < 0:
			return
		_cheat_arm_kind = "unit"
		_cheat_arm_id = unit_picker.get_item_text(unit_picker.selected)
		_cheat_arm_count = int(count_box.value)
		_debug_status_label.text = "Armed: %d x %s — click the ground (right-click cancels)" \
			% [_cheat_arm_count, _cheat_arm_id])
	unit_row.add_child(unit_arm_button)

	col.add_child(HSeparator.new())

	var building_label := Label.new()
	building_label.text = "Spawn a COMPLETE building — arm, then click:"
	building_label.add_theme_font_size_override("font_size", 13)
	building_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(building_label)

	var building_row := HBoxContainer.new()
	building_row.add_theme_constant_override("separation", 6)
	col.add_child(building_row)
	var building_picker := OptionButton.new()
	var defs := BuildingSim.all_defs()
	for def in defs:
		building_picker.add_item(def.display_name)
	building_row.add_child(building_picker)
	var building_arm_button := _styled_button("Arm", Color(0.7, 0.6, 0.5))
	building_arm_button.pressed.connect(func():
		var idx := building_picker.selected
		if idx < 0 or idx >= defs.size():
			return
		_cheat_arm_kind = "building"
		_cheat_arm_id = String((defs[idx] as BuildingDef).id)
		_debug_status_label.text = "Armed: %s — click the ground (right-click cancels)" \
			% _cheat_arm_id)
	building_row.add_child(building_arm_button)

	var cancel_button := _styled_button("Cancel spawn mode", Color(0.7, 0.4, 0.4))
	cancel_button.pressed.connect(_on_cheat_cancel_pressed)
	col.add_child(cancel_button)

	_debug_status_label = Label.new()
	_debug_status_label.add_theme_font_size_override("font_size", 12)
	_debug_status_label.modulate = Color(0.9, 0.85, 0.4)
	_debug_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_debug_status_label)


## Bound at build time from the same cap `server.gd`'s CHEAT_SPAWN_MAX_
## COUNT enforces — kept as its own constant here (not shared across the
## client/server boundary the way NetProtocol constants are) since it
## only shapes the SpinBox's range, not correctness: the server clamps
## again regardless.
const CHEAT_SPAWN_MAX_COUNT_LABEL := 20


func _on_cheat_add_resources_pressed() -> void:
	if not _connected:
		return
	_peer.send(0, NetProtocol.encode_cheat_add_resources(), ENetPacketPeer.FLAG_RELIABLE)


func _on_cheat_cancel_pressed() -> void:
	_cheat_arm_kind = ""
	if _debug_status_label != null:
		_debug_status_label.text = ""


## Fires whichever cheat is armed at the clicked cell. Returns true if the
## click was consumed (armed at all and over real ground) — false lets the
## caller fall through to ordinary selection/placement handling, the same
## contract `_place_armed_building` already has.
func _fire_armed_cheat(screen_position: Vector2) -> bool:
	if not _connected or _state.space == null:
		return false
	var cell := _cell_under(screen_position)
	if cell.x < 0:
		return false
	var cell_index := _state.space.index(cell)

	match _cheat_arm_kind:
		"unit":
			_peer.send(0, NetProtocol.encode_cheat_spawn_unit(
				_cheat_arm_id, cell_index, _cheat_arm_count), ENetPacketPeer.FLAG_RELIABLE)
		"building":
			_peer.send(0, NetProtocol.encode_cheat_spawn_building(_cheat_arm_id, cell_index),
				ENetPacketPeer.FLAG_RELIABLE)
		_:
			return false
	return true


## Shows the panel only once the server confirms sandbox mode is actually
## on AND a match is running — a lobby has nothing to spawn units into,
## and a client that decided this for itself would be trusting its own
## copy of a server-owned fact (D-002).
func _refresh_debug_panel() -> void:
	if _debug_window == null:
		return
	var showing: bool = bool(_state.lobby.get("sandbox", false)) and not _state.in_lobby()
	if showing and not _debug_visible_last:
		# Sandbox mode just turned on (or a match just started with it
		# already on) — open automatically. Does NOT run every frame
		# sandbox stays on, so a player who closes the window themselves
		# is not fighting it reopening on the very next refresh.
		_debug_window.show()
	elif not showing:
		_debug_window.hide()
		if _debug_visible_last:
			_on_cheat_cancel_pressed()
	_debug_visible_last = showing


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
	style.bg_color = HudTheme.BG_ROW if mine else HudTheme.BG_ROW_DIM
	style.set_corner_radius_all(HudTheme.RADIUS_LG)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_color = HudTheme.accent_border(1.0) if mine else HudTheme.BORDER
	style.set_border_width_all(1)
	if mine:
		style.border_width_left = 3
	frame.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	frame.add_child(row)

	# The PLAYER's colour, not the civ's (D-052): twenty players share
	# two civs, so a civ swatch cannot tell them apart — and this is the
	# same colour their army will be on the field.
	row.add_child(_swatch(PlayerColours.of_index(index), Vector2(20.0, 20.0)))

	var kind := Label.new()
	kind.text = "ai" if is_ai else "human"
	kind.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE + 1)
	kind.modulate = HudTheme.TEXT_FAINT
	kind.custom_minimum_size = Vector2(56.0, 0.0)
	row.add_child(kind)

	var name_label := Label.new()
	name_label.text = String(seat["name"])
	name_label.add_theme_font_size_override("font_size", HudTheme.TITLE_SIZE)
	name_label.custom_minimum_size = Vector2(120.0, 0.0)
	name_label.modulate = HudTheme.TEXT_BRIGHT
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
	tags.text = ("Admin" if int(seat["player"]) == int(_state.lobby.get("admin", 0)) else "")
	tags.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE + 1)
	tags.modulate = HudTheme.ACCENT_BRIGHT
	tags.custom_minimum_size = Vector2(44.0, 0.0)
	row.add_child(tags)

	# Only AI seats can be removed, and only by the host. A player leaves
	# by disconnecting — eviction is a moderation feature nobody asked for.
	if is_ai and _state.is_admin():
		var remove := _styled_button("Remove", HudTheme.DANGER)
		remove.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE + 1)
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


## Ask the SERVER to draw a new seed (D-100). The value is ignored at the
## far end — rolling here would hand the map to whoever is host, and would
## pin the result, which is the opposite of what the button says.
func _on_map_reroll() -> void:
	_send_lobby(NetProtocol.LOBBY_SET_OPTION, 0, "%s=0" % MatchState.REROLL_OPTION)


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
		note.add_theme_font_size_override("font_size", HudTheme.CAPTION_SIZE + 1)
		note.modulate = HudTheme.TEXT_GHOST
		note.text = "Only the host can change these."
		_map_rows.add_child(note)


func _map_row(option: Dictionary, settings: Dictionary, admin: bool) -> Control:
	var key := String(option["key"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = String(option["label"])
	label.add_theme_font_size_override("font_size", HudTheme.BODY_SIZE)
	label.custom_minimum_size = Vector2(140.0, 0.0)
	label.modulate = HudTheme.TEXT_DIM
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
			# Typing a seed PINS it; the button beside it asks the server
			# for a fresh one and leaves it unpinned, so the lobby keeps
			# rolling between matches (D-100). Only the admin gets either,
			# so a guest's row keeps the full-width spinner.
			var rerollable := bool(option.get("reroll", false)) and admin
			if rerollable:
				# Narrower, so the row still reads as one control with an
				# affordance beside it rather than two settings.
				spin.custom_minimum_size = Vector2(148.0, 0.0)
			row.add_child(spin)

			if rerollable:
				var roll := _styled_button("Reroll", HudTheme.ACCENT)
				roll.tooltip_text = "Draw a new map. Type a seed instead to keep playing this one."
				roll.pressed.connect(_on_map_reroll)
				row.add_child(roll)

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
			value.text = _slider_readout(option, settings)
			value.add_theme_font_size_override("font_size", HudTheme.BODY_SIZE)
			value.custom_minimum_size = Vector2(66.0, 0.0)
			value.modulate = HudTheme.TEXT_MUTED
			row.add_child(value)

	return row


## What a map slider's number reads as.
##
## Most are the raw parameter, which is what a sea level or a relief
## multiplier already means to a human. Landmass size is not: since D-101
## `elevation_frequency` is a density against `TerrainGen.REFERENCE_WIDTH`,
## and the number a player can act on is how wide a landmass comes out —
## which is now the same at every map size, and is the point.
func _slider_readout(option: Dictionary, settings: Dictionary) -> String:
	var raw := float(settings.get(String(option["key"]), 0.0))
	if String(option.get("readout", "")) == "cells":
		return "%d cells" % roundi(TerrainGen.feature_cells(raw))
	return "%.2f" % raw


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
