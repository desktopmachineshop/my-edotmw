extends SceneTree

## Headless load-test bot (see justfile `run-bots` / `test-load`).
##
## Runs N virtual clients inside a single process rather than N
## processes, per the M0 planning session's memory-budget analysis: on
## the current dev hardware (16 GB RAM), N separate Godot headless
## processes is both slower to spin up and a much heavier footprint than
## N lightweight virtual-client objects sharing one process. Each virtual
## client owns its own ENet host, so the server sees N genuinely
## independent connections rather than one connection pretending to be N.
##
## Beyond "did it crash", these bots assert the thing M1 exists to prove:
## every client derives soldier positions from received squad curves
## (D-006) and never receives a soldier position over the wire.

const DEFAULT_SERVER_ADDRESS := "127.0.0.1"
const DEFAULT_SERVER_PORT := 4433
const CHANNELS := 2

const ORDER_INTERVAL_SECONDS := 3.0

## How many orders a bot spends marching one way before turning around.
## At ORDER_INTERVAL_SECONDS that is ~24 seconds per leg, which is about
## what crossing half a 128x64 map costs — long enough to actually arrive,
## fight, and then break contact again.
const ORDERS_PER_RAID_PHASE := 8
const CONNECT_TIMEOUT_SECONDS := 10.0

# How many of each bot's squads march on a neighbouring player's known
# spawn cell, and when they're called back home. Left as random
# single-squad orders (the pre-existing periodic behaviour below), two
# players' squads meeting inside a short DURATION is mostly luck —
# server.gd._spawn_squads_for deliberately spreads players across the
# whole torus (a real design property worth keeping for an actual match),
# and D-024/D-025's attack_range/vision_range are short relative to that
# spread. Leaving contact to chance would make the M2 verdict conditions
# below flaky rather than a real check — exactly the kind of check D-022's
# audit warns against trusting.
#
# So a handful of squads per player are sent somewhere they are near-
# certain to make contact: a neighbouring player's STARTING CELL, read
# from the spawn table the welcome message carries (D-036). Players form
# a ring, so every adjacent pair is approached from at least one side.
#
# This used to mirror server.gd's spawn arithmetic (5, 7, 2) to compute
# where a neighbour's squads sat — a documented duplication, with a note
# saying it would go stale loudly if the formula changed. D-039 changed
# it, and the note was half right: spawns are random now, so a formula
# cannot predict them at all. Reading the server's own table is not a
# tighter coupling than the constants were, it is a looser one — the
# server is already telling every client this.
#
# It still only shapes a LOAD-TEST SCENARIO (which squads go where), not
# any correctness assertion; the vision field, combat resolution and
# casualties that follow are the real system responding to a real order.
#
# The remaining squads per player never move on this schedule, which is
# what keeps D-026 criterion 6's "even the most-informed bot knows fewer
# squads than the server simulates" true even while this is happening —
# see _max_known_squads() below.
const SCOUT_SQUADS_PER_BOT := 3
const RALLY_AT_SECONDS := 0.0
const RECALL_AT_SECONDS := 8.0

class VirtualClient:
	var index: int
	var server_address: String
	var server_port: int
	# Total bots in this run. Player ids are assigned 1..player_count in
	# join order (server.gd's `_next_player`), so with every bot connecting
	# this is also the count of players that will exist — needed to pick a
	# cyclic "next player" neighbour to rally toward (see _issue_rally_order).
	var player_count: int

	var host: ENetConnection
	var peer: ENetPacketPeer
	var connected := false
	# Tracked separately from `connected`, because they answer different
	# questions. At the end of a load test the server is torn down first,
	# so every bot is legitimately disconnected — reporting that as "0
	# connected, something is wrong" is how this originally produced a
	# false failure after a completely successful run.
	var ever_connected := false
	var failed := false

	# The SAME client implementation the GUI client uses, deliberately —
	# a load test against a simplified stand-in could pass while the real
	# client is broken.
	var state := ClientState.new()
	var soldiers_derived := 0

	var _next_order_at := 1.0
	var _orders_issued := 0

	## Whether this bot's opening town hall order has actually gone out.
	## Distinct from `_orders_issued == 0` on purpose — see where it is set.
	var _town_hall_ordered := false

	## The squad sent to found the town hall, or -1 before that has
	## happened. Read by `_issue_order` to keep the raid-order pool from
	## ever picking this squad while it is still walking to build.
	var _founding_squad := -1

	## How many times _issue_order has run, whether or not this bot had a
	## squad to order. Production is paced off this so it keeps running
	## while the bot owns nothing — which is precisely when it must.
	var _order_ticks := 0
	var _rng := RandomNumberGenerator.new()

	# Rally/recall scripting (see the constants above) — a bounded, one-shot
	# sequence layered on top of the existing periodic random order, not a
	# replacement for it.
	var _scout_squads: Array = []
	var _home_cell: Dictionary = {}  # squad id -> Vector2i, sampled before rallying
	var _rallied := false
	var _recalled := false

	func _init(p_index: int, p_address: String, p_port: int, p_player_count: int) -> void:
		index = p_index
		server_address = p_address
		server_port = p_port
		player_count = p_player_count
		# Seeded per client so a load test is reproducible — which matters
		# because replays (D-016) are the tool for diagnosing whatever a
		# load test turns up.
		_rng.seed = 0x5EED + p_index

	func start() -> Error:
		host = ENetConnection.new()
		var err := host.create_host(1, CHANNELS)
		if err != OK:
			failed = true
			return err
		peer = host.connect_to_host(server_address, server_port, CHANNELS)
		if peer == null:
			failed = true
			return FAILED
		return OK

	func poll(now: float) -> void:
		if host == null or failed:
			return

		while true:
			var event := host.service(0)
			var type: int = event[0]
			if type == ENetConnection.EVENT_NONE:
				break
			match type:
				ENetConnection.EVENT_CONNECT:
					connected = true
					ever_connected = true
				ENetConnection.EVENT_DISCONNECT:
					connected = false
				ENetConnection.EVENT_RECEIVE:
					_drain(event[1])

		if connected and not _rallied and not state.squads.is_empty() and now >= RALLY_AT_SECONDS:
			_issue_rally_order(now)
			_rallied = true

		if _rallied and not _recalled and now >= RECALL_AT_SECONDS:
			_issue_recall_order()
			_recalled = true

		if connected and now >= _next_order_at:
			_issue_order()
			_next_order_at = now + ORDER_INTERVAL_SECONDS

	func _drain(from_peer: ENetPacketPeer) -> void:
		while from_peer.get_available_packet_count() > 0:
			state.handle_packet(from_peer.get_packet())

	## Derive soldier positions from held curves — the client-side half of
	## D-006. Nothing here came off the wire; it is all recomputed.
	##
	## Composition now comes from the server rather than being assumed. It
	## used to pass a nominal 40 soldiers in "line" at 1.0 spacing, while
	## the server was actually spawning 32-strong archers in "loose" — so
	## every derived soldier sat somewhere the server did not put it.
	func derive_soldiers(now: float) -> int:
		soldiers_derived = state.derive_all(now)
		return soldiers_derived

	func curve_packets_received() -> int:
		return state.curve_packets_received

	## Where player `target_player` starts.
	##
	## Read from the welcome message's spawn table, not reconstructed. It
	## used to mirror server.gd's `_spawn_squads_for` arithmetic here — a
	## deliberate duplication, with a comment saying so — and D-039 made
	## that arithmetic obsolete: spawns are scattered at random now, so a
	## formula cannot predict them and a bot marching on the answer it
	## computed would walk to empty ground.
	##
	## The server has sent every spawn point since D-036 precisely so no
	## client has to guess. A guess that was merely fragile before is
	## simply wrong now.
	func _spawn_cell_of(target_player: int) -> Vector2i:
		return state.spawn_cell_of(target_player)

	## Send a handful of this bot's squads to march directly on a
	## neighbouring player's known (stationary) squad, guaranteeing contact
	## well inside the run's time budget instead of hoping a random
	## destination happens to cross paths — see the header comment on the
	## constants above for why this is a deliberate scenario choice, not a
	## fabricated result. Players form a ring (1 -> 2 -> ... -> N -> 1) so
	## every adjacent pair gets approached from at least one side. Records
	## each scout's pre-rally cell first, so _issue_recall_order() can send
	## it home rather than to a fresh random spot.
	func _issue_rally_order(now: float) -> void:
		if state.space == null or state.squads.is_empty() or player_count <= 0:
			return
		var count := mini(SCOUT_SQUADS_PER_BOT, state.squads.size())
		_scout_squads = []
		for i in range(count):
			_scout_squads.append(state.squads[i])

		var neighbour_player := (state.player % player_count) + 1
		var rally_cell := _spawn_cell_of(neighbour_player)
		if rally_cell.x < 0:
			return
		for squad in _scout_squads:
			_home_cell[squad] = state.squad_cell(squad, now)
			var order := state.encode_order(squad, rally_cell)
			if not order.is_empty():
				peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)

	## Call the scouts back home. A squad that routed during the rally
	## ignores this (SquadSim.order_move refuses PLAYER orders while
	## routed, D-024) and keeps fleeing under its own steam instead — which
	## is also a legitimate way to leave vision and produce a conceal, so
	## this is additive to that path, not a replacement for it.
	func _issue_recall_order() -> void:
		if state.space == null:
			return
		for squad in _scout_squads:
			if not _home_cell.has(squad):
				continue
			var order := state.encode_order(squad, _home_cell[squad])
			if not order.is_empty():
				peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)

	## Train at every finished building this bot owns.
	##
	## Spends the starting stockpile on gatherers — the economic opening a
	## real player makes, and what puts the production path (cost, squad
	## cap, queue, spawn) under the load test rather than leaving it to
	## unit tests.
	##
	## Every other order, not every fourth. Squad count is the axis
	## D-018's budget is stated in, and the load test could not reach a
	## count comparable to M2's 48-squad measurement while bots recruited
	## more slowly than this — leaving D-027 criterion 17 measurable but
	## not COMPARABLE.
	## Paced by `_order_ticks`, NOT `_orders_issued`. The latter only
	## advances on the squad path below, so a bot with no squads would
	## freeze it — and gating production on a counter that stops moving
	## exactly when a bot has nothing to move is the same deadlock this
	## function was just lifted out of, one level down.
	func _issue_production() -> void:
		if _order_ticks % 2 != 0:
			return
		for wire_id in state.buildings:
			var info: Dictionary = state.buildings[wire_id]
			if int(info["owner"]) != state.player or bool(info["destroyed"]):
				continue
			if float(info["progress"]) < 1.0:
				continue
			peer.send(0, NetProtocol.encode_order_produce(int(wire_id), "gatherers"),
				ENetPacketPeer.FLAG_RELIABLE)
			break


	func _issue_order() -> void:
		if state.space == null:
			return
		_order_ticks += 1

		# Training needs a BUILDING, not a squad, so it runs before the
		# "no squads" guard below.
		#
		# It used to sit after that guard, which was harmless while a bot
		# always owned something, and became a deadlock the moment the
		# founding party started being consumed at order time (D-031): a
		# bot with a finished town hall and no squads stopped issuing
		# every kind of order — including the one order that would have
		# given it squads again. Twenty players each built a hall and
		# then trained nothing for two minutes.
		#
		# What hid it for a while was the client keeping dead squads in
		# its owned list, so this guard stayed false and production kept
		# running past a squad that no longer existed. Two bugs whose
		# symptoms cancelled; fixing the honest one exposed this.
		_issue_production()

		if state.squads.is_empty():
			return

		# Never pick the squad that is still walking to found its town
		# hall as the target of the RAID order below. server.gd's
		# `_handle_order_move` cancels a pending build the instant its
		# squad is ordered anywhere else ("A builder told to go somewhere
		# has been told to stop building") — and with a single founding
		# party, the raid order a few lines down was picking that exact
		# squad and cancelling the build this same function had just
		# issued, every 3 seconds, for the rest of the match. No refusal
		# ever reached the wire, because nothing was refused: both orders
		# were individually valid, and the second one is just what "stop
		# building" means. The founding party never built anything and the
		# load test failed with `buildings_known=0`, which reads exactly
		# like a replication bug and is not one.
		# `state.squads` is a PackedInt32Array, which has no `.filter()` —
		# only the generic Array does — so this is a plain loop rather
		# than the one-liner it looks like it should be.
		var founding_pending := _founding_squad in state.squads
		var raid_pool: Array = []
		for candidate in state.squads:
			if not founding_pending or candidate != _founding_squad:
				raid_pool.append(candidate)
		if raid_pool.is_empty():
			# The founder is the only squad there is. Leave it be — any
			# raid order right now has nothing to send but the squad that
			# must not receive one.
			return
		var squad: int = raid_pool[_rng.randi_range(0, raid_pool.size() - 1)]

		# Converge on the middle of the map rather than wandering anywhere
		# on it. Destinations used to be uniform over the whole torus,
		# which produced contact reliably on a 64x32 map and stopped
		# producing it at all when M3 grew the map 4x (D-036): four armies
		# spread over 8,192 cells simply never met, and the verdict
		# correctly reported casualties=0, conceals=0, reveals=0.
		#
		# That was the check working — but a load test that only exercises
		# combat and fog by luck is not one to depend on. Symmetric spawns
		# are always a full quadrant apart, so the middle is the one place
		# every player can reach, and heading there makes the engagement
		# deliberate. The jitter keeps squads from stacking on one cell.
		# Alternate between the contested middle and home, rather than
		# marching to the centre and sitting there.
		#
		# Sitting was enough to produce fog churn when a player started
		# with twelve spread-out squads. It stopped being enough when the
		# opening became a single founding party (D-031): four squads all
		# parked in the middle can see each other permanently, so nothing
		# was ever concealed and the verdict correctly reported
		# conceal_events=0. Raiding in and back out is both more like real
		# play and what makes vision genuinely gain and lose contact.
		# First order of the match: found a town hall where we stand
		# (D-031). A player starts with founders and nothing else, so this
		# is the opening move a real player makes — and it means the load
		# test exercises construction, building replication and the
		# persistent-explored hash in the running system rather than
		# leaving all three to unit tests.
		# Retried until it is actually SENT, not attempted once on the first
		# order. `spawn_cell_of` needs the WELCOME, and a bot whose first
		# order tick beat that packet skipped its opening move silently and
		# never tried again — no town hall, so no production, so four
		# founding parties wandering an empty map for the whole run. The
		# verdict then failed with `buildings_known=0`, which reads exactly
		# like a replication bug and is not one.
		#
		# It survived because the guard was `_orders_issued == 0` while the
		# counter below increments unconditionally, so "did I send it" and
		# "is this my first order" were quietly the same question. They stop
		# being the same the moment the send does not happen.
		if not _town_hall_ordered:
			var home := state.spawn_cell_of(state.player)
			if home.x >= 0:
				var build := state.encode_build(squad, "town_centre", home)
				if not build.is_empty():
					peer.send(0, build, ENetPacketPeer.FLAG_RELIABLE)
					_town_hall_ordered = true
					_founding_squad = squad
					# Stop here — no raid order for this squad on the same
					# tick its build order was sent. See the note above
					# `raid_pool` for what happens if a move order follows.
					return

		# Flip phase every ORDERS_PER_RAID_PHASE orders, not every order.
		# Orders go out every 3 seconds while the contested middle is a
		# good 25 seconds of marching away, so alternating per order made
		# the bots thrash on the spot and never arrive anywhere — fog
		# churned nicely and casualties_applied sat at zero.
		var spread := 8
		var target: Vector2i
		if (_orders_issued / ORDERS_PER_RAID_PHASE) % 2 == 0:
			target = Vector2i(state.space.width / 2, state.space.height / 2)
		else:
			# Spawn points come from the welcome message, so this is where
			# the bot actually started rather than a guess (D-036).
			var home := state.spawn_cell_of(state.player)
			target = home if home.x >= 0 else Vector2i(0, 0)
		_orders_issued += 1

		var destination := Vector2i(
			target.x + _rng.randi_range(-spread, spread),
			target.y + _rng.randi_range(-spread, spread))

		var order := state.encode_order(squad, destination)
		if not order.is_empty():
			peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)

	## Idempotent. Teardown runs twice — once when _process decides the run
	## is over, and again from _finalize as the SceneTree exits — so this
	## must tolerate being called on an already-stopped client. Destroying
	## the host invalidates `peer` without setting the reference to null,
	## so a second pass would call peer_disconnect_now on a dead peer and
	## log an error for a completely successful run.
	func stop() -> void:
		if host == null:
			return
		if peer != null and connected:
			peer.peer_disconnect_now(0)
		peer = null
		connected = false
		host.destroy()
		host = null


var _clients: Array[VirtualClient] = []
var _elapsed := 0.0
var _duration := -1.0
var _reported := false
var _finished := false


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())

	var client_count: int = int(args.get("clients", 1))
	# Inside the compose network the server is a hostname, not localhost,
	# so the address is overridable by env as well as by flag.
	var default_address := OS.get_environment("EDOTMW_SERVER_ADDRESS")
	if default_address == "":
		default_address = DEFAULT_SERVER_ADDRESS
	var address: String = String(args.get("address", default_address))
	var port: int = int(args.get("port", DEFAULT_SERVER_PORT))
	_duration = float(args.get("duration", -1.0))

	print("bot_client.gd: spawning %d virtual client(s) against %s:%d" % [client_count, address, port])

	for i in range(client_count):
		var vc := VirtualClient.new(i, address, port, client_count)
		var err := vc.start()
		if err != OK:
			push_error("bot %d: could not start ENet host (error %d)" % [i, err])
		_clients.append(vc)


func _process(delta: float) -> bool:
	_elapsed += delta

	for vc in _clients:
		vc.poll(_elapsed)

	# Exercise the derived-position path on every client, every frame —
	# this is the cost a real client pays, so a load test that skipped it
	# would be measuring the wrong thing.
	for vc in _clients:
		vc.derive_soldiers(_elapsed)

	# Only a bot that NEVER connected indicates a problem. Losing the
	# connection later is normal — the load test tears the server down
	# first.
	if not _ever_connected_any() and _elapsed > CONNECT_TIMEOUT_SECONDS:
		push_error("bot_client.gd: no client connected within %.0fs — is the server up?" % CONNECT_TIMEOUT_SECONDS)
		_finish()
		return true

	if _duration > 0.0 and _elapsed >= _duration:
		_finish()
		return true

	return false


func _finalize() -> void:
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_report()
	for vc in _clients:
		vc.stop()
	# Exit code is the machine-readable half of the verdict, so
	# `just test-load` can fail on it instead of trying to infer success
	# by grepping prose.
	quit(0 if _verdict_ok() else 1)


func _ever_connected_count() -> int:
	var n := 0
	for vc in _clients:
		if vc.ever_connected:
			n += 1
	return n


func _ever_connected_any() -> bool:
	return _ever_connected_count() > 0


func _packets_received() -> int:
	var n := 0
	for vc in _clients:
		n += vc.curve_packets_received()
	return n


func _desync_count() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.desync_count
	return n


func _state_hash_checks() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.state_hash_checks
	return n


func _squads_awaiting_composition() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.squads_awaiting_composition()
	return n


## Total soldiers subtracted from any squad's `alive` across every bot
## (D-026 criteria 3/9). Zero here means the run never observed a single
## casualty — which proves nothing about combat, however clean everything
## else looks (see the header comment on _verdict_ok()).
func _casualties_applied() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.casualties_applied
	return n


func _conceal_events() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.conceal_events
	return n


func _buildings_known() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.buildings.size()
	return n


func _building_desyncs() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.building_desync_count
	return n


func _reveal_events() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.reveal_events
	return n


func _ghosts_peak() -> int:
	var n := 0
	for vc in _clients:
		n += vc.state.ghosts_peak
	return n


## The single MOST-INFORMED bot's known-squad count — deliberately NOT a
## union/sum across every bot. Every squad in this game belongs to exactly
## one connected player, and an owner always sees its own squads regardless
## of vision (SquadSim.visible_to's owner check) — so a union across ALL
## bots is mathematically guaranteed to equal the server's total every
## single run, fog or no fog, since between them the bots own the whole
## roster. That would make the D-026 criterion 6 comparison vacuous in
## exactly the shape D-022's audit warns about: a check that cannot fail.
##
## What fog actually claims is per-client: no ONE client knows the whole
## board. So this reports the bot that knows the MOST (own squads plus
## whatever enemies it has ever had revealed to it, including stale
## ghosts, via `curves.size()` — a curve is never removed once received),
## and the comparison this feeds is "even that bot knows less than the
## server simulates". A regression that made visible_to() return every
## squad (M1's own stub bug, D-022's "known stub" note) would push this to
## equal the total — which is exactly the case the comparison exists to
## catch, and exactly what was used to perturb-test it (see the report).
func _max_known_squads() -> int:
	var most := 0
	for vc in _clients:
		most = maxi(most, vc.state.curves.size())
	return most


## A run is only a success if every bot connected, state actually
## replicated, the client's view was *checked* against the server's, and
## that check passed.
##
## The `state_hash_checks > 0` condition is the important one and is there
## deliberately. The previous version of this suite grepped logs for the
## word "desync" that no code path ever emitted — a check that cannot fail
## is indistinguishable from a check that passes, and it hid a real bug
## (client and server deriving different soldier positions) through many
## green runs. Requiring that verification demonstrably HAPPENED, not just
## that it didn't complain, is what stops that recurring.
##
## M2 extends the same principle (D-026 criterion 9): a run in which nobody
## ever died proves nothing about combat, and a run in which nothing was
## ever hidden or re-shown proves nothing about fog — however clean the
## rest of the verdict looks. So on top of the M1 conditions, this now also
## requires at least one casualty, at least one conceal, AND at least one
## reveal to have actually happened.
func _verdict_ok() -> bool:
	if _clients.is_empty():
		return false
	if _ever_connected_count() != _clients.size():
		return false
	if _packets_received() <= 0:
		return false
	if _state_hash_checks() <= 0:
		return false
	if _desync_count() != 0:
		return false
	if _casualties_applied() <= 0:
		return false
	if _conceal_events() <= 0:
		return false
	if _reveal_events() <= 0:
		return false
	# Slice 4's live proof: a town hall was founded and reached clients,
	# and the persistent-explored hash agreed about it throughout. A run
	# where nobody built anything proves nothing about buildings, exactly
	# as a run where nobody died proves nothing about combat.
	if _buildings_known() <= 0:
		return false
	if _building_desyncs() != 0:
		return false
	return true


func _report() -> void:
	if _reported:
		return
	_reported = true

	var soldiers := 0
	var curves := 0
	for vc in _clients:
		soldiers += vc.soldiers_derived
		curves += vc.state.curves.size()

	# Trailing key=value tokens (rather than folding these into the prose
	# above) so `just test-load` can grep each one precisely — same
	# "structured markers, not scary words" rule the log scan already
	# follows. known_squads_max is the single most-informed bot's count,
	# for D-026 criterion 6's load half; the recipe compares it against the
	# server log's FOG_TOTAL_SQUADS (see _max_known_squads()'s comment for
	# why this must be a max, not a sum/union across bots).
	print("bot_client.gd: MEMORY — %.1f MB for %d virtual clients, %d soldiers derived" % [float(OS.get_static_memory_usage()) / 1048576.0, _clients.size(), soldiers])

	# D-006's OTHER half. The decision trades bandwidth for client CPU, and
	# only the bandwidth side had ever been measured. This is what a client
	# pays per frame for every soldier it was never sent.
	var derive_usec := 0
	var derived_total := 0
	var worst_derive := 0
	for vc in _clients:
		derive_usec += vc.state.total_derive_usec
		derived_total += vc.state.soldiers_derived_total
		worst_derive = maxi(worst_derive, vc.state.last_derive_usec)
	var per_soldier := 0.0
	if derived_total > 0:
		per_soldier = float(derive_usec) / float(derived_total)
	print("bot_client.gd: DERIVE — %.3f us/soldier over %d soldier-derivations, worst single pass %.2f ms" % [
		per_soldier, derived_total, float(worst_derive) / 1000.0])
	print("bot_client.gd: VERDICT %s — %d/%d bots connected, %d curve packets received, %d squad curves held, %d soldiers derived client-side, %d state-hash checks, %d desyncs, casualties_applied=%d conceal_events=%d reveal_events=%d ghosts_peak=%d known_squads_max=%d buildings_known=%d building_desyncs=%d nodes_known_max=%d" % [
		"ok" if _verdict_ok() else "failed",
		_ever_connected_count(), _clients.size(),
		_packets_received(), curves, soldiers,
		_state_hash_checks(), _desync_count(),
		_casualties_applied(), _conceal_events(), _reveal_events(), _ghosts_peak(),
		_max_known_squads(), _buildings_known(), _building_desyncs(), _max_known_nodes()])

	# Printed only on failure, and containing the word the log scan looks
	# for — which now actually appears when something is wrong.
	if _desync_count() > 0:
		for vc in _clients:
			if vc.state.desync_count > 0:
				push_error("bot %d: desync — %s" % [vc.index, vc.state.last_desync])

	var awaiting := _squads_awaiting_composition()
	if awaiting > 0:
		push_error("bot_client.gd: %d squad(s) had a curve but no composition — the server replicated something it never described" % awaiting)


## Minimal `--key=value` CLI parser for user args (after `--`).
## Example: godot --headless --script bot_client.gd -- --clients=20 --address=127.0.0.1 --port=4433
func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed


## The best-informed bot's resource-node count (D-061).
##
## A MAX rather than a union, for the same reason `_max_known_squads` is:
## the union across twenty bots would approach the whole map and say
## nothing about what any one player is allowed to know. What proves the
## gating is that the single most-informed client still knows fewer nodes
## than exist.
func _max_known_nodes() -> int:
	var best := 0
	for vc in _clients:
		best = maxi(best, vc.state.nodes.size())
	return best
