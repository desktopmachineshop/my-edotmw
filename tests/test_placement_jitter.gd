extends GutTest

## Guards the cosmetic building/resource-node placement variation added to
## stop freestanding structures and nodes from all sitting dead-centre on
## their hex cell facing one of exactly 6 directions.
##
## `PlacementJitter` is pure and stateless by construction (same reason as
## `render_cull.gd`/`selection_pick.gd`) so it's testable without a GPU or a
## running client. What actually matters here is determinism (two clients
## must draw the same building at the same spot without anything on the
## wire) and boundedness (a jittered object must still read as standing on
## its own cell, not a neighbour's).


func test_position_offset_is_deterministic() -> void:
	var a := PlacementJitter.position_offset(42, 0.3)
	var b := PlacementJitter.position_offset(42, 0.3)
	assert_eq(a, b, "The same id must jitter identically on every client — nothing is on the wire")


func test_yaw_is_deterministic() -> void:
	assert_eq(PlacementJitter.yaw(7), PlacementJitter.yaw(7),
		"The same id must face the same cosmetic direction on every client")


func test_position_offset_stays_within_max_radius() -> void:
	for id in range(200):
		var offset: Vector3 = PlacementJitter.position_offset(id, 0.3)
		assert_eq(offset.y, 0.0, "Placement jitter is horizontal only")
		assert_true(Vector2(offset.x, offset.z).length() <= 0.3 + 0.0001,
			"id %d jittered outside its max_radius" % id)


func test_zero_radius_offset_is_zero() -> void:
	assert_eq(PlacementJitter.position_offset(123, 0.0), Vector3.ZERO,
		"A caller passing 0 (a wall segment/access tower, deliberately excluded) must get no jitter")


func test_yaw_stays_in_range() -> void:
	for id in range(200):
		var angle: float = PlacementJitter.yaw(id)
		assert_true(angle >= 0.0 and angle < TAU, "yaw(%d) = %f out of [0, TAU)" % [id, angle])


func test_different_ids_spread_out_rather_than_coincide() -> void:
	# Not a claim of true randomness — just that neighbouring wire ids
	# (buildings and resource nodes both mint sequential/small ids) don't
	# all land on the same offset or facing, which would look identical to
	# the grid-locked placement this replaced.
	var seen_offsets := {}
	var seen_yaws := {}
	for id in range(50):
		seen_offsets[PlacementJitter.position_offset(id, 0.3)] = true
		seen_yaws[PlacementJitter.yaw(id)] = true
	assert_gt(seen_offsets.size(), 40, "Offsets across 50 ids collapsed onto too few distinct values")
	assert_gt(seen_yaws.size(), 40, "Yaws across 50 ids collapsed onto too few distinct values")


# --- yaw_byte / radians_of_byte (the replicated-facing half) -----------

func test_yaw_byte_is_deterministic_and_in_range() -> void:
	for id in range(200):
		var byte: int = PlacementJitter.yaw_byte(id)
		assert_eq(byte, PlacementJitter.yaw_byte(id), "yaw_byte(%d) must be stable" % id)
		assert_true(byte >= 0 and byte <= 255, "yaw_byte(%d) = %d out of [0, 255]" % [id, byte])


func test_radians_of_byte_covers_a_full_turn() -> void:
	assert_almost_eq(PlacementJitter.radians_of_byte(0), 0.0, 0.001)
	assert_almost_eq(PlacementJitter.radians_of_byte(128), PI, 0.02)
	# 256 wraps back to the same angle as 0 — a byte is mod 256 by
	# construction, and a wire value can arrive as any int (see
	# BuildingSim.add_building's own posmod), not just 0-255.
	assert_almost_eq(PlacementJitter.radians_of_byte(256), PlacementJitter.radians_of_byte(0), 0.001)
	assert_almost_eq(PlacementJitter.radians_of_byte(-1), PlacementJitter.radians_of_byte(255), 0.001)


func test_yaw_byte_and_radians_of_byte_stay_in_step_with_each_other() -> void:
	# Not the same VALUE as yaw() (that one is quantised, this isn't), but
	# close enough that a byte round-trips to roughly the angle yaw() would
	# have offered — the two must never point in visibly different
	# directions for the same id, since one is the ghost's fallback default
	# and the other is what a resource node (never replicated) still uses.
	for id in [0, 1, 42, 999]:
		var from_byte: float = PlacementJitter.radians_of_byte(PlacementJitter.yaw_byte(id))
		var direct: float = PlacementJitter.yaw(id)
		var diff := absf(wrapf(from_byte - direct, -PI, PI))
		assert_lt(diff, 0.05, "id %d: byte round-trip (%f) drifted from yaw() (%f)" % [id, from_byte, direct])
