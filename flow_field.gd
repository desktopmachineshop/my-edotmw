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


## Build the field for `p_destination`.
##
## `passable` is one byte per cell, non-zero meaning passable. Pass an
## empty array to treat every cell as passable. An impassable destination
## yields an entirely unreachable field rather than an exception — the
## caller decides what to do about an invalid order.
func build(p_space: TorusSpace, p_destination: Vector2i, passable := PackedByteArray()) -> void:
	assert(p_space != null, "FlowField.build needs a TorusSpace")
	assert(p_space.is_valid(), "FlowField.build got an invalid TorusSpace: %s" % p_space.validate())

	space = p_space
	var count := space.cell_count()
	destination = space.index(p_destination)

	_distance = PackedInt32Array()
	_distance.resize(count)
	_distance.fill(UNREACHABLE)

	_flow = PackedByteArray()
	_flow.resize(count)
	_flow.fill(NO_DIRECTION)

	var use_passable := passable.size() == count
	if passable.size() > 0 and not use_passable:
		push_error("FlowField.build: passable array is %d long but the space has %d cells — ignoring it" % [passable.size(), count])

	if use_passable and passable[destination] == 0:
		# Destination itself is blocked; leave the field fully unreachable.
		return

	# Breadth-first expansion outward from the destination. Uniform step
	# cost, so BFS is exact and no priority queue is needed. The queue is
	# a packed array with a head index rather than Array.pop_front(),
	# which is O(n) per pop and would dominate at 10,000+ cells.
	var queue := PackedInt32Array()
	queue.resize(count)
	var head := 0
	var tail := 0

	_distance[destination] = 0
	queue[tail] = destination
	tail += 1

	while head < tail:
		var current := queue[head]
		head += 1
		var next_distance := _distance[current] + 1

		for dir in range(6):
			var neighbor := space.neighbor_index(current, dir)
			if _distance[neighbor] != UNREACHABLE:
				continue
			if use_passable and passable[neighbor] == 0:
				continue
			_distance[neighbor] = next_distance
			# We expanded from `current` to `neighbor` in direction `dir`,
			# so the path back toward the destination leaves `neighbor` in
			# the opposite direction. Opposite of d is (d + 3) % 6 given
			# TorusSpace.DIRECTIONS' counter-clockwise ordering.
			_flow[neighbor] = (dir + 3) % 6
			queue[tail] = neighbor
			tail += 1


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
