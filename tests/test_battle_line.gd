extends GutTest

## Guards D-20260819-a-drag-draws-the-battle-line: the stroke splits into
## non-crossing segments, the line faces away from the troops, width is
## what fits shoulder to shoulder, and the quantisation is the one the
## facing order uses.


func _squad(id: int, at: Vector3, alive := 24, spacing := 1.0,
		shape := "line") -> Dictionary:
	return {"id": id, "at": at, "alive": alive, "spacing": spacing,
		"shape": shape}


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


# --- D-20260823-the-drag-shows-the-line-it-will-form ---------------------

const PREVIEW_W := 64
const PREVIEW_H := 32


func _preview_space() -> TorusSpace:
	return TorusSpace.new(PREVIEW_W, PREVIEW_H, 1.0)


func test_the_preview_is_the_order_it_previews() -> void:
	# The strongest form of "the preview cannot lie": plan a line, ask for
	# the preview points, then put a squad WHERE THE ORDER WOULD PUT IT
	# and ask the renderer's own soldier_transforms where its men stand.
	# The two must agree man for man, because they are the same call.
	var space := _preview_space()
	var alive := 20
	var plan := BattleLine.plan(Vector3(10, 0, 16), Vector3(26, 0, 16),
		[_squad(1, Vector3(18, 0, 24), alive, 1.0)])
	var entry: Dictionary = plan[0]
	var points := BattleLine.formation_points(entry, "line", 1.0, alive)
	assert_eq(points.size(), alive, "one disc per living man")

	var destination: Vector3 = entry["destination"]
	var curve := StateCurve.new()
	curve.append_cell(0.0, space.world_to_cell(destination), space)
	var real := Formation.soldier_transforms(curve, 0.0, alive, "line", 1.0,
		space, Callable(), PackedByteArray(), int(entry["files"]),
		BattleLine.angle_of_quantised(int(entry["facing_quantised"])))

	var cell_centre := space.to_world(space.world_to_cell(destination))
	for i in range(alive):
		var expected: Vector3 = real[i].origin
		# The preview is anchored on the exact stroke point; the ordered
		# squad lands on that point's CELL. Compare the offsets from each
		# one's own anchor, which is what "the same formation" means.
		var got := points[i] - destination
		var want := expected - cell_centre
		assert_almost_eq(got.x, want.x, 0.001, "man %d sits where he is sent (x)" % i)
		assert_almost_eq(got.z, want.z, 0.001, "man %d sits where he is sent (z)" % i)


func test_a_long_stroke_is_thin_and_a_short_one_is_deep() -> void:
	# One gesture, three shapes — the whole of "shape is defined by the
	# right click". Depth is what is left once the frontage is set.
	var alive := 24
	var long_line := BattleLine.plan(Vector3(0, 0, 0), Vector3(24, 0, 0),
		[_squad(1, Vector3(12, 0, 9), alive, 1.0)])
	var short_line := BattleLine.plan(Vector3(0, 0, 0), Vector3(5, 0, 0),
		[_squad(1, Vector3(2, 0, 9), alive, 1.0)])
	var long_files := int(long_line[0]["files"])
	var short_files := int(short_line[0]["files"])
	assert_gt(long_files, short_files,
		"a longer stroke is a wider, thinner line")
	assert_lte(ceili(float(alive) / float(long_files)), 2,
		"24 men over a 24-unit stroke are at most two ranks deep")
	assert_gte(ceili(float(alive) / float(short_files)), 4,
		"the same 24 men over a 5-unit stroke form a deep block")


func test_tightness_packs_more_men_into_the_same_stroke() -> void:
	# Tightness is CLOSENESS, never shape: the stroke is identical, so the
	# frontage is identical, and the tight formation simply fits more men
	# along it. Before this, `plan` used the unit's raw spacing and a tight
	# squad was dealt a loose squad's files — it packed short of its own
	# stroke and left a gap at each end.
	var loose := BattleLine.plan(Vector3(0, 0, 0), Vector3(20, 0, 0),
		[_squad(1, Vector3(10, 0, 9), 40, 1.0, "line")])
	var tight := BattleLine.plan(Vector3(0, 0, 0), Vector3(20, 0, 0),
		[_squad(1, Vector3(10, 0, 9), 40, 1.0, "tight")])
	assert_gt(int(tight[0]["files"]), int(loose[0]["files"]),
		"tighter men fit more per metre of the same frontage")
	assert_eq((tight[0]["destination"] as Vector3), (loose[0]["destination"] as Vector3),
		"and stand in the same place — tightness moved nobody")


func test_a_dragged_width_outranks_a_formations_own_ranks() -> void:
	# shield_wall declares ranks = 2. A player who drags a short, deep
	# block must get one: the gesture is the shape, the .tres is the
	# fighting style (D-058 stays intact, it just stops owning geometry
	# the player asked for).
	var offsets := []
	for slot in range(12):
		offsets.append(Formation.slot_offset("shield_wall", slot, 12, 1.0, 3))
	var ranks := {}
	for offset in offsets:
		ranks[snappedf((offset as Vector2).y, 0.01)] = true
	assert_gt(ranks.size(), 2,
		"an ordered width of 3 over 12 men is four ranks, not the def's two")
