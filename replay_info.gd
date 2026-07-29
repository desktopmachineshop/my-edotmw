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

	var objects := {}
	var keyframes := 0
	for record in records:
		objects[int(record["object_id"])] = true
		keyframes += (record["curve"] as StateCurve).key_count()

	print("replay-info: %s" % path)
	print("  map:      %dx%d cells, hex size %.2f, tick %.0f Hz" % [
		space.width, space.height, space.hex_size, float(replay["tick_hz"])])
	print("  records:  %d curve installations covering %.1fs (t=%.1f to t=%.1f)" % [
		records.size(), last_time - first_time, first_time, last_time])
	print("  objects:  %d distinct, %d keyframes total (%.1f per record)" % [
		objects.size(), keyframes, float(keyframes) / float(records.size())])

	# Reconstructing state proves the log is a REPLAY and not just a dump:
	# the curves re-install in order and yield positions.
	var sample_at := last_time if at_time < 0.0 else at_time
	var state := ReplayLog.reconstruct_at(replay, sample_at)
	print("  at t=%.1f: %d objects reconstructed" % [sample_at, state.size()])

	var shown := 0
	for object_id in state:
		if shown >= 5:
			break
		var curve: StateCurve = state[object_id]
		print("    squad %d -> cell %s" % [object_id, curve.sample_cell(sample_at, space)])
		shown += 1
	if state.size() > shown:
		print("    ... and %d more" % (state.size() - shown))

	quit(0)


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
