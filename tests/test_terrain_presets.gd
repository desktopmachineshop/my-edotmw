extends GutTest

## Which presets a player may pick, and why one of them may not (#280,
## `D-20260828-a-map-a-player-can-pick-is-a-map-an-army-can-cross`).
##
## `islands` generates perfectly good terrain and cannot host a match:
## measured over 48 worlds it is 29-35% walkable across 8-268
## disconnected components, and the game has no naval movement, no
## transport and no bridge — so most of what it draws is ground no army
## can reach. It fails at TWO seats, which is why it is retired from the
## lobby rather than gated behind a seat count.
##
## The retirement is `TerrainPreset.playable`, and these pin both halves:
## the lobby stops offering it, and everything else keeps working, so the
## day armies can cross water this is one bool rather than a rewrite.

const REACHABLE_SEATS := 2


func _preset(id: StringName) -> TerrainPreset:
	return TerrainPresetRoster.by_id(id)


# --- the retirement itself ---------------------------------------------

## Observed to fail before the fix: with `playable` defaulting true for
## every preset, `ids()` returns `islands` and the lobby offers it.
func test_the_lobby_does_not_offer_islands() -> void:
	assert_false(TerrainPresetRoster.ids().has(&"islands"),
		"islands is offered to players, and no army on it can reach most of the map")


## ...and the presets that DO host a match are still all there, or
## "retire the broken one" would pass by retiring everything.
func test_every_other_preset_is_still_offered() -> void:
	var offered := TerrainPresetRoster.ids()
	assert_gte(offered.size(), 3,
		"fewer than three playable presets — the map variety is gone, not fixed")
	for id in TerrainPresetRoster.all_ids():
		if id == &"islands":
			continue
		assert_true(offered.has(id), "playable preset %s vanished from the picker" % id)


## Retired is not deleted. `by_id` and `load_all` still answer, so
## `--preset=islands` still generates one for terrain work and a saved
## setting naming it still loads — which is what makes this reversible
## rather than destructive.
func test_a_retired_preset_is_still_loadable_by_name() -> void:
	var def := _preset(&"islands")
	assert_not_null(def, "islands must still LOAD — retiring it is not deleting it")
	assert_false(def.playable, "...and it must be the flag that hides it, not its absence")
	assert_true(TerrainPresetRoster.all_ids().has(&"islands"),
		"all_ids is what tooling and terrain tests mean by 'every preset'")


## The picker and the server's option channel read the SAME list. Two
## lists is how a lobby comes to draw a choice the server refuses — the
## defect #125 was, one field over.
func test_the_picker_and_the_option_channel_cycle_one_list() -> void:
	var source := FileAccess.get_file_as_string("res://client.gd")
	var server_side := FileAccess.get_file_as_string("res://match_state.gd")
	assert_true(source.contains("TerrainPresetRoster.ids()"),
		"the lobby picker must read the playable list")
	assert_true(server_side.contains("TerrainPresetRoster.ids()"),
		"the server's preset option must cycle the same playable list")
	for text in [source, server_side]:
		assert_false(text.contains("TerrainPresetRoster.all_ids()"),
			"neither side may offer a retired preset by reaching past the filter")


# --- why islands was retired, asserted rather than remembered ----------

## The evidence, re-derived from the shipped preset rather than quoted:
## a two-player match on `islands` cannot reliably put both starts on
## ground they can walk between. This is the measurement the decision was
## made on, kept as a test so that a future preset change has to face it.
##
## Deliberately at REACHABLE_SEATS = 2: the argument for retiring rather
## than seat-gating is that there is no seat count at which it works, and
## two is the smallest count there is.
func test_islands_cannot_seat_even_two_players_on_one_landmass() -> void:
	var shared := 0
	var tried := 0
	for seed_value in [1337, 42, 7, 99]:
		var settings := MapSettings.new()
		settings.apply_preset(_preset(&"islands"))
		settings.width = 168
		settings.height = 194
		settings.seed = seed_value
		settings.player_slots = REACHABLE_SEATS

		var space := TorusSpace.new(settings.width, settings.height, 1.0)
		var passable := settings.to_terrain().passability(space)
		var points := settings.to_spawn_config().spawn_points(passable)
		if points.size() < REACHABLE_SEATS:
			continue
		tried += 1
		if _same_component(space, passable, points[0], points[1]):
			shared += 1

	assert_gt(tried, 2, "too few worlds seated two players at all to conclude anything")
	assert_lt(shared, tried,
		"every sampled islands world put both starts on one landmass — if that is now "
		+ "true, the reason for retiring it has gone and the decision should be revisited")


## The control, and it is the important half: the same test on the
## SHIPPED default preset must pass every time. Without it, "islands
## strands players" would be indistinguishable from "the check is broken".
func test_the_default_preset_always_seats_two_players_together() -> void:
	for seed_value in [1337, 42, 7, 99]:
		var settings := MapSettings.new()
		settings.apply_preset(_preset(&"continents"))
		settings.width = 168
		settings.height = 194
		settings.seed = seed_value
		settings.player_slots = REACHABLE_SEATS

		var space := TorusSpace.new(settings.width, settings.height, 1.0)
		var passable := settings.to_terrain().passability(space)
		var points := settings.to_spawn_config().spawn_points(passable)
		assert_eq(points.size(), REACHABLE_SEATS,
			"the shipped preset failed to seat two players at seed %d" % seed_value)
		assert_true(_same_component(space, passable, points[0], points[1]),
			"the shipped preset stranded a player at seed %d" % seed_value)


## Wrap-aware flood fill from `a`, stopping the moment it reaches `b`.
## Capped, so an unreachable pair costs the component rather than the map
## — and inline rather than shared, because the component walk this file
## needs is one question ("can these two walk to each other") and not the
## full labelling.
func _same_component(space: TorusSpace, passable: PackedByteArray,
		a: Vector2i, b: Vector2i) -> bool:
	var target := space.index(b)
	var start := space.index(a)
	if start == target:
		return true
	if passable[start] == 0 or passable[target] == 0:
		return false
	var seen := {start: true}
	var frontier := PackedInt32Array([start])
	while not frontier.is_empty():
		var at := frontier[frontier.size() - 1]
		frontier.resize(frontier.size() - 1)
		for neighbour in space.neighbors(space.from_index(at)):
			var index := space.index(neighbour)
			if seen.has(index) or passable[index] == 0:
				continue
			if index == target:
				return true
			seen[index] = true
			frontier.append(index)
	return false
