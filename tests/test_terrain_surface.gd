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


## Since D-097 the surface has deliberate STEPS in it, so a point sitting
## exactly on a shared corner has up to three drawn heights and no single right
## answer. The claim that still holds — and the one everything standing on the
## ground depends on — is that a point strictly INSIDE a cell samples that
## cell's own drawn surface.
##
## So each vertex is nudged 2% of the way toward its cell's centre, which is far
## enough inside for `round_axial` to name the same cell and near enough that
## the mesh's height there is a known lerp between the vertex and the centre.
func test_the_sampler_returns_the_height_the_mesh_was_built_with() -> void:
	var space := _space()
	var terrain := _terrain()
	var fields := terrain.build_fields(space)
	var surface := fields.surface
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK, fields)
	assert_not_null(mesh)

	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_gt(vertices.size(), 0)

	const INWARD := 0.02
	var worst := 0.0
	var checked := 0
	for cell in range(vertices.size() / TerrainGen.SURFACE_STRIDE):
		var base := cell * TerrainGen.SURFACE_STRIDE
		var centre := vertices[base]
		for vertex in range(TerrainGen.SURFACE_STRIDE):
			var here := vertices[base + vertex]
			var probe := here.lerp(centre, INWARD)
			var expected := lerpf(here.y, centre.y, INWARD)
			var sampled := TerrainChunk.height_at(space, surface, probe.x, probe.z)
			worst = maxf(worst, absf(sampled - expected))
			checked += 1

	assert_gt(checked, 0)
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
	var fields := terrain.build_fields(space)
	var surface := fields.surface

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


## Two adjacent cells must either place their SHARED corner at the same height,
## or step by a whole cliff (D-097). What must never happen is a sliver: a
## vertical slot too small to be a cliff and too large to be nothing, which
## nothing draws and which shows as a dark seam. That was the pre-D-084 defect —
## elevation is continuous noise sampled per cell, so essentially no two
## neighbours shared a height and almost every boundary had one.
##
## `a` and `b` are UNWRAPPED cell coordinates. Positions come from
## `axial_offset_to_world` rather than `to_world`, because `to_world` normalises
## and a seam-crossing pair would then sit a whole map apart and share nothing —
## the same unwrapped-geometry/wrapped-data rule `terrain_chunk.gd` documents.
func _assert_corners_agree(space: TorusSpace, surface: PackedFloat32Array,
		a: Vector2i, b: Vector2i, min_step := 0.0) -> void:
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
			var gap := absf(ha - hb)
			if gap <= 0.0001:
				continue
			assert_gte(gap, min_step,
				"cells %s and %s differ by %.4f at their shared corner — too "
					% [a, b, gap]
				+ "small to be a cliff and too large to be nothing, so nothing "
				+ "draws it and it shows as a seam")
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
			cell + TorusSpace.DIRECTIONS[direction], _terrain().cliff_min_step)


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
			edge + TorusSpace.DIRECTIONS[direction], _terrain().cliff_min_step)


# --- water ---------------------------------------------------------------


func test_the_sea_is_flat_however_deep_the_noise_goes() -> void:
	var space := _space()
	var terrain := _terrain()
	var raw := terrain.elevation_field(space)
	var fields := terrain.build_fields(space)
	var surface := fields.surface

	# Two OPEN-water cells whose RAW elevations differ. Without clamping their
	# rendered heights would differ too, and the sea would visibly tilt.
	#
	# Open water — every one of the six neighbours also under water — because
	# D-096's pillow moved the centre vertex off the cell's own elevation and
	# onto a blend with its six shared corners. At a shoreline those corners are
	# averaged with the land beside them and the water genuinely does lift, by
	# the fraction `terrain_gen.gd`'s water section has always described. The
	# claim being tested is that the SEA is flat, not that every wet cell is;
	# the shore lift is bounded by the test below.
	var first := -1
	var second := -1
	for i in range(space.cell_count()):
		if not _is_open_water(space, terrain, raw, i):
			continue
		if first < 0:
			first = i
		elif absf(raw[i] - raw[first]) > 0.02:
			second = i
			break

	if second < 0:
		pass_test("no two open-water cells with different depths at this seed")
		return

	assert_almost_eq(
		surface[first * TerrainGen.SURFACE_STRIDE],
		surface[second * TerrainGen.SURFACE_STRIDE], 0.0001,
		"two water cells rendered at different heights, so the sea slopes")
	assert_almost_eq(surface[first * TerrainGen.SURFACE_STRIDE],
		terrain.sea_level * terrain.height_scale, 0.0001,
		"water should render at exactly sea level")


## Water with water on every side. Its corners are then averaged over water
## alone, so nothing about it can lift above sea level.
func _is_open_water(space: TorusSpace, terrain: TerrainGen,
		raw: PackedFloat32Array, index: int) -> bool:
	if raw[index] >= terrain.sea_level:
		return false
	for direction in range(6):
		if raw[space.neighbor_index(index, direction)] >= terrain.sea_level:
			return false
	return true


## The shoreline lift the clamp buys, bounded. A water cell touching land takes
## some of that land's height through its shared corners; if that were ever
## large the sea would visibly ramp up to the beach instead of meeting it.
func test_water_beside_land_lifts_only_slightly() -> void:
	var space := _space()
	var terrain := _terrain()
	var raw := terrain.elevation_field(space)
	var surface := terrain.build_fields(space).surface
	var sea := terrain.sea_level * terrain.height_scale

	var checked := 0
	for i in range(space.cell_count()):
		if raw[i] >= terrain.sea_level:
			continue
		checked += 1
		# The most any vertex of this cell can legally take from the land: a
		# corner is the mean of three cells, one of which is this water cell
		# sitting at exactly sea level, so two thirds of the tallest neighbour's
		# excess is the ceiling. Anything above it means something OTHER than a
		# shared corner is lifting the water.
		var tallest := 0.0
		for direction in range(6):
			tallest = maxf(tallest,
				raw[space.neighbor_index(i, direction)] - terrain.sea_level)
		var bound := tallest * 2.0 / 3.0 * terrain.height_scale + 0.0001
		for vertex in range(TerrainGen.SURFACE_STRIDE):
			var lift := surface[i * TerrainGen.SURFACE_STRIDE + vertex] - sea
			# Below sea level is the clamp failing: without it a deep cell's own
			# elevation would drag its rendered height down and the sea would
			# have a hole in it.
			assert_gte(lift, -0.0001, "water rendered BELOW sea level")
			assert_lte(lift, bound,
				"a water vertex sits %.3f above sea level, more than the %.3f "
					% [lift, bound]
				+ "its neighbours can account for through shared corners")
	assert_gt(checked, 0, "no water at this seed; the test proved nothing")


func test_clamping_water_did_not_flatten_the_land() -> void:
	var space := _space()
	var terrain := _terrain()
	var fields := terrain.build_fields(space)
	var surface := fields.surface
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
	var fields := terrain.build_fields(space)
	var surface := fields.surface
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK, fields)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# Group vertices by position; anything appearing more than once is shared
	# between cells and must carry one agreed normal.
	var by_position := {}
	for i in range(vertices.size()):
		# Position AND height: a cliff corner is two points at the same place,
		# and lighting the plateau with the valley's normal is exactly what
		# D-097 stopped doing.
		var key := "%.3f,%.3f,%.3f" % [vertices[i].x, vertices[i].z, vertices[i].y]
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
