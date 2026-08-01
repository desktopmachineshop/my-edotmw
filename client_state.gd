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

## Buildings this client has ever been shown, by wire id (D-029/D-030).
## Never pruned: buildings are persistent-explored, so leaving vision
## freezes what is known rather than forgetting it.
## This player's own four resource totals (D-028). There is nowhere to
## put anyone else's, deliberately: wallets are private, so the protocol
## never carries another player's.
var wallet := PackedInt32Array()
var wallet_updates: int = 0

## The most recent thing the server refused, and why (D-002 owns the
## rules, so it owns the explanation).
var last_notice := ""
var notices_received: int = 0

## Resource nodes: cell index -> ResourceKind. Sent once at join; the
## client draws where resources are, never how much is left.
var nodes := {}

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
		NetProtocol.S2C_NOTICE:
			last_notice = NetProtocol.decode_notice(data)
			notices_received += 1
		NetProtocol.S2C_WALLET:
			wallet = NetProtocol.decode_wallet(data)
			wallet_updates += 1
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
	welcomed = true


## Where `player` (1-based) starts, or (-1, -1) if the server sent no
## spawn table. Mirrors server.gd's own wrap — players are numbered from
## 1, spawn points indexed from 0 — so both sides answer this the same
## way instead of each doing its own arithmetic.
func spawn_cell_of(player: int) -> Vector2i:
	if space == null or spawn_cells.is_empty() or player < 1:
		return Vector2i(-1, -1)
	return space.from_index(spawn_cells[(player - 1) % spawn_cells.size()])


func _handle_curve(data: PackedByteArray) -> void:
	var decoded := NetProtocol.decode_curve(data)
	curves[int(decoded["id"])] = decoded["curve"]
	curve_packets_received += 1


func _handle_squad_info(data: PackedByteArray) -> void:
	for entry in NetProtocol.decode_squad_info(data):
		var def_id := String(entry["def_id"])
		# Shape and spacing come from the UnitDef rather than the wire, so
		# there is exactly one definition of them and no opportunity for
		# client and server to drift (D-010).
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
		# orders at all once their founding party was spent, because the
		# only squad they knew they owned no longer existed.
		if int(entry.get("owner", 0)) == player and not squads.has(id):
			squads.append(id)

		composition[id] = {
			"def_id": def_id,
			"alive": int(entry["alive"]),
			"shape": def.formation_shape,
			"spacing": def.formation_spacing,
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
## renderer can draw a ghost differently later (D-025 part 3); nothing in
## this file's own live accounting (composition_hash, alive_of,
## squads_awaiting_composition, derive_all) ever consults this — they
## exclude ghosts by construction because `composition` simply doesn't
## contain them.
func is_ghost(squad: int) -> bool:
	return _ghosts.has(squad)


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
	var ours := composition_hash()
	var theirs := int(decoded["hash"])
	if ours != theirs:
		desync_count += 1
		last_desync = "tick %d: client composition hash %d != server %d over %d squads" % [
			int(decoded["tick"]), ours, theirs, composition.size()]


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
		buildings[id] = {
			"def_id": String(entry["def_id"]),
			"owner": int(entry["owner"]),
			"cell": int(entry["cell"]),
			"progress": float(entry["progress"]),
			"destroyed": bool(entry["destroyed"]),
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
func encode_build(squad: int, def_id: String, cell: Vector2i) -> PackedByteArray:
	if space == null or not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_build(squad, def_id, space.index(cell))


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
func routed_of(squad: int) -> bool:
	return bool(composition[squad].get("routed", false)) if composition.has(squad) else false


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
		terrain_sampler)


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
