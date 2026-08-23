extends RefCounted
class_name Formation

## Derived soldier positions (D-006) — the keystone that keeps networking
## and simulation cost at ~1,000 squads instead of ~40,000 soldiers.
##
## ## The rule this file exists to enforce
##
## Every function here is STATIC and PURE. A soldier's position is a
## function of (squad curve, formation shape, slot index, terrain sample)
## and nothing else. The terrain sample has two halves, and both are
## supplied by the caller: how high the ground is, and whether the squad
## could walk on it at all (see `grounded_offset`). There is no
## per-soldier velocity, no accumulated offset, no history carried between
## ticks, and deliberately no instance state of any kind — the class is
## static so there is nowhere to put any.
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

# Facing derivation looks this far ALONG THE PATH to find travel
# direction — a chord of fixed ARC LENGTH from where the squad is to
# where it will be, in continuous axial units.
#
# Two things hang on this being a length rather than a span of time
# (D-20260818):
#
#  * A hex flow field can only step in six directions, so a march that is
#    "north-east" in world terms is walked as a run of one lattice
#    direction and then a run of another. An instantaneous difference
#    reads every junction between runs as a real 60 degree turn and flips
#    the whole formation with it in one frame; a chord spanning a stretch
#    of path rounds it into the direction the squad is actually
#    travelling.
#
#  * A chord measured in TIME rotates faster when the squad walks slower,
#    because it spans less path — so slowing a squad down to wheel it
#    safely made its facing whip round harder, and the fix fought itself.
#    Measured in path, the facing turns at (curvature x speed) whatever
#    the speed is, which is exactly what SquadSim's pace arithmetic
#    assumes.
#
# Bounded ABOVE by how much curve a client actually holds: its copy is
# clipped to [now, now + CurveReplicator.horizon_seconds], and at the
# slowest pace SquadSim will ever set (its MIN_TURNING_SPEED, on the
# slowest shipped unit) that window is only so many cells long. Reaching
# past it would derive one facing on the server and another on the
# client. test_the_facing_chord_fits_in_what_a_client_holds pins it.
#
# It stays a pure function of (curve, time) — D-006 clause 1 is
# untouched, there is still nowhere for a turn rate to accumulate.
const HEADING_ARC := 0.4

# Fallback facing for a squad that has never moved. Arbitrary but fixed —
# it must be deterministic, because client and server both derive it.
const DEFAULT_HEADING := Vector2(0.0, 1.0)

# How many times a slot standing on ground its squad could not walk on is
# pulled back toward the squad before it simply stands where the squad
# stands. Four, because the pull is along the offset ray and a quarter of
# a formation's half-width is finer than a hex at every shipped spacing —
# and because this loop only ever runs for the handful of men actually
# over water or rock. A soldier on open ground costs one array lookup.
const PASSABLE_PULL_STEPS := 4


## Offset of one slot within the formation, in formation-local space:
## +x is right, +y is forward. Units are multiples of `spacing`.
##
## Pure in (shape, slot, alive, spacing). Note `alive` is an input: that
## is the casualty restamp.
## `files` overrides the def's own ranks arithmetic when positive — the
## player's ordered WIDTH (D-20260819-facing-and-width-are-orders).
## Grid and scatter kinds honour it; wedge and ring have no files to
## override and ignore it. Clamped to the squad's strength: a 40-file
## order on 12 men is 12 files, not a line with holes.
static func slot_offset(shape: String, slot: int, alive: int, spacing: float,
		files: int = 0) -> Vector2:
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
	return _offset_for(def, index, alive, spacing, files)


## Dispatch to a geometry generator. Adding a `kind` to FormationDef's
## enum means adding a branch HERE — and a roster test fails if a .tres
## names a kind nothing implements, rather than letting it fall through to
## a line and merely look wrong.
static func _offset_for(def: FormationDef, index: int, alive: int,
		spacing: float, files: int = 0) -> Vector2:
	var scaled := spacing * maxf(def.spacing_scale, 0.01)
	var chosen := clampi(files, 1, alive) if files > 0 else _grid_files(def, alive)
	match def.kind:
		"grid":
			return _grid_offset(index, alive, chosen, scaled)
		"scatter":
			return _scatter_offset(index, alive, scaled, chosen, def.jitter)
		"wedge":
			return _wedge_offset(index, scaled)
		"ring":
			return _ring_offset(index, alive, scaled)
		_:
			push_error("FormationDef '%s' has unimplemented kind '%s'" % [def.id, def.kind])
			return _grid_offset(index, alive, _files_for_ranks(alive, LINE_RANKS), scaled)


## The files a squad forms by DEFAULT in `shape` — what a width order of
## "one wider" is one wider THAN. Public because the client's Widen and
## Narrow buttons need the starting point, and deriving it their own way
## would drift from the geometry above.
static func default_files(shape: String, alive: int) -> int:
	var def := FormationRoster.by_id(StringName(shape))
	if def == null or alive <= 0:
		return maxi(alive, 1)
	return _grid_files(def, alive)


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
static func footprint(shape: String, alive: int, spacing: float,
		files: int = 0) -> Dictionary:
	# `files` is in the key or a widened squad would cull, separate and
	# click-test at its old size forever (D-20260819-facing-and-width).
	var key := "%s|%d|%.3f|%d" % [shape, alive, spacing, files]
	if _footprint_cache.has(key):
		return _footprint_cache[key]

	var result := {"centre": Vector2.ZERO, "radius": maxf(spacing, 0.5),
		"lever": maxf(spacing, 0.5)}
	if alive > 0:
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		# The rotation lever arm is measured from the CURVE POINT, not from
		# the footprint centre, because that is what the formation rotates
		# about — soldier_transform() rotates every slot offset about the
		# origin of formation-local space. See turn_lever().
		var lever := 0.0
		for slot in range(alive):
			var p := slot_offset(shape, slot, alive, spacing, files)
			min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
			max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
			lever = maxf(lever, p.length())
		var centre := (min_p + max_p) * 0.5
		# Half the diagonal, so the circle contains the whole extent
		# whichever way the squad is facing. Plus a soldier's own width, so
		# the edge of the marker sits just outside the outermost man rather
		# than bisecting him.
		var half := (max_p - min_p) * 0.5
		result = {"centre": centre, "radius": half.length() + spacing * 0.5,
			"lever": lever}

	_footprint_cache[key] = result
	return result


## How far the outermost soldier stands from the point the formation
## rotates about, in world units.
##
## This is the number that turns a squad's TURN into a soldier's WALK:
## where the path bends, that man covers `1 + lever * curvature` times the
## distance the squad centre does. SquadSim divides its pace by exactly
## that, so no soldier is ever asked to outrun his own move_speed to keep
## his place (D-20260818).
##
## Shares footprint()'s cache and its loop — it is the same scan over the
## same slots, and a second cache keyed the same way would only be another
## thing to keep in step.
static func turn_lever(shape: String, alive: int, spacing: float) -> float:
	return float(footprint(shape, alive, spacing)["lever"])


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
## Derived entirely from the curve: a chord of HEADING_ARC along the path
## ahead while moving, the same chord backwards just after stopping, and
## failing both, a scan back through the keyframes for the last real
## displacement. A stopped squad therefore keeps the facing it arrived
## with WITHOUT anyone storing it.
##
## Forward rather than centred, and that is not a preference: the server
## rebuilds a squad's curve from its CURRENT cell, so neither side holds
## any history to look back into, and the client's copy is clipped to
## [now, now + horizon] on top of that. Looking ahead is the only
## direction with curve in it — which is also how a real formation
## wheels, beginning the turn before the corner rather than at it.
static func heading(curve: StateCurve, time: float) -> Vector2:
	if curve == null or curve.is_empty():
		return DEFAULT_HEADING

	var forward := _chord(curve, time, HEADING_ARC, 1)
	if forward.length_squared() > 1e-8:
		return forward.normalized()

	var backward := _chord(curve, time, HEADING_ARC, -1)
	if backward.length_squared() > 1e-8:
		return (-backward).normalized()

	# Stationary at `time`: find the most recent segment that moved.
	for i in range(curve.key_count() - 1, 0, -1):
		var d := curve.point_at(i) - curve.point_at(i - 1)
		if d.length_squared() > 1e-8:
			return d.normalized()

	return DEFAULT_HEADING


## THE resolver for which way a squad's formation is stamped
## (D-20260819-facing-and-width-are-orders): its path while it moves, its
## ORDERED facing once it stands. One function on purpose — soldier
## derivation on both machines AND combat's aspect term read this, so the
## line a player braced is the line the rear-shock arithmetic sees.
## Nothing else may interpret the ordered value.
##
## `ordered_facing` is a world-space angle in radians (the Basis(UP, a)
## convention: forward is +z), NAN meaning "never ordered". A moving
## squad ignores it: march-facing is what wheeling, pace and the whole
## D-20260818 turning model are built on.
static func facing_angle(curve: StateCurve, time: float, space: TorusSpace,
		ordered_facing: float = NAN) -> float:
	if not is_nan(ordered_facing) and curve != null and not curve.is_empty():
		var forward := _chord(curve, time, HEADING_ARC, 1)
		if forward.length_squared() <= 1e-8:
			return ordered_facing
	var world_dir := space.axial_offset_to_world(heading(curve, time))
	return atan2(world_dir.x, world_dir.z)


## The slot offset a soldier actually stands at: `offset` as the formation
## drew it, or the furthest fraction of it that still lands on ground the
## squad itself could walk on.
##
## ## Why this is here at all (#97)
##
## Passability was enforced on the SQUAD and on nothing else. A squad
## cannot path into water or onto a mountain, but its slot offsets are
## pure geometry, so a squad parked on a beach stamped part of its
## formation into the sea and part of it up the rock behind — and because
## `TerrainGen.surface_field` draws the impassable HIGH class on its own
## lifted tier (D-097's `cliff_rise`, 2.0 world units), a slot crossing
## that boundary did not nudge, it teleported onto the top of the drawn
## cliff. That is the "popping" the playtest reported.
##
## ## Why it stays legal under D-006
##
## `passable` is an INPUT, not remembered state. The answer for a slot
## depends on (curve, shape, slot, alive, spacing, terrain) and nothing
## else, so the same call gives the same result forever and both sides
## derive the same man in the same place. There is no per-soldier nudge
## accumulating anywhere — this is not local avoidance wearing a hat, and
## a soldier that walks back onto open ground gets its full offset again
## the very next frame.
##
## ## Why the pull is toward the squad rather than to the nearest free cell
##
## A nearest-passable-cell walk moves each man his own way, so neighbours
## separate and the formation tears along the shoreline. Pulling along the
## offset ray keeps every man on his own line out from the centre, so the
## block compresses against the water instead of scattering — and the
## fallback is guaranteed: the squad's own cell is passable, because the
## simulation would not have routed it anywhere else.
##
## An empty `passable` means "fully open", the same convention as
## `SquadSim.is_passable`, so a caller with no terrain gets exactly the
## geometry it always got.
static func grounded_offset(centre: Vector3, offset: Vector3, space: TorusSpace,
		passable: PackedByteArray) -> Vector3:
	if passable.is_empty() or _stands_on_passable(centre + offset, space, passable):
		return offset
	for step in range(PASSABLE_PULL_STEPS - 1, 0, -1):
		var pulled := offset * (float(step) / float(PASSABLE_PULL_STEPS))
		if _stands_on_passable(centre + pulled, space, passable):
			return pulled
	return Vector3.ZERO


## Whether the cell containing a world point is one a squad could walk on.
##
## Terrain passability only — never the server's building-stamped copy.
## See `ClientState.terrain_passable` for why that distinction is what
## keeps the two sides deriving the same answer.
static func _stands_on_passable(at: Vector3, space: TorusSpace,
		passable: PackedByteArray) -> bool:
	var index := space.index(space.world_to_cell(at))
	return index >= 0 and index < passable.size() and passable[index] != 0


## The vector from the curve point at `time` to the point `arc` further
## along it, walking in `step` direction (+1 ahead, -1 back). Shorter than
## `arc` when the curve runs out, which is what a squad about to stop
## gets.
##
## Cut at exactly `arc` rather than at the next keyframe, because a chord
## that ended on a keyframe would jump from one segment's direction to the
## next as the squad crossed it — the stepping this exists to remove,
## reintroduced at keyframe granularity.
static func _chord(curve: StateCurve, time: float, arc: float, step: int) -> Vector2:
	var start := curve.sample_axial(time)
	var here := start
	var remaining := arc

	var count := curve.key_count()
	var i := 0
	if step > 0:
		while i < count and curve.time_at(i) <= time:
			i += 1
	else:
		i = count - 1
		while i >= 0 and curve.time_at(i) >= time:
			i -= 1

	while i >= 0 and i < count:
		var leg := curve.point_at(i) - here
		var span := leg.length()
		if span > 0.0:
			if span >= remaining:
				return here + leg * (remaining / span) - start
			remaining -= span
			here = curve.point_at(i)
		i += step
	return here - start


## World transform for a single soldier.
##
## `terrain_height` is the terrain sample from D-006's input tuple. The
## caller supplies it because sampling needs the soldier's XZ, which this
## function computes — see soldier_transforms() for the assembled form.
## `passable` is the other half of that sample (see `grounded_offset`);
## note that a clamped slot moves in XZ, so a height sampled at the
## unclamped position is a height for the wrong spot. The bulk path below
## samples after clamping for exactly that reason.
static func soldier_transform(
	curve: StateCurve,
	time: float,
	slot: int,
	alive: int,
	shape: String,
	spacing: float,
	space: TorusSpace,
	terrain_height: float = 0.0,
	passable: PackedByteArray = PackedByteArray(),
	files: int = 0,
	ordered_facing: float = NAN
) -> Transform3D:
	var centre := curve.sample_world(time, space)

	# The path's heading while moving, the player's ordered facing while
	# standing — resolved in ONE place (facing_angle), the same one
	# combat's aspect reads (D-20260819-facing-and-width-are-orders).
	var angle := facing_angle(curve, time, space, ordered_facing)

	var local := slot_offset(shape, slot, alive, spacing, files)
	# Formation-local +y is forward, which is +z after rotation.
	var offset := grounded_offset(
		centre, Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, angle),
		space, passable)

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
	terrain_sampler := Callable(),
	passable: PackedByteArray = PackedByteArray(),
	files: int = 0,
	ordered_facing: float = NAN
) -> Array[Transform3D]:
	return soldier_transforms_sampled(
		curve, time, alive, shape, spacing, space, terrain_sampler, alive,
		passable, files, ordered_facing)


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
	max_count: int = -1,
	passable: PackedByteArray = PackedByteArray(),
	files: int = 0,
	ordered_facing: float = NAN
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
	var angle := facing_angle(curve, time, space, ordered_facing)
	var basis := Basis(Vector3.UP, angle)
	var sample_terrain := terrain_sampler.is_valid()
	# Hoisted for the same reason everything else here is: without terrain
	# there is nothing to clamp against, and this path derives every
	# soldier on screen every frame.
	var clamp_to_ground := not passable.is_empty()

	out.resize(count)
	for i in range(count):
		# `i * alive / count` is `i` exactly when count == alive (integer
		# division), so the full-detail path is unchanged and stays
		# bit-identical to soldier_transform().
		var slot := i * alive / count
		var local := slot_offset(shape, slot, alive, spacing, files)
		var offset := Vector3(local.x, 0.0, local.y).rotated(Vector3.UP, angle)
		# Clamped BEFORE the height is sampled, so a man pulled back off the
		# rock takes the height of the ground he ends up on rather than of
		# the cliff top he was briefly aimed at.
		if clamp_to_ground:
			offset = grounded_offset(centre, offset, space, passable)
		var origin := centre + offset
		origin.y = terrain_sampler.call(origin.x, origin.z) if sample_terrain else 0.0
		out[i] = Transform3D(basis, origin)
	return out
