extends GutTest

## Guards D-034's command vocabulary (move, stop, attack-move) and
## D-027's criterion 4.
##
## The interesting one is attack-move. Squads already engage anything that
## comes into range, so "move and also fight" is what a plain move does
## already — an attack-move order that did nothing extra would look
## implemented, pass a smoke run, and be pure decoration. What makes it a
## real order is what happens ON CONTACT: it halts and fights where it
## stands, while a plain move walks on through. Every test here is built
## around telling those two apart.

const W := 32
const H := 16


func _sim() -> SquadSim:
	return SquadSim.new(TorusSpace.new(W, H, 1.0), CurveReplicator.new())


func _mover_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"command_test_mover"
	d.squad_size = 10
	d.health = 200.0        # tough: survives the walk, so the test is about movement
	d.damage = 0.0          # harmless by default; contact tests add an enemy that isn't
	d.attack_range = 3.0
	d.attack_interval = 0.1
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	d.morale = 100.0
	d.rout_threshold = 0.0  # never routs, so routing cannot explain a halt
	d.morale_loss_per_casualty = 0.0
	d.damage_variance = 0.0
	return d


func _enemy_def() -> UnitDef:
	var d := _mover_def()
	d.id = &"command_test_enemy"
	d.move_speed = 0.0  # stands still, so contact happens where we put it
	return d


# --- stop --------------------------------------------------------------

func test_stop_halts_a_moving_squad_where_it_stands() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_mover_def(), 1, Vector2i(2, 8))
	sim.order_move(squad, Vector2i(20, 8))

	for _i in range(6):
		sim.tick()
	var cell_when_stopped := sim.cell_of(squad)
	assert_ne(cell_when_stopped, Vector2i(2, 8), "Setup: the squad must actually have set off")

	sim.stop(squad)
	for _i in range(20):
		sim.tick()

	assert_eq(sim.cell_of(squad), cell_when_stopped,
		"A stopped squad must stay where it was when the order arrived")
	assert_eq(sim.destination_of(squad), cell_when_stopped,
		"Its destination should be its own cell, not the abandoned one")


func test_stop_uses_the_authoritative_position_not_a_supplied_one() -> void:
	# The stop order carries no destination on purpose (D-002): the client
	# view lags by up to a tick, so taking its word for "here" would let a
	# stop order shuffle a squad backwards.
	var sim := _sim()
	var squad := sim.add_squad(_mover_def(), 1, Vector2i(2, 8))
	sim.order_move(squad, Vector2i(20, 8))
	for _i in range(6):
		sim.tick()

	var authoritative := sim.cell_of(squad)
	sim.stop(squad)
	assert_eq(sim.destination_of(squad), authoritative)


func test_a_routed_squad_ignores_stop() -> void:
	# Consistent with order_move: a broken squad is not taking instructions
	# (D-024). Without this, stop would be a way to cancel routing.
	var sim := _sim()
	var squad := sim.add_squad(_mover_def(), 1, Vector2i(2, 8))
	sim.force_move(squad, Vector2i(20, 8))
	sim.set_routed(squad, true)

	var destination_before := sim.destination_of(squad)
	sim.stop(squad)
	assert_eq(sim.destination_of(squad), destination_before, "A routed squad keeps fleeing")


# --- attack-move -------------------------------------------------------

## Destination for the contact tests. Deliberately CLOSE to the start,
## and closer going forwards than backwards.
##
## The first version of this sent a squad from x=2 to x=24 on a 32-wide
## torus, past an enemy at x=10 — and the squad never met it, because the
## short way round is backwards (10 cells, against 22 going forwards) and
## the flow field quite correctly took it (D-007/D-008). A test that
## reasons about "past" on a torus has to check which way "past" is.
const START := Vector2i(2, 8)
const ENEMY := Vector2i(7, 8)
const TARGET := Vector2i(12, 8)


## Sends a squad past a stationary enemy and reports where it ended up.
func _advance_past_enemy(attack_move: bool) -> Dictionary:
	var sim := _sim()
	var mover := sim.add_squad(_mover_def(), 1, START)

	var enemy_def := _enemy_def()
	enemy_def.damage = 0.0  # contact, but no casualties, so nothing dies mid-test
	sim.add_squad(enemy_def, 2, ENEMY)

	if attack_move:
		sim.order_attack_move(mover, TARGET)
	else:
		sim.order_move(mover, TARGET)

	# Ten cells at ~2 cells/second is ~5 seconds; 80 ticks leaves margin
	# so "did not arrive" means halted, not merely still walking.
	for _i in range(80):
		sim.tick()
	return {"cell": sim.cell_of(mover), "stance": sim.is_attack_moving(mover)}


func test_attack_move_halts_on_contact() -> void:
	var result := _advance_past_enemy(true)
	assert_lt(result["cell"].x, TARGET.x,
		"An attack-moving squad must stop when it meets an enemy, not walk on to its destination")


func test_a_plain_move_walks_on_through() -> void:
	# The other half of the same claim. Without this, the test above would
	# pass against a squad that simply never reached its destination —
	# which is exactly how the first version of this pair failed.
	var result := _advance_past_enemy(false)
	assert_eq(result["cell"], TARGET,
		"A plain move must ignore contact and reach its destination")


func test_the_attack_move_stance_is_spent_once_it_halts() -> void:
	# Otherwise the squad re-halts and rebuilds its curve every tick it
	# stays engaged, which costs bandwidth for no change (D-003).
	var result := _advance_past_enemy(true)
	assert_false(result["stance"], "The stance should be cleared once contact has halted the squad")


func test_ordering_a_plain_move_clears_an_attack_move_stance() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_mover_def(), 1, Vector2i(2, 8))
	sim.order_attack_move(squad, Vector2i(20, 8))
	assert_true(sim.is_attack_moving(squad))

	sim.order_move(squad, Vector2i(4, 8))
	assert_false(sim.is_attack_moving(squad),
		"A plain move must replace the stance, not leave the squad still halting on contact")


# --- the wire ----------------------------------------------------------

func test_orders_round_trip_through_the_protocol() -> void:
	var stop_bytes := NetProtocol.encode_order_stop(7)
	assert_eq(NetProtocol.opcode_of(stop_bytes), NetProtocol.C2S_ORDER_STOP)
	assert_eq(int(NetProtocol.decode_order_stop(stop_bytes)["squad"]), 7)

	var attack_bytes := NetProtocol.encode_order_attack_move(3, 129)
	assert_eq(NetProtocol.opcode_of(attack_bytes), NetProtocol.C2S_ORDER_ATTACK_MOVE)
	var decoded := NetProtocol.decode_order_attack_move(attack_bytes)
	assert_eq(int(decoded["squad"]), 3)
	assert_eq(int(decoded["destination"]), 129)


func test_every_order_opcode_is_distinct() -> void:
	# Two orders sharing an opcode is a silently-ignored packet rather than
	# a compile error — the exact failure NetProtocol's header says one
	# shared definition exists to prevent.
	var opcodes := [
		NetProtocol.C2S_ORDER_MOVE,
		NetProtocol.C2S_ORDER_STOP,
		NetProtocol.C2S_ORDER_ATTACK_MOVE,
	]
	var seen := {}
	for code in opcodes:
		assert_false(seen.has(code), "Opcode %d is used twice" % code)
		seen[code] = true


func test_a_client_will_not_send_an_order_for_a_squad_it_does_not_own() -> void:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [4, 5]))

	assert_true(state.encode_stop(9).is_empty(), "Squad 9 is not owned")
	assert_true(state.encode_attack_move(9, Vector2i(1, 1)).is_empty(), "Squad 9 is not owned")
	assert_false(state.encode_stop(4).is_empty(), "Squad 4 is owned")
	assert_false(state.encode_attack_move(4, Vector2i(1, 1)).is_empty(), "Squad 4 is owned")
