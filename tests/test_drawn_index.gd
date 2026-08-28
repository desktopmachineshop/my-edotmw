extends GutTest

## Guards `drawn_index.gd` — the cross-squad jostle's neighbour lookup
## (#262).
##
## Two claims, and the file is worth nothing without both:
##
##   1. It returns the SAME men the walk it replaces returned. The walk is
##      reimplemented here as the reference, because "same men" against a
##      plausible-looking answer is not the same assertion.
##   2. The work it does per squad stops growing with the number of drawn
##      squads. Asserted as a COUNT of candidates examined, never as
##      milliseconds — a wall-clock assertion on a shared host goes red
##      with nothing wrong, which this project wrote down and then did
##      two commits later (D-106's amendment).
##
## The measured defect: 9.97 ms at 155 drawn squads and 152.43 ms at 630,
## 4.06x the squads for 14.3x the time, 39% of the whole frame at 1,000
## squads — and it fired for STANDING squads, i.e. once the battle
## started.

const RADIUS := 4.0


func _men_around(centre: Vector3, count: int, spread: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(count):
		var angle := TAU * float(i) / float(maxi(count, 1))
		out.append(centre + Vector3(cos(angle), 0.0, sin(angle)) * spread)
	return out


## The walk `DrawnIndex` replaces, verbatim, as the reference answer.
func _walked(cache: Dictionary, squad_id, at: Vector3,
		radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for other_id in cache:
		if other_id == squad_id:
			continue
		var record: Dictionary = cache[other_id]
		if (record["centre"] as Vector3).distance_to(at) \
				> radius + float(record["radius"]) + 1.0:
			continue
		var men: PackedVector3Array = record["men"]
		for k in range(men.size()):
			if Vector2(men[k].x - at.x, men[k].z - at.z).length() <= radius + 1.0:
				out.append(men[k])
	return out


func _sorted(men: PackedVector3Array) -> Array:
	# Order is not part of the contract (`SoldierMotion.ease` sums a
	# repulsion per man and skips anything past JOSTLE_RADIUS), so the
	# comparison is over the SET.
	var out := []
	for man in men:
		out.append("%.4f,%.4f,%.4f" % [man.x, man.y, man.z])
	out.sort()
	return out


## A field of squads on a grid, in both forms: the dictionary the walk
## reads and the index the lookup reads.
func _field(squads: int, spacing: float, men_each := 24) -> Dictionary:
	var cache := {}
	var index := DrawnIndex.new()
	index.begin()
	var per_row := maxi(1, int(ceil(sqrt(float(squads)))))
	for i in range(squads):
		var centre := Vector3(
			float(i % per_row) * spacing, 0.0, float(i / per_row) * spacing)
		var men := _men_around(centre, men_each, RADIUS * 0.6)
		cache[i] = {"men": men, "centre": centre, "radius": RADIUS}
		index.put(i, centre, RADIUS, men)
	return {"cache": cache, "index": index, "per_row": per_row,
		"spacing": spacing}


# --- claim 1: the same men -----------------------------------------------

func test_the_index_returns_exactly_the_men_the_walk_returned() -> void:
	# Squads packed tightly enough that most have neighbours, spread over
	# several buckets, so the 3x3 neighbourhood is genuinely exercised.
	for spacing in [2.0, 5.0, 9.0, 17.0]:
		var field := _field(64, spacing)
		var cache: Dictionary = field["cache"]
		var index: DrawnIndex = field["index"]
		var found := 0
		for id in cache:
			var at: Vector3 = cache[id]["centre"]
			var want := _walked(cache, id, at, RADIUS)
			var got := index.neighbours_of(id, at, RADIUS)
			assert_eq(_sorted(got), _sorted(want),
				"squad %s at spacing %.1f" % [id, spacing])
			found += got.size()
		if spacing <= 5.0:
			# The vacuity check: at wider spacings nobody is within
			# reach of anybody, so an empty answer is correct and proves
			# nothing. At 2 and 5 apart they overlap and it does.
			assert_gt(found, 0,
				"at spacing %.1f somebody has neighbours, or this proves "
				% spacing + "nothing")


func test_it_finds_neighbours_across_a_bucket_boundary() -> void:
	# The failure a grid index has: two squads a metre apart either side
	# of a bucket edge. Walked one bucket at a time they never meet.
	var index := DrawnIndex.new()
	index.begin()
	var bucket: float = DrawnIndex.MIN_BUCKET
	var left := Vector3(bucket - 0.5, 0.0, 0.0)
	var right := Vector3(bucket + 0.5, 0.0, 0.0)
	index.put(1, left, RADIUS, _men_around(left, 8, 0.5))
	index.put(2, right, RADIUS, _men_around(right, 8, 0.5))
	assert_gt(index.neighbours_of(1, left, RADIUS).size(), 0,
		"a squad just over the bucket line is still a neighbour")
	assert_gt(index.neighbours_of(2, right, RADIUS).size(), 0)


func test_a_squad_never_jostles_against_itself() -> void:
	var index := DrawnIndex.new()
	index.begin()
	var at := Vector3(3.0, 0.0, 3.0)
	index.put(7, at, RADIUS, _men_around(at, 12, 1.0))
	assert_eq(index.neighbours_of(7, at, RADIUS).size(), 0)


func test_far_squads_contribute_nothing() -> void:
	var index := DrawnIndex.new()
	index.begin()
	index.put(1, Vector3.ZERO, RADIUS, _men_around(Vector3.ZERO, 12, 1.0))
	var far := Vector3(400.0, 0.0, 400.0)
	index.put(2, far, RADIUS, _men_around(far, 12, 1.0))
	assert_eq(index.neighbours_of(1, Vector3.ZERO, RADIUS).size(), 0)


func test_the_order_is_deterministic_rather_than_match_history() -> void:
	# The walk iterated a dictionary, so its order depended on which squad
	# was drawn first — a thing two clients can disagree about. This one
	# is ascending squad id whatever order the squads arrived in.
	var forwards := DrawnIndex.new()
	var backwards := DrawnIndex.new()
	forwards.begin()
	backwards.begin()
	var centres := []
	for i in range(12):
		centres.append(Vector3(float(i) * 1.5, 0.0, 0.0))
	for i in range(12):
		forwards.put(i, centres[i], RADIUS, _men_around(centres[i], 6, 0.4))
	for i in range(11, -1, -1):
		backwards.put(i, centres[i], RADIUS, _men_around(centres[i], 6, 0.4))
	assert_eq(forwards.neighbours_of(5, centres[5], RADIUS),
		backwards.neighbours_of(5, centres[5], RADIUS),
		"the answer does not depend on the order squads were drawn in")


# --- claim 2: the work stops growing -------------------------------------

func test_the_work_per_squad_does_not_grow_with_the_field() -> void:
	# THE point of #262. Same local density, four times the squads: the
	# walk examined every squad in the match, this examines the ones
	# nearby. Counted, not timed.
	# Both fields are larger than one query's neighbourhood, which is the
	# only comparison that says anything: a field smaller than the
	# neighbourhood is examined whole however good the index is.
	var small := _field(256, 3.0)
	var large := _field(1024, 3.0)
	var small_index: DrawnIndex = small["index"]
	var large_index: DrawnIndex = large["index"]

	small_index.neighbours_of(0, (small["cache"] as Dictionary)[0]["centre"], RADIUS)
	var small_examined := small_index.candidates_examined
	large_index.neighbours_of(0, (large["cache"] as Dictionary)[0]["centre"], RADIUS)
	var large_examined := large_index.candidates_examined

	gut.p("examined %d of 256 squads, %d of 1024"
		% [small_examined, large_examined])
	assert_lt(large_examined, 256,
		"a query touches a neighbourhood, not the match")
	assert_lte(large_examined, small_examined + 4,
		"four times the squads at the same density is the SAME work — "
		+ "that is the quadratic #262 is about, gone")


func test_the_sweep_over_a_whole_frame_is_linear_in_squads() -> void:
	# The frame-level claim: every drawn squad asking for its neighbours.
	# Doubling the field must roughly double the total, not quadruple it.
	var totals := {}
	for squads in [256, 1024]:
		var field := _field(squads, 3.0)
		var index: DrawnIndex = field["index"]
		var cache: Dictionary = field["cache"]
		var total := 0
		for id in cache:
			index.neighbours_of(id, cache[id]["centre"], RADIUS)
			total += index.candidates_examined
		totals[squads] = total
	gut.p("candidates examined per frame: %d at 256 squads, %d at 1024"
		% [totals[256], totals[1024]])
	# Quadratic would be 16x for 4x the squads. Linear is 4x. The slack
	# covers edge effects — a grid's border squads have fewer neighbours,
	# so the smaller field is cheaper per squad than the larger.
	assert_lt(totals[1024], totals[256] * 6,
		"the per-frame sweep grows with the squads, not with their square")


# --- the pruning half of #262 -------------------------------------------

func test_a_squad_that_is_no_longer_drawn_is_dropped() -> void:
	# `_drawn_cache` was never pruned, so the walk covered every squad the
	# match had ever drawn. This is a deliberate behaviour change and it is
	# the right one: a squad nobody is drawing has no men on screen for
	# anyone to jostle against.
	var index := DrawnIndex.new()
	index.begin()
	var here := Vector3(1.0, 0.0, 1.0)
	index.put(1, here, RADIUS, _men_around(here, 8, 0.5))
	index.put(2, here + Vector3(1.0, 0.0, 0.0), RADIUS,
		_men_around(here + Vector3(1.0, 0.0, 0.0), 8, 0.5))
	assert_gt(index.neighbours_of(1, here, RADIUS).size(), 0, "both drawn")

	index.begin()
	index.put(1, here, RADIUS, _men_around(here, 8, 0.5))
	assert_eq(index.neighbours_of(1, here, RADIUS).size(), 0,
		"squad 2 was not drawn this frame, so its men are not on screen")
	assert_eq(index.size(), 1, "and it is not in the index")


func test_the_index_is_empty_before_anything_is_drawn() -> void:
	var index := DrawnIndex.new()
	assert_eq(index.size(), 0)
	assert_eq(index.neighbours_of(0, Vector3.ZERO, RADIUS).size(), 0)


# --- the callers ---------------------------------------------------------

func test_both_drawing_surfaces_use_the_index() -> void:
	# D-106's caller-exists rule, and #240's lesson: the client and the
	# benchmark that claims to measure it must gather neighbours the same
	# way, or the benchmark stops pricing the thing that ships.
	for path in ["res://client.gd", "res://bench_render.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "%s is readable" % path)
		assert_true(text.contains("_drawn.neighbours_of("),
			"%s gathers jostle neighbours through the index (#262)" % path)
		assert_false(text.contains("for other_id in _drawn_cache"),
			"%s must not walk every drawn squad again" % path)


func test_nothing_simulation_side_reads_the_drawn_index() -> void:
	# Per-soldier RENDER state is legal under D-006 clause 2 as amended
	# (bounded, one-way, outcome-blind) and legal ONLY there. Same scan
	# `test_tier_three.gd` runs for SoldierMotion, for the same reason.
	var scripts: Array = []
	_all_scripts("res://", scripts)
	var readers: Array = []
	for path in scripts:
		var path_str := String(path)
		if path_str == "res://drawn_index.gd" or path_str.begins_with("res://tests/"):
			continue
		var text := FileAccess.get_file_as_string(path_str)
		if text.contains("DrawnIndex"):
			readers.append(path_str)
	assert_gt(readers.size(), 0, "somebody uses it, or it is dead code")
	for reader in readers:
		assert_true(String(reader) == "res://client.gd"
			or String(reader) == "res://bench_render.gd",
			("only a drawing surface may hold drawn men — %s reading "
			+ "DrawnIndex is per-soldier render state one call from an "
			+ "outcome, which is D-006's revisit trigger firing") % reader)


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "tools" or sub == "addons":
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))
