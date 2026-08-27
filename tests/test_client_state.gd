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


## A synthetic def, for tests that don't go through SQUAD_INFO.
func _def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"client_test"
	d.squad_size = 10
	d.move_speed = 3.5
	return d


## The def the SERVER actually spawns. Tests that exercise the live path
## must use this rather than a synthetic one — a hand-built def would not
## resolve through UnitRoster.by_id on the client side, and more
## importantly a test that invents its own squad size cannot notice the
## client and server disagreeing about the real one.
func _roster_def() -> UnitDef:
	return UnitRoster.first()


## Drive a sim and a client through the real protocol, exactly as
## server.gd does: welcome, then composition, then curves.
func _connect(sim: SquadSim, state: ClientState, player: int) -> void:
	var visible := sim.visible_to(player)
	state.handle_packet(NetProtocol.encode_welcome(player, W, H, visible))
	state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))


func _pump(sim: SquadSim, state: ClientState, player: int, ticks: int) -> int:
	var bytes := 0
	for _i in range(ticks):
		sim.tick()
		for packet in sim.replicator.collect_for_client(player, sim.time, sim.visible_to(player)):
			var wire := NetProtocol.encode_curve(packet["bytes"])
			bytes += wire.size()
			state.handle_packet(wire)
		state.handle_packet(NetProtocol.encode_state_hash(
			sim.tick_count, sim.composition_hash(sim.visible_to(player))))
	return bytes


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


func test_welcome_carries_the_squad_cap_and_the_match_clock() -> void:
	# Both are the HUD's, and both must come from the server: the cap is
	# MapConfig data this side has no copy of, and a clock each client ran
	# for itself would show every player a different match length.
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(2, W, H, [4], [], 40, 1200))

	assert_eq(state.squad_cap, 40)
	# 1200 ticks at 10 Hz is two minutes in.
	assert_almost_eq(state.match_elapsed(), 120.0, 1.0)


func test_a_welcome_carrying_everything_still_reads_the_spawn_table() -> void:
	# The fields added for the HUD sit AFTER the spawn table on the wire,
	# so a mistake in either length prefix silently shifts the other. The
	# bots found their town hall at `spawn_cell_of`, so a shifted spawn
	# table does not error — it just means nobody ever builds anything,
	# which is a load-test verdict of buildings_known=0 and no clue why.
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(2, W, H, [4, 5], [11, 22], 40, 1200))

	assert_true(state.owns(4) and state.owns(5), "squads survive the added fields")
	assert_eq(Array(state.spawn_cells), [11, 22], "and so does the spawn table")
	assert_eq(state.squad_cap, 40)
	assert_almost_eq(state.match_elapsed(), 120.0, 1.0)


func test_a_client_and_the_server_agree_where_an_ai_player_starts() -> void:
	# The client's own copy of "which spawn point is mine" drifted from the
	# server's the day the server moved to the SEAT index (MatchState.
	# spawn_index), and stayed wrong for every AI player: ids start at 1000
	# (D-051), so `(player - 1) % point_count` lands on some other player's
	# start. An AI asked where its home was and was told a rival's corner —
	# where it then tried to found its capital.
	#
	# Driven through the real seat list, because that is the fact both sides
	# key on and the only thing that makes them agree by construction.
	var m := MatchState.new()
	m.require_admin_start = true
	m.add_player(1)                            # seat 0 — the human
	m.add_ai(1, CivRoster.ids()[0], 1000)      # seat 1
	m.add_ai(1, CivRoster.ids()[0], 1001)      # seat 2

	var spawns := [11, 22, 33, 44]
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_lobby(m.admin_player, m.seats, {}, 0))
	state.handle_packet(NetProtocol.encode_welcome(1000, W, H, [], spawns))

	for seat in m.seats:
		var who := int(seat["player"])
		var server_cell := state.space.from_index(
			spawns[m.spawn_index(who, spawns.size())])
		assert_eq(state.spawn_cell_of(who), server_cell,
			"client and server disagree about where player %d starts" % who)

	# Name the exact case that shipped, so a regression says so rather than
	# just failing somewhere in the loop.
	assert_eq(state.spawn_cell_of(1000), state.space.from_index(22),
		"AI 1000 sits in seat 1 and starts on spawn point 1, not on (1000-1)%4")


func test_a_client_with_no_seat_list_still_answers_from_the_spawn_table() -> void:
	# The fallback, kept honest: a fixture that sends only a WELCOME (every
	# test above, and any client that has not yet been told the lobby) has
	# nothing but a player id to go on, and must still get a usable cell
	# rather than nothing.
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(2, W, H, [], [11, 22]))
	assert_eq(state.spawn_cell_of(2), state.space.from_index(22))


func test_a_welcome_without_the_new_fields_still_reads() -> void:
	# The trailing-field rule this protocol already uses for spawns: a
	# packet written before these existed must read back as "not stated"
	# rather than as garbage.
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(2, W, H, [4]))
	assert_eq(state.squad_cap, 0, "no cap stated")
	assert_eq(state.match_elapsed(), 0.0, "no clock stated")


func test_the_match_clock_reanchors_on_later_server_ticks() -> void:
	# The clock derives locally between messages (D-003) and re-anchors
	# whenever the server states a tick, which is what stops it drifting
	# over a match this project wants to run for one to two hours (D-056).
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(2, W, H, [4], [], 40, 100))
	assert_almost_eq(state.match_elapsed(), 10.0, 1.0)

	state.note_server_tick(6000)
	assert_almost_eq(state.match_elapsed(), 600.0, 1.0)


func test_the_match_clock_never_runs_backwards() -> void:
	# A stale or out-of-order tick must not rewind the timer. A match
	# clock that jumps back is read as a bug by every player who sees it,
	# and it would be a plausible thing to see if any path ever stated an
	# older tick.
	var state := ClientState.new()
	state.note_server_tick(6000)
	var later := state.match_elapsed()
	state.note_server_tick(100)
	assert_true(state.match_elapsed() >= later - 0.01,
		"an older tick must not rewind the clock")


func test_living_squad_count_matches_what_the_cap_actually_limits() -> void:
	# The HUD prints this against `squad_cap`, so it has to count the same
	# things the server counts in MatchState.has_squad_capacity: this
	# player's own living squads. Counting every squad on screen — which
	# is what `curves` holds — would put other players' armies into a
	# number printed beside YOUR ceiling.
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, []))
	state.handle_packet(NetProtocol.encode_squad_info([
		{"id": 1, "def_id": "gildedreach_levy", "alive": 10, "shape": "line", "owner": 1},
		{"id": 2, "def_id": "gildedreach_levy", "alive": 10, "shape": "line", "owner": 1},
		{"id": 3, "def_id": "gildedreach_levy", "alive": 10, "shape": "line", "owner": 2},
	]))
	assert_eq(state.living_squad_count(), 2, "only this player's squads")

	state.handle_packet(NetProtocol.encode_squad_info([
		{"id": 2, "def_id": "gildedreach_levy", "alive": 0, "shape": "line", "owner": 1},
	]))
	assert_eq(state.living_squad_count(), 1, "and only the living ones")


func test_a_squad_wiped_out_stops_being_one_this_client_owns() -> void:
	# Ownership has to shrink, not only grow. It did not, and the symptom
	# was invisible for a long time because the server refused the orders
	# anyway: the GUI kept offering dead squads for selection, and the
	# load-test bots kept ordering corpses instead of noticing they had
	# nothing left and training more.
	#
	# The founding party makes this ordinary rather than exotic — it is
	# consumed the moment it is committed to a town hall (D-031), so every
	# player reaches zero owned squads in the first minute of a match.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var id := sim.add_squad(_roster_def(), 1, Vector2i(2, 2))

	var state := ClientState.new()
	_connect(sim, state, 1)
	assert_true(state.owns(id), "The client should start owning what the welcome gave it")

	state.handle_packet(NetProtocol.encode_squad_combat(
		sim.tick_count, [{"id": id, "alive": 0, "routed": false}]))

	assert_false(state.owns(id), "A squad with no soldiers left is not one this client can order")
	assert_eq(state.encode_order(id, Vector2i(3, 3)).size(), 0,
		"The client should stop sending orders for a squad it just watched die")


func test_a_squad_merely_bloodied_is_still_ours() -> void:
	# The other side of the boundary, so the check above cannot pass by
	# dropping squads on any casualty at all.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var id := sim.add_squad(_roster_def(), 1, Vector2i(2, 2))

	var state := ClientState.new()
	_connect(sim, state, 1)

	state.handle_packet(NetProtocol.encode_squad_combat(
		sim.tick_count, [{"id": id, "alive": 1, "routed": true}]))

	assert_true(state.owns(id), "One surviving soldier is still a squad we command")


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
	#
	# The test deliberately never mentions squad size, formation shape or
	# spacing. Its predecessor passed `def.squad_size` straight to the
	# client, which meant it proved Formation is a pure function — it could
	# not notice that the live client was feeding that function completely
	# different inputs than the server used. It passed for the entire time
	# a real client was drawing 40-strong lines where the server had
	# 32-strong loose formations.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var id := sim.add_squad(_roster_def(), 1, Vector2i(4, 4))
	sim.order_move(id, Vector2i(18, 10))

	var state := ClientState.new()
	_connect(sim, state, 1)
	_pump(sim, state, 1, 20)

	var server_side := sim.soldier_transforms(id)
	var client_side := state.soldier_transforms(id, sim.time)

	assert_gt(client_side.size(), 0, "The client should be deriving soldiers by now")
	assert_eq(client_side.size(), server_side.size(),
		"Client and server disagree about how many soldiers this squad has")
	for i in range(server_side.size()):
		assert_almost_eq(client_side[i].origin.x, server_side[i].origin.x, 0.001,
			"Soldier %d x diverges" % i)
		assert_almost_eq(client_side[i].origin.z, server_side[i].origin.z, 0.001,
			"Soldier %d z diverges" % i)


func test_client_learns_composition_rather_than_assuming_it() -> void:
	# The specific regression. The roster's default unit is NOT 40 strong
	# in "line" — the values the client used to assume — so this fails
	# loudly if anyone reintroduces a nominal default.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var def := _roster_def()
	var id := sim.add_squad(def, 1, Vector2i(2, 2))

	var state := ClientState.new()
	_connect(sim, state, 1)

	assert_eq(state.alive_of(id), def.squad_size,
		"Client's squad strength should come from the server, not a guess")
	assert_eq(state.shape_of(id), def.formation_shape,
		"A freshly spawned squad should be in its UnitDef's shape")
	assert_almost_eq(state.spacing_of(id), def.formation_spacing, 0.0001)


func test_a_formation_change_reaches_the_client() -> void:
	# D-058's client half. Shape is MUTABLE replicated state, so a client
	# that resolves it from the UnitDef instead of the wire is stuck with
	# the spawn default forever: the formation buttons look inert, and every
	# soldier stands somewhere the server did not put him.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var def := _roster_def()
	var id := sim.add_squad(def, 1, Vector2i(2, 2))

	var state := ClientState.new()
	_connect(sim, state, 1)
	# Curves too: soldier positions are derived from one, so without this
	# the comparison below would pass by both sides deriving nothing.
	_pump(sim, state, 1, 2)

	var ordered := "ring" if def.formation_shape != "ring" else "tight"
	sim.set_shape(id, ordered)
	# Exactly what server.gd sends for a shape change: an ordinary
	# SQUAD_INFO for the squads take_shape_dirty() reports.
	state.handle_packet(NetProtocol.encode_squad_info(
		sim.squad_info_entries(sim.take_shape_dirty())))

	assert_eq(state.shape_of(id), ordered,
		"The client should be deriving from the shape the server put the squad in")

	# And the point of the shape: where the soldiers actually stand.
	var server_side := sim.soldier_transforms(id)
	var client_side := state.soldier_transforms(id, sim.time)
	assert_eq(client_side.size(), server_side.size(),
		"Client and server disagree about how many soldiers this squad has")
	for i in range(server_side.size()):
		assert_almost_eq(client_side[i].origin.x, server_side[i].origin.x, 0.001,
			"Soldier %d x diverges after a formation change" % i)
		assert_almost_eq(client_side[i].origin.z, server_side[i].origin.z, 0.001,
			"Soldier %d z diverges after a formation change" % i)


func test_a_formation_change_does_not_desync_a_client_that_was_told() -> void:
	# Shape is hashed, so a client that never learns the new one is not
	# merely drawing the wrong picture — it reports a desync on a perfectly
	# healthy system, which is the failure mode D-026 criterion 8 warns
	# about. Gatherers switch shape by themselves (D-058), so this would
	# have fired for every crew that ever worked a node.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var def := _roster_def()
	var id := sim.add_squad(def, 1, Vector2i(3, 3))

	var state := ClientState.new()
	_connect(sim, state, 1)

	sim.set_shape(id, "ring" if def.formation_shape != "ring" else "tight")
	state.handle_packet(NetProtocol.encode_squad_info(
		sim.squad_info_entries(sim.take_shape_dirty())))
	state.handle_packet(NetProtocol.encode_state_hash(
		sim.tick_count, sim.composition_hash(sim.visible_to(1))))

	assert_eq(state.state_hash_checks, 1,
		"The client must actually have been checked")
	assert_eq(state.desync_count, 0,
		"A client that was told about the shape change must agree with the server")


func test_squad_with_no_composition_derives_nothing_rather_than_guessing() -> void:
	# A plausible-looking wrong answer is worse than none: guessing puts
	# every soldier somewhere the server did not.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var id := sim.add_squad(_roster_def(), 1, Vector2i(6, 6))

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [id]))
	# Curves, but no SQUAD_INFO.
	for packet in sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1)):
		state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))

	assert_eq(state.soldier_transforms(id, sim.time).size(), 0,
		"Without composition the client must derive nothing at all")
	assert_eq(state.squads_awaiting_composition(), 1,
		"...and must be able to report that it is missing")


func test_client_never_receives_soldier_positions() -> void:
	# Structural: everything a client holds is a squad curve. The soldier
	# count it can draw is derived, and bears no relation to bytes on the
	# wire — which is the entire 40x saving in D-006.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var def := _roster_def()
	var ids := []
	for i in range(10):
		ids.append(sim.add_squad(def, 1, Vector2i(i * 2, 3)))
	for id in ids:
		sim.order_move(id, Vector2i(20, 12))

	var state := ClientState.new()
	_connect(sim, state, 1)

	var ticks := 20
	var bytes := _pump(sim, state, 1, ticks)

	var soldiers := state.derive_all(sim.time)
	assert_eq(soldiers, 10 * def.squad_size,
		"10 squads should derive 10x the roster def's squad size")

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


# --- composition and desync detection ---------------------------------

func test_squad_info_roundtrips() -> void:
	var entries := [
		{"id": 4, "def_id": "test_alpha", "alive": 40, "shape": "ring"},
		{"id": 9, "def_id": "test_beta", "alive": 32, "shape": "tight"},
	]
	var decoded := NetProtocol.decode_squad_info(NetProtocol.encode_squad_info(entries))
	assert_eq(decoded.size(), 2)
	assert_eq(int(decoded[0]["id"]), 4)
	assert_eq(String(decoded[0]["def_id"]), "test_alpha")
	assert_eq(int(decoded[0]["alive"]), 40)
	# Shape is mutable squad state (D-058), so it travels rather than being
	# resolved from the UnitDef — that is the whole difference between a
	# formation a player can change and one baked in at spawn.
	assert_eq(String(decoded[0]["shape"]), "ring")
	assert_eq(String(decoded[1]["def_id"]), "test_beta")
	assert_eq(int(decoded[1]["alive"]), 32)
	assert_eq(String(decoded[1]["shape"]), "tight")


func test_state_hash_roundtrips() -> void:
	var decoded := NetProtocol.decode_state_hash(NetProtocol.encode_state_hash(77, 123456))
	assert_eq(int(decoded["tick"]), 77)
	assert_eq(int(decoded["hash"]), 123456)


func test_composition_hash_ignores_entry_order() -> void:
	# Server and client build their entry lists by iterating different
	# containers, so the hash must not depend on iteration order.
	var a := [{"id": 1, "alive": 10, "shape": "line", "spacing": 1.0},
		{"id": 2, "alive": 20, "shape": "wedge", "spacing": 1.5}]
	var b := [{"id": 2, "alive": 20, "shape": "wedge", "spacing": 1.5},
		{"id": 1, "alive": 10, "shape": "line", "spacing": 1.0}]
	assert_eq(NetProtocol.composition_hash(a), NetProtocol.composition_hash(b))


func test_composition_hash_changes_with_every_field() -> void:
	# A hash that ignored a field would let that field drift undetected.
	var base := [{"id": 1, "alive": 10, "shape": "line", "spacing": 1.0}]
	var baseline := NetProtocol.composition_hash(base)
	assert_ne(baseline, NetProtocol.composition_hash(
		[{"id": 2, "alive": 10, "shape": "line", "spacing": 1.0}]), "id must matter")
	assert_ne(baseline, NetProtocol.composition_hash(
		[{"id": 1, "alive": 11, "shape": "line", "spacing": 1.0}]), "alive must matter")
	assert_ne(baseline, NetProtocol.composition_hash(
		[{"id": 1, "alive": 10, "shape": "sparse", "spacing": 1.0}]), "shape must matter")
	assert_ne(baseline, NetProtocol.composition_hash(
		[{"id": 1, "alive": 10, "shape": "line", "spacing": 1.4}]), "spacing must matter")


func test_matching_client_reports_no_desync() -> void:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	for i in range(5):
		sim.add_squad(_roster_def(), 1, Vector2i(i * 3, 4))

	var state := ClientState.new()
	_connect(sim, state, 1)
	_pump(sim, state, 1, 30)

	assert_gt(state.state_hash_checks, 0,
		"The client must actually have been checked — a check that never runs is not a check")
	assert_eq(state.desync_count, 0, "A correctly-informed client should never desync")


func test_desync_check_catches_a_client_that_assumed_the_wrong_squad_size() -> void:
	# THE regression test. This reproduces the exact bug that shipped:
	# the server spawns the roster's default unit, the client assumes a
	# nominal 40-strong "line" squad, and because Formation.slot_offset
	# takes `alive` as an input, every soldier ends up somewhere the
	# server did not put it.
	#
	# This is what a working desync check would have caught on the first
	# load test. The check that existed grepped logs for a word no code
	# ever printed, so it caught nothing, for many green runs.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var def := _roster_def()
	var id := sim.add_squad(def, 1, Vector2i(3, 3))

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [id]))

	# Hand-inject the old assumption instead of the server's truth.
	state.composition[id] = {
		"def_id": String(def.id), "alive": 40, "shape": "line", "spacing": 1.0,
	}
	assert_ne(def.squad_size, 40,
		"This test is only meaningful while the roster default is not 40 strong")

	state.handle_packet(NetProtocol.encode_state_hash(
		sim.tick_count, sim.composition_hash(sim.visible_to(1))))

	assert_eq(state.state_hash_checks, 1)
	assert_eq(state.desync_count, 1,
		"A client deriving from the wrong squad size must be detected")
	assert_string_contains(state.last_desync, "composition hash")


func test_desync_check_catches_a_wrong_formation_shape() -> void:
	# The bots' other assumption: hardcoded "line" regardless of the def.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var def := _roster_def()
	var id := sim.add_squad(def, 1, Vector2i(3, 3))

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [id]))
	state.composition[id] = {
		"def_id": String(def.id),
		"alive": def.squad_size,
		"shape": "line" if def.formation_shape != "line" else "column",
		"spacing": def.formation_spacing,
	}

	state.handle_packet(NetProtocol.encode_state_hash(
		sim.tick_count, sim.composition_hash(sim.visible_to(1))))
	assert_eq(state.desync_count, 1, "A wrong formation shape must be detected")


# --- surfacing a desync where a human can see it ----------------------
#
# The counters above were counted correctly and then read by nobody
# outside `client.gd`'s VERDICT line — and that line lives in the
# screenshot path, which ends in `get_tree().quit()`. An interactive
# session never reaches it, so the GUI client printed exactly the same
# thing (nothing) through zero desyncs and through a thousand, while
# playtest issues instructed testers to judge "zero desyncs across the
# session" by watching that console.
#
# That is D-022's audit finding again: a check whose only outcome is
# silence cannot fail. These tests exist so the surfacing path is one
# that can be exercised headless, rather than one only a human at a
# keyboard could ever notice missing.


## The wrong-squad-size assumption the regression test above reproduces,
## which is simply the cheapest genuine desync to manufacture.
func _client_that_will_desync(sim: SquadSim) -> ClientState:
	var def := _roster_def()
	var id := sim.add_squad(def, 1, Vector2i(3, 3))
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, [id]))
	state.composition[id] = {
		"def_id": String(def.id), "alive": 40, "shape": "line", "spacing": 1.0,
	}
	return state


func _send_state_hash(sim: SquadSim, state: ClientState) -> void:
	state.handle_packet(NetProtocol.encode_state_hash(
		sim.tick_count, sim.composition_hash(sim.visible_to(1))))


func test_a_desync_queues_a_report_for_a_client_to_print() -> void:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var state := _client_that_will_desync(sim)
	_send_state_hash(sim, state)

	var reports := state.take_desync_reports()
	assert_eq(reports.size(), 1,
		"A detected desync must leave something for the client to say out loud")
	assert_string_contains(String(reports[0]), "DESYNC")
	assert_string_contains(String(reports[0]), "composition hash")

	assert_eq(state.take_desync_reports(), [],
		"Draining hands the reports over — a drained report must not print again next frame")


func test_a_building_desync_queues_a_report_too() -> void:
	# Counted since D-030 and, until now, read by nothing anywhere: the
	# bots gate on it, the GUI client did not even print it.
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_building_state_hash(12, 987654321))

	assert_eq(state.building_desync_count, 1)
	var reports := state.take_desync_reports()
	assert_eq(reports.size(), 1, "A building desync must surface like a squad one")
	assert_string_contains(String(reports[0]), "building hash")


func test_a_healthy_client_queues_nothing_to_report() -> void:
	# The other half of the property, and the more important one: a
	# diagnostic that cries wolf on a working system gets muted, which is
	# how the original "0 desyncs" log scan was lost.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	for i in range(5):
		sim.add_squad(_roster_def(), 1, Vector2i(i * 3, 4))

	var state := ClientState.new()
	_connect(sim, state, 1)
	_pump(sim, state, 1, 30)

	assert_gt(state.state_hash_checks, 0, "The checks must actually have run")
	assert_eq(state.take_desync_reports(), [],
		"A correctly-informed client must print nothing at all")


func test_desync_reports_are_capped_but_the_counter_is_not() -> void:
	# A client desyncing on every state-hash message would otherwise print
	# ~10 lines a second for the rest of the match, and would grow an
	# unbounded array in a headless consumer that never drains.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	var state := _client_that_will_desync(sim)
	for _i in range(20):
		_send_state_hash(sim, state)

	var reports := state.take_desync_reports()
	assert_eq(reports.size(), ClientState.DESYNC_REPORT_LIMIT + 1,
		"The cap is the limit plus the one line that says the cap was hit")
	assert_string_contains(String(reports[-1]), "capped",
		"A console that goes quiet must say why, or the silence reads as the desyncs stopping")
	assert_eq(state.desync_count, 20,
		"The counter is the source of truth and must keep counting past the report cap")


func test_desync_summary_says_what_was_checked_not_merely_that_nobody_complained() -> void:
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	for i in range(4):
		sim.add_squad(_roster_def(), 1, Vector2i(i * 3, 4))

	var state := ClientState.new()
	_connect(sim, state, 1)
	_pump(sim, state, 1, 12)

	var summary := state.desync_summary()
	assert_string_contains(summary, "0 desyncs",
		"The readout must state the result, not leave it to be inferred from silence")
	assert_string_contains(summary, str(state.state_hash_checks),
		"Zero desyncs in zero checks is not a pass — the summary must carry the check count")

	var broken := _client_that_will_desync(SquadSim.new(_space(), CurveReplicator.new()))
	broken.handle_packet(NetProtocol.encode_state_hash(3, 4242))
	assert_string_contains(broken.desync_summary(), "1 desync ")


## The structural half, in the shape of test_world_look_is_the_only_light:
## the rule is only real if breaking it fails.
##
## `client.gd` cannot be run headless (D-014), so this reads its source
## instead and asks the one question the defect turned on — is any read of
## the desync counters reachable from an ordinary frame, or do they all
## live in `_finish_capture`, which quits the process?
func test_the_client_reads_the_desync_counters_outside_the_capture_path() -> void:
	var handle := FileAccess.open("res://client.gd", FileAccess.READ)
	assert_not_null(handle, "client.gd must be readable for this scan to mean anything")
	var text := handle.get_as_text()
	handle.close()

	var reader := RegEx.new()
	reader.compile("_state\\.(desync_count|building_desync_count|desync_summary|take_desync_reports)")

	var current := ""
	var readers: Array = []
	for raw_line in text.split("\n"):
		var line := String(raw_line)
		if line.begins_with("func "):
			current = line.substr(5).split("(")[0]
		# Comments talk about desyncs all over this file; only code counts.
		if line.strip_edges().begins_with("#"):
			continue
		if reader.search(line) != null and not readers.has(current):
			readers.append(current)

	assert_true(readers.has("_finish_capture"),
		"Scan is broken, not the code — the capture verdict has always read these")
	readers.erase("_finish_capture")
	assert_ne(readers, [],
		"Every read of the desync counters is inside _finish_capture, which ends in "
		+ "get_tree().quit() — so an interactive session can never see one")


func test_sim_and_client_agree_on_the_hash_for_the_same_state() -> void:
	# Both sides must compute the hash identically from their own storage.
	var sim := SquadSim.new(_space(), CurveReplicator.new())
	for i in range(4):
		sim.add_squad(_roster_def(), 1, Vector2i(i, i))

	var state := ClientState.new()
	_connect(sim, state, 1)

	assert_eq(state.composition_hash(), sim.composition_hash(sim.visible_to(1)),
		"Server and client must derive the same composition hash from the same facts")


# --- what the transport choice rests on (D-042) -----------------------

func test_curve_application_is_last_write_wins_so_order_is_load_bearing() -> void:
	# A curve packet carries no sequence number, and the client installs
	# whichever arrives most recently. That is fine — and only fine —
	# because the transport delivers reliably and IN ORDER.
	#
	# This test exists to make that dependency explicit rather than
	# implicit. "Unreliable with resend" is not a drop-in swap: without
	# ordering, two curves for the same squad can arrive reversed and the
	# client permanently installs the older one, with nothing to detect it
	# — curves are sent only on change (D-003), so there is no later
	# message to correct the mistake. Any move off ordered delivery needs
	# a version field on the curve first.
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var id := sim.add_squad(_roster_def(), 1, Vector2i(2, 2))

	var state := ClientState.new()
	_connect(sim, state, 1)

	sim.order_move(id, Vector2i(20, 10))
	sim.tick()
	var first := _curve_bytes_for(sim, 1, id)

	sim.order_move(id, Vector2i(4, 12))
	sim.tick()
	var second := _curve_bytes_for(sim, 1, id)

	assert_false(first.is_empty(), "The first order should have produced a curve")
	assert_false(second.is_empty(), "The second order should have produced a curve")
	assert_ne(first, second, "The two orders should produce different curves")

	# In order: the newer curve wins, which is correct.
	state.handle_packet(NetProtocol.encode_curve(first))
	state.handle_packet(NetProtocol.encode_curve(second))
	var in_order := state.squad_cell(id, sim.time + 1.0)

	# Reversed: the client installs the STALE curve and keeps it. Nothing
	# here is asserting that this is desirable — it is asserting that
	# ordering is what stands between the protocol and this outcome.
	var reversed := ClientState.new()
	_connect(sim, reversed, 1)
	reversed.handle_packet(NetProtocol.encode_curve(second))
	reversed.handle_packet(NetProtocol.encode_curve(first))
	var out_of_order := reversed.squad_cell(id, sim.time + 1.0)

	assert_ne(in_order, out_of_order,
		"Reordering two curves changed nothing, so either the test is not exercising the hazard or a sequence number was added — if the latter, D-042 can be revisited")


## The raw curve payload the replicator would send `player` for `squad`,
## or empty if it sent none this tick.
func _curve_bytes_for(sim: SquadSim, player: int, squad: int) -> PackedByteArray:
	for packet in sim.replicator.collect_for_client(player, sim.time, sim.visible_to(player)):
		if int(packet.get("id", -1)) == squad:
			return packet["bytes"]
	return PackedByteArray()
