extends RefCounted
class_name StateCurve

## A keyframed curve of object state over time (D-003).
##
## This is the unit of replication: object state is sent as curves, not
## per-tick snapshots, so an object that isn't changing costs zero
## bandwidth. See CurveReplicator for the gating/clipping/budgeting that
## sits on top.
##
## ## Why points are stored in CONTINUOUS UNWRAPPED axial space
##
## The obvious implementation stores world positions and lerps between
## them. On a torus that is wrong at exactly the moment it matters: two
## keyframes either side of a seam are numerically far apart, so the lerp
## sends the object sprinting the long way across the map instead of one
## step over the seam. This is D-008's "recurring tax" showing up in the
## netcode.
##
## Instead, append_cell() extends a continuous chain: each new point is
## the previous point plus the SHORTEST wrapped delta to the new cell. The
## stored values may drift outside [0,width)x[0,height) — that is the
## point. Interpolation in this space is always correct, and normalization
## happens only at the end, when sampling to a cell or to world space.

# Wire format sizes, kept explicit because the tests assert real byte
# counts rather than estimates (D-003's "zero bandwidth when idle" is
# only meaningful if measured).
const HEADER_BYTES := 2  # keyframe count, uint16
const KEYFRAME_BYTES := 12  # time float32 + axial q/r float32 pair

var _times := PackedFloat32Array()
var _points := PackedVector2Array()


func clear() -> void:
	_times = PackedFloat32Array()
	_points = PackedVector2Array()


func key_count() -> int:
	return _times.size()


func is_empty() -> bool:
	return _times.is_empty()


## Keyframe accessors. Formation needs to find the squad's last real
## movement to derive facing for a stopped squad, and doing that by
## scanning keyframes keeps the derivation a pure function of the curve
## rather than requiring stored facing state (D-006 clause 1).
func time_at(i: int) -> float:
	return _times[i]


func point_at(i: int) -> Vector2:
	return _points[i]


func start_time() -> float:
	return 0.0 if _times.is_empty() else _times[0]


func end_time() -> float:
	return 0.0 if _times.is_empty() else _times[_times.size() - 1]


## An object is idle when its curve pins it to one place — either a
## single keyframe, or several that never move it. Idle objects are what
## D-003's zero-bandwidth claim is about.
func is_idle() -> bool:
	if _points.size() <= 1:
		return true
	var first := _points[0]
	for i in range(1, _points.size()):
		if not _points[i].is_equal_approx(first):
			return false
	return true


## Append a keyframe at a grid cell, extending the continuous chain by
## the shortest wrapped delta. This is the append that callers should use.
func append_cell(time: float, cell: Vector2i, space: TorusSpace) -> void:
	if _points.is_empty():
		var c := space.normalize(cell)
		_append_raw(time, Vector2(float(c.x), float(c.y)))
		return

	var last := _points[_points.size() - 1]
	var last_cell := Vector2i(roundi(last.x), roundi(last.y))
	var d := space.delta(last_cell, cell)
	_append_raw(time, last + Vector2(float(d.x), float(d.y)))


## Append a point already expressed in continuous unwrapped axial space.
## Only correct if the caller has maintained chain continuity itself —
## prefer append_cell().
func append_axial(time: float, point: Vector2) -> void:
	_append_raw(time, point)


func _append_raw(time: float, point: Vector2) -> void:
	if not _times.is_empty() and time < _times[_times.size() - 1]:
		push_error("StateCurve keyframes must be appended in non-decreasing time order (got %f after %f)" % [time, _times[_times.size() - 1]])
		return
	_times.append(time)
	_points.append(point)


## Sample in continuous unwrapped axial space. Holds at both ends: before
## the first keyframe and after the last, the object is stationary.
func sample_axial(t: float) -> Vector2:
	if _points.is_empty():
		return Vector2.ZERO
	if t <= _times[0]:
		return _points[0]
	var last_index := _times.size() - 1
	if t >= _times[last_index]:
		return _points[last_index]

	for i in range(last_index):
		var t0 := _times[i]
		var t1 := _times[i + 1]
		if t >= t0 and t <= t1:
			var span := t1 - t0
			if span <= 0.0:
				return _points[i + 1]
			return _points[i].lerp(_points[i + 1], (t - t0) / span)
	return _points[last_index]


## Sample to a wrapped grid cell.
##
## Through `TorusSpace.round_axial`, which is the project's one answer to
## "which hex is this fractional axial coordinate in" and what
## `world_to_cell` has always used. This used to round each component with
## `roundi`, which partitions the plane into RHOMBI rather than hexagons —
## a different answer over about a quarter of every cell's area
## (D-20260818, amended for #101).
##
## Nothing had ever caught it because nothing was ever between cells
## anywhere but on a lattice line: a curve's keyframes were cell centres
## and the segment between two of them ran along one of the six lattice
## directions, where the two roundings agree everywhere except the exact
## midpoint. Smoothing a path takes a squad OFF those lines, and the
## disagreement stops being a single point and becomes a region — a squad
## rounding an obstacle read as standing INSIDE it while its own line was
## a clear cell away.
func sample_cell(t: float, space: TorusSpace) -> Vector2i:
	return space.normalize(space.round_axial(sample_axial(t)))


## Sample to a world position. Uses the continuous value, so an object
## crossing a seam moves smoothly rather than teleporting — the wrap is
## applied to the coordinate, not to the rendered motion.
func sample_world(t: float, space: TorusSpace, y: float = 0.0) -> Vector3:
	var p := sample_axial(t)
	var wrapped_q := fposmod(p.x, float(space.width))
	var wrapped_r := fposmod(p.y, float(space.height))
	return Vector3(
		space.hex_size * TorusSpace.SQRT_3 * (wrapped_q + wrapped_r * 0.5),
		y,
		space.hex_size * 1.5 * wrapped_r
	)


## A copy covering only [from_time, to_time].
##
## This is D-003's mandatory clip, and it is the anti-intent-leakage
## mechanism: keyframes past `to_time` are DROPPED, not merely ignored, so
## a client that inspects the raw packet still cannot read where an enemy
## squad intends to be after the horizon.
##
## Endpoints are interpolated so the clipped curve agrees exactly with
## the original everywhere inside the window.
func clipped(from_time: float, to_time: float) -> StateCurve:
	var out := StateCurve.new()
	if _points.is_empty() or to_time < from_time:
		return out

	# Intersect the requested window with the curve's own extent.
	var window_start := maxf(from_time, start_time())
	var window_end := minf(to_time, end_time())

	# No overlap: the curve is entirely before or entirely after the
	# window, so the object is stationary for its whole duration. Sampling
	# rather than taking _points[-1] matters — it holds the FIRST value
	# for a curve that hasn't started yet, and the last for one that has
	# already finished.
	if window_end < window_start:
		out._append_raw(from_time, sample_axial(from_time))
		return out

	# Anchor the window. Without this the clipped curve loses its starting
	# position whenever a keyframe sits exactly on `from_time` — which is
	# the common case, since the sim emits a keyframe on the same tick
	# boundary the replicator clips at.
	out._append_raw(window_start, sample_axial(window_start))

	for i in range(_times.size()):
		var t := _times[i]
		if t > window_start and t < window_end:
			out._append_raw(t, _points[i])

	if window_end > window_start:
		out._append_raw(window_end, sample_axial(window_end))

	return out


func duplicate_curve() -> StateCurve:
	var out := StateCurve.new()
	out._times = _times.duplicate()
	out._points = _points.duplicate()
	return out


## Wire encoding. Also the replay format (D-016) — replays are the curve
## log, so there is deliberately only one serialization to keep them from
## drifting apart.
func to_bytes() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u16(_times.size())
	for i in range(_times.size()):
		buf.put_float(_times[i])
		buf.put_float(_points[i].x)
		buf.put_float(_points[i].y)
	return buf.data_array


static func from_bytes(data: PackedByteArray) -> StateCurve:
	var out := StateCurve.new()
	if data.size() < HEADER_BYTES:
		return out
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var count := buf.get_u16()
	for i in range(count):
		var t := buf.get_float()
		var q := buf.get_float()
		var r := buf.get_float()
		out._append_raw(t, Vector2(q, r))
	return out


func byte_size() -> int:
	return HEADER_BYTES + _times.size() * KEYFRAME_BYTES
