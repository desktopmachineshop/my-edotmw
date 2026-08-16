extends Node3D

## Renders a WOOD — real node placement, real trees, real ground cover —
## and screenshots it. Run by `just gen-forest-preview`.
##
## It exists because a forest read as ranks and files for a whole milestone
## with every number healthy. Node counts, chunk counts and frame times all
## said the same thing before and after the defect was found, and every
## assertion in `tests/test_resource_visuals.gd` is about species pools,
## bounds and determinism. None of them can see a lattice. The instruments
## that could have are the two that existed, and neither looks at a wood:
## `gen-terrain-preview` draws a TOP-DOWN biome map with no trees in it at
## all, and `test-client` aims its camera at a spawn, which is open ground
## by construction — the one place a forest is least likely to be.
##
## So the artifact is the evidence, and it is meant to be LOOKED AT.
##
## Everything goes through the REAL path: `Economy.generate` decides which
## cells hold nodes exactly as the server does, `ResourceVisuals.trees_for`
## grows each cell's stand, `UnitMesh` loads the authored `.glb`, and the
## trees are drawn from one MultiMesh per model — which is how the client
## draws them. A preview that scattered its own trees would be a picture of
## itself.
##
## Software-rasterised, so it needs no GPU and answers "is the picture
## right", never "how fast" — `bench-render` is the one that needs real
## hardware.
##
## Three things are framed on purpose:
##   1. the DENSEST wood on the patch, from a low angle, because ranks and
##      files are invisible from directly overhead and obvious from a
##      player's eye height;
##   2. a squad of real soldiers standing in it, so canopy size is read
##      against the thing a player actually looks at;
##   3. ground cover (D-100) on everything else, because a wood is judged
##      against the ground it stands on, not against a bare plane.

const PATCH_WIDTH := 48
const PATCH_HEIGHT := 32
const SQUAD_SIZE := 8

## How many cells across the window that picks the densest wood is. Wide
## enough to be a wood rather than a copse, narrow enough that "densest"
## means somewhere in particular.
const WOOD_WINDOW := 5

@export var seconds: float = 0.6
@export var out_path: String = "res://artifacts/forest-godot.png"

var _space: TorusSpace
var _terrain: TerrainGen
var _economy: Economy
var _surface: PackedFloat32Array
var _biomes := PackedInt32Array()
var _moisture := PackedFloat32Array()
var _centre: Vector3
var _elapsed := 0.0
var _shot := false
var _trees := 0
var _instances := 0
var _multis := 0
var _models_drawn := {}


func _ready() -> void:
	_parse_arguments()
	_build_terrain()
	_place_nodes()
	_centre = _space.to_world(_densest_wood())
	_build_environment()
	_build_forest()
	_build_cover()
	_build_squad()
	_report()


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--seconds="):
			seconds = float(text.trim_prefix("--seconds="))
		elif text.begins_with("--out="):
			out_path = text.trim_prefix("--out=")


## Terrain in its own space coordinates, sampled once into the same
## per-cell arrays the client keeps — six `biome_at` calls per cell to read
## a neighbour ring would be the shape of the defect that cost vision
## 232 µs/squad.
func _build_terrain() -> void:
	_space = TorusSpace.new(PATCH_WIDTH, PATCH_HEIGHT)
	_terrain = TerrainGen.new()
	# One `build_fields` pass rather than a `surface_field` call (D-096):
	# the mesher needs the colours and tile slots from the SAME build.
	var fields := _terrain.build_fields(_space)
	_surface = fields.surface

	var count := _space.cell_count()
	_biomes.resize(count)
	_moisture.resize(count)
	for i in range(count):
		var coord := _space.from_index(i)
		_biomes[i] = _terrain.biome_at(_space, coord)
		_moisture[i] = _terrain.moisture_at(_space, coord)

	var material := TerrainChunk.make_material()
	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(_space, chunk_size)
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(_space, _terrain, Vector2i(cx, cy),
				chunk_size, fields)
			if mesh == null:
				continue
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			add_child(instance)


## The SERVER's own node placement (D-087's density field), not a scatter
## of this preview's own. Which cells hold wood is half of what the picture
## is about — a forest whose OUTLINE is organic and whose interior is a
## lattice is exactly what this was written to catch.
func _place_nodes() -> void:
	_economy = Economy.new(_space)
	_economy.generate(_terrain)


## The centre of the thickest patch of wood on the map, which is where the
## shot is framed. Deliberately not the middle of the patch and not a
## random node: the failure being looked for is a lattice INSIDE a dense
## wood, and a lone tree on a hillside cannot show it either way.
func _densest_wood() -> Vector2i:
	var best := Vector2i(PATCH_WIDTH / 2, PATCH_HEIGHT / 2)
	var best_score := -1
	for i in range(_space.cell_count()):
		var coord := _space.from_index(i)
		# Away from the patch edge in WORLD terms: the drawn patch is a
		# parallelogram (pointy-top axial shears each row half a column
		# across), so "interior in q and r" is not interior on screen, and
		# framing the edge frames the void.
		if coord.x < WOOD_WINDOW or coord.x >= PATCH_WIDTH - WOOD_WINDOW * 2:
			continue
		if coord.y < WOOD_WINDOW or coord.y >= PATCH_HEIGHT - WOOD_WINDOW:
			continue
		var score := 0
		for dq in range(-WOOD_WINDOW, WOOD_WINDOW + 1):
			for dr in range(-WOOD_WINDOW, WOOD_WINDOW + 1):
				var at := _space.index(Vector2i(coord.x + dq, coord.y + dr))
				if _economy.kind_at(at) == Economy.ResourceKind.WOOD:
					score += 1
		if score > best_score:
			best_score = score
			best = coord
	return best


func _build_environment() -> void:
	var camera := Camera3D.new()
	# A shallow, raised three-quarter view: a lattice is invisible from
	# straight above — every hex looks the same from there — and
	# unmistakable at an angle, which is also how the complaint was made.
	#
	# The height is taken from the GROUND UNDER THE CAMERA, not from the
	# focus. Terrain here runs at height_scale 15, so a camera placed a
	# fixed distance above the thing it is looking at is as likely to be
	# inside the next hill as above it — the first version of this shot
	# framed the inside of one.
	var focus := _centre
	focus.y = _ground(focus.x, focus.z)
	# Far enough back that the near canopy does not fill the frame — a
	# forest is judged by how a MASS of trees reads, and a close camera
	# just photographs the two trees in front of it — and high enough to
	# see over that canopy into the wood behind it.
	var eye := focus + Vector3(0.0, 0.0, 30.0)
	eye.y = maxf(focus.y, _ground(eye.x, eye.z)) + 16.0
	camera.position = eye
	add_child(camera)
	camera.look_at(focus + Vector3(0.0, 2.0, 0.0))
	camera.fov = 55.0
	camera.make_current()

	# The SHIPPING rig, not `model_preview`'s flat studio backdrop
	# (`terrain_shot.gd`'s reasoning): the question here is how a wood
	# looks in the game, and a picture lit differently from the game
	# cannot answer it.
	#
	# Fog at the DEFAULT camera ceiling — the Standard map's — rather than
	# derived from this camera. `terrain_shot` passes its own height
	# because it frames a cliff face a few units away; a wood is read
	# across tens of units, and re-deriving the density for a close camera
	# put a grey wash over the whole picture on the first attempt.
	add_child(WorldLook.make_sun())
	var world := WorldEnvironment.new()
	world.environment = WorldLook.make_environment()
	add_child(world)


func _ground(x: float, z: float) -> float:
	return TerrainChunk.height_at(_space, _surface, x, z)


## Every node on the patch, dressed the way the client dresses one: the
## cell's whole stand from `ResourceVisuals.trees_for`, each tree sampled
## for ground height AT ITS OWN position, batched one MultiMesh per model.
func _build_forest() -> void:
	var groups := {}
	for entry in _economy.node_entries():
		var cell := int(entry["cell"])
		var coord := _space.from_index(cell)
		var neighbours: Array = []
		for dir in range(6):
			neighbours.append(_biomes[_space.neighbor_index(cell, dir)])
		var world := _space.to_world(coord)
		for tree in ResourceVisuals.trees_for(int(entry["kind"]), _biomes[cell],
				neighbours, _moisture[cell], cell):
			var at: Vector3 = world + (tree["offset"] as Vector3) * _space.hex_size
			at.y = _ground(at.x, at.z)
			_add_instance(groups, tree["model"],
				_pose(at, float(tree["yaw"]), float(tree["scale"])))
			_trees += 1
	_flush(groups)


## Ground cover on everything the nodes do not occupy — the same
## `occupied` input the client passes (D-100). A wood is judged against the
## ground under it, and bare terrain flatters any scatter.
func _build_cover() -> void:
	var elevation := _terrain.elevation_field(_space)
	var groups := {}
	for i in range(_space.cell_count()):
		var neighbours: Array = []
		for dir in range(6):
			neighbours.append(_biomes[_space.neighbor_index(i, dir)])
		for prop in GroundCover.props_for(_biomes[i], neighbours, _moisture[i],
				elevation[i], i, _economy.kind_at(i) >= 0):
			var at: Vector3 = _space.to_world(_space.from_index(i)) \
				+ (prop["offset"] as Vector3) * _space.hex_size
			at.y = _ground(at.x, at.z)
			_add_instance(groups, prop["model"],
				_pose(at, float(prop["yaw"]), float(prop["scale"])))
	_flush(groups)


## Real soldiers standing in the wood. Canopy size is the constant this
## change moved most, and "is that tree the right size" is a question only
## answerable against the thing a player spends the match looking at.
func _build_squad() -> void:
	# The first authored archetype the roster offers, NOT a named one: unit
	# ids are civ-prefixed (D-047) and no `.gd` here may name a civ.
	var def: UnitDef = null
	for candidate in UnitRoster.load_all():
		if candidate.model_id != &"":
			def = candidate
			break
	if def == null:
		push_warning("forest_preview: no authored unit to stand in the wood")
		return
	var unit := PrimitiveUnit.new()
	add_child(unit)
	unit.rebuild(def, PlayerColours.of_index(0))
	var origin := _centre + Vector3(0.0, 0.0, 6.0)
	unit.position = origin

	var transforms: Array[Transform3D] = []
	for i in range(SQUAD_SIZE):
		var local := Vector3((float(i % 4) - 1.5) * 1.15, 0.0, float(i / 4) * -1.25)
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
## SKIPPED, not substituted: missing art costs fidelity, never the game
## (D-081's fallback rule).
func _flush(groups: Dictionary) -> void:
	for model in groups:
		var mesh := UnitMesh.mesh_for(model)
		if mesh == null:
			push_warning("forest_preview: no mesh for %s; skipped" % model)
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
		add_child(instance)
		_multis += 1
		_instances += transforms.size()
		_models_drawn[model] = true


## The numbers the recipe gates on. They cannot tell whether the wood looks
## like a wood — that is what the PNG is for — but they can tell whether
## there is one, which is the failure that would otherwise produce a
## confident screenshot of an empty meadow.
func _report() -> void:
	var nodes := 0
	var wood := 0
	for entry in _economy.node_entries():
		nodes += 1
		if int(entry["kind"]) == Economy.ResourceKind.WOOD:
			wood += 1
	print("forest_preview: %d nodes (%d wood) on %d cells, %d trees "
		% [nodes, wood, _space.cell_count(), _trees]
		+ "(%.2f per node), %d instances in %d multimeshes, %d models"
			% [float(_trees) / maxf(1.0, float(nodes)), _instances, _multis,
				_models_drawn.size()])
	print("forest_preview: renderer=%s adapter=%s"
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
		push_error("forest_preview: could not write %s (%d)" % [absolute, err])
		get_tree().quit(1)
		return
	print("forest_preview: wrote %s (%dx%d)"
		% [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)
