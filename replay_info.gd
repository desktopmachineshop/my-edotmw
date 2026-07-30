extends SceneTree

## Inspect a replay (`just replay-info FILE`).
##
## D-016 calls the curve log "the primary desync-forensics tool". A log
## you cannot read is not a forensics tool, so this is the other half of
## that decision: it reads a replay back through the same StateCurve
## deserialization the client uses and reports what is in it.
##
## Exits non-zero on an unreadable or empty replay, so it doubles as a
## check that a run actually recorded something.

const DEFAULT_PATH := "res://artifacts/replay-4433.edmw"


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var path := String(args.get("file", DEFAULT_PATH))
	var at_time := float(args.get("at", -1.0))

	var replay := ReplayLog.read(path)
	if replay.is_empty():
		push_error("replay-info: %s is not a readable replay" % path)
		quit(1)
		return

	var records: Array = replay["records"]
	if records.is_empty():
		push_error("replay-info: %s contains no records" % path)
		quit(1)
		return

	var space := TorusSpace.new(int(replay["width"]), int(replay["height"]), float(replay["hex_size"]))
	var first_time := float(records[0]["time"])
	var last_time := float(records[records.size() - 1]["time"])

	# Not every record is a curve any more. M2 put composition (SQUAD_INFO)
	# and casualty/rout (SQUAD_COMBAT) records into the same log so a replay
	# can explain a battle (D-026 criterion 11), and neither of those
	# carries an `object_id` or a `curve` at all. This loop used to index
	# every record as though it were a curve install, which faults on the
	# first record a real M2 match writes — the server logs composition the
	# moment a player joins. Count each kind on its own terms instead.
	var objects := {}
	var keyframes := 0
	var curve_records := 0
	var info_records := 0
	var combat_records := 0
	var casualty_events := 0
	for record in records:
		match int(record.get("kind", ReplayLog.Kind.CURVE)):
			ReplayLog.Kind.CURVE:
				curve_records += 1
				objects[int(record["object_id"])] = true
				keyframes += (record["curve"] as StateCurve).key_count()
			ReplayLog.Kind.SQUAD_INFO:
				info_records += 1
			ReplayLog.Kind.COMBAT:
				combat_records += 1
				var combat: Dictionary = record.get("combat", {})
				casualty_events += (combat.get("events", []) as Array).size()

	print("replay-info: %s" % path)
	print("  map:      %dx%d cells, hex size %.2f, tick %.0f Hz" % [
		space.width, space.height, space.hex_size, float(replay["tick_hz"])])
	print("  records:  %d total covering %.1fs (t=%.1f to t=%.1f) — %d curve, %d composition, %d combat (%d casualty/rout events)" % [
		records.size(), last_time - first_time, first_time, last_time,
		curve_records, info_records, combat_records, casualty_events])
	print("  objects:  %d distinct, %d keyframes total (%.1f per curve record)" % [
		objects.size(), keyframes,
		float(keyframes) / float(maxi(curve_records, 1))])

	# Reconstructing state proves the log is a REPLAY and not just a dump:
	# the curves re-install in order and yield positions.
	var sample_at := last_time if at_time < 0.0 else at_time
	var state := ReplayLog.reconstruct_at(replay, sample_at)

	# The sentinel keys (see ReplayLog.reconstruct_at) carry squad
	# strength/rout state folded from SQUAD_INFO/SQUAD_COMBAT records —
	# everything else in `state` is squad_id -> StateCurve.
	var strengths: Dictionary = state.get(ReplayLog.STRENGTHS_KEY, {})
	var routed: Dictionary = state.get(ReplayLog.ROUTED_KEY, {})

	var curve_ids := []
	for key in state.keys():
		if key is int:
			curve_ids.append(key)

	print("  at t=%.1f: %d objects reconstructed" % [sample_at, curve_ids.size()])

	var shown := 0
	for object_id in curve_ids:
		if shown >= 5:
			break
		var curve: StateCurve = state[object_id]
		var alive_note := ""
		if strengths.has(object_id):
			alive_note = " alive=%d" % int(strengths[object_id])
			if bool(routed.get(object_id, false)):
				alive_note += " (routed)"
		print("    squad %d -> cell %s%s" % [object_id, curve.sample_cell(sample_at, space), alive_note])
		shown += 1
	if curve_ids.size() > shown:
		print("    ... and %d more" % (curve_ids.size() - shown))

	# Final squad strengths (D-016, D-026 criterion 11): this is what lets
	# a replay explain a battle, not just replay motion. The server's
	# replay is unclipped ground truth, so this covers every squad that
	# ever had a SQUAD_INFO or SQUAD_COMBAT record — including one that
	# never fought and so has no combat event at all.
	print("  final strengths (%d squads known):" % strengths.size())
	var strength_ids := strengths.keys()
	strength_ids.sort()
	for id in strength_ids:
		var note := " (routed)" if bool(routed.get(id, false)) else ""
		print("    squad %d: %d alive%s" % [id, int(strengths[id]), note])

	quit(0)


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
