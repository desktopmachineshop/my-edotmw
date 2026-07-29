extends RefCounted
class_name ReplayLog

## Replays are the curve log (D-016) — not a separate recording system.
##
## Because D-003 already expresses all object state as curves, capturing a
## match is just writing down each curve as it is installed, plus the time
## it was installed at. Playback re-installs them in order. That makes
## replay capture nearly free, which is why D-016 adopts it from M1 rather
## than deferring it: it is the primary desync-forensics tool exactly when
## netcode bugs are most likely.
##
## The serialization is StateCurve's own `to_bytes`, deliberately. One
## format for the wire and the replay means a replay cannot drift into
## describing something the network never sent.

const MAGIC := "EDMWRPL1"
const HEADER_BYTES := 8 + 4 + 4 + 4 + 4  # magic + hz + width + height + hex_size

var _file: FileAccess = null
var records_written: int = 0


## Begin recording. Returns OK, or an error code — a replay that cannot
## be opened must not silently do nothing, since its absence would only
## be discovered when someone needs it to debug a desync.
func open_for_write(path: String, tick_hz: float, space: TorusSpace) -> Error:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			push_error("ReplayLog: could not create %s (error %d)" % [dir, err])
			return err

	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		var err := FileAccess.get_open_error()
		push_error("ReplayLog: could not open %s for writing (error %d)" % [path, err])
		return err

	_file.store_buffer(MAGIC.to_utf8_buffer())
	_file.store_float(tick_hz)
	_file.store_32(space.width)
	_file.store_32(space.height)
	_file.store_float(space.hex_size)
	records_written = 0
	return OK


func is_open() -> bool:
	return _file != null


## Record one curve installation.
func record(at_time: float, object_id: int, version: int, curve: StateCurve) -> void:
	if _file == null:
		return
	var payload := curve.to_bytes()
	_file.store_float(at_time)
	_file.store_32(object_id)
	_file.store_16(version)
	_file.store_32(payload.size())
	_file.store_buffer(payload)
	records_written += 1


func close() -> void:
	if _file != null:
		_file.close()
		_file = null


## Read a replay back. Returns
## { "tick_hz", "width", "height", "hex_size", "records": [ {time,
## object_id, version, curve} ] }, or an empty dictionary if the file is
## missing or not a replay.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ReplayLog.read: no such file %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ReplayLog.read: could not open %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}

	var magic := file.get_buffer(MAGIC.length()).get_string_from_utf8()
	if magic != MAGIC:
		push_error("ReplayLog.read: %s is not a replay (bad magic '%s')" % [path, magic])
		return {}

	var out := {
		"tick_hz": file.get_float(),
		"width": file.get_32(),
		"height": file.get_32(),
		"hex_size": file.get_float(),
		"records": [],
	}

	while file.get_position() < file.get_length():
		var at_time := file.get_float()
		var object_id := file.get_32()
		var version := file.get_16()
		var length := file.get_32()
		# A truncated tail means the match was killed mid-write (Ctrl-C on
		# a load test, a crashed server). Stop cleanly and keep what we
		# have — a partial replay of a crash is the interesting case.
		if length < 0 or file.get_position() + length > file.get_length():
			break
		var payload := file.get_buffer(length)
		out["records"].append({
			"time": at_time,
			"object_id": object_id,
			"version": version,
			"curve": StateCurve.from_bytes(payload),
		})

	file.close()
	return out


## Rebuild the world state a replay describes at a given time, as
## object_id -> StateCurve. This is what makes it a replay rather than a
## log: the same curves, re-installed in the same order.
static func reconstruct_at(replay: Dictionary, at_time: float) -> Dictionary:
	var state := {}
	if not replay.has("records"):
		return state
	for record in replay["records"]:
		if float(record["time"]) <= at_time:
			state[int(record["object_id"])] = record["curve"]
	return state
