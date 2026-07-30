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

# squad id -> { "def_id": String, "alive": int, "shape": String,
# "spacing": float }. Told to us by the server, never guessed — see
# NetProtocol.encode_squad_info for why guessing was a real bug.
var composition := {}

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


func handle_packet(data: PackedByteArray) -> void:
	match NetProtocol.opcode_of(data):
		NetProtocol.S2C_WELCOME:
			_handle_welcome(data)
		NetProtocol.S2C_CURVE:
			_handle_curve(data)
		NetProtocol.S2C_SQUAD_INFO:
			_handle_squad_info(data)
		NetProtocol.S2C_STATE_HASH:
			_handle_state_hash(data)
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
		composition[int(entry["id"])] = {
			"def_id": def_id,
			"alive": int(entry["alive"]),
			"shape": def.formation_shape,
			"spacing": def.formation_spacing,
		}


func _handle_state_hash(data: PackedByteArray) -> void:
	var decoded := NetProtocol.decode_state_hash(data)
	state_hash_checks += 1
	var ours := composition_hash()
	var theirs := int(decoded["hash"])
	if ours != theirs:
		desync_count += 1
		last_desync = "tick %d: client composition hash %d != server %d over %d squads" % [
			int(decoded["tick"]), ours, theirs, composition.size()]


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


## Hash of the composition this client will derive from, in the format
## SquadSim produces for the server side. Compared on every STATE_HASH.
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
func derive_all(now: float) -> int:
	var total := 0
	for id in curves:
		total += soldier_transforms(id, now).size()
	return total


## Squads whose curve has arrived but whose composition has not. Should
## settle to zero; a persistent non-zero value means the server is
## replicating something it never described.
func squads_awaiting_composition() -> int:
	var missing := 0
	for id in curves:
		if not composition.has(id):
			missing += 1
	return missing


## Build an order for the server. Returns an empty array if the client
## doesn't own the squad — the server enforces this too (D-002), but
## sending a knowingly invalid order is just noise.
func encode_order(squad: int, destination: Vector2i) -> PackedByteArray:
	if space == null or not owns(squad):
		return PackedByteArray()
	return NetProtocol.encode_order_move(squad, space.index(destination))
