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
##
## Nothing reads this in a shipped run: the raid rotation it paces is
## unreachable while every squad a bot owns is a hauling crew — see
## `_issue_order`'s empty-pool branch.
const ORDERS_PER_RAID_PHASE := 8
const CONNECT_TIMEOUT_SECONDS := 10.0

## How far from its start a bot will look for somewhere its town hall is
## allowed to stand. `server.gd`'s BUILD_REACH_CELLS is 3 and a builder has
## to be within that of the site, so this is the whole of the ground a
## opening crew standing on its start can reach without walking first.
const BUILD_SITE_SEARCH_CELLS := 3

## How long a crew told to build is left alone before the bot considers
## asking again (#123). A barracks has to stand clear of the town hall's
## `no_build_radius`, so the crew WALKS there, and the building only exists
## once it arrives — re-ordering sooner hands it a new destination before it
## reaches the last one. Generous against ~10 cells at the shipped
## gatherer's 1.96 cells/s.
const BUILDER_COOLDOWN_SECONDS := 20.0

## How often a bot works its gate (#337). Slow on purpose: a gate change
## flushes the flow fields that cross it (D-076's own revisit trigger
## names exactly that interaction), so a bot hammering it would be
## measuring the flush rather than the wire.
const GATE_WORK_SECONDS := 12.0

# WHY a handful of each bot's squads march on a neighbouring player's
# start rather than wandering. Left as random
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
#
# How MANY squads scout, how close they come and when a leg is over all
# live in `bot_patrol.gd` now (D-20260817-load-test-bots-must-manoeuvre,
# #69/#84), because they are the part of this file worth testing without
# a server. What used to be here was a pair of absolute timestamps —
# rally at 0 s, recall at 8 s — that ran ONCE, in the window where D-031's
# opening leaves a bot holding nothing but the founding party it is about
# to spend on a town hall. The manoeuvre the fog gates depend on therefore
# never happened at all, on any run, and `reveal_events` was left to luck.

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
	var _refusal_reported := false

	# The SAME client implementation the GUI client uses, deliberately —
	# a load test against a simplified stand-in could pass while the real
	# client is broken.
	var state := ClientState.new()
	var soldiers_derived := 0

	var _next_order_at := 1.0
	var _orders_issued := 0

	## How many town hall sites this bot has asked for. NOT a latch saying
	## it has one — see `_owns_a_building`, which is what actually gates the
	## opening now.
	var _build_attempts := 0

	## The same, for everything raised after the town hall (#123), plus when
	## the crew doing it is next free to be told something else. Neither is
	## a latch either: `_raise_buildings` re-asks until the building is
	## actually THERE.
	var _site_attempts := 0
	var _builder_free_at := 0.0

	# The one gate this bot builds and works (#337). `gate_orders` is the
	# INTENT and `gate_toggles` the state changes actually asked for;
	# both are reported, because "never decided to" and "asked and was
	# refused" are different faults with the same symptom.
	var gate_orders := 0
	var gate_toggles := 0
	var _gate_next_at := 0.0
	var _gate_wanted_open := false

	## The crew currently walking to raise something, or -1.
	##
	## Held explicitly because the alternative did not work and failed in
	## the exact way this file has been bitten by twice already. The first
	## version ERASED the builder's gather assignment when it sent the build
	## order — reasoning that a crew told to build has stopped hauling
	## (D-034) — which left it UNASSIGNED, so `_put_gatherers_to_work` saw an
	## idle crew on its next pass and sent it to a tree, cancelling the build
	## it had been given three seconds earlier. Two filters disagreeing about
	## who owns a squad, which is the whole reason `BotPatrol.assign` exists.
	##
	## Measured: over a 600 s run three of four bots ordered a barracks
	## repeatedly and one ever finished one, at 586 s, with wood peaking at
	## 850. It was never affordability.
	var _builder_squad := -1

	## Why this bot has not raised its next building, in its own words.
	## Reported per bot, because "no wood", "no spare crew" and "nothing to
	## want" are three different faults with one symptom — no barracks — and
	## the per-bot line is what turned the town hall's silent refusal from a
	## four-run mystery into a one-run answer.
	var build_block := "not tried"

	## When this bot first owned a building it did not start with, and when
	## it first owned a squad the haul loop will not claim — seconds into the
	## run, or -1 for never. The load test's duration is bounded below by
	## these, so they are measured rather than guessed at (#123).
	var second_building_at := -1.0
	var first_soldier_at := -1.0
	var wood_peak := 0
	var military_peak := 0

	## The most squads this bot ever HELD, against the terminal count the
	## BOT line reports beside it.
	##
	## The two together are what separate "never produced a crew" from
	## "produced one and lost it" — a terminal `squads=1` is equally
	## consistent with both, and that ambiguity cost a diagnosis
	## (#350: three bots ending at one squad, with no way to tell from
	## the line whether they had ever had more). The server's periodic
	## status line carries a FLEET total that answers it in aggregate,
	## but a fleet total cannot see one bot losing while another gains.
	var squads_peak := 0

	## Raid orders actually issued. The verdict gates on this, because
	## `raid_pool` was empty on every tick of every match and everything
	## below it was unreachable — a load test cannot claim to have put two
	## armies in front of each other while reporting zero of these (#123).
	var raid_orders := 0

	## The renewable economy, as two numbers rather than one
	## (D-20260828-food-is-grown-not-only-found): the most FIELDS this bot
	## ever had standing, and the gather orders it issued AT one. Both are
	## METRICS, not gates — a farm needs an opening plus 80 wood, and the
	## shipped map already leaves two of four bots short of a barracks at
	## 420 s, so gating on either would fail honest runs (D-031's stale
	## timing trap, which this project has now re-set three times).
	##
	## Two, for the reason `military_peak` sits beside `raid_orders`:
	## "it never built a field" and "it built fields and never worked one"
	## are different faults with the same symptom, and only the pair can
	## tell them apart.
	var farms_peak := 0
	var field_orders := 0

	## The squad sent to found the town hall, or -1 before that has
	## happened. Read by `_issue_order` to keep the raid-order pool from
	## ever picking this squad while it is still walking to build.
	var _founding_squad := -1

	## How many times _issue_order has run, whether or not this bot had a
	## squad to order. Production is paced off this so it keeps running
	## while the bot owns nothing — which is precisely when it must.
	var _order_ticks := 0
	var _rng := RandomNumberGenerator.new()

	# The scouting patrol (BotPatrol) — a REPEATING out-and-back run for the
	# whole match, layered on top of the periodic order below rather than
	# replacing it.
	var _scouts: Array = []
	var _gather_assigned: Dictionary = {}  # gatherer squad id -> node cell index
	## Which leg the detachment is on: even legs watch the neighbour, odd
	## legs withdraw home.
	var _leg := 0
	## When the current leg's orders went out, or -1 before any have. NOT a
	## schedule — see bot_patrol.gd's header for why the cycle turns on
	## arrival rather than on a clock.
	var _leg_started_at := -1.0

	## The largest detachment this bot ever fielded. Reported, because a
	## patrol nobody could staff and a patrol that ran are indistinguishable
	## from `reveal_events` alone — and telling those two apart is the whole
	## of #69's investigation.
	var scouts_peak := 0

	## Legs COMPLETED, not legs ordered. `_leg` counts the boundaries the
	## detachment actually reached, so a run that reports zero of them is a
	## run in which the manoeuvre the fog gates depend on did not happen —
	## which is the state `main` was in, undetectably, for a day.
	func patrol_legs() -> int:
		return _leg

	## How many sites this bot asked for before one stuck. Reported beside
	## the building count, because "never asked" and "asked and was refused"
	## are different faults with the same symptom, and telling them apart is
	## what found the latch this replaces.
	func build_attempts() -> int:
		return _build_attempts

	## Whether the opening has actually HAPPENED — a building this bot owns
	## exists as far as it can tell. The server files a structure the moment
	## construction starts, so this goes true while the hall is still going
	## up, which is exactly when the bot should stop asking for another one.
	func _owns_a_building() -> bool:
		for wire_id in state.buildings:
			if int(state.buildings[wire_id]["owner"]) == state.player:
				return true
		return false

	## The protocol version this bot CLAIMS to speak (#179). Always the
	## real one in a load test; settable to something else by
	## `--protocol=N` so `just test-handshake` can drive a deliberately
	## wrong build at a real server over a real socket and watch it be
	## refused. That is the observed-to-fail rule made permanent: a
	## refusal path nobody ever takes is a refusal path that will be
	## broken the first time it matters.
	var protocol := NetProtocol.PROTOCOL_VERSION

	func _init(p_index: int, p_address: String, p_port: int, p_player_count: int,
			p_protocol: int = NetProtocol.PROTOCOL_VERSION) -> void:
		index = p_index
		server_address = p_address
		server_port = p_port
		player_count = p_player_count
		protocol = p_protocol
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
					# The version handshake (#179). The bots share
					# net_protocol.gd with both real binaries, which is
					# exactly why they must perform it rather than be
					# exempted: `test-load` is the only thing that
					# exercises the ACCEPT path against a real socket,
					# and an exemption would leave it unexercised while
					# looking green.
					peer.send(0, NetProtocol.encode_hello(
						protocol, BuildVersion.string()),
						ENetPacketPeer.FLAG_RELIABLE)
				ENetConnection.EVENT_DISCONNECT:
					connected = false
				ENetConnection.EVENT_RECEIVE:
					_drain(event[1])
					_report_refusal()

		# Before the order tick below, so the detachment is claimed on the
		# same pass a crew appears rather than one tick after the haul loop
		# has already sent it to a tree.
		if connected:
			_note_progress(now)
			_run_patrol(now)

		if connected and now >= _next_order_at:
			_issue_order(now)
			_next_order_at = now + ORDER_INTERVAL_SECONDS

	## Say it once, in the bot's own voice, if the server refused us
	## (#179). A bot that quietly failed to connect and a bot refused for
	## being the wrong build look identical from outside, and one of them
	## is a broken test estate — so the two must not be the same line in a
	## log.
	func _report_refusal() -> void:
		if _refusal_reported or state.refusal.is_empty():
			return
		_refusal_reported = true
		print("bot %d: REFUSED — %s" % [
			index, str(state.refusal.get("text", "")).replace("
", " ")])

	## Whether the server refused this bot's handshake. Reported in the
	## verdict, where `just test-handshake` reads it.
	func was_refused() -> bool:
		return not state.refusal.is_empty()

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

	## Walk the scouting detachment out to a neighbour and back, over and
	## over, for the whole match (D-20260817-load-test-bots-must-manoeuvre).
	##
	## This is what makes the verdict's fog conditions a MANOEUVRE rather
	## than a coincidence: a squad the neighbour can see, which then leaves
	## its sight (conceal) and comes back (reveal). Players form a ring
	## (1 -> 2 -> ... -> N -> 1), so every adjacent pair is watched from at
	## least one side. It only shapes a LOAD-TEST SCENARIO — which squads go
	## where — and never a correctness assertion: the vision field,
	## concealment and the reveal that follow are the real system responding
	## to real orders.
	##
	## Nothing here is latched. The detachment is re-derived every pass, so
	## a scout that died is replaced by whatever the bot has now, and a bot
	## that owns nothing yet simply does not patrol — the predecessor
	## latched on t=0/t=8 s and was therefore spent before a bot had an army
	## at all. Where the leg boundaries come from is bot_patrol.gd's job.
	## Note when the things the duration depends on actually happened.
	## Cheap, and it is the difference between "the bots cannot afford a
	## barracks" and "the run ended first" — which read identically in every
	## counter this file had before.
	func _note_progress(now: float) -> void:
		if state.wallet.size() > Economy.ResourceKind.WOOD:
			wood_peak = maxi(wood_peak, state.wallet[Economy.ResourceKind.WOOD])
		if second_building_at < 0.0:
			var owned := 0
			for wire_id in state.buildings:
				if int(state.buildings[wire_id]["owner"]) == state.player:
					owned += 1
			if owned >= 2:
				second_building_at = now
		# NOT gated on the founding crew being identified (#230). It was,
		# and `_is_military` already excludes the founder on its own — no
		# squad has id -1, so the extra guard bought nothing and cost the
		# whole metric on any scenario with no crew to identify. On
		# `scenarios/clash.tres` a bot reported `military=5` and
		# `military_peak=0` in the same line.
		#
		# The guard outlived its reason twice over: it was added against a
		# t=0 artefact from an opening in which the founder was the only
		# squad, and D-20260823-the-opening-is-a-crew-and-a-general has
		# since given every player a general from tick one, which is what
		# the comment here used to say made latching early honest.
		#
		# #123 made this a METRIC so that "there was nothing to send" and
		# "there was something and it was never sent" could be told apart.
		# Reporting zero beside five said the first when the second was
		# true, which is worse than not reporting it.
		var fighting := military_squads()
		military_peak = maxi(military_peak, fighting)
		# Every squad, not just the fighting ones: the question this
		# answers is about CREWS, which are the thing a stalled bot
		# fails to produce.
		squads_peak = maxi(squads_peak, state.squads.size())
		if first_soldier_at < 0.0 and fighting > 0:
			first_soldier_at = now
		# Own fields standing. `farm_cells(true)` includes an ally's, and a
		# load-test bot has none (every bot is its own side), so this is
		# this bot's own count.
		farms_peak = maxi(farms_peak, state.farm_cells(true).size())

	func _run_patrol(now: float) -> void:
		if state.space == null or player_count <= 0:
			return
		# The opening comes first: a move order cancels a pending build
		# (D-031), so a bot still trying to plant its town hall has nothing
		# it may march anywhere. Gated on the building EXISTING rather than
		# on the order having gone out, for the same reason `_issue_order`
		# is — a refused opening leaves a bot with one squad, and that squad
		# is the founder.
		if _opening_pending():
			return
		var home := state.spawn_cell_of(state.player)
		var watching := _spawn_cell_of((state.player % player_count) + 1)
		if home.x < 0 or watching.x < 0:
			return

		var split := BotPatrol.assign(state.squads, _founding_squad)
		var scouts: Array = split["scouts"]
		if scouts.is_empty():
			_scouts = scouts
			return

		var target := BotPatrol.leg_target(state.space, _leg, home, watching)
		# Re-order whenever the detachment changed (a scout died, or the
		# first one has just been produced) as well as when a leg ends, or a
		# replacement would stand at base for the rest of the run.
		var reissue := _leg_started_at < 0.0 or scouts != _scouts
		if not reissue and BotPatrol.leg_done(state.space,
				_scout_cells(scouts, now), _leg, watching,
				now - _leg_started_at):
			_leg += 1
			target = BotPatrol.leg_target(state.space, _leg, home, watching)
			reissue = true
		if not reissue:
			return

		_scouts = scouts
		scouts_peak = maxi(scouts_peak, scouts.size())
		_leg_started_at = now
		for squad in scouts:
			# A crew claimed for scouting stops being the haul loop's
			# business, so its old assignment goes with it — two filters
			# quietly disagreeing about who owns a squad is the defect this
			# whole change replaces.
			_gather_assigned.erase(squad)
			var order := state.encode_order(squad, target)
			if not order.is_empty():
				peer.send(0, order, ENetPacketPeer.FLAG_RELIABLE)

	## Where the detachment is, in its own order — `BotPatrol.leg_done`
	## judges the leg on the FIRST entry, and its header explains at length
	## why that must not be "whichever of them suits the current leg".
	##
	## A squad with no curve yet contributes nothing: `squad_cell` answers
	## (0, 0) for one it has never been sent, and the map origin is a real
	## cell that a distance test would take at face value.
	func _scout_cells(scouts: Array, now: float) -> Array:
		var out: Array = []
		for squad in scouts:
			if state.curves.has(squad):
				out.append(state.squad_cell(squad, now))
		return out

	## Train at every finished building this bot owns — what IT makes, not
	## gatherers at whichever one came first (#123).
	##
	## The old version asked for the literal archetype "gatherers" and
	## `break`ed at the first finished building, which was fine while a bot
	## owned exactly one town centre and is two bugs the moment it owns a
	## barracks: the barracks would be asked for gatherers, refused, and
	## then never asked again because the loop had already stopped.
	##
	## Spending the starting stockpile on crews is still the economic
	## opening a real player makes, and what puts the production path
	## (cost, squad cap, queue, spawn) under the load test rather than
	## leaving it to unit tests. What is new is that the run does not END
	## there.
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
	## Climb the tree, cheapest first
	## (`D-20260827-the-tree-is-the-ladder`).
	##
	## Deliberately simpler than `AiPlayer._research`: a bot is a LOAD
	## instrument, not an opponent, so there is no bias, no priority and no
	## retry latch — it buys whatever it can. What it is here for is that
	## without it `just test-load` would exercise STRICTLY LESS than it did
	## before the tree existed: every archetype past the levy is gated now,
	## so four bots would field levies and gatherers for the whole run and
	## the research path would never be touched under load at all.
	##
	## That is this project's own recurring shape — a gate landing and the
	## harness quietly asserting less afterwards (#123's empty `raid_pool`,
	## and D-20260818's "the fast loop carries the gate") — so it is fixed
	## here rather than discovered later.
	## Lines this bot has already asked for. The server refuses a repeat
	## (`ResearchState.is_pending`) and the CLIENT cannot see pending —
	## `research_view()` holds completed lines only — so without this a bot
	## would re-order the same tech every fourth tick for the whole run and
	## collect a refusal notice each time.
	var _research_ordered := {}

	## How many techs this bot ordered, and how many it has been told it
	## HOLDS. Two counters, not one, because they answer different
	## questions: "it never asked" and "it asked and was refused" are
	## different faults with the same symptom — the same split
	## `AI_STATS` makes, and the reason #123's `raid_orders` became a gate.
	var techs_ordered: int = 0

	## The cheapest tech this bot could start and has not asked for yet, or
	## null. One definition, so the banking rule below and the order above
	## can never disagree about which tech is "next".
	func _next_tech() -> TechDef:
		var civ := state.civ_of(state.player)
		var candidates := state.research_view().available(state.player, civ)
		candidates = candidates.filter(
			func(t): return not _research_ordered.has((t as TechDef).line))
		if candidates.is_empty():
			return null
		candidates.sort_custom(func(a: TechDef, b: TechDef) -> bool:
			if a.resource_points() != b.resource_points():
				return a.resource_points() < b.resource_points()
			return a.id < b.id)
		return candidates[0]


	## Hold the purse shut until the next tech is paid for.
	##
	## Without this the bots research NOTHING, measured twice: `4 300` and
	## `4 480` both came back `VERDICT ok` with `techs_ordered=0`. It is
	## STRUCTURAL rather than a duration problem — a bot enqueues at every
	## building every other tick, so its wallet never simultaneously holds
	## one tech's cost, however long the run is. That is the whole reason
	## the counter was added before this rule was.
	##
	## Bounded three ways, because a load instrument that starves itself is
	## worse than one that skips a code path:
	##
	## - only after THREE hauling crews, or a bot that just spent its
	##   opening crew founding a hall would bank instead of training the
	##   gatherers that earn the money — a deadlock, not a delay;
	## - only for the first two techs, so the load profile is perturbed
	##   early and briefly rather than for the whole run;
	## - and never when there is nothing to bank FOR.
	func _banking_for_research() -> bool:
		if techs_ordered >= 2 or _hauling_crew_count() < 3:
			return false
		var next := _next_tech()
		return next != null and not _can_afford_tech(next)


	func _issue_research() -> void:
		if _order_ticks % 4 != 0:
			return
		var candidates := [_next_tech()] if _next_tech() != null else []
		if candidates.is_empty():
			return
		for wire_id in state.buildings:
			var info: Dictionary = state.buildings[wire_id]
			if int(info["owner"]) != state.player or bool(info["destroyed"]):
				continue
			# A SHORT queue is fine to join. Requiring an idle building
			# looked right and was wrong: a bot enqueues gatherers every
			# other tick, so its town centre is never idle and research
			# was never ordered ONCE in a 300 s run. One queue holding
			# both kinds is the design (D-20260827) — research waiting its
			# turn behind two units is exactly what should happen.
			if float(info["progress"]) < 1.0 or (info.get("queue", []) as Array).size() > 2:
				continue
			var def := BuildingSim.def_by_id(StringName(info["def_id"]))
			if def == null:
				continue
			var here := BuildingSim.archetype_of_def(def)
			for tech in candidates:
				var t := tech as TechDef
				if t.research_at != here or not _can_afford_tech(t):
					continue
				peer.send(0, NetProtocol.encode_order_research(
					int(wire_id), String(t.line)), ENetPacketPeer.FLAG_RELIABLE)
				_research_ordered[t.line] = true
				techs_ordered += 1
				return


	func _can_afford_tech(tech: TechDef) -> bool:
		if state.wallet.size() < 4:
			return false
		return state.wallet[0] >= tech.cost_food and state.wallet[1] >= tech.cost_wood \
			and state.wallet[2] >= tech.cost_gold and state.wallet[3] >= tech.cost_stone


	func _issue_production() -> void:
		_issue_research()
		if _order_ticks % 2 != 0:
			return
		# Research before troops, briefly and early — see
		# `_banking_for_research`.
		if _banking_for_research():
			return
		var crews := _hauling_crew_count()
		for wire_id in state.buildings:
			var info: Dictionary = state.buildings[wire_id]
			if int(info["owner"]) != state.player or bool(info["destroyed"]):
				continue
			if float(info["progress"]) < 1.0:
				continue
			# Ask each building for what IT makes, rather than every
			# building for gatherers (#123). The old version asked for the
			# literal archetype "gatherers" and stopped at the first
			# finished building, so a barracks would have been asked for
			# gatherers, refused, and never asked again — and there was
			# never a barracks to find out.
			var archetype := BotBuildPlan.archetype_for(
				BuildingSim.def_by_id(StringName(info["def_id"])),
				state.civ_of(state.player), crews, state.techs)
			if archetype == &"":
				continue
			peer.send(0, NetProtocol.encode_order_produce(int(wire_id), String(archetype)),
				ENetPacketPeer.FLAG_RELIABLE)

	## Squads this bot owns that HAUL — the cap `BotBuildPlan` reads.
	func _hauling_crew_count() -> int:
		var n := 0
		for squad in state.squads:
			var def: UnitDef = UnitRoster.by_id(StringName(
				String(state.composition.get(squad, {}).get("def_id", ""))))
			if def != null and def.carry_capacity > 0:
				n += 1
		return n

	## Whether one squad is something the haul loop will never claim, which
	## on this roster is the same as "it fights".
	func _is_military(squad: int) -> bool:
		if squad == _founding_squad:
			return false
		var def: UnitDef = UnitRoster.by_id(StringName(
			String(state.composition.get(squad, {}).get("def_id", ""))))
		return def != null and def.carry_capacity <= 0

	## Squads this bot owns that FIGHT — no carry capacity, so the haul loop
	## never claims them and they are exactly what `raid_pool` is made of.
	## Reported in the verdict, because "the raid path ran" and "there was
	## anything to run it with" are different claims (#123).
	func military_squads() -> int:
		var n := 0
		for squad in state.squads:
			if _is_military(squad):
				n += 1
		return n

	## Raise the building that makes this bot a PLAYER rather than an
	## economy (#123) — something its crews can build that TRAINS
	## something. Which building that is comes from the shipped defs, not
	## from a name here.
	##
	## Paced by a cooldown rather than retried every order tick, and that is
	## not a schedule in the sense bot_patrol.gd argues against: the EFFECT
	## this waits for (a barracks in `state.buildings`) only happens when the
	## crew ARRIVES, because `server.gd::_finish_build` raises the site on
	## arrival. Re-ordering every three seconds would hand the crew a new
	## destination before it reached the last one, forever. `ai_player.gd`
	## carries `_builder_busy_until` for exactly this reason and says so.
	##
	## Affordability is checked here rather than left to the server for the
	## same arrival reason: the cost is charged on arrival, so an
	## unaffordable order is a crew walking ten cells to be turned away.
	func _raise_buildings(now: float) -> void:
		if state.space == null:
			build_block = "no space"
			return
		if now < _builder_free_at:
			build_block = "cooldown"
			return
		# The cooldown has lapsed: whatever it was doing, this crew is the
		# haul loop's business again unless it is picked afresh below.
		_builder_squad = -1
		var owned: Array = []
		for wire_id in state.buildings:
			var info: Dictionary = state.buildings[wire_id]
			if int(info["owner"]) == state.player and not bool(info["destroyed"]):
				owned.append(String(info["def_id"]))
		if owned.is_empty():
			build_block = "no hall"  # the opening comes first
			return
		var def := BotBuildPlan.wanted_building(owned, &"gatherers")
		if def == null:
			# Nothing that TRAINS is outstanding, so the one gate (#337).
			# Deliberately last: a gate must never outbid a barracks, and
			# reaching this line at all means there is no barracks left to
			# outbid.
			def = BotBuildPlan.wanted_gate(owned, &"gatherers")
		if def == null:
			build_block = "nothing wanted"
			return
		if not BotBuildPlan.can_afford(state.wallet, def):
			build_block = "cannot afford %s (wallet %s, needs w%d f%d g%d s%d)" % [
				def.id, state.wallet, def.cost_wood, def.cost_food,
				def.cost_gold, def.cost_stone]
			return
		var builder := _idle_worker()
		if builder < 0:
			build_block = "no spare crew for %s" % def.id
			return
		var home := state.spawn_cell_of(state.player)
		if home.x < 0:
			build_block = "no home yet"
			return
		var site := BotBuildPlan.building_site(state.space, home, def,
			BotBuildPlan.claimed_radius_of(owned), _site_attempts)
		var build := state.encode_build(builder, String(def.id), site)
		if build.is_empty():
			build_block = "cannot encode a build for %s" % def.id
			return
		peer.send(0, build, ENetPacketPeer.FLAG_RELIABLE)
		build_block = "ordered %s at %s (try %d)" % [def.id, site, _site_attempts]
		# A crew told to build has stopped hauling (D-034) — and must stay
		# out of the haul loop's reach until it has arrived, or the next pass
		# sends it to a tree and cancels the build.
		_gather_assigned.erase(builder)
		_builder_squad = builder
		_site_attempts += 1
		_builder_free_at = now + BUILDER_COOLDOWN_SECONDS

	## Work the gate this bot built (#337).
	##
	## D-076's two gate opcodes had never crossed a real socket under
	## load — no bot built a gate, so nothing drove them. That is the
	## same gap #337 names in the AI, in the harness.
	##
	## It CLOSES and re-opens rather than setting AUTO, and the
	## difference is the whole point. New gates start in auto mode
	## (`BuildingSim._gate_mode`'s own comment), so a bot ordering AUTO
	## would send a packet that changed nothing and a verdict counting
	## those packets would pass against a bot that never used a gate.
	## Closing is a state change the server can refuse, the sim has to
	## re-path around, and the client has to redraw.
	##
	## Latched on the EFFECT — the replicated `gate_mode` and `gate_open`
	## coming back — never on having sent. D-107.
	func work_the_gate(now: float) -> void:
		if now < _gate_next_at:
			return
		for wire_id in state.buildings:
			var info: Dictionary = state.buildings[wire_id]
			if int(info["owner"]) != state.player or bool(info["destroyed"]):
				continue
			var def := BuildingSim.def_by_id(StringName(String(info["def_id"])))
			if def == null or not def.is_gate:
				continue
			var mode := int(info.get("gate_mode", BuildingSim.GATE_MODE_AUTO))
			# Manual first: the server refuses a state order on a gate
			# still in auto mode, so the two orders are two ticks apart
			# and the second is only sent once the first has ARRIVED.
			if mode != BuildingSim.GATE_MODE_MANUAL:
				gate_orders += 1
				peer.send(0, NetProtocol.encode_order_gate_mode(
					int(wire_id), BuildingSim.GATE_MODE_MANUAL),
					ENetPacketPeer.FLAG_RELIABLE)
				_gate_next_at = now + GATE_WORK_SECONDS
				return
			gate_orders += 1
			gate_toggles += 1
			_gate_wanted_open = not bool(info.get("gate_open", false))
			peer.send(0, NetProtocol.encode_order_gate_state(
				int(wire_id), _gate_wanted_open), ENetPacketPeer.FLAG_RELIABLE)
			_gate_next_at = now + GATE_WORK_SECONDS
			return


	## A crew that can be spared to build: a hauler that is not scouting.
	## The LAST one, so this does not fight the patrol over the first —
	## `ai_player.gd` picks the last crew for its scout for the mirror
	## reason, and losing the builder to something else is how its barracks
	## used to go unbuilt.
	func _idle_worker() -> int:
		var best := -1
		for squad in state.squads:
			if _scouts.has(squad) or squad == _founding_squad or squad == _builder_squad:
				continue
			var def: UnitDef = UnitRoster.by_id(StringName(
				String(state.composition.get(squad, {}).get("def_id", ""))))
			if def != null and def.carry_capacity > 0:
				best = squad
		return best


	## Send every idle gatherer crew at the nearest wood node this bot has
	## actually been shown. Bots produced gatherers for two milestones and
	## never ORDERED them, so the whole haul cycle — gather orders, wallet
	## replication, node depletion, crew retargeting — ran only in unit
	## tests and under the server-side AI, never under the load test's
	## wire. With trees a minute deep (D-087) depletion now happens well
	## inside a load run, and the bots are what make the felling events a
	## live, observable flow (`nodes_felled` in the verdict line).
	##
	## Re-ordered only when unassigned or when the assigned node vanished
	## from `state.nodes` (a felling): the server retargets crews itself,
	## and a bot that re-ordered every tick would fight it.
	##
	## Iterates the WORKERS half of `BotPatrol.assign`, not `state.squads`.
	## This loop used to claim every crew a bot owned, and a bot's whole
	## army is crews — so a squad the patrol wanted was already hauling and
	## a move order would cancel the haul (D-034) every pass. One split, two
	## halves, no squad in both.
	func _put_gatherers_to_work() -> void:
		# The bot's own FIELDS (D-20260828-food-is-grown-not-only-found),
		# one crew each. Without this the load test would raise farms and
		# never work one — the "the configuration nothing runs" gap that
		# #119 and #123 were both about, arriving a third time.
		var fields: Dictionary = state.farm_cells(true)
		var field_taken := {}
		for assigned_squad in _gather_assigned:
			var at := int(_gather_assigned[assigned_squad])
			if fields.has(at):
				field_taken[at] = true

		for squad in BotPatrol.assign(state.squads, _founding_squad)["workers"]:
			if squad == _builder_squad:
				continue  # walking to a building site; see `_builder_squad`
			var def: UnitDef = UnitRoster.by_id(StringName(
				String(state.composition.get(squad, {}).get("def_id", ""))))
			if def == null or def.carry_capacity <= 0:
				continue
			# A field is a work site the server keeps and `state.nodes` does
			# not, so the still-valid test has to ask both — otherwise a crew
			# standing in a farm is re-ordered onto it every single pass.
			if _gather_assigned.has(squad) \
					and (state.nodes.has(_gather_assigned[squad])
						or fields.has(_gather_assigned[squad])):
				continue
			var best := -1
			var best_distance := 1 << 30
			var here := state.squad_cell(squad, 0.0)
			for cell in fields:
				if field_taken.has(int(cell)):
					continue
				var fd := state.space.distance(here, state.space.from_index(int(cell)))
				if fd < best_distance:
					best_distance = fd
					best = int(cell)
			if best >= 0:
				field_taken[best] = true
				field_orders += 1
			else:
				for cell in state.nodes:
					if int(state.nodes[cell]) != Economy.ResourceKind.WOOD:
						continue
					var d := state.space.distance(here, state.space.from_index(int(cell)))
					if d < best_distance:
						best_distance = d
						best = int(cell)
			if best < 0:
				continue
			_gather_assigned[squad] = best
			peer.send(0, NetProtocol.encode_order_gather(squad, best),
				ENetPacketPeer.FLAG_RELIABLE)

	## Which squad this bot could found its town hall with, or -1.
	##
	## Whichever squad `built_by` actually admits — the crew, not whichever
	## id sorts first. `state.squads[0]` was fine while the opening was one
	## squad; with a general in the list it is a coin toss between the
	## settler and a squad the server will refuse ("general cannot build a
	## Town Centre") forever.
	##
	## Extracted from `_found_town_hall` so `_opening_pending` can ask the
	## same question rather than a second version of it (#230).
	func _founding_builder() -> int:
		if _founding_squad in state.squads:
			return _founding_squad
		var hall := BuildingSim.def_by_id(&"town_centre")
		for squad in state.squads:
			var def: UnitDef = UnitRoster.by_id(StringName(
				String(state.composition.get(squad, {}).get("def_id", ""))))
			if def != null and BuildingSim.can_build(hall, def.archetype):
				return squad
		return -1


	## Whether this bot still has an OPENING to complete, and so must not
	## be marched anywhere (D-031: a move order cancels a pending build).
	##
	## Its two callers used to ask `_owns_a_building()` alone, which is the
	## same question only while every match starts from the opening. A
	## SCENARIO (D-098) can hand a bot five fighting squads, no crew and no
	## buildings — `scenarios/clash.tres` does exactly that — and there the
	## plain question answers "no building" on every tick forever. So the
	## bot spent the whole run trying to found a town hall it had nobody to
	## found with, and never reached the raid order or the patrol at all:
	## `raid_orders=0 scouts_peak=0 patrol_legs=0` beside five military
	## squads, and `test-scenario clash` could not pass (#230).
	##
	## Stated as what the guard's own comment always said it meant — "a bot
	## still trying to plant its town hall" — rather than as a proxy for it.
	## A bot whose crew has DIED also falls through now, and raids with what
	## it has left, which is better than standing still forever.
	func _opening_pending() -> bool:
		if _owns_a_building():
			return false
		return _founding_builder() >= 0
	## Which resource the next crew should be sent after (#337).
	##
	## WOOD unless something the bot wants to BUY is short of something
	## else, and then exactly ONE crew is diverted per pass.
	##
	## The bots gathered wood and nothing else — not even food — which was
	## fine while the only thing they bought was a barracks. It stopped
	## being fine the moment they were asked to build a gate: `gate.tres`
	## costs 45 STONE, so the gate was unaffordable forever and the bot
	## half of #337 would have shipped as dead code exercising nothing.
	## Measured before this: `test-load 4 300` came back clean with
	## `gate_orders=0 gate_toggles=0`.
	##
	## That is the SAME root cause as the AI half, and it reuses the same
	## shared function rather than a second copy of the rule
	## (`StaticDefence.scarcest_shortfall`, which naval stage 7 also
	## reads).
	##
	## ONE crew, and only while the purchase is unaffordable, because
	## every timing in `docs/status/load-testing.md` is tuned against
	## these bots gathering wood — this must move the economy as little as
	## it can while still reaching the thing it has to exercise.
	func _kind_wanted(already_diverted: bool) -> int:
		if already_diverted:
			return Economy.ResourceKind.WOOD
		var owned: Array = []
		for wire_id in state.buildings:
			var info: Dictionary = state.buildings[wire_id]
			if int(info["owner"]) == state.player and not bool(info["destroyed"]):
				owned.append(String(info["def_id"]))
		var next := BotBuildPlan.wanted_building(owned, &"gatherers")
		if next == null:
			next = BotBuildPlan.wanted_gate(owned, &"gatherers")
		if next == null or BotBuildPlan.can_afford(state.wallet, next):
			return Economy.ResourceKind.WOOD
		var short := StaticDefence.scarcest_shortfall(
			state.wallet, StaticDefence.cost_of(next))
		return Economy.ResourceKind.WOOD if short < 0 else short


	## Ask for a town hall, and keep asking until there IS one.
	##
	## A player starts with one gatherer crew and one general and no base
	## (D-20260823-the-opening-is-a-crew-and-a-general), so this is the
	## opening move a real player makes — and it is what puts construction,
	## building replication and the persistent-explored hash under the load
	## test rather than leaving all three to unit tests.
	##
	## Two fixes are layered here and the second is the interesting one. The
	## guard used to be `_orders_issued == 0`, which asks "is this my first
	## order" rather than "did I send it", so a bot whose first order tick
	## beat the WELCOME skipped its opening silently and never tried again.
	## That was corrected to a flag set on the `peer.send` — and the send is
	## not the event that matters either.
	##
	## A build order the server REFUSES — "Cannot build there, a forest is
	## in the way" is entirely likely on a start, since D-087 put 1,920
	## nodes on the map — left the bot with no hall, no production, no crews
	## and no scouts for the whole run, while its own flag said the opening
	## had been dealt with. Seen directly in the per-bot line:
	##
	##   BOT player=1 squads=1 buildings=0 town_hall_ordered=true
	##
	## That is D-107's rule with the names changed: *a latch that records an
	## INTENT will eventually be read as a record of an OUTCOME. Latch on
	## the effect — something the actor can SEE — or do not latch.* D-107
	## was written about `_founded = true` sitting one line above
	## `send.call(order)` in `ai_player.gd`; this is the same line of code in
	## the load-test bot.
	##
	## So there is no latch: the caller asks `_owns_a_building()`, and each
	## attempt asks for a DIFFERENT site, walking outward from home through
	## the nearest-first offset table (D-067 sorted it for exactly this).
	## Retrying the refused cell forever would be a loop, not a fix. The
	## radius is `server.gd`'s BUILD_REACH_CELLS, because a builder has to be
	## within that of the site it is handed.
	func _found_town_hall() -> void:
		# The builder is whichever squad `built_by` actually admits — the
		# crew, not whichever id sorts first. `state.squads[0]` was fine
		# while the opening was one squad; with a general in the list it is
		# a coin toss between the settler and a squad the server will
		# refuse ("general cannot build a Town Centre") forever.
		var builder := _founding_builder()
		if builder < 0:
			return  # the crew is dead; nothing this bot owns may settle
		var home := state.spawn_cell_of(state.player)
		if home.x < 0:
			return
		var offsets := TorusSpace.disk_offsets(BUILD_SITE_SEARCH_CELLS)
		var site := state.space.normalize(
			home + offsets[_build_attempts % offsets.size()])
		var build := state.encode_build(builder, "town_centre", site)
		if build.is_empty():
			return
		peer.send(0, build, ENetPacketPeer.FLAG_RELIABLE)
		_build_attempts += 1
		_founding_squad = builder

	func _issue_order(now: float) -> void:
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
		_raise_buildings(now)
		# Beside the build step, and BEFORE the "no squads" guard below:
		# working a gate needs no squad, and putting it after that guard
		# is precisely how `_issue_production` became a deadlock the
		# moment a bot could legitimately own nothing (D-031).
		work_the_gate(now)
		_put_gatherers_to_work()

		if state.squads.is_empty():
			return

		# The opening comes first, and it comes BEFORE `raid_pool` (D-031).
		#
		# That ordering is the whole of it. `raid_pool` excludes the founding
		# party — it must, or a raid order cancels the build it is walking
		# to — so a bot whose ONLY squad is that founder builds an empty pool
		# and returns. Put the opening below that and it is unreachable for
		# exactly the bot that has not managed it yet. Observed, one run
		# after the retry itself was written: `build_attempts=1 buildings=0`
		# on a bot that asked once, was refused, and never got another turn.
		if _opening_pending():
			_found_town_hall()
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
			if founding_pending and candidate == _founding_squad:
				continue
			# Working crews stay out of the raid rotation: a move order
			# cancels a haul the same way it cancels a build (D-034), and a
			# bot that raids with its own economy exercises neither. The
			# scouting detachment is out for the same reason — its orders
			# come from `_run_patrol`, and two callers ordering one squad is
			# how the rally used to cancel the town hall it had just asked
			# for.
			if _gather_assigned.has(candidate) or _scouts.has(candidate):
				continue
			# ...and the crew walking to a building site. This was the FOURTH
			# place that tells a squad what to do, and the one the builder
			# guard first missed: with the crew out of `_gather_assigned` it
			# read as idle here instead, and got marched to the contested
			# middle three seconds after being sent to build. Measured:
			# `raid_orders=149` with `military_squads=0` — a gate passing on
			# a hauling crew nobody meant to raid with.
			if candidate == _builder_squad:
				continue
			raid_pool.append(candidate)
		if raid_pool.is_empty():
			# Nothing this bot owns is free to raid with, which today is
			# EVERY tick after the founding party is spent: a bot only ever
			# builds a town centre, a town centre `produces` gatherers only
			# (buildings/town_centre.tres), and every crew is either hauling
			# or scouting. So this branch is the load test's standing
			# admission that its bots field no army — issue #123, kept
			# separate from #69/#84 because military production cannot be
			# reached inside a 120 s run at all.
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
			# Counted only for a squad that FIGHTS. The gate asks whether an
			# army was ever sent anywhere, and an order that went to a
			# hauling crew — because some other guard let one into the pool —
			# answers a different question. A gate met by the wrong squad is
			# the vacuous pass D-022's audit block is about.
			if _is_military(squad):
				raid_orders += 1

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
## The ScenarioDef this run is playing, or null for a real opening.
##
## A scenario is an opening POSITION (D-098), and a verdict that gates on
## something the position does not contain is a vacuous FAILURE — the
## mirror of the vacuous passes D-022's audit block was written about, and
## it fails the same way every time, which teaches the next person to
## ignore the result.
var _scenario: ScenarioDef = null
## The protocol version the bots claim (#179). See `--protocol`.
var _protocol := NetProtocol.PROTOCOL_VERSION
var _reported := false
var _finished := false


func _initialize() -> void:
	# Which build this is, first line (#178) — see server.gd's copy. The
	# bots share net_protocol.gd with both, so a load-test log that does
	# not say the same version as the server it ran against is the one
	# thing that would explain an otherwise impossible desync.
	print(BuildVersion.banner("bots"))
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	# A load test measured with the wrong number of bots is worse than one
	# that did not run: `int()` strips non-digits, so a mistyped --clients
	# reads as a plausible count and the verdict quotes it as fact
	# (D-20260817-recipe-args-are-positional, #89/#98).
	# The SCENARIO this run is playing, or "" for a real opening. Read only
	# to scope the verdict below to what the scenario actually contains
	# (#230) — nothing about it reaches the wire or a bot's decisions, so
	# a harness reading its own fixture is not a client learning something
	# it should not know.
	_scenario = Scenario.by_id(StringName(String(args.get("scenario", ""))))
	var bad_args := CmdArgs.invalid_integers(args, ["clients", "port"])
	var bad_args := CmdArgs.invalid_integers(args, ["clients", "port", "protocol"])
	bad_args.append_array(CmdArgs.invalid_numbers(args, ["duration"]))
	if not bad_args.is_empty():
		push_error(CmdArgs.complaint("bot_client.gd", bad_args))
		quit(1)
		return

	var client_count: int = int(args.get("clients", 1))
	# Inside the compose network the server is a hostname, not localhost,
	# so the address is overridable by env as well as by flag.
	var default_address := OS.get_environment("EDOTMW_SERVER_ADDRESS")
	if default_address == "":
		default_address = DEFAULT_SERVER_ADDRESS
	var address: String = String(args.get("address", default_address))
	var port: int = int(args.get("port", DEFAULT_SERVER_PORT))
	_duration = float(args.get("duration", -1.0))
	# Dev-only, and never set by `just test-load`: it exists so
	# `just test-handshake` can present a deliberately wrong build to a
	# real server and prove the refusal fires (#179).
	_protocol = int(args.get("protocol", NetProtocol.PROTOCOL_VERSION))
	if _protocol != NetProtocol.PROTOCOL_VERSION:
		print("bot_client.gd: claiming protocol %d instead of %d — expecting to be REFUSED" % [
			_protocol, NetProtocol.PROTOCOL_VERSION])

	print("bot_client.gd: spawning %d virtual client(s) against %s:%d" % [client_count, address, port])

	for i in range(client_count):
		var vc := VirtualClient.new(i, address, port, client_count, _protocol)
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


## Patrol legs completed across every bot, and the largest detachment any
## of them staffed (D-20260817-load-test-bots-must-manoeuvre).
##
## Reported rather than gated, deliberately. `reveal_events` is the gate
## and stays the gate — this is what tells the next person WHY a zero
## happened, which is the question #69 and #84 each spent a session on. A
## run with `patrol_legs=0` never manoeuvred and the fog counters mean
## nothing; a run with legs and no reveals is a fog problem.
func _patrol_legs() -> int:
	var n := 0
	for vc in _clients:
		n += vc.patrol_legs()
	return n


func _scouts_peak() -> int:
	var n := 0
	for vc in _clients:
		n += vc.scouts_peak
	return n


## Raid orders issued across every bot, and the soldiers there were to
## issue them to (#123).
##
## `raid_orders` is a GATE, not a metric, and it is the only one here that
## is. `raid_pool` was empty on every tick of every match — a bot only
## builds a town centre, a town centre `produces` gatherers only, and the
## haul loop claimed every crew — so everything below
## `if raid_pool.is_empty(): return` was written, correct, called, and
## unreachable, while the verdict reported clean. A load test that has
## never once sent an army anywhere must say so out loud.
##
## READ IT WITH `military_peak` NOW, and know what one of those is worth.
## Every player opens with a GENERAL
## (D-20260823-the-opening-is-a-crew-and-a-general), which is a fighting
## squad the haul loop never claims — so one raid order and
## `military_peak = 1` per bot are the OPENING, not production. This gate
## still says what it was written to say (an army was sent somewhere) and
## no longer says the thing it used to imply alongside it (a barracks
## finished and trained something). The signal for that is
## `military_peak` ABOVE one per bot, and `first_soldier_at`
## beside it. Deliberately not turned into a gate here: the shipped map
## already leaves two of four bots short of a barracks at 420 s, so
## gating on it would fail honest runs, and picking the duration that
## does not is a measurement this change did not take.
func _raid_orders() -> int:
	var n := 0
	for vc in _clients:
		n += vc.raid_orders
	return n


func _military_squads() -> int:
	var n := 0
	for vc in _clients:
		n += vc.military_peak
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
## How many bots the server refused at the handshake (#179). Zero in
## every ordinary run; `just test-handshake` is the one thing that
## deliberately makes it nonzero, and it FAILS if it is zero — because a
## refusal path that is never taken is a refusal path that will be broken
## the first time it matters.
func _refused_count() -> int:
	var count := 0
	for vc in _clients:
		if vc.was_refused():
			count += 1
	return count


## Gate orders and state changes across all bots (#337). Reported rather
## than gated, and the reasoning is #123's `nodes_felled` verbatim: a bot
## reaches its gate only after a barracks is standing and a crew is spare,
## which needs minutes of match — so gating on it would re-set D-031's
## stale-timing trap, where a duration that no longer reaches the
## condition fails an honest run. `just test-scenario` starts mid-game and
## is where the gate belongs once somebody measures the duration that
## always reaches it.
func _gate_orders() -> int:
	var count := 0
	for vc in _clients:
		count += vc.gate_orders
	return count


func _gate_toggles() -> int:
	var count := 0
	for vc in _clients:
		count += vc.gate_toggles
	return count


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
	# #123: the raid path had never run, on any load test, ever. A run in
	# which nobody was sent anywhere proves nothing about an engagement
	# between armies, however clean the rest of the verdict looks — the same
	# principle as the casualty, conceal and reveal conditions above.
	if _raid_orders() <= 0:
		return false
	# Slice 4's live proof: a town hall was founded and reached clients,
	# and the persistent-explored hash agreed about it throughout. A run
	# where nobody built anything proves nothing about buildings, exactly
	# as a run where nobody died proves nothing about combat.
	#
	# ASKED ONLY OF A RUN THAT COULD HAVE BUILDINGS (#230). A scenario
	# that places none, and hands out no squad that could found one,
	# cannot satisfy this however healthy the run is —
	# `scenarios/clash.tres` is two armies and nothing else, deliberately,
	# and it is the scenario `docs/status/ai-opponent.md` tells you to
	# reach for. Gating on it there fails every run identically, which is
	# not a check.
	#
	# What replaces it is not nothing: a scenario with no buildings must
	# still field the army it was given (below). The desync clause stays
	# unconditional — it says "if any building WAS seen, both sides agreed
	# about it", which is true and cheap on a run with none.
	if _expects_buildings() and _buildings_known() <= 0:
		return false
	if _building_desyncs() != 0:
		return false
	# And the army the scenario DID hand out has to be real. On a run with
	# buildings this is implied by `raid_orders` above; on `clash` it is
	# the gate that replaces the buildings one, and it is exactly the
	# number that read 0 beside `military=5` before #230.
	if not _expects_buildings() and _military_squads() <= 0:
		return false
	return true


## Whether this run could produce a building at all: a real opening always
## can, and a scenario can only if it places one or hands out a squad that
## could found one.
##
## Derived from the SCENARIO RESOURCE rather than from a list of scenario
## NAMES, so a new `.tres` is covered the day it is written rather than
## the day somebody remembers to add it here.
func _expects_buildings() -> bool:
	if _scenario == null:
		return true
	if not _scenario.buildings.is_empty():
		return true
	var hall := BuildingSim.def_by_id(&"town_centre")
	for entry in _scenario.squads:
		if BuildingSim.can_build(hall, entry.archetype):
			return true
	return false


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
	print("bot_client.gd: VERDICT %s — %d/%d bots connected, %d curve packets received, %d squad curves held, %d soldiers derived client-side, %d state-hash checks, %d desyncs, casualties_applied=%d conceal_events=%d reveal_events=%d ghosts_peak=%d patrol_legs=%d scouts_peak=%d raid_orders=%d military_peak=%d known_squads_max=%d buildings_known=%d building_desyncs=%d nodes_known_max=%d nodes_felled=%d techs_ordered=%d techs_held=%d gate_orders=%d gate_toggles=%d farms_peak=%d field_orders=%d refused=%d" % [
		"ok" if _verdict_ok() else "failed",
		_ever_connected_count(), _clients.size(),
		_packets_received(), curves, soldiers,
		_state_hash_checks(), _desync_count(),
		_casualties_applied(), _conceal_events(), _reveal_events(), _ghosts_peak(),
		_patrol_legs(), _scouts_peak(), _raid_orders(), _military_squads(),
		_max_known_squads(), _buildings_known(), _building_desyncs(), _max_known_nodes(),
		_nodes_felled(), _techs_ordered(), _techs_held(), _gate_orders(), _gate_toggles(), _farms_peak(), _field_orders(), _refused_count()])

	# Printed only on failure, and containing the word the log scan looks
	# for — which now actually appears when something is wrong.
	if _desync_count() > 0:
		for vc in _clients:
			if vc.state.desync_count > 0:
				push_error("bot %d: desync — %s" % [vc.index, vc.state.last_desync])

	# Per-bot, because every aggregate above hides WHICH bot. Four of the
	# five defects behind #69/#84 were "one of them is not doing the thing",
	# and each cost a three-minute run to localise from sums alone.
	for vc in _clients:
		print("bot_client.gd: BOT player=%d squads=%d squads_peak=%d military=%d buildings=%d build_attempts=%d scouts_peak=%d patrol_legs=%d raid_orders=%d conceal=%d reveal=%d military_peak=%d wood_peak=%d second_building_at=%.0f first_soldier_at=%.0f farms_peak=%d field_orders=%d build=%s" % [
			vc.state.player, vc.state.squads.size(), vc.squads_peak,
			vc.military_squads(), vc.state.buildings.size(),
		print("bot_client.gd: BOT player=%d squads=%d military=%d buildings=%d build_attempts=%d scouts_peak=%d patrol_legs=%d raid_orders=%d conceal=%d reveal=%d military_peak=%d wood_peak=%d second_building_at=%.0f first_soldier_at=%.0f techs=%d/%d epoch=%d build=%s" % [
			vc.state.player, vc.state.squads.size(), vc.military_squads(),
			vc.state.buildings.size(),
			vc.build_attempts(), vc.scouts_peak, vc.patrol_legs(), vc.raid_orders,
			vc.state.conceal_events, vc.state.reveal_events,
			vc.military_peak, vc.wood_peak, vc.second_building_at, vc.first_soldier_at,
			vc.state.techs.size(), vc.techs_ordered, vc.state.epoch, vc.farms_peak, vc.field_orders, vc.build_block])

	var awaiting := _squads_awaiting_composition()
	if awaiting > 0:
		push_error("bot_client.gd: %d squad(s) had a curve but no composition — the server replicated something it never described" % awaiting)


## Minimal `--key=value` CLI parser for user args (after `--`).
## Example: godot --headless --script bot_client.gd -- --clients=20 --address=127.0.0.1 --port=4433
## Techs the bots ORDERED and techs they were told they HOLD
## (`D-20260827-the-tree-is-the-ladder`).
##
## A METRIC, not a gate, and deliberately so — for `nodes_felled`'s reason.
## Research costs a real bank, and how long a bot takes to afford one is a
## property of the map, the seed and the duration; gating on it would
## re-set D-031's stale-timing trap the first time the map ladder moved.
##
## What it is FOR is that the bots' research is the only thing keeping
## `test-load` from exercising strictly less of the roster than it did
## before the tree: every archetype past the levy is gated now. A run
## reporting `techs_held=0` means that coverage is gone, whatever else is
## green — which is precisely the shape of #123's empty `raid_pool`, and
## the reason this is printed rather than assumed.
func _techs_ordered() -> int:
	var total := 0
	for vc in _clients:
		total += vc.techs_ordered
	return total


func _techs_held() -> int:
	var total := 0
	for vc in _clients:
		total += vc.state.techs.size()
	return total


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


## Depletion events received across all bots (D-087). Bots never drain
## `felled`, so its size IS the running count. A metric rather than a
## verdict gate: a felling needs a town hall (40 s), a produced crew and a
## worked-out tree (~60 s of gathering), so gating on it would quietly pin
## every run to ~3 minutes — the exact stale-timing trap D-031 set for
## `test-load 4 40`. Assert it by running long enough and READING it.
func _nodes_felled() -> int:
	var total := 0
	for vc in _clients:
		total += vc.state.felled.size()
	return total


## The renewable half, summed across bots
## (D-20260828-food-is-grown-not-only-found). Both are METRICS — read them
## together: `farms_peak=0` is "nobody could afford a field", while
## `farms_peak>0 field_orders=0` is "fields were raised and never worked",
## and only the pair separates those.
func _farms_peak() -> int:
	var total := 0
	for vc in _clients:
		total += vc.farms_peak
	return total


func _field_orders() -> int:
	var total := 0
	for vc in _clients:
		total += vc.field_orders
	return total
