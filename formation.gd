extends RefCounted
class_name Formation

## Derived soldier positions (D-006) — the keystone that keeps networking
## and simulation cost at ~1,000 squads instead of ~40,000 soldiers.
##
## ## The rule this file exists to enforce
##
## Every function here is STATIC and PURE. A soldier's position is a
## function of (squad curve, formation shape, slot index, terrain sample)
## and nothing else. There is no per-soldier velocity, no accumulated
## offset, no history carried between ticks, and deliberately no instance
## state of any kind — the class is static so there is nowhere to put any.
##
## That is not a stylistic preference. It is what makes server and client
## agree without the server sending a single soldier position: both sides
## evaluate the same function over the same replicated squad state and get
## the same answer by construction (D-006's confirmation block).
##
## ## What is forbidden here
##
## Local avoidance, collision push-back, soldiers jostling, and neighbours
## walking into a dead man's slot all give a soldier its own integration
## state and break the purity clause. If one of those is ever wanted, it
## is a D-006 revisit, not a patch to this file.
##
## Casualties restamp: the formation is computed for `alive` soldiers, so
## losing one re-derives everyone's slot. Soldiers do not walk to fill the
## gap (D-006 clause 3).
##
## Cosmetic per-soldier motion lives in cosmetic_offset.gd, is applied
## only on the render path, and is never read back here (clause 2).

# Ranks deep for each shape. Line is wide and shallow; column is narrow
# and deep. Both are Total War-ish rather than physically surveyed.
const LINE_RANKS := 3
const COLUMN_FILES := 4

# Facing derivation looks this far along the curve to find travel
# direction. Small enough to track turns, large enough to survive
# float noise on a 10 Hz tick (D-020).
const HEADING_EPSILON := 0.05

# Fallback facing for a squad that has never moved. Arbitrary but fixed —
# it must be deterministic, because client and server both derive it.
const DEFAULT_HEADING := Vector2(0.0, 1.0)


## Offset of one slot within the formation, in formation-local space:
## +x is right, +y is forward. Units are multiples of `spacing`.
##
## Pure in (shape, slot, alive, spacing). Note `alive` is an input: that
## is the casualty restamp.
static func slot_offset(shape: String, slot: int, alive: int, spacing: float) -> Vector2:
	if alive <= 0:
		return Vector2.ZERO
	var index := clampi(slot, 0, alive - 1)

	# Resolved from /formations/*.tres (D-058), not from a match statement
	# here. The GEOMETRY is an algorithm and has to be code; which
	# formations exist, what they are called, how they are parameterised
	# and which are offered to a player are data — the same split UnitDef
	# makes with `mesh_primitive`.
	var def := FormationRoster.by_id(StringName(shape))
	if def == null:
		push_error("Unknown formation '%s' — falling back to line" % shape)
		def = FormationRoster.by_id(&"line")
		if def == null:
			return _grid_offset(index, alive, _files_for_ranks(alive, LINE_RANKS), spacing)
	return _offset_for(def, index, alive, spacing)


## Dispatch to a geometry generator. Adding a `kind` to FormationDef's
## enum means adding a branch HERE — and a roster test fails if a .tres
## names a kind nothing implements, rather than letting it fall through to
## a line and merely look wrong.
static func _offset_for(def: FormationDef, index: int, alive: int,
		spacing: float) -> Vector2:
	var scaled := spacing * maxf(def.spacing_scale, 0.01)
	match def.kind:
		"grid":
			return _grid_offset(index, alive, _grid_files(def, alive), scaled)
		"scatter":
			return _scatter_offset(index, alive, scaled, _grid_files(def, alive), def.jitter)
		"wedge":
			return _wedge_offset(index, scaled)
		"ring":
			return _ring_offset(index, alive, scaled)
		_:
			push_error("FormationDef '%s' has unimplemented kind '%s'" % [def.id, def.kind])
			return _grid_offset(index, alive, _files_for_ranks(alive, LINE_RANKS), scaled)


## How wide a grid formation is: from its declared ranks, its declared
## files, or square if it declares neither.
static func _grid_files(def: FormationDef, alive: int) -> int:
	if def.ranks > 0:
		return _files_for_ranks(alive, def.ranks)
	if def.files > 0:
		return def.files
	return maxi(1, ceili(sqrt(float(alive))))


static func _files_for_ranks(alive: int, ranks: int) -> int:
	return maxi(1, ceili(float(alive) / float(maxi(ranks, 1))))


## Cache: "shape|alive|spacing" -> {"centre": Vector2, "radius": float}.
## Pure in those three, so one static cache serves every squad — the same
## reasoning as TorusSpace.disk_offsets.
static var _footprint_cache: Dictionary = {}


## The ground a squad actually occupies, in formation-local units.
##
## Returns the CENTRE of the occupied area (which is not the squad's curve
## point) and a radius covering every slot.
##
## Both halves matter and both were wrong. Selection tested a click
## against the squad's curve position with a fixed pixel radius, so
## clicking a soldier at the edge of a forty-man line selected nothing —
## the hit test was aimed at one point inside a formation many metres
## across. And the selection marker was drawn at that same curve point,
## which for a line formation sits at the FRONT rank: `_grid_offset` puts
## rank r at -r * spacing, so the body of the squad extends backwards and
## a marker centred on the curve point is visibly offset from the troops
## it is marking.
##
## A circle rather than a rectangle, deliberately: the formation rotates
## with the squad's heading, and a radius is rotation-invariant while a
## box would need re-deriving every frame the squad turned.
static func footprint(shape: String, alive: int, spacing: float) -> Dictionary:
	var key := "%s|%d|%.3f" % [shape, alive, spacing]
	if _footprint_cache.has(key):
		return _footprint_cache[key]

	var result := {"centre": Vector2.ZERO, "radius": maxf(spacing, 0.5)}
	if alive > 0:
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		for slot in range(alive):
			var p := slot_offset(shape, slot, alive, spacing)
			min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
			max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
		var centre := (min_p + max_p) * 0.5
		# Half the diagonal, so the circle contains the whole extent
		# whichever way the squad is facing. Plus a soldier's own width, so
		# the edge of the marker sits just outside the outermost man rather
		# than bisecting him.
		var half := (max_p - min_p) * 0.5
		result = {"centre": centre, "radius": half.length() + spacing * 0.5}

	_footprint_cache[key] = result
	return result


static func _grid_offset(index: int, alive: int, files: int, spacing: float) -> Vector2:
	var rank := index / files
	var file := index % files

	# Centre each rank independently so a partially filled back rank sits
	# in the middle rather than hanging off one edge.
	var in_this_rank := mini(files, alive - rank * files)
	var centre := float(in_this_rank - 1) * 0.5

	return Vector2((float(file) - centre) * spacing, -float(rank) * spacing)



static func _wedge_offset(index: int, spacing: float) -> Vector2:
	# Triangular: row r holds r+1 soldiers, point facing forward.
	var row := 0
	var consumed := 0
	while consumed + row + 1 <= index:
		consumed += row + 1
		row += 1
	var position_in_row := index - consumed
	var centre := float(row) * 0.5
	return Vector2((float(position_in_row) - centre) * spacing, -float(row) * spacing)


## Concentric rings around the centre, nobody standing on it.
##
## For a work crew rather than a fighting line: a squad ordered onto a
## resource node walks its curve to that node, so a formation that circles
## its own centre puts the gatherers AROUND the thing they are working —
## which is what they visibly ought to be doing, and what a spread grid
## never looked like.
##
## Ring sizes and how the crew is shared between them are `_ring_layout`'s
## business — see it for why a crew only gains a second ring when one
## genuinely cannot hold it.
##
## Pure in (index, alive, spacing) like every other shape, with no
## per-soldier state anywhere (D-006 clause 1).
static func _ring_offset(index: int, alive: int, spacing: float) -> Vector2:
	var layout := _ring_layout(alive, spacing)
	var consumed := 0
	for k in range(layout.size()):
		var count: int = layout[k]
		if index < consumed + count:
			var place := index - consumed
			# Half-step alternate rings so the rings interleave rather
			# than lining every soldier up on the same spokes.
			var angle := TAU * (float(place) + 0.5 * float(k % 2)) / float(count)
			return Vector2(cos(angle), sin(angle)) * float(k + 1) * spacing
		consumed += count
	return Vector2.ZERO


## Cache: "alive|spacing" -> Array of how many stand in each ring.
static var _ring_layout_cache: Dictionary = {}


## How to spread `alive` soldiers over as few rings as will hold them.
##
## The first version filled ring 1 to its capacity of six and started ring
## 2 with whatever was left, so eight gatherers stood as a tight six with
## two stranded on their own out at double the radius. Spacing was even
## WITHIN a ring and the crew still looked wrong, because the rings were
## unevenly loaded.
##
## Now: take the fewest rings whose combined capacity holds everyone, then
## spread the crew across them in proportion to each ring's circumference.
## Each ring is evenly divided, so angular spacing is uniform and arc
## spacing is close to `spacing` at every radius — for a crew of any size,
## which is what "equal spacing regardless of squad size" asks for.
##
## Ring k has radius k * spacing, so its circumference is TAU * k * spacing
## and it holds floor(TAU * k) at one `spacing` apart — 6, 12, 18, and so
## on. A crew only gains a second ring when a single one genuinely cannot
## hold it without soldiers standing on each other.
static func _ring_layout(alive: int, spacing: float) -> Array:
	var key := "%d|%.3f" % [alive, spacing]
	if _ring_layout_cache.has(key):
		return _ring_layout_cache[key]

	var layout := []
	if alive > 0:
		# Fewest rings that can hold the crew.
		var rings := 1
		while _capacity_of_rings(rings) < alive:
			rings += 1

		# Share them out by circumference, so no ring is left with a
		# lonely pair while another is packed shoulder to shoulder.
		var total_capacity := _capacity_of_rings(rings)
		var placed := 0
		for k in range(1, rings + 1):
			var share := int(round(float(alive) * float(_ring_capacity(k)) / float(total_capacity)))
			# The last ring takes the remainder, so rounding can never
			# lose or invent a soldier.
			if k == rings:
				share = alive - placed
			share = clampi(share, 0, alive - placed)
			layout.append(share)
			placed += share

	_ring_layout_cache[key] = layout
	return layout


static func _ring_capacity(ring: int) -> int:
	return maxi(1, floori(TAU * float(ring)))


static func _capacity_of_rings(rings: int) -> int:
	var total := 0
	for k in range(1, rings + 1):
		total += _ring_capacity(k)
	return total


## Skirmish order: a grid with a deterministic scatter over it.
##
## The scatter is hashed from the slot index, NOT drawn from an RNG. An
## RNG would either need seeding state (breaking purity) or would desync
## client from server. The same index always yields the same offset, on
## every machine, forever.
##
## Spread and jitter are the FormationDef's, so "how loose is loose" is a
## number in a text file rather than two literals in here.
static func _scatter_offset(index: int, alive: int, spacing: float,
		files: int, jitter: float) -> Vector2:
	var base := _grid_offset(index, alive, files, spacing)
	var scatter := Vector2(_hash_unit(index * 2 + 1), _hash_unit(index * 2 + 2))
	return base + scatter * spacing * jitter


## Deterministic hash of an integer to [-0.5, 0.5]. Integer ops only, so
## it produces identical results on every platform — a float-based hash
## would risk client/server divergence.
static func _hash_unit(n: int) -> float:
	var h := (n * 2654435761) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h & 0xFFFF) / 65535.0 - 0.5


## Squad facing at `time`, in continuous axial space.
##
## Derived entirely from the curve: forward difference while moving,
## backward difference just after stopping, and failing both, a scan back
## through the keyframes for the last real displacement. A stopped squad
## therefore keeps the facing it arrived with WITHOUT anyone storing it.
static func heading(curve: StateCurve, time: float) -> Vector2:
	if curve == null or curve.is_empty():
		return DEFAULT_HEADING

	var here := curve.sample_axial(time)

	var forward := curve.sample_axial(time + HEADING_EPSILON) - here
	if forward.length_squared() > 1e-8:
		return forward.normalized()

	var backward := here - curve.sample_axial(time - HEADING_EPSILON)
	if backward.length_squared() > 1e-8:
		return backward.normalized()

	# Stationary at `time`: find the most recent segment that moved.
	for i in range(curve.key_count() - 1, 0, -1):
		var d := curve.point_at(i) - curve.point_at(i - 1)
		if d.length_squared() > 1e-8:
			return d.normalized()

	return DEFAULT_HEADING


## World transform for a single soldier.
##
## `terrain_height` is the terrain sample from D-006's input tuple. The
## caller supplies it because sampling needs the soldier's XZ, which this
## function computes — see soldier_transforms() for the assembled form.
static func soldier_transform(
	curve: StateCurve,
	time: float,
	slot: int,
	alive: int,
	shape: String,
	spacing: float,
	space: TorusSpace,
	terrain_height: float = 0.0
) -> Transform3D:
	var centre := curve.sample_world(time, space)
	var dir := heading(curve, time)

	# Rotate the formation to face travel direction. The axial->world map
	# is linear, so converting the axial heading gives the world heading.
	var world_dir := space.axial_offset_to_world(dir)
	var angle := atan2(world_dir.x, world_dir.z)

	var local := slot_offset(shape, slot, alive, spacing)
	# Formation-local +y is forward, which is +z after rotation.
	var offset := Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, angle)

	var basis := Basis(Vector3.UP, angle)
	var origin := centre + offset
	origin.y = terrain_height
	return Transform3D(basis, origin)


## All slot transforms for a squad, ready for PrimitiveUnit's MultiMesh.
##
## `terrain_sampler` is an optional Callable taking (x: float, z: float)
## and returning a height. It must itself be pure — it is part of D-006's
## input tuple, so a stateful sampler would break the purity clause just
## as surely as storing velocity here would.
static func soldier_transforms(
	curve: StateCurve,
	time: float,
	alive: int,
	shape: String,
	spacing: float,
	space: TorusSpace,
	terrain_sampler := Callable()
) -> Array[Transform3D]:
	return soldier_transforms_sampled(
		curve, time, alive, shape, spacing, space, terrain_sampler, alive)


## As above, but derives at most `max_count` of the squad's soldiers,
## spread evenly across the formation — the render LOD tier (D-045).
##
## ## This is COSMETIC ONLY, and the boundary is not negotiable
##
## `alive` is unchanged, `slot_offset` is still asked for the squad's real
## size, and the formation therefore keeps its true footprint and shape —
## a distant squad is drawn thinner, never smaller. Nothing here is ever
## read back by the simulation, which is D-006 clause 2's one-way rule,
## and D-012 permits render LOD to be camera-keyed precisely because it
## cannot affect an outcome. Simulation LOD may NOT be camera-keyed, and
## conflating the two would make combat depend on where someone was
## looking.
##
## Slots are picked as `i * alive / n` rather than the first `n`, so a
## half-detail squad still occupies its whole frontage instead of
## bunching into one end of the line.
static func soldier_transforms_sampled(
	curve: StateCurve,
	time: float,
	alive: int,
	shape: String,
	spacing: float,
	space: TorusSpace,
	terrain_sampler := Callable(),
	max_count: int = -1
) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if curve == null or alive <= 0:
		return out

	var count := alive if max_count < 0 else clampi(max_count, 1, alive)

	# Everything except the slot offset is a property of the SQUAD, not the
	# soldier, so it is computed once here rather than once per soldier.
	# Calling soldier_transform() in the loop re-sampled the curve twice
	# (position and heading) and rebuilt the basis for every man — 40
	# identical curve samples for a 40-man squad, every frame.
	#
	# This is not a shortcut around D-006's purity clause; it is the same
	# pure function with its loop-invariants hoisted. The result must stay
	# bit-identical to soldier_transform(), which is what
	# test_bulk_derivation_matches_the_single_soldier_path asserts — if
	# these two ever disagree, client and server disagree about where
	# soldiers are, and that is the exact failure D-006 exists to prevent.
	var centre := curve.sample_world(time, space)
	var world_dir := space.axial_offset_to_world(heading(curve, time))
	var angle := atan2(world_dir.x, world_dir.z)
	var basis := Basis(Vector3.UP, angle)
	var sample_terrain := terrain_sampler.is_valid()

	out.resize(count)
	for i in range(count):
		# `i * alive / count` is `i` exactly when count == alive (integer
		# division), so the full-detail path is unchanged and stays
		# bit-identical to soldier_transform().
		var slot := i * alive / count
		var local := slot_offset(shape, slot, alive, spacing)
		var origin := centre + Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, angle)
		origin.y = terrain_sampler.call(origin.x, origin.z) if sample_terrain else 0.0
		out[i] = Transform3D(basis, origin)
	return out
