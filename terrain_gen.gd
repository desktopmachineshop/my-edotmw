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
@export var axis_repeats: int = 2
## Vertical exaggeration applied when building meshes.
@export var height_scale: float = 2.0

## Normalised thresholds in [0,1].
@export var sea_level: float = 0.38
@export var beach_level: float = 0.44
@export var mountain_level: float = 0.74

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


## Squads cannot cross water or mountains in M1. This is the array the
## flow field routes around (D-007), which is what makes terrain interact
## with pathfinding rather than being decoration.
func passability(space: TorusSpace) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(space.cell_count())
	for i in range(space.cell_count()):
		var e := elevation_at(space, space.from_index(i))
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
	var e := elevation_at(space, cell)

	if e < sea_level * 0.6:
		return Biome.DEEP_WATER
	if e < sea_level:
		return Biome.WATER
	if e < beach_level:
		return Biome.BEACH
	if e >= mountain_level:
		return Biome.PEAK if e > mountain_level + 0.12 else Biome.MOUNTAIN

	var m := moisture_at(space, cell)
	if m < 0.35:
		return Biome.DRY_GRASSLAND
	if m < 0.62:
		return Biome.GRASSLAND
	return Biome.FOREST


## Biome colour for the preview and the terrain mesh — a pure function of
## biome_at(), so the picture and the simulation always agree.
func biome_color(space: TorusSpace, cell: Vector2i) -> Color:
	match biome_at(space, cell):
		Biome.DEEP_WATER:
			return Color(0.05, 0.14, 0.35)
		Biome.WATER:
			return Color(0.12, 0.32, 0.55)
		Biome.BEACH:
			return Color(0.78, 0.72, 0.48)
		Biome.PEAK:
			return Color(0.92, 0.92, 0.95)
		Biome.MOUNTAIN:
			return Color(0.45, 0.44, 0.42)
		Biome.DRY_GRASSLAND:
			return Color(0.68, 0.62, 0.32)
		Biome.GRASSLAND:
			return Color(0.29, 0.52, 0.24)
		_:
			return Color(0.14, 0.36, 0.18)  # forest
