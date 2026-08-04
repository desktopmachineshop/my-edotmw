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
##
## ## M2 addendum (D-024, D-026 criterion 11)
##
## Combat makes squad composition change *during* a run for the first
## time, so the replay now also carries composition (SQUAD_INFO) and
## casualty/rout events (SQUAD_COMBAT), using NetProtocol's own encoders —
## there is exactly one definition of each wire shape, used by the server,
## the client, and the replay alike (see record_squad_info/record_combat).
## The replay logs the FULL, unfiltered stream regardless of any client's
## fog of war: it is deliberately ground truth, "what fog hid from every
## client", not what a client happened to see (server.gd's
## _broadcast_squad_info and SquadSim's own combat logging both pass the
## unfiltered set here, never a visible_to() subset).
##
## The on-disk format bumped MAGIC "EDMWRPL1" -> "EDMWRPL2" because every
## record now carries a leading `kind` byte, so a reader knows whether a
## record's payload is a curve install, a composition broadcast, or a
## combat event before it decodes the payload.

const MAGIC := "EDMWRPL2"
const HEADER_BYTES := 8 + 4 + 4 + 4 + 4  # magic + hz + width + height + hex_size

# Fixed portion of every record: kind (u8) + at_time (float32) +
# payload_size (u32).
const RECORD_HEADER_BYTES := 1 + 4 + 4

## SEATS records who played as whom (D-046 criterion 11). Appended as a
## new kind rather than folded into the header: a reader that predates it
## skips an unknown kind by its length prefix, so old replays stay
## readable and new ones do not need a format version bump.
enum Kind { CURVE = 0, SQUAD_INFO = 1, COMBAT = 2, BUILDING_INFO = 3, SEATS = 4 }

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


## Record one curve installation. Payload mirrors CurveReplicator's own
## wire packet shape (object id + version + curve bytes) so the curve
## portion of a replay record is recognisably the same thing that went
## out over the network, just wrapped in this format's own record header.
func record(at_time: float, object_id: int, version: int, curve: StateCurve) -> void:
	if _file == null:
		return
	var payload := StreamPeerBuffer.new()
	payload.put_u32(object_id)
	payload.put_u16(version)
	payload.put_data(curve.to_bytes())
	_write_record(Kind.CURVE, at_time, payload.data_array)


## Record a SQUAD_INFO broadcast verbatim — the server's full, unfiltered
## composition, not any one client's clipped view (D-026 criterion 11).
## `wire_bytes` must be exactly NetProtocol.encode_squad_info(...)'s
## output; there is no second encoding of this shape in this file.
func record_squad_info(at_time: float, wire_bytes: PackedByteArray) -> void:
	_write_record(Kind.SQUAD_INFO, at_time, wire_bytes)


## Record a SQUAD_COMBAT (casualty/rout) event verbatim. `wire_bytes` must
## be exactly NetProtocol.encode_squad_combat(...)'s output, for the same
## reason as record_squad_info above.
func record_combat(at_time: float, wire_bytes: PackedByteArray) -> void:
	_write_record(Kind.COMBAT, at_time, wire_bytes)


## Record a BUILDING_INFO broadcast verbatim (D-016, D-027 criterion 18).
## Same discipline as the two above: NetProtocol's own encoding, and the
## server's FULL unfiltered view rather than any one client's — a replay
## is ground truth, including what fog hid from everybody.
func record_building_info(at_time: float, wire_bytes: PackedByteArray) -> void:
	_write_record(Kind.BUILDING_INFO, at_time, wire_bytes)


func _write_record(kind: int, at_time: float, payload: PackedByteArray) -> void:
	if _file == null:
		return
	_file.store_8(kind)
	_file.store_float(at_time)
	_file.store_32(payload.size())
	_file.store_buffer(payload)
	records_written += 1
	# Flush every record, not just on close().
	#
	# `docker compose stop` (used by test-load to collect the server's
	# shutdown summary, and how any real deployment eventually stops the
	# process) sends SIGTERM. Godot headless does not run `_exit_tree` for
	# SIGTERM — server.gd's own comment above `_print_summary` documents
	# this exact behaviour — so `close()` never runs and anything sitting
	# in FileAccess's internal write buffer past the last flush is lost.
	# Composition (SQUAD_INFO) and combat (SQUAD_COMBAT) records are
	# written strictly after the curve records that describe a squad's
	# march (see the M2 addendum above this class), so a lost tail is
	# precisely the casualty/rout history D-026 criterion 11 needs a
	# replay to explain a battle at all — losing "the last few curve
	# keyframes" would be an inconvenience; losing "who won" is not.
	#
	# At 10 Hz (D-020) this is at most one flush per tick per active
	# record-producing event, and idle squads already cost zero records
	# (D-003) — so this does not turn a 10 Hz tick into a 10 Hz fsync of
	# unrelated data, only a flush of whatever this call actually wrote.
	# A load-test run's own measured recipe (`just test-load`, which
	# prints µs/squad-update) is the place to notice if this ever becomes
	# a real cost; until it does, durability wins the tradeoff outright,
	# per this defect's own instruction to err toward not losing the tail.
	_file.flush()


func close() -> void:
	if _file != null:
		_file.close()
		_file = null


## Read a replay back. Returns
## { "tick_hz", "width", "height", "hex_size", "records": [ {time, kind,
## ...} ] }, or an empty dictionary if the file is missing or not a
## replay. Each record's extra fields depend on `kind`:
##   CURVE      -> object_id, version, curve (a StateCurve)
##   SQUAD_INFO -> squad_info (decoded NetProtocol.decode_squad_info array)
##   COMBAT     -> combat (decoded NetProtocol.decode_squad_combat dict)
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
		# A truncated tail means the match was killed mid-write (Ctrl-C on
		# a load test, a crashed server). Stop cleanly and keep what we
		# have — a partial replay of a crash is the interesting case.
		if file.get_position() + RECORD_HEADER_BYTES > file.get_length():
			break

		var kind := file.get_8()
		var at_time := file.get_float()
		var length := file.get_32()
		if length < 0 or file.get_position() + length > file.get_length():
			break
		var payload := file.get_buffer(length)

		var record := {"time": at_time, "kind": kind}
		match kind:
			Kind.CURVE:
				if payload.size() < 6:
					break
				var buf := StreamPeerBuffer.new()
				buf.data_array = payload
				record["object_id"] = buf.get_u32()
				record["version"] = buf.get_u16()
				record["curve"] = StateCurve.from_bytes(payload.slice(6))
			Kind.SQUAD_INFO:
				record["squad_info"] = NetProtocol.decode_squad_info(payload)
			Kind.COMBAT:
				record["combat"] = NetProtocol.decode_squad_combat(payload)
			Kind.BUILDING_INFO:
				record["buildings"] = NetProtocol.decode_building_info(payload)
			Kind.SEATS:
				record["seats"] = decode_seats(payload)
			_:
				pass  # Unknown kind: keep the record's time/kind, decode nothing.

		out["records"].append(record)

	file.close()
	return out


# Sentinel keys folded into reconstruct_at()'s return dictionary alongside
# integer squad ids. A squad id is always a non-negative int, so these
# String keys can never collide with one — which is what lets this stay
# the SAME dictionary shape the M1 callers already index by squad id
# (state[id] as StateCurve) rather than a new nested return shape.
const STRENGTHS_KEY := "__strengths__"
const ROUTED_KEY := "__routed__"

## Buildings get their own top-level key rather than sharing the numeric
## keyspace with squads (D-029). Building wire ids are offset far above
## squad ids so they could not collide anyway, but relying on that inside
## a dictionary that also holds squad curves would make the offset
## load-bearing in a second place. One numeric keyspace per dictionary.
const BUILDINGS_KEY := "__buildings__"


## Rebuild the world state a replay describes at a given time.
##
## Returns squad_id -> StateCurve for every curve installed by `at_time`,
## exactly as this returned before M2 — plus two sentinel entries that
## cannot collide with a squad id: STRENGTHS_KEY (squad_id -> alive int)
## and ROUTED_KEY (squad_id -> bool), folded from SQUAD_INFO/SQUAD_COMBAT
## records in the order they were written (already chronological, since
## write order is tick order). This is what lets a replay explain a
## battle — reporting final strengths, not just final positions — without
## changing the shape every M1-era caller already relies on (D-026
## criterion 11).
static func reconstruct_at(replay: Dictionary, at_time: float) -> Dictionary:
	var state := {}
	var strengths := {}
	var routed := {}
	var buildings := {}
	if not replay.has("records"):
		return state

	for record in replay["records"]:
		if float(record["time"]) > at_time:
			continue
		match int(record.get("kind", Kind.CURVE)):
			Kind.CURVE:
				if record.has("curve"):
					state[int(record["object_id"])] = record["curve"]
			Kind.SQUAD_INFO:
				for entry in (record.get("squad_info", []) as Array):
					strengths[int(entry["id"])] = int(entry["alive"])
			Kind.COMBAT:
				var combat: Dictionary = record.get("combat", {})
				for event in (combat.get("events", []) as Array):
					strengths[int(event["id"])] = int(event["alive"])
					routed[int(event["id"])] = bool(event["routed"])
			Kind.BUILDING_INFO:
				for entry in (record.get("buildings", []) as Array):
					buildings[int(entry["id"])] = entry

	state[STRENGTHS_KEY] = strengths
	state[ROUTED_KEY] = routed
	state[BUILDINGS_KEY] = buildings
	return state


## Record who is playing as which civilisation and on whose side (D-046
## criterion 11, D-047, D-050).
##
## Written once, when the match starts — which is the first moment it is
## knowable, because a seat may have said "Random" until then (D-048). A
## replay that reconstructed the battle but not who fought it would
## answer "what happened" and not "who won", and with asymmetric civs the
## second question is most of the first.
func record_seats(at_time: float, seats: Array) -> void:
	var payload := StreamPeerBuffer.new()
	payload.put_u32(seats.size())
	for seat in seats:
		payload.put_u32(int(seat["player"]))
		payload.put_u8(int(seat.get("team", 0)))
		var civ := String(seat["civ"]).to_utf8_buffer()
		payload.put_u16(civ.size())
		payload.put_data(civ)
		var name := String(seat["name"]).to_utf8_buffer()
		payload.put_u16(name.size())
		payload.put_data(name)
	_write_record(Kind.SEATS, at_time, payload.data_array)


## Read a SEATS payload back.
static func decode_seats(payload: PackedByteArray) -> Array:
	var buf := StreamPeerBuffer.new()
	buf.data_array = payload
	var count := int(buf.get_u32())
	var out := []
	for _i in range(count):
		var player := int(buf.get_u32())
		var team := int(buf.get_u8())
		var civ_bytes: PackedByteArray = buf.get_data(buf.get_u16())[1]
		var name_bytes: PackedByteArray = buf.get_data(buf.get_u16())[1]
		out.append({
			"player": player, "team": team,
			"civ": civ_bytes.get_string_from_utf8(),
			"name": name_bytes.get_string_from_utf8(),
		})
	return out
