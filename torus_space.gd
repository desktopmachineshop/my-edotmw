extends Resource
class_name TorusSpace

## Wrapped flat hex grid on a torus (D-008).
##
## Axial coordinates (q, r) on a parallelogram domain, q in [0, width),
## r in [0, height). Both axes wrap.
##
## D-008's requirement is that wrap-awareness is a property of the TYPE,
## not a convention every call site has to remember. That is enforced
## here by making every public method normalize its own inputs: passing
## an un-wrapped coordinate to any method on this class cannot produce a
## wrong answer, because the space wraps it for you. There is deliberately
## no "raw" variant of any method that skips normalization.
##
## Hot paths (flow fields, per-squad updates) should work in cell
## INDICES rather than coordinates — see index()/from_index(). An index
## is normalized by construction, so it cannot represent an out-of-domain
## cell at all, and it costs no allocation. Coordinates are Vector2i and
## are only meaningful paired with the TorusSpace that produced them.
##
## Coordinate convention is pointy-top hexes:
##     world.x = hex_size * sqrt(3) * (q + r/2)
##     world.z = hex_size * 1.5 * r

# Axial neighbor directions, pointy-top, counter-clockwise from east.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),   # E
	Vector2i(1, -1),  # NE
	Vector2i(0, -1),  # NW
	Vector2i(-1, 0),  # W
	Vector2i(-1, 1),  # SW
	Vector2i(0, 1),   # SE
]

const SQRT_3 := 1.7320508075688772

# The nine ghost-copy shift multipliers delta() searches (this axis's own
# copy plus one period-shift either way). A const rather than a fresh
# `[-1, 0, 1]` array literal built on every delta() call — delta() is the
# hottest function in the whole simulation (every distance() call goes
# through it), so two per-call heap allocations here were pure waste.
const _GHOST_SHIFTS := [-1, 0, 1]

@export var width: int = 64
@export var height: int = 64
@export var hex_size: float = 1.0


func _init(p_width: int = 64, p_height: int = 64, p_hex_size: float = 1.0) -> void:
	width = p_width
	height = p_height
	hex_size = p_hex_size


## Why height must be even (D-008's "row-parity constraint on map
## dimensions").
##
## Wrapping q by `width` shifts world x by sqrt(3)*width*hex_size and
## leaves z alone — always lattice-aligned, no constraint needed.
##
## Wrapping r by `height` shifts world x by sqrt(3)*(height/2)*hex_size.
## If `height` is odd, that is a HALF column width, so the map's left and
## right edges meet misaligned by half a hex when the vertical seam is
## crossed. The topology still works, but the torus can no longer be
## presented as a seamless rectangle — which the minimap and camera
## panning both need. Requiring even height keeps the vertical wrap a
## whole number of columns.
##
## Returns "" if valid, else a human-readable reason.
func validate() -> String:
	if width <= 0 or height <= 0:
		return "TorusSpace dimensions must be positive (got %dx%d)" % [width, height]
	if height % 2 != 0:
		return "TorusSpace height must be even (got %d) — see D-008 row parity; an odd height misaligns the vertical seam by half a column" % height
	# A torus narrower than 2 cells makes a cell its own neighbor across
	# the wrap, which silently breaks distance and flow-field expansion.
	if width < 2 or height < 2:
		return "TorusSpace must be at least 2x2 (got %dx%d)" % [width, height]
	return ""


func is_valid() -> bool:
	return validate() == ""


func cell_count() -> int:
	return width * height


## Wrap an arbitrary axial coordinate into the domain.
func normalize(coord: Vector2i) -> Vector2i:
	return Vector2i(posmod(coord.x, width), posmod(coord.y, height))


## Cell index for packed-array storage (D-009). Normalizes first, so an
## out-of-domain coordinate maps to its wrapped cell rather than blowing
## up or silently indexing out of bounds.
func index(coord: Vector2i) -> int:
	var c := normalize(coord)
	return c.y * width + c.x


func from_index(i: int) -> Vector2i:
	var wrapped := posmod(i, cell_count())
	return Vector2i(wrapped % width, wrapped / width)


## The neighbor of `coord` in direction `dir` (0..5), wrapped.
func neighbor(coord: Vector2i, dir: int) -> Vector2i:
	return normalize(coord + DIRECTIONS[posmod(dir, 6)])


func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(normalize(coord + d))
	return out


## Neighbor in index space — the allocation-free form for hot loops.
func neighbor_index(i: int, dir: int) -> int:
	return index(from_index(i) + DIRECTIONS[posmod(dir, 6)])


## Shortest wrapped axial delta from `a` to `b`.
##
## This is D-008's "ghost-copy comparison": the candidate deltas are the
## direct one plus the eight copies displaced by the torus period vectors,
## and the shortest wins. Everything directional (movement, facing, world
## offsets) must go through this rather than subtracting coordinates,
## which would send a squad the long way around the map whenever the short
## path crosses a seam.
func delta(a: Vector2i, b: Vector2i) -> Vector2i:
	var na := normalize(a)
	var nb := normalize(b)
	var raw_dq := nb.x - na.x
	var raw_dr := nb.y - na.y

	var best := Vector2i(raw_dq, raw_dr)
	var best_len := hex_length(best)

	for i in _GHOST_SHIFTS:
		for j in _GHOST_SHIFTS:
			if i == 0 and j == 0:
				continue
			var candidate := Vector2i(raw_dq + i * width, raw_dr + j * height)
			var candidate_len := hex_length(candidate)
			if candidate_len < best_len:
				best = candidate
				best_len = candidate_len

	return best


## Toroidal hex distance in cells.
func distance(a: Vector2i, b: Vector2i) -> int:
	return hex_length(delta(a, b))


## World-space position of a cell centre. Note this is the position on
## the *unwrapped* parallelogram — for anything comparing two positions,
## use world_delta() instead, which respects the seam.
func to_world(coord: Vector2i, y: float = 0.0) -> Vector3:
	var c := normalize(coord)
	return Vector3(
		hex_size * SQRT_3 * (float(c.x) + float(c.y) * 0.5),
		y,
		hex_size * 1.5 * float(c.y)
	)


## Shortest world-space vector from `a` to `b`, respecting the wrap.
## Derived from delta() so it can never disagree with distance().
func world_delta(a: Vector2i, b: Vector2i) -> Vector3:
	var d := delta(a, b)
	return axial_offset_to_world(Vector2(float(d.x), float(d.y)))


## Convert a continuous axial OFFSET (not a position) to world space. The
## axial-to-world map is linear, so offsets convert without needing to
## know where they start — which is what lets StateCurve and Formation
## work in continuous axial space and only touch world space at the end.
func axial_offset_to_world(d: Vector2) -> Vector3:
	return Vector3(
		hex_size * SQRT_3 * (d.x + d.y * 0.5),
		0.0,
		hex_size * 1.5 * d.y
	)


## Inverse of to_world(): which cell contains this world position.
##
## Needed by the client to turn a mouse click into an order. Uses cube
## rounding rather than rounding q and r independently — independent
## rounding picks the wrong hex near cell corners, which shows up as
## orders landing one cell off exactly where the player was aiming
## carefully.
func world_to_cell(world: Vector3) -> Vector2i:
	var r := world.z / (1.5 * hex_size)
	var q := world.x / (SQRT_3 * hex_size) - r * 0.5
	return normalize(_axial_round(Vector2(q, r)))


func _axial_round(fractional: Vector2) -> Vector2i:
	# Convert to cube, round, then repair the component with the largest
	# rounding error so x + y + z == 0 still holds.
	var x := fractional.x
	var z := fractional.y
	var y := -x - z

	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)

	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)

	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector2i(int(rx), int(rz))


## Hex length of an axial OFFSET, via the cube-coordinate identity
## (x, y, z) = (q, -q-r, r) and length = (|x| + |y| + |z|) / 2. Pure
## geometry — no torus, no wrap, no instance state — so it's static and
## public: disk_offsets()'s callers (Vision, Combat) need this to rank
## candidates without re-deriving it via a wrap-aware distance() call.
static func hex_length(d: Vector2i) -> int:
	return int((abs(d.x) + abs(d.x + d.y) + abs(d.y)) / 2.0)


## Cache: integer radius -> Array[Vector2i] of every (dq, dr) axial offset
## whose hex_length() is <= radius, i.e. a full hex disk of that radius
## centred at the origin. Pure axial geometry — independent of
## width/height/hex_size — so one static cache safely serves every
## TorusSpace instance and every radius.
static var _disk_offset_cache: Dictionary = {}


## The hex disk of integer `radius`, as (dq, dr) offsets from an
## unspecified centre.
##
## Why this can be cached and reused unmodified for any squad, any
## centre, any rebuild: a hex disk is translation-invariant — the set of
## offsets within a given hex length of the origin does not depend on
## where the origin actually sits on the torus. So it is computed once
## per radius rather than re-enumerated (and, in the code this replaces,
## re-distance-tested cell by cell) for every squad on every vision
## rebuild or combat round (D-025, D-024).
##
## The standard cube-coordinate diamond bound below — for each dq in
## [-radius, radius], dr ranges over [max(-radius, -dq-radius),
## min(radius, -dq+radius)] — already enumerates EXACTLY the disk (every
## offset it yields has hex_length() <= radius, and no offset with
## hex_length() <= radius is skipped). That means no per-offset distance
## test is needed to trim it: the old code's "enumerate a superset
## diamond, then call distance() per candidate to filter it down to the
## true disk" was doing work this bound already does for free.
##
## Callers still turn (origin + offset) into an actual wrapped cell via
## index() — that normalization, not this function, is where D-008's
## wrap-awareness lives. A radius exceeding half the map's width or
## height can make the same wrapped cell reachable via more than one
## offset in this table; that is harmless here for exactly the reason
## combat.gd's header already gives (a redundant visit, never a wrong
## set), and Combat._find_target's header explains why it doesn't even
## corrupt nearest-target ranking.
static func disk_offsets(radius: int) -> Array[Vector2i]:
	if radius < 0:
		return []
	if _disk_offset_cache.has(radius):
		return _disk_offset_cache[radius]

	var offsets: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		var dr_min := maxi(-radius, -dq - radius)
		var dr_max := mini(radius, -dq + radius)
		for dr in range(dr_min, dr_max + 1):
			offsets.append(Vector2i(dq, dr))

	_disk_offset_cache[radius] = offsets
	return offsets
