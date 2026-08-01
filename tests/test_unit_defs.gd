extends GutTest

## Guards the two decisions most likely to be violated silently later:
##
##  - D-010: units are data (`/units/*.tres` against the UnitDef schema),
##    not hardcoded script subclasses. If a .tres stops parsing or drifts
##    from the schema, that breaks the "editable by Claude Code without
##    the Godot GUI" premise the whole project rests on — so every .tres
##    in /units/ is loaded and schema-checked here, not just a sample.
##  - D-009: a squad renders as ONE MultiMesh, never one Node per
##    soldier. Asserted structurally (child count) rather than by
##    profiling, so a well-meaning refactor to per-soldier nodes fails
##    the suite instead of quietly costing 40,000 nodes at full scale.

const UNITS_DIR := "res://units"

const VALID_FORMATIONS := ["line", "column", "wedge", "loose"]
const VALID_PRIMITIVES := ["capsule", "box", "cylinder", "hull"]


func _unit_def_paths() -> Array:
	var paths := []
	var dir := DirAccess.open(UNITS_DIR)
	assert_not_null(dir, "Expected %s to exist and be readable" % UNITS_DIR)
	if dir == null:
		return paths
	for file_name in dir.get_files():
		# Godot reports imported resources with a .remap suffix in some
		# contexts; normalise so this works headless and exported alike.
		var normalised := file_name.trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			paths.append("%s/%s" % [UNITS_DIR, normalised])
	return paths


func test_units_dir_is_not_empty() -> void:
	var paths := _unit_def_paths()
	assert_gt(paths.size(), 0, "No .tres unit definitions found in %s" % UNITS_DIR)


func test_every_unit_def_loads_and_matches_schema() -> void:
	for path in _unit_def_paths():
		var res = load(path)
		assert_not_null(res, "Failed to load %s" % path)
		if res == null:
			continue

		assert_is(res, UnitDef, "%s did not load as a UnitDef" % path)
		if not (res is UnitDef):
			continue

		var def: UnitDef = res
		assert_ne(String(def.id), "", "%s has an empty id" % path)
		assert_gt(def.squad_size, 0, "%s has a non-positive squad_size" % path)
		assert_gt(def.health, 0.0, "%s has non-positive health" % path)
		assert_has(VALID_FORMATIONS, def.formation_shape,
			"%s has formation_shape '%s' outside the UnitDef enum" % [path, def.formation_shape])
		assert_has(VALID_PRIMITIVES, def.mesh_primitive,
			"%s has mesh_primitive '%s' outside the UnitDef enum" % [path, def.mesh_primitive])
		# A squad that starts already below its own rout threshold would
		# rout on spawn once D-019's morale system lands in M2.
		assert_lt(def.rout_threshold, def.morale,
			"%s has rout_threshold >= morale, so it would rout on spawn" % path)


func test_unit_def_ids_are_unique() -> void:
	var seen := {}
	for path in _unit_def_paths():
		var def = load(path)
		if def is UnitDef:
			var key := String(def.id)
			assert_false(seen.has(key),
				"Duplicate UnitDef id '%s' in %s (also in %s)" % [key, path, seen.get(key, "")])
			seen[key] = path


func test_squad_renders_as_one_multimesh_not_one_node_per_soldier() -> void:
	var def := load("res://units/militia.tres") as UnitDef
	assert_not_null(def, "militia.tres should load as a UnitDef")
	if def == null:
		return

	var unit := PrimitiveUnit.new()
	autofree(unit)
	unit.rebuild(def)

	assert_eq(unit.get_child_count(), 1,
		"A squad should add exactly one MultiMeshInstance3D child (D-009), not one node per soldier")

	var mmi := unit.get_child(0) as MultiMeshInstance3D
	assert_not_null(mmi, "PrimitiveUnit's child should be a MultiMeshInstance3D")
	if mmi == null:
		return

	assert_not_null(mmi.multimesh, "MultiMeshInstance3D should have a MultiMesh")
	assert_eq(mmi.multimesh.instance_count, def.squad_size,
		"MultiMesh instance_count should match the UnitDef's squad_size")
	assert_not_null(mmi.multimesh.mesh, "MultiMesh should have a generated primitive mesh")


func test_rebuild_is_idempotent_and_tracks_squad_size() -> void:
	var def := load("res://units/archers.tres") as UnitDef
	var unit := PrimitiveUnit.new()
	autofree(unit)

	unit.rebuild(def)
	unit.rebuild(def)

	assert_eq(unit.get_child_count(), 1,
		"Rebuilding should reuse the existing MultiMeshInstance3D, not stack up children")
	var mmi := unit.get_child(0) as MultiMeshInstance3D
	assert_eq(mmi.multimesh.instance_count, def.squad_size)


func test_the_roster_is_cached_rather_than_rescanned_per_lookup() -> void:
	# `by_id` is called from inside SquadSim.tick, once per squad a
	# building finishes. It used to re-open /units and re-load every .tres
	# on every call, which cost 858 ms in a single live tick when twenty
	# players completed a unit at the same moment — against a 100 ms
	# budget.
	#
	# Asserted structurally rather than by timing: same array instance, so
	# no scan happened. A duration assertion would be flaky on a loaded
	# host and would not say WHY it got slow.
	var first_call := UnitRoster.load_all()
	var second_call := UnitRoster.load_all()
	assert_true(is_same(first_call, second_call),
		"load_all rebuilt the roster — /units is being re-scanned per call")

	var a := UnitRoster.by_id(first_call[0].id)
	var b := UnitRoster.by_id(first_call[0].id)
	assert_true(is_same(a, b), "by_id returned a freshly loaded UnitDef rather than the cached one")
	assert_not_null(a, "by_id should find a unit the roster just listed")


func test_reloading_the_roster_still_produces_the_same_units() -> void:
	# The cache must be droppable without changing what the roster says,
	# or the escape hatch is worse than no escape hatch.
	var before := UnitRoster.load_all().map(func(d): return d.id)
	UnitRoster.reload()
	var after := UnitRoster.load_all().map(func(d): return d.id)
	assert_eq(before, after, "Reloading the roster changed which units exist")


func test_a_squad_stops_drawing_soldiers_it_has_lost() -> void:
	# The MultiMesh is built with one instance per soldier at full
	# strength, and casualties mean fewer transforms are written. Without
	# capping `visible_instance_count`, the instances past that point keep
	# rendering at whatever transform they last held — so a squad that
	# lost half its men went on displaying them, frozen, for the rest of
	# the match.
	#
	# Nothing numeric would notice: `alive` is correct, the composition
	# hash is correct, the client and server agree. Only the picture is
	# wrong, which is the same class of defect as the frame that derived
	# every soldier at y=0 and rendered them inside the terrain.
	var def := UnitRoster.first()
	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def)

	var multimesh: MultiMesh = unit.find_children("*", "MultiMeshInstance3D", true, false)[0].multimesh
	assert_eq(multimesh.instance_count, def.squad_size,
		"The mesh should be allocated for a squad at full strength")

	var survivors: Array[Transform3D] = []
	for i in range(3):
		survivors.append(Transform3D(Basis(), Vector3(float(i), 0.0, 0.0)))
	unit.set_slot_transforms(survivors)

	assert_eq(multimesh.visible_instance_count, 3,
		"Three soldiers were given; anything else is drawing the dead")
