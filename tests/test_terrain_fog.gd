extends GutTest

## Guards D-106: the GROUND has fog of war, in three states, and it reaches
## the renderer.
##
## The defect these were written against (#58) was not a wrong fog field. It
## was a right one that nothing drew: `client.gd`'s explored set was correct,
## documented as "the map starts black and is revealed by line of sight", and
## read at exactly two sites, both inside the minimap. The 3D world drew the
## whole map lit from the first frame, and no number anywhere could see it —
## `test-client` asserts distinct colour counts, and a fully lit map passes
## that as readily as a fogged one.
##
## So these tests come in two halves, and the second half is the one that
## matters:
##
## 1. **The field is right** — three states, persistence, wrap, and a lit disk
##    the same size as the vision disk the server gates on.
## 2. **The field is CONNECTED** — the mesh carries the coordinate, the shader
##    declares the input, and something outside `terrain_chunk.gd` actually
##    binds it. That last one is this project's "grep for uncalled public
##    members" rule written as a test, for the one defect family the rest of
##    the suite is blind to by construction: nothing fails, the game simply
##    lacks a rule.


func _space() -> TorusSpace:
	return TorusSpace.new(16, 8)


func _terrain() -> TerrainGen:
	var terrain := TerrainGen.new()
	terrain.noise_seed = 4242
	return terrain


const CHUNK_SIZE := 8


# --- the field -----------------------------------------------------------


func test_a_map_nobody_has_walked_is_entirely_unknown() -> void:
	var space := _space()
	var fog := TerrainFog.new(space)
	for i in range(space.cell_count()):
		assert_eq(fog.level_at(i), TerrainFog.UNEXPLORED,
			"cell %d starts unexplored" % i)
		assert_false(fog.is_explored(i), "cell %d starts unexplored" % i)


func test_a_reveal_lights_its_disk_and_leaves_the_rest_dark() -> void:
	var space := _space()
	var fog := TerrainFog.new(space)
	var centre := Vector2i(8, 4)
	fog.reveal(centre, 2)

	for offset in TorusSpace.disk_offsets(2):
		assert_eq(fog.level_at(space.index(centre + offset)), TerrainFog.VISIBLE,
			"%s is inside the disk" % [centre + offset])

	# One ring out. Deliberately checked against `distance`, not against the
	# same `disk_offsets` table the reveal walked — a table that quietly grew
	# would otherwise agree with itself.
	var lit := 0
	for i in range(space.cell_count()):
		if fog.level_at(i) != TerrainFog.UNEXPLORED:
			lit += 1
			assert_lte(space.distance(centre, space.from_index(i)), 2,
				"cell %s lit but more than two cells away" % space.from_index(i))
	assert_eq(lit, TorusSpace.disk_offsets(2).size(), "exactly the disk is lit")


## Three states, which is the whole reason this is not a set of explored
## cells. Ground the player scouted and walked away from is REMEMBERED: drawn,
## but visibly not live. Two states would either black it back out — throwing
## away the map the player earned — or leave it lit, claiming knowledge they
## no longer have.
func test_ground_a_player_has_left_is_remembered_rather_than_lit_or_black() -> void:
	var space := _space()
	var fog := TerrainFog.new(space)
	var centre := Vector2i(3, 3)
	fog.reveal(centre, 1)
	fog.forget_visible()

	var here := space.index(centre)
	assert_eq(fog.level_at(here), TerrainFog.EXPLORED)
	assert_true(fog.is_explored(here), "explored ground stays explored — terrain does not move")
	assert_gt(TerrainFog.SHADES[TerrainFog.EXPLORED], TerrainFog.SHADES[TerrainFog.UNEXPLORED],
		"remembered ground is drawn")
	assert_lt(TerrainFog.SHADES[TerrainFog.EXPLORED], TerrainFog.SHADES[TerrainFog.VISIBLE],
		"remembered ground is visibly not live ground")


func test_walking_back_over_remembered_ground_makes_it_live_again() -> void:
	var space := _space()
	var fog := TerrainFog.new(space)
	fog.reveal(Vector2i(3, 3), 1)
	fog.forget_visible()
	fog.reveal(Vector2i(3, 3), 1)
	assert_eq(fog.level_at(space.index(Vector2i(3, 3))), TerrainFog.VISIBLE)


## The torus tax (D-008), which the fog pays like everything else: a squad
## standing at the seam sees across it.
func test_a_reveal_at_the_seam_lights_both_sides() -> void:
	var space := _space()
	var fog := TerrainFog.new(space)
	fog.reveal(Vector2i(0, 0), 1)
	assert_eq(fog.level_at(space.index(Vector2i(space.width - 1, 0))), TerrainFog.VISIBLE,
		"the cell west of x=0 is the one at the far edge")


## The client draws its own lit disk and the server gates what it SENDS with
## `Vision`. The two have to agree about how far a `vision_range` in world
## units reaches, or enemies arrive on ground the player is being shown as
## dark — which reads as an entity bug and is a terrain one.
func test_the_lit_disk_is_the_size_of_the_vision_disk() -> void:
	var space := _space()
	var hex_width := space.hex_size * TorusSpace.SQRT_3
	for world_range in [0.0, 0.4, 1.0, 3.7, 12.0, 25.0]:
		assert_eq(TerrainFog.radius_in_cells(space, world_range),
			floori(world_range / hex_width),
			"%f world units in cells" % world_range)


# --- what the renderer is handed -----------------------------------------


## The baked image is addressed by cell, in `TorusSpace.index` order, because
## that is the layout the mesh's fog UVs assume. Getting it transposed would
## fog the map with a rotated copy of itself — a picture that looks like fog
## and is a lie about where the player has been.
func test_the_baked_field_is_laid_out_like_the_cell_index() -> void:
	var space := _space()
	var fog := TerrainFog.new(space)
	var cell := Vector2i(11, 2)
	fog.reveal(cell, 0)

	var image := fog.bake()
	assert_eq(image.get_width(), space.width)
	assert_eq(image.get_height(), space.height)
	# The brightest texel is the one that was revealed. Compared as a maximum
	# rather than as an exact value because the bake blurs (see below).
	var best := Vector2i(-1, -1)
	var best_value := -1.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var value := image.get_pixel(x, y).r
			if value > best_value:
				best_value = value
				best = Vector2i(x, y)
	assert_eq(best, cell, "the lit texel is at the revealed cell's own coordinate")


func test_an_unexplored_map_bakes_to_black() -> void:
	var space := _space()
	var image := TerrainFog.new(space).bake()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			assert_eq(image.get_pixel(x, y).r, 0.0,
				"unexplored ground is black, not merely dark — D-086's rig has "
				+ "sky ambient, so only zero albedo is actually unlit")


## Fully inside a scouted region the ground is drawn at full brightness: the
## blur that softens the EDGE must not dim the middle.
func test_ground_well_inside_a_scouted_region_is_drawn_fully() -> void:
	var space := _space()
	var fog := TerrainFog.new(space)
	fog.reveal(Vector2i(8, 4), 4)
	var image := fog.bake()
	assert_eq(image.get_pixel(8, 4).r, 1.0)


## D-096 measured what a one-cell transition at high contrast looks like: the
## contour follows the hex edges and the boundary reads as scalloped. Black
## against lit is the strongest contrast the map can produce, so the field is
## blurred before it is uploaded — and this asserts the resulting RAMP, which
## is the property, rather than the blur weights, which are a tuning knob.
func test_the_edge_of_a_scouted_region_fades_rather_than_stepping() -> void:
	var space := TorusSpace.new(32, 16)
	var fog := TerrainFog.new(space)
	var centre := Vector2i(16, 8)
	fog.reveal(centre, 4)
	var image := fog.bake()

	# Straight out along +q from the centre: full inside, zero well outside,
	# and strictly decreasing across the boundary rather than stepping once.
	var ramp: Array[float] = []
	for d in range(3, 8):
		ramp.append(image.get_pixel(centre.x + d, centre.y).r)
	assert_eq(ramp[0], 1.0, "three cells out is still well inside")
	assert_eq(ramp[ramp.size() - 1], 0.0, "seven cells out is unexplored")
	var falling := 0
	for i in range(1, ramp.size()):
		assert_lte(ramp[i], ramp[i - 1], "the ramp never brightens outward")
		if ramp[i] < ramp[i - 1]:
			falling += 1
	assert_gte(falling, 3, "the edge fades over several cells rather than in one step")


## The whole field is restamped and re-baked on the client's MAIN THREAD, four
## times a second, so its cost is a frame-time question rather than a startup
## one. Measured on the shipped map, because that is the one a player pays for.
##
## The bound is deliberately loose — this runs in a container beside whatever
## else the host is doing, and a tight timing gate on a shared machine gets
## muted rather than fixed (the same reasoning `test-client` gives for
## reporting reveals instead of gating them). What it is really guarding is the
## shape: a blur that reached for `distance()` per cell, or a neighbour lookup
## that walked `from_index`/`index` per query instead of the table built once,
## would land orders of magnitude above this, not a little above it.
func test_a_fog_refresh_of_the_shipped_map_is_not_accidentally_expensive() -> void:
	var config := load("res://maps/default.tres") as MapConfig
	assert_not_null(config, "maps/default.tres did not load")
	var space := config.to_space()
	var fog := TerrainFog.new(space)

	# A plausible mid-game player: a dozen seeing things scattered over the map.
	var seers: Array[Vector2i] = []
	for i in range(12):
		seers.append(Vector2i((i * 17) % space.width, (i * 11) % space.height))

	var refreshes := 4
	var started := Time.get_ticks_usec()
	for _pass in range(refreshes):
		fog.forget_visible()
		for seer in seers:
			fog.reveal(seer, 7)
		fog.bake()
	var per_refresh := float(Time.get_ticks_usec() - started) / (1000.0 * float(refreshes))

	gut.p("fog refresh: %.2f ms for %d cells (%d seers, radius 7)"
		% [per_refresh, space.cell_count(), seers.size()])
	assert_lt(per_refresh, 60.0,
		"a fog refresh costs %.2f ms on %d cells — four of those a second is "
		% [per_refresh, space.cell_count()]
		+ "not a frame cost any more, so something has gone quadratic")


# --- and is it actually connected ----------------------------------------


## The mesh has to carry a per-vertex coordinate into the fog field, and it has
## to be derived from the CELL (D-035) — the terrain is drawn nine times across
## the seams from the same meshes, so a world-position-derived coordinate would
## fog each copy differently.
func test_the_terrain_mesh_carries_a_fog_coordinate_per_vertex() -> void:
	var space := _space()
	var mesh := TerrainChunk.build_mesh(space, _terrain(), Vector2i(0, 0), CHUNK_SIZE)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var fog_uvs := _fog_uvs_of(arrays)

	assert_eq(fog_uvs.size(), vertices.size(),
		"every terrain vertex knows where to read the fog")

	# Each cell's CENTRE vertex must land on its own texel, exactly — that is
	# what makes a cell entirely inside a vision disk take that cell's own
	# value rather than a blend of its neighbours'.
	for cell_y in range(CHUNK_SIZE):
		for cell_x in range(CHUNK_SIZE):
			var cell := Vector2i(cell_x, cell_y)
			var uv := TerrainChunk.fog_uv(space, cell, -1)
			assert_eq(floori(uv.x * float(space.width)), cell.x, "%s reads its own column" % cell)
			assert_eq(floori(uv.y * float(space.height)), cell.y, "%s reads its own row" % cell)


## The cliff faces (D-097) are a second surface of the same mesh, wearing the
## same material — so they sample the same fog and need the same channel. A
## missing one leaves rock walls fully lit in unexplored country, which is
## precisely the bug this file exists for, one surface down.
func test_cliff_faces_carry_the_fog_coordinate_too() -> void:
	# The shipped map, because cliffs are rare on it by nature (D-097 counts 363
	# faces on 8,064 cells) and a small synthetic map may contain none at all —
	# which would leave this passing while asserting nothing.
	var config := load("res://maps/default.tres") as MapConfig
	assert_not_null(config, "maps/default.tres did not load")
	var space := config.to_space()
	var terrain := TerrainGen.new()
	var fields := terrain.build_fields(space)
	var grid := TerrainChunk.chunk_grid(space, 16)

	var checked := 0
	for cy in range(grid.y):
		for cx in range(grid.x):
			var mesh := TerrainChunk.build_mesh(space, terrain, Vector2i(cx, cy), 16, fields)
			if mesh == null or mesh.get_surface_count() <= TerrainChunk.SKIRT_SURFACE:
				continue
			var arrays := mesh.surface_get_arrays(TerrainChunk.SKIRT_SURFACE)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var fog_uvs := _fog_uvs_of(arrays)
			assert_gt(vertices.size(), 0)
			assert_eq(fog_uvs.size(), vertices.size(),
				"chunk (%d,%d)'s rock faces must read the fog like the ground does" % [cx, cy])
			checked += 1
			if checked >= 2:
				return
	assert_gt(checked, 0, "the shipped map drew no cliffs at all — see D-097")


func test_the_terrain_shader_declares_the_fog_input() -> void:
	var handle := FileAccess.open(TerrainChunk.SHADER_PATH, FileAccess.READ)
	assert_not_null(handle, "the terrain shader is where terrain_chunk.gd says it is")
	var text := handle.get_as_text()
	handle.close()

	var declaration := RegEx.new()
	declaration.compile("uniform\\s+sampler2D\\s+%s\\s*:" % TerrainFog.SHADER_PARAM)
	assert_not_null(declaration.search(text),
		"terrain.gdshader must declare the uniform TerrainChunk.set_fog binds")
	assert_true(text.contains("texture(%s, UV2)" % TerrainFog.SHADER_PARAM),
		"the ground has to actually SAMPLE the fog, at the coordinate the mesh carries")


func test_binding_fog_puts_it_on_the_material() -> void:
	var material := TerrainChunk.make_material()
	if not (material is ShaderMaterial):
		# No generated/ atlas in this checkout: make_material falls back to
		# plain vertex colour, which has no fog and is not supposed to.
		return
	var texture := ImageTexture.create_from_image(TerrainFog.new(_space()).bake())
	TerrainChunk.set_fog(material, texture)
	assert_eq((material as ShaderMaterial).get_shader_parameter(TerrainFog.SHADER_PARAM),
		texture)


## The test that would have caught #58, and the only one here that could have.
##
## Every other check in this file can pass while the ground is drawn fully
## lit, because a mechanism with no caller fails nothing. `BuildingSim.damage`
## went two milestones unwired (D-055), `UnitDef.cost` and `BuildingDef.cost`
## before it, three `CivDef` knobs after — and the client's explored set is the
## same shape: fully written, correct, and read by nothing that draws the
## world. So this asserts the CALLER exists.
func test_something_outside_terrain_chunk_actually_binds_the_fog() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10, "Found almost no scripts — the walk is broken, not the code clean")

	var callers: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str == "res://terrain_chunk.gd" or path_str.begins_with("res://tests/"):
			continue
		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		if text.contains("TerrainChunk.set_fog("):
			callers.append(path_str)

	assert_true(callers.has("res://client.gd"),
		"client.gd must hand its fog field to the terrain material — a fog set "
		+ "nothing draws is exactly the defect D-106 closes")


## A surface's fog channel, reported as MISSING rather than as an engine error.
## A mesh built without it hands back a null here, and letting that convert
## itself into a typed array turns "the ground cannot read the fog" into an
## unrelated-looking cast failure.
func _fog_uvs_of(arrays: Array) -> PackedVector2Array:
	var channel = arrays[Mesh.ARRAY_TEX_UV2]
	assert_true(channel is PackedVector2Array,
		"the terrain mesh carries no ARRAY_TEX_UV2 at all — nothing tells a "
		+ "fragment which cell's fog to read")
	if channel is PackedVector2Array:
		return channel
	return PackedVector2Array()


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))
