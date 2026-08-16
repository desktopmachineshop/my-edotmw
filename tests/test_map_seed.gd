extends GutTest

## Guards D-099 — the map seed is rolled for a lobby, pinnable, and the
## civ draw follows it.
##
## Every rule here is about something that LOOKS completely normal when it
## is broken, which is why none of them were noticed for a milestone:
## `MapSettings.seed` documented itself as "rolled per match" while
## nothing rolled it, so every lobby match generated the identical world;
## and `civ_rng` was seeded from a constant, so a seat set to Random
## resolved to a real civ — the visible part working — and to the SAME
## real civ every match.
##
## The lobby half lives in MatchState for the reason that file's header
## gives: a GUT test cannot stand up an ENet host, and "the next match is
## a different place" is a rule rather than a UI state. The server's own
## wiring (roll on a `--lobby` start, not on a headless one) is checked by
## running it, not here.


func _lobby() -> MatchState:
	var m := MatchState.new()
	m.require_admin_start = true
	m.civ_seed_base = 0
	m.reseed_civ_rng()
	return m


func _running_match() -> MatchState:
	var m := _lobby()
	m.add_player(1)
	m.add_ai(1, CivRoster.RANDOM, 2)
	assert_true(m.request_start(1), "Setup: the admin should be able to start")
	return m


# --- rolling ----------------------------------------------------------

func test_rolling_actually_changes_the_map() -> void:
	# The reported defect in its smallest form: the seed had a doc comment
	# saying it was rolled, and no code anywhere that rolled it.
	var settings := MapSettings.new()
	var seen := {}
	for i in range(24):
		seen[settings.roll_seed()] = true
	assert_gt(seen.size(), 1,
		"Rolling 24 times should not keep handing back the same world")


func test_a_rolled_seed_is_one_the_lobby_can_show() -> void:
	# A roll the spinner cannot display is a map nobody can write down and
	# play again, which is half of what pinning is for.
	var settings := MapSettings.new()
	for i in range(200):
		var rolled := settings.roll_seed()
		assert_between(rolled, 0, MapSettings.SEED_MAX,
			"A rolled seed must be inside the range the lobby offers")


func test_rolling_leaves_the_seed_unpinned() -> void:
	var settings := MapSettings.new()
	settings.pin_seed(4242)
	settings.roll_seed()
	assert_false(settings.seed_pinned,
		"A rolled map is not a chosen one — the next lobby must roll again")


func test_typing_a_seed_pins_it() -> void:
	var m := _lobby()
	m.add_player(1)
	assert_true(m.set_map_option(1, "seed", 4242.0))
	assert_eq(m.map_settings.seed, 4242, "The admin's number should be the seed")
	assert_true(m.map_settings.seed_pinned,
		"Choosing a seed on purpose is what pinning means")


func test_a_seed_the_lobby_could_not_show_is_wrapped_rather_than_taken() -> void:
	# A spinner is a suggestion from an untrusted client (D-002), and a
	# seed outside its range would be unreadable and unrepeatable.
	var m := _lobby()
	m.add_player(1)
	for value in [5_000_123.0, -12.0, float(MapSettings.SEED_MAX) + 1.0]:
		m.set_map_option(1, "seed", value)
		assert_between(m.map_settings.seed, 0, MapSettings.SEED_MAX,
			"Every seed must land inside the range the lobby can show")

	# Wrapped rather than clamped, because a seed is an identifier: two
	# out-of-range seeds must not silently be the same map.
	m.set_map_option(1, "seed", 2_000_123.0)
	var first := m.map_settings.seed
	m.set_map_option(1, "seed", 3_000_456.0)
	assert_ne(m.map_settings.seed, first,
		"Two different seeds should not collapse onto one world")


func test_the_reroll_button_asks_for_a_new_map_without_pinning_it() -> void:
	var m := _lobby()
	m.add_player(1)
	m.set_map_option(1, "seed", 4242.0)
	var rolled := false
	# The roll is random, so it may legitimately hand back the number it
	# already had. Asking a few times makes that a coincidence rather than
	# a flaky test — and unpinning is unconditional either way.
	for i in range(8):
		m.set_map_option(1, MatchState.REROLL_OPTION, 0.0)
		if m.map_settings.seed != 4242:
			rolled = true
	assert_true(rolled, "Reroll should reach a different map")
	assert_false(m.map_settings.seed_pinned,
		"A rerolled seed must stay unpinned, or the lobby stops rolling")


func test_only_the_admin_may_reroll() -> void:
	var m := _lobby()
	m.add_player(1)
	m.add_player(2)
	m.map_settings.pin_seed(4242)
	assert_false(m.set_map_option(2, MatchState.REROLL_OPTION, 0.0),
		"A guest must not be able to reroll the host's map")
	assert_eq(m.map_settings.seed, 4242, "and nothing should have changed")


# --- the next match is a new place -------------------------------------

func test_the_next_match_is_a_different_map() -> void:
	# The consequence the issue actually reported, one level up: without
	# this, "play again" replays the map just played for as long as the
	# server stays up, and nothing about it looks wrong.
	var m := _running_match()
	var played := m.map_settings.seed
	var seen := {}
	for i in range(24):
		m.return_to_lobby()
		seen[m.map_settings.seed] = true
		m.request_start(1)
	assert_gt(seen.size(), 1,
		"Returning to the lobby should roll a new world, not re-serve %d" % played)


func test_a_pinned_seed_is_played_again() -> void:
	# The other half of the same rule, and the reason the pin exists: a
	# good map is worth replaying deliberately.
	var m := _running_match()
	m.return_to_lobby()
	m.map_settings.pin_seed(4242)
	m.request_start(1)
	m.return_to_lobby()
	assert_eq(m.map_settings.seed, 4242,
		"A seed somebody chose must survive the match it was chosen for")
	assert_true(m.map_settings.seed_pinned)


# --- the civ draw follows the map --------------------------------------

func test_the_civ_draw_follows_the_map_seed() -> void:
	# Seeded from a constant, every lobby drew the same civs forever: the
	# seat DID resolve to a real civ, so the visible half worked.
	var drawn := {}
	for i in range(32):
		var m := MatchState.new()
		m.civ_seed_base = 0
		m.map_settings.pin_seed(i * 7919)
		m.reseed_civ_rng()
		drawn[String(CivRoster.resolve(CivRoster.RANDOM, m.civ_rng))] = true
	assert_gt(drawn.size(), 1,
		"Random should not resolve to the same civ on every map")


func test_the_same_seed_draws_the_same_civs() -> void:
	# What the pin buys beyond the terrain (D-016's replay obligation):
	# the same seed reproduces the whole match setup, not merely the
	# ground it is played on.
	var first: Array = []
	var second: Array = []
	for run in range(2):
		var m := MatchState.new()
		m.civ_seed_base = hash("standard")
		m.map_settings.pin_seed(4242)
		m.reseed_civ_rng()
		var out := first if run == 0 else second
		for i in range(8):
			out.append(String(CivRoster.resolve(CivRoster.RANDOM, m.civ_rng)))
	assert_eq(first, second, "One seed, one draw — a replay depends on it")


func test_two_maps_of_the_same_seed_still_draw_differently() -> void:
	# `civ_seed_base` is the map-independent half. Without it, every map
	# file of the same seed would field the same sides.
	var draws := {}
	for base in [hash("standard"), hash("skirmish"), hash("huge")]:
		var m := MatchState.new()
		m.civ_seed_base = base
		m.map_settings.pin_seed(4242)
		m.reseed_civ_rng()
		assert_eq(m.civ_rng.seed, base + 4242,
			"The draw's seed is the map's seed plus the map file's identity")
		draws[m.civ_rng.seed] = true
	assert_eq(draws.size(), 3, "Three map files should not share one sequence")


func test_a_rolled_lobby_redraws_its_civs() -> void:
	# The two halves joined up: a new map means a new draw, so a Random
	# seat is random per MATCH rather than random once, ever.
	var m := _running_match()
	var seeds := {}
	for i in range(24):
		m.return_to_lobby()
		seeds[m.civ_rng.seed] = true
		m.request_start(1)
	assert_gt(seeds.size(), 1,
		"A rolled map must carry its civ draw with it")


# --- what must NOT roll -------------------------------------------------

func test_a_headless_default_is_still_reproducible() -> void:
	# Bots, scenarios and every test recipe run seedless and want ONE
	# world, not a surprise. Nothing constructs a rolled seed: the roll is
	# something the server does for a lobby, deliberately.
	assert_eq(MapSettings.new().seed, MapSettings.DEFAULT_SEED,
		"A fresh MapSettings must be the reproducible default map")
	assert_false(MapSettings.new().seed_pinned,
		"and it is a default rather than a choice, so a lobby may roll it")
