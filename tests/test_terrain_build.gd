extends GutTest

## Guards D-20260818-terrain-builds-a-slice-at-a-time: the ground is built in
## budgeted slices behind a loading bar, not in one blocking pass.
##
## The defect (#106) was a five-second frozen window at the start of every
## match — found by a human closing it and asking whether the server was down,
## because a frozen window is indistinguishable from a dead one. Every number
## was healthy: the server reported 0 dropped ticks and a 3.1 ms worst tick
## throughout.
##
## Three things are asserted here, and they fail in different ways:
##
## 1. **The slicing is arithmetic-neutral.** `TerrainGen.build_fields` was cut
##    into `fields_begin` + `fields_step` so it could be resumed, and a map that
##    came out even slightly different would move every coastline in the game.
##    So the sliced build is compared to the whole-map one BYTE FOR BYTE rather
##    than to a tolerance — the same standard `corner_cells`' sorting is held to.
## 2. **The slices are real.** A budget that quietly runs to completion is the
##    freeze with extra steps, and it would pass every other check in this file.
##    Asserted as WORK — cells advanced per slice — never as milliseconds: this
##    project has already shipped one timing gate that went red on a loaded host
##    with nothing wrong (`docs/status/ground-fog.md`).
## 3. **Something SHOWS it.** A progress fraction nothing draws is #58's defect
##    family exactly: correct, documented, and read by nobody. So the last tests
##    drive the real `client.gd` and assert the bar is on screen while the
##    ground is built and gone afterwards.


const CHUNK := 16


## Big enough that every phase needs several slices — a map that finishes in one
## cannot show the difference between slicing and not.
func _space() -> TorusSpace:
	return TorusSpace.new(48, 32)


func _terrain() -> TerrainGen:
	var gen := TerrainGen.new()
	gen.noise_seed = 1337
	return gen


# --- 1. the slicing changes no arithmetic -----------------------------

func test_a_sliced_fields_build_is_byte_identical_to_the_whole_map_one() -> void:
	# `build_fields` is the whole-map case of the sliced path now, so this is
	# really "resuming changed nothing". It is checked exactly rather than
	# approximately because these arrays decide where the water is: a last-bit
	# difference at a threshold moves a coastline, and float addition is not
	# associative (see `TerrainGen.corner_cells` for the same argument).
	var space := _space()
	var gen := _terrain()
	var whole := gen.build_fields(space)

	var work := gen.fields_begin(space)
	while not gen.fields_step(work, 97):
		pass
	var sliced := work["fields"] as TerrainFields

	assert_eq(sliced.surface, whole.surface, "Heights must survive being resumed")
	assert_eq(sliced.colors, whole.colors, "Vertex colours must survive being resumed")
	assert_eq(sliced.biome, whole.biome, "Biomes must survive being resumed")
	assert_eq(sliced.passable, whole.passable, "Passability must survive being resumed")
	assert_eq(sliced.cliff_class, whole.cliff_class, "Cliff classes must survive being resumed")
	assert_eq(sliced.corner_weights, whole.corner_weights,
		"Corner weights must survive being resumed — the blend warp reads them")


func test_the_slice_boundary_does_not_move_with_the_budget() -> void:
	# A shared memo (`weight_done`/`weight_cache`) is written by whichever cell
	# reaches a corner first, so a different budget visits it in a different
	# order. If that order could change the answer, the map would depend on the
	# frame rate — which is the one way this refactor could have gone wrong
	# without a single test noticing.
	var space := _space()
	var gen := _terrain()
	var coarse := gen.fields_begin(space)
	while not gen.fields_step(coarse, 1000):
		pass
	var fine := gen.fields_begin(space)
	while not gen.fields_step(fine, 7):
		pass
	assert_eq((fine["fields"] as TerrainFields).surface,
		(coarse["fields"] as TerrainFields).surface,
		"The map must not depend on how the work was divided up")


# --- 2. the slices are real, and progress is kept ---------------------

func test_a_slice_does_no_more_work_than_it_was_given() -> void:
	var space := _space()
	var gen := _terrain()
	var work := gen.fields_begin(space)
	var budget := 64
	var previous := 0
	var slices := 0
	while not gen.fields_step(work, budget):
		slices += 1
		var done := int(work["cells_done"]) + int(work["corners_done"])
		assert_lte(done - previous, budget,
			"A slice that overruns its budget is the freeze with extra steps")
		assert_gt(done, previous, "Every slice must make progress or this never ends")
		previous = done
	assert_gt(slices, 4, "Setup: this map should take several slices")


func test_the_builder_yields_before_it_is_finished() -> void:
	# The check that goes red if `step()` is ever "fixed" to run to completion —
	# which is exactly what the code did before #106 and what every other
	# assertion here would still pass with.
	var build := TerrainBuild.new(_space(), _terrain(), CHUNK)
	assert_false(build.step(), "The first slice must not build the whole map")
	assert_false(build.is_complete(), "…nor claim to have")

	var slices := 1
	while not build.step():
		slices += 1
		assert_lt(slices, 10000, "The build must terminate")
	assert_gt(slices, 4,
		"A build that finishes in a slice or two is one blocking pass wearing a loop")


func test_the_fields_are_finished_before_a_single_chunk_is_meshed() -> void:
	# A corner reads the three cells that meet at it, so a chunk meshed against
	# half-built fields would be meshed against sea-level holes — and it would
	# look like a rendering bug rather than an ordering one.
	var build := TerrainBuild.new(_space(), _terrain(), CHUNK)
	while not build.fields_ready():
		assert_eq(build.chunks_done(), 0, "Nothing may be meshed before the fields exist")
		assert_null(build.fields, "…and the fields must not be readable until they are whole")
		build.step()
	assert_not_null(build.fields, "The fields should be there the moment they are ready")


func test_every_chunk_is_handed_over_exactly_once() -> void:
	var build := TerrainBuild.new(_space(), _terrain(), CHUNK)
	var taken := 0
	while not build.step():
		taken += build.take_meshes().size()
	taken += build.take_meshes().size()
	assert_eq(taken, build.chunk_total(),
		"Every chunk must reach the caller — a dropped one is a hole in the world")
	assert_eq(build.take_meshes().size(), 0,
		"A mesh handed over twice would be parented twice, in all nine copies")


func test_progress_runs_from_nothing_to_one_and_never_backwards() -> void:
	# A bar that jumps backwards, or reaches 100% and then sits there, is worse
	# than no bar: the whole point is telling a player the game is not hung.
	var build := TerrainBuild.new(_space(), _terrain(), CHUNK)
	var last := build.progress()
	assert_almost_eq(last, 0.0, 0.01, "A build that has done nothing is at zero")
	while not build.step():
		var now := build.progress()
		assert_gte(now, last, "Progress must not go backwards")
		assert_lte(now, 1.0, "Progress must not overshoot")
		last = now
	assert_almost_eq(build.progress(), 1.0, 0.001, "A finished build reads full")


# --- 3. the client waits for it, and shows a bar while it does --------
#
# `client.gd` needs no GPU and no window for any of this — it is node
# lifetime, which `tests/test_return_to_lobby.gd` established is testable
# (D-075's 2026-08-16 amendment). Instantiated, never added to the tree:
# `_ready()` opens a socket.


## The real `client.gd`, one match's worth of world already known to it, with
## its loading screen built the way `_ready()` builds it.
func _client_with_a_map() -> Node3D:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(
		1, 48, 32, PackedInt32Array([0, 1]), [], 40, 0))
	var settings := MapSettings.new()
	settings.width = 48
	settings.height = 32
	settings.seed = 7
	state.handle_packet(NetProtocol.encode_map_settings(settings.to_dict()))
	assert_true(state.has_map(), "Setup: the client should have the map settings (D-049)")

	var client: Node3D = autofree(load("res://client.gd").new())
	client._state = state
	client._build_loading_screen()
	return client


func test_a_match_does_not_start_until_the_ground_is_finished() -> void:
	var client := _client_with_a_map()
	var frames := 0
	while not client._advance_terrain():
		frames += 1
		assert_false(client._terrain_built,
			"A client that reports built ground mid-build would draw squads on nothing")
		assert_false(client._state.terrain_sampler.is_valid(),
			"The sampler must not be bound early: soldiers would derive at sea level")
		assert_lt(frames, 10000, "The build must terminate")

	assert_gt(frames, 4, "The build must be spread over frames, not done in one")
	assert_true(client._terrain_built, "The world is ready once the last chunk is in")
	assert_true(client._state.terrain_sampler.is_valid(),
		"Nothing stands on the ground without the sampler (D-006's fourth input)")
	assert_null(client._terrain_stream, "A finished build releases its buffers")


func test_the_ground_is_drawn_nine_times_when_the_build_finishes() -> void:
	# The torus tax (D-035), and the thing streaming could most easily have
	# broken: a chunk that arrives after the tiles are built must still reach
	# all nine copies, or the world ends at the seam again.
	var client := _client_with_a_map()
	while not client._advance_terrain():
		pass
	assert_eq(client._terrain_root.get_child_count(), 9,
		"The chunk set is drawn at every lattice offset (D-035)")
	var expected := 0
	for tile in client._terrain_root.get_children():
		expected = maxi(expected, tile.get_child_count())
	assert_gt(expected, 0, "Setup: the map should have meshed some chunks")
	for tile in client._terrain_root.get_children():
		assert_eq(tile.get_child_count(), expected,
			"Every lattice copy must hold every chunk — a short one is a hole at the seam")


func test_the_loading_bar_is_on_screen_while_the_ground_is_built() -> void:
	# The D-106 lesson as a test: a progress fraction nothing draws is the
	# defect family this project keeps rediscovering. `_update_loading_screen`
	# is the caller, and this is the only check that it exists at all.
	var client := _client_with_a_map()
	client._advance_terrain()
	client._update_loading_screen()
	assert_true(client._loading_layer.visible,
		"The player is looking at a frozen-looking window without this")
	var early: float = client._loading_bar_fill.anchor_right

	while not client._advance_terrain():
		client._update_loading_screen()
	var late: float = client._loading_bar_fill.anchor_right
	assert_gt(late, early, "The bar must actually move as the ground is built")

	client._update_loading_screen()
	assert_false(client._loading_layer.visible,
		"The bar must come off the screen when the match starts")


func test_the_bar_never_leaves_its_own_track() -> void:
	# Anchors, not pixels — so the one thing that can go wrong is a fill that
	# runs past the back of the bar (or starts left of it) at some progress.
	var client := _client_with_a_map()
	while not client._advance_terrain():
		client._update_loading_screen()
		var right: float = client._loading_bar_fill.anchor_right
		assert_gte(right, client.LOADING_BAR_LEFT, "The fill must start at the left end")
		assert_lte(right, client.LOADING_BAR_RIGHT, "The fill must not overrun the track")


## The test that would catch the bar being built and never shown, and the only
## one here that could: every check above drives `_update_loading_screen()`
## itself, so all of them pass on a client whose `_process` never calls it —
## which is #58's defect family precisely (a correct mechanism with no caller).
##
## Scanned from the source rather than run, because reaching `_process` needs a
## socket, a window and a server. Same trade `test_terrain_fog.gd` makes for
## `TerrainChunk.set_fog`, for the same reason.
func test_the_client_draws_the_bar_from_its_own_frame_loop() -> void:
	var handle := FileAccess.open("res://client.gd", FileAccess.READ)
	assert_not_null(handle, "client.gd is where it has always been")
	var text := handle.get_as_text()
	handle.close()

	var process_at := text.find("func _process(")
	assert_gt(process_at, 0, "client.gd must still have a frame loop")
	var next_func := text.find("\nfunc ", process_at + 1)
	var body := text.substr(process_at, next_func - process_at)
	assert_true(body.contains("_update_loading_screen()"),
		"Nothing would ever draw the bar: the player is back to a frozen-looking window")
