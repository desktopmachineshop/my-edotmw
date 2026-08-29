extends GutTest

## Guards D-20260818-a-slider-and-its-constraint-are-one-thing (#125) —
## the map-generation sliders and the rules deciding which maps the server
## will accept are ONE definition, and the coupling between two handles on
## the same ordering is in the handles rather than in a hidden number.
##
## What went wrong is worth restating, because no number could see it: the
## ranges were a literal table in `client.gd`, the clamps were a second
## copy in `MatchState.set_map_option`, and the constraints were a third
## set of rules in `MapSettings.validate` — each correct alone. The value
## that made the set of them incoherent was `beach_level`, which a preset
## set and no control exposed: on `plains` it sat at 0.27 and pinned a
## slider drawn to 0.90, so 74% of that slider's travel produced a map the
## server refused, for a reason nothing on screen could show.
##
## The rules live in `MapSettings`, so this tests them there and against
## the server's own `MatchState`, not against a screenshot — the client
## needs a GPU (D-014); the arithmetic that was wrong does not.


func _lobby() -> MatchState:
	var m := MatchState.new()
	m.require_admin_start = true
	m.civ_rng.seed = 42
	m.add_player(1)
	m.add_player(2)
	return m


## The LOBBY's index for a preset — `ids()` on purpose, because that is
## the list the picker and the option channel cycle
## (`D-20260828-a-map-a-player-can-pick-is-a-map-an-army-can-cross`).
##
## Every other use in this file is `all_ids()`, and the difference
## matters: the tests below assert things about the shipped `.tres` DATA,
## which stay true of a preset the lobby has retired. Retiring `islands`
## silently dropped it from two of them until this was noticed — a change
## narrowing a test's scope as a side effect, which is the "what can no
## longer be reached" family (D-20260817-selection-bar-three-columns)
## pointed at coverage instead of at a control.
func _preset_index(id: StringName) -> int:
	return TerrainPresetRoster.ids().find(id)


# --- the beach is a band above the water, not a free parameter ---------

func test_a_shipped_preset_keeps_its_beach_exactly_where_it_put_it() -> void:
	# The band is stored and the level derived, so every preset generates
	# the world it generated before this changed — that is the claim which
	# makes deriving it a fix rather than a re-tuning of four maps.
	for id in TerrainPresetRoster.all_ids():
		var preset := TerrainPresetRoster.by_id(id)
		var settings := MapSettings.new()
		settings.apply_preset(preset)
		assert_almost_eq(settings.beach_level, preset.beach_level, 0.0001,
			"%s should keep the beach line its .tres asks for" % id)


func test_the_beach_follows_the_water() -> void:
	var settings := MapSettings.new()
	settings.apply_preset(TerrainPresetRoster.by_id(&"plains"))
	var band := settings.beach_level - settings.sea_level
	assert_gt(band, 0.0, "Setup: plains has a beach at all")

	settings.set_slider("sea_level", 0.5)
	assert_almost_eq(settings.beach_level, 0.5 + band, 0.0001,
		"raising the sea takes the shoreline with it")
	assert_true(settings.beach_level >= settings.sea_level,
		"and never leaves it underwater")


func test_no_point_of_any_slider_breaks_the_ordering() -> void:
	# The defect, stated as the invariant it broke: sea <= beach <=
	# mountain, at every point of every slider, from every shipped preset.
	# Before the beach became a band this failed on the first sample past
	# the preset's own beach line — on `plains`, at 0.28 of a slider drawn
	# to 0.90.
	for id in TerrainPresetRoster.all_ids():
		for key in MapSettings.SLIDER_LIMITS.keys():
			var settings := MapSettings.new()
			settings.apply_preset(TerrainPresetRoster.by_id(id))
			var bounds: Vector2 = settings.slider_bounds(String(key))
			for i in range(21):
				settings.set_slider(String(key),
					lerpf(bounds.x, bounds.y, float(i) / 20.0))
				var where := "%s at %s=%.3f" % [id, key, settings.get(String(key))]
				assert_lt(settings.sea_level, settings.mountain_level,
					"%s: the sea must stay below the mountain line" % where)
				assert_true(settings.beach_level >= settings.sea_level
						and settings.beach_level <= settings.mountain_level,
					"%s: the beach must stay between them" % where)


func test_the_handles_stop_where_each_other_is() -> void:
	# The coupling made visible: the ends MOVE. A player pushing the
	# mountain line down finds the sea-level slider shorter, rather than
	# finding out from the server that the combination was refused.
	var settings := MapSettings.new()
	settings.mountain_level = 0.4
	assert_almost_eq(settings.slider_bounds("sea_level").y,
		0.4 - MapSettings.SLIDER_STEP, 0.0001,
		"the sea may go up to just under the mountain line, and no further")

	settings.sea_level = 0.3
	assert_almost_eq(settings.slider_bounds("mountain_level").x,
		0.3 + MapSettings.SLIDER_STEP, 0.0001,
		"and the mountain line may come down to just above the water")

	settings.set_slider("sea_level", 0.95)
	assert_lt(settings.sea_level, settings.mountain_level,
		"a value past the end is clamped to the travel that exists")


# --- one definition, not three -----------------------------------------

func test_the_lobby_draws_no_range_of_its_own() -> void:
	# Against `client.gd`'s own constant. A `min`/`max` written here is a
	# second copy of a bound the server also holds, which is exactly how
	# the two came to disagree — and disagreeing is silent, because each
	# is a perfectly good number on its own.
	var options: Array = load("res://client.gd").get_script_constant_map()["MAP_OPTIONS"]
	for option in options:
		assert_false(option.has("min") or option.has("max"),
			"the '%s' row must take its travel from MapSettings.slider_bounds"
				% String(option["key"]))


func test_the_server_clamps_through_the_same_definition() -> void:
	var source := FileAccess.get_file_as_string("res://match_state.gd")
	assert_ne(source, "", "Setup: match_state.gd should be readable")
	for key in MapSettings.SLIDER_LIMITS.keys():
		assert_false(source.contains("map_settings.%s = clampf" % key),
			"%s must be clamped by MapSettings.set_slider, not by a range written here"
				% key)


func test_every_slider_the_lobby_draws_is_one_the_server_accepts() -> void:
	# The pair, tested as a pair: every row the client builds must be a
	# key `set_map_option` knows, or it is a control that does nothing
	# (D-065's family), and every slider the server clamps must be a row,
	# or it is a rule nobody can reach.
	var options: Array = load("res://client.gd").get_script_constant_map()["MAP_OPTIONS"]
	var drawn: Array = []
	for option in options:
		if String(option.get("kind", "")) == "slider":
			drawn.append(String(option["key"]))
	var m := _lobby()
	for key in drawn:
		assert_true(MapSettings.SLIDER_LIMITS.has(key),
			"the lobby draws a '%s' slider, so MapSettings must bound one" % key)
		# One step from where the shipped default has it, rather than an
		# end of the travel: the ends are legal handle positions and are
		# not all legal WORLDS — a mountain line one step above the water
		# leaves nothing walkable between them, which `validate` refuses
		# on purpose. What is being asserted here is that the key reaches
		# the server at all.
		var current := float(m.map_settings.get(key))
		var bounds: Vector2 = m.map_settings.slider_bounds(key)
		var nudged := clampf(current + MapSettings.SLIDER_STEP, bounds.x, bounds.y)
		if is_equal_approx(nudged, current):
			nudged = clampf(current - MapSettings.SLIDER_STEP, bounds.x, bounds.y)
		assert_true(m.set_map_option(1, key, nudged),
			"and the server must accept a nudge on it")
	for key in MapSettings.SLIDER_LIMITS.keys():
		assert_true(drawn.has(String(key)),
			"MapSettings bounds a '%s' slider the lobby never draws" % key)


# --- what the hidden beach line used to cost ---------------------------

func test_the_sea_level_slider_works_past_the_presets_own_beach() -> void:
	# The reported symptom, on the preset it was worst on. `plains` sets a
	# beach line of 0.27; this move is a nudge past it, well inside a
	# slider drawn to 0.90, and it was refused with a message about a
	# value the lobby does not show.
	var m := _lobby()
	assert_true(m.set_map_option(1, "preset", float(_preset_index(&"plains"))),
		"Setup: the admin may choose a preset")
	assert_lt(m.map_settings.beach_level, 0.5,
		"Setup: plains' beach line is below the level about to be asked for")

	assert_true(m.set_map_option(1, "sea_level", 0.5),
		"half the map under water is a map, and the server should generate it")
	assert_almost_eq(m.map_settings.sea_level, 0.5, 0.0001,
		"and it should be the level that was asked for, not a rolled-back one")


# --- validation is about the world, not only about the ordering --------

func test_validate_refuses_a_world_with_no_ground_on_it() -> void:
	# The open question in #125, answered: yes, a combination could pass
	# every threshold check and still be unplayable. Measured on the
	# shipped Standard map at seed 1337 before this check existed — sea
	# level 0.85 with the mountain line at 0.98 is 0.0% walkable and
	# yields 0 of 8 starting positions, with `validate` returning "".
	var settings := MapSettings.new()
	settings.set_slider("mountain_level", 0.98)
	settings.set_slider("sea_level", 0.85)
	assert_lt(settings.sea_level, settings.mountain_level,
		"Setup: every threshold is in order")

	assert_ne(settings.validate(), "",
		"a map with nowhere to stand is not a map the server should generate")

	# The evidence, generated rather than asserted about: the real spawn
	# sampler on the real passability field finds nowhere for anyone.
	var points := settings.to_spawn_config().spawn_points(
		settings.to_terrain().passability(settings.to_space()))
	assert_eq(points.size(), 0, "and the spawn sampler agrees there is nowhere to start")


func test_an_unplayable_slider_move_is_refused_and_rolled_back() -> void:
	var m := _lobby()
	assert_true(m.set_map_option(1, "mountain_level", 0.98), "Setup: room above")
	var before := m.map_settings.sea_level
	assert_false(m.set_map_option(1, "sea_level", 0.85),
		"the server refuses the drowned world rather than the match")
	assert_almost_eq(m.map_settings.sea_level, before, 0.0001,
		"and leaves the settings as they were")


func test_every_shipped_preset_generates_a_map_at_every_size() -> void:
	# The other half: the check must not refuse anything the game ships
	# with. Four presets x four sizes, through the real generator.
	for entry in MapSettings.sizes():
		for id in TerrainPresetRoster.all_ids():
			var settings := MapSettings.new()
			settings.width = int(entry["width"])
			settings.height = int(entry["height"])
			settings.apply_preset(TerrainPresetRoster.by_id(id))
			assert_eq(settings.validate(), "",
				"%s at %s must generate" % [id, entry["name"]])


func test_the_sampled_ground_estimate_matches_the_real_generation() -> void:
	# `walkable_fraction` samples a lattice where `TerrainGen.passability`
	# generates every cell, and it repeats that generator's threshold test
	# rather than calling it — so this compares the two on the far side of
	# the boundary (the VAT-compression rule), and a drift in either
	# fails here instead of quietly moving where the check bites.
	for id in TerrainPresetRoster.all_ids():
		var settings := MapSettings.new()
		settings.width = 84
		settings.height = 96
		settings.apply_preset(TerrainPresetRoster.by_id(id))

		var passable := settings.to_terrain().passability(settings.to_space())
		var walkable := 0
		for cell in passable:
			if cell != 0:
				walkable += 1
		var truth := float(walkable) / float(passable.size())
		assert_almost_eq(settings.walkable_fraction(), truth, 0.03,
			"%s: the estimate should track the world it is estimating" % id)
