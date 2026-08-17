extends RefCounted
class_name PropFog

## Fog of war for the things that STAND on the ground
## (D-20260817-fog-covers-props).
##
## `TerrainFog` decides what one client knows about each CELL and
## `shaders/terrain.gdshader` draws it. This is the other half of that: the same
## field, read by the models standing on those cells, so a forest is as dim as
## the ground it grows in.
##
## D-106 landed the ground half and stopped there. Every entity-level fog
## mechanism was real and tested, the terrain shader multiplied its albedo by
## `known` correctly, and the resource-node visuals (D-087) — thousands of trees
## and stone piles, one MultiMesh per (chunk, model) — carried no fog uniform at
## all. Ground the player scouted and left rendered at 0.45 with a fully lit
## forest floating on it, and at the blurred edge of a vision disk with a fully
## lit forest on ground close to black. Sixth instance of the family: nothing
## failed, every number stayed green, the game quietly lacked a rule.
##
## ## Why the materials have to be rebuilt rather than configured
##
## The authored models arrive as ordinary glTF — one StandardMaterial3D per part
## colour, flat albedo, no textures. A StandardMaterial3D has no way to multiply
## its albedo by a texture sampled at a coordinate the mesh does not carry, and
## `material_override` on a MultiMeshInstance3D replaces EVERY surface at once,
## which would cost a tree the difference between its trunk and its canopy. So
## each surface is re-expressed as `shaders/prop_fog.gdshader` with the authored
## numbers passed straight through — and `test_prop_fog.gd` asserts they arrive
## unchanged, because a colour that crosses a pipeline is not the colour that
## comes out (D-100's lesson, one boundary further along).
##
## ## What it does NOT touch
##
## `UnitMesh.mesh_for` still returns the authored mesh untouched. Rewriting a
## cached, shared resource under every other caller is action at a distance, and
## `tests/test_ground_cover.gd` asserts against exactly those imported materials.
## The shaded mesh is a copy, cached here, and callers ask for it by name.
##
## Buildings are deliberately left alone. A building once seen is KNOWLEDGE, not
## sight (D-030), and D-101 has just settled that it is drawn un-dimmed for that
## reason — the minimap and the world agree about it, and dimming one and not the
## other is how the two drift.
##
## All-static, like `Formation`, `AnimationState` and `TerrainFog`'s siblings:
## the only mutable state here is the two caches, and both are keyed by their
## input, so there is nowhere for a per-tree value to live.

const SHADER_PATH := "res://shaders/prop_fog.gdshader"

## The uniform names on `shaders/prop_fog.gdshader`. The fog sampler shares
## `TerrainFog.SHADER_PARAM` with the terrain shader on purpose — it is the same
## texture bound to both, and one definition means a rename cannot fog the
## ground while leaving the trees lit.
const ALBEDO_PARAM := "albedo"
const ROUGHNESS_PARAM := "surface_roughness"
const METALLIC_PARAM := "surface_metallic"
const EMISSION_PARAM := "surface_emission"

static var _shader: Shader = null

## Authored mesh -> the shaded copy of it. Keyed by the mesh object because that
## is what `UnitMesh` already caches by model id, so this is one entry per model
## and never one per node on the map — the M4 `by_id` shape, which this project
## has now paid for four times.
static var _shaded := {}

## Every shaded material built so far, so one call can bind a client's fog field
## to all of them. Held rather than rediscovered because the alternative is
## walking the scene tree for MultiMeshInstance3Ds, which is a rendering
## question asked of a data structure.
static var _materials: Array[ShaderMaterial] = []

## The field currently bound, kept so a material built AFTER `set_fog` still
## gets it. Chunks are shaded lazily as the server reveals nodes, which is
## minutes after the client binds its fog — a `set_fog` that only walked the
## materials that already existed would leave every forest scouted after the
## first frame drawn fully lit, which is this bug with a smaller blast radius.
static var _fog: Texture2D = null


## Drop every cache. For tests only, like `UnitMesh.reload`.
static func reload() -> void:
	_shader = null
	_shaded = {}
	_materials = []
	_fog = null


## `mesh`, with every surface re-expressed so it can read the fog field.
##
## Returns the SAME copy for the same input mesh every time, so a chunk rebuild
## costs nothing and every tree of one species shares one material — which is
## also what makes `set_fog` a single pass rather than a per-instance one.
##
## Hands the mesh straight back if there is nothing to shade (no shader on disk,
## no surfaces, a surface with no material). That is the same bargain the rest of
## the art path makes: a missing or damaged build costs fidelity, never the game.
static func shaded(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	if _shaded.has(mesh):
		return _shaded[mesh]

	var copy := _shade(mesh)
	_shaded[mesh] = copy
	return copy


static func _shade(mesh: Mesh) -> Mesh:
	if _shader_resource() == null:
		return mesh

	# A PrimitiveMesh (the capsule/cylinder stand-ins used when `generated/` has
	# not been built) keeps its material in a property rather than in a surface,
	# so it takes the other branch. Both are duplicated first: the authored mesh
	# is shared with the previews and with `UnitMesh`'s cache, and rewriting it
	# in place would change what every other caller draws.
	if mesh is PrimitiveMesh:
		var primitive := (mesh as PrimitiveMesh).duplicate() as PrimitiveMesh
		var swapped := material_for(primitive.material as StandardMaterial3D)
		if swapped == null:
			return mesh
		primitive.material = swapped
		return primitive

	var array_mesh := mesh as ArrayMesh
	if array_mesh == null or array_mesh.get_surface_count() == 0:
		return mesh

	var copy := array_mesh.duplicate() as ArrayMesh
	if copy == null:
		return mesh
	for surface in range(copy.get_surface_count()):
		var swapped := material_for(copy.surface_get_material(surface) as StandardMaterial3D)
		if swapped != null:
			copy.surface_set_material(surface, swapped)
	return copy


## The fog-capable equivalent of one imported material: the authored albedo,
## roughness and metallic passed through unchanged, plus the fog tap.
##
## `albedo` is declared `source_color` in the shader, which is the same treatment
## `StandardMaterial3D.albedo_color` gets — so the sRGB/linear round trip that
## turned an authored 0.36 into a rendered 0.63 in D-100 cannot happen here by
## the value crossing one more boundary. The test asserts it on the far side
## rather than trusting the argument.
static func material_for(base: StandardMaterial3D) -> ShaderMaterial:
	if base == null or _shader_resource() == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = _shader_resource()
	material.set_shader_parameter(ALBEDO_PARAM, base.albedo_color)
	material.set_shader_parameter(ROUGHNESS_PARAM, base.roughness)
	material.set_shader_parameter(METALLIC_PARAM, base.metallic)
	# Emission is carried rather than dropped for the primitive stand-ins, which
	# lean on it to read against similar-hued ground; every authored model on the
	# map has none. It is multiplied by `known` in the shader like albedo is —
	# an emissive marker that fog could not dim would be the one thing on the
	# ground still glowing over country nobody has walked.
	material.set_shader_parameter(EMISSION_PARAM,
		(base.emission * base.emission_energy_multiplier) if base.emission_enabled
			else Color(0.0, 0.0, 0.0, 1.0))
	material.set_shader_parameter(TerrainFog.SHADER_PARAM, _fog)
	_materials.append(material)
	return material


## Bind one client's fog field to everything shaded so far, and to everything
## shaded afterwards.
##
## Global rather than per-material because a process runs exactly one client
## (D-014) and the alternative is threading a texture through the chunk builder.
## `null` unbinds — which is what leaving a match wants, since the shader's
## `hint_default_white` then draws the whole world again, exactly as it does for
## the previews that never bind anything.
static func set_fog(fog: Texture2D) -> void:
	_fog = fog
	for material in _materials:
		material.set_shader_parameter(TerrainFog.SHADER_PARAM, fog)


## Whether a field is bound. Reported by `client.gd` beside `textured=` and
## `fogged=` for the reason those two are reported: an unbound prop draws the
## whole map's forests fully lit, and that is what a healthy frame looks like to
## every number the client prints.
static func is_bound() -> bool:
	return _fog != null


## Where a model standing on `cell` reads the fog field, as MultiMesh
## per-instance custom data: `(u, v, 1, 0)`.
##
## The coordinate is `TerrainChunk.fog_uv`'s — the SAME function the terrain mesh
## bakes into its own vertices, not a second copy of the arithmetic — so a tree
## and the ground under it can only ever read the same texel. Cell-derived, never
## world-derived: a chunk root is moved to a different torus copy every frame
## (D-035), and a world-position lookup would fog the copies differently.
##
## The third component is the "this is real" flag `prop_fog.gdshader` mixes on.
## An instance that never gets custom data reads zero there and is drawn fully
## lit, which is the honest answer for a renderer with no player.
static func instance_data(space: TorusSpace, cell: Vector2i) -> Color:
	var uv := TerrainChunk.fog_uv(space, cell, -1)
	return Color(uv.x, uv.y, 1.0, 0.0)


static func _shader_resource() -> Shader:
	if _shader == null and ResourceLoader.exists(SHADER_PATH):
		_shader = load(SHADER_PATH) as Shader
	return _shader
