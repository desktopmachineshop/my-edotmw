extends GutTest

## Guards D-059 — client-side easing and activity motion, and the D-006
## boundary they live on.
##
## D-006 clause 1 forbids per-soldier integration state in the SIMULATION;
## clause 2 permits client-side visual offsets that are never read back.
## `SoldierMotion` holds per-soldier state, so the tests that matter most
## here are the ones proving it stays on the render side of that line.


func _slots(count: int, at: Vector3) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in range(count):
		out.append(Transform3D(Basis.IDENTITY, at + Vector3(float(i), 0.0, 0.0)))
	return out


func test_soldiers_ease_toward_their_slot_rather_than_snapping() -> void:
	# THE point: a squad's slots all rotate in the same instant when it
	# turns, so the block snaps round. Nothing is wrong with the
	# simulation — that is the authoritative answer — but no army moves
	# like that.
	var motion := SoldierMotion.new()
	motion.ease(1, _slots(4, Vector3.ZERO), 0.016)

	# Now the formation jumps a short distance, as a turn would move it.
	var moved := _slots(4, Vector3(0.0, 0.0, 2.0))
	var first := motion.ease(1, moved, 0.016)

	for i in range(first.size()):
		var gap := first[i].origin.distance_to(moved[i].origin)
		assert_gt(gap, 0.01, "soldier %d snapped straight to its new slot" % i)
		assert_lt(gap, 2.1, "soldier %d did not move toward its slot at all" % i)


func test_easing_converges_rather_than_lagging_forever() -> void:
	# The other side: a soldier that never arrives would trail his own
	# formation permanently, which is worse than snapping.
	var motion := SoldierMotion.new()
	motion.ease(1, _slots(3, Vector3.ZERO), 0.016)
	var target := _slots(3, Vector3(0.0, 0.0, 2.0))

	var result: Array[Transform3D] = []
	for _i in range(120):
		result = motion.ease(1, target, 0.016)

	for i in range(result.size()):
		assert_lt(result[i].origin.distance_to(target[i].origin), 0.02,
			"soldier %d never caught up with its slot" % i)


func test_a_seam_sized_jump_snaps_instead_of_flying_across_the_map() -> void:
	# A wrapped squad legitimately jumps a whole map width in one frame
	# (D-035). Easing that would send soldiers streaming across the world.
	var motion := SoldierMotion.new()
	motion.ease(1, _slots(3, Vector3.ZERO), 0.016)
	var wrapped := _slots(3, Vector3(200.0, 0.0, 0.0))
	var result := motion.ease(1, wrapped, 0.016)

	for i in range(result.size()):
		assert_almost_eq(result[i].origin.x, wrapped[i].origin.x, 0.001,
			"soldier %d is easing across the seam instead of snapping" % i)


func test_easing_never_mutates_the_authoritative_transforms() -> void:
	# The D-006 boundary. Whatever this does on the render path, the
	# derived value that selection, combat and the composition hash read
	# must come back untouched.
	var motion := SoldierMotion.new()
	var authoritative := _slots(5, Vector3(3.0, 0.0, 4.0))
	var before := []
	for t in authoritative:
		before.append(t.origin)

	motion.ease(1, authoritative, 0.016)
	motion.ease(1, _slots(5, Vector3(9.0, 0.0, 9.0)), 0.016)

	for i in range(authoritative.size()):
		assert_eq(authoritative[i].origin, before[i],
			"the authoritative transform for soldier %d was modified" % i)


func test_forgetting_a_squad_releases_its_state() -> void:
	# Per-soldier state that is never released is a leak for the length of
	# a match, at 40,000 soldiers.
	var motion := SoldierMotion.new()
	motion.ease(7, _slots(4, Vector3.ZERO), 0.016)
	assert_eq(motion.tracked_count(), 1)
	motion.forget(7)
	assert_eq(motion.tracked_count(), 0, "eased state outlived the squad")


# --- activity motion ---------------------------------------------------

func test_an_idle_squad_gets_no_swing() -> void:
	var slots := _slots(6, Vector3.ZERO)
	var idle := CosmeticOffset.decorate_activity(
		slots, 1.0, 0.0, CosmeticOffset.Activity.IDLE, Vector3(5.0, 0.0, 0.0))
	var plain := CosmeticOffset.decorate_all(slots, 1.0, 0.0)
	for i in range(idle.size()):
		assert_almost_eq(idle[i].origin.distance_to(plain[i].origin), 0.0, 0.0001,
			"an idle soldier is swinging at nothing")


func test_working_and_fighting_move_soldiers_toward_what_they_are_doing() -> void:
	# The complaint: units stand perfectly still while a resource drains
	# or an enemy dies, so nothing looks like it is interacting.
	#
	# Sampled across time because the swing is a cycle through zero — one
	# instant proves nothing, and a test that happened to sample the zero
	# crossing would fail for a working feature.
	for activity in [CosmeticOffset.Activity.WORKING, CosmeticOffset.Activity.FIGHTING]:
		var slots := _slots(6, Vector3.ZERO)
		var largest := 0.0
		for step in range(40):
			var t := float(step) * 0.05
			var moved := CosmeticOffset.decorate_activity(
				slots, t, 0.0, activity, Vector3(0.0, 0.0, 6.0))
			var plain := CosmeticOffset.decorate_all(slots, t, 0.0)
			for i in range(moved.size()):
				largest = maxf(largest, moved[i].origin.distance_to(plain[i].origin))
		assert_gt(largest, 0.05,
			"activity %d never displaced a soldier — the squad stands still while it works" % activity)
