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


## A squad def with a chosen sight radius, wearing a REAL roster def's
## identity so the AI resolves it off the wire the way it would in a match.
##
## It wears the opening CREW's, specifically, and copies the archetype.
## This used to take `UnitRoster.first()` — whatever sorted first — which
## happened to be the founding party, so the AI could found a town and
## `test_an_ai_issues_real_protocol_packets` had something to observe.
## With founders gone (D-20260823-the-opening-is-a-crew-and-a-general)
## first is an ARCHER, which may build nothing, and that test went red on
## a FIXTURE rather than on the AI. Naming the settler is the honest
## version of what it was always relying on.
func _def(vision_range: float) -> UnitDef:
	var real := UnitRoster.for_civ_archetype(CivRoster.ids()[0], &"gatherers")
	var d := UnitDef.new()
	d.id = real.id
	d.archetype = real.archetype
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


## The def the server really spawns a player's opening crew from, so
## `BuildingSim.can_build` sees the archetype it will see in a match. A
## synthetic def would pass every assertion here and prove nothing about
## who may found a town.
func _crew_def() -> UnitDef:
	return UnitRoster.for_civ_archetype(CivRoster.ids()[0], &"gatherers")


## The opening ESCORT — a squad that may build nothing, so an AI holding
## only this one has no legal founding move
## (D-20260823-the-opening-is-a-crew-and-a-general).
func _general_def() -> UnitDef:
	return UnitRoster.for_civ_archetype(CivRoster.ids()[0], &"general")


## An AI holding the shipped opening — one crew and one general — told the
## world exactly as the server tells it: seats and phase first (S2C_LOBBY),
## then the welcome, then composition and curves.
func _founding_ai(phase: int) -> Dictionary:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	sim.add_squad(_crew_def(), 1000, Vector2i(8, 8))
	sim.add_squad(_general_def(), 1000, Vector2i(9, 8))
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
	ai.set_time(sim.time + ai.profile.think_interval)
	ai.update(sim.time + ai.profile.think_interval)

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

	var later := sim.time + AiPlayer.FOUND_RETRY + ai.profile.think_interval
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


func test_an_ai_holding_no_settler_never_asks_for_a_town_centre() -> void:
	# The other bound, and the reason the retry cannot become a spin. The
	# crew is consumed by the town it raises and the general may build
	# nothing (D-20260823-the-opening-is-a-crew-and-a-general), so an AI
	# left with only its escort has no legal move here at all. Ordering
	# anyway is what fills a log with "cannot build a Town Centre", which is
	# exactly what removing the latch outright was measured doing.
	#
	# Non-vacuity is proved by running the SAME fixture with a crew in it
	# rather than by a "setup" assertion about some other order: the whole
	# question is what the presence of a settler changes, and an AI holding
	# only a general legitimately does nothing else either (`_idle_builder`
	# wants gatherers too).
	assert_eq(_halls_asked_for([_general_def(), _general_def()]), 0,
		"An AI with no settler left must not ask for a town centre")
	assert_gt(_halls_asked_for([_crew_def(), _general_def()]), 0,
		"and the same fixture with a crew in it must ask — or the check above "
		+ "passes on an AI that was never going to act at all")


## How many town centres an AI holding exactly these squads asks for over
## six founding retries, with a full wallet and no buildings anywhere.
func _halls_asked_for(defs: Array) -> int:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	for i in range(defs.size()):
		sim.add_squad(defs[i], 1000, Vector2i(8 + i, 8))
	sim.tick()

	var seats := [{"kind": "ai", "player": 1000, "civ": String(ai.civ),
		"team": 0, "name": "AI 1000"}]
	ai.state.handle_packet(NetProtocol.encode_lobby(0, seats, {}, 1))
	_feed(sim, ai)
	# A full wallet, so nothing here is refused for being unaffordable.
	ai.state.handle_packet(NetProtocol.encode_wallet(
		PackedInt32Array([9999, 9999, 9999, 9999])))

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)

	for i in range(6):
		var t := sim.time + AiPlayer.FOUND_RETRY * float(i + 1)
		ai.set_time(t)
		ai.update(t)

	var halls := 0
	for order in _build_orders(sent):
		if String(order["def_id"]) == "town_centre":
			halls += 1
	return halls


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
	sim.add_squad(_crew_def(), 1000,
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


# --- alliances: what an AI may march on (D-050) -----------------------
#
# `ai_player.gd` held no reference to teams at all, so "not mine" meant
# "hostile" and a TEAMMATE was a valid attack objective — the nearest one,
# usually, since allies start close and D-050's shared vision makes their
# buildings known without scouting. Combat is what made it visible rather
# than merely wrong: it refuses to let allies damage each other (D-024),
# so the objective never clears, the nearest-first scan re-picks it every
# time, and the army parks on its teammate for the rest of the match.
#
# Nothing in the test estate could see it. `just ai-ladder` is a
# free-for-all, and every fixture above seats its AI on team 0 — which is
# explicitly NOT a team (D-050), so `are_allied` was false for every pair
# every fixture ever built.

const ALLY := 1001
const FOE := 1002


## An AI (1000) with a teammate and an enemy, told its seats and its spawn
## points exactly as the server tells them. One `BuildingSim`, because two
## would both mint id 0 and collide on the wire.
func _teamed_world() -> Dictionary:
	var space := _space()
	var spawns := [Vector2i(8, 8), Vector2i(14, 8), Vector2i(36, 8)]
	var spawn_indices := []
	for cell in spawns:
		spawn_indices.append(space.index(cell))

	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	var civ := String(ai.civ)
	var seats := [
		{"kind": "ai", "player": 1000, "civ": civ, "team": 1, "name": "AI 1000"},
		{"kind": "ai", "player": ALLY, "civ": civ, "team": 1, "name": "AI 1001"},
		{"kind": "ai", "player": FOE, "civ": civ, "team": 2, "name": "AI 1002"},
	]
	ai.state.handle_packet(NetProtocol.encode_lobby(0, seats, {}, 1))
	ai.state.handle_packet(NetProtocol.encode_welcome(1000, W, H, [], spawn_indices))
	assert_true(ai.state.are_allied(1000, ALLY),
		"Setup: the fixture's teams never reached the AI")
	assert_false(ai.state.are_allied(1000, FOE),
		"Setup: the fixture has no enemy in it")
	return {"space": space, "ai": ai, "spawns": spawns,
		"buildings": BuildingSim.new(space)}


func _tell_about_building(world: Dictionary, owner: int, cell: Vector2i) -> void:
	var buildings: BuildingSim = world["buildings"]
	var id := buildings.add_building(
		BuildingSim.def_by_id(&"town_centre"), owner, cell, true)
	var ai: AiPlayer = world["ai"]
	ai.state.handle_packet(NetProtocol.encode_building_info(
		buildings.info_entries([id])))


func test_an_ai_does_not_march_on_its_teammates_town() -> void:
	# The ally's town is NEARER, which is the ordinary case rather than a
	# contrived one: teammates start beside each other and buildings are
	# picked nearest-first.
	var world := _teamed_world()
	var ai: AiPlayer = world["ai"]
	_tell_about_building(world, ALLY, Vector2i(12, 8))
	_tell_about_building(world, FOE, Vector2i(36, 8))

	assert_eq(ai._enemy_target(), Vector2i(36, 8),
		"The AI picked its teammate's town as the attack objective")


func test_an_ai_that_can_see_only_allies_has_nothing_to_attack() -> void:
	# The livelock itself. An allied building is never destroyed, so a
	# target that names one is re-picked forever — "no target" is the only
	# honest answer, and it is what sends the army out to LOOK instead.
	var world := _teamed_world()
	var ai: AiPlayer = world["ai"]
	_tell_about_building(world, ALLY, Vector2i(12, 8))
	_tell_about_building(world, ALLY, Vector2i(13, 9))

	assert_eq(ai._enemy_target(), Vector2i(-1, -1),
		"The AI found an attack objective in a world containing only its own team")


func test_an_ai_does_not_march_on_a_teammates_army() -> void:
	# The squad half of the same scan, reached only once no building is
	# known — so it needs its own test or the building fix hides it.
	var world := _teamed_world()
	var ai: AiPlayer = world["ai"]
	var space: TorusSpace = world["space"]
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.add_squad(_def(12.0), 1000, Vector2i(8, 8))
	sim.add_squad(_def(4.0), ALLY, Vector2i(10, 8))
	sim.add_squad(_def(4.0), FOE, Vector2i(13, 8))
	sim.tick()

	var visible := sim.visible_to(1000)
	ai.state.handle_packet(NetProtocol.encode_squad_info(
		sim.squad_info_entries(visible)))
	for packet in sim.replicator.collect_for_client(1000, sim.time, visible):
		ai.state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))
	ai.set_time(sim.time)

	assert_eq(ai.state.composition.size(), 3,
		"Setup: the AI cannot see all three armies, so this proves nothing")
	assert_eq(ai._enemy_target(), Vector2i(13, 8),
		"The AI picked its teammate's army as the attack objective")


func test_the_enemy_buildings_seen_metric_does_not_count_allies() -> void:
	# The instrument built to answer "did it ever find an opponent's base"
	# shared the targeting's blind spot, so it would report a found base
	# when what was found was a teammate's.
	var world := _teamed_world()
	var ai: AiPlayer = world["ai"]
	_tell_about_building(world, 1000, Vector2i(8, 8))
	_tell_about_building(world, ALLY, Vector2i(12, 8))
	ai._record_stats()
	assert_eq(ai.peak_enemy_buildings_known, 0,
		"An ally's town was counted as an enemy base")

	_tell_about_building(world, FOE, Vector2i(36, 8))
	ai._record_stats()
	assert_eq(ai.peak_enemy_buildings_known, 1,
		"…and a real enemy's town was then not counted, so the check above is vacuous")


func test_an_ai_does_not_go_looking_at_a_teammates_home() -> void:
	# The third site, and the one the issue did not name. With shared
	# vision (D-050) an ally's start is the one place on the map guaranteed
	# to hold nothing the AI has not already been shown, so marching the
	# army there is a wasted leg every time the cycle comes round.
	var world := _teamed_world()
	var ai: AiPlayer = world["ai"]
	var spawns: Array = world["spawns"]

	var looked := []
	for _i in range(4):
		var cell := ai._next_place_to_look()
		if cell.x < 0:
			break
		looked.append(cell)

	assert_eq(looked, [spawns[2]],
		"The AI went looking at its own team's homes")


## An AI with two crews, a full wallet and nobody in sight (#351).
##
## The wallet is what makes this the right fixture: `_kinds_below_floor`
## is empty, so the ECONOMY has nothing to look for. Whether the AI still
## walks somewhere new is then a question about knowledge alone.
func _sated_ai_with_nobody_in_sight() -> Dictionary:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var ai := AiPlayer.new(1000, CivRoster.ids()[0])
	sim.add_squad(_crew_def(), 1000, Vector2i(8, 8))
	sim.add_squad(_crew_def(), 1000, Vector2i(9, 8))
	sim.tick()

	var seats := [{"kind": "ai", "player": 1000, "civ": String(ai.civ),
		"team": 0, "name": "AI 1000"}]
	ai.state.handle_packet(NetProtocol.encode_lobby(0, seats, {}, 1))
	_feed(sim, ai)
	ai.state.handle_packet(NetProtocol.encode_wallet(
		PackedInt32Array([9999, 9999, 9999, 9999])))
	# A KNOWN NODE OF EVERY KIND THE FLOOR ASKS FOR, and this is the half
	# the fixture is worthless without. `_kinds_below_floor` appends FOOD
	# unconditionally, so an AI that has been shown no nodes at all is
	# hungry by construction and scouts forever for a reason that has
	# nothing to do with the rule under test. The first version of this
	# fixture omitted them and passed identically with the change
	# reverted — a test constructing its own input and then testing the
	# constructor.
	var space := _space()
	ai.state.handle_packet(NetProtocol.encode_nodes([
		{"cell": space.index(Vector2i(10, 8)),
			"kind": Economy.ResourceKind.FOOD},
		{"cell": space.index(Vector2i(11, 8)),
			"kind": Economy.ResourceKind.WOOD},
	]))

	var sent := []
	ai.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	return {"sim": sim, "ai": ai, "sent": sent}


## THE DEFECT THIS FILE EXISTS FOR (#351).
##
## Scouting used to be driven only by a resource the AI lacked, so an AI
## whose economy was satisfied stopped walking anywhere new — and
## `_scout_leg`, which the naval question reads to answer "have I
## searched", stopped with it. Measured on a real 600 s match on
## `maps/isles.tres` before the fix: 3 buildings, 29 squads,
## `scout_legs=2` after ten minutes, so the AI never concluded it had run
## out of world and never built a navy. The predicate was right; the
## number under it did not mean what its name said.
##
## A BEHAVIOURAL version of this test was written first and DELETED for
## being vacuous: driven through `update()`, the AI retires a node its
## crew never reaches, goes hungry, and scouts again for the old reason —
## so it passed identically with the fix reverted. Only asking the guard
## directly measures the enemy trigger alone.
func test_it_looks_for_an_enemy_and_stops_once_it_has_searched() -> void:
	# The other half, and the reason the trigger is bounded: past
	# SCOUTED_ENOUGH_LEGS the answer is "I have looked and nobody is
	# here", which is what the naval question is waiting to hear. An
	# unbounded search would spend a crew forever on a map with one
	# opponent behind a wall of fog.
	#
	# Driven at the GUARD rather than through `update()`, deliberately.
	# The economy has its own reason to scout — a node whose crew never
	# arrives is retired, and the AI is hungry again — and in a fixture
	# with no real gathering that churn re-triggers scouting for a reason
	# that is not the one under test. Asking the function directly is the
	# only way to measure the enemy trigger alone.
	var w := _sated_ai_with_nobody_in_sight()
	var ai: AiPlayer = w["ai"]
	var sim: SquadSim = w["sim"]
	ai.set_time(sim.time + 1.0)

	ai._scout_leg = AiPlayer.SCOUTED_ENOUGH_LEGS
	var before := ai.scout_legs
	ai._scout_for_what_it_lacks()
	assert_eq(ai.scout_legs, before,
		"an AI that has searched enough and needs nothing must not keep "
		+ "walking — the enemy trigger is bounded, not a standing order")

	# And the mirror, so the assertion above cannot pass by the function
	# being inert: one leg short, it still goes.
	ai._scout_leg = AiPlayer.SCOUTED_ENOUGH_LEGS - 1
	ai._resource_scout = -1
	ai._scout_leg_until = 0.0
	ai._scout_for_what_it_lacks()
	assert_gt(ai.scout_legs, before,
		"premise: one leg short of enough, the same call does scout — "
		+ "otherwise the bound above proves only that nothing happens")


## An AI holding the shipped opening, with a resource node standing on the
## cell its crew is about to found on (#381 / #217, fixed by PR #255).
func _founding_ai_blocked_at_home() -> Dictionary:
	var w := _founding_ai(1)
	var ai: AiPlayer = w["ai"]
	var sim: SquadSim = w["sim"]
	var builder := ai._founder()
	assert_gte(builder, 0, "premise: something in the opening may found")
	var home := ai.state.squad_cell(builder, sim.time)
	assert_gte(home.x, 0, "premise: the founder has a known cell")
	ai.state.handle_packet(NetProtocol.encode_nodes([
		{"cell": ai.state.space.index(home), "kind": Economy.ResourceKind.WOOD},
	]))
	w["home"] = home
	return w


func _town_sites(sent: Array) -> Array:
	var out := []
	for order in _build_orders(sent):
		if String(order["def_id"]) == "town_centre":
			out.append(int(order["cell"]))
	return out


func test_an_ai_blocked_at_its_start_founds_somewhere_else() -> void:
	# #381's symptom, verified against the merged #255 fix rather than by
	# reading it. Before that fix `_found_town` ordered at the spawn cell
	# and never varied, so a node standing there — 20.0% of starts on the
	# shipped default map, 8.3% on `ladder`, measured by worker 88 — meant
	# the seat re-asked for the same refused cell for the whole match:
	# buildings=0, the crew never consumed so squads_peak stayed at the
	# opening 2, and no scouting, because scouting needs two crews.
	#
	# Driven as a FIXTURE rather than looked for in a ladder run on
	# purpose: with 2 AI seats on `isles` a run has only about a 34%
	# chance of containing a blocked start, so a green there would have
	# meant "the case did not arise" — a coin flip dressed as evidence.
	var w := _founding_ai_blocked_at_home()
	var ai: AiPlayer = w["ai"]
	var sim: SquadSim = w["sim"]
	var blocked: Vector2i = w["home"]

	for i in range(6):
		var t := sim.time + AiPlayer.FOUND_RETRY * float(i + 1)
		ai.set_time(t)
		ai.update(t)

	var sites := _town_sites(w["sent"])
	assert_gt(sites.size(), 0,
		"premise: a blocked AI must still ASK — a seat that stops asking "
		+ "is a different defect from one that asks in the wrong place")
	assert_false(sites.has(ai.state.space.index(blocked)),
		"an AI whose start holds a resource node must found elsewhere, "
		+ "not re-ask for the refused cell for the whole match (#381)")


func test_an_unblocked_ai_still_founds_on_its_own_start() -> void:
	# The mirror, and it is what stops the test above passing for the
	# wrong reason. If the AI simply never chose its own cell, the
	# assertion would hold with the filter doing nothing — so this pins
	# that the start IS the preferred site when it is free, and that the
	# node is what moved it.
	var w := _founding_ai(1)
	var ai: AiPlayer = w["ai"]
	var sim: SquadSim = w["sim"]
	var builder := ai._founder()
	var home := ai.state.squad_cell(builder, sim.time)

	ai.set_time(sim.time + AiPlayer.FOUND_RETRY)
	ai.update(sim.time + AiPlayer.FOUND_RETRY)

	var sites := _town_sites(w["sent"])
	assert_gt(sites.size(), 0, "premise: an unblocked AI founds")
	assert_true(sites.has(ai.state.space.index(home)),
		"with nothing in the way the start is the site — so the other "
		+ "test's result is the node moving it, not indifference")
