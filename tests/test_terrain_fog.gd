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
##
## Asserted against `Vision._range_in_cells` ITSELF, not against a copy of its
## arithmetic written out here. The first version of this test did the latter:
## it read as a cross-check and was really one hand-copy agreeing with another,
## so a change to `Vision` would leave it green while the two diverged — the
## exact shape of the M1 defect the audit block at the end of D-022 records,
## where a test supplied both sides the same input and could not see the live
## system feeding them different ones.
func test_the_lit_disk_is_the_size_of_the_vision_disk() -> void:
	var space := _space()
	var ranges: Array[float] = [0.0, 0.4, 1.0, 3.7, 12.0, 25.0]
	# The shipped numbers as well as the interesting ones, since those are what
	# a player actually sees the edge of.
	for def in UnitRoster.load_all():
		if not ranges.has(def.vision_range):
			ranges.append(def.vision_range)

	for world_range in ranges:
		var vision_cells := Vision._range_in_cells(space, world_range)
		if vision_cells <= 0.0:
			# `Vision._stamp` returns early here and stamps NOTHING — not even
			# the origin cell. A radius of 0 would be a different answer: it is
			# a one-cell disk. Hence the negative sentinel.
			assert_lt(TerrainFog.radius_in_cells(space, world_range), 0,
				"%f world units sees nothing on the server, so it must light "
					% world_range + "nothing on the client either")
		else:
			assert_eq(TerrainFog.radius_in_cells(space, world_range),
				floori(vision_cells),
				"%f world units in cells" % world_range)


## The sentinel, at the level that actually matters: a seeing thing with no
## range lights no ground at all, matching `Vision._stamp`'s early return.
func test_a_range_that_sees_nothing_lights_nothing() -> void:
	var space := _space()
	var fog := TerrainFog.new(space)
	fog.reveal(Vector2i(4, 4), TerrainFog.radius_in_cells(space, 0.0))
	assert_eq(fog.level_at(space.index(Vector2i(4, 4))), TerrainFog.UNEXPLORED)

	# ...while any positive range under one hex still lights the cell it stands
	# on, because that is what `Vision` covers.
	fog.reveal(Vector2i(4, 4), TerrainFog.radius_in_cells(space, 0.4))
	assert_eq(fog.level_at(space.index(Vector2i(4, 4))), TerrainFog.VISIBLE)


# --- stamped from what this client knows ---------------------------------


## A ClientState holding one building, owned by `owner`, on a two-seat lobby
## whose teams are `my_team` and `their_team`.
##
## Built by hand rather than driven through the wire because the question here
## is which entities the fog asks about, not how they arrived.
func _state_with_allied_building(my_team: int, their_team: int) -> ClientState:
	var state := ClientState.new()
	state.space = _space()
	state.player = 1
	state.lobby = {"seats": [
		{"player": 1, "team": my_team},
		{"player": 2, "team": their_team},
	]}
	state.buildings[7] = {
		"def_id": "town_centre",
		"owner": 2,
		"cell": state.space.index(ALLY_BASE),
		"progress": 1.0,
		"destroyed": false,
	}
	return state


const ALLY_BASE := Vector2i(9, 5)


## The server stamps buildings into the TEAM's shared coverage
## (`Vision._group_of`), so an ally's town hall lights ground for everyone on
## that side. A client that filtered buildings by OWNER drew its ally's base as
## unexplored black while enemy squads standing in it rendered fully lit — fog
## strictly narrower than the vision being gated on, which is the failure the
## squad loop's own comment warns about, one entity type down.
func test_an_allied_building_lights_ground_for_its_ally() -> void:
	var state := _state_with_allied_building(3, 3)
	var fog := TerrainFog.new(state.space)
	fog.rebuild(state, 0.0)

	var def := BuildingSim.def_by_id(&"town_centre")
	assert_not_null(def, "town_centre is the def this test leans on")
	assert_gt(def.vision_range, 0.0, "a town centre that sees nothing makes this vacuous")

	assert_eq(fog.level_at(state.space.index(ALLY_BASE)), TerrainFog.VISIBLE,
		"an ally's town hall must light the ground it stands on")
	assert_true(fog.is_explored(state.space.index(ALLY_BASE + Vector2i(1, 0))),
		"and the ground around it, out to its vision range")


## The other half of the same rule, and the reason it cannot be "reveal around
## every building we know about": we are TOLD about enemy buildings we have
## seen (D-030 keeps them once explored), and they must not keep lighting
## ground for the player who scouted them once.
func test_an_enemy_building_lights_nothing() -> void:
	# Same seats, opposing teams.
	var state := _state_with_allied_building(3, 4)
	var fog := TerrainFog.new(state.space)
	fog.rebuild(state, 0.0)
	assert_eq(fog.level_at(state.space.index(ALLY_BASE)), TerrainFog.UNEXPLORED,
		"an enemy's town hall is not our eyes")


## Team 0 is FREE-FOR-ALL, not "everybody's team" — `ClientState.are_allied`
## says so and this is where getting it wrong would show: in an FFA every
## player's base would light the map for every other player.
func test_two_players_on_team_zero_are_not_allies() -> void:
	var state := _state_with_allied_building(0, 0)
	var fog := TerrainFog.new(state.space)
	fog.rebuild(state, 0.0)
	assert_eq(fog.level_at(state.space.index(ALLY_BASE)), TerrainFog.UNEXPLORED)


func test_a_destroyed_building_stops_seeing() -> void:
	var state := _state_with_allied_building(3, 3)
	state.buildings[7]["destroyed"] = true
	var fog := TerrainFog.new(state.space)
	fog.rebuild(state, 0.0)
	assert_eq(fog.level_at(state.space.index(ALLY_BASE)), TerrainFog.UNEXPLORED,
		"rubble sees nothing")


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
## `bake` re-shades only the cells whose level changed, plus one ring — which
## is an optimisation, and therefore a thing that can be silently wrong.
##
## The specific way it goes wrong is a one-cell halo of stale fog trailing a
## moving army: correct everywhere the eye is not, and invisible to every other
## test in this file. So it is checked the only way that means anything —
## against a fog that has been baked from scratch after the same reveals.
func test_an_incremental_bake_matches_one_computed_from_scratch() -> void:
	var space := _space()
	var walked := TerrainFog.new(space)
	var reference: TerrainFog = null

	# March a pair of seers across the map, re-baking each step.
	for step in range(6):
		walked.forget_visible()
		walked.reveal(Vector2i(3 + step, 4), 2)
		walked.reveal(Vector2i(12, 2 + step), 1)

		# A fresh field given the SAME history: it has explored everywhere the
		# walked one has, and its only bake is the full one.
		reference = TerrainFog.new(space)
		for past in range(step + 1):
			reference.forget_visible()
			reference.reveal(Vector2i(3 + past, 4), 2)
			reference.reveal(Vector2i(12, 2 + past), 1)
		var fresh := reference.bake()

		var incremental := walked.bake()
		for y in range(space.height):
			for x in range(space.width):
				assert_eq(incremental.get_pixel(x, y).r, fresh.get_pixel(x, y).r,
					"step %d, cell (%d,%d): the incremental bake left a stale "
						% [step, x, y] + "shade behind")


## Measured at BOTH ends of the map-size range, which is the point.
##
## An earlier version loaded `maps/default.tres` and nothing else, so it was
## structurally unable to see the thing worth worrying about: the Huge preset is
## 32,592 cells against Standard's 8,064, and the passes this used to do were
## per-cell, on the main thread, at 4 Hz, on a frame M5 and M7 both measured as
## CPU-bound. A generous bound on the small map would have stayed green through
## a four-times regression on the big one.
##
## The claim is stronger than "fast enough": a steady-state refresh costs what
## the player is LOOKING at, so the two map sizes should do the SAME AMOUNT OF
## WORK. That is asserted on `cells_shaded_last_bake` — the work itself — and not
## on the clock.
##
## It was asserted on the clock first, as a ratio of milliseconds, and that gate
## went red on a loaded host with nothing wrong: the same code measured 2.73 vs
## 2.61 ms quiet and 7.81 vs 20.61 ms while eleven branches were being built
## beside it. A tight timing gate on a shared machine gets muted rather than
## fixed — this file's own comment said so two commits before writing one. The
## milliseconds are still measured and REPORTED, because the number is worth
## knowing; they are simply not the assertion.
func test_a_fog_refresh_costs_the_army_not_the_map() -> void:
	var wanted := ["Standard", "Huge"]
	var presets := []
	for size in MapSettings.sizes():
		if wanted.has(String(size["name"])):
			presets.append(size)
	assert_eq(presets.size(), wanted.size(),
		"MapSettings.sizes() no longer offers %s — this test names the extremes "
			% [wanted] + "on purpose, so re-point it rather than dropping one")

	var costs := {}
	var shaded := {}
	for preset in presets:
		var space := TorusSpace.new(int(preset["width"]), int(preset["height"]))
		var fog := TerrainFog.new(space)

		# A plausible mid-game player: a dozen seeing things, walking.
		#
		# At the SAME coordinates on both maps, and well inside the smaller one,
		# which is the whole basis of the comparison below. Deriving the
		# positions from `space.width` instead — as the first version did —
		# spread the seers further apart on the bigger map, so their vision
		# disks overlapped less and genuinely covered more distinct cells: 1,092
		# against 1,176. That is a difference in the ARMY, not in the algorithm,
		# and it made a correct implementation look like a scaling one.
		var walk := func(step: int) -> void:
			fog.forget_visible()
			for i in range(12):
				fog.reveal(Vector2i((i * 7 + step) % 60, (i * 5 + step) % 60), 7)

		# The FIRST bake shades the whole map, necessarily — there is no
		# previous state to diff against. It happens once, at match start,
		# beside a terrain mesh build that costs hundreds of milliseconds, so
		# it is reported rather than budgeted. It is emphatically not the
		# steady state, and folding it into the average below would hide the
		# very scaling this test exists to measure.
		var first_started := Time.get_ticks_usec()
		walk.call(0)
		fog.bake()
		var first_bake := float(Time.get_ticks_usec() - first_started) / 1000.0
		assert_eq(fog.cells_shaded_last_bake, space.cell_count(),
			"the first bake has nothing to diff against and must shade the map")

		var refreshes := 8
		var started := Time.get_ticks_usec()
		for step in range(1, refreshes + 1):
			walk.call(step)
			fog.bake()
		var per_refresh := float(Time.get_ticks_usec() - started) / (1000.0 * float(refreshes))

		costs[space.cell_count()] = per_refresh
		shaded[space.cell_count()] = fog.cells_shaded_last_bake
		gut.p("fog refresh: %d cells re-shaded, %.2f ms, on a %d-cell map "
			% [fog.cells_shaded_last_bake, per_refresh, space.cell_count()]
			+ "(12 seers, radius 7, walking); first bake %.2f ms" % first_bake)

	var cells: Array = costs.keys()
	cells.sort()
	var small_map: int = cells[0]
	var large_map: int = cells[cells.size() - 1]

	# THE assertion: identical armies looking at identical amounts of ground do
	# identical work, whatever the map around them measures.
	assert_eq(int(shaded[large_map]), int(shaded[small_map]),
		"the same twelve seers re-shaded %d cells on a %d-cell map and %d on a "
			% [int(shaded[small_map]), small_map, int(shaded[large_map])]
			+ "%d-cell one — a refresh is supposed to cost what is being looked "
			% large_map + "at, not what the map contains")
	assert_lt(int(shaded[large_map]), large_map / 4,
		"a steady-state refresh touched %d of %d cells, which is not a diff any more"
			% [int(shaded[large_map]), large_map])
	# Wall-clock kept only as a sanity floor, orders of magnitude away from the
	# measurements above, so host load cannot turn it red on its own.
	assert_lt(float(costs[large_map]), 60.0,
		"a fog refresh on the largest shipped map costs %.2f ms, and four of "
		% float(costs[large_map]) + "those a second is not a frame cost any more")


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
