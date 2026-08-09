extends RefCounted
class_name NetProtocol

## Single definition of the wire protocol, shared by the server, the real
## client, and the load-test bots.
##
## The opcodes were originally declared separately in server.gd and
## bot_client.gd. That works right up until one side gains a message and
## the other doesn't, at which point the failure is a silently ignored
## packet rather than a compile error. One definition, imported by
## everyone, removes that class of bug entirely.
##
## Payloads are deliberately thin: the interesting content is the curve
## bytes from StateCurve, which are the same on the wire and in replays
## (D-016).

# Server -> client
const S2C_WELCOME := 1
const S2C_CURVE := 2
const S2C_SQUAD_INFO := 3
const S2C_STATE_HASH := 4
const S2C_SQUAD_COMBAT := 5
const S2C_SQUAD_CONCEAL := 6

# Client -> server
const S2C_BUILDING_INFO := 7
const S2C_BUILDING_STATE_HASH := 8

const C2S_ORDER_MOVE := 10
const C2S_ORDER_STOP := 11
const C2S_ORDER_ATTACK_MOVE := 12
const C2S_ORDER_BUILD := 13
const C2S_ORDER_PRODUCE := 14
const C2S_ORDER_GATHER := 16
const C2S_ORDER_RALLY := 23
const C2S_ORDER_FORMATION := 24

const S2C_WALLET := 9
const S2C_NOTICE := 15
const S2C_NODES := 17

# FNV-1a, 32-bit. Chosen because it is trivially reimplementable and has
# no platform-dependent behaviour — both ends must agree exactly, and a
# hash that depends on String.hash() or float formatting would not.
const FNV_OFFSET_BASIS := 2166136261
const FNV_PRIME := 16777619


## WELCOME: tells a joining client who it is, how big the map is, and
## which squads it owns. Map dimensions matter because the client needs a
## TorusSpace to derive soldier positions (D-006) and to interpret curves.
## `spawn_cells` is the map's starting positions as cell indices, in
## player order (D-036). Sent because the client otherwise has to *guess*
## where anyone starts: the capture-mode scenario used to duplicate
## server.gd's spawn formula to do exactly that, and went silently wrong
## the moment spawns became map data. One definition, on the wire.
## `squad_cap` and `match_tick` are the HUD's, and both must come from the
## server for the same reason everything else here does: the cap is
## MapConfig data the client has no copy of, and a clock each client ran
## for itself would show a different match length to every player and drift
## further apart the longer the game went on. `match_tick` is the server's
## own tick counter at the moment of welcome, which at a fixed 10 Hz
## (D-020) IS the elapsed time — and the client re-anchors on every later
## tick it hears, so it cannot drift (D-003's derive-between-messages
## pattern, the same one construction progress uses).
static func encode_welcome(player: int, width: int, height: int, squads: Array,
		spawn_cells: Array = [], squad_cap: int = 0,
		match_tick: int = 0) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_WELCOME)
	buf.put_u32(player)
	buf.put_u32(width)
	buf.put_u32(height)
	buf.put_u32(squads.size())
	for id in squads:
		buf.put_u32(id)
	buf.put_u32(spawn_cells.size())
	for cell_index in spawn_cells:
		buf.put_u32(cell_index)
	buf.put_u32(squad_cap)
	buf.put_u32(match_tick)
	return buf.data_array


static func decode_welcome(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var player := buf.get_u32()
	var width := buf.get_u32()
	var height := buf.get_u32()

	# Built locally and assigned once. PackedInt32Array is a value type in
	# GDScript, so `out["squads"].append(...)` appends to a COPY and
	# silently leaves the dictionary entry empty — the client then thinks
	# it owns no squads and every order it tries to send is dropped.
	var count := buf.get_u32()
	var squads := PackedInt32Array()
	for i in range(count):
		squads.append(buf.get_u32())

	# Trailing field, so a packet written before spawn tables existed reads
	# back as "no spawns known" rather than as garbage: get_u32 past the
	# end returns 0, which is exactly an empty table.
	var spawn_count := buf.get_u32()
	var spawns := PackedInt32Array()
	for i in range(spawn_count):
		spawns.append(buf.get_u32())

	# Trailing fields, read the same forgiving way `spawns` is: a packet
	# written before these existed reads back as 0, which the HUD shows as
	# "no cap known" rather than as a wrong number.
	var squad_cap := buf.get_u32()
	var match_tick := buf.get_u32()

	return {
		"player": player,
		"width": width,
		"height": height,
		"squads": squads,
		"spawns": spawns,
		"squad_cap": squad_cap,
		"match_tick": match_tick,
	}


## CURVE: an opcode byte followed by a CurveReplicator packet verbatim.
static func encode_curve(replicator_packet: PackedByteArray) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_CURVE)
	buf.put_data(replicator_packet)
	return buf.data_array


static func decode_curve(data: PackedByteArray) -> Dictionary:
	return CurveReplicator.decode_packet(data.slice(1))


## ORDER_MOVE: the only client input in M1. Note it carries a squad id and
## a destination CELL INDEX — never a position for anything to move to
## directly. The server decides what that order means (D-002).
static func encode_order_move(squad: int, destination_index: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_ORDER_MOVE)
	buf.put_u32(squad)
	buf.put_u32(destination_index)
	return buf.data_array


static func decode_order_move(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return {"squad": buf.get_u32(), "destination": buf.get_u32()}


## STOP: halt where you stand (D-034). Carries no destination — the
## server decides that "here" means the squad's current cell, because the
## client's idea of where a squad is lags replication by up to a tick and
## is not authoritative (D-002).
static func encode_order_stop(squad: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_ORDER_STOP)
	buf.put_u32(squad)
	return buf.data_array


static func decode_order_stop(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return {"squad": buf.get_u32()}


## ATTACK_MOVE: advance, but stop on contact (D-034).
##
## Squads already engage anything that comes into range, so this is not
## "move and also fight" — that is what a plain move already does. The
## difference is what happens on contact: an attack-moving squad halts
## and fights where it stands, while a moving squad walks on through and
## keeps taking hits from behind. That distinction is the whole reason
## the order exists.
static func encode_order_attack_move(squad: int, destination_index: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_ORDER_ATTACK_MOVE)
	buf.put_u32(squad)
	buf.put_u32(destination_index)
	return buf.data_array


static func decode_order_attack_move(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return {"squad": buf.get_u32(), "destination": buf.get_u32()}


## SQUAD_INFO: what each squad actually IS — its UnitDef id and current
## strength.
##
## This closes a real hole. Before it existed, the welcome told a client
## which squads it owned but never their composition, so the client
## guessed a nominal squad size. Because Formation.slot_offset takes
## `alive` as an input, a wrong guess does not merely draw the wrong
## number of soldiers — it moves every one of them, and client and server
## silently disagree about where an entire army is standing.
##
## D-006 says client and server agree "by construction, not by
## synchronization". That is only true if both are handed identical
## inputs, which makes supplying those inputs a protocol obligation.
##
## SHAPE travels; SPACING does not. That asymmetry is D-058: shape became
## mutable squad state (a player orders it, and the economy switches a
## gathering crew between working and walking order), while spacing is
## still a fixed property of the UnitDef and cannot drift. This header
## previously said neither was sent, and it was right when it was written
## — but shape stopped being a UnitDef property and this did not change,
## so every formation change was invisible to clients AND desynced them,
## since shape is hashed. `shape` is read without a default deliberately:
## a caller that omits it is a bug that must be loud, because the silent
## version puts every soldier in the squad somewhere the server did not.
static func encode_squad_info(entries: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_SQUAD_INFO)
	buf.put_u32(entries.size())
	for entry in entries:
		buf.put_u32(int(entry["id"]))
		var def_id := String(entry["def_id"]).to_utf8_buffer()
		buf.put_u16(def_id.size())
		buf.put_data(def_id)
		buf.put_u32(int(entry["alive"]))
		# A name rather than an ordinal, exactly as ORDER_FORMATION carries
		# it: adding a formation should not renumber the wire.
		var shape := String(entry["shape"]).to_utf8_buffer()
		buf.put_u16(shape.size())
		buf.put_data(shape)
		# Owner rides along so a client learns it owns a squad it did not
		# start with. The welcome message lists what a player begins with,
		# and nothing updated that list when a building PRODUCED a squad —
		# so trained units could not be selected or ordered by anybody,
		# including the player who paid for them.
		buf.put_u32(int(entry.get("owner", 0)))
	return buf.data_array


static func decode_squad_info(data: PackedByteArray) -> Array:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var count := buf.get_u32()
	var out := []
	for i in range(count):
		var id := buf.get_u32()
		var name_length := buf.get_u16()
		# get_data returns [error, PackedByteArray]; the array element has
		# no static type, so the String must be annotated explicitly.
		var name_bytes: PackedByteArray = buf.get_data(name_length)[1]
		var def_id := name_bytes.get_string_from_utf8()
		var alive := buf.get_u32()
		var shape_length := buf.get_u16()
		var shape_bytes: PackedByteArray = buf.get_data(shape_length)[1]
		out.append({
			"id": id, "def_id": def_id, "alive": alive,
			"shape": shape_bytes.get_string_from_utf8(), "owner": buf.get_u32(),
		})
	return out


## BUILDING_INFO: everything a client needs to know a building exists
## (D-029). Sent when a building is first revealed and again whenever its
## state changes in a way clients must see.
##
## `progress` rides along rather than being replicated as a curve for now:
## a build is short, and the client only needs to know how far along it
## is, not to interpolate it precisely. The curve treatment D-003
## describes is worth having when construction gets long enough to watch.
static func encode_building_info(entries: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_BUILDING_INFO)
	buf.put_u32(entries.size())
	for entry in entries:
		buf.put_u32(int(entry["id"]))
		var def_id := String(entry["def_id"]).to_utf8_buffer()
		buf.put_u16(def_id.size())
		buf.put_data(def_id)
		buf.put_u32(int(entry["owner"]))
		buf.put_u32(int(entry["cell"]))
		buf.put_float(float(entry["progress"]))
		buf.put_u8(1 if bool(entry["destroyed"]) else 0)

		# Health as a FRACTION, and the production queue.
		#
		# Added so a selected building can show what it is doing (health,
		# what is training, what is waiting). Neither is hashed — the
		# building composition hash covers identity, owner, kind and
		# whether it still stands, deliberately excluding anything that
		# varies continuously, because a client legitimately lags a tick
		# and hashing these would report a desync on a healthy system.
		#
		# This message is sent on CHANGE, never per tick (BuildingSim's
		# `take_dirty`), so an idle building still costs zero bandwidth —
		# D-003's claim survives. `head_remaining` lets the client run the
		# progress bar down locally between messages, the same derivation
		# as construction progress rather than a stream of floats.
		buf.put_float(float(entry.get("health_fraction", 1.0)))
		buf.put_float(float(entry.get("head_remaining", 0.0)))
		buf.put_u32(int(entry.get("rally", 0)))
		var queue: Array = entry.get("queue", [])
		buf.put_u16(queue.size())
		for queued in queue:
			var queued_id := String(queued).to_utf8_buffer()
			buf.put_u16(queued_id.size())
			buf.put_data(queued_id)
	return buf.data_array


static func decode_building_info(data: PackedByteArray) -> Array:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var count := buf.get_u32()
	var out := []
	for i in range(count):
		var id := buf.get_u32()
		var name_length := buf.get_u16()
		var name_bytes: PackedByteArray = buf.get_data(name_length)[1]
		var entry := {
			"id": id,
			"def_id": name_bytes.get_string_from_utf8(),
			"owner": buf.get_u32(),
			"cell": buf.get_u32(),
			"progress": buf.get_float(),
			"destroyed": buf.get_u8() == 1,
			"health_fraction": buf.get_float(),
			"head_remaining": buf.get_float(),
			"rally": buf.get_u32(),
		}
		var queue := []
		for _q in range(buf.get_u16()):
			var queued_length := buf.get_u16()
			var queued_bytes: PackedByteArray = buf.get_data(queued_length)[1]
			queue.append(queued_bytes.get_string_from_utf8())
		entry["queue"] = queue
		out.append(entry)
	return out


## WALLET: a player's four resource totals — sent to that player ONLY.
##
## Wallets are private (D-028). Knowing an opponent's stockpile tells you
## what they are about to field, which is the same class of knowledge
## D-003's horizon clipping and D-004's fog exist to withhold. There is
## therefore no player id on the wire: this message is always about the
## client receiving it, and a client that could ask about someone else's
## wallet is a client that could be modified to.
static func encode_wallet(totals: PackedInt32Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_WALLET)
	buf.put_u32(totals.size())
	for total in totals:
		buf.put_u32(total)
	return buf.data_array


static func decode_wallet(data: PackedByteArray) -> PackedInt32Array:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var count := buf.get_u32()
	var out := PackedInt32Array()
	for i in range(count):
		out.append(buf.get_u32())
	return out


## NODES: where the resources are, sent once at join.
##
## Node PLACEMENT is derived from terrain and would be reproducible on the
## client — but reproducing it would mean the client running the
## generator and the fairness pass with the same parameters, and any drift
## in those would put resources on the client's map that are not on the
## server's. Sending them is a couple of kilobytes once and removes the
## question entirely.
##
## Their remaining STOCK is not sent: that changes constantly and belongs
## to whoever can see the node. The client draws where resources are, not
## how much is left.
static func encode_nodes(entries: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_NODES)
	buf.put_u32(entries.size())
	for entry in entries:
		buf.put_u32(int(entry["cell"]))
		buf.put_u8(int(entry["kind"]))
	return buf.data_array


static func decode_nodes(data: PackedByteArray) -> Array:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var count := buf.get_u32()
	var out := []
	for i in range(count):
		out.append({"cell": buf.get_u32(), "kind": buf.get_u8()})
	return out


## ORDER_GATHER: put a gatherer squad to work on a resource node
## (D-028). Carries the cell rather than a node id, because a node IS a
## cell — there is no separate node entity to name.
static func encode_order_gather(squad: int, cell_index: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_ORDER_GATHER)
	buf.put_u32(squad)
	buf.put_u32(cell_index)
	return buf.data_array


static func decode_order_gather(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return {"squad": buf.get_u32(), "cell": buf.get_u32()}


## ORDER_FORMATION: change a squad's formation (D-058).
##
## The shape travels as a STRING rather than an enum ordinal, for the same
## reason `produces` lists archetypes: adding a formation should not
## renumber the wire, and a name in a packet capture is readable.
static func encode_order_formation(squad: int, shape: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_ORDER_FORMATION)
	buf.put_u32(squad)
	var bytes := shape.to_utf8_buffer()
	buf.put_u16(bytes.size())
	buf.put_data(bytes)
	return buf.data_array


static func decode_order_formation(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var squad := buf.get_u32()
	var length := buf.get_u16()
	var bytes: PackedByteArray = buf.get_data(length)[1]
	return {"squad": squad, "shape": bytes.get_string_from_utf8()}


## ORDER_RALLY: where a building sends what it produces.
##
## The building is named by its WIRE id (BuildingSim.wire_id), like every
## other building order — squad ids and building ids share a number space
## and the offset is what keeps them apart.
static func encode_order_rally(building_wire_id: int, cell_index: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_ORDER_RALLY)
	buf.put_u32(building_wire_id)
	buf.put_u32(cell_index)
	return buf.data_array


static func decode_order_rally(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return {"building": buf.get_u32(), "cell": buf.get_u32()}


## NOTICE: a short human-readable line for the player who sent an order.
##
## The server refuses orders for good reasons — out of reach, wrong
## ground, cannot afford it — and used to do so in total silence. A
## playtest pressed B nine cells from its founders, saw nothing at all
## happen, and had no way to tell a refused order from a broken key.
##
## The REASON has to come from the server: it owns the rules, and a
## client that decided its own refusal messages would be a second copy of
## those rules, free to drift from the real ones. That is the mistake the
## duplicated spawn formula already made once.
static func encode_notice(text: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_NOTICE)
	var bytes := text.to_utf8_buffer()
	buf.put_u16(bytes.size())
	buf.put_data(bytes)
	return buf.data_array


static func decode_notice(data: PackedByteArray) -> String:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var length := buf.get_u16()
	var bytes: PackedByteArray = buf.get_data(length)[1]
	return bytes.get_string_from_utf8()


## ORDER_PRODUCE: a building is told to make a unit (D-028/D-031).
## Carries the building's wire id and the unit's def id.
static func encode_order_produce(building_wire_id: int, unit_def_id: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_ORDER_PRODUCE)
	buf.put_u32(building_wire_id)
	var name_bytes := unit_def_id.to_utf8_buffer()
	buf.put_u16(name_bytes.size())
	buf.put_data(name_bytes)
	return buf.data_array


static func decode_order_produce(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var building := buf.get_u32()
	var name_length := buf.get_u16()
	var name_bytes: PackedByteArray = buf.get_data(name_length)[1]
	return {"building": building, "def_id": name_bytes.get_string_from_utf8()}


## BUILDING_STATE_HASH: its own message rather than folded into
## S2C_STATE_HASH, and deliberately so (D-030).
##
## The two hashes are computed over differently-shaped sets — squads over
## what a client can see RIGHT NOW, buildings over everything it has EVER
## been shown, because a building once seen stays known. Combining them
## into one number would make a mismatch undiagnosable: you could not tell
## which subsystem had broken.
static func encode_building_state_hash(tick: int, hash_value: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_BUILDING_STATE_HASH)
	buf.put_u32(tick)
	buf.put_u32(hash_value)
	return buf.data_array


static func decode_building_state_hash(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return {"tick": buf.get_u32(), "hash": buf.get_u32()}


## ORDER_BUILD: a squad is told to found a building at a cell (D-031).
## Carries the building's def id rather than an index, so adding a
## building to /buildings never renumbers the wire.
static func encode_order_build(squad: int, def_id: String, cell_index: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_ORDER_BUILD)
	buf.put_u32(squad)
	var name_bytes := def_id.to_utf8_buffer()
	buf.put_u16(name_bytes.size())
	buf.put_data(name_bytes)
	buf.put_u32(cell_index)
	return buf.data_array


static func decode_order_build(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var squad := buf.get_u32()
	var name_length := buf.get_u16()
	var name_bytes: PackedByteArray = buf.get_data(name_length)[1]
	return {
		"squad": squad,
		"def_id": name_bytes.get_string_from_utf8(),
		"cell": buf.get_u32(),
	}


## STATE_HASH: the server's view of composition, for the client to check
## its own against. See composition_hash() for what is and isn't covered.
static func encode_state_hash(tick: int, hash_value: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_STATE_HASH)
	buf.put_u32(tick)
	buf.put_u32(hash_value)
	return buf.data_array


static func decode_state_hash(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return {"tick": buf.get_u32(), "hash": buf.get_u32()}


## SQUAD_COMBAT: casualty/rout events for the tick they happened on
## (D-024, D-026 criterion 3).
##
## This is the ONLY place a squad's `alive` changes after it spawns, and
## it is sent exclusively when at least one squad in the message actually
## changed — a tick with no deaths and no routing produces no message at
## all, not a message with an empty list, so it is genuinely zero bytes
## rather than merely a small constant. `ReplayLog` logs this exact
## encoding too (D-016): there is one definition of this wire shape, used
## by the server, the client, and the replay alike.
static func encode_squad_combat(tick: int, events: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_SQUAD_COMBAT)
	buf.put_u32(tick)
	buf.put_u32(events.size())
	for event in events:
		buf.put_u32(int(event["id"]))
		buf.put_u32(int(event["alive"]))
		buf.put_u8(1 if bool(event["routed"]) else 0)
	return buf.data_array


static func decode_squad_combat(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var tick := buf.get_u32()
	var count := buf.get_u32()
	var events := []
	for i in range(count):
		var id := buf.get_u32()
		var alive := buf.get_u32()
		var routed := buf.get_u8() != 0
		events.append({"id": id, "alive": alive, "routed": routed})
	return {"tick": tick, "events": events}


## SQUAD_CONCEAL: a squad (or squads) leaving this client's vision this
## tick (D-025 part 3, D-026 criterion 7).
##
## This is the explicit event D-025 insists on rather than leaving conceal
## as an inference from silence. Without it a client cannot tell "this
## squad just left my vision" apart from "its curve update is merely late"
## — and worse, the server's STATE_HASH would then be computed over a
## different set than the client's own composition_hash(), which is
## exactly the "check that cries wolf" failure composition_hash's header
## warns about (D-026 criterion 8). The client's response is to keep the
## squad's last-known curve and composition as a stale, explicitly flagged
## ghost (ClientState._ghosts) rather than discarding or silently ageing it.
static func encode_squad_conceal(tick: int, squad_ids: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_SQUAD_CONCEAL)
	buf.put_u32(tick)
	buf.put_u32(squad_ids.size())
	for id in squad_ids:
		buf.put_u32(int(id))
	return buf.data_array


static func decode_squad_conceal(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var tick := buf.get_u32()
	var count := buf.get_u32()
	var squad_ids := []
	for i in range(count):
		squad_ids.append(buf.get_u32())
	return {"tick": tick, "squad_ids": squad_ids}


## Hash of squad COMPOSITION — id, strength, formation shape and spacing —
## over the squads a given client should know about.
##
## ## What this deliberately does not cover, and why
##
## It does not hash positions. A client legitimately lags the server: the
## replication budget (D-003) means a curve update can be a tick or more
## behind, so comparing positions would report a desync for a system
## working exactly as designed. A check that cries wolf gets muted, which
## is worse than no check.
##
## Composition is delivery-independent — it is sent explicitly and does
## not change during M1 — so a mismatch is always a real fault. And it is
## the input that actually matters: given the same curve and the same
## composition, D-006's purity clause guarantees the derived soldier
## positions agree, so composition agreement plus curve delivery IS
## positional agreement.
##
## `entries` is an Array of { id, alive, shape, spacing }. Order does not
## matter; entries are sorted by id first.
static func composition_hash(entries: Array) -> int:
	var sorted_entries := entries.duplicate()
	sorted_entries.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))

	var h := FNV_OFFSET_BASIS
	for entry in sorted_entries:
		h = _hash_int(h, int(entry["id"]))
		h = _hash_int(h, int(entry["alive"]))
		h = _hash_string(h, String(entry["shape"]))
		# Quantised rather than hashed as a float: identical values must
		# hash identically, and float bit patterns are a bad thing to
		# depend on across a wire.
		h = _hash_int(h, int(round(float(entry["spacing"]) * 10000.0)))
	return h


static func _hash_byte(h: int, byte_value: int) -> int:
	return ((h ^ (byte_value & 0xFF)) * FNV_PRIME) & 0xFFFFFFFF


static func _hash_int(h: int, value: int) -> int:
	var out := h
	for shift in [0, 8, 16, 24]:
		out = _hash_byte(out, (value >> shift) & 0xFF)
	return out


static func _hash_string(h: int, text: String) -> int:
	var out := h
	for byte_value in text.to_utf8_buffer():
		out = _hash_byte(out, byte_value)
	return out


static func opcode_of(data: PackedByteArray) -> int:
	return -1 if data.is_empty() else data[0]


## Deterministic seed derivation for anything that needs a map-derived
## seed rather than a wall-clock one — Combat (D-024) is the current
## user, via server.gd. Not part of the wire protocol, but kept here to
## reuse the same FNV mixing the composition hash already does rather
## than inventing a second hash for the same purpose. Same inputs always
## produce the same seed, which is what lets a replay reproduce the exact
## battle that happened (D-016) rather than a different one seeded from
## whatever moment the server happened to start.
static func seed_from(text: String, a: int, b: int) -> int:
	var h := _hash_string(FNV_OFFSET_BASIS, text)
	h = _hash_int(h, a)
	h = _hash_int(h, b)
	return h


## LOBBY (D-048). The whole seat list, sent on any change.
##
## Sent whole rather than as diffs: a lobby changes when somebody clicks
## something, which is thousands of times rarer than a curve update, and
## the entire state is a few hundred bytes. D-003's incremental machinery
## exists because squad state changes ten times a second — spending that
## complexity here would be paying a cost the problem does not have.
const S2C_LOBBY := 18
const C2S_LOBBY := 19

## What a client can ask the lobby to do. The server checks every one of
## them against MatchState's rules; these are requests, not commands.
const LOBBY_SET_CIV := 0
const LOBBY_ADD_AI := 1
const LOBBY_REMOVE_AI := 2
const LOBBY_START := 3
const LOBBY_SET_OPTION := 4
const LOBBY_SET_TEAM := 5


## `phase` is MatchState.Phase. Carried because a client cannot infer
## "am I in a lobby" from HAVING a seat list — it keeps the seats all
## match, for player colours and teams (D-052). Inferring it from the
## list being non-empty made the client draw the lobby over a running
## game while every counter reported a healthy match.
static func encode_lobby(admin_player: int, seats: Array, settings := {}, phase := 0) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_LOBBY)
	buf.put_u8(phase)
	buf.put_u32(admin_player)
	buf.put_u32(seats.size())
	for seat in seats:
		buf.put_u8(1 if String(seat["kind"]) == "ai" else 0)
		buf.put_u8(int(seat.get("team", 0)))
		buf.put_u32(int(seat["player"]))
		_put_string(buf, String(seat["civ"]))
		_put_string(buf, String(seat["name"]))
	var json := JSON.stringify(settings)
	_put_string(buf, json)
	return buf.data_array


static func decode_lobby(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var phase := int(buf.get_u8())
	var admin := int(buf.get_u32())
	var count := int(buf.get_u32())
	var seats := []
	for _i in range(count):
		var is_ai := buf.get_u8() == 1
		var team := int(buf.get_u8())
		var player := int(buf.get_u32())
		var civ := _get_string(buf)
		var name := _get_string(buf)
		seats.append({
			"kind": "ai" if is_ai else "human",
			"player": player, "civ": civ, "team": team, "name": name,
		})
	var settings := {}
	var json := _get_string(buf)
	if json != "":
		var parsed = JSON.parse_string(json)
		if parsed is Dictionary:
			settings = parsed
	return {"admin": admin, "seats": seats, "settings": settings, "phase": phase}


static func encode_lobby_command(action: int, seat: int, civ: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_LOBBY)
	buf.put_u8(action)
	buf.put_u32(seat)
	_put_string(buf, civ)
	return buf.data_array


static func decode_lobby_command(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var action := int(buf.get_u8())
	var seat := int(buf.get_u32())
	var civ := _get_string(buf)
	return {"action": action, "seat": seat, "civ": civ}


static func _put_string(buf: StreamPeerBuffer, text: String) -> void:
	var bytes := text.to_utf8_buffer()
	buf.put_u16(bytes.size())
	buf.put_data(bytes)


static func _get_string(buf: StreamPeerBuffer) -> String:
	var length := buf.get_u16()
	var bytes: PackedByteArray = buf.get_data(length)[1]
	return bytes.get_string_from_utf8()


## MAP_SETTINGS (D-049) — the concrete world the match is about to use.
##
## Sent at match start, before any welcome, so a client can generate
## terrain identical to the server's. CONCRETE NUMBERS, never a preset
## name: `server.gd` warned in M3 that "the moment terrain parameters
## become tunable they have to become map data and travel on the wire, or
## the two sides will quietly disagree about which cells a squad may
## enter". Sending "islands" would leave two implementations of what that
## means, one per side, free to drift apart.
const S2C_MAP_SETTINGS := 20


static func encode_map_settings(settings: Dictionary) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_MAP_SETTINGS)
	buf.put_u32(int(settings["width"]))
	buf.put_u32(int(settings["height"]))
	buf.put_u32(int(settings["player_slots"]))
	buf.put_32(int(settings["seed"]))
	_put_string(buf, String(settings["preset"]))
	for key in ["sea_level", "beach_level", "mountain_level",
			"elevation_frequency", "moisture_frequency", "height_scale"]:
		buf.put_float(float(settings[key]))
	return buf.data_array


static func decode_map_settings(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	var out := {
		"width": int(buf.get_u32()),
		"height": int(buf.get_u32()),
		"player_slots": int(buf.get_u32()),
		"seed": int(buf.get_32()),
		"preset": _get_string(buf),
	}
	for key in ["sea_level", "beach_level", "mountain_level",
			"elevation_frequency", "moisture_frequency", "height_scale"]:
		out[key] = buf.get_float()
	return out


## CHAT (D-050). Player-authored text, relayed by the server.
##
## The server is the only thing that decides who said what: a client sends
## text and nothing else, and the server attaches the speaker. Letting a
## client name its own speaker would let it put words in someone's mouth,
## which is the same "the client is not trusted" rule (D-002) that governs
## orders — it is just less obvious when the payload is prose.
const S2C_CHAT := 21
const C2S_CHAT := 22

## Longest message accepted. Bounded because it arrives on the same
## reliable channel as everything else (D-042), so an unbounded message
## is an unbounded stall for every packet queued behind it.
const CHAT_MAX_CHARS := 240


static func encode_chat(speaker: String, text: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_CHAT)
	_put_string(buf, speaker)
	_put_string(buf, text)
	return buf.data_array


static func decode_chat(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return {"speaker": _get_string(buf), "text": _get_string(buf)}


static func encode_chat_send(text: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(C2S_CHAT)
	_put_string(buf, text)
	return buf.data_array


static func decode_chat_send(data: PackedByteArray) -> String:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.get_u8()
	return _get_string(buf)


## Strip anything that would let a message rewrite the chat log rather
## than appear in it — newlines and control characters — and cap length.
##
## Applied on the SERVER before the message is relayed, so one client
## cannot fake extra lines in everyone else's window.
static func sanitise_chat(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		var c := text[i]
		if c.unicode_at(0) >= 32:
			out += c
	out = out.strip_edges()
	if out.length() > CHAT_MAX_CHARS:
		out = out.substr(0, CHAT_MAX_CHARS)
	return out
