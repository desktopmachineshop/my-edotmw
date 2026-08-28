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
##
## The wrap is written out rather than delegated to `normalize`, and that
## is a measurement rather than a preference: a GDScript call costs
## 0.174 us on this hardware, `normalize` costs 0.214 total, and the two
## `posmod`s it performs cost 0.095 — so the delegation was more call
## than arithmetic. `index` runs once per drawn man per frame (and once
## per cell in every disk scan in the project), which is where 0.19 us
## stops being nothing.
##
## D-008 is untouched: the wrap rule still lives in exactly one FILE, and
## every caller still goes through this class. What is gone is a stack
## frame, not a definition — `normalize` remains the answer for anyone
## who wants the coordinate rather than the index, and
## `test_torus_space.gd` holds the two to the same answer.
func index(coord: Vector2i) -> int:
	return posmod(coord.y, height) * width + posmod(coord.x, width)


## Every cell index within `radius` of `cell_index`, wrapped.
##
## `disk_offsets` gives the OFFSETS and a caller then converts each to an
## index — sixty-one `index()` calls per query at the radius the client's
## tree lookup uses, once per drawn squad per frame. A GDScript call
## costs 0.174 us on the hardware this was measured on
## (D-20260828-inside-the-derive-phase), so at 630 drawn squads that is
## most of the cost of the scan and none of its work.
##
## Same answer, one call: `index(origin + offset)` for each offset, in
## the same order, so a caller swapping to this cannot change what it
## finds — `test_torus_space.gd` holds the two to each other.
##
## Not cached, deliberately: the offsets are (they are translation
## invariant, which is `disk_offsets`' whole point), but the INDICES
## depend on where the disk is centred and a table per origin would be
## the map over again.
func disk_indices(cell_index: int, radius: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var origin := from_index(cell_index)
	for offset in TorusSpace.disk_offsets(radius):
		out.append(posmod(origin.y + offset.y, height) * width
			+ posmod(origin.x + offset.x, width))
	return out


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
	return normalize(round_axial(world_to_axial(world)))


## Continuous axial coordinates for a world position — `world_to_cell` without
## the rounding or the wrap.
##
## Exists so a caller that needs to know WHERE INSIDE a cell a point falls can
## get the fractional part without doing the conversion a second time by hand.
## The ground sampler (D-067) needs exactly that, and it needs the UNWRAPPED
## cell: subtracting a wrapped cell centre from a world position gives a
## garbage offset for anything near a seam.
func world_to_axial(world: Vector3) -> Vector2:
	var r := world.z / (1.5 * hex_size)
	return Vector2(world.x / (SQRT_3 * hex_size) - r * 0.5, r)


## Round continuous axial coordinates to the containing cell, unwrapped.
##
## Cube rounding rather than rounding q and r independently — see
## `world_to_cell`, which this is factored out of.
##
## The body is here rather than in a private helper for the same measured
## reason as `index` above: the delegation was a whole extra call
## (0.174 us of the 0.621 this used to cost) around arithmetic that is
## cheaper than the frame it sat in, on a function that runs once per
## drawn man per frame.
func round_axial(fractional: Vector2) -> Vector2i:
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
## The two world-space vectors that tile this torus (D-035, D-045).
##
## Stepping `width` in q moves world x only. Stepping `height` in r moves
## BOTH z and x, because x depends on r/2 — tiling by an axis-aligned
## rectangle instead looks correct straight ahead and tears at the
## diagonal seams.
##
## Defined once because there are three consumers: the client's nine-copy
## terrain tiling, the camera's wrap, and render culling. M3 deleted a
## spawn formula that had been duplicated between server and client for
## exactly this reason (D-036), and a torus has more of these traps than
## most geometries — every distance, neighbour and now every visibility
## test has to know about the seam.
func lattice_steps() -> Array[Vector3]:
	var out: Array[Vector3] = [
		Vector3(float(width) * hex_size * SQRT_3, 0.0, 0.0),
		Vector3(
			float(height) * 0.5 * hex_size * SQRT_3,
			0.0,
			float(height) * 1.5 * hex_size),
	]
	return out


## The nine world offsets at which this torus's contents appear: the
## centre copy and its eight neighbours across both seams.
##
## The centre (0,0) is FIRST, so a caller scanning for the first visible
## copy prefers the canonical position and only reaches for a wrapped one
## when the canonical position is off screen.
func lattice_offsets() -> Array[Vector3]:
	var steps := lattice_steps()
	var out: Array[Vector3] = [Vector3.ZERO]
	for i in [-1, 0, 1]:
		for j in [-1, 0, 1]:
			if i == 0 and j == 0:
				continue
			out.append(steps[0] * float(i) + steps[1] * float(j))
	return out


static func hex_length(d: Vector2i) -> int:
	return int((abs(d.x) + abs(d.x + d.y) + abs(d.y)) / 2.0)


## Cache: integer radius -> Array[Vector2i] of every (dq, dr) axial offset
## whose hex_length() is <= radius, i.e. a full hex disk of that radius
## centred at the origin. Pure axial geometry — independent of
## width/height/hex_size — so one static cache safely serves every
## TorusSpace instance and every radius.
static var _disk_offset_cache: Dictionary = {}

# `neighbor_table()`'s cache, and the dimensions it was built for. Per
# INSTANCE rather than static like the disk table above, because a
# neighbour index depends on width and height where a disk offset does
# not. The dimensions are remembered rather than inferred from the array
# length: width and height are @export, so a 64x64 space reshaped to
# 32x128 keeps its cell count and would otherwise keep a wrong table.
var _neighbor_table := PackedInt32Array()
var _table_width: int = -1
var _table_height: int = -1


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

	# Sorted NEAREST FIRST, which the bound above does not give: it
	# enumerates dq-major from -radius, so the first entries are the far
	# edge of the disk. Set-consumers (vision stamping, combat's disk scan)
	# never cared about order, but every "walk outward until you find a
	# free cell" caller did, and each of them silently took a cell up to
	# `radius` away in a fixed direction — see SquadSim._free_cell_near,
	# which cost a besieging squad its place in the fight (D-067).
	#
	# Ties broken by (dq, dr) so the order is a total one: two squads
	# ordered onto the same cell must pick the same way out on the server
	# and in a replay.
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var la := hex_length(a)
		var lb := hex_length(b)
		if la != lb:
			return la < lb
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)

	# Sorted once per radius and cached, so this costs nothing per call —
	# the table is reused by every squad, every rebuild (see above).
	_disk_offset_cache[radius] = offsets
	return offsets


## The six neighbours of every cell, flat, stride 6: the neighbour of cell
## `i` in direction `dir` is `neighbor_table()[i * 6 + dir]`.
##
## Same shape and the same reason as `disk_offsets`: a wrap-aware
## derivation that a hot loop was recomputing per element. `FlowField`'s
## BFS called `neighbor_index()` six times per cell, and each of those
## calls is a method dispatch plus a posmod, an integer division, a
## Vector2i and two more posmods — which turned out to be **93% of the
## solver's cost**. Measured on the shipped 168x194 map: a full field is
## **228.2 ms via neighbor_index() and 10.4 ms reading this table** (8.54
## vs 0.40 µs/cell). That is the FIFTH time this project has found the same
## defect (vision's distance() per candidate cell, UnitRoster.by_id per
## produced squad, terrain noise per soldier per frame, the per-squad
## building scan), so it is filed with them — see
## decisions/D-20260818-the-flow-field-solver-was-93-percent-neighbour-lookup.md.
##
## Cached for the life of the space and built lazily on first use, because
## it is a property of the LATTICE alone: nothing in it depends on
## passability, terrain, gates or the match, so a gate opening does not
## invalidate it the way it invalidates every cached field. 764 KB and
## 14.7 ms on the shipped map; 3.0 MB and 46.9 ms at Huge (130,368 cells).
##
## `neighbor_index()` remains the definition of record — this is a
## memoisation of it, not a second opinion, and `test_torus_space.gd`
## asserts the two agree for EVERY cell and EVERY direction rather than
## trusting the same arithmetic written twice. The build below is row-wise
## rather than a loop over `neighbor_index` because that costs 14.7 ms
## against 341.5 ms, which is the difference between a lazy build being a
## non-event and being a dropped tick.
func neighbor_table() -> PackedInt32Array:
	if _table_width == width and _table_height == height \
			and _neighbor_table.size() == width * height * 6:
		return _neighbor_table

	var table := PackedInt32Array()
	table.resize(width * height * 6)
	for dir in range(6):
		var offset: Vector2i = DIRECTIONS[dir]
		for r in range(height):
			# Both wraps are hoisted out of the inner loop: the row is
			# constant across it, and the column only ever advances by one
			# and wraps at most once per row.
			var row_base := posmod(r + offset.y, height) * width
			var at := r * width * 6 + dir
			var q := posmod(offset.x, width)
			for _x in range(width):
				table[at] = row_base + q
				at += 6
				q += 1
				if q >= width:
					q = 0

	_neighbor_table = table
	_table_width = width
	_table_height = height
	return _neighbor_table
