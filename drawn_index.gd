extends RefCounted
class_name DrawnIndex

## Where every squad's men were DRAWN last frame, indexed so the
## cross-squad jostle can find its neighbours without walking the whole
## match (#262).
##
## ## The defect this replaces
##
## `client.gd` kept a plain dictionary of the previous frame's drawn men
## and, for every standing squad, walked ALL of it:
##
##     for other_id in _drawn_cache:      # every squad ever drawn
##         ...distance test...
##         for k in range(men.size()):    # ...and each of its men
##
## That is O(drawn squads x drawn men) per frame, and it is not a
## theoretical worry: measured through the benchmark that finally runs
## the client's own render passes (#240), the gather cost **9.97 ms at
## 155 drawn squads and 152.43 ms at 630** — 4.06x the squads for 14.3x
## the time, against 16.5x for a perfect square, while every pass beside
## it stayed linear. At 1,000 squads it was 39% of the whole frame.
##
## It also fired at the worst possible moment. The gate is
## `speed <= MOVING_SPEED_EPSILON`, so it runs for squads that are
## STANDING — which is to say when the armies have arrived and the battle
## has started. The frame got worse exactly when the player was looking.
##
## D-20260821 bounded it for "72-squad scale" and said so; this is what
## that bound is worth at D-018's.
##
## ## What this is, and what it deliberately is not
##
## A uniform grid over the men's WORLD positions, cell size chosen so any
## query touches at most 3x3 buckets. The predicate is unchanged — same
## centre test, same per-man test — so the men handed to
## `SoldierMotion.ease` are the same men. Only how they are FOUND changed.
##
## **Not a torus disk scan, and that is a deliberate departure from a
## standing rule.** This project's rule is to reach for
## `TorusSpace.disk_offsets` before `distance()`, and it is the right rule
## for anything indexed by CELL. These coordinates are not cell
## coordinates: they are the world positions a squad was drawn at, which
## since D-20260818 is a LATTICE COPY — two squads a map apart in
## canonical space are adjacent on screen, and two copies of one squad are
## legitimately a map apart in this space. Normalising them onto the torus
## would merge things the renderer deliberately keeps separate and change
## which men jostle. The grid indexes exactly the space the predicate is
## written in, which is what makes the result provably identical.
##
## **Not `combat.gd`'s bucket map either**, and that was checked before
## writing this. That map is `cell index -> squad ids` over a `SquadSim`,
## rebuilt per combat round, on the SERVER (D-024, server-only). This one
## holds per-soldier DRAWN positions on the client, one frame stale, in
## lattice-copy space. They share a shape and nothing else: no data, no
## side of the wire, and no coordinate system. Sharing nine lines of
## dictionary-building would couple a server file to the render path for
## no saving — which is the sort of trade that produces the coupling this
## project keeps having to undo.
##
## ## Why it may hold state at all
##
## D-006 clause 2, as amended by D-20260819, permits bounded, one-way,
## outcome-blind per-soldier RENDER state. This is that state, and it
## already existed — `client.gd`'s `_drawn_cache` — with a worse home. It
## is bounded by the squads DRAWN (see `begin`), it is written only by a
## drawing surface, and nothing in the simulation may read it; a scan test
## enforces the last part the way `test_tier_three.gd` does for
## `SoldierMotion`.

## How wide one bucket is, in world units.
##
## A CONSTANT, and the two rejected alternatives are worth more than the
## number. Sizing it from the widest formation in the index means knowing
## that width before the first `put`, which nobody does; deferring the
## bucketing to the first QUERY instead — which is what was written first
## — re-bucketed every record on every query, because the caller
## interleaves puts and queries as it walks its squads. That is the
## quadratic rebuilt inside its own fix, and it measured worse than the
## walk it replaced: the jostle went 152 ms -> 188 ms at 630 drawn
## squads before the flag came out.
##
## 9.0 covers a formation radius plus a query's reach plus the slack, so
## a lookup is normally the 3x3 neighbourhood; `neighbours_of` widens the
## span itself when it is not, so a wider formation is slower and never
## wrong.
const MIN_BUCKET := 9.0

var _records := {}
var _by_bucket := {}
var _bucket_size := MIN_BUCKET
var _widest := 0.0
## Squads written since the last `begin`. What is NOT written this frame
## is dropped, which is the second half of #262: `_drawn_cache` was never
## pruned, so the walk covered every squad ever drawn rather than every
## squad on screen. A squad nobody is drawing has no men on screen for
## anyone to jostle against.
var _seen := {}

## Comparisons the last `neighbours_of` sweep made. The honest measure of
## whether this is still linear: a wall-clock assertion on a shared host
## goes red with nothing wrong (D-106's amendment), so the test counts
## WORK.
var candidates_examined := 0


## Start a frame. Everything not re-`put` before the next `begin` is gone.
func begin() -> void:
	_records = {}
	_by_bucket = {}
	_seen = {}
	_widest = 0.0
	_bucket_size = MIN_BUCKET


## Record where a squad's men were drawn: `centre` is the point the
## formation was drawn about (with its lattice offset already applied),
## `radius` its on-screen extent, `men` their world positions.
func put(squad_id, centre: Vector3, radius: float, men: PackedVector3Array) -> void:
	_records[squad_id] = {"men": men, "centre": centre, "radius": radius}
	_seen[squad_id] = true
	_widest = maxf(_widest, radius)
	var key := _bucket_key(centre)
	if not _by_bucket.has(key):
		_by_bucket[key] = []
	_by_bucket[key].append(squad_id)


## Foreign drawn men within `radius + 1.0` of `at`, for the squad whose
## own id is `squad_id` (its own men are never returned).
##
## Identical in CONTENT to the walk this replaces: same centre test, same
## per-man test, same 1.0 of slack. Returned in ascending squad id, which
## the old walk did not do — it iterated a dictionary, so the order
## depended on which squad happened to be drawn first. Nothing downstream
## reads the order (`SoldierMotion.ease` sums a repulsion per man and
## skips anything past `JOSTLE_RADIUS`), but an order that depends on
## match history is one two clients can disagree about, and this one
## cannot.
func neighbours_of(squad_id, at: Vector3, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	candidates_examined = 0
	if _records.is_empty():
		return out

	# The furthest a qualifying centre can sit: our reach plus the widest
	# extent anything in the index has. Taken from the index rather than
	# assumed, so a formation nobody anticipated cannot be missed.
	var reach := radius + _widest + 1.0
	var span := maxi(1, ceili(reach / _bucket_size))
	var home := _bucket_cell(at)

	var candidates := []
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := _key_of(home.x + dx, home.y + dz)
			if not _by_bucket.has(key):
				continue
			for other in _by_bucket[key]:
				candidates.append(other)
	candidates.sort()

	for other in candidates:
		if other == squad_id:
			continue
		candidates_examined += 1
		var record: Dictionary = _records[other]
		if (record["centre"] as Vector3).distance_to(at) \
				> radius + float(record["radius"]) + 1.0:
			continue
		var men: PackedVector3Array = record["men"]
		for k in range(men.size()):
			if Vector2(men[k].x - at.x, men[k].z - at.z).length() <= radius + 1.0:
				out.append(men[k])
	return out


## The men a squad was last drawn with, or an empty list. For callers that
## kept the old dictionary for a second purpose.
func men_of(squad_id) -> PackedVector3Array:
	var record: Dictionary = _records.get(squad_id, {})
	return record.get("men", PackedVector3Array())


func size() -> int:
	return _records.size()


func has(squad_id) -> bool:
	return _records.has(squad_id)


## Every squad in the index, for a caller that genuinely needs all of them
## (a test, mostly). The point of this class is that the per-frame gather
## does NOT.
func squad_ids() -> Array:
	return _records.keys()


func _bucket_cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / _bucket_size), floori(at.z / _bucket_size))


func _bucket_key(at: Vector3) -> int:
	var cell := _bucket_cell(at)
	return _key_of(cell.x, cell.y)


## Two bucket coordinates in one integer key — a dictionary of ints
## hashes faster than one of Vector2i, and this is read once per bucket
## per squad per frame.
##
## Injective for |x|, |z| < HALF_SPAN, which at MIN_BUCKET is about eight
## million world units either way. A shift-and-xor packing was written
## first and is NOT injective across the sign boundary; the arithmetic
## form is longer and cannot collide two buckets into one, which here
## would silently drop a neighbour.
const HALF_SPAN := 1 << 20
const SPAN := 1 << 21


static func _key_of(x: int, z: int) -> int:
	return (x + HALF_SPAN) * SPAN + (z + HALF_SPAN)
