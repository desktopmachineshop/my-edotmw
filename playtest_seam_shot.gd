extends Node3D

## A rendered picture of the TORUS SEAM, with armies standing on it.
##
## ## Why this had to exist
##
## Playtest ticket #32 asks whether the wrapped world reads as seamless:
## terrain across both seams, and armies that neither vanish nor duplicate
## while straddling one. Nothing in the estate could frame that question.
## `test-client` points its camera at a player's spawn; `gen-terrain-shot`
## finds the longest run of passability boundary; `gen-forest-preview`
## frames the densest wood. All three are deliberate framings of something
## else, and a seam is exactly as likely to appear in any of them as any
## other cell -- which is to say almost never, and never on purpose.
##
## Same lesson three other instruments here were bought with: when a
## rendered check has to see something specific, frame it on purpose.
##
## Software-rasterised like `terrain_shot.gd`, so it needs no GPU and says
## nothing about speed. Lighting is `WorldLook` with `preview = false` --
## the SHIPPING rig, or the picture is of a different game (D-086).
##
## What it draws, and why each part is the game's own code rather than
## this file's idea of it:
##
## - terrain through `TerrainChunk.build_mesh` + `TerrainChunk.make_material`,
##   tiled over all nine lattice copies as `client.gd` draws it (D-035)
## - squads through `PrimitiveUnit`, drawn at every copy
##   `RenderCull.visible_offsets_of_extent` reports, via `LatticeCopies.draw`
##   -- the exact pipeline client.gd runs per frame
##   (D-20260818-entities-are-drawn-at-every-visible-copy)
##
## A squad is placed ON the seam so its men are split across the wrap line,
## which is the configuration the ticket names and the one every historical
## seam defect in this project showed up in.

@export var out_path: String = "res://artifacts/seam-godot.png"
@export var map_path: String = "res://maps/default.tres"
@export var seconds: float = 0.6
@export var camera_height: float = 16.0
## Which seam to frame: "q" (the width wrap), "r" (the height wrap), or
## "corner" (where the two meet -- the case a single-axis shot cannot show).
@export var seam: String = "q"

const SQUAD_SIZE := 24

var _space: TorusSpace
var _fields: TerrainFields
var _camera: Camera3D
var _units: Array[PrimitiveUnit] = []
var _mirrors: Array = []
var _bases: Array[Vector3] = []
var _elapsed := 0.0
var _shot := false
var _reported := false


func _ready() -> void:
	_parse_arguments()

	var config := load(map_path) as MapConfig
	if config == null:
		push_error("seam_shot: could not load %s" % map_path)
		get_tree().quit(1)
		return
	_space = config.to_space()
	var terrain := TerrainGen.new()
	_fields = terrain.build_fields(_space)

	add_child(WorldLook.make_sun())
	var environment := WorldEnvironment.new()
	environment.environment = WorldLook.make_environment(false,
		maxf(camera_height, 8.0))
	add_child(environment)

	_build_terrain(terrain)

	var focus := _seam_focus()
	_camera = Camera3D.new()
	_camera.current = true
	# Parented BEFORE aiming: `look_at` works on the global transform and
	# quietly does nothing to a node outside the tree.
	add_child(_camera)
	_camera.position = focus + _camera_offset()
	_camera.look_at(focus, Vector3.UP)

	_build_squads(focus)

	print("seam_shot: map %dx%d, seam=%s, focus cell %s, %d squads drawn"
		% [_space.width, _space.height, seam, _space.world_to_cell(focus),
			_units.size()])
	print("seam_shot: renderer=%s adapter=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		RenderingServer.get_video_adapter_name()])


## Nine copies of the ground, sharing one set of Mesh resources.
func _build_terrain(terrain: TerrainGen) -> void:
	var chunk_size := 16
	var grid := TerrainChunk.chunk_grid(_space, chunk_size)
	var material := TerrainChunk.make_material()
	var meshes: Array[ArrayMesh] = []
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(_space, terrain,
				Vector2i(cx, cy), chunk_size, _fields)
			if mesh != null:
				meshes.append(mesh)
	for i in [-1, 0, 1]:
		for j in [-1, 0, 1]:
			var tile := Node3D.new()
			tile.position = _space.lattice_steps()[0] * float(i) \
				+ _space.lattice_steps()[1] * float(j)
			for mesh in meshes:
				var instance := MeshInstance3D.new()
				instance.mesh = mesh
				instance.material_override = material
				tile.add_child(instance)
			add_child(tile)


## The world point the seam of interest passes through.
##
## Cell (0, 0) is the wrap origin on both axes, so the q seam runs along
## q = 0 and the r seam along r = 0. The focus is nudged ALONG the seam to
## a stretch of walkable ground with variety around it, because a shot of
## the wrap line through open water shows a join in two flat blue planes
## and proves nothing about biome colour, cliffs or trees meeting across it.
func _seam_focus() -> Vector3:
	var best := Vector2i.ZERO
	var best_score := -1
	if seam == "corner":
		best = _best_near(Vector2i.ZERO)
	else:
		var length := _space.height if seam == "q" else _space.width
		for step in range(length):
			var cell := Vector2i(0, step) if seam == "q" else Vector2i(step, 0)
			var score := _interest_of(cell)
			if score > best_score:
				best_score = score
				best = cell
	var world := _space.to_world(best)
	world.y = TerrainChunk.height_at(_space, _fields.surface, world.x, world.z)
	return world


## The best cell within a couple of steps of the wrap ORIGIN. The corner
## shot has one candidate by definition, and if that one cell is water
## there is nothing to look at -- so it may drift, but only far enough
## that both seams are still in frame.
func _best_near(centre: Vector2i) -> Vector2i:
	var best := centre
	var best_score := -1
	for offset in TorusSpace.disk_offsets(2):
		var cell := centre + offset
		var score := _interest_of(cell)
		if score > best_score:
			best_score = score
			best = cell
	return best


## How much a seam cell would SHOW. Land beats water, and land with
## variety around it beats a featureless plain: the defects this shot
## hunts (a texture jump, a colour step, a lighting change) are only
## visible where there is something for them to be discontinuous in.
func _interest_of(cell: Vector2i) -> int:
	var here := _space.index(cell)
	if _fields.passable[here] != 1:
		return -1
	var score := 4
	var biomes := {}
	for offset in TorusSpace.disk_offsets(3):
		var j := _space.index(cell + offset)
		biomes[_fields.biome[j]] = true
	score += biomes.size() * 3
	return score


## Where the eye sits relative to the focus, so the seam LINE crosses the
## frame instead of running away from the camera.
func _camera_offset() -> Vector3:
	var high := camera_height
	if seam == "q":
		return Vector3(high * 1.0, high * 0.55, high * 0.15)
	if seam == "r":
		return Vector3(high * 0.15, high * 0.55, high * 1.0)
	return Vector3(high * 0.8, high * 0.6, high * 0.8)


## One squad standing ON the seam, and one a few cells clear of it as a
## control. The seam squad's men straddle the wrap line, which is where
## every historical defect in this class showed up.
func _build_squads(focus: Vector3) -> void:
	var def: UnitDef = null
	for candidate in UnitRoster.load_all():
		if candidate.model_id != &"":
			def = candidate
			break
	if def == null:
		push_warning("seam_shot: no authored unit in the roster")
		return
	var places: Array[Vector3] = [focus, focus + _control_offset()]
	for i in range(places.size()):
		var unit := PrimitiveUnit.new()
		add_child(unit)
		unit.rebuild(def, PlayerColours.of_index(i))
		var origin := places[i]
		origin.y = TerrainChunk.height_at(_space, _fields.surface,
			origin.x, origin.z)
		var transforms: Array[Transform3D] = []
		for slot in range(SQUAD_SIZE):
			@warning_ignore("integer_division")
			var row := slot / 6
			var local := Vector3((float(slot % 6) - 2.5) * 1.15, 0.0,
				float(row) * -1.25)
			local.y = TerrainChunk.height_at(_space, _fields.surface,
				origin.x + local.x, origin.z + local.z) - origin.y
			transforms.append(Transform3D(Basis(), local))
		unit.set_slot_transforms(transforms)
		unit.set_clip_data(0, 0, 3.2)
		_units.append(unit)
		_bases.append(origin)
		_mirrors.append([] as Array[Node3D])


func _process(delta: float) -> void:
	_draw_copies()
	if _shot:
		return
	_elapsed += delta
	if _elapsed < seconds:
		return
	_shot = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	# `res://` cannot be written in an exported build (#201,
	# D-20260828-artifacts-are-written-where-the-build-can-write). Identity
	# in a checkout, so the recipe's own `--out=` still lands exactly where
	# the justfile looks for it, and this instrument keeps working as it
	# did — the same one-line conversion every other writer in the estate
	# took.
	out_path = ArtifactPath.resolve(out_path)
	var dir_error := ArtifactPath.ensure_dir_for(out_path)
	if dir_error != OK:
		print("VERDICT: fail - could not make the directory for %s (error %d)"
			% [ArtifactPath.describe(out_path), dir_error])
		get_tree().quit(1)
		return
	var absolute := ProjectSettings.globalize_path(out_path)
	var error := image.save_png(absolute)
	if error != OK:
		print("VERDICT: fail - could not write %s (error %d)"
			% [ArtifactPath.describe(out_path), error])
		get_tree().quit(1)
		return
	# `describe` rather than the bare path: `user://` is not a place
	# anybody can open, and the whole of #201 is a writer whose failure
	# nobody could act on.
	print("seam_shot: wrote %s (%dx%d)" % [ArtifactPath.describe(out_path),
		image.get_width(), image.get_height()])
	print("VERDICT: ok - LOOK AT %s" % ArtifactPath.describe(out_path))
	get_tree().quit(0)


## The client's own per-frame copy pipeline, verbatim: ask RenderCull which
## lattice copies of this squad are on screen, then LatticeCopies.draw them
## all. A seam squad legitimately reports TWO, and drawing only one of them
## is the bug class D-20260818 closed.
func _draw_copies() -> void:
	for i in range(_units.size()):
		var offsets := RenderCull.visible_offsets_of_extent(_camera,
			_space.lattice_offsets(), _bases[i], 4.0, 32.0,
			get_viewport().get_visible_rect().size)
		if not _reported:
			print("seam_shot: squad %d at %s visible on %d lattice copy/copies"
				% [i, _space.world_to_cell(_bases[i]), offsets.size()])
		LatticeCopies.draw(_units[i], _mirrors[i], _bases[i], offsets)
	_reported = true


func _control_offset() -> Vector3:
	if seam == "q":
		return Vector3(6.0, 0.0, 0.0)
	if seam == "r":
		return Vector3(0.0, 0.0, 6.0)
	return Vector3(5.0, 0.0, 5.0)


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
		elif text.begins_with("--seam="):
			seam = text.trim_prefix("--seam=")
