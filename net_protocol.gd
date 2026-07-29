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

# Client -> server
const C2S_ORDER_MOVE := 10


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


static func opcode_of(data: PackedByteArray) -> int:
	return -1 if data.is_empty() else data[0]
