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

func test_only_founders_can_build_a_town_hall() -> void:
	var town_centre: BuildingDef = load("res://buildings/town_centre.tres")
	assert_true(BuildingSim.can_build(town_centre, &"founders"),
		"Founders settle — that is the whole point of them")
	for other in [&"militia", &"archers", &"cavalry", &"spearmen", &"gatherers"]:
		assert_false(BuildingSim.can_build(town_centre, other),
			"%s must not be able to plant a town hall" % other)


func test_founders_can_build_ONLY_the_town_hall() -> void:
	# The other half of the claim, and the reason built_by is expressed on
	# the building rather than as a list on the unit: every other building
	# refuses founders simply by not listing them, with no second list to
	# keep in step.
	for name in ["barracks", "storehouse", "tower"]:
		var def: BuildingDef = load("res://buildings/%s.tres" % name)
		assert_false(BuildingSim.can_build(def, &"founders"),
			"Founders found towns; they do not run a construction firm (%s)" % name)


func test_an_unrestricted_building_accepts_any_builder() -> void:
	# Empty built_by means unrestricted. Nothing shipped uses it, but the
	# default has to be the permissive one or every new .tres would be
	# unbuildable until someone remembered to fill the field in.
	var def := _building_def()
	assert_true(def.built_by.is_empty(), "Setup: the default is unrestricted")
	assert_true(BuildingSim.can_build(def, &"anything_at_all"))


func test_the_founding_party_outfights_basic_infantry() -> void:
	# "Can fight" is a real claim, not flavour: a founding party that lost
	# to the cheapest melee unit would make settling a formality rather
	# than a choice.
	var founders: UnitDef = UnitRoster.by_id(&"founders")
	var militia: UnitDef = UnitRoster.for_civ_archetype(CivRoster.ids()[0], &"militia")
	assert_not_null(founders, "The roster must ship a 'founders' unit")
	assert_not_null(militia)

	assert_gt(founders.damage, militia.damage, "Founders hit harder, man for man")
	assert_gt(founders.health, militia.health, "And are harder to kill")
	assert_lt(founders.rout_threshold, militia.rout_threshold,
		"And hold their nerve longer — they have nowhere to run to")
	assert_lt(founders.squad_size, militia.squad_size,
		"But there are few of them: this is a founding party, not an army")


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
