extends GutTest

## Guards D-20260819-tier-three-lives-on-the-render-side and D-006's
## 2026-08-19 amendment: survivors walk into vacated slots, drawn men
## jostle apart, and the amendment's three conditions hold as TESTS —
## one-way (the boundary scan), bounded (MAX_RENDER_DRIFT, enforced where
## the drift is made), outcome-blind (nothing here is reachable from
## resolution, which the scan is the structural half of).


func _t(points: Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for point in points:
		out.append(Transform3D(Basis(), point))
	return out


# --- the walk-in -------------------------------------------------------

func test_survivors_walk_to_their_nearest_slots() -> void:
	var old := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)])
	var deal := SoldierMotion.assign(old, _t([
		Vector3(9, 0, 0), Vector3(19, 0, 0)]))
	assert_eq(deal[0], 1, "the man at 10 takes the slot at 9")
	assert_eq(deal[1], 2, "the man at 20 takes the slot at 19")
	# The man at 0 is the casualty: unassigned, exactly one survivor per
	# slot.


func test_no_man_fills_two_slots() -> void:
	var old := PackedVector3Array([Vector3(0, 0, 0), Vector3(30, 0, 0)])
	var deal := SoldierMotion.assign(old, _t([
		Vector3(0.1, 0, 0), Vector3(0.2, 0, 0)]))
	assert_ne(deal[0], deal[1],
		"two slots beside one man must still be filled by two men")


func test_a_restamp_walks_rather_than_teleports() -> void:
	var motion := SoldierMotion.new()
	var line := _t([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0)])
	motion.ease(1, line, 0.1)
	# A casualty restamps to two slots far from anyone's feet. Teleporting
	# would put men AT the new slots this frame; walking puts them still
	# near where they visibly were.
	var restamped := _t([Vector3(2.5, 0, 3), Vector3(4.5, 0, 3)])
	var drawn := motion.ease(1, restamped, 0.016)
	for i in range(drawn.size()):
		var to_new := drawn[i].origin.distance_to(restamped[i].origin)
		assert_gt(to_new, 1.0,
			"one frame after a restamp a survivor is still WALKING to his "
			+ "slot, not standing on it — the vacated-slot behaviour the "
			+ "old revisit trigger named first")


# --- the jostle --------------------------------------------------------

func test_overlapping_men_push_apart_and_separated_men_stand() -> void:
	var anchors := _t([Vector3(0, 0, 0), Vector3(0.2, 0, 0), Vector3(5, 0, 0)])
	var jostled := SoldierMotion.jostle(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0.2, 0, 0), Vector3(5, 0, 0)]), anchors)
	assert_gt(jostled[0].distance_to(jostled[1]), 0.2,
		"the overlapping pair separates")
	assert_almost_eq(jostled[2].distance_to(Vector3(5, 0, 0)), 0.0, 0.001,
		"a man standing clear is not touched")


func test_the_amendments_bound_holds_where_the_drift_is_made() -> void:
	# Positions handed in ALREADY past the bound (a hostile caller, or
	# accumulated drift): the clamp must pull them back. The first
	# version piled men on one spot, and one jostle iteration could not
	# push anyone past the bound anyway — a fixture that cannot violate
	# the rule cannot see the rule removed.
	var drifted := PackedVector3Array([Vector3(3.0, 0, 0), Vector3(9, 0, 9)])
	var anchors := _t([Vector3.ZERO, Vector3(9, 0, 9)])
	var clamped := SoldierMotion.jostle(drifted, anchors)
	assert_lte(Vector2(clamped[0].x, clamped[0].z).length(),
		SoldierMotion.MAX_RENDER_DRIFT + 0.001,
		"the bound is enforced where the drift is made, not promised")
	assert_almost_eq(clamped[1].distance_to(Vector3(9, 0, 9)), 0.0, 0.001,
		"a man on his anchor is untouched")


func test_ease_actually_jostles() -> void:
	# The caller-exists half (the D-055 rule): jostle() being correct
	# says nothing if ease() never calls it. Two men whose SLOTS overlap
	# must come out of ease() separated.
	var motion := SoldierMotion.new()
	var crowded := _t([Vector3(0, 0, 0), Vector3(0.1, 0, 0)])
	var drawn := motion.ease(1, crowded, 0.1)
	assert_gt(drawn[0].origin.distance_to(drawn[1].origin), 0.15,
		"drawn men breathe apart even when their slots do not")


func test_the_duel_step_fits_inside_the_bound() -> void:
	assert_lte(Engagement.MAX_STEP, SoldierMotion.MAX_RENDER_DRIFT,
		"Tier 1's drawn step must fit inside the amendment's drift bound, "
		+ "or the two rules disagree about how far a drawn man may stray")


# --- the boundary (the amendment's condition 1, structurally) ----------

func test_nothing_simulation_side_reads_the_render_state() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	var offenders: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str.begins_with("res://tests/") \
				or path_str == "res://soldier_motion.gd":
			continue
		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		if handle.get_as_text().contains("SoldierMotion"):
			offenders.append(path_str)
		handle.close()
	for reader in offenders:
		assert_true(String(reader) == "res://client.gd"
			or String(reader) == "res://animation_state.gd"
			or String(reader) == "res://cosmetic_duel.gd"
			or String(reader) == "res://corpse_ledger.gd",
			("only the render path (and doc comments in its siblings) may "
			+ "touch SoldierMotion — %s reading it is per-soldier render "
			+ "state one call from an outcome, the amendment's own new "
			+ "revisit trigger") % reader)


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
