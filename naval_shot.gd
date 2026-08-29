extends Node3D

## A rendered picture of SHIPS ON WATER, in the shipping lighting rig —
## naval stage 8's exit criterion (`docs/plans/naval.md` §7).
##
## ## Why this had to exist
##
## Stage 8's deliverable is "ship height at sea level; minimap check;
## selection over water", and its done-when is *a rendered frame with
## ships on water, looked at*. No existing instrument can produce one:
##
## - `gen-terrain-shot` frames the longest run of passability boundary and
##   deliberately PREFERS a mountain, because "a shoreline shows up in any
##   shot at all" — and it draws no units;
## - `gen-model-preview` puts the roster on a studio plane with no sea;
## - `gen-forest-preview` frames a wood;
## - `test-client` aims at a spawn, which is walkable ground by
##   construction and therefore the one place a hull cannot be.
##
## This project's own rule is that when a rendered check has to see
## something specific, you frame it on purpose (D-108's forests, D-097's
## cliffs). So this frames a COASTLINE, with a hull afloat on the water
## and a land squad on the beach beside it — the contrast is the point,
## because "the ship is at the right height" is only visible against
## something standing on the ground.
##
## Everything goes through the REAL path: a shipped warship `UnitDef`, a
## `PrimitiveUnit`, the shipping shaders, and
## `Formation.soldier_transforms_sampled` with the same `water_height`
## `ClientState` passes. A preview that placed hulls itself would prove
## the models exist and nothing about whether the game floats them.
##
## Software-rasterised like `gen-terrain-shot`, so it needs no GPU and
## says nothing about speed.

@export var out_path: String = "res://artifacts/naval-godot.png"
@export var preset_id: String = "islands"
@export var seconds: float = 0.6
@export var camera_height: float = 9.0
## Derive the hulls the way the client did BEFORE this stage — through the
## ground sampler, with no water plane. The perturbation that makes the
## picture mean something: a hull inshore rides up the beach, because a
## water cell sharing corners with land takes their heights. Not a mode
## anything ships with; it exists so the before-and-after pair can be
## taken with one recipe and one camera (`--seabed=1`).
@export var on_the_seabed: bool = false

var _elapsed := 0.0
var _shot := false
var _drawn := 0
var _report := ""
## What was actually placed, in world space — the camera is backed off
## against THIS rather than a distance that happened to look right on one
## map. `model_preview.gd` learned the same lesson four times over: a
## frame sized against anything but the drawn content clips the content
## the first time the content changes.
var _bounds := AABB()
var _bounded := false
## The world point the frame is built around. Bounds are measured from
## the copy of each man NEAREST to it, because a shore cell and the open
## water three hexes out are routinely on opposite sides of a seam — and
## measured canonically they span the whole map (108 world units on a
## 64-wide torus, from squads a few metres apart).
var _anchor := Vector3.ZERO


func _ready() -> void:
	_parse_arguments()

	var space := TorusSpace.new(64, 48, 1.0)
	var terrain := TerrainGen.new()
	var preset := TerrainPresetRoster.by_id(StringName(preset_id))
	if preset != null:
		terrain.sea_level = preset.sea_level
		terrain.beach_level = preset.beach_level
		terrain.mountain_level = preset.mountain_level
		terrain.elevation_frequency = preset.elevation_frequency
		terrain.moisture_frequency = preset.moisture_frequency
		terrain.height_scale = preset.height_scale
	var fields := terrain.build_fields(space)
	var navigable := terrain.navigability(space)

	add_child(WorldLook.make_sun())
	var environment := WorldEnvironment.new()
	environment.environment = WorldLook.make_environment(false,
		maxf(camera_height, 8.0))
	add_child(environment)

	_build_ground(space, terrain, fields)

	# The water plane the client derives, from the same product
	# `build_fields` clamps its vertices to. One expression, three
	# readers: the mesher, `ClientState.water_plane_height` and this.
	var plane := terrain.sea_level * terrain.height_scale

	var shore := _busiest_shore(space, navigable, fields)
	# TWO hulls, and which two is the whole argument. `inshore` is the
	# water cell against the beach — the case this stage exists for, whose
	# corners are shared with land and whose interpolated surface climbs
	# it. `offshore` is open water, where the ground sampler was already
	# right. They must be drawn at the SAME height; before stage 8 the
	# inshore one rode up the beach and only a picture with both in it can
	# say so.
	var inshore := _water_cell_near(space, navigable, shore, 1)
	var offshore := _water_cell_near(space, navigable, shore, 3)
	_report = ("preset %s, %dx%d, shore %s, inshore hull %s, offshore hull %s, "
		+ "sea plane %.3f%s") % [preset_id, space.width, space.height, shore,
		inshore, offshore, plane,
		" [SEABED: hulls derived the pre-stage-8 way]" if on_the_seabed else ""]

	_anchor = space.to_world(shore)
	var ship_def := _first_def_with_domain("water")
	var ship_span := Vector2(NAN, NAN)
	var hull_height := NAN if on_the_seabed else plane
	if ship_def != null:
		ship_span = _place(space, ship_def, inshore, fields, hull_height,
			PlayerColours.of_index(0))
		var far_span := _place(space, ship_def, offshore, fields, hull_height,
			PlayerColours.of_index(0))
		ship_span = Vector2(minf(ship_span.x, far_span.x),
			maxf(ship_span.y, far_span.y))
	# ...and a LAND squad ashore beside them, derived the ordinary way.
	# Without something standing on the ground, a hull at the wrong height
	# looks exactly like a hull at the right one.
	var land_def := _first_def_with_domain("ground")
	var land_span := Vector2(NAN, NAN)
	if land_def != null:
		land_span = _place(space, land_def, shore, fields, NAN,
			PlayerColours.of_index(1))

	# Between the beach and the open water, so the COASTLINE is what the
	# frame is about rather than either squad — and the torus tax is paid
	# here, because the two cells are routinely on opposite sides of a
	# seam. Averaging their world positions put the camera in the middle
	# of the map looking at open sea, with both squads a map away and
	# every printed number healthy (D-008's ghost-copy rule; the same
	# mistake `Engagement.aligning_offset` exists for).
	var focus := space.to_world(shore) + space.axial_offset_to_world(
		Vector2(space.delta(shore, offshore)) * 0.5)
	focus.y = plane
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	# Low, and BROADSIDE to the coast rather than at some fixed compass
	# bearing: the shot stands off to the side of the beach-to-sea line so
	# the transition is seen in profile, with the men ashore at one end
	# and the hulls at the other. A hull riding a hand's breadth too high
	# is invisible from overhead and unmistakable from here.
	var seaward := (space.axial_offset_to_world(
		Vector2(space.delta(shore, offshore)))).normalized()
	var broadside := Vector3(-seaward.z, 0.0, seaward.x)
	# Backed off against what was DRAWN: enough to hold the beach, the men
	# and both hulls, whatever the coast turned out to look like.
	var reach := maxf(camera_height,
		maxf(_bounds.size.x, _bounds.size.z) * 0.9 + 3.0)
	camera.position = focus + broadside * reach 		+ Vector3(0.0, reach * 0.38, 0.0)
	camera.look_at(focus, Vector3.UP)

	print("naval_shot: %s" % _report)
	print("naval_shot: %d squads drawn (%s afloat x2, %s ashore)" % [_drawn,
		ship_def.id if ship_def != null else "NONE",
		land_def.id if land_def != null else "NONE"])
	# The picture's claim, as numbers beside it: every hull vertex is ON
	# the plane, and the men ashore are ABOVE it. A shot nobody looks at
	# would still catch a hull put back on the seabed.
	print("naval_shot: hull y %.3f..%.3f (plane %.3f), ashore y %.3f..%.3f"
		% [ship_span.x, ship_span.y, plane, land_span.x, land_span.y])
	print("naval_shot: drawn content spans %.1f x %.1f world units"
		% [_bounds.size.x, _bounds.size.z])
	print("naval_shot: renderer=%s adapter=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		RenderingServer.get_video_adapter_name()])


## The nine lattice copies, as the client draws them (D-035) — a shot
## that does not tile the torus is a picture of a different world, which
## `terrain_shot.gd` learned by framing a cliff hanging over a void.
func _build_ground(space: TorusSpace, terrain: TerrainGen,
		fields: TerrainFields) -> void:
	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(space, chunk_size)
	var material := TerrainChunk.make_material()
	var meshes: Array[ArrayMesh] = []
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(space, terrain,
				Vector2i(cx, cy), chunk_size, fields)
			if mesh != null:
				meshes.append(mesh)
	for i in [-1, 0, 1]:
		for j in [-1, 0, 1]:
			var tile := Node3D.new()
			tile.position = space.lattice_steps()[0] * float(i) \
				+ space.lattice_steps()[1] * float(j)
			for mesh in meshes:
				var instance := MeshInstance3D.new()
				instance.mesh = mesh
				instance.material_override = material
				tile.add_child(instance)
			add_child(tile)


## One squad, through the real derivation, at its own strength. Returns
## the min and max Y of the men it drew — the numbers the picture is
## making a claim about.
##
## `water_height` NAN means "not a ship", which is the same argument
## `ClientState` passes for a land squad.
func _place(space: TorusSpace, def: UnitDef, cell: Vector2i,
		fields: TerrainFields, water_height: float, colour: Color) -> Vector2:
	var curve := StateCurve.new()
	curve.append_cell(0.0, cell, space)
	var men := Formation.soldier_transforms_sampled(
		curve, 0.0, def.squad_size, def.formation_shape, def.formation_spacing,
		space, Callable(), -1, fields.passable, 0, NAN, fields.surface, 0.0,
		water_height)
	if men.is_empty():
		return Vector2(NAN, NAN)
	var unit := PrimitiveUnit.new()
	add_child(unit)
	unit.rebuild(def, colour)
	# The transforms are world-space; the node sits at the origin, exactly
	# as `client.gd` places a squad's canonical copy.
	unit.set_slot_transforms(men)
	unit.set_clip_data(int(cell.x) * 31 + int(cell.y), 0, 0.0)
	# Every visible lattice copy, exactly as the client draws a squad
	# (D-20260818-entities-are-drawn-at-every-visible-copy). Not a nicety
	# here: the frame is a few hexes across and routinely straddles a
	# seam, so a canonical-only squad would simply be absent from half the
	# shots this recipe takes.
	var mirrors: Array[Node3D] = []
	LatticeCopies.draw(unit, mirrors, Vector3.ZERO, space.lattice_offsets())
	_drawn += 1
	for man in men:
		var at := _nearest_copy(space, man.origin)
		if _bounded:
			_bounds = _bounds.expand(at)
		else:
			_bounds = AABB(at, Vector3.ZERO)
			_bounded = true
	var lowest := INF
	var highest := -INF
	for man in men:
		lowest = minf(lowest, man.origin.y)
		highest = maxf(highest, man.origin.y)
	return Vector2(lowest, highest)


## Which lattice copy of a world position is nearest the frame's anchor.
## The torus tax, paid for MEASUREMENT rather than for drawing — the
## squad itself is drawn at every copy above.
func _nearest_copy(space: TorusSpace, at: Vector3) -> Vector3:
	var best := at
	var best_distance := INF
	for offset in space.lattice_offsets():
		var candidate := at + offset
		var distance := candidate.distance_squared_to(_anchor)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## The piece of coast the picture is framed on: a walkable cell with water
## on several sides, preferring the one whose own ground stands HIGHEST
## above the sea.
##
## Both halves are needed. Water on several sides puts a hull and a
## footman in one frame; height is what makes the shore legible at all —
## a beach cell sits within a few centimetres of the waterline by
## definition, so framed on the flattest coast the picture shows two
## squads at apparently the same height and proves nothing.
func _busiest_shore(space: TorusSpace, navigable: PackedByteArray,
		fields: TerrainFields) -> Vector2i:
	var best := Vector2i.ZERO
	var best_score := -INF
	for i in range(space.cell_count()):
		if fields.passable[i] != 1:
			continue
		var water_sides := 0
		for direction in range(6):
			if navigable[space.neighbor_index(i, direction)] != 0:
				water_sides += 1
		if water_sides < 2:
			continue
		# The cell centre, which is `surface`'s first of seven entries
		# (the other six are its corners — `TerrainChunk.height_in_cell`).
		var height := fields.surface[i * 7]
		# HEIGHT leads and the side count only breaks ties: ranked the
		# other way round, six water sides beats any amount of relief and
		# the shot frames the flattest sandbar on the map — measured at
		# 0.002 world units above the waterline, which is a picture of two
		# squads at the same height.
		var score := height + 0.05 * float(water_sides)
		if score > best_score:
			best_score = score
			best = space.from_index(i)
	return best


## The navigable cell nearest to `radius` hexes out from that shore.
## `disk_offsets` is sorted nearest-first, so walking it backwards finds
## the outermost water in the disk — which is how "open water" and "up
## against the beach" come out of one function.
func _water_cell_near(space: TorusSpace, navigable: PackedByteArray,
		shore: Vector2i, radius: int) -> Vector2i:
	var offsets := TorusSpace.disk_offsets(radius)
	for i in range(offsets.size() - 1, -1, -1):
		var cell := space.normalize(shore + offsets[i])
		if navigable[space.index(cell)] != 0:
			return cell
	return shore


func _first_def_with_domain(domain: String) -> UnitDef:
	for def in UnitRoster.load_all():
		if def.movement_domain == domain:
			return def
	return null


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--out="):
			# REBASED through ArtifactPath, never taken as given
			# (D-20260828). `res://` is a real directory in a checkout and a
			# read-only virtual filesystem inside an exported build's .pck,
			# so a writer that trusts its own argument works here and writes
			# nothing at all from a shipped build — which is #201, found
			# after an exported server played a whole match and recorded no
			# replay. Same one line as `terrain_shot.gd`.
			out_path = ArtifactPath.resolve(text.trim_prefix("--out="))
		elif text.begins_with("--preset="):
			preset_id = text.trim_prefix("--preset=")
		elif text.begins_with("--seconds="):
			seconds = float(text.trim_prefix("--seconds="))
		elif text.begins_with("--height="):
			camera_height = float(text.trim_prefix("--height="))
		elif text.begins_with("--seabed="):
			on_the_seabed = text.trim_prefix("--seabed=") != "0"


func _process(delta: float) -> void:
	_elapsed += delta
	if _shot or _elapsed < seconds:
		return
	_shot = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		print("VERDICT: fail - could not write %s (error %d)" % [out_path, error])
		get_tree().quit(1)
		return
	if _drawn < 3:
		print("VERDICT: fail - %d squads drawn; the shot needs hulls AND "
			% _drawn + "a squad ashore, or it cannot show the difference")
		get_tree().quit(1)
		return
	print("naval_shot: wrote %s (%dx%d)"
		% [out_path, image.get_width(), image.get_height()])
	print("VERDICT: ok - %s; LOOK AT %s" % [_report, out_path])
	get_tree().quit(0)
