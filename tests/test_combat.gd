extends GutTest

## Guards Combat (D-024's squad-level stochastic model), the morale/rout
## half of D-019, the casualty-replication half of D-006 ("combat outcomes
## replicate as sparse reliable events, not continuous per-soldier
## state"), and D-016's replay coverage of combat. Specifically written
## against D-026's M2 exit criteria 1, 2, 3, 4, 9, 11 and 12:
##
##  1. Combat is squad-level and stochastic, server-only.
##  2. Deterministic given a seed: the same inputs run twice produce an
##     identical sequence of strengths.
##  3. Casualties replicate as sparse reliable events — zero bytes when
##     nothing changed, proven by a byte count, not by inspection.
##  4. Morale and routing exist at squad level, with rally as the path
##     back.
##  9. Every new check here was observed to fail before being trusted (see
##     the final report, not this file — GUT has no "expect fail" mode,
##     so the perturbation was done by hand and reverted).
## 11. Replays cover combat: casualty/rout events land in the log and
##     reconstruction reports final strengths.
## 12. New tuning lives in UnitDef fields (this file never hardcodes a
##     combat constant it could instead set on a UnitDef).


const W := 32
const H := 16
const REPLAY_PATH := "user://test-combat-replay.edmw"


func after_each() -> void:
	if FileAccess.file_exists(REPLAY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REPLAY_PATH))


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


## A squad that deals real damage but takes essentially none back
## (high health), so tests about "the defender takes casualties" don't
## also have to reason about the attacker's own strength changing.
## attack_range = 3.0 world units converts to ~1.73 cells (the hex width
## at hex_size 1.0), so it reaches an adjacent cell (distance 1) but not
## a cell two away (distance 2) — the in-range/out-of-range line the
## first two tests sit on either side of.
func _attacker_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"combat_test_attacker"
	d.squad_size = 20
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	d.health = 100.0
	d.damage = 2.0
	d.attack_range = 3.0
	d.attack_interval = 0.1  # one 10 Hz tick — attacks every round
	d.morale = 100.0
	d.rout_threshold = 25.0
	d.rout_rally_margin = 15.0
	d.morale_recovery_per_second = 2.0
	d.morale_loss_per_casualty = 4.0
	d.damage_variance = 0.0  # deterministic magnitude for easy arithmetic
	return d


## Same shape, but fragile: low health so the attacker's fixed damage
## output reliably produces several casualties per hit, and fast morale
## recovery so the rally test doesn't need an unreasonable tick budget.
func _defender_def() -> UnitDef:
	var d := _attacker_def()
	d.id = &"combat_test_defender"
	d.health = 10.0
	d.rout_threshold = 50.0
	d.morale_recovery_per_second = 50.0
	d.morale_loss_per_casualty = 8.0
	return d


## Both sides actually stochastic (nonzero variance), for the determinism
## test — the point there is that the ROLL reproduces, not just fixed
## arithmetic that would reproduce trivially either way.
func _stochastic_def(id: StringName) -> UnitDef:
	var d := _attacker_def()
	d.id = id
	d.health = 40.0
	d.damage_variance = 0.6
	return d


## Mirrors server.gd's own gating: a combat message is sent only when the
## event list is non-empty, and the bytes are NetProtocol's own encoding.
## Used instead of asserting on server.gd directly, since server.gd needs
## a live ENet host to exercise — this is the same wire encoding it sends.
func _combat_wire_bytes(events: Array) -> int:
	if events.is_empty():
		return 0
	return NetProtocol.encode_squad_combat(0, events).size()


## Two squads that are identical in every respect, for the simultaneity
## test. `damage_variance` is zero deliberately: the stochastic roll is a
## function of squad id, so with variance the two would legitimately deal
## different damage and the test could not tell an unfair resolution ORDER
## apart from an ordinary unlucky roll. Morale loss is zero so neither
## routs and walks away mid-test — this is about ordering, not morale.
func _mirror_def() -> UnitDef:
	var d := _attacker_def()
	d.id = &"combat_test_mirror"
	d.health = 20.0
	d.morale_loss_per_casualty = 0.0
	d.damage_variance = 0.0
	return d


# --- simultaneous resolution (D-024 amendment, D-027 criterion 14) -----

func test_mirror_matchup_is_symmetric_not_won_by_the_lower_squad_id() -> void:
	# Combat used to resolve in squad-id order against live state, so the
	# lower id struck first at full strength and its enemy answered
	# weakened. Identical unit types share an attack_interval and both
	# start at _last_attack_tick = -1, so they fire on the same ticks
	# forever and the bias never averages out — player 1 would
	# systematically win mirror engagements.
	var sim := _sim()
	var def := _mirror_def()
	var first := sim.add_squad(def, 1, Vector2i(5, 5))
	var second := sim.add_squad(def, 2, Vector2i(6, 5))  # adjacent: in range

	for _i in range(5):
		sim.tick()

	# Both halves matter: a fight that never started, or one that ended in
	# mutual annihilation, would satisfy the equality below while proving
	# nothing about resolution order.
	assert_lt(sim.alive_of(first), def.squad_size, "Setup: the two squads must actually be fighting")
	assert_gt(sim.alive_of(first), 0, "Setup: the fight must still be in progress, not over")

	assert_eq(sim.alive_of(first), sim.alive_of(second),
		"Two identical squads must take identical losses — squad id must not confer a first strike")


func test_simultaneity_does_not_depend_on_which_side_has_the_lower_id() -> void:
	# The same engagement with the owners swapped must produce the same
	# outcome. If resolution order still leaked into the result, swapping
	# which player owns the lower id would change who wins.
	var sim := _sim()
	var def := _mirror_def()
	var a := sim.add_squad(def, 2, Vector2i(5, 5))  # player 2 now holds the LOWER id
	var b := sim.add_squad(def, 1, Vector2i(6, 5))

	for _i in range(5):
		sim.tick()

	assert_eq(sim.alive_of(a), sim.alive_of(b),
		"Swapping which player owns the lower squad id must not change the outcome")


# --- reach (D-024) -----------------------------------------------------

func test_every_armed_unit_can_reach_an_adjacent_cell() -> void:
	# A hex is SQRT_3 (~1.73) world units across, so any attack_range
	# below that floors to a radius of ZERO cells — the unit can only
	# attack something standing in its own cell, which for a melee unit
	# means it can never attack anything at all.
	#
	# Every melee unit in the roster shipped that way. It stayed invisible
	# for two milestones because the opening spawned archers, whose range
	# of 8.0 is nearly five hexes; it surfaced the moment the starting
	# unit became a melee founding party and combat silently stopped
	# happening at load.
	var hex_width := TorusSpace.SQRT_3  # every shipped map uses hex_size 1.0
	for def in UnitRoster.load_all():
		if def.damage <= 0.0:
			continue
		assert_true(floori(def.attack_range / hex_width) >= 1,
			"%s has attack_range %.2f, under one hex width (%.2f) — it could only ever attack its own cell" % [
				def.id, def.attack_range, hex_width])


# --- counters (D-032, D-027 criterion 13) ------------------------------

## Runs one engagement and returns the defender's surviving strength.
## Same setup both times apart from the attacker's counter table, so the
## difference in outcome is attributable to the counter and nothing else.
func _survivors_after_engagement(bonus: Dictionary) -> int:
	var sim := _sim()

	var attacker_def := _attacker_def()
	attacker_def.damage_variance = 0.0
	attacker_def.bonus_vs = bonus

	var defender_def := _defender_def()
	defender_def.armour_class = "infantry"
	defender_def.damage = 0.0  # doesn't hit back; this is about one direction
	defender_def.morale_loss_per_casualty = 0.0  # and doesn't rout away

	sim.add_squad(attacker_def, 1, Vector2i(5, 5))
	var defender := sim.add_squad(defender_def, 2, Vector2i(6, 5))

	for _i in range(3):
		sim.tick()
	return sim.alive_of(defender)


func test_counter_multiplier_changes_the_outcome() -> void:
	var without_bonus := _survivors_after_engagement({})
	var with_bonus := _survivors_after_engagement({"infantry": 2.0})

	# The mechanism has to be visible in casualties, not merely present in
	# the data. A counter system nothing verifies is decoration.
	assert_lt(with_bonus, without_bonus,
		"A unit with a bonus against the defender's armour class must kill more of it")


func test_a_bonus_against_a_different_class_does_nothing() -> void:
	# Guards the lookup itself: a bonus keyed to a class the defender is
	# NOT would silently apply if the code ignored the key.
	assert_eq(_survivors_after_engagement({"cavalry": 2.0}), _survivors_after_engagement({}),
		"A bonus against cavalry must not apply to an infantry defender")


func test_shipped_roster_has_a_real_counter_triangle() -> void:
	# D-015's cut line asks for 3-4 unit types; four types with no
	# counters between them would meet the letter of it and none of the
	# point. This checks the shipped .tres data, not a fixture.
	# Keyed on ARCHETYPE, not unit id (D-047): every civ has its own
	# spearmen, and the triangle has to hold for all of them. Checking one
	# civ's would let a civ added later quietly ship archers that lose to
	# infantry.
	var by_archetype := {}
	for def in UnitRoster.load_all():
		if not by_archetype.has(String(def.archetype)):
			by_archetype[String(def.archetype)] = []
		by_archetype[String(def.archetype)].append(def)

	for expected in ["militia", "archers", "spearmen", "cavalry"]:
		assert_true(by_archetype.has(expected),
			"Some civ should field the '%s' archetype" % expected)

	for def in by_archetype.get("archers", []):
		assert_eq(def.armour_class, "missile", "%s is archers but not missile" % def.id)
	for def in by_archetype.get("cavalry", []):
		assert_eq(def.armour_class, "cavalry", "%s is cavalry but not cavalry-classed" % def.id)
	for def in by_archetype.get("spearmen", []):
		assert_eq(def.armour_class, "infantry", "%s is spearmen but not infantry" % def.id)

	# Flatten back to one representative per archetype for the triangle
	# assertions below, which are about the shape rather than the tuning.
	var by_id := {}
	for archetype in by_archetype:
		by_id[archetype] = by_archetype[archetype][0]

	# The triangle: spears beat cavalry, cavalry beat missile, missile
	# beats infantry.
	assert_gt(float(by_id["spearmen"].bonus_vs.get("cavalry", 1.0)), 1.0,
		"Spearmen should counter cavalry")
	assert_gt(float(by_id["cavalry"].bonus_vs.get("missile", 1.0)), 1.0,
		"Cavalry should counter missile troops")
	assert_gt(float(by_id["archers"].bonus_vs.get("infantry", 1.0)), 1.0,
		"Archers should counter infantry")


# --- engagement range (D-024) ------------------------------------------

func test_engagement_in_range_produces_casualties() -> void:
	var sim := _sim()
	sim.add_squad(_attacker_def(), 1, Vector2i(5, 5))
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(6, 5))  # distance 1

	var before := sim.alive_of(defender)
	for _i in range(5):
		sim.tick()

	assert_lt(sim.alive_of(defender), before,
		"A squad engaged within attack_range should take casualties")


func test_engagement_out_of_range_produces_no_casualties() -> void:
	var sim := _sim()
	sim.add_squad(_attacker_def(), 1, Vector2i(0, 0))
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(16, 8))  # far side of the torus

	var before := sim.alive_of(defender)
	for _i in range(20):
		sim.tick()

	assert_eq(sim.alive_of(defender), before,
		"A squad outside attack_range must take no casualties")
	assert_true(sim.last_combat_events.is_empty(),
		"No engagement should mean no combat events at all")


# --- determinism (D-016, D-026 criterion 2) -----------------------------

func _run_battle_and_record_strengths(seed_value: int) -> Array:
	var sim := _sim()
	sim.combat_seed = seed_value
	var a := sim.add_squad(_stochastic_def(&"det_a"), 1, Vector2i(5, 5))
	var b := sim.add_squad(_stochastic_def(&"det_b"), 2, Vector2i(6, 5))

	var history := []
	for _i in range(40):
		sim.tick()
		history.append([sim.alive_of(a), sim.alive_of(b), sim.is_routed(a), sim.is_routed(b)])
	return history


func test_determinism_same_seed_produces_identical_strength_sequence() -> void:
	var seq_a := _run_battle_and_record_strengths(90210)
	var seq_b := _run_battle_and_record_strengths(90210)

	assert_eq(seq_a, seq_b,
		"The same seed and inputs run twice must produce an identical sequence of strengths")

	# Sanity: the battle must actually have changed something, or equal
	# sequences would be true vacuously (two runs that both did nothing).
	var changed := false
	for entry in seq_a:
		if entry[0] < 20 or entry[1] < 20:
			changed = true
			break
	assert_true(changed, "This test is only meaningful if the battle actually produced casualties")


func test_different_seed_can_produce_a_different_sequence() -> void:
	# Not a requirement of D-024 (a different seed COULD coincidentally
	# match), but confirms combat_seed is actually wired into the roll
	# rather than being an inert field nobody reads.
	var seq_a := _run_battle_and_record_strengths(1)
	var seq_b := _run_battle_and_record_strengths(2)
	assert_ne(seq_a, seq_b,
		"Different seeds should (in practice) produce different battles — if this ever fails, check combat_seed is reaching the roll")


# --- zero bandwidth when nothing died (D-026 criterion 3) ---------------

func test_zero_bandwidth_when_nothing_died() -> void:
	# Same owner: adjacent, but no enemy to fight.
	var sim := _sim()
	sim.add_squad(_attacker_def(), 1, Vector2i(5, 5))
	sim.add_squad(_attacker_def(), 1, Vector2i(6, 5))
	for _i in range(10):
		sim.tick()
		assert_eq(_combat_wire_bytes(sim.last_combat_events), 0,
			"Two friendly squads with no enemy nearby must cost zero casualty bytes")

	# Different owners, but far apart: no engagement either.
	var sim2 := _sim()
	sim2.add_squad(_attacker_def(), 1, Vector2i(0, 0))
	sim2.add_squad(_defender_def(), 2, Vector2i(16, 8))
	for _i in range(10):
		sim2.tick()
		assert_eq(_combat_wire_bytes(sim2.last_combat_events), 0,
			"An idle, unengaged squad must cost zero casualty bytes even with an enemy on the map")

	# Positive control: an actual engagement must be able to produce a
	# nonzero byte count, or the zero assertions above would be measuring
	# nothing.
	var sim3 := _sim()
	sim3.add_squad(_attacker_def(), 1, Vector2i(5, 5))
	sim3.add_squad(_defender_def(), 2, Vector2i(6, 5))
	var saw_nonzero := false
	for _i in range(10):
		sim3.tick()
		if _combat_wire_bytes(sim3.last_combat_events) > 0:
			saw_nonzero = true
	assert_true(saw_nonzero,
		"An actual engagement must produce a nonzero byte count, or this test proves nothing")


# --- morale and routing (D-019, D-024) -----------------------------------

func test_morale_falls_with_casualties() -> void:
	var sim := _sim()
	sim.add_squad(_attacker_def(), 1, Vector2i(5, 5))
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(6, 5))

	var initial_morale := sim.morale_of(defender)
	for _i in range(3):
		sim.tick()

	assert_lt(sim.morale_of(defender), initial_morale,
		"Morale should fall as the squad takes casualties")


func _tick_until_routed(sim: SquadSim, defender: int, max_ticks: int) -> bool:
	for _i in range(max_ticks):
		sim.tick()
		if sim.is_routed(defender):
			return true
	return false


func test_squad_routs_below_threshold() -> void:
	var sim := _sim()
	sim.add_squad(_attacker_def(), 1, Vector2i(5, 5))
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(6, 5))
	var def := _defender_def()

	assert_true(_tick_until_routed(sim, defender, 20),
		"The defender should rout once morale falls below rout_threshold")
	assert_lt(sim.morale_of(defender), def.rout_threshold,
		"A routed squad's morale should genuinely be below its rout_threshold")


func test_routed_squad_ignores_player_orders() -> void:
	var sim := _sim()
	sim.add_squad(_attacker_def(), 1, Vector2i(5, 5))
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(6, 5))

	assert_true(_tick_until_routed(sim, defender, 20), "Setup should have routed the defender")

	var fleeing_destination := sim.destination_of(defender)
	sim.order_move(defender, Vector2i(20, 12))

	assert_eq(sim.destination_of(defender), fleeing_destination,
		"A routed squad must ignore a player's move order and keep fleeing")


func test_routed_squad_rallies_when_morale_recovers() -> void:
	var sim := _sim()
	var attacker := sim.add_squad(_attacker_def(), 1, Vector2i(5, 5))
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(6, 5))

	assert_true(_tick_until_routed(sim, defender, 20), "Setup should have routed the defender")

	# Stop the beating so morale can recover, isolating rally behaviour
	# from the geometry of how far the flee order carries it.
	sim.set_alive(attacker, 0)

	var rallied := false
	for _i in range(200):
		sim.tick()
		if not sim.is_routed(defender):
			rallied = true
			break
	assert_true(rallied,
		"A routed squad must rally once its morale recovers past rout_threshold + rout_rally_margin")

	# order_move should work normally again post-rally.
	sim.order_move(defender, Vector2i(20, 12))
	assert_eq(sim.destination_of(defender), Vector2i(20, 12),
		"A rallied squad should obey player orders again")


# --- protocol round-trip and desync agreement (D-006) -------------------

func test_casualty_event_round_trips_and_hashes_agree() -> void:
	var sim := _sim()
	var attacker_def := _attacker_def()
	var defender_def := _defender_def()
	var attacker := sim.add_squad(attacker_def, 1, Vector2i(5, 5))
	var defender := sim.add_squad(defender_def, 2, Vector2i(6, 5))

	var client := ClientState.new()
	client.handle_packet(NetProtocol.encode_welcome(2, W, H, [defender]))
	# Seeded directly rather than via handle_packet(SQUAD_INFO): that path
	# resolves shape/spacing through UnitRoster.by_id, which only knows
	# the real /units/*.tres defs, not these synthetic test ones. Same
	# reason test_client_state.gd's desync tests hand-inject composition
	# rather than routing synthetic defs through the real roster lookup.
	client.composition[attacker] = {
		"def_id": String(attacker_def.id), "alive": sim.alive_of(attacker),
		"shape": attacker_def.formation_shape, "spacing": attacker_def.formation_spacing,
	}
	client.composition[defender] = {
		"def_id": String(defender_def.id), "alive": sim.alive_of(defender),
		"shape": defender_def.formation_shape, "spacing": defender_def.formation_spacing,
	}

	assert_eq(client.composition_hash(), sim.composition_hash([attacker, defender]),
		"Hashes must agree before any casualties happen")

	var saw_event := false
	for _i in range(10):
		sim.tick()
		if not sim.last_combat_events.is_empty():
			saw_event = true
			var wire := NetProtocol.encode_squad_combat(sim.tick_count, sim.last_combat_events)
			var decoded := NetProtocol.decode_squad_combat(wire)
			assert_eq(int(decoded["tick"]), sim.tick_count, "Decoded tick should round-trip")
			assert_eq((decoded["events"] as Array).size(), sim.last_combat_events.size(),
				"Decoded event count should round-trip")
			client.handle_packet(wire)

	assert_true(saw_event, "The engagement should have produced at least one casualty event")
	assert_eq(client.composition_hash(), sim.composition_hash([attacker, defender]),
		"Client and server composition hashes must still agree after casualties")


# --- replay coverage (D-016, D-026 criterion 11) -------------------------

func test_replay_reconstructs_post_combat_strengths() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var log := ReplayLog.new()
	assert_eq(log.open_for_write(REPLAY_PATH, SquadSim.TICK_HZ, space), OK)
	sim.replay = log

	var defender_def := _defender_def()
	var attacker := sim.add_squad(_attacker_def(), 1, Vector2i(5, 5))
	var defender := sim.add_squad(defender_def, 2, Vector2i(6, 5))

	# Mirrors server._broadcast_squad_info: the FULL, unfiltered
	# composition, logged once so a squad that never takes a casualty
	# still has a known starting strength to reconstruct.
	log.record_squad_info(sim.time, NetProtocol.encode_squad_info(
		sim.squad_info_entries([attacker, defender])))

	for _i in range(15):
		sim.tick()

	var final_attacker_alive := sim.alive_of(attacker)
	var final_defender_alive := sim.alive_of(defender)
	log.close()

	assert_lt(final_defender_alive, defender_def.squad_size,
		"This test is only meaningful if the defender actually took casualties")

	var replay := ReplayLog.read(REPLAY_PATH)
	var state := ReplayLog.reconstruct_at(replay, sim.time)
	var strengths: Dictionary = state[ReplayLog.STRENGTHS_KEY]

	assert_eq(int(strengths[attacker]), final_attacker_alive,
		"Replay should reconstruct the attacker's final strength")
	assert_eq(int(strengths[defender]), final_defender_alive,
		"Replay should reconstruct the defender's final (post-casualty) strength")


func test_allies_do_not_shoot_each_other() -> void:
	# The whole point of teams (D-050). A team dropdown that combat
	# ignored would be decoration.
	var space := TorusSpace.new(24, 12, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.teams = {1: 1, 2: 1}

	var def := UnitRoster.first()
	var a := sim.add_squad(def, 1, Vector2i(5, 5))
	var b := sim.add_squad(def, 2, Vector2i(5, 5))
	var before := sim.alive_of(a) + sim.alive_of(b)

	for _i in range(30):
		sim.tick()

	assert_eq(sim.alive_of(a) + sim.alive_of(b), before,
		"Allied squads standing on each other fought anyway")


func test_enemies_on_no_team_still_fight() -> void:
	# The other side of the boundary: without it, "allies never fight"
	# could be satisfied by nobody ever fighting.
	var space := TorusSpace.new(24, 12, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())

	var def := UnitRoster.first()
	var a := sim.add_squad(def, 1, Vector2i(5, 5))
	var b := sim.add_squad(def, 2, Vector2i(5, 5))
	var before := sim.alive_of(a) + sim.alive_of(b)

	for _i in range(30):
		sim.tick()

	assert_lt(sim.alive_of(a) + sim.alive_of(b), before,
		"Two players with no team set should be enemies (free-for-all is the default)")


# --- squads vs buildings (the half that was missing) -------------------
#
# `BuildingSim.damage()` was written, marked buildings dirty so
# destruction would replicate, and was called by nothing outside its own
# tests for two milestones. Buildings were indestructible, so a match
# could not be won: D-033 ends a match by elimination, and a town centre
# that survives everything keeps producing replacements. Every AI ladder
# match drew at the time cap and it was read as an AI weakness through
# several rounds of AI work.
#
# These four tests are what would have caught it. Each was observed to
# fail before being trusted, by reverting the pass in combat.gd and
# watching them go red (D-022's standing rule).


func _armed_building_def(id: StringName = &"combat_test_hall") -> BuildingDef:
	var d := BuildingDef.new()
	d.id = id
	d.max_health = 120.0
	d.build_time = 1.0
	d.vision_range = 8.0
	return d


func test_a_squad_destroys_an_enemy_building() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var hall := buildings.add_building(_armed_building_def(), 2, Vector2i(5, 5), true)
	sim.add_squad(_attacker_def(), 1, Vector2i(5, 6))

	for _i in range(200):
		sim.tick()
		if buildings.is_destroyed(hall):
			break

	assert_true(buildings.is_destroyed(hall),
		"A squad stood next to an enemy building and never damaged it")


func test_a_squad_leaves_its_own_buildings_alone() -> void:
	# The other side of the boundary. Without it, "buildings can be
	# destroyed" would be satisfied by an army that razes its own town.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var hall := buildings.add_building(_armed_building_def(), 1, Vector2i(5, 5), true)
	sim.add_squad(_attacker_def(), 1, Vector2i(5, 6))

	for _i in range(200):
		sim.tick()

	assert_false(buildings.is_destroyed(hall),
		"A squad demolished a building belonging to its own player")
	assert_almost_eq(buildings.health_of(hall), 120.0, 0.001,
		"An own building took damage from a friendly squad")


func test_a_squad_out_of_range_cannot_reach_a_building() -> void:
	# _attacker_def's range reaches distance 1 and not distance 2, the
	# same line the squad-vs-squad range tests sit on.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var hall := buildings.add_building(_armed_building_def(), 2, Vector2i(5, 5), true)
	sim.add_squad(_attacker_def(), 1, Vector2i(5, 7))

	for _i in range(200):
		sim.tick()

	assert_almost_eq(buildings.health_of(hall), 120.0, 0.001,
		"A building took damage from a squad two cells away, out of range")


func test_a_squad_fighting_a_squad_does_not_also_hit_a_building() -> void:
	# Defenders come first. A squad that spends its attack on a wall while
	# being cut down behind it is a bug in a siege costume, and it would
	# make a garrison pointless — an attacker could ignore it entirely.
	#
	# Worth knowing before trusting this one: TWO redundant guards enforce
	# the rule (see resolve_squads_vs_buildings), and this test only goes
	# red when BOTH are removed. Perturbing either alone leaves it green —
	# which is not the test failing to guard anything, but it does mean it
	# cannot tell you which mechanism is carrying the rule.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var hall := buildings.add_building(_armed_building_def(), 2, Vector2i(5, 5), true)
	var attacker := sim.add_squad(_attacker_def(), 1, Vector2i(5, 6))
	# A defender standing with the attacker, so it has a squad target in
	# range for as long as the defender lives.
	var defender := sim.add_squad(_defender_def(), 2, Vector2i(5, 6))

	# Checked EVERY tick while the garrison holds, rather than once at the
	# end. The first version of this test ticked a fixed 40 times and
	# failed — correctly: the defender dies part-way through, after which
	# hitting the building is exactly right. Asserting at the end measured
	# the wrong window and would have reported a working rule as broken.
	var ticks_with_a_defender := 0
	for _i in range(60):
		if sim.alive_of(defender) <= 0 or sim.is_routed(defender):
			break
		sim.tick()
		if sim.alive_of(attacker) <= 0:
			break
		ticks_with_a_defender += 1
		assert_almost_eq(buildings.health_of(hall), 120.0, 0.001,
			"A squad ignored the enemy squad in front of it to hit a building")

	assert_gt(ticks_with_a_defender, 0,
		"The garrison never survived a single tick, so nothing was actually tested")


func test_soldiers_are_not_siege_engines() -> void:
	# D-056. Unscaled, a single 36-strong militia squad razed a 900 HP town
	# centre in 2.1 SECONDS (measured), so a base evaporated the moment any
	# army reached it and matches decided in about three minutes against a
	# 1-2 hour target.
	#
	# The bound is deliberately generous rather than pinned to today's
	# tuning — this guards the RULE (a lone squad cannot flatten a town
	# hall in seconds), not a balance number somebody should be free to
	# tune. Perturbed by removing the damage_vs_buildings factor in
	# combat.gd, which takes it from ~57s to ~2s and turns it red.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var hall := BuildingSim.def_by_id(&"town_centre")
	assert_not_null(hall, "town_centre.tres is missing, so nothing was tested")
	var id := buildings.add_building(hall, 2, Vector2i(5, 5), true)

	# The roster's heaviest hitter against buildings, so this measures the
	# best case for the attacker rather than a convenient one.
	var worst: UnitDef = null
	for def in UnitRoster.load_all():
		if def.carry_capacity > 0:
			continue  # villagers are not the question
		var rate := def.damage * float(def.squad_size) * def.damage_vs_buildings \
			/ maxf(def.attack_interval, 0.001)
		if worst == null or rate > worst.damage * float(worst.squad_size) \
				* worst.damage_vs_buildings / maxf(worst.attack_interval, 0.001):
			worst = def
	assert_not_null(worst, "no fighting units in the roster")

	sim.add_squad(worst, 1, Vector2i(5, 6))
	var ticks := 0
	while ticks < 6000 and not buildings.is_destroyed(id):
		sim.tick()
		ticks += 1

	var seconds := float(ticks) / SquadSim.TICK_HZ
	assert_gt(seconds, 20.0,
		"%s razed a town centre in %.1fs — a lone squad should not flatten a base in seconds" % [
			worst.id, seconds])
