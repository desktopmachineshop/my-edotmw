extends GutTest

## Guards D-008: the grid wraps, and wrap-awareness is a property of the
## type rather than something each call site remembers.
##
## D-008 requires seam-crossing cases in the suite from M1 onward, so the
## seam tests below are the point of this file — the non-seam cases exist
## mainly to prove the seam cases aren't passing vacuously.
##
## The recurring bug this is written against: subtracting two coordinates
## directly instead of going through delta(), which sends a squad the long
## way around the map whenever the short path crosses a seam. Every
## directional test here asserts the SHORT answer specifically.

const W := 16
const H := 12  # even, per D-008 row parity


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


# --- domain validity -------------------------------------------------

func test_default_space_is_valid() -> void:
	var t := _space()
	assert_eq(t.validate(), "", "A %dx%d space should be valid" % [W, H])


func test_odd_height_is_rejected_for_row_parity() -> void:
	var t := TorusSpace.new(16, 11, 1.0)
	assert_false(t.is_valid(),
		"Odd height must be rejected — it misaligns the vertical seam by half a column (D-008)")
	assert_string_contains(t.validate(), "even")


func test_degenerate_dimensions_are_rejected() -> void:
	assert_false(TorusSpace.new(0, 12, 1.0).is_valid(), "Zero width should be invalid")
	assert_false(TorusSpace.new(-4, 12, 1.0).is_valid(), "Negative width should be invalid")
	# A 1-wide torus makes a cell its own neighbour across the wrap.
	assert_false(TorusSpace.new(1, 12, 1.0).is_valid(), "A 1-wide torus should be invalid")


# --- normalization / index space -------------------------------------

func test_normalize_wraps_out_of_domain_coordinates() -> void:
	var t := _space()
	assert_eq(t.normalize(Vector2i(W, 0)), Vector2i(0, 0))
	assert_eq(t.normalize(Vector2i(-1, 0)), Vector2i(W - 1, 0))
	assert_eq(t.normalize(Vector2i(0, -1)), Vector2i(0, H - 1))
	# Far out of domain, both axes, negative — posmod not fmod.
	assert_eq(t.normalize(Vector2i(-W * 3 - 2, -H * 5 - 3)), Vector2i(W - 2, H - 3))


func test_index_roundtrips_for_every_cell() -> void:
	var t := _space()
	assert_eq(t.cell_count(), W * H)
	for i in range(t.cell_count()):
		assert_eq(t.index(t.from_index(i)), i, "index/from_index should roundtrip at %d" % i)


func test_index_normalizes_rather_than_going_out_of_bounds() -> void:
	var t := _space()
	# The whole point of index space: you cannot construct an index that
	# refers to a cell outside the domain, even from a bad coordinate.
	var i := t.index(Vector2i(W + 3, H + 5))
	assert_between(i, 0, t.cell_count() - 1,
		"index() of an out-of-domain coordinate must still land inside the domain")
	assert_eq(i, t.index(Vector2i(3, 5)), "index() should agree with the wrapped coordinate")


# --- neighbours ------------------------------------------------------

func test_every_cell_has_six_distinct_neighbours_at_distance_one() -> void:
	var t := _space()
	for i in range(t.cell_count()):
		var c := t.from_index(i)
		var seen := {}
		for n in t.neighbors(c):
			assert_eq(t.distance(c, n), 1,
				"Neighbour %s of %s should be at distance 1" % [n, c])
			seen[n] = true
		assert_eq(seen.size(), 6, "Cell %s should have 6 distinct neighbours" % c)


func test_neighbor_index_agrees_with_neighbor() -> void:
	var t := _space()
	for i in range(t.cell_count()):
		for dir in range(6):
			assert_eq(t.neighbor_index(i, dir), t.index(t.neighbor(t.from_index(i), dir)),
				"neighbor_index should match neighbor at cell %d dir %d" % [i, dir])


# --- distance --------------------------------------------------------

func test_distance_to_self_is_zero() -> void:
	var t := _space()
	for i in range(t.cell_count()):
		var c := t.from_index(i)
		assert_eq(t.distance(c, c), 0)


func test_distance_is_symmetric_everywhere() -> void:
	var t := _space()
	for i in range(t.cell_count()):
		for j in range(t.cell_count()):
			var a := t.from_index(i)
			var b := t.from_index(j)
			assert_eq(t.distance(a, b), t.distance(b, a),
				"distance should be symmetric between %s and %s" % [a, b])


func test_distance_obeys_triangle_inequality_across_the_seam() -> void:
	var t := _space()
	# Sampled rather than exhaustive: full triple iteration is W*H cubed.
	var samples := [
		Vector2i(0, 0), Vector2i(W - 1, 0), Vector2i(0, H - 1),
		Vector2i(W - 1, H - 1), Vector2i(W / 2, H / 2), Vector2i(1, H - 2),
	]
	for a in samples:
		for b in samples:
			for c in samples:
				assert_lte(t.distance(a, c), t.distance(a, b) + t.distance(b, c),
					"Triangle inequality violated for %s -> %s -> %s" % [a, b, c])


# --- the seam: these are the tests D-008 actually demands --------------

func test_opposite_horizontal_edges_are_adjacent() -> void:
	var t := _space()
	var left := Vector2i(0, 4)
	var right := Vector2i(W - 1, 4)
	assert_eq(t.distance(left, right), 1,
		"Cells on opposite horizontal edges should be neighbours across the seam, not %d apart" % (W - 1))


func test_opposite_vertical_edges_are_adjacent() -> void:
	var t := _space()
	var top := Vector2i(5, 0)
	var bottom := Vector2i(5, H - 1)
	assert_eq(t.distance(top, bottom), 1,
		"Cells on opposite vertical edges should be neighbours across the seam")


func test_delta_takes_the_short_way_around_the_seam() -> void:
	var t := _space()
	# The naive (b - a) answer here is (W-1, 0) — a near-lap of the map.
	# The correct answer is a single step west.
	assert_eq(t.delta(Vector2i(0, 3), Vector2i(W - 1, 3)), Vector2i(-1, 0),
		"delta should step west across the seam, not east across the whole map")
	assert_eq(t.delta(Vector2i(2, 0), Vector2i(2, H - 1)), Vector2i(0, -1),
		"delta should step north across the seam")


func test_no_distance_exceeds_the_short_way_bound() -> void:
	var t := _space()
	# Nothing on a wrapped WxH board can be further than half the board in
	# each axis. If any pair exceeds this, delta() is missing a ghost copy.
	var bound := (W / 2) + (H / 2)
	for i in range(t.cell_count()):
		for j in range(t.cell_count()):
			var d := t.distance(t.from_index(i), t.from_index(j))
			assert_lte(d, bound,
				"distance %d between %s and %s exceeds the wrapped bound %d" % [d, t.from_index(i), t.from_index(j), bound])


func test_world_delta_is_short_across_the_seam() -> void:
	var t := _space()
	var a := Vector2i(0, 2)
	var b := Vector2i(W - 1, 2)
	var wd := t.world_delta(a, b)
	# One hex step west, not (W-1) steps east.
	assert_lt(wd.length(), 2.0 * t.hex_size,
		"world_delta across the seam should be about one hex, got %f" % wd.length())
	assert_lt(wd.x, 0.0, "Crossing the west seam should move in -x")


func test_world_delta_agrees_with_to_world_when_no_wrap_is_involved() -> void:
	var t := _space()
	# Well away from any seam, the wrapped answer and the naive difference
	# must coincide — otherwise the seam logic is corrupting the interior.
	var a := Vector2i(4, 4)
	var b := Vector2i(6, 5)
	var naive := t.to_world(b) - t.to_world(a)
	var wrapped := t.world_delta(a, b)
	assert_almost_eq(wrapped.x, naive.x, 0.0001)
	assert_almost_eq(wrapped.z, naive.z, 0.0001)


# --- the "forgot to wrap" protection ---------------------------------

func test_unnormalized_input_gives_the_same_answer_as_normalized() -> void:
	var t := _space()
	# This is the D-008 type-level guarantee: a call site that forgets to
	# wrap cannot get a different answer than one that remembers.
	var raw := Vector2i(W + 2, H + 3)
	var wrapped := Vector2i(2, 3)
	var target := Vector2i(7, 7)

	assert_eq(t.distance(raw, target), t.distance(wrapped, target))
	assert_eq(t.delta(raw, target), t.delta(wrapped, target))
	assert_eq(t.index(raw), t.index(wrapped))
	assert_eq(t.to_world(raw), t.to_world(wrapped))
	for dir in range(6):
		assert_eq(t.neighbor(raw, dir), t.neighbor(wrapped, dir))


# --- disk_offsets() — the cached table that replaced per-candidate
# distance() calls in Vision._stamp_squad and Combat._find_target -------
#
# The property under test: for any origin and any integer radius, the set
# of cell indices reached by { index(origin + offset) : offset in
# disk_offsets(radius) } must be EXACTLY { idx : distance(origin,
# from_index(idx)) <= radius }, the brute-force definition disk_offsets()
# is replacing. This is the thing D-022's standing rule cares about most:
# a faster wrong answer would silently change what's visible or
# targetable.

func _brute_force_disk(t: TorusSpace, origin: Vector2i, radius: int) -> Dictionary:
	var expected := {}
	for i in range(t.cell_count()):
		var cell := t.from_index(i)
		if t.distance(origin, cell) <= radius:
			expected[i] = true
	return expected


func _disk_via_offsets(t: TorusSpace, origin: Vector2i, radius: int) -> Dictionary:
	var actual := {}
	for offset in TorusSpace.disk_offsets(radius):
		actual[t.index(origin + offset)] = true
	return actual


func test_disk_offsets_agrees_with_brute_force_distance_at_several_radii() -> void:
	var t := _space()
	var origins := [Vector2i(0, 0), Vector2i(5, 5), Vector2i(W - 1, 0), Vector2i(0, H - 1), Vector2i(W - 1, H - 1)]
	var radii := [0, 1, 2, 3, 5]

	for origin in origins:
		for radius in radii:
			var expected := _brute_force_disk(t, origin, radius)
			var actual := _disk_via_offsets(t, origin, radius)
			assert_eq(actual.keys().size(), expected.keys().size(),
				"disk_offsets(%d) from %s: cell count should match brute force" % [radius, origin])
			for idx in expected:
				assert_true(actual.has(idx),
					"disk_offsets(%d) from %s: missing cell %s (brute-force distance %d)" %
						[radius, origin, t.from_index(idx), t.distance(origin, t.from_index(idx))])
			for idx in actual:
				assert_true(expected.has(idx),
					"disk_offsets(%d) from %s: extra cell %s not within brute-force distance" %
						[radius, origin, t.from_index(idx)])


func test_disk_offsets_agrees_with_brute_force_at_a_radius_large_relative_to_the_map() -> void:
	# W=16, H=12: half-width is 8, half-height is 6. A radius bigger than
	# BOTH exercises the "same wrapped cell reachable via more than one
	# (dq, dr) offset" case combat.gd's header calls out as harmless — the
	# whole point of this test is proving it really is harmless: the
	# deduped SET disk_offsets() produces (via index() collapsing
	# duplicate offsets to the same cell) must still exactly equal the
	# brute-force disk, not merely be a superset of it.
	var t := _space()
	var radius := 10
	assert_gt(radius, W / 2, "Setup: radius must exceed half the map width to exercise wrap doubling")
	assert_gt(radius, H / 2, "Setup: radius must exceed half the map height to exercise wrap doubling")

	for origin in [Vector2i(0, 0), Vector2i(3, 7), Vector2i(W - 1, H - 1)]:
		var expected := _brute_force_disk(t, origin, radius)
		var actual := _disk_via_offsets(t, origin, radius)
		assert_eq(actual.keys().size(), expected.keys().size(),
			"disk_offsets(%d) from %s should match brute force even with wrap doubling" % [radius, origin])
		for idx in expected:
			assert_true(actual.has(idx), "missing cell %s at radius %d from %s" % [t.from_index(idx), radius, origin])
		for idx in actual:
			assert_true(expected.has(idx), "extra cell %s at radius %d from %s" % [t.from_index(idx), radius, origin])

	# At this radius, on this map, the disk necessarily covers every cell
	# on the torus (the map is smaller than the disk) — a degenerate but
	# valid confirmation that "the whole map" is handled correctly too.
	var expected_all := _brute_force_disk(t, Vector2i(0, 0), radius)
	assert_eq(expected_all.keys().size(), t.cell_count(),
		"Setup: at this radius the brute-force disk should cover the whole %dx%d map" % [W, H])


func test_disk_offsets_radius_zero_is_just_the_origin() -> void:
	assert_eq(TorusSpace.disk_offsets(0), [Vector2i.ZERO])


func test_disk_offsets_negative_radius_is_empty() -> void:
	assert_eq(TorusSpace.disk_offsets(-1), [])
	assert_eq(TorusSpace.disk_offsets(-5), [])


func test_disk_offsets_cell_count_matches_the_hex_disk_formula() -> void:
	# A hex disk of radius r has 1 + 3*r*(r+1) cells — the standard
	# identity, independent of this file's implementation.
	for radius in range(0, 8):
		var expected_count := 1 + 3 * radius * (radius + 1)
		assert_eq(TorusSpace.disk_offsets(radius).size(), expected_count,
			"disk_offsets(%d) should have %d offsets" % [radius, expected_count])


func test_hex_length_agrees_with_distance_for_unwrapped_offsets() -> void:
	# hex_length() is the pure local-offset formula distance() reduces to
	# once delta() has picked the shortest representative. Away from any
	# seam (well inside half the map in both axes) they must agree exactly
	# — this is the property Combat._find_target's ranking shortcut
	# depends on.
	var t := _space()
	var origin := Vector2i(6, 5)
	for dq in range(-3, 4):
		for dr in range(-3, 4):
			var offset := Vector2i(dq, dr)
			if TorusSpace.hex_length(offset) > 3:
				continue
			var target := origin + offset
			assert_eq(t.distance(origin, target), TorusSpace.hex_length(offset),
				"hex_length(%s) should equal distance() away from any seam" % offset)


# --- neighbour table (#107) ------------------------------------------
#
# `neighbor_table()` is a memoisation of `neighbor_index()`, added because
# FlowField's BFS spent 93% of its time in six method calls per cell. The
# whole risk of a memoisation is that it becomes a SECOND opinion, so the
# tests below assert the two agree exhaustively rather than trusting the
# same wrapping arithmetic written twice — the "assert the value on the
# far side of the boundary" rule D-100 wrote down for asset pipelines,
# applied to a cache.

func test_neighbor_table_agrees_with_neighbor_index_for_every_cell() -> void:
	var t := _space()
	var table := t.neighbor_table()
	assert_eq(table.size(), t.cell_count() * 6,
		"The table is flat, stride 6 — one entry per cell per direction")
	for cell in range(t.cell_count()):
		for dir in range(6):
			assert_eq(table[cell * 6 + dir], t.neighbor_index(cell, dir),
				"Cell %d direction %d disagrees with neighbor_index" % [cell, dir])


func test_neighbor_table_agrees_on_an_odd_width_space() -> void:
	# W and H above are both even and both powers-of-two-ish, which is
	# exactly the shape a modulo bug hides in. An odd width makes the
	# row-wise column wrap in the builder do something a power of two
	# would forgive.
	var t := TorusSpace.new(13, 6, 1.0)
	var table := t.neighbor_table()
	for cell in range(t.cell_count()):
		for dir in range(6):
			assert_eq(table[cell * 6 + dir], t.neighbor_index(cell, dir),
				"Cell %d direction %d disagrees on a 13x6 space" % [cell, dir])


func test_neighbor_table_is_cached_and_survives_a_reshape() -> void:
	# Cached per instance, because a neighbour index depends on width and
	# height where a disk offset does not. width/height are @export, so a
	# reshape that preserves the cell count must not be allowed to keep a
	# table built for the old dimensions.
	var t := TorusSpace.new(16, 8, 1.0)
	assert_eq(t.neighbor_table(), t.neighbor_table(), "The table should be stable across calls")

	t.width = 8
	t.height = 16
	var reshaped := t.neighbor_table()
	for cell in range(t.cell_count()):
		for dir in range(6):
			assert_eq(reshaped[cell * 6 + dir], t.neighbor_index(cell, dir),
				"Cell %d direction %d kept a table built for the old shape" % [cell, dir])


func test_index_and_normalize_are_the_same_wrap() -> void:
	# `index` writes its own two `posmod`s rather than calling
	# `normalize`, because the delegation cost more than the arithmetic
	# it wrapped (0.19 us of a 0.41 us call, once per drawn man per frame
	# and once per cell in every disk scan). D-008 is untouched — the wrap
	# rule still lives in one FILE and every caller still comes through
	# this class — but two spellings of one rule is exactly the shape this
	# project keeps having to undo, so they are held to the same answer
	# here.
	var space := TorusSpace.new(W, H, 1.0)
	for q in range(-2 * W, 2 * W, 3):
		for r in range(-2 * H, 2 * H, 3):
			var coord := Vector2i(q, r)
			var wrapped := space.normalize(coord)
			assert_eq(space.index(coord), wrapped.y * space.width + wrapped.x,
				"index(%s) is the index OF normalize(%s)" % [coord, coord])


func test_round_axial_still_cube_rounds() -> void:
	# The body moved out of a private helper into `round_axial` itself for
	# the same measured reason. Cube rounding is what makes the plane
	# partition into HEXAGONS rather than rhombi
	# (D-20260818-a-curve-samples-the-hex-not-the-rhombus), so the
	# property is asserted rather than the implementation: the rounded
	# cell must be the nearest cell centre, which independent per-axis
	# rounding is not.
	var space := TorusSpace.new(W, H, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF00D
	for _i in range(4000):
		var fractional := Vector2(rng.randf_range(0.0, float(W)),
			rng.randf_range(0.0, float(H)))
		var cell := space.round_axial(fractional)
		var at := space.axial_offset_to_world(fractional - Vector2(cell))
		# Inside its own hex: no point of a unit hexagon is further than
		# its circumradius from the centre.
		assert_lte(Vector2(at.x, at.z).length(), space.hex_size * 1.0001,
			"%s rounds into the hex it is in" % fractional)


func test_disk_indices_is_disk_offsets_through_index() -> void:
	# The one-call form of "every cell within radius r", added because the
	# per-offset `index()` call was most of the cost of the client's tree
	# lookup and none of its work. Same cells, same ORDER — a caller that
	# swapped to it must not find anything different.
	var space := TorusSpace.new(W, H, 1.0)
	for cell_index in range(space.cell_count()):
		for radius in [0, 1, 3, 5]:
			var want := PackedInt32Array()
			var origin := space.from_index(cell_index)
			for offset in TorusSpace.disk_offsets(radius):
				want.append(space.index(origin + offset))
			assert_eq(space.disk_indices(cell_index, radius), want,
				"cell %d, radius %d" % [cell_index, radius])


func test_disk_indices_wraps_at_the_seam() -> void:
	# The half a non-wrapping implementation gets wrong, and the reason
	# this lives in TorusSpace rather than in the caller that wanted it.
	var space := TorusSpace.new(W, H, 1.0)
	var corner := space.index(Vector2i(0, 0))
	var indices := space.disk_indices(corner, 1)
	assert_eq(indices.size(), 7, "a radius-1 disk is seven cells")
	for i in indices:
		assert_gte(i, 0, "every index is in range")
		assert_lt(i, space.cell_count())
	# The neighbour across the west seam is a real cell on the far side.
	assert_true(indices.has(space.index(Vector2i(-1, 0))),
		"the cell west of the origin is the one at x = width - 1")
