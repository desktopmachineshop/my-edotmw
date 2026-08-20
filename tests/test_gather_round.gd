extends GutTest

## Guards D-20260820-men-gather-round-what-they-strike: the perimeter
## stand-ins are even, exact and deterministic, and the one-per-point
## deal makes a squad WRAP a static target rather than pile onto the
## near arc.


func test_ring_points_are_even_exact_and_deterministic() -> void:
	var centre := Vector3(10, 0, 5)
	var ring := Engagement.ring_points(centre, 2.0, 12)
	assert_eq(ring.size(), 12)
	for i in range(12):
		assert_almost_eq(ring[i].origin.distance_to(centre), 2.0, 0.001,
			"every point sits exactly on the ring")
	var gap0 := ring[0].origin.distance_to(ring[1].origin)
	assert_gt(gap0, 0.5,
		"the points are SPREAD — collapsed-to-one-spot passes every "
		+ "equal-gaps assert vacuously, which is how the first "
		+ "perturbation of this file stayed green")
	for i in range(11):
		assert_almost_eq(ring[i].origin.distance_to(ring[i + 1].origin),
			gap0, 0.001, "even spacing — nothing jitters frame to frame")
	assert_eq(ring[3].origin, Engagement.ring_points(centre, 2.0, 12)[3].origin,
		"pure: the same ring every call")


func test_a_line_of_men_wraps_the_whole_ring() -> void:
	# A line approaching from one side, one ring point per man: the deal
	# must use EVERY point exactly once — that is the wrap, structurally,
	# where nearest-only pairing would pile everyone onto the near arc.
	var men: Array[Transform3D] = []
	for i in range(10):
		men.append(Transform3D(Basis(), Vector3(float(i) - 4.5, 0, -8)))
	var ring := Engagement.ring_points(Vector3.ZERO, 1.5, 10)
	var points := PackedVector3Array()
	points.resize(ring.size())
	for i in range(ring.size()):
		points[i] = ring[i].origin
	var deal := SoldierMotion.assign(points, men)
	var used := {}
	for i in range(deal.size()):
		used[deal[i]] = true
	assert_eq(used.size(), 10,
		"every perimeter point takes exactly one man — the far side of "
		+ "the building is besieged too")


func test_the_dealt_ring_runs_the_ordinary_duel_bounds() -> void:
	# The ring feeds the SAME engage(): a man dealt the far side cannot
	# teleport there — MAX_STEP and the rear lean still bound him.
	var man: Array[Transform3D] = [Transform3D(Basis(), Vector3(0, 0, -8))]
	var far_point: Array[Transform3D] = [Transform3D(Basis(), Vector3(0, 0, 8))]
	var engaged := CosmeticDuel.engage(man, far_point, PackedInt32Array([0]))
	assert_lte(engaged[0].origin.distance_to(Vector3(0, 0, -8)),
		Engagement.MAX_STEP + 0.001,
		"a static target grants no exemption from the drift bounds")


func test_only_men_at_their_mark_swing() -> void:
	# The owner's screenshot: crowded men far from the wall windmilling
	# at air. A man swings only within STRIKE_REACH of his dealt mark;
	# a queued man leans and waits.
	var near: Array[Transform3D] = [Transform3D(Basis(), Vector3(0, 0, 0))]
	var far: Array[Transform3D] = [Transform3D(Basis(), Vector3(0, 0, -6))]
	var mark: Array[Transform3D] = [Transform3D(Basis(), Vector3(0, 0, 1))]
	var strike_time := 1.5 / 5.5
	var swinging := CosmeticDuel.strike_decorate(near, mark,
		PackedInt32Array([0]), strike_time, 0.0)
	var waiting := CosmeticDuel.strike_decorate(far, mark,
		PackedInt32Array([0]), strike_time, 0.0)
	var plain_near := CosmeticOffset.decorate(near[0], 0, strike_time, 0.0)
	var plain_far := CosmeticOffset.decorate(far[0], 0, strike_time, 0.0)
	assert_gt(swinging[0].origin.distance_to(plain_near.origin), 0.05,
		"a man at his mark swings at it")
	assert_almost_eq(waiting[0].origin.distance_to(plain_far.origin), 0.0,
		0.001, "a man six units back waits — he does not windmill at air")


func test_rect_points_line_the_faces_of_the_box() -> void:
	# A building is a BOX (D-20260820, second amendment): every dealt
	# point sits ON the rectangle's own perimeter, spread along it, and
	# the box's yaw turns the whole deal with it.
	var half := Vector2(3.0, 1.5)
	var rect := Engagement.rect_points(Vector3(5, 0, 7), half, 0.0, 16)
	assert_eq(rect.size(), 16)
	var on_left_or_right := 0
	for point in rect:
		var local := Vector2(point.origin.x - 5.0, point.origin.z - 7.0)
		var edge := maxf(absf(local.x) / half.x, absf(local.y) / half.y)
		assert_almost_eq(edge, 1.0, 0.01,
			"a point off the perimeter is a man inside or away from the wall")
		if absf(absf(local.x) - half.x) < 0.01:
			on_left_or_right += 1
	assert_gt(on_left_or_right, 2,
		"the short faces are manned too — spread, not collapsed (the "
		+ "vacuous-collapse lesson from the ring)")

	# Yaw: a quarter turn swaps the long axis.
	var turned := Engagement.rect_points(Vector3.ZERO, half, PI / 2.0, 4)
	var spread_z := 0.0
	for point in turned:
		spread_z = maxf(spread_z, absf(point.origin.z))
	assert_almost_eq(spread_z, 3.0, 0.05,
		"the box's facing rotates the deal — a wall is lined along its "
		+ "own length, not the world axes")
