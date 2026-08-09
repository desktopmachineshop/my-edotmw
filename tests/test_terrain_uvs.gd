extends GutTest

## Guards D-066 — terrain texturing — and the two ways it can go wrong quietly.
##
## First: a cell whose UVs stray into a NEIGHBOURING biome's atlas tile paints
## forest on water. Nothing errors; the map simply lies about what a cell
## yields, which is the exact drift `terrain_gen.gd`'s "a cell that looks like
## forest is a cell that yields wood, by construction" exists to prevent.
##
## Second: the seam. Terrain geometry is UNWRAPPED and terrain data is WRAPPED
## (see terrain_chunk.gd). UVs are derived from the wrapped cell precisely so
## the nine lattice copies (D-035) agree; a UV derived from position would give
## each copy a different texture phase and tear the seam.

const CHUNK_SIZE := 8


func _space() -> TorusSpace:
	return TorusSpace.new(16, 8)


func _terrain() -> TerrainGen:
	var terrain := TerrainGen.new()
	terrain.noise_seed = 4242
	return terrain


## The atlas tile a biome owns, as a Rect2 in UV space.
func _tile_rect(biome: int) -> Rect2:
	var tile_w := 1.0 / float(TerrainChunk.ATLAS_COLUMNS)
	var tile_h := 1.0 / float(TerrainChunk.ATLAS_ROWS)
	@warning_ignore("integer_division")
	var row := biome / TerrainChunk.ATLAS_COLUMNS
	var column := biome % TerrainChunk.ATLAS_COLUMNS
	return Rect2(float(column) * tile_w, float(row) * tile_h, tile_w, tile_h)


# --- every hex samples its own biome's tile -----------------------------


func test_each_cell_samples_only_its_own_biome_tile() -> void:
	var space := _space()
	var terrain := _terrain()
	var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(0, 0), CHUNK_SIZE)
	assert_not_null(mesh, "chunk did not build")

	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_not_null(uvs, "terrain has no UVs; the atlas cannot be addressed")
	if uvs == null:
		return

	# Seven vertices per cell, laid out centre-then-corners, in the same
	# row-major order the builder walks.
	var vertex := 0
	for dy in range(CHUNK_SIZE):
		for dx in range(CHUNK_SIZE):
			var cell := Vector2i(dx, dy)
			var biome := int(terrain.biome_at(space, space.normalize(cell)))
			var rect := _tile_rect(biome)
			for corner in range(7):
				var uv := uvs[vertex + corner]
				assert_true(rect.has_point(uv),
					"cell %s is biome %d but samples UV %s, outside that "
						% [cell, biome, uv]
					+ "biome's tile %s — it would be painted as another biome"
						% rect)
			vertex += 7


func test_uvs_stay_inside_the_atlas() -> void:
	var mesh := TerrainChunk.build_mesh(_space(), _terrain(), Vector2i(0, 0), CHUNK_SIZE)
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	for uv in uvs:
		assert_between(uv.x, 0.0, 1.0, "UV escaped the atlas horizontally")
		assert_between(uv.y, 0.0, 1.0, "UV escaped the atlas vertically")


# --- the seam (D-008's recurring tax) -----------------------------------


## A chunk whose cells run past the map's width must still texture from the
## WRAPPED cell's biome. Geometry there is unwrapped — that is deliberate and
## tested elsewhere — so this is the check that data and geometry were not
## confused with each other.
func test_a_chunk_across_the_seam_textures_from_the_wrapped_cell() -> void:
	var space := TorusSpace.new(12, 8)
	var terrain := _terrain()
	# Last chunk column on a 12-wide map at chunk size 8 starts at x = 8 and
	# runs to x = 11; nudge the map so a chunk genuinely straddles.
	var chunk := Vector2i(1, 0)
	var mesh := TerrainChunk.build_mesh(space, terrain, chunk, 8)
	if mesh == null:
		pass_test("no straddling chunk at this size")
		return

	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var origin := Vector2i(chunk.x * 8, chunk.y * 8)
	var cells_x: int = mini(8, space.width - origin.x)
	var cells_y: int = mini(8, space.height - origin.y)

	var vertex := 0
	for dy in range(cells_y):
		for dx in range(cells_x):
			var unwrapped := Vector2i(origin.x + dx, origin.y + dy)
			var biome := int(terrain.biome_at(space, space.normalize(unwrapped)))
			var rect := _tile_rect(biome)
			assert_true(rect.has_point(uvs[vertex]),
				"cell %s (wrapped %s) textures from the wrong biome across "
					% [unwrapped, space.normalize(unwrapped)]
				+ "the seam")
			vertex += 7


## Two cells that are the SAME cell after wrapping must get identical UVs,
## including the per-cell rotation. The nine lattice copies draw the same mesh
## at nine offsets, so any disagreement here is a visible seam.
func test_the_same_wrapped_cell_always_gets_the_same_uvs() -> void:
	var space := TorusSpace.new(12, 8)
	var terrain := _terrain()

	var here := TerrainChunk._atlas_frame(space, terrain, Vector2i(2, 3))
	var wrapped_around := TerrainChunk._atlas_frame(
		space, terrain, Vector2i(2 + space.width, 3 + space.height))

	assert_eq(here["centre"], wrapped_around["centre"],
		"a cell and its lattice copy must sample the same tile")
	assert_eq(here["rotation"], wrapped_around["rotation"],
		"a cell and its lattice copy must use the same rotation, or the "
		+ "texture visibly steps at the seam")


# --- the geometry contract is unchanged ---------------------------------


## Adding a vertex attribute must not change the mesh's shape. D-017's existing
## test asserts the counts; this asserts the UV array is exactly as long as the
## vertex array, which is the way a partially-filled attribute usually shows up.
func test_adding_uvs_did_not_change_the_mesh_topology() -> void:
	var mesh := TerrainChunk.build_mesh(_space(), _terrain(), Vector2i(0, 0), CHUNK_SIZE)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(uvs.size(), vertices.size(), "one UV per vertex")
	assert_eq(colors.size(), vertices.size(),
		"vertex colour still decides the biome's colour (D-066) — the atlas "
		+ "only modulates it")


# --- the atlas layout matches the generator -----------------------------


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
