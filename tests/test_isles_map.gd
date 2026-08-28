extends GutTest

## Guards `maps/isles.tres` — the naval gate's map (#301, cut-list row 9,
## `docs/plans/naval.md` §6.2).
##
## The chain shipped a gate that fails unless a landing happens, and no
## map existed on which a landing was possible. **A gate that cannot fire
## is a gate that lies green** — D-076's lesson, which §6 opens by naming:
## that feature shipped its AI consumers with nothing exercising them.
##
## So the acceptance is a PAIR, and both halves are here:
##
##   - on `isles`, the starts are on several islands with sea between
##     them, so an AI that never sails can never reach anybody;
##   - on `ladder`, every start shares one landmass, so `wants_navy = 0`
##     is the CORRECT answer and the gate must not fire at all.
##
## Without the second half the first proves nothing: a predicate that
## always wants a navy would pass it.

## Seeds vary the MATCH, which regenerates the terrain — not merely where
## the sampler puts starts in one world. The first version of the sizing
## probe behind this map swept `spawn_seed` instead and declared a 64x72
## map healthy on every seed; these tests then went red at three of five,
## because a match seed makes a different world. Twelve here; the sweep
## that chose the dimensions ran sixty.
const SEEDS := [1, 2, 3, 5, 7, 13, 42, 99, 404, 1337, 4242, 20260801]


func _world(map_path: String, seed_value: int) -> Dictionary:
	var cfg: MapConfig = load(map_path)
	var st := MapSettings.from_map(cfg)
	st.apply_preset(TerrainPresetRoster.by_id(st.preset))
	st.pin_seed(seed_value)
	var space := st.to_space()
	var terrain := st.to_terrain()
	var passable := terrain.passability(space)
	var navigable := terrain.navigability(space)
	return {
		"config": cfg, "settings": st, "space": space,
		"passable": passable, "navigable": navigable,
		"points": st.to_spawn_config().spawn_points(passable, navigable),
	}


## Distinct labels the starts occupy, under a given component labelling.
func _islands(w: Dictionary, labels: PackedInt32Array, limit := -1) -> int:
	var seen := {}
	var points: Array = w["points"]
	var n := points.size() if limit < 0 else mini(limit, points.size())
	for i in n:
		seen[labels[w["space"].index(points[i])]] = true
	return seen.size()


func _foot(w: Dictionary) -> PackedInt32Array:
	return MapConfig.walkable_components(w["space"], w["passable"])["labels"]


func _sea(w: Dictionary) -> PackedInt32Array:
	return MapConfig.reachable_components(w["space"], w["passable"], w["navigable"])


# --- the map names its own ground --------------------------------------

func test_isles_names_its_own_ground() -> void:
	# The whole reason `MapConfig.preset` exists. Selected by dimensions
	# alone this map generated a CONTINENTS world at isles dimensions —
	# one landmass, no water worth crossing — and the gate would have
	# reported `wants_navy = 0` correctly and passed having tested
	# nothing. No recipe passes `--preset`, so the map file is the only
	# place this fact could live.
	var cfg: MapConfig = load("res://maps/isles.tres")
	assert_eq(cfg.preset, &"islands", "isles must name the islands preset")
	assert_eq(MapSettings.from_map(cfg).preset, &"islands",
		"and the settings the server builds must carry it")


func test_a_map_that_names_no_preset_is_left_alone() -> void:
	# The no-churn claim, asserted rather than trusted: adding a field
	# with an empty default must not move any map that shipped before it.
	var untouched := MapSettings.new().preset
	for path in ["res://maps/default.tres", "res://maps/huge.tres",
			"res://maps/ladder.tres"]:
		var cfg: MapConfig = load(path)
		assert_eq(cfg.preset, &"", "%s must name no preset" % path)
		assert_eq(MapSettings.from_map(cfg).preset, untouched,
			"%s must still get the default ground" % path)


# --- isles: a ship is REQUIRED -----------------------------------------

func test_isles_seats_every_slot_it_claims() -> void:
	# #276's lesson: a seat past what the map authored shares another
	# player's start. A map that claims 8 and seats 5 is a map that lies
	# about how many can play on it.
	var cfg: MapConfig = load("res://maps/isles.tres")
	for seed_value in SEEDS:
		var w := _world("res://maps/isles.tres", seed_value)
		assert_eq(w["points"].size(), cfg.player_slots,
			"isles must seat all %d slots at seed %d" % [
				cfg.player_slots, seed_value])


func test_every_start_on_isles_is_reachable_by_sea() -> void:
	# Stage 9's rule: two starts on different islands are mutually
	# reachable if a hull can sail between them. One component means
	# nobody is marooned — which under D-033 would be an undecidable
	# match reading as a draw at the time cap.
	for seed_value in SEEDS:
		var w := _world("res://maps/isles.tres", seed_value)
		assert_eq(_islands(w, _sea(w)), 1,
			"every start must share one SEA component at seed %d" % seed_value)


func test_isles_cannot_be_played_on_foot() -> void:
	# The half that makes the gate mean something. If the starts shared
	# one walkable component, an AI that never built a ship could still
	# win, `wants_navy = 0` would be right, and `landings = 0` would be a
	# truthful pass.
	for seed_value in SEEDS:
		var w := _world("res://maps/isles.tres", seed_value)
		assert_gt(_islands(w, _foot(w)), 1,
			"isles starts must span several LANDMASSES at seed %d" % seed_value)


func test_the_gates_own_four_seats_span_several_islands() -> void:
	# `test-load 4` seats bots on 0-3, not on a random four. A map whose
	# eight starts span four islands can still put the first four on ONE,
	# and then the gate is vacuous for exactly the run people execute.
	# Measured while sizing: 56x64 does this at seed 1337 and 64x72 does
	# not at any seed tried.
	for seed_value in SEEDS:
		var w := _world("res://maps/isles.tres", seed_value)
		assert_gt(_islands(w, _foot(w), 4), 1,
			"seats 0-3 must not share one island at seed %d" % seed_value)


func test_no_start_on_isles_stands_in_the_sea() -> void:
	for seed_value in SEEDS:
		var w := _world("res://maps/isles.tres", seed_value)
		var navigable: PackedByteArray = w["navigable"]
		for p in w["points"]:
			assert_eq(navigable[w["space"].index(p)], 0,
				"a start must be on land at seed %d" % seed_value)


# --- ladder: a ship is NOT required, and that must stay true -----------

func test_the_ladder_map_correctly_needs_no_navy() -> void:
	# The negative half of the acceptance pair. Without it, a predicate
	# that always wanted a navy would pass every test above.
	for seed_value in SEEDS:
		var w := _world("res://maps/ladder.tres", seed_value)
		assert_eq(_islands(w, _foot(w)), 1,
			"every ladder start must share ONE landmass at seed %d — the AI is right to want no navy there" % seed_value)


func test_the_topology_separates_a_naval_map_from_a_land_one() -> void:
	# The arithmetic the naval gate keys on, asserted on the shipped maps
	# so a change to placement or to the water graph reds here rather
	# than in a five-minute gate run.
	#
	# The MARKER itself is 81's (`SPAWN_LANDMASSES`, printed by the
	# server on their branch and parsed by `gate-check.sh naval`). I
	# printed a second one here and removed it: two log lines stating one
	# fact, both from `server.gd`, is the duplication this project keeps
	# paying for — and theirs is the one their gate already consumes.
	# What is asserted here is the QUANTITY, which needs no marker.
	#
	# `landmasses > 1` is "a ship is REQUIRED"; `sea_components == 1` is
	# "a ship is SUFFICIENT". Both are needed: a map where every start is
	# marooned on its own island with no shared water would satisfy the
	# first and be unplayable.
	for seed_value in SEEDS:
		var isles := _world("res://maps/isles.tres", seed_value)
		assert_gt(_islands(isles, _foot(isles)), 1,
			"isles must REQUIRE a navy at seed %d" % seed_value)
		assert_eq(_islands(isles, _sea(isles)), 1,
			"and a navy must SUFFICE at seed %d" % seed_value)

		var ladder := _world("res://maps/ladder.tres", seed_value)
		assert_eq(_islands(ladder, _foot(ladder)), 1,
			("ladder must not require a navy at seed %d — a gate that fires "
			+ "there would be turned off within a week") % seed_value)
