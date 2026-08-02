extends GutTest

## Guards D-051 — AI players, and specifically D-046 criterion 9: an AI
## sees exactly what a human in its seat would see.
##
## This is the check the whole design is arranged around. An AI that
## quietly saw through fog would not look like a bug; it would look like a
## good AI, and nobody would find it by playing. So the guarantee is
## structural — the AI holds a real ClientState fed by real packets — and
## these tests confirm the structure holds rather than trusting it.

const W := 48
const H := 24


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _def(vision_range: float) -> UnitDef:
	var real := UnitRoster.first()
	var d := UnitDef.new()
	d.id = real.id
	d.formation_shape = real.formation_shape
	d.formation_spacing = real.formation_spacing
	d.squad_size = 8
	d.health = 50.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.vision_range = vision_range
	d.move_speed = 3.0
	return d


## Drive a sim and an AI's ClientState through the real replication path,
## exactly as server.gd does — the same shape test_client_state.gd uses,
## because that is the point: the AI is a client.
func _feed(sim: SquadSim, ai: AiPlayer) -> void:
	var visible := sim.visible_to(ai.player)
	ai.state.handle_packet(NetProtocol.encode_welcome(ai.player, W, H, visible))
	ai.state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))
	for packet in sim.replicator.collect_for_client(ai.player, sim.time, visible):
		ai.state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))


func test_an_ai_knows_nothing_the_server_did_not_send_it() -> void:
	# D-046 criterion 9. An enemy sitting outside the AI's vision must not
	# appear in its ClientState at all — not as a stale entry, not as a
	# ghost, not anywhere.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(2, CivRoster.ids()[0])

	sim.add_squad(_def(6.0), 2, Vector2i(4, 4))
	var far_enemy := sim.add_squad(_def(6.0), 1, Vector2i(40, 20))
	sim.tick()
	_feed(sim, ai)

	assert_false(ai.state.composition.has(far_enemy),
		"The AI knows about an enemy the server never told it about")
	assert_false(ai.state.curves.has(far_enemy),
		"The AI holds a curve for a squad outside its vision")


func test_everything_an_ai_knows_is_something_it_can_see() -> void:
	# The general form, rather than one planted enemy: whatever ended up
	# in the AI's head must appear in the server's visible set for its
	# player.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(2, CivRoster.ids()[0])

	sim.add_squad(_def(8.0), 2, Vector2i(10, 10))
	sim.add_squad(_def(4.0), 1, Vector2i(12, 10))   # close: should be seen
	sim.add_squad(_def(4.0), 1, Vector2i(44, 22))   # far: should not
	sim.add_squad(_def(4.0), 3, Vector2i(30, 4))    # far: should not
	sim.tick()
	_feed(sim, ai)

	var visible := sim.visible_to(2)
	for id in ai.state.composition:
		assert_true(visible.has(int(id)),
			"The AI knows squad %d, which is not in its visible set" % id)
	assert_gt(ai.state.composition.size(), 1,
		"The AI saw nothing at all, so the subset check above proves nothing")


func test_an_ai_can_see_a_neighbour_and_still_not_the_far_side() -> void:
	# Both halves in one match, so "sees nothing" cannot pass for
	# "correctly fogged".
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(2, CivRoster.ids()[0])

	sim.add_squad(_def(8.0), 2, Vector2i(10, 10))
	var near := sim.add_squad(_def(4.0), 1, Vector2i(12, 10))
	var far := sim.add_squad(_def(4.0), 1, Vector2i(44, 22))
	sim.tick()
	_feed(sim, ai)

	assert_true(ai.state.composition.has(near), "The AI should see an enemy standing next to it")
	assert_false(ai.state.composition.has(far), "…and not one across the map")


# --- orders take the same road as a human's --------------------------

func test_an_ai_issues_real_protocol_packets() -> void:
	# Its decisions must be ordinary client commands, so every rule a
	# human is held to applies unchanged. If the AI called into SquadSim
	# directly it could do things no human could.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(2, CivRoster.ids()[0])
	sim.add_squad(_def(6.0), 2, Vector2i(4, 4))
	sim.tick()
	_feed(sim, ai)

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	ai.set_time(sim.time)
	ai.update(sim.time)

	assert_gt(sent.size(), 0, "The AI did nothing on its first think")
	for packet in sent:
		var opcode := NetProtocol.opcode_of(packet)
		assert_true(opcode >= NetProtocol.C2S_ORDER_MOVE,
			"The AI sent something that is not a client command (opcode %d)" % opcode)


func test_a_loopback_peer_delivers_bytes_to_its_client_state() -> void:
	# The one line the whole no-cheating guarantee rests on.
	var state := ClientState.new()
	var peer := LoopbackPeer.new(state)
	peer.send(0, NetProtocol.encode_welcome(7, W, H, []), 0)
	assert_true(state.welcomed, "A packet sent to the loopback peer never reached the client")
	assert_eq(state.player, 7)
