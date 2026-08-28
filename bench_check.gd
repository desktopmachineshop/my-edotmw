extends SceneTree

## Compare a recorded render baseline against a fresh run, loudly (#286).
##
## Deliberately thin: everything that decides pass or fail lives in
## `BenchBaseline`, which is all-static and pure and therefore testable
## headless. This file loads two JSON files, prints, and picks an exit
## code — nothing a test would want to reach.
##
## Two modes, because they are two questions:
##
##   --run=artifacts/bench-latest.json    compare a fresh run (needs the
##                                        run; the run needs a GPU)
##   --stale                              ask only whether the recorded
##                                        numbers are about THIS tree.
##                                        Seconds, no GPU, any machine.
##
## The second is the one that belongs on a pull request: it cannot tell
## you the client got slower, and it can tell you that nobody has
## measured since the map, the roster, the built assets or the render
## path last moved — which is exactly what #229 needed and did not have.

func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var strict := int(args.get("strict", 0)) != 0
	var baseline := _read(String(args.get("baseline", BenchBaseline.PATH)))

	if args.has("stale"):
		_stale_only(baseline, strict)
		return

	var run_path := String(args.get("run", "res://artifacts/bench-latest.json"))
	var run := _read(run_path)
	if run.is_empty():
		print("bench-check: no run at %s — `just bench-check` runs the "
			% run_path + "benchmark first, and it needs a real GPU (D-014).")
		quit(1)
		return

	var comparison := BenchBaseline.compare(baseline, run)
	print(BenchBaseline.report(comparison))
	quit(BenchBaseline.exit_code(comparison, strict))


func _stale_only(baseline: Dictionary, strict: bool) -> void:
	if baseline.is_empty():
		print("bench-check: no baseline at %s — nothing has ever been "
			% BenchBaseline.PATH + "recorded, so nothing can be stale.")
		quit(1 if strict else 0)
		return
	var drifted := BenchBaseline.stale_against(
		baseline.get("fingerprint", {}), BenchBaseline.fingerprint())
	if drifted.is_empty():
		print("bench-check: FRESH — the recorded render numbers were taken "
			+ "against this map, this roster, these assets and this render "
			+ "path.\nbench-check: recorded %s on %s"
			% [str(baseline.get("recorded", "?")),
				str(baseline.get("adapter", "?"))])
		quit(0)
		return
	print("bench-check: STALE")
	for entry in drifted:
		print("  %-12s %s -> %s" % [entry["what"], entry["was"], entry["now"]])
	print("bench-check: the recorded render cost is a number about a "
		+ "different tree. Re-measure with `just bench-record` — on hardware "
		+ "you can name — and commit bench/baseline.json.")
	quit(1 if strict else 0)


func _read(path: String) -> Dictionary:
	# `res://` on purpose, like every other artifact path in this tree.
	# When #237's `ArtifactPath` lands, this and the writer in
	# `bench_render.gd` are two of its call sites — an exported build
	# cannot write here, and a baseline check has no business running in
	# one anyway.
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _parse(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in raw:
		var text := String(arg)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = true
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out
