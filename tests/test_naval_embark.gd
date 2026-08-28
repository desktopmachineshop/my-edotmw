extends GutTest

## Guards naval stage 4 — embark and disembark (#301,
## `docs/plans/naval.md` §3).
##
## ## What is here and what is deliberately not
##
## Stage 4's done-when is "a land squad crosses water and lands, and
## `composition_hash` matches with cargo aboard". **A hull cannot sail
## until naval stage 2**, which is delayed. So every voyage here is
## PLACED rather than sailed: the mechanism is complete and tested end to
## end, and the one clause that has to wait is the crossing itself. Said
## plainly rather than claimed — the last thing this estate needs is a
## green test standing in for a leg nobody has run.
##
## ## The two facts worth knowing before changing any of it
##
## **A carried squad is removed from the world, not flagged in it.** It
## goes through `alive = 0` exactly as `consume_squad` spends a founder,
## so every loop in `squad_sim.gd` that already guards `alive <= 0`
## excludes it for free. A flag would have needed all of them audited and
## the one missed would be a squad fighting from inside a boat with
## nothing failing.
##
## **That is also why the hashes agree.** The server hashes
## `visible_to(player)` and the client hashes what it holds live; a
## boarded squad reads on both sides exactly as a wiped one, which both
## sides have agreed about since M1. Nobody has to remember to skip
## cargo — D-099's lesson, which cost a real desync when a client folded
## its own ghosts in.

const W := 24
const H := 12


## Land on the left, water on the right, a dock on the boundary — the same
## hand-built coastline `test_naval_docks.gd` uses and for the same
## reason: a fixture whose shore depends on a seed proves something
## different next year.
func _world() -> Dictionary:
	var space := TorusSpace.new(W, H, 1.0)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var wet := coord.x >= 12 and coord.x < 20
		passable[index] = 0 if wet else 1
		navigable[index] = 1 if wet else 0

	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	sim.set_passable(passable)
	sim.set_navigable(navigable)

	# A dock on the last land column, with the first water column as its
	# water side — set the way `server._finish_build` sets it.
	var quay := Vector2i(11, 4)
	var water := Vector2i(12, 4)
	var dock: int = buildings.add_building(BuildingSim.def_by_id(&"dock"), 1, quay, true)
	buildings.set_water_cell(dock, space.index(water))

	return {"sim": sim, "buildings": buildings, "space": space,
		"quay": quay, "water": water, "dock": dock}


## A land cell the hull at `from` is genuinely adjacent to. Derived rather
## than written down: the landing rule is "beside the ground it was sent
## to", so a hardcoded beach that happens to be two cells away tests the
## NOT-arrived branch while looking like it tests the arrived one.
func _beach_beside(sim: SquadSim, from: Vector2i) -> Vector2i:
	for direction in TorusSpace.DIRECTIONS:
		var candidate := sim.space.normalize(from + direction)
		if sim.is_passable(candidate):
			return candidate
	return Vector2i(-1, -1)


func _transport(civ: StringName = &"gravesworn") -> UnitDef:
	var d := UnitRoster.for_civ_archetype(civ, &"transport")
	assert_not_null(d, "Setup: %s fields a transport" % civ)
	return d


func _land_unit(civ: StringName = &"gravesworn") -> UnitDef:
	var d := UnitRoster.for_civ_archetype(civ, &"levy")
	assert_not_null(d, "Setup: %s fields a levy" % civ)
	return d


## Place a hull at the dock's water cell and a land squad on the quay,
## then order the squad onto the hull and tick until it boards.
func _loaded(w: Dictionary, riders: int = 1) -> Dictionary:
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var boarded := []
	for i in range(riders):
		var squad := sim.add_squad(_land_unit(), 1, w["quay"])
		sim.order_move(squad, w["water"])
		for _t in range(20):
			sim.tick()
			if sim.alive_of(squad) <= 0:
				break
		boarded.append(squad)
	return {"hull": hull, "boarded": boarded}


# --- the fixture is what it claims -------------------------------------

func test_the_fixture_puts_a_hull_at_a_dock_a_land_squad_can_reach() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	assert_true(sim.is_navigable(w["water"]), "the hull's cell must be water")
	assert_true(sim.is_passable(w["quay"]), "the quay must be land")
	assert_eq(sim.space.distance(w["quay"], w["water"]), 1,
		"and they must be adjacent, or nothing can board")


# --- 1. cargo on the carrier -------------------------------------------

func test_a_squad_ordered_onto_a_friendly_transport_boards_it() -> void:
	# THE embark trigger. `order_move` onto a cell holding a friendly hull
	# with room is the embark order — see that function for why this
	# reading was taken and what it means for naval §2.4.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var loaded := _loaded(w)
	var hull: int = loaded["hull"]
	var squad: int = loaded["boarded"][0]

	assert_eq(sim.cargo_of(hull).size(), 1, "the squad is aboard")
	assert_eq(sim.alive_of(squad), 0, "and is no longer in the world")
	assert_eq(String(sim.cargo_of(hull)[0]["def_id"]), String(_land_unit().id),
		"and the hull knows what it is carrying")


func test_cargo_keeps_the_men_it_had_left() -> void:
	# A squad that boards at half strength lands at half strength. Losing
	# the count would make a transport a way to heal.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var squad := sim.add_squad(_land_unit(), 1, w["quay"])
	var half := int(sim.alive_of(squad) / 2)
	sim.set_alive(squad, half)
	sim.order_move(squad, w["water"])
	for _t in range(20):
		sim.tick()
		if sim.alive_of(squad) <= 0:
			break
	assert_eq(sim.cargo_of(hull).size(), 1, "it boarded")
	assert_eq(int(sim.cargo_of(hull)[0]["alive"]), half,
		"and brought exactly the men it had")


func test_a_hull_refuses_more_than_it_can_carry() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	var capacity := _transport().transport_capacity
	assert_gt(capacity, 0, "Setup: a transport carries something")
	var loaded := _loaded(w, capacity + 2)
	assert_eq(sim.cargo_of(loaded["hull"]).size(), capacity,
		"a hull carries its capacity and no more")
	# The ones that could not board are still standing on the quay.
	var still_ashore := 0
	for squad in loaded["boarded"]:
		if sim.alive_of(squad) > 0:
			still_ashore += 1
	assert_eq(still_ashore, 2, "the rest are left on the quay, not lost")


func test_a_ship_cannot_be_cargo() -> void:
	# §3.4's "no ship-to-ship transfer", falling out of the data rather
	# than needing a rule: a rider must be a ground unit.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var other := sim.add_squad(_transport(), 1, Vector2i(13, 4))
	assert_false(sim.can_carry(hull, other), "a hull may not board a hull")


func test_an_enemy_may_not_board_your_transport() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var thief := sim.add_squad(_land_unit(), 2, w["quay"])
	assert_false(sim.can_carry(hull, thief), "an enemy squad may not board")
	sim.order_move(thief, w["water"])
	for _t in range(20):
		sim.tick()
	assert_eq(sim.cargo_of(hull).size(), 0, "and ordering it there does not board it")
	assert_gt(sim.alive_of(thief), 0, "it is still in the world")


func test_an_ally_may_board_your_transport() -> void:
	# D-050 gives teams a shared front; a teammate who cannot use your
	# ferry is a worse partner than an enemy.
	var w := _world()
	var sim: SquadSim = w["sim"]
	sim.teams = {1: 1, 2: 1}
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var friend := sim.add_squad(_land_unit(), 2, w["quay"])
	assert_true(sim.are_allied(1, 2), "Setup: an actual alliance")
	assert_true(sim.can_carry(hull, friend))


func test_boarding_needs_a_dock_and_not_merely_a_hull() -> void:
	# §3.4: you load at a dock and nowhere else. Landing is the thing that
	# can happen anywhere, and that asymmetry is the design's centre.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var buildings: BuildingSim = w["buildings"]
	buildings.damage(w["dock"], 100000.0)  # no dock any more
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var squad := sim.add_squad(_land_unit(), 1, w["quay"])
	sim.order_move(squad, w["water"])
	for _t in range(20):
		sim.tick()
	assert_eq(sim.cargo_of(hull).size(), 0, "no dock, no boarding")
	assert_gt(sim.alive_of(squad), 0, "and the squad is not lost")


func test_a_hull_that_leaves_before_the_squad_arrives_takes_nobody() -> void:
	# Re-asked on ARRIVAL, never trusted from order time — a hull sails, is
	# sunk, or fills up while a squad walks to the quay. Every rule in this
	# codebase that survives a walk is re-checked the same way.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var squad := sim.add_squad(_land_unit(), 1, Vector2i(4, 4))  # far away
	sim.order_move(squad, w["water"])
	sim.tick()
	sim.set_alive(hull, 0)  # sunk while the squad was walking
	for _t in range(60):
		sim.tick()
	assert_gt(sim.alive_of(squad), 0, "the squad must not board a wreck")


# --- 2. the cap ---------------------------------------------------------

func test_cargo_still_counts_against_the_squad_cap() -> void:
	# §3.1: it is an army slot you are using. Leaving it out would make a
	# transport a way to hold more army than the cap allows.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var loaded := _loaded(w)
	assert_eq(sim.carried_squad_count(1), 1, "one squad is at sea")

	var match_state := MatchState.new()
	match_state.squad_cap = 2
	# One hull on the field plus one squad aboard is two of two.
	assert_false(match_state.has_squad_capacity(sim, 1),
		"a squad in a hold fills a slot")
	match_state.squad_cap = 3
	assert_true(match_state.has_squad_capacity(sim, 1))


# --- 3. sink kills cargo ------------------------------------------------

func test_when_a_hull_sinks_its_cargo_drowns() -> void:
	# §3.2, stated plainly because the alternative is worse: ejecting cargo
	# onto the nearest shore would make a transport strictly better than
	# not using one.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var loaded := _loaded(w)
	var hull: int = loaded["hull"]
	assert_eq(sim.cargo_of(hull).size(), 1, "Setup: laden")

	sim.set_alive(hull, 0)
	sim.tick()

	assert_eq(sim.cargo_of(hull).size(), 0, "the cargo went down with it")
	assert_eq(sim.last_drownings.size(), 1, "and the loss is reported")
	# Nobody reappears anywhere.
	var alive := 0
	for i in range(sim.squad_count()):
		if sim.alive_of(i) > 0:
			alive += 1
	assert_eq(alive, 0, "no rider is ejected onto the shore")


func test_a_hull_that_dies_empty_reports_no_drowning() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	sim.set_alive(hull, 0)
	sim.tick()
	assert_eq(sim.last_drownings.size(), 0, "an empty hull drowns nobody")


# --- 4. landing ---------------------------------------------------------

func test_a_laden_hull_ordered_at_land_puts_its_cargo_ashore() -> void:
	# §3.3's one leg. The hull is PLACED beside the beach rather than
	# sailed there — naval stage 2 is what moves it — so this tests the
	# landing and honestly not the crossing.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var loaded := _loaded(w)
	var hull: int = loaded["hull"]
	var beach := _beach_beside(sim, sim.cell_of(hull))
	assert_true(sim.is_passable(beach), "Setup: the target is land")
	assert_eq(sim.space.distance(sim.cell_of(hull), beach), 1,
		"Setup: and the hull is beside it")

	# Ticked until it ARRIVES rather than once. A hull ordered at land is
	# corrected (naval 2.4) to the nearest sea room, which need not be the
	# cell it is already on — so "ordered" and "arrived" are different
	# ticks even when the beach is one step away.
	sim.order_move(hull, beach)
	for _t in range(60):
		sim.tick()
		if not sim.last_landings.is_empty():
			break

	assert_eq(sim.cargo_of(hull).size(), 0, "the hold is empty")
	assert_eq(sim.last_landings.size(), 1, "and a squad came ashore")
	if sim.last_landings.is_empty():
		return
	var landed: int = sim.last_landings[0]
	assert_gt(sim.alive_of(landed), 0, "it is alive")
	assert_true(sim.is_passable(sim.cell_of(landed)),
		"and standing on ground it could have walked to")
	assert_lte(sim.space.distance(sim.cell_of(landed), beach), 4,
		"near where it was sent")


func test_a_landed_squad_is_an_ordinary_squad_that_kept_its_men() -> void:
	# §3.4: no assault penalty and no bonus. What it must keep is the men
	# it had and the shape its player chose.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var squad := sim.add_squad(_land_unit(), 1, w["quay"])
	sim.set_alive(squad, 9)
	sim.set_shape(squad, "column")
	sim.order_move(squad, w["water"])
	for _t in range(20):
		sim.tick()
		if sim.alive_of(squad) <= 0:
			break
	assert_eq(sim.cargo_of(hull).size(), 1, "Setup: aboard")

	sim.order_move(hull, _beach_beside(sim, sim.cell_of(hull)))
	for _t in range(60):
		sim.tick()
		if not sim.last_landings.is_empty():
			break
	assert_eq(sim.last_landings.size(), 1)
	if sim.last_landings.is_empty():
		return
	var landed: int = sim.last_landings[0]
	assert_eq(sim.alive_of(landed), 9, "it landed with the men it boarded with")
	assert_eq(sim.shape_of(landed), "column", "and the shape its player chose")


func test_a_hull_ordered_at_water_is_not_a_landing() -> void:
	# An ordinary move for a hull. Without this every repositioning order
	# would dump the army into the sea.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var loaded := _loaded(w)
	sim.order_move(loaded["hull"], Vector2i(15, 8))
	for _t in range(60):
		sim.tick()
	assert_eq(sim.cargo_of(loaded["hull"]).size(), 1, "the cargo stays aboard")
	assert_eq(sim.last_landings.size(), 0, "and nobody landed")


func test_a_hull_still_under_way_lands_nobody_yet() -> void:
	# The arrival test, stated as what it actually is. A laden hull puts
	# its cargo ashore when it ARRIVES — `_cell == _destination` — and not
	# before, or an army would be dropped in the water halfway across.
	#
	# It says "not yet" rather than "never" on purpose: a hull ordered
	# somewhere it cannot reach is corrected (naval 2.4) to the nearest
	# sea room it CAN reach, arrives there, and unloads — which is the
	# right behaviour and not what this test is about. Measured while
	# writing it: an earlier version claimed "never", ticked 120 times,
	# and went red because the hull had sensibly landed the army on the
	# nearest shore.
	var w := _channel()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var squad := sim.add_squad(_land_unit(), 1, w["quay"])
	sim.order_move(squad, w["water"])
	for _t in range(60):
		sim.tick()
		if sim.alive_of(squad) <= 0:
			break
	assert_eq(sim.cargo_of(hull).size(), 1, "Setup: aboard")

	# The far island, a long crossing away.
	sim.order_move(hull, Vector2i(21, 6))
	for _t in range(10):  # nowhere near enough to cross
		sim.tick()
	assert_ne(sim.cell_of(hull), sim.space.from_index(sim.space.index(Vector2i(21, 6))),
		"Setup: it has not arrived")
	assert_eq(sim.cargo_of(hull).size(), 1,
		"a hull still under way keeps its cargo aboard")
	assert_eq(sim.last_landings.size(), 0)
	assert_true(sim.is_navigable(sim.cell_of(hull)), "and is still at sea")


# --- 5. THE hash, with cargo aboard -------------------------------------

func test_the_composition_hash_agrees_with_cargo_aboard() -> void:
	# Stage 4's done-when, and the reason §3.1 excludes cargo from
	# `visible_to` on BOTH sides: the hashes agree BY CONSTRUCTION rather
	# than because two places both remembered to skip something.
	#
	# Driven through the real wire — `squad_info_entries` -> encode ->
	# decode -> `ClientState` — because D-006's own note says a test that
	# hands both sides the same inputs proves the function is pure and
	# cannot see the live system feeding them different ones.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var loaded := _loaded(w)

	var state := ClientState.new()
	state.space = sim.space
	state.player = 1
	var visible := sim.visible_to(1)
	state._handle_squad_info(NetProtocol.encode_squad_info(
		sim.squad_info_entries(visible)))

	assert_eq(state.composition_hash(), sim.composition_hash(visible),
		"server and client must agree on the composition with cargo aboard")


func test_the_hash_still_agrees_after_the_cargo_lands() -> void:
	# The other end of the voyage: a landing CREATES a squad, which the
	# client learns about the way it learns about any produced one.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var loaded := _loaded(w)
	sim.order_move(loaded["hull"], _beach_beside(sim, sim.cell_of(loaded["hull"])))
	for _t in range(60):
		sim.tick()
		if not sim.last_landings.is_empty():
			break
	assert_eq(sim.last_landings.size(), 1, "Setup: something landed")

	var state := ClientState.new()
	state.space = sim.space
	state.player = 1
	var visible := sim.visible_to(1)
	state._handle_squad_info(NetProtocol.encode_squad_info(
		sim.squad_info_entries(visible)))
	assert_eq(state.composition_hash(), sim.composition_hash(visible),
		"and after the landing")


func test_a_client_is_told_what_a_hull_is_carrying() -> void:
	# The owner still sees their army, because cargo rides as a property
	# of the CARRIER — an addition to `SQUAD_INFO`, not a new message.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var loaded := _loaded(w)
	var hull: int = loaded["hull"]

	var state := ClientState.new()
	state.space = sim.space
	state.player = 1
	state._handle_squad_info(NetProtocol.encode_squad_info(
		sim.squad_info_entries(sim.visible_to(1))))

	var info: Dictionary = state.composition.get(hull, {})
	assert_false(info.is_empty(), "the client knows the hull")
	var cargo: Array = info.get("cargo", [])
	assert_eq(cargo.size(), 1, "and what it is carrying")
	assert_eq(String(cargo[0]["def_id"]), String(_land_unit().id))
	assert_gt(int(cargo[0]["alive"]), 0, "with the men aboard")


func test_an_empty_hull_costs_the_wire_a_zero_and_nothing_else() -> void:
	# Every squad in the game now carries a cargo count. Asserted because
	# a variable-length field read conditionally is how a decoder loses
	# sync with everything after it in the same batch.
	var w := _world()
	var sim: SquadSim = w["sim"]
	sim.add_squad(_transport(), 1, w["water"])
	sim.add_squad(_land_unit(), 1, w["quay"])
	var entries := sim.squad_info_entries(sim.visible_to(1))
	var decoded := NetProtocol.decode_squad_info(
		NetProtocol.encode_squad_info(entries))
	assert_eq(decoded.size(), entries.size(),
		"every entry survives the round trip")
	for entry in decoded:
		assert_true(entry.has("cargo"), "every squad reports its cargo")
		assert_eq((entry["cargo"] as Array).size(), 0, "which is empty here")


# --- 6. the crossing, now that a hull can sail --------------------------

## The clause stage 4 could NOT discharge, discharged.
##
## Stage 4's done-when is "a land squad crosses water and lands"; it was
## written before naval stage 2, so every voyage above is PLACED rather
## than sailed and the file said so rather than claiming otherwise. With
## the water domain live the whole leg can be run, and this is it: board
## at a dock on one shore, sail a real field across a real channel, land
## on the far side.
##
## TWO ISLANDS, not one coastline with water in the middle — and that
## distinction is the fixture trap this project has recorded before ("a
## wall of constant q does not block a torus at all"). A single band of
## water on a 40-wide torus leaves the far shore reachable the SHORT way
## round, so the first version of this measured an 11-cell wrap and called
## it a crossing. Land on x in [0,5) and [20,25), water everywhere else:
## whichever way the hull goes, it goes over open sea.
func _channel() -> Dictionary:
	var space := TorusSpace.new(40, 12, 1.0)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var dry := coord.x < 5 or (coord.x >= 20 and coord.x < 25)
		passable[index] = 1 if dry else 0
		navigable[index] = 0 if dry else 1
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	sim.set_passable(passable)
	sim.set_navigable(navigable)

	var quay := Vector2i(4, 6)
	var water := Vector2i(5, 6)
	var dock: int = buildings.add_building(BuildingSim.def_by_id(&"dock"), 1, quay, true)
	buildings.set_water_cell(dock, space.index(water))
	return {"sim": sim, "space": space, "quay": quay, "water": water}


func test_a_land_squad_crosses_water_and_lands() -> void:
	var w := _channel()
	var sim: SquadSim = w["sim"]
	var far_shore := Vector2i(21, 6)
	assert_true(sim.is_passable(far_shore), "Setup: the far shore is land")
	assert_gt(sim.space.distance(w["quay"], far_shore), 12,
		"Setup: and it is a genuine crossing — TOROIDAL distance, so a wrap")
	# The two islands must not touch by land, or a "crossing" is a walk.
	assert_false(sim.is_passable(Vector2i(12, 6)), "Setup: open sea between them")
	assert_false(sim.is_passable(Vector2i(32, 6)), "Setup: and the other way too")

	# 1. board at the dock.
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var squad := sim.add_squad(_land_unit(), 1, w["quay"])
	var boarded := sim.alive_of(squad)
	sim.order_move(squad, w["water"])
	for _t in range(60):
		sim.tick()
		if sim.alive_of(squad) <= 0:
			break
	assert_eq(sim.cargo_of(hull).size(), 1, "it boarded at the dock")

	# 2. sail — a real water field across a real channel — and 3. land.
	sim.order_move(hull, far_shore)
	var landed := -1
	for _t in range(600):
		sim.tick()
		if not sim.last_landings.is_empty():
			landed = int(sim.last_landings[0])
			break
	assert_gte(landed, 0, "the cargo came ashore on the far side")
	if landed < 0:
		return
	assert_true(sim.is_passable(sim.cell_of(landed)), "on ground it could walk")
	assert_lte(sim.space.distance(sim.cell_of(landed), far_shore), 4,
		"where it was sent")
	assert_eq(sim.alive_of(landed), boarded, "with the men that boarded")
	assert_gt(sim.space.distance(sim.cell_of(landed), w["quay"]), 12,
		"and it is genuinely on the OTHER island")


func test_the_hash_agrees_across_the_whole_voyage() -> void:
	# The done-when's other half, re-asked at every stage of a real
	# crossing rather than only with the hull parked: aboard at the dock,
	# aboard mid-channel, and ashore on the far side. Through the wire
	# each time.
	var w := _channel()
	var sim: SquadSim = w["sim"]
	var hull := sim.add_squad(_transport(), 1, w["water"])
	var squad := sim.add_squad(_land_unit(), 1, w["quay"])
	sim.order_move(squad, w["water"])
	for _t in range(60):
		sim.tick()
		if sim.alive_of(squad) <= 0:
			break
	_assert_wire_agrees(sim, "aboard at the dock")

	sim.order_move(hull, Vector2i(21, 6))
	for _t in range(40):
		sim.tick()
	_assert_wire_agrees(sim, "aboard, mid-channel")

	for _t in range(600):
		sim.tick()
		if not sim.last_landings.is_empty():
			break
	_assert_wire_agrees(sim, "ashore on the far side")


func _assert_wire_agrees(sim: SquadSim, when: String) -> void:
	var state := ClientState.new()
	state.space = sim.space
	state.player = 1
	var visible := sim.visible_to(1)
	state._handle_squad_info(NetProtocol.encode_squad_info(
		sim.squad_info_entries(visible)))
	assert_eq(state.composition_hash(), sim.composition_hash(visible),
		"server and client must agree: %s" % when)
