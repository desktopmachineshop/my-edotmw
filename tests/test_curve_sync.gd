extends GutTest

## The netcode proof (D-003), and the reason M1 exists as a milestone.
##
## D-022 criterion 3 requires all three properties be demonstrated by
## test rather than by inspection, so each has its own section below:
## zero bandwidth when idle, no intent leakage past the horizon, and
## bounded cost under an invalidation storm.

const W := 16
const H := 12


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _moving_curve(space: TorusSpace, start: Vector2i, steps: int, t0: float = 0.0) -> StateCurve:
	var c := StateCurve.new()
	for i in range(steps):
		c.append_cell(t0 + float(i), Vector2i(start.x + i, start.y), space)
	return c


func _parked_curve(space: TorusSpace, at: Vector2i) -> StateCurve:
	var c := StateCurve.new()
	c.append_cell(0.0, at, space)
	return c


# --- curve semantics --------------------------------------------------

func test_sampling_holds_before_and_after_the_curve() -> void:
	var t := _space()
	var c := _moving_curve(t, Vector2i(2, 2), 3)
	assert_eq(c.sample_cell(-5.0, t), Vector2i(2, 2), "Before the curve, hold the first value")
	assert_eq(c.sample_cell(99.0, t), Vector2i(4, 2), "After the curve, hold the last value")


func test_curve_interpolates_across_the_seam_the_short_way() -> void:
	# The bug this guards: storing world positions and lerping sends the
	# object the long way around the map when a segment straddles a seam.
	var t := _space()
	var c := StateCurve.new()
	c.append_cell(0.0, Vector2i(W - 1, 5), t)
	c.append_cell(1.0, Vector2i(0, 5), t)

	# Midway between the two cells should be *between* them across the
	# seam, i.e. within half a hex of either — not out in the middle of
	# the map.
	var mid := c.sample_axial(0.5)
	assert_almost_eq(mid.x, float(W) - 0.5, 0.0001,
		"Midpoint should sit on the seam, not lerp back across the whole map")
	assert_eq(c.sample_cell(1.0, t), Vector2i(0, 5), "Endpoint should wrap into the domain")


func test_idle_detection() -> void:
	var t := _space()
	assert_true(_parked_curve(t, Vector2i(3, 3)).is_idle(), "A single-keyframe curve is idle")
	assert_false(_moving_curve(t, Vector2i(3, 3), 4).is_idle(), "A moving curve is not idle")

	var stationary := StateCurve.new()
	stationary.append_cell(0.0, Vector2i(3, 3), t)
	stationary.append_cell(5.0, Vector2i(3, 3), t)
	assert_true(stationary.is_idle(), "Repeated identical keyframes are still idle")


func test_serialization_roundtrips() -> void:
	var t := _space()
	var c := _moving_curve(t, Vector2i(1, 1), 5)
	var restored := StateCurve.from_bytes(c.to_bytes())
	assert_eq(restored.key_count(), c.key_count())
	for i in range(10):
		var at := float(i) * 0.5
		assert_almost_eq(restored.sample_axial(at).x, c.sample_axial(at).x, 0.001)


func test_byte_size_matches_actual_encoding() -> void:
	# byte_size() is used in budgeting, so it must not drift from to_bytes().
	var t := _space()
	for steps in [1, 3, 10]:
		var c := _moving_curve(t, Vector2i(0, 0), steps)
		assert_eq(c.to_bytes().size(), c.byte_size(),
			"byte_size() disagrees with to_bytes() at %d keyframes" % steps)


# --- property 1: zero bandwidth when idle ----------------------------

func test_idle_object_costs_zero_bytes_after_first_delivery() -> void:
	var t := _space()
	var r := CurveReplicator.new()
	r.set_curve(1, _parked_curve(t, Vector2i(4, 4)))

	var first := r.collect_for_client(100, 0.0, [1])
	assert_gt(CurveReplicator.total_bytes(first), 0, "The first delivery must actually send something")

	# Tick forward repeatedly. A parked object must never cost another byte.
	for i in range(20):
		var later := r.collect_for_client(100, float(i) * 0.1, [1])
		assert_eq(CurveReplicator.total_bytes(later), 0,
			"An idle object cost bandwidth at t=%f — D-003's central claim is broken" % (float(i) * 0.1))


func test_many_idle_objects_cost_zero_bytes() -> void:
	# The claim has to hold at population scale, not just for one object.
	var t := _space()
	var r := CurveReplicator.new()
	var ids := []
	for i in range(500):
		r.set_curve(i, _parked_curve(t, Vector2i(i % W, (i / W) % H)))
		ids.append(i)

	# Drain the initial delivery over as many ticks as the budget needs.
	for tick in range(200):
		if CurveReplicator.total_bytes(r.collect_for_client(1, float(tick) * 0.1, ids)) == 0:
			break

	var settled := r.collect_for_client(1, 100.0, ids)
	assert_eq(CurveReplicator.total_bytes(settled), 0,
		"500 idle objects should cost zero bytes once delivered")


func test_changing_a_curve_makes_it_send_again() -> void:
	var t := _space()
	var r := CurveReplicator.new()
	r.set_curve(1, _parked_curve(t, Vector2i(4, 4)))
	r.collect_for_client(100, 0.0, [1])
	assert_eq(CurveReplicator.total_bytes(r.collect_for_client(100, 0.1, [1])), 0)

	r.set_curve(1, _parked_curve(t, Vector2i(9, 9)))
	assert_gt(CurveReplicator.total_bytes(r.collect_for_client(100, 0.2, [1])), 0,
		"A re-pathed object must replicate again")


# --- property 2: no intent leakage -----------------------------------

func test_clipping_drops_keyframes_beyond_the_horizon() -> void:
	var t := _space()
	# A 20-second march. The client must not learn where it ends up.
	var long_march := _moving_curve(t, Vector2i(0, 5), 20)
	var clipped := long_march.clipped(0.0, 1.0)

	assert_lte(clipped.end_time(), 1.0,
		"Clipped curve must not extend past the horizon")
	# The destination is at q=19 -> wraps to 3. It must not be recoverable.
	for i in range(clipped.key_count()):
		assert_lte(clipped.sample_axial(1.0).x, 1.5,
			"Clipped curve leaks a position beyond the horizon")


func test_client_cannot_read_future_intent_from_the_wire() -> void:
	# The strong form: decode the actual bytes a client receives and
	# confirm the enemy's future position is not recoverable from them.
	var t := _space()
	var r := CurveReplicator.new()
	r.horizon_seconds = 1.0

	var march := _moving_curve(t, Vector2i(0, 5), 20)
	r.set_curve(7, march)

	var packets := r.collect_for_client(100, 0.0, [7])
	assert_eq(packets.size(), 1)

	var decoded := CurveReplicator.decode_packet(packets[0]["bytes"])
	var received: StateCurve = decoded["curve"]

	assert_lte(received.end_time(), 1.0 + 0.0001,
		"The wire format itself must not carry keyframes past the horizon")

	# Where the squad truly is at t=10 versus what the client can infer.
	var truth := march.sample_axial(10.0)
	var inferred := received.sample_axial(10.0)
	assert_gt(absf(truth.x - inferred.x), 5.0,
		"Client inferred the enemy's position 10s ahead — intent leaked")


func test_horizon_window_advances_as_time_passes() -> void:
	# Clipping must not mean the client stops receiving updates — it
	# should receive successive windows instead of the whole future.
	var t := _space()
	var r := CurveReplicator.new()
	r.horizon_seconds = 1.0
	r.set_curve(7, _moving_curve(t, Vector2i(0, 5), 20))

	r.collect_for_client(100, 0.0, [7])
	var later := r.collect_for_client(100, 2.0, [7])
	assert_gt(CurveReplicator.total_bytes(later), 0,
		"A moving object should keep receiving successive horizon windows")


func test_invisible_objects_are_not_replicated_at_all() -> void:
	# Fog of war is curve gating (D-004), not client-side hiding.
	var t := _space()
	var r := CurveReplicator.new()
	r.set_curve(1, _moving_curve(t, Vector2i(0, 0), 5))
	r.set_curve(2, _moving_curve(t, Vector2i(8, 8), 5))

	var packets := r.collect_for_client(100, 0.0, [1])
	assert_eq(packets.size(), 1, "Only the visible object should replicate")
	assert_eq(packets[0]["id"], 1)

	for p in packets:
		assert_ne(p["id"], 2, "An unseen object must never reach the client")


func test_object_leaving_and_re_entering_vision_resends() -> void:
	var t := _space()
	var r := CurveReplicator.new()
	r.set_curve(1, _parked_curve(t, Vector2i(4, 4)))

	r.collect_for_client(100, 0.0, [1])
	assert_eq(CurveReplicator.total_bytes(r.collect_for_client(100, 0.1, [1])), 0)

	# Leaves vision entirely...
	assert_eq(r.collect_for_client(100, 0.2, []).size(), 0)
	# ...and comes back. The client's knowledge is stale, so resend.
	assert_gt(CurveReplicator.total_bytes(r.collect_for_client(100, 0.3, [1])), 0,
		"Re-entering vision must resend rather than assume the client still holds the curve")


# --- property 3: bounded cost under an invalidation storm ------------

func test_invalidation_storm_respects_the_byte_budget() -> void:
	var t := _space()
	var r := CurveReplicator.new()
	r.byte_budget_per_tick = 512

	var ids := []
	for i in range(1000):
		r.set_curve(i, _moving_curve(t, Vector2i(i % W, (i / W) % H), 6))
		ids.append(i)

	# Every squad re-paths in the same tick — D-003's named spike risk.
	var packets := r.collect_for_client(1, 0.0, ids)
	var sent := CurveReplicator.total_bytes(packets)
	assert_lte(sent, r.byte_budget_per_tick,
		"A 1000-squad invalidation storm sent %d bytes against a %d budget" % [sent, r.byte_budget_per_tick])
	assert_gt(packets.size(), 0, "The scheduler should still make progress under a storm")


func test_storm_drains_over_successive_ticks_without_starvation() -> void:
	var t := _space()
	var r := CurveReplicator.new()
	r.byte_budget_per_tick = 512

	var ids := []
	var count := 300
	for i in range(count):
		r.set_curve(i, _moving_curve(t, Vector2i(i % W, (i / W) % H), 4))
		ids.append(i)

	var delivered := {}
	var now := 0.0
	for tick in range(400):
		var packets := r.collect_for_client(1, now, ids)
		assert_lte(CurveReplicator.total_bytes(packets), r.byte_budget_per_tick,
			"Budget exceeded at tick %d" % tick)
		for p in packets:
			delivered[p["id"]] = true
		if delivered.size() == count:
			break
		now += 0.1

	assert_eq(delivered.size(), count,
		"Least-recently-sent scheduling should eventually deliver every object; got %d of %d" % [delivered.size(), count])


func test_oversized_single_curve_is_not_starved_forever() -> void:
	# A packet bigger than the entire per-tick budget must still get
	# through, or that object would be permanently invisible.
	#
	# Note how hard this is to provoke: horizon clipping already bounds a
	# packet to the keyframes inside one window, so a 50-second march
	# still serializes to a handful of keyframes. The residual risk is a
	# budget set smaller than a single minimal packet, which is what this
	# constructs. That clipping bounds packet size this effectively is
	# itself worth knowing — it means the budget protects against many
	# objects, not against one large one.
	var t := _space()
	var r := CurveReplicator.new()
	r.byte_budget_per_tick = 16

	r.set_curve(1, _moving_curve(t, Vector2i(0, 0), 50))
	var packets := r.collect_for_client(1, 0.0, [1])
	assert_gt(CurveReplicator.total_bytes(packets), r.byte_budget_per_tick,
		"This test is only meaningful if the packet really does exceed the budget")

	assert_eq(packets.size(), 1, "An oversized curve should be sent rather than deadlocked")
	assert_gt(r.budget_overruns, 0, "The overrun should be recorded, not silently ignored")


func test_scheduling_is_deterministic_for_replay() -> void:
	# Replays are the curve log (D-016), so two identical runs must
	# schedule identically or replays diverge from the match.
	var t := _space()
	var first_order := []
	var second_order := []

	for pass_index in range(2):
		var r := CurveReplicator.new()
		r.byte_budget_per_tick = 256
		var ids := []
		for i in range(50):
			r.set_curve(i, _moving_curve(t, Vector2i(i % W, 0), 4))
			ids.append(i)
		var order := []
		for tick in range(20):
			for p in r.collect_for_client(1, float(tick) * 0.1, ids):
				order.append(p["id"])
		if pass_index == 0:
			first_order = order
		else:
			second_order = order

	assert_eq(first_order, second_order,
		"Replication order must be deterministic or replays cannot reproduce a match")


# --- curve updates merge, gaps replace (D-20260824-the-client-renders-
# on-the-servers-clock, D-025) ------------------------------------------

func _curve_between(t_a: float, p_a: Vector2, t_b: float, p_b: Vector2) -> StateCurve:
	var c := StateCurve.new()
	c.append_axial(t_a, p_a)
	c.append_axial(t_b, p_b)
	return c


func test_an_overlapping_curve_update_keeps_the_past() -> void:
	# A packet REPLACING the whole curve is why the render clock had
	# nowhere safe to stand: behind the newest start it clamped (squads
	# teleporting), at the live head it ran off the end (freezes at every
	# bend). History is the fix, so history surviving an update is the
	# thing to pin.
	var old_curve := _curve_between(0.0, Vector2(0, 0), 1.0, Vector2(10, 0))
	var update := _curve_between(0.9, Vector2(9, 0), 2.0, Vector2(20, 0))
	var merged := ClientState.merge_curve(old_curve, update)
	assert_almost_eq(merged.sample_axial(0.5).x, 5.0, 0.01,
		"an overlapping update must keep the history it overlaps")
	assert_almost_eq(merged.sample_axial(2.0).x, 20.0, 0.01,
		"and carry the update's own keyframes forward")


func test_a_gapped_curve_update_replaces_outright() -> void:
	# D-025's truthful pop-in. A squad revealed after concealment arrives
	# as a fresh curve well past its ghost's last keyframe; bridging that
	# gap would interpolate the squad SPRINTING from where it was last
	# seen — synthetic catch-up, which reveal semantics forbid.
	var ghost := _curve_between(0.0, Vector2(0, 0), 1.0, Vector2(10, 0))
	var reveal := _curve_between(5.0, Vector2(40, 0), 6.0, Vector2(50, 0))
	var merged := ClientState.merge_curve(ghost, reveal)
	assert_almost_eq(merged.sample_axial(3.0).x, 40.0, 0.01,
		"a gapped update stands alone — sampling before it holds at ITS start, "
		+ "never at a bridge from the ghost")
	assert_eq(merged.key_count(), 2,
		"no keyframe from before the gap may survive")


func test_a_join_that_would_teleport_replaces_instead() -> void:
	# Curves store continuous UNWRAPPED axial points; a fresh packet can be
	# normalised into a different lattice copy than the chain this client
	# extended, and at a seam the same cell is a map period away. Merging
	# across that draws the squad sprinting a whole map in one segment.
	var old_curve := _curve_between(0.0, Vector2(0, 0), 1.0, Vector2(2, 0))
	var wrapped := _curve_between(1.1, Vector2(170, 0), 2.0, Vector2(172, 0))
	var merged := ClientState.merge_curve(old_curve, wrapped)
	assert_eq(merged.key_count(), 2,
		"a join further than any unit can walk is a lattice-frame mismatch, "
		+ "and the fresh curve stands alone")
