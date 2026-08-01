extends RefCounted
class_name FlowField

## Flow-field pathfinding, computed per squad destination (D-007).
##
## One field is built per destination and shared by every squad heading
## there — that is the whole reason this scales where per-unit A* does
## not. Cost is O(cells) per destination, paid once, regardless of how
## many squads follow it.
##
## Wrap-aware by construction: every expansion step goes through
## TorusSpace.neighbor_index(), so a squad approaching a destination from
## the far side of a seam is routed the short way around without any
## special casing here (D-008).
##
## CPU-side only, deliberately. A compute-shader implementation is NOT a
## valid substitute: the authoritative server is headless and may be
## CPU-only depending on Q3's hosting answer, so the solver has to run
## without a GPU (see D-021's rejected alternatives).
##
## Storage is packed arrays, not per-cell objects (D-009).

const NO_DIRECTION := 255
const UNREACHABLE := -1

var space: TorusSpace
var destination: int = -1

# Per-cell integer step distance to the destination. UNREACHABLE where
# no path exists.
var _distance := PackedInt32Array()

# Per-cell direction index (0..5) pointing at the next cell along the
# path to the destination. NO_DIRECTION at the destination itself and in
# unreachable cells.
var _flow := PackedByteArray()

# Frontier state, kept between expand() calls so one BFS can be spread
# across several ticks (D-040). A completed field leaves head == tail and
# never touches these again.
var _queue := PackedInt32Array()
var _head := 0
var _tail := 0
var _passable := PackedByteArray()
var _use_passable := false


## Build the field for `p_destination`, all at once.
##
## `passable` is one byte per cell, non-zero meaning passable. Pass an
## empty array to treat every cell as passable. An impassable destination
## yields an entirely unreachable field rather than an exception — the
## caller decides what to do about an invalid order.
func build(p_space: TorusSpace, p_destination: Vector2i, passable := PackedByteArray()) -> void:
	begin(p_space, p_destination, passable)
	expand(-1)


## Start an incremental build (D-040). Allocates and seeds the frontier
## but expands nothing; call expand() until it returns true.
##
## Splitting build() in two is what makes an order wave survivable: a full
## BFS is ~2 µs per cell no matter the language, so the problem was never
## the per-cell cost but doing every cell inside one 100 ms tick.
func begin(p_space: TorusSpace, p_destination: Vector2i, passable := PackedByteArray()) -> void:
	assert(p_space != null, "FlowField.begin needs a TorusSpace")
	assert(p_space.is_valid(), "FlowField.begin got an invalid TorusSpace: %s" % p_space.validate())

	space = p_space
	var count := space.cell_count()
	destination = space.index(p_destination)

	_distance = PackedInt32Array()
	_distance.resize(count)
	_distance.fill(UNREACHABLE)

	_flow = PackedByteArray()
	_flow.resize(count)
	_flow.fill(NO_DIRECTION)

	_use_passable = passable.size() == count
	if passable.size() > 0 and not _use_passable:
		push_error("FlowField.begin: passable array is %d long but the space has %d cells — ignoring it" % [passable.size(), count])
	_passable = passable if _use_passable else PackedByteArray()

	_queue = PackedInt32Array()
	_head = 0
	_tail = 0

	if _use_passable and _passable[destination] == 0:
		# Destination itself is blocked; leave the field fully unreachable
		# and already complete — there is nothing to expand.
		return

	_queue.resize(count)
	_distance[destination] = 0
	_queue[_tail] = destination
	_tail += 1


## Expand up to `cell_budget` frontier cells; -1 means "until finished".
## Returns true when the field is complete.
##
## Breadth-first expansion outward from the destination. Uniform step
## cost, so BFS is exact and no priority queue is needed. The queue is a
## packed array with a head index rather than Array.pop_front(), which is
## O(n) per pop and would dominate at 10,000+ cells.
##
## **A partially expanded field is CORRECT wherever it is defined**, which
## is the property the whole amortisation rests on: BFS assigns a cell its
## final distance the first time it is reached, so nothing already written
## can change later. A partial field is not an approximation to be
## corrected — it is a complete answer over a smaller region.
##
## The one thing a caller must not do is read UNREACHABLE as "no path"
## while `is_complete()` is false. Mid-build it means "not reached YET",
## and those are opposite instructions.
func expand(cell_budget: int = -1) -> bool:
	var spent := 0
	while _head < _tail and (cell_budget < 0 or spent < cell_budget):
		var current := _queue[_head]
		_head += 1
		spent += 1
		var next_distance := _distance[current] + 1

		for dir in range(6):
			var neighbor := space.neighbor_index(current, dir)
			if _distance[neighbor] != UNREACHABLE:
				continue
			if _use_passable and _passable[neighbor] == 0:
				continue
			_distance[neighbor] = next_distance
			# We expanded from `current` to `neighbor` in direction `dir`,
			# so the path back toward the destination leaves `neighbor` in
			# the opposite direction. Opposite of d is (d + 3) % 6 given
			# TorusSpace.DIRECTIONS' counter-clockwise ordering.
			_flow[neighbor] = (dir + 3) % 6
			_queue[_tail] = neighbor
			_tail += 1

	if _head >= _tail:
		# Release the frontier as soon as it is spent. At 32,768 cells this
		# is 128 KB per field, and fields are cached for the life of the
		# match — holding them all would turn a latency fix into a memory
		# problem.
		_queue = PackedInt32Array()
		_passable = PackedByteArray()
		return true
	return false


## Whether the BFS has finished. Until it has, a cell with no distance may
## simply not have been reached yet — see expand().
func is_complete() -> bool:
	return _head >= _tail


## Whether this cell has a final answer yet. True for reachable cells the
## expansion has covered, and for the destination itself.
func covers(cell: int) -> bool:
	if _distance.is_empty():
		return false
	return _distance[posmod(cell, _distance.size())] != UNREACHABLE


## How many cells remain on the frontier — a progress gauge for callers
## budgeting expansion across several fields.
func pending_cells() -> int:
	return maxi(0, _tail - _head)


## How many frontier cells this field has expanded in total. What a
## budgeting caller should charge itself, since a field that finishes
## early costs less than the budget it was offered.
func expanded_cells() -> int:
	return _head


## Direction index (0..5) to travel from this cell, or NO_DIRECTION if
## this is the destination or the cell cannot reach it.
func direction_at(cell: int) -> int:
	if _flow.is_empty():
		return NO_DIRECTION
	return _flow[posmod(cell, _flow.size())]


## Step distance from this cell to the destination, or UNREACHABLE.
func distance_at(cell: int) -> int:
	if _distance.is_empty():
		return UNREACHABLE
	return _distance[posmod(cell, _distance.size())]


func is_reachable(cell: int) -> bool:
	return distance_at(cell) != UNREACHABLE


## The next cell along the path. Returns `cell` unchanged at the
## destination or in an unreachable cell, so a caller that steps blindly
## stalls in place rather than walking off the field.
func step_from(cell: int) -> int:
	var dir := direction_at(cell)
	if dir == NO_DIRECTION:
		return posmod(cell, maxi(_distance.size(), 1))
	return space.neighbor_index(cell, dir)


## Walk the field from `cell` to the destination, returning the full path
## including both endpoints. Primarily a test and debugging affordance —
## the sim follows the field one step per tick rather than materializing
## paths. Returns an empty array if the destination is unreachable.
func path_from(cell: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var current := posmod(cell, maxi(_distance.size(), 1))
	if not is_reachable(current):
		return out

	out.append(current)
	# distance_at is a strict decreasing bound, so this cannot loop
	# forever even if the field were somehow malformed.
	var guard := distance_at(current) + 1
	while current != destination and guard > 0:
		current = step_from(current)
		out.append(current)
		guard -= 1
	return out
