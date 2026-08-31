extends GutTest

## Guards D-20260831-a-placement-ghost-is-the-building-it-will-build: the
## build preview wears the model it is about to raise, semi-transparent
## and tinted by whether the ground will take it, instead of a plain box.
##
## The split is `render_cull.gd`'s (D-045): the half with the interesting
## failure mode does not need a GPU. What a ghost WEARS and how far it
## sits off the ground are resolvable headless; only the pixels are not,
## and those are `just test-client`'s and the owner's playtest.


func test_an_authored_mesh_sits_on_its_base_and_a_primitive_is_centred() -> void:
	# THE rule that was wrong in three places at once — hardcoded 1.5 in
	# both ghost paths (half the DEFAULT box, so every wall-family segment
	# previewed floating) and written out longhand in the building path.
	assert_eq(UnitMesh.ground_lift(3.6, true), 0.0,
		"an authored model is built with its origin at its base")
	assert_eq(UnitMesh.ground_lift(3.0, false), 1.5,
		"a primitive is centred on its own origin, so it rises by half")
	assert_eq(UnitMesh.ground_lift(1.95, false), 0.975,
		"...by half of ITS OWN height — the wall-family case the "
		+ "hardcoded 1.5 got wrong")


func test_the_ghost_material_ignores_the_owner_colour_mask() -> void:
	# COLOR_0's alpha is the owner-colour MASK (D-052), not transparency.
	# A StandardMaterial3D with vertex_color_use_as_albedo multiplies it
	# into ALBEDO.a, so a ghost built that way is transparent exactly
	# where the building shows least owner colour — walls gone, roof
	# hanging in the air, nothing failing. The shader is the fix, so the
	# guard is that the material IS the shader.
	var material := UnitMesh.ghost_material_for(Color(0.4, 0.95, 0.5, 1.0))
	assert_true(material is ShaderMaterial,
		"a ghost must not be a StandardMaterial3D — see the shader header")
	assert_eq(material.shader.resource_path, UnitMesh.GHOST_SHADER)

	var source := FileAccess.get_file_as_string(UnitMesh.GHOST_SHADER)
	var code := ""
	for line in source.split("\n"):
		code += line.get_slice("//", 0) + "\n"
	assert_true(code.contains("surface = COLOR.rgb"),
		"the ghost shader must take rgb only — COLOR.a is the owner mask")
	assert_false(code.contains("ALPHA = surface"),
		"vertex alpha must never become transparency")
	assert_true(code.contains("ALPHA = opacity"),
		"one opacity for the whole model, from the preview rather than "
		+ "from whichever part of the mesh a fragment lands on")


func test_the_shipped_buildings_resolve_a_ghost_mesh() -> void:
	# The data half: a preview can only show the real building if the
	# model actually loads. Not asserted per def — a def with an empty
	# `model_id` correctly falls back to the box (D-064) — but at least
	# the ones that name a model must resolve, or the feature is silently
	# the old box everywhere.
	var resolved := 0
	for def in BuildingSim.all_defs():
		if def.model_id == &"":
			continue
		assert_not_null(UnitMesh.mesh_for(def.model_id),
			"%s names model '%s' and it does not load" % [def.id, def.model_id])
		resolved += 1
	assert_gt(resolved, 0,
		"no building named a model, so this test proves nothing")


func test_a_civs_own_body_is_what_its_ghost_wears() -> void:
	# The preview resolves through `BuildingDef.model_for` against the
	# viewing player's civ, so an emberdeep player previewing a town
	# centre sees the dwarf hall they will get
	# (D-20260830-a-building-wears-a-civs-own-body). Same call the real
	# building path makes — a preview with its own idea of which model to
	# draw is a preview that eventually lies.
	var hall := BuildingSim.def_by_id(&"town_centre")
	assert_not_null(UnitMesh.mesh_for(hall.model_for(&"emberdeep")),
		"emberdeep's hall model must load for its ghost")
	assert_not_null(UnitMesh.mesh_for(hall.model_for(&"stoneblood")),
		"and so must the neutral one every other civ previews")
	assert_ne(hall.model_for(&"emberdeep"), hall.model_for(&"stoneblood"),
		"setup: the two civs genuinely preview different bodies")


func test_the_client_draws_previews_through_the_shared_resolver() -> void:
	# The caller scans (D-106). Everything above can hold while client.gd
	# still builds a bare BoxMesh in either ghost path, and then the
	# feature is absent with every other test green. Comments stripped —
	# a commented-out call still contains the string, which is how the
	# founding-crew scan was fooled a day earlier.
	var source := FileAccess.get_file_as_string("res://client.gd")
	var code := ""
	for line in source.split("\n"):
		code += line.get_slice("#", 0) + "\n"

	assert_true(code.contains("func _ghost_visual_for("),
		"client.gd must resolve a preview's mesh in one place")
	assert_true(code.contains("_ghost_visual_for(def, size)"),
		"...and both ghost paths must call it")
	assert_eq(code.count("_ghost_visual_for(def, size)"), 2,
		"the single ghost AND the drag line, or one of them still boxes")
	assert_true(code.contains("_place_ghost(_placement_ghost"),
		"the single ghost must go through the shared placer")
	assert_true(code.contains("UnitMesh.ground_lift("),
		"and the real building path must read the same lift rule")
	assert_false(code.contains("Vector3(0.0, 1.5, 0.0)"),
		"the hardcoded 1.5 lift must be gone from every preview path")
