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
## Squads whose shape changed and whose clients have not been told yet.
var _shape_dirty := {}
## Squads whose player has chosen a formation, and which therefore ignore
## the simulation's automatic switching (see set_shape/suggest_shape). A
## set rather than an array: it is read once per gathering crew per tick.
var _shape_chosen := {}
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

## Local BuildingSim ids destroyed by squads on the most recent tick.
## Not a wire message: BuildingSim.damage() already marks the building
## dirty, and the server replicates building state from take_dirty(). This
## is for the match rules and the log.
var destroyed_buildings: Array = []

## Local BuildingSim ids that finished construction on the most recent
## tick (BuildingSim.advance_construction's own return value, kept here
## for the same reason `destroyed_buildings` is: a wall-family building
## only blocks ground movement once complete — playtest fix, see
## BuildingSim.blocking_cells — so server.gd needs to know the moment one
## crosses that line to refresh passability, not just on a destruction.
var completed_buildings: Array = []

# Flow fields are per DESTINATION and shared by every squad heading there
# (D-007). This dictionary is the thing that makes that claim real.
var _fields := {}

# --- the wall-top tier (D-076) ------------------------------------------
#
# A squad's ELEVATION is real state — 0 (ground) or 1 (a wall-top) — but
# its POSITION within a tier is still derived from a curve exactly as
# D-006 requires. A tier change happens only as an explicit hop through an
# access tower's one door, never a smooth walk, so there is nowhere for a
# per-soldier integration value to hide: the render side reads (cell,
# tier) and derives a height from it, nothing more.

var _tier := PackedInt32Array()  # 0 = ground, 1 = wall-top, per squad

## Passability for the tier-1 network. Nonzero only on cells
## BuildingSim.walkable_top_cells() reports. Unlike `_passable`, EMPTY
## means "no walkway anywhere" rather than "fully open" — a bare SquadSim
## with no buildings has nothing to climb onto, where a bare SquadSim with
## no terrain has nowhere blocked.
var _passable_top := PackedByteArray()

## A second, independent FlowField cache (D-076), the class itself
## completely unmodified — keyed by tier-1 destination cell index.
## Deliberately NOT sharing `_fields`/`_pending_fields`/
## `field_cells_per_tick` with the ground layer: that budget is one
## counter shared by every in-flight field today, and a wall-top field
## solving on the same tick as a ground order wave would silently halve
## both layers' throughput.
var _fields_top := {}
var _pending_fields_top: Array[int] = []
var _field_cells_this_tick_top: int = 0

## Per-tick BFS cell budget for the tier-1 layer, separate from
## `field_cells_per_tick` for the reason above. Wall-top networks are tiny
## relative to the map — bounded by how many segments a player has built,
## not by map area — so a modest fixed budget is enough to solve one
## outright in a single tick in the ordinary case.
var top_field_cells_per_tick: int = 1024

## A cross-tier order in progress, per squad: the squad is walking to
## `_pending_tier_tower[squad]`'s door on its CURRENT tier and will hop to
## `_pending_tier_target[squad]` once it arrives, then continue toward
## `_pending_tier_destination[squad]` if that differs from the tower's own
## cell. -1 in `_pending_tier_target` means "nothing pending" — the same
## shape server.gd's `_pending_builds` uses for "walk there, then finish".
var _pending_tier_target := PackedInt32Array()
var _pending_tier_tower := PackedInt32Array()
var _pending_tier_destination := PackedInt32Array()

# --- measurement (D-012 / D-022 criterion 5) --------------------------
var last_tick_usec: int = 0
var total_tick_usec: int = 0
var fields_built: int = 0
var total_field_usec: int = 0
var curves_rebuilt: int = 0
var vision_rebuilds: int = 0

## Every phase of the tick as an identifiable COMPONENT of last_tick_usec/
## total_tick_usec (D-026 criterion 10, D-020, D-012) — same accounting
## style, just scoped to one region of `tick()` each rather than the whole
## tick. `total_tick_usec` already includes them all; these do not double
## the cost, they name slices of it.
##
## The phases PARTITION the tick, and that is the point of them
## (D-20260818): vision and combat were the only two ever reported, so a
## rise that landed anywhere else had nowhere to be seen. Whatever the
## named phases do not account for is reported as `other` — a residual
## that is computed, not assumed to be small, so the next unexplained
## number has a place to show up rather than hiding inside a total.
##
## `total_field_usec` cuts ACROSS this partition and is left alone: it
## counts BFS solving wherever it happens, which is the expansion phase
## below plus the field a curve rebuild starts inline. Divide it by
## `fields_built` for the cost of a field; use `total_fields_usec` for the
## cost of a tick's expansion slice.
var last_fields_usec: int = 0
var total_fields_usec: int = 0
var last_vision_usec: int = 0
var total_vision_usec: int = 0
var total_curves_usec: int = 0
var total_combat_usec: int = 0
var total_buildings_usec: int = 0
var total_production_usec: int = 0
var total_economy_usec: int = 0

var _validated := false

# Terrain passability. Empty means fully open, which is M1's case —
# terrain generation is explicitly out of M1's scope (D-022).
var _passable := PackedByteArray()

## Playtest fix: squad id -> destination cell INDEX, for an order
## `_rebuild_curve` gave up on as unreachable. D-040's give-up logic
## ("unreachable now is unreachable later") is only true for STATIC
## terrain; a gate (D-076) is passability that changes at runtime, so a
## squad ordered to the far side of a currently-CLOSED gate hit the same
## give-up path and had its order silently cancelled forever, even once
## the gate opened — the door "not working" was really an order that had
## already been thrown away. `set_passable` retries every entry here
## (see `_retry_deferred_orders`) instead of the squad waiting on nothing.
## Cleared for a squad the moment it receives any FRESH order
## (`_apply_move_order`), so a stale give-up can never override a player's
## newer one.
var _deferred_destination := {}


func _init(p_space: TorusSpace = null, p_replicator: CurveReplicator = null) -> void:
	space = p_space if p_space != null else TorusSpace.new()
	replicator = p_replicator if p_replicator != null else CurveReplicator.new()
	combat = Combat.new()
	vision = Vision.new()


func squad_count() -> int:
	return _cell.size()


func set_passable(p: PackedByteArray) -> void:
	_passable = p
	# Any cached field was solved against the old terrain — including any
	# still mid-solve, whose frontier holds a reference to the array that
	# just went stale (D-040).
	_fields.clear()
	_pending_fields.clear()
	_retry_deferred_orders()


## Re-issue every order `_rebuild_curve` gave up on (see
## `_deferred_destination`'s doc) now that passability has actually
## changed — a gate opening is exactly the kind of change that can turn a
## "permanently unreachable" verdict from ten ticks ago into a perfectly
## normal walk. Duplicated and cleared up front, not iterated in place:
## `order_move` below calls back into `_apply_move_order`, which erases a
## squad's entry the moment it gets ANY fresh destination — including this
## one — so mutating the live dict while walking it would skip entries.
func _retry_deferred_orders() -> void:
	if _deferred_destination.is_empty():
		return
	var retry := _deferred_destination.duplicate()
	_deferred_destination.clear()
	for squad in retry:
		var id: int = squad
		if id < 0 or id >= _cell.size() or alive_of(id) <= 0:
			continue
		order_move(id, space.from_index(int(retry[squad])))


## Tier-1 counterpart of `set_passable` (D-076) — same reasoning, scoped
## to the wall-top network: any cached tier-1 field was solved against the
## old set of walkway cells and must be dropped, not just left to expire.
func set_passable_top(p: PackedByteArray) -> void:
	_passable_top = p
	_fields_top.clear()
	_pending_fields_top.clear()


## Whether `cell` is walkable at tier 1. Empty `_passable_top` means "no
## walkway exists at all" — the opposite default from `is_passable`,
## because most sims (and every test that predates this feature) have no
## walls, and treating that as "everything climbable" would be wrong.
func is_passable_top(cell: Vector2i) -> bool:
	if _passable_top.is_empty():
		return false
	var index := space.index(cell)
	return index < _passable_top.size() and _passable_top[index] != 0


func tier_of(squad: int) -> int:
	return _tier[squad]


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

	_tier.append(0)
	_pending_tier_target.append(-1)
	_pending_tier_tower.append(-1)
	_pending_tier_destination.append(-1)

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


func shape_of(squad: int) -> String:
	return _shape[squad]


## Change a squad's formation (D-058).
##
## Shape is REPLICATED squad state and is part of `composition_hash`, so a
## change here has to reach every client that can see the squad or they
## will disagree with the server about what it looks like — and, because
## `Formation` derives soldier positions from it, about where every
## soldier in it is standing. `take_shape_dirty` is how the server finds
## out; that is the whole reason this cannot just assign to `_shape`.
##
## Ignores a no-op, so a caller may set the same shape every tick without
## generating wire traffic. That matters: the economy suggests a shape for
## a gathering crew on every tick (see `suggest_shape`).
##
## This is the PLAYER's entry point, and it latches: from here on the
## squad keeps the shape it was given and `suggest_shape` is ignored for
## it. Without the latch the economy re-asserted a gathering crew's shape
## on the very next tick, so a player pressing a formation button on
## workers saw it undone within 100 ms and concluded the button did
## nothing (D-058 amendment).
func set_shape(squad: int, shape: String) -> void:
	if squad < 0 or squad >= _shape.size():
		return
	# Latched even when the shape is unchanged: choosing the shape a squad
	# is already in is still a choice, and it must stop the economy
	# switching away from it on the next phase change.
	_shape_chosen[squad] = true
	_apply_shape(squad, shape)


## The SIMULATION's entry point for shape: a default, not an override.
##
## Identical to `set_shape` except that a squad whose player has chosen a
## formation ignores it. Automatic switching (D-058's ring-while-working)
## is a convenience for crews nobody has given an opinion about; a player
## who has expressed one outranks it, and keeps it for the rest of the
## match.
func suggest_shape(squad: int, shape: String) -> void:
	if squad < 0 or squad >= _shape.size() or _shape_chosen.has(squad):
		return
	_apply_shape(squad, shape)


func _apply_shape(squad: int, shape: String) -> void:
	if _shape[squad] == shape:
		return
	_shape[squad] = shape
	_shape_dirty[squad] = true
	# Soldier positions come from the shape, so the curve is unaffected but
	# anything caching a footprint is not.
	_dirty_footprint(squad)


## Squads whose shape changed since the last call, and clears the list.
## Same contract as BuildingSim.take_dirty, and for the same reason.
func take_shape_dirty() -> Array:
	var out := _shape_dirty.keys()
	_shape_dirty.clear()
	out.sort()
	return out


func _dirty_footprint(_squad: int) -> void:
	# Placeholder hook: Formation's footprint cache is keyed by
	# (shape, alive, spacing) and so needs no invalidation — a changed
	# shape simply looks up a different entry. Kept as a named seam so a
	# future per-squad cache cannot quietly go stale.
	pass


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
		out.append({
			"id": id, "def_id": String(_def_id[id]),
			"alive": _alive[id], "shape": _shape[id], "owner": _owner[id],
			# D-076: an explicit fact, not something inferred from a curve
			# going quiet — the same principle D-004/D-025 apply to conceal.
			"tier": _tier[id],
		})
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
## Squads that have ARRIVED do not stack: one settles onto a free cell
## nearby (D-060).
##
## ## Why on arrival, and not by spreading destinations
##
## Spreading at order time was the obvious version and it broke D-007:
## twenty squads sent to one point got twenty DIFFERENT destinations and
## therefore built twenty flow fields instead of sharing one. That
## sharing is the whole scaling claim, and `_quantise` (D-038) exists to
## force nearby orders onto the same destination for exactly this reason.
## An existing test caught it immediately.
##
## So travel is unchanged — one destination, one field, everybody walks
## the same way — and separation happens only where the pile-up actually
## shows: at the end.
##
## ## Why squad-granular and not per soldier
##
## The obvious fix for "units stack" is per-soldier collision, and D-006
## names that specifically as out of bounds: "local avoidance, collision
## push-back, jostling" each give a soldier integration state and fire the
## revisit trigger. That purity is what lets client and server agree on
## 40,000 soldier positions without sending any of them, which is not a
## small thing to trade for spacing.
##
## The GOAL though — armies taking up room instead of heaping — is a
## squad-level property, and squads are the atomic unit (D-005).
##
## Deterministic tie-break: the LOWER squad id keeps the cell and the
## higher one moves. Without that, two squads would each decide the other
## was there first and swap places forever.
func _separate_arrivals() -> void:
	var occupants := {}
	for i in range(_cell.size()):
		if _alive[i] <= 0:
			continue
		# Tier-1 squads are exempt (D-076): the wall-top network is small
		# and stacking there is expected, not something to shove aside —
		# see the plan's note that this is a visual concern to revisit
		# after looking at test-client output, not a capacity system.
		if _tier[i] != 0:
			continue
		# Only settled squads: one still walking is passing through, and
		# shoving it aside mid-journey is the per-tick avoidance D-006
		# rules out.
		if _cell[i] != _destination[i]:
			continue

		# A crew AT WORK is exempt, and this is not a nicety.
		#
		# Gathering requires standing on the node's own cell (D-028), and
		# several crews working one node is both normal and desirable. The
		# first version separated them anyway: a displaced crew could never
		# reach the gathering phase, so it hauled nothing, forever. The
		# ladder showed 22 gatherer squads and a stockpile that never rose
		# above the STARTING 480 — an economy that looked staffed and was
		# producing literally nothing.
		if economy != null and economy.is_gathering(i):
			continue
		var cell := _cell[i]
		if not occupants.has(cell):
			occupants[cell] = i
			continue

		# Someone is already here. Lower id stays.
		var sitting: int = occupants[cell]
		var mover := i if i > sitting else sitting
		if mover == sitting:
			occupants[cell] = i
		var spot := _free_cell_near(space.from_index(cell), mover)
		if spot != space.from_index(cell):
			_destination[mover] = space.index(spot)
			_rebuild_curve(mover)


## The nearest cell to `cell` that no living squad is sitting on.
func _free_cell_near(cell: Vector2i, asking: int) -> Vector2i:
	for offset in TorusSpace.disk_offsets(4):
		var candidate := space.normalize(cell + offset)
		if not is_passable(candidate):
			continue
		var index := space.index(candidate)
		var taken := false
		for i in range(_cell.size()):
			if i != asking and _alive[i] > 0 and _cell[i] == index:
				taken = true
				break
		if not taken:
			return candidate
	# Nowhere free within reach: standing too close beats never settling.
	return cell


## `cell` if a squad can stand there, otherwise the nearest cell it can.
##
## Walks outward in `disk_offsets` order, which is deterministic, so two
## squads ordered onto the same wall pick the same approach and a replay
## reproduces it. Gives up after a few rings and returns the original —
## somewhere sealed off is better handled by the squad failing to arrive
## than by searching the whole map every order.
## `tier` (D-076): 0 checks ground passability, 1 checks the wall-top
## network. Defaulted to 0 so every pre-existing call site (ground-only,
## from before tiers existed) is unaffected.
func _approachable(cell: Vector2i, tier: int = 0) -> Vector2i:
	if is_passable(cell, tier):
		return cell
	for offset in TorusSpace.disk_offsets(3):
		var candidate := space.normalize(cell + offset)
		if is_passable(candidate, tier):
			return candidate
	return cell


## Whether a squad may stand on a cell: terrain only.
##
## Empty GROUND passability means fully open, which is what a bare
## SquadSim in a test gets. `tier` 1 defers to `is_passable_top`, whose
## empty-array default is the OPPOSITE (D-076) — see that function.
func is_passable(cell: Vector2i, tier: int = 0) -> bool:
	if tier == 1:
		return is_passable_top(cell)
	if _passable.is_empty():
		return true
	var index := space.index(cell)
	return index < _passable.size() and _passable[index] != 0


## A cell just outside a building, for a squad that has just been made
## there — walkable, not underneath the building, and not inside another.
##
## Walks the hex ring at increasing radius, so it prefers to stand a new
## squad right at the door and only spreads out when the door is blocked.
## Deterministic: `disk_offsets` enumerates in a fixed order, so server and
## replay agree about where a unit appeared.
func _spawn_cell_near(buildings: BuildingSim, building: int) -> Vector2i:
	var home := buildings.cell_of(building)
	for offset in TorusSpace.disk_offsets(4):
		if TorusSpace.hex_length(offset) < 2:
			continue  # under the building itself
		var candidate := space.normalize(home + offset)
		if not is_passable(candidate):
			continue
		if buildings.building_at(candidate) >= 0:
			continue
		return candidate
	# Hemmed in on every side: put them at the door anyway rather than
	# losing a squad somebody paid for.
	return space.normalize(home + Vector2i(2, 0))


## Issue a player move order (see the class-level docs below for the full
## reasoning on separation/quantisation).
##
## D-076: the target TIER is inferred from the destination cell itself —
## a click on a cell `BuildingSim.is_walkable_top_cell` reports is "go up
## there", any other cell is "go down there" — rather than a parameter a
## caller has to pass. That is what keeps this signature, and therefore
## every existing call site and every wire order that reaches it, exactly
## as it was before the wall-top tier existed. If the squad is already on
## the tier the destination implies, this is an ordinary same-tier move;
## otherwise it is a cross-tier request, handled by `_begin_tier_crossing`.
func order_move(squad: int, destination: Vector2i) -> void:
	if is_routed(squad):
		return
	_attack_move[squad] = 0
	var wanted_tier := _tier_for_destination(destination)
	if wanted_tier == _tier[squad]:
		_pending_tier_target[squad] = -1
		_apply_move_order(squad, destination, true)
		return
	_begin_tier_crossing(squad, destination, wanted_tier)


## Advance, but halt on contact (D-034). Combat clears the stance when it
## halts the squad, so the order is spent once it has done its job rather
## than sticking around to re-halt the squad every tick it stays engaged.
##
## Tier inference (D-076) works exactly as `order_move`'s does — see there.
func order_attack_move(squad: int, destination: Vector2i) -> void:
	if is_routed(squad):
		return
	var wanted_tier := _tier_for_destination(destination)
	if wanted_tier == _tier[squad]:
		_pending_tier_target[squad] = -1
		_apply_move_order(squad, destination, true)
	else:
		_begin_tier_crossing(squad, destination, wanted_tier)
	_attack_move[squad] = 1


## Which tier `destination` belongs to (D-076): 1 if it is a cell on the
## wall-top network, 0 otherwise. A bare SquadSim with no `buildings`
## always answers 0 — there is nothing to climb onto.
func _tier_for_destination(destination: Vector2i) -> int:
	if buildings == null:
		return 0
	return 1 if buildings.is_walkable_top_cell(space.index(destination)) else 0


## Start (or restart) a cross-tier move (D-076): walk to the nearest
## reachable access tower's door on the squad's CURRENT tier, then hop and
## continue toward `destination` on `wanted_tier` once there. Not a
## unified BFS graph — `FlowField` itself is never modified for this, only
## driven twice — this is an explicit two-leg order, the same "walk there,
## then finish" shape `server.gd`'s `_pending_builds` already uses for
## out-of-reach construction.
func _begin_tier_crossing(squad: int, destination: Vector2i, wanted_tier: int) -> void:
	var tower := _nearest_door_tower(squad, wanted_tier)
	if tower < 0:
		# Nothing to climb via. Degrades like any other unreachable order —
		# the squad simply keeps doing whatever it was already doing.
		return
	_pending_tier_target[squad] = wanted_tier
	_pending_tier_tower[squad] = tower
	_pending_tier_destination[squad] = space.index(destination)
	# Walk to the cell the squad must be standing on BEFORE the hop, on its
	# CURRENT tier: the door (ground) when climbing, the tower's own cell
	# (tier-1) when descending — `_advance_tier_transitions` checks arrival
	# against this same cell, so the two must agree on which one it is.
	var walk_to := buildings.door_cell_of(tower) if wanted_tier == 1 \
		else buildings.cell_index_of(tower)
	_apply_move_order(squad, space.from_index(walk_to), true)


## Nearest access tower whose door can carry the squad from its CURRENT
## tier to `wanted_tier` (D-076): the door's ground-side cell when
## climbing (tier 0 -> 1), the tower's own tier-1 cell when descending
## (tier 1 -> 0). Straight cell distance, not tier-1 reachability — an
## unreachable pick simply never arrives, the same as any other walled-off
## order (`_rebuild_curve`'s give-up rule already handles that).
func _nearest_door_tower(squad: int, wanted_tier: int) -> int:
	if buildings == null:
		return -1
	var from := cell_of(squad)
	var best := -1
	var best_distance := -1
	for i in range(buildings.building_count()):
		var door := buildings.door_cell_of(i)
		if door < 0:
			continue
		var from_cell := door if wanted_tier == 1 else buildings.cell_index_of(i)
		var d := space.distance(from, space.from_index(from_cell))
		if best == -1 or d < best_distance:
			best = i
			best_distance = d
	return best


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
	# A squad mid-approach to a tower's door is stopping short of climbing
	# it (D-076) — the same "an order in progress is spent" rule a move
	# order already applies to server.gd's _pending_builds.
	_pending_tier_target[squad] = -1
	_apply_move_order(squad, space.from_index(_cell[squad]))


## The move Combat issues when a squad routs. Bypasses the routed check
## that order_move enforces — that check exists specifically to block
## PLAYER orders, and fleeing away from the enemy is exactly what a
## routed squad is supposed to do, so it goes through the sim directly
## rather than through the player-facing entry point.
## How coarsely a ROUT's destination is snapped (D-038).
##
## Routing is where unique destinations come from: a broken squad flees to
## its own computed cell, so a rout produces one full flow-field solve PER
## SQUAD — and routs happen during exactly the large engagements that are
## already re-pathing everyone.
##
## Unlike a player's order, a rout has no exact destination worth
## preserving. The squad is running away; where it stops is a detail
## nobody chose. Snapping coarsely makes a whole routing army share a
## handful of fields instead of one each, which is the same D-007 sharing
## that already works for deliberate orders.
var rout_quantum: int = 8


## Flee, sharing a field with everyone fleeing the same way.
func flee_move(squad: int, destination: Vector2i) -> void:
	var previous := destination_quantum
	destination_quantum = rout_quantum
	_apply_move_order(squad, destination, true)
	destination_quantum = previous


func force_move(squad: int, destination: Vector2i) -> void:
	_apply_move_order(squad, destination)


## Snap a destination to a coarse grid (D-038).
##
## Two orders a few cells apart would otherwise solve two entire flow
## fields. Snapped, they share one, and D-007's per-destination sharing
## does the rest — this converts field builds from per-CLICK to
## per-REGION, which is the cheap attack on the 437 ms order-wave spike.
##
## The squad ends up at the bucket's cell rather than the exact click.
## For a squad whose soldiers already spread over several cells that is
## imperceptible; it is a trade of a little path precision for a large
## amount of peak cost.
func _quantise(cell: Vector2i) -> Vector2i:
	if destination_quantum <= 1:
		return cell
	var c := space.normalize(cell)
	return Vector2i(
		(c.x / destination_quantum) * destination_quantum,
		(c.y / destination_quantum) * destination_quantum)


## `quantise` is false for orders that must land EXACTLY where asked.
## Stop means stop where you stand — snapping it would shove the squad to
## a bucket corner. Gathering must reach the node's own cell or the squad
## never registers as arrived and never starts work.
func _apply_move_order(squad: int, destination: Vector2i, quantise := false) -> void:
	# An order onto ground nobody can stand on becomes an order to the
	# nearest ground they can.
	#
	# Buildings block movement now, so their cells are impassable — and
	# without this, right-clicking a town hall, or a gatherer hauling to a
	# storehouse, would set a destination the flow field can never reach
	# and the squad would simply never move. Handled HERE rather than at
	# each call site because there are four of them (player orders,
	# attack-moves, rally points, hauling) and three would have been fixed.
	#
	# D-076: resolved against the squad's OWN tier, not always ground —
	# `_rebuild_curve` reads `_tier[squad]` the same way to pick which
	# passability/field layer serves the rest of this order.
	var tier := _tier[squad]
	var wanted := _quantise(destination) if quantise else destination
	var dest_index := space.index(_approachable(wanted, tier))
	if _destination[squad] == dest_index:
		return
	_destination[squad] = dest_index
	# A fresh order always supersedes whatever _rebuild_curve may have
	# given up on earlier — see _deferred_destination's doc. Without this,
	# a later gate opening could resurrect and re-issue an order the
	# player had already replaced with a different one.
	_deferred_destination.erase(squad)
	_rebuild_curve(squad)


## Shared per-destination flow field, built on demand (D-007).
## How many NEW flow fields may be solved in one tick (D-038).
##
## A build is a wrap-aware BFS over every cell — about 2 µs per cell, so
## 17 ms on the current 8,192-cell map and 67 ms at 32,768. One is
## affordable; several in the same tick is D-003's invalidation storm with
## a number attached, and a large engagement re-paths many squads at once.
##
## Budgeting them bounds the spike without touching the algorithm. A squad
## that cannot get a field this tick keeps walking its existing curve and
## retries — it already tolerates a tick of latency before its curve is
## extended, which is exactly the slack this spends.
## 0 means unlimited, which is the DEFAULT because measurement said so.
##
## Budgeting to 2/tick was tried and made things markedly worse: with
## every squad heading somewhere different, 250 squads competed for 2
## builds, and each deferred squad retried on every subsequent tick. Worst
## tick went from 41 ms to 58 ms and 31,413 deferrals accumulated — a
## thundering herd, where the throttle cost more than the work it was
## throttling.
##
## Kept as a safety valve rather than deleted, because it is the right
## shape for a genuine storm; it is simply not the right default. The
## actual mitigation is destination SHARING (D-007) — one field serves
## every squad heading to the same place, and a player ordering a group
## somewhere produces exactly one build.
var fields_per_tick: int = 0

## Grid size destinations snap to before pathing (D-038).
##
## **1 (disabled) is the default, because measurement said the trade was
## not worth it.** Snapping to a 4-cell grid was tried against the
## order-wave spike and bought about 18% of the worst tick at the shipped
## map size (457 ms → 375 ms) — nowhere near the 4.4x needed — while
## costing something real: a squad stops arriving where it was ordered,
## which broke two tests that were right to break.
##
## Field BUILD COUNT barely moved (186 → 198), which is the informative
## part: if merging nearby destinations does not reduce builds, then most
## builds are not coming from nearby player orders at all. The suspect is
## routing — `Combat._check_rout` sends each broken squad fleeing to its
## own computed cell via force_move, so a rout produces one unique
## destination PER SQUAD, which is precisely the pattern D-007's sharing
## cannot help with.
##
## Kept, disabled, because it is cheap to switch on if a future workload
## is genuinely dominated by clustered player orders.
var destination_quantum: int = 1
var _fields_built_this_tick: int = 0

## Squads that wanted a field and did not get one. Counted rather than
## silently dropped: if this stays high, the budget is too tight and the
## symptom would otherwise be squads mysteriously slow to turn.
var field_builds_deferred: int = 0


## How many BFS frontier cells may be expanded per tick, across ALL
## in-flight fields (D-040). -1 disables amortisation entirely and every
## field completes in the tick it is requested.
##
## 4,096 is half a ship-map field, so an ordinary single order paths in
## two ticks (0.2 s) — below noticing — and an eight-destination wave
## drains over about a second with the FIRST group moving immediately,
## because the queue is FIFO.
##
## Chosen by measurement, not by argument. At 1,000 squads on the ship
## map, the worst tick was 1,226 ms unamortised, 103 ms at a budget of
## 12,288, and **72.8 ms at 4,096** — the first value that fits D-020's
## 100 ms tick at D-018's full scale, with ~27% headroom. The cost is
## about 9% on average tick time, which is the right way round: the
## budget being blown was always a latency spike, never throughput.
const DEFAULT_FIELD_CELLS_PER_TICK := 4096
var field_cells_per_tick: int = DEFAULT_FIELD_CELLS_PER_TICK

## Destination indices whose fields are still expanding, oldest first.
##
## FIFO rather than "nearest first" or "most squads waiting first": every
## ordering heuristic tried here would need a squad-to-field index to
## evaluate, and the queue is only ever a handful deep because a wave
## drains in a few ticks. Finishing the oldest first also bounds the worst
## wait, which is the number that matters — the spike was never about
## throughput.
var _pending_fields: Array[int] = []

## Cells expanded so far this tick, against `field_cells_per_tick`.
var _field_cells_this_tick: int = 0

## Per-phase cost of the LAST tick, for attributing a spike to a phase
## instead of guessing at one. Same regions as the run totals above, so
## the two lines a server prints — the over-budget spike and the final
## summary — name the same phases. `last_production_usec` is a slice of
## `last_buildings_usec`, not a phase beside it.
var last_curves_usec: int = 0
var last_economy_usec: int = 0
var last_squad_combat_usec: int = 0
var last_buildings_usec: int = 0
var last_production_usec: int = 0

## How many ticks ended with at least one field still expanding. If this
## sits near zero the budget is never binding; if it climbs with squad
## count, the budget is too tight and squads are waiting to path.
var ticks_with_pending_fields: int = 0

## Squads that could not path this tick because their field had not
## reached them yet. The honest cost of amortisation, counted rather than
## assumed to be small.
var field_waits: int = 0


## Spend this tick's expansion budget on fields still being built.
##
## Called at the START of tick, so a field begun on a previous tick makes
## progress before any squad asks it for a direction.
func _expand_pending_fields() -> void:
	_field_cells_this_tick = 0
	if _pending_fields.is_empty():
		return

	var started := Time.get_ticks_usec()
	var still_pending: Array[int] = []
	for destination_index in _pending_fields:
		var field: FlowField = _fields.get(destination_index, null)
		if field == null or field.is_complete():
			continue
		var remaining := _field_budget_remaining()
		if remaining == 0:
			# Out of budget: keep it queued, untouched, for next tick.
			still_pending.append(destination_index)
			continue
		var before := field.expanded_cells()
		if not field.expand(remaining):
			still_pending.append(destination_index)
		# Charge what was actually expanded, not the budget offered — a
		# field that finishes early must not consume the whole allowance
		# and starve the next one in the same wave.
		_field_cells_this_tick += field.expanded_cells() - before
	_pending_fields = still_pending
	total_field_usec += Time.get_ticks_usec() - started

	if not _pending_fields.is_empty():
		ticks_with_pending_fields += 1


func _field_budget_remaining() -> int:
	if field_cells_per_tick < 0:
		return -1
	return maxi(0, field_cells_per_tick - _field_cells_this_tick)


## `tier` (D-076): 0 is the ground layer, unchanged from before tiers
## existed; 1 dispatches to `_field_for_top`, a completely separate cache
## and budget — see that function and `_fields_top`'s own doc for why.
func _field_for(destination_index: int, tier: int = 0) -> FlowField:
	if tier == 1:
		return _field_for_top(destination_index)

	if _fields.has(destination_index):
		return _fields[destination_index]

	if fields_per_tick > 0 and _fields_built_this_tick >= fields_per_tick:
		field_builds_deferred += 1
		return null
	_fields_built_this_tick += 1
	# Timed separately because this is the one kernel D-021 names as its
	# GDExtension candidate: a wrap-aware BFS over every cell, rebuilt per
	# destination. Whether it needs escaping to native code is an M4
	# question with a number attached, not a matter of opinion.
	var started := Time.get_ticks_usec()
	var field := FlowField.new()
	field.begin(space, space.from_index(destination_index), _passable)
	# Expand into whatever budget this tick has left. In a quiet tick that
	# is the whole field and the amortisation is invisible; in a wave, the
	# later fields get little or nothing here and finish over the next few
	# ticks.
	if not field.expand(_field_budget_remaining()):
		_pending_fields.append(destination_index)
	_field_cells_this_tick += field.expanded_cells()
	total_field_usec += Time.get_ticks_usec() - started

	_fields[destination_index] = field
	fields_built += 1
	return field


## Tier-1 counterpart of `_field_for` (D-076) — same `FlowField` class,
## unmodified, but its own dictionary, its own pending queue and its own
## per-tick cell budget (`top_field_cells_per_tick`), not the ground
## layer's. No `fields_per_tick` build-count throttle here: wall-top
## networks are small enough that it has never been needed.
func _field_for_top(destination_index: int) -> FlowField:
	if _fields_top.has(destination_index):
		return _fields_top[destination_index]

	var field := FlowField.new()
	field.begin(space, space.from_index(destination_index), _passable_top)
	var remaining := maxi(0, top_field_cells_per_tick - _field_cells_this_tick_top)
	if not field.expand(remaining):
		_pending_fields_top.append(destination_index)
	_field_cells_this_tick_top += field.expanded_cells()

	_fields_top[destination_index] = field
	fields_built += 1
	return field


## Tier-1 counterpart of `_expand_pending_fields` (D-076) — identical
## shape, over the tier-1 dictionary/queue/budget instead of the ground
## ones.
func _expand_pending_fields_top() -> void:
	_field_cells_this_tick_top = 0
	if _pending_fields_top.is_empty():
		return

	var still_pending: Array[int] = []
	for destination_index in _pending_fields_top:
		var field: FlowField = _fields_top.get(destination_index, null)
		if field == null or field.is_complete():
			continue
		var remaining := maxi(0, top_field_cells_per_tick - _field_cells_this_tick_top)
		if remaining == 0:
			still_pending.append(destination_index)
			continue
		var before := field.expanded_cells()
		if not field.expand(remaining):
			still_pending.append(destination_index)
		_field_cells_this_tick_top += field.expanded_cells() - before
	_pending_fields_top = still_pending


## Write the squad's planned path into its curve, starting from where it
## is *now*. Keyframes are one per cell, timed by the squad's speed.
func _rebuild_curve(squad: int) -> void:
	var curve := StateCurve.new()
	var current := _cell[squad]
	var at := time
	curve.append_cell(at, space.from_index(current), space)

	var speed := _speed[squad]
	if speed > 0.0 and _destination[squad] != current:
		# D-076: the squad's OWN tier picks which layer serves this path —
		# ground or the wall-top network. A squad never silently crosses
		# tiers here; that only happens through `_advance_tier_transitions`.
		var field := _field_for(_destination[squad], _tier[squad])
		# No field this tick (budgeted — see fields_per_tick). Leave the
		# existing curve alone and try again next tick, rather than
		# stranding the squad with a one-keyframe curve it would then
		# rebuild every tick forever.
		if field == null:
			return

		# The field exists but its wavefront has not reached this squad yet
		# (D-040). Leave the curve alone and try again next tick — the
		# squad keeps moving on whatever path it already had.
		#
		# This MUST come before the give-up rule at the bottom of this
		# function. That rule reads "the field cannot move this squad" as
		# "the destination is unreachable" and cancels the order, which is
		# right for a finished field and catastrophic for an unfinished
		# one: every squad in an order wave would have its order silently
		# dropped in the tick it was issued.
		if not field.covers(current) and not field.is_complete():
			field_waits += 1
			return

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
	# is unreachable RIGHT NOW — walled off by water or mountains, or
	# (D-076) by a closed gate. Give up on it by treating the current cell
	# as the destination, exactly as before.
	#
	# Without this the squad re-paths EVERY TICK forever: its curve holds
	# one keyframe, so `time >= curve.end_time()` is true immediately, and
	# tick() rebuilds again. That is an invalidation storm of one (D-003),
	# and it is not subtle — turning terrain on made curves_rebuilt jump
	# from 265 to 2,011 over a 40-second load test and doubled per-squad
	# cost, while every functional check stayed green. For pure terrain,
	# unreachable now is unreachable later and there is nothing to retry —
	# but a gate is passability that changes at runtime, and treating its
	# "unreachable now" as forever was a real bug: an order given while a
	# gate happened to be closed was cancelled and never revisited even
	# once the gate opened. So the ORIGINAL destination is stashed before
	# being overwritten — see _deferred_destination's doc — and
	# `set_passable` retries it the moment passability actually changes.
	# That retry is what keeps this cheap: nothing re-attempts on its own
	# every tick, only when something could plausibly have unblocked it.
	if curve.key_count() <= 1 and current != _destination[squad]:
		_deferred_destination[squad] = _destination[squad]
		_destination[squad] = current

	_curves[squad] = curve
	replicator.set_curve(squad, curve)
	_log_curve(squad, curve)
	curves_rebuilt += 1


func _log_curve(squad: int, curve: StateCurve) -> void:
	if replay != null:
		replay.record(time, squad, replicator.version_of(squad), curve)


## Complete any cross-tier move whose squad has now reached its tower's
## door (D-076). Runs once per tick, after positions are derived from
## curves — the same "cheap because the array is normally all -1" shape
## `server.gd`'s `_advance_pending_builds` uses for its own two-leg orders.
func _advance_tier_transitions() -> void:
	for squad in range(_cell.size()):
		if _pending_tier_target[squad] < 0:
			continue
		if _alive[squad] <= 0:
			_pending_tier_target[squad] = -1
			continue
		if _cell[squad] != _destination[squad]:
			continue  # still walking to the door

		var tower := _pending_tier_tower[squad]
		var wanted_tier := _pending_tier_target[squad]
		_pending_tier_target[squad] = -1
		if buildings == null or tower < 0 or buildings.is_destroyed(tower) \
				or not buildings.is_complete(tower):
			continue  # the tower is gone; the order simply lapses

		var door := buildings.door_cell_of(tower)
		var tower_cell := buildings.cell_index_of(tower)
		if door < 0:
			continue
		# The cell the squad must be standing on to hop, on its CURRENT
		# tier — the door when climbing, the tower's own cell when
		# descending. Must match `_begin_tier_crossing`'s `walk_to` exactly,
		# or a squad already sitting on the departure cell (the ordinary
		# case for a descend, since it is already standing on the tower)
		# would never be recognised as having "arrived".
		var departure := door if wanted_tier == 1 else tower_cell
		if _cell[squad] != departure:
			# Arrival snapped somewhere other than the departure cell (e.g.
			# it became briefly unreachable and _approachable picked a
			# neighbour) — do not hop from the wrong cell.
			continue

		_tier[squad] = wanted_tier
		var landing := tower_cell if wanted_tier == 1 else door
		_cell[squad] = landing
		_teleport_curve(squad, landing)

		var final_destination := _pending_tier_destination[squad]
		if final_destination != landing:
			_apply_move_order(squad, space.from_index(final_destination), true)
		else:
			_destination[squad] = landing


## An instantaneous hop's curve: one keyframe at the new cell, exactly the
## shape `add_squad` gives a freshly spawned squad. Climbing/descending is
## a discrete event (D-076), not a walked, curve-interpolated transition —
## the whole reason it is legal under D-006 is that there is nowhere for a
## partial-climb integration value to live.
func _teleport_curve(squad: int, cell_index: int) -> void:
	var curve := StateCurve.new()
	curve.append_cell(time, space.from_index(cell_index), space)
	_curves[squad] = curve
	replicator.set_curve(squad, curve)
	_log_curve(squad, curve)


## Any squad standing at tier 1 whose cell no longer has a living
## `walkable_top` structure under it — its tower or wall segment was just
## destroyed — is dropped to the nearest passable GROUND cell (D-076).
## Evicted alive, not killed: losing the structure is punishing enough
## without an invisible instant-kill riding along on top of it. Called
## only when something was actually destroyed this tick, so it costs
## nothing on every ordinary tick.
func _evict_stranded_tier1_squads() -> void:
	for squad in range(_cell.size()):
		if _tier[squad] != 1 or _alive[squad] <= 0:
			continue
		if buildings != null and buildings.is_walkable_top_cell(_cell[squad]):
			continue
		_tier[squad] = 0
		var spot := space.index(_free_cell_near(space.from_index(_cell[squad]), squad))
		_cell[squad] = spot
		_teleport_curve(squad, spot)
		_destination[squad] = spot
		_pending_tier_target[squad] = -1


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

	# Fresh field-build budget each tick (D-038).
	_fields_built_this_tick = 0

	# Push in-flight BFS solves forward before anything asks a field for a
	# direction (D-040). Also resets this tick's cell budget, so it must
	# run even when nothing is pending.
	#
	# Timed as a phase of its own, because it is a phase of its own: the
	# budget is per TICK, so this slice costs what it costs whether one
	# squad or fifty is waiting on it, and until D-20260818 it was charged
	# to nothing at all.
	var fields_started := Time.get_ticks_usec()
	_expand_pending_fields()
	_expand_pending_fields_top()  # D-076: its own budget, see that function
	last_fields_usec = Time.get_ticks_usec() - fields_started
	total_fields_usec += last_fields_usec

	time += 1.0 / TICK_HZ
	tick_count += 1

	var curves_started := Time.get_ticks_usec()
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

	# Squads that have arrived shuffle off each other's cell (D-060), so
	# an army settles as a body rather than a heap. Only touches squads
	# already at their destination, so it costs nothing while everyone is
	# walking and never interferes with a journey in progress.
	_separate_arrivals()

	# A squad that just reached a tower's door hops tiers here (D-076) —
	# after positions are derived and arrivals settle, so it acts on this
	# tick's real position, and before vision/combat see the result.
	_advance_tier_transitions()

	last_curves_usec = Time.get_ticks_usec() - curves_started
	total_curves_usec += last_curves_usec

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

	# Idle combat squads chase a nearby enemy rather than waiting for one to
	# walk all the way into attack_range — the default "for now" stance
	# (see combat.gd's assign_idle_engagements). Runs after resolve() so it
	# can see this tick's _engaged set and skip anyone already fighting
	# where they stand, and reuses resolve()'s bucket map rather than
	# rebuilding one.
	combat.assign_idle_engagements(self, tick_count)
	# Both halves of the combat phase, not just resolve(): the assignment
	# scan is combat work and would otherwise land in the residual.
	last_squad_combat_usec = Time.get_ticks_usec() - combat_started
	total_combat_usec += last_squad_combat_usec

	var buildings_started := Time.get_ticks_usec()

	# Buildings advance and shoot after the squad round (D-029). Their
	# casualty events merge into the same list, so they replicate through
	# the path clients already understand rather than needing a second
	# message — and a tick with neither kind of fighting still sends
	# nothing at all (D-003).
	if buildings != null:
		completed_buildings = buildings.advance_construction(1.0 / TICK_HZ)

		# Production closes the loop: resources become squads (D-028).
		# Spawned next to the building that made them, which is why this
		# lives here rather than in BuildingSim — that class has no
		# SquadSim to put a squad into.
		var production_started := Time.get_ticks_usec()
		for finished in buildings.advance_production(1.0 / TICK_HZ):
			var produced := UnitRoster.by_id(StringName(finished["def_id"]))
			if produced == null:
				push_error("SquadSim: building produced unknown unit '%s'" % finished["def_id"])
				continue
			var at: int = int(finished["building"])
			# Clear of the building, then walk to its rally point.
			#
			# This used to be `cell + (1, 0)` — one hex from the building's
			# centre, which is INSIDE the box drawn on top of it, because a
			# building's mesh is wider than a hex. Units appeared standing
			# in the wall of the thing that made them.
			var door := _spawn_cell_near(buildings, at)
			var spawned := add_squad(produced, buildings.owner_of(at), door)
			var rally := buildings.rally_of(at)
			if rally != door:
				order_move(spawned, rally)
		last_production_usec = Time.get_ticks_usec() - production_started
		total_production_usec += last_production_usec
		var building_events := combat.resolve_buildings(self, buildings, tick_count)
		if not building_events.is_empty():
			last_combat_events = last_combat_events + building_events

		# ...and squads shoot back. Needs no event list of its own:
		# BuildingSim.damage() marks the building dirty, and take_dirty()
		# is already what the server replicates building state from, so a
		# destruction reaches clients through the path that already
		# existed for it. `destroyed_buildings` is published for the match
		# rules and the log, not for the wire.
		destroyed_buildings = combat.resolve_squads_vs_buildings(
			self, buildings, tick_count)

		# A tower or wall segment razed this tick may have had a squad
		# standing on top of it (D-076) — drop them to the ground rather
		# than leaving them stranded at tier 1 on top of rubble.
		if not destroyed_buildings.is_empty():
			_evict_stranded_tier1_squads()

	# Hauling runs after combat, so a crew wiped out this tick does not
	# also deliver a load (D-028).
	last_buildings_usec = Time.get_ticks_usec() - buildings_started
	total_buildings_usec += last_buildings_usec

	last_wallet_changes = []
	var economy_started := Time.get_ticks_usec()
	if economy != null:
		last_wallet_changes = economy.tick(self, buildings, 1.0 / TICK_HZ)
	last_economy_usec = Time.get_ticks_usec() - economy_started
	total_economy_usec += last_economy_usec
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
	return _mean_usec_per_squad_update(total_vision_usec)


## Combat's own slice of mean_usec_per_squad_update (D-026 criterion 10) —
## see mean_vision_usec_per_squad_update's comment; same reasoning, scoped
## to the combat phase (Combat.resolve plus the idle-engagement scan)
## instead of Vision.rebuild().
##
## It covered building advance, production and hauling too until
## D-20260818, which is how a run could report "combat=32.7" for a tick in
## which combat was a third of that: the phases now partition the tick
## instead of two of them overlapping the rest.
func mean_combat_usec_per_squad_update() -> float:
	return _mean_usec_per_squad_update(total_combat_usec)


## THE breakdown of mean_usec_per_squad_update, phase by phase, in tick
## order (D-20260818). Keys sum to that figure exactly, because `other` is
## the difference rather than an estimate — so a rise always lands on a
## named phase or on the residual, and never simply vanishes into the
## total the way M6's 40.8 -> ~77 and M10's 83 -> 167.7 both did.
##
## `production` is a slice of `buildings` and is reported alongside rather
## than summed; everything else is disjoint.
func phase_usec_per_squad_update() -> Dictionary:
	var named := (total_fields_usec + total_curves_usec + total_vision_usec
		+ total_combat_usec + total_buildings_usec + total_economy_usec)
	return {
		"fields": _mean_usec_per_squad_update(total_fields_usec),
		"curves": _mean_usec_per_squad_update(total_curves_usec),
		"vision": _mean_usec_per_squad_update(total_vision_usec),
		"combat": _mean_usec_per_squad_update(total_combat_usec),
		"buildings": _mean_usec_per_squad_update(total_buildings_usec),
		"production": _mean_usec_per_squad_update(total_production_usec),
		"economy": _mean_usec_per_squad_update(total_economy_usec),
		"other": _mean_usec_per_squad_update(total_tick_usec - named),
	}


## Shared divisor for every per-squad-update figure above: no squads means
## an honest zero, not the tick's fixed overhead reported as if it were
## per-squad cost.
func _mean_usec_per_squad_update(total: int) -> float:
	if _cell.is_empty() or tick_count <= 0:
		return 0.0
	return float(total) / float(tick_count * _cell.size())


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
		# You always see your allies' squads, not merely whatever their
		# vision happens to cover (D-050).
		if are_allied(_owner[i], player) or vision.is_visible(player, _cell[i]):
			ids.append(i)
	return ids


# --- alliances (D-050) ------------------------------------------------

## player id -> team number. 0 means "no team", which is free-for-all:
## everyone is hostile to everyone.
##
## Held here rather than in MatchState because COMBAT needs it every
## round, and combat is driven from this class. MatchState owns choosing
## teams; this owns the consequence.
var teams := {}


## Whether two players are on the same side.
##
## A player is always allied with itself. Team 0 is deliberately NOT a
## team — two players who both picked "none" are enemies, not allies,
## which is what makes free-for-all the default rather than a special
## case that has to be spelled somewhere.
func are_allied(a: int, b: int) -> bool:
	if a == b:
		return true
	var team_a := int(teams.get(a, 0))
	var team_b := int(teams.get(b, 0))
	return team_a != 0 and team_a == team_b
