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
