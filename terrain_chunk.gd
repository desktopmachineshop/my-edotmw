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

# Corner angles for a pointy-top hexagon.
const CORNERS := 6


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
static func build_mesh(space: TorusSpace, terrain: TerrainGen, chunk: Vector2i, chunk_size: int) -> ArrayMesh:
	var size := maxi(1, chunk_size)
	var origin := Vector2i(chunk.x * size, chunk.y * size)

	var cells_x := mini(size, space.width - origin.x)
	var cells_y := mini(size, space.height - origin.y)
	if cells_x <= 0 or cells_y <= 0:
		return null

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for dy in range(cells_y):
		for dx in range(cells_x):
			var unwrapped := Vector2i(origin.x + dx, origin.y + dy)
			# Geometry unwrapped...
			var centre := space.axial_offset_to_world(Vector2(float(unwrapped.x), float(unwrapped.y)))
			# ...data wrapped.
			var elevation := terrain.elevation_at(space, unwrapped)
			var color := terrain.biome_color(space, unwrapped)
			centre.y = elevation * terrain.height_scale

			var base := vertices.size()
			vertices.append(centre)
			normals.append(Vector3.UP)
			colors.append(color)

			for corner in range(CORNERS):
				var angle := TAU * (float(corner) / float(CORNERS)) - PI / 6.0
				vertices.append(centre + Vector3(
					space.hex_size * cos(angle), 0.0, space.hex_size * sin(angle)))
				normals.append(Vector3.UP)
				colors.append(color)

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
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Build every chunk, returning stats. This is the measurement
## `gen-terrain-preview` reports so chunk size can be chosen from data
## rather than guessed (D-017's revisit trigger).
static func build_all(space: TorusSpace, terrain: TerrainGen, chunk_size: int) -> Dictionary:
	var grid := chunk_grid(space, chunk_size)
	var started := Time.get_ticks_usec()

	var meshes := 0
	var vertices := 0
	var triangles := 0

	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := build_mesh(space, terrain, Vector2i(cx, cy), chunk_size)
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
