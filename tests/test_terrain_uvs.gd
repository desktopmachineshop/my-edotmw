extends GutTest

## Guards D-096's third strand — terrain texturing — and the ways it can go
## wrong quietly.
##
## Before D-096 each hex was inscribed in its own biome's atlas tile with an
## inset and a hashed rotation, so the texture RESTARTED at every cell boundary.
## That was the strongest remaining cue of the hex lattice once the colour was
## blended, and it is what these tests now describe the replacement of.
##
## Three separate properties, each with its own failure:
##
## 1. **Continuity.** Two cells sharing a corner must place that corner at the
##    same UV, or the texture steps at the boundary — the old defect, back.
## 2. **The seam.** Terrain geometry is UNWRAPPED and terrain data is WRAPPED
##    (see terrain_chunk.gd), and the whole map is drawn nine times (D-035). A
##    continuous coordinate therefore has to be PERIODIC over the map's two
##    lattice vectors, or the ninth copy meets the first mid-pattern.
## 3. **The right tile.** A fragment reads the atlas at a continuous coordinate,
##    so it has to be told which of the eight tiles to wrap that coordinate into.
##    Getting it wrong paints forest on water — nothing errors; the map simply
##    lies about what a cell yields.


func _space() -> TorusSpace:
	return TorusSpace.new(16, 8)


func _terrain() -> TerrainGen:
	var terrain := TerrainGen.new()
	terrain.noise_seed = 4242
	return terrain


const CHUNK_SIZE := 8


# --- continuity ----------------------------------------------------------


## The claim, read off a real mesh: a corner two cells share carries ONE UV.
##
## Exactly equal, not nearly — `TerrainChunk.vertex_uv` evaluates the
## coordinate as an integer numerator over a fixed denominator precisely so
## that two cells reaching the same point by different arithmetic cannot land a
## few ulps apart.
func test_two_cells_sharing_a_corner_place_it_at_the_same_uv() -> void:
	var space := _space()
	var mesh := TerrainChunk.build_mesh(space, _terrain(), Vector2i(0, 0), CHUNK_SIZE)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]

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
			assert_eq(uvs[group[0]], uvs[group[j]],
				"a shared corner has two different UVs, so the texture steps "
				+ "across that boundary")
	assert_gt(checked, 0, "no shared corners found; the test proved nothing")


## The defect being removed, stated directly. Every cell used to sample its
## biome's tile at the same place, so two grassland hexes had literally
## identical UVs and the pattern restarted in each.
func test_the_texture_no_longer_restarts_inside_every_hex() -> void:
	var space := _space()
	var mesh := TerrainChunk.build_mesh(space, _terrain(), Vector2i(0, 0), CHUNK_SIZE)
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]

	var centres := {}
	var cells := uvs.size() / TerrainGen.SURFACE_STRIDE
	for cell in range(cells):
		centres[uvs[cell * TerrainGen.SURFACE_STRIDE]] = true
	assert_eq(centres.size(), cells,
		"%d cells share only %d distinct centre UVs — the texture is still "
			% [cells, centres.size()] + "an island per hex")


# --- the seam ------------------------------------------------------------


## The condition that makes the nine lattice copies (D-035) agree: stepping a
## whole map period in either direction must move the UV by a WHOLE number of
## texture repeats.
##
## Both of the torus's period vectors are checked, and the second is the one
## that catches a plausible-looking mistake: stepping `height` in r moves world
## x as well as z, because x depends on r/2 — so a scale that only divides the
## width leaves a visible tear along the diagonal seams.
func test_a_whole_map_period_is_a_whole_number_of_texture_repeats() -> void:
	for space in [TorusSpace.new(16, 8), TorusSpace.new(84, 96),
			TorusSpace.new(24, 16), TorusSpace.new(12, 8)]:
		var scale := TerrainChunk.uv_scale(space)
		for corner in range(-1, 6):
			var here := TerrainChunk.vertex_uv(scale, Vector2i(3, 2), corner)
			for step in [Vector2i(space.width, 0), Vector2i(0, space.height)]:
				var there := TerrainChunk.vertex_uv(scale,
					Vector2i(3, 2) + step, corner)
				var delta := there - here
				assert_almost_eq(delta.x, roundf(delta.x), 0.0001,
					"stepping %s on a %dx%d map shifts u by %.4f repeats — the "
						% [step, space.width, space.height, delta.x]
					+ "texture will not meet itself across the seam")
				assert_almost_eq(delta.y, roundf(delta.y), 0.0001,
					"stepping %s on a %dx%d map shifts v by %.4f repeats"
						% [step, space.width, space.height, delta.y])


## The scale must also be doing something: a repeat count of one across the
## whole map would satisfy the periodicity test above and stretch a single tile
## over 8,000 cells.
func test_the_texture_repeats_at_roughly_the_intended_size() -> void:
	var space := TorusSpace.new(84, 96)
	var scale := TerrainChunk.uv_scale(space)
	var cells_per_repeat := 1.0 / (scale.x * float(space.width) / float(space.width))
	# One repeat spans `1 / scale.x` cells along q.
	cells_per_repeat = 1.0 / scale.x
	assert_between(cells_per_repeat, 1.5, 6.0,
		"one texture repeat covers %.1f cells, against a target of %.1f"
			% [cells_per_repeat, TerrainChunk.UV_CELLS_PER_TILE])


# --- which tile ----------------------------------------------------------


func _custom(mesh: ArrayMesh, which: int) -> PackedFloat32Array:
	var arrays := mesh.surface_get_arrays(0)
	var raw = arrays[which]
	if raw == null:
		return PackedFloat32Array()
	return raw as PackedFloat32Array


## Every vertex's weights sum to one. A shortfall does not mis-texture the
## ground, it DARKENS it — the detail is a multiplier, so weights summing to 0.8
## would scale the whole fragment down and read as a stain nobody could trace to
## a vertex attribute.
func test_every_vertex_asks_for_exactly_one_tile_worth_of_detail() -> void:
	var mesh := TerrainChunk.build_mesh(_space(), _terrain(), Vector2i(0, 0), CHUNK_SIZE)
	var weights := _custom(mesh, Mesh.ARRAY_CUSTOM1)
	var slots := _custom(mesh, Mesh.ARRAY_CUSTOM0)
	assert_gt(weights.size(), 0,
		"the mesh carries no CUSTOM1 channel; the shader would read zeroes and "
		+ "paint the map black")
	assert_eq(slots.size(), weights.size(), "one slot triple per weight triple")

	var vertices := weights.size() / 4
	for vertex in range(vertices):
		var total := 0.0
		for i in range(TerrainChunk.TILE_SLOTS):
			total += weights[vertex * 4 + i]
			var tile := slots[vertex * 4 + i]
			assert_eq(tile, floorf(tile), "a tile index must be a whole number")
			assert_between(tile, 0.0, float(TerrainGen.Biome.size() - 1),
				"tile index %f is outside the atlas" % tile)
		assert_almost_eq(total, 1.0, 0.0001,
			"vertex %d's tile weights sum to %.4f" % [vertex, total])


## The centre of a hex is one biome and nothing else, so it must ask for its own
## tile at full strength. If it did not, a cell's middle would be tinted by its
## neighbours and every biome would read as a blur of the map's average.
func test_a_cell_centre_asks_for_its_own_biome_alone() -> void:
	var space := _space()
	var terrain := _terrain()
	var fields := terrain.build_fields(space)
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK_SIZE, fields)
	var slots := _custom(mesh, Mesh.ARRAY_CUSTOM0)
	var weights := _custom(mesh, Mesh.ARRAY_CUSTOM1)

	var vertex := 0
	for dy in range(CHUNK_SIZE):
		for dx in range(CHUNK_SIZE):
			var biome := int(fields.biome[space.index(Vector2i(dx, dy))])
			assert_eq(int(slots[vertex * 4]), biome,
				"cell (%d,%d)'s first tile slot is not its own biome" % [dx, dy])
			assert_eq(weights[vertex * 4], 1.0,
				"cell (%d,%d)'s centre does not ask for its own tile outright"
					% [dx, dy])
			vertex += TerrainGen.SURFACE_STRIDE


## What a corner asks for, against what meets there. Checked on the SHIPPED map,
## and reported as a fraction rather than asserted per corner, because three
## slots cannot always hold a cell whose six neighbours span four biomes —
## `TerrainChunk.cell_tiles` says so in as many words, and this is the
## measurement that keeps that admission honest.
func test_a_corner_asks_for_the_biomes_that_actually_meet_there() -> void:
	var config := load("res://maps/default.tres") as MapConfig
	var space := config.to_space()
	var terrain := TerrainGen.new()
	var fields := terrain.build_fields(space)

	var corners := 0
	var truncated := 0
	for i in range(space.cell_count()):
		var tiling := TerrainChunk.cell_tiles(space, fields, i)
		var slots: PackedFloat32Array = tiling["tiles"]
		var weights: PackedFloat32Array = tiling["weights"]
		for k in range(6):
			corners += 1
			# What the vertex will actually blend, folded back to biomes.
			var asked := {}
			for slot in range(TerrainChunk.TILE_SLOTS):
				var w: float = weights[(1 + k) * TerrainChunk.TILE_SLOTS + slot]
				if w <= 0.0:
					continue
				var b := int(slots[slot])
				asked[b] = float(asked.get(b, 0.0)) + w
			# What is really there: each owner at the weight the WARP gave it
			# (D-096 amendment). Before the warp this was a third each; a test
			# still asserting thirds would report three quarters of the map's
			# corners as truncated and be measuring its own stale arithmetic.
			var truth := {}
			var trio := TerrainGen.corner_cells(space, i, k)
			var blend := fields.weights(i, k)
			for m in range(3):
				var b := int(fields.biome[trio[m]])
				truth[b] = float(truth.get(b, 0.0)) + blend[m]
			var same := asked.size() == truth.size()
			if same:
				for b in truth:
					if absf(float(asked.get(b, 0.0)) - float(truth[b])) > 0.0001:
						same = false
						break
			if not same:
				truncated += 1

	# Measured at 0.09% of corners (45 of 48,384) on the shipped map when this
	# was written. The bound is far above it, so only a change that pushed
	# truncation up by more than twenty-fold trips it — and that WOULD be
	# visible, as texture detail disagreeing across a boundary.
	assert_lt(truncated, corners / 50,
		"%d of %d corners (%.1f%%) cannot fit their biome mixture into three "
			% [truncated, corners, 100.0 * float(truncated) / float(corners)]
		+ "tile slots — the ground's detail will disagree across those edges")
	gut.p("corner tile truncation: %d of %d (%.2f%%)"
		% [truncated, corners, 100.0 * float(truncated) / float(corners)])


# --- the material and the atlas layout -----------------------------------


## `make_material` is ONE definition shared by the client, `bench-render` and
## `gen-model-preview`, because those three had drifted into copies once and a
## benchmark that renders a different material measures the wrong thing.
func test_the_ground_material_is_the_shader_when_the_atlas_is_built() -> void:
	var material := TerrainChunk.make_material()
	assert_not_null(material)
	if not TerrainChunk.has_atlas():
		assert_true(material is StandardMaterial3D,
			"with no generated atlas the ground must fall back to plain vertex "
			+ "colour, exactly as units fall back to primitives")
		return

	assert_true(material is ShaderMaterial,
		"the atlas is built but the ground is not using the terrain shader — "
		+ "continuous UVs over an eight-tile atlas would sample the wrong tiles")
	var shader_material := material as ShaderMaterial
	assert_not_null(shader_material.shader, "the shader failed to load")
	assert_not_null(shader_material.get_shader_parameter("atlas"),
		"the shader has no atlas bound, so the ground would be untextured")
	assert_eq(shader_material.get_shader_parameter("atlas_grid"),
		Vector2(float(TerrainChunk.ATLAS_COLUMNS), float(TerrainChunk.ATLAS_ROWS)),
		"the shader is told a different atlas layout than the mesher uses")


func test_atlas_layout_matches_the_generator() -> void:
	var manifest_path := "res://generated/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		pass_test("generated/ not built")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var terrain: Dictionary = (parsed as Dictionary).get("terrain", {})
	if terrain.is_empty():
		pass_test("no terrain atlas in the manifest")
		return

	assert_eq(int(terrain.get("columns", -1)), TerrainChunk.ATLAS_COLUMNS,
		"atlas column count disagrees between art/terrain/atlas.py and "
		+ "TerrainChunk — cells would sample the wrong tile")
	assert_eq(int(terrain.get("rows", -1)), TerrainChunk.ATLAS_ROWS,
		"atlas row count disagrees between the generator and TerrainChunk")

	# One tile per biome, and the enum is what indexes them.
	var biomes: Array = terrain.get("biomes", [])
	assert_eq(biomes.size(), TerrainGen.Biome.size(),
		"the atlas has %d tiles for %d biomes; a biome with no tile samples "
			% [biomes.size(), TerrainGen.Biome.size()]
		+ "whatever is next to it")


# --- the geometry contract is unchanged ---------------------------------


## Adding vertex attributes must not change the mesh's shape. D-017's existing
## test asserts the counts; this asserts every per-vertex array is exactly as
## long as the vertex array, which is how a partially-filled attribute shows up.
func test_adding_attributes_did_not_change_the_mesh_topology() -> void:
	var mesh := TerrainChunk.build_mesh(_space(), _terrain(), Vector2i(0, 0), CHUNK_SIZE)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(uvs.size(), vertices.size(), "one UV per vertex")
	assert_eq(colors.size(), vertices.size(),
		"vertex colour still decides the biome's colour (D-066) — the atlas "
		+ "only modulates it")
	assert_eq(_custom(mesh, Mesh.ARRAY_CUSTOM0).size(), vertices.size() * 4,
		"one four-float tile slot entry per vertex")
	assert_eq(_custom(mesh, Mesh.ARRAY_CUSTOM1).size(), vertices.size() * 4,
		"one four-float weight entry per vertex")
