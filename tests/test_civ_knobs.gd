extends GutTest

## Guards the three MECHANICAL knobs on `CivDef` (D-047, issue #158):
## `squad_cap_bonus`, `production_speed` and `gather_speed`.
##
## They shipped declared, non-default in the data, and read by NOTHING for
## a milestone — the fourth instance of this project's declared-and-unread
## defect class after `UnitDef.cost`, `BuildingDef.cost` and
## `BuildingSim.damage()` (D-055, which meant no match could be won for
## two milestones). Nothing failed; the two shipped civs simply differed
## by their roster, their colour and their opening stockpile, while three
## fields said otherwise.
##
## So this file asserts two different kinds of thing, and the second kind
## is the one that would have caught it:
##
## - the knobs DO something — a bonus seats another squad, a fast civ
##   trains sooner, a rich civ gathers more from the same node;
## - and something that SHIPS reads each of them. Every behaviour test
##   here can pass with the server never applying any of it, because a
##   mechanism with no caller fails nothing. `test_terrain_fog.gd` learned
##   the same lesson for D-106 and this is the same shape.


const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


## A civ that turns every knob, built here rather than picked out of
## /civs. No shipped civ turns `gather_speed` at all, so a fixture reading
## the roster would silently prove nothing about a third of this file —
## and pinning a test to a shipped value would make a data change fail an
## engine test.
func _civ(cap_bonus: int, production: float, gather: float) -> CivDef:
	var d := CivDef.new()
	d.id = &"fixture"
	d.squad_cap_bonus = cap_bonus
	d.production_speed = production
	d.gather_speed = gather
	return d


func _gatherer_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"gatherers"
	d.squad_size = 10
	d.health = 30.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.move_speed = 4.0
	d.formation_shape = "sparse"
	d.formation_spacing = 1.0
	d.morale = 100.0
	d.carry_capacity = 200
	d.gather_rate = 1.0
	return d


func _drop_off_def() -> BuildingDef:
	var d := BuildingDef.new()
	d.id = &"town_centre"
	d.max_health = 500.0
	d.is_drop_off = true
	d.vision_range = 10.0
	return d


# --- the arithmetic, in one place (CivDef) -----------------------------

func test_the_knobs_are_applied_by_the_schema_and_not_by_each_caller() -> void:
	var civ := _civ(4, 1.3, 1.25)
	assert_eq(civ.squad_cap(40), 44,
		"the cap bonus is ADDITIVE — the map keeps the final say on scale (D-018)")
	assert_almost_eq(civ.production_time(13.0), 10.0, 0.001,
		"a production_speed above 1.0 must SHORTEN the time, not lengthen it")
	assert_almost_eq(civ.gather_rate(1.0), 1.25, 0.001)


func test_a_civ_that_turns_nothing_changes_nothing() -> void:
	# The default-constructed CivDef is what an unknown civ resolves to,
	# so "no civ" and "a civ at its defaults" have to be the same numbers
	# or every mechanism needs a second code path for the unseated.
	var plain := CivDef.new()
	assert_eq(plain.squad_cap(40), 40)
	assert_almost_eq(plain.production_time(13.0), 13.0, 0.001)
	assert_almost_eq(plain.gather_rate(1.0), 1.0, 0.001)


func test_an_unknown_civ_resolves_to_the_schema_defaults_rather_than_null() -> void:
	var neutral := CivRoster.effects_of(&"")
	assert_not_null(neutral,
		"effects_of must never answer null — a caller branching on 'is there a civ'"
		+ " is a second default free to disagree with civ_def.gd")
	assert_eq(neutral.squad_cap_bonus, CivDef.new().squad_cap_bonus)
	assert_almost_eq(neutral.production_speed, CivDef.new().production_speed, 0.001)
	assert_almost_eq(neutral.gather_speed, CivDef.new().gather_speed, 0.001)


func test_a_shipped_civ_resolves_to_itself() -> void:
	var ids := CivRoster.ids()
	assert_gt(ids.size(), 0, "no civs are shipped at all")
	assert_eq(CivRoster.effects_of(ids[0]).id, ids[0])


func test_the_shipped_data_actually_turns_at_least_one_knob() -> void:
	# Wiring knobs nobody sets would be the D-066 failure — mechanism
	# correct, shipped numbers do nothing. If this ever goes red the fix
	# is a decision about civ identity, not a looser assertion.
	var turned := 0
	for def in CivRoster.load_all():
		if def.squad_cap_bonus != 0 \
				or not is_equal_approx(def.production_speed, 1.0) \
				or not is_equal_approx(def.gather_speed, 1.0):
			turned += 1
	assert_gt(turned, 0,
		"every shipped civ leaves all three mechanical knobs at their default — "
		+ "civ differentiation would be roster-only, which is #158's other option")


# --- the cap (D-033) ---------------------------------------------------

func test_a_civ_bonus_raises_that_players_squad_cap() -> void:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var match_state := MatchState.new()
	match_state.squad_cap = 5
	sim.civs[1] = _civ(4, 1.0, 1.0)

	assert_eq(match_state.squad_cap_for(sim, 1), 9)
	assert_eq(match_state.squad_cap_for(sim, 2), 5,
		"a player whose civ is unknown keeps the map's own cap")


func test_the_bonus_is_what_the_refusal_actually_counts() -> void:
	# The cap that matters is the one `has_squad_capacity` enforces, not
	# the one a helper reports: D-061's family is a rule that is fully
	# written and read from nowhere the player can reach.
	var space := _space()
	var generous := SquadSim.new(space, CurveReplicator.new())
	var plain := SquadSim.new(space, CurveReplicator.new())
	generous.civs[1] = _civ(2, 1.0, 1.0)

	var match_state := MatchState.new()
	match_state.squad_cap = 2
	for i in range(2):
		generous.add_squad(_gatherer_def(), 1, Vector2i(4 + i, 4))
		plain.add_squad(_gatherer_def(), 1, Vector2i(4 + i, 4))

	assert_false(match_state.has_squad_capacity(plain, 1),
		"two squads against a cap of two is full")
	assert_true(match_state.has_squad_capacity(generous, 1),
		"the same two squads on the same map, for a civ that brings +2")


# --- production (D-028) ------------------------------------------------

func test_a_faster_civ_finishes_a_unit_sooner() -> void:
	var buildings := BuildingSim.new(_space())
	var barracks := buildings.add_building(_drop_off_def(), 1, Vector2i(4, 4), true)
	var unit := _gatherer_def()
	unit.build_time = 10.0

	var civ := _civ(0, 2.0, 1.0)
	buildings.enqueue(barracks, unit, false, civ.production_time(unit.build_time))

	var finished_at := -1.0
	for i in range(200):
		if not buildings.advance_production(0.1).is_empty():
			finished_at = (i + 1) * 0.1
			break
	assert_almost_eq(finished_at, 5.0, 0.15,
		"a civ at production_speed 2.0 must take half the def's build_time")


func test_production_time_is_stored_as_seconds_the_client_can_count_down() -> void:
	# The wire carries `head_remaining` and the client counts it down at
	# one second per second (D-003). A civ multiplier applied per TICK
	# instead of at enqueue would leave every client's "— 12s" wrong.
	var buildings := BuildingSim.new(_space())
	var barracks := buildings.add_building(_drop_off_def(), 1, Vector2i(4, 4), true)
	var unit := _gatherer_def()
	unit.build_time = 10.0

	var civ := _civ(0, 2.0, 1.0)
	buildings.enqueue(barracks, unit, false, civ.production_time(unit.build_time))
	var entry: Dictionary = buildings.info_entries([barracks])[0]
	assert_almost_eq(float(entry["head_remaining"]), 5.0, 0.001,
		"the queue head is real seconds, already carrying the civ's speed")


func test_omitting_the_time_still_means_the_defs_own_build_time() -> void:
	# Every caller that has no civ to resolve — a fixture, a sandbox path
	# — must keep the behaviour it had before #158.
	var buildings := BuildingSim.new(_space())
	var barracks := buildings.add_building(_drop_off_def(), 1, Vector2i(4, 4), true)
	var unit := _gatherer_def()
	unit.build_time = 10.0

	buildings.enqueue(barracks, unit)
	var entry: Dictionary = buildings.info_entries([barracks])[0]
	assert_almost_eq(float(entry["head_remaining"]), 10.0, 0.001)


# --- gathering (D-028) -------------------------------------------------

func _haul_take(civ) -> int:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	var economy := Economy.new(space)
	sim.buildings = buildings
	sim.economy = economy
	if civ != null:
		sim.civs[1] = civ

	var node_cell := Vector2i(10, 8)
	var node := space.index(node_cell)
	economy.nodes[node] = {"kind": Economy.ResourceKind.WOOD, "remaining": 500}
	buildings.add_building(_drop_off_def(), 1, Vector2i(8, 8), true)
	var squad := sim.add_squad(_gatherer_def(), 1, node_cell)

	assert_true(economy.order_gather(sim, squad, node))
	for _i in range(20):
		sim.tick()
	return 500 - economy.remaining_at(node)


func test_a_civ_with_a_gathering_bonus_takes_more_from_the_same_node() -> void:
	var plain := _haul_take(null)
	var fast := _haul_take(_civ(0, 1.0, 2.0))
	assert_gt(plain, 0, "the fixture must gather at all, or this proves nothing")
	assert_gt(fast, plain,
		"gather_speed above 1.0 must put more wood in the wagon in the same time")


func test_a_civ_at_the_default_gathers_exactly_what_no_civ_does() -> void:
	assert_eq(_haul_take(_civ(0, 1.0, 1.0)), _haul_take(null),
		"turning no knob must be bit-for-bit the behaviour that shipped")


# --- the checks that would actually have caught #158 -------------------

## Directories whose scripts do not count as a reader.
const EXEMPT_PREFIXES := ["res://tests/", "res://addons/"]


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))


func _shipping_callers_of(needle: String) -> Array:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10,
		"Found almost no scripts — the walk is broken, not the code clean")

	var callers: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str == "res://civ_def.gd":
			continue
		var exempt := false
		for prefix in EXEMPT_PREFIXES:
			if path_str.begins_with(prefix):
				exempt = true
		if exempt:
			continue
		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		if text.contains(needle):
			callers.append(path_str)
	return callers


## The one test in this file that #158 could not have passed.
##
## Every behaviour test above drives the mechanism by hand. The defect was
## never that the arithmetic was wrong — it was that nothing that ships
## performed it, which is invisible to a test of the arithmetic. So assert
## the CALLER exists, per knob.
func test_every_mechanical_knob_is_read_by_something_that_ships() -> void:
	var expected := {
		".squad_cap(": "res://match_state.gd",
		".production_time(": "res://server.gd",
		".gather_rate(": "res://economy.gd",
	}
	for needle in expected:
		var callers := _shipping_callers_of(needle)
		assert_true(callers.has(expected[needle]),
			("%s is applied by nothing that ships — a civ knob with no reader is "
			+ "not a weaker rule, it is no rule (#158). Expected %s.")
				% [needle, expected[needle]])


func test_the_simulation_is_told_who_plays_what() -> void:
	# The knobs are resolved off `SquadSim.civs`, and #119's lesson is
	# that the handover nothing performs is the dangerous half: a match
	# whose simulation never learned the civs applies every default while
	# every seat list and every client agrees who is who.
	assert_true(_shipping_callers_of("civs[player] =").has("res://server.gd"),
		"server.gd must hand the players' civs to the simulation")
	assert_true(_shipping_callers_of("civ_effects(").has("res://economy.gd"),
		"the economy must read the gatherer owner's civ")


# --- through the SERVER's own produce path ----------------------------
#
# Everything above this line drives the mechanism by hand, and the review
# of the first version of this work found the gap that leaves: with all
# three knobs unwired, both production BEHAVIOUR tests above stayed GREEN
# — they call `BuildingSim.enqueue` themselves, so they prove the
# arithmetic and say nothing about whether the server performs it. Only
# the source scan went red for `production_speed`, and a source scan
# cannot see a caller that passes the WRONG argument.
#
# "server.gd needs a socket and a scene tree" is this project's standing
# reason for testing it by source scan, and it is true of `_ready()`
# rather than of the whole file — the same distinction D-075's 2026-08-16
# amendment had to make for `client.gd`, where reading the claim too
# widely cost a milestone of matches with no terrain. `_handle_order_produce`
# needs neither: a Node that is never added to the tree does not run
# `_ready()`, and `LoopbackPeer` is already the server's own stand-in for
# a socket (D-051).
#
# So these drive the REAL function, with the REAL shipped defs, and each
# one fails if the server stops resolving a knob or resolves it wrongly.


## The shipped civ that trains fastest.
func _fastest_civ() -> CivDef:
	var best: CivDef = null
	for def in CivRoster.load_all():
		if best == null or def.production_speed > best.production_speed:
			best = def
	return best


## The shipped civ with the largest squad cap bonus.
func _most_numerous_civ() -> CivDef:
	var best: CivDef = null
	for def in CivRoster.load_all():
		if best == null or def.squad_cap_bonus > best.squad_cap_bonus:
			best = def
	return best


## A server far enough along to answer a produce order, and no further.
##
## Deliberately assembled the way the server assembles itself — `_civs`
## written as `_on_match_started` writes it, then `_hand_civs_to_sim()` —
## so the HANDOVER is inside what these tests exercise rather than being
## stepped around. Setting `_sim.civs` directly here would prove the knobs
## work in a server that never learned anybody's civ.
func _server_for(civ: StringName, cap: int) -> Dictionary:
	var server = load("res://server.gd").new()
	var space := TorusSpace.new(W, H, 1.0)

	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy

	server._match = MatchState.new()
	server._match.squad_cap = cap
	server._match.add_player(1)
	server._match.phase = MatchState.Phase.RUNNING
	server._civs[1] = civ
	server._hand_civs_to_sim()

	var barracks_def := BuildingSim.def_by_id(&"barracks")
	assert_not_null(barracks_def, "the shipped barracks is where BuildingSim looks for it")
	var barracks: int = server._buildings.add_building(barracks_def, 1, Vector2i(4, 4), true)

	# A wallet nothing here is about — the affordability gate is not under
	# test, and a refusal there would look exactly like a cap refusal.
	for kind in range(Economy.RESOURCE_COUNT):
		server._economy.credit(1, kind, 100000)

	var peer := LoopbackPeer.new()
	server._ai_clients[peer] = {"player": 1, "visible": {}}

	return {"server": server, "peer": peer, "barracks": barracks, "def": barracks_def}


## Something this civ fields from a barracks. Never the general: one per
## player is its own production gate, and a refusal there would read as a
## civ knob failing.
func _producible(civ: StringName, barracks_def: BuildingDef) -> UnitDef:
	for archetype in barracks_def.produces:
		var unit := UnitRoster.for_civ_archetype(civ, archetype)
		if unit != null and not unit.is_general:
			return unit
	return null


func _order_produce(w: Dictionary, unit: UnitDef) -> void:
	var server = w["server"]
	server._handle_order_produce(w["peer"], NetProtocol.encode_order_produce(
		BuildingSim.wire_id(w["barracks"]), String(unit.archetype)))


func test_the_server_trains_a_fast_civs_unit_in_that_civs_time() -> void:
	var civ := _fastest_civ()
	assert_not_null(civ, "no civs are shipped at all")
	assert_gt(civ.production_speed, 1.0,
		"no shipped civ trains faster than the default, so this test cannot tell "
		+ "a wired production_speed from an unwired one")

	var w := _server_for(civ.id, 40)
	var server = w["server"]
	var unit := _producible(civ.id, w["def"])
	assert_not_null(unit, "this civ fields nothing a barracks makes")
	_order_produce(w, unit)

	assert_eq(server._buildings.queue_length(w["barracks"]), 1,
		"the order should have been accepted")
	var entry: Dictionary = server._buildings.info_entries([w["barracks"]])[0]
	assert_almost_eq(float(entry["head_remaining"]),
		unit.build_time / civ.production_speed, 0.001,
		"the server must queue the OWNER'S CIV's training time, not the def's own")
	# And the two genuinely differ, or the assertion above would pass on a
	# server that ignores the civ entirely.
	assert_true(absf(float(entry["head_remaining"]) - unit.build_time) > 0.001,
		"this civ's time must differ from the raw build_time, or nothing is proven")
	server.free()


func test_the_server_lets_a_numerous_civ_past_the_maps_own_cap() -> void:
	var civ := _most_numerous_civ()
	assert_not_null(civ, "no civs are shipped at all")
	assert_gt(civ.squad_cap_bonus, 0,
		"no shipped civ raises the squad cap, so this test cannot tell a wired "
		+ "squad_cap_bonus from an unwired one")

	# Standing exactly at the map's own cap: one more squad is legal only
	# for a civ whose bonus is actually being read.
	var cap := 3
	var w := _server_for(civ.id, cap)
	var server = w["server"]
	var unit := _producible(civ.id, w["def"])
	assert_not_null(unit, "this civ fields nothing a barracks makes")
	for i in range(cap):
		server._sim.add_squad(unit, 1, Vector2i(8 + i, 8))
	assert_eq(server._sim.living_squad_count(1), cap,
		"setup: the player should be exactly at the map's cap")
	_order_produce(w, unit)

	assert_eq(server._buildings.queue_length(w["barracks"]), 1,
		"a civ carrying +%d must be allowed its squad past the map's %d"
			% [civ.squad_cap_bonus, cap])
	server.free()


func test_the_server_still_refuses_a_plain_civ_at_the_cap() -> void:
	# The counter-test, and the one that stops the pair above from passing
	# on a server that has simply stopped enforcing the cap at all.
	var plain: CivDef = null
	for def in CivRoster.load_all():
		if def.squad_cap_bonus == 0:
			plain = def
	assert_not_null(plain, "every shipped civ raises the cap — nothing holds the line")

	var cap := 3
	var w := _server_for(plain.id, cap)
	var server = w["server"]
	var unit := _producible(plain.id, w["def"])
	assert_not_null(unit, "this civ fields nothing a barracks makes")
	for i in range(cap):
		server._sim.add_squad(unit, 1, Vector2i(8 + i, 8))
	_order_produce(w, unit)

	assert_eq(server._buildings.queue_length(w["barracks"]), 0,
		"a civ with no bonus must still be refused at the map's own cap")
	server.free()


# --- what the bonus costs the tick budget ------------------------------

## `squad_cap` is an ENGINEERING ceiling for D-018/D-020, not a design
## lever (CLAUDE.md says so outright), and `squad_cap_bonus` adds to it —
## so the worst case a civ can produce is a number the tick budget has to
## have been measured against.
##
## PINNED rather than bounded. This is not a rule about what a civ may
## ask for; it is a tripwire that makes a future civ's bonus a DELIBERATE
## re-measurement instead of a silent one. If it goes red, take a fresh
## `just profile` at the new worst case and record it in
## `decisions/D-20260823-a-civs-knobs-are-read-by-the-simulation.md`
## before changing the number here.
const SWEEP_TOP_RUNG := 1000


func test_the_cap_bonus_worst_case_is_the_one_the_decision_records() -> void:
	var cap := 0
	for path in ["res://maps/default.tres", "res://maps/huge.tres", "res://maps/ladder.tres"]:
		var config := load(path) as MapConfig
		assert_not_null(config, "%s is not a MapConfig" % path)
		cap = maxi(cap, config.squad_cap)
	var bonus := 0
	for def in CivRoster.load_all():
		bonus = maxi(bonus, def.squad_cap_bonus)

	# D-018's stated target, which is what every sweep and every tick
	# figure in this repo is quoted against.
	assert_eq(20 * (cap + bonus), 880,
		"the 20-player worst case moved — re-measure and update the decision")
	assert_true(20 * (cap + bonus) <= SWEEP_TOP_RUNG,
		("a civ bonus has pushed D-018's 20 players past the %d squads "
		+ "`just profile` actually measures") % SWEEP_TOP_RUNG)

	# And the LOBBY's own ceiling, which sits above D-018's target on
	# purpose (MatchState.MAX_PLAYER_SLOTS: "D-018's 20-player target with
	# room above it"). Recorded rather than asserted safe: it is already
	# past the sweep's top rung with no civ bonus at all.
	assert_eq(MatchState.MAX_PLAYER_SLOTS * (cap + bonus), 1056,
		"the 24-seat worst case moved — re-measure and update the decision")
