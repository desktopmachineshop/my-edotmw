extends Node3D

## Renders ground cover on real terrain, next to real soldiers, and
## screenshots it (D-100). Run by `just gen-cover-preview`.
##
## This project's most repeated failure is "numbers green, picture wrong" —
## three milestones running — and cover is a feature whose entire purpose is
## how the ground LOOKS. Every assertion in `tests/test_ground_cover.gd` is
## about counts, palettes and bounds; none of them can see a prop lit from the
## inside, a fern the size of a hut, or grass that vanishes into the terrain
## colour. So the artifact is the evidence, and it is meant to be LOOKED AT.
##
## Everything goes through the REAL path: `GroundCover` chooses, `UnitMesh`
## loads the authored `.glb`, and the props are drawn from one MultiMesh per
## model — which is exactly how the client will draw them, and is the reason
## the prop meshes carry glTF MATERIALS rather than vertex colours (a MultiMesh
## overrides `COLOR`; see `art/lib/bake.py`). A preview that built its own
## material would prove nothing about whether the game can draw these.
##
## Software-rasterised, so it needs no GPU and answers "is the picture right",
## never "how fast" — `bench-render` is the one that needs real hardware.
##
## Three things are framed on purpose:
##   1. a PARADE of every shipped prop, close enough to read individually;
##   2. a squad of real soldiers standing in the scatter, so "cover never
##      hides a unit" (D-045's readability rule) is visible, not merely
##      asserted;
##   3. the scatter itself over generated terrain, which is the only way to
##      see whether a region reads as a place.

const PATCH_WIDTH := 32
const PATCH_HEIGHT := 24
const PARADE_SPACING := 1.2
const PARADE_ROW := 6
const SQUAD_SIZE := 8

@export var seconds: float = 0.6
@export var out_path: String = "res://artifacts/cover-godot.png"

var _space: TorusSpace
var _terrain: TerrainGen
var _surface: PackedFloat32Array
var _centre: Vector3
var _elapsed := 0.0
var _shot := false
var _instances := 0
var _models_drawn := {}


func _ready() -> void:
	_parse_arguments()
	_build_terrain()
	_build_environment()
	# The parade is laid out FIRST so the scatter can be told those cells are
	# taken. That is not staging: it is the same `occupied` input the client
	# will pass for a cell holding a node, a building or a wall, and the bare
	# strip the parade stands in is what that rule looks like.
	var parade := _parade_positions()
	var cells := _build_cover(_reserved_cells(parade))
	_build_parade(parade)
	_build_squad()
	_report(cells)


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--seconds="):
			seconds = float(text.trim_prefix("--seconds="))
		elif text.begins_with("--out="):
			out_path = text.trim_prefix("--out=")


## Terrain in its own space coordinates — the patch is NOT re-centred on the
## origin. Everything else is placed in the same coordinates and sampled from
## the same `surface_field`, so a prop's foot is on the ground it is drawn
## over rather than on the ground half a map away.
func _build_terrain() -> void:
	_space = TorusSpace.new(PATCH_WIDTH, PATCH_HEIGHT)
	_terrain = TerrainGen.new()
	_surface = _terrain.surface_field(_space)
	_centre = _space.to_world(_flattest_cell())

	var material := TerrainChunk.make_material()
	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(_space, chunk_size)
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(_space, _terrain, Vector2i(cx, cy),
				chunk_size, _surface)
			if mesh == null:
				continue
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			add_child(instance)


## The flattest patch of dry land, which is where the shot is framed.
##
## Terrain is drawn at height_scale 15, so on a patch this size a fixed focus
## point is as likely to be a cliff face as a meadow — the first version of
## this preview framed a hillside and hid its own parade behind the crest.
## Choosing the flattest LAND cell makes the shot legible whatever the seed
## does, without flattening the ground it is a picture of.
func _flattest_cell() -> Vector2i:
	var best := Vector2i.ZERO
	var best_relief := INF
	# Near the middle of the drawn patch, and on land. The patch is a torus in
	# the SIMULATION's sense but it is drawn once here, with no lattice copies
	# (D-035 is client.gd's job), so anywhere past the last cell is void — and
	# the flattest ground on any map tends to be the shoreline, which is
	# exactly where framing a shot leaves half the props hanging over nothing.
	#
	# The bound is in WORLD units rather than cell counts: `to_world` shears
	# each row half a column across (pointy-top axial), so the drawn patch is a
	# parallelogram and "interior in q and r" is not interior on screen.
	const FOCUS_RADIUS := 6.0
	var middle := _space.to_world(Vector2i(PATCH_WIDTH / 2, PATCH_HEIGHT / 2))
	for i in range(_space.cell_count()):
		var coord := _space.from_index(i)
		var here := _space.to_world(coord)
		if Vector2(here.x - middle.x, here.z - middle.z).length() > FOCUS_RADIUS:
			continue
		if _terrain.is_water(_space, coord):
			continue
		var low := _surface[i * TerrainGen.SURFACE_STRIDE]
		var high := low
		for dir in range(6):
			var h := _surface[_space.neighbor_index(i, dir) * TerrainGen.SURFACE_STRIDE]
			low = minf(low, h)
			high = maxf(high, h)
		if high - low < best_relief:
			best_relief = high - low
			best = coord
	return best


func _build_environment() -> void:
	var camera := Camera3D.new()
	# Low and close: props are 0.1-0.5 units tall, and the strategy camera's
	# usual height renders them as a few pixels of noise. This is the "can you
	# tell a mushroom from a rock" shot; the wide read is `test-client`'s.
	#
	# Positioned RELATIVE TO THE GROUND, and inside the patch. Terrain here is
	# drawn at height_scale 15 (terrain_gen.gd), so a camera placed at a fixed
	# world y is as likely to be underground as above it, and one placed past
	# the patch edge frames the void — both of which this shot did on its
	# first run.
	var focus := _centre + Vector3(0.0, 0.0, 1.0)
	focus.y = _ground(focus.x, focus.z)
	camera.position = focus + Vector3(0.0, 3.4, 9.0)
	add_child(camera)
	camera.look_at(focus)
	camera.fov = 60.0
	camera.make_current()

	add_child(WorldLook.make_sun(true))
	var world := WorldEnvironment.new()
	world.environment = WorldLook.make_environment(true)
	add_child(world)


func _ground(x: float, z: float) -> float:
	return TerrainChunk.height_at(_space, _surface, x, z)


## Dress every cell of the patch, batched one MultiMesh per model — the
## client's chunked batching without the chunking, since the whole patch is
## smaller than one chunk's worth of interest here.
func _build_cover(reserved: Dictionary) -> int:
	var biomes := PackedInt32Array()
	var moisture := PackedFloat32Array()
	var count := _space.cell_count()
	biomes.resize(count)
	moisture.resize(count)
	var elevation := _terrain.elevation_field(_space)
	for i in range(count):
		var coord := _space.from_index(i)
		biomes[i] = _terrain.biome_at(_space, coord)
		moisture[i] = _terrain.moisture_at(_space, coord)

	var groups := {}
	var dressed := 0
	for i in range(count):
		var neighbours: Array = []
		for dir in range(6):
			neighbours.append(biomes[_space.neighbor_index(i, dir)])
		var props := GroundCover.props_for(biomes[i], neighbours, moisture[i],
			elevation[i], i, reserved.has(i))
		if props.is_empty():
			continue
		dressed += 1
		var world := _space.to_world(_space.from_index(i))
		for prop in props:
			var at: Vector3 = world + (prop["offset"] as Vector3) * _space.hex_size
			at.y = _ground(at.x, at.z)
			_add_instance(groups, prop["model"],
				_pose(at, float(prop["yaw"]), float(prop["scale"])))

	_flush(groups, self)
	return dressed


## Where the parade stands: one of every shipped prop, in rows near the
## camera, so the picture shows each model on its own as well as en masse.
## On the real ground, for the same reason everything else is.
func _parade_positions() -> Array:
	var out: Array = []
	var ids := GroundCover.model_ids()
	for i in range(ids.size()):
		var at := _centre + Vector3(
			(float(i % PARADE_ROW) - float(PARADE_ROW - 1) / 2.0) * PARADE_SPACING,
			0.0,
			5.6 - float(i / PARADE_ROW) * 1.2)
		at.y = _ground(at.x, at.z)
		out.append({"model": ids[i], "at": at})
	return out


## The cells the parade occupies, as `props_for`'s `occupied` input wants
## them. Two purposes at once: the parade stands in cleared ground and is
## therefore legible against the scatter, and the clearing IS the picture of
## the occupancy rule.
func _reserved_cells(parade: Array) -> Dictionary:
	var out := {}
	for entry in parade:
		var at: Vector3 = entry["at"]
		out[_space.index(_space.world_to_cell(at))] = true
	return out


func _build_parade(parade: Array) -> void:
	var groups := {}
	for entry in parade:
		# Full scale and no yaw: this row is the reference, not the dressing.
		_add_instance(groups, entry["model"],
			_pose(entry["at"], 0.0, GroundCover.SCALE_MAX))
	_flush(groups, self)


## Real soldiers standing in the cover. The whole justification for ground
## cover existing is that it does not interfere with reading units, and that
## claim is settled by looking at this, not by any number.
func _build_squad() -> void:
	# The first authored archetype the roster offers, NOT a named one: unit ids
	# are civ-prefixed (D-047) and no `.gd` in this project may name a civ —
	# `tests/test_civs.gd` fails if one does. Asking for a plain "militia"
	# silently returned null and this preview quietly had no soldiers in it,
	# which is the same silent-fallback family as a missing mesh.
	var def: UnitDef = null
	for candidate in UnitRoster.load_all():
		if candidate.model_id != &"":
			def = candidate
			break
	if def == null:
		push_warning("cover_preview: no authored unit to stand in the cover")
		return
	var unit := PrimitiveUnit.new()
	add_child(unit)
	unit.rebuild(def, PlayerColours.of_index(0))
	var origin := _centre + Vector3(0.0, 0.0, -1.6)
	unit.position = origin

	var transforms: Array[Transform3D] = []
	for i in range(SQUAD_SIZE):
		var local := Vector3((float(i % 4) - 1.5) * 1.15, 0.0,
			float(i / 4) * -1.25)
		local.y = _ground(origin.x + local.x, origin.z + local.z) - origin.y
		transforms.append(Transform3D(Basis(), local))
	unit.set_slot_transforms(transforms)
	unit.set_clip_data(0, 0, 3.2)


func _pose(at: Vector3, yaw: float, scale: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), at)


func _add_instance(groups: Dictionary, model: StringName,
		xform: Transform3D) -> void:
	if not groups.has(model):
		groups[model] = []
	groups[model].append(xform)


## Turn the collected transforms into MultiMeshes. A model with no mesh is
## SKIPPED, not substituted: missing art costs cover, never the client
## (D-081's fallback rule).
func _flush(groups: Dictionary, parent: Node) -> void:
	for model in groups:
		var mesh := UnitMesh.mesh_for(model)
		if mesh == null:
			push_warning("cover_preview: no mesh for %s; skipped" % model)
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		var transforms: Array = groups[model]
		multimesh.instance_count = transforms.size()
		for i in range(transforms.size()):
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		parent.add_child(instance)
		_instances += transforms.size()
		_models_drawn[model] = true


## The numbers the recipe gates on. They cannot tell whether the picture is
## right — that is what the PNG is for — but they can tell whether there is a
## picture at all, which is the failure mode that would otherwise produce a
## confident screenshot of bare ground.
func _report(dressed: int) -> void:
	print("cover_preview: %d cells dressed of %d, %d instances, %d/%d models drawn"
		% [dressed, _space.cell_count(), _instances, _models_drawn.size(),
			GroundCover.model_ids().size()])
	print("cover_preview: renderer=%s adapter=%s"
		% [ProjectSettings.get_setting("rendering/renderer/rendering_method"),
			RenderingServer.get_video_adapter_name()])


func _process(delta: float) -> void:
	_elapsed += delta
	if _shot or _elapsed < seconds:
		return
	_shot = true

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var err := image.save_png(absolute)
	if err != OK:
		push_error("cover_preview: could not write %s (%d)" % [absolute, err])
		get_tree().quit(1)
		return
	print("cover_preview: wrote %s (%dx%d)"
		% [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)
