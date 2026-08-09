extends RefCounted
class_name UnitMesh

## Loads authored models and their vertex animation textures (D-064, D-065).
##
## Everything here is CACHED, and that is not an optimisation. `UnitRoster.by_id`
## re-scanned `/units` from disk on every call and `SquadSim.tick` calls it once
## per squad a building finishes; twenty simultaneous completions spent 858 ms —
## over eight tick budgets — inside a filesystem walk (M4). A `.glb` is a scene
## that must be instantiated to get a mesh out of, which is strictly more
## expensive than that, and the client creates a node per squad. Loading per
## squad would be the same defect with a bigger constant.
##
## The sweep could not see that one and would not see this one either: a
## benchmark resolves its assets once at setup. Where a sweep and a live run
## disagree, believe the live run.
##
## ## Missing assets degrade, they do not crash
##
## `mesh_for` returns null when a model is absent, and `PrimitiveUnit` falls
## back to its primitive. That keeps the bots, the tests and a fresh clone whose
## `generated/` has not been built working, and it means an art build failure
## costs fidelity rather than the game.

const MANIFEST_PATH := "res://generated/manifest.json"
const MODEL_DIR := "res://generated/models"
const VAT_DIR := "res://generated/vat"

const OPAQUE_SHADER := "res://shaders/unit_anim.gdshader"
const GHOST_SHADER := "res://shaders/unit_anim_ghost.gdshader"
const STATIC_SHADER := "res://shaders/building_static.gdshader"

static var _manifest := {}
static var _manifest_loaded := false
static var _meshes := {}
static var _vats := {}
static var _shaders := {}

## How many times a model was actually pulled off disk. A test asserts this
## stays at one per model however many squads are built, which is the check the
## M4 defect above would have failed.
static var load_count := 0


## Drop every cache. For tests only; assets do not change at runtime.
static func reload() -> void:
	_manifest = {}
	_manifest_loaded = false
	_meshes = {}
	_vats = {}
	_shaders = {}
	load_count = 0


static func manifest() -> Dictionary:
	if _manifest_loaded:
		return _manifest
	_manifest_loaded = true
	_manifest = {}

	if not FileAccess.file_exists(MANIFEST_PATH):
		# Not an error: `generated/` is a build output, and the primitive path
		# is a working game without it.
		return _manifest

	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("UnitMesh: %s did not parse as JSON" % MANIFEST_PATH)
		return _manifest

	_manifest = parsed
	return _manifest


## The manifest entry for a model, or an empty Dictionary.
static func layout_for(model_id: StringName) -> Dictionary:
	var units: Dictionary = manifest().get("units", {})
	return units.get(String(model_id), {})


static func has_model(model_id: StringName) -> bool:
	return not layout_for(model_id).is_empty()


## The authored mesh for `model_id`, or null if there is no such model.
static func mesh_for(model_id: StringName) -> Mesh:
	if _meshes.has(model_id):
		return _meshes[model_id]

	var mesh: Mesh = null
	var path := "%s/%s.glb" % [MODEL_DIR, model_id]
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			# A .glb imports as a scene. Instantiate once, take the mesh
			# resource, free the scene — the mesh outlives it.
			var root := packed.instantiate()
			var found := _first_mesh(root)
			if found != null:
				mesh = found.mesh
			root.queue_free()
			load_count += 1
	# Warn only when the manifest CLAIMS this model exists and it still would
	# not load — that is the surprising case, and it means `generated/` is
	# damaged rather than absent.
	#
	# A model_id with no manifest entry is quiet on purpose: either nobody has
	# run `just build-assets` (in which case capsules everywhere is the designed
	# behaviour, not news), or a `.tres` names a model that was never built —
	# and tests/test_art_assets.gd fails loudly on exactly that, which is a
	# better place to catch it than a runtime warning nobody reads.
	if mesh == null and not layout_for(model_id).is_empty():
		push_warning("UnitMesh: '%s' is in the manifest but did not load; "
			% model_id + "using the primitive")

	_meshes[model_id] = mesh
	return mesh


## The baked clips for `model_id`, or null.
static func vat_for(model_id: StringName) -> Texture2D:
	if _vats.has(model_id):
		return _vats[model_id]

	var tex: Texture2D = null
	var path := "%s/%s.exr" % [VAT_DIR, model_id]
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_vats[model_id] = tex
	return tex


## A material for one squad. Per squad rather than shared, because the owner's
## colour is a uniform on it (D-052) and two players' squads of the same type
## must not share one.
static func material_for(model_id: StringName, team_colour: Color,
		ghost: bool = false) -> ShaderMaterial:
	var vat := vat_for(model_id)
	if vat == null:
		return null

	var material := ShaderMaterial.new()
	material.shader = _shader(ghost)

	var layout := layout_for(model_id)
	material.set_shader_parameter("vat", vat)
	material.set_shader_parameter("vat_size", vat.get_size())
	material.set_shader_parameter("total_frames",
		float(layout.get("total_frames", 64)))
	material.set_shader_parameter("colour_row",
		float(layout.get("colour_row", 128)))
	material.set_shader_parameter("frames_per_clip",
		float(layout.get("frames_per_clip", 16)))
	material.set_shader_parameter("team_colour", team_colour)
	return material


## A material for an authored model with no VAT — buildings (D-064).
##
## Separate from `material_for` because the two answer different questions: a
## unit needs its clips and a building needs none, and giving buildings the
## animated shader would make every one of them carry a texture sampler it
## never reads.
static func static_material_for(team_colour: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if not _shaders.has(STATIC_SHADER):
		_shaders[STATIC_SHADER] = load(STATIC_SHADER) as Shader
	material.shader = _shaders[STATIC_SHADER]
	material.set_shader_parameter("team_colour", team_colour)
	return material


static func _shader(ghost: bool) -> Shader:
	var path := GHOST_SHADER if ghost else OPAQUE_SHADER
	if not _shaders.has(path):
		_shaders[path] = load(path) as Shader
	return _shaders[path]


static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null
