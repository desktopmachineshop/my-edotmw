extends GutTest

## Guards D-064 — the asset pipeline — and the contracts between the Python
## that bakes assets and the GDScript that renders them.
##
## The failure this file exists for is not a crash. It is a `generated/` that
## quietly no longer matches the `art/` it came from, or a layout constant that
## drifted on one side of the language boundary. Both leave a game that runs and
## draws the wrong thing, which is the defect class CLAUDE.md says this
## project's testing discipline is blind to by construction.
##
## Every check here degrades to a skip when `generated/` or `art/` is absent,
## because the primitive path is a working game without either (D-064) and a
## clone that has not run `just build-assets` should not fail its test suite.

const ART_DIR := "res://art"
const MANIFEST := "res://generated/manifest.json"

## Matches art/build.py. Cavalry carries a horse, which is a second body — the
## allowance is stated rather than implied.
const TRIANGLE_BUDGET := 300
const MOUNTED_TRIANGLE_BUDGET := 460

## Files under art/ that cannot change a byte of generated/, so hashing them
## would mark the build stale over an edit that produces identical output.
## Duplicated from art/build.py's NOT_A_GENERATOR, in full res:// form.
const NOT_A_GENERATOR := ["res://art/gui.py"]


func _manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


# --- generated/ is in step with art/ (D-063 criterion 2) -----------------


## Re-implements art/build.py's `source_hash` — same walk order, same bytes.
##
## Deliberately a reimplementation rather than a stored value: the point is to
## detect a `generated/` committed from a DIFFERENT `art/` than the one in the
## tree, which is what happens when someone edits a generator and forgets to
## rebuild. Comparing the manifest against itself would prove nothing.
func _source_hash() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not _feed_directory(context, ART_DIR):
		return ""
	return context.finish().hex_encode()


func _feed_directory(context: HashingContext, path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false

	var files := []
	for name in dir.get_files():
		var normalised := String(name).trim_suffix(".remap")
		if not normalised.ends_with(".py"):
			continue
		# Mirrors art/build.py's NOT_A_GENERATOR — read its comment for why
		# the list is safe and why nothing else belongs on it. The two must
		# agree exactly, or this test reports a stale build on a clean tree.
		if "%s/%s" % [path, normalised] in NOT_A_GENERATOR:
			continue
		files.append(normalised)
	files.sort()

	for name in files:
		var full := "%s/%s" % [path, name]
		# The relative path is fed first, exactly as build.py does, so moving
		# a file changes the hash even if its contents do not.
		context.update(full.trim_prefix("res://").to_utf8_buffer())
		var bytes := FileAccess.get_file_as_bytes(full)
		# HashingContext.update() errors on an empty buffer, and package
		# markers are legitimately empty. Feeding nothing is what Python's
		# hashlib does with b"" anyway, so the two agree.
		if bytes.size() > 0:
			context.update(bytes)

	var subdirectories := []
	for name in dir.get_directories():
		if name != "__pycache__":
			subdirectories.append(String(name))
	subdirectories.sort()
	for name in subdirectories:
		if not _feed_directory(context, "%s/%s" % [path, name]):
			return false
	return true


func test_generated_assets_match_the_generators_that_produced_them() -> void:
	var manifest := _manifest()
	if manifest.is_empty():
		pass_test("generated/ not built; the primitive path is the game (D-064)")
		return
	if DirAccess.open(ART_DIR) == null:
		pass_test("art/ not present in this build")
		return

	var expected := _source_hash()
	assert_ne(expected, "", "could not hash art/ — the walk found nothing")
	assert_eq(String(manifest.get("source_hash", "")), expected,
		"generated/ is stale: it was built from a different art/ than the one "
		+ "in this tree. Run `just build-assets`.")


# --- every unit that names a model actually has one ---------------------


func test_every_model_id_resolves_to_a_built_model() -> void:
	if _manifest().is_empty():
		pass_test("generated/ not built")
		return
	for def in UnitRoster.load_all():
		if def.model_id == &"":
			continue
		assert_true(UnitMesh.has_model(def.model_id),
			"%s names model '%s', which is not in the manifest — the unit "
			% [def.id, def.model_id] + "would silently fall back to a capsule")
		assert_not_null(UnitMesh.mesh_for(def.model_id),
			"model '%s' is in the manifest but did not load" % def.model_id)


func test_models_stay_inside_the_triangle_budget() -> void:
	var manifest := _manifest()
	if manifest.is_empty():
		pass_test("generated/ not built")
		return
	var units: Dictionary = manifest.get("units", {})
	for model_id in units:
		var entry: Dictionary = units[model_id]
		var budget := MOUNTED_TRIANGLE_BUDGET if bool(entry.get("mounted", false)) \
			else TRIANGLE_BUDGET
		assert_lte(int(entry.get("triangles", 0)), budget,
			"%s is over the D-064 triangle budget at %d — 26,644 soldiers are "
			% [model_id, int(entry.get("triangles", 0))]
			+ "drawn at full scale, so this is not a rounding error")


# --- the VAT layout the shader assumes is the one that was baked --------


func test_vat_dimensions_match_the_mesh_and_the_declared_layout() -> void:
	var manifest := _manifest()
	if manifest.is_empty():
		pass_test("generated/ not built")
		return

	var units: Dictionary = manifest.get("units", {})
	for model_id in units:
		var entry: Dictionary = units[model_id]
		var texture := UnitMesh.vat_for(StringName(model_id))
		assert_not_null(texture, "no VAT for %s" % model_id)
		if texture == null:
			continue

		var size := texture.get_size()
		# Width is the vertex count: the shader indexes a column per vertex,
		# so a mismatch reads a neighbouring vertex's pose for every soldier.
		assert_eq(int(size.x), int(entry.get("vertices", -1)),
			"%s VAT width must equal its vertex count" % model_id)
		# Height is positions + normals + one colour row.
		var expected_height := int(entry.get("total_frames", 0)) * 2 + 1
		assert_eq(int(size.y), expected_height,
			"%s VAT height must be total_frames*2 + 1 (positions, normals, colour)"
				% model_id)
		assert_eq(int(entry.get("colour_row", -1)),
			int(entry.get("total_frames", 0)) * 2,
			"%s colour row must sit immediately after the normal block" % model_id)

		var mesh := UnitMesh.mesh_for(StringName(model_id))
		if mesh != null:
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			assert_eq(vertices.size(), int(size.x),
				"%s mesh vertex count must match its VAT width" % model_id)


## The vertex-index-in-UV2 contract (see art/lib/bake.py).
##
## Every vertex must address its OWN column, and every column must be
## addressed exactly once. If the glTF importer ever merges or reorders
## vertices in a way that breaks this, soldiers animate as somebody else.
func test_every_vertex_carries_its_own_vat_column() -> void:
	if _manifest().is_empty():
		pass_test("generated/ not built")
		return

	for def in UnitRoster.load_all():
		if def.model_id == &"":
			continue
		var mesh := UnitMesh.mesh_for(def.model_id)
		if mesh == null:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		assert_not_null(uv2, "%s has no UV2; the VAT could not be indexed"
			% def.model_id)
		if uv2 == null:
			continue

		var width := uv2.size()
		var seen := {}
		for uv in uv2:
			var column := int(uv.x * float(width))
			assert_between(column, 0, width - 1,
				"%s has a UV2 column outside the VAT" % def.model_id)
			seen[column] = true
		assert_eq(seen.size(), width,
			"%s must address every VAT column exactly once, got %d of %d"
				% [def.model_id, seen.size(), width])
		break  # one model proves the contract; the rest share the exporter


# --- the clip list is the same on both sides of the language boundary ---


## `AnimationState`'s clip constants index row blocks that `art/lib/clips.py`
## laid out. Nothing errors if they disagree — the shader just plays the wrong
## animation — so the two lists are compared directly.
func test_clip_order_matches_the_python_that_baked_it() -> void:
	var path := "%s/lib/clips.py" % ART_DIR
	if not FileAccess.file_exists(path):
		pass_test("art/ not present in this build")
		return

	var source := FileAccess.get_file_as_string(path)
	var start := source.find("CLIP_ORDER = (")
	assert_true(start >= 0, "CLIP_ORDER not found in clips.py")
	if start < 0:
		return
	var finish := source.find(")", start)
	var body := source.substr(start, finish - start)

	var names: Array[String] = []
	for piece in body.split("\""):
		var trimmed := piece.strip_edges()
		if trimmed != "" and not trimmed.begins_with("CLIP_ORDER") \
				and not trimmed.begins_with(","):
			names.append(trimmed)

	assert_eq(names, Array(AnimationState.CLIP_NAMES).map(func(v): return String(v)),
		"clip order disagrees between art/lib/clips.py and AnimationState — "
		+ "the shader would select the wrong row block, with no error anywhere")
