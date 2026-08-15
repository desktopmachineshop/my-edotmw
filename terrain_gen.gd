extends Resource
class_name TerrainGen

## Terrain field generation over the torus (D-017), data-driven so
## parameters can be tuned in a .tres rather than in code.
##
## ## Periodic noise is mandatory here, not a nicety
##
## D-008 lists "periodic noise sampling" as one of the places the torus
## tax lands. Ordinary 2D noise sampled over a wrapped grid produces a
## visible discontinuity at both seams: mountains that stop mid-range, a
## coastline that doesn't meet itself.
##
## The fix is to sample 3D noise along a torus embedded in 3-space. As the
## grid coordinate walks once around either axis, the sample point walks
## once around the corresponding circle and returns exactly to where it
## started — so the field is periodic by construction rather than by
## blending seams afterwards.
##
## M1 scope: this exists to give `gen-terrain-preview` something real to
## chunk and to give the flow field something to route around (D-022
## explicitly excludes terrain generation beyond that).

@export var noise_seed: int = 1337
## Roughly how many features fit across the map on each axis. Independent
## of `axis_repeats` — see _sample, which divides the noise scale by the
## repeat count so raising symmetry does not silently shrink features.
@export var elevation_frequency: float = 2.5
@export var moisture_frequency: float = 4.0

## How many times the field repeats along each axis (D-036).
##
## 1 is ordinary terrain. **2 makes the four quadrants bit-identical**,
## which is how M3 guarantees 4-player spawn fairness: the generator walks
## twice around each circle of the embedding torus, so cell (x, y) and
## cell (x + width/2, y) map to exactly the same sample point and cannot
## differ. Fairness becomes a property of the generator rather than
## something scored and validated after the fact — there is no heuristic
## to tune and no seed to reject.
##
## The repeat count must divide the map's width and height, and it is
## tied to the player count: 2 serves 4, 2 or 1 players. Changing the
## player count is therefore a map-generation change, not a config tweak.
@export var axis_repeats: int = 1
## Vertical exaggeration applied when building meshes. 15.0 (up from 2.0) is
## the "for now" default requested after a live look at extreme relief —
## purely cosmetic (surface_field is the only reader; passability still
## thresholds the unscaled elevation_field, so this cannot change which
## ground is walkable).
@export var height_scale: float = 15.0

## How much of its OWN elevation a cell's centre vertex keeps, against the mean
## of that cell's six (shared) corners (D-096).
##
## 1.0 is the pre-D-096 behaviour: the centre sat at the cell's own elevation
## while every corner was averaged with two neighbours, which made each hex a
## shallow dome. `surface_field`'s own comment used to call that a feature —
## "keeps the hex grid faintly readable" — and it is precisely what made the
## ground read as a honeycomb of flat hexes once the terrain was textured.
##
## 0.0 would flatten a cell to the plane of its corners and lose the cell's
## true height at its centre entirely. 0.15 keeps a trace of it — enough that a
## lone high cell still bulges — without the lighting picking the lattice out.
##
## Purely cosmetic, like `height_scale`: `build_fields` is the only reader, and
## `passability` still thresholds the unscaled elevation. It is therefore not
## on the wire, and both sides using their own default cannot desync.
@export_range(0.0, 1.0, 0.01) var pillow: float = 0.15

## Normalised thresholds in [0,1].
@export var sea_level: float = 0.38
@export var beach_level: float = 0.44
@export var mountain_level: float = 0.74

## Moisture thresholds splitting land into dry grassland / grassland /
## forest. Constants rather than exports because `Economy.generate` shapes
## its tree densities against the same boundaries `biome_at` classifies
## with — two copies of these numbers would let "how dense is a forest"
## drift away from "what is a forest".
const MOISTURE_DRY := 0.35
const MOISTURE_FOREST := 0.62

# Bounds on the sampling torus's minor radius. The actual value tracks
# the map's aspect ratio (see _sample) so features come out about as
# large in cells vertically as horizontally; these just keep the torus
# from degenerating or self-intersecting on extreme map shapes.
const MIN_MINOR_RADIUS := 0.15
const MAX_MINOR_RADIUS := 0.8

var _elevation_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite


func _ensure_noise() -> void:
	if _elevation_noise != null:
		return
	_elevation_noise = FastNoiseLite.new()
	_elevation_noise.seed = noise_seed
	_elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elevation_noise.fractal_octaves = 4
	# FastNoiseLite applies its OWN frequency (default 0.01) on top of the
	# sample coordinates. Since our sample points live on a unit-ish torus
	# — coordinates in roughly [-1.35, 1.35] — that default scales them
	# down to a span of ~0.03 in noise space, which is flat enough that
	# the whole map comes out one elevation. Feature scale is controlled
	# here by elevation_frequency instead, so this must be 1.0.
	_elevation_noise.frequency = 1.0

	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = noise_seed + 7919
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moisture_noise.fractal_octaves = 3
	_moisture_noise.frequency = 1.0


## Sample a noise field at a cell, periodically in both axes.
func _sample(noise: FastNoiseLite, space: TorusSpace, cell: Vector2i, frequency: float) -> float:
	var c := space.normalize(cell)

	# `repeats` laps of each circle instead of one. Because u and v are
	# ANGLES, walking round twice returns to exactly the same embedding
	# point at the halfway cell — so quadrant symmetry is exact, not
	# approximate, and costs nothing at runtime (D-036).
	var repeats := maxi(1, axis_repeats)
	var u := TAU * float(repeats) * float(c.x) / float(space.width)
	var v := TAU * float(repeats) * float(c.y) / float(space.height)

	# Minor radius tracks the map's aspect ratio, so a 64x32 map gets
	# features that are about as many cells tall as they are wide. With a
	# fixed minor radius the vertical axis is compressed relative to the
	# horizontal and terrain comes out visibly banded.
	var minor := clampf(float(space.height) / float(space.width),
		MIN_MINOR_RADIUS, MAX_MINOR_RADIUS)

	var ring := 1.0 + minor * cos(v)
	var x := ring * cos(u)
	var y := ring * sin(u)
	var z := minor * sin(v)

	# `frequency` reads as "features across the map's long axis". One full
	# lap of u covers TAU units of embedding space, so dividing by TAU
	# converts that intent into noise-space units.
	#
	# Getting this wrong is not subtle but IS silent: too large and every
	# cell samples an independent point, producing per-cell static that
	# still looks superficially like terrain in aggregate statistics
	# (sensible water fraction, sensible biome spread) while having no
	# coherent landmasses at all.
	# Divided by the repeat count too. The sample point now travels
	# `repeats` laps, so without this a symmetric map would draw the same
	# terrain at half the feature size and `elevation_frequency` would
	# quietly mean something different depending on symmetry. With it, the
	# two settings are independent: symmetry changes how often the field
	# repeats, frequency changes how big its features are.
	var scale := frequency / (TAU * float(repeats))

	# get_noise_3d returns roughly [-1,1]; normalise to [0,1].
	return clampf(noise.get_noise_3d(x * scale, y * scale, z * scale) * 0.5 + 0.5, 0.0, 1.0)


func elevation_at(space: TorusSpace, cell: Vector2i) -> float:
	_ensure_noise()
	return _sample(_elevation_noise, space, cell, elevation_frequency)


func moisture_at(space: TorusSpace, cell: Vector2i) -> float:
	_ensure_noise()
	return _sample(_moisture_noise, space, cell, moisture_frequency)


func is_water(space: TorusSpace, cell: Vector2i) -> bool:
	return elevation_at(space, cell) < sea_level


## Elevation for every cell, computed once (D-045).
##
## `elevation_at` evaluates 3D simplex noise on every call, and the
## client's terrain sampler — D-006's fourth input — calls it once **per
## soldier per frame**. At D-018's full scale that is ~26,600 noise
## evaluations a frame, and the render benchmark measured the sampler as
## the dominant term in a frame that was 97% CPU.
##
## This is memoisation, not approximation: same generator, same cells,
## identical values by construction. Anything sampling terrain more than
## once per cell should use this rather than calling `elevation_at` in a
## loop — the same rule `TorusSpace.disk_offsets` established for radius
## scans after vision cost 232 µs/squad doing the equivalent.
func elevation_field(space: TorusSpace) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(space.cell_count())
	for i in range(space.cell_count()):
		out[i] = elevation_at(space, space.from_index(i))
	return out


## Vertices per cell in `surface_field`: the centre, then 6 corners in the
## same order `TerrainChunk` emits them.
const SURFACE_STRIDE := 7


## The three cells that meet at corner `corner` of cell `cell_index`, as cell
## indices SORTED ascending (D-096).
##
## Corner k lies between two neighbours. With `TorusSpace.DIRECTIONS` ordered
## counter-clockwise from east and corner k drawn at (60k - 30) degrees, those
## are directions (1 - k) and (-k) — the relationship `surface_field` has always
## used and `TerrainChunk._corner_normal` re-derived by hand.
##
## ## Why sorted
##
## All three owners of a corner must produce the SAME value for it, or the
## surface is not watertight. Each owner enumerates the same three cells but in
## its own order, and floating-point addition is not associative, so
## `(a + b + c) / 3` computed three ways can differ in the last bit. Sorting
## first makes the three sums bit-identical, which turns "watertight" from a
## property checked against a tolerance into a property of the arithmetic.
##
## That mattered little for heights and matters a great deal for what D-096
## adds on top of it: a vertex's blended colour, and (with the shader) its
## atlas tile weights, both of which are chosen from the same triple.
static func corner_cells(space: TorusSpace, cell_index: int, corner: int) -> Vector3i:
	var a := space.neighbor_index(cell_index, 1 - corner)
	var b := space.neighbor_index(cell_index, -corner)
	var lo := mini(cell_index, mini(a, b))
	var hi := maxi(cell_index, maxi(a, b))
	return Vector3i(lo, cell_index + a + b - lo - hi, hi)


## The RENDERED height of every vertex of every cell, in world units (D-067).
##
## This is the surface the ground is drawn as, and it is deliberately NOT the
## same thing as `elevation_field`. Elevation stays discrete per cell — it is
## what `passability` thresholds and what the flow field routes around — while
## the surface interpolates, so the picture is continuous without the simulation
## acquiring a notion of slope.
##
## ## Why corners are shared
##
## Each hex corner is a point where three cells meet, and it takes the MEAN of
## those three elevations. Neighbours therefore agree at every shared corner and
## the surface is watertight. Before this, every vertex of a cell sat at that
## cell's single elevation, so each hex was a flat plateau — and since elevation
## comes from continuous noise sampled per cell, essentially no two neighbours
## shared a height. The result was a small vertical wall at almost every
## boundary that nothing drew, which read as dark seams across the whole map.
##
## The CENTRE vertex used to keep the cell's own elevation outright, which made
## each hex a shallow dome — "keeps the hex grid faintly readable", said the
## comment that lived here, and that readability is exactly what D-096 removes.
## It now sits at `lerp(mean of its own six corners, own elevation, pillow)`.
##
## ## Water
##
## Every contributing elevation is clamped up to `sea_level` first, so all
## sub-sea variation flattens and the sea reads as a sea. Clamping BEFORE the
## average rather than special-casing water cells afterwards is what keeps the
## shoreline watertight: a water cell and the beach beside it still agree at
## their shared corner. The cost is that the water within one cell of land lifts
## by a fraction of the land's height above sea level, which at beach_level -
## sea_level is a few hundredths of a world unit.
##
## Returns `SURFACE_STRIDE` floats per cell: centre first, then corners 0..5.
## One array, read by both the mesher and the client's ground sampler, so the
## two cannot disagree about where the ground is — which is exactly the bug that
## would leave soldiers floating.
func surface_field(space: TorusSpace) -> PackedFloat32Array:
	return build_fields(space).surface


## Every per-cell and per-vertex field the mesher needs, in one pass (D-096).
##
## Heights, colours, biomes and passability all walk the same cells and share
## the same corner-averaging rule, so they are built together: separate builders
## would evaluate the elevation noise once each, and — worse — could be paired
## up wrongly by a caller. See `terrain_fields.gd` for that argument in full.
##
## Colour is blended at shared corners by exactly the trick D-084 used for
## heights: a corner takes the mean of the three cells meeting there, a centre
## keeps its own. `biome_color` remains the single source of truth (D-083) and
## is still what the minimap and the terrain preview read per cell — the blend
## is DERIVED from it, so the small picture and the big one cannot drift.
func build_fields(space: TorusSpace) -> TerrainFields:
	var count := space.cell_count()
	var raw := elevation_field(space)

	var fields := TerrainFields.new()
	fields.biome.resize(count)
	fields.passable.resize(count)

	# Clamped once up front rather than inside the corner loop, where each cell
	# is read six times by its neighbours.
	var clamped := PackedFloat32Array()
	clamped.resize(count)
	# One colour per CELL, from which the per-vertex colours below are averaged.
	# Deriving a corner's colour by calling biome_color for its three owners
	# would evaluate the elevation and moisture noise eighteen times per hex.
	var cell_color := PackedColorArray()
	cell_color.resize(count)

	for i in range(count):
		var e := raw[i]
		var cell := space.from_index(i)
		var b := _classify(space, cell, e)
		fields.biome[i] = int(b)
		# The identical predicate `passability()` applies, spelled once here so
		# the rendering side and the flow field cannot drift (D-097).
		fields.passable[i] = 0 if (e < sea_level or e >= mountain_level) else 1
		clamped[i] = maxf(e, sea_level)
		cell_color[i] = color_of(b)

	fields.surface.resize(count * SURFACE_STRIDE)
	fields.colors.resize(count * SURFACE_STRIDE)
	for i in range(count):
		var base := i * SURFACE_STRIDE
		var corner_total := 0.0
		for k in range(6):
			var trio := corner_cells(space, i, k)
			var height := (clamped[trio.x] + clamped[trio.y] + clamped[trio.z]) \
				/ 3.0 * height_scale
			fields.surface[base + 1 + k] = height
			fields.colors[base + 1 + k] = (cell_color[trio.x] + cell_color[trio.y] \
				+ cell_color[trio.z]) / 3.0
			corner_total += height
		# The pillow, as a tunable rather than an implicit 1.0 — see `pillow`.
		fields.surface[base] = lerpf(corner_total / 6.0,
			clamped[i] * height_scale, pillow)
		fields.colors[base] = cell_color[i]
	return fields


## Squads cannot cross water or mountains in M1. This is the array the
## flow field routes around (D-007), which is what makes terrain interact
## with pathfinding rather than being decoration.
func passability(space: TorusSpace) -> PackedByteArray:
	var field := elevation_field(space)
	var out := PackedByteArray()
	out.resize(space.cell_count())
	for i in range(space.cell_count()):
		var e := field[i]
		out[i] = 0 if (e < sea_level or e >= mountain_level) else 1
	return out


## Biome as simulation data (D-037).
##
## This used to be colour only, with a comment explaining that an enum
## nothing consumed would be speculative. M3 makes that false: resource
## nodes are derived from biome (forest gives wood, mountain gives stone),
## so biome is now something the simulation reads, not just something the
## renderer paints.
enum Biome { DEEP_WATER, WATER, BEACH, DRY_GRASSLAND, GRASSLAND, FOREST, MOUNTAIN, PEAK }


## The single classification. `biome_color` paints whatever this returns,
## so colour and gameplay cannot drift apart — a cell that looks like
## forest is a cell that yields wood, by construction rather than by two
## threshold ladders being kept in sync by hand.
func biome_at(space: TorusSpace, cell: Vector2i) -> Biome:
	return _classify(space, cell, elevation_at(space, cell))


## `biome_at` with the elevation already in hand, so `build_fields` can classify
## the whole map from `elevation_field` instead of re-evaluating the noise per
## cell. Split out rather than duplicated: two ladders of thresholds kept in
## step by hand is precisely what `biome_at`'s own comment warns against.
func _classify(space: TorusSpace, cell: Vector2i, e: float) -> Biome:
	if e < sea_level * 0.6:
		return Biome.DEEP_WATER
	if e < sea_level:
		return Biome.WATER
	if e < beach_level:
		return Biome.BEACH
	if e >= mountain_level:
		return Biome.PEAK if e > mountain_level + 0.12 else Biome.MOUNTAIN

	var m := moisture_at(space, cell)
	if m < MOISTURE_DRY:
		return Biome.DRY_GRASSLAND
	if m < MOISTURE_FOREST:
		return Biome.GRASSLAND
	return Biome.FOREST


## Biome colour for the preview and the terrain mesh — a pure function of
## biome_at(), so the picture and the simulation always agree.
##
## Re-tuned for D-080's lighting rig (`world_look.gd`): ACES compresses
## highlights and desaturates midtones, and ambient now samples a blue sky
## instead of a flat grey, so the pre-D-080 values read muddier and
## cooler than they were authored to. The two darkest biomes (deep water,
## forest) are lifted the most — those are the values closest to crushing
## toward black under the tonemap — and the land biomes are warmed
## slightly to offset the sky-tinted ambient pushing everything blue.
## Relative ordering (deep water darker than water, forest darker than
## grassland) is preserved on purpose: that hierarchy is what a player
## reads at a glance, and `biome_at()` — the thing that actually gates
## passability — is untouched.
func biome_color(space: TorusSpace, cell: Vector2i) -> Color:
	return color_of(biome_at(space, cell))


## The colour of a biome, with the classification already done.
##
## Static and taking the enum rather than a cell, so `build_fields` can paint
## from `fields.biome` without re-sampling the noise — and so this stays the ONE
## table of colours that `biome_color`, the minimap and the mesh all read.
static func color_of(biome: Biome) -> Color:
	match biome:
		Biome.DEEP_WATER:
			return Color(0.08, 0.20, 0.42)
		Biome.WATER:
			return Color(0.16, 0.38, 0.60)
		Biome.BEACH:
			return Color(0.82, 0.74, 0.46)
		Biome.PEAK:
			return Color(0.93, 0.93, 0.96)
		Biome.MOUNTAIN:
			return Color(0.48, 0.46, 0.44)
		Biome.DRY_GRASSLAND:
			return Color(0.72, 0.64, 0.30)
		Biome.GRASSLAND:
			return Color(0.30, 0.56, 0.24)
		_:
			return Color(0.16, 0.40, 0.19)  # forest
