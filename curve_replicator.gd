extends RefCounted
class_name CurveReplicator

## The replication layer over StateCurve (D-003), and the thing M1 exists
## to prove. It enforces three properties that the curve type alone
## cannot:
##
##  1. **Zero bandwidth when idle.** Sending is gated on a per-object
##     version plus how much of the curve a client already holds. An
##     object whose curve has not changed and whose window is fully
##     delivered produces literally zero bytes, tick after tick.
##
##  2. **No intent leakage.** Every curve is clipped to [now, now +
##     horizon] before transmission. A client cannot read an enemy's
##     future path out of the raw packet, because those keyframes were
##     never in it. D-003 calls this out as a specific failure mode of
##     naive curve replication, and it is why clipping is mandatory
##     rather than an optimization.
##
##  3. **Bounded cost under invalidation storms.** Re-pathing many squads
##     at once (a large engagement) invalidates many curves in the same
##     tick. Sending them all immediately is a bandwidth spike; D-003
##     requires a budgeted, prioritized scheduler instead. Priority is
##     least-recently-sent-first, which is starvation-free: an object
##     that loses arbitration keeps ageing until it wins.
##
## Fog of war rides on this rather than being a separate system (D-004):
## `collect_for_client` is passed the set of objects a client can see, and
## anything outside it is simply not replicated.

const PACKET_HEADER_BYTES := 6  # object id uint32 + version uint16

## How far ahead of `now` a client is allowed to see. D-003's bounded
## lookahead: also the anti-intent-leakage knob.
var horizon_seconds: float = 1.0

## Per-client, per-tick send budget in bytes. The invalidation-storm
## safety valve.
var byte_budget_per_tick: int = 4096

# object_id -> StateCurve
var _curves := {}
# object_id -> int
var _versions := {}
# client_id -> { object_id -> { "version": int, "until": float, "last_sent": float } }
var _delivery := {}

# Observability — M1's exit criteria require the invalidation-storm cost
# to be measured, not asserted (D-003 consequences).
var bytes_sent_total: int = 0
var packets_sent_total: int = 0
var budget_overruns: int = 0


func object_count() -> int:
	return _curves.size()


func has_object(object_id: int) -> bool:
	return _curves.has(object_id)


## Install or replace an object's curve. Bumps the version, which is what
## makes the object a candidate for replication on the next collect.
## Callers should only call this when the curve actually changed —
## re-setting an identical curve costs bandwidth for nothing.
func set_curve(object_id: int, curve: StateCurve) -> void:
	_curves[object_id] = curve
	_versions[object_id] = int(_versions.get(object_id, 0)) + 1


func get_curve(object_id: int) -> StateCurve:
	return _curves.get(object_id, null)


func version_of(object_id: int) -> int:
	return int(_versions.get(object_id, 0))


func remove_object(object_id: int) -> void:
	_curves.erase(object_id)
	_versions.erase(object_id)
	for client_id in _delivery:
		_delivery[client_id].erase(object_id)


func forget_client(client_id: int) -> void:
	_delivery.erase(client_id)


func _client_records(client_id: int) -> Dictionary:
	if not _delivery.has(client_id):
		_delivery[client_id] = {}
	return _delivery[client_id]


## How much of this object's curve the client needs to hold right now:
## the end of the horizon window, or the end of the curve, whichever
## comes first.
func _needed_until(curve: StateCurve, now: float) -> float:
	return minf(curve.end_time(), now + horizon_seconds)


## Collect the packets to send to one client this tick.
##
## `visible_ids` is the fog-of-war gate (D-004) — objects outside it are
## not replicated and, importantly, their delivery records are dropped, so
## that re-entering vision resends rather than silently assuming the
## client still holds a stale curve. Which of D-004's three reveal
## semantics applies (pop-in / catch-up curve / stale ghost) is still
## open, but all three require the resend; they differ only in what the
## client does with it.
##
## Returns an array of { "id": int, "version": int, "bytes": PackedByteArray }.
func collect_for_client(client_id: int, now: float, visible_ids: Array) -> Array:
	var records := _client_records(client_id)

	var visible := {}
	for id in visible_ids:
		visible[id] = true

	# Drop records for anything no longer visible or no longer existing.
	for tracked_id in records.keys():
		if not visible.has(tracked_id) or not _curves.has(tracked_id):
			records.erase(tracked_id)

	# Candidates: visible objects whose delivered state is behind.
	var candidates := []
	for id in visible:
		if not _curves.has(id):
			continue
		var curve: StateCurve = _curves[id]
		var version := version_of(id)
		var needed_until := _needed_until(curve, now)

		var record = records.get(id, null)
		if record == null:
			candidates.append(id)
		elif int(record["version"]) != version:
			candidates.append(id)
		elif float(record["until"]) < needed_until - 0.0001:
			# The client holds a valid but expiring window; extend it.
			candidates.append(id)

	# Least-recently-sent first. Starvation-free under a storm: anything
	# that loses arbitration this tick has an older last_sent next tick.
	candidates.sort_custom(func(a, b):
		var ra = records.get(a, null)
		var rb = records.get(b, null)
		var ta: float = -INF if ra == null else float(ra["last_sent"])
		var tb: float = -INF if rb == null else float(rb["last_sent"])
		if ta == tb:
			return a < b  # deterministic tiebreak; replays must reproduce
		return ta < tb
	)

	var packets := []
	var spent := 0

	for id in candidates:
		var curve: StateCurve = _curves[id]
		var clipped := curve.clipped(now, now + horizon_seconds)
		var payload := _encode_packet(id, version_of(id), clipped)

		if spent + payload.size() > byte_budget_per_tick:
			# A single packet larger than the entire budget would never be
			# sendable, so let the first one through and record the
			# overrun rather than deadlocking that object forever.
			if packets.is_empty() and payload.size() > byte_budget_per_tick:
				budget_overruns += 1
			else:
				break

		packets.append({"id": id, "version": version_of(id), "bytes": payload})
		spent += payload.size()

		records[id] = {
			"version": version_of(id),
			"until": _needed_until(curve, now),
			"last_sent": now,
		}

	bytes_sent_total += spent
	packets_sent_total += packets.size()
	return packets


func _encode_packet(object_id: int, version: int, curve: StateCurve) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(object_id)
	buf.put_u16(version)
	buf.put_data(curve.to_bytes())
	return buf.data_array


## Total bytes in a packet list — the measurement the M1 exit criteria
## are stated in terms of.
static func total_bytes(packets: Array) -> int:
	var total := 0
	for p in packets:
		total += (p["bytes"] as PackedByteArray).size()
	return total


## Decode on the client side. Returns { "id", "version", "curve" }.
static func decode_packet(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var id := buf.get_u32()
	var version := buf.get_u16()
	var rest := data.slice(PACKET_HEADER_BYTES)
	return {"id": id, "version": version, "curve": StateCurve.from_bytes(rest)}
