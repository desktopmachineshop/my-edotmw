extends GutTest

## Guards D-008's "periodic noise sampling" tax and D-017's chunking.
##
## The seam tests here are the ones that matter. Non-periodic noise over a
## wrapped grid produces terrain that looks completely fine in isolation
## and in aggregate statistics — sensible water fraction, sensible biome
## spread — while having a hard discontinuity down both seams. It is only
## visible if you specifically go looking, which is what these do.

const W := 64
const H := 32


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _terrain() -> TerrainGen:
	return TerrainGen.new()


# --- periodicity ------------------------------------------------------

## Mean absolute elevation change between two columns.
func _column_delta(terrain: TerrainGen, space: TorusSpace, q_a: int, q_b: int) -> float:
	var total := 0.0
	for r in range(space.height):
		total += absf(terrain.elevation_at(space, Vector2i(q_a, r))
			- terrain.elevation_at(space, Vector2i(q_b, r)))
	return total / float(space.height)


## Mean absolute elevation change between two rows.
func _row_delta(terrain: TerrainGen, space: TorusSpace, r_a: int, r_b: int) -> float:
	var total := 0.0
	for q in range(space.width):
		total += absf(terrain.elevation_at(space, Vector2i(q, r_a))
			- terrain.elevation_at(space, Vector2i(q, r_b)))
	return total / float(space.width)


func test_elevation_is_continuous_across_the_horizontal_seam() -> void:
	var space := _space()
	var terrain := _terrain()

	var seam := _column_delta(terrain, space, W - 1, 0)
	# Compare against typical adjacent-column change well inside the map.
	var interior := 0.0
	for q in [8, 20, 33, 47]:
		interior += _column_delta(terrain, space, q, q + 1)
	interior /= 4.0

	assert_lt(seam, interior * 3.0,
		"Elevation jumps %.4f across the horizontal seam vs %.4f typical interior — noise is not periodic in q" % [seam, interior])


func test_elevation_is_continuous_across_the_vertical_seam() -> void:
	var space := _space()
	var terrain := _terrain()

	var seam := _row_delta(terrain, space, H - 1, 0)
	var interior := 0.0
	for r in [5, 12, 19, 26]:
		interior += _row_delta(terrain, space, r, r + 1)
	interior /= 4.0

	assert_lt(seam, interior * 3.0,
		"Elevation jumps %.4f across the vertical seam vs %.4f typical interior — noise is not periodic in r" % [seam, interior])


func test_sampling_out_of_domain_wraps() -> void:
	var space := _space()
	var terrain := _terrain()
	assert_almost_eq(terrain.elevation_at(space, Vector2i(W + 3, 5)),
		terrain.elevation_at(space, Vector2i(3, 5)), 0.0001)
	assert_almost_eq(terrain.elevation_at(space, Vector2i(-1, H + 2)),
		terrain.elevation_at(space, Vector2i(W - 1, 2)), 0.0001)


func test_terrain_is_deterministic_for_a_seed() -> void:
	# Client and server both derive terrain; divergence here would move
	# soldiers (D-006 takes a terrain sample as an input).
	var space := _space()
	var a := TerrainGen.new()
	var b := TerrainGen.new()
	for cell in [Vector2i(0, 0), Vector2i(31, 17), Vector2i(63, 31)]:
		assert_almost_eq(a.elevation_at(space, cell), b.elevation_at(space, cell), 0.0001,
			"Two TerrainGen instances disagree at %s" % cell)


func test_different_seeds_give_different_terrain() -> void:
	var space := _space()
	var a := TerrainGen.new()
	var b := TerrainGen.new()
	b.noise_seed = a.noise_seed + 1

	var differences := 0
	for q in range(0, W, 4):
		for r in range(0, H, 4):
			if absf(a.elevation_at(space, Vector2i(q, r)) - b.elevation_at(space, Vector2i(q, r))) > 0.01:
				differences += 1
	assert_gt(differences, 0, "Changing the seed should change the terrain")


# --- the field is actually varied ------------------------------------

func test_terrain_has_both_land_and_water() -> void:
	# The failure this catches: a scaling mistake that flattens the noise
	# produces a map that is entirely one biome, which still "works".
	var space := _space()
	var terrain := _terrain()
	var water := 0
	for i in range(space.cell_count()):
		if terrain.is_water(space, space.from_index(i)):
			water += 1
	var fraction := float(water) / float(space.cell_count())
	assert_between(fraction, 0.02, 0.8,
		"Water covers %.1f%% of the map — expected a mix of land and water" % (fraction * 100.0))


func test_neighbouring_cells_are_usually_similar() -> void:
	# Guards the opposite mistake: sampling at too large a scale gives
	# every cell an independent value, which is per-cell static rather
	# than terrain — and which passes every aggregate check.
	var space := _space()
	var terrain := _terrain()

	var neighbour_delta := 0.0
	var samples := 0
	for q in range(0, W, 2):
		for r in range(0, H, 2):
			var here := terrain.elevation_at(space, Vector2i(q, r))
			for n in space.neighbors(Vector2i(q, r)):
				neighbour_delta += absf(here - terrain.elevation_at(space, n))
				samples += 1
	neighbour_delta /= float(samples)

	# Compare against the delta between far-apart cells, which should be
	# much larger if the field is spatially coherent.
	#
	# A QUARTER of the map away, not half. This used to sample half a map
	# away, which stopped being "far" the moment terrain became
	# quadrant-symmetric (D-036): with axis_repeats=2 the cell half a map
	# away is the *same sample point*, so far_delta measured exactly 0.0
	# and the test failed against a perfectly good generator. A quarter map
	# is the furthest two cells can actually be in noise terms once the
	# field repeats twice per axis.
	var far_delta := 0.0
	var far_samples := 0
	for q in range(0, W, 2):
		for r in range(0, H, 2):
			far_delta += absf(terrain.elevation_at(space, Vector2i(q, r))
				- terrain.elevation_at(space, Vector2i((q + W / 4) % W, (r + H / 4) % H)))
			far_samples += 1
	far_delta /= float(far_samples)

	assert_lt(neighbour_delta, far_delta * 0.5,
		"Neighbouring cells differ by %.4f vs %.4f for distant cells — the field is static, not terrain" % [neighbour_delta, far_delta])


# --- passability feeds pathfinding -----------------------------------

func test_passability_marks_water_and_mountains_impassable() -> void:
	var space := _space()
	var terrain := _terrain()
	var passable := terrain.passability(space)

	assert_eq(passable.size(), space.cell_count())
	for i in range(space.cell_count()):
		var cell := space.from_index(i)
		var e := terrain.elevation_at(space, cell)
		if e < terrain.sea_level or e >= terrain.mountain_level:
			assert_eq(passable[i], 0, "Cell %s at elevation %.2f should be impassable" % [cell, e])


func test_flow_field_routes_around_terrain() -> void:
	# The point of passability: terrain has to actually affect movement,
	# not just colour the map.
	var space := _space()
	var terrain := _terrain()
	var passable := terrain.passability(space)

	var destination := -1
	for i in range(space.cell_count()):
		if passable[i] != 0:
			destination = i
			break
	assert_gt(destination, -1, "There should be at least one passable cell")

	var field := FlowField.new()
	field.build(space, space.from_index(destination), passable)

	for i in range(space.cell_count()):
		if passable[i] == 0:
			assert_false(field.is_reachable(i),
				"Impassable cell %d should not be routable through" % i)


# --- chunking (D-017) -------------------------------------------------

func test_chunk_grid_covers_the_map() -> void:
	var space := _space()
	for chunk_size in [1, 7, 16, 64, 128]:
		var grid := TerrainChunk.chunk_grid(space, chunk_size)
		assert_gte(grid.x * chunk_size, space.width,
			"Chunk grid at size %d does not span the map width" % chunk_size)
		assert_gte(grid.y * chunk_size, space.height,
			"Chunk grid at size %d does not span the map height" % chunk_size)


func test_every_cell_is_meshed_exactly_once_regardless_of_chunk_size() -> void:
	# D-017's chunk size is open, so the mesher must be correct at ANY
	# size — including sizes that do not divide the map evenly.
	var space := _space()
	var terrain := _terrain()

	for chunk_size in [7, 16, 30]:
		var stats := TerrainChunk.build_all(space, terrain, chunk_size)
		# The ground is 7 vertices and 6 triangles per cell; since D-097 the
		# cliff faces share the same chunk meshes and are counted in the same
		# totals, at 4 vertices and 2 triangles per quad. Subtracting them by
		# arithmetic rather than ignoring them keeps this test pinning the SHAPE
		# of the skirt as well as the count of the ground.
		var quads := int(stats["cliff_quads"])
		var expected_vertices := space.cell_count() * 7 + quads * 4
		var expected_triangles := space.cell_count() * 6 + quads * 2
		assert_eq(stats["vertices"], expected_vertices,
			"Chunk size %d meshed %d verts, expected %d (%d cells + %d cliff faces) — cells are being dropped or duplicated" % [chunk_size, stats["vertices"], expected_vertices, space.cell_count(), quads])
		assert_eq(stats["triangles"], expected_triangles,
			"Chunk size %d meshed %d tris, expected %d" % [chunk_size, stats["triangles"], expected_triangles])


func test_chunking_is_not_one_mesh_per_cell() -> void:
	# The explicit D-017 prohibition.
	var space := _space()
	var stats := TerrainChunk.build_all(space, _terrain(), 16)
	assert_lt(stats["chunks"], space.cell_count(),
		"Chunked terrain must produce far fewer meshes than cells (D-017)")
	assert_eq(stats["chunks"], 8, "A 64x32 map at chunk size 16 should be a 4x2 grid of chunks")


func test_chunk_geometry_is_contiguous_not_torn_by_the_wrap() -> void:
	# Chunk vertices are placed at unwrapped coordinates so a chunk stays
	# one piece. If they were wrapped, a chunk touching a seam would have
	# vertices at both ends of the map and its bounding box would span it.
	var space := _space()
	var mesh := TerrainChunk.build_mesh(space, _terrain(), Vector2i(3, 1), 16)
	assert_not_null(mesh)

	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var min_x := INF
	var max_x := -INF
	for v in vertices:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)

	var map_width_world := space.hex_size * TorusSpace.SQRT_3 * float(space.width)
	assert_lt(max_x - min_x, map_width_world * 0.5,
		"Chunk spans %.1f of a %.1f-wide map — geometry was wrapped and the chunk is torn" % [max_x - min_x, map_width_world])
