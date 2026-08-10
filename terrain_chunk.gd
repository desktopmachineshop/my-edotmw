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

## ## UVs come from the CELL, never from world position (D-066)
##
## Each hex is mapped into its biome's tile in the generated atlas, and the
## whole tile layout is addressed by the biome index. That choice is what keeps
## the nine lattice copies (D-035) in agreement: the same mesh is drawn nine
## times at nine offsets, so any UV derived from world position would show a
## different phase on each copy unless the tile period happened to divide the
## lattice step exactly. Cell-derived UVs are identical on every copy by
## construction — the torus tax paid once, at design time, instead of forever.
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
## How far inside its tile a hex is drawn, as a fraction of the tile. Keeps the
## mip chain from sampling a neighbouring biome's tile at distance; the tiles
## themselves are periodic, so an inset costs continuity nothing.
const ATLAS_INSET := 0.06


## Where cell `unwrapped` samples the atlas, as (centre, radius) in UV space,
## plus a per-cell rotation.
##
## The rotation is hashed from the WRAPPED cell so it matches across the seam,
## and exists because a hex grid all sampling its tile at the same orientation
## reads as a visible repeating pattern — the eye finds the lattice immediately.
static func _atlas_frame(space: TorusSpace, terrain: TerrainGen,
		unwrapped: Vector2i) -> Dictionary:
	var wrapped := space.normalize(unwrapped)
	var biome := int(terrain.biome_at(space, wrapped))
	var column := biome % ATLAS_COLUMNS
	var row := biome / ATLAS_COLUMNS

	var tile_w := 1.0 / float(ATLAS_COLUMNS)
	var tile_h := 1.0 / float(ATLAS_ROWS)
	var centre := Vector2(
		(float(column) + 0.5) * tile_w,
		(float(row) + 0.5) * tile_h)

	# One radius in each axis, so a non-square atlas cell does not stretch the
	# texture; the hex is inscribed in the tile.
	var radius := Vector2(tile_w * (0.5 - ATLAS_INSET), tile_h * (0.5 - ATLAS_INSET))

	var hash_input := wrapped.x * 73856093 + wrapped.y * 19349663
	hash_input = (hash_input ^ (hash_input >> 13)) * 1274126177
	var turn := float((hash_input ^ (hash_input >> 16)) & 0xFFFF) / 65536.0
	return {"centre": centre, "radius": radius, "rotation": turn * TAU}


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
		chunk_size: int, surface := PackedFloat32Array()) -> ArrayMesh:
	# Callers meshing more than one chunk should build the surface once and pass
	# it: it is O(cells), and recomputing it per chunk would evaluate the
	# elevation noise for the whole map once per chunk. Defaulted rather than
	# required so existing call sites and tests keep working.
	if surface.is_empty():
		surface = terrain.surface_field(space)

	var size := maxi(1, chunk_size)
	var origin := Vector2i(chunk.x * size, chunk.y * size)

	var cells_x := mini(size, space.width - origin.x)
	var cells_y := mini(size, space.height - origin.y)
	if cells_x <= 0 or cells_y <= 0:
		return null

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for dy in range(cells_y):
		for dx in range(cells_x):
			var unwrapped := Vector2i(origin.x + dx, origin.y + dy)
			# Geometry unwrapped...
			var centre := space.axial_offset_to_world(Vector2(float(unwrapped.x), float(unwrapped.y)))
			# ...data wrapped.
			var color := terrain.biome_color(space, unwrapped)
			var surface_base := space.index(unwrapped) * TerrainGen.SURFACE_STRIDE
			centre.y = surface[surface_base]

			var frame := _atlas_frame(space, terrain, unwrapped)
			var uv_centre: Vector2 = frame["centre"]
			var uv_radius: Vector2 = frame["radius"]
			var uv_turn: float = frame["rotation"]

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
			colors.append(color)
			uvs.append(uv_centre)

			for corner in range(CORNERS):
				var angle := TAU * (float(corner) / float(CORNERS)) - PI / 6.0
				vertices.append(corner_positions[corner])
				# A corner's normal is derived from the three CELL CENTRES that
				# meet there, not from this cell's triangles. All three cells
				# compute it from the same three points and so agree exactly —
				# which is what makes the lighting continuous instead of
				# faceting the map back into hexes after the geometry stopped
				# doing so.
				normals.append(_corner_normal(space, surface, unwrapped, corner))
				colors.append(color)
				# The same corner, turned by this cell's rotation, inside its
				# biome's tile. V is negated because UV space runs downward
				# while the world's +Z runs away from the camera.
				var uv_angle := angle + uv_turn
				uvs.append(uv_centre + Vector2(
					uv_radius.x * cos(uv_angle), -uv_radius.y * sin(uv_angle)))

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
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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


## The material every terrain chunk shares.
##
## One definition, used by the client and by `bench-render`, because those two
## had drifted into identical copies and a benchmark that renders a different
## material than the game measures the wrong thing.
##
## `vertex_color_use_as_albedo` stays on and the atlas MULTIPLIES it (D-066).
## The texture supplies detail; `biome_color` still supplies the colour, so the
## minimap and the terrain preview — which read that same function and never
## touch this material — cannot fall out of step with the 3D view. An atlas
## whose tiles average near neutral therefore changes the palette not at all,
## which is what `art/terrain/atlas.py` is written to guarantee.
##
## Falls back to plain vertex colour when `generated/` has not been built, for
## the same reason units fall back to primitives: a missing art build should
## cost fidelity, not the game.
static func make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	if ResourceLoader.exists(ATLAS_PATH):
		material.albedo_texture = load(ATLAS_PATH) as Texture2D
	return material


## Build every chunk, returning stats. This is the measurement
## `gen-terrain-preview` reports so chunk size can be chosen from data
## rather than guessed (D-017's revisit trigger).
static func build_all(space: TorusSpace, terrain: TerrainGen, chunk_size: int) -> Dictionary:
	var grid := chunk_grid(space, chunk_size)
	var started := Time.get_ticks_usec()
	# Once for the whole map, not once per chunk — see build_mesh.
	var surface := terrain.surface_field(space)

	var meshes := 0
	var vertices := 0
	var triangles := 0

	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := build_mesh(space, terrain, Vector2i(cx, cy), chunk_size, surface)
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
