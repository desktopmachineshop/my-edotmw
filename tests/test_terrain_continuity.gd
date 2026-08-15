extends GutTest

## Guards D-096 — the ground is continuous — and the two ways it can quietly
## stop being so.
##
## The ground used to read as a honeycomb of flat hexes for three reasons, all
## of which pass every numeric check: vertex colour was one flat value per cell,
## the centre vertex sat at the cell's own elevation and domed each hex, and the
## texture restarted inside every hex. This file covers the first two; the UVs
## are `test_terrain_uvs.gd`'s job.
##
## None of it can be seen by counting anything, which is why the standing rule
## applies twice over here: the artifact PNG is the primary evidence, and these
## tests exist to stop it silently regressing afterwards.

const CHUNK := 8


func _space() -> TorusSpace:
	return TorusSpace.new(16, 8)


func _terrain() -> TerrainGen:
	var terrain := TerrainGen.new()
	terrain.noise_seed = 90210
	return terrain


# --- colour is per VERTEX, and shared corners agree ----------------------


## The whole claim, read off a real mesh: a corner that two or three cells own
## carries ONE colour. If each owner blended in its own order the values would
## differ in the last bit and the seam would be invisible here but present in
## the picture; `TerrainGen.corner_cells` sorts precisely so this is exact.
func test_a_shared_corner_gets_the_same_colour_from_every_cell_that_owns_it() -> void:
	var space := _space()
	var terrain := _terrain()
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]

	var by_position := {}
	for i in range(vertices.size()):
		# Position AND height, because since D-097 a cliff corner is two points
		# at the same place: the colour steps with the surface there, so that the
		# rock face is not painted in the colours of the valley below it.
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
			assert_eq(colors[group[0]], colors[group[j]],
				"a shared corner carries two different colours, which steps the "
				+ "ground at that boundary — the honeycomb, back again")
	assert_gt(checked, 0, "no shared corners found; the test proved nothing")


## `biome_color` stays the single source of truth (D-083). The minimap and the
## terrain preview PNG read it per cell and never see this mesh, so if the
## centre vertex stopped agreeing with it the small picture and the big one
## would drift apart with nothing failing.
func test_the_centre_vertex_still_carries_biome_color_exactly() -> void:
	var space := _space()
	var terrain := _terrain()
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK)
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]

	var vertex := 0
	for dy in range(CHUNK):
		for dx in range(CHUNK):
			var expected := terrain.biome_color(space, Vector2i(dx, dy))
			# Within a quantisation step: an ArrayMesh stores vertex colour as
			# RGBA8, so a channel read back out is the authored value rounded to
			# 1/255. That rounding is deterministic, which is why the
			# shared-corner test above can still demand exact equality.
			for channel in ["r", "g", "b"]:
				assert_almost_eq(colors[vertex][channel], expected[channel],
					1.0 / 255.0,
					"cell (%d,%d)'s centre is not its biome colour" % [dx, dy])
			vertex += TerrainGen.SURFACE_STRIDE


## Every blended colour must stay inside the range its three owners span. A
## blend that overshot would invent a colour no biome has — and, worse, one the
## minimap could never show.
func test_a_blended_corner_stays_between_the_biomes_it_blends() -> void:
	var space := _space()
	var terrain := _terrain()
	var fields := terrain.build_fields(space)

	for i in range(space.cell_count()):
		for k in range(6):
			var trio := TerrainGen.corner_cells(space, i, k)
			var blended := fields.color(i, 1 + k)
			for channel in ["r", "g", "b"]:
				var low := 2.0
				var high := -1.0
				for owner in [trio.x, trio.y, trio.z]:
					var own: float = TerrainGen.color_of(fields.biome[owner])[channel]
					low = minf(low, own)
					high = maxf(high, own)
				assert_between(blended[channel], low - 0.0001, high + 0.0001,
					"corner %d of cell %d blended outside its owners' range"
						% [k, i])


## Assert the blend actually HAPPENS, on the SHIPPED map with the SHIPPED
## generator — not on a caricature. A mechanism that is correct and does nothing
## on the map people play is a defect family this project has hit repeatedly
## (D-066's building damage being the clearest case).
func test_the_shipped_map_really_does_blend() -> void:
	var config := load("res://maps/default.tres") as MapConfig
	assert_not_null(config, "maps/default.tres did not load")
	var space := config.to_space()
	var terrain := TerrainGen.new()
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(1, 1), 16)
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]

	var cells := colors.size() / TerrainGen.SURFACE_STRIDE
	var blended := 0
	for cell in range(cells):
		var base := cell * TerrainGen.SURFACE_STRIDE
		for vertex in range(1, TerrainGen.SURFACE_STRIDE):
			if colors[base + vertex] != colors[base]:
				blended += 1
				break

	assert_gt(blended, cells / 5,
		"only %d of %d cells in a shipped chunk have any colour variation "
			% [blended, cells]
		+ "across their vertices — the ground is still flat per hex")


# --- the pillow ----------------------------------------------------------


## `pillow` must be READ, not merely declared. Three shipped `CivDef` knobs and
## two `.cost` fields have been declared-and-unread in this project's history;
## a tunable nothing consumes is the fourth family member.
func test_the_pillow_changes_the_centre_vertex() -> void:
	var space := _space()

	var domed := _terrain()
	domed.pillow = 1.0
	var flat := _terrain()
	flat.pillow = 0.0

	var raw := domed.elevation_field(space)
	var domed_fields := domed.build_fields(space)
	var domed_surface := domed_fields.surface
	var flat_surface := flat.build_fields(space).surface

	var moved := 0
	for i in range(space.cell_count()):
		var base := i * TerrainGen.SURFACE_STRIDE
		# pillow 1.0 is the pre-D-096 behaviour exactly: the centre sits at the
		# cell's own (clamped) elevation — plus D-097's rise, on the impassable
		# tier that is deliberately drawn above its own elevation.
		var own := maxf(raw[i], domed.sea_level) * domed.height_scale
		if domed_fields.cliff_class[i] == int(TerrainGen.CliffClass.HIGH):
			own += domed.cliff_rise
		assert_almost_eq(domed_surface[base], own, 0.0001,
			"pillow 1.0 must reproduce the old centre height")
		# pillow 0.0 puts the centre on the plane of its own six corners.
		var corner_mean := 0.0
		for k in range(6):
			corner_mean += flat_surface[base + 1 + k]
		corner_mean /= 6.0
		assert_almost_eq(flat_surface[base], corner_mean, 0.0001,
			"pillow 0.0 must put the centre on its corners' mean")
		if absf(domed_surface[base] - flat_surface[base]) > 0.001:
			moved += 1

	assert_gt(moved, space.cell_count() / 4,
		"only %d cells moved between pillow 0 and 1; the knob is barely "
			% moved + "connected to anything")


## The shipped value, on the shipped map: the dome must be mostly gone. Stated
## as a fraction of the dome the old code drew, because that is the quantity
## that made the lattice legible.
func test_the_shipped_pillow_flattens_the_dome() -> void:
	var config := load("res://maps/default.tres") as MapConfig
	var space := config.to_space()
	var terrain := TerrainGen.new()
	assert_lt(terrain.pillow, 0.25,
		"the shipped pillow is %.2f — high enough to put the hex grid back "
			% terrain.pillow + "into the lighting")

	var surface := terrain.build_fields(space).surface
	var worst := 0.0
	for i in range(space.cell_count()):
		var base := i * TerrainGen.SURFACE_STRIDE
		var corner_mean := 0.0
		for k in range(6):
			corner_mean += surface[base + 1 + k]
		corner_mean /= 6.0
		worst = maxf(worst, absf(surface[base] - corner_mean))

	# The old code's dome, for comparison: the same map with pillow 1.0.
	var domed := TerrainGen.new()
	domed.pillow = 1.0
	var domed_surface := domed.build_fields(space).surface
	var domed_worst := 0.0
	for i in range(space.cell_count()):
		var base := i * TerrainGen.SURFACE_STRIDE
		var corner_mean := 0.0
		for k in range(6):
			corner_mean += domed_surface[base + 1 + k]
		corner_mean /= 6.0
		domed_worst = maxf(domed_worst, absf(domed_surface[base] - corner_mean))

	assert_lt(worst, domed_worst * 0.25,
		"the worst dome is %.3f world units against the old %.3f — the pillow "
			% [worst, domed_worst] + "is not actually flattening anything")


# --- the corner triple ---------------------------------------------------


## `corner_cells` is the one definition of "which three cells meet here", and
## heights, colours and (with the shader) tile weights all hang off it. Checked
## GEOMETRICALLY rather than against a re-derivation of the same index
## arithmetic, which would only prove the formula equals itself.
func test_corner_cells_names_the_three_cells_whose_corners_coincide() -> void:
	var space := _space()
	for cell in [Vector2i(3, 2), Vector2i(0, 0), Vector2i(space.width - 1, 5)]:
		var index := space.index(cell)
		for k in range(6):
			var trio := TerrainGen.corner_cells(space, index, k)
			assert_true(trio.x <= trio.y and trio.y <= trio.z,
				"corner_cells must return sorted indices, got %s" % trio)
			var members := [trio.x, trio.y, trio.z]
			assert_true(members.has(index),
				"a cell must be one of the owners of its own corner")

			var here := _corner_world(space, cell, k)
			for owner in members:
				if owner == index:
					continue
				var found := false
				for other in range(6):
					var there := _corner_world(space,
						space.from_index(owner), other)
					# Wrapped comparison: a corner shared across the seam sits a
					# whole map period away in unwrapped world space.
					if _same_point(space, here, there):
						found = true
						break
				assert_true(found,
					"cell %d is named as an owner of corner %d of %s but has no "
						% [owner, k, cell] + "corner at that point")


static func _corner_world(space: TorusSpace, cell: Vector2i, corner: int) -> Vector3:
	var angle := TAU * (float(corner) / 6.0) - PI / 6.0
	return space.to_world(cell) + Vector3(
		space.hex_size * cos(angle), 0.0, space.hex_size * sin(angle))


static func _same_point(space: TorusSpace, a: Vector3, b: Vector3) -> bool:
	for offset in space.lattice_offsets():
		if a.distance_to(b + offset) < 0.001:
			return true
	return false
