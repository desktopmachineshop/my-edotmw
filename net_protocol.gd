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

# Client -> server
const C2S_ORDER_MOVE := 10

# FNV-1a, 32-bit. Chosen because it is trivially reimplementable and has
# no platform-dependent behaviour — both ends must agree exactly, and a
# hash that depends on String.hash() or float formatting would not.
const FNV_OFFSET_BASIS := 2166136261
const FNV_PRIME := 16777619


## WELCOME: tells a joining client who it is, how big the map is, and
## which squads it owns. Map dimensions matter because the client needs a
## TorusSpace to derive soldier positions (D-006) and to interpret curves.
static func encode_welcome(player: int, width: int, height: int, squads: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(S2C_WELCOME)
	buf.put_u32(player)
	buf.put_u32(width)
	buf.put_u32(height)
	buf.put_u32(squads.size())
	for id in squads:
		buf.put_u32(id)
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

	return {
		"player": player,
		"width": width,
		"height": height,
		"squads": squads,
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
## Shape and spacing are not sent: they are properties of the UnitDef, so
## the client resolves them through UnitRoster.by_id and cannot drift.
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
		out.append({"id": id, "def_id": def_id, "alive": alive})
	return out


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
