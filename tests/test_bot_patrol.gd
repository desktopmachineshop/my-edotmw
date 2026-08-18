extends GutTest

## Guards D-20260817-load-test-bots-must-manoeuvre (#69, #84): `test-load`'s
## `reveal_events` gate asserts a manoeuvre, and the bots had stopped
## performing it — so the gate was unreachable on `main` and every session
## told to run it as its standing check had to attribute a red run first.
##
## The gate itself is D-026 criterion 9 and is right: a run in which nothing
## was ever hidden and shown again proves nothing about fog. What was wrong
## was underneath it, so that is what these tests hold:
##
##  - a bot's whole army is hauling crews, so a split that gives the economy
##    everything leaves nothing to scout with (the defect, exactly);
##  - a scout has to stand where the defender can SEE it and cannot SHOOT
##    it, or the return leg never happens and `reveal_events` stays zero for
##    a new reason. Asserted against the shipped town centre and the shipped
##    map, not against the constants' own comments (D-066: a mechanism being
##    right says nothing about whether the shipped numbers do anything);
##  - and the whole cycle has to fit inside the duration the docs tell
##    people to run, on the map they will run it on.
##
## Observed to fail before being trusted, per D-022's audit rule. Four
## perturbations, each reinstating a piece of the original defect, and what
## each one actually reddened:
##
##  - `assign` sparing nobody (`wanted := 0`, the haul loop taking
##    everything): `..._still_fields_scouts` and `..._keeps_the_majority`.
##  - `leg_target` returning the neighbour on every leg — march out, never
##    withdraw, which is the one-shot rally that shipped:
##    `..._alternates_out_and_back` and `..._produces_a_reveal`, the latter
##    at 0 of 4 pairs.
##  - `STANDOFF_CELLS := 4`, inside the town centre's guns:
##    `..._inside_the_defenders_sight_and_outside_its_guns`.
##  - `STANDOFF_CELLS := 14`, outside its sight: that one AND
##    `..._produces_a_reveal`, again at 0 of 4.
##  - `leg_done` judging whichever scout suits the current leg — the rule
##    that actually shipped for one run: `..._does_not_thrash`, at 600
##    flips in ten simulated seconds against a limit of 1.


## Where the load test's own server starts its players. Built the way
## `server.gd::_build_world` builds it for a headless run — `MapSettings`
## seeded from the map file, nothing seated, so `player_slots` is the file's
## 20 and the four bots take seats 0..3. A lobby match derives that number
## from its seats instead (D-20260817-starting-positions-follow-the-seats);
## the load test has no lobby.
func _spawn_points() -> Array:
	var config: MapConfig = load("res://maps/default.tres")
	var settings := MapSettings.from_map(config)
	var passable := settings.to_terrain().passability(settings.to_space())
	return settings.to_spawn_config().spawn_points(passable)


func _space() -> TorusSpace:
	return MapSettings.from_map(load("res://maps/default.tres")).to_space()


## World units -> cells, the conversion `Vision._range_in_cells` and
## `Combat._range_in_cells` both make. Written out rather than called
## because both are private to their own class; the arithmetic is one line
## and a test that disagreed with it would be caught by the assertions that
## use it.
func _cells(space: TorusSpace, world_range: float) -> int:
	return floori(world_range / (space.hex_size * TorusSpace.SQRT_3))


# --- the split: who works, who scouts ----------------------------------

func test_a_bot_whose_whole_army_hauls_still_fields_scouts() -> void:
	# The defect, in one assertion. A bot only ever builds a town centre and
	# a town centre `produces` gatherers only, so every squad it owns after
	# the founding party carries. The haul loop claimed all of them, which
	# left nothing for either the raid rotation or the rally — and the
	# bots spent every match standing still.
	var army := PackedInt32Array([3, 4, 5, 6])
	var split := BotPatrol.assign(army, -1)
	var scouts: Array = split["scouts"]
	var workers: Array = split["workers"]

	assert_false(scouts.is_empty(), "an army of four crews must spare somebody to scout")
	assert_false(workers.is_empty(), "and must keep somebody working")
	for squad in scouts:
		assert_false(workers.has(squad), "squad %d cannot both haul and scout" % squad)
	assert_eq(scouts.size() + workers.size(), army.size(),
		"every squad lands in exactly one half")


func test_the_economy_keeps_the_majority() -> void:
	# Scouting is paid for out of gathering, so the share matters: a bot that
	# sends everything out stops producing and the run ends with four crews
	# and no reveals for the opposite reason.
	for size in range(1, 9):
		var army := PackedInt32Array()
		for i in range(size):
			army.append(i + 3)
		var split := BotPatrol.assign(army, -1)
		var scouts: int = split["scouts"].size()
		assert_true(scouts <= size / BotPatrol.MAX_SCOUT_SHARE,
			"%d squads should spare at most %d scouts, spared %d" % [
				size, size / BotPatrol.MAX_SCOUT_SHARE, scouts])
		assert_true(scouts <= BotPatrol.SCOUTS_PER_BOT,
			"%d squads should never spare more than the detachment size" % size)
	assert_eq(BotPatrol.assign(PackedInt32Array([7]), -1)["scouts"].size(), 0,
		"a bot with one crew keeps it working")
	assert_eq(BotPatrol.assign(PackedInt32Array([7, 8]), -1)["scouts"].size(), 1,
		"the second crew is what starts the patrol")


func test_the_founding_party_is_never_sent_anywhere() -> void:
	# A move order cancels a pending build, and the founding party IS the
	# opening (D-031). The predecessor of this module rallied at t=0 s, when
	# the founder was the only squad a bot had, and recalled it at t=8 s —
	# which is how a mechanism written to produce conceals came to be spent
	# on the one squad that must not receive an order.
	var split := BotPatrol.assign(PackedInt32Array([0, 1, 2, 3]), 0)
	assert_false(split["scouts"].has(0), "the founder does not scout")
	assert_false(split["workers"].has(0), "and does not haul")
	assert_eq(BotPatrol.assign(PackedInt32Array([0]), 0)["scouts"].size(), 0,
		"a bot holding only its founding party patrols with nothing")


# --- the standoff: seen, and not shot ----------------------------------

func test_a_scout_stands_inside_the_defenders_sight_and_outside_its_guns() -> void:
	# Both halves are load-bearing and they pull in opposite directions.
	# Too far and the scout is never seen, so there is nothing to conceal;
	# too close and the town centre kills it (5 men at 35 HP against 42
	# damage a shot), so there is no return leg and `reveal_events` stays
	# zero for a new reason.
	var space := _space()
	var town_centre: BuildingDef = load("res://buildings/town_centre.tres")
	var sight := _cells(space, town_centre.vision_range)
	var reach := _cells(space, town_centre.attack_range)

	assert_true(BotPatrol.STANDOFF_CELLS <= sight,
		"a scout standing %d cells out must be inside the town centre's %d-cell sight" % [
			BotPatrol.STANDOFF_CELLS, sight])
	assert_true(BotPatrol.STANDOFF_CELLS > reach,
		"and outside its %d-cell reach, or it never comes back" % reach)
	assert_true(BotPatrol.WITHDRAW_CELLS > sight,
		"and a withdrawal has to end outside that %d-cell sight, or it conceals nothing" % sight)


func test_the_leg_ends_on_arrival_rather_than_on_the_clock() -> void:
	# "Latch on the effect, not the intent" (D-107). Every timing this file
	# replaces was tuned against an opening that later changed.
	var space := _space()
	var watching := Vector2i(38, 10)
	var far := [Vector2i(watching.x - BotPatrol.WITHDRAW_CELLS, watching.y)]
	var post := [Vector2i(watching.x - BotPatrol.STANDOFF_CELLS, watching.y)]

	assert_false(BotPatrol.leg_done(space, far, 0, watching, 0.0),
		"a scout still out at the withdrawal line has not closed on anything yet")
	assert_true(BotPatrol.leg_done(space, post, 0, watching, 0.0),
		"a scout at the standoff has, without any time having passed")
	assert_false(BotPatrol.leg_done(space, post, 1, watching, 0.0),
		"and it has not withdrawn while it is still standing there")
	assert_true(BotPatrol.leg_done(space, far, 1, watching, 0.0),
		"the withdrawal is over when the watcher has lost it")
	assert_true(BotPatrol.leg_done(space, far, 0, watching, BotPatrol.LEG_TIMEOUT_SECONDS),
		"and a scout that plainly is not going to arrive gives up eventually")
	assert_false(BotPatrol.leg_done(space, [], 0, watching, 0.0),
		"a detachment nobody can place yet decides nothing")


func test_a_detachment_split_across_the_map_does_not_thrash() -> void:
	# Found by running it. Judging the leg on whichever scout is nearest the
	# CURRENT destination reads as strictly more robust — one crew stuck in
	# a lake cannot stall the cycle — and it flips the leg on every frame:
	# with two scouts apart, the one at the outward post has arrived at the
	# very moment the one at base satisfies the withdrawal, so each leg is
	# finished by a different squad the instant it starts. Measured at
	# patrol_legs=1077 in a 120 s run against 10 for the same code judging
	# one squad.
	#
	# So this drives the real decision the way `bot_client.gd` does, for a
	# detachment in exactly that arrangement, and counts the flips.
	var space := _space()
	var watching := Vector2i(38, 10)
	var at_post := Vector2i(watching.x - BotPatrol.STANDOFF_CELLS, watching.y)
	var at_base := Vector2i(watching.x - BotPatrol.WITHDRAW_CELLS - 6, watching.y)
	var detachment := [at_post, at_base]

	var leg := 0
	var seconds_on_leg := 0.0
	var dt := 1.0 / 60.0
	var flips := 0
	for frame in range(600):  # ten seconds of polling, nobody moving
		if BotPatrol.leg_done(space, detachment, leg, watching, seconds_on_leg):
			leg += 1
			seconds_on_leg = 0.0
			flips += 1
		else:
			seconds_on_leg += dt
	assert_true(flips <= 1,
		"a stationary detachment flipped legs %d times in ten seconds — the cycle is judging whichever scout suits it" % flips)


func test_the_patrol_alternates_out_and_back() -> void:
	var space := _space()
	var watching := Vector2i(30, 40)
	var home := Vector2i(30 + BotPatrol.WITHDRAW_CELLS + 5, 40)
	assert_eq(space.distance(BotPatrol.leg_target(space, 0, home, watching), watching),
		BotPatrol.STANDOFF_CELLS, "leg 0 marches out to the observation post")
	assert_eq(BotPatrol.leg_target(space, 1, home, watching), home,
		"leg 1 withdraws to a base that is already out of sight")
	assert_eq(space.distance(BotPatrol.leg_target(space, 2, home, watching), watching),
		BotPatrol.STANDOFF_CELLS, "leg 2 goes out again")


func test_the_standoff_is_a_destination_not_a_distance_to_notice() -> void:
	# The lesson that cost a load run. A bot samples its own squads off a
	# clock it accumulates itself, against a curve the replicator clipped to
	# a one-second horizon, so "where is my scout" is ~2 cells stale. If the
	# outward DESTINATION were the neighbour's start, the scout would keep
	# walking while the bot decided it had arrived — and 2 cells past a
	# 9-cell standoff is 7, against a town centre that shoots at 6.
	# Measured: casualties_applied 56 -> 164 and one player eliminated.
	#
	# So the overshoot has to be absorbed by where the squad is SENT, not by
	# how promptly the bot notices. Asserted for every neighbour pair on the
	# shipped map, since the geometry is per-pair.
	var space := _space()
	var points := _spawn_points()
	var town_centre: BuildingDef = load("res://buildings/town_centre.tres")
	var reach := _cells(space, town_centre.attack_range)
	var sight := _cells(space, town_centre.vision_range)

	for bot in range(4):
		var home: Vector2i = points[bot]
		var watching: Vector2i = points[(bot + 1) % 4]
		var post := BotPatrol.leg_target(space, 0, home, watching)
		var apart := space.distance(post, watching)
		assert_true(apart > reach,
			"bot %d's post sits %d cells out, inside the %d-cell reach it is standing off from" % [
				bot + 1, apart, reach])
		assert_true(apart <= sight,
			"bot %d's post sits %d cells out, outside the %d cells that would see it" % [
				bot + 1, apart, sight])


func test_a_base_too_close_to_watch_from_is_withdrawn_past() -> void:
	# Starts scatter at a minimum spacing of 12 cells (D-039) against a town
	# centre that sees 11, so a pair can land closer than the watcher's
	# sight — "go home" is then not the same question as "get out of their
	# view", and it is the second one the conceal counts. Synthetic rather
	# than read off the shipped map, because which pairs are tight is a
	# property of the map and seed: it was 13 cells on the 84x96 map and is
	# 17 on the 168x194 one.
	var space := _space()
	var watching := Vector2i(30, 40)
	var near_home := Vector2i(30 + 13, 40)
	var target := BotPatrol.withdrawal_target(space, near_home, watching)
	assert_true(space.distance(target, watching) >= BotPatrol.WITHDRAW_CELLS,
		"a withdrawal from a base 13 cells out has to end further out than that")

	var far_home := Vector2i(30 + BotPatrol.WITHDRAW_CELLS + 8, 40)
	assert_eq(BotPatrol.withdrawal_target(space, far_home, watching), far_home,
		"a base that is already far enough is simply where they go")


# --- the gate itself, on the shipped map -------------------------------

## When a bot's SECOND crew exists, which is when it can first spare one.
## Measured, not guessed: on `just test-load 4 120` the server reports
## squads=4 (four founding parties) until 50 s, 8 at 60 s and 12 at 70 s —
## a town hall takes 40 s (D-031) and production runs after it. Rounded up
## to the later of those, so this test is not flattering itself.
const PATROL_CAN_START_AT := 70.0

## The duration `docs/status/load-testing.md` quotes for the CURRENT
## default map. It was 120 s until the map doubled on 2026-08-17 (84x96 ->
## 168x194) — marching time scales with LINEAR size, and this test went red
## on the pair that is now 93 cells apart, which is the check doing its job
## rather than a number needing a nudge.
const RUN_SECONDS := 300.0


## One scout's walk, in real cells on the real torus, at the shipped
## gatherer's speed. Deliberately not a distance countdown: the wrapped
## arithmetic is the part of a load test that has broken before.
func _step_toward(space: TorusSpace, here: Vector2i, target: Vector2i, cells: float) -> Vector2i:
	var offset := space.delta(here, target)
	var remaining := TorusSpace.hex_length(offset)
	if remaining <= cells:
		return space.normalize(target)
	return space.normalize(here + space.round_axial(Vector2(offset) * (cells / float(remaining))))


func test_a_run_of_the_documented_length_produces_a_reveal() -> void:
	# The headline. `reveal_events` needs a squad SEEN, then HIDDEN, then
	# SEEN AGAIN — the last fog criterion to be satisfied and the first to
	# fail. This walks the patrol at the shipped gatherer's speed, from the
	# moment a bot can first spare a crew, over the four starts the load
	# test's own server hands its four bots, and counts what the neighbour
	# would observe.
	var space := _space()
	var points := _spawn_points()
	assert_true(points.size() >= 4, "Setup: the shipped map seats four bots")

	var gatherers: UnitDef = load("res://units/gatherers.tres")
	var cells_per_second := gatherers.move_speed / (space.hex_size * TorusSpace.SQRT_3)
	var town_centre: BuildingDef = load("res://buildings/town_centre.tres")
	var sight := _cells(space, town_centre.vision_range)

	var dt := 0.5
	var pairs_revealing := 0
	for bot in range(4):
		# Players form a ring, so bot n watches bot n+1 — the same
		# neighbour `bot_client.gd` picks.
		var home: Vector2i = points[bot]
		var watching: Vector2i = points[(bot + 1) % 4]

		var here := home
		var leg := 0
		var leg_started_at := PATROL_CAN_START_AT
		var was_visible := false
		var concealed_once := false
		var reveals := 0
		var t := PATROL_CAN_START_AT
		while t < RUN_SECONDS:
			var target := BotPatrol.leg_target(space, leg, home, watching)
			here = _step_toward(space, here, target, cells_per_second * dt)
			t += dt
			if BotPatrol.leg_done(space, [here], leg, watching, t - leg_started_at):
				leg += 1
				leg_started_at = t

			# What the neighbour's town centre, sitting on its own start,
			# can see. The real thing also has crews with 10-unit sight, so
			# this understates the neighbour's coverage.
			var visible := space.distance(here, watching) <= sight
			if was_visible and not visible:
				concealed_once = true
			elif visible and not was_visible and concealed_once:
				reveals += 1
			was_visible = visible

		gut.p("bot %d: start %s watching %s (%d cells apart) — legs=%d reveals=%d" % [
			bot + 1, home, watching, space.distance(home, watching), leg, reveals])
		if reveals > 0:
			pairs_revealing += 1

	# EVERY pair, not "somebody managed it". The pairs are wildly uneven on
	# a map with randomly scattered starts (13 to 44 cells on the shipped
	# one), and a gate met by whichever pair got lucky is the flaky-at-zero
	# behaviour #69 reports rather than a fix for it.
	assert_eq(pairs_revealing, 4,
		"all four neighbour pairs must produce a reveal inside a %.0f s run — that is the gate #69 is about" % RUN_SECONDS)


func test_a_full_cycle_fits_in_the_run_for_every_pair() -> void:
	# The same claim as the simulation above, arrived at by arithmetic
	# instead, so a mistake in the walk model cannot make both agree. The
	# scout has to close from base to the standoff, withdraw, and close
	# again: seen, hidden, seen.
	var space := _space()
	var points := _spawn_points()
	var gatherers: UnitDef = load("res://units/gatherers.tres")
	var cells_per_second := gatherers.move_speed / (space.hex_size * TorusSpace.SQRT_3)
	var budget := RUN_SECONDS - PATROL_CAN_START_AT

	for bot in range(4):
		var apart := space.distance(points[bot], points[(bot + 1) % 4])
		var approach := float(maxi(apart, BotPatrol.WITHDRAW_CELLS) - BotPatrol.STANDOFF_CELLS)
		var cycle := float(BotPatrol.WITHDRAW_CELLS - BotPatrol.STANDOFF_CELLS) * 2.0
		var seconds := (approach + cycle) / cells_per_second
		assert_true(seconds <= budget,
			"bot %d watches a start %d cells away — %.0f s of walking against %.0f s left in the run" % [
				bot + 1, apart, seconds, budget])
