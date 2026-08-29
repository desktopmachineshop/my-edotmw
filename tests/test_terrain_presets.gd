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


## Islands stays retired because ARMIES CANNOT CROSS WATER, and that is
## now the whole of the reason.
##
## It used to be asserted the other way round — that sampled worlds
## stranded a player's start on a landmass the other could not reach — and
## #216 made that false by sampling every start from the LARGEST walkable
## component. Nobody is stranded on `islands` any more. The retirement
## stands anyway, and rewriting the test rather than deleting it is the
## point: the premise moved, the conclusion did not, and a reader deserves
## to know which.
##
## **Un-retiring it via #216 would quietly defeat the gate the naval block
## ships.** Largest-component sampling puts every start on one landmass, so
## `SPAWN_LANDMASSES` is 1 and naval's own gate SKIPS on the one preset it
## exists to exercise. Stage 9 un-retires `islands` properly — ship-
## reachable placement and multi-landmass starts on the measured isles map
## — which is strictly better than merely not-stranding anybody. Retired
## until then is load-bearing, not inertia.
##
## What is measured here is the thing that has not changed: most of an
## `islands` world is ground no army can walk to from a start.
func test_islands_is_mostly_ground_no_army_can_walk_to() -> void:
	var sampled := 0
	var worst_reach := 1.0
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
		if points.is_empty():
			continue
		sampled += 1
		# The share of walkable ground a start can actually reach on foot.
		# Everything else is scenery until something can carry an army to it.
		var reach := float(_component_size(space, passable, points[0]))
		var walkable := 0
		for i in range(passable.size()):
			if passable[i] != 0:
				walkable += 1
		if walkable > 0:
			worst_reach = minf(worst_reach, reach / float(walkable))

	assert_gt(sampled, 2, "too few islands worlds generated to conclude anything")
	assert_lt(worst_reach, 0.9,
		"every islands world now lets a start walk to nearly all of its own "
		+ "walkable ground — if that is true, water has stopped dividing the "
		+ "map and the retirement can be revisited")


## How much walkable ground is reachable on foot from `from`.
func _component_size(space: TorusSpace, passable: PackedByteArray, from: Vector2i) -> int:
	var start := space.index(from)
	if passable[start] == 0:
		return 0
	var seen := {start: true}
	var frontier := PackedInt32Array([start])
	while not frontier.is_empty():
		var at := frontier[frontier.size() - 1]
		frontier.resize(frontier.size() - 1)
		for neighbour in space.neighbors(space.from_index(at)):
			var index := space.index(neighbour)
			if seen.has(index) or passable[index] == 0:
				continue
			seen[index] = true
			frontier.append(index)
	return seen.size()


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


## A retired preset must still be COVERED by the data-invariant tests,
## even though the lobby no longer offers it. `test_map_slider_ranges.gd`
## asserts things about every shipped `.tres` — the beach band, the
## slider ordering, that it generates at every size — and those stay true
## of a preset a player cannot pick.
##
## This is a caller-exists scan (D-106's rule): retiring `islands` dropped
## it out of two of those tests silently, because they iterated the
## PLAYABLE list. Nothing failed; the coverage just shrank.
func test_the_data_invariant_tests_cover_retired_presets_too() -> void:
	var source := FileAccess.get_file_as_string("res://tests/test_map_slider_ranges.gd")
	assert_true(source.contains("TerrainPresetRoster.all_ids()"),
		"the shipped-data invariants must iterate every preset, not only the playable ones")
	assert_eq(source.count("TerrainPresetRoster.ids()"), 1,
		"exactly one use of the playable list belongs there — the lobby's own index; "
		+ "any other is a data invariant that stops covering a retired preset")


## And the two lists must actually differ while anything is retired, or
## `all_ids()` is a synonym and the distinction above is decoration.
func test_the_playable_list_is_genuinely_shorter() -> void:
	assert_lt(TerrainPresetRoster.ids().size(), TerrainPresetRoster.all_ids().size(),
		"nothing is retired, so every all_ids() call in the estate is untested")
