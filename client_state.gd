extends RefCounted
class_name ClientState

## Everything a client knows, with no rendering and no networking
## transport attached.
##
## Both the real GUI client and the load-test bots use this, deliberately:
## it means `just test-load` exercises the same protocol handling and the
## same soldier derivation the real client runs, rather than a simplified
## imitation that could pass while the client is broken. It also makes the
## client's logic testable headless, which the GUI client itself is not
## (D-014 — the client needs a GPU and cannot be containerized).
##
## What a client holds is only ever squad CURVES. Soldier positions are
## never received; they are recomputed here from the curve, the formation
## and the slot index (D-006). If this class ever grows a field holding a
## soldier position that came off the wire, the keystone decision has been
## broken.

var space: TorusSpace = null
var player: int = -1
var squads := PackedInt32Array()

## The map's starting cells, in player order (D-036). Told to us rather
## than derived, so nothing on this side has to reimplement the server's
## spawn placement — see NetProtocol.encode_welcome for what happened
## when something did.
var spawn_cells := PackedInt32Array()

## The per-player squad ceiling (MatchState.squad_cap, from MapConfig).
## Told to us rather than read from a local .tres, so the HUD's "n/cap"
## can never disagree with the rule the server actually enforces. 0 means
## the server never said, which the HUD shows as no cap rather than as 0.
var squad_cap: int = 0

## The highest server tick this client has been told about, and the local
## clock reading when it heard it. Together they are the match timer —
## see note_server_tick and match_elapsed.
var server_tick: int = 0
var server_tick_at: float = 0.0

## Buildings this client has ever been shown, by wire id (D-029/D-030).
## Never pruned: buildings are persistent-explored, so leaving vision
## freezes what is known rather than forgetting it.
## This player's own four resource totals (D-028). There is nowhere to
## put anyone else's, deliberately: wallets are private, so the protocol
## never carries another player's.
var wallet := PackedInt32Array()
var wallet_updates: int = 0

## This player's own researched tech LINES and the epoch they put them in
## (`D-20260827-the-tree-is-the-ladder`).
##
## Own and allies' only. There is nowhere to put an enemy's, deliberately,
## for the reason there is nowhere to put their wallet: the protocol never
## carries it, so no future caller can leak one. And it must never enter
## `composition_hash` — the server hashes `visible_to(player)`, and a
## client that hashed an upgrade it was never told about would desync a
## perfectly healthy system (D-099's ghost rule, different field).
##
## The set arrives WHOLE on every change, so this is an assignment and not
## a merge; a merge would leave a client that missed a packet permanently
## one tech behind with nothing able to notice.
var techs: Array[StringName] = []
var epoch: int = 1
var tech_updates: int = 0

## This client's own civ as the SERVER named it, or "" before the first
## TECH_STATE. Read through `civ_of`, never directly.
##
## The lobby is the ordinary source (D-048) and stays so. This is the
## fallback for a match with no lobby — `--lobby=0`, which is how every
## `just test-load` run starts — where `civ_of` answered "" for every bot
## in every run there has ever been (docs/status/load-testing.md). Any
## client can resolve its own techs now, lobby or not.
var own_civ: StringName = &""


## Has this player researched `line`? Empty is "no tech needed", which is
## every unit and building that shipped before the tree — so a client
## talking to a server with no `/techs` shows exactly the menu it always
## did.
func has_tech(line: StringName) -> bool:
	return line == &"" or techs.has(line)


var _research_view: ResearchState = null
var _research_view_at: int = -1


## What this client knows it has, as the SAME object the server reasons
## with (`D-20260827-the-tree-is-the-ladder`).
##
## The point is that the client does not get its own copy of "what may I
## research next". `ResearchState.can_research` holds the prerequisite,
## epoch and already-known rules; the research panel and the AI both ask
## it, and so does the server. Three readers, one definition — which is
## the D-058/D-065 lesson (a rule written out twice is two rules free to
## drift) applied before it costs anything rather than after.
##
## Rebuilt only when `tech_updates` moves, so the panel asking every frame
## costs one integer comparison.
func research_view() -> ResearchState:
	if _research_view != null and _research_view_at == tech_updates:
		return _research_view
	var view := ResearchState.new()
	for line in techs:
		view.grant(player, line)
	_research_view = view
	_research_view_at = tech_updates
	return view

## The most recent thing the server refused, and why (D-002 owns the
## rules, so it owns the explanation).
var last_notice := ""
var notices_received: int = 0

## Resource nodes: cell index -> ResourceKind. Fog-gated by the server as
## vision reaches them; the client draws where resources are, never how
## much is left.
var nodes := {}

## Nodes the server reported worked out, in arrival order, not yet shown
## falling. Removal from `nodes` happens immediately on receipt — that is
## what stops the AI ordering crews at a stump and takes the dot off the
## minimap — while this queue lets the GUI fell the tree it drew there.
## Drain with `take_felled()`; a felled cell carries its last known kind,
## because `nodes` no longer does.
var felled := []

## Nodes the server has just told this client about, in arrival order, not
## yet drawn. The other end of the same idea as `felled`: `nodes` is what is
## KNOWN and answers questions, this is the NEWS, and the GUI drains it to
## decide what it still has to grow.
##
## Its reason for existing is the drain, not the record. The client used to
## find newly revealed cells by scanning all of `nodes` — 7,664 of them on
## the shipped map — and could only afford to do so on frames where the two
## sides' SIZES disagreed, which stops being a sound test the moment drawing
## is budgeted and placed lags known on purpose (see `node_placement.gd`).
var revealed := []


## Fellings not yet animated. Draining hands ownership to the caller; the
## headless consumers (bots, AI seats) never call this, and the queue is
## bounded by the map's node count, so it cannot grow without limit.
func take_felled() -> Array:
	var out := felled
	felled = []
	return out


## Reveals not yet drawn. Same drain-once contract, same bound — a cell is
## revealed once (`server.gd`'s `_send_visible_nodes` sends only cells it
## has not sent before), so the headless consumers that never drain this
## cannot accumulate more than the map's node count.
func take_revealed() -> Array:
	var out := revealed
	revealed = []
	return out


## Casualty events whose men FELL and have not yet been laid down as
## corpses (D-20260819-a-casualty-is-visible). Same drain-once contract as
## `take_felled` — but unlike those queues this one has no natural bound,
## so it is only ever WRITTEN when `record_corpses` is true, which only a
## renderer that drains it sets. Bots and AI seats leave it off and the
## list stays empty for the length of a run.
##
## Entries are {"id", "before", "after"}: the men to lay down are slots
## [after, before) of that squad's formation, derived by the caller at its
## own frame time — this class records the NEWS, not the geometry.
var record_corpses := false
var _casualty_sites := []


func take_casualty_sites() -> Array:
	var out := _casualty_sites
	_casualty_sites = []
	return out


## World events worth HEARING, not yet sounded (#344).
##
## The exact shape and contract of `_casualty_sites` above, and for the
## same reason: this class is run by the load-test bots and the AI seats
## as well as the GUI client, and an unread queue would grow for the
## length of a run. Only something that DRAINS it sets `record_audio`,
## which is the GUI client and nothing else — bots and AI leave it off
## and the list stays empty.
##
## Entries are {"event": StringName, "cell": int, "magnitude": float}.
## A CELL, never a world position: the fog query this is gated through is
## per cell (`TerrainFog.level_at`), and handing audio a position would
## be inventing a second notion of where something happened.
##
## Nothing here crosses the wire, and nothing reads it back — audio is a
## one-way client cosmetic (D-006 clause 2) and the simulation has no
## concept of it.
var record_audio := false
var _audio_events := []


func take_audio_events() -> Array:
	var out := _audio_events
	_audio_events = []
	return out


## Note something worth hearing. Squad-level by construction: the caller
## passes a cell and a weight, and there is nowhere in the entry for a
## per-soldier anything to live — a volley is one event, not thirty-six
## (D-024).
func note_audio(event: StringName, cell: int, magnitude: float = 1.0) -> void:
	if not record_audio:
		return
	_audio_events.append({"event": event, "cell": cell, "magnitude": magnitude})

var buildings := {}
var buildings_revealed: int = 0
var building_state_hash_checks: int = 0
var building_desync_count: int = 0
var last_building_desync := ""

# squad id -> StateCurve. The entirety of replicated world state.
var curves := {}

# squad id -> { "def_id": String, "alive": int, "shape": String,
# "spacing": float }. Told to us by the server, never guessed — see
# NetProtocol.encode_squad_info for why guessing was a real bug.
#
# LIVE squads only (D-025 part 3, D-026 criterion 8). A concealed squad is
# moved OUT of this dict and into `_ghosts`, not flagged in place — so
# every accessor that reads `composition` (composition_hash() above all)
# excludes ghosts by construction, not by remembering to check a flag.
# See `_ghosts` below.
var composition := {}

# squad id -> stale ghost entry: { "def_id", "alive", "shape", "spacing",
# "routed", "concealed_tick" }. Populated by SQUAD_CONCEAL
# (_handle_squad_conceal), cleared by the next SQUAD_INFO for that id
# (_handle_squad_info) — re-reveal replaces a ghost wholesale (D-025 part
# 3), never merges into it.
#
# Kept structurally separate from `composition` rather than a bit on the
# same dict, because the failure this guards against is specific: the
# server computes STATE_HASH over what a client can currently SEE, and a
# client that folded ghosts back into its own hash would be hashing a
# strictly larger set on every tick a squad is hidden. That would desync
# on a perfectly healthy system, constantly — the exact "a check that
# cries wolf gets muted" failure mode `NetProtocol.composition_hash`'s
# header comment was written to avoid. A stale ghost's `alive` also goes
# out of date while hidden (casualty events are visibility-gated too, so a
# squad fighting off-screen from this client keeps losing soldiers this
# client never hears about) — that staleness is correct and intended; it
# is what "last-known information" means. Re-reveal is what refreshes it.
var _ghosts := {}

## Terrain height sampler, taking (x, z) and returning a world Y.
##
## D-006's input tuple is (squad curve, formation shape, slot index,
## TERRAIN SAMPLE) — this is that fourth input. Left unset it means flat
## ground, which is correct for the headless load-test bots (they never
## draw anything) but wrong for anything that renders: soldiers derived at
## y=0 sit *inside* elevated terrain, which is exactly how it shipped and
## exactly what no numeric assertion caught.
##
## Must be pure, like everything else feeding Formation. When the server
## starts deriving soldier positions for combat in M2, it has to use an
## identical sampler or the two sides will disagree about who is standing
## where.
var terrain_sampler := Callable()

var welcomed := false
var curve_packets_received: int = 0
var unknown_packets: int = 0

# Desync accounting. A client that derives from different inputs than the
# server used is the failure D-006 cannot tolerate, so it is counted and
# surfaced rather than merely logged.
var state_hash_checks: int = 0
var desync_count: int = 0
var last_desync := ""

## Desync lines nobody has printed yet. Same drain-once shape as `felled`
## above: whoever surfaces them takes ownership, and a consumer that never
## drains (the bots, which report through their own VERDICT instead) costs
## nothing.
##
## This queue exists because the counters above were *write-only outside
## the capture path*. `client.gd`'s VERDICT line reads `desync_count`, and
## that line only ever runs in the screenshot path used by
## `just test-client`, which ends in `get_tree().quit()`. An interactive
## session never reaches it, so a GUI client stayed silent through zero
## desyncs and through a thousand alike — and a playtest told to "watch
## the console for any desync report" was judging a criterion that could
## not fail. That is D-022's audit finding wearing new clothes: silence
## read as success.
##
## Drain with `take_desync_reports()`; read `desync_summary()` for the
## totals, which are the source of truth. This queue is deliberately NOT:
## it stops filling at DESYNC_REPORT_LIMIT so a client that is desyncing
## every tick cannot flood a console (or grow an array without bound in a
## headless consumer that never drains). The counters keep counting past
## the cap, and the last queued line says so.
var _desync_reports := []

## Enough to see the first few and their ticks — after that the pattern is
## established and the number is what matters.
const DESYNC_REPORT_LIMIT := 5


func _note_desync(what: String) -> void:
	var reported := _desync_reports.size()
	if reported < DESYNC_REPORT_LIMIT:
		_desync_reports.append("client: DESYNC %s" % what)
	elif reported == DESYNC_REPORT_LIMIT:
		# Queued rather than dropped silently, so a console that goes quiet
		# after five lines says why instead of looking like the desyncs
		# stopped — which is the same silence-reads-as-success trap this
		# whole queue exists to close.
		_desync_reports.append(
			"client: DESYNC reporting capped at %d lines — the counters keep counting"
			% DESYNC_REPORT_LIMIT)


## Desync lines not yet surfaced, handing ownership to the caller (the
## GUI client prints them). Empty on a healthy client, which is the
## normal case and costs nothing.
func take_desync_reports() -> Array:
	var out := _desync_reports
	_desync_reports = []
	return out


## The state-sync accounting as one line a human can read at any moment.
##
## Phrased as a POSITIVE statement of what was checked, not as the absence
## of a complaint: "zero desyncs across the session" is only a meaningful
## pass if the checks are known to have run at all. Same reasoning as
## `test-load`'s verdict failing when zero comparisons ran.
func desync_summary() -> String:
	return "squads %d desync%s in %d checks, buildings %d desync%s in %d checks" % [
		desync_count, "" if desync_count == 1 else "s", state_hash_checks,
		building_desync_count, "" if building_desync_count == 1 else "s",
		building_state_hash_checks]

# --- M2 observation counters (D-026 criterion 9) ---------------------
#
# Additive only — nothing above this reads them, so they cannot change any
# existing behaviour. They exist because the load test's verdict must
# prove combat and fog were actually EXERCISED by a running system, not
# merely that the code paths compile: a run in which nobody died proves
# nothing about combat, and a run in which nothing was ever hidden proves
# nothing about fog (see bot_client.gd's _verdict_ok()).

## Total soldiers this client has seen subtracted from any squad's `alive`
## via SQUAD_COMBAT (D-024) — not a count of events, a count of soldiers,
## so a single lopsided battle counts for more than a single skirmish.
var casualties_applied: int = 0

## How many times a squad has moved from `composition` into `_ghosts` here
## (SQUAD_CONCEAL processed). One per squad per conceal, not per tick.
var conceal_events: int = 0

## How many times a squad that WAS a ghost has been re-revealed (SQUAD_INFO
## arriving for an id `_ghosts` currently holds). Deliberately does not
## count a squad's very first-ever SQUAD_INFO (never having been a ghost is
## not a reveal in D-025's sense) — see _handle_squad_info.
var reveal_events: int = 0

## The largest number of ghosts held simultaneously at any point in this
## client's lifetime — a high-water mark, not a running total, since
## `_ghosts.size()` itself already answers "how many right now".
var ghosts_peak: int = 0


func handle_packet(data: PackedByteArray) -> void:
	match NetProtocol.opcode_of(data):
		NetProtocol.S2C_WELCOME:
			_handle_welcome(data)
		NetProtocol.S2C_CURVE:
			_handle_curve(data)
		NetProtocol.S2C_SQUAD_INFO:
			_handle_squad_info(data)
		NetProtocol.S2C_SQUAD_COMBAT:
			_handle_squad_combat(data)
		NetProtocol.S2C_SQUAD_CONCEAL:
			_handle_squad_conceal(data)
		NetProtocol.S2C_STATE_HASH:
			_handle_state_hash(data)
		NetProtocol.S2C_NODES:
			for entry in NetProtocol.decode_nodes(data):
				nodes[int(entry["cell"])] = int(entry["kind"])
				revealed.append(int(entry["cell"]))
		NetProtocol.S2C_NODES_DEPLETED:
			for cell in NetProtocol.decode_nodes_depleted(data):
				if nodes.has(int(cell)):
					felled.append({"cell": int(cell), "kind": int(nodes[int(cell)])})
					nodes.erase(int(cell))
		NetProtocol.S2C_CHAT:
			_handle_chat(data)
		NetProtocol.S2C_MAP_SETTINGS:
			map_settings = NetProtocol.decode_map_settings(data)
		NetProtocol.S2C_LOBBY:
			# The whole seat list, replacing whatever was held before — the
			# server sends it entire on any change (see encode_lobby).
			lobby = NetProtocol.decode_lobby(data)
		NetProtocol.S2C_NOTICE:
			last_notice = NetProtocol.decode_notice(data)
			notices_received += 1
		NetProtocol.S2C_WALLET:
			wallet = NetProtocol.decode_wallet(data)
			wallet_updates += 1
		NetProtocol.S2C_TECH_STATE:
			var state := NetProtocol.decode_tech_state(data)
			epoch = int(state["epoch"])
			own_civ = StringName(state.get("civ", &""))
			techs.assign(state["lines"])
			tech_updates += 1
		NetProtocol.S2C_BUILDING_INFO:
			_handle_building_info(data)
		NetProtocol.S2C_BUILDING_STATE_HASH:
			_handle_building_state_hash(data)
		_:
			unknown_packets += 1


func _handle_welcome(data: PackedByteArray) -> void:
	var welcome := NetProtocol.decode_welcome(data)
	player = int(welcome["player"])
	space = TorusSpace.new(int(welcome["width"]), int(welcome["height"]), 1.0)
	squads = welcome["squads"]
	spawn_cells = welcome["spawns"]
	squad_cap = int(welcome.get("squad_cap", 0))
	note_server_tick(int(welcome.get("match_tick", 0)))
	welcomed = true


## The server's tick counter, whenever a message states it.
##
## At a fixed 10 Hz (D-020) the tick count IS the elapsed match time, so
## this is the whole clock — no separate timestamp on the wire, and no way
## for the clock and the simulation to disagree about how long the match
## has been running.
##
## Monotonic on purpose. Messages are reliable-ordered (D-042) so ticks
## should arrive in order, but a clock that could ever run BACKWARDS is
## worse than one that is briefly stale: a match timer that jumps back is
## read as a bug by every player who sees it.
func note_server_tick(tick: int) -> void:
	if tick > server_tick:
		server_tick = tick
		server_tick_at = Time.get_ticks_msec() / 1000.0


## Seconds since the match began, derived between messages.
##
## The same shape as construction progress and the production countdown:
## anchor on what the server last stated, run locally from there (D-003).
## Streaming a clock at 10 Hz would be a per-tick snapshot of a number
## both sides can compute.
func match_elapsed() -> float:
	if server_tick <= 0:
		return 0.0
	var stated := float(server_tick) / SquadSim.TICK_HZ
	return stated + maxf(Time.get_ticks_msec() / 1000.0 - server_tick_at, 0.0)


## The SIMULATION clock, estimated between messages — the time axis every
## curve keyframe lives on.
##
## The same anchor `match_elapsed()` reads (the server's tick is the whole
## clock, D-020), exposed under the name that says what it is FOR: sampling
## curves. The GUI client used to sample them at a wall clock started at
## its own node's _ready — behind the server by however long its terrain
## build took, so every sample CLAMPED. Positions still appeared to move
## (each fresh curve's first keyframe advanced, and the render-side easing smoothed
## the hops), which is exactly why nothing failed: the one number the
## clamp forced to zero was measured SPEED, and the only consumer that
## cared was animation. The walk clip never played in a live client, for
## any unit, from the day animation shipped until a supplied model's
## rest pose made "no walking" visible enough to chase.
func estimated_sim_time() -> float:
	return match_elapsed()


## The freshest curve START this client has received, and when it heard it.
## The render clock's anchor — see `render_time()`.
var newest_curve_time := 0.0
var newest_curve_at := 0.0


## The time to SAMPLE CURVES at, free-running between packets.
##
## Anchored to the curves themselves, not to the tick anchor, because a
## curve packet REPLACES the squad's whole curve (`_handle_curve`) and its
## first keyframe is the squad's position at SEND time. For a squad whose
## path is being re-emitted continuously that packet cadence was measured
## at ~0.25 s — so any render clock even slightly behind the freshest
## start spends most of each interval CLAMPED before it: the squad jumps
## to the new first keyframe, freezes, slides, and jumps again. Measured
## as a sawtooth (speed ramp 0.25 -> 2.07, snap to 0.00, repeat) and
## reported from play as teleporting. Anchoring on the newest start
## self-tunes to whatever the emission cadence is: the sample sits AT the
## freshest packet's start and interpolates forward into the future
## keyframes every movement curve carries.
##
## A squad whose curve is old is simply UNCHANGED (an idle squad's curve
## is never resent — that is D-003's whole bandwidth claim), and sampling
## past its end clamps to the spot it stands on, speed zero, idle clip:
## correct by construction.
## How far behind the freshest curve start the world is rendered. History
## is MERGED now, so standing behind the head costs nothing — and it is
## what absorbs packet jitter and the short spans emitted mid-wheel,
## which at the live head were a freeze at every bend.
const RENDER_BUFFER := 0.12


func render_time() -> float:
	if newest_curve_at <= 0.0:
		return match_elapsed()
	return newest_curve_time - RENDER_BUFFER + maxf(
		Time.get_ticks_msec() / 1000.0 - newest_curve_at, 0.0)


## Where `player` (1-based) starts, or (-1, -1) if the server sent no
## spawn table.
##
## Answered by calling the SERVER'S OWN function over the seat list this
## client already holds (`MatchState.spawn_index_in`), rather than by
## repeating its arithmetic here. The repeat is what went wrong: this used
## to compute `(player - 1) % spawn_cells.size()` under a comment saying it
## mirrored the server, and the server moved to the seat index — precisely
## because AI ids start at 1000 (D-051) and any modulo of a player id
## collides. Every AI then believed its home was some other player's spawn
## and founded its town hall there.
##
## Falls back to the old wrap when no seat list has arrived, which is the
## honest answer in that case: with nothing but a player id there is
## nothing better to say, and a test fixture that sends only a WELCOME
## still gets a usable cell.
func spawn_cell_of(player: int) -> Vector2i:
	if space == null or spawn_cells.is_empty() or player < 1:
		return Vector2i(-1, -1)
	var seats: Array = lobby.get("seats", [])
	var index := MatchState.spawn_index_in(seats, player, spawn_cells.size()) \
		if not seats.is_empty() else (player - 1) % spawn_cells.size()
	return space.from_index(spawn_cells[index])


## A curve update MERGES with what this client already holds when the two
## overlap in time, and REPLACES it when there is a gap.
##
## Both halves are load-bearing. A packet carries [send-time .. horizon]
## and a mover's curve is re-emitted continuously, so pure replacement
## leaves the client with no PAST — and a render clock has nowhere safe
## to stand: behind the newest start it clamps (measured as squads
## teleporting to each packet's first keyframe), at the live head it runs
## off the span's end between packets (measured as marching squads
## freezing mid-turn, where the emitted span is shortest). Keeping a few
## seconds of history lets the clock render just behind the newest start
## with neither artifact, at any emission cadence.
##
## The GAP case is D-025's truthful pop-in: a squad revealed after
## concealment arrives as a fresh curve well past its ghost's last
## keyframe, and BRIDGING that gap would interpolate the squad sprinting
## from where it was last seen — synthetic catch-up, exactly what D-025
## forbids. A gap means the client was not entitled to the missing
## stretch; the fresh curve stands alone.
const CURVE_MERGE_GAP := 0.35
const CURVE_KEEP_SECONDS := 4.0


static func merge_curve(existing: StateCurve, incoming: StateCurve) -> StateCurve:
	if existing == null or existing.is_empty() or incoming == null or incoming.is_empty():
		return incoming
	var t0 := incoming.start_time()
	if t0 > existing.end_time() + CURVE_MERGE_GAP:
		return incoming
	# The two packets must agree where the squad IS at the join. Curves
	# store CONTINUOUS UNWRAPPED axial points (state_curve.gd's header),
	# and a fresh packet can be normalised into a different lattice copy
	# than the chain this client has been extending — at a seam crossing
	# the same cell is a whole map period apart. A join that would move
	# the squad further than any unit can walk is that case, and the
	# honest answer is to replace rather than draw the sprint.
	if (existing.sample_axial(t0) - incoming.point_at(0)).length() > 4.0:
		return incoming
	var out := StateCurve.new()
	for i in range(existing.key_count()):
		var t := existing.time_at(i)
		if t >= t0:
			break
		if t < t0 - CURVE_KEEP_SECONDS:
			continue
		out.append_axial(t, existing.point_at(i))
	for i in range(incoming.key_count()):
		out.append_axial(incoming.time_at(i), incoming.point_at(i))
	return out


func _handle_curve(data: PackedByteArray) -> void:
	var decoded := NetProtocol.decode_curve(data)
	var curve := decoded["curve"] as StateCurve
	var id := int(decoded["id"])
	curves[id] = merge_curve(curves.get(id), curve)
	curve_packets_received += 1
	# The render clock's anchor (see `render_time`): the freshest START a
	# curve has arrived with is the closest thing this client has to "the
	# server's now, on the axis curves are actually sampled on".
	if not curve.is_empty() and curve.start_time() > newest_curve_time:
		newest_curve_time = curve.start_time()
		newest_curve_at = Time.get_ticks_msec() / 1000.0


func _handle_squad_info(data: PackedByteArray) -> void:
	for entry in NetProtocol.decode_squad_info(data):
		var def_id := String(entry["def_id"])
		# SPACING comes from the UnitDef rather than the wire, so there is
		# exactly one definition of it and no opportunity to drift (D-010).
		# SHAPE cannot: it is mutable squad state since D-058 — a player
		# orders it, and a gathering crew switches between working and
		# walking order — so resolving it from the def would pin every
		# squad to its spawn formation forever, and desync the client the
		# moment the server changed one, because shape is hashed.
		var def := UnitRoster.by_id(StringName(def_id))
		if def == null:
			push_error("ClientState: server referenced unknown UnitDef '%s'" % def_id)
			continue
		var id := int(entry["id"])
		# A reveal specifically means "this id was a ghost a moment ago" — a
		# squad's very first SQUAD_INFO (never concealed) is not a reveal in
		# D-025's sense, so this must be checked BEFORE _ghosts.erase(id)
		# below, and only counted when it was actually true.
		if _ghosts.has(id):
			reveal_events += 1

		# Learn ownership of squads produced after the welcome message.
		# Without this a trained unit belongs to nobody as far as the
		# client is concerned — not selectable, not orderable, and refused
		# if an order somehow reached the server. Bots stopped issuing any
		# orders at all once their founding crew was spent, because the
		# only squad they knew they owned no longer existed.
		if int(entry.get("owner", 0)) == player and not squads.has(id):
			squads.append(id)

		composition[id] = {
			"def_id": def_id,
			"alive": int(entry["alive"]),
			"shape": String(entry["shape"]),
			"spacing": def.formation_spacing,
			# Kept so the client can tell an ally's squad from an enemy's
			# (D-050). Deliberately NOT part of composition_hash, which
			# builds its own entry list from named fields — adding a key
			# here cannot drift into what the desync check compares.
			"owner": int(entry.get("owner", 0)),
			# D-076: which tier the squad occupies. Also not part of
			# composition_hash, for the same reason owner is not — it is a
			# fact the client is TOLD explicitly (never inferred), so a
			# lagging hash comparison has nothing to disagree about.
			"tier": int(entry.get("tier", 0)),
			# The player's ordered facing and width (D-20260819) — soldier
			# positions derive from both, and both ARE hashed, so these
			# must be exactly the server's integers, never resolved
			# locally (the D-058/D-065 lesson).
			"facing": int(entry.get("facing", -1)),
			"files": int(entry.get("files", 0)),
			"stance": int(entry.get("stance", 0)),
			"exploring": bool(entry.get("exploring", false)),
		}
		# A squad this is describing is live, full stop — whether this is
		# its first-ever SQUAD_INFO or a reveal after concealment. Reveal
		# replaces a ghost wholesale (D-025 part 3): the stale entry above
		# is simply gone, never merged with what just arrived.
		_ghosts.erase(id)


## SQUAD_COMBAT (D-024): the server's only channel for changing `alive`
## after spawn. Applied straight into `composition`, which is exactly what
## composition_hash() reads — so a client that received this stays in
## agreement with the server's next STATE_HASH, and one that missed it
## (or a resend after packet loss) would visibly desync instead.
func _handle_squad_combat(data: PackedByteArray) -> void:
	var decoded := NetProtocol.decode_squad_combat(data)
	for event in (decoded["events"] as Array):
		var id := int(event["id"])
		if not composition.has(id):
			# A casualty event for a squad this client was never described
			# is a protocol gap, not a thing to silently guess at — the
			# same "supplying identical inputs is a protocol obligation"
			# point D-006's 2026-07-29 note makes about SQUAD_INFO.
			push_error("ClientState: casualty event for unknown squad %d" % id)
			continue
		var previous_alive := int(composition[id]["alive"])
		var new_alive := int(event["alive"])
		# Counted in soldiers, not events, and only the decrease — a squad
		# cannot un-die, so `alive` only ever falls here, but staying
		# defensive costs nothing and this is exactly the number the load
		# test's verdict needs to prove combat did more than resolve to a
		# no-op (D-026 criterion 9).
		if new_alive < previous_alive:
			casualties_applied += previous_alive - new_alive
			# Where men FELL, for the corpse layer
			# (D-20260819-a-casualty-is-visible). Recorded only when a
			# renderer has said it will drain the list — the load-test
			# bots run this class too, and an unread list would grow for
			# the length of a run. `fell` is the wire's word that these
			# men died by violence rather than being spent founding a
			# town (D-20260823-the-opening-is-a-crew-and-a-general) or
			# wiped by a disconnect (D-033); slots
			# [after, before) are the men the restamp removes (D-024).
			if record_corpses and bool(event.get("fell", false)):
				_casualty_sites.append({
					"id": id, "before": previous_alive, "after": new_alive,
				})
			# The volley (#344). ONE event for the whole exchange, not one
			# per man: D-024 resolves combat as aggregate arithmetic over
			# a squad, and `fell` here is already a COUNT. Gated on the
			# same `fell` byte the corpses are, so men spent founding a
			# town or wiped by a disconnect make no battle noise.
			if record_audio and bool(event.get("fell", false)):
				var lost := previous_alive - new_alive
				var size := int(composition.get(id, {}).get("size", previous_alive))
				note_audio(&"combat_volley", space.index(squad_cell(id, 0.0)) if space != null else -1,
					AudioCue.volley_magnitude(lost, maxi(size, 1)))
		composition[id]["alive"] = new_alive
		composition[id]["routed"] = bool(event["routed"])

		# A squad that reaches zero is no longer ours to command. Without
		# this, `owns()` keeps saying yes for the rest of the match: the
		# GUI offers a dead squad for selection, and the bots go on
		# ordering corpses. The server refuses either way — it reads
		# ownership from the sim — but a client that knows better should
		# not be sending the order at all.
		if new_alive <= 0:
			var index := squads.find(id)
			if index >= 0:
				squads.remove_at(index)


## SQUAD_CONCEAL (D-025 part 3): explicit notice that a squad left this
## client's vision this tick. The squad's current composition moves
## wholesale from `composition` into `_ghosts` — not copied, not flagged
## in place — so every live accessor (composition_hash, alive_of,
## squads_awaiting_composition, ...) stops seeing it in the same tick this
## is processed, by construction rather than by remembering to check a
## flag.
##
## Its curve in `curves` is left untouched: that IS "keeping the
## last-known curve" (D-025 part 3). The server stops sending curve
## updates for a concealed squad the moment it drops out of visible_to(),
## so nothing further will move it — it simply holds its last delivered
## position, which is exactly what a stale ghost should show.
func _handle_squad_conceal(data: PackedByteArray) -> void:
	var decoded := NetProtocol.decode_squad_conceal(data)
	for raw_id in (decoded["squad_ids"] as Array):
		var id := int(raw_id)
		if not composition.has(id):
			# A conceal for a squad this client had no live composition for
			# is a protocol gap, not a thing to silently shrug at — same
			# posture as the unknown-squad check in _handle_squad_combat.
			push_error("ClientState: conceal event for squad %d with no known live composition" % id)
			continue
		var entry = composition[id]
		entry["concealed_tick"] = int(decoded["tick"])
		_ghosts[id] = entry
		composition.erase(id)
		conceal_events += 1
		if _ghosts.size() > ghosts_peak:
			ghosts_peak = _ghosts.size()


## True if `squad` is a stale ghost right now — concealed, showing its
## last-known composition and curve rather than live state. Exists so a
## renderer can tell a ghost from a live squad (D-025 part 3); the shipped
## answer is that it draws neither the squad nor its minimap dot (D-099),
## but that is the client's decision to make and not this file's.
##
## Nothing in this file's own live accounting (composition_hash, alive_of,
## squads_awaiting_composition, derive_all) ever consults this — they
## exclude ghosts by construction because `composition` simply doesn't
## contain them.
func is_ghost(squad: int) -> bool:
	return _ghosts.has(squad)


## How many living squads this player has, counted the way the SERVER
## counts them for the squad cap (`MatchState.has_squad_capacity`):
## this player's own, still alive, gatherers included.
##
## Deliberately not `squads.size()`, which only ever grows — it is the
## list of ids this client has been told it owns, and nothing removes a
## squad from it when that squad dies. A HUD reading "41/40" is what that
## would produce, and it would look like a broken cap rather than a
## miscount.
func living_squad_count() -> int:
	var n := 0
	for id in composition:
		var entry: Dictionary = composition[id]
		if int(entry.get("owner", 0)) == player and int(entry.get("alive", 0)) > 0:
			n += 1
	return n


## Squad ids currently held as ghosts.
func ghost_squad_ids() -> Array:
	return _ghosts.keys()


## A ghost's last-known composition (alive, shape, spacing, and the tick
## it was concealed on) — {} if `squad` isn't currently a ghost.
## Deliberately separate from alive_of()/shape_of()/spacing_of(), which
## read `composition` and are live-only by construction.
func ghost_info(squad: int) -> Dictionary:
	return _ghosts.get(squad, {})


## Squad ids this client currently treats as live — exactly the set
## composition_hash() covers. One explicit answer to "how many squads does
## this client think are live", rather than every future caller
## re-deriving it from composition.keys() and risking forgetting ghosts
## are stored elsewhere.
func live_squad_ids() -> Array:
	return composition.keys()


func _handle_state_hash(data: PackedByteArray) -> void:
	var decoded := NetProtocol.decode_state_hash(data)
	state_hash_checks += 1
	# Re-anchors the match clock. This message already carries the server's
	# tick and already arrives regularly, so the timer costs no bandwidth
	# of its own and cannot drift away from the simulation.
	note_server_tick(int(decoded["tick"]))
	var ours := composition_hash()
	var theirs := int(decoded["hash"])
	if ours != theirs:
		desync_count += 1
		last_desync = "tick %d: client composition hash %d != server %d over %d squads" % [
			int(decoded["tick"]), ours, theirs, composition.size()]
		_note_desync(last_desync)


## BUILDING_INFO (D-029/D-030). Buildings are **persistent-explored**:
## once a client has been shown one it keeps it forever, with its state
## frozen at last-known while out of vision. That is deliberately NOT
## D-025's ghosting, which exists because a squad moves while unseen —
## a building does not, so there is no positional staleness to represent
## and no reason to stop knowing it is there.
func _handle_building_info(data: PackedByteArray) -> void:
	for entry in NetProtocol.decode_building_info(data):
		var id := int(entry["id"])
		if not buildings.has(id):
			buildings_revealed += 1
		# Worth HEARING (#344), decided from what changed rather than
		# from a new message: the wire already says everything audio
		# needs, and inventing a packet for it would be the second
		# channel #344 forbids and D-004 forbids generally.
		#
		# Fog is not consulted HERE — `AudioCue` does that, from the one
		# vision query, and doing it in two places is how the two come to
		# disagree. This only records that something happened.
		if record_audio:
			var was: Dictionary = buildings.get(id, {})
			var had := not was.is_empty()
			var was_done := float(was.get("progress", 0.0)) >= 1.0
			var now_done := float(entry["progress"]) >= 1.0
			var cell := int(entry["cell"])
			if bool(entry["destroyed"]) and not bool(was.get("destroyed", false)):
				note_audio(&"building_destroyed", cell)
			elif had and now_done and not was_done:
				note_audio(&"building_complete", cell)
			elif not had and not now_done:
				note_audio(&"building_placed", cell)
		buildings[id] = {
			"def_id": String(entry["def_id"]),
			"owner": int(entry["owner"]),
			"cell": int(entry["cell"]),
			"progress": float(entry["progress"]),
			"destroyed": bool(entry["destroyed"]),
			# For the selection panel (health bar, production queue).
			# Neither is hashed — see the hash's own comment.
			"health_fraction": float(entry.get("health_fraction", 1.0)),
			"head_remaining": float(entry.get("head_remaining", 0.0)),
			"queue": entry.get("queue", []),
			"rally": int(entry.get("rally", 0)),
			# Everything below was DECODED and then thrown away here.
			#
			# This dictionary is rebuilt field by field rather than taking
			# the decoded entry wholesale, so a field added to the protocol
			# reaches the client and then silently stops at this line. The
			# renderer's `info.get("facing", 0)` and
			# `info.get("gate_open", false)` were therefore reading their
			# DEFAULTS on every building, forever — nothing failed, nothing
			# logged, and the wire carried the right values the whole time.
			#
			# Symptoms it was causing, none of which pointed here: walls
			# built at their cell centres instead of their true offsets,
			# which along a diagonal reads as a staircase while the
			# placement ghost (which never crosses the wire) looks perfect;
			# every wall drawn at facing 0; and a gate that could be opened,
			# could be walked through, and never looked open.
			#
			# This is D-065's rule almost word for word — "a decision entry
			# saying a field is on the wire is not evidence that it is" —
			# and the answer is the same: open the code that CONSUMES it and
			# look for the field, not just the encoder.
			"facing": int(entry.get("facing", 0)),
			"offset_x": float(entry.get("offset_x", 0.0)),
			"offset_z": float(entry.get("offset_z", 0.0)),
			"gate_open": bool(entry.get("gate_open", false)),
			"gate_mode": int(entry.get("gate_mode", 0)),
		}


## Its own hash, checked against its own message (D-030).
##
## The set matters more than the arithmetic: this covers every building
## EVER shown to this client, and the server hashes the same ever-revealed
## set. Hashing "what I can see now" on one side and "everything I have
## seen" on the other would compare differently-shaped sets and fire on a
## perfectly healthy system — the same trap D-025 part 3 documents for
## squads, wearing different clothes.
func _handle_building_state_hash(data: PackedByteArray) -> void:
	var decoded := NetProtocol.decode_building_state_hash(data)
	building_state_hash_checks += 1
	var ours := building_hash()
	var theirs := int(decoded["hash"])
	if ours != theirs:
		building_desync_count += 1
		last_building_desync = "tick %d: client building hash %d != server %d over %d buildings" % [
			int(decoded["tick"]), ours, theirs, buildings.size()]
		_note_desync(last_building_desync)


## Hash of every building this client knows about. Must produce the same
## entry shape as BuildingSim.composition_entries, which is why health and
## progress are absent from both: they vary continuously and a client
## legitimately lags a tick.
func building_hash() -> int:
	var entries := []
	for id in buildings:
		var info: Dictionary = buildings[id]
		entries.append({
			"id": id,
			"alive": 0 if bool(info["destroyed"]) else 1,
			"shape": String(info["def_id"]),
			"spacing": float(info["owner"]),
		})
	return NetProtocol.composition_hash(entries)


## Put a gatherer squad to work on a node (D-028). The server owns the
## rules about which squads can gather and what a cell holds; this only
## avoids sending an order for a squad we do not own.
func encode_gather(squad: int, cell: Vector2i) -> PackedByteArray:
	if space == null or not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_gather(squad, space.index(cell))


## Build order for the server (D-031). The server re-checks everything —
## ownership, who may build what, whether the ground is buildable — so
## this only avoids sending obvious nonsense.
func encode_build(squad: int, def_id: String, cell: Vector2i, facing: int = 0,
		offset: Vector2 = Vector2.ZERO) -> PackedByteArray:
	if space == null or not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_build(squad, def_id, space.index(cell), facing, offset)


## As above, but APPENDS to the squad's build queue instead of replacing
## it (D-076's drag-to-build-a-line tool) — see `NetProtocol.C2S_ORDER_BUILD_QUEUE`.
func encode_build_queue(squad: int, def_id: String, cell: Vector2i, facing: int = 0,
		offset: Vector2 = Vector2.ZERO) -> PackedByteArray:
	if space == null or not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_build_queue(squad, def_id, space.index(cell), facing, offset)


func owns(squad: int) -> bool:
	return squads.has(squad)


func known_squad_ids() -> Array:
	return curves.keys()


## Where a squad is now, as far as this client can tell — sampled from the
## curve, not received.
func squad_cell(squad: int, now: float) -> Vector2i:
	if space == null or not curves.has(squad):
		return Vector2i.ZERO
	return (curves[squad] as StateCurve).sample_cell(now, space)


func squad_world_position(squad: int, now: float) -> Vector3:
	if space == null or not curves.has(squad):
		return Vector3.ZERO
	return (curves[squad] as StateCurve).sample_world(now, space)


## Ground speed in world units per second, from the curve alone (D-065).
##
## Feeds the walk cycle's playback rate, so footfalls match travel instead of
## soldiers skating. Pure: a function of the curve and the time, holding no
## state and reading nothing it has to remember — which is what keeps animation
## inside D-006 clause 1.
##
## Differences the CONTINUOUS AXIAL samples, not `squad_world_position`. Those
## are wrapped (`sample_world` applies fposmod), so a squad crossing a seam
## would appear to cross the whole map in one interval and its soldiers would
## sprint on the spot. The axial-to-world scaling is linear, so it applies to
## the delta unchanged — the wrap is the only nonlinear step, and skipping it is
## exactly the point. The recurring torus tax D-008 warns about.
func squad_speed(squad: int, now: float, interval: float = 0.2) -> float:
	if space == null or not curves.has(squad) or interval <= 0.0:
		return 0.0
	var curve := curves[squad] as StateCurve
	var before := curve.sample_axial(now - interval)
	var after := curve.sample_axial(now)
	var delta := after - before
	var world := Vector2(
		space.hex_size * TorusSpace.SQRT_3 * (delta.x + delta.y * 0.5),
		space.hex_size * 1.5 * delta.y)
	return world.length() / interval


## Composition accessors. These are the values fed to Formation, so they
## are also exactly what composition_hash() hashes — the check therefore
## verifies what the client actually derives from, not merely that a
## message round-tripped intact.
func alive_of(squad: int) -> int:
	return int(composition[squad]["alive"]) if composition.has(squad) else 0


func shape_of(squad: int) -> String:
	return String(composition[squad]["shape"]) if composition.has(squad) else ""


func spacing_of(squad: int) -> float:
	return float(composition[squad]["spacing"]) if composition.has(squad) else 0.0


## Not hashed (see composition_hash below) — routing is display/behaviour
## state, not part of what "the same composition" means for desync
## purposes, so a client that hasn't heard about a rout yet still agrees
## with the server on strength.
func stance_of(squad: int) -> int:
	return int(composition[squad].get("stance", 0)) if composition.has(squad) else 0


## Whether this squad is hunting fog (#120). Read off the wire rather than
## remembered when the order was sent: the server owns the mode, and a
## button lit from a local guess would keep claiming the squad was
## exploring after a rout cancelled it.
func is_exploring(squad: int) -> bool:
	return bool(composition[squad].get("exploring", false)) if composition.has(squad) else false


func facing_of(squad: int) -> int:
	return int(composition[squad].get("facing", -1)) if composition.has(squad) else -1


func files_of(squad: int) -> int:
	return int(composition[squad].get("files", 0)) if composition.has(squad) else 0


## The mirror of SquadSim.facing_angle_of — the SAME reconstruction from
## the SAME wire integer, so the two machines' derived soldiers cannot
## disagree by a bit (D-20260819-facing-and-width-are-orders).
func facing_angle_of(squad: int) -> float:
	var q := facing_of(squad)
	return NAN if q < 0 else TAU * float(q) / 4096.0


func routed_of(squad: int) -> bool:
	return bool(composition[squad].get("routed", false)) if composition.has(squad) else false


func tier_of(squad: int) -> int:
	return int(composition[squad].get("tier", 0)) if composition.has(squad) else 0


## The world-unit height added on top of ground for a squad standing at
## tier 1 (D-076): the `top_height` of whichever `walkable_top` building
## currently occupies its cell, or 0 if it is not actually standing on one
## (should not happen once tier is correct, but degrades to ground height
## rather than guessing at a number).
##
## Linear over `buildings`, same shape and justification as
## `BuildingSim.building_at`: orders of magnitude fewer buildings than
## cells, and this only runs at all for the rare tier-1 squad — every
## ordinary ground squad skips it entirely.
func walkway_height_of(squad: int, now: float) -> float:
	if tier_of(squad) != 1 or space == null or not curves.has(squad):
		return 0.0
	var cell := space.index(curves[squad].sample_cell(now, space))
	for info in buildings.values():
		if bool(info.get("destroyed", false)) or int(info["cell"]) != cell:
			continue
		var def := BuildingSim.def_by_id(StringName(info["def_id"]))
		if def != null and def.walkable_top:
			return def.top_height
	return 0.0


## Wraps `terrain_sampler` with the wall-top bump for a tier-1 squad, or
## returns it unchanged for a ground one (D-076). `Formation` itself never
## learns a tier exists — this is the "call site passes the right height
## in" half of D-006 compliance, not a new branch inside the pure function.
func _sampler_for(squad: int, now: float) -> Callable:
	if not terrain_sampler.is_valid() or tier_of(squad) != 1:
		return terrain_sampler
	var bump := walkway_height_of(squad, now)
	var base := terrain_sampler
	return func(x, z): return base.call(x, z) + bump


## The map's TERRAIN passability, one byte per cell, 1 where a squad could
## walk (#97). Empty until the client has built its terrain, which means
## "fully open" — the same convention as `SquadSim.is_passable` — so a
## client that has not generated a map yet derives exactly the geometry it
## always did.
##
## TERRAIN only, and the distinction is what keeps client and server
## deriving the same man in the same place. The server stamps living
## buildings out of its own copy (`Server._refresh_passability`) so squads
## walk around a town hall; a client under fog cannot know that set, so a
## soldier clamp built on it would put the two sides in different places —
## the M1 desync D-022's audit block describes, rebuilt from parts. Water
## and rock are what #97 is about, they come from `MapSettings` over the
## wire (D-049), and both sides derive them from the identical numbers.
var terrain_passable := PackedByteArray()


## Hash of the composition this client will derive from, in the format
## SquadSim produces for the server side. Compared on every STATE_HASH.
##
## Iterates `composition` only — LIVE squads, by construction, since
## ghosts are never stored there (see `_ghosts` above). The server hashes
## exactly `visible_to(player)`, so this must hash exactly what this
## client currently treats as live, or the two sides compare different
## sets and the check fires on a healthy system (D-026 criterion 8).
func composition_hash() -> int:
	var entries := []
	for id in composition:
		entries.append({
			"id": id,
			"alive": alive_of(id),
			"shape": shape_of(id),
			"spacing": spacing_of(id),
			"facing": facing_of(id),
			"files": files_of(id),
		})
	return NetProtocol.composition_hash(entries)


## Derive one squad's soldier transforms (D-006). Nothing here came off
## the wire — the curve did, the positions are recomputed.
##
## Returns empty for a squad whose composition hasn't arrived. Guessing a
## default here is exactly the bug this signature was changed to prevent:
## a plausible-looking wrong answer is worse than none, because it silently
## puts every soldier in the wrong place.
func soldier_transforms(squad: int, now: float) -> Array[Transform3D]:
	var empty: Array[Transform3D] = []
	if space == null or not curves.has(squad) or not composition.has(squad):
		return empty
	return Formation.soldier_transforms(
		curves[squad], now, alive_of(squad), shape_of(squad), spacing_of(squad), space,
		_sampler_for(squad, now), terrain_passable, files_of(squad),
		facing_angle_of(squad))


## As above, but drawing at most `max_soldiers` of them — the render LOD
## tier (D-045).
##
## Deliberately a SEPARATE entry point rather than a parameter on
## soldier_transforms, so that every existing caller keeps full detail by
## construction and nothing acquires a reduced view of a squad by
## accident. The only caller is the renderer; `composition_hash` and the
## desync check never come near it, which is what keeps this cosmetic
## (D-006 clause 2, D-012).
func soldier_transforms_lod(squad: int, now: float, max_soldiers: int) -> Array[Transform3D]:
	var empty: Array[Transform3D] = []
	if space == null or not curves.has(squad) or not composition.has(squad):
		return empty
	return Formation.soldier_transforms_sampled(
		curves[squad], now, alive_of(squad), shape_of(squad), spacing_of(squad), space,
		_sampler_for(squad, now), max_soldiers, terrain_passable,
		files_of(squad), facing_angle_of(squad))


## Total soldiers this client would be drawing — the number that makes
## D-006's 40x claim concrete, since none of them cost bandwidth.
##
## Timed, because D-006 trades BANDWIDTH for CLIENT CPU and only one half
## of that trade had ever been measured. Every soldier not sent is a
## soldier the client must place itself, every frame, from the squad
## curve — so "costs zero bandwidth" is only good news if the derivation
## fits a frame.
func derive_all(now: float) -> int:
	var started := Time.get_ticks_usec()
	var total := 0
	for id in curves:
		total += soldier_transforms(id, now).size()
	last_derive_usec = Time.get_ticks_usec() - started
	total_derive_usec += last_derive_usec
	derive_calls += 1
	soldiers_derived_total += total
	return total


## Microseconds spent in the last derive_all, and the running totals
## behind the per-soldier figure M4 reports.
var last_derive_usec: int = 0
var total_derive_usec: int = 0
var derive_calls: int = 0
var soldiers_derived_total: int = 0


## Mean microseconds to place ONE soldier. The number D-006's trade is
## actually settled on: multiply by the soldiers on screen to get the
## per-frame cost of not having received them.
func mean_usec_per_soldier() -> float:
	if soldiers_derived_total <= 0:
		return 0.0
	return float(total_derive_usec) / float(soldiers_derived_total)


## Squads whose curve has arrived but whose composition has not — LIVE
## composition, specifically: a ghost has a curve and no entry in
## `composition` by design (it moved to `_ghosts` on conceal), and that is
## not the same "never described" gap this is meant to catch, so ghosts
## are excluded here too. Should otherwise settle to zero; a persistent
## non-zero value means the server is replicating something it never
## described.
func squads_awaiting_composition() -> int:
	var missing := 0
	for id in curves:
		if not composition.has(id) and not _ghosts.has(id):
			missing += 1
	return missing


## Build an order for the server. Returns an empty array if the client
## doesn't own the squad — the server enforces this too (D-002), but
## sending a knowingly invalid order is just noise.
func encode_order(squad: int, destination: Vector2i) -> PackedByteArray:
	if space == null or not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_move(squad, space.index(destination))


## Advance but halt on contact (D-034). Same ownership guard as above —
## the server enforces it too, but sending a knowingly invalid order is
## just noise on the wire.
func encode_attack_move(squad: int, destination: Vector2i) -> PackedByteArray:
	if space == null or not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_attack_move(squad, space.index(destination))


## Halt where the squad stands. Carries no destination: where "here" is
## belongs to the server, since this client's view of the position lags
## replication by up to a tick.
func encode_stop(squad: int) -> PackedByteArray:
	if not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_stop(squad)


## Hunt fog until told to stop (#120). Carries no destination for the same
## reason `encode_stop` does not: the destination is the server's to pick,
## over and over, and picking it is the whole of what is being asked for.
##
## Ownership is checked HERE like every other order, so the GUI client and
## the load-test bots get the same refusal from one place.
func encode_explore(squad: int) -> PackedByteArray:
	if not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_explore(squad)


# --- lobby (D-048) ----------------------------------------------------

## The lobby as the server last described it: {admin: int, seats: Array}.
## Empty until the first S2C_LOBBY arrives, which is also how the client
## knows whether it is in a lobby at all.
var lobby := {}


## True only while the match has not started. The seat list survives the
## whole match (colours, teams), so its presence says nothing about the
## phase — inferring it from that drew the lobby over a live game.
func in_lobby() -> bool:
	if lobby.get("seats", []).is_empty():
		return false
	return int(lobby.get("phase", 0)) == 0


## Forget the match, keep the session (D-075).
##
## Called when the server puts everyone back in the lobby. Everything
## here is state ABOUT A WORLD that no longer exists — squads, curves,
## ghosts, buildings, resource nodes, the map itself — and carrying any of
## it into the next match would draw the last one's armies on the new
## one's terrain. The ids are reused, too: both sims mint entities from an
## array length, so match two's squad 0 is a different squad 0.
##
## Three things deliberately SURVIVE:
##
## - the seat list and chat, which belong to the lobby and not to a match;
## - every diagnostic counter (desyncs, casualties, reveals), because they
##   describe this CLIENT's whole session. `test-load` and `test-client`
##   read them as run totals, and zeroing them mid-run would make a
##   verdict report a quiet client rather than a client that had been
##   busy;
## - `player`, which the server does not reissue.
##
## `terrain_sampler` goes because it closes over terrain chunks the client
## is about to free — left in place it would sample freed nodes, and the
## symptom would be soldiers at wrong heights rather than a crash.
## `terrain_passable` goes with it: it describes the map just left, and the
## next match's may be a different size, so keeping it would clamp soldiers
## against another world's coastline.
func leave_match() -> void:
	welcomed = false
	space = null
	map_settings = {}
	terrain_sampler = Callable()
	terrain_passable = PackedByteArray()

	squads = PackedInt32Array()
	spawn_cells = PackedInt32Array()
	curves.clear()
	composition.clear()
	_ghosts.clear()
	buildings.clear()
	nodes.clear()
	felled.clear()
	revealed.clear()
	wallet = PackedInt32Array()

	server_tick = 0
	server_tick_at = 0.0
	newest_curve_time = 0.0
	newest_curve_at = 0.0


## A player's civ as the lobby last described it, or "" if unknown.
##
## Needed so the HUD can name what a building will actually produce: a
## barracks offers ARCHETYPES (D-047), and which troops those are depends
## on who is asking. Resolving through the seat list means the client can
## only ever name its own civ's units — it has no way to name another's,
## which is D-046 criterion 4 holding structurally rather than by care.
func civ_of(who: int) -> StringName:
	for seat in lobby.get("seats", []):
		if int(seat["player"]) == who:
			var seated := StringName(seat.get("civ", ""))
			# A seat exists but Random is unresolved until the match
			# starts (D-048), so an empty seat civ still falls through to
			# what the server told us about OURSELVES.
			if seated != &"" or who != player:
				return seated
	# One function, two sources, and the fallback is narrower than the
	# rule: the server names only THIS player's civ, so this can never
	# answer for anybody else and D-046 criterion 4 still holds
	# structurally — a client has no way to name another civ's units.
	return own_civ if who == player else &""


## This client's own seat index, or -1.
func my_seat() -> int:
	var seats: Array = lobby.get("seats", [])
	for i in range(seats.size()):
		if String(seats[i]["kind"]) == "human" and int(seats[i]["player"]) == player:
			return i
	return -1


func is_admin() -> bool:
	return player > 0 and int(lobby.get("admin", 0)) == player


## The sandbox's full-world-visibility flag, as the SERVER reports it
## (D-20260821). The client derives its terrain fog locally (D-106), so
## this half has to know too — a server sending everything still leaves
## the ground black otherwise.
func reveal_all() -> bool:
	return bool(lobby.get("reveal_all", false))


## The world's concrete terrain parameters, once the server has sent them
## (D-049). Empty until then — and until then there is no world to draw,
## which is exactly the point: the client used to generate terrain on
## connect, before anybody had chosen a size, a seed or a shape.
var map_settings := {}


func has_map() -> bool:
	return not map_settings.is_empty()


## The generator the server is using. One conversion, shared, so the two
## sides cannot disagree about where the water is.
func terrain_from_settings() -> TerrainGen:
	return MapSettings.from_dict(map_settings).to_terrain()


## Chat backlog, oldest first (D-050). Bounded, because a long match
## should not grow this without limit.
var chat_log: Array = []
const CHAT_HISTORY := 40


func _handle_chat(data: PackedByteArray) -> void:
	var message := NetProtocol.decode_chat(data)
	chat_log.append(message)
	if chat_log.size() > CHAT_HISTORY:
		chat_log = chat_log.slice(chat_log.size() - CHAT_HISTORY)


## Squads on this player's side — its own, plus any ally's it can see
## (D-050).
##
## Derived from the lobby's seat list, which the client already holds and
## which keeps its teams after the match starts. That avoids a second
## message carrying the same fact, and avoids the client inventing its own
## idea of who is allied with whom.
func friendly_squads() -> Array:
	var out := []
	for squad in squads:
		out.append(squad)
	if lobby.is_empty():
		return out

	var my_team := _team_of(player)
	if my_team == 0:
		return out
	for id in composition:
		var owner := int(composition[id].get("owner", 0))
		if owner != player and _team_of(owner) == my_team and not out.has(id):
			out.append(id)
	return out


## Whether two players are on the same side (D-050).
##
## Mirrors `MatchState.are_allied` exactly, including the part that is
## easy to get wrong: team 0 means FREE-FOR-ALL, so two players both on
## team 0 are NOT allies — they are each their own side. Treating 0 like
## any other team would make every player in an FFA everybody's friend.
func are_allied(a: int, b: int) -> bool:
	if a == b:
		return true
	var team_a := _team_of(a)
	return team_a != 0 and team_a == _team_of(b)


func _team_of(who: int) -> int:
	for seat in lobby.get("seats", []):
		if int(seat["player"]) == who:
			return int(seat.get("team", 0))
	return 0


## The colour that identifies a player's units and buildings (D-052).
##
## Derived from the SEAT ORDER the server sent, so every client agrees
## without a message dedicated to colour — and so a player's colour is
## stable for the whole match rather than depending on who happens to be
## on screen.
func colour_of(player: int) -> Color:
	var seats: Array = lobby.get("seats", [])
	for i in range(seats.size()):
		if int(seats[i]["player"]) == player:
			return PlayerColours.of_index(i)
	# Before the seat list arrives, or for a player not in it: fall back
	# to something stable rather than flickering as the list loads.
	return PlayerColours.of_index(maxi(player - 1, 0))
