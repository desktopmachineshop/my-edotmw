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
