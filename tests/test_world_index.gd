extends GutTest

## Guards `world_index.gd` — the building lookup's neighbourhood scan
## (#325).
##
## `client.gd`'s `_nearby_building_boxes` walked every known building, per
## drawn squad, per frame. Measured through the benchmark that runs the
## client's own render passes: **one millisecond per building per frame**
## at 630 drawn squads, exactly linear, and buildings only ever
## accumulate (D-030 keeps one known forever, D-076 makes a wall one
## building per cell).
##
## Two claims, and the file is worth nothing without both:
##
##   1. The caller sees the SAME buildings. The walk is reimplemented here
##      as the reference — "same set" against a plausible-looking answer
##      is not the same assertion.
##   2. The work per query stops growing with how many buildings are in
##      the match. Asserted as a COUNT of candidates returned, never as
##      milliseconds (D-106's amendment).

const REACH := 14.0


func _boxes(count: int, spread: float, seed_value: int = 0xB0B) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	for i in range(count):
		var half := Vector2(rng.randf_range(1.2, 3.0), rng.randf_range(1.2, 3.0))
		out.append({
			"at": Vector3(rng.randf_range(-spread, spread), 0.0,
				rng.randf_range(-spread, spread)),
			"half": half,
			"reach": maxf(half.x, half.y),
		})
	return out


func _indexed(boxes: Array) -> WorldIndex:
	var index := WorldIndex.new()
	index.begin()
	for i in range(boxes.size()):
		index.put(boxes[i]["at"], i, float(boxes[i]["reach"]))
	return index


## What `_nearby_building_boxes` did before #325, verbatim, as the
## reference answer.
func _walked(boxes: Array, centre: Vector3, search: float) -> Array:
	var out := []
	for i in range(boxes.size()):
		var entry: Dictionary = boxes[i]
		var at: Vector3 = entry["at"]
		if Vector2(at.x - centre.x, at.z - centre.z).length() \
				<= search + float(entry["reach"]):
			out.append(i)
	out.sort()
	return out


## The same test applied to whatever the index hands back — the caller's
## half, unchanged.
func _filtered(index: WorldIndex, boxes: Array, centre: Vector3,
		search: float) -> Array:
	var out := []
	for which in index.near(centre, search):
		var entry: Dictionary = boxes[which]
		var at: Vector3 = entry["at"]
		if Vector2(at.x - centre.x, at.z - centre.z).length() \
				<= search + float(entry["reach"]):
			out.append(which)
	out.sort()
	return out


# --- claim 1: the same buildings ----------------------------------------

func test_the_index_returns_exactly_what_the_walk_returned() -> void:
	for spread in [20.0, 60.0, 200.0]:
		var boxes := _boxes(120, spread)
		var index := _indexed(boxes)
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x9EED
		var found := 0
		for _probe in range(300):
			var centre := Vector3(rng.randf_range(-spread, spread), 0.0,
				rng.randf_range(-spread, spread))
			var want := _walked(boxes, centre, REACH)
			var got := _filtered(index, boxes, centre, REACH)
			assert_eq(got, want, "at spread %.0f, centre %s" % [spread, centre])
			found += got.size()
		# The vacuity check: a spread where nothing is ever in range would
		# make every assertion above a comparison of two empty lists.
		assert_gt(found, 0, "at spread %.0f somebody is in range" % spread)


func test_a_building_bigger_than_a_bucket_is_still_found() -> void:
	# `put` enters a thing into every bucket it reaches into, so a query
	# never has to widen for someone else's size. The failure this guards
	# is a wall or a keep whose extent crosses a bucket line.
	var boxes := [{
		"at": Vector3.ZERO, "half": Vector2(30.0, 30.0), "reach": 30.0,
	}]
	var index := _indexed(boxes)
	# Far outside the bucket the building's CENTRE sits in, but well
	# inside the building.
	var centre := Vector3(28.0, 0.0, 0.0)
	assert_eq(_filtered(index, boxes, centre, 4.0), [0],
		"a building wider than a bucket is found from inside it")
	assert_eq(_filtered(index, boxes, centre, 4.0),
		_walked(boxes, centre, 4.0), "and the walk agrees")


func test_a_query_wider_than_a_bucket_still_sees_everything() -> void:
	var boxes := _boxes(60, 80.0)
	var index := _indexed(boxes)
	for search in [4.0, 20.0, 60.0, 140.0]:
		assert_eq(_filtered(index, boxes, Vector3(10.0, 0.0, -5.0), search),
			_walked(boxes, Vector3(10.0, 0.0, -5.0), search),
			"a %.0f-unit search widens its own span" % search)


func test_an_empty_index_answers_nothing() -> void:
	var index := WorldIndex.new()
	index.begin()
	assert_eq(index.near(Vector3.ZERO, REACH).size(), 0)
	assert_eq(index.size(), 0)


func test_begin_forgets_the_last_frame() -> void:
	# The scan is rebuilt once per frame and the index is rebuilt with it;
	# a building razed between frames must not go on being found.
	var boxes := _boxes(8, 10.0)
	var index := _indexed(boxes)
	assert_gt(index.near(Vector3.ZERO, REACH).size(), 0)
	index.begin()
	assert_eq(index.near(Vector3.ZERO, REACH).size(), 0)
	assert_eq(index.size(), 0)


# --- claim 2: the work stops growing with the match ---------------------

func test_a_query_does_not_grow_with_buildings_far_away() -> void:
	# THE point of #325. Same local density around the query, four times
	# the buildings spread over four times the ground: the walk looked at
	# every one, this looks at the neighbourhood.
	var small := _boxes(60, 60.0)
	var large := _boxes(240, 120.0)
	var small_index := _indexed(small)
	var large_index := _indexed(large)
	small_index.near(Vector3.ZERO, REACH)
	var small_seen := small_index.candidates_returned
	large_index.near(Vector3.ZERO, REACH)
	var large_seen := large_index.candidates_returned
	gut.p("returned %d of 60 buildings, %d of 240"
		% [small_seen, large_seen])
	assert_lt(large_seen, 240 / 4,
		"a query touches a neighbourhood, not the match")
	assert_lte(large_seen, small_seen + 8,
		"four times the buildings at the same density is the same work — "
		+ "that is the linear-in-buildings term #325 is about, gone")


func test_the_whole_frame_stops_being_linear_in_buildings() -> void:
	# The frame-level claim: every drawn squad asking for its buildings.
	# The measured defect was 12.94 -> 59.50 -> 199.19 ms for 12 -> 60 ->
	# 200 buildings, dead linear. Counted here rather than timed.
	var totals := {}
	for count in [12, 60, 200]:
		var boxes := _boxes(count, 60.0)
		var index := _indexed(boxes)
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x5A1D
		var total := 0
		for _squad in range(200):
			index.near(Vector3(rng.randf_range(-60.0, 60.0), 0.0,
				rng.randf_range(-60.0, 60.0)), REACH)
			total += index.candidates_returned
		totals[count] = total
	gut.p("candidates returned over 200 squads: %d at 12 buildings, %d at 60, %d at 200"
		% [totals[12], totals[60], totals[200]])
	# The walk would be exactly 200 x count: 2,400 / 12,000 / 40,000.
	assert_lt(totals[200], 40000 / 3,
		"200 buildings must not cost every squad 200 candidates")


# --- the callers --------------------------------------------------------

func test_both_drawing_surfaces_use_the_index() -> void:
	# D-106's caller-exists rule, and #240's lesson: the client and the
	# benchmark that claims to measure it must find their buildings the
	# same way, or the benchmark stops pricing what ships.
	for path in ["res://client.gd", "res://bench_render.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "%s is readable" % path)
		assert_true(text.contains("_building_index.near("),
			"%s finds its buildings through the index (#325)" % path)
		assert_false(text.contains("for entry in _building_scan:"),
			"%s must not walk every known building again" % path)
