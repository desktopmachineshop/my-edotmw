extends RefCounted
class_name CorpseLedger

## Bookkeeping for the corpse layer (D-20260819-a-casualty-is-visible).
##
## Client-render-only state, like `SoldierMotion`: a corpse is a client's
## record of a replicated casualty event (D-006 clause 2 — nothing here is
## ever read back by simulation, and `tests/test_corpse_ledger.gd` scans
## the sources to keep it that way).
##
## ## Why the logic lives apart from the MultiMeshes it drives
##
## A headless MultiMesh stores nothing (the dummy RenderingServer, see
## D-20260817-fog-covers-props), so no GUT test can assert instance data.
## The half with the interesting failure modes — the cap, cross-bucket
## eviction, the falling set — is therefore pure bookkeeping here, tested
## headless, and the renderer applies the OPS this class returns without
## making any decisions of its own. The picture checks the renderer.
##
## ## The cap is a ring
##
## D-018-scale battles kill tens of thousands of men; the layer holds at
## most `max_corpses`, evicting the OLDEST when full. Corpses batch into
## one MultiMesh per (model, owner) — "bucket" — so evicting the oldest
## means a swap-remove in ITS bucket while the newcomer appends to its
## own; the ops describe both halves and the renderer replays them.
##
## ## The fall is derived, never accumulated
##
## `fall_phase(record, now) = clamp((now - time) / FALL_SECONDS)` — a pure
## function of the replicated event's arrival time and the clock, D-082's
## rule in different clothes. The shader's rate field is zero for every
## corpse; the renderer rewrites the phase float per FALLING corpse per
## frame from this formula and then never touches it again.

## How long the fall plays, in seconds. When the VAT gains its death clip
## this is that clip's duration; the tip-over fallback uses it identically.
const FALL_SECONDS := 1.1

## Default cap. Sized for one battlefield's worth of dead, not a match's:
## the decision's revisit trigger is visible churn during ONE battle.
const DEFAULT_MAX := 1536

var _max: int
# Oldest first. Each record: {"model": StringName, "owner": int,
# "xform": Transform3D, "time": float, "fog_uv": Vector2,
# "bucket": String, "index": int}.
var _order: Array = []
# bucket key -> Array of record references (the same dictionaries).
var _buckets := {}
# Records whose fall is still playing, oldest first.
var _falling: Array = []


func _init(max_corpses: int = DEFAULT_MAX) -> void:
	_max = maxi(1, max_corpses)


static func bucket_key(model: StringName, owner: int) -> String:
	return "%s|%d" % [model, owner]


## Record one fallen man. Returns the ops the renderer must apply, in
## order. Op shapes:
##   {"op": "set",    "bucket": key, "index": i, "record": r}
##   {"op": "shrink", "bucket": key, "count": n}
## An eviction that moves a survivor into the vacated slot emits a "set"
## for the moved record followed by a "shrink"; evicting a bucket's last
## entry emits only the "shrink".
func add(model: StringName, owner: int, xform: Transform3D, time: float,
		fog_uv: Vector2) -> Array:
	var ops := []
	if _order.size() >= _max:
		var oldest: Dictionary = _order.pop_front()
		_falling.erase(oldest)
		var old_bucket: Array = _buckets[String(oldest["bucket"])]
		var last: Dictionary = old_bucket.back()
		old_bucket.pop_back()
		if last != oldest:
			# The bucket's last record moves into the vacated slot so the
			# MultiMesh stays dense. Order within a bucket means nothing —
			# age lives in `_order`.
			last["index"] = int(oldest["index"])
			old_bucket[int(oldest["index"])] = last
			ops.append({"op": "set", "bucket": String(oldest["bucket"]),
				"index": int(last["index"]), "record": last})
		ops.append({"op": "shrink", "bucket": String(oldest["bucket"]),
			"count": old_bucket.size()})

	var key := bucket_key(model, owner)
	if not _buckets.has(key):
		_buckets[key] = []
	var bucket: Array = _buckets[key]
	var record := {
		"model": model, "owner": owner, "xform": xform, "time": time,
		"fog_uv": fog_uv, "bucket": key, "index": bucket.size(),
	}
	bucket.append(record)
	_order.append(record)
	_falling.append(record)
	ops.append({"op": "set", "bucket": key, "index": int(record["index"]),
		"record": record})
	return ops


## Phase of one record's fall at `now`, in [0, 1]. Pure.
static func fall_phase(record: Dictionary, now: float) -> float:
	return clampf((now - float(record["time"])) / FALL_SECONDS, 0.0, 1.0)


## The records whose fall the renderer must animate THIS frame. A record
## is returned once at phase 1.0 — its final, frozen frame — and then
## leaves the set, so a settled battlefield costs zero writes per frame.
func falling(now: float) -> Array:
	var out := []
	var keep := []
	for record in _falling:
		out.append(record)
		if fall_phase(record, now) < 1.0:
			keep.append(record)
	_falling = keep
	return out


func count() -> int:
	return _order.size()


func falling_count() -> int:
	return _falling.size()


## A bucket's full contents, for a renderer growing that bucket's
## MultiMesh — a grown MultiMesh starts blank, so everything is rewritten.
func bucket_records(key: String) -> Array:
	return _buckets.get(key, [])


func bucket_keys() -> Array:
	return _buckets.keys()
