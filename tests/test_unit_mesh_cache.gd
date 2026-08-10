extends GutTest

## Guards the caching in `UnitMesh` (D-064), and it exists because this project
## has now made the same mistake four times.
##
## `UnitRoster.by_id` re-scanned `/units` from disk on every call while
## `SquadSim.tick` called it once per squad a building finished; twenty
## simultaneous completions spent 858 ms in a filesystem walk (M4).
## `TorusSpace.distance()` per candidate cell did it in vision (M2), terrain
## noise did it per soldier per frame (M5), and a per-squad building scan did it
## again (M6). CLAUDE.md's standing rule came out of that run of four.
##
## Loading a `.glb` is worse than any of them: it instantiates a whole scene.
## The client builds a node per squad, so a naive `mesh_for` would pay that per
## squad — and, exactly like the M4 defect, no benchmark would ever see it,
## because a benchmark resolves its assets once at setup.
##
## `UnitMesh.load_count` exists to make the check possible at all. Counting is
## the only way to assert an absence of work; timing it would be flaky and would
## not say WHY.


func before_each() -> void:
	UnitMesh.reload()


func after_all() -> void:
	UnitMesh.reload()


func _first_model() -> StringName:
	for def in UnitRoster.load_all():
		if def.model_id != &"" and UnitMesh.has_model(def.model_id):
			return def.model_id
	return &""


func test_a_model_is_pulled_off_disk_once_however_many_squads_want_it() -> void:
	var model_id := _first_model()
	if model_id == &"":
		pass_test("generated/ not built; nothing to cache")
		return

	assert_eq(UnitMesh.load_count, 0, "cache should start cold")
	var first := UnitMesh.mesh_for(model_id)
	assert_not_null(first)
	assert_eq(UnitMesh.load_count, 1, "the first ask loads it")

	for i in range(200):
		UnitMesh.mesh_for(model_id)
	assert_eq(UnitMesh.load_count, 1,
		"200 squads of the same type loaded the model %d times. This is the "
			% UnitMesh.load_count
		+ "M4 `UnitRoster.by_id` defect again, with a scene instantiation "
		+ "instead of a directory walk.")


func test_repeated_lookups_return_the_very_same_resource() -> void:
	var model_id := _first_model()
	if model_id == &"":
		pass_test("generated/ not built")
		return
	var first := UnitMesh.mesh_for(model_id)
	var second := UnitMesh.mesh_for(model_id)
	assert_true(first == second,
		"each squad holding its own copy of the mesh would multiply memory by "
		+ "the squad count at D-018's ~1,000 squads")


## A model that does not exist must be remembered as absent, or every squad of
## a unit whose art failed to build pays a failed load every time it is asked
## for — the same cost the cache exists to remove, on the unhappiest path.
func test_a_missing_model_is_not_retried_forever() -> void:
	var before := UnitMesh.load_count
	for i in range(50):
		assert_null(UnitMesh.mesh_for(&"no_such_model_exists"))
	assert_eq(UnitMesh.load_count, before,
		"a missing model should be cached as missing, not re-attempted")


func test_a_missing_model_degrades_to_the_primitive_rather_than_failing() -> void:
	var def := UnitDef.new()
	def.squad_size = 6
	def.model_id = &"no_such_model_exists"
	def.mesh_primitive = "capsule"

	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def, Color.RED)

	# The whole point of the empty default (D-064): a clone with no generated/
	# still plays. One child, a mesh, and the right instance count — the same
	# structural contract D-009's test asserts.
	assert_eq(unit.get_child_count(), 1)
	var child := unit.get_child(0) as MultiMeshInstance3D
	assert_not_null(child)
	assert_not_null(child.multimesh.mesh,
		"a squad whose art is missing must still draw something")
	assert_eq(child.multimesh.instance_count, def.squad_size)


func test_an_authored_squad_carries_per_soldier_animation_data() -> void:
	var model_id := _first_model()
	if model_id == &"":
		pass_test("generated/ not built")
		return

	var def := UnitDef.new()
	def.squad_size = 8
	def.model_id = model_id

	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def, Color.BLUE)

	var child := unit.get_child(0) as MultiMeshInstance3D
	assert_true(child.multimesh.use_custom_data,
		"D-065 carries clip, phase and rate in MultiMesh custom data; without "
		+ "it every soldier animates identically and in lockstep")

	# What is written cannot be read back here: under --headless Godot uses a
	# dummy rendering server and MultiMesh per-instance buffers do not survive
	# it — `get_instance_custom_data` and even `get_instance_transform` return
	# zeros. So the WRITES are counted instead, which is the more useful
	# property anyway (see below).
	assert_eq(unit.custom_data_writes, 0, "nothing written before it is asked for")
	unit.set_clip_data(3, AnimationState.CLIP_WALK, 4.0)
	assert_eq(unit.custom_data_writes, 1, "the first clip must be written")

	# The values themselves are a pure function, covered by
	# tests/test_animation_state.gd, so nothing is lost by not reading them back.
	var a := AnimationState.custom_data(3, 0, AnimationState.CLIP_WALK, 4.0)
	var b := AnimationState.custom_data(3, 1, AnimationState.CLIP_WALK, 4.0)
	assert_eq(int(a.r), AnimationState.CLIP_WALK)
	assert_ne(a.g, b.g,
		"two soldiers in one squad must not share a phase offset")


## The cost claim D-045 cares about: a squad walking at a steady speed rewrites
## nothing. The client calls this every frame for every visible squad, in the
## loop that was measured at 97% of the frame.
func test_a_squad_at_a_steady_pace_rewrites_nothing() -> void:
	var model_id := _first_model()
	if model_id == &"":
		pass_test("generated/ not built")
		return

	var def := UnitDef.new()
	def.squad_size = 12
	def.model_id = model_id

	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def, Color.BLUE)

	unit.set_clip_data(1, AnimationState.CLIP_WALK, 4.0)
	assert_eq(unit.custom_data_writes, 1)

	for frame in range(120):
		unit.set_clip_data(1, AnimationState.CLIP_WALK, 4.0)
	assert_eq(unit.custom_data_writes, 1,
		"120 frames at an unchanged pace rewrote the buffer %d times; phase "
			% unit.custom_data_writes
		+ "advances in the shader from TIME, so the CPU should do nothing here")

	# A real change must still get through.
	unit.set_clip_data(1, AnimationState.CLIP_ROUT, 4.0)
	assert_eq(unit.custom_data_writes, 2, "a clip change must be written")

	unit.set_clip_data(1, AnimationState.CLIP_ROUT, 12.0)
	assert_eq(unit.custom_data_writes, 3,
		"a squad breaking into a run must have its playback rate updated")


## Still exactly one child, whichever path a squad renders on. D-009's own test
## covers the primitive; this covers the authored one, because the authored
## path was the plausible place to add a second node for a weapon or an LOD.
func test_an_authored_squad_is_still_one_multimesh() -> void:
	var model_id := _first_model()
	if model_id == &"":
		pass_test("generated/ not built")
		return

	var def := UnitDef.new()
	def.squad_size = 5
	def.model_id = model_id

	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def, Color.GREEN)
	assert_eq(unit.get_child_count(), 1,
		"one MultiMesh per squad (D-009), authored models included")


func test_toggling_ghost_keeps_the_node_layout() -> void:
	var model_id := _first_model()
	if model_id == &"":
		pass_test("generated/ not built")
		return

	var def := UnitDef.new()
	def.squad_size = 4
	def.model_id = model_id

	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def, Color.GREEN)
	var lit := (unit.get_child(0) as MultiMeshInstance3D).material_override

	unit.set_ghost(true)
	var ghosted := (unit.get_child(0) as MultiMeshInstance3D).material_override
	assert_eq(unit.get_child_count(), 1)
	assert_true(lit != ghosted,
		"the ghost variant is a different shader program, because whether a "
		+ "material is transparent is fixed at shader compile time (D-025)")

	unit.set_ghost(false)
	assert_eq(unit.get_child_count(), 1)
