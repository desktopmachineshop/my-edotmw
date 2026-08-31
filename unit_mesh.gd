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
const STATIC_SHADER := "res://shaders/building_static.gdshader"
const GHOST_SHADER := "res://shaders/building_ghost.gdshader"
const CORPSE_SHADER := "res://shaders/unit_corpse.gdshader"

static var _manifest := {}
static var _manifest_loaded := false
static var _meshes := {}
static var _vats := {}
static var _textures := {}
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
	_textures = {}
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


## The model's OWN albedo texture, or null when it has none — which is every
## generated model in the roster (D-20260824-a-textured-model-keeps-its-
## texture). Cached like everything else here, for the M4 reason in the
## header: a texture pulled off disk per squad is the `by_id` defect again.
static func texture_for(model_id: StringName) -> Texture2D:
	if _textures.has(model_id):
		return _textures[model_id]
	var texture: Texture2D = null
	var relative := String(layout_for(model_id).get("texture", ""))
	if relative != "":
		var path := "res://" + relative
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
		else:
			# The manifest CLAIMS one and it is not there — that is
			# `generated/` damaged rather than absent, the same distinction
			# `mesh_for` draws.
			push_warning("UnitMesh: '%s' names texture '%s', which is missing"
				% [model_id, relative])
	_textures[model_id] = texture
	return texture


## A material for one squad. Per squad rather than shared, because the owner's
## colour is a uniform on it (D-052) and two players' squads of the same type
## must not share one.
##
## One shader, always opaque: a squad is drawn or it is not (D-099). The
## transparent variant this used to select for fog ghosts is gone with the
## ghost rendering it existed for.
static func material_for(model_id: StringName, team_colour: Color) -> ShaderMaterial:
	var vat := vat_for(model_id)
	if vat == null:
		return null

	var material := ShaderMaterial.new()
	material.shader = _shader()

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
	_bind_albedo(material, model_id)
	return material


## Bind a model's own texture, when it has one. Kept in one function because
## the corpse layer draws the SAME model and must not disagree about what it
## looks like.
static func _bind_albedo(material: ShaderMaterial, model_id: StringName) -> void:
	var texture := texture_for(model_id)
	material.set_shader_parameter("use_albedo_tex", texture != null)
	if texture != null:
		material.set_shader_parameter("albedo_tex", texture)


## A material for one (model, owner) bucket of the corpse layer
## (D-20260819-a-casualty-is-visible). Same VAT and layout as
## `material_for`, a different program: the corpse shader remaps the
## per-instance floats to (fall phase, fog UV, fog flag) and takes its one
## clip as the `corpse_clip` uniform — "death" when the bake carries it,
## whatever pose the renderer chose while it does not (D-081's fallback:
## a missing clip costs fidelity, never the game).
static func corpse_material_for(model_id: StringName, team_colour: Color,
		fog: Texture2D) -> ShaderMaterial:
	var vat := vat_for(model_id)
	if vat == null:
		return null

	var material := ShaderMaterial.new()
	if not _shaders.has(CORPSE_SHADER):
		_shaders[CORPSE_SHADER] = load(CORPSE_SHADER) as Shader
	material.shader = _shaders[CORPSE_SHADER]

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
	material.set_shader_parameter("corpse_clip", float(death_clip_for(model_id)))
	_bind_albedo(material, model_id)
	if fog != null:
		material.set_shader_parameter("fog", fog)
	return material


## Which row block of THIS model's VAT plays `wanted`, an `AnimationState`
## clip index.
##
## ## Why a clip index has to be translated at all
##
## `AnimationState.CLIP_NAMES` is the NUMBERING every clip shares; a model's
## manifest entry says which prefix of it that model actually baked
## (`clips_for` in art/lib/clips.py). Most of the roster bakes four; the
## gatherer bakes seven, because it is the only unit carrying tools.
##
## The translation cannot happen in the shader. `unit_vat.gdshaderinc` finds a
## row at `clip * frames_per_clip + local`, so asking a four-clip militia for
## clip 4 is not an out-of-range error — row 64 of its VAT is the first NORMALS
## row, and the model would come apart into a cloud with nothing reporting
## anything. So it happens here, on the CPU, where "this model has no such
## clip" is a fact the manifest can answer.
##
## The fallback is stated per clip rather than always idle: a gatherer model
## that has not been rebuilt should still swing at a tree, and `attack` is the
## nearest thing every model has to a work stroke. `forage` has no tool in it
## and falls to `idle`, which is what it looks like anyway.
##
## Same shape as `death_clip_for` below, and the same reason: the manifest has
## carried a per-model clip list since M7, and reading it is how a model gains
## a clip without every caller learning about it.
static func clip_index(model_id: StringName, wanted: int) -> int:
	var clips: Array = layout_for(model_id).get("clips", [])
	if clips.is_empty():
		return wanted
	var found := clips.find(_clip_name(wanted))
	if found >= 0:
		return found
	for fallback in CLIP_FALLBACK.get(wanted, []):
		found = clips.find(_clip_name(fallback))
		if found >= 0:
			return found
	return maxi(0, clips.find("idle"))


## What each clip degrades to on a model that never baked it, in order.
const CLIP_FALLBACK := {
	AnimationState.CLIP_CHOP: [AnimationState.CLIP_ATTACK],
	AnimationState.CLIP_MINE: [AnimationState.CLIP_ATTACK],
	AnimationState.CLIP_FORAGE: [AnimationState.CLIP_IDLE],
}


static func _clip_name(index: int) -> String:
	if index < 0 or index >= AnimationState.CLIP_NAMES.size():
		return ""
	return String(AnimationState.CLIP_NAMES[index])


## The clip index a corpse of `model_id` samples, from the manifest's own
## clip list — the upgrade path D-20260819 records: the moment a rebuilt
## bake ships a "death" clip, corpses use it with no code change here.
## Until then the pose is the idle clip's and the renderer tips the whole
## transform instead. -1 only when the model has no clips at all.
static func death_clip_for(model_id: StringName) -> int:
	var clips: Array = layout_for(model_id).get("clips", [])
	var death := clips.find("death")
	if death >= 0:
		return death
	return clips.find("idle")


## Whether `model_id`'s bake shows the WORK itself, or the render layer has to
## suggest it by leaning the whole soldier about
## (`CosmeticOffset.SWING_AMPLITUDE`).
##
## Asked of the manifest rather than of the archetype: "is this a gatherer" is
## the wrong question — what matters is whether this MODEL was baked with the
## work clips, and a `generated/` from before that bake was not.
static func animates_work(model_id: StringName) -> bool:
	var clips: Array = layout_for(model_id).get("clips", [])
	return clips.has("chop") or clips.has("mine")


## Whether `model_id`'s bake carries a real death clip, or corpses of it
## fall by the renderer's tip-over instead.
static func has_death_clip(model_id: StringName) -> bool:
	return Array(layout_for(model_id).get("clips", [])).has("death")


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


## The PLACEMENT PREVIEW material for an authored building
## (D-20260831-a-placement-ghost-is-the-building-it-will-build) —
## `static_material_for`'s sibling, and deliberately not a variant of it:
## a ghost reads the mesh's COLOR.rgb and must IGNORE its alpha, which
## that shader uses as the owner-colour mask (D-052). See
## `shaders/building_ghost.gdshader` for what a StandardMaterial3D does
## to a building whose walls carry alpha 0.
static func ghost_material_for(tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if not _shaders.has(GHOST_SHADER):
		_shaders[GHOST_SHADER] = load(GHOST_SHADER) as Shader
	material.shader = _shaders[GHOST_SHADER]
	material.set_shader_parameter("tint", tint)
	return material


## How far to lift a building's mesh so its BASE sits on the ground.
##
## THE one definition, because it has been wrong in three places at once.
## An authored model is built with its origin already at the base
## (`box(..., centre=(0, height/2, 0))` spans y=0 to y=height), so it needs
## no lift; a primitive (BoxMesh, CylinderMesh, ...) is centred on its own
## origin and rises by half its height. A single hardcoded 1.5 — half the
## default box's 3.0 — used to stand in for all of it, which floated every
## authored building when M7 landed, and still floated every wall-family
## ghost by the difference between 1.5 and its own half-height.
static func ground_lift(mesh_height: float, authored: bool) -> float:
	return 0.0 if authored else mesh_height / 2.0


static func _shader() -> Shader:
	if not _shaders.has(OPAQUE_SHADER):
		_shaders[OPAQUE_SHADER] = load(OPAQUE_SHADER) as Shader
	return _shaders[OPAQUE_SHADER]


static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null
