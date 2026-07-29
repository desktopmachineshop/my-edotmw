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
## Roughly how many features fit across the map on each axis.
@export var elevation_frequency: float = 2.5
@export var moisture_frequency: float = 4.0
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
	var u := TAU * float(c.x) / float(space.width)
	var v := TAU * float(c.y) / float(space.height)

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
	var scale := frequency / TAU

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


## Biome colour for the preview and for the (M2+) terrain mesh. Colour
## rather than a biome enum for now: M1 has no gameplay that reads biome,
## and inventing an enum nothing consumes would be speculative.
func biome_color(space: TorusSpace, cell: Vector2i) -> Color:
	var e := elevation_at(space, cell)
	var m := moisture_at(space, cell)

	if e < sea_level * 0.6:
		return Color(0.05, 0.14, 0.35)  # deep water
	if e < sea_level:
		return Color(0.12, 0.32, 0.55)  # shallow water
	if e < beach_level:
		return Color(0.78, 0.72, 0.48)  # beach
	if e >= mountain_level:
		return Color(0.92, 0.92, 0.95) if e > mountain_level + 0.12 else Color(0.45, 0.44, 0.42)
	if m < 0.35:
		return Color(0.68, 0.62, 0.32)  # dry grassland
	if m < 0.62:
		return Color(0.29, 0.52, 0.24)  # grassland
	return Color(0.14, 0.36, 0.18)  # forest
