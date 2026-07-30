extends RefCounted
class_name SquadSim

## The authoritative simulation (D-005, D-009, D-020).
##
## Squads are the atomic unit; soldiers are never simulated, only derived
## (D-006). State lives in parallel packed arrays rather than Nodes or
## objects — one entry per squad, indexed by squad id — because the scene
## tree does not survive D-018's target of ~1,000 squads.
##
## The tick is driven by an explicit accumulator owned by the caller
## (D-023), never by `_physics_process`. That is what lets tests and
## replay playback step the sim without a SceneTree.
##
## ## The curve IS the state
##
## The important structural choice here: a squad's authoritative position
## is `curve.sample_cell(now)`, not a separately integrated position that
## happens to be described by a curve. Server and client therefore agree
## because they sample the same function, not because the server keeps
## correcting the client. It also means an idle squad's state genuinely
## does not change, which is what makes D-003's zero-bandwidth claim true
## rather than merely approximated.

const TICK_HZ := 10.0  # D-020. Also see D-023 on why this lives here.

## How far ahead a squad's path is written into its curve. Must exceed
## the replicator's horizon, or clients run out of curve between updates.
## Kept modest so a re-path discards little work.
var curve_lookahead_seconds: float = 3.0

var space: TorusSpace
var replicator: CurveReplicator
var replay: ReplayLog = null

var time: float = 0.0
var tick_count: int = 0

# --- packed squad state (D-009) --------------------------------------
var _cell := PackedInt32Array()
var _destination := PackedInt32Array()
var _alive := PackedInt32Array()
var _owner := PackedInt32Array()
var _speed := PackedFloat32Array()  # cells per second
var _shape: Array[String] = []
var _spacing := PackedFloat32Array()
var _def_id: Array[StringName] = []
var _curves: Array[StateCurve] = []

# Flow fields are per DESTINATION and shared by every squad heading there
# (D-007). This dictionary is the thing that makes that claim real.
var _fields := {}

# --- measurement (D-012 / D-022 criterion 5) --------------------------
var last_tick_usec: int = 0
var total_tick_usec: int = 0
var fields_built: int = 0
var curves_rebuilt: int = 0

var _validated := false

# Terrain passability. Empty means fully open, which is M1's case —
# terrain generation is explicitly out of M1's scope (D-022).
var _passable := PackedByteArray()


func _init(p_space: TorusSpace = null, p_replicator: CurveReplicator = null) -> void:
	space = p_space if p_space != null else TorusSpace.new()
	replicator = p_replicator if p_replicator != null else CurveReplicator.new()


func squad_count() -> int:
	return _cell.size()


func set_passable(p: PackedByteArray) -> void:
	_passable = p
	# Any cached field was solved against the old terrain.
	_fields.clear()


## Add a squad and return its id (also its index in every packed array).
func add_squad(def: UnitDef, owner: int, at: Vector2i) -> int:
	var id := _cell.size()
	var cell := space.index(at)

	_cell.append(cell)
	_destination.append(cell)
	_alive.append(def.squad_size)
	_owner.append(owner)
	_speed.append(_cells_per_second(def))
	_shape.append(def.formation_shape)
	_spacing.append(def.formation_spacing)
	_def_id.append(def.id)

	var curve := StateCurve.new()
	curve.append_cell(time, at, space)
	_curves.append(curve)
	replicator.set_curve(id, curve)
	_log_curve(id, curve)

	return id


## move_speed is in world units per second; convert to cells per second
## using the hex's width so unit stats stay in intuitive units.
func _cells_per_second(def: UnitDef) -> float:
	var hex_width := space.hex_size * TorusSpace.SQRT_3
	if hex_width <= 0.0:
		return 0.0
	return def.move_speed / hex_width


func cell_of(squad: int) -> Vector2i:
	return space.from_index(_cell[squad])


func destination_of(squad: int) -> Vector2i:
	return space.from_index(_destination[squad])


func alive_of(squad: int) -> int:
	return _alive[squad]


func owner_of(squad: int) -> int:
	return _owner[squad]


func curve_of(squad: int) -> StateCurve:
	return _curves[squad]


func def_id_of(squad: int) -> StringName:
	return _def_id[squad]


## What each squad IS, for the server to tell clients (D-006's inputs are
## a protocol obligation — see NetProtocol.encode_squad_info).
func squad_info_entries(squad_ids: Array) -> Array:
	var out := []
	for id in squad_ids:
		if id < 0 or id >= _cell.size():
			continue
		out.append({"id": id, "def_id": String(_def_id[id]), "alive": _alive[id]})
	return out


## The same composition, hashed, for clients to check themselves against.
func composition_hash(squad_ids: Array) -> int:
	var entries := []
	for id in squad_ids:
		if id < 0 or id >= _cell.size():
			continue
		entries.append({
			"id": id,
			"alive": _alive[id],
			"shape": _shape[id],
			"spacing": _spacing[id],
		})
	return NetProtocol.composition_hash(entries)


## Configuration sanity. Returns "" if valid, else the reason.
##
## The lookahead/horizon relationship was previously stated only in a
## comment. If the replicator's horizon is raised past the sim's lookahead
## — an entirely natural thing to try while tuning — clients run out of
## curve between updates and squads stutter, with nothing anywhere saying
## why. An invariant worth writing down is worth enforcing.
func validate() -> String:
	if replicator == null:
		return "SquadSim needs a CurveReplicator"
	if curve_lookahead_seconds <= replicator.horizon_seconds:
		return "curve_lookahead_seconds (%.2f) must exceed the replicator's horizon_seconds (%.2f), or clients run out of curve between updates" % [
			curve_lookahead_seconds, replicator.horizon_seconds]
	return ""


func is_valid() -> bool:
	return validate() == ""


func is_idle(squad: int) -> bool:
	return _cell[squad] == _destination[squad]


## Apply casualties. Positions restamp on the next derivation with no
## further work here, because soldier slots are a function of `alive`
## (D-006 clause 3) rather than stored per soldier.
func set_alive(squad: int, alive: int) -> void:
	_alive[squad] = maxi(0, alive)


## Issue a move order. This is the invalidation event D-003 warns about:
## ordering many squads at once re-paths many curves in one tick, which is
## exactly what the replicator's budget exists to absorb.
func order_move(squad: int, destination: Vector2i) -> void:
	var dest_index := space.index(destination)
	if _destination[squad] == dest_index:
		return
	_destination[squad] = dest_index
	_rebuild_curve(squad)


## Shared per-destination flow field, built on demand (D-007).
func _field_for(destination_index: int) -> FlowField:
	if _fields.has(destination_index):
		return _fields[destination_index]
	var field := FlowField.new()
	field.build(space, space.from_index(destination_index), _passable)
	_fields[destination_index] = field
	fields_built += 1
	return field


## Write the squad's planned path into its curve, starting from where it
## is *now*. Keyframes are one per cell, timed by the squad's speed.
func _rebuild_curve(squad: int) -> void:
	var curve := StateCurve.new()
	var current := _cell[squad]
	var at := time
	curve.append_cell(at, space.from_index(current), space)

	var speed := _speed[squad]
	if speed > 0.0 and _destination[squad] != current:
		var field := _field_for(_destination[squad])
		var seconds_per_cell := 1.0 / speed
		var max_steps := maxi(1, ceili(curve_lookahead_seconds * speed))

		for _i in range(max_steps):
			if current == field.destination:
				break
			var next := field.step_from(current)
			if next == current:
				break  # unreachable; stall rather than wander
			at += seconds_per_cell
			curve.append_cell(at, space.from_index(next), space)
			current = next

	_curves[squad] = curve
	replicator.set_curve(squad, curve)
	_log_curve(squad, curve)
	curves_rebuilt += 1


func _log_curve(squad: int, curve: StateCurve) -> void:
	if replay != null:
		replay.record(time, squad, replicator.version_of(squad), curve)


## Advance one 10 Hz tick.
func tick() -> void:
	# Checked once rather than at construction, because callers legitimately
	# tune horizon and lookahead after wiring the two together. One bool
	# test per tick is a fair price for the invariant never going unnoticed.
	if not _validated:
		_validated = true
		var invalid := validate()
		if invalid != "":
			push_error("SquadSim: %s" % invalid)

	var started := Time.get_ticks_usec()

	time += 1.0 / TICK_HZ
	tick_count += 1

	for squad in range(_cell.size()):
		var curve := _curves[squad]

		# Authoritative position is a sample of the curve, not a
		# separately integrated value.
		_cell[squad] = space.index(curve.sample_cell(time, space))

		if _cell[squad] == _destination[squad]:
			# Arrived. Deliberately does NOT touch the curve: an idle
			# squad must cost zero bandwidth (D-003).
			continue

		# Extend the path before the client runs out of curve. Rebuilding
		# exactly at the end would leave a gap at the horizon.
		if time >= curve.end_time() - (1.0 / TICK_HZ):
			_rebuild_curve(squad)

	last_tick_usec = Time.get_ticks_usec() - started
	total_tick_usec += last_tick_usec


## Mean microseconds per squad-update — the number D-020's budget is
## stated in (~50 us/squad to consume half a core at full scale) and that
## D-012 requires be measurable from M1.
func mean_usec_per_squad_update() -> float:
	# With no squads there are no squad-updates, so the honest answer is
	# zero. Dividing by max(count, 1) instead would report the whole
	# tick's fixed overhead as if it were per-squad cost, which reads as a
	# suspiciously high number on an idle server.
	if _cell.is_empty() or tick_count <= 0:
		return 0.0
	return float(total_tick_usec) / float(tick_count * _cell.size())


## Soldier transforms for a squad, derived not stored (D-006).
func soldier_transforms(squad: int, at_time: float = -1.0) -> Array[Transform3D]:
	var sample_at := time if at_time < 0.0 else at_time
	return Formation.soldier_transforms(
		_curves[squad], sample_at, _alive[squad], _shape[squad], _spacing[squad], space
	)


## Squad ids visible to a player. M1 has no fog of war yet (D-004 is an
## M2 milestone), so this is "everything" — but the seam exists here, in
## the shape the replicator already expects, so M2 changes this function
## rather than the replication path.
func visible_to(_player: int) -> Array:
	var ids := []
	for i in range(_cell.size()):
		ids.append(i)
	return ids
