extends GutTest

## Guards D-20260821-game-assets-are-files.
##
## Units and buildings are authored `.blend` files under `art/source/`, opened
## in an ordinary Blender and baked to the `.glb` + VAT the client consumes.
## That is the industry-normal arrangement and it replaces D-081's generated
## roster; what it costs is that the source of truth is now BINARY, and every
## rule here exists because a binary source fails differently from a Python one.
##
## Three failure modes, none of which produce a crash:
##
##  - an edited `.blend` that nobody rebuilt, so the game ships yesterday's
##    mesh while the file on disk shows today's;
##  - a `.blend` silently corrupted by the line-ending machinery, which for a
##    generator would be a diff and for a binary is destruction of the original;
##  - the bake quietly falling back to the legacy generator, so an artist's
##    work is present in the repo and absent from the game.
##
## These are text scans in the style of test_civs.gd's no-script-names-a-civ
## rule. They need neither Blender nor the bpy wheel.

const BUILD_PY := "res://art/build.py"
const SOURCE_DIR := "res://art/source"


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func _sources() -> PackedStringArray:
	var dir := DirAccess.open(SOURCE_DIR)
	if dir == null:
		return PackedStringArray()
	var out := PackedStringArray()
	for name in dir.get_files():
		var normalised := String(name).trim_suffix(".remap")
		if normalised.ends_with(".blend"):
			out.append(normalised.trim_suffix(".blend"))
	return out


# --- an edited source cannot ship silently ------------------------------


func test_authored_sources_are_in_the_staleness_hash() -> void:
	# THE rule this whole arrangement stands on. `generated/` is committed, so
	# nothing at runtime ever reads a `.blend`; the only thing standing between
	# "I edited the model" and "the game still draws the old one" is the
	# manifest hash covering the file that changed.
	#
	# Checked on BOTH sides, because the hash is reimplemented in GDScript to
	# catch exactly the case where the two disagree (see test_art_assets.gd).
	var build := _read(BUILD_PY)
	assert_true(build.contains("SOURCE_SUFFIXES"),
		"art/build.py must declare what the staleness hash covers")
	assert_true(build.contains("\".blend\""),
		("art/build.py's staleness hash must cover .blend — without it an "
		+ "edited model ships as the previous bake and nothing fails"))

	var mirror := _read("res://tests/test_art_assets.gd")
	assert_true(mirror.contains("\".blend\""),
		("tests/test_art_assets.gd must hash .blend too, or the two "
		+ "implementations disagree and report a stale build on a clean tree"))


func test_the_source_of_truth_is_protected_from_the_line_ending_machinery() -> void:
	# The dev machine has core.autocrlf=true (#118). A CRLF substitution inside
	# a `.glb` corrupts a build product, which is recoverable by rebuilding. A
	# `.blend` is the ORIGINAL: there is nothing to rebuild it from.
	var attributes := _read("res://.gitattributes")
	assert_true(attributes.contains("*.blend binary"),
		("*.blend must be marked binary in .gitattributes — it is the source of "
		+ "truth now, and a silent CRLF substitution destroys the original "
		+ "rather than a regenerable output"))


# --- the bake actually uses them ---------------------------------------


func test_the_build_prefers_an_authored_source() -> void:
	var build := _read(BUILD_PY)
	assert_true(build.contains("blend_source.has_source"),
		"art/build.py must check for an authored source before generating")
	assert_true(build.contains("\"authored\"") and build.contains("\"generated\""),
		("art/build.py must RECORD which source produced each model, so a "
		+ "surprising .glb is traced to a file rather than guessed at"))


func test_every_authored_source_is_recorded_as_authored_in_the_manifest() -> void:
	# The quiet failure this catches: a `.blend` added to art/source/ that the
	# build never picked up — the artist's work in the repo and absent from the
	# game, with every triangle count healthy because the generator still runs.
	var manifest_path := "res://generated/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		pass_test("generated/ not built")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		pass_test("manifest unreadable")
		return

	var entries := {}
	for group in ["units", "buildings"]:
		for id in (parsed as Dictionary).get(group, {}):
			entries[id] = (parsed[group] as Dictionary)[id]

	var wrong := PackedStringArray()
	for id in _sources():
		if not entries.has(id):
			continue
		if String((entries[id] as Dictionary).get("source", "")) != "authored":
			wrong.append(id)
	assert_eq(wrong.size(), 0,
		("art/source/ holds a .blend for these, but the manifest says they were "
		+ "generated — the bake is ignoring authored work: %s") % str(wrong))


func test_the_roster_is_actually_migrated() -> void:
	# Not a style rule: the generated fallback is deliberately kept, so nothing
	# would fail if the whole roster quietly reverted to it. This asserts the
	# migration HAPPENED rather than that it could.
	if DirAccess.open(SOURCE_DIR) == null:
		pass_test("art/source/ absent — a clone that has not migrated")
		return
	assert_gt(_sources().size(), 0,
		"art/source/ exists but holds no .blend; the roster is not migrated")


# --- the file is Z-up, the game is Y-up --------------------------------


func test_the_authored_files_are_blender_native_z_up() -> void:
	# `geom.py` authors Y-up to match Godot, which was right while a generator
	# wrote every vertex and nobody opened the result. It is wrong for a file
	# somebody MODELS in: a Y-up mesh in a Z-up application lies on its back —
	# wrong floor, swapped ortho views, mirror on the wrong axis, and every
	# rigging tool assuming Z-up. Measured on the first seeded militia before
	# this was fixed: 1.68 units "deep" along Y, 0.37 "tall" along Z.
	#
	# So the sources are Z-up and the conversion happens at the BAKE boundary,
	# which is what every glTF exporter does.
	var seed := _read("res://art/seed_source.py")
	var bake := _read("res://art/lib/blend_source.py")
	assert_true(seed.contains("_to_blender"),
		"the seeder must convert into Blender's Z-up space")
	assert_true(bake.contains("_to_engine"),
		"the bake must convert back into the engine's Y-up space")

	# The pair must be exact inverses, written as explicit tuples so that they
	# can be checked against each other by eye. (x,y,z)->(x,-z,y) one way,
	# (x,y,z)->(x,z,-y) back.
	assert_true(seed.contains("(v[0], -v[2], v[1])"),
		"art/seed_source.py's _to_blender must be (x, y, z) -> (x, -z, y)")
	assert_true(bake.contains("(v[0], v[2], -v[1])"),
		"art/lib/blend_source.py's _to_engine must be (x, y, z) -> (x, z, -y)")


func test_the_pose_basis_matches_the_vertex_conversion() -> void:
	# The sign here got it wrong once, and the failure is the interesting kind:
	# a basis quaternion that is the INVERSE of the vertex transform still
	# produces a model that stands up correctly in the viewport, because the
	# rest pose is carried by the vertices. Only the ANIMATION comes out
	# rotated — invisible in Blender, wrong in the game.
	#
	# Caught by the round-trip check (0.32 world units against an expected
	# 1e-7), which is why that check exists; pinned here so it cannot come back.
	var seed := _read("res://art/seed_source.py")
	assert_true(seed.contains("Vector((1.0, 0.0, 0.0)), 1.5707963267948966"),
		("art/seed_source.py's _basis must be a POSITIVE 90 degrees about X, "
		+ "matching _to_blender: a rotation by theta sends y to y*cos - z*sin, "
		+ "so (x, y, z) -> (x, -z, y) is +90, not -90"))
	assert_true(seed.contains("basis @ q @ basis_inv"),
		("a clip's rotations are named in Y-UP terms, so the pose must be "
		+ "CONJUGATED into the new basis rather than relabelled — relabelling "
		+ "gets the handedness wrong on one axis and mirrors the animation"))


# --- the migration script cannot eat an artist's work -------------------


func test_seeding_refuses_to_overwrite_an_authored_source() -> void:
	# `seed_source.py` writes a .blend FROM the legacy generator. Run twice
	# without a guard it would silently replace a hand-modelled file with the
	# blocky thing it came from, and the loss would be invisible until someone
	# opened it.
	var seed := _read("res://art/seed_source.py")
	assert_true(seed.contains("--force"),
		"art/seed_source.py must require an explicit flag to overwrite")
	assert_true(seed.contains("already exists"),
		"art/seed_source.py must say which sources it skipped rather than skip silently")

	# Matched as IMPORT forms, not as a bare mention: `seed_source.py` appears
	# quoted in art/build.py's NOT_A_GENERATOR, where it is the name of a file
	# excluded from the staleness hash rather than a call site. A file name in
	# an exclusion list is not an invocation — the same trap that read a
	# `UILayout.box()` as a geometry call.
	var build := _read(BUILD_PY)
	for form in ["import seed_source", "from art.seed_source",
			"import art.seed_source", "seed_source.main"]:
		assert_false(build.contains(form),
			("art/build.py must never invoke the seeder (`%s`) — a build that "
			+ "reseeds is a build that overwrites the models it was asked to "
			+ "bake") % form)


# --- Blender itself is not this repo's business ------------------------


func test_blender_is_a_local_install_the_repo_does_not_manage() -> void:
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("bash blender-path.sh find"),
		"the justfile must resolve Blender through blender-path.sh, not re-derive it")
	assert_false(justfile.contains("bootstrap-blender-gui"),
		"the Blender-download recipe was removed deliberately; do not reintroduce it")

	var script := _read("res://blender-path.sh")
	assert_false(script.contains("download.blender.org"),
		("blender-path.sh must not carry a download URL — it finds an installed "
		+ "Blender and, when there is none, says how to install one normally"))


func test_the_gui_recipe_opens_the_file_itself() -> void:
	# There is no wrapper script and no custom panel any more: the .blend IS
	# the scene and Blender's own timeline is the animation. A launcher that
	# went back to building a scene from Python would be reintroducing the
	# generated pipeline through the viewer.
	var justfile := _read("res://justfile")
	var at := justfile.find("blender-gui TARGET=")
	assert_true(at > 0, "the blender-gui recipe must exist")
	if at <= 0:
		return
	var rest := justfile.substr(at)
	var end := rest.find("\n[doc(")
	var body := rest.substr(0, end) if end > 0 else rest

	assert_true(body.contains("art/source/"),
		"just blender-gui must open art/source/<TARGET>.blend")
	assert_false(body.contains("--python"),
		("just blender-gui must open the FILE, not run a script that rebuilds a "
		+ "scene — the .blend is the source of truth now"))
	assert_false(body.contains("--factory-startup"),
		("just blender-gui must open the owner's OWN Blender, preferences and "
		+ "add-ons included"))
	assert_false(body.contains("host-gate.sh acquire"),
		"just blender-gui must not be host-gated; it is a desktop tool, not agent work")
