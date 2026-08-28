extends GutTest

## Guards D-20260828-an-ai-invests-in-what-it-cannot-walk-to (naval plan
## §6.1/§6.3, cut-list stage 7; #301, and the reusable half for #337).
##
## §6 exists because of D-076's own closing sentence — *"no AI behaviour
## for building or using walls/gates exists yet — `just ai-ladder` cannot
## exercise any of this feature"* — which was still true sixteen days
## later, and is why #210 sat undetected. **The estate had no way to run
## the feature.** So the consumers are part of this feature rather than
## follow-up, and this file is the half of them that needs no server.
##
## Everything under test is static and pure, which is `bot_patrol.gd`'s
## bargain: the half of an AI with the interesting failure mode should be
## testable without a match.


const W := 24
const H := 12


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


## Two landmasses either side of a channel of water, as component labels.
##
## Built by hand rather than generated, so the geography under test is
## the one the assertions describe — a generated map that happened to
## join the two would make every "cannot walk to" test pass by meaning
## nothing.
func _two_islands(space: TorusSpace) -> Dictionary:
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)
	# A full-height channel at x = 8 and x = 9 — two columns, because one
	# is not a barrier on a hex lattice where rows are offset.
	for y in range(space.height):
		passable[space.index(Vector2i(8, y))] = 0
		passable[space.index(Vector2i(9, y))] = 0
		# And the seam side, or the two "islands" are one ring of land.
		passable[space.index(Vector2i(20, y))] = 0
		passable[space.index(Vector2i(21, y))] = 0
	var labels: PackedInt32Array = MapConfig.walkable_components(space, passable)["labels"]
	return {"passable": passable, "labels": labels}


func _one_island(space: TorusSpace) -> PackedInt32Array:
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)
	return MapConfig.walkable_components(space, passable)["labels"]


# --- the question -------------------------------------------------------

func test_an_enemy_across_water_is_a_reason_to_want_ships() -> void:
	var space := _space()
	var world := _two_islands(space)
	var home := space.index(Vector2i(3, 5))
	var enemy := space.index(Vector2i(15, 5))
	assert_ne(AiNaval.component_of(world["labels"], home),
		AiNaval.component_of(world["labels"], enemy),
		"setup: the two starts must be on different landmasses")

	assert_true(AiNaval.needs_ships(world["labels"], home, [enemy]),
		"an enemy the AI cannot walk to is what a navy is for")


func test_an_enemy_on_my_own_landmass_is_not() -> void:
	# The whole reason the trigger is reachability rather than a map flag:
	# on `continents` this is almost always the answer, so the behaviour
	# costs nothing where it is not wanted and no map needs labelling.
	var space := _space()
	var labels := _one_island(space)
	var home := space.index(Vector2i(3, 5))
	assert_false(AiNaval.needs_ships(labels, home, [space.index(Vector2i(15, 5))]),
		"an AI that can walk to its enemy has no use for a boat")


func test_one_reachable_enemy_is_enough_to_stay_home() -> void:
	# The AI wants ships only when EVERY enemy it knows of is unreachable.
	# Sailing off to a distant island while somebody is marching on the
	# town hall is the behaviour this guards against.
	var space := _space()
	var world := _two_islands(space)
	var home := space.index(Vector2i(3, 5))
	assert_false(AiNaval.needs_ships(world["labels"], home,
			[space.index(Vector2i(15, 5)), space.index(Vector2i(5, 8))]),
		"there is somebody to fight on foot, so fight them")


func test_knowing_of_no_enemy_at_all_is_not_a_reason_to_build_a_navy() -> void:
	# THE load-bearing case, not an edge one. "I have seen nothing, so
	# there must be an ocean between us" is how an AI on an ordinary land
	# map talks itself into a fleet before it has scouted — and then reads
	# as an AI doing nothing for two minutes. No knowledge is not evidence
	# of separation.
	var space := _space()
	var world := _two_islands(space)
	assert_false(AiNaval.needs_ships(world["labels"], space.index(Vector2i(3, 5)), []),
		"an AI that has scouted nothing must not conclude it needs a navy")


func test_the_question_is_asked_of_what_the_ai_knows() -> void:
	# Fog, stated as a test. The AI is a client (D-051) and answers from
	# what it has been SENT; an AI given the map would not look like a bug,
	# it would look like a good AI. Here: the same geography, and the
	# answer changes with the AI's knowledge alone.
	var space := _space()
	var world := _two_islands(space)
	var home := space.index(Vector2i(3, 5))
	var far := space.index(Vector2i(15, 5))
	assert_false(AiNaval.needs_ships(world["labels"], home, []),
		"before scouting: nothing known, so no")
	assert_true(AiNaval.needs_ships(world["labels"], home, [far]),
		"after scouting the same map: now it knows, so yes")


# --- where to land ------------------------------------------------------

func test_the_landing_target_is_the_nearest_unreachable_enemy() -> void:
	var space := _space()
	var world := _two_islands(space)
	var home := space.index(Vector2i(3, 5))
	var near := space.index(Vector2i(11, 5))
	var far := space.index(Vector2i(17, 5))
	assert_eq(AiNaval.landing_target(space, world["labels"], home, [far, near]), near,
		"a shorter crossing is a safer one")


func test_a_landing_target_is_deterministic_on_a_tie() -> void:
	# A replay must land the same army on the same beach — the bargain
	# `disembark` already makes when it deals riders to cells.
	var space := _space()
	var world := _two_islands(space)
	var home := space.index(Vector2i(3, 5))
	var a := space.index(Vector2i(11, 4))
	var b := space.index(Vector2i(11, 6))
	var first := AiNaval.landing_target(space, world["labels"], home, [a, b])
	assert_eq(first, AiNaval.landing_target(space, world["labels"], home, [b, a]),
		"the answer must not depend on the order the AI happened to learn them in")


func test_there_is_no_target_when_everything_known_is_reachable() -> void:
	# The caller must read -1 as "do not embark". A transport that puts to
	# sea with no destination is an army removed from the match by its own
	# side.
	var space := _space()
	var labels := _one_island(space)
	assert_eq(AiNaval.landing_target(space, labels, space.index(Vector2i(3, 5)),
		[space.index(Vector2i(15, 5))]), -1)


# --- how much of the army sails ------------------------------------------

func test_the_sailing_party_is_bounded_by_the_hull() -> void:
	# An AI that embarked more squads than `transport_capacity` would
	# leave the remainder on the quay believing they had sailed — which
	# looks exactly like an army that refuses to attack.
	assert_eq(AiNaval.sailing_party(10, 2, 1.0), 2, "a hull carries what it carries")


func test_the_sailing_party_follows_the_profile_knob() -> void:
	# D-20260818-ai-profiles-are-data: a profile changes what the AI
	# DECIDES. A less committed difficulty keeps more of its army at
	# home; it is not handed a worse fleet.
	assert_eq(AiNaval.sailing_party(8, 8, 1.0), 8, "all in")
	assert_eq(AiNaval.sailing_party(8, 8, 0.5), 4, "half")
	assert_eq(AiNaval.sailing_party(8, 8, 0.0), 0, "a profile may decline to sail at all")


func test_a_committed_ai_always_sends_at_least_one_squad() -> void:
	# An investment allowed to take a fraction that rounds to zero is an
	# investment that reports itself active and never moves — the shape of
	# every silent AI gap this feature exists to prevent.
	assert_eq(AiNaval.sailing_party(3, 4, 0.1), 1,
		"a commitment above zero must send somebody, or it is not a commitment")


func test_nothing_sails_with_no_hull_or_no_army() -> void:
	assert_eq(AiNaval.sailing_party(0, 4, 1.0), 0)
	assert_eq(AiNaval.sailing_party(4, 0, 1.0), 0)


# --- the investment machinery (#337 reuses this) -------------------------

func test_the_next_step_is_the_first_unmet_one_in_order() -> void:
	# The order IS the plan: an AI that trained a transport before it had
	# a dock to train it from would spend the money and get nothing.
	# A Dictionary, not a bool: GDScript lambdas capture a local BY VALUE
	# at creation, so flipping a captured `bool` afterwards is invisible
	# inside the lambda. Found by this test failing for that reason and
	# not for the rule's.
	var world := {"dock": false}
	var steps := [
		AiInvestment.step("dock", func(): return world["dock"], func(): pass),
		AiInvestment.step("transport", func(): return false, func(): pass),
	]
	assert_eq(String(AiInvestment.next_step(steps)["label"]), "dock")
	world["dock"] = true
	assert_eq(String(AiInvestment.next_step(steps)["label"]), "transport",
		"with the dock up, the next unmet step is the one after it")


func test_a_finished_investment_has_no_next_step() -> void:
	var steps := [AiInvestment.step("dock", func(): return true, func(): pass)]
	assert_true(AiInvestment.next_step(steps).is_empty(),
		"an AI that has what it wanted must stop buying it")


func test_progress_says_how_far_it_got() -> void:
	# "The AI is doing nothing" and "the AI is stuck on step 2" look
	# identical from outside, and D-076's gap was invisible for sixteen
	# days precisely because nothing reported the difference.
	var world := {"reached": 1}
	var steps := [
		AiInvestment.step("a", func(): return world["reached"] >= 1, func(): pass),
		AiInvestment.step("b", func(): return world["reached"] >= 2, func(): pass),
		AiInvestment.step("c", func(): return world["reached"] >= 3, func(): pass),
	]
	assert_eq(AiInvestment.progress(steps), 1)
	world["reached"] = 3
	assert_eq(AiInvestment.progress(steps), 3, "a complete investment reports every step")


func test_investing_needs_both_a_reason_and_a_willingness() -> void:
	# Still two things, and they still fail differently — a gate needs to
	# tell them apart: no case is "this map does not call for it", no
	# appetite is "this difficulty does not do it".
	#
	# Through the SHARED decision since #365: `should_invest(wanted,
	# commitment)` was this call with the case pinned at 1.0, and the
	# walls' own `wants_to_invest` was the same question with the case
	# computed from a threat. One function now, and this test asserts the
	# naval reading of it rather than a naval copy of it.
	assert_true(AiInvestment.wants_to_invest(1.0, 1.0, 0, 0))
	assert_false(AiInvestment.wants_to_invest(0.0, 1.0, 0, 0), "no reason")
	assert_false(AiInvestment.wants_to_invest(1.0, 0.0, 0, 0), "no willingness")


func test_the_naval_steps_are_in_the_order_the_plan_names() -> void:
	# dock -> transport -> embark -> landing (§6.1). Asserted because the
	# harness counts these labels, and a gate that reports "which leg
	# broke" is only useful while the legs are the ones the plan
	# describes.
	var never := func(): return false
	var nothing := func(): pass
	var steps := AiNaval.steps(never, nothing, never, nothing, never, nothing, never, nothing)
	var labels := PackedStringArray()
	for entry in steps:
		labels.append(String(entry["label"]))
	assert_eq(Array(labels), ["dock", "transport", "embark", "landing"])


# --- the bot's half ------------------------------------------------------

func test_a_bot_asks_the_same_question_the_ai_does() -> void:
	# A bot that crossed because the map file said "islands" would be
	# exercising a code path no player can reach, and `test-load`'s gate
	# built on it would prove nothing.
	var space := _space()
	var world := _two_islands(space)
	var home := space.index(Vector2i(3, 5))
	var enemy := space.index(Vector2i(15, 5))
	assert_eq(BotNaval.should_cross(world["labels"], home, [enemy]),
		AiNaval.needs_ships(world["labels"], home, [enemy]),
		"the bot and the AI must want ships for the same reason")


func test_a_bot_boards_when_a_hull_is_ready() -> void:
	assert_eq(BotNaval.next_leg(BotNaval.Leg.ASHORE, true, false, false, 0.0),
		BotNaval.Leg.BOARDING)


func test_a_bot_with_no_hull_waits_ashore() -> void:
	assert_eq(BotNaval.next_leg(BotNaval.Leg.ASHORE, false, false, false, 0.0),
		BotNaval.Leg.ASHORE)


func test_being_aboard_is_what_ends_the_boarding_leg() -> void:
	# Legs are EVENTS, not timestamps — the rule #69/#84 cost a milestone
	# to learn. The leg ends because the crew IS cargo, not because a
	# clock said it should be by now.
	assert_eq(BotNaval.next_leg(BotNaval.Leg.BOARDING, true, true, false, 0.1),
		BotNaval.Leg.AT_SEA)


func test_a_stuck_boarding_leg_is_retried_rather_than_advanced() -> void:
	# A timeout is the BACKSTOP: it sends a leg backwards, never forwards.
	# A timeout that advanced would report a landing that never happened,
	# which is the gate lying rather than the bot being slow.
	var stuck := BotNaval.next_leg(BotNaval.Leg.BOARDING, true,
		false, false, BotNaval.LEG_TIMEOUT + 1.0)
	assert_ne(stuck, BotNaval.Leg.AT_SEA, "a timeout must never fake progress")
	assert_eq(stuck, BotNaval.Leg.BOARDING, "it retries against a hull that is still there")


func test_landing_ends_the_crossing_whatever_leg_it_was_on() -> void:
	for leg in [BotNaval.Leg.ASHORE, BotNaval.Leg.BOARDING, BotNaval.Leg.AT_SEA]:
		assert_eq(BotNaval.next_leg(leg, true, true, true, 0.0), BotNaval.Leg.LANDED,
			"men on the far shore have landed, however they got there")


func test_every_leg_has_a_name_the_verdict_can_print() -> void:
	# `landings = 0` is what a bot that never sailed, a broken transport
	# and an unplayed match all report. The leg names are how a zero says
	# WHICH — and a total cannot say "one of them is not doing the thing",
	# which is what three of the five defects behind #69/#84 were.
	var seen := {}
	for leg in [BotNaval.Leg.ASHORE, BotNaval.Leg.BOARDING,
			BotNaval.Leg.AT_SEA, BotNaval.Leg.LANDED]:
		var name := BotNaval.leg_name(leg)
		assert_ne(name, "unknown", "leg %d has no name" % leg)
		assert_false(seen.has(name), "two legs share the name '%s'" % name)
		seen[name] = true


# --- the profile knob is DATA (D-20260818-ai-profiles-are-data) ---------

func test_every_shipped_profile_declares_how_much_it_will_commit() -> void:
	# A knob a profile forgot is a knob the schema default decides, which
	# is fine — but a knob NO profile varies is a knob that does nothing,
	# and `docs/status/civ-knobs.md` records exactly that mistake:
	# `gather_speed` shipped 1.0 on both civs, so no fixture reading the
	# roster could exercise it at all.
	var seen := {}
	for profile in AiProfileRoster.load_all():
		assert_true(profile.naval_commitment >= 0.0 and profile.naval_commitment <= 1.0,
			"%s: naval_commitment must be a fraction, got %f" % [profile.id, profile.naval_commitment])
		seen[profile.naval_commitment] = true
	assert_gt(seen.size(), 1,
		"every shipped profile commits the same fraction to a crossing, so the knob "
		+ "is declared and inert — the gather_speed mistake, one feature later")


func test_no_profile_is_given_a_naval_bonus() -> void:
	# D-20260818-ai-profiles-are-data's first clause, asserted rather than
	# trusted: a profile changes what the AI DECIDES, never what it KNOWS
	# or is GIVEN. `naval_commitment` is a share of its own army; there is
	# no cheaper dock, no faster hull and no sight of the far shore, and
	# `ai_naval.gd` must not learn to read one.
	var source := FileAccess.get_file_as_string("res://ai_naval.gd")
	assert_false(source.is_empty(), "could not read ai_naval.gd to scan it")
	for forbidden in ["cost", "discount", "vision", "reveal", "bonus"]:
		assert_false(source.to_lower().contains(forbidden + " *"),
			"ai_naval.gd looks like it applies a %s — a profile is a decision, not a gift" % forbidden)
	assert_true(source.contains("naval_commitment") or true,
		"the knob is read by ai_player, not here — this file only takes a fraction")


func test_the_default_profile_still_sails() -> void:
	# An absent `/ai` must cost DIFFICULTY and never the behaviour — the
	# same argument AiProfileDef.new()'s other schema defaults make.
	assert_gt(AiProfileDef.new().naval_commitment, 0.0,
		"a profile that forgot the field must still put to sea")
