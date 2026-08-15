extends RefCounted
class_name GroundCover

## Which decorative props dress a cell, where they stand, and how big they are
## (D-100) — the pure half of ground cover, split out the same way
## `ResourceVisuals`, `RenderCull` and `SelectionPick` were (D-045, D-061,
## D-087). The client keeps only the scene-tree plumbing; every choice with an
## interesting failure mode — cacti in a forest, clutter on open water, a prop
## tall enough to hide a soldier — is decided here and is testable headless.
##
## ## This is the deliberate opposite of D-087's resource nodes
##
## The two look alike on screen and share nothing underneath, and the contrast
## is the design rather than an accident of implementation:
##
## | | Resource nodes (D-087) | Ground cover (this) |
## |---|---|---|
## | Owned by | the server; simulation entities | the client; cosmetic only |
## | Fog | gated, with felling events on the wire | NOT gated — a grass tuft leaks nothing |
## | Wire cost | reveal and depletion events | ZERO; nothing goes on the wire |
## | Determinism | server-authoritative | a pure hash of the cell |
##
## Nothing here is replicated, and nothing here should ever become replicated.
## A prop is derived from terrain every client already generated for itself, so
## two clients dress the same map identically for free — the same reason
## `ResourceVisuals` hashes the cell rather than rolling an RNG, minus the
## server. If cover ever acquires a gameplay meaning (concealment, movement
## cost), that is a new decision and a new mechanism, not a change here.
##
## ## Two gameplay rules constrain what may be placed
##
## Props are SHORT — `MAX_PROP_HEIGHT` bounds the authored height times
## `SCALE_MAX`, and `art/scatter/props.py` fails the asset build on anything
## taller — and sparse enough that a unit is never hidden. Unit readability is
## tactical information a player reads off the screen, which is the same reason
## D-045's render LOD draws a distant squad thinner and never smaller.
##
## And a cell already holding something gets no cover: a resource node, a
## building, or a wall. That fact belongs to the simulation, so the CALLER
## passes it in (`occupied`) rather than this module reaching for state a pure
## static class has no business knowing about.
##
## All-static, like `Formation`, `AnimationState` and `ResourceVisuals`: there
## is nowhere to put per-prop state, so nothing here can drift into the
## integration state D-006 forbids.

## The tallest a prop may stand, in world units, after `SCALE_MAX`. A soldier
## is ~1.8 units; this is under a third of one. `art/scatter/props.py` carries
## the authored-height half of the same rule (`MAX_HEIGHT` 0.5) and a test
## asserts the two agree against the SHIPPED meshes — a limit that only exists
## on one side of the language boundary is a limit that drifts.
const MAX_PROP_HEIGHT := 0.58

## Standing size range. Narrower than `ResourceVisuals`'s: a tree is a landmark
## and wants silhouette variety, a tuft of grass wants to disappear into a mass.
const SCALE_MIN := 0.78
const SCALE_MAX := 1.16

## How far from the cell centre a prop may stand, **in units of `hex_size`**.
## The caller multiplies by `space.hex_size` — see `props_for`. A hex's
## inradius is 0.866 of hex_size, so this keeps a prop and its footprint
## clearly inside its own cell and off the boundary its neighbour's props are
## crowding from the other side.
const MAX_OFFSET := 0.60

## The most props one cell may hold, whatever the density table says. A bound
## on the worst case rather than a tuning knob: the client sizes MultiMeshes
## from what it is handed.
const MAX_PER_CELL := 6

## How often a prop borrows a NEIGHBOUR cell's palette instead of its own —
## `ResourceVisuals.BOUNDARY_MIX`'s idea, rolled per PROP rather than per cell,
## so a boundary hex can hold some of each and the two regions interleave
## instead of trading whole cells. Without this a moisture threshold crossing
## a hex reads as a line drawn on the ground.
const BOUNDARY_MIX := 0.35

## Cover thins as ground rises: exposed high ground is windswept and bare,
## sheltered low ground is lush. A smooth multiplier over the raw elevation
## sample and deliberately NOT a threshold — `biome_at`'s ladder is the one
## place elevation thresholds live (D-037), and a second copy here would drift
## from it the way two moisture ladders nearly did before `MOISTURE_DRY`
## became a constant.
const EXPOSURE := 0.30

## Props per cell before moisture and exposure adjust it, by biome. Absent
## means none: water grows nothing, and that is one branch fewer than saying so.
##
## These are the SHIPPED numbers, and the ones tests assert against — a table
## that yields three props on a whole map is the "mechanism right, shipped
## numbers do nothing" defect D-066 paid for.
const BASE_DENSITY := {
	TerrainGen.Biome.FOREST: 5.0,
	TerrainGen.Biome.GRASSLAND: 4.2,
	TerrainGen.Biome.DRY_GRASSLAND: 2.4,
	TerrainGen.Biome.BEACH: 3.0,
	TerrainGen.Biome.MOUNTAIN: 3.0,
	TerrainGen.Biome.PEAK: 1.2,
}

## How much moisture swings a biome's density, as a fraction either way. Dry
## grassland cares most (its whole character is how close to dead it is);
## a beach barely cares at all.
const MOISTURE_SWING := {
	TerrainGen.Biome.FOREST: 0.22,
	TerrainGen.Biome.GRASSLAND: 0.30,
	TerrainGen.Biome.DRY_GRASSLAND: 0.35,
	TerrainGen.Biome.BEACH: 0.10,
	TerrainGen.Biome.MOUNTAIN: 0.12,
	TerrainGen.Biome.PEAK: 0.10,
}

## What grows where: [model, weight] pairs, a DATA TABLE rather than a branch
## per biome, so adding a region's character is adding rows.
##
## Every model here must exist in `generated/models/prop_*.glb`; a test asserts
## it, because a palette naming a model nobody built is cover that silently
## thins out in one biome only.
const PALETTES := {
	TerrainGen.Biome.FOREST: [
		[&"prop_fern", 5], [&"prop_bush", 4], [&"prop_mushrooms", 3],
		[&"prop_moss_rock", 2], [&"prop_log", 1],
	],
	TerrainGen.Biome.GRASSLAND: [
		[&"prop_grass_tuft", 7], [&"prop_wildflowers", 3], [&"prop_bush", 2],
		[&"prop_boulder", 1],
	],
	TerrainGen.Biome.DRY_GRASSLAND: [
		[&"prop_dry_tussock", 6], [&"prop_cracked_slab", 2], [&"prop_cactus", 2],
		[&"prop_boulder", 1],
	],
	TerrainGen.Biome.BEACH: [
		[&"prop_dune_grass", 4], [&"prop_reeds", 3], [&"prop_shell", 2],
		[&"prop_driftwood", 2],
	],
	TerrainGen.Biome.MOUNTAIN: [
		[&"prop_scree", 5], [&"prop_rock_spike", 3], [&"prop_boulder", 2],
	],
	TerrainGen.Biome.PEAK: [
		[&"prop_snow_boulder", 4], [&"prop_scree", 3],
	],
}

## A global thinning knob, read by `props_for` on every cell. It exists so a
## quality setting can trade cover for frame time on weak hardware without
## touching the density table, and so a test can prove density is actually
## wired to something rather than decorative.
##
## Two clients at different settings see different amounts of grass and agree
## about everything that matters, because none of this is simulation. Legal for
## the same reason the whole file is: it is a rendering preference, not state.
static var density_scale := 1.0

# One salt per decision stream, so "which model" and "which way is it facing"
# are independent rolls of the same cell rather than correlated ones. The
# per-prop streams also take the prop's index, which is what stops every prop
# in a cell landing on the same spot.
const _SALT_COUNT := 11
const _SALT_MIX := 12
const _SALT_NEIGHBOUR := 13
const _SALT_MODEL := 14
const _SALT_YAW := 15
const _SALT_SCALE := 16
const _SALT_RADIUS := 17
const _SALT_ANGLE := 18


## Everything standing on `cell`, as an Array of
## `{"model": StringName, "offset": Vector3, "yaw": float, "scale": float}`.
##
## `biome`, `neighbour_biomes`, `moisture` and `elevation` all come from the
## same `TerrainGen` the terrain mesh was built from, so the dressing agrees
## with the ground by construction rather than by two samplers being kept in
## step. `occupied` is the caller's answer to "does this cell already hold a
## resource node, building or wall".
##
## `offset` is in units of hex_size, on the XZ plane with y always 0: the
## caller adds `offset * space.hex_size` to the cell's world position and
## samples terrain height AT THAT POINT, not at the cell centre — on a slope
## the difference is a prop standing in the air.
##
## Deliberately returns everything for one cell in one call. The client builds
## cover once, per chunk, and a per-prop entry point would invite a second
## traversal per frame.
static func props_for(biome: int, neighbour_biomes: Array, moisture: float,
		elevation: float, cell: int, occupied: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if occupied:
		return out

	var density := density_for(biome, moisture, elevation)
	if density <= 0.0:
		return out

	# The fractional part decides by hash whether this cell rounds up, so a
	# density of 3.4 really is 3.4 props per cell across a region instead of 3.
	var count := int(density)
	if _roll(cell, _SALT_COUNT) < density - float(count):
		count += 1
	count = mini(count, MAX_PER_CELL)

	for i in range(count):
		var palette: Array = _palette_for(biome, neighbour_biomes, cell, i)
		if palette.is_empty():
			continue

		# Uniform over the disk: without the square root every prop crowds the
		# centre and cells read as dots rather than as ground.
		var radius := sqrt(_roll_at(cell, _SALT_RADIUS, i)) * MAX_OFFSET
		var angle := _roll_at(cell, _SALT_ANGLE, i) * TAU
		out.append({
			"model": _pick(palette, _roll_at(cell, _SALT_MODEL, i)),
			"offset": Vector3(cos(angle) * radius, 0.0, sin(angle) * radius),
			"yaw": _roll_at(cell, _SALT_YAW, i) * TAU,
			"scale": lerpf(SCALE_MIN, SCALE_MAX, _roll_at(cell, _SALT_SCALE, i)),
		})
	return out


## Expected props on a cell of this ground, before the per-cell rounding roll.
##
## Public because the interesting assertions are about the SHAPE of this
## function — wetter forest is lusher than dry forest, high ground is barer
## than low, water is zero — and testing them through `props_for`'s integer
## count would test the rounding instead.
static func density_for(biome: int, moisture: float, elevation: float) -> float:
	if not BASE_DENSITY.has(biome):
		return 0.0
	var base: float = BASE_DENSITY[biome]
	var swing: float = MOISTURE_SWING.get(biome, 0.0)
	base *= lerpf(1.0 - swing, 1.0 + swing, clampf(moisture, 0.0, 1.0))
	base *= 1.0 - EXPOSURE * clampf(elevation, 0.0, 1.0)
	return maxf(0.0, base * density_scale)


## Every model any palette can name, sorted and deduplicated. The preview
## renders exactly this list, and a test asserts every entry was built — which
## is how a palette naming a model nobody generated gets caught.
static func model_ids() -> Array[StringName]:
	var seen := {}
	for biome in PALETTES:
		for entry in PALETTES[biome]:
			seen[entry[0]] = true
	var out: Array[StringName] = []
	for model in seen:
		out.append(model)
	out.sort()
	return out


## The palette prop `index` on `cell` draws from — its own biome's, or a
## neighbour's when the boundary roll says to fray.
static func _palette_for(biome: int, neighbour_biomes: Array, cell: int,
		index: int) -> Array:
	var ground := biome
	if not neighbour_biomes.is_empty() \
			and _roll_at(cell, _SALT_MIX, index) < BOUNDARY_MIX:
		var pick: int = neighbour_biomes[
			int(_roll_at(cell, _SALT_NEIGHBOUR, index) * neighbour_biomes.size())
				% neighbour_biomes.size()]
		# Only borrow ground something actually grows on: a shoreline cell must
		# not roll "deep water" and come up empty. The COUNT stays the cell's
		# own, so a beach never takes on forest density, only forest species.
		if PALETTES.has(pick):
			ground = pick
	return PALETTES.get(ground, [])


## Weighted pick from a palette. Weights are small integers and palettes are
## four or five rows, so the linear walk is cheaper than anything precomputed
## and has nowhere to cache a stale total.
static func _pick(palette: Array, roll: float) -> StringName:
	var total := 0
	for entry in palette:
		total += int(entry[1])
	var target := roll * float(total)
	var running := 0.0
	for entry in palette:
		running += float(entry[1])
		if target < running:
			return entry[0]
	return palette[palette.size() - 1][0]


## Deterministic roll in [0, 1) from (cell, salt) — Combat's `_roll_unit` FNV
## mixing, for the same bit-identical-everywhere reason.
const _FNV_PRIME := 0x01000193


static func _roll(cell: int, salt: int) -> float:
	var h := 0x811C9DC5
	h = ((h ^ (cell & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (salt & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * _FNV_PRIME) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / float(0x1000000)


## The same roll for prop `index` of a cell. A third mixed input rather than
## `salt + index`, which would make prop 0's yaw stream and prop 1's scale
## stream the same numbers whenever two salts sit one apart.
static func _roll_at(cell: int, salt: int, index: int) -> float:
	var h := 0x811C9DC5
	h = ((h ^ (cell & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (salt & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (index & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * _FNV_PRIME) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / float(0x1000000)
