extends GutTest

## Guards D-20260817-fog-covers-props: the fog D-106 put on the GROUND also
## reaches everything standing on it (#81).
##
## D-106 landed a day before this and stopped at the terrain shader. Every
## number stayed green — `test-client` counts chunks and colours, the fog field
## itself is covered end to end by `test_terrain_fog.gd`, and the ground really
## was drawn correctly — while the forests, stone piles and ore seams on top of
## it rendered at full brightness over ground the player had walked away from,
## and over the near-black ground at the blurred edge of a vision disk.
##
## So this file is shaped like `test_terrain_fog.gd`, deliberately, and for the
## same reason: the second half is the half that matters.
##
##   1. **The value is right** — the coordinate comes from the CELL, the
##      authored colours survive being re-expressed as a shader.
##   2. **The value is CONNECTED** — the shader declares the input, the client
##      draws resource nodes through a material that has it, and something
##      outside `prop_fog.gd` actually binds a field to it and lets go of it
##      again. That last group is this project's "grep for uncalled public
##      members" rule written as a test, which is the only instrument that has
##      ever caught this defect family.
##
## MultiMesh instance data is deliberately NOT asserted here. A `--headless`
## Godot runs the dummy RenderingServer, which stores nothing: transforms,
## colours and custom data all read back as their defaults, so a test that
## checked them would be asserting the engine's null object. The per-instance
## half is checked by `just test-client`'s rendered frame instead.


const TREE := &"tree_oak_0"
const ORE := &"resource_gold"


func before_each() -> void:
	PropFog.reload()


func after_all() -> void:
	PropFog.reload()


func _space() -> TorusSpace:
	return TorusSpace.new(16, 8)


func _authored(model: StringName) -> Mesh:
	var mesh := UnitMesh.mesh_for(model)
	assert_not_null(mesh, "%s did not load — generated/ is committed, so this "
		% model + "is a damaged checkout rather than a missing art build")
	return mesh


# --- where a prop reads the fog ------------------------------------------


## The one rule the issue's own comment asked for in advance: a tree's fog
## lookup comes from its CELL.
##
## Trees batch one MultiMesh per (chunk, model) and the chunk root is moved
## every frame to whichever of the nine torus copies is on screen (D-035), so
## the same tree renders at nine different world positions over a match. A
## world-derived lookup would sample a different part of the field for each, and
## the tell would be forests correctly fogged mid-map and wrongly fogged at a
## seam — which is D-035's rule and D-096's re-learning of it.
##
## Asserted against `TerrainChunk.fog_uv` ITSELF rather than against a copy of
## its arithmetic written out here, for `test_terrain_fog.gd`'s stated reason: a
## hand-copy agreeing with another hand-copy is not a cross-check. The ground
## and the tree standing on it must read the same texel or the tree is lit by a
## different cell's knowledge.
func test_a_prop_reads_the_fog_at_its_own_cell() -> void:
	var space := _space()
	for cell in [Vector2i(0, 0), Vector2i(7, 3), Vector2i(15, 7)]:
		var data := PropFog.instance_data(space, cell)
		var uv := TerrainChunk.fog_uv(space, cell, -1)
		assert_almost_eq(data.r, uv.x, 1e-6, "%s reads its own column" % cell)
		assert_almost_eq(data.g, uv.y, 1e-6, "%s reads its own row" % cell)
		assert_eq(floori(data.r * float(space.width)), cell.x,
			"%s samples the texel of its own cell" % cell)
		assert_eq(floori(data.g * float(space.height)), cell.y,
			"%s samples the texel of its own cell" % cell)


## The third component is the shader's "this is real" flag, and it must be set
## for anything drawn through a MultiMesh. Zero is what a plain MeshInstance3D
## gets for free — a felled tree mid-animation, a preview's parade — and means
## "fully lit"; a prop that shipped with zero here would be the bug this file
## exists for, wearing the fix.
func test_a_placed_prop_declares_that_its_coordinate_is_real() -> void:
	assert_eq(PropFog.instance_data(_space(), Vector2i(4, 4)).b, 1.0)


# --- the authored colours survive ----------------------------------------


## The re-expressed material must render as the imported one did. A colour that
## crosses an asset pipeline is not the colour that comes out (D-100: an
## authored 0.36 arrived as 0.63 because Godot's glTF importer converts
## linear -> sRGB and nothing converts it back), so this asserts the value on
## the FAR side of the boundary rather than trusting that the copy is a copy.
func test_a_shaded_material_carries_the_authored_numbers() -> void:
	for model in [TREE, ORE]:
		var authored := _authored(model) as ArrayMesh
		if authored == null:
			continue
		var shaded := PropFog.shaded(authored) as ArrayMesh
		assert_not_null(shaded, "%s came back unshaded" % model)
		assert_eq(shaded.get_surface_count(), authored.get_surface_count(),
			"%s must keep every surface — a tree that lost its canopy is what "
				% model + "a material_override would have cost")

		for surface in range(authored.get_surface_count()):
			var base := authored.surface_get_material(surface) as StandardMaterial3D
			var material := shaded.surface_get_material(surface) as ShaderMaterial
			assert_not_null(material,
				"%s surface %d must be able to read the fog" % [model, surface])
			if material == null or base == null:
				continue
			assert_eq(material.get_shader_parameter(PropFog.ALBEDO_PARAM),
				base.albedo_color, "%s surface %d keeps its colour" % [model, surface])
			assert_almost_eq(float(material.get_shader_parameter(PropFog.ROUGHNESS_PARAM)),
				base.roughness, 1e-6, "%s surface %d keeps its roughness" % [model, surface])
			assert_almost_eq(float(material.get_shader_parameter(PropFog.METALLIC_PARAM)),
				base.metallic, 1e-6, "%s surface %d keeps its metal" % [model, surface])


## A tree is a trunk AND a canopy, in two surfaces with two materials — which is
## the whole reason this rebuilds materials instead of setting one
## `material_override` on the MultiMeshInstance3D. If the shipped models ever
## collapse to one surface the assertion above stops meaning anything.
func test_the_shipped_models_have_more_than_one_colour_to_lose() -> void:
	var mesh := _authored(TREE)
	assert_gt(mesh.get_surface_count(), 1,
		"a tree used to be a trunk and a canopy; if it is one surface now, the "
		+ "per-surface machinery in PropFog is no longer buying anything")


## The authored mesh is `UnitMesh`'s cached, shared resource: the previews read
## it, and `tests/test_ground_cover.gd` asserts the imported albedo against the
## manifest. Rewriting it in place would change what every other caller draws
## without any of them asking.
func test_shading_leaves_the_authored_mesh_alone() -> void:
	var authored := _authored(TREE) as ArrayMesh
	PropFog.shaded(authored)
	assert_true(authored.surface_get_material(0) is StandardMaterial3D,
		"UnitMesh.mesh_for must still hand back the imported material")


func test_the_same_mesh_is_shaded_once() -> void:
	var authored := _authored(TREE)
	assert_eq(PropFog.shaded(authored), PropFog.shaded(authored),
		"one material per model, not one per node on the map — the M4 by_id "
		+ "shape this project has now paid for four times")


# --- and is it actually connected ----------------------------------------


func test_the_prop_shader_declares_and_samples_the_fog() -> void:
	var handle := FileAccess.open(PropFog.SHADER_PATH, FileAccess.READ)
	assert_not_null(handle, "the prop shader is where prop_fog.gd says it is")
	if handle == null:
		return
	var text := handle.get_as_text()
	handle.close()

	var declaration := RegEx.new()
	declaration.compile("uniform\\s+sampler2D\\s+%s\\s*:" % TerrainFog.SHADER_PARAM)
	assert_not_null(declaration.search(text),
		"prop_fog.gdshader must declare the uniform PropFog.set_fog binds — and "
		+ "under the SAME name the ground uses, since it is the same texture")
	assert_true(text.contains("texture(%s," % TerrainFog.SHADER_PARAM),
		"declaring the sampler is not sampling it")
	assert_true(text.contains("INSTANCE_CUSTOM"),
		"the coordinate has to arrive per INSTANCE — one material serves every "
		+ "tree of a species, and they stand on different cells")


## Binding must reach materials that already exist AND materials built later.
## Chunks are shaded lazily, as the server reveals nodes, which is minutes after
## the client binds its field: a `set_fog` that only walked what existed at the
## time would leave every forest scouted after the first frame fully lit, which
## is this bug again with a smaller blast radius.
func test_binding_reaches_materials_built_before_and_after_it() -> void:
	var early := PropFog.shaded(_authored(TREE)) as ArrayMesh
	var texture := ImageTexture.create_from_image(TerrainFog.new(_space()).bake())
	PropFog.set_fog(texture)
	var late := PropFog.shaded(_authored(ORE)) as ArrayMesh

	for mesh in [early, late]:
		assert_not_null(mesh)
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			assert_not_null(material)
			if material != null:
				assert_eq(material.get_shader_parameter(TerrainFog.SHADER_PARAM),
					texture, "surface %d never received the field" % surface)


## The materials are cached per model and outlive a match, so the field has to
## be released as well as bound — D-075's rule, one resource further out. Left
## bound, the next match opens drawing its forests through the previous match's
## record of who had been where.
func test_the_field_can_be_let_go_of() -> void:
	var mesh := PropFog.shaded(_authored(TREE)) as ArrayMesh
	PropFog.set_fog(ImageTexture.create_from_image(TerrainFog.new(_space()).bake()))
	PropFog.set_fog(null)
	assert_null((mesh.surface_get_material(0) as ShaderMaterial)
		.get_shader_parameter(TerrainFog.SHADER_PARAM),
		"unbinding leaves the shader's hint_default_white, which draws the "
		+ "whole world — the honest answer for a renderer with no player")


# --- the caller, which is the only check that could have caught this -----


## THE test. Every other check in this file can pass while the client draws its
## forests with the imported StandardMaterial3D and no fog anywhere — which is
## exactly the state `main` was in when #81 was filed, with `TerrainFog`,
## `terrain.gdshader` and the whole of `test_terrain_fog.gd` green.
##
## `client.gd` is native-only (D-014), but `_node_mesh_for` needs no GPU, no
## window and no scene tree: it is a mesh lookup. The lifetime lesson from
## `test_return_to_lobby.gd` applies — "the client is untestable" is only ever
## true of what it DRAWS.
func test_the_client_draws_resource_nodes_with_a_material_that_reads_the_fog() -> void:
	var client: Node3D = autofree(load("res://client.gd").new())
	var mesh: Mesh = client._node_mesh_for(TREE, Economy.ResourceKind.WOOD)
	assert_not_null(mesh, "the client drew nothing at all for a wood node")
	if mesh == null:
		return

	for surface in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface) as ShaderMaterial
		assert_not_null(material,
			"surface %d of a tree the CLIENT draws carries no fog-capable " % surface
			+ "material — a forest the player walked away from renders at full "
			+ "brightness on dim ground, which is #81")
		if material != null:
			assert_true(material.shader.code.contains(TerrainFog.SHADER_PARAM),
				"surface %d's shader cannot read a fog field" % surface)


## The primitive stand-ins too — a checkout that has never run `build-assets`
## should lose fidelity, not the rule. They are the one thing on the ground with
## emission, which is precisely what would keep glowing through fog if it were
## dropped on the way through.
func test_the_primitive_stand_in_is_fogged_as_well() -> void:
	var client: Node3D = autofree(load("res://client.gd").new())
	var mesh: Mesh = client._node_mesh_for(&"no_such_model", Economy.ResourceKind.STONE)
	assert_not_null(mesh, "the fallback must still draw something")
	if mesh == null:
		return
	var material := mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(material, "the stand-in marker is drawn unfogged")
	if material != null:
		var emission: Color = material.get_shader_parameter(PropFog.EMISSION_PARAM)
		assert_gt(emission.r + emission.g + emission.b, 0.0,
			"the stand-in leans on emission to read against similar-hued ground; "
			+ "dropping it on the way through the shader costs the readability "
			+ "the fallback exists for")


## Leaving a match must let the field go. Driven through the real
## `_teardown_match`, because the thing being asserted is that somebody
## remembered to call it — which is the same shape as the bug above.
func test_leaving_a_match_releases_the_field() -> void:
	var client: Node3D = autofree(load("res://client.gd").new())
	var mesh: Mesh = client._node_mesh_for(TREE, Economy.ResourceKind.WOOD)
	PropFog.set_fog(ImageTexture.create_from_image(TerrainFog.new(_space()).bake()))
	client._teardown_match()
	assert_null((mesh.surface_get_material(0) as ShaderMaterial)
		.get_shader_parameter(TerrainFog.SHADER_PARAM),
		"_teardown_match left the next match pointed at this one's fog")


## And the per-instance half, which no headless check can see the VALUE of:
## assert that the client passes one at all. `PropFog.instance_data` with no
## caller is `_explored` read only by the minimap (#58), `BuildingSim.damage`
## (D-055) and `UnitDef.cost` — a rule fully written, correct, and reaching
## nothing that draws.
func test_something_outside_prop_fog_actually_binds_and_places_the_field() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10,
		"Found almost no scripts — the walk is broken, not the code clean")

	var binds: Array = []
	var places: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str == "res://prop_fog.gd" or path_str.begins_with("res://tests/"):
			continue
		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		if text.contains("PropFog.set_fog("):
			binds.append(path_str)
		if text.contains("PropFog.instance_data("):
			places.append(path_str)

	assert_true(binds.has("res://client.gd"),
		"client.gd must hand its fog field to the props as well as to the "
		+ "ground — a field nothing standing on the map reads is #81")
	assert_true(places.has("res://client.gd"),
		"client.gd must give every drawn prop the cell it stands on; without "
		+ "that the instances all read cell (0,0) and a whole forest is lit by "
		+ "one corner of the map")


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))
