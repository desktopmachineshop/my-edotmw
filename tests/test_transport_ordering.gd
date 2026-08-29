extends GutTest

## Guards #184 / D-094 criterion 5, and makes D-042's central finding
## falsifiable at the SEAM for the first time.
##
## D-042 measured that curve packets carry no sequence number, so the
## client installs whichever curve arrived most recently — and decided to
## hold the TRANSPORT to reliable-ordered delivery rather than add
## sequencing the protocol was measured not to need.
## `test_client_state.gd` already proves the protocol's half: feed two
## curves backwards by hand and the client keeps the stale one.
##
## What was missing is the other half. A transport is a thing you can
## SWAP, and D-088 is about to swap one in: nothing anywhere said "a
## transport that reorders breaks this game", in a form a new transport
## could be held against. That is what this file is. It drives the same
## scenario through `NetTransport` — the seam both ENet and Steam sit
## behind — with two fakes, one honest and one that reorders, and asserts
## that the honest one agrees with the server and **the reordering one
## does not**.
##
## The second assertion is the point. A test that only checked the good
## case would pass just as happily against a transport with no ordering
## guarantee at all, which is the vacuous-pass shape this project refuses
## everywhere else.


## A peer that is not a socket, duck-typed to what a caller drains: the
## same shape `loopback_peer.gd` (D-051), `host_link.gd` (#182) and
## `ENetPacketPeer` all present.
class FakePeer extends RefCounted:
	var queued: Array = []

	func get_available_packet_count() -> int:
		return queued.size()

	func get_packet() -> PackedByteArray:
		return queued.pop_front()

	func send(_channel: int, _packet: PackedByteArray, _flags: int = 0) -> int:
		return OK


## A transport that delivers what it was given — in order, or reversed.
##
## `reorder` is not a hypothetical knob: it is the property a real
## transport either has or lacks, and a relay transport has to be
## configured to lack it (reliable-ordered lanes, not unreliable ones).
## This is what a wrapper that got that configuration wrong would look
## like from the outside.
class FakeTransport extends NetTransport:
	var peer := FakePeer.new()
	var reorder := false
	var _pending: Array = []
	var _delivered := false

	func offer(packet: PackedByteArray) -> void:
		_pending.append(packet)

	## Hand everything over at once, which is when the ordering question
	## is actually decided — a transport reorders within what it has in
	## flight, not across a quiet period.
	func poll() -> Array:
		if _delivered or _pending.is_empty():
			return [EVENT_NONE, null]
		_delivered = true
		var order := _pending.duplicate()
		if reorder:
			order.reverse()
		peer.queued.append_array(order)
		return [EVENT_RECEIVE, peer]

	func is_open() -> bool:
		return true

	func describe() -> String:
		return "fake transport (reorder=%s)" % reorder


## The wire bytes of one squad's curve, drained from the replicator the
## same way `server.gd` drains it — the identical helper
## `test_client_state.gd` uses, because a second way of getting curve
## bytes is a second thing to keep true.
func _curve_bytes_for(sim: SquadSim, player: int, squad: int) -> PackedByteArray:
	for packet in sim.replicator.collect_for_client(player, sim.time, sim.visible_to(player)):
		if int(packet.get("id", -1)) == squad:
			return packet["bytes"]
	return PackedByteArray()


func _space() -> TorusSpace:
	return TorusSpace.new(32, 16, 1.0)


func _roster_def() -> UnitDef:
	var def := UnitRoster.for_civ_archetype(&"emberdeep", &"levy")
	assert_not_null(def, "Setup: the shipped roster must field something to move")
	return def


## Drain a transport into a client, exactly as `client.gd` does — through
## the seam's own event shape, so this exercises the contract rather than
## a convenient shortcut around it.
func _drain(transport: NetTransport, state: ClientState) -> void:
	while true:
		var event := transport.poll()
		if int(event[0]) == NetTransport.EVENT_NONE:
			return
		if int(event[0]) != NetTransport.EVENT_RECEIVE:
			continue
		var peer = event[1]
		while peer.get_available_packet_count() > 0:
			state.handle_packet(peer.get_packet())


## Two curves for one squad, newer last, and the world that produced
## them.
func _two_curves() -> Dictionary:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var id := sim.add_squad(_roster_def(), 1, Vector2i(2, 2))

	var welcome := NetProtocol.encode_welcome(
		1, space.width, space.height, PackedInt32Array([id]), [], 40, 0)
	var info := NetProtocol.encode_squad_info(sim.squad_info_entries(sim.visible_to(1)))

	sim.order_move(id, Vector2i(20, 10))
	sim.tick()
	var first := _curve_bytes_for(sim, 1, id)

	sim.order_move(id, Vector2i(4, 12))
	sim.tick()
	var second := _curve_bytes_for(sim, 1, id)

	assert_false(first.is_empty(), "Setup: the first order should have produced a curve")
	assert_false(second.is_empty(), "Setup: the second order should have produced a curve")
	assert_ne(first, second, "Setup: the two orders should produce different curves")

	return {"sim": sim, "id": id, "welcome": welcome, "info": info,
		"first": first, "second": second}


func test_the_seam_keeps_enets_event_vocabulary_value_for_value() -> void:
	# net_transport.gd claims its constants mirror ENet's so the existing
	# `_service_network` loops did not have to be rewritten. If Godot
	# ever renumbered them, every event would be misrouted SILENTLY — a
	# connect handled as a disconnect — so the claim is asserted rather
	# than trusted.
	assert_eq(NetTransport.EVENT_NONE, ENetConnection.EVENT_NONE)
	assert_eq(NetTransport.EVENT_CONNECT, ENetConnection.EVENT_CONNECT)
	assert_eq(NetTransport.EVENT_DISCONNECT, ENetConnection.EVENT_DISCONNECT)
	assert_eq(NetTransport.EVENT_RECEIVE, ENetConnection.EVENT_RECEIVE)
	assert_eq(NetTransport.EVENT_ERROR, ENetConnection.EVENT_ERROR)


func test_an_ordered_transport_leaves_the_client_agreeing_with_the_server() -> void:
	var world := _two_curves()
	var sim: SquadSim = world["sim"]
	var id: int = world["id"]

	var transport := FakeTransport.new()
	transport.offer(world["welcome"])
	transport.offer(world["info"])
	transport.offer(NetProtocol.encode_curve(world["first"]))
	transport.offer(NetProtocol.encode_curve(world["second"]))

	var state := ClientState.new()
	_drain(transport, state)

	# Sampled at the SERVER's own clock, where `cell_of` is defined —
	# comparing a client's future-sampled position against a sim that has
	# not reached that time yet would be a different question.
	assert_eq(state.squad_cell(id, sim.time), sim.cell_of(id),
		"with delivery in order, the client must be where the server says the squad is")


func test_a_reordering_transport_is_CAUGHT() -> void:
	# The half that matters. Without this, a transport with no ordering
	# guarantee would pass the test above unchanged — and D-042's whole
	# argument is that such a transport is not usable here.
	var world := _two_curves()
	var sim: SquadSim = world["sim"]
	var id: int = world["id"]

	var honest := FakeTransport.new()
	var shuffled := FakeTransport.new()
	shuffled.reorder = true
	for t in [honest, shuffled]:
		t.offer(world["welcome"])
		t.offer(world["info"])

	# Only the CURVES are reordered; the welcome has to arrive first or
	# the client has no map to interpret anything against, which would
	# fail for a reason that is not ordering.
	var ordered_state := ClientState.new()
	_drain(honest, ordered_state)
	ordered_state.handle_packet(NetProtocol.encode_curve(world["first"]))
	ordered_state.handle_packet(NetProtocol.encode_curve(world["second"]))

	var shuffled_state := ClientState.new()
	_drain(shuffled, shuffled_state)
	shuffled_state.handle_packet(NetProtocol.encode_curve(world["second"]))
	shuffled_state.handle_packet(NetProtocol.encode_curve(world["first"]))

	# Compared client-to-client at one future time, the shape
	# `test_client_state.gd` established: the question is whether ORDER
	# changed what the client believes, and the two differ only in that.
	var truth: Vector2i = ordered_state.squad_cell(id, sim.time + 1.0)
	assert_eq(ordered_state.squad_cell(id, sim.time), sim.cell_of(id),
		"Setup: in order, the client agrees with the server")
	assert_ne(shuffled_state.squad_cell(id, sim.time + 1.0), truth,
		("a transport that reorders two curves for one squad leaves the client "
		+ "permanently holding the stale one — curves are sent only on change "
		+ "(D-003), so no later message corrects it. This is what a relay peer "
		+ "configured on an unreliable or unordered lane would do."))


func test_the_enet_transport_reports_what_it_is() -> void:
	# The transport is the first thing to suspect when two machines
	# disagree, and "which one was it" must not be a guess — both binaries
	# print `describe()` beside the endpoint.
	var closed := EnetTransport.new()
	assert_false(closed.is_open(), "an unopened transport must say so")
	assert_true(closed.describe().contains("enet"),
		"and still name itself: %s" % closed.describe())

	var listening := EnetTransport.listen(0, 4, 2)
	# Port 0 asks the OS for any free port, so this genuinely binds.
	assert_true(listening.is_open(), "listening on an ephemeral port should succeed")
	assert_true(listening.describe().contains("listening"),
		"a listening transport says so: %s" % listening.describe())
	listening.close()
	assert_false(listening.is_open(), "and close() is observable")
	listening.close()


func test_both_binaries_go_through_the_seam() -> void:
	# The caller-exists check (D-106's rule as a test). A seam nothing
	# uses is the declared-and-unread shape — and it would be worse than
	# useless here, because the Steam transport would then be written
	# against an interface the game does not actually take.
	for path in ["res://server.gd", "res://client.gd"]:
		var source := _read(path)
		assert_true(source.contains("NetTransport"),
			"%s must service its network through the seam" % path)
		assert_false(source.contains("ENetConnection"),
			("%s must not reach ENetConnection directly any more — the whole point "
			+ "is that neither end knows which transport it got") % path)


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text
