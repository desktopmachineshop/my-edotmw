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


# --- the opening: when an AI may act, and when it may stop trying -----
#
# Every test below covers the same defect from a different side: an AI
# seat sat on its founding party for the whole of every match, in every
# game against computer opponents, on every map. The mechanic was written
# and correct; it was called one tick too early, and the attempt was
# latched as though it had worked. CLAUDE.md's D-061 note names this
# family exactly — suspect an unreachable branch before a missing
# mechanic — and this one was reachable exactly once, into a closed door.


## The def the server really spawns a player's opening party from, so
## `BuildingSim.can_build` sees the archetype it will see in a match. A
## synthetic def would pass every assertion here and prove nothing about
## who may found a town.
func _founders_def() -> UnitDef:
	return UnitRoster.by_id(&"founders")


## An AI holding one founding party, told the world exactly as the server
## tells it: seats and phase first (S2C_LOBBY), then the welcome, then
## composition and curves.
func _founding_ai(phase: int) -> Dictionary:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	sim.add_squad(_founders_def(), 1000, Vector2i(8, 8))
	sim.tick()

	var seats := [{"kind": "ai", "player": 1000, "civ": String(ai.civ),
		"team": 0, "name": "AI 1000"}]
	ai.state.handle_packet(NetProtocol.encode_lobby(0, seats, {}, phase))
	_feed(sim, ai)

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	ai.set_time(sim.time)
	return {"sim": sim, "ai": ai, "sent": sent}


func _build_orders(sent: Array) -> Array:
	var out := []
	for packet in sent:
		if NetProtocol.opcode_of(packet) == NetProtocol.C2S_ORDER_BUILD:
			out.append(NetProtocol.decode_order_build(packet))
	return out


func test_an_ai_does_nothing_before_the_match_is_running() -> void:
	# The server ticks AI seats from the moment they are created, which in a
	# no-lobby match is before anybody has connected. Everything the AI sent
	# then was dropped by server._validated_squad's not-running guard,
	# silently — so the founding order was spent into a closed door.
	var w := _founding_ai(0)  # Phase.LOBBY
	var ai: AiPlayer = w["ai"]

	ai.update(w["sim"].time)
	assert_eq(w["sent"].size(), 0,
		"An AI acted while the match was still in the lobby — every order will be dropped")


func test_an_ai_founds_its_town_once_the_match_is_running() -> void:
	# The other half, so "does nothing" cannot pass for "correctly waiting".
	var w := _founding_ai(1)  # Phase.RUNNING
	var ai: AiPlayer = w["ai"]

	ai.update(w["sim"].time)
	assert_eq(_build_orders(w["sent"]).size(), 1,
		"An AI in a running match should found its town hall on its first think")


func test_an_ai_told_the_match_started_stops_waiting() -> void:
	# The transition itself. An AI seated during the lobby is told the phase
	# again when the match begins (server._note_match_started broadcasts to
	# _recipients, AI seats included) — without that message it waits for a
	# match it has already been dealt into.
	var w := _founding_ai(0)
	var ai: AiPlayer = w["ai"]
	var sim: SquadSim = w["sim"]

	ai.update(sim.time)
	assert_eq(w["sent"].size(), 0, "Setup: still in the lobby")

	ai.state.handle_packet(NetProtocol.encode_lobby(0, ai.state.lobby["seats"], {}, 1))
	ai.set_time(sim.time + AiPlayer.THINK_INTERVAL)
	ai.update(sim.time + AiPlayer.THINK_INTERVAL)

	assert_eq(_build_orders(w["sent"]).size(), 1,
		"An AI that has been told the match started should get on with it")


func test_an_ai_whose_founding_order_was_dropped_tries_again() -> void:
	# Latching on the SEND is what turned one lost order into a lost match.
	# The order here is thrown away exactly as the server threw it away —
	# well-formed, sent, and gone — and nothing else about the world changes.
	var w := _founding_ai(1)
	var ai: AiPlayer = w["ai"]
	var sim: SquadSim = w["sim"]

	ai.update(sim.time)
	assert_eq(_build_orders(w["sent"]).size(), 1, "Setup: it tried once")
	w["sent"].clear()   # the server dropped it; no town centre appears

	var later := sim.time + AiPlayer.FOUND_RETRY + AiPlayer.THINK_INTERVAL
	ai.set_time(later)
	ai.update(later)

	assert_eq(_build_orders(w["sent"]).size(), 1,
		"An AI whose founding order never landed must try again — it has no other move")


func test_an_ai_stops_asking_once_its_town_centre_exists() -> void:
	# The bound on the retry above, and the reason removing the latch
	# outright is the other wrong answer: the AI must stop when it can SEE
	# that the town is up, not when it remembers asking.
	var w := _founding_ai(1)
	var ai: AiPlayer = w["ai"]
	var sim: SquadSim = w["sim"]

	ai.update(sim.time)
	assert_eq(_build_orders(w["sent"]).size(), 1, "Setup: it tried once")
	w["sent"].clear()

	var buildings := BuildingSim.new(_space())
	var hall := buildings.add_building(
		BuildingSim.def_by_id(&"town_centre"), 1000, Vector2i(8, 8), true)
	ai.state.handle_packet(NetProtocol.encode_building_info(
		buildings.info_entries([hall])))

	for i in range(6):
		var t := sim.time + AiPlayer.FOUND_RETRY * float(i + 1)
		ai.set_time(t)
		ai.update(t)

	assert_eq(_build_orders(w["sent"]).size(), 0,
		"An AI with a town centre standing must not keep ordering another one")


func test_an_ai_holding_no_founders_never_asks_for_a_town_centre() -> void:
	# The other bound, and the reason the retry cannot become a spin. The
	# founding party is consumed by the town it raises (D-031) and only
	# founders may raise one (BuildingDef.built_by) — so an AI past that
	# point has no legal move here at all. Ordering anyway is what fills a
	# log with "gatherers cannot build a Town Centre", which is exactly what
	# removing the latch outright was measured doing.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	sim.add_squad(UnitRoster.by_id(&"gatherers"), 1000, Vector2i(8, 8))
	sim.add_squad(UnitRoster.by_id(&"gatherers"), 1000, Vector2i(9, 8))
	sim.tick()

	var seats := [{"kind": "ai", "player": 1000, "civ": String(ai.civ),
		"team": 0, "name": "AI 1000"}]
	ai.state.handle_packet(NetProtocol.encode_lobby(0, seats, {}, 1))
	_feed(sim, ai)
	# A full wallet, so the ordinary building path IS live and this cannot
	# pass by the AI simply doing nothing at all.
	ai.state.handle_packet(NetProtocol.encode_wallet(
		PackedInt32Array([9999, 9999, 9999, 9999])))

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)

	for i in range(6):
		var t := sim.time + AiPlayer.FOUND_RETRY * float(i + 1)
		ai.set_time(t)
		ai.update(t)

	var orders := _build_orders(sent)
	assert_gt(orders.size(), 0,
		"Setup: this AI should still be building things, or the check below is vacuous")
	var halls := 0
	for order in orders:
		if String(order["def_id"]) == "town_centre":
			halls += 1
	assert_eq(halls, 0,
		"An AI with no founders left must not ask for a town centre")


func test_an_ai_asks_for_its_own_spawn_and_not_a_rivals() -> void:
	# The second defect in the same path: an AI that DID found a town
	# founded it on somebody else's start, because the client's copy of
	# "where do I begin" keyed on the player id and the server keys on the
	# seat. See test_client_state.gd for the arithmetic; this is the caller
	# that made it matter.
	var m := MatchState.new()
	m.require_admin_start = true
	m.add_player(1)                             # seat 0
	m.add_ai(1, CivRoster.ids()[0], 1000)       # seat 1
	m.start_match()

	# FOUR points and two seats, which is the ladder map's shape and the
	# shape in which the two arithmetics disagree: seat 1 is point 1, while
	# (1000 - 1) % 4 is point 3.
	var spawns := [Vector2i(4, 4), Vector2i(20, 12), Vector2i(34, 4), Vector2i(44, 18)]
	var space := _space()
	var spawn_indices := []
	for cell in spawns:
		spawn_indices.append(space.index(cell))

	var sim := SquadSim.new(space, CurveReplicator.new())
	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	# Spawned where the SERVER would put it — at its seat's point.
	sim.add_squad(_founders_def(), 1000,
		spawns[m.spawn_index(1000, spawns.size())])
	sim.tick()

	ai.state.handle_packet(NetProtocol.encode_lobby(
		m.admin_player, m.seats, {}, int(m.phase)))
	var visible := sim.visible_to(1000)
	ai.state.handle_packet(NetProtocol.encode_welcome(
		1000, W, H, visible, spawn_indices))
	ai.state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))
	for packet in sim.replicator.collect_for_client(1000, sim.time, visible):
		ai.state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	ai.set_time(sim.time)
	ai.update(sim.time)

	var orders := _build_orders(sent)
	assert_eq(orders.size(), 1, "Setup: it should have tried to found a town")
	assert_eq(space.from_index(int(orders[0]["cell"])), spawns[1],
		"The AI founded its capital on another player's spawn point")


func test_a_loopback_peer_delivers_bytes_to_its_client_state() -> void:
	# The one line the whole no-cheating guarantee rests on.
	var state := ClientState.new()
	var peer := LoopbackPeer.new(state)
	peer.send(0, NetProtocol.encode_welcome(7, W, H, []), 0)
	assert_true(state.welcomed, "A packet sent to the loopback peer never reached the client")
	assert_eq(state.player, 7)
