extends GutTest

## Guards the dev-testing sandbox mode: wire round-trips for the cheat
## opcodes and the lobby packet's new flags, `BuildingSim.enqueue`'s
## instant-completion path, and `AiPlayer.economy_only` actually holding
## fire. Admin-gating and per-flag independence of the MatchState settings
## themselves are covered in test_lobby.gd, which already owns "the lobby
## admin controls this" as a class of rule.

const W := 48
const H := 24


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _def(vision_range: float, damage: float = 0.0) -> UnitDef:
	var real := UnitRoster.first()
	var d := UnitDef.new()
	d.id = real.id
	d.formation_shape = real.formation_shape
	d.formation_spacing = real.formation_spacing
	d.squad_size = 8
	d.health = 50.0
	d.damage = damage
	d.attack_range = damage  # only matters when damage > 0
	d.vision_range = vision_range
	d.move_speed = 3.0
	return d


# --- wire round-trips ----------------------------------------------------

func test_lobby_packet_round_trips_the_sandbox_flags() -> void:
	var bytes := NetProtocol.encode_lobby(1, [], {}, 0, true, false, true)
	var decoded := NetProtocol.decode_lobby(bytes)
	assert_true(bool(decoded["sandbox"]))
	assert_false(bool(decoded["instant_build"]))
	assert_true(bool(decoded["ai_economy_only"]))


func test_lobby_packet_defaults_sandbox_flags_to_false() -> void:
	var decoded := NetProtocol.decode_lobby(NetProtocol.encode_lobby(1, [], {}, 0))
	assert_false(bool(decoded["sandbox"]))
	assert_false(bool(decoded["instant_build"]))
	assert_false(bool(decoded["ai_economy_only"]))


func test_cheat_add_resources_uses_its_own_opcode_and_carries_no_payload() -> void:
	var bytes := NetProtocol.encode_cheat_add_resources()
	assert_eq(NetProtocol.opcode_of(bytes), NetProtocol.C2S_CHEAT_ADD_RESOURCES)
	assert_eq(bytes.size(), 1, "no payload beyond the opcode byte — who receives it "
		+ "is read from the connection, same as chat's speaker")


func test_cheat_spawn_unit_round_trips() -> void:
	var bytes := NetProtocol.encode_cheat_spawn_unit("militia", 77, 5)
	assert_eq(NetProtocol.opcode_of(bytes), NetProtocol.C2S_CHEAT_SPAWN_UNIT)
	var decoded := NetProtocol.decode_cheat_spawn_unit(bytes)
	assert_eq(String(decoded["archetype"]), "militia")
	assert_eq(int(decoded["cell"]), 77)
	assert_eq(int(decoded["count"]), 5)


func test_cheat_spawn_building_round_trips() -> void:
	var bytes := NetProtocol.encode_cheat_spawn_building("garrison_wall", 42, 3)
	assert_eq(NetProtocol.opcode_of(bytes), NetProtocol.C2S_CHEAT_SPAWN_BUILDING)
	var decoded := NetProtocol.decode_cheat_spawn_building(bytes)
	assert_eq(String(decoded["def_id"]), "garrison_wall")
	assert_eq(int(decoded["cell"]), 42)
	assert_eq(int(decoded["facing"]), 3)


# --- instant_build (BuildingSim.enqueue) ---------------------------------

func test_enqueue_instant_finishes_on_the_next_advance_not_the_first() -> void:
	# "Instant" means near-zero remaining, not zero-cost same-tick — the
	# existing advance_production path (dt=0.1 at 10 Hz) already finishes
	# a 0.001s remaining head on the tick right after it was queued, so
	# no new completion code path is needed at all.
	var buildings := BuildingSim.new(_space())
	var def := _def(1.0)
	def.build_time = 999.0  # would never finish this test un-instant
	var hall_def := BuildingDef.new()
	hall_def.id = &"test_hall"
	hall_def.max_health = 100.0
	var hall := buildings.add_building(hall_def, 1, Vector2i(4, 4), true)

	buildings.enqueue(hall, def, true)
	assert_eq(buildings.advance_production(0.1).size(), 1,
		"an instant-queued unit should finish on the very next production tick")


func test_enqueue_without_instant_still_uses_build_time() -> void:
	var buildings := BuildingSim.new(_space())
	var def := _def(1.0)
	def.build_time = 999.0
	var hall_def := BuildingDef.new()
	hall_def.id = &"test_hall"
	hall_def.max_health = 100.0
	var hall := buildings.add_building(hall_def, 1, Vector2i(4, 4), true)

	buildings.enqueue(hall, def)
	assert_eq(buildings.advance_production(0.1).size(), 0,
		"an ordinary (non-instant) order must not be affected by the instant path existing")


# --- AiPlayer.economy_only ------------------------------------------------

func _feed(sim: SquadSim, ai: AiPlayer) -> void:
	var visible := sim.visible_to(ai.player)
	ai.state.handle_packet(NetProtocol.encode_welcome(ai.player, W, H, visible))
	ai.state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))
	for packet in sim.replicator.collect_for_client(ai.player, sim.time, visible):
		ai.state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))


func test_an_economy_only_ai_never_sends_an_attack_move() -> void:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(2, CivRoster.ids()[0])
	ai.economy_only = true

	# A combat-capable owned squad and a visible enemy right next to it —
	# exactly the setup that makes an ordinary AI attack immediately.
	sim.add_squad(_def(10.0, 10.0), 2, Vector2i(10, 10))
	sim.add_squad(_def(4.0), 1, Vector2i(11, 10))
	sim.tick()
	_feed(sim, ai)

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	ai.set_time(sim.time)
	ai.update(sim.time)

	for packet in sent:
		assert_ne(NetProtocol.opcode_of(packet), NetProtocol.C2S_ORDER_ATTACK_MOVE,
			"an economy-only AI must never issue an attack-move order")


func test_the_same_scenario_without_economy_only_does_attack() -> void:
	# The control for the test above: proves the scenario actually WOULD
	# have produced an attack if not for the flag, so the previous test's
	# pass is not just "nothing happened either way".
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(2, CivRoster.ids()[0])

	sim.add_squad(_def(10.0, 10.0), 2, Vector2i(10, 10))
	sim.add_squad(_def(4.0), 1, Vector2i(11, 10))
	sim.tick()
	_feed(sim, ai)

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	ai.set_time(sim.time)
	ai.update(sim.time)

	var attacked := false
	for packet in sent:
		if NetProtocol.opcode_of(packet) == NetProtocol.C2S_ORDER_ATTACK_MOVE:
			attacked = true
	assert_true(attacked, "setup: an ordinary AI should attack a visible enemy right beside it")
