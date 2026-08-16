extends RefCounted
class_name TerrainChunk

## Chunked hex terrain meshing (D-017).
##
## One mesh per CHUNK of cells, never one mesh per cell — at 10,000+ cells
## the per-cell approach is a known performance failure, so chunking is a
## requirement rather than a style choice. Chunk size is deliberately a
## parameter and not a constant: D-017 leaves it open pending profiling,
## and `gen-terrain-preview` exists to make that experiment cheap.
##
## ## Geometry is unwrapped, data is wrapped
##
## Chunk vertices are placed at UNWRAPPED coordinates, so a chunk that
## straddles a seam stays one contiguous piece of geometry instead of
## being torn in half across the map. Terrain values for those same cells
## are sampled at WRAPPED coordinates, so the chunk shows the terrain that
## is actually there. Getting these the wrong way round produces either
## stretched geometry or a visible seam, both of which look like noise
## bugs rather than indexing bugs.

## ## UVs come from the CELL, never from world position (D-066, D-096)
##
## That choice is what keeps the nine lattice copies (D-035) in agreement: the
## same mesh is drawn nine times at nine offsets, so any UV derived from world
## position would show a different phase on each copy unless the tile period
## happened to divide the lattice step exactly. Cell-derived UVs are identical
## on every copy by construction — the torus tax paid once, at design time,
## instead of forever.
##
## What D-096 changed is that the cell-derived coordinate is now CONTINUOUS
## across cell boundaries instead of restarting inside each hex's own tile. Each
## hex used to be inscribed in its biome's atlas tile with a 6% inset and a
## hashed rotation, which broke the texture at every edge and was the strongest
## remaining cue of the lattice once the colour was blended.
##
## Continuity across the SEAM is a separate condition, and it is why `uv_scale`
## exists: the texture period must divide the map period exactly on both axes,
## or the ninth copy meets the first mid-pattern.
##
## The atlas MODULATES; vertex colour still decides (D-066). `biome_color`
## remains the single source of truth that the minimap and the preview PNG also
## read, so those cannot drift from the 3D view.

## ## The ground is a continuous surface, and this file owns both halves
##
## Vertex heights come from `TerrainGen.surface_field` (D-067): corners take the
## mean of the three cells meeting there, so neighbours agree and the surface is
## watertight. `height_at` below samples that SAME array with the same geometry,
## which is what stops the mesh and the client's ground height from drifting
## apart. They live in one file for that reason — a soldier standing on ground
## the renderer disagrees about is the "numbers right, picture wrong" failure
## this project keeps paying for, and it would show as an army floating.

# Corner angles for a pointy-top hexagon.
const CORNERS := 6

## Unit offsets of the six corners, in the order they are emitted. Corner k sits
## at (60k - 30) degrees, matching the angle used when building the fan.
const CORNER_OFFSETS: Array[Vector2] = [
	Vector2(0.8660254037844387, -0.5),
	Vector2(0.8660254037844387, 0.5),
	Vector2(0.0, 1.0),
	Vector2(-0.8660254037844387, 0.5),
	Vector2(-0.8660254037844387, -0.5),
	Vector2(0.0, -1.0),
]

## |C_k x C_(k+1)| for unit corners 60 degrees apart. Constant for every sector,
## so the barycentric solve needs no per-sector table.
const CORNER_DET := 0.8660254037844387

# Atlas layout. Must match art/terrain/atlas.py — a test asserts they agree,
# because a silent disagreement paints forest on water rather than erroring.
const ATLAS_COLUMNS := 4
const ATLAS_ROWS := 2
## Roughly how many cells one repeat of an atlas tile should cover. The actual
## repeat count is rounded from this to something that divides the map period
## (see `uv_scale`), so it is a target rather than a setting.
##
## 3 cells was chosen by eye against the shipped tiles: much larger and the
## noise reads as blotches rather than ground; much smaller and it aliases into
## a shimmer at play distance, which no amount of mipping fixes because the
## camera is nearly always moving.
const UV_CELLS_PER_TILE := 3.0

## Corner k's axial offset from its cell's centre, in THIRDS of a cell.
##
## Integers on purpose: `vertex_uv` evaluates the UV over a common denominator
## so its numerator is exact, which is what lets two cells sharing a corner
## produce bit-identical UVs rather than merely close ones.
const CORNER_AXIAL_THIRDS: Array[Vector2i] = [
	Vector2i(2, -1),
	Vector2i(1, 1),
	Vector2i(-1, 2),
	Vector2i(-2, 1),
	Vector2i(-1, -1),
	Vector2i(1, -2),
]


## How many atlas repeats fit across the map on each axis, as a scale applied to
## the continuous axial coordinate: `u = scale.x * (q + r/2)`, `v = scale.y * r`.
##
## ## The seam is what makes this arithmetic rather than a constant
##
## The two vectors that tile this torus (`TorusSpace.lattice_steps`) are not
## axis-aligned: stepping `width` in q moves world x alone, but stepping
## `height` in r moves BOTH z and x, because x depends on r/2. So a repeating
## texture meets itself across the seam only if all three of these are whole
## numbers of repeats: `scale.x * width`, `scale.x * height/2` and
## `scale.y * height`. Writing scale.x as `repeats / width` turns the first into
## `repeats` and the second into `repeats * (height/2) / width`, which is whole
## exactly when `repeats` is a multiple of `width / gcd(width, height/2)`.
##
## The v axis has no such coupling — world z depends on r alone — so any whole
## number of repeats down the map will do, and it is chosen to keep the texture
## square in WORLD units rather than in axial ones. A hex column is sqrt(3) wide
## and a hex row 1.5 deep, so an axially square texture comes out stretched.
static func uv_scale(space: TorusSpace) -> Vector2:
	var half_height := maxi(1, space.height / 2)
	var granularity := maxi(1, space.width / _gcd(space.width, half_height))
	var wanted := float(space.width) / UV_CELLS_PER_TILE
	var steps := maxi(1, int(round(wanted / float(granularity))))
	var repeats_u := granularity * steps
	var repeats_v := maxi(1, int(round(
		1.5 * float(space.height) * float(repeats_u)
		/ (TorusSpace.SQRT_3 * float(space.width)))))
	return Vector2(
		float(repeats_u) / float(space.width),
		float(repeats_v) / float(space.height))


static func _gcd(a: int, b: int) -> int:
	var x := absi(a)
	var y := absi(b)
	while y != 0:
		var t := y
		y = x % y
		x = t
	return maxi(1, x)


## The UV of one vertex of one cell. `corner` is -1 for the centre and 0..5 for
## a corner, matching `TerrainGen.SURFACE_STRIDE`'s layout.
##
## `cell` is the UNWRAPPED coordinate, so the texture runs continuously across a
## chunk boundary. The seam is handled by `uv_scale` making the map period a
## whole number of repeats, not by normalising here — normalising would restart
## the texture at the map's edge, which is the defect this replaced one scale up.
##
## Evaluated as an integer numerator over a common denominator rather than in
## floats, so two cells sharing a corner compute the identical value. Corner
## offsets are thirds of a cell and `r/2` contributes a half, which makes sixths
## the denominator.
static func vertex_uv(scale: Vector2, cell: Vector2i, corner: int) -> Vector2:
	var nq := 0
	var nr := 0
	if corner >= 0:
		var offset: Vector2i = CORNER_AXIAL_THIRDS[corner]
		nq = offset.x
		nr = offset.y
	var u_numerator := 6 * cell.x + 2 * nq + 3 * cell.y + nr
	var v_numerator := 3 * cell.y + nr
	return Vector2(
		scale.x * float(u_numerator) / 6.0,
		scale.y * float(v_numerator) / 3.0)


## Where one vertex of one cell reads the fog-of-war field (D-102), as a UV into
## a one-texel-per-cell texture laid out like `TorusSpace.index`.
##
## Cell-derived, like `vertex_uv` and for the same reason (D-035): the mesh is
## drawn nine times across the seams and all nine copies must sample the same
## cell. Deriving it from world position instead would fog each copy differently.
##
## `cell` is the UNWRAPPED coordinate, so a chunk at the map's edge produces a UV
## slightly outside [0,1] — which is exactly right, because the fog sampler
## repeats and the torus period is the texture period. The half-texel is what
## puts a cell's CENTRE vertex on its own texel centre, so a cell entirely inside
## a vision disk samples that cell's own value exactly and only the corners
## blend.
static func fog_uv(space: TorusSpace, cell: Vector2i, corner: int) -> Vector2:
	var nq := 0
	var nr := 0
	if corner >= 0:
		var offset: Vector2i = CORNER_AXIAL_THIRDS[corner]
		nq = offset.x
		nr = offset.y
	return Vector2(
		(float(3 * cell.x + nq) / 3.0 + 0.5) / float(maxi(space.width, 1)),
		(float(3 * cell.y + nr) / 3.0 + 0.5) / float(maxi(space.height, 1)))


## How many atlas tiles a fragment blends. Three, because a hex corner is shared
## by exactly three cells and therefore mixes at most three biomes.
const TILE_SLOTS := 3


## The three atlas tiles a cell's fragments may sample, and each of its seven
## vertices' weights over them (D-096).
##
## Returns `{"tiles": PackedFloat32Array (TILE_SLOTS), "weights":
## PackedFloat32Array (SURFACE_STRIDE * TILE_SLOTS)}`.
##
## ## Why the slots are per CELL and the weights per vertex
##
## A fragment cannot blend tiles chosen per vertex: the rasteriser interpolates
## every varying, and an interpolated tile INDEX asks for tile 4.7. So the index
## set has to be constant over each triangle and the weights — which interpolate
## perfectly well — carry the variation. Every cell already emits its own seven
## vertices (no vertex is shared between cells, only positions coincide), so
## "constant per cell" costs nothing: the same triple is written to all seven and
## the interpolation is a no-op.
##
## ## Where it can be inexact, and why that is acceptable
##
## A corner mixes the biomes of its three owners at a third each, and the two
## cells sharing an edge interpolate between the same two corner mixtures — so
## the blend is continuous across every boundary, exactly, as long as both cells'
## slot sets contain every biome involved. Three slots hold any single corner's
## mixture, but a cell whose six neighbours span more than three biomes must drop
## the least demanded, and its neighbour may drop a different one. The result is
## a small difference in texture DETAIL — never in colour, which is exact and
## carried separately — across that one edge.
##
## `tests/test_terrain_uvs.gd` MEASURES how often that happens on the shipped
## map rather than assuming it is rare.
static func cell_tiles(space: TorusSpace, fields: TerrainFields,
		cell_index: int) -> Dictionary:
	var own := int(fields.biome[cell_index])

	# Total weight this cell's vertices will ask for, per biome: the centre asks
	# for its own at 1, and each of the six corners for a third of each owner.
	var demand := {own: 1.0}
	var corner_trios: Array[Vector3i] = []
	for k in range(6):
		var trio := TerrainGen.corner_cells(space, cell_index, k)
		corner_trios.append(trio)
		# The SAME warped weights the colour blend used (D-096 amendment), so
		# the texture boundary and the colour boundary meander together. Two
		# boundaries wandering independently would cross, which reads worse than
		# either of them following the lattice.
		var weights := fields.weights(cell_index, k)
		for m in range(3):
			var b := int(fields.biome[trio[m]])
			demand[b] = float(demand.get(b, 0.0)) + weights[m]

	# Own biome first — a cell must always be able to paint itself — then the
	# rest by demand, ties broken by biome index so the choice is deterministic.
	var others: Array = []
	for b in demand:
		if b != own:
			others.append(b)
	others.sort_custom(func(a: int, b: int) -> bool:
		var da: float = demand[a]
		var db: float = demand[b]
		if da != db:
			return da > db
		return a < b)

	var tiles := PackedFloat32Array()
	tiles.resize(TILE_SLOTS)
	var slot_of := {own: 0}
	tiles[0] = float(own)
	for i in range(1, TILE_SLOTS):
		if i - 1 < others.size():
			var b: int = others[i - 1]
			tiles[i] = float(b)
			slot_of[b] = i
		else:
			# An unused slot points at the cell's own tile rather than staying 0,
			# which is DEEP_WATER and would paint a puddle if any weight ever
			# leaked into it.
			tiles[i] = float(own)

	var weights := PackedFloat32Array()
	weights.resize(TerrainGen.SURFACE_STRIDE * TILE_SLOTS)
	# The centre asks for its own biome outright.
	weights[0] = 1.0
	for k in range(6):
		var base := (1 + k) * TILE_SLOTS
		var blend := fields.weights(cell_index, k)
		for m in range(3):
			# A biome with no slot falls back to the cell's own, which keeps the
			# weights summing to exactly 1. A shortfall would darken the fragment
			# rather than merely mis-texture it.
			var slot: int = slot_of.get(int(fields.biome[corner_trios[k][m]]), 0)
			weights[base + slot] += blend[m]

	return {"tiles": tiles, "weights": weights}


## How many chunks tile the map at this chunk size, rounding up.
static func chunk_grid(space: TorusSpace, chunk_size: int) -> Vector2i:
	var size := maxi(1, chunk_size)
	return Vector2i(
		ceili(float(space.width) / float(size)),
		ceili(float(space.height) / float(size))
	)


static func chunk_count(space: TorusSpace, chunk_size: int) -> int:
	var grid := chunk_grid(space, chunk_size)
	return grid.x * grid.y


## The two corners of the edge a cell shares with its neighbour in direction
## `direction`, as `[[ours, theirs], [ours, theirs]]` corner indices (D-097).
##
## `corner_cells` says which three cells meet at a corner; this says which
## corner INDEX each of two neighbours uses for the same physical point, which
## is what a skirt needs in order to read both sides' heights out of one array.
##
## Derived once and checked geometrically by `tests/test_terrain_cliffs.gd`
## rather than trusted: the arithmetic is a rotation of a reflection and reads
## like a typo either way.
static func edge_corners(direction: int) -> Array:
	var out := []
	for ours in [posmod(1 - direction, 6), posmod(-direction, 6)]:
		out.append([ours, posmod(4 - 2 * direction - ours, 6)])
	return out


## Which surface of a chunk mesh the rock faces are. Surface 0 is the ground;
## a chunk with no cliff in it has no surface 1 at all.
const SKIRT_SURFACE := 1

## Directions a cell emits skirts for. Three of the six, so every shared edge is
## drawn exactly once — by the cell on one particular side of it, never by both
## and never by neither.
const SKIRT_DIRECTIONS := [0, 1, 2]

## Heights closer than this are the same height. Well under `cliff_min_step`,
## which is what actually decides whether a step exists; this only stops a
## degenerate zero-area quad being emitted for a corner that merged.
const SKIRT_EPSILON := 0.0005

## How much darker than the mountain biome the rock face is drawn. A cliff read
## at a glance is a change of VALUE before it is anything else, and the ground
## above it is often the same grey.
##
## Mild on purpose. The face is vertical, so the lighting already darkens it far
## more than this does — see `SKIRT_NORMAL_LIFT`, which exists because the first
## version of this was near-black in the render.
const SKIRT_SHADE := 0.9

## How far the rock face's normal is tilted UP from horizontal, as a fraction of
## the horizontal component.
##
## A deliberate cheat, and worth saying so. D-086's rig is one directional sun
## with sky ambient and NO shadows, so a truly vertical normal makes a cliff
## face catch almost nothing: the first render of this drew mountain walls at
## sRGB 0.09 — dark enough that they read as holes cut in the world rather than
## as rock. Tilting the normal about 27 degrees up lets the face take some sun
## while the geometry stays exactly vertical, which is the whole point of the
## thing being on the passability boundary.
##
## This is the same class of choice as D-045's "distant squads draw thinner,
## never smaller": the picture is adjusted so a player can READ it, and the
## adjustment is in the shading rather than in where anything is.
const SKIRT_NORMAL_LIFT := 0.5


## Append the rock face filling the step between cell `unwrapped` and its
## neighbour in `direction`, if there is one (D-097).
##
## ## The wall sits exactly on the shared edge
##
## Both sides' corner positions are the same two points in the horizontal plane
## — only their heights differ — so the quad is vertical and lands precisely on
## the boundary. That is what keeps the passable side's plateau flat right up to
## the edge, which in turn is what keeps `TerrainChunk.height_at` returning the
## walkable height for anything standing near it (see `height_at`, and the band
## test in `tests/test_terrain_cliffs.gd`).
##
## ## It goes in the same mesh
##
## Emitted as a second surface of the chunk's own ArrayMesh, so it inherits the
## nine-copy lattice tiling (D-035) and adds no draw-call structure — and,
## because it wears the same material, no material plumbing either. Rock is
## expressed through the shader's existing per-vertex tile channel (all three
## slots pointing at MOUNTAIN, so the face gets the atlas's rock strata) rather
## than through a second material that the callers' `material_override` would
## have flattened anyway.
static func _append_skirt(space: TorusSpace, fields: TerrainFields,
		unwrapped: Vector2i, centre: Vector3, corner_positions: Array[Vector3],
		direction: int, uv_step: Vector2, out: Dictionary) -> void:
	var here := space.index(unwrapped)
	var there := space.index(unwrapped + TorusSpace.DIRECTIONS[direction])
	if here == there:
		return

	var pairs := edge_corners(direction)
	var ours: Array[int] = [pairs[0][0], pairs[1][0]]
	var theirs: Array[int] = [pairs[0][1], pairs[1][1]]

	var high: Array[float] = []
	var low: Array[float] = []
	var stepped := false
	for e in range(2):
		var mine := fields.height(here, 1 + ours[e])
		var yours := fields.height(there, 1 + theirs[e])
		high.append(maxf(mine, yours))
		low.append(minf(mine, yours))
		if absf(mine - yours) > SKIRT_EPSILON:
			stepped = true
	if not stepped:
		return

	# Outward is away from whichever side is taller, so the face is visible from
	# the ground below it rather than from inside the hill.
	var to_neighbour := space.world_delta(space.from_index(here),
		space.from_index(there)).normalized()
	var mine_taller := fields.height(here, 1 + ours[0]) + fields.height(here, 1 + ours[1]) \
		>= fields.height(there, 1 + theirs[0]) + fields.height(there, 1 + theirs[1])
	var outward := to_neighbour if mine_taller else -to_neighbour
	# Tilted up so the face catches the sun; the geometry stays vertical.
	var shading_normal := (outward + Vector3.UP * SKIRT_NORMAL_LIFT).normalized()

	var vertices: PackedVector3Array = out["vertices"]
	var normals: PackedVector3Array = out["normals"]
	var colors: PackedColorArray = out["colors"]
	var uvs: PackedVector2Array = out["uvs"]
	var fog_uvs: PackedVector2Array = out["fog_uvs"]
	var tiles: PackedFloat32Array = out["tiles"]
	var weights: PackedFloat32Array = out["weights"]
	var indices: PackedInt32Array = out["indices"]

	var rock := TerrainGen.color_of(TerrainGen.Biome.MOUNTAIN) * SKIRT_SHADE
	rock.a = 1.0
	# Vertical v, so the strata run along the face rather than up it, at the
	# same world scale the ground uses. Horizontal u comes from the ground's own
	# coordinate at that corner, so a cliff and the plateau above it are cut from
	# one continuous texture.
	var v_per_world := uv_step.y / (1.5 * space.hex_size)

	var base := vertices.size()
	for e in range(2):
		var flat: Vector3 = corner_positions[ours[e]]
		var u := vertex_uv(uv_step, unwrapped, ours[e]).x
		# The ground's own fog coordinate at that corner, so a cliff face is as
		# known as the plateau it holds up. Its atlas v is derived from world
		# HEIGHT (see just above), which is why fog needs its own channel rather
		# than being recovered from UV the way the ground's cell could be.
		var rock_fog := fog_uv(space, unwrapped, ours[e])
		for height in [high[e], low[e]]:
			vertices.append(Vector3(flat.x, height, flat.z))
			normals.append(shading_normal)
			colors.append(rock)
			uvs.append(Vector2(u, height * v_per_world))
			fog_uvs.append(rock_fog)
			for slot in range(TILE_SLOTS):
				tiles.append(float(TerrainGen.Biome.MOUNTAIN))
				weights.append(1.0 / float(TILE_SLOTS))
			tiles.append(0.0)
			weights.append(0.0)

	# Vertices are (corner0 top, corner0 bottom, corner1 top, corner1 bottom).
	# Which winding faces outward depends on the order the two corners come
	# round the hex AND on which side is taller, so it is decided by measuring
	# the triangle rather than by case analysis — a back-facing cliff is
	# invisible and would look exactly like the skirt never being built.
	var facing := (vertices[base + 2] - vertices[base]).cross(
		vertices[base + 1] - vertices[base])
	if facing.dot(outward) >= 0.0:
		indices.append_array([base, base + 2, base + 1,
			base + 1, base + 2, base + 3])
	else:
		indices.append_array([base, base + 1, base + 2,
			base + 1, base + 3, base + 2])


## Build one chunk's mesh. `chunk` is a chunk-grid coordinate, not a cell
## coordinate. Returns null if the chunk contains no cells.
static func build_mesh(space: TorusSpace, terrain: TerrainGen, chunk: Vector2i,
		chunk_size: int, fields: TerrainFields = null) -> ArrayMesh:
	# Callers meshing more than one chunk should build the fields once and pass
	# them: they are O(cells), and recomputing them per chunk would evaluate the
	# elevation noise for the whole map once per chunk. Defaulted rather than
	# required so short tests and one-off call sites keep working.
	if fields == null:
		fields = terrain.build_fields(space)
	var surface := fields.surface

	var size := maxi(1, chunk_size)
	var origin := Vector2i(chunk.x * size, chunk.y * size)

	var cells_x := mini(size, space.width - origin.x)
	var cells_y := mini(size, space.height - origin.y)
	if cells_x <= 0 or cells_y <= 0:
		return null

	var uv_step := uv_scale(space)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	# Where each vertex reads the client's fog-of-war field (D-102). A second UV
	# channel rather than a custom one: it is a texture coordinate, and both of
	# the custom channels are already spoken for by the atlas tiling.
	var fog_uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Four floats per vertex each, because Godot's custom vertex channels come
	# in fixed widths; the fourth is unused and the shader reads .xyz.
	var tile_slots := PackedFloat32Array()
	var tile_weights := PackedFloat32Array()

	# The rock faces filling the steps at passability boundaries (D-097). Their
	# own surface of this same mesh, so they inherit the nine-copy tiling and
	# add no draw-call structure. One dictionary because `_append_skirt` fills
	# seven parallel arrays and seven parameters would be worse.
	var skirt := {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"colors": PackedColorArray(),
		"uvs": PackedVector2Array(),
		"fog_uvs": PackedVector2Array(),
		"tiles": PackedFloat32Array(),
		"weights": PackedFloat32Array(),
		"indices": PackedInt32Array(),
	}

	for dy in range(cells_y):
		for dx in range(cells_x):
			var unwrapped := Vector2i(origin.x + dx, origin.y + dy)
			# Geometry unwrapped...
			var centre := space.axial_offset_to_world(Vector2(float(unwrapped.x), float(unwrapped.y)))
			# ...data wrapped.
			var cell_index := space.index(unwrapped)
			var surface_base := cell_index * TerrainGen.SURFACE_STRIDE
			centre.y = surface[surface_base]

			# Which three atlas tiles this cell's fragments may blend, and how
			# much of each every one of its vertices asks for (D-096).
			var tiling := cell_tiles(space, fields, cell_index)
			var slots: PackedFloat32Array = tiling["tiles"]
			var weights: PackedFloat32Array = tiling["weights"]

			# Corners first, so the centre's normal can be averaged from the fan
			# they form.
			var corner_positions: Array[Vector3] = []
			for corner in range(CORNERS):
				var angle := TAU * (float(corner) / float(CORNERS)) - PI / 6.0
				corner_positions.append(Vector3(
					centre.x + space.hex_size * cos(angle),
					surface[surface_base + 1 + corner],
					centre.z + space.hex_size * sin(angle)))

			var base := vertices.size()
			vertices.append(centre)
			normals.append(_centre_normal(centre, corner_positions))
			colors.append(fields.colors[surface_base])
			# Continuous across cells, derived from the UNWRAPPED cell, and
			# periodic over the map — see `vertex_uv` and `uv_scale`.
			uvs.append(vertex_uv(uv_step, unwrapped, -1))
			fog_uvs.append(fog_uv(space, unwrapped, -1))
			_append_tiles(tile_slots, tile_weights, slots, weights, 0)

			for corner in range(CORNERS):
				vertices.append(corner_positions[corner])
				# A corner's normal is derived from the three CELL CENTRES that
				# meet there, not from this cell's triangles. All three cells
				# compute it from the same three points and so agree exactly —
				# which is what makes the lighting continuous instead of
				# faceting the map back into hexes after the geometry stopped
				# doing so.
				normals.append(_corner_normal(space, fields, unwrapped, corner))
				colors.append(fields.colors[surface_base + 1 + corner])
				uvs.append(vertex_uv(uv_step, unwrapped, corner))
				fog_uvs.append(fog_uv(space, unwrapped, corner))
				_append_tiles(tile_slots, tile_weights, slots, weights, 1 + corner)

			# Fan from the centre vertex.
			for corner in range(CORNERS):
				indices.append(base)
				indices.append(base + 1 + corner)
				indices.append(base + 1 + (corner + 1) % CORNERS)

			# Half the six directions, so each shared edge is skirted once.
			for direction in SKIRT_DIRECTIONS:
				_append_skirt(space, fields, unwrapped, centre, corner_positions,
					direction, uv_step, skirt)

	if vertices.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = fog_uvs
	arrays[Mesh.ARRAY_CUSTOM0] = tile_slots
	arrays[Mesh.ARRAY_CUSTOM1] = tile_weights
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	# The custom channels have to be declared in the surface format as well as
	# supplied, or Godot reads the arrays as empty and the shader silently gets
	# zeroes — which paints the whole map as tile 0, deep water.
	var format := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)

	var skirt_vertices: PackedVector3Array = skirt["vertices"]
	if not skirt_vertices.is_empty():
		var rock := []
		rock.resize(Mesh.ARRAY_MAX)
		rock[Mesh.ARRAY_VERTEX] = skirt_vertices
		rock[Mesh.ARRAY_NORMAL] = skirt["normals"]
		rock[Mesh.ARRAY_COLOR] = skirt["colors"]
		rock[Mesh.ARRAY_TEX_UV] = skirt["uvs"]
		rock[Mesh.ARRAY_TEX_UV2] = skirt["fog_uvs"]
		rock[Mesh.ARRAY_CUSTOM0] = skirt["tiles"]
		rock[Mesh.ARRAY_CUSTOM1] = skirt["weights"]
		rock[Mesh.ARRAY_INDEX] = skirt["indices"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rock, [], {}, format)

	return mesh


## One vertex's worth of tile slots and weights, padded to the four floats a
## custom channel carries.
static func _append_tiles(slots_out: PackedFloat32Array,
		weights_out: PackedFloat32Array, slots: PackedFloat32Array,
		weights: PackedFloat32Array, vertex: int) -> void:
	for i in range(TILE_SLOTS):
		slots_out.append(slots[i])
		weights_out.append(weights[vertex * TILE_SLOTS + i])
	slots_out.append(0.0)
	weights_out.append(0.0)


## The normal at a shared corner: the plane through the cell centres that AGREE
## about that corner's height (D-067, D-097).
##
## Derived from the FIELD rather than from this cell's triangles, so every owner
## that resolved the corner to the same height produces the identical vector.
## Accumulating triangle normals per cell would give each hex its own shading and
## put the grid straight back into the picture, which is the thing the smoothing
## exists to remove.
##
## Since D-097 a corner can resolve to more than one height — that is what a
## cliff IS — so the plane is fitted only over the owners on this side of the
## step. Fitting it over all three would tilt a perfectly flat plateau to face
## the valley, and light the ground beside a mountain as if it were the
## mountainside.
##
## With only two owners agreeing there is no third centre to make a plane from,
## so the corner point itself is used: both owners compute it from the same
## three points and so still agree. With ONE owner the cell is alone in its
## class there, its corner height equals its own elevation, and the surface is
## locally flat — which is what `Vector3.UP` says.
static func _corner_normal(space: TorusSpace, fields: TerrainFields,
		cell: Vector2i, corner: int) -> Vector3:
	# The same two neighbours TerrainGen.corner_heights resolved this corner
	# with, and the corner index each of them files it under.
	var partners := TerrainGen.corner_partners(corner)
	var here := space.normalize(cell)
	var a := space.normalize(cell + TorusSpace.DIRECTIONS[posmod(1 - corner, 6)])
	var b := space.normalize(cell + TorusSpace.DIRECTIONS[posmod(-corner, 6)])

	var here_index := space.index(here)
	var mine := fields.height(here_index, 1 + corner)

	var points: Array[Vector3] = [Vector3(0.0, fields.height(here_index, 0), 0.0)]
	for pair in [[a, partners.x], [b, partners.y]]:
		var neighbour: Vector2i = pair[0]
		var index := space.index(neighbour)
		if absf(fields.height(index, 1 + int(pair[1])) - mine) > 0.0001:
			continue
		# Positions relative to `here`, so the seam cannot stretch the triangle.
		var offset := space.world_delta(here, neighbour)
		offset.y = fields.height(index, 0)
		points.append(offset)

	if points.size() < 3:
		if points.size() < 2:
			return Vector3.UP
		# Two agreeing owners plus the corner they agree about. The corner sits
		# at the centroid of the three cells in plan, so it is off the line
		# joining the two centres and the plane is well defined — and both
		# owners build it from the same three points.
		var angle := TAU * (float(corner) / float(CORNERS)) - PI / 6.0
		points.append(Vector3(
			space.hex_size * cos(angle), mine, space.hex_size * sin(angle)))

	var normal := (points[1] - points[0]).cross(points[2] - points[0])
	if normal.length_squared() < 1e-12:
		return Vector3.UP
	normal = normal.normalized()
	# Winding depends on which of the two neighbours came first; the ground
	# always faces up, so orientation is settled here rather than by case
	# analysis on the direction indices.
	return normal if normal.y >= 0.0 else -normal


## The centre vertex's normal, averaged over the six triangles of its own fan.
##
## The centre belongs to exactly one cell, so unlike a corner there is nobody to
## agree with and the mesh's own geometry is the right source.
static func _centre_normal(centre: Vector3, corners: Array[Vector3]) -> Vector3:
	var total := Vector3.ZERO
	for i in range(CORNERS):
		var a := corners[i] - centre
		var b := corners[(i + 1) % CORNERS] - centre
		total += b.cross(a)
	if total.length_squared() < 1e-12:
		return Vector3.UP
	total = total.normalized()
	return total if total.y >= 0.0 else -total


## Ground height at an arbitrary world position, matching the mesh exactly
## (D-067).
##
## `surface` is `TerrainGen.surface_field(space)` — pass the SAME array the
## chunks were built from.
##
## ## This is a hot path
##
## The client calls this once per soldier per frame: ~26,600 times a frame at
## D-018's full scale, inside the loop D-045 measured at 97% CPU. It was one
## array index while every hex was flat. It is now an atan2 and a handful of
## multiplies, and it must not become more than that — no noise evaluation, no
## allocation, nothing that touches the scene tree. `TerrainGen.elevation_at`
## called per soldier was the third instance of that defect in this project's
## history; do not make it the fifth.
##
## Works in AXIAL space rather than subtracting a cell's world centre, because
## a wrapped centre subtracted from an unwrapped position gives a nonsense
## offset at the seam. The axial delta is small by construction.
static func height_at(space: TorusSpace, surface: PackedFloat32Array,
		x: float, z: float) -> float:
	if surface.is_empty():
		return 0.0

	var fractional := space.world_to_axial(Vector3(x, 0.0, z))
	var cell := space.round_axial(fractional)
	var base := space.index(cell) * TerrainGen.SURFACE_STRIDE

	# Offset of the point from the cell's centre, in world units.
	var local := space.axial_offset_to_world(fractional - Vector2(cell))

	# Which of the six fan triangles contains it. Corner k spans
	# [60k - 30, 60k + 30) degrees, so shifting by 30 makes the sector a
	# straight floor-divide.
	var sector := int(floor((atan2(local.z, local.x) + PI / 6.0) / (PI / 3.0)))
	sector = posmod(sector, CORNERS)
	var next_sector := (sector + 1) % CORNERS

	var c0: Vector2 = CORNER_OFFSETS[sector] * space.hex_size
	var c1: Vector2 = CORNER_OFFSETS[next_sector] * space.hex_size

	# Barycentric weights in the triangle (centre, c0, c1).
	var det := CORNER_DET * space.hex_size * space.hex_size
	var w0 := (local.x * c1.y - local.z * c1.x) / det
	var w1 := (c0.x * local.z - c0.y * local.x) / det
	var wc := 1.0 - w0 - w1

	return (wc * surface[base]
		+ w0 * surface[base + 1 + sector]
		+ w1 * surface[base + 1 + next_sector])


const ATLAS_PATH := "res://generated/textures/terrain_atlas.png"
const SHADER_PATH := "res://shaders/terrain.gdshader"


## Whether the generated atlas is present. Callers that only want to REPORT
## which path they are on ask this rather than inspecting the material, which
## stopped being a StandardMaterial3D when D-096 gave the ground a shader.
static func has_atlas() -> bool:
	return ResourceLoader.exists(ATLAS_PATH)


## The material every terrain chunk shares.
##
## One definition, used by the client and by `bench-render`, because those two
## had drifted into identical copies and a benchmark that renders a different
## material than the game measures the wrong thing.
##
## The atlas MULTIPLIES vertex colour (D-066). The texture supplies detail;
## `biome_color` still supplies the colour, so the minimap and the terrain
## preview — which read that same function and never touch this material —
## cannot fall out of step with the 3D view. An atlas whose tiles average near
## neutral therefore changes the palette not at all, which is what
## `art/terrain/atlas.py` is written to guarantee.
##
## Since D-096 the textured path is a ShaderMaterial: the UVs run continuously
## across cells, so which of the eight tiles a fragment belongs in is a
## per-fragment decision and there is no fixed-function way to say it. See
## `shaders/terrain.gdshader`.
##
## Falls back to plain vertex colour when `generated/` has not been built, for
## the same reason units fall back to primitives: a missing art build should
## cost fidelity, not the game. That fallback is also the honest answer for a
## renderer that cannot compile the shader — nothing here can make a frame
## without an atlas look textured.
static func make_material() -> Material:
	if not has_atlas():
		var plain := StandardMaterial3D.new()
		plain.vertex_color_use_as_albedo = true
		plain.roughness = 0.95
		return plain

	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	material.set_shader_parameter("atlas", load(ATLAS_PATH) as Texture2D)
	# Passed in rather than hardcoded in the shader, so the layout has exactly
	# one definition on the Godot side and `test_terrain_uvs.gd` pins that one
	# to `art/terrain/atlas.py`.
	material.set_shader_parameter("atlas_grid",
		Vector2(float(ATLAS_COLUMNS), float(ATLAS_ROWS)))
	# Fog is NOT set here: this material is shared by four headless tools that
	# have no player, and the shader's `hint_default_white` leaves them looking
	# at the whole map. Only a client in a match calls `set_fog` (D-102).
	return material


## Bind one client's fog-of-war field to the terrain material (D-102).
##
## Separated from the client so the binding is reachable from a headless test:
## the defect this closes was not a wrong fog field, it was a right one that
## never reached the ground, and the only thing that could have caught it is a
## check that the material actually carries it.
##
## Silently does nothing on the untextured fallback (`make_material` returns a
## StandardMaterial3D when `generated/` has not been built), which is the same
## bargain the fallback already makes everywhere else: no art build costs
## fidelity, never the game.
static func set_fog(material: Material, fog: Texture2D) -> void:
	var shaded := material as ShaderMaterial
	if shaded == null:
		return
	shaded.set_shader_parameter(TerrainFog.SHADER_PARAM, fog)


## Build every chunk, returning stats. This is the measurement
## `gen-terrain-preview` reports so chunk size can be chosen from data
## rather than guessed (D-017's revisit trigger).
static func build_all(space: TorusSpace, terrain: TerrainGen, chunk_size: int) -> Dictionary:
	var grid := chunk_grid(space, chunk_size)
	var started := Time.get_ticks_usec()
	# Once for the whole map, not once per chunk — see build_mesh.
	var fields := terrain.build_fields(space)

	var meshes := 0
	var vertices := 0
	var triangles := 0
	# Counted separately, because "the mechanism is built and the shipped map
	# produces none of it" is a defect family this project has hit repeatedly and
	# a total that folds the two together could not show it (D-097).
	var cliff_quads := 0

	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := build_mesh(space, terrain, Vector2i(cx, cy), chunk_size, fields)
			if mesh == null:
				continue
			meshes += 1
			for surface in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface)
				vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var faces := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				triangles += faces
				if surface == SKIRT_SURFACE:
					@warning_ignore("integer_division")
					cliff_quads += faces / 2

	return {
		"chunk_size": chunk_size,
		"chunks": meshes,
		"grid": grid,
		"vertices": vertices,
		"triangles": triangles,
		"cliff_quads": cliff_quads,
		"build_usec": Time.get_ticks_usec() - started,
	}
