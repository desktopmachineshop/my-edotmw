extends Node3D

## Renders every authored unit, animated, and screenshots it (D-063 criterion 4).
##
## Run by `just gen-model-preview`. Software-rasterised so it needs no GPU —
## which is what makes it usable from a container and from CI, unlike
## `just bench-render`, which needs real hardware and answers a different
## question (how fast) than this one (does it look right).
##
## Every squad here goes through the REAL path: a `UnitDef` from `/units`, a
## `PrimitiveUnit`, `UnitMesh`, and the same shaders the client uses. A preview
## that built its own MultiMesh would prove the assets exist and nothing about
## whether the game can draw them.
##
## `CLAUDE.md` is blunt about why this exists: "Numbers can all be right while
## the picture is wrong." The PNG is meant to be looked at.

const ROW_SPACING := 7.0
const COLUMN_SPACING := 5.5
const SOLDIERS_PER_SQUAD := 12
# D-076: the building roster grew from 4 to 9 with the wall/gate/garrison
# family. The camera framing below was tuned for 4 and silently clipped the
# ends of a wider row rather than failing — exactly the class of defect
# this file's own docstring warns about ("the picture is meant to be looked
# at"), so both the spacing and the camera were widened together to fit the
# whole roster, not just the buildings that used to exist.
const BUILDING_SPACING := 4.2

@export var seconds: float = 1.5
@export var out_path: String = "res://artifacts/models-godot.png"

var _units: Array[PrimitiveUnit] = []
var _space: TorusSpace
var _terrain_sampler: Callable
var _elapsed := 0.0
var _shot := false


func _ready() -> void:
	_parse_arguments()
	_build_environment()
	_build_terrain()
	_build_buildings()
	_build_squads()


## Authored buildings, in front of the squads (D-064).
##
## Two owners again, for the same reason the squads have two: a town hall you
## cannot attribute at a glance is worse than a squad you cannot, because it
## tells you whose ground you are standing on (D-052).
func _build_buildings() -> void:
	var defs := BuildingSim.all_defs()
	var colours := [PlayerColours.of_index(0), PlayerColours.of_index(1)]

	for i in range(defs.size()):
		var def: BuildingDef = defs[i]
		if def.model_id == &"":
			continue
		var mesh := UnitMesh.mesh_for(def.model_id)
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = UnitMesh.static_material_for(
			colours[i % colours.size()])
		var at := Vector3((float(i) - float(defs.size() - 1) / 2.0) * BUILDING_SPACING, 0.0, 6.5)
		if _terrain_sampler.is_valid():
			at.y = _terrain_sampler.call(at.x, at.z)
		instance.position = at
		add_child(instance)
	print("model_preview: %d buildings" % defs.size())


## Real terrain under the models (D-066), so one picture answers whether the
## atlas reads at play distance and whether soldiers sit ON the ground.
##
## Built through `TerrainChunk` with the shared material, not a stand-in plane:
## a preview that invented its own ground would be checking nothing about the
## thing that ships. Small and flat-seeded because this is a model preview —
## the seam and the full map are `test-client`'s job.
func _build_terrain() -> void:
	var config := MapConfig.new()
	config.width = 24
	config.height = 16
	_space = TorusSpace.new(config.width, config.height)

	var terrain := TerrainGen.new()
	# The continuous ground surface (D-067), shared with the mesh below.
	var fields := terrain.build_fields(_space)
	var surface := fields.surface
	_terrain_sampler = func(x: float, z: float) -> float:
		return TerrainChunk.height_at(_space, surface, x, z)

	var material := TerrainChunk.make_material()
	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(_space, chunk_size)
	var root := Node3D.new()
	# Centre the patch under the squads rather than moving the camera, so the
	# framing stays comparable with earlier shots.
	root.position = -_space.to_world(Vector2i(config.width / 2, config.height / 2))
	add_child(root)

	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(_space, terrain, Vector2i(cx, cy), chunk_size, fields)
			if mesh == null:
				continue
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			root.add_child(instance)

	print("model_preview: terrain %dx%d, atlas=%s"
		% [config.width, config.height,
			"yes" if TerrainChunk.has_atlas() else "NO (generated/ not built)"])


## `--seconds=` and `--out=`, after a bare `--`.
##
## `seconds` is what makes the animation check possible: two runs at different
## times must produce DIFFERENT pixels. A preview that only ever shot one moment
## could not tell a working VAT from a frozen rest pose, which is the same trap
## as asserting nothing complained rather than asserting something happened.
func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--seconds="):
			seconds = float(text.trim_prefix("--seconds="))
		elif text.begins_with("--out="):
			out_path = text.trim_prefix("--out=")


func _build_environment() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 14.0, 30.0)
	camera.rotation_degrees = Vector3(-27.0, 0.0, 0.0)
	camera.fov = 62.0
	add_child(camera)
	camera.make_current()

	add_child(WorldLook.make_sun(true))

	var world := WorldEnvironment.new()
	world.environment = WorldLook.make_environment(true)
	add_child(world)


## One row per archetype, one column per clip, so a single frame shows every
## model in every state it can be in.
func _build_squads() -> void:
	var defs := UnitRoster.load_all()
	var seen := {}
	var archetypes: Array[UnitDef] = []
	for def in defs:
		if def.model_id == &"" or seen.has(def.model_id):
			continue
		seen[def.model_id] = true
		archetypes.append(def)

	# Two owners, so D-063 criterion 5 — can you tell two armies apart — is
	# visible in the same picture rather than taken on trust.
	var colours := [PlayerColours.of_index(0), PlayerColours.of_index(1)]

	for row in range(archetypes.size()):
		var def := archetypes[row]
		for clip in range(AnimationState.CLIP_NAMES.size()):
			var unit := PrimitiveUnit.new()
			add_child(unit)
			unit.rebuild(def, colours[clip % colours.size()])

			var origin := Vector3(
				(float(clip) - 1.5) * COLUMN_SPACING,
				0.0,
				-float(row) * ROW_SPACING)
			unit.position = origin

			var transforms: Array[Transform3D] = []
			for i in range(SOLDIERS_PER_SQUAD):
				var col := i % 4
				var rank := i / 4
				var local := Vector3(
					(float(col) - 1.5) * 1.15, 0.0, float(rank) * -1.25)
				# Soldiers stand ON the terrain, as in client.gd. Deriving at
				# y = 0 puts them inside every hill — which is exactly how the
				# first client frame this project ever rendered came out empty.
				if _terrain_sampler.is_valid():
					local.y = _terrain_sampler.call(
						origin.x + local.x, origin.z + local.z) - origin.y
				transforms.append(Transform3D(Basis(), local))
			unit.set_slot_transforms(transforms)
			unit.set_clip_data(row * 10 + clip, clip, 3.2)
			_units.append(unit)

	print("model_preview: %d archetypes x %d clips = %d squads, %d soldiers each"
		% [archetypes.size(), AnimationState.CLIP_NAMES.size(), _units.size(),
			SOLDIERS_PER_SQUAD])
	print("model_preview: renderer=%s adapter=%s"
		% [ProjectSettings.get_setting("rendering/renderer/rendering_method"),
			RenderingServer.get_video_adapter_name()])


func _process(delta: float) -> void:
	_elapsed += delta
	# Let a little time pass before the shot: the clips are driven by TIME in
	# the shader, so a screenshot at t=0 would show every model in its rest
	# pose and prove nothing about whether animation runs.
	if _shot or _elapsed < seconds:
		return
	_shot = true

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var err := image.save_png(absolute)
	if err != OK:
		push_error("model_preview: could not write %s (%d)" % [absolute, err])
		get_tree().quit(1)
		return
	print("model_preview: wrote %s (%dx%d)"
		% [out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)
