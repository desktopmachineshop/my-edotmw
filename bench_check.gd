extends SceneTree

## Compare a recorded render baseline against a fresh run, loudly (#286).
##
## Deliberately thin: everything that decides pass or fail lives in
## `BenchBaseline`, which is all-static and pure and therefore testable
## headless. This file loads JSON, prints, and picks an exit code —
## nothing a test would want to reach.
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
##
## ## Baselines are PER ADAPTER (#285)
##
## A frame time is a statement about hardware, so there is one recorded
## file per GPU (`bench/baseline-<slug>.json`) and a run is compared
## against ITS OWN. Where no slot matches — a machine nobody has recorded
## on, which is every first run on new hardware — the counts are still
## gated, against whichever slot is present, because counts are
## deterministic given the map, the roster and the render path and have
## nothing to do with the GPU. The milliseconds are simply not compared,
## and the report says so.

func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var strict := int(args.get("strict", 0)) != 0

	if args.has("stale"):
		_stale_only(String(args.get("baseline", "")), strict)
		return

	var run_path := String(args.get("run", "res://artifacts/bench-latest.json"))
	var run := _read(run_path)
	if run.is_empty():
		print("bench-check: no run at %s — `just bench-check` runs the "
			% run_path + "benchmark first, and it needs a real GPU (D-014).")
		quit(1)
		return

	# The run names the adapter it measured on, so it is the run that
	# decides which slot it is compared against — never a flag, never the
	# machine's own guess. A comparison that had to be TOLD its hardware
	# is one somebody can point at the wrong file.
	var adapter := String(run.get("adapter", ""))
	var chosen := _slot_for(String(args.get("baseline", "")), adapter)
	var baseline := _read(String(chosen["path"]))
	if not String(chosen["note"]).is_empty():
		print("bench-check: %s" % String(chosen["note"]))

	var comparison := BenchBaseline.compare(baseline, run)
	print(BenchBaseline.report(comparison))
	quit(BenchBaseline.exit_code(comparison, strict))


## Which recorded file this run is measured against, and what to say
## about the choice. Returns `{"path": String, "note": String}`.
func _slot_for(explicit: String, adapter: String) -> Dictionary:
	if not explicit.is_empty():
		return {"path": explicit, "note": ""}
	var own := BenchBaseline.path_for(adapter)
	if FileAccess.file_exists(own):
		return {"path": own, "note": ""}
	var slots := BenchBaseline.slots()
	if slots.is_empty():
		return {"path": own, "note": ""}
	# No slot for this adapter. The counts still gate — they are a
	# property of the tree, not of the GPU — and `BenchBaseline.compare`
	# already refuses to compare milliseconds across adapters and says
	# why, so this only has to pick something and be honest about it.
	return {"path": String(slots[0]), "note":
		("no baseline recorded on '%s' yet (%s). Comparing COUNTS against "
		+ "%s; milliseconds are not compared. `just bench-record` on this "
		+ "machine writes its own slot and overwrites nobody.")
		% [adapter, own.get_file(), String(slots[0]).get_file()]}


func _stale_only(explicit: String, strict: bool) -> void:
	var paths := PackedStringArray([explicit]) if not explicit.is_empty() \
		else BenchBaseline.slots()
	if paths.is_empty():
		print("bench-check: no baseline in %s — nothing has ever been "
			% BenchBaseline.DIR + "recorded, so nothing can be stale.")
		quit(1 if strict else 0)
		return

	# EVERY slot, because staleness is a question about the TREE and each
	# recorded adapter answers it separately: one machine's numbers can
	# predate a roster change while another's do not, and a check that
	# read one file would call the tree fresh on the strength of whichever
	# it happened to open.
	var any_stale := false
	for path in paths:
		var baseline := _read(String(path))
		if baseline.is_empty():
			continue
		var drifted := BenchBaseline.stale_against(
			baseline.get("fingerprint", {}), BenchBaseline.fingerprint())
		var who := "%s (%s)" % [String(path).get_file(),
			str(baseline.get("adapter", "?"))]
		if drifted.is_empty():
			print("bench-check: FRESH — %s was taken against this map, this "
				% who + "roster, these assets and this render path, on %s"
				% str(baseline.get("recorded", "?")))
			continue
		any_stale = true
		print("bench-check: STALE — %s" % who)
		for entry in drifted:
			print("  %-12s %s -> %s" % [entry["what"], entry["was"], entry["now"]])

	if any_stale:
		print("bench-check: a stale slot is a number about a different tree. "
			+ "Re-measure with `just bench-record` — on hardware you can name "
			+ "— and commit the slot it writes.")
	quit(1 if (any_stale and strict) else 0)


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


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	for raw in argv:
		var text := String(raw)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var split := body.find("=")
		if split < 0:
			out[body] = true
		else:
			out[body.substr(0, split)] = body.substr(split + 1)
	return out
