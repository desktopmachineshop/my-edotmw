extends GutTest

## Guards D-20260818-load-test-bots-must-field-an-army (#123): `test-load`'s
## bots built one town centre, trained gatherers out of it, and put every
## crew on a tree — so `raid_pool` was empty on every tick of every match
## and everything below `if raid_pool.is_empty(): return` was written,
## correct, called, and unreachable.
##
## The gate that catches this is `raid_orders > 0` in the verdict, and it
## can only be observed to fail against a live run — a bot is a SceneTree
## and GUT cannot stand up an ENet host, so the decision records that
## perturbation and its red run instead. What is testable here is the
## decision underneath it — what a bot builds and what it asks a building
## for — which is where every way of getting this wrong lives:
##
##  - asking a building for something it does not make (`ai_player.gd`
##    asked a barracks for the opening party's archetype for three
##    milestones and trained nothing but gatherers with a finished
##    barracks standing there);
##  - asking for something the CIV does not field, which is a refusal on
##    the wire rather than a unit;
##  - never stopping asking for gatherers, so one `squad_cap` covering
##    workers and soldiers alike (D-033) fills with workers — the ladder's
##    recorded "15 squads, 15 workers, 0 attacks";
##  - putting the building inside the town hall's `no_build_radius`, which
##    is refused every time and looks exactly like a bot that is simply
##    slow.
##
## Observed to fail before being trusted, and one of them had to be
## rewritten to earn that. Three perturbations, and what each reddened:
##
##  - `archetype_for` ignoring `hauling_crews`:
##    `..._stops_asking_for_crews_once_it_has_enough`.
##  - `wanted_building` dropping its `produces.is_empty()` filter:
##    `..._only_ever_wants_a_building_that_trains`, at six buildings.
##    **This one passed the first time it was perturbed** — the original
##    test asked for one answer, and `all_defs()` is alphabetical, so
##    "barracks" came back first whether the filter was there or not. A
##    check that green-lights the defect it exists for is worse than no
##    check; it walks the roster to exhaustion now.
##  - `building_site` ignoring the claimed radius:
##    `..._clears_every_claim_the_bot_already_has`, at every attempt.


func _space() -> TorusSpace:
	return MapSettings.from_map(load("res://maps/default.tres")).to_space()


func _hall() -> BuildingDef:
	return load("res://buildings/town_centre.tres")


# --- what to build -----------------------------------------------------

func test_a_bot_only_ever_wants_a_building_that_trains() -> void:
	# Walked to EXHAUSTION rather than asked once, and that is the whole
	# point of it. The first version of this test asserted only the first
	# answer, and stayed green with the `produces` filter deleted — because
	# `all_defs()` is alphabetical and "barracks" happens to sort first.
	# A test that passes by accident of filename order guards nothing; this
	# one keeps asking until there is nothing left to want, so a non-training
	# building anywhere in the roster is caught.
	var owned := ["town_centre"]
	var wanted := 0
	for _round in range(BuildingSim.all_defs().size() + 1):
		var def := BotBuildPlan.wanted_building(owned, &"gatherers")
		if def == null:
			break
		assert_false(def.produces.is_empty(),
			"a bot was told to raise %s, which trains nothing" % def.id)
		assert_true(BuildingSim.can_build(def, &"gatherers"),
			"and %s is not something its crews can raise" % def.id)
		assert_false(owned.has(String(def.id)),
			"a bot must not ask twice for %s" % def.id)
		owned.append(String(def.id))
		wanted += 1
	assert_true(wanted > 0,
		"a bot holding only a town centre must want something more")


func test_nothing_here_names_a_building() -> void:
	# The same rule `tests/test_civs.gd` applies to civs, for the same
	# reason: these are data ids. A roster that grows a stable should widen
	# what a bot builds with no code change.
	var source := FileAccess.get_file_as_string("res://bot_build_plan.gd")
	assert_ne(source, "", "Setup: bot_build_plan.gd should be readable")
	var code := ""
	for line in source.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	for def in BuildingSim.all_defs():
		assert_false(code.contains('&"%s"' % def.id),
			"bot_build_plan.gd names the building '%s' — it should discover it" % def.id)


# --- what to train -----------------------------------------------------

func test_a_building_is_only_asked_for_what_it_makes() -> void:
	# `ai_player.gd` records the cost of getting this wrong: it asked a
	# barracks for the opening party's archetype — a fighting unit with no
	# carry capacity, so it passed every test for "military" — and trained
	# nothing but gatherers for a whole match with a finished barracks
	# standing there.
	for civ in CivRoster.ids():
		for building_def in BuildingSim.all_defs():
			var archetype := BotBuildPlan.archetype_for(building_def, civ, 0)
			if archetype == &"":
				continue
			assert_true(building_def.produces.has(archetype),
				"%s was asked for %s, which it does not produce" % [building_def.id, archetype])
			assert_not_null(UnitRoster.for_civ_archetype(civ, archetype),
				"%s does not field %s, so asking for it is a refusal not a unit" % [civ, archetype])


func test_every_civ_can_field_a_soldier_from_what_it_can_build() -> void:
	# The shipped-numbers half (D-066). A plan that is right in the abstract
	# and produces no soldier on the real roster leaves `raid_pool` exactly
	# as empty as before.
	for civ in CivRoster.ids():
		var fighters := 0
		for building_def in BuildingSim.all_defs():
			if not BuildingSim.can_build(building_def, &"gatherers") \
					and building_def.id != &"town_centre":
				continue
			var archetype := BotBuildPlan.archetype_for(building_def, civ, 0)
			if archetype == &"":
				continue
			var unit := UnitRoster.for_civ_archetype(civ, archetype)
			if unit != null and unit.carry_capacity <= 0:
				fighters += 1
		assert_true(fighters > 0,
			"%s can raise nothing that trains a squad the haul loop will not claim" % civ)


func test_a_bot_stops_asking_for_crews_once_it_has_enough() -> void:
	# One `squad_cap` covers workers and soldiers alike (D-033), so a bot
	# that trains gatherers forever fills the cap with them and fields no
	# army — which reads as an AI too passive to attack rather than as an
	# economy with no brakes.
	var hall := _hall()
	assert_false(hall.produces.is_empty(), "Setup: a town centre trains something")

	var civ: StringName = CivRoster.ids()[0]
	assert_ne(BotBuildPlan.archetype_for(hall, civ, 0), &"",
		"a bot with no crews asks its hall for some")
	assert_eq(BotBuildPlan.archetype_for(hall, civ, BotBuildPlan.MAX_HAULING_CREWS), &"",
		"a bot at the crew cap asks its hall for nothing")

	# And the cap must not silence a building that trains soldiers.
	var barracks := BotBuildPlan.wanted_building(["town_centre"], &"gatherers")
	assert_not_null(barracks, "Setup: there is a military building")
	assert_ne(BotBuildPlan.archetype_for(barracks, civ, BotBuildPlan.MAX_HAULING_CREWS), &"",
		"the crew cap must not stop a bot training soldiers")


# --- what it costs and where it goes -----------------------------------

func test_a_bot_does_not_order_what_it_cannot_pay_for() -> void:
	# The cost is charged on ARRIVAL (`server.gd::_finish_build`), so an
	# unaffordable order is a crew walking ten cells to be turned away — and
	# the bot cannot tell that from a crew still walking.
	var barracks := BotBuildPlan.wanted_building(["town_centre"], &"gatherers")
	assert_not_null(barracks, "Setup: there is a military building")
	var empty := PackedInt32Array([0, 0, 0, 0])
	assert_false(BotBuildPlan.can_afford(empty, barracks),
		"an empty wallet buys nothing")
	var rich := PackedInt32Array([9999, 9999, 9999, 9999])
	assert_true(BotBuildPlan.can_afford(rich, barracks), "a full one buys it")
	assert_false(BotBuildPlan.can_afford(PackedInt32Array([0, 0]), barracks),
		"a wallet that has not arrived yet buys nothing either")


func test_a_site_clears_every_claim_the_bot_already_has() -> void:
	# `no_build_radius` denies a disk around every building to anyone not
	# allied with its owner, and a bot's own hall is on its start. A site
	# inside it is refused every time, which looks exactly like a bot that
	# is merely slow.
	var space := _space()
	var hall := _hall()
	var barracks := BotBuildPlan.wanted_building(["town_centre"], &"gatherers")
	assert_not_null(barracks, "Setup: there is a military building")
	var home := Vector2i(40, 40)

	for attempt in range(12):
		var site := BotBuildPlan.building_site(space, home, barracks,
			BotBuildPlan.claimed_radius_of(["town_centre"]), attempt)
		assert_true(space.distance(site, home) > hall.no_build_radius,
			"attempt %d put the site %d cells out, inside the hall's %d-cell claim" % [
				attempt, space.distance(site, home), hall.no_build_radius])


func test_successive_attempts_ask_for_different_ground() -> void:
	# Retrying the same refused cell forever is a loop, not a fix — the
	# lesson the town hall's own retry is built on.
	var space := _space()
	var hall := _hall()
	var barracks := BotBuildPlan.wanted_building(["town_centre"], &"gatherers")
	var home := Vector2i(40, 40)
	var seen := {}
	for attempt in range(6):
		seen[BotBuildPlan.building_site(space, home, barracks,
			BotBuildPlan.claimed_radius_of(["town_centre"]), attempt)] = true
	assert_true(seen.size() >= 5,
		"six attempts asked for only %d distinct sites" % seen.size())


func test_a_bot_that_does_not_know_its_civ_still_asks_for_soldiers() -> void:
	# Every load-test bot is in this position, in every run. `server.gd`
	# broadcasts the lobby only while there IS a lobby and `test-load` starts
	# a match without one, so `ClientState.civ_of` answers "" throughout.
	#
	# Resolving strictly per civ found gatherers — `civ = &"neutral"`, so
	# they match anybody — and nothing else. Measured before this was fixed:
	# two bots raised a barracks at 137 s and 193 s and trained not one
	# soldier from either, `military_peak=0`, while the town centre went on
	# making crews.
	var barracks := BotBuildPlan.wanted_building(["town_centre"], &"gatherers")
	assert_not_null(barracks, "Setup: there is a military building")
	var archetype := BotBuildPlan.archetype_for(barracks, &"", 0)
	assert_ne(archetype, &"",
		"a bot with no civ must still ask a barracks for something")
	assert_true(barracks.produces.has(archetype),
		"and for something it makes — asked for %s" % archetype)

	# The crew cap still has to work without a civ, or a bot fills the
	# squad cap with workers and the army never appears for the other reason.
	var hall: BuildingDef = load("res://buildings/town_centre.tres")
	assert_ne(BotBuildPlan.archetype_for(hall, &"", 0), &"",
		"a bot with no civ and no crews still asks its hall for some")
	assert_eq(BotBuildPlan.archetype_for(hall, &"", BotBuildPlan.MAX_HAULING_CREWS), &"",
		"and still stops at the cap")


func test_a_named_civ_is_never_handed_another_civs_unit() -> void:
	# `_resolve`'s any-civ fallback exists for the CIV-LESS load-test bot,
	# which never learns its civ. Applied to a caller that names one it
	# hands back somebody else's unit, and the server then refuses the
	# order (D-047 resolves per civ) — which reads as a bot that will not
	# train rather than as a bad lookup.
	#
	# Latent until the naval roster, because `archetype_for` returns the
	# first entry of `produces` that resolves and every pre-naval building
	# lists a universal archetype first. A dock offers `warship` first and
	# two civs field a `warboat` instead.
	for civ in CivRoster.ids():
		for building_def in BuildingSim.all_defs():
			var archetype := BotBuildPlan.archetype_for(building_def, civ, 0)
			if archetype == &"":
				continue
			var def := UnitRoster.for_civ_archetype(civ, archetype)
			assert_not_null(def,
				"%s asked %s for %s, which it does not field" % [
					civ, building_def.id, archetype])
			if def != null:
				assert_true(String(def.civ) == String(civ) or String(def.civ) == "neutral",
					"%s asked %s for %s and got %s's unit" % [
						civ, building_def.id, archetype, def.civ])


func test_the_civ_less_bot_still_gets_an_answer() -> void:
	# The other half, and the reason the fallback is narrowed rather than
	# deleted: with no civ a bot must still be able to size a request, or
	# `test-load` stops fielding an army at all (#123).
	var asked := 0
	for building_def in BuildingSim.all_defs():
		if building_def.produces.is_empty():
			continue
		var archetype := BotBuildPlan.archetype_for(building_def, &"", 0)
		if archetype == &"":
			continue
		asked += 1
		assert_true(building_def.produces.has(archetype),
			"%s was asked for %s, which it does not produce" % [building_def.id, archetype])
	assert_gt(asked, 0, "a civ-less bot must still be able to ask for something")
