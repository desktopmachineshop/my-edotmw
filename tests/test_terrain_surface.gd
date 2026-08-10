extends GutTest

## Guards D-067 — the continuous ground surface — and above all the agreement
## between the mesh and the ground sampler.
##
## The failure this file exists for does not crash and does not fail any count.
## If `TerrainChunk.height_at` and `TerrainChunk.build_mesh` ever disagree about
## where the ground is, the army floats or sinks while squad counts, soldier
## counts and desyncs all stay perfectly green. That is the exact shape of the
## first client frame this project ever rendered, which contained no visible
## soldiers because they were deriving at y = 0 inside the hills.
##
## So the central test here does not re-implement the surface and compare
## against its own arithmetic — it reads the vertices out of a REAL built mesh
## and asks the sampler about those same positions.

const CHUNK := 8


func _space() -> TorusSpace:
	return TorusSpace.new(16, 8)


func _terrain() -> TerrainGen:
	var terrain := TerrainGen.new()
	terrain.noise_seed = 90210
	return terrain


# --- the sampler and the mesh agree (the whole point) -------------------


func test_the_sampler_returns_the_height_the_mesh_was_built_with() -> void:
	var space := _space()
	var terrain := _terrain()
	var surface := terrain.surface_field(space)
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK, surface)
	assert_not_null(mesh)

	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_gt(vertices.size(), 0)

	var worst := 0.0
	for vertex in vertices:
		var sampled := TerrainChunk.height_at(space, surface, vertex.x, vertex.z)
		worst = maxf(worst, absf(sampled - vertex.y))

	assert_lt(worst, 0.001,
		"the ground sampler disagrees with the mesh by up to %.4f world units. "
			% worst
		+ "Soldiers, buildings and resource nodes are all placed by that "
		+ "sampler, so they would float above or sink into the ground that is "
		+ "actually drawn.")


func test_the_sampler_interpolates_between_vertices_rather_than_stepping() -> void:
	# The defect being removed: every point inside a hex used to return that
	# cell's single height, so the ground was a field of plateaus.
	var space := _space()
	var terrain := _terrain()
	var surface := terrain.surface_field(space)

	var centre := space.to_world(Vector2i(4, 4))
	var samples := []
	for step in range(9):
		var x := centre.x - 0.8 + 0.2 * float(step)
		samples.append(TerrainChunk.height_at(space, surface, x, centre.z))

	var distinct := {}
	for value in samples:
		distinct[snappedf(value, 0.0001)] = true
	assert_gt(distinct.size(), 2,
		"nine samples across one hex produced %d distinct heights — the ground "
			% distinct.size() + "is still stepping rather than interpolating")


# --- watertight: neighbours agree at every shared corner ----------------


## Two adjacent cells must place their SHARED corner at the same height, or a
## vertical slot opens between them. That slot is what produced dark seams
## across the whole map: elevation is continuous noise sampled per cell, so
## essentially no two neighbours shared a height and almost every boundary had
## one.
## `a` and `b` are UNWRAPPED cell coordinates. Positions come from
## `axial_offset_to_world` rather than `to_world`, because `to_world` normalises
## and a seam-crossing pair would then sit a whole map apart and share nothing —
## the same unwrapped-geometry/wrapped-data rule `terrain_chunk.gd` documents.
func _assert_corners_agree(space: TorusSpace, surface: PackedFloat32Array,
		a: Vector2i, b: Vector2i) -> void:
	var world_a := space.axial_offset_to_world(Vector2(a))
	var world_b := space.axial_offset_to_world(Vector2(b))
	var shared := 0
	for ka in range(6):
		var pa := world_a + _corner_offset(space, ka)
		for kb in range(6):
			var pb := world_b + _corner_offset(space, kb)
			if Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)) > 0.001:
				continue
			shared += 1
			var ha := surface[space.index(a) * TerrainGen.SURFACE_STRIDE + 1 + ka]
			var hb := surface[space.index(b) * TerrainGen.SURFACE_STRIDE + 1 + kb]
			assert_almost_eq(ha, hb, 0.0001,
				"cells %s and %s disagree about their shared corner (%.4f vs "
					% [a, b, ha] + "%.4f) — that gap is what shows as a seam" % hb)
	assert_eq(shared, 2, "adjacent hexes share exactly two corners, found %d"
		% shared)


static func _corner_offset(space: TorusSpace, corner: int) -> Vector3:
	var angle := TAU * (float(corner) / 6.0) - PI / 6.0
	return Vector3(space.hex_size * cos(angle), 0.0, space.hex_size * sin(angle))


func test_neighbouring_cells_agree_at_their_shared_corners() -> void:
	var space := _space()
	var surface := _terrain().surface_field(space)
	var cell := Vector2i(5, 3)
	for direction in range(6):
		_assert_corners_agree(space, surface, cell,
			cell + TorusSpace.DIRECTIONS[direction])


func test_cells_agree_across_the_seam_too() -> void:
	# D-008's recurring tax. The corner field is built from neighbour lookups,
	# and a lookup that forgot to wrap would tear the map along its own edge.
	var space := _space()
	var surface := _terrain().surface_field(space)
	var edge := Vector2i(space.width - 1, 4)
	for direction in range(6):
		# Deliberately NOT space.neighbor(), which wraps: the neighbour east of
		# the last column is cell `width`, whose geometry sits just past the
		# seam while its data comes from column 0.
		_assert_corners_agree(space, surface, edge,
			edge + TorusSpace.DIRECTIONS[direction])


# --- water ---------------------------------------------------------------


func test_the_sea_is_flat_however_deep_the_noise_goes() -> void:
	var space := _space()
	var terrain := _terrain()
	var raw := terrain.elevation_field(space)
	var surface := terrain.surface_field(space)

	# Two water cells whose RAW elevations differ. Without clamping their
	# rendered heights would differ too, and the sea would visibly tilt.
	var first := -1
	var second := -1
	for i in range(space.cell_count()):
		if raw[i] >= terrain.sea_level:
			continue
		if first < 0:
			first = i
		elif absf(raw[i] - raw[first]) > 0.02:
			second = i
			break

	if second < 0:
		pass_test("no two water cells with different depths at this seed")
		return

	assert_almost_eq(
		surface[first * TerrainGen.SURFACE_STRIDE],
		surface[second * TerrainGen.SURFACE_STRIDE], 0.0001,
		"two water cells rendered at different heights, so the sea slopes")
	assert_almost_eq(surface[first * TerrainGen.SURFACE_STRIDE],
		terrain.sea_level * terrain.height_scale, 0.0001,
		"water should render at exactly sea level")


func test_clamping_water_did_not_flatten_the_land() -> void:
	var space := _space()
	var terrain := _terrain()
	var surface := terrain.surface_field(space)
	var heights := {}
	for i in range(space.cell_count()):
		heights[snappedf(surface[i * TerrainGen.SURFACE_STRIDE], 0.001)] = true
	assert_gt(heights.size(), 5,
		"the whole map rendered at %d distinct heights — the clamp is eating "
			% heights.size() + "the terrain, not just the sea")


# --- normals -------------------------------------------------------------


## Normals were hardcoded to Vector3.UP, so slopes had no shading at all. This
## asserts the thing HAPPENED rather than that nothing complained: at least some
## of the surface must now face somewhere other than straight up.
func test_slopes_have_real_normals_now() -> void:
	var space := _space()
	var terrain := _terrain()
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK)
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]

	var tilted := 0
	for normal in normals:
		assert_almost_eq(normal.length(), 1.0, 0.001, "normals must be unit length")
		assert_gt(normal.y, 0.0, "the ground must never face downward")
		if normal.distance_to(Vector3.UP) > 0.001:
			tilted += 1

	assert_gt(tilted, normals.size() / 10,
		"only %d of %d normals are tilted; the ground is still being lit as if "
			% [tilted, normals.size()] + "it were flat")


## A corner's normal is derived from the three cell centres meeting there, so
## all three owners compute the same vector. If it were accumulated from each
## cell's own triangles instead, every hex would light slightly differently and
## the grid would reappear in the shading after the geometry stopped showing it.
func test_a_shared_corner_gets_the_same_normal_from_every_cell_that_owns_it() -> void:
	var space := _space()
	var terrain := _terrain()
	var surface := terrain.surface_field(space)
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK, surface)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# Group vertices by position; anything appearing more than once is shared
	# between cells and must carry one agreed normal.
	var by_position := {}
	for i in range(vertices.size()):
		var key := "%.3f,%.3f" % [vertices[i].x, vertices[i].z]
		if not by_position.has(key):
			by_position[key] = []
		by_position[key].append(i)

	var checked := 0
	for key in by_position:
		var group: Array = by_position[key]
		if group.size() < 2:
			continue
		checked += 1
		for j in range(1, group.size()):
			assert_lt(normals[group[0]].distance_to(normals[group[j]]), 0.001,
				"a shared corner has two different normals, which lights each "
				+ "hex separately and puts the grid back into the picture")
	assert_gt(checked, 0, "no shared corners found; the test proved nothing")
