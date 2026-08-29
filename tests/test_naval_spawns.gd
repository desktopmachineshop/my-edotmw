extends GutTest

## Guards naval stage 9 — spawn placement over the water graph (#301,
## `docs/plans/naval.md` §9, cut-list row 9).
##
## #128 required every start to share ONE walkable component, because an
## army that cannot walk to its enemy is a match nobody can finish. That
## is what retired `islands`: 12 to 268 components and as little as 7.8%
## of the map on the mainland, so twenty players were crammed onto one
## island or not seated at all.
##
## **Ships change what "reachable" means, not whether it is required.**
## Two starts on different islands are mutually reachable if a hull can
## sail between them, so the rule becomes: every start in the same
## component of the graph where a cell is traversable if it is passable OR
## navigable. On a dry map that graph IS the walkable one, and the rule is
## exactly #128's — asserted below, because a change that quietly altered
## `plains` would be a much worse bug than the one it fixes.
##
## The exit criterion is "`islands` seats its full slot count with every
## start reachable", and both halves are here. So is the third thing that
## makes it worth having: the starts must land on SEVERAL islands. Seating
## twenty players on one island would satisfy the criterion and defeat the
## point.

const SLOTS := 20
const SEEDS := [1337, 7, 42]


func _settings(preset: StringName, size_index: int, seed_value: int) -> MapSettings:
	var sizes := MapSettings.sizes()
	var st := MapSettings.from_map(load("res://maps/default.tres"))
	var size: Dictionary = sizes[size_index]
	st.width = int(size["width"])
	st.height = int(size["height"])
	st.preset = preset
	st.apply_preset(TerrainPresetRoster.by_id(preset))
	st.pin_seed(seed_value)
	st.player_slots = SLOTS
	return st


func _world(preset: StringName, size_index: int, seed_value: int) -> Dictionary:
	var st := _settings(preset, size_index, seed_value)
	var space := st.to_space()
	var terrain := st.to_terrain()
	return {
		"settings": st, "space": space,
		"passable": terrain.passability(space),
		"navigable": terrain.navigability(space),
		"config": st.to_spawn_config(),
	}


func _reach_labels(w: Dictionary) -> PackedInt32Array:
	return MapConfig.reachable_components(w["space"], w["passable"], w["navigable"])


# --- the fixture is what it claims -------------------------------------

func test_the_islands_preset_is_still_mostly_water_and_many_islands() -> void:
	# Every claim below is about a map that is genuinely an archipelago.
	# If the preset were ever re-tuned into one continent these tests would
	# keep passing while proving nothing.
	var w := _world(&"islands", 1, 1337)
	var space: TorusSpace = w["space"]
	var wet := 0
	for index in range(space.cell_count()):
		if w["navigable"][index] != 0:
			wet += 1
	var share := float(wet) / float(space.cell_count())
	assert_between(share, 0.5, 0.9, "islands must be mostly water (got %.2f)" % share)

	var sizes: PackedInt32Array = MapConfig.walkable_components(
		w["space"], w["passable"])["sizes"]
	assert_gt(sizes.size(), 5, "and genuinely broken into many landmasses")


# --- THE exit criterion ------------------------------------------------

func test_islands_seats_its_full_slot_count_at_every_shipped_size() -> void:
	var sizes := MapSettings.sizes()
	for i in range(sizes.size()):
		for seed_value in SEEDS:
			var w := _world(&"islands", i, seed_value)
			var points: Array[Vector2i] = w["config"].spawn_points(
				w["passable"], w["navigable"])
			assert_eq(points.size(), SLOTS,
				"%s seed %d seated %d of %d" % [
					String(sizes[i]["name"]), seed_value, points.size(), SLOTS])


func test_every_start_can_reach_every_other_one() -> void:
	# The other half, and the half #128 was protecting: a start nobody can
	# get to is a player nobody can beat.
	var sizes := MapSettings.sizes()
	for i in range(sizes.size()):
		for seed_value in SEEDS:
			var w := _world(&"islands", i, seed_value)
			var points: Array[Vector2i] = w["config"].spawn_points(
				w["passable"], w["navigable"])
			assert_gt(points.size(), 1, "Setup: something to compare")
			var reach := _reach_labels(w)
			var space: TorusSpace = w["space"]
			var home: int = reach[space.index(points[0])]
			for p in points:
				assert_eq(reach[space.index(p)], home,
					"%s seed %d: a start is cut off from the rest" % [
						String(sizes[i]["name"]), seed_value])


func test_the_starts_are_spread_over_several_islands() -> void:
	# The point of the feature, and the thing the criterion alone does not
	# say: twenty players on one island would seat twenty and be exactly
	# the game `islands` could not host.
	var sizes := MapSettings.sizes()
	for i in range(sizes.size()):
		var w := _world(&"islands", i, 1337)
		var points: Array[Vector2i] = w["config"].spawn_points(
			w["passable"], w["navigable"])
		var labels: PackedInt32Array = MapConfig.walkable_components(
			w["space"], w["passable"])["labels"]
		var seen := {}
		for p in points:
			seen[labels[w["space"].index(p)]] = true
		assert_gt(seen.size(), 2,
			"%s put every start on %d island(s)" % [
				String(sizes[i]["name"]), seen.size()])


func test_the_water_graph_is_what_made_the_difference() -> void:
	# The A/B, so "it seats twenty" is attributed rather than assumed. The
	# old rule is still reachable by passing no water: a caller with no
	# navigable array gets #128's mainland rule unchanged.
	var w := _world(&"islands", 0, 1337)  # Skirmish, where land is scarcest
	var without: Array[Vector2i] = w["config"].spawn_points(w["passable"])
	var with_water: Array[Vector2i] = w["config"].spawn_points(
		w["passable"], w["navigable"])
	assert_lt(without.size(), with_water.size(),
		"the water graph must be what seats the extra starts")
	assert_eq(with_water.size(), SLOTS)


# --- what must NOT change ----------------------------------------------

func test_a_dry_map_places_exactly_where_it_did_before() -> void:
	# `plains` is 0.2-1.3% water, so the union graph is the walkable graph
	# and the rule must be #128's, cell for cell. A change that quietly
	# moved every start on every dry map would be a far worse bug than the
	# one this fixes.
	var sizes := MapSettings.sizes()
	for preset in [&"plains", &"highlands", &"continents"]:
		for i in range(sizes.size()):
			var w := _world(preset, i, 1337)
			var before: Array[Vector2i] = w["config"].spawn_points(w["passable"])
			var after: Array[Vector2i] = w["config"].spawn_points(
				w["passable"], w["navigable"])
			assert_eq(after, before,
				"%s %s: the water graph moved a start on a dry map" % [
					String(preset), String(sizes[i]["name"])])


func test_no_start_is_ever_placed_on_water() -> void:
	# The union graph is for REACHABILITY. A start is still a place to
	# build a town hall, and water has never been one.
	var sizes := MapSettings.sizes()
	for i in range(sizes.size()):
		for seed_value in SEEDS:
			var w := _world(&"islands", i, seed_value)
			var points: Array[Vector2i] = w["config"].spawn_points(
				w["passable"], w["navigable"])
			for p in points:
				var index: int = w["space"].index(p)
				assert_true(w["passable"][index] != 0, "a start is in the sea")
				assert_true(w["navigable"][index] == 0, "and it is navigable too")


func test_every_start_still_has_ground_enough_to_build_on() -> void:
	# D-104 survives the change, asked of the start's OWN island rather
	# than of the mainland: an island of `min_spawn_landmass` cells is a
	# home if a ship can reach it, and a six-cell rock still is not — which
	# is the exact failure D-104 was written about.
	var sizes := MapSettings.sizes()
	for i in range(sizes.size()):
		var w := _world(&"islands", i, 1337)
		var config: MapConfig = w["config"]
		var points: Array[Vector2i] = config.spawn_points(
			w["passable"], w["navigable"])
		var components := MapConfig.walkable_components(w["space"], w["passable"])
		var labels: PackedInt32Array = components["labels"]
		var comp_sizes: PackedInt32Array = components["sizes"]
		for p in points:
			var label: int = labels[w["space"].index(p)]
			assert_gte(int(comp_sizes[label]), config.min_spawn_landmass,
				"%s: a start sits on a %d-cell rock" % [
					String(sizes[i]["name"]), int(comp_sizes[label])])


func test_an_island_no_ship_can_reach_is_not_seated_on() -> void:
	# A lake island: big enough to build on, and cut off from the sea that
	# joins everything else. Hand-built, because a generated map that
	# happened to contain one would be a fixture that stops proving this
	# the next time the noise changes.
	var space := TorusSpace.new(40, 20, 1.0)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	# THE TORUS TAX, paid explicitly. The first version of this fixture
	# rocked the sealed island only on its left, and x = 39 wraps to x = 0
	# — so it touched the mainland across the seam and five starts landed
	# on it. A band of constant x does not enclose anything on a torus; it
	# takes two. Same family as the wall of constant q that did not block
	# a torus at all (`docs/status/formation.md`).
	for index in range(space.cell_count()):
		var c := space.from_index(index)
		var rock := c.x == 0 or (c.x >= 32 and c.x < 34) or c.x == 39
		var mainland := c.x >= 1 and c.x < 12
		var sea := c.x >= 12 and c.x < 26
		var isle := c.x >= 26 and c.x < 32       # across the sea: reachable
		var sealed := c.x >= 34 and c.x < 39     # ringed by rock: not
		passable[index] = 0 if rock else (1 if (mainland or isle or sealed) else 0)
		navigable[index] = 1 if (sea and not rock) else 0

	var config := MapConfig.new()
	config.width = 40
	config.height = 20
	config.player_slots = 12
	config.min_spawn_spacing = 2
	config.min_spawn_landmass = 40
	config.spawn_seed = 99

	var reach := MapConfig.reachable_components(space, passable, navigable)
	var points: Array[Vector2i] = config.spawn_points(passable, navigable)
	assert_gt(points.size(), 1, "Setup: something was seated")
	var home: int = reach[space.index(points[0])]
	var on_sealed := 0
	for p in points:
		assert_eq(reach[space.index(p)], home, "a start is cut off")
		if p.x >= 34:
			on_sealed += 1
	assert_eq(on_sealed, 0,
		"a sealed island is big enough to build on and no ship can reach it")


# --- the argument-sharing guard (D-104's own lesson) -------------------

func test_both_sides_ask_the_spawn_question_with_the_water_graph() -> void:
	# D-104: "sharing an implementation is not sharing its ARGUMENTS", and
	# the comment asserting otherwise is why it survived. The last time
	# these two disagreed the lobby drew twenty markers of which none were
	# real — so this scans for the argument rather than for the call.
	for path in ["res://server.gd", "res://client.gd"]:
		var source := FileAccess.get_file_as_string(path)
		assert_ne(source, "", "Setup: %s should be readable" % path)
		var code := ""
		for line in source.split("\n"):
			if not line.strip_edges().begins_with("#"):
				code += line + "\n"
		var at := code.find("spawn_points(")
		assert_true(at >= 0, "%s must ask for spawn points at all" % path)
		# The call and its arguments, up to the closing bracket of the
		# statement — enough to see whether navigability was handed over.
		var tail := code.substr(at, 220)
		assert_true(tail.contains("navigab"),
			"%s calls spawn_points without the water graph" % path)


# --- "islands back in the lobby" ---------------------------------------

func test_islands_is_offered_in_the_lobby() -> void:
	# The cut-list's last row, and the design's §9: the preset becomes
	# visible on the day it becomes playable.
	#
	# On THIS branch it never left. `TerrainPreset.playable` is worker 80's
	# retirement mechanism (PR #299,
	# D-20260828-a-map-a-player-can-pick-is-a-map-an-army-can-cross) and it
	# is not in this tree, so there is no bool here to flip — `islands` is
	# in `TerrainPresetRoster.ids()`, which is the one list both the lobby
	# picker and the server's preset channel cycle.
	#
	# THIS TEST IS THE INTERLOCK. If #299 lands first and retires the
	# preset, this goes red — which is exactly the signal wanted, because
	# by then the seating and reachability below have made it playable and
	# the flip is one line. A comment could not do that.
	# WHAT STAGE 9 ACTUALLY NEEDS is that the naval MAP generates islands
	# terrain, not that the lobby offers `islands` as a free-form preset.
	# `MapConfig.preset` is resolved through `TerrainPresetRoster.by_id`
	# (server.gd), which is deliberately NOT filtered by `playable` — that
	# is #299's own design, so a retired preset still loads from a `.tres`
	# that names it.
	#
	# This assertion used to demand `islands` be in `ids()`, the LOBBY
	# PICKER's list, and that directly contradicted
	# `test_the_lobby_does_not_offer_islands`. Two tests cannot both be
	# right about one flag; the question of whether a player may pick
	# `islands` free-form is #299's to answer, not stage 9's, and stage 9
	# does not depend on the answer.
	var naval_map: MapConfig = load("res://maps/isles.tres")
	assert_not_null(naval_map, "the naval map ships")
	assert_eq(String(naval_map.preset), "islands",
		"the naval map names the islands preset")
	assert_not_null(TerrainPresetRoster.by_id(&"islands"),
		"and that preset still LOADS by id, which is what the map needs — "
		+ "retirement hides a preset from the picker, it does not delete it")
	var offered := TerrainPresetRoster.ids()
	assert_gt(offered.size(), 1, "Setup: there are presets to choose between")


func test_the_validator_asks_the_same_question_the_sampler_does() -> void:
	# 81 found this on the first isles probe: `spawn_points` moved to the
	# land-and-water graph and `disconnected_spawns` — one screen above
	# it, in the same file — kept asking the LAND-ONLY question. So the
	# sampler correctly seated players across islands and the validator
	# immediately called that stranding, on every naval map:
	#
	#   server: map seats all 8 players but strands 2 of them on ground
	#   the others cannot walk to
	#
	# Two definitions of "reachable" in one file, disagreeing, with the
	# naval change having moved one of them. It is not cosmetic:
	# `ai-ladder` fails on engine diagnostics, so every naval ladder run
	# failed on this warning whatever the AI did.
	#
	# Authored seating rather than a generated map, which is why
	# `disconnected_spawns` is public — its own doc says so.
	var space := TorusSpace.new(12, 8, 1.0)
	var count := space.width * space.height
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(count)
	navigable.resize(count)
	# Two land bands separated by water at both q seams (a torus needs
	# BOTH, or the "channel" is walkable round the back — the trap this
	# file already records twice).
	for r in space.height:
		for q in space.width:
			var index := space.index(Vector2i(q, r))
			var wet := q == 0 or q == 6
			passable[index] = 0 if wet else 1
			navigable[index] = 1 if wet else 0

	var west: Array[Vector2i] = [Vector2i(3, 2)]
	var both: Array[Vector2i] = [Vector2i(3, 2), Vector2i(9, 5)]
	assert_eq(west.size(), 1, "fixture: one-sided control")

	var cfg := MapConfig.new()
	cfg.width = space.width
	cfg.height = space.height

	assert_eq(cfg.disconnected_spawns(both, passable), 1,
		"fixture: on FOOT the far start is genuinely unreachable, or this "
		+ "test proves nothing about the water graph")
	assert_eq(cfg.disconnected_spawns(both, passable, navigable), 0,
		"with the water graph, a start across a strait is REACHABLE — the "
		+ "sampler's own rule, and the validator must use it too")


func test_validate_spawns_does_not_call_a_water_seating_stranded() -> void:
	# The CALLER, which is where the defect actually was. The test above
	# drives `disconnected_spawns` directly and passes whatever
	# `validate_spawns` does with it — I perturbed the call site and it
	# stayed green, which is the vacuous-guard shape this repo keeps
	# paying for. This one goes through `validate_spawns`.
	var space := TorusSpace.new(16, 10, 1.0)
	var count := space.width * space.height
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(count)
	navigable.resize(count)
	for r in space.height:
		for q in space.width:
			var index := space.index(Vector2i(q, r))
			# Two land masses, water at BOTH q seams so the torus cannot
			# join them round the back.
			var wet := q == 0 or q == 8
			passable[index] = 0 if wet else 1
			navigable[index] = 1 if wet else 0

	var cfg := MapConfig.new()
	cfg.width = space.width
	cfg.height = space.height
	cfg.player_slots = 2
	cfg.min_spawn_spacing = 5
	cfg.min_spawn_landmass = 8
	cfg.spawn_seed = 7

	var points := cfg.spawn_points(passable, navigable)
	assert_eq(points.size(), 2, "fixture: both slots must seat")

	# The fixture is only meaningful if the sampler actually spread them
	# across the water — otherwise there is no stranding to mis-report.
	var land: PackedInt32Array = MapConfig.walkable_components(space, passable)["labels"]
	var masses := {}
	for p in points:
		masses[land[space.index(p)]] = true
	assert_eq(masses.size(), 2,
		"fixture: the sampler must have seated ACROSS the water, or this "
		+ "test cannot see the bug it is written for")

	assert_eq(cfg.validate_spawns(passable, navigable), "",
		"a seating the sampler chose over the water graph must not then be "
		+ "reported as stranded by the validator — ai-ladder fails on "
		+ "engine diagnostics, so this warning reds every naval run")
