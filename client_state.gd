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

# squad id -> StateCurve. The entirety of replicated world state.
var curves := {}

var welcomed := false
var curve_packets_received: int = 0
var unknown_packets: int = 0


func handle_packet(data: PackedByteArray) -> void:
	match NetProtocol.opcode_of(data):
		NetProtocol.S2C_WELCOME:
			_handle_welcome(data)
		NetProtocol.S2C_CURVE:
			_handle_curve(data)
		_:
			unknown_packets += 1


func _handle_welcome(data: PackedByteArray) -> void:
	var welcome := NetProtocol.decode_welcome(data)
	player = int(welcome["player"])
	space = TorusSpace.new(int(welcome["width"]), int(welcome["height"]), 1.0)
	squads = welcome["squads"]
	welcomed = true


func _handle_curve(data: PackedByteArray) -> void:
	var decoded := NetProtocol.decode_curve(data)
	curves[int(decoded["id"])] = decoded["curve"]
	curve_packets_received += 1


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


## Derive one squad's soldier transforms (D-006). Nothing here came off
## the wire.
func soldier_transforms(squad: int, now: float, alive: int, shape: String, spacing: float) -> Array[Transform3D]:
	var empty: Array[Transform3D] = []
	if space == null or not curves.has(squad):
		return empty
	return Formation.soldier_transforms(curves[squad], now, alive, shape, spacing, space)


## Total soldiers this client would be drawing — the number that makes
## D-006's 40x claim concrete, since none of them cost bandwidth.
func derive_all(now: float, alive_per_squad: int, shape: String, spacing: float) -> int:
	var total := 0
	for id in curves:
		total += soldier_transforms(id, now, alive_per_squad, shape, spacing).size()
	return total


## Build an order for the server. Returns an empty array if the client
## doesn't own the squad — the server enforces this too (D-002), but
## sending a knowingly invalid order is just noise.
func encode_order(squad: int, destination: Vector2i) -> PackedByteArray:
	if space == null or not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_move(squad, space.index(destination))
