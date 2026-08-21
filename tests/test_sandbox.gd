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


# --- D-20260821-the-sandbox-panel-runs-the-world -------------------------

func test_spawn_cheats_round_trip_the_enemy_flag() -> void:
	var unit := NetProtocol.decode_cheat_spawn_unit(
		NetProtocol.encode_cheat_spawn_unit("militia", 77, 5, true))
	assert_true(bool(unit["enemy"]))
	var mine := NetProtocol.decode_cheat_spawn_unit(
		NetProtocol.encode_cheat_spawn_unit("militia", 77, 5))
	assert_false(bool(mine["enemy"]), "the default spawns for the sender")
	var building := NetProtocol.decode_cheat_spawn_building(
		NetProtocol.encode_cheat_spawn_building("tower", 42, 3, true))
	assert_true(bool(building["enemy"]))


func test_regen_map_has_its_own_opcode_and_no_payload() -> void:
	var bytes := NetProtocol.encode_cheat_regen_map()
	assert_eq(NetProtocol.opcode_of(bytes), NetProtocol.C2S_CHEAT_REGEN_MAP)
	assert_eq(bytes.size(), 1, "who asked is read from the connection")


func test_lobby_packet_round_trips_the_resources_flag() -> void:
	var off := NetProtocol.decode_lobby(
		NetProtocol.encode_lobby(1, [], {}, 0, true, false, false, false))
	assert_false(bool(off["resources"]))
	var default_on := NetProtocol.decode_lobby(NetProtocol.encode_lobby(1, [], {}, 0))
	assert_true(bool(default_on["resources"]),
		"resources default ON — a world with no nodes is the sandbox exception")


func test_resources_is_a_fourth_admin_gated_sandbox_option() -> void:
	var m := MatchState.new()
	m.require_admin_start = true
	m.add_player(1)
	m.add_player(2)
	assert_true(m.resources_enabled, "on by default")
	assert_false(m.set_sandbox_option(2, "resources", false), "not the admin")
	assert_true(m.resources_enabled)
	assert_true(m.set_sandbox_option(1, "resources", false))
	assert_false(m.resources_enabled)
	assert_false(m.sandbox, "flags stay independent (D-077)")


func test_enemy_of_finds_a_hostile_seat_and_only_a_hostile_seat() -> void:
	var m := MatchState.new()
	m.require_admin_start = true
	m.add_player(1)
	m.add_player(2)
	# Free-for-all (team 0 is not a team, D-050): each is the other's enemy.
	assert_eq(m.enemy_of(1), 2)
	assert_eq(m.enemy_of(2), 1)
	# Allied: nobody left to spawn for — the handler must refuse, loudly.
	# Each player sets their OWN seat (the permission a human seat has;
	# the first version had the admin set player 2's seat, which is
	# refused, and the refusal made this assertion test nothing).
	assert_true(m.set_team(1, m.seat_of(1), 1))
	assert_true(m.set_team(2, m.seat_of(2), 1))
	assert_eq(m.enemy_of(1), -1, "an ally is not an enemy, and there is no one else")


func test_ai_frozen_is_an_admin_gated_sandbox_option() -> void:
	var m := MatchState.new()
	m.require_admin_start = true
	m.add_player(1)
	m.add_player(2)
	assert_false(m.ai_frozen, "off by default — a frozen AI is a dev request, never a state a match wakes up in")
	assert_false(m.set_sandbox_option(2, "ai_frozen", true), "not the admin")
	assert_true(m.set_sandbox_option(1, "ai_frozen", true))
	assert_true(m.ai_frozen)


func test_lobby_packet_round_trips_the_ai_frozen_flag() -> void:
	var frozen := NetProtocol.decode_lobby(
		NetProtocol.encode_lobby(1, [], {}, 0, true, false, false, true, true))
	assert_true(bool(frozen["ai_frozen"]))
	var default_off := NetProtocol.decode_lobby(NetProtocol.encode_lobby(1, [], {}, 0))
	assert_false(bool(default_off["ai_frozen"]))


func test_cheat_spawn_building_round_trips_facing_and_offset() -> void:
	# The cheat rides the SAME placement flow as an ordinary build now
	# (ghost, facing, sub-cell offset) — so the wire has to carry what the
	# ghost promised, or the spawn drifts from the preview, which is the
	# exact defect D-096's shared-pose rule exists to prevent.
	var decoded := NetProtocol.decode_cheat_spawn_building(
		NetProtocol.encode_cheat_spawn_building("tower", 42, 137, true,
			Vector2(0.25, -0.4)))
	assert_eq(int(decoded["facing"]), 137)
	assert_true(bool(decoded["enemy"]))
	assert_almost_eq((decoded["offset"] as Vector2).x, 0.25, 0.001)
	assert_almost_eq((decoded["offset"] as Vector2).y, -0.4, 0.001)
