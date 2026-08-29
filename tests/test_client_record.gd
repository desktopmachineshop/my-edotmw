extends GutTest

## Guards D-20260827-a-client-record-forgets-the-match-it-left (#157).
##
## A per-client record on the server is a player id plus a set of
## PER-MATCH baselines: "buildings I have already shown this client",
## "resource cells I have already sent", "squads that were visible last
## tick". Every one of those is keyed by an id or a cell index that the
## NEXT match mints again from zero — so one surviving a return to the
## lobby makes the server believe it has already told a client about a
## thing that no longer exists, and never tell it about the one now
## standing there.
##
## Two instances have been paid for already. `known_buildings` surviving
## produced 106 building desyncs in one playtest (the sandbox Regen
## button), and #157 is the quieter version of the same thing: match
## two's town centre takes match one's id, the server finds it already
## known, sends no BUILDING_INFO, and hashes a building the client was
## never given — a static disagreement that heals the moment something
## marks that building dirty. `nodes_known` and `nodes_depleted_told`
## were still live when this file was written.
##
## server.gd is instantiated directly and never added to the tree, so
## `_ready()` — which wants a socket and a command line — does not run.
## That is the same distinction D-075's 2026-08-16 amendment had to make
## for client.gd: "it needs a scene tree" is true of `_ready()`, not of
## the file.

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


## A server mid-match, with one human client holding a real ClientState
## on the other end of a LoopbackPeer.
##
## The peer goes in `_clients`, not `_ai_clients`, deliberately: AI
## records are dropped wholesale by `_return_to_lobby` (their brains go
## with the world), so the bug this file is about can only be reached
## through a SOCKET's record. Nothing in the paths exercised here treats
## a `_clients` key as an ENet peer — `_broadcast_lobby` and `_replicate`
## both call `send()` and nothing else, and say so.
func _server_in_match() -> Dictionary:
	var server = load("res://server.gd").new()
	var space := _space()

	server._match = MatchState.new()
	server._match.require_admin_start = false
	server._settings = server._match.map_settings
	server._match.add_player(1)
	server._match.phase = MatchState.Phase.RUNNING

	var state := ClientState.new()
	var peer := LoopbackPeer.new(state)
	server._clients[peer] = server._fresh_record(1)

	_build_world(server, space)
	return {"server": server, "peer": peer, "state": state, "space": space}


## The half of `_build_world` these tests need: a fresh sim, buildings and
## economy over a fresh space. Called again after the return to the lobby,
## which is what makes the second match a second WORLD rather than the
## same objects with different contents.
func _build_world(server, space: TorusSpace) -> void:
	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy
	server._passable = PackedByteArray()
	server._depleted_nodes.clear()


## A squad whose only job is to make its owner see the ground around it.
func _watcher(server, at: Vector2i, owner: int = 1) -> int:
	var def := UnitRoster.first()
	assert_not_null(def, "no units are shipped at all")
	return server._sim.add_squad(def, owner, at)


func _refresh_vision(server) -> void:
	server._sim.vision.rebuild(server._sim, server._buildings)


func _cell(server, at: Vector2i) -> int:
	return server._sim.space.index(at)


## Everybody out, then a new world over the same ground.
##
## Cell indices are a property of the MAP SIZE and entity ids of an array
## length, so match two mints exactly the identifiers match one used —
## which is the whole reason a surviving baseline is silent rather than
## loud.
func _second_match(w: Dictionary) -> void:
	var server = w["server"]
	server._return_to_lobby()
	(w["state"] as ClientState).leave_match()
	_build_world(server, w["space"])
	server._match.phase = MatchState.Phase.RUNNING


# --- the node half: the two sets that were still live -------------------

func test_a_second_matchs_forests_reach_a_client_that_played_the_first() -> void:
	var w := _server_in_match()
	var server = w["server"]
	var state: ClientState = w["state"]
	var peer = w["peer"]
	var here := Vector2i(8, 6)

	_watcher(server, here)
	_refresh_vision(server)

	# Match one puts a forest on this client's doorstep and tells them.
	var cell := _cell(server, here)
	server._economy.nodes[cell] = {"kind": Economy.ResourceKind.WOOD, "remaining": 100}
	server._send_visible_nodes(peer, 1, server._clients[peer])
	assert_true(state.nodes.has(cell),
		"setup: a visible node should reach the client in the first match")

	_second_match(w)

	_watcher(server, here)
	_refresh_vision(server)
	server._economy.nodes[cell] = {"kind": Economy.ResourceKind.STONE, "remaining": 100}
	server._send_visible_nodes(peer, 1, server._clients[peer])

	assert_true(state.nodes.has(cell),
		"the second match's node must be sent — the client tore its world down, "
		+ "so a server that thinks it already told them leaves the cell empty forever")
	if state.nodes.has(cell):
		assert_eq(int(state.nodes[cell]), int(Economy.ResourceKind.STONE),
			"and it must be THIS match's node, not the one that stood there before")

	server.free()


func test_a_second_matchs_felling_is_reported_to_a_client_that_played_the_first() -> void:
	# `nodes_depleted_told` is the sibling set, and it fails the other way
	# round: a cell felled in match one is remembered as "already told",
	# so the tree match two grows there is never taken down and the client
	# draws a forest over ground the economy has finished with.
	var w := _server_in_match()
	var server = w["server"]
	var state: ClientState = w["state"]
	var peer = w["peer"]
	var here := Vector2i(8, 6)

	_watcher(server, here)
	_refresh_vision(server)
	var cell := _cell(server, here)

	server._economy.nodes[cell] = {"kind": Economy.ResourceKind.WOOD, "remaining": 100}
	server._send_visible_nodes(peer, 1, server._clients[peer])
	server._depleted_nodes[cell] = true
	server._send_visible_nodes(peer, 1, server._clients[peer])
	assert_eq(state.felled.size(), 1,
		"setup: a felling the client can see should reach them in the first match")

	_second_match(w)

	_watcher(server, here)
	_refresh_vision(server)
	server._economy.nodes[cell] = {"kind": Economy.ResourceKind.WOOD, "remaining": 100}
	server._send_visible_nodes(peer, 1, server._clients[peer])
	assert_true(state.nodes.has(cell), "setup: the second match's node must arrive first")

	server._depleted_nodes[cell] = true
	server._send_visible_nodes(peer, 1, server._clients[peer])
	assert_eq(state.felled.size(), 1,
		"the second match's felling must be reported too — a client that is never "
		+ "told keeps drawing a tree over ground the economy has finished with")

	server.free()


# --- the building half: #157's own symptom -----------------------------

func test_a_second_matchs_buildings_are_hashed_over_a_set_the_client_was_given() -> void:
	# #157 exactly: match two's town centre takes match one's id, the
	# server finds it already in `known_buildings`, sends no BUILDING_INFO
	# — and then hashes it anyway, because the hash is taken over that
	# same ever-revealed set (D-030). Client and server both hash a
	# constant, and they differ, until something marks the building dirty
	# and the resend heals it. Four desyncs, ticks 340-370, then silence.
	var w := _server_in_match()
	var server = w["server"]
	var state: ClientState = w["state"]
	var peer = w["peer"]
	var here := Vector2i(8, 6)

	var def := BuildingSim.def_by_id(&"town_centre")
	assert_not_null(def, "the shipped town centre is where BuildingSim looks for it")

	_watcher(server, here)
	server._buildings.add_building(def, 1, here, true)
	_refresh_vision(server)
	_deliver_buildings(server, peer, 1)
	assert_eq(state.buildings.size(), 1,
		"setup: a visible building should reach the client in the first match")

	_second_match(w)

	# Match two, same opening: ids restart at 0, so this is a DIFFERENT
	# building wearing the id the client was shown last match.
	_watcher(server, here)
	var second: int = server._buildings.add_building(def, 1, here, true)
	_refresh_vision(server)
	_deliver_buildings(server, peer, 1)

	assert_eq(state.buildings.size(), 1,
		"the second match's building must be delivered, not assumed known")
	assert_eq(state.building_hash(),
		server._buildings.composition_hash(server._clients[peer]["known_buildings"].keys()),
		"client and server must hash the same set — a building the server counts "
		+ "and the client was never sent is #157's static, self-healing desync")
	assert_true(state.buildings.has(BuildingSim.wire_id(second)),
		"and the id the client holds must be this match's building")

	server.free()


## The building half of `_replicate`'s per-client loop, lifted out so a
## test can run it without a tick. Deliberately the same two steps in the
## same order the server performs — grow `known_buildings` from what is
## visible, then send exactly what was added — because the hash is taken
## over the set the first step leaves behind.
func _deliver_buildings(server, peer, player: int) -> void:
	var record = server._clients[peer]
	var known: Dictionary = record.get("known_buildings", {})
	var to_send := []
	for id in server._buildings.visible_to(player, server._sim.vision):
		if not known.has(id):
			known[id] = true
			to_send.append(id)
	record["known_buildings"] = known
	if not to_send.is_empty():
		peer.send(0, NetProtocol.encode_building_info(
			server._buildings.info_entries(to_send)), 0)


# --- the rule itself ---------------------------------------------------

func test_every_per_match_key_a_record_grows_is_one_the_birth_shape_clears() -> void:
	# The list is the defect, so this is the test that has to exist: it
	# reads server.gd for every key anything ever writes onto a client
	# record, and fails if `_fresh_record` does not mint it. A future
	# baseline added to `_replicate` goes red HERE rather than in a
	# playtest of the second match, which is the only place the last two
	# were ever going to show up.
	#
	# Same shape as test_terrain_fog.gd's "assert the caller exists" scan
	# and test_multi_agent_isolation.gd's literal scan — and it answers
	# D-106's own caveat about those, which is that a scan only ever
	# covers what it enumerates.
	var source := FileAccess.get_file_as_string("res://server.gd")
	assert_false(source.is_empty(), "could not read server.gd to scan it")

	var server = load("res://server.gd").new()
	var fresh: Dictionary = server._fresh_record(1)
	server.free()

	var written := {}
	var re := RegEx.create_from_string('record(?:\\["|\\.get\\(")([a-z_]+)"')
	assert_not_null(re, "the scan's own regex failed to compile")
	for m in re.search_all(source):
		written[m.get_string(1)] = true

	assert_true(written.has("known_buildings"),
		"the scan found no known_buildings at all, so it is matching nothing "
		+ "and would pass however wrong the reset was")

	for key in written:
		assert_true(fresh.has(key),
			("`%s` is written onto a client record but `_fresh_record` does not mint it, "
			+ "so a return to the lobby carries it into the next match") % key)
