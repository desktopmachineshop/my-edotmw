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
		for owner in [trio.x, trio.y, trio.z]:
			var b := int(fields.biome[owner])
			demand[b] = float(demand.get(b, 0.0)) + 1.0 / 3.0

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
		for owner in [corner_trios[k].x, corner_trios[k].y, corner_trios[k].z]:
			# A biome with no slot falls back to the cell's own, which keeps the
			# weights summing to exactly 1. A shortfall would darken the fragment
			# rather than merely mis-texture it.
			var slot: int = slot_of.get(int(fields.biome[owner]), 0)
			weights[base + slot] += 1.0 / 3.0

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
	var indices := PackedInt32Array()
	# Four floats per vertex each, because Godot's custom vertex channels come
	# in fixed widths; the fourth is unused and the shader reads .xyz.
	var tile_slots := PackedFloat32Array()
	var tile_weights := PackedFloat32Array()

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
			_append_tiles(tile_slots, tile_weights, slots, weights, 0)

			for corner in range(CORNERS):
				vertices.append(corner_positions[corner])
				# A corner's normal is derived from the three CELL CENTRES that
				# meet there, not from this cell's triangles. All three cells
				# compute it from the same three points and so agree exactly —
				# which is what makes the lighting continuous instead of
				# faceting the map back into hexes after the geometry stopped
				# doing so.
				normals.append(_corner_normal(space, surface, unwrapped, corner))
				colors.append(fields.colors[surface_base + 1 + corner])
				uvs.append(vertex_uv(uv_step, unwrapped, corner))
				_append_tiles(tile_slots, tile_weights, slots, weights, 1 + corner)

			# Fan from the centre vertex.
			for corner in range(CORNERS):
				indices.append(base)
				indices.append(base + 1 + corner)
				indices.append(base + 1 + (corner + 1) % CORNERS)

	if vertices.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
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


## The normal at a shared corner: the plane through the three cell centres that
## meet there (D-067).
##
## Derived from the FIELD rather than from this cell's triangles, so all three
## owners produce the identical vector. Accumulating triangle normals per cell
## would give each hex its own shading and put the grid straight back into the
## picture, which is the thing the smoothing exists to remove.
static func _corner_normal(space: TorusSpace, surface: PackedFloat32Array,
		cell: Vector2i, corner: int) -> Vector3:
	# The same two neighbours TerrainGen.surface_field averages for this corner.
	var a := space.normalize(cell + TorusSpace.DIRECTIONS[posmod(1 - corner, 6)])
	var b := space.normalize(cell + TorusSpace.DIRECTIONS[posmod(-corner, 6)])
	var here := space.normalize(cell)

	# Positions relative to `here`, so the seam cannot stretch the triangle.
	var pa := space.world_delta(here, a)
	pa.y = surface[space.index(a) * TerrainGen.SURFACE_STRIDE] \
		- surface[space.index(here) * TerrainGen.SURFACE_STRIDE]
	var pb := space.world_delta(here, b)
	pb.y = surface[space.index(b) * TerrainGen.SURFACE_STRIDE] \
		- surface[space.index(here) * TerrainGen.SURFACE_STRIDE]

	var normal := pa.cross(pb)
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
	return material


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

	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := build_mesh(space, terrain, Vector2i(cx, cy), chunk_size, fields)
			if mesh == null:
				continue
			meshes += 1
			var arrays := mesh.surface_get_arrays(0)
			vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3

	return {
		"chunk_size": chunk_size,
		"chunks": meshes,
		"grid": grid,
		"vertices": vertices,
		"triangles": triangles,
		"build_usec": Time.get_ticks_usec() - started,
	}
