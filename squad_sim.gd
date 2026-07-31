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

## Buildings, if this match has any (D-029). Optional so every existing
## test and tool that builds a bare SquadSim keeps working — a sim with
## no buildings simply skips their vision and their guns.
var buildings: BuildingSim = null

## The gathering economy, if this match has one (D-028). Optional for the
## same reason `buildings` is: a bare SquadSim still ticks.
var economy: Economy = null

## Players whose wallets changed on the most recent tick, so the server
## replicates only those — and only to their owner, since wallets are
## private (D-028).
var last_wallet_changes: Array = []
var replay: ReplayLog = null

## The combat resolver (D-024), owned here and driven once per tick. Split
## into its own file/class because it is a distinct concern from movement,
## not because it needs any state of its own — Combat is stateless and
## reads/writes squad state through this SquadSim.
var combat: Combat

## The vision field (D-025), owned here and rebuilt every
## `vision_recompute_every_ticks` ticks. Split into its own file for the
## same reason Combat is: a distinct concern from movement, driven through
## this SquadSim rather than carrying any state of its own beyond the
## coverage it stamps.
var vision: Vision

## How often (in ticks) the vision field recomputes (D-025 part 1).
## Deliberately decoupled from the 10 Hz sim tick (D-020) rather than
## rebuilt every tick: a squad covers at most a fraction of a cell in one
## tick at plausible roster speeds, which is small relative to a vision
## radius of several cells, so recomputing every tick would pay the full
## O(squads * radius^2) stamp cost repeatedly for a field that barely
## moved. Default 3 (~300 ms at 10 Hz): the staleness this introduces is
## bounded by how far a squad can move in 300 ms, which stays well under
## one cell for the roster's speeds against a multi-cell vision radius —
## negligible next to the 3x cut in rebuild cost. Tune down for a smaller,
## faster-moving roster; tune up if profiling shows the rebuild itself is
## the bottleneck.
var vision_recompute_every_ticks: int = 3

## Seeds every stochastic combat roll (D-024, D-016). Must come from map
## configuration, never from wall-clock time — server.gd sets this via
## NetProtocol.seed_from() before the sim starts ticking. Defaults to a
## fixed, non-zero value (rather than 0) so a SquadSim built without a
## server (tests, tools) still gets deterministic, reproducible combat.
var combat_seed: int = 1

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
var _defs: Array[UnitDef] = []
var _curves: Array[StateCurve] = []

# --- combat state (D-024, D-019) — per-SQUAD, not per-soldier, which is
# exactly what D-006 clause 1 permits (it forbids per-soldier integration
# state, not squad state; squads already carry position and destination).
var _morale := PackedFloat32Array()
var _routed := PackedByteArray()  # 0/1 — not bool, to stay a packed array
var _damage_accum := PackedFloat32Array()  # fractional casualties carried
var _last_attack_tick := PackedInt32Array()  # -1 = never attacked

# Stance (D-034). 1 means the squad is attack-moving and should halt the
# moment it finds something to fight; 0 means an ordinary move, which
# walks on through a fight. Per-squad, like everything else here.
var _attack_move := PackedByteArray()

## Casualty/rout events produced by the most recent tick's combat
## resolution — empty whenever nothing changed (D-026 criterion 3).
## server.gd reads this once per tick, right after calling tick(), and
## broadcasts it (filtered per client by visible_to()) before the state
## hash for that tick.
var last_combat_events: Array = []

# Flow fields are per DESTINATION and shared by every squad heading there
# (D-007). This dictionary is the thing that makes that claim real.
var _fields := {}

# --- measurement (D-012 / D-022 criterion 5) --------------------------
var last_tick_usec: int = 0
var total_tick_usec: int = 0
var fields_built: int = 0
var curves_rebuilt: int = 0
var vision_rebuilds: int = 0

## Vision and combat as identifiable COMPONENTS of last_tick_usec/
## total_tick_usec (D-026 criterion 10, D-020, D-012) — same accounting
## style, just scoped to the one phase each measures rather than the whole
## tick. `total_tick_usec` already includes both; these do not double the
## cost, they name a slice of it so a run can report "vision costs this
## much, combat costs this much" instead of only the tick's grand total.
var last_vision_usec: int = 0
var total_vision_usec: int = 0
var last_combat_usec: int = 0
var total_combat_usec: int = 0

var _validated := false

# Terrain passability. Empty means fully open, which is M1's case —
# terrain generation is explicitly out of M1's scope (D-022).
var _passable := PackedByteArray()


func _init(p_space: TorusSpace = null, p_replicator: CurveReplicator = null) -> void:
	space = p_space if p_space != null else TorusSpace.new()
	replicator = p_replicator if p_replicator != null else CurveReplicator.new()
	combat = Combat.new()
	vision = Vision.new()


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
	_defs.append(def)

	_morale.append(def.morale)
	_routed.append(0)
	_damage_accum.append(0.0)
	_last_attack_tick.append(-1)
	_attack_move.append(0)

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


## The actual UnitDef this squad was spawned from. Combat reads stats
## through this rather than UnitRoster.by_id(def_id_of(...)) — the roster
## does a directory scan and reload per call, which is fine for the rare
## SQUAD_INFO resolve but would reintroduce an O(n) cost per squad per
## tick into the one file this milestone is explicitly trying to keep
## cheap. Storing the reference the caller already handed add_squad() is
## free by comparison.
func def_of(squad: int) -> UnitDef:
	return _defs[squad]


## Cell index (not coordinate) — the allocation-free form Combat's bucket
## map is built from, same rationale as TorusSpace's own index-space hot
## path.
func cell_index_of(squad: int) -> int:
	return _cell[squad]


func morale_of(squad: int) -> float:
	return _morale[squad]


func set_morale(squad: int, value: float) -> void:
	_morale[squad] = value


func is_routed(squad: int) -> bool:
	return _routed[squad] == 1


func set_routed(squad: int, value: bool) -> void:
	_routed[squad] = 1 if value else 0


func damage_accum_of(squad: int) -> float:
	return _damage_accum[squad]


func set_damage_accum(squad: int, value: float) -> void:
	_damage_accum[squad] = value


func last_attack_tick_of(squad: int) -> int:
	return _last_attack_tick[squad]


func set_last_attack_tick(squad: int, value: int) -> void:
	_last_attack_tick[squad] = value


## Snapshots for Combat's before/after diff (see Combat._diff). Duplicated
## rather than referenced so mutating the live arrays during resolution
## can never retroactively change what "before" meant.
func alive_snapshot() -> PackedInt32Array:
	return _alive.duplicate()


func routed_snapshot() -> PackedByteArray:
	return _routed.duplicate()


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


## Issue a player move order. This is the invalidation event D-003 warns
## about: ordering many squads at once re-paths many curves in one tick,
## which is exactly what the replicator's budget exists to absorb.
##
## A routed squad ignores this (D-024, D-019): it is fleeing under its own
## steam and does not take player orders again until it rallies. That is
## enforced here, structurally, rather than left to callers to remember.
func order_move(squad: int, destination: Vector2i) -> void:
	if is_routed(squad):
		return
	_attack_move[squad] = 0
	_apply_move_order(squad, destination)


## Advance, but halt on contact (D-034). Combat clears the stance when it
## halts the squad, so the order is spent once it has done its job rather
## than sticking around to re-halt the squad every tick it stays engaged.
func order_attack_move(squad: int, destination: Vector2i) -> void:
	if is_routed(squad):
		return
	_apply_move_order(squad, destination)
	_attack_move[squad] = 1


func is_attack_moving(squad: int) -> bool:
	return _attack_move[squad] == 1


## Halt where the squad actually is (D-034).
##
## "Here" is resolved from the authoritative cell rather than from
## anything the client sent, because a client's view lags replication by
## up to a tick (D-002) — taking its word for a position would let a stop
## order teleport a squad backwards.
func stop(squad: int) -> void:
	if is_routed(squad):
		return
	_attack_move[squad] = 0
	_apply_move_order(squad, space.from_index(_cell[squad]))


## The move Combat issues when a squad routs. Bypasses the routed check
## that order_move enforces — that check exists specifically to block
## PLAYER orders, and fleeing away from the enemy is exactly what a
## routed squad is supposed to do, so it goes through the sim directly
## rather than through the player-facing entry point.
func force_move(squad: int, destination: Vector2i) -> void:
	_apply_move_order(squad, destination)


func _apply_move_order(squad: int, destination: Vector2i) -> void:
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

	# If the field could not take the squad a single step, the destination
	# is unreachable — walled off by water or mountains, which became
	# possible the moment the server started feeding terrain passability
	# into the sim. Give up on it by treating the current cell as the
	# destination.
	#
	# Without this the squad re-paths EVERY TICK forever: its curve holds
	# one keyframe, so `time >= curve.end_time()` is true immediately, and
	# tick() rebuilds again. That is an invalidation storm of one (D-003),
	# and it is not subtle — turning terrain on made curves_rebuilt jump
	# from 265 to 2,011 over a 40-second load test and doubled per-squad
	# cost, while every functional check stayed green. Terrain is static,
	# so unreachable now is unreachable later; there is nothing to retry.
	if curve.key_count() <= 1 and current != _destination[squad]:
		_destination[squad] = current

	_curves[squad] = curve
	replicator.set_curve(squad, curve)
	_log_curve(squad, curve)
	curves_rebuilt += 1


func _log_curve(squad: int, curve: StateCurve) -> void:
	if replay != null:
		replay.record(time, squad, replicator.version_of(squad), curve)


## Log this tick's casualty/rout events to the replay, if any — same
## rationale as _log_curve, and using NetProtocol's own encoder so the
## replay never describes a message shape the wire itself doesn't use
## (D-016, D-026 criterion 11). Skipped entirely when nothing changed, so
## an uneventful tick costs nothing in the replay either.
func _log_combat_events(events: Array) -> void:
	if replay == null or events.is_empty():
		return
	replay.record_combat(time, NetProtocol.encode_squad_combat(tick_count, events))


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

	# Vision (D-025) recomputes against THIS tick's freshly-derived
	# positions, at its own slower cadence — see
	# vision_recompute_every_ticks. Always stamped on the very first tick
	# so visible_to() is never answering from an empty field for a sim
	# that has ticked at least once.
	if tick_count == 1 or tick_count % vision_recompute_every_ticks == 0:
		var vision_started := Time.get_ticks_usec()
		vision.rebuild(self, buildings)
		last_vision_usec = Time.get_ticks_usec() - vision_started
		total_vision_usec += last_vision_usec
		vision_rebuilds += 1

	# Combat resolves against THIS tick's freshly-derived positions
	# (D-024), one round per 10 Hz tick (D-020's 100 ms minimum round
	# granularity). Casualties/rout events are sparse by construction —
	# empty whenever nothing changed (D-026 criterion 3) — so logging and
	# replication both skip the empty case rather than sending nothing
	# dressed up as a message.
	var combat_started := Time.get_ticks_usec()
	last_combat_events = combat.resolve(self, tick_count, 1.0 / TICK_HZ)

	# Buildings advance and shoot after the squad round (D-029). Their
	# casualty events merge into the same list, so they replicate through
	# the path clients already understand rather than needing a second
	# message — and a tick with neither kind of fighting still sends
	# nothing at all (D-003).
	if buildings != null:
		buildings.advance_construction(1.0 / TICK_HZ)

		# Production closes the loop: resources become squads (D-028).
		# Spawned next to the building that made them, which is why this
		# lives here rather than in BuildingSim — that class has no
		# SquadSim to put a squad into.
		for finished in buildings.advance_production(1.0 / TICK_HZ):
			var produced := UnitRoster.by_id(StringName(finished["def_id"]))
			if produced == null:
				push_error("SquadSim: building produced unknown unit '%s'" % finished["def_id"])
				continue
			var at: int = int(finished["building"])
			add_squad(produced, buildings.owner_of(at), buildings.cell_of(at) + Vector2i(1, 0))
		var building_events := combat.resolve_buildings(self, buildings, tick_count)
		if not building_events.is_empty():
			last_combat_events = last_combat_events + building_events

	# Hauling runs after combat, so a crew wiped out this tick does not
	# also deliver a load (D-028).
	last_wallet_changes = []
	if economy != null:
		last_wallet_changes = economy.tick(self, buildings, 1.0 / TICK_HZ)
	last_combat_usec = Time.get_ticks_usec() - combat_started
	total_combat_usec += last_combat_usec
	_log_combat_events(last_combat_events)

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


## Vision's own slice of mean_usec_per_squad_update (D-026 criterion 10) —
## same divisor (tick_count * squad_count), same "no squads means an honest
## zero, not a fixed-overhead spike" reasoning, just scoped to the vision
## rebuild phase so it's identifiable as a component rather than folded
## into the tick's grand total.
func mean_vision_usec_per_squad_update() -> float:
	if _cell.is_empty() or tick_count <= 0:
		return 0.0
	return float(total_vision_usec) / float(tick_count * _cell.size())


## Combat's own slice of mean_usec_per_squad_update (D-026 criterion 10) —
## see mean_vision_usec_per_squad_update's comment; same reasoning, scoped
## to Combat.resolve() instead of Vision.rebuild().
func mean_combat_usec_per_squad_update() -> float:
	if _cell.is_empty() or tick_count <= 0:
		return 0.0
	return float(total_combat_usec) / float(tick_count * _cell.size())


## Soldier transforms for a squad, derived not stored (D-006).
func soldier_transforms(squad: int, at_time: float = -1.0) -> Array[Transform3D]:
	var sample_at := time if at_time < 0.0 else at_time
	return Formation.soldier_transforms(
		_curves[squad], sample_at, _alive[squad], _shape[squad], _spacing[squad], space
	)


## Force an immediate vision rebuild, bypassing
## `vision_recompute_every_ticks`. Tests use this to get a deterministic,
## up-to-date field right after moving squads around, rather than ticking
## an arbitrary number of times and hoping the schedule has caught up.
func recompute_vision_now() -> void:
	vision.rebuild(self, buildings)


## How many of `player`'s squads still have soldiers in them.
##
## Elimination (D-033) reads this rather than keeping a parallel "is this
## player still alive" flag, so "defeated" has exactly one definition and
## cannot drift out of step with the simulation.
func living_squad_count(player: int) -> int:
	var n := 0
	for i in range(_cell.size()):
		if _owner[i] == player and _alive[i] > 0:
			n += 1
	return n


## Spend a squad founding something (D-031). Returns the casualty events
## describing it, or an empty array if there was nothing to consume.
##
## Consumed when the order is ACCEPTED, not when the building finishes.
## That timing is the whole mechanism: consuming on completion left the
## founders standing for the length of the build, and one founding party
## could queue as many town halls as it could click on — which is exactly
## what the first playtest did, three times in a row. Committing the party
## to the site immediately makes one founding party mean one town.
func consume_squad(squad: int) -> Array:
	if squad < 0 or squad >= _cell.size() or _alive[squad] <= 0:
		return []
	_alive[squad] = 0
	_routed[squad] = 0
	return [{"id": squad, "alive": 0, "routed": false}]


## Wipe out everything `player` owns, returning the casualty events that
## describes. Used when a player disconnects (D-033) — an abandoned army
## does not get to keep standing on the field.
##
## Returns Combat's own {id, alive, routed} shape deliberately, so the
## server broadcasts this through the existing casualty path rather than
## inventing a second message. Clients already know how to apply it, and
## the composition hash stays in agreement for free.
func eliminate_player(player: int) -> Array:
	var events := []
	for i in range(_cell.size()):
		if _owner[i] == player and _alive[i] > 0:
			_alive[i] = 0
			_routed[i] = 0
			events.append({"id": i, "alive": 0, "routed": false})
	return events


## Squad ids visible to `player` (D-025, closing D-022's "known stub").
## Always the player's own squads, plus any other squad sitting in a cell
## the player's vision field currently covers — a single O(1) lookup per
## squad into `vision`'s per-player coverage (Vision.is_visible), never a
## per-pair distance test. Fog of war is exactly this gate on top of
## D-003/D-004: no second data-hiding mechanism exists anywhere.
func visible_to(player: int) -> Array:
	var ids := []
	for i in range(_cell.size()):
		if _owner[i] == player or vision.is_visible(player, _cell[i]):
			ids.append(i)
	return ids
