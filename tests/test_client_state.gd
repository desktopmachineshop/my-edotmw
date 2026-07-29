extends GutTest

## Tests the client half of the protocol against bytes a real server
## would produce.
##
## This matters more than it looks: the GUI client cannot be tested
## headless (D-014 — it needs a GPU), so ClientState is deliberately
## where all its non-rendering logic lives. Everything asserted here is
## logic the real client actually runs, and that the load-test bots drive
## through the same path.

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"client_test"
	d.squad_size = 10
	d.move_speed = 3.5
	return d


# --- protocol roundtrips ---------------------------------------------

func test_welcome_roundtrips() -> void:
	var encoded := NetProtocol.encode_welcome(3, W, H, [7, 8, 9])
	var decoded := NetProtocol.decode_welcome(encoded)
	assert_eq(int(decoded["player"]), 3)
	assert_eq(int(decoded["width"]), W)
	assert_eq(int(decoded["height"]), H)
	assert_eq(Array(decoded["squads"] as PackedInt32Array), [7, 8, 9])


func test_order_move_roundtrips() -> void:
	var decoded := NetProtocol.decode_order_move(NetProtocol.encode_order_move(12, 345))
	assert_eq(int(decoded["squad"]), 12)
	assert_eq(int(decoded["destination"]), 345)


func test_unknown_opcode_is_counted_not_crashed_on() -> void:
	var state := ClientState.new()
	var junk := PackedByteArray([200, 1, 2, 3])
	state.handle_packet(junk)
	assert_eq(state.unknown_packets, 1, "An unknown opcode should be counted, not fatal")
	assert_false(state.welcomed)


func test_empty_packet_is_survivable() -> void:
	var state := ClientState.new()
	state.handle_packet(PackedByteArray())
	assert_eq(state.unknown_packets, 1)


# --- welcome ----------------------------------------------------------

func test_welcome_establishes_the_clients_view_of_the_map() -> void:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(2, W, H, [4, 5]))

	assert_true(state.welcomed)
	assert_eq(state.player, 2)
	assert_not_null(state.space)
	assert_eq(state.space.width, W)
	assert_eq(state.space.height, H)
	assert_true(state.owns(4))
	assert_false(state.owns(99), "A client should not think it owns a squad it wasn't given")


func test_orders_are_refused_for_squads_the_client_does_not_own() -> void:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [4]))

	assert_gt(state.encode_order(4, Vector2i(3, 3)).size(), 0, "Owned squads should be orderable")
	assert_eq(state.encode_order(77, Vector2i(3, 3)).size(), 0,
		"A client should not send orders for squads it doesn't own")


# --- end-to-end against a real server-side replicator ----------------

func test_client_reconstructs_squad_state_from_server_packets() -> void:
	# Drive a real SquadSim, take the bytes its replicator produces, and
	# feed them to a ClientState exactly as the transport would.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var id := sim.add_squad(_def(), 1, Vector2i(2, 2))
	sim.order_move(id, Vector2i(14, 8))

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [id]))

	for _i in range(30):
		sim.tick()
		for packet in sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1)):
			state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))

	assert_gt(state.curve_packets_received, 0, "The client should have received curves")
	assert_eq(state.squad_cell(id, sim.time), sim.cell_of(id),
		"The client's idea of where the squad is should match the server's")


func test_client_derives_the_same_soldiers_the_server_would() -> void:
	# D-006 end to end through the real protocol: no soldier position is
	# ever sent, and both sides still agree.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := _def()
	var id := sim.add_squad(def, 1, Vector2i(4, 4))
	sim.order_move(id, Vector2i(18, 10))

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [id]))

	for _i in range(20):
		sim.tick()
		for packet in sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1)):
			state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))

	var server_side := sim.soldier_transforms(id)
	var client_side := state.soldier_transforms(
		id, sim.time, def.squad_size, def.formation_shape, def.formation_spacing)

	assert_eq(client_side.size(), server_side.size())
	assert_gt(client_side.size(), 0)
	for i in range(server_side.size()):
		assert_almost_eq(client_side[i].origin.x, server_side[i].origin.x, 0.001,
			"Soldier %d x diverges" % i)
		assert_almost_eq(client_side[i].origin.z, server_side[i].origin.z, 0.001,
			"Soldier %d z diverges" % i)


func test_client_never_receives_soldier_positions() -> void:
	# Structural: everything a client holds is a squad curve. The soldier
	# count it can draw is derived, and bears no relation to bytes on the
	# wire — which is the entire 40x saving in D-006.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := _def()
	def.squad_size = 40
	var ids := []
	for i in range(10):
		ids.append(sim.add_squad(def, 1, Vector2i(i * 2, 3)))
	for id in ids:
		sim.order_move(id, Vector2i(20, 12))

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, ids))

	var ticks := 20
	var bytes := 0
	for _i in range(ticks):
		sim.tick()
		for packet in sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1)):
			var wire := NetProtocol.encode_curve(packet["bytes"])
			bytes += wire.size()
			state.handle_packet(wire)

	var soldiers := state.derive_all(sim.time, def.squad_size, def.formation_shape, def.formation_spacing)
	assert_eq(soldiers, 400, "10 squads of 40 should derive 400 soldiers")

	# Compare like with like: what per-soldier snapshot replication would
	# have cost over the SAME ticks. (Comparing cumulative bytes against a
	# single snapshot is not a fair test and fails for the wrong reason.)
	var per_soldier_equivalent := soldiers * StateCurve.KEYFRAME_BYTES * ticks
	assert_lt(bytes, per_soldier_equivalent / 2,
		"Sent %d bytes where per-soldier replication would cost ~%d — the 40x saving in D-006 is not materialising" % [bytes, per_soldier_equivalent])
	gut.p("%d bytes replicated for %d client-side soldiers over %d ticks (per-soldier equivalent: ~%d)" % [
		bytes, soldiers, ticks, per_soldier_equivalent])


# --- world <-> cell (client input) -----------------------------------

func test_world_to_cell_inverts_to_world_for_every_cell() -> void:
	# Orders are placed by clicking, so a click that lands one cell off is
	# a real bug. Independent rounding of q and r gets corners wrong;
	# this asserts cube rounding across the whole map.
	var space := _space()
	for i in range(space.cell_count()):
		var cell := space.from_index(i)
		assert_eq(space.world_to_cell(space.to_world(cell)), cell,
			"world_to_cell did not invert to_world at %s" % cell)


func test_world_to_cell_wraps_out_of_bounds_clicks() -> void:
	var space := _space()
	var beyond := space.to_world(Vector2i(2, 2)) + Vector3(
		space.hex_size * TorusSpace.SQRT_3 * float(W), 0.0, 0.0)
	assert_eq(space.world_to_cell(beyond), Vector2i(2, 2),
		"A click past the map edge should wrap onto the torus")


func test_world_to_cell_picks_the_nearest_cell_near_boundaries() -> void:
	var space := _space()
	var centre := space.to_world(Vector2i(5, 5))
	# Nudge a small fraction of a hex in each direction; should stay put.
	for offset in [Vector3(0.2, 0, 0), Vector3(-0.2, 0, 0), Vector3(0, 0, 0.2), Vector3(0, 0, -0.2)]:
		assert_eq(space.world_to_cell(centre + offset), Vector2i(5, 5),
			"A small nudge from the centre of a cell should stay in that cell")
