extends RefCounted
class_name WallRun

## Where the segments of a continuously-placed wall run actually go (D-096).
##
## All-static and pure, for exactly the reason `render_cull.gd` and
## `selection_pick.gd` are: the client that USES this needs a GPU and a live
## server, and the arithmetic that decides whether a wall ends up with a
## hole in it needs neither. That arithmetic is the half worth testing, so
## it lives somewhere it can be.
##
## A run is described in WORLD space — the two points the player dragged
## between — and comes back as one entry per segment, each carrying exactly
## what a build order needs: the anchor cell it is filed under, the
## continuous facing byte, and the sub-cell offset saying where inside that
## cell it truly stands.
##
## Wrap-awareness is not optional here (D-008). A run near a seam has two
## endpoints whose raw coordinates differ by nearly a whole map, and taking
## the naive difference would lay a wall right across the world.


## Shortest world-space vector from `from` to `to` across the torus.
##
## Ghost-copy comparison over the same lattice offsets rendering already
## uses, rather than a second wrap implementation to keep in step.
static func shortest_delta(space: TorusSpace, from: Vector3, to: Vector3) -> Vector3:
	var best := to - from
	for offset in space.lattice_offsets():
		var candidate := (to + offset) - from
		if candidate.length_squared() < best.length_squared():
			best = candidate
	return best


## Where a world point sits relative to its own cell's centre.
##
## Measured across the seam rather than through it, for the same reason as
## above: a point just past the wrap belongs to a cell whose canonical
## centre is a map away, and the raw difference would be a garbage offset
## rather than a sub-cell one.
static func offset_in_cell(space: TorusSpace, point: Vector3) -> Vector2:
	var centre := space.to_world(space.world_to_cell(point))
	var best := point - centre
	for offset in space.lattice_offsets():
		var candidate := (point + offset) - centre
		if candidate.length_squared() < best.length_squared():
			best = candidate
	return Vector2(best.x, best.z)


## One entry per segment of the run, ordered from `from` to `to`.
##
## Segments are laid END TO END at the def's own length — fixed spacing,
## always — and the run simply runs past the release point by whatever the
## last segment does not use.
##
## The first version distributed them evenly across the dragged length
## instead, so the spacing came out as `length / count` rather than one
## segment. That is only equal to a segment length when the drag happens to
## divide evenly; the rest of the time it stretches every joint in the run
## by the same small amount, which reads as a wall built out of separated
## pieces. Reported from play as segments "spaced rather than fixed
## spacing". Uniform-but-wrong spacing is worse than an untidy end: the end
## is one place a player can see and accept, while a stretched joint is a
## defect repeated the whole way along.
##
## `ceil`, not `round`, so the run always COVERS the line that was drawn.
## Rounding down would leave the last stretch of a dragged line with no
## wall on it at all — a hole exactly where the player last aimed, which is
## the failure D-096 exists to prevent.
static func segments(space: TorusSpace, def: BuildingDef,
		from: Vector3, to: Vector3) -> Array:
	var out := []
	if space == null or def == null:
		return out

	var delta := shortest_delta(space, from, to)
	delta.y = 0.0
	var length := delta.length()
	var segment_length := def.mesh_size.x
	if segment_length <= 0.01:
		segment_length = space.hex_size * TorusSpace.SQRT_3

	# A click rather than a drag: one segment, standing exactly where it was
	# put. THIS is the case that makes a single wall freely placed instead of
	# snapped back to the centre of whatever cell it landed in.
	if length < segment_length * 0.5:
		out.append(entry(space, from, 0.0))
		return out

	var direction := delta / length
	# Matches client.gd's `_angle_of_offset`, which is the convention the
	# renderer and `BuildingSim.span_cells` both already assume: with this
	# as rotation.y, the mesh's local +X — a wall segment's long axis —
	# points along `direction`.
	var angle := atan2(-direction.z, direction.x)

	var count := maxi(1, int(ceil(length / segment_length - 0.001)))
	for i in range(count):
		# The i-th segment's CENTRE: half a segment in, then one whole
		# segment per step. This is what makes consecutive segments touch
		# exactly, independent of how long the drag happened to be.
		var along := (float(i) + 0.5) * segment_length
		out.append(entry(space, from + direction * along, angle))
	return out


## The best place to ATTACH a new wall to the walls already standing, or
## `found = false` if nothing is near enough (D-096 follow-up).
##
## `walls` is [{"pos": Vector3, "angle": float, "length": float}] — every
## existing wall-family segment's true centre, rotation and length.
##
## Attaches to the nearest point ANYWHERE ALONG an existing segment, not
## just its two ends. Ends alone would be the obvious implementation and it
## is not what a player wants: running a spur off the middle of a long
## curtain wall is an ordinary thing to do, and having it refuse to connect
## unless you found an endpoint would make walls feel like they only join
## where the geometry happens to be divided.
##
## Returns the attach point, the angle of the wall attached to (so a new
## piece can default to CONTINUING that run rather than to some arbitrary
## direction), and whether the attach point is at one of that wall's ends.
static func nearest_attach(space: TorusSpace, walls: Array, point: Vector3,
		max_distance: float) -> Dictionary:
	var best := {"found": false, "point": point, "angle": 0.0, "at_end": false}
	var best_distance := max_distance
	for wall in walls:
		var centre: Vector3 = wall["pos"]
		var angle: float = wall["angle"]
		var half: float = float(wall["length"]) * 0.5
		var direction := Vector3(cos(angle), 0.0, -sin(angle))
		# Wrap-aware: a wall just across the seam is a legitimate thing to
		# attach to, and the raw difference would put it a map away.
		var to_point := shortest_delta(space, centre, point)
		to_point.y = 0.0
		var along := clampf(to_point.dot(direction), -half, half)
		var attach := centre + direction * along
		var distance := (to_point - direction * along).length()
		if distance < best_distance:
			best_distance = distance
			best = {
				"found": true,
				"point": attach,
				"angle": angle,
				# Within a hair of the end, so a caller can tell "extend
				# this run" from "branch off its middle" if it wants to.
				"at_end": absf(absf(along) - half) < 0.05,
			}
	return best


## Where a SINGLE wall placed at `cursor` should stand, given the walls
## already up — the whole snap decision, in one testable place.
##
## This lived in `client.gd` and could therefore only be checked by playing
## the game, which is exactly how it shipped broken three times running.
## The client now calls this and does nothing else, so what a player sees
## when they click is a thing a test can assert on.
##
## `chosen_facing` is the player's scroll-wheel angle, or -1 for "no
## preference" — in which case a snapped wall CONTINUES the run it attached
## to and an unsnapped one points east.
static func place_single(space: TorusSpace, def: BuildingDef, walls: Array,
		cursor: Vector3, chosen_facing: int, snap_distance: float) -> Dictionary:
	var attach := nearest_attach(space, walls, cursor, snap_distance)

	var facing := chosen_facing
	if facing < 0:
		facing = PlacementJitter.byte_of_radians(float(attach["angle"])) \
			if bool(attach["found"]) else 0
	var angle := PlacementJitter.radians_of_byte(facing)

	var centre := cursor
	if bool(attach["found"]):
		var half := def.mesh_size.x * 0.5
		if half <= 0.01:
			half = space.hex_size * TorusSpace.SQRT_3 * 0.5
		var direction := Vector3(cos(angle), 0.0, -sin(angle))
		# Extend AWAY from the join, on the side the cursor is reaching
		# toward — otherwise a wall attached to a run's end would lie back
		# on top of the run it just joined.
		if shortest_delta(space, attach["point"], cursor).dot(direction) < 0.0:
			direction = -direction
		centre = attach["point"] + direction * half

	var out := entry(space, centre, angle)
	out["facing"] = facing
	out["angle"] = angle
	out["snapped"] = bool(attach["found"])
	return out


## One segment's build-order fields, from where it stands and how it is
## turned. Public because the placement ghost wants exactly this for the
## single-segment case without going through `segments`.
static func entry(space: TorusSpace, point: Vector3, angle: float) -> Dictionary:
	return {
		"cell": space.world_to_cell(point),
		"facing": PlacementJitter.byte_of_radians(angle),
		"offset": offset_in_cell(space, point),
	}
