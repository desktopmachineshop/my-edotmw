extends RefCounted
class_name WorldIndex

## Things at WORLD positions, bucketed so "what is near me" is a
## neighbourhood scan rather than a walk of everything (#325).
##
## ## The defect this exists for
##
## `client.gd`'s `_nearby_building_boxes` walked EVERY known building, per
## drawn squad, per frame — paying `Engagement.aligning_offset` (nine
## lattice comparisons) on each one before testing the distance. That is
## O(drawn squads x buildings), and buildings are the one thing in a match
## that only ever accumulates: D-030 makes a building known forever once
## seen, a wall is one building PER CELL (D-076), and nothing is ever
## removed from the scan.
##
## Measured through the benchmark that runs the client's own render passes
## (#240), 1,000 squads / 630 drawn, shipped map, Intel Iris Xe:
##
##     buildings    12       60       200
##     box lookup   12.94    59.50    199.19 ms per frame
##
## **One millisecond per building per frame**, exactly linear, while every
## other part of the gather stayed flat. Two hundred buildings — an
## ordinary late-game count once anyone builds a wall — spent more of the
## frame finding buildings than doing everything else put together.
##
## ## Why this is a world grid and NOT `TorusSpace.disk_offsets`
##
## The standing rule is to reach for `disk_offsets` before `distance()`,
## and a cell-disk index was written FIRST, on exactly that reasoning: a
## building is at a cell, so the cell is the natural key.
##
## **It measured ten times worse than the walk it replaced** — 12.94 ms
## to 131.82 ms at twelve buildings. The reason is arithmetic, not
## implementation: the query reach is `SQUAD_CULL_RADIUS + 6` plus the
## widest building, about fourteen world units, and a cell is 1.73 across.
## That is a disk of **469 cells** scanned per squad per frame to find
## twelve buildings.
##
## So the rule earns a boundary, and it is worth stating: **`disk_offsets`
## is for avoiding a `distance()` per candidate over a radius of a FEW
## CELLS, not for finding sparse things over a radius of many.** It is
## right for `_nearby_node_discs` (radius 4, and nodes are dense enough
## that most cells hit); it is wrong here. The bucket width below is
## chosen from the query's own reach so a lookup is a 3x3 neighbourhood
## whatever the radius is — which is what `drawn_index.gd` does, for the
## same reason, one phase over.
##
## ## What it does not do
##
## It narrows the candidates; it does not decide. The caller applies
## exactly the predicate it always applied, so the SET is unchanged —
## which is what makes this an optimisation and not a behaviour change,
## and what `test_world_index.gd` asserts against the walk it replaces.

## Bucket width in world units. Wide enough that a squad's building
## lookup (about fourteen units) is a 3x3 neighbourhood; `near` widens
## its own span when a caller asks for more.
const BUCKET := 16.0

var _by_bucket := {}
var _count := 0
## The furthest any entry reaches. A query widens its own span by this,
## because the test a caller applies is "within my search PLUS the thing's
## own extent" — so a building whose centre is further away than the
## search alone can still qualify.
var _widest := 0.0

## Candidates the last `near()` returned, before the caller's own test.
## Counted rather than timed: a wall-clock assertion on a shared host goes
## red with nothing wrong (D-106's amendment).
var candidates_returned := 0


func begin() -> void:
	_by_bucket = {}
	_count = 0
	_widest = 0.0


## Record `payload` at `at`. `reach` is how far the thing itself extends,
## so a query centred elsewhere still finds it.
func put(at: Vector3, payload, reach: float = 0.0) -> void:
	# ONE bucket, and the size is remembered rather than smeared. Entering
	# a thing into every bucket it reaches into was written first and is
	# wrong twice: it returns the same payload several times when the
	# query overlaps more than one of them, and it does not help anyway,
	# because the caller's test is "within my search plus ITS extent" — a
	# question about the centre. `test_world_index.gd` caught both.
	var key := _bucket_key(at)
	if not _by_bucket.has(key):
		_by_bucket[key] = []
	_by_bucket[key].append(payload)
	_widest = maxf(_widest, reach)
	_count += 1


## Everything within `reach` of `at` — a SUPERSET of what the caller
## wants, which still applies its own test.
func near(at: Vector3, reach: float) -> Array:
	var out := []
	candidates_returned = 0
	if _by_bucket.is_empty():
		return out
	# `_widest` because the caller's test adds the entry's own extent to
	# its search: a building whose centre sits further away than `reach`
	# alone can still qualify, and a span that did not allow for it would
	# silently drop it.
	var span := maxi(1, ceili((reach + _widest) / BUCKET))
	var home := _cell_of(at)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := _key_of(home.x + dx, home.y + dz)
			if not _by_bucket.has(key):
				continue
			for payload in _by_bucket[key]:
				out.append(payload)
	candidates_returned = out.size()
	return out


func size() -> int:
	return _count


func _cell_of(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / BUCKET), floori(at.z / BUCKET))


func _bucket_key(at: Vector3) -> int:
	var cell := _cell_of(at)
	return _key_of(cell.x, cell.y)


## Two bucket coordinates in one integer key. Injective for
## |x|, |z| < HALF_SPAN — a shift-and-xor packing is not, across the sign
## boundary, and a collision here would silently drop a candidate.
const HALF_SPAN := 1 << 20
const SPAN := 1 << 21


static func _key_of(x: int, z: int) -> int:
	return (x + HALF_SPAN) * SPAN + (z + HALF_SPAN)
