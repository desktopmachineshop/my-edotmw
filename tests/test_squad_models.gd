extends GutTest

## Guards D-20260826-a-squad-wears-more-than-one-model:
##
##  - `UnitDef.slot_models` names the models of the leading formation slots
##    (a hero squad's general, a cannon crew's gun) and `model_mix` is
##    dealt round-robin across the rest; both default empty, in which case
##    a squad is exactly the single-model squad it always was.
##  - `PrimitiveUnit` draws one MultiMesh per DISTINCT model under one
##    body composite, and routes transforms so that whatever prefix of the
##    squad is drawn (LOD thins, casualties shrink), each group's written
##    instances are a PREFIX of its buffer — `visible_instance_count`'s
##    contract.
##  - The leader (slot 0) is drawn at EVERY detail tier: the LOD sampler
##    picks `i * alive / n`, so drawn index 0 is always slot 0.
##
## Buffers cannot be read back under --headless (dummy rendering server),
## so structure and counts are asserted, per test_unit_mesh_cache.gd's
## rule.


func _def(size: int, model: StringName, leaders: Array[StringName],
		mix: Array[StringName]) -> UnitDef:
	var def := UnitDef.new()
	def.squad_size = size
	def.model_id = model
	def.slot_models = leaders
	def.model_mix = mix
	def.mesh_primitive = "capsule"
	return def


func _groups(unit: PrimitiveUnit) -> Array:
	var out := []
	for child in unit.get_child(0).get_children():
		if child is MultiMeshInstance3D:
			out.append(child)
	return out


func test_model_for_slot_deals_leaders_then_mix_then_the_base_model() -> void:
	var def := _def(8, &"tenders", [&"gun"] as Array[StringName],
		[&"a", &"b", &"c"] as Array[StringName])
	assert_eq(PrimitiveUnit.model_for_slot(def, 0), &"gun",
		"slot 0 wears the first named leader model")
	assert_eq(PrimitiveUnit.model_for_slot(def, 1), &"a")
	assert_eq(PrimitiveUnit.model_for_slot(def, 2), &"b")
	assert_eq(PrimitiveUnit.model_for_slot(def, 3), &"c")
	assert_eq(PrimitiveUnit.model_for_slot(def, 4), &"a",
		"the mix is dealt round-robin")

	var plain := _def(8, &"tenders", [] as Array[StringName],
		[] as Array[StringName])
	for i in range(8):
		assert_eq(PrimitiveUnit.model_for_slot(plain, i), &"tenders",
			"empty fields mean every slot wears model_id, as the whole "
			+ "existing roster does")


func test_a_mixed_squad_builds_one_group_per_distinct_model() -> void:
	# Model ids that do not exist, deliberately: every group falls back to
	# the primitive, which exercises the grouping without needing
	# generated/ built. Distinctness is what is under test.
	var def := _def(4, &"no_such_tender", [&"no_such_gun"] as Array[StringName],
		[] as Array[StringName])
	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def)

	assert_eq(unit.get_child_count(), 1, "one body composite per squad")
	var groups := _groups(unit)
	assert_eq(groups.size(), 2, "gun + tenders is two distinct models")
	var total := 0
	for group in groups:
		total += (group as MultiMeshInstance3D).multimesh.instance_count
	assert_eq(total, def.squad_size,
		"every slot must land in exactly one group")


func test_the_leader_is_the_last_thing_a_thinned_squad_shows() -> void:
	var def := _def(4, &"no_such_tender", [&"no_such_gun"] as Array[StringName],
		[] as Array[StringName])
	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def)

	# LOD thinned the squad to ONE drawn soldier. The sampler puts slot 0
	# first, so the gun must be the group that draws.
	unit.set_slot_transforms([Transform3D(Basis(), Vector3.ZERO)] as Array[Transform3D])
	var groups := _groups(unit)
	assert_eq((groups[0] as MultiMeshInstance3D).multimesh.visible_instance_count, 1,
		"slot 0's group — the leader — must be the one that draws")
	assert_eq((groups[1] as MultiMeshInstance3D).multimesh.visible_instance_count, 0,
		"no tender was written, so no tender may be drawn")


func test_each_group_draws_exactly_the_slots_written_this_frame() -> void:
	# 1 gun + a 2-model mix over 7 retinue slots: slots are
	# gun, a, b, a, b, a, b, a — so 5 drawn soldiers cover gun, 2 of a,
	# 2 of b.
	var def := _def(8, &"unused", [&"no_such_gun"] as Array[StringName],
		[&"no_such_a", &"no_such_b"] as Array[StringName])
	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def)

	var five: Array[Transform3D] = []
	for i in range(5):
		five.append(Transform3D(Basis(), Vector3(float(i), 0.0, 0.0)))
	unit.set_slot_transforms(five)

	var groups := _groups(unit)
	assert_eq(groups.size(), 3)
	var visible := []
	for group in groups:
		visible.append((group as MultiMeshInstance3D).multimesh.visible_instance_count)
	assert_eq(visible, [1, 2, 2],
		"5 drawn slots of gun,a,b,a,b must light 1/2/2 instances — a group "
		+ "drawing more would show soldiers at stale transforms, which is "
		+ "the invisible-casualties defect with extra steps")

	# Casualties: fewer transforms next frame must SHRINK the groups.
	unit.set_slot_transforms([Transform3D(Basis(), Vector3.ZERO)] as Array[Transform3D])
	visible = []
	for group in groups:
		visible.append((group as MultiMeshInstance3D).multimesh.visible_instance_count)
	assert_eq(visible, [1, 0, 0], "a shrunk squad must hide the lost slots")


func test_a_single_model_squad_is_unchanged_by_the_feature() -> void:
	var def := _def(6, &"no_such_model", [] as Array[StringName],
		[] as Array[StringName])
	var unit := PrimitiveUnit.new()
	add_child_autofree(unit)
	unit.rebuild(def)
	var groups := _groups(unit)
	assert_eq(groups.size(), 1,
		"a squad with empty slot_models/model_mix is one group, exactly as "
		+ "before the schema change")
	assert_eq((groups[0] as MultiMeshInstance3D).multimesh.instance_count, 6)


func test_the_shipped_thane_and_bombard_defs_are_mixed_squads() -> void:
	# The two units the feature exists for
	# (D-20260826-the-dwarf-roster-wears-supplied-models). Asserted from
	# the shipped .tres so a refactor that drops the fields fails here
	# rather than in a playtest. Emberdeep is the civ the supplied dwarf
	# models belong to; the other civs' generals stay primitives until
	# their own bodies arrive.
	var thane := UnitRoster.by_id(&"emberdeep_general")
	assert_not_null(thane, "the Deep Thane should ship")
	if thane != null:
		assert_eq(thane.slot_models, [&"general"] as Array[StringName],
			"the Deep Thane's slot 0 is the thane model")
		assert_false(thane.model_mix.is_empty(),
			"the Thane's retinue should carry mixed kit — 'one general, a "
			+ "few other dwarfs with mixed weapons' is the owner's spec")

	var bombard := UnitRoster.by_id(&"emberdeep_bombard")
	assert_not_null(bombard, "the Ember Bombard should ship")
	if bombard != null:
		assert_eq(bombard.squad_size, 4, "1 cannon + 3 tenders")
		assert_eq(bombard.slot_models, [&"cannon"] as Array[StringName])
		assert_eq(bombard.model_id, &"archers",
			"the tenders are the crossbow people — the owner's spec")
