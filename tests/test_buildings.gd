extends GutTest

## Guards D-029 (buildings as a second networked entity class) and D-031
## (construction), against D-027's criteria 9, 10 and 11.
##
## ## The first test is the one that matters
##
## `SquadSim.add_squad` mints an id as `_cell.size()` — the id IS the
## array index — and `BuildingSim.add_building` does the same. So the
## first squad and the first building are both entity 0. Anything that
## funnels both through one CurveReplicator, one ReplayLog key or one
## composition-hash entry list would have a building silently overwrite a
## squad's record: no error, no crash, just wrong state.
##
## That is the same invisible-corruption class this project has now been
## bitten by twice (D-022's audit, D-026's review), and it is invisible to
## a green suite by construction — which is why this test exists before
## any other building code does.

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _building_def(id: StringName = &"test_building") -> BuildingDef:
	var d := BuildingDef.new()
	d.id = id
	d.max_health = 100.0
	d.build_time = 10.0
	d.vision_range = 12.0
	return d


func _unit_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"militia"
	d.squad_size = 10
	d.health = 50.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	return d


# --- id space (D-029, the highest-risk item in the milestone) ----------

func test_a_squad_and_a_building_at_the_same_index_do_not_collide() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)

	var squad := sim.add_squad(_unit_def(), 1, Vector2i(3, 3))
	var building := buildings.add_building(_building_def(), 1, Vector2i(9, 9))

	# Both really are entity 0 locally. That is not a bug — it is the
	# condition every assertion below exists to survive.
	assert_eq(squad, 0, "Setup: the squad is local id 0")
	assert_eq(building, 0, "Setup: the building is local id 0 too")

	assert_ne(BuildingSim.wire_id(building), squad,
		"A building's wire id must never equal a squad's")
	assert_true(BuildingSim.is_building_id(BuildingSim.wire_id(building)))
	assert_false(BuildingSim.is_building_id(squad))
	assert_eq(BuildingSim.local_id(BuildingSim.wire_id(building)), building,
		"wire_id and local_id must round-trip")
	assert_eq(BuildingSim.local_id(squad), -1, "A squad id is not a building id")


func test_one_dictionary_can_hold_both_without_either_overwriting_the_other() -> void:
	# CurveReplicator and ReplayLog both key on a bare integer. This is
	# what they would do if a future change ever fed them both kinds.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)

	var squad := sim.add_squad(_unit_def(), 1, Vector2i(3, 3))
	var building := buildings.add_building(_building_def(), 1, Vector2i(9, 9))

	var store := {}
	store[squad] = "squad"
	store[BuildingSim.wire_id(building)] = "building"

	assert_eq(store.size(), 2, "Two entities must occupy two entries, not one")
	assert_eq(store[squad], "squad", "The building must not have overwritten the squad")


func test_the_offset_clears_full_scale_squad_counts() -> void:
	# D-018 targets ~1,000 squads at full scale. The offset has to sit far
	# enough above that a squad id can never reach it, or this whole
	# scheme fails quietly at scale rather than loudly in a test.
	assert_gt(BuildingSim.BUILDING_ID_OFFSET, 1000 * 100,
		"The building id offset must clear D-018's squad counts by orders of magnitude")


# --- construction (D-031) ---------------------------------------------

func test_construction_progresses_and_completes() -> void:
	var buildings := BuildingSim.new(_space())
	var def := _building_def()
	def.build_time = 2.0
	var id := buildings.add_building(def, 1, Vector2i(4, 4))

	assert_eq(buildings.progress_of(id), 0.0)
	assert_false(buildings.is_complete(id), "A building starts as a building site")

	assert_eq(buildings.advance_construction(1.0), [], "Half-built is not complete")
	assert_almost_eq(buildings.progress_of(id), 0.5, 0.001)

	assert_eq(buildings.advance_construction(1.0), [id], "Completion is reported once")
	assert_true(buildings.is_complete(id))
	assert_eq(buildings.advance_construction(1.0), [],
		"A finished building is not reported complete again every tick")
	assert_almost_eq(buildings.progress_of(id), 1.0, 0.001, "Progress does not run past 1")


func test_a_building_can_be_placed_already_finished() -> void:
	# Starting bases exist from the first tick; they are not building
	# sites the player has to wait out.
	var buildings := BuildingSim.new(_space())
	var id := buildings.add_building(_building_def(), 1, Vector2i(4, 4), true)
	assert_true(buildings.is_complete(id))


# --- damage and destruction (D-031) -----------------------------------

func test_damage_destroys_a_building_once_and_only_once() -> void:
	var buildings := BuildingSim.new(_space())
	var id := buildings.add_building(_building_def(), 1, Vector2i(4, 4), true)

	assert_false(buildings.damage(id, 60.0), "Surviving damage is not a destruction")
	assert_almost_eq(buildings.health_of(id), 40.0, 0.001)

	assert_true(buildings.damage(id, 60.0), "The blow that kills it reports so")
	assert_true(buildings.is_destroyed(id))
	assert_eq(buildings.health_of(id), 0.0, "Health floors at zero rather than going negative")

	assert_false(buildings.damage(id, 60.0),
		"Hitting rubble must not report a second destruction — the caller announces what this returns")


func test_surviving_damage_replicates_and_not_only_fatal_damage() -> void:
	# The defect: `damage()` marked the building dirty only when the blow
	# killed it, so a client was told a building's health exactly twice —
	# 100% on reveal, and nothing again until it was rubble. Every bar in
	# the game therefore read full green right up to the moment the
	# building vanished, and a player had no way to see a base being taken
	# apart while there was still time to answer it.
	#
	# Nothing failed: the sim's health was correct throughout, the wire
	# format already carried `health_fraction`, and the client already drew
	# it. The rule was simply never delivered — the declared-and-unread
	# shape this project keeps meeting.
	var buildings := BuildingSim.new(_space())
	var id := buildings.add_building(_building_def(), 1, Vector2i(4, 4), true)
	buildings.take_dirty()

	assert_false(buildings.damage(id, 30.0), "not a killing blow")
	assert_eq(buildings.take_dirty(), [id],
		"a surviving hit still has to reach the client")


func test_scratches_too_small_to_see_do_not_resend_the_building() -> void:
	# The other half of the rule, and the reason health is quantised at
	# all: a besieged building takes damage every attack cooldown, and
	# marking each scratch dirty would resend its whole entry several times
	# a second per attacker — D-003's per-tick snapshot, wearing a health
	# bar. Steps finer than the drawn bar resolves are not worth a packet.
	var buildings := BuildingSim.new(_space())
	var id := buildings.add_building(_building_def(), 1, Vector2i(4, 4), true)
	# Off the boundary first. Full health sits exactly ON a step edge, so
	# the very first scratch of a building's life always crosses one — that
	# is correct (a player should see the instant a building is touched at
	# all) but it is not what this test is about.
	buildings.damage(id, 2.0)
	buildings.take_dirty()

	# A hundredth of full health, against a step three times that wide.
	buildings.damage(id, 1.0)
	assert_eq(buildings.take_dirty(), [],
		"a scratch within one step is not worth a packet")

	# Enough to cross a step boundary, however small the step.
	buildings.damage(id, 100.0 / BuildingSim.HEALTH_REPLICATION_STEPS)
	assert_eq(buildings.take_dirty(), [id],
		"crossing a step does reach the client")


func test_a_whole_siege_costs_a_bounded_number_of_health_messages() -> void:
	# Stated as a bound rather than described, because the bound is the
	# claim: quantising is what lets `take_dirty`'s "event-driven, never
	# per tick" promise survive a building being drawn health.
	var buildings := BuildingSim.new(_space())
	var id := buildings.add_building(_building_def(), 1, Vector2i(4, 4), true)
	buildings.take_dirty()

	var messages := 0
	# 200 blows of half a percent each — far more attack rounds than any
	# real siege, and the answer must still be small.
	for _i in range(200):
		buildings.damage(id, 0.5)
		messages += buildings.take_dirty().size()

	assert_true(messages <= int(BuildingSim.HEALTH_REPLICATION_STEPS) + 1,
		"200 blows cost %d messages, not one each" % messages)
	assert_true(messages >= 8, "but the bar still moves: %d updates" % messages)


func test_an_unfinished_building_can_still_be_destroyed() -> void:
	# A half-built tower is a real thing standing on the map, not a plan.
	var buildings := BuildingSim.new(_space())
	var id := buildings.add_building(_building_def(), 1, Vector2i(4, 4))
	buildings.advance_construction(1.0)
	assert_true(buildings.damage(id, 1000.0))
	assert_false(buildings.is_complete(id), "Rubble is not a completed building")


func test_living_counts_are_per_player_and_exclude_rubble() -> void:
	var buildings := BuildingSim.new(_space())
	var mine := buildings.add_building(_building_def(), 1, Vector2i(2, 2), true)
	buildings.add_building(_building_def(), 1, Vector2i(4, 2), true)
	buildings.add_building(_building_def(), 2, Vector2i(8, 8), true)

	assert_eq(buildings.living_building_count(1), 2)
	assert_eq(buildings.living_building_count(2), 1)

	buildings.damage(mine, 1000.0)
	assert_eq(buildings.living_building_count(1), 1)
	assert_eq(buildings.ids_of(1).size(), 1, "ids_of agrees with the count")


# --- the composition hash (D-030) -------------------------------------

func test_the_hash_ignores_health_and_progress_but_notices_destruction() -> void:
	# Same reasoning as NetProtocol.composition_hash excluding position:
	# health and progress vary continuously and a client legitimately lags
	# a tick, so hashing them would report a desync for a healthy system.
	var buildings := BuildingSim.new(_space())
	var id := buildings.add_building(_building_def(), 1, Vector2i(4, 4), true)
	var ids := [id]

	var before := buildings.composition_hash(ids)
	buildings.damage(id, 50.0)
	assert_eq(buildings.composition_hash(ids), before,
		"Taking damage must not change the hash — a lagging client would false-positive")

	buildings.damage(id, 1000.0)
	assert_ne(buildings.composition_hash(ids), before,
		"Being destroyed must change it: that is a discrete, reliably-delivered fact")


func test_buildings_of_different_owners_hash_differently() -> void:
	var buildings := BuildingSim.new(_space())
	var a := buildings.add_building(_building_def(), 1, Vector2i(2, 2), true)
	var b := buildings.add_building(_building_def(), 2, Vector2i(2, 2), true)
	assert_ne(buildings.composition_hash([a]), buildings.composition_hash([b]),
		"Ownership is part of what a client must agree with the server about")


# --- buildings see (D-029 + D-025) ------------------------------------

func test_a_building_grants_its_owner_vision() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var watched := Vector2i(20, 8)
	# An enemy squad far from anything player 1 owns.
	sim.add_squad(_unit_def(), 2, watched)
	sim.recompute_vision_now()
	assert_false(sim.visible_to(1).has(0), "Setup: player 1 cannot see it yet")

	# Put a building next to the enemy. Nothing else changes.
	buildings.add_building(_building_def(), 1, watched + Vector2i(1, 0), true)
	sim.recompute_vision_now()
	assert_true(sim.visible_to(1).has(0),
		"A building must contribute to its owner's vision, not just squads")


func test_rubble_sees_nothing() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var watched := Vector2i(20, 8)
	sim.add_squad(_unit_def(), 2, watched)
	var eye := buildings.add_building(_building_def(), 1, watched + Vector2i(1, 0), true)
	sim.recompute_vision_now()
	assert_true(sim.visible_to(1).has(0), "Setup: the building sees it")

	buildings.damage(eye, 10000.0)
	sim.recompute_vision_now()
	assert_false(sim.visible_to(1).has(0), "Destroyed buildings stop seeing")


# --- armed buildings shoot (D-032) ------------------------------------

func _armed_def() -> BuildingDef:
	var d := _building_def(&"test_tower")
	d.attack_range = 6.0
	d.damage = 40.0
	d.attack_interval = 0.1  # one tick, so a short test still sees fire
	return d


func _shooting_sim() -> Dictionary:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var enemy_def := _unit_def()
	enemy_def.health = 20.0
	enemy_def.morale_loss_per_casualty = 0.0  # no routing; this is about damage
	var squad := sim.add_squad(enemy_def, 2, Vector2i(10, 8))
	return {"sim": sim, "buildings": buildings, "squad": squad}


func test_an_armed_building_damages_an_enemy_squad_in_range() -> void:
	var setup := _shooting_sim()
	var sim: SquadSim = setup["sim"]
	var buildings: BuildingSim = setup["buildings"]
	var squad: int = setup["squad"]

	buildings.add_building(_armed_def(), 1, Vector2i(11, 8), true)
	var before := sim.alive_of(squad)
	for _i in range(5):
		sim.tick()

	assert_lt(sim.alive_of(squad), before, "A tower in range must actually shoot")


## A whole encounter with SHIPPED data: one militia squad walks onto a
## defended building and razes it. Returns what it cost the attacker.
##
## Every other test in this section uses a synthetic def with damage 40 on
## a 0.1 s interval against 20 HP men — a caricature, chosen so a five-tick
## test can see a casualty. That proves the MECHANISM and says nothing
## about whether the shipped numbers do anything, which is exactly the gap
## D-066 fell through: `damage > 0` passed for two milestones while a town
## centre cost an attacking squad 4 men out of 36 and players reported the
## defence as missing.
func _rush_cost(building_id: StringName, unit_id: StringName, squad_count: int) -> Dictionary:
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var def := BuildingSim.def_by_id(building_id)
	assert_not_null(def, "buildings/%s.tres is missing, so nothing was tested" % building_id)
	var unit := UnitRoster.by_id(unit_id)
	assert_not_null(unit, "the roster should ship %s" % unit_id)

	var target := buildings.add_building(def, 1, Vector2i(20, 20), true)
	var squads := []
	var started_with := 0
	for i in range(squad_count):
		# Ordered in from outside the building's reach, so the approach
		# under fire is part of what is measured — range is half of what a
		# defence is. All ordered onto the SAME cell, which is what a
		# player does and what arrival separation then has to resolve
		# sensibly (D-067).
		var squad := sim.add_squad(unit, 2, Vector2i(26, 20 + i * 2))
		sim.order_attack_move(squad, Vector2i(21, 20))
		squads.append(squad)
		started_with += sim.alive_of(squad)

	# 300 s, and an early exit the moment either side is finished. Long
	# enough for rout-and-rally cycles to resolve, so "did not raze" means
	# beaten rather than merely unfinished; bounded so a stalemate fails
	# the test instead of hanging it.
	var razed_at := -1
	for i in range(3000):
		sim.tick()
		var alive := 0
		for squad in squads:
			alive += sim.alive_of(squad)
		if buildings.is_destroyed(target):
			razed_at = i
			break
		if alive <= 0:
			break

	var left := 0
	for squad in squads:
		left += sim.alive_of(squad)
	return {
		"razed": razed_at >= 0,
		"seconds": (razed_at + 1) / 10.0,
		"casualties": started_with - left,
		"started_with": started_with,
		"health": buildings.health_of(target),
	}


func test_two_melee_squads_besiege_a_building_about_twice_as_fast_as_one() -> void:
	# The rule this project wants — "one squad cannot take a base, two can"
	# — is not reachable by tuning damage while this is false, and it WAS
	# false: a second melee squad ordered onto the same building was shoved
	# four cells away by arrival separation, outside its 1-cell reach, and
	# contributed nothing. Measured, 30 s against a passive town centre:
	# one squad 1461, two squads 1560.
	#
	# Ranged units never showed it — they were displaced within their own
	# range and kept firing — which is why the numbers looked merely
	# ungenerous rather than broken.
	var space := TorusSpace.new(42, 48, 1.0)
	var militia := UnitRoster.by_id(&"gildedreach_levy")
	assert_not_null(militia)

	var dealt := []
	for squad_count in [1, 2]:
		var sim := SquadSim.new(space, CurveReplicator.new())
		var buildings := BuildingSim.new(space)
		sim.buildings = buildings

		# A passive target: this is about how much the attackers can
		# deliver, not about who wins.
		var def: BuildingDef = BuildingSim.def_by_id(&"town_centre").duplicate()
		def.damage = 0.0
		var target := buildings.add_building(def, 1, Vector2i(20, 20), true)

		for i in range(squad_count):
			var squad := sim.add_squad(militia, 2, Vector2i(26, 20 + i * 2))
			sim.order_attack_move(squad, Vector2i(21, 20))
		for _i in range(300):
			sim.tick()
		dealt.append(def.max_health - buildings.health_of(target))

	assert_gt(float(dealt[1]), float(dealt[0]) * 1.7,
		"two squads dealt %.0f against one squad's %.0f — the second squad is not in the fight"
		% [dealt[1], dealt[0]])


## Every troop of the six fantasy civs a player can field early (#191) —
## the population the SOLO rule is asked of, because any of them could be
## thrown at a base in the first three minutes.
##
## Generals and gatherers are handled separately: both are in the SOLO
## rule (added at its call site) and neither is in the PAIR rule, because
## a player may only ever have one general alive
## (D-20260819-a-general-holds-the-line) and gatherers are workers.
##
## SIEGE units (breaker, engine, ram, bombard) are absent from BOTH:
## cracking a defended building alone is their design brief, not a rush
## exploit — the Ember Bombard's whole identity is outranging the tower —
## so D-067's "no single squad" rule is scoped to troops, exactly as its
## own text says ("any STARTING troop"), and the siege train pays for the
## licence in speed, fragility and gold.
const STARTING_TROOPS := [
	&"stoneblood_levy", &"stoneblood_heavy", &"stoneblood_skirmishers",
	&"gravesworn_levy", &"gravesworn_spearmen", &"gravesworn_shades",
	&"thornwood_levy", &"thornwood_archers", &"thornwood_cavalry",
	&"thornwood_greatbow",
	&"windmarch_levy", &"windmarch_skirmishers", &"windmarch_cavalry",
	&"windmarch_bowriders",
	&"gildedreach_levy", &"gildedreach_spearmen", &"gildedreach_archers",
	&"gildedreach_cavalry", &"gildedreach_sellswords",
	&"emberdeep_levy", &"emberdeep_heavy", &"emberdeep_archers",
]


## The LINE troops — the population the PAIR rule is asked of.
##
## This list is the correction #152 turned out to need, and it is a
## CATEGORY fix rather than a relaxed assertion
## (D-20260827-a-buildings-hp-is-one-knob-and-the-rule-needs-two). D-067
## states its two halves in different words on purpose: "one squad of any
## starting TROOP must fail" against "two squads of any LINE troop must
## succeed". Under the old eight-unit legion/northmen roster the
## difference barely bit — six of the eight were line infantry — so one
## list served both, and when #191 replaced the roster with 22 troops the
## list was carried across whole. Ten of the new 22 are cavalry, missile
## or light infiltrators, and the pair rule was asking them to do a line
## troop's job.
##
## Membership is by ROLE, and every entry is MEASURED: at the shipped
## building numbers each of these clears the solo ceiling by at least
## 13%, and each excluded troop is checked below to be doing real damage
## rather than none.
const LINE_TROOPS: Array[StringName] = [
	&"stoneblood_levy", &"stoneblood_heavy",
	&"gravesworn_levy", &"gravesworn_spearmen",
	&"thornwood_levy",
	&"windmarch_levy",
	&"gildedreach_levy", &"gildedreach_spearmen", &"gildedreach_sellswords",
	&"emberdeep_levy", &"emberdeep_heavy",
]


## The troops the pair rule is NOT asked of — cavalry, missile troops and
## light infiltrators. Derived, so the two lists cannot fall out of step
## and a new `.tres` cannot go unexamined by both.
static func _light_troops() -> Array:
	var out := []
	for unit_id in STARTING_TROOPS:
		if not LINE_TROOPS.has(unit_id):
			out.append(unit_id)
	return out


func test_no_single_starting_squad_can_raze_a_defended_building() -> void:
	# The anti-rush rule (D-067), stated as the owner asked for it: ONE
	# squad of anything available at the start must fail against either
	# defended building. This is the half that prevents a two-minute win.
	#
	# Every troop type is checked rather than a representative one, and
	# with the fantasy roster (#191) that matters more than it used to:
	# effective squad HP spans 760 (gravesworn_shades, 20 x 38) to 3,040
	# (stoneblood_heavy, 8 x 380) and damage per second against buildings
	# spans 15.0 to 34.6, so "the strongest solo attacker" is not obvious
	# by inspection and changes whenever a `.tres` does. It is
	# stoneblood_heavy, by a wide margin, and it is what bounds the pair
	# rule below — see
	# D-20260827-a-buildings-hp-is-one-knob-and-the-rule-needs-two.
	for building in [&"town_centre", &"tower"]:
		for unit_id in STARTING_TROOPS + [&"emberdeep_gatherers",
				&"windmarch_gatherers", &"stoneblood_general",
				&"gravesworn_general"]:
			var result := _rush_cost(building, unit_id, 1)
			assert_false(bool(result["razed"]),
				"one squad of %s razed a defended %s in %.0fs — that is the early rush this rule exists to stop"
					% [unit_id, building, result["seconds"]])


func test_two_squads_of_any_line_troop_can_take_a_town_centre() -> void:
	# The other half: the rule must not make bases untakeable, which is how
	# D-055's every-match-a-draw happened. Two squads of any LINE troop
	# must finish a town centre.
	#
	# Gatherers are workers, and the general is excluded because a player
	# may only ever have one alive (D-20260819-a-general-holds-the-line), so
	# "two generals" is not a situation the game can produce. Cavalry,
	# missile troops and light infiltrators are excluded because they are
	# not line troops — see LINE_TROOPS, and the companion test below that
	# stops that exclusion becoming "they do nothing".
	for unit_id in LINE_TROOPS:
		var result := _rush_cost(&"town_centre", unit_id, 2)
		assert_true(bool(result["razed"]),
			"two squads of %s could not take a town centre (%.0f HP left) — defence has passed decidable"
				% [unit_id, result["health"]])


func test_two_squads_of_any_line_troop_but_light_skirmishers_can_take_a_tower() -> void:
	# Same rule against the purpose-built defence. Light raiders do not
	# crack a fortification; their own side's line and heavy troops all do.
	#
	# The exception is a CLASS now rather than a list of ids
	# (D-20260827-a-buildings-hp-is-one-knob-and-the-rule-needs-two).
	# D-067 carved out one unit by name and predicted this in its revisit
	# trigger: with the fantasy roster's 22 troops, no tower HP separates
	# the strongest solo attacker from the weakest pair, because
	# `max_health` and `damage` are ONE knob — scaling the tower's damage
	# rescales solo and pair delivery together, and coverage was measured
	# INVARIANT at 15 of 22 across a 2.4x sweep of tower damage. What
	# separates them is the ROLE of the troop, which is why the rule is
	# asked of LINE_TROOPS.
	for unit_id in LINE_TROOPS:
		var result := _rush_cost(&"tower", unit_id, 2)
		assert_true(bool(result["razed"]),
			"two squads of %s could not take a tower (%.0f HP left)"
				% [unit_id, result["health"]])


func test_every_light_troop_still_hurts_a_tower_even_though_two_cannot_take_it() -> void:
	# Guards the exclusion above from becoming an excuse: a troop the pair
	# rule does not cover must still be doing real damage to a tower, so a
	# future change that makes cavalry or archers harmless to buildings
	# fails here rather than hiding behind the documented carve-out.
	#
	# This used to check the ONE carved-out unit. It checks the whole
	# excluded class now, because that class went from one member to ten
	# and "the carve-out is honest" is a claim about all of them — the
	# same "a caller-exists test only covers the caller it names" lesson
	# D-106's amendment paid for, applied to a data rule.
	#
	# The bar is a QUARTER of the tower, derived from the def rather than
	# written down: a literal here would go stale the next time the
	# tower's HP moves, which is exactly what happened to the
	# `1700.0 * 0.75` this replaces. The quarter keeps the predecessor's
	# spirit and its margin — the weakest excluded pair, windmarch_
	# bowriders, takes 479 of 1250 (38%) off the tower, so it clears a
	# 25% bar by 13 points. A third was tried first and cleared by 5,
	# which is a guard that would go red on ordinary tuning drift while
	# still calling it "not fighting it at all".
	var tower: BuildingDef = BuildingSim.def_by_id(&"tower")
	assert_not_null(tower, "buildings/tower.tres is missing, so nothing was tested")
	var light := _light_troops()
	assert_gt(light.size(), 0, "setup: no troop is excluded, so this test proves nothing")
	for unit_id in light:
		var result := _rush_cost(&"tower", unit_id, 2)
		assert_lt(float(result["health"]), tower.max_health * 0.75,
			"two squads of %s left the tower on %.0f of %.0f HP — they are not fighting it at all"
				% [unit_id, result["health"], tower.max_health])


func test_the_pair_rule_covers_every_line_troop_the_roster_ships() -> void:
	# LINE_TROOPS is hand-written, and the defect it exists to correct was
	# itself a hand-written list carried across a roster change (#152). So
	# this asserts the list against the ROSTER: every shipped unit whose
	# archetype is a line archetype must be in it, and nothing else may be.
	#
	# Without this, adding `windmarch_spearmen` tomorrow would silently go
	# unasserted by the pair rule — which is precisely how the old list
	# came to be asking cavalry to crack fortifications.
	const LINE_ARCHETYPES := [&"levy", &"spearmen", &"heavy", &"sellswords"]
	var expected := []
	for def in UnitRoster.load_all():
		if LINE_ARCHETYPES.has(def.archetype):
			expected.append(def.id)
	expected.sort()
	var listed := LINE_TROOPS.duplicate()
	listed.sort()
	assert_eq(listed, expected,
		"LINE_TROOPS has drifted from the roster's line archetypes %s" % [LINE_ARCHETYPES])


func test_a_building_site_does_not_shoot() -> void:
	# A half-built tower is a target, not a garrison.
	var setup := _shooting_sim()
	var sim: SquadSim = setup["sim"]
	var buildings: BuildingSim = setup["buildings"]
	var squad: int = setup["squad"]

	var def := _armed_def()
	def.build_time = 1000.0
	buildings.add_building(def, 1, Vector2i(11, 8), false)

	var before := sim.alive_of(squad)
	for _i in range(5):
		sim.tick()
	assert_eq(sim.alive_of(squad), before, "An unfinished building must not fire")


func test_an_unarmed_building_does_not_shoot() -> void:
	var setup := _shooting_sim()
	var sim: SquadSim = setup["sim"]
	var buildings: BuildingSim = setup["buildings"]
	var squad: int = setup["squad"]

	buildings.add_building(_building_def(), 1, Vector2i(11, 8), true)  # damage 0
	var before := sim.alive_of(squad)
	for _i in range(5):
		sim.tick()
	assert_eq(sim.alive_of(squad), before, "A storehouse is not a weapon")


func test_a_building_does_not_shoot_its_own_side() -> void:
	var setup := _shooting_sim()
	var sim: SquadSim = setup["sim"]
	var buildings: BuildingSim = setup["buildings"]

	var friendly_def := _unit_def()
	friendly_def.health = 20.0
	var friendly := sim.add_squad(friendly_def, 1, Vector2i(12, 8))
	buildings.add_building(_armed_def(), 1, Vector2i(11, 8), true)

	var before := sim.alive_of(friendly)
	for _i in range(5):
		sim.tick()
	assert_eq(sim.alive_of(friendly), before, "Buildings must not fire on their owner's squads")


func test_a_building_out_of_range_does_not_reach() -> void:
	var setup := _shooting_sim()
	var sim: SquadSim = setup["sim"]
	var buildings: BuildingSim = setup["buildings"]
	var squad: int = setup["squad"]

	# attack_range 6.0 world units is ~3.4 cells; 12 cells away is well out.
	buildings.add_building(_armed_def(), 1, Vector2i(22, 8), true)
	var before := sim.alive_of(squad)
	for _i in range(5):
		sim.tick()
	assert_eq(sim.alive_of(squad), before, "Range has to mean something")


func test_building_fire_reports_casualty_events() -> void:
	# The events merge into the same list squad combat produces, so they
	# replicate through the path clients already understand (D-029).
	var setup := _shooting_sim()
	var sim: SquadSim = setup["sim"]
	var buildings: BuildingSim = setup["buildings"]
	var squad: int = setup["squad"]

	buildings.add_building(_armed_def(), 1, Vector2i(11, 8), true)

	var saw_event := false
	for _i in range(5):
		sim.tick()
		for event in sim.last_combat_events:
			if int(event["id"]) == squad:
				saw_event = true
	assert_true(saw_event, "Damage from a building must surface as a casualty event")


# --- persistent-explored fog and its hash (D-030) ---------------------

## Mirrors server.gd's building block in _replicate() for one client.
## Hand-driven for the same reason test_fog.gd hand-drives the squad
## path: server.gd needs a live ENet host a GUT test cannot stand up.
func _replicate_buildings(sim: SquadSim, buildings: BuildingSim, state: ClientState,
		player: int, known: Dictionary) -> Dictionary:
	var to_send := []
	for id in buildings.visible_to(player, sim.vision):
		if not known.has(id):
			known[id] = true
			to_send.append(id)
	for id in buildings.take_dirty():
		if known.has(id) and not to_send.has(id):
			to_send.append(id)

	if not to_send.is_empty():
		state.handle_packet(NetProtocol.encode_building_info(buildings.info_entries(to_send)))
	state.handle_packet(NetProtocol.encode_building_state_hash(
		sim.tick_count, buildings.composition_hash(known.keys())))
	return known


func test_a_building_once_seen_stays_known_and_the_hash_keeps_agreeing() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var scout := sim.add_squad(_unit_def(), 1, Vector2i(9, 8))
	var enemy_hall := buildings.add_building(_building_def(), 2, Vector2i(10, 8), true)

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [scout]))

	sim.recompute_vision_now()
	var known := _replicate_buildings(sim, buildings, state, 1, {})
	assert_eq(state.buildings.size(), 1, "The scout should have revealed the enemy hall")
	assert_eq(state.building_desync_count, 0, "Hashes agree once it is known")

	# The scout dies, so player 1 can no longer see that cell at all.
	sim.set_alive(scout, 0)
	sim.recompute_vision_now()
	assert_false(buildings.visible_to(1, sim.vision).has(enemy_hall),
		"Setup: the hall is genuinely out of vision now")

	for _i in range(5):
		known = _replicate_buildings(sim, buildings, state, 1, known)

	assert_eq(state.buildings.size(), 1,
		"A building once seen is never un-known — it cannot have moved (D-030)")
	assert_eq(state.building_desync_count, 0,
		"And the hash keeps agreeing the whole time it is out of sight")


func test_hashing_the_visible_set_instead_of_the_known_set_would_desync() -> void:
	# The trap this design exists to avoid, demonstrated rather than
	# asserted. If the server hashed "what you can see now" while the
	# client hashes "everything you have been shown", the two compare
	# differently-shaped sets and the check fires on a perfectly healthy
	# system — the same failure D-025 part 3 documents for squads.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var scout := sim.add_squad(_unit_def(), 1, Vector2i(9, 8))
	buildings.add_building(_building_def(), 2, Vector2i(10, 8), true)

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [scout]))
	sim.recompute_vision_now()
	_replicate_buildings(sim, buildings, state, 1, {})
	assert_eq(state.building_desync_count, 0, "Setup: healthy so far")

	sim.set_alive(scout, 0)
	sim.recompute_vision_now()

	# The WRONG hash: over the currently-visible set, which is now empty.
	state.handle_packet(NetProtocol.encode_building_state_hash(
		1, buildings.composition_hash(buildings.visible_to(1, sim.vision))))
	assert_gt(state.building_desync_count, 0,
		"Hashing the visible set must desync a healthy client — which is why the server hashes the known set")


func test_a_client_is_told_about_a_building_only_once() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var scout := sim.add_squad(_unit_def(), 1, Vector2i(9, 8))
	buildings.add_building(_building_def(), 2, Vector2i(10, 8), true)

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [scout]))
	sim.recompute_vision_now()

	var known := {}
	for _i in range(6):
		known = _replicate_buildings(sim, buildings, state, 1, known)

	assert_eq(state.buildings_revealed, 1,
		"Re-announcing a known building every tick would be bandwidth for nothing (D-003)")


func test_destruction_reaches_a_client_that_has_walked_away() -> void:
	# The reason take_dirty() exists: destruction is IN the hash, so a
	# client that knows a building but can no longer see it must still be
	# told when it falls, or the two sides diverge for the rest of the match.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var scout := sim.add_squad(_unit_def(), 1, Vector2i(9, 8))
	var hall := buildings.add_building(_building_def(), 2, Vector2i(10, 8), true)

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [scout]))
	sim.recompute_vision_now()
	var known := _replicate_buildings(sim, buildings, state, 1, {})

	sim.set_alive(scout, 0)
	sim.recompute_vision_now()
	buildings.damage(hall, 10000.0)
	known = _replicate_buildings(sim, buildings, state, 1, known)

	assert_true(bool(state.buildings[BuildingSim.wire_id(hall)]["destroyed"]),
		"The client must learn the building fell even though it could not see it")
	assert_eq(state.building_desync_count, 0, "And the hash must still agree afterwards")


# --- the build order on the wire (D-031) ------------------------------

func test_build_orders_round_trip() -> void:
	var bytes := NetProtocol.encode_order_build(4, "town_centre", 129)
	assert_eq(NetProtocol.opcode_of(bytes), NetProtocol.C2S_ORDER_BUILD)
	var decoded := NetProtocol.decode_order_build(bytes)
	assert_eq(int(decoded["squad"]), 4)
	assert_eq(String(decoded["def_id"]), "town_centre")
	assert_eq(int(decoded["cell"]), 129)


func test_a_client_will_not_send_a_build_order_for_a_squad_it_does_not_own() -> void:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [4]))
	assert_true(state.encode_build(9, "town_centre", Vector2i(1, 1)).is_empty())
	assert_false(state.encode_build(4, "town_centre", Vector2i(1, 1)).is_empty())


func test_building_info_round_trips_every_field() -> void:
	var entries := [{
		"id": BuildingSim.wire_id(3), "def_id": "tower", "owner": 2,
		"cell": 77, "progress": 0.5, "destroyed": false,
	}]
	var decoded := NetProtocol.decode_building_info(NetProtocol.encode_building_info(entries))
	assert_eq(decoded.size(), 1)
	assert_eq(int(decoded[0]["id"]), BuildingSim.wire_id(3))
	assert_eq(String(decoded[0]["def_id"]), "tower")
	assert_eq(int(decoded[0]["owner"]), 2)
	assert_eq(int(decoded[0]["cell"]), 77)
	assert_almost_eq(float(decoded[0]["progress"]), 0.5, 0.001)
	assert_false(bool(decoded[0]["destroyed"]))


# --- who may build what (D-031) ---------------------------------------

func test_only_gatherers_can_build_a_town_hall() -> void:
	# D-20260823-the-opening-is-a-crew-and-a-general: the settler is the
	# economy unit now, and founders are gone from the roster entirely.
	var town_centre: BuildingDef = load("res://buildings/town_centre.tres")
	assert_true(BuildingSim.can_build(town_centre, &"gatherers"),
		"The opening crew settles — that is what makes the opening a decision")
	for other in [&"militia", &"archers", &"cavalry", &"spearmen", &"general"]:
		assert_false(BuildingSim.can_build(town_centre, other),
			"%s must not be able to plant a town hall" % other)


func test_the_general_can_build_nothing_at_all() -> void:
	# The escort is an escort. It is barred from every building by being
	# listed in no `built_by` — no second, builder-side list to keep in
	# step, which is the whole reason the rule reads one way only.
	for def in BuildingSim.all_defs():
		assert_false(BuildingSim.can_build(def, &"general"),
			"a general raised a %s — the opening's escort is not a builder" % def.id)


func test_no_founders_unit_remains_in_the_roster() -> void:
	# The removal itself (issue #190). A leftover `founders` def would be
	# fielded by nothing and refused by nothing — the declared-and-unread
	# family with the reader gone instead of the writer.
	for def in UnitRoster.load_all():
		assert_ne(String(def.archetype), "founders",
			"%s still uses the removed 'founders' archetype" % def.id)
		assert_false(String(def.id).contains("founders"),
			"%s is a leftover founders unit" % def.id)


func test_an_unrestricted_building_accepts_any_builder() -> void:
	# Empty built_by means unrestricted. Nothing shipped uses it, but the
	# default has to be the permissive one or every new .tres would be
	# unbuildable until someone remembered to fill the field in.
	var def := _building_def()
	assert_true(def.built_by.is_empty(), "Setup: the default is unrestricted")
	assert_true(BuildingSim.can_build(def, &"anything_at_all"))


func test_the_opening_general_outfights_basic_infantry() -> void:
	# What the founding party's "can fight" claim became. The opening is a
	# crew and an ESCORT (D-20260823-the-opening-is-a-crew-and-a-general),
	# and an escort that lost to the cheapest melee unit would make settling
	# a formality rather than a choice — a rush would simply walk in while
	# the crew was mid-build.
	for civ in CivRoster.ids():
		var general: UnitDef = UnitRoster.for_civ_archetype(civ, &"general")
		var militia: UnitDef = UnitRoster.for_civ_archetype(civ, &"militia")
		assert_not_null(general, "civ %s fields no general to open with" % civ)
		assert_not_null(militia, "civ %s fields no militia to compare against" % civ)
		if general == null or militia == null:
			continue

		assert_gt(general.damage, militia.damage, "A general hits harder, man for man")
		assert_gt(general.health, militia.health, "And is harder to kill")
		assert_lt(general.rout_threshold, militia.rout_threshold,
			"And holds his nerve longer — that is what the aura is about")
		assert_lt(general.squad_size, militia.squad_size,
			"But there are few of them: this is a command party, not an army")


# --- the shipped roster (D-010) ---------------------------------------

func test_the_shipped_buildings_load_and_make_sense() -> void:
	var by_id := {}
	for name in ["town_centre", "barracks", "storehouse", "tower"]:
		var def: BuildingDef = load("res://buildings/%s.tres" % name)
		assert_not_null(def, "buildings/%s.tres should load as a BuildingDef" % name)
		by_id[String(def.id)] = def

	assert_true(by_id["town_centre"].is_drop_off, "The town centre takes deliveries")
	assert_true(by_id["storehouse"].is_drop_off, "So does the storehouse — that is its whole job")
	assert_false(by_id["barracks"].is_drop_off)

	# Two buildings shoot: the tower, and the town centre, which defends
	# itself so an early rush cannot simply walk into an undefended base
	# before anything has been built. This is why the buildings combat
	# pass is written as a loop over every armed building rather than a
	# special case for towers — the roster was always going to grow a
	# second shooter.
	assert_gt(by_id["tower"].damage, 0.0, "The tower must actually shoot")
	assert_gt(by_id["town_centre"].damage, 0.0,
		"The town centre defends itself — early-game protection")
	assert_lt(by_id["town_centre"].damage, by_id["tower"].damage,
		"A town centre defends; a tower is what you build when you mean it")
	assert_lt(by_id["town_centre"].attack_range, by_id["tower"].attack_range,
		"And it does not outrange a purpose-built tower")

	for quiet in ["barracks", "storehouse"]:
		assert_eq(by_id[quiet].damage, 0.0, "%s should be a target, not a shooter" % quiet)

	assert_false(by_id["barracks"].produces.is_empty(), "A barracks that produces nothing is furniture")


# --- collision and rally points (playtest feedback) --------------------

func test_a_produced_squad_does_not_appear_inside_the_building() -> void:
	# Reported from a real game: units spawn inside/on top of the building
	# that made them. Production placed them at `cell + (1, 0)` — one hex
	# from the centre, which is INSIDE the box drawn on top, because a
	# building's mesh is wider than a hex is across.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var def := _building_def()
	def.produces = [&"militia"]
	def.build_time = 0.001
	var hall := buildings.add_building(def, 1, Vector2i(8, 8), true)

	var unit := UnitRoster.first()
	buildings.enqueue(hall, unit)
	for _i in range(400):
		sim.tick()
		if sim.squad_count() > 0:
			break

	assert_gt(sim.squad_count(), 0, "nothing was produced, so nothing was tested")
	var made := sim.squad_count() - 1
	assert_gt(space.distance(sim.cell_of(made), Vector2i(8, 8)), 1,
		"the new squad is standing on the building that made it")


func test_a_squad_cannot_stand_where_a_building_stands() -> void:
	# Buildings block movement now. Ordering a squad onto one sends it to
	# the nearest ground it can actually occupy instead of setting a
	# destination the flow field can never reach — without which the squad
	# would simply never move, which looks exactly like a broken order.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	# Every cell walkable except the one the hall stands on.
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)
	var hall_cell := Vector2i(10, 6)
	passable[space.index(hall_cell)] = 0
	sim.set_passable(passable)

	var squad := sim.add_squad(_unit_def(), 1, Vector2i(4, 6))
	sim.order_move(squad, hall_cell)
	for _i in range(200):
		sim.tick()

	assert_ne(sim.cell_of(squad), hall_cell,
		"a squad walked onto the cell a building occupies")
	assert_lt(space.distance(sim.cell_of(squad), hall_cell), 4,
		"the squad never approached the building at all — the order was lost, "
		+ "not redirected")


func test_a_rally_point_defaults_in_front_and_can_be_moved() -> void:
	var space := _space()
	var buildings := BuildingSim.new(space)
	var hall := buildings.add_building(_building_def(), 1, Vector2i(9, 9), true)

	var default_rally := buildings.rally_of(hall)
	assert_gt(space.distance(default_rally, Vector2i(9, 9)), 1,
		"the default rally point is on top of the building")

	buildings.set_rally(hall, Vector2i(14, 12))
	assert_eq(buildings.rally_of(hall), Vector2i(14, 12),
		"setting a rally point did not take")


# --- claimed ground (D-062) --------------------------------------------

func test_a_building_denies_ground_to_other_players_but_not_to_you() -> void:
	# Territory: nobody hostile may plant anything inside a building's
	# no_build_radius, so a town cannot be walled in by towers built
	# against its walls, and a settlement means something on the map.
	#
	# Your OWN ground stays yours — a rule that stopped you extending your
	# own base would be a different and much worse mechanic.
	var space := _space()
	var buildings := BuildingSim.new(space)
	var hall := BuildingSim.def_by_id(&"town_centre")
	assert_not_null(hall, "town_centre.tres is missing")
	assert_gt(hall.no_build_radius, 0, "a town centre should claim some ground")

	var at := Vector2i(10, 8)
	buildings.add_building(hall, 1, at, true)

	# A cell inside the claim, and one outside it.
	var inside := space.normalize(at + Vector2i(hall.no_build_radius - 1, 0))
	var outside := space.normalize(at + Vector2i(hall.no_build_radius + 3, 0))
	assert_lte(space.distance(inside, at), hall.no_build_radius, "setup: inside the claim")
	assert_gt(space.distance(outside, at), hall.no_build_radius, "setup: outside the claim")


func test_the_claim_is_data_not_a_constant() -> void:
	# Per building, so a town centre claims a settlement's worth of ground
	# and a tower claims its own footprint — and a scenario can tune
	# territory without touching a script (D-010).
	var hall := BuildingSim.def_by_id(&"town_centre")
	var tower := BuildingSim.def_by_id(&"tower")
	assert_not_null(hall)
	assert_not_null(tower)
	assert_gt(hall.no_build_radius, tower.no_build_radius,
		"a town centre should claim more ground than a tower — if these are equal, "
		+ "the radius is behaving like one global constant")


# --- walls, gates and the wall-top access point (D-076) -----------------
#
# Phase A only: ground-level blocking, gates, and the tower's per-instance
# door direction. The walkable tier itself (SquadSim._tier, the second
# FlowField layer, climb/descend, tier-aware combat) is a separate slice
# with its own tests once that lands.

func test_the_shipped_wall_and_gate_defs_load_and_block_for_free() -> void:
	for id in [&"wall", &"gate", &"garrison_wall", &"garrison_gate", &"wall_tower"]:
		var def := BuildingSim.def_by_id(id)
		assert_not_null(def, "buildings/%s.tres should load as a BuildingDef" % id)
		assert_eq(def.damage, 0.0,
			"%s must not attack on its own — offense comes from whoever stands on it" % id)
		assert_eq(def.footprint_radius, 0,
			"%s needs footprint_radius 0 so adjacent segments do not reject each other" % id)

	assert_false(BuildingSim.def_by_id(&"wall").is_gate)
	assert_true(BuildingSim.def_by_id(&"gate").is_gate)
	assert_false(BuildingSim.def_by_id(&"wall").walkable_top)
	assert_true(BuildingSim.def_by_id(&"garrison_wall").walkable_top)
	assert_true(BuildingSim.def_by_id(&"garrison_gate").walkable_top)
	assert_true(BuildingSim.def_by_id(&"wall_tower").walkable_top)
	assert_true(BuildingSim.def_by_id(&"wall_tower").is_access_tower)
	for id in [&"wall", &"gate", &"garrison_wall", &"garrison_gate"]:
		assert_false(BuildingSim.def_by_id(id).is_access_tower,
			"only the tower piece is a climb point (D-076) — a plain segment must not be one")


func test_a_wall_blocks_ground_movement_for_free() -> void:
	# No new blocking code exists for this — BuildingSim.blocking_cells()
	# reports any living wall's cell, and server._refresh_passability()
	# feeds that straight into SquadSim.set_passable() exactly the way it
	# already does for every other building.
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)
	var wall_cell := Vector2i(10, 6)
	buildings.add_building(BuildingSim.def_by_id(&"wall"), 1, wall_cell, true)

	assert_true(buildings.blocking_cells().has(space.index(wall_cell)),
		"a living wall must block its own cell")


func test_a_wall_under_construction_does_not_block() -> void:
	# Playtest fix: walls are built in long drag-built chains, and blocking
	# from the moment of founding could seal the builder itself into a
	# pocket with no path to the next segment in its own queue — reported
	# as gatherers trapped against the wall they were still building.
	# footprint_radius == 0 buildings (the wall family) skip blocking until
	# `_progress` reaches 1.0; every other building is unaffected.
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)
	var wall_cell := Vector2i(10, 6)
	var hall_cell := Vector2i(12, 6)
	var wall := buildings.add_building(BuildingSim.def_by_id(&"wall"), 1, wall_cell)
	buildings.add_building(BuildingSim.def_by_id(&"town_centre"), 1, hall_cell)

	assert_false(buildings.blocking_cells().has(space.index(wall_cell)),
		"an unfinished wall must not block — its builder could be sealed in by its own chain")
	assert_true(buildings.blocking_cells().has(space.index(hall_cell)),
		"this fix is wall-family only — an ordinary building still blocks while under construction")

	buildings.advance_construction(BuildingSim.def_by_id(&"wall").build_time)
	assert_true(buildings.is_complete(wall), "setup: the wall should have finished")
	assert_true(buildings.blocking_cells().has(space.index(wall_cell)),
		"a COMPLETE wall blocks exactly as before, including against its own builder")


## Guards the playtest fix letting a wall_tower be raised in place of an
## already-built wall segment (BuildingDef.upgrade_from), instead of
## requiring it be torn down first. server.gd has no test file of its own
## (a Node, not scene-tree-dependent for these two methods), so it is
## instantiated directly and its state set by hand — exactly the state
## `_upgrade_target_at`/`_is_buildable` actually read, nothing more.
func test_a_compatible_upgrade_replaces_the_old_building_in_place() -> void:
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var server = load("res://server.gd").new()
	server._sim = sim
	server._buildings = buildings
	server._passable = PackedByteArray()  # empty means "fully open"

	var wall_cell := Vector2i(10, 6)
	var wall := buildings.add_building(BuildingSim.def_by_id(&"wall"), 1, wall_cell, true)
	var tower_def := BuildingSim.def_by_id(&"wall_tower")
	var wall_def := BuildingSim.def_by_id(&"wall")

	assert_eq(server._upgrade_target_at(wall_cell, tower_def, 1), wall,
		"a complete, owned wall should be a valid upgrade target for a tower")
	assert_eq(server._upgrade_target_at(wall_cell, tower_def, 2), -1,
		"a different owner's wall must not be upgradeable")
	assert_eq(server._upgrade_target_at(wall_cell, wall_def, 1), -1,
		"only a def that actually lists this as an upgrade source qualifies")

	assert_true(server._is_buildable(wall_cell, tower_def, 1),
		"occupied ground must still be buildable when it is a compatible upgrade")
	# D-096 changed this case ON PURPOSE, so it is re-pointed rather than
	# deleted. A cell is an ANCHOR for the wall family, not an exclusive
	# slot: consecutive segments of a continuously-placed run sit ~1.77
	# apart while a hex is ~1.73 across, so two of them occasionally round
	# into the same cell, and refusing the second would leave a hole in a
	# wall the player watched themselves draw.
	assert_true(server._is_buildable(wall_cell, wall_def, 1),
		"two wall-family segments may share an anchor cell (D-096) — they stand at different offsets")

	# The rule this assertion originally existed to guard is still real for
	# everything that is NOT wall-on-wall, which is what keeps it a guard
	# rather than a relaxation: a storehouse may not be dropped onto a cell
	# a wall already anchors in.
	var storehouse_def := BuildingSim.def_by_id(&"storehouse")
	assert_false(server._is_buildable(wall_cell, storehouse_def, 1),
		"ordinary occupied ground still refuses a non-wall build")
	assert_false(server._is_buildable(wall_cell),
		"and the no-def/no-owner call every OTHER caller still uses is unaffected")

	# The still-under-construction case: nothing finished to upgrade yet.
	buildings.add_building(BuildingSim.def_by_id(&"wall"), 1, Vector2i(4, 4))
	assert_eq(server._upgrade_target_at(Vector2i(4, 4), tower_def, 1), -1,
		"a wall not yet complete has nothing finished to replace")

	server.free()


func test_a_resource_node_is_ground_you_cannot_build_on() -> void:
	# Playtest fix. Nothing consulted the economy when deciding whether
	# ground was buildable, so a town centre could be founded directly on
	# top of a forest: the node stayed gatherable underneath, the building
	# stood in the middle of it, and the gatherers who need to stand there
	# were quietly denied the cell. Nothing FAILED, which is why it survived
	# — the same shape as this project's other declared-but-unenforced rules.
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var server = load("res://server.gd").new()
	server._sim = sim
	server._buildings = buildings
	server._passable = PackedByteArray()  # empty means "fully open"

	var wood_cell := Vector2i(9, 5)
	var clear_cell := Vector2i(12, 5)
	assert_true(server._is_buildable(wood_cell),
		"setup: with no economy attached this ground should be free")

	var economy := Economy.new(space)
	# `stock_for(kind)`, not a single NODE_STOCK constant: stock is per-kind
	# since forests became many small trees rather than one rich marker, so
	# this seeds the node the same way `Economy` itself does.
	economy.nodes[space.index(wood_cell)] = {
		"kind": Economy.ResourceKind.WOOD,
		"remaining": Economy.stock_for(Economy.ResourceKind.WOOD),
	}
	server._economy = economy

	assert_false(server._is_buildable(wood_cell),
		"a cell holding a live resource node must refuse a build")
	assert_true(server._is_buildable(clear_cell),
		"ordinary ground beside it is unaffected")

	# A depleted node is not an obstacle — `has_node` is about live stock,
	# and ground you have finished mining should build like any other.
	economy.nodes[space.index(wood_cell)]["remaining"] = 0
	assert_true(server._is_buildable(wood_cell),
		"an exhausted node must stop blocking, or the map fills with permanent dead spots")

	server.free()


## Issue #55: the refusal must name the reason that actually fired.
##
## `_is_buildable` rejects on FOUR conditions and the message enumerated
## three of them — the resource-node rule landed later as a playtest fix
## and the wording was never updated. On the reported `highlands` world,
## 348 of 1,174 walkable cells (29.6%) were refused by a node while being
## told to look for water or a mountain, and the client's ghost draws
## GREEN over a node it has not been shown, so the named reason is also
## the only thing that explains an unrevealed one.
##
## Every branch is asserted through `_build_refusal`, which is now the one
## definition of the rule (`_is_buildable` is a wrapper over it), against a
## world built the way the server builds its own: real terrain, real
## passability, real nodes.
func test_a_refused_build_names_which_of_the_four_reasons_it_was() -> void:
	var space := TorusSpace.new(48, 32, 1.0)
	var terrain := TerrainGen.new()
	var passable := terrain.passability(space)

	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var server = load("res://server.gd").new()
	server._sim = sim
	server._buildings = buildings
	server._passable = passable
	server._terrain = terrain

	# Found one cell of each impassable kind rather than asserting against
	# a hand-built `_passable`: the point of the distinction is that
	# `_passable` CANNOT make it, so a fixture that fakes the array would
	# be testing the wrong thing.
	var water := Vector2i(-1, -1)
	var mountain := Vector2i(-1, -1)
	var open := Vector2i(-1, -1)
	for i in range(space.cell_count()):
		var cell := space.from_index(i)
		if passable[i] == 1:
			if open.x < 0:
				open = cell
			continue
		if terrain.is_water(space, cell):
			if water.x < 0:
				water = cell
		elif mountain.x < 0:
			mountain = cell
	assert_true(water.x >= 0 and mountain.x >= 0 and open.x >= 0,
		"setup: the default generator should give this map water, mountain and open ground")

	assert_eq(server._build_refusal(open), "",
		"setup: ordinary open ground must refuse nothing")
	assert_true(server._build_refusal(water).contains("water"),
		"a lake must say it is water — not 'water, steep ground, or already occupied'")
	assert_true(server._build_refusal(mountain).contains("steep"),
		"steep ground must say it is too steep "
		+ "(D-20260826-passable-means-flat-enough-to-cross: the biome no longer decides)")
	assert_false(server._build_refusal(water).contains("steep"),
		"and neither may name the other, or the message is the same shrug in longer words")

	# The reason the issue exists: a forest, on ground that is neither
	# water, nor mountain, nor occupied.
	var economy := Economy.new(space)
	economy.nodes[space.index(open)] = {
		"kind": Economy.ResourceKind.WOOD,
		"remaining": Economy.stock_for(Economy.ResourceKind.WOOD),
	}
	server._economy = economy
	var node_refusal: String = server._build_refusal(open)
	assert_true(node_refusal.contains("forest"),
		"a cell blocked by a resource node must say so — this is issue #55 itself")
	assert_false(node_refusal.contains("water") or node_refusal.contains("mountain"),
		"and must not send the player looking for terrain that is not there")
	# The kind is named, so a gold seam does not report itself as a wood.
	economy.nodes[space.index(open)]["kind"] = Economy.ResourceKind.GOLD
	assert_true(server._build_refusal(open).contains("gold"),
		"the node's KIND is what the player is looking at; naming the wrong one is a new lie")

	# Occupied ground names what is standing there, which is also what the
	# old message only ever managed to be right about.
	economy.nodes.erase(space.index(open))
	var hall_def := BuildingSim.def_by_id(&"town_centre")
	buildings.add_building(hall_def, 1, open, true)
	assert_true(server._build_refusal(open).contains(hall_def.display_name),
		"occupied ground must name the building occupying it")

	# The wrapper still answers exactly what it always did, so every
	# existing caller and test is unaffected by the rule gaining a voice.
	assert_false(server._is_buildable(water), "the bool wrapper must still refuse water")
	assert_false(server._is_buildable(open), "and must still refuse occupied ground")

	server.free()


func test_an_open_gate_stops_blocking_but_a_closed_one_still_does() -> void:
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)
	var gate_cell := Vector2i(10, 6)
	var gate := buildings.add_building(BuildingSim.def_by_id(&"gate"), 1, gate_cell, true)

	assert_true(buildings.blocking_cells().has(space.index(gate_cell)),
		"a new gate starts closed and must block")

	buildings.set_gate_open(gate, true)
	assert_false(buildings.blocking_cells().has(space.index(gate_cell)),
		"an OPEN gate must not block — occupied_cells() still reports it, blocking_cells() must not")
	assert_true(buildings.occupied_cells().has(space.index(gate_cell)),
		"the gate still stands there for placement/combat purposes even while open")

	buildings.set_gate_open(gate, false)
	assert_true(buildings.blocking_cells().has(space.index(gate_cell)),
		"closing it again must block again")


func test_a_flow_field_routes_around_a_closed_wall() -> void:
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)

	var wall_cell := Vector2i(10, 6)
	buildings.add_building(BuildingSim.def_by_id(&"wall"), 1, wall_cell, true)
	for index in buildings.blocking_cells():
		if index < passable.size():
			passable[index] = 0
	sim.set_passable(passable)

	var squad := sim.add_squad(_unit_def(), 2, Vector2i(4, 6))
	sim.order_move(squad, Vector2i(16, 6))
	for _i in range(400):
		sim.tick()

	assert_ne(sim.cell_of(squad), wall_cell, "a squad must not walk onto the wall's cell")
	assert_lt(space.distance(sim.cell_of(squad), Vector2i(16, 6)), 3,
		"the squad should still have reached near its destination by going around")


func test_gate_defaults_to_auto_mode_and_closed() -> void:
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)
	var gate := buildings.add_building(BuildingSim.def_by_id(&"gate"), 1, Vector2i(4, 4), true)
	assert_false(buildings.is_gate_open(gate), "a new gate starts closed")
	assert_eq(buildings.gate_mode(gate), BuildingSim.GATE_MODE_AUTO,
		"a new gate starts in auto mode — the ergonomic default")


func test_setting_gate_state_and_mode_marks_the_building_dirty_and_a_no_op_does_not() -> void:
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)
	var gate := buildings.add_building(BuildingSim.def_by_id(&"gate"), 1, Vector2i(4, 4), true)
	buildings.take_dirty()

	buildings.set_gate_open(gate, true)
	assert_eq(buildings.take_dirty(), [gate], "opening a gate must replicate")

	buildings.set_gate_open(gate, true)
	assert_eq(buildings.take_dirty(), [],
		"setting the SAME state again must not resend — D-003's zero-cost-when-idle claim")

	buildings.set_gate_mode(gate, BuildingSim.GATE_MODE_MANUAL)
	assert_eq(buildings.take_dirty(), [gate], "switching mode must replicate")


func test_only_the_tower_piece_stores_a_door_direction() -> void:
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)

	var tower := buildings.add_building(
		BuildingSim.def_by_id(&"wall_tower"), 1, Vector2i(6, 6), true, -1, 2)
	assert_eq(buildings.access_direction_of(tower), 2)
	assert_eq(buildings.access_direction_at(space.index(Vector2i(6, 6))), 2)

	# A door direction handed to a building that isn't an access tower must
	# be ignored — BuildingDef.is_access_tower's own doc explains why the
	# field is per-instance at all: only a tower ever reads it.
	var wall := buildings.add_building(
		BuildingSim.def_by_id(&"wall"), 1, Vector2i(8, 8), true, -1, 3)
	assert_eq(buildings.access_direction_of(wall), -1,
		"a plain wall segment must not become a climb point just because a direction was passed")


func test_every_building_carries_a_facing_not_just_the_tower(
		) -> void:
	# D-076 amendment: facing was generalised from the access-tower-only
	# door direction to a per-instance rotation every building carries,
	# for the rotate-while-placing control. access_direction_of stays
	# tower-only (the test above); facing_of answers the general question.
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)

	var town_hall := buildings.add_building(
		BuildingSim.def_by_id(&"town_centre"), 1, Vector2i(4, 4), true, -1, 4)
	assert_eq(buildings.facing_of(town_hall), 4,
		"an ordinary building's chosen facing must be stored and readable")

	var default_facing := buildings.add_building(
		BuildingSim.def_by_id(&"wall"), 1, Vector2i(6, 4), true)
	assert_eq(buildings.facing_of(default_facing), 0,
		"a building placed with no facing argument defaults to 0 (east)")

	# D-096 moved the 6-way wrap to the ACCESS TOWER alone. Its door has to
	# open onto a real neighbouring cell, so it is the one structure whose
	# facing still has to be one of the six. Walls used to wrap here too,
	# and that is exactly what locked a wall run to six angles.
	var wrapped := buildings.add_building(
		BuildingSim.def_by_id(&"wall_tower"), 1, Vector2i(8, 4), true, -1, 9)
	assert_eq(buildings.facing_of(wrapped), 3,
		"an access tower's out-of-range facing must wrap into 0..5 (9 mod 6), never be stored raw")


func test_a_freestanding_buildings_facing_is_a_continuous_byte_not_a_hex_direction(
		) -> void:
	# Placement decoupling: a wall/gate/access-tower's facing MUST stay one
	# of 6 hex directions (wall-joint alignment, the door), but a
	# freestanding building's is purely cosmetic (client.gd's
	# scroll-to-rotate control), so it must NOT be forced through the same
	# mod-6 wrap — that would silently put it back on a 6-way grid. See
	# `add_building`'s own `wraps_to_hex_direction` split.
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)

	var storehouse := buildings.add_building(
		BuildingSim.def_by_id(&"storehouse"), 1, Vector2i(4, 4), true, -1, 200)
	assert_eq(buildings.facing_of(storehouse), 200,
		"a freestanding building's facing byte must survive un-wrapped-mod-6 (200, not 200 mod 6 = 2)")

	var wrapped_byte := buildings.add_building(
		BuildingSim.def_by_id(&"storehouse"), 1, Vector2i(6, 4), true, -1, 300)
	assert_eq(buildings.facing_of(wrapped_byte), 300 - 256,
		"still wrapped into a sane byte range (300 mod 256 = 44), just not mod 6")


func test_building_info_entries_carry_facing() -> void:
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)
	var id := buildings.add_building(
		BuildingSim.def_by_id(&"wall"), 1, Vector2i(4, 4), true, -1, 5)

	var entries := buildings.info_entries([id])
	assert_eq(int(entries[0]["facing"]), 5,
		"the wire payload must carry the facing a client needs to render the same rotation")


func test_walkable_top_cells_only_include_complete_living_walkway_buildings() -> void:
	var space := TorusSpace.new(32, 16, 1.0)
	var buildings := BuildingSim.new(space)

	var wall := buildings.add_building(BuildingSim.def_by_id(&"wall"), 1, Vector2i(4, 4), true)
	var rampart := buildings.add_building(
		BuildingSim.def_by_id(&"garrison_wall"), 1, Vector2i(6, 4), true)
	buildings.add_building(BuildingSim.def_by_id(&"garrison_wall"), 1, Vector2i(8, 4), false)

	var top := buildings.walkable_top_cells()
	assert_false(top.has(space.index(Vector2i(4, 4))), "a plain wall has no walkway")
	assert_true(top.has(space.index(Vector2i(6, 4))), "a complete garrison wall is part of the walkway")
	assert_false(top.has(space.index(Vector2i(8, 4))), "a still-under-construction one is not walkable yet")
	assert_eq(wall, 0, "sanity: the plain wall really is the first building added")

	buildings.damage(rampart, 100000.0)
	assert_false(buildings.walkable_top_cells().has(space.index(Vector2i(6, 4))),
		"a destroyed rampart drops out of the walkway")


func test_a_wall_can_be_destroyed_with_shipped_data() -> void:
	# Walls have no attack of their own (damage 0) — unlike the town centre
	# and tower, nothing here is meant to survive a lone squad. This is a
	# smoke test that the shipped .tres actually behaves that way, not a
	# new mechanism: Combat.resolve_squads_vs_buildings already handles any
	# BuildingDef generically.
	var space := TorusSpace.new(42, 48, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var wall_cell := Vector2i(20, 20)
	var wall := buildings.add_building(BuildingSim.def_by_id(&"wall"), 1, wall_cell, true)

	var militia := UnitRoster.by_id(&"gildedreach_levy")
	assert_not_null(militia)
	var squad := sim.add_squad(militia, 2, Vector2i(20, 22))
	sim.order_attack_move(squad, wall_cell)

	var destroyed := false
	for _i in range(600):
		sim.tick()
		if buildings.is_destroyed(wall):
			destroyed = true
			break

	assert_true(destroyed,
		"a single squad should break an undefended wall segment — it has no return fire to deter one")


# --- gate/build wire orders (D-076) ---------------------------------------

func test_build_orders_round_trip_a_facing() -> void:
	var bytes := NetProtocol.encode_order_build(4, "wall_tower", 129, 3)
	var decoded := NetProtocol.decode_order_build(bytes)
	assert_eq(int(decoded["facing"]), 3)

	# Every building carries a facing now (D-076 amendment) — not just the
	# access tower's door — defaulting to 0 (east) for a caller that does
	# not choose one.
	var plain := NetProtocol.decode_order_build(NetProtocol.encode_order_build(4, "wall", 129))
	assert_eq(int(plain["facing"]), 0)


func test_build_queue_orders_round_trip_and_use_their_own_opcode() -> void:
	# D-076 amendment: the drag-to-build-a-line tool needs its own opcode
	# so the server can tell "replace the queue" (C2S_ORDER_BUILD) apart
	# from "append to it" (C2S_ORDER_BUILD_QUEUE) — same payload shape,
	# decoded by the same decode_order_build, distinguished only by which
	# opcode byte led it in.
	var bytes := NetProtocol.encode_order_build_queue(7, "garrison_wall", 55, 2)
	assert_eq(NetProtocol.opcode_of(bytes), NetProtocol.C2S_ORDER_BUILD_QUEUE)
	assert_ne(NetProtocol.opcode_of(bytes), NetProtocol.C2S_ORDER_BUILD)

	var decoded := NetProtocol.decode_order_build(bytes)
	assert_eq(int(decoded["squad"]), 7)
	assert_eq(String(decoded["def_id"]), "garrison_wall")
	assert_eq(int(decoded["cell"]), 55)
	assert_eq(int(decoded["facing"]), 2)


func test_gate_state_and_mode_orders_round_trip() -> void:
	var open_bytes := NetProtocol.encode_order_gate_state(BuildingSim.wire_id(2), true)
	assert_eq(NetProtocol.opcode_of(open_bytes), NetProtocol.C2S_ORDER_GATE_STATE)
	var open_decoded := NetProtocol.decode_order_gate_state(open_bytes)
	assert_eq(int(open_decoded["building"]), BuildingSim.wire_id(2))
	assert_true(bool(open_decoded["open"]))

	var mode_bytes := NetProtocol.encode_order_gate_mode(
		BuildingSim.wire_id(2), BuildingSim.GATE_MODE_MANUAL)
	assert_eq(NetProtocol.opcode_of(mode_bytes), NetProtocol.C2S_ORDER_GATE_MODE)
	var mode_decoded := NetProtocol.decode_order_gate_mode(mode_bytes)
	assert_eq(int(mode_decoded["mode"]), BuildingSim.GATE_MODE_MANUAL)


func test_building_info_round_trips_gate_state() -> void:
	var entries := [{
		"id": BuildingSim.wire_id(1), "def_id": "gate", "owner": 1,
		"cell": 5, "progress": 1.0, "destroyed": false,
		"gate_open": true, "gate_mode": BuildingSim.GATE_MODE_MANUAL,
	}]
	var decoded := NetProtocol.decode_building_info(NetProtocol.encode_building_info(entries))
	assert_true(bool(decoded[0]["gate_open"]))
	assert_eq(int(decoded[0]["gate_mode"]), BuildingSim.GATE_MODE_MANUAL)


func test_building_info_round_trips_facing() -> void:
	var entries := [{
		"id": BuildingSim.wire_id(1), "def_id": "wall_tower", "owner": 1,
		"cell": 5, "progress": 1.0, "destroyed": false, "facing": 4,
	}]
	var decoded := NetProtocol.decode_building_info(NetProtocol.encode_building_info(entries))
	assert_eq(int(decoded[0]["facing"]), 4)


func test_building_info_defaults_facing_to_east_when_unspecified() -> void:
	var entries := [{
		"id": BuildingSim.wire_id(1), "def_id": "wall", "owner": 1,
		"cell": 5, "progress": 1.0, "destroyed": false,
	}]
	var decoded := NetProtocol.decode_building_info(NetProtocol.encode_building_info(entries))
	assert_eq(int(decoded[0]["facing"]), 0)


func test_building_info_defaults_gate_fields_for_a_non_gate_entry() -> void:
	# Sent uniformly rather than conditionally, like every other
	# per-building field — an entry that never mentions gate state must
	# still decode to sane, harmless defaults.
	var entries := [{
		"id": BuildingSim.wire_id(1), "def_id": "wall", "owner": 1,
		"cell": 5, "progress": 1.0, "destroyed": false,
	}]
	var decoded := NetProtocol.decode_building_info(NetProtocol.encode_building_info(entries))
	assert_false(bool(decoded[0]["gate_open"]))
	assert_eq(int(decoded[0]["gate_mode"]), BuildingSim.GATE_MODE_MANUAL)


# --- D-20260821-a-recruit-steps-out-the-near-door ----------------------

func test_a_recruit_appears_on_the_rally_side_of_its_building() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	var home := Vector2i(9, 9)
	var id := buildings.add_building(_building_def(), 1, home, true)

	# Two opposite rallies must produce two different doors, each on its
	# own side. The enumeration-order spawn put every recruit on the same
	# lattice-chosen side regardless of the rally, and the squad then
	# marched around its own building.
	var east_rally := space.normalize(home + Vector2i(6, 0))
	var west_rally := space.normalize(home + Vector2i(-6, 0))
	buildings.set_rally(id, east_rally)
	var east_door := sim._spawn_cell_near(buildings, id)
	buildings.set_rally(id, west_rally)
	var west_door := sim._spawn_cell_near(buildings, id)

	assert_ne(east_door, west_door, "the door follows the rally point")
	assert_lt(space.distance(east_door, east_rally),
		space.distance(west_door, east_rally),
		"the east recruit stands nearer the east rally than the west one")
	assert_eq(space.distance(east_door, home), 2,
		"the bearing never costs the ring — a recruit still stands at the door")
	assert_eq(space.distance(west_door, home), 2,
		"same on the far side")
