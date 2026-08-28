extends RefCounted
class_name BenchBaseline

## The recorded render baseline, and what a fresh run is allowed to differ
## from it by (#286).
##
## ## Why this exists
##
## #229 was a 3x client render regression found months late, by a human
## playing the game. Nothing re-measured render cost when the map ladder
## moved, when the roster changed, or when a render pass was added — and
## #240 then found the benchmark had not measured the client at all since
## the RTW programme. Both are the same absence: **there was no recorded
## number for anything to be compared against.**
##
## ## The two halves, and why they are different questions
##
## **What a run COUNTS is deterministic; what it TIMES is not.** Given the
## same map, roster and viewport, a run draws the same soldiers at the
## same LOD tiers in the same draw calls every time — those numbers move
## only when the world or the render path moves, which is exactly the
## trigger #286 asks for. Milliseconds move when the host is busy, and
## this project has already gone red once on a wall-clock gate with
## nothing wrong (D-106's amendment, two commits after writing the
## warning down).
##
## So: **gate on counts, publish milliseconds.** That is the gap
## assessment's own rule for CI, and it is the rule here.
##
## ## And a third question the fingerprint answers
##
## A count that changed because somebody added a unit is not a
## regression, it is a baseline that is now STALE. The fingerprint records
## what the numbers were measured against — the map, the roster, the built
## assets, and the source of the render path itself — so a comparison can
## say "re-record" instead of "regression". Without it every roster change
## would read as a fault and the mechanism would be muted within a month,
## which is D-022's audit block arriving from the other direction.
##
## All-static and pure over its arguments (`fingerprint` reads the tree,
## which is what makes it a fingerprint). The arithmetic that decides
## pass or fail must be testable without a GPU — `bench_render.gd` needs
## one, and a gate nobody can run headless is a gate nobody perturbs.

const VERSION := 1
const PATH := "res://bench/baseline.json"

## Which counts are deterministic given the fingerprint, and therefore
## gate. `soldiers` is the army the roster fields; `drawn` and
## `squads_drawn` are what survives culling and LOD; `draw_calls` is what
## reaches the GPU; `keys_worst` is the longest curve sampled.
const GATED_COUNTS := ["soldiers", "drawn", "squads_drawn", "draw_calls",
	"fighting", "working", "marching"]

## Reported, never gated. See the header: a millisecond is a statement
## about the host as much as about the build.
const REPORTED_TIMES := ["cpu_ms", "wall_ms", "cull_ms", "derive_ms",
	"decorate_ms", "upload_ms"]

## The files whose contents decide what a frame does. A change to any of
## them makes a recorded number a number about a different renderer —
## which is the "render path changed and nothing re-measured" half of
## #286. Data rather than a rule in code, so adding a render module means
## adding a line here and re-recording, not discovering later that the
## baseline stopped meaning anything.
const RENDER_PATH_SOURCES := [
	"res://formation.gd",
	"res://squad_render.gd",
	"res://render_cull.gd",
	"res://client_state.gd",
	"res://primitive_unit.gd",
	"res://cosmetic_duel.gd",
	"res://cosmetic_offset.gd",
	"res://soldier_motion.gd",
	"res://engagement.gd",
	"res://animation_state.gd",
	"res://terrain_chunk.gd",
	"res://bench_render.gd",
]

## How far a REPORTED number may move before the report calls it out.
## Advisory: it decides how loud the line is, never the exit code.
const TIME_NOTICE_PCT := 15.0


## What this tree's render numbers would be measured against.
##
## Cheap on purpose — it reads a handful of files and hashes them — so
## the "is the baseline stale" question can be asked on any machine, in
## seconds, without a GPU. That is the check that belongs on a pull
## request; the measurement itself needs hardware and belongs where the
## hardware is.
static func fingerprint(map_path := "res://maps/default.tres") -> Dictionary:
	var config := load(map_path) as MapConfig
	var map := "missing"
	if config != null:
		map = "%dx%d" % [config.width, config.height]

	# The roster decides how many men a squad fields, which is the whole
	# of `soldiers` and most of `drawn`.
	var roster := []
	for def in UnitRoster.load_all():
		roster.append("%s:%d:%s" % [def.id, def.squad_size, def.model_id])

	return {
		"map": map,
		"map_path": map_path,
		"roster": _hash_of("\n".join(roster)),
		"roster_units": roster.size(),
		"generated": _hash_of(FileAccess.get_file_as_string(
			"res://generated/manifest.json")),
		"render_path": _hash_of(_render_path_source()),
		"godot": Engine.get_version_info().get("string", "?"),
	}


static func _render_path_source() -> String:
	var parts := []
	for path in RENDER_PATH_SOURCES:
		parts.append(path)
		parts.append(FileAccess.get_file_as_string(path))
	return "\n".join(parts)


static func _hash_of(text: String) -> String:
	if text == "":
		return "missing"
	return String.num_uint64(text.hash(), 16)


## Which parts of the fingerprint differ, in a caller-friendly form.
## Empty means the recorded numbers are about this tree.
static func stale_against(recorded: Dictionary, current: Dictionary) -> Array:
	var out := []
	for key in ["map", "roster", "generated", "render_path", "godot"]:
		var was = recorded.get(key, "?")
		var now = current.get(key, "?")
		if was != now:
			out.append({"what": key, "was": was, "now": now})
	return out


## Compare a fresh run against the baseline.
##
## Returns {"status", "stale", "rows", "notes"} where status is:
##   "ok"      — every gated count matches
##   "stale"   — the world or the render path moved; re-record
##   "changed" — same world, and a gated count moved. THE failure.
##   "unknown" — nothing recorded for this configuration yet
##
## `stale` outranks `changed` deliberately: a count that moved because a
## unit was added is news about the roster, not about the renderer, and
## reporting it as a regression is how a check earns its way onto the
## ignore list.
static func compare(baseline: Dictionary, run: Dictionary) -> Dictionary:
	var out := {"status": "ok", "stale": [], "rows": [], "notes": []}

	if baseline.is_empty():
		out["status"] = "unknown"
		out["notes"].append(
			"no baseline recorded — run `just bench-record` on hardware you "
			+ "can name, and commit bench/baseline.json")
		return out
	if int(baseline.get("version", 0)) != VERSION:
		out["status"] = "unknown"
		out["notes"].append("baseline is format v%s, this is v%d — re-record"
			% [str(baseline.get("version", "?")), VERSION])
		return out

	out["stale"] = stale_against(
		baseline.get("fingerprint", {}), run.get("fingerprint", {}))

	# The viewport is not part of the TREE, but every drawn count is a
	# count at that size — the cull tests against the screen. A runner
	# whose window differs is measuring a different question, and saying
	# so beats blaming the renderer for it.
	var recorded_viewport := String(baseline.get("viewport", ""))
	var run_viewport := String(run.get("viewport", ""))
	if recorded_viewport != "" and run_viewport != "" 			and recorded_viewport != run_viewport:
		out["stale"].append({"what": "viewport", "was": recorded_viewport,
			"now": run_viewport})

	var recorded: Dictionary = baseline.get("rows", {})
	var fresh: Dictionary = run.get("rows", {})
	var adapter := String(run.get("adapter", ""))
	var same_hardware := adapter == String(baseline.get("adapter", ""))
	if not same_hardware:
		out["notes"].append(
			("milliseconds are NOT compared: recorded on '%s', run on '%s'. "
			+ "A frame time without its hardware is not a number anyone can "
			+ "use (D-044 criterion 2).")
			% [String(baseline.get("adapter", "?")), adapter])

	var changed := false
	for key in fresh:
		var row: Dictionary = fresh[key]
		if not recorded.has(key):
			out["rows"].append({"squads": key, "state": "new", "counts": [],
				"times": []})
			out["notes"].append("no recorded row for %s squads" % key)
			continue
		var was: Dictionary = recorded[key]
		var count_deltas := []
		for name in GATED_COUNTS:
			var before = was.get(name, null)
			var after = row.get(name, null)
			if before == null or after == null:
				continue
			if int(before) != int(after):
				count_deltas.append({"what": name, "was": int(before),
					"now": int(after)})
		var time_deltas := []
		if same_hardware:
			for name in REPORTED_TIMES:
				var before := float(was.get(name, 0.0))
				var after := float(row.get(name, 0.0))
				if before <= 0.0:
					continue
				var pct := (after - before) / before * 100.0
				time_deltas.append({"what": name, "was": before, "now": after,
					"pct": pct, "notable": absf(pct) >= TIME_NOTICE_PCT})
		if not count_deltas.is_empty():
			changed = true
		out["rows"].append({"squads": key, "state": "compared",
			"counts": count_deltas, "times": time_deltas})

	if not out["stale"].is_empty():
		out["status"] = "stale"
	elif changed:
		out["status"] = "changed"
	return out


## The loud half. One string, so the caller prints it and CI captures it.
static func report(comparison: Dictionary) -> String:
	var lines := []
	var status := String(comparison.get("status", "unknown"))
	lines.append("bench-check: %s" % status.to_upper())

	for entry in comparison.get("stale", []):
		lines.append("  STALE  %-12s %s -> %s"
			% [entry["what"], entry["was"], entry["now"]])

	for row in comparison.get("rows", []):
		var squads := String(row.get("squads", "?"))
		if String(row.get("state", "")) == "new":
			lines.append("  NEW    %s squads — nothing recorded to compare" % squads)
			continue
		for delta in row.get("counts", []):
			lines.append("  COUNT  %s squads: %-13s %d -> %d"
				% [squads, delta["what"], delta["was"], delta["now"]])
		for delta in row.get("times", []):
			lines.append("  %s %s squads: %-13s %8.2f -> %8.2f  %+6.1f%%"
				% ["TIME! " if delta["notable"] else "time  ", squads,
					delta["what"], delta["was"], delta["now"], delta["pct"]])

	for note in comparison.get("notes", []):
		lines.append("  note   %s" % note)

	match status:
		"ok":
			lines.append("bench-check: every gated count matches the baseline.")
		"stale":
			lines.append("bench-check: the baseline was measured against a "
				+ "DIFFERENT tree. Re-record it (`just bench-record`) and say "
				+ "on what hardware — the numbers above are not comparable.")
		"changed":
			lines.append("bench-check: same map, same roster, same render "
				+ "path, and a DETERMINISTIC COUNT moved. That is either a "
				+ "render-path change nothing declared or a real defect.")
		_:
			lines.append("bench-check: nothing to compare against.")
	return "\n".join(lines)


## Exit code for `status`. Counts gate; milliseconds never do — a
## wall-clock gate on a shared host goes red with nothing wrong, which
## this project has already paid for once (D-106's amendment).
static func exit_code(comparison: Dictionary, strict_stale := false) -> int:
	match String(comparison.get("status", "unknown")):
		"changed":
			return 1
		"stale":
			return 1 if strict_stale else 0
		_:
			return 0
