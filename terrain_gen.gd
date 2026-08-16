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
## Feature size, expressed as "how many features fit across a map of
## `REFERENCE_WIDTH` cells" (D-105). Higher means smaller landmasses.
##
## Read that as a DENSITY, not as a count: `_sample_at` scales it by the
## map's own width, so a landmass comes out the same size IN CELLS at
## every map size and a bigger map holds proportionally more of them.
## Before D-105 this was a count per map, which made map size a
## resolution control — a Huge map was the same two continents as a
## Skirmish map, each 16x larger.
##
## Independent of `axis_repeats` — see `_sample_at`, which divides the
## noise scale by the repeat count so raising symmetry does not silently
## shrink features.
@export var elevation_frequency: float = 2.5
## The same units, for the field `_classify` splits grassland/forest with.
## Scaled by map width for the same reason: biome patches that grew with
## the map would leave a Huge map with the same handful of forests.
@export var moisture_frequency: float = 4.0

## The map width every shipped frequency is calibrated against (D-105).
##
## 84 is the Standard lobby size (`MapSettings.sizes()`), chosen so every
## preset's tuned numbers keep exactly the meaning they were authored
## with — `continents` at Standard is bit-identical before and after
## D-105, which is what let the change land without re-tuning /terrain.
const REFERENCE_WIDTH := 84.0

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
var _warp_noise: FastNoiseLite


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

	# The blend warp (D-096 amendment). Two octaves, because this only has to
	# wander — detail in it would read as noise on the coastline rather than as
	# a coastline.
	_warp_noise = FastNoiseLite.new()
	_warp_noise.seed = noise_seed + 15485
	_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp_noise.fractal_octaves = 2
	_warp_noise.frequency = 1.0


## Sample a noise field at a cell, periodically in both axes.
func _sample(noise: FastNoiseLite, space: TorusSpace, cell: Vector2i, frequency: float) -> float:
	var c := space.normalize(cell)
	return _sample_at(noise, space, Vector2(c), frequency)


## The same sampling at a CONTINUOUS axial coordinate.
##
## `_sample` is the per-cell case of this and delegates to it, so there is one
## embedding and not two to keep in step. The continuous form exists for the
## blend warp (D-096 amendment), which has to sample at hex CORNERS — points
## that fall between cells by construction.
##
## Periodicity survives the generalisation for the reason the header gives: u
## and v are angles, so any real coordinate maps onto the same circles and a
## point one full map period away lands on exactly the same embedding point.
## That is what lets the warp meander a biome boundary without tearing the seam.
func _sample_at(noise: FastNoiseLite, space: TorusSpace, point: Vector2,
		frequency: float) -> float:
	var c := point

	# `repeats` laps of each circle instead of one. Because u and v are
	# ANGLES, walking round twice returns to exactly the same embedding
	# point at the halfway cell — so quadrant symmetry is exact, not
	# approximate, and costs nothing at runtime (D-036).
	var repeats := maxi(1, axis_repeats)
	var u := TAU * float(repeats) * c.x / float(space.width)
	var v := TAU * float(repeats) * c.y / float(space.height)

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

	# `frequency` reads as "features across a REFERENCE_WIDTH-cell map".
	# One full lap of u covers TAU units of embedding space, so dividing by
	# TAU converts that intent into noise-space units.
	#
	# Multiplied by the map's width in reference widths (D-105), which is
	# what makes a feature a size in CELLS rather than a fraction of the
	# map. Without it the noise is parameterised over the unit torus and
	# every map, at every size, is the same world at a different
	# resolution — measured on `continents`/1337: two landmasses covering
	# 39% and 78% of the map at Standard, Large and Huge alike.
	#
	# Periodicity survives it exactly. u and v are ANGLES, so scaling the
	# embedded torus uniformly in noise space cannot move where the field
	# meets itself; D-008's wrap guarantees hold for any real frequency.
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
	var scale := effective_frequency(space, frequency) / (TAU * float(repeats))

	# get_noise_3d returns roughly [-1,1]; normalise to [0,1].
	return clampf(noise.get_noise_3d(x * scale, y * scale, z * scale) * 0.5 + 0.5, 0.0, 1.0)


## `frequency` as the noise field actually uses it on THIS map (D-105).
##
## The ONE place map size enters feature scale, so elevation, moisture and
## the blend warp are all treated alike by construction — a size term
## applied per-field would have left biome patches map-sized while
## landmasses became cell-sized, which is half a fix.
static func effective_frequency(space: TorusSpace, frequency: float) -> float:
	return frequency * float(space.width) / REFERENCE_WIDTH


## How wide, in CELLS, a feature at `frequency` comes out — at ANY map size.
##
## The inverse of the above, and the number worth showing a human: the
## lobby's slider is labelled in these units (D-105), because "landmass
## count" stopped being a property of the parameter the moment the
## parameter stopped depending on the map.
static func feature_cells(frequency: float) -> float:
	return REFERENCE_WIDTH / maxf(frequency, 0.0001)


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


## The corner index each of a corner's OTHER two owners files the same physical
## point under.
##
## `.x` belongs to the neighbour in direction (1 - corner) and `.y` to the one
## in direction (-corner) — the same two `corner_cells` collects, before it
## sorts them. Needed by anything that has to read both sides of a corner out of
## one array: the cliff skirt, and the corner normal now that a corner can carry
## two heights.
static func corner_partners(corner: int) -> Vector2i:
	return Vector2i(posmod(2 + corner, 6), posmod(4 + corner, 6))


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


## How far, as a fraction of a hex's radius, the blend boundary between two
## biomes is allowed to wander off the lattice (D-096 amendment, 2026-08-15).
##
## ## The defect this fixes, and why D-096 alone did not
##
## D-096 blends a shared corner over the three cells meeting there, which makes
## every transition exactly one cell wide. At a LOW-contrast boundary — grass to
## dry grass, sand to grass — that is plenty, and it reads as soft. At the
## highest-contrast boundary on the map, sand against water, one cell of feather
## is still one HEX of feather: the 50% contour runs along the hex edges,
## because that is precisely where the three weights are equal, and the eye
## reads the resulting chain of arcs as a scalloped lattice.
##
## Feathering harder does not help. A wider soft band centred on the same
## contour is still centred on the lattice. So this moves the CONTOUR instead:
## each corner's three weights are skewed by a low-frequency noise field, and
## the boundary meanders across cells rather than along them.
##
## 0.0 disables the warp exactly, restoring D-096's equal thirds — which is what
## the test guarding this perturbs to.
@export var blend_warp: float = 2.0

## How much of its own six (already blended) corners a cell's CENTRE takes,
## against its own biome colour (D-096 amendment).
##
## The warp alone was not enough, and the pictures say why. Warping moves the
## boundary off the lattice but the transition is still exactly one cell wide,
## because a corner is the only vertex that mixes biomes at all. At sand against
## water — the highest contrast on the map — one cell is one HEX, so the eye
## still finds the cell.
##
## This widens the band to roughly two cells for three lines of arithmetic and
## no extra sampling: a corner already carries a third of each of its three
## owners, so averaging the six of them and pulling the centre partway toward
## that reaches the neighbours' neighbours.
##
## ## What it costs, stated precisely
##
## D-096 said the centre vertex carries `biome_color` EXACTLY, so the minimap
## and the 3D view could not drift. That now holds for every cell whose six
## neighbours share its biome — which is most of any map — and is deliberately
## relaxed at boundaries, where the whole point is that the colour is on its way
## to being the neighbour's. `tests/test_terrain_continuity.gd` asserts the
## interior case exactly rather than loosening the check to a tolerance
## everywhere, so the invariant that survives is still a real one.
##
## 0.0 restores D-096's original centre, and is what the guarding test perturbs
## to. Above about 0.6 the sand starts washing into the grassland inland, where
## there was never a problem — 0.45 was chosen by looking at both.
@export var centre_bleed: float = 0.45

## Feature size of the warp field, in the same units as
## `elevation_frequency` — features across a `REFERENCE_WIDTH`-cell map.
## High enough that the boundary wanders every few cells rather than bulging
## once across a whole coastline, low enough that it does not become per-cell
## static, which would read as a noisy shoreline rather than a natural one.
##
## "Every few cells" is a CELL-relative intent, and before D-105 it was
## expressed in map-relative units — so at Huge the warp wandered every ~7.6
## cells where Standard got ~3.8, and the shoreline it was written to
## de-scallop came out scalloped again at exactly the sizes nobody looked at.
## Scaling by map width inside `_sample_at` makes 22.0 mean ~3.8 cells at
## every size, which is what this number was chosen against.
@export var blend_warp_frequency: float = 22.0

## How fast an owner's weight falls off as the warped point moves away from its
## centre, as a fraction of a hex's radius. Sized so the shipped `blend_warp`
## skews the weights substantially without ever driving one to zero — a zero
## weight makes the blend a hard choice again, and the boundary comes out crisp
## and wiggly instead of soft and wiggly.
const WEIGHT_FALLOFF := 1.6

## A constant offset in cell space, used to read a second, uncorrelated
## component out of one noise field. Deliberately not a small integer: an
## integer offset would correlate the two components on the lattice.
const WARP_DECORRELATION := Vector2(37.31, 19.73)


## How much each of a corner's three owners contributes to it (D-096 amendment).
##
## Returns one weight per member of `trio`, in `trio`'s order, summing to 1.
##
## ## Why every input is derived from the SORTED trio
##
## All three owners of a corner must compute the identical triple, or the ground
## tears at a boundary in exactly the way D-096 exists to prevent. Two things
## would break that if this were written the obvious way:
##
## - Sampling the warp at a CELL's position skews every corner of that cell the
##   same way, which shifts a boundary rather than bending it, and gives the
##   three owners three different answers. So the sample point is the corner's
##   own position.
## - Deriving that position in the caller's own frame makes it a different
##   float on each side of a seam. The same embedding point, and so the same
##   noise value in exact arithmetic — but not bit for bit. So the frame is the
##   LOWEST-INDEXED owner's, which all three agree on because `corner_cells`
##   sorts, exactly as it does for heights and colours.
##
## Unwarped, a corner is equidistant from its three centres and the weights come
## out as exact thirds — D-096's original blend, recovered rather than
## approximated. The warp displaces the point those distances are measured from;
## a centre it moves toward gains weight, and the boundary moves with it.
##
## Periodic, because `_sample_at` is: a corner one map period away samples the
## same embedding point, so the nine lattice copies (D-035) agree.
func corner_weights(space: TorusSpace, cell_index: int, corner: int,
		trio: Vector3i) -> Vector3:
	var third := 1.0 / 3.0
	if blend_warp <= 0.0:
		return Vector3(third, third, third)
	_ensure_noise()

	# The three owners as SMALL INTEGER offsets in this cell's own frame — no
	# wrapping and, deliberately, no `TorusSpace.delta`. delta() searches nine
	# ghost copies and is the hottest function in the simulation; called twice
	# per corner it cost five seconds of terrain build on the standard map,
	# which is the `distance()`-per-candidate defect in its sixth outfit.
	var here := space.from_index(cell_index)
	var local_a := TorusSpace.DIRECTIONS[posmod(1 - corner, 6)]
	var local_b := TorusSpace.DIRECTIONS[posmod(-corner, 6)]
	var index_a := space.index(here + local_a)
	var index_b := space.index(here + local_b)

	# Re-expressed in the LOWEST-INDEXED owner's frame, and ordered to match
	# `trio`. Both are what make the three owners agree bit for bit.
	var offsets := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var base_offset := Vector2i.ZERO
	for m in range(3):
		var owner := trio[m]
		var own_offset := Vector2i.ZERO
		if owner == index_a and owner != cell_index:
			own_offset = local_a
		elif owner == index_b and owner != cell_index:
			own_offset = local_b
		offsets[m] = Vector2(own_offset)
		if owner == trio.x:
			base_offset = own_offset
	for m in range(3):
		offsets[m] -= Vector2(base_offset)

	# A hex corner is the circumcentre of the three cell centres meeting there,
	# which for an equilateral triangle is their centroid.
	var corner_offset: Vector2 = (offsets[0] + offsets[1] + offsets[2]) / 3.0
	var sample_point := Vector2(space.from_index(trio.x)) + corner_offset

	var amplitude := blend_warp * space.hex_size
	var warped := space.axial_offset_to_world(corner_offset)
	warped.x += (_sample_at(_warp_noise, space, sample_point,
		blend_warp_frequency) * 2.0 - 1.0) * amplitude
	warped.z += (_sample_at(_warp_noise, space,
		sample_point + WARP_DECORRELATION, blend_warp_frequency) * 2.0 - 1.0) * amplitude

	# World distances, not axial ones: the axial basis is not orthogonal, so an
	# axial length would stretch the warp along one diagonal.
	var falloff := WEIGHT_FALLOFF * space.hex_size
	var weights := Vector3.ZERO
	for m in range(3):
		var centre := space.axial_offset_to_world(offsets[m])
		weights[m] = maxf(0.0,
			1.0 + (space.hex_size - centre.distance_to(warped)) / falloff)

	var total := weights.x + weights.y + weights.z
	if total <= 0.0:
		return Vector3(third, third, third)
	return weights / total


## The three classes of ground the rendered surface is allowed to STEP between
## (D-097).
##
## This is `passability` split by WHICH of its two reasons applies, and nothing
## else: `passable` is true exactly when the class is LAND, which
## `tests/test_terrain_cliffs.gd` asserts cell by cell on the shipped map. A
## cliff must be a drawing of the predicate the flow field already routes
## around — two definitions that could disagree is how this project has been
## bitten before.
##
## Water and mountain need separate classes even though both are impassable: a
## corner where a lake meets a peak would otherwise average sea level with rock
## and hang the surface halfway up the mountainside.
enum CliffClass { WATER, LAND, HIGH }


## Which class a biome belongs to. Derived from the biome rather than
## re-thresholding the elevation, so there is one ladder of thresholds and not
## two to keep in step (`biome_at`'s own warning).
static func cliff_class_of(biome: Biome) -> CliffClass:
	match biome:
		Biome.DEEP_WATER, Biome.WATER:
			return CliffClass.WATER
		Biome.MOUNTAIN, Biome.PEAK:
			return CliffClass.HIGH
		_:
			return CliffClass.LAND


## The smallest step, in WORLD units, that is drawn as a cliff rather than
## smoothed away (D-097).
##
## The corner-averaging that makes the surface watertight (D-084) also averages
## ACROSS the passability boundary, which is what turned every mountain into a
## smooth ramp that happened to be grey. Averaging within a class instead gives
## the corner two heights and a real vertical face — but applied to every class
## boundary it would also put a hard lip along every shoreline, where the land
## beside the water is usually only a few hundredths above sea level.
##
## So classes whose heights differ by less than this MERGE at that corner, and
## the two results fall out of one mechanism: a highland dropping into the sea
## gives a sea cliff, a beach sloping into it draws no skirt at all and reads as
## a shore.
##
## In world units rather than raw elevation because a cliff is a thing you see:
## `height_scale` is a per-preset knob and this is a fraction of a hex's width
## whatever it is set to.
##
## 0.4 was chosen from a measurement, not by eye. The natural step where two
## classes meet on the shipped map is small — median 0.20 world units along the
## coast, p90 0.65, and 0.66 at a mountain foot — because elevation is smooth
## noise and `passability` is a level set on it, so the ground genuinely does
## ramp across the boundary. At 0.8 only 87 faces were drawn on the whole map,
## which is the "mechanism correct, shipped numbers do nothing" failure exactly.
## At 0.4 roughly a quarter of the coastline gets a rock ledge and the rest
## keeps its beach, which is the shore-versus-sea-cliff split D-097 wants.
@export var cliff_min_step: float = 0.4

## How far above its own elevation the impassable HIGH class is DRAWN, in world
## units (D-097).
##
## The one place the picture is deliberately not the data, and it needs saying
## plainly. Measured on the shipped map, the natural rise from the last walkable
## cell to the first mountain cell is 0.66 world units — under half a hex's
## width, and quite invisible at play distance. The passability threshold is a
## level set on smooth noise, so it can never fall anywhere the ground is
## already steep: a truthful drawing of it, with no lift at all, is a truthful
## drawing of nothing.
##
## So mountains are lifted onto their own tier. The wall still stands EXACTLY
## where `passability` changes — that is the part that must not be negotiable —
## and the lift only makes it tall enough to see.
##
## Rendering only, like `height_scale` and `pillow`: `build_fields` is the sole
## reader, `passability` still thresholds the unscaled elevation, and nothing
## stands on impassable ground for the offset to disagree with. Any cell a
## soldier can walk on is LAND and is drawn at its own height, which is what
## `tests/test_terrain_cliffs.gd`'s band test pins down.
@export var cliff_rise: float = 2.0


## The height each of a corner's three owners renders it at, in world units
## (D-097).
##
## Returns one height per member of `trio`, in `trio`'s order. Where all three
## agree the corner is a single point and the surface is smooth; where they do
## not, the corner resolves into two or three heights and `TerrainChunk` fills
## the step with a rock skirt.
##
## ## Why this is a pure function of the sorted triple
##
## All three owners run it, over the same three cells, in the same order, and
## must reach the same answer — otherwise the "cliff" is a hole. Grouping by
## class and merging by gap is deterministic; taking `trio` sorted (which
## `corner_cells` guarantees) is what makes the arithmetic identical rather than
## merely equivalent.
static func corner_heights(classes: PackedByteArray,
		clamped: PackedFloat32Array, trio: Vector3i, step: float) -> Vector3:
	# The overwhelmingly common case, and worth its own branch: three cells of
	# one class have nothing to step between, so the answer is the plain mean
	# D-084 always took. On the shipped map that is 99% of the map's 48,384
	# corners, and the general path below allocates half a dozen small arrays
	# per call — meshing the standard map cost twice as long without this.
	var class_x := classes[trio.x]
	if class_x == classes[trio.y] and class_x == classes[trio.z]:
		var mean := (clamped[trio.x] + clamped[trio.y] + clamped[trio.z]) / 3.0
		return Vector3(mean, mean, mean)

	var members := [trio.x, trio.y, trio.z]

	# Partition by class. At most three groups, so the linear scan is the
	# cheapest thing that could work.
	var keys: Array[int] = []
	var sums: Array[float] = []
	var counts: Array[int] = []
	var group_of := [0, 0, 0]
	for m in range(3):
		var key := int(classes[members[m]])
		var found := -1
		for g in range(keys.size()):
			if keys[g] == key:
				found = g
				break
		if found < 0:
			found = keys.size()
			keys.append(key)
			sums.append(0.0)
			counts.append(0)
		group_of[m] = found
		sums[found] += clamped[members[m]]
		counts[found] += 1

	# Lowest first, so merging walks up the slope. Ties broken by class so the
	# order is total — two groups at the same mean must merge the same way every
	# time this runs.
	var order: Array[int] = []
	for g in range(keys.size()):
		order.append(g)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ma := sums[a] / float(counts[a])
		var mb := sums[b] / float(counts[b])
		if ma != mb:
			return ma < mb
		return keys[a] < keys[b])

	var resolved: Array[float] = [0.0, 0.0, 0.0]
	var start := 0
	while start < order.size():
		var sum := sums[order[start]]
		var count := counts[order[start]]
		var stop := start + 1
		while stop < order.size():
			var next_mean := sums[order[stop]] / float(counts[order[stop]])
			# Compared against the RUNNING mean, so a staircase of small steps
			# merges into one slope rather than into two half-cliffs.
			if next_mean - sum / float(count) >= step:
				break
			sum += sums[order[stop]]
			count += counts[order[stop]]
			stop += 1
		var mean := sum / float(count)
		for g in range(start, stop):
			resolved[order[g]] = mean
		start = stop

	return Vector3(
		resolved[group_of[0]], resolved[group_of[1]], resolved[group_of[2]])


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
	fields.cliff_class.resize(count)

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
		fields.cliff_class[i] = int(cliff_class_of(b))
		clamped[i] = maxf(e, sea_level)
		cell_color[i] = color_of(b)

	fields.surface.resize(count * SURFACE_STRIDE)
	fields.colors.resize(count * SURFACE_STRIDE)
	fields.corner_weights.resize(count * 6 * 3)
	# Every hex corner is visited three times — once per owning cell — and the
	# warp's two noise samples are the most expensive thing in this loop. A hex
	# lattice has two corners per cell, so computing each one once and looking
	# it up twice more is a 3x cut, and it took the standard map's terrain build
	# from 2.27 s back to under 1.3 s. Same shape as `TorusSpace.disk_offsets`
	# and `TerrainGen.elevation_field` before it.
	var weight_done := PackedByteArray()
	weight_done.resize(count * 6)
	# A SEPARATE array from fields.corner_weights: this one is indexed by the
	# canonical corner and that one by (cell, corner), and the two index spaces
	# overlap, so sharing the buffer would have one corner overwrite another.
	var weight_cache := PackedFloat32Array()
	weight_cache.resize(count * 6 * 3)
	# The cliff threshold in raw elevation units, converted once. A zero or
	# negative height_scale would make every corner a cliff, so guard rather
	# than divide by it.
	var step := cliff_min_step / maxf(height_scale, 0.0001)
	# The rendered elevation: the clamped one, plus the tier the HIGH class is
	# drawn on. Applied to the CENTRE as well as the corners, or a mountain hex
	# would tilt into its own cliff.
	var rise := cliff_rise / maxf(height_scale, 0.0001)
	var rendered := PackedFloat32Array()
	rendered.resize(count)
	for i in range(count):
		rendered[i] = clamped[i] + (rise if fields.cliff_class[i] == int(CliffClass.HIGH) else 0.0)
	for i in range(count):
		var base := i * SURFACE_STRIDE
		var corner_total := 0.0
		for k in range(6):
			var trio := corner_cells(space, i, k)
			# Heights average WITHIN a passability class and step between them
			# (D-097). Colour still averages over all three owners, so the cliff
			# face and the ground above it belong to the same landscape.
			var resolved := corner_heights(fields.cliff_class, rendered, trio, step)
			var mine := resolved.x
			if trio.y == i:
				mine = resolved.y
			elif trio.z == i:
				mine = resolved.z
			var height := mine * height_scale
			fields.surface[base + 1 + k] = height
			# Colour blends over the owners on THIS side of the step, not over
			# all three. Where nothing steps that is all three and the blend is
			# D-096's; where a cliff steps, a mountain plateau would otherwise be
			# painted in the colours of the valley it towers over — rock walls
			# with grassland on top, which is what the first render of D-097
			# actually showed.
			# Which corner of the LOWEST-indexed owner this same point is —
			# the canonical name for it, and the cache key. `corner_cells`
			# sorts, so trio.x is always that owner.
			var canonical := k
			if trio.x != i:
				canonical = posmod(2 + k, 6) if trio.x == space.neighbor_index(i, 1 - k) 					else posmod(4 + k, 6)
			var key := trio.x * 6 + canonical
			if weight_done[key] == 0:
				var computed := corner_weights(space, i, k, trio)
				var slot := key * 3
				weight_cache[slot] = computed.x
				weight_cache[slot + 1] = computed.y
				weight_cache[slot + 2] = computed.z
				weight_done[key] = 1
			var cached := key * 3
			var weights := Vector3(weight_cache[cached], weight_cache[cached + 1],
				weight_cache[cached + 2])
			var weight_base := (i * 6 + k) * 3
			fields.corner_weights[weight_base] = weights.x
			fields.corner_weights[weight_base + 1] = weights.y
			fields.corner_weights[weight_base + 2] = weights.z

			var blended := Color(0.0, 0.0, 0.0, 0.0)
			var owners := 0.0
			var members := 0.0
			var unweighted := Color(0.0, 0.0, 0.0, 0.0)
			for m in range(3):
				var owner := trio[m]
				if absf(resolved[m] - mine) > 1e-6:
					continue
				blended += cell_color[owner] * weights[m]
				owners += weights[m]
				unweighted += cell_color[owner]
				members += 1.0
			# A group whose weights all clamped to zero — possible where the warp
			# pushes hard and the cliff split leaves one owner alone — would
			# otherwise divide near-nothing by near-nothing and come out BLACK.
			# It showed up as ink blots along a coastline at high warp, and no
			# count could have found it.
			if owners > 1e-4:
				fields.colors[base + 1 + k] = blended / owners
			else:
				fields.colors[base + 1 + k] = unweighted / maxf(members, 1.0)
			corner_total += height
		# The pillow, as a tunable rather than an implicit 1.0 — see `pillow`.
		fields.surface[base] = lerpf(corner_total / 6.0,
			rendered[i] * height_scale, pillow)
		var centre_colour := cell_color[i]
		if centre_bleed > 0.0:
			var ring := Color(0.0, 0.0, 0.0, 0.0)
			for k in range(6):
				ring += fields.colors[base + 1 + k]
			centre_colour = cell_color[i].lerp(ring / 6.0, centre_bleed)
		fields.colors[base] = centre_colour
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
