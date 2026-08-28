extends GutTest

## Guards `bench_baseline.gd` — the recorded render baseline and what a
## fresh run may differ from it by (#286).
##
## The measurement needs a GPU (D-014) and cannot run here. The
## arithmetic that decides PASS or FAIL does not, and this is it: a gate
## nobody can run headless is a gate nobody perturbs, and a check nobody
## has seen fail is vacuous by this project's own law (D-022's audit
## block).
##
## Three behaviours matter and each has its own test below:
##
##   counts GATE          — deterministic given the fingerprint
##   milliseconds REPORT  — they move with the host, never with the build
##   stale OUTRANKS changed — a count that moved because a unit was added
##                            is news about the roster, not a regression

const ADAPTER := "Intel(R) Iris(R) Xe Graphics"


func _fingerprint(overrides := {}) -> Dictionary:
	var out := {
		"map": "168x194", "roster": "aaaa", "generated": "bbbb",
		"render_path": "cccc", "godot": "4.7.1-stable (official)",
	}
	for key in overrides:
		out[key] = overrides[key]
	return out


func _row(overrides := {}) -> Dictionary:
	var out := {
		"soldiers": 15756, "drawn": 4385, "squads_drawn": 630,
		"draw_calls": 228, "fighting": 167, "working": 167, "marching": 666,
		"cpu_ms": 350.0, "wall_ms": 400.0, "cull_ms": 18.0,
		"derive_ms": 60.0, "decorate_ms": 260.0, "upload_ms": 14.0,
	}
	for key in overrides:
		out[key] = overrides[key]
	return out


func _record(row_overrides := {}, fingerprint_overrides := {},
		adapter := ADAPTER) -> Dictionary:
	return {
		"version": BenchBaseline.VERSION,
		"adapter": adapter,
		"viewport": "1152x648",
		"fingerprint": _fingerprint(fingerprint_overrides),
		"rows": {"1000": _row(row_overrides)},
	}


# --- the gate -----------------------------------------------------------

func test_an_identical_run_passes() -> void:
	var comparison := BenchBaseline.compare(_record(), _record())
	assert_eq(String(comparison["status"]), "ok")
	assert_eq(BenchBaseline.exit_code(comparison), 0)


func test_a_moved_count_fails() -> void:
	# THE gate. Same map, same roster, same render path, and the renderer
	# draws a different number of men: either a render-path change nobody
	# declared or a defect.
	for count in BenchBaseline.GATED_COUNTS:
		var run := _record({count: 1})
		var comparison := BenchBaseline.compare(_record(), run)
		assert_eq(String(comparison["status"]), "changed",
			"%s moving is a failure" % count)
		assert_eq(BenchBaseline.exit_code(comparison), 1,
			"%s moving exits non-zero" % count)
		assert_true(BenchBaseline.report(comparison).contains(count),
			"and the report names %s" % count)


func test_milliseconds_never_fail() -> void:
	# The rule this project has already paid for once: a wall-clock gate
	# on a shared host goes red with nothing wrong (D-106's amendment,
	# written two commits before it happened). The first pair of real runs
	# taken with this mechanism moved 13% on identical code, which is the
	# evidence, and this is the rule.
	var run := _record({
		"cpu_ms": 3500.0, "wall_ms": 4000.0, "cull_ms": 180.0,
		"derive_ms": 600.0, "decorate_ms": 2600.0, "upload_ms": 140.0})
	var comparison := BenchBaseline.compare(_record(), run)
	assert_eq(String(comparison["status"]), "ok",
		"ten times slower is not a FAILURE of this check")
	assert_eq(BenchBaseline.exit_code(comparison), 0)
	# Reported all the same, and loudly.
	var text := BenchBaseline.report(comparison)
	assert_true(text.contains("TIME!"), "a 10x is called out")
	assert_true(text.contains("+900.0%"), "with the delta on it")


func test_a_small_time_move_is_reported_quietly() -> void:
	var run := _record({"cpu_ms": 350.0 * 1.05})
	var text := BenchBaseline.report(BenchBaseline.compare(_record(), run))
	assert_true(text.contains("time  "), "small moves are still printed")
	assert_false(text.contains("TIME!"), "but not shouted about")


# --- stale outranks changed --------------------------------------------

func test_a_changed_roster_reads_as_STALE_not_as_a_regression() -> void:
	# A count that moved because somebody added a unit is a baseline that
	# needs re-recording. Reporting it as a regression is how a check
	# earns its way onto the ignore list.
	var run := _record({"soldiers": 16000}, {"roster": "dddd"})
	var comparison := BenchBaseline.compare(_record(), run)
	assert_eq(String(comparison["status"]), "stale")
	assert_eq(BenchBaseline.exit_code(comparison), 0,
		"stale is news by default")
	assert_eq(BenchBaseline.exit_code(comparison, true), 1,
		"and a fault when the caller asks for strict")
	var text := BenchBaseline.report(comparison)
	assert_true(text.contains("STALE"), "the report leads with it")
	assert_true(text.contains("roster"), "and says which part moved")


func test_every_part_of_the_fingerprint_can_go_stale() -> void:
	# #286's own list: the map, the roster, the built assets, the render
	# path. Godot's version too, since a frame time across engine versions
	# is a different measurement.
	for part in ["map", "roster", "generated", "render_path", "godot"]:
		var drifted := BenchBaseline.stale_against(
			_fingerprint(), _fingerprint({part: "moved"}))
		assert_eq(drifted.size(), 1, "%s alone is one difference" % part)
		assert_eq(String(drifted[0]["what"]), part)
	assert_eq(BenchBaseline.stale_against(_fingerprint(), _fingerprint()), [],
		"an unchanged tree is not stale")


# --- hardware -----------------------------------------------------------

func test_times_are_not_compared_across_hardware() -> void:
	# "Never quote a frame time without the hardware" (D-044 criterion 2),
	# applied to the comparison itself: a baseline from integrated
	# graphics says nothing about a run on a discrete GPU.
	var run := _record({"cpu_ms": 40.0}, {}, "NVIDIA Something")
	var comparison := BenchBaseline.compare(_record(), run)
	assert_eq(String(comparison["status"]), "ok")
	var row: Dictionary = comparison["rows"][0]
	assert_eq((row["times"] as Array).size(), 0,
		"no millisecond deltas across different adapters")
	assert_true(BenchBaseline.report(comparison).contains("NOT compared"),
		"and the report says why rather than going quiet")


func test_counts_are_still_gated_across_hardware() -> void:
	# The half that IS comparable everywhere: how many men a run drew does
	# not depend on the GPU.
	var run := _record({"drawn": 4000}, {}, "NVIDIA Something")
	assert_eq(String(BenchBaseline.compare(_record(), run)["status"]), "changed")


# --- the empty cases ----------------------------------------------------

func test_no_baseline_is_reported_rather_than_passed() -> void:
	var comparison := BenchBaseline.compare({}, _record())
	assert_eq(String(comparison["status"]), "unknown")
	assert_true(BenchBaseline.report(comparison).contains("bench-record"),
		"and says what to do about it")
	# Deliberately not a failure: a tree that has never recorded one has
	# nothing to regress against, and failing here would only teach
	# whoever sees it to pass `--strict=0` forever.
	assert_eq(BenchBaseline.exit_code(comparison), 0)


func test_a_new_squad_count_is_reported_not_failed() -> void:
	var run := _record()
	run["rows"]["500"] = _row({"soldiers": 7868})
	var comparison := BenchBaseline.compare(_record(), run)
	assert_eq(String(comparison["status"]), "ok")
	assert_true(BenchBaseline.report(comparison).contains("NEW"),
		"a row nothing was recorded for is named")


func test_an_old_format_asks_to_be_re_recorded() -> void:
	var old := _record()
	old["version"] = BenchBaseline.VERSION - 1
	var comparison := BenchBaseline.compare(old, _record())
	assert_eq(String(comparison["status"]), "unknown")
	assert_true(BenchBaseline.report(comparison).contains("re-record"))


# --- the fingerprint is about THIS tree ---------------------------------

func test_the_fingerprint_reads_the_real_tree() -> void:
	var print_of := BenchBaseline.fingerprint()
	assert_eq(String(print_of["map"]), "168x194",
		"the shipped map, by its dimensions")
	assert_gt(int(print_of["roster_units"]), 20, "the whole roster")
	for part in ["roster", "generated", "render_path"]:
		assert_ne(String(print_of[part]), "missing",
			"%s hashed something real" % part)


func test_the_render_path_list_names_files_that_exist() -> void:
	# The list is data, so it can go stale in the other direction: a
	# module renamed out from under it would silently stop being watched,
	# which is the "declared and unread" family aimed at a config.
	for path in BenchBaseline.RENDER_PATH_SOURCES:
		assert_true(FileAccess.file_exists(path),
			"%s is watched for render-path changes and must exist" % path)


func test_the_committed_baseline_is_readable_and_names_its_hardware() -> void:
	var text := FileAccess.get_file_as_string(BenchBaseline.PATH)
	assert_ne(text, "", "%s is committed" % BenchBaseline.PATH)
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "and is JSON")
	if parsed is Dictionary:
		assert_ne(String(parsed.get("adapter", "")), "",
			"a frame time without its hardware is not a number anyone can use")
		assert_false(bool(parsed.get("headless", false)),
			"a baseline recorded headless has no draw calls and a cull that "
			+ "passes everything — it must come from a real GPU")
		assert_gt((parsed.get("rows", {}) as Dictionary).size(), 0,
			"and it has rows")


func test_a_different_window_is_stale_rather_than_changed() -> void:
	# The cull tests against the SCREEN, so every drawn count is a count
	# at that size. A CI runner whose window differs is asking a different
	# question, and blaming the renderer for it would be the fastest way
	# to teach everyone to ignore this check.
	var run := _record({"drawn": 4000})
	run["viewport"] = "1920x1080"
	var comparison := BenchBaseline.compare(_record(), run)
	assert_eq(String(comparison["status"]), "stale")
	assert_true(BenchBaseline.report(comparison).contains("viewport"),
		"and the report names it")
