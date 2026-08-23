extends GutTest

## Guards D-20260819-a-drag-draws-the-battle-line: the stroke splits into
## non-crossing segments, the line faces away from the troops, width is
## what fits shoulder to shoulder, and the quantisation is the one the
## facing order uses.


func _squad(id: int, at: Vector3, alive := 24, spacing := 1.0) -> Dictionary:
	return {"id": id, "at": at, "alive": alive, "spacing": spacing}


func test_squads_keep_their_order_along_the_stroke() -> void:
	# Two squads, the LEFT one listed second. The left segment must go to
	# the left squad or the two cross while forming.
	var plan := BattleLine.plan(Vector3(0, 0, 10), Vector3(20, 0, 10), [
		_squad(7, Vector3(15, 0, 0)),
		_squad(9, Vector3(2, 0, 0)),
	])
	assert_lt((plan[1]["destination"] as Vector3).x,
		(plan[0]["destination"] as Vector3).x,
		"the leftmost squad takes the leftmost segment")
	assert_eq(int(plan[0]["id"]), 7, "results stay in input order")


func test_the_line_faces_away_from_the_troops() -> void:
	# Troops south of the stroke: the line must face north (-z here means
	# larger z is south... use concrete numbers: troops at z=20, stroke at
	# z=10 — facing must point toward SMALLER z, away from the troops).
	var plan := BattleLine.plan(Vector3(0, 0, 10), Vector3(20, 0, 10), [
		_squad(1, Vector3(10, 0, 20)),
	])
	var q := int(plan[0]["facing_quantised"])
	var angle := TAU * float(q) / 4096.0
	assert_lt(cos(angle), -0.9,
		"facing (forward = +z convention) points away from where the "
		+ "troops stand, so they walk up and face onward")


func test_width_is_what_fits_shoulder_to_shoulder() -> void:
	var plan := BattleLine.plan(Vector3(0, 0, 0), Vector3(24, 0, 0), [
		_squad(1, Vector3(6, 0, 5)),
		_squad(2, Vector3(18, 0, 5)),
	])
	# 24 units of stroke, two squads: 12 each at spacing 1 -> 12 files.
	assert_eq(int(plan[0]["files"]), 12)
	assert_eq(int(plan[1]["files"]), 12)
	# And files never exceed the men available.
	var small := BattleLine.plan(Vector3(0, 0, 0), Vector3(24, 0, 0), [
		_squad(1, Vector3(6, 0, 5), 4),
	])
	assert_eq(int(small[0]["files"]), 4,
		"a 24-unit stroke on 4 men is 4 files, not a line with holes")


func test_degenerate_strokes_plan_nothing() -> void:
	assert_eq(BattleLine.plan(Vector3.ZERO, Vector3.ZERO,
		[_squad(1, Vector3.ZERO)]).size(), 0,
		"a zero-length stroke is the caller's click, not a plan")
	assert_eq(BattleLine.plan(Vector3.ZERO, Vector3(10, 0, 0), []).size(), 0)


func test_the_quantisation_is_the_facing_orders_own() -> void:
	# One definition: the same angle through BattleLine and through the
	# wire clamp must be the same integer.
	var q := BattleLine.quantise_angle(PI)
	assert_eq(q, 2048)
	assert_eq(BattleLine.quantise_angle(PI + TAU), 2048, "wrap-stable")
	assert_eq(BattleLine.quantise_angle(-PI), 2048, "sign-stable")


func test_battle_line_is_all_static() -> void:
	var handle := FileAccess.open("res://battle_line.gd", FileAccess.READ)
	assert_not_null(handle)
	var text := handle.get_as_text()
	handle.close()
	for line in text.split("\n"):
		assert_false(line.begins_with("var "),
			"BattleLine is pure client geometry — state here is untestable "
			+ "state (the D-061 lesson): '%s'" % line)
