extends Node3D

## A rendered picture of the GROUND, in the shipping lighting rig (D-096/D-097).
##
## ## Why this had to exist
##
## `gen-terrain-preview` draws a top-down biome PNG from `biome_color` and
## reports chunk counts. Every number it prints was healthy for two milestones
## while the ground read as a honeycomb of flat hexes and no cliff was visible
## anywhere on the map — because none of those numbers is about how the ground
## LOOKS. `test-client` does render the real thing, but it points its camera at
## a player's spawn, which is walkable ground by construction and therefore the
## one place a cliff cannot be.
##
## So this frames the terrain deliberately: it finds the longest run of
## passability boundary on the map and looks at it from a shallow angle. That is
## the shot that answers the owner's actual question.
##
## Software-rasterised like `gen-model-preview`, so it needs no GPU and says
## nothing about speed — `bench-render` is the recipe for that, and it is native
## for exactly that reason (D-044 criterion 2).
##
## Lighting comes from `WorldLook` with `preview = false`: the SHIPPING sun, sky,
## ambient, tonemap and fog. A terrain shot lit by the model preview's flat
## studio backdrop would be a picture of a different game (D-086).

@export var out_path: String = "res://artifacts/terrain-3d.png"
@export var map_path: String = "res://maps/default.tres"
@export var seconds: float = 0.4
@export var camera_height: float = 7.0

var _elapsed := 0.0
var _shot := false


func _ready() -> void:
	_parse_arguments()

	var config := load(map_path) as MapConfig
	if config == null:
		push_error("terrain_shot: could not load %s" % map_path)
		get_tree().quit(1)
		return
	var space := config.to_space()
	var terrain := TerrainGen.new()
	var fields := terrain.build_fields(space)

	add_child(WorldLook.make_sun())
	var environment := WorldEnvironment.new()
	# Fog tuned for a camera at THIS height, not for the map's overhead ceiling:
	# `fog_density_for` derives the density from how far the camera can see, and
	# a close-up shot lit for a 90-unit view is a picture of grey haze.
	environment.environment = WorldLook.make_environment(false,
		maxf(camera_height, 8.0))
	add_child(environment)

	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(space, chunk_size)
	var material := TerrainChunk.make_material()
	var cliff_quads := 0
	var meshes: Array[ArrayMesh] = []
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(space, terrain,
				Vector2i(cx, cy), chunk_size, fields)
			if mesh == null:
				continue
			if mesh.get_surface_count() > TerrainChunk.SKIRT_SURFACE:
				var faces: PackedInt32Array = mesh.surface_get_arrays(
					TerrainChunk.SKIRT_SURFACE)[Mesh.ARRAY_INDEX]
				@warning_ignore("integer_division")
				cliff_quads += faces.size() / 6
			meshes.append(mesh)

	# All NINE lattice copies, as the client draws them (D-035) — sharing the
	# same Mesh resources, so this costs draw calls rather than memory.
	#
	# The first version of this shot drew one copy, and the cell it framed
	# happened to sit on row 0. Half the ground around the cliff was on the far
	# side of the seam and therefore drawn nowhere, so the picture showed a rock
	# wall hanging over a void — which reads exactly like a hole in the mesh and
	# was reported as one. A terrain shot that does not tile the torus is a
	# picture of a different world than the one the game renders.
	for i in [-1, 0, 1]:
		for j in [-1, 0, 1]:
			var tile := Node3D.new()
			tile.position = space.lattice_steps()[0] * float(i) 				+ space.lattice_steps()[1] * float(j)
			for mesh in meshes:
				var instance := MeshInstance3D.new()
				instance.mesh = mesh
				instance.material_override = material
				tile.add_child(instance)
			add_child(tile)

	var target := _most_interesting_cell(space, fields)
	var focus := space.to_world(target)
	focus.y = TerrainChunk.height_at(space, fields.surface, focus.x, focus.z)

	var camera := Camera3D.new()
	camera.current = true
	# Low and close, unlike the client's overhead view: a vertical face is
	# invisible from directly above, which is the other half of why nobody had
	# seen one.
	# Parented BEFORE aiming: `look_at` works on the global transform and quietly
	# does nothing to a node outside the tree, which left the first version of
	# this shot pointing at the horizon with the cliff in a corner.
	add_child(camera)
	camera.position = focus + Vector3(camera_height * 0.85, camera_height * 0.5,
		camera_height * 0.85)
	camera.look_at(focus, Vector3.UP)

	print("terrain_shot: map %dx%d, %d cliff faces, looking at cell %s"
		% [space.width, space.height, cliff_quads, target])
	print("terrain_shot: renderer=%s adapter=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		RenderingServer.get_video_adapter_name()])


## The cell with the most impassable neighbours that is itself walkable — the
## foot of the longest stretch of cliff on the map. Prefers mountain to water,
## because a mountain wall is the case D-097 exists for and a shoreline shows up
## in any shot at all.
func _most_interesting_cell(space: TorusSpace, fields: TerrainFields) -> Vector2i:
	var best := Vector2i.ZERO
	var best_score := -1
	for i in range(space.cell_count()):
		if fields.passable[i] != 1:
			continue
		var score := 0
		for direction in range(6):
			var j := space.neighbor_index(i, direction)
			if fields.cliff_class[j] == int(TerrainGen.CliffClass.HIGH):
				score += 4
			elif fields.cliff_class[j] == int(TerrainGen.CliffClass.WATER):
				score += 1
		if score > best_score:
			best_score = score
			best = space.from_index(i)
	return best


func _process(delta: float) -> void:
	if _shot:
		return
	_elapsed += delta
	if _elapsed < seconds:
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
	print("terrain_shot: wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	print("VERDICT: ok - LOOK AT %s" % out_path)
	get_tree().quit(0)


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--out="):
			out_path = text.trim_prefix("--out=")
		elif text.begins_with("--map="):
			map_path = text.trim_prefix("--map=")
		elif text.begins_with("--height="):
			camera_height = float(text.trim_prefix("--height="))
		elif text.begins_with("--seconds="):
			seconds = float(text.trim_prefix("--seconds="))
