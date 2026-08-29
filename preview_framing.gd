extends RefCounted
class_name PreviewFraming

## Where a preview camera has to stand to hold EVERYTHING it drew
## (#228).
##
## All-static and pure, the `hud_layout.gd`/`battle_line.gd` family:
## preview geometry that only lives inside a `*_preview.gd` scene is
## geometry nobody can test, and this particular arithmetic has been got
## wrong four times in one file. Each fix framed the grid that had just
## grown and left every other dimension of the scene hardcoded, so the
## next thing to grow fell off the edge again:
##
##   1. a camera distance tuned for four clip columns,
##   2. the building roster going from four to nine,
##   3. the gatherer's three work clips widening the sheet to seven,
##   4. #228 — the squad grid measured, the building row in front of it
##      not, so the largest building was cut by the frame.
##
## The lesson those four share is not "measure the buildings too". It is
## that a camera which is TOLD its extents can only ever hold the extents
## somebody remembered to tell it about. So the contract here takes an
## `AABB` of world-space content — whatever was actually placed, however
## many kinds of thing that was — and returns a camera position that
## PROVABLY contains it: `position_for` finishes by asking `covers`, and
## backs off until the answer is yes. A tenth building, a seventh clip and
## a prop nobody has thought of yet are all the same input.
##
## `covers` is the honest half. It is the frustum test a viewer performs,
## written once, so the framing function and its test ask the same
## question rather than two arithmetics that agree until they don't
## (D-096's shared-arithmetic rule).

## How much empty space to leave around the content, as a share of the
## content's own half-extent. Slack, not safety: `position_for` is
## correct with a margin of zero, and the margin only stops models
## touching the edge of the picture.
const DEFAULT_MARGIN := 0.18

## Backing-off search bounds. The analytic estimate is exact for a
## content box centred on the aim point; the search exists for the ones
## that are not — a building row in front of a squad grid is asymmetric
## in depth, and depth is what the pitch foreshortens.
const BACKOFF_STEP := 1.04
const BACKOFF_LIMIT := 200

## Composition: how many recentre-then-close-in passes to run, and how
## far each closing step reaches (as a share of the content's diagonal)
## before halving. Both are pure quality-of-picture — a preview framed by
## the estimate alone is correct and merely stands too far back.
const COMPOSE_PASSES := 3
const CLOSE_STEP := 0.25
const CLOSE_LIMIT := 40


## The camera basis for a preview that looks down at `pitch_deg` along -Z.
static func basis_for(pitch_deg: float) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), 0.0, 0.0))


## Where to stand to hold every corner of `content` in shot.
##
## Three steps, and every one of them ends at `covers`:
##
## 1. an analytic estimate from the box's half-extents, which is exact for
##    a box centred on the aim point;
## 2. a recentring pass, because the content of a preview is not centred
##    on anything in particular — a building row standing in FRONT of a
##    squad grid is asymmetric in depth, and depth is what the pitch
##    foreshortens; and
## 3. a closing-in pass, so the estimate being conservative costs pixels
##    on the models rather than being paid for in dead sky.
##
## The last good position is what is returned, so no step can hand back a
## camera that clips its own input. That is the property the four previous
## framings in `model_preview.gd` each lacked: each was arithmetic that
## looked right, verified by looking at the one roster that existed.
static func position_for(content: AABB, aspect: float, fov_deg := 62.0,
		pitch_deg := 27.0, margin := DEFAULT_MARGIN) -> Vector3:
	var padded := grown(content, margin)
	var centre := padded.get_center()
	var pitch := deg_to_rad(pitch_deg)
	var basis := basis_for(pitch_deg)
	var offset := Vector3(0.0, sin(pitch), cos(pitch))

	var half_v := deg_to_rad(fov_deg) * 0.5
	var half_h := atan(tan(half_v) * maxf(aspect, 0.01))
	var half := padded.size * 0.5
	# The vertical extent on screen is fed by the box's own height AND by
	# its depth, which the pitch tips towards the viewer.
	var for_width := half.x / maxf(tan(half_h), 0.01)
	var for_height := (half.y + half.z * sin(pitch)) / maxf(tan(half_v), 0.01)
	var distance := maxf(maxf(for_width, for_height), 0.001) + half.z * cos(pitch)

	var at := centre + offset * distance
	for _i in range(BACKOFF_LIMIT):
		if covers(padded, at, aspect, fov_deg, pitch_deg):
			break
		distance *= BACKOFF_STEP
		at = centre + offset * distance
	if not covers(padded, at, aspect, fov_deg, pitch_deg):
		return at

	for _pass in range(COMPOSE_PASSES):
		# Composed on the CONTENT, checked against the padded box: the
		# margin is slack around the picture, not part of the subject, and
		# centring on it puts the models off-centre by however much slack
		# happens to be configured.
		at = _recentred(content, padded, at, basis, aspect, fov_deg, pitch_deg)
		at = _closer(padded, at, basis, aspect, fov_deg, pitch_deg)
	return at


## Slide the camera across its own view plane until the content's
## projection is centred on it. Verified, and reverted if it is not: a
## recentring that pushed a corner off the edge would be the same class of
## mistake as the framing it is refining.
static func _recentred(content: AABB, padded: AABB, at: Vector3, basis: Basis,
		aspect: float, fov_deg: float, pitch_deg: float) -> Vector3:
	var view := Transform3D(basis, at).affine_inverse()
	var half_v := deg_to_rad(fov_deg) * 0.5
	var tan_v := tan(half_v)
	var tan_h := tan_v * maxf(aspect, 0.01)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var depth_total := 0.0
	for corner in corners(content):
		var local := view * corner
		var depth := -local.z
		if depth <= 0.001:
			return at
		depth_total += depth
		low.x = minf(low.x, local.x / (tan_h * depth))
		low.y = minf(low.y, local.y / (tan_v * depth))
		high.x = maxf(high.x, local.x / (tan_h * depth))
		high.y = maxf(high.y, local.y / (tan_v * depth))
	var mid := (low + high) * 0.5
	var depth_mean := depth_total / 8.0
	var moved := at 		+ basis.x * (mid.x * tan_h * depth_mean) 		+ basis.y * (mid.y * tan_v * depth_mean)
	if covers(padded, moved, aspect, fov_deg, pitch_deg):
		return moved
	return at


## Walk the camera in along its own view axis while the content still
## fits, so a conservative estimate does not cost the models their pixels.
static func _closer(padded: AABB, at: Vector3, basis: Basis, aspect: float,
		fov_deg: float, pitch_deg: float) -> Vector3:
	var forward := -basis.z
	var step := padded.size.length() * CLOSE_STEP
	var here := at
	for _i in range(CLOSE_LIMIT):
		var nearer := here + forward * step
		if not covers(padded, nearer, aspect, fov_deg, pitch_deg):
			step *= 0.5
			if step < padded.size.length() * 0.002:
				break
			continue
		here = nearer
	return here


## Is every corner of `content` inside the frustum of a camera standing
## at `at`, pitched down by `pitch_deg`?
##
## This is what a person looking at the PNG checks, and it is the only
## check that catches the class: every previous version of this framing
## was verified against the roster that existed when it was written.
static func covers(content: AABB, at: Vector3, aspect: float,
		fov_deg := 62.0, pitch_deg := 27.0) -> bool:
	var view := Transform3D(basis_for(pitch_deg), at).affine_inverse()
	var half_v := deg_to_rad(fov_deg) * 0.5
	var tan_v := tan(half_v)
	var tan_h := tan_v * maxf(aspect, 0.01)
	for corner in corners(content):
		var local := view * corner
		# Godot looks down its own -Z, so anything with local.z >= 0 is
		# behind the camera and cannot be in the picture at all.
		if local.z >= -0.001:
			return false
		var depth := -local.z
		if absf(local.x) > tan_h * depth or absf(local.y) > tan_v * depth:
			return false
	return true


## The eight corners of a box. Corners rather than the centre and a
## radius, because the content is a box and a sphere around it would
## demand a distance nothing in shot needs.
static func corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for x in [box.position.x, box.position.x + box.size.x]:
		for y in [box.position.y, box.position.y + box.size.y]:
			for z in [box.position.z, box.position.z + box.size.z]:
				out.append(Vector3(x, y, z))
	return out


## `content` with `margin` of its own half-extent added on every side.
static func grown(content: AABB, margin: float) -> AABB:
	var pad := content.size * 0.5 * maxf(margin, 0.0)
	# A degenerate axis (one building, one row) would otherwise grow by
	# nothing and leave the model touching the frame.
	pad = Vector3(maxf(pad.x, 0.05), maxf(pad.y, 0.05), maxf(pad.z, 0.05))
	return AABB(content.position - pad, content.size + pad * 2.0)
