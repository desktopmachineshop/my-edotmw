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

## How far a settling squad will walk to find room, as a multiple of the
## separation it needs from ONE neighbour. Two neighbours' worth lets a
## handful of squads sent to the same place form a ring around it rather
## than all giving up on the first occupied spot.
const SEPARATION_SEARCH := 2

## Hard ceiling on that search, in hex rings. `_free_cell_near` is the
## one loop in the arrival pass whose cost is not bounded by the squad
## count, and a crowd big enough to need more room than this is better
## served by standing a little close (the function's existing fallback)
## than by scanning a quarter of the map.
const SEPARATION_MAX_RINGS := 16

## Smoothing passes applied to a flow-field path before it is written into
## the curve (D-20260818).
##
## A flow field can only step in six directions, so it walks a route off
## those six as a run of one direction and then a run of another. Facing
## is derived from the curve, so every junction between runs reads as a
## real 60 degree turn when it is nothing of the sort. A binomial [1,2,1]
## pass has exactly ZERO gain at the highest frequency the lattice can
## express, so a cell-by-cell alternation goes outright; the passes after
## that widen the radius a run junction is rounded onto, which is what
## lets the squad keep some pace through it. Genuine corners survive as
## corners.
const PATH_SMOOTHING_PASSES := 4

## How many times a path may be split finer when a corner is still too
## sharp for any pace to wheel through (D-20260818). Each round doubles
## the keyframes on that squad's curve, so it is bounded and only spent on
## paths that actually need it — a straight march never reaches it.
const PATH_REFINEMENTS := 3

## How many times the clearance repair may sweep a smoothed path before it
## gives up and takes the flow field's own line whole
## (D-20260818, amended for #133/#135).
##
## Putting one vertex back changes what its NEIGHBOURS' segments cross, so
## one sweep is not always enough. Three is well past anything a measured
## path has needed, and what it falls back to is safe rather than merely
## better.
const PATH_CLEARANCE_ROUNDS := 3

## How far a path point is pushed away from ground the squad cannot walk
## on, in cells, before the smoothing runs
## (D-20260818, amended for #133/#135).
##
## Binomial smoothing rounds a corner by pulling the path toward the
## INSIDE of the bend, and the inside of a bend the flow field made is
## usually the obstacle that caused it. Refusing those points (which is
## all the original guard did) leaves a route that hugs a wall with 60
## degree vertices in it and no room to be rounded at all — and a vertex
## that concentrated is one no pace can wheel through, because the whole
## turn has to happen while the squad crosses a single point.
##
## So the path is given the room first. Under half a cell, because that is
## what keeps a pushed point inside its own cell or a walkable neighbour;
## the point is passability-tested afterwards regardless.
const PATH_CLEARANCE := 0.45

## A vertex turning less than this is treated as straight when deciding
## whether a path needs splitting finer (D-20260818). Smoothing leaves a
## little residue everywhere, and refining for a tenth of a degree would
## buy keyframes on every march for nothing anyone could see.
const STRAIGHT_ENOUGH := 0.02

## Margin on the turning pace for the facing chord sweeping unevenly
## rather than at its average rate (D-20260818).
##
## The chord runs from where the squad is to a fixed distance further
## along its path, so its two ends do not contribute equally as it crosses
## a bend and the swing is a little faster in the middle than across the
## whole of it. 2.0 is what that peak measured on the shipped militia
## rounding a tight obstacle: without it the outermost soldier ran 19%
## over his move_speed at the sharpest moment, with it 0.3%. The pace
## budget carries it so the allowance covers the WORST instant of a turn
## rather than its mean.
const TURN_SWEEP := 2.0

## The slowest a squad may walk while wheeling, as a fraction of its
## move_speed (D-20260818).
##
## Not a comfort setting: a squad that crawls covers less path inside the
## replication horizon than Formation.HEADING_ARC needs, and then the
## client — which holds only that window — would derive its facing from a
## SHORTER chord than the server does. So this floor is what keeps the two
## sides agreeing, and it is also the one place the "nobody outruns his
## own move_speed" rule is approximate rather than exact: a corner tight
## enough to need less than this pace gets it anyway.
const MIN_TURNING_SPEED := 0.3

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

## What each SIDE believes the ground to be
## (D-20260818-pathing-knows-only-what-the-player-knows), owned here and
## folded from `vision`'s coverage on the same cadence. This — never
## `_passable` — is what a flow field is solved against, so a squad can
## neither route around terrain its owner has not discovered nor be
## refused an order on the strength of it. See terrain_knowledge.gd for
## why unknown ground reads PASSABLE and what that buys.
var knowledge: TerrainKnowledge

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
var _spacing := PackedFloat32Array()
# The player's ordered facing, quantised to 1/4096 of a turn, -1 = never
# ordered — and ordered files (width), 0 = the formation's own default
# (D-20260819-facing-and-width-are-orders). Both are REPLICATED squad
# state like _shape: soldier positions derive from them on both machines,
# so they ride SQUAD_INFO and the composition hash.
var _facing := PackedInt32Array()
var _files := PackedInt32Array()
# The stance byte (D-20260819-stances-are-standing-orders): bit 1 GUARD,
# bit 2 SKIRMISH, bit 4 HOLD FIRE. Rides SQUAD_INFO for the panel but is
# NOT hashed — the owner/tier family, a fact the client is told.
var _stance := PackedByteArray()
# Fatigue (D-20260819-tired-men-fight-uphill): one server-only scalar
# per squad, 0..100. Drains under charge/fight/run, recovers otherwise;
# never replicated — the panel indicator is its own decision.
var _fatigue := PackedFloat32Array()
# Per-cell terrain elevation, set by the SERVER from its own TerrainGen
# (empty in bare test sims — empty means flat, so every pre-existing
# test is untouched). Read-only here; combat prices the slope.
var elevation := PackedFloat32Array()
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
#
# Keyed by Vector2i(destination cell, KNOWLEDGE SIDE) since
# D-20260818-pathing-knows-only-what-the-player-knows: two sides that have
# explored different ground genuinely have different answers, so one field
# cannot serve both. The sharing D-007's scaling claim rests on is
# unharmed — a player ordering fifty squads to one place still solves ONE
# field, because they all share their owner's knowledge (and their allies',
# per D-050). Only two different sides ordering squads to the same cell
# costs a second solve.
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

# --- the water domain (naval stage 2, #301, docs/plans/naval.md 2.2/2.3)

## `_tier`'s three values. A DOMAIN rather than a tier, and the field
## keeps its name only so D-076's call sites do not churn.
##
## Three values in one field is right because they are MUTUALLY EXCLUSIVE
## BY CONSTRUCTION: a ship is never on a wall, and a land squad is never
## on open water except as cargo, which is not in the world at all
## (naval 3.1, and `_cargo` is where that is enforced).
const DOMAIN_GROUND := 0
const DOMAIN_WALL_TOP := 1
const DOMAIN_WATER := 2

## How far a mis-domained order is corrected before it simply lapses
## (naval 2.4). A shoreline is by definition within a cell or two of the
## other domain, so this only has to cover a genuine misclick — not a
## click on the far side of a continent, which is an order nobody meant.
const CORRECTION_RADIUS := 6

## The water layer's own cache, queue and counter — a third set, for the
## reason D-076's entry gives about the second: one shared budget would
## let a naval solve silently halve ground-pathing throughput on any tick
## both run, and on the maps this feature exists for BOTH run constantly.
var _fields_water := {}
var _pending_fields_water: Array[int] = []
var _field_cells_this_tick_water: int = 0

## Per-tick BFS cell budget for the water layer.
##
## MEASURED, not copied. D-076's 1,024 is right for a wall-top network,
## which is bounded by how many segments a player has built; water is
## bounded by the MAP, and on the maps that matter it is most of it —
## `islands` is 65-71% water, so a naval field is routinely LARGER than a
## ground field on the same ground. Copying 1,024 would have made every
## naval order wait dozens of ticks.
##
## The number comes from `just profile` over the shipped ladder: see the
## decision entry for the table. It is deliberately NOT the ground
## layer's 16,384 either — that was set by D-20260818 after finding the
## solver was 93% neighbour lookup, and the water layer inherits that fix
## for free (`TorusSpace.neighbor_table()` is memoised per space instance
## and the sim holds one), so the two budgets answer different questions
## about different-sized regions.
var water_field_cells_per_tick: int = 24576

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
var total_separation_usec: int = 0

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
	knowledge = TerrainKnowledge.new()


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
## Which cells are WATER (naval stage 1, §2.1). Held here so ship
## production can place a hull in the sea; it is NOT a movement domain
## yet — naval stage 2 is what gives `_tier` its third value and solves
## fields against this array.
##
## Deliberately no field invalidation, unlike `set_passable`: nothing
## paths on it today, so there is nothing cached to throw away. When
## stage 2 lands, this is the setter that grows one.
var _navigable := PackedByteArray()


func set_navigable(p: PackedByteArray) -> void:
	_navigable = p
	# Any cached water field was solved against the old sea, including any
	# still mid-solve whose frontier holds a reference to the array that
	# just went stale — the same reason `set_passable` clears the ground
	# caches (D-040).
	_fields_water.clear()
	_pending_fields_water.clear()


func is_navigable(cell: Vector2i) -> bool:
	if _navigable.is_empty():
		return false
	var index := space.index(cell)
	return index < _navigable.size() and _navigable[index] != 0


# --- cargo (naval stage 4, #301, docs/plans/naval.md section 3) -------

## What each squad is CARRYING: an Array per squad of
## {"def_id", "def", "owner", "alive", "shape", "spacing"}.
##
## A carried squad is NOT IN THE WORLD (3.1). It is removed the way
## `consume_squad` removes a founder — `alive` to zero, reported through
## the ordinary casualty path — and its composition is recorded HERE, on
## the carrier, to be rebuilt when it lands.
##
## Removed rather than flagged in place, and that is the load-bearing
## choice. Every loop in this file already guards `alive <= 0`, so a
## carried squad cannot fight, be seen, be targeted, be separated or
## gather without a single one of them being edited to know about cargo.
## A flag would have needed every one of them audited, and the one missed
## would be a squad fighting from inside a boat with nothing failing.
##
## The cost is that a squad's ID does not survive a voyage. That is
## honest rather than convenient: 3.1 already says cargo is not
## addressable — not targetable, not in `visible_to`, not drawn — so an
## id that outlived the embark would be an id naming nothing.
var _cargo := []

## Squads lost with a hull on the last tick, as the rider records that
## went down with it. Read by the server for its log and by the naval
## gates; nothing on the wire needs it, because the carrier's own death
## is what a client already sees.
var last_drownings := []

## Squads put ashore on the last tick, as new squad ids. The server
## replicates them the way it replicates any squad that did not exist a
## tick ago.
var last_landings := []

## Squads that boarded on the last tick, as casualty-shaped events for the
## server to broadcast. Drained by reading it — the same contract
## `last_wallet_changes` has, and the same reason: the simulation reports
## news, the server decides who hears it.
var last_embarks := []

## Squads walking to a dock in order to board, and the carrier they mean:
## squad -> carrier id, or -1. `_pending_tier_target`'s sibling, and
## deliberately the same shape — this is the same two-leg order D-076
## already established, with a boat where the ladder was.
var _pending_embark := PackedInt32Array()

## Carriers ordered to put their cargo ashore, and where: carrier -> land
## cell index, or -1.
var _pending_landing := PackedInt32Array()


func cargo_of(carrier: int) -> Array:
	if carrier < 0 or carrier >= _cargo.size():
		return []
	return _cargo[carrier]


func cargo_capacity_left(carrier: int) -> int:
	if carrier < 0 or carrier >= _cargo.size():
		return 0
	var def := _defs[carrier]
	if def == null:
		return 0
	return maxi(0, def.transport_capacity - (_cargo[carrier] as Array).size())


## Total squads a player has at sea inside a hull.
##
## Cargo still counts against the squad cap — it is an army slot you are
## using (3.1) — and it has to be counted HERE rather than left to
## `living_squad_count`, whose whole contract is "alive on the field".
func carried_squad_count(player: int) -> int:
	var n := 0
	for i in range(_cargo.size()):
		if _alive[i] <= 0:
			continue
		for rider in _cargo[i]:
			if int(rider["owner"]) == player:
				n += 1
	return n


## May `squad` board `carrier`? THE one predicate, so the order path, the
## arrival hop and any future caller cannot disagree about it.
func can_carry(carrier: int, squad: int) -> bool:
	if carrier < 0 or carrier >= _cell.size() or squad < 0 or squad >= _cell.size():
		return false
	if carrier == squad or _alive[carrier] <= 0 or _alive[squad] <= 0:
		return false
	var carrier_def := _defs[carrier]
	var rider_def := _defs[squad]
	if carrier_def == null or rider_def == null:
		return false
	if carrier_def.transport_capacity <= 0:
		return false
	# A hull carries; a land squad rides. A ship cannot be cargo, which is
	# 3.4's "no ship-to-ship transfer" falling out of the data rather than
	# needing a rule of its own.
	if carrier_def.movement_domain != "water" or rider_def.movement_domain != "ground":
		return false
	if _owner[carrier] != _owner[squad] and not are_allied(_owner[carrier], _owner[squad]):
		return false
	return cargo_capacity_left(carrier) > 0


## The hop that puts `squad` aboard `carrier` (3.3's second leg).
##
## ONE explicit hop, nothing partial, which is what keeps it legal under
## D-006 clause 1: there is nowhere for a half-embarked value to live.
## Returns the casualty-shaped events the server broadcasts, exactly as
## `consume_squad` does — clients already know how to apply them and the
## composition hash stays in agreement for free.
func embark(carrier: int, squad: int) -> Array:
	if not can_carry(carrier, squad):
		return []
	(_cargo[carrier] as Array).append({
		"def_id": _def_id[squad],
		"def": _defs[squad],
		"owner": _owner[squad],
		"alive": _alive[squad],
		"shape": _shape[squad],
		"spacing": _spacing[squad],
	})
	_alive[squad] = 0
	_routed[squad] = 0
	_pending_embark[squad] = -1
	# `fell` is FALSE: nobody died boarding a boat.
	# D-20260819-a-casualty-is-visible lays a corpse for men lost to
	# violence, and drawing one here would put a row of bodies on the quay
	# every time a squad got on a ship.
	return [{"id": squad, "alive": 0, "routed": false, "fell": false}]


## Put every rider ashore around `at` (3.3's one leg), returning the new
## squad ids. Empty if the carrier has no cargo or there is no passable
## land to land on.
##
## Cells are taken nearest-first through `disk_offsets` (D-067 sorted it
## for exactly this walk), so a landing is deterministic and a replay
## lands the same army on the same beach.
func disembark(carrier: int, at: Vector2i) -> Array:
	if carrier < 0 or carrier >= _cargo.size():
		return []
	var riders: Array = _cargo[carrier]
	if riders.is_empty():
		return []
	var landed := []
	var taken := {}
	for rider in riders:
		var spot := _landing_cell_near(at, taken)
		if spot.x < 0:
			break  # nowhere ashore; the rest stay aboard
		taken[space.index(spot)] = true
		var id := add_squad(rider["def"], int(rider["owner"]), spot)
		# A landed squad is an ORDINARY squad the tick it lands (3.4) — no
		# assault penalty, no bonus — but it keeps what it was: the men it
		# had left and the shape its player chose.
		_alive[id] = mini(int(rider["alive"]), _alive[id])
		_shape[id] = String(rider["shape"])
		_spacing[id] = float(rider["spacing"])
		landed.append(id)
	if landed.size() >= riders.size():
		_cargo[carrier] = []
	else:
		_cargo[carrier] = riders.slice(landed.size())
	_pending_landing[carrier] = -1
	return landed


## Every hull that has died still holding cargo, emptied (3.2).
##
## Iterates `_cargo` rather than tracking deaths, because a carrier can
## die down several paths — squad combat, building fire, a disconnect
## wipe, elimination — and a hook on each is a hook one of them will one
## day be added without. The list is one entry per squad and almost all
## of them are empty, so this is a scan of nothing on nearly every tick.
## A laden hull standing beside the ground it was sent to puts its cargo
## ashore (3.3).
##
## "Beside" rather than "on": a hull cannot stand on land, so the arrival
## test is that the ordered cell is within reach of where the hull now is.
## One cell, because that is what adjacency means on this lattice and a
## wider radius would let a ship unload across a strait it never crossed.
##
## Returns the squads that landed, so the server can replicate them the
## way it replicates anything else newly created.
func _advance_landings() -> Array:
	var landed := []
	for carrier in range(_cargo.size()):
		var target := _pending_landing[carrier]
		if target < 0:
			continue
		if _alive[carrier] <= 0 or (_cargo[carrier] as Array).is_empty():
			_pending_landing[carrier] = -1
			continue
		var at := space.from_index(target)
		if space.distance(cell_of(carrier), at) > 1:
			continue  # still sailing — naval stage 2 is what moves it
		landed.append_array(disembark(carrier, at))
	return landed


func _advance_drownings() -> Array:
	var lost := []
	for carrier in range(_cargo.size()):
		if _alive[carrier] > 0:
			continue
		if (_cargo[carrier] as Array).is_empty():
			continue
		lost.append_array(drown_cargo(carrier))
	return lost


func _landing_cell_near(at: Vector2i, taken: Dictionary) -> Vector2i:
	for offset in TorusSpace.disk_offsets(4):
		var candidate := space.normalize(at + offset)
		var index := space.index(candidate)
		if taken.has(index):
			continue
		if not is_passable(candidate):
			continue
		var occupied := false
		for other in range(_cell.size()):
			if _alive[other] > 0 and _cell[other] == index:
				occupied = true
				break
		if not occupied:
			return candidate
	return Vector2i(-1, -1)


## Everything a sinking carrier takes down with it (3.2).
##
## The cargo DROWNS. Ejecting it onto the nearest shore would make a
## transport strictly better than not using one, and would be an
## invisible rule a player cannot see operating. D-076 chose the opposite
## for a razed wall — evict, do not kill — and its reason does not
## transfer: a squad on a razed wall is standing on ground that still
## exists, while a squad on a sunk ship is in open water it could never
## have entered on its own.
##
## The riders have no squad ids any more — they left the world when they
## boarded — so this returns what was lost rather than casualty events.
## The carrier's own death is what clients already see.
func drown_cargo(carrier: int) -> Array:
	if carrier < 0 or carrier >= _cargo.size():
		return []
	var riders: Array = _cargo[carrier]
	if riders.is_empty():
		return []
	_cargo[carrier] = []
	return riders


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


## The domain constants live ONCE, above, with the rest of `_tier`'s
## definition (naval stage 2). Stage 5 declared an identical block here
## before stage 2 existed so that `combat.gd` could name the domain it
## refuses melee across rather than compare against a bare `2`; the merge
## brought both, and GDScript would happily carry two constants of the
## same name and value until one of them moved.


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
	_facing.append(-1)
	_files.append(0)
	_stance.append(0)
	_fatigue.append(100.0)
	_def_id.append(def.id)
	_defs.append(def)
	_cargo.append([])
	_pending_embark.append(-1)
	_pending_landing.append(-1)

	_morale.append(def.morale)
	_routed.append(0)
	_damage_accum.append(0.0)
	_last_attack_tick.append(-1)
	_attack_move.append(0)

	# A unit begins in the domain its def names (naval 2.4): the UNIT
	# decides its domain and the cell decides only whether an order is
	# legal. Everything that predates ships is `ground`, which is 0 and
	# exactly what this appended before.
	_tier.append(DOMAIN_WATER if def.movement_domain == "water" else DOMAIN_GROUND)
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


func spacing_of(squad: int) -> float:
	return _spacing[squad]


func facing_of(squad: int) -> int:
	return _facing[squad]


const STANCE_GUARD := 1
const STANCE_SKIRMISH := 2
const STANCE_HOLD_FIRE := 4
## Run (D-20260819-tired-men-fight-uphill): pace for fatigue. Refused as
## a free lever until fatigue existed to price it (the ws7 entry says
## so); it spends what charging spends.
const STANCE_RUN := 8

const FATIGUE_CHARGE_DRAIN := 12.0
const FATIGUE_FIGHT_DRAIN := 2.0
const FATIGUE_RUN_DRAIN := 6.0
const FATIGUE_RECOVERY := 4.0
const CHARGE_MIN_FATIGUE := 40.0
const CHARGE_EXHAUST_FLOOR := 25.0
const RUN_MIN_FATIGUE := 20.0
const RUN_PACE_MULT := 1.3


## Whether `player` already fields a living general
## (D-20260819-a-general-holds-the-line) — the one-alive limit's
## question, answered here so a test can ask it without a server.
func has_live_general(player: int) -> bool:
	for i in range(_cell.size()):
		if _owner[i] == player and _alive[i] > 0:
			var def := def_of(i)
			if def != null and def.is_general:
				return true
	return false


func fatigue_of(squad: int) -> float:
	return _fatigue[squad]


## Test access. Fatigue is otherwise the tick's own business.
func set_fatigue(squad: int, value: float) -> void:
	_fatigue[squad] = clampf(value, 0.0, 100.0)


func stance_of(squad: int) -> int:
	return _stance[squad]


func has_stance(squad: int, bit: int) -> bool:
	return (_stance[squad] & bit) != 0


## A player's standing orders (D-20260819-stances-are-standing-orders).
## The whole byte at once — the client sends its full toggled state, so
## there is no read-modify-write race across the wire.
func set_stance(squad: int, bits: int) -> void:
	if squad < 0 or squad >= _stance.size():
		return
	var clamped := bits & (STANCE_GUARD | STANCE_SKIRMISH | STANCE_HOLD_FIRE | STANCE_RUN)
	if _stance[squad] == clamped:
		return
	_stance[squad] = clamped
	_shape_dirty[squad] = true


func files_of(squad: int) -> int:
	return _files[squad]


## The ordered facing as the world angle Formation.facing_angle wants,
## NAN when never ordered. THE quantised-to-angle conversion — the client
## carries an identical one (ClientState.facing_angle_of), and both
## reconstruct from the same wire integer so the two machines cannot
## disagree by a bit (D-20260819-facing-and-width-are-orders).
func facing_angle_of(squad: int) -> float:
	var q := _facing[squad]
	return NAN if q < 0 else TAU * float(q) / 4096.0


## A player's facing order (D-20260819). Quantised on the way in; takes
## effect the moment the squad stands (Formation.facing_angle). Rides the
## shape-dirty channel: a SQUAD_INFO rebroadcast carries every field.
func set_facing(squad: int, quantised: int) -> void:
	if squad < 0 or squad >= _facing.size():
		return
	var clamped := clampi(quantised, 0, 4095)
	if _facing[squad] == clamped:
		return
	_facing[squad] = clamped
	_shape_dirty[squad] = true


## A player's width order (D-20260819). 0 restores the formation's own
## default; otherwise clamped to something a squad can actually form.
## Footprint changes with width, so the cache is invalidated exactly as a
## shape change does it.
func set_files(squad: int, files: int) -> void:
	if squad < 0 or squad >= _files.size():
		return
	var clamped := clampi(files, 0, 255)
	if _files[squad] == clamped:
		return
	_files[squad] = clamped
	_shape_dirty[squad] = true
	_dirty_footprint(squad)


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
	_apply_shape(squad, shape)


## `suggest_shape` — the per-tick assertion channel D-065 built for
## D-058's ring-while-working — is GONE with its only caller
## (D-20260820-men-gather-round-what-they-strike, amended): nothing in
## the simulation asserts shapes any more, so the latch that protected a
## player's choice from it has nothing to protect against. D-065's rule
## still stands: if any future system wants to assert a squad's shape
## per tick, it re-reads that entry and rebuilds the suggest/latch pair
## rather than calling set_shape in a loop.


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
			# The player's ordered facing and width (D-20260819) — soldier
			# positions derive from them, so the client must hold the
			# server's exact values.
			"facing": _facing[id], "files": _files[id],
			"stance": _stance[id],
			# What it is carrying (3.1). Only the two fields a client can
			# use — a name and a count — because cargo is drawn nowhere and
			# the selection panel is all it feeds.
			"cargo": _cargo_wire(id),
		})
	return out


func _cargo_wire(carrier: int) -> Array:
	var out := []
	for rider in _cargo[carrier]:
		out.append({"def_id": String(rider["def_id"]), "alive": int(rider["alive"])})
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
			"facing": _facing[id],
			"files": _files[id],
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
## Squads that have ARRIVED do not stack: one settles onto free ground
## nearby (D-060), far enough that its soldiers clear its neighbour's.
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
## ## How much room, and why the first version bought almost none
##
## Separation used to mean "no two squads share a CENTRE CELL", which is
## one cell of guaranteed clearance between armies that are eleven cells
## wide (#104). Squads ordered to one place did not shove each other far
## away — they overlapped almost completely, and the rule was doing
## exactly what it said while being an order of magnitude short of the
## geometry.
##
## `Formation.footprint` had computed the missing number since selection
## needed it, and nothing in the simulation had ever read it — so the
## selection marker was drawn at the squad's true size and visibly
## overlapped its neighbours. The picture was telling the truth. The
## clearance required is `footprint_cells(a) + footprint_cells(b)` now,
## which for two line formations is very nearly shoulder to shoulder.
##
## ## Cost
##
## A squad asks only the cells its own footprint can reach, against a
## bucket map built once per pass — the D-066 shape, not a squad x squad
## scan, which would be ~10^6 comparisons a tick at D-018's scale.
##
## Deterministic tie-break: the LOWER squad id keeps the cell and the
## higher one moves. Without that, two squads would each decide the other
## was there first and swap places forever.
func _separate_arrivals() -> void:
	# Cell index -> the squads holding that ground, built up as the pass
	# places them. A squad that has just been sent somewhere else is
	# recorded at its NEW spot, so the next squad in the pass does not
	# pick the same one — without that, three squads on one cell all
	# settled on the same free cell and had to re-separate over the
	# following ticks.
	var held := {}
	var widest := 0
	var settling := PackedInt32Array()

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

		widest = maxi(widest, footprint_cells(i))

		# A crew AT WORK is exempt, and this is not a nicety.
		#
		# Gathering requires standing on the node's own cell (D-028), and
		# several crews working one node is both normal and desirable. The
		# first version separated them anyway: a displaced crew could never
		# reach the gathering phase, so it hauled nothing, forever. The
		# ladder showed 22 gatherer squads and a stockpile that never rose
		# above the STARTING 480 — an economy that looked staffed and was
		# producing literally nothing.
		#
		# It still HOLDS its ground — an arriving squad goes around a
		# working crew rather than standing in it — it is simply never the
		# one that moves.
		if economy != null and economy.is_gathering(i):
			_hold_ground(held, _cell[i], i)
			continue

		# A squad IN A FIGHT is exempt for the same reason, and this is
		# not a nicety either. Two squads battering one town centre have
		# to BOTH be within `attack_range` of it — a little over one cell
		# for melee — so pushing the second one out to its own footprint
		# takes it out of the fight entirely. That is D-067's shipped rule
		# ("one squad cannot raze a defended building; two can") broken by
		# a spacing change, and it is what `test_buildings.gd` reported
		# when this pass first went in: "the second squad is not in the
		# fight".
		#
		# The pass runs AFTER combat for this to be answerable at all —
		# see tick(). A squad reads engaged on the very tick it arrives,
		# which is the tick separation would otherwise have sent it away.
		if combat != null and combat.is_engaged(i):
			_hold_ground(held, _cell[i], i)
			continue
		settling.append(i)

	# Ascending id, so the LOWER id keeps its ground and the higher one
	# moves. Without that, two squads would each decide the other was
	# there first and swap places forever.
	for i in settling:
		var cell := _cell[i]
		if _crowded(held, space.from_index(cell), i, widest):
			var spot := _free_cell_near(space.from_index(cell), i, held, widest)
			if spot != space.from_index(cell):
				cell = space.index(spot)
				_destination[i] = cell
				_rebuild_curve(i)
		_hold_ground(held, cell, i)


func _hold_ground(held: Dictionary, cell: int, squad: int) -> void:
	if not held.has(cell):
		held[cell] = []
	held[cell].append(squad)


## Whether a squad of `asking`'s size standing on `cell` would have its
## soldiers standing inside somebody else's.
##
## Scans `asking`'s own hex disk against the bucket map — the furthest a
## squad that overlaps it can be is its own footprint plus the widest one
## on the board — rather than testing every squad, which is the
## radius-scan defect this project has now hit five times (vision,
## UnitRoster.by_id, terrain noise, the building scan).
func _crowded(held: Dictionary, cell: Vector2i, asking: int, widest: int) -> bool:
	for offset in TorusSpace.disk_offsets(footprint_cells(asking) + widest):
		var index := space.index(cell + offset)
		if not held.has(index):
			continue
		for other in held[index]:
			if other != asking and space.distance(cell, space.from_index(index)) \
					< _clearance(asking, other):
				return true
	return false


## How far apart two squads must stand, in CELLS — not world units,
## because every other radius rule here is a hex-disk scan and
## `TorusSpace.disk_offsets` is how this project does those.
##
## EVERYONE keeps D-060's original ONE cell since
## D-20260821-a-fight-loosens-a-formation (the owner's call, reverting
## #104's ally half): displacing a whole ALLIED squad by two footprints
## was exactly the "whole squad snaps or moves" a player sees, and
## overlap is resolved at the individual drawn man now — the
## cross-squad jostle — not by teleporting forty men sideways. Enemies
## were always here: interpenetrating enemies is what a fight looks
## like; combat (D-024) resolves it, not spacing.
func _clearance(_asking: int, _other: int) -> int:
	return 1


## The ground a squad's soldiers actually cover, as a radius in CELLS.
##
## `Formation.footprint` has answered this in world units since selection
## needed a hit target and a marker of the right size; until #104 nothing
## in the simulation had ever asked, which is why separation guaranteed
## one cell of clearance to squads eleven cells across.
##
## Rounded UP, and converted at the spacing between neighbouring cell
## centres (`sqrt(3) * hex_size`): half a cell of extra room beats two
## squads sharing a rank of men because the arithmetic landed just under.
func footprint_cells(squad: int) -> int:
	if squad < 0 or squad >= _alive.size() or _alive[squad] <= 0:
		return 0
	var world: float = Formation.footprint(
		_shape[squad], _alive[squad], _spacing[squad], _files[squad])["radius"]
	return ceili(world / (TorusSpace.SQRT_3 * space.hex_size))


## The nearest cell where `asking` can stand clear of everything already
## holding ground.
##
## `disk_offsets` is sorted nearest-first, so the first candidate that
## clears is the nearest one — that ordering is what stops a displaced
## squad landing four cells away in a fixed direction and out of its own
## reach (D-067's amendment).
##
## Neighbours are collected ONCE from the bucket map and then tested per
## candidate, rather than re-scanning the map for every candidate: the
## scan is the expensive half and it does not change as the candidate
## moves.
func _free_cell_near(cell: Vector2i, asking: int, held: Dictionary,
		widest: int) -> Vector2i:
	var radius := footprint_cells(asking)
	var reach := mini(SEPARATION_MAX_RINGS, (radius + widest) * SEPARATION_SEARCH)

	var neighbours := []
	for offset in TorusSpace.disk_offsets(reach + widest):
		var index := space.index(cell + offset)
		if not held.has(index):
			continue
		for other in held[index]:
			if other != asking:
				neighbours.append([space.from_index(index), _clearance(asking, other)])

	for offset in TorusSpace.disk_offsets(reach):
		var candidate := space.normalize(cell + offset)
		if not is_passable(candidate):
			continue
		var taken := false
		for neighbour in neighbours:
			if space.distance(candidate, neighbour[0]) < int(neighbour[1]):
				taken = true
				break
		if not taken:
			return candidate
	# Nowhere free within reach: standing too close beats never settling.
	return cell


## Cell index -> the squads standing on it, for every living GROUND
## squad. Built fresh by each caller, the same shape and for the same
## reason as Combat._build_buckets: the curve IS the state, so an
## incrementally maintained map would be a second source of truth.
func _ground_held() -> Dictionary:
	var held := {}
	for i in range(_cell.size()):
		if _alive[i] > 0 and _tier[i] == 0:
			_hold_ground(held, _cell[i], i)
	return held


## The largest footprint standing on the ground right now, in cells — how
## far a scan has to reach to be sure it has seen every squad that could
## overlap the one asking.
func _widest_footprint() -> int:
	var widest := 0
	for i in range(_cell.size()):
		if _alive[i] > 0 and _tier[i] == 0:
			widest = maxi(widest, footprint_cells(i))
	return widest


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
	# The domain dispatch (naval 2.2). `tier` keeps its name; its doc is
	# 'domain' and the constants are `DOMAIN_*`.
	if tier == DOMAIN_WATER:
		return is_navigable(cell)
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
## Within the smallest workable ring, the door FACES THE RALLY POINT
## (D-20260821-a-recruit-steps-out-the-near-door): a recruit appears on
## the side his orders will take him, instead of popping out wherever the
## enumeration happened to start and marching around his own building.
## The ring outranks the bearing — at the door beats two cells further
## out on a better heading. Deterministic: `disk_offsets` enumerates in a
## fixed order and the improvement test is strict, so ties resolve to the
## earlier candidate and server and replay agree about where a unit
## appeared.
func _spawn_cell_near(buildings: BuildingSim, building: int,
		produced: UnitDef = null) -> Vector2i:
	# A HULL is launched, not marched out (naval stage 3, §4.2). Same walk,
	# same determinism argument, different array — seeded from the dock's
	# own water cell rather than from its land cell, because that is the
	# side the water is on.
	#
	# It cannot move yet: giving `_tier` its third value and solving fields
	# over `_navigable` is naval stage 2. Stage 3's claim is only that a
	# hull APPEARS in water, which is what makes stage 2 something that can
	# be looked at rather than inferred.
	if produced != null and produced.movement_domain == "water":
		var launched := _launch_cell_near(buildings, building)
		if launched.x >= 0:
			return launched
	var home := buildings.cell_of(building)
	var rally := buildings.rally_of(building)
	var best := Vector2i.ZERO
	var best_dist := 0
	var best_ring := 0
	var found := false
	for offset in TorusSpace.disk_offsets(4):
		var ring := TorusSpace.hex_length(offset)
		if ring < 2:
			continue  # under the building itself
		if found and ring > best_ring:
			break  # sorted nearest-first (D-067): the workable ring is done
		var candidate := space.normalize(home + offset)
		if not is_passable(candidate):
			continue
		if buildings.building_at(candidate) >= 0:
			continue
		var dist := space.distance(candidate, rally)
		if not found or dist < best_dist:
			found = true
			best = candidate
			best_dist = dist
			best_ring = ring
	if found:
		return best
	# Hemmed in on every side: put them at the door anyway rather than
	# losing a squad somebody paid for.
	return space.normalize(home + Vector2i(2, 0))


## The water cell a new hull is launched onto, or (-1, -1) if this
## building has no water side or every cell around it is taken.
##
## Nearest-first from the dock's OWN water cell (D-067 sorted
## `disk_offsets` for this), so two hulls launched together do not stack
## and a replay launches them in the same order.
func _launch_cell_near(buildings: BuildingSim, building: int) -> Vector2i:
	var water := buildings.water_cell_of(building)
	if water < 0 or _navigable.is_empty():
		return Vector2i(-1, -1)
	var from := space.from_index(water)
	for offset in TorusSpace.disk_offsets(3):
		var candidate := space.normalize(from + offset)
		if not is_navigable(candidate):
			continue
		# Not on top of another hull. Land squads are not consulted: a
		# land squad cannot be standing on water in the first place.
		var taken := false
		for other in range(_alive.size()):
			if _alive[other] > 0 and _cell[other] == space.index(candidate):
				taken = true
				break
		if not taken:
			return candidate
	# Every berth full: launch at the dock's own water cell rather than
	# losing a hull somebody paid for, the same call the land path makes.
	return from


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
	# A plain move is not a charge (D-20260819): walking somewhere must
	# not carry a three-times blow eight seconds after somebody clicked
	# Charge and changed their mind.
	_charge_until.erase(squad)
	if is_routed(squad):
		return
	_attack_move[squad] = 0
	# THE EMBARK TRIGGER, and it comes first on purpose (naval stage 4).
	#
	# Section 2.4 pins "a land squad ordered to a water cell is corrected
	# to the nearest passable land cell, UNLESS IT IS AN EMBARK ORDER" and
	# never says what an embark order is, while insisting there be no new
	# opcode for movement. The reading taken here is the one that needs
	# neither: ordering a land squad onto a cell holding a FRIENDLY
	# TRANSPORT WITH ROOM is the embark. The cell's contents disambiguate,
	# it is the gesture every game in the genre uses — right-click the
	# boat — and it makes the exception precise.
	#
	# Checked BEFORE any destination correction so that naval stage 2 can
	# write section 2.4's rule without knowing embark exists: the
	# correction is naturally downstream of this branch. If that ordering
	# is ever inverted, every embark order silently becomes a walk to the
	# beach.
	var carrier := _transport_at(destination, squad)
	if carrier >= 0:
		_begin_embark(squad, carrier)
		return
	_pending_embark[squad] = -1
	# A LADEN HULL ordered at land is a landing (3.3's one leg), and the
	# asymmetry with embark is the design's central choice: loading is a
	# logistics operation you build a dock for, landing is the attack.
	# D-076 chose "one door" for a wall and explicitly rejected "any
	# adjacent cell" because it made a wall's LINE pointless — there is no
	# line to defend at sea, and a rule that only let you land where
	# somebody had already built a dock would mean you can only invade an
	# island the enemy has already settled.
	#
	# The hull still has to GET there, which is naval stage 2. This
	# records the intent; `_advance_landings` performs it when the hull is
	# actually beside the ground it was sent to.
	if not (_cargo[squad] as Array).is_empty() and not is_passable(destination):
		pass  # ordered at water: an ordinary move for a hull, not a landing
	elif not (_cargo[squad] as Array).is_empty():
		_pending_landing[squad] = space.index(destination)
	# THE DOMAIN CORRECTION (naval 2.4), and it comes AFTER the embark and
	# landing branches above on purpose — both of those are orders that
	# deliberately name a cell in the other domain, and correcting first
	# would turn every embark into a walk to the beach and every landing
	# into a move to open sea. That ordering is the whole interlock
	# between naval stages 2 and 4; it is asserted by
	# `test_naval_domain.gd` rather than left to a comment.
	destination = _corrected_destination(squad, destination)
	var wanted_tier := _wanted_domain_for(squad, destination)
	if wanted_tier == _tier[squad]:
		_pending_tier_target[squad] = -1
		_apply_move_order(squad, destination, true)
		return
	_begin_tier_crossing(squad, destination, wanted_tier)


## The cell this squad can actually be ordered to, given the domain it
## lives in (naval 2.4).
##
## **The unit decides its domain; the cell decides only whether the order
## is legal.** D-076 could infer a tier from the destination because a
## wall-top cell is unambiguous. A shore cell is not: it is legal ground
## for a land squad AND adjacent to legal water, so "which domain did they
## mean" cannot be answered from the cell.
##
## So an order into the wrong domain is CORRECTED rather than refused —
## the same shape as `_approachable`, which D-20260818 deliberately left
## omniscient precisely because it can never refuse an order, only move
## one. A player who clicks the sea with infantry selected gets a march to
## the shore, which is what they meant.
##
## Returns `destination` unchanged for every squad in its own domain,
## which is every squad that predates ships.
func _corrected_destination(squad: int, destination: Vector2i) -> Vector2i:
	var domain := _tier[squad]
	if domain == DOMAIN_WATER:
		if is_navigable(destination):
			return destination
		return _nearest_in_domain(destination, true)
	if domain == DOMAIN_GROUND:
		if not is_navigable(destination) or _navigable.is_empty():
			return destination
		return _nearest_in_domain(destination, false)
	return destination


## The nearest cell of the wanted kind to `from`, or `from` itself if
## there is none within reach.
##
## Nearest-first through `disk_offsets` (D-067 sorted it for exactly this
## walk), so the correction is deterministic and a replay corrects
## identically. Bounded rather than unbounded: a correction that searched
## the whole map would happily send a ship to the far side of the world
## because somebody misclicked, and "the order lapses" is the behaviour
## every other unreachable order in this file already has.
func _nearest_in_domain(from: Vector2i, want_water: bool) -> Vector2i:
	for offset in TorusSpace.disk_offsets(CORRECTION_RADIUS):
		var candidate := space.normalize(from + offset)
		if is_navigable(candidate) == want_water:
			if want_water or is_passable(candidate):
				return candidate
	return from


## The friendly transport standing on `destination` that `squad` could
## board, or -1. Every condition is `can_carry`'s, so there is one answer
## to "may this squad board that hull" and the order path cannot drift
## from the hop.
func _transport_at(destination: Vector2i, squad: int) -> int:
	var index := space.index(destination)
	for other in range(_cell.size()):
		if _alive[other] <= 0 or _cell[other] != index:
			continue
		if can_carry(other, squad):
			return other
	return -1


## Start the two-leg embark (section 3.3), in exactly
## `_begin_tier_crossing`'s shape and for the same reason: this is one
## explicit two-leg order, not a unified graph.
##
## Leg one is an ordinary land walk to the DOCK'S LAND CELL — the cell a
## land squad can actually stand on beside the hull. Leg two is the hop,
## in `_advance_embarks`.
func _begin_embark(squad: int, carrier: int) -> void:
	var quay := _quay_for(carrier)
	if quay.x < 0:
		# The hull is not at a dock, so there is nowhere to board from.
		# Degrades like any other unreachable order — the squad keeps
		# doing whatever it was doing, which is D-076's own answer to a
		# missing tower.
		return
	_pending_embark[squad] = carrier
	_pending_tier_target[squad] = -1
	_apply_move_order(squad, quay, true)


## The land cell a squad boards `carrier` from: the cell of the dock whose
## water side the hull is sitting on, or (-1, -1) if it is not at one.
##
## Section 3.4: you load at a dock and nowhere else. Landing is the thing
## that can happen anywhere.
func _quay_for(carrier: int) -> Vector2i:
	if buildings == null:
		return Vector2i(-1, -1)
	var at := _cell[carrier]
	for i in range(buildings.building_count()):
		if buildings.is_destroyed(i) or not buildings.is_complete(i):
			continue
		if buildings.water_cell_of(i) == at:
			return buildings.cell_of(i)
	return Vector2i(-1, -1)


## Leg two: hop aboard, once the squad is standing on the quay and the
## hull is still there with room. Called from the tick beside
## `_advance_tier_transitions`, which is the same shape and the same
## arrival test.
##
## Returns the casualty-shaped events for every squad that boarded, so the
## server broadcasts them through the path it already has.
func _advance_embarks() -> Array:
	var events := []
	for squad in range(_cell.size()):
		var carrier := _pending_embark[squad]
		if carrier < 0:
			continue
		if _alive[squad] <= 0:
			_pending_embark[squad] = -1
			continue
		if _cell[squad] != _destination[squad]:
			continue  # still walking to the quay
		_pending_embark[squad] = -1
		# Re-asked on ARRIVAL, never trusted from order time: a hull sails,
		# is sunk, or fills up while a squad walks to the quay. Every other
		# rule in this codebase that survives a walk is re-checked the same
		# way (server._finish_build re-asks the ground, the cost and the
		# claims).
		if not can_carry(carrier, squad):
			continue
		if _quay_for(carrier) != cell_of(squad):
			continue  # the hull moved to another dock while we walked
		events.append_array(embark(carrier, squad))
	return events


## Advance, but halt on contact (D-034). Combat clears the stance when it
## halts the squad, so the order is spent once it has done its job rather
## than sticking around to re-halt the squad every tick it stays engaged.
##
## Tier inference (D-076) works exactly as `order_move`'s does — see there.
## A charge: attack-move at CHARGE_SPEED_MULT with one x-damage impact
## waiting at the end (D-20260819-a-charge-is-spent-on-its-impact).
## Point-blank orders get no flag — re-ordering a charge against the man
## in front of you must not be a free impact every click. The sprint now
## ends when FATIGUE gives out (D-20260819-tired-men-fight-uphill),
## which replaced the original tick deadline outright: the cost lingers,
## so charge-rest-charge is no longer free.
const CHARGE_SPEED_MULT := 1.5
const MIN_CHARGE_CELLS := 3

# squad -> the tick its charge expires. Squad-level state, exactly what
# D-024 permits squads to have.
var _charge_until := {}


func order_charge(squad: int, destination: Vector2i) -> void:
	if is_routed(squad):
		return
	if space.distance(cell_of(squad), destination) < MIN_CHARGE_CELLS \
			or _fatigue[squad] < CHARGE_MIN_FATIGUE:
		# Too close, or too spent (D-20260819-tired-men-fight-uphill):
		# either way the order degrades to an honest attack-move.
		order_attack_move(squad, destination)
		return
	# Flag FIRST: the order below rebuilds the curve, and the rebuild
	# must already see the charge speed. Membership is the flag; the
	# fatigue sweep is what ends it.
	_charge_until[squad] = true
	order_attack_move(squad, destination)


func is_charging(squad: int) -> bool:
	return _charge_until.has(squad)


func order_attack_move(squad: int, destination: Vector2i) -> void:
	if is_routed(squad):
		return
	# An explicit attack order is weapons-free: it RELEASES a hold-fire
	# stance rather than fighting it (D-20260819-stances) — the flag it
	# would otherwise be gated on is spent by D-034's halt one exchange in.
	if has_stance(squad, STANCE_HOLD_FIRE):
		set_stance(squad, _stance[squad] & ~STANCE_HOLD_FIRE)
	var wanted_tier := _wanted_domain_for(squad, destination)
	if wanted_tier == _tier[squad]:
		_pending_tier_target[squad] = -1
		_apply_move_order(squad, destination, true)
	else:
		_begin_tier_crossing(squad, destination, wanted_tier)
	_attack_move[squad] = 1


## Which DOMAIN this squad's order belongs to (naval 2.4).
##
## THE rule the design pins: **the unit decides its domain, the cell
## decides only whether the order is legal.** D-076 could infer a tier
## from the cell because a wall-top cell is unambiguous; a shore cell is
## not, being legal ground for a land squad and adjacent to legal water.
##
## So a water squad's domain is simply its own — it never climbs a wall
## and never walks ashore, and its destination has already been corrected
## into water by `_corrected_destination`. Everything else keeps D-076's
## inference exactly, which is what leaves every pre-naval call site and
## every wire order untouched.
##
## Without this a hull ordered anywhere fell into `_begin_tier_crossing`
## looking for an access tower, found none, and the order was dropped in
## silence — measured, before it was fixed: 120 ticks, 0 fields built, a
## ship that never moved.
func _wanted_domain_for(squad: int, destination: Vector2i) -> int:
	if _tier[squad] == DOMAIN_WATER:
		return DOMAIN_WATER
	return _tier_for_destination(destination)


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
	# A halt spends or cancels any charge — Combat holds its own halt
	# until the impact fires, so by the time the sim's stop runs the blow
	# has already landed (D-20260819-a-charge-is-spent-on-its-impact).
	_charge_until.erase(squad)
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
	# A broken squad is not charging anything (D-20260819) — without this
	# a routed ex-charger would flee at sprint speed until the deadline.
	_charge_until.erase(squad)
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
## 4,096 was half a field on the 8,064-cell map D-040 measured, and an
## EIGHTH of one on the 32,592-cell map the ladder shipped in
## D-20260817-the-zoom-cap-was-modelling-the-wrong-axis — so the latency
## D-040 deliberately bought with a per-tick budget quietly quadrupled and
## a squad could stand still for six ticks after a right-click (#107).
##
## 16,384 is that number re-taken on the shipped map, and it costs LESS
## tick time than the 4,096 it replaces rather than more: the solver got
## 21x cheaper per cell when `TorusSpace.neighbor_table` replaced six
## `neighbor_index()` calls per cell, so the per-tick expansion bound went
## from 4,096 x 8.54 µs = **35 ms** to 16,384 x 0.40 µs = **6.6 ms**. The
## budget is doing four times the work for a fifth of the cost.
##
## Chosen by measurement, not by argument, on the shipped 168x194 map:
## worst wait over 114 spawn-to-spawn orders is **6 ticks at 4,096 and 1
## tick at 16,384** (mean 2.58 -> 0.31), which discharges
## D-20260817-m10-scale-optimisation criterion 3. D-040's own property is
## preserved on purpose — worst tick stays FLAT in map size, because the
## budget is a constant and not a fraction of the map — and the price of
## that is the top of the ladder: worst wait is 3 ticks on Large and 6 on
## Huge (0.6 s, against 3.2 s before). Raising this further is now cheap
## and the numbers are in the decision entry; it is not raised today
## because 100 ms of latency on the DEFAULT map is what was asked for and
## a bigger constant buys the two sizes nobody has played.
##
## D-040's original reading, kept because it is what the shape of this
## budget is for: at 1,000 squads on the then-ship map the worst tick was
## 1,226 ms unamortised and 72.8 ms at 4,096. The thing being blown was
## always a latency spike, never throughput.
const DEFAULT_FIELD_CELLS_PER_TICK := 16384
var field_cells_per_tick: int = DEFAULT_FIELD_CELLS_PER_TICK

## Destination indices whose fields are still expanding, oldest first.
##
## FIFO rather than "nearest first" or "most squads waiting first": every
## ordering heuristic tried here would need a squad-to-field index to
## evaluate, and the queue is only ever a handful deep because a wave
## drains in a few ticks. Finishing the oldest first also bounds the worst
## wait, which is the number that matters — the spike was never about
## throughput.
##
## Entries are `_fields` keys — (destination, side) — not bare
## destinations, since the same destination can be in flight for two sides
## at once (D-20260818-pathing-knows-only-what-the-player-knows).
var _pending_fields: Array[Vector2i] = []

## Cells expanded so far this tick, against `field_cells_per_tick`.
var _field_cells_this_tick: int = 0

## Per-phase cost of the LAST tick, for attributing a spike to a phase
## instead of guessing at one. Same regions as the run totals above, so
## the two lines a server prints — the over-budget spike and the final
## summary — name the same phases. `last_production_usec` is a slice of
## `last_buildings_usec`, not a phase beside it.
var last_curves_usec: int = 0

## What `_separate_arrivals` cost this tick (#104). Its own phase rather
## than a share of `last_curves_usec`, where it used to sit: the pass
## scans a hex disk per settled squad now, and the phases PARTITION the
## tick — so a pass with no accumulator of its own does not go unmeasured,
## it lands in `other` and looks like the next unexplained rise.
var last_separation_usec: int = 0
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

## Planned steps that ran into ground the mover's side had not known was
## blocked, each of which drops a field and re-routes
## (D-20260818-pathing-knows-only-what-the-player-knows). Counted for the
## same reason `field_waits` is: it is the price of optimistic pathing, and
## a match with terrain that reports ZERO of these is one where the whole
## mechanism is quietly dead — this project's most-repeated defect.
var route_discoveries: int = 0


## Spend this tick's expansion budget on fields still being built.
##
## Called at the START of tick, so a field begun on a previous tick makes
## progress before any squad asks it for a direction.
func _expand_pending_fields() -> void:
	_field_cells_this_tick = 0
	if _pending_fields.is_empty():
		return

	var started := Time.get_ticks_usec()
	var still_pending: Array[Vector2i] = []
	for key in _pending_fields:
		var field: FlowField = _fields.get(key, null)
		if field == null or field.is_complete():
			continue
		var remaining := _field_budget_remaining()
		if remaining == 0:
			# Out of budget: keep it queued, untouched, for next tick.
			still_pending.append(key)
			continue
		var before := field.expanded_cells()
		if not field.expand(remaining):
			still_pending.append(key)
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


## `knower` is the KNOWLEDGE SIDE the field is solved for
## (`knowledge_group_of`), never a player id directly — allies share sight
## (D-050) and therefore share fields.
##
## `tier` (D-076): 0 is the ground layer, unchanged from before tiers
## existed; 1 dispatches to `_field_for_top`, a completely separate cache
## and budget — see that function and `_fields_top`'s own doc for why. The
## wall-top network is deliberately NOT fogged: it is made of buildings a
## side put there itself, so there is no unknown ground in it to be
## optimistic about.
func _field_for(destination_index: int, knower: int, tier: int = 0) -> FlowField:
	if tier == 1:
		return _field_for_top(destination_index)
	if tier == DOMAIN_WATER:
		return _field_for_water(destination_index)

	var key := Vector2i(destination_index, knower)
	if _fields.has(key):
		return _fields[key]

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
	# What this SIDE believes, not what the map is
	# (D-20260818-pathing-knows-only-what-the-player-knows). Empty when the
	# side has never observed a blocked cell, which FlowField reads as
	# "everything passable" — exactly the optimism a side that has explored
	# nothing is entitled to.
	field.begin(space, space.from_index(destination_index),
		knowledge.believed_passable(knower))
	# Expand into whatever budget this tick has left. In a quiet tick that
	# is the whole field and the amortisation is invisible; in a wave, the
	# later fields get little or nothing here and finish over the next few
	# ticks.
	# `has` rather than a bare append: a field dropped mid-solve by a
	# re-route (see `_rebuild_curve`) and immediately rebuilt would
	# otherwise be queued twice and charged the budget twice.
	if not field.expand(_field_budget_remaining()) and not _pending_fields.has(key):
		_pending_fields.append(key)
	_field_cells_this_tick += field.expanded_cells()
	total_field_usec += Time.get_ticks_usec() - started

	_fields[key] = field
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


## The water counterpart of `_field_for` (naval 2.3) — same `FlowField`
## class, unmodified, driven a third time over its own dictionary, queue
## and budget.
##
## NOT FOGGED, and the argument is stronger than the wall-top layer's
## rather than weaker. D-20260818 made ground pathing solve against what a
## SIDE believes, because unknown land can hide a lake or a wall. In v1
## there is nothing about water to discover: `navigable[i]` is exactly
## `elevation(i) < sea_level` (naval 2.1), no building subtracts from it,
## and no ramp carves it — so a per-side belief array would be identical
## to the truth array for every side on every tick, and fogging it would
## be cost with provably no effect.
##
## `test_naval_domain.gd` asserts that premise rather than trusting it: if
## anything ever subtracts a cell from `_navigable` — naval 2.2 names a
## sea wall and a floating platform as the cases — the test fires and this
## layer needs belief before that lands.
func _field_for_water(destination_index: int) -> FlowField:
	if _fields_water.has(destination_index):
		return _fields_water[destination_index]

	var started := Time.get_ticks_usec()
	var field := FlowField.new()
	field.begin(space, space.from_index(destination_index), _navigable)
	var remaining := maxi(0, water_field_cells_per_tick - _field_cells_this_tick_water)
	if not field.expand(remaining) and not _pending_fields_water.has(destination_index):
		_pending_fields_water.append(destination_index)
	_field_cells_this_tick_water += field.expanded_cells()
	total_field_usec += Time.get_ticks_usec() - started

	_fields_water[destination_index] = field
	fields_built += 1
	return field


## The water counterpart of `_expand_pending_fields` — identical shape,
## over the water dictionary/queue/budget.
func _expand_pending_fields_water() -> void:
	_field_cells_this_tick_water = 0
	if _pending_fields_water.is_empty():
		return

	var still_pending: Array[int] = []
	for destination_index in _pending_fields_water:
		var field: FlowField = _fields_water.get(destination_index, null)
		if field == null or field.is_complete():
			continue
		var remaining := maxi(0, water_field_cells_per_tick - _field_cells_this_tick_water)
		if remaining == 0:
			still_pending.append(destination_index)
			continue
		var before := field.expanded_cells()
		if not field.expand(remaining):
			still_pending.append(destination_index)
		_field_cells_this_tick_water += field.expanded_cells() - before
	_pending_fields_water = still_pending


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
## is *now*. One keyframe per cell the flow field walks; where they end up
## and how long each takes is _path_curve()'s business.
func _rebuild_curve(squad: int) -> void:
	var current := _cell[squad]
	# The cell path first, the curve second. Timing a path needs to know
	# where it turns, and a turn is only visible once the step after it
	# exists — so the walk cannot also be the emit (D-20260818).
	var cells := PackedInt32Array([current])

	var speed := _speed[squad]
	# The sprint (D-20260819-a-charge-is-spent-on-its-impact). Expiry
	# rebuilds the curve, so a lapsed charge slows on the next keyframe
	# rather than at the destination.
	if is_charging(squad):
		speed *= CHARGE_SPEED_MULT
	elif has_stance(squad, STANCE_RUN) and _fatigue[squad] > RUN_MIN_FATIGUE:
		speed *= RUN_PACE_MULT
	# A fighting style's mobility price (D-20260819-a-formation-is-a-
	# fighting-style): a testudo crawls because its data says so.
	var style := FormationRoster.by_id(StringName(_shape[squad]))
	if style != null:
		speed *= style.pace_scale
	# Set when a planned step turns out to cross ground this side now knows
	# is blocked: the field that produced it was solved against older
	# knowledge, so it is dropped and the give-up rule below is held off
	# (D-20260818-pathing-knows-only-what-the-player-knows).
	var stale := false
	if speed > 0.0 and _destination[squad] != current:
		var knower := knowledge_group_of(squad)
		# D-076: the squad's OWN tier picks which layer serves this path —
		# ground or the wall-top network. A squad never silently crosses
		# tiers here; that only happens through `_advance_tier_transitions`.
		var field := _field_for(_destination[squad], knower, _tier[squad])
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

		var max_steps := maxi(1, ceili(curve_lookahead_seconds * speed))

		for _i in range(max_steps):
			if current == field.destination:
				break
			var next := field.step_from(current)
			if next == current:
				break  # unreachable; stall rather than wander

			# The route was planned on what this side BELIEVES, and belief
			# is optimistic about ground nobody has looked at
			# (D-20260818-pathing-knows-only-what-the-player-knows). So the
			# step about to be written is the moment of truth, and it does
			# two jobs at once:
			#
			# 1. DISCOVERY. A squad about to walk onto a cell learns what it
			#    is, whatever its vision_range — the safety net that keeps
			#    optimism from ever putting soldiers inside a mountain, and
			#    the only teacher a sightless unit has.
			# 2. RE-ROUTE. If the cell is blocked in truth or in what this
			#    side now knows, the cached field predates the knowledge and
			#    must be re-solved. The curve keeps the prefix already
			#    written, so the squad walks up to the obstruction while the
			#    new field is being solved rather than stopping dead.
			#
			# `_passable` empty means a sim with no terrain at all (most
			# tests): nothing to be wrong about, and no belief array worth
			# allocating.
			if _tier[squad] == 0 and not _passable.is_empty():
				var open := next < _passable.size() and _passable[next] != 0
				if knowledge.discover(knower, next, open, _passable.size()):
					route_discoveries += 1
				if not open or not knowledge.believes_passable(knower, next):
					stale = true
					break

			cells.append(next)
			current = next

		if stale:
			# Dropped, not re-solved here: field builds are budgeted (D-040)
			# and re-entering the solver from inside a curve rebuild would
			# spend that budget out of turn. The next rebuild — next tick,
			# since the curve now ends where the squad is heading — solves
			# against what this side knows NOW, and every squad sharing the
			# field gets the corrected route with it.
			_fields.erase(Vector2i(_destination[squad], knower))

	var curve := _path_curve(squad, cells, speed)

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
	#
	# D-20260818-pathing-knows-only-what-the-player-knows narrows what
	# "unreachable" is allowed to mean here: the field is solved against
	# this side's own knowledge, so this now fires only when the ground the
	# player has actually SEEN proves the destination impossible — never on
	# the strength of a lake nobody has scouted. `stale` holds it off for
	# the one tick between discovering an obstruction and re-solving
	# around it; without that, walking into the first unknown wall would
	# read as a refusal and cancel a perfectly good order.
	#
	# The "unreachable now is unreachable later" reasoning survives intact:
	# belief only ever loses passable cells (see terrain_knowledge.gd), so
	# a destination the known map has ruled out cannot be re-opened by
	# further exploration — only by passability itself changing, which is
	# what `set_passable`'s retry is for.
	if curve.key_count() <= 1 and current != _destination[squad] and not stale:
		_deferred_destination[squad] = _destination[squad]
		_destination[squad] = current

	_curves[squad] = curve
	replicator.set_curve(squad, curve)
	_log_curve(squad, curve)
	curves_rebuilt += 1


## Turn a flow-field cell path into the squad's replicated curve
## (D-20260818). Two jobs, and they only work together:
##
##  1. **Smooth the lattice out of the path.** A flow field steps between
##     hex centres, so it walks a route off the six lattice directions as
##     a run of one direction and then a run of another. Facing is derived
##     from the curve, so every junction between runs reads as a real 60
##     degree turn — that is most of the "formations jump around", and it
##     is not a turn at all. Smoothing is binomial and pins both ends: the
##     squad is standing on the first point and arrival is tested against
##     the last, so neither may move. A smoothed point that would round
##     onto impassable ground is left where the field put it — the field's
##     cells are the ones proven walkable, and this is a nicer line
##     through them, not a new route.
##
##  2. **Give the outermost soldier a pace he can walk.** The formation
##     rotates with the squad's facing, so where the path bends, the man
##     on the outside covers `1 + lever * curvature` times the distance
##     the centre does. Dividing the centre's speed by exactly that puts
##     HIM on his own move_speed — and the men on the inside of the turn
##     cover less ground in the same time, without anything anywhere being
##     told to slow them down. That is the whole of #101's rule.
##
## The squad is already at the turning pace as it APPROACHES a bend,
## because facing is derived by looking ahead (Formation.HEADING_ARC):
## the block wheels into a corner and is square to the new direction by
## the time it gets there.
func _path_curve(squad: int, cells: PackedInt32Array, speed: float) -> StateCurve:
	var curve := StateCurve.new()
	if cells.is_empty():
		return curve

	# Unwrapped continuous axial space, exactly as StateCurve.append_cell
	# maintains it — done here rather than through append_cell because the
	# points are about to be moved off their cell centres (D-008's tax).
	var points := PackedVector2Array()
	var first := space.normalize(space.from_index(cells[0]))
	points.append(Vector2(float(first.x), float(first.y)))
	for i in range(1, cells.size()):
		var d := space.delta(space.from_index(cells[i - 1]), space.from_index(cells[i]))
		points.append(points[i - 1] + Vector2(float(d.x), float(d.y)))

	if cells.size() == 1:
		curve.append_axial(time, points[0])
		return curve

	var hex_width := space.hex_size * TorusSpace.SQRT_3
	# Formation offsets are world units; `speed` is cells per second.
	var lever := 0.0
	if hex_width > 0.0:
		lever = Formation.turn_lever(
			_shape[squad], _alive[squad], _spacing[squad]) / hex_width

	# The field's own line, carried alongside at whatever resolution the
	# refinement loop below reaches. Every point on it is a cell centre or
	# a point between two ADJACENT cell centres, so the whole of it is
	# ground the field itself walked — which is what makes it the line
	# _walkable_line can always retreat to.
	var raw := points.duplicate()

	points = _smooth_path(_pushed_clear(points, _tier[squad]), _tier[squad])

	# The facing chord spans Formation.HEADING_ARC of path, so a bend
	# packed into a shorter stretch than that gets swept in one go rather
	# than followed round — the snap again, at keyframe granularity.
	# Halving the spacing is the only lever that reaches it: a longer chord
	# is capped by the replication horizon, and more smoothing pulls the
	# route off the cells the flow field proved walkable. A straight march
	# has no bend to resolve and never enters the loop, so it buys no
	# keyframes for this.
	for _round in range(PATH_REFINEMENTS):
		if _bends_are_resolved(points):
			break
		raw = _subdivided(raw)
		points = _smooth_path(_subdivided(points), _tier[squad])

	points = _walkable_line(points, raw, _tier[squad])

	var lengths := _segment_lengths(points)
	var paces := _segment_paces(points, lengths, speed, lever)

	var at := time
	curve.append_axial(at, points[0])
	for i in range(lengths.size()):
		at += lengths[i] / paces[i]
		curve.append_axial(at, points[i + 1])
	return curve


## Length of each segment of `points`, in cells.
func _segment_lengths(points: PackedVector2Array) -> PackedFloat32Array:
	var hex_width := maxf(space.hex_size * TorusSpace.SQRT_3, 0.0001)
	var out := PackedFloat32Array()
	for i in range(points.size() - 1):
		out.append(
			space.axial_offset_to_world(points[i + 1] - points[i]).length() / hex_width)
	return out


## How fast the squad may walk each segment, in cells per second.
##
## The outermost soldier walks `1 + lever * curvature` times as far as the
## squad centre does — his own path around the outside of the turn — so
## dividing the centre's speed by that is exactly what puts HIM on
## move_speed. That is the whole rule from #101, in one line.
##
## Curvature is taken from the sharper of the two vertices bounding the
## segment, because the facing chord straddles a vertex and the squad has
## to already be walking at the turning pace when it arrives.
## TURN_SWEEP is the margin for the chord sweeping unevenly rather than at
## its average rate, and MIN_TURNING_SPEED the floor under all of it.
func _segment_paces(points: PackedVector2Array, lengths: PackedFloat32Array,
		speed: float, lever: float) -> PackedFloat32Array:
	var turns := PackedFloat32Array()
	for i in range(lengths.size()):
		var here := space.axial_offset_to_world(points[i + 1] - points[i])
		var turn := 0.0
		if i + 2 < points.size():
			var onward := space.axial_offset_to_world(points[i + 2] - points[i + 1])
			if here.length_squared() > 1e-12 and onward.length_squared() > 1e-12:
				turn = absf(here.signed_angle_to(onward, Vector3.UP))
		turns.append(turn)

	var floor_speed := speed * MIN_TURNING_SPEED
	var out := PackedFloat32Array()
	for i in range(lengths.size()):
		# The sharper of the two vertices bounding this segment: the chord
		# straddles a vertex, so the squad has to already be walking at the
		# turning pace by the time it arrives at one.
		var curvature := turns[i] / maxf(lengths[i], 0.0001)
		if i > 0:
			curvature = maxf(curvature, turns[i - 1] / maxf(lengths[i - 1], 0.0001))
		out.append(clampf(
			speed / (1.0 + lever * TURN_SWEEP * curvature), floor_speed, speed))
	return out


## Whether every segment that turns is short enough for the facing chord
## to span it. A segment that does not turn needs no resolution at all,
## which is why a straight march buys no extra keyframes here.
func _bends_are_resolved(points: PackedVector2Array) -> bool:
	for i in range(1, points.size() - 1):
		var a := points[i] - points[i - 1]
		var b := points[i + 1] - points[i]
		if a.length_squared() <= 1e-12 or b.length_squared() <= 1e-12:
			continue
		if absf(a.angle_to(b)) <= STRAIGHT_ENOUGH:
			continue
		if a.length() > Formation.HEADING_ARC or b.length() > Formation.HEADING_ARC:
			return false
	return true


## A midpoint inserted in every segment. Geometry unchanged — it is the
## RESOLUTION that changes, so the smoothing pass after it has somewhere
## finer to spread a corner into.
func _subdivided(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(points.size() - 1):
		out.append(points[i])
		out.append((points[i] + points[i + 1]) * 0.5)
	out.append(points[points.size() - 1])
	return out


## The field's path, with every interior point nudged away from the
## blocked cells beside it (D-20260818, amended for #133/#135).
##
## This is what buys the smoothing its room. A flow-field route that
## rounds an obstacle runs along the obstacle's edge, so every point of
## the interesting stretch has the blockage on the inside of its own bend
## — which is exactly where a binomial pass wants to pull it. Without the
## push, every one of those points is refused, the route keeps the
## lattice's 60 degree vertices, and a turn concentrated at one vertex is
## one no pace can wheel through: `MIN_TURNING_SPEED` floors the crawl
## long before the outermost soldier is inside his own move_speed.
##
## Direction is summed in WORLD space, not in axial: the six neighbours
## are a regular hexagon on the ground and a skewed one in axial
## coordinates, so summing axial offsets would push hardest along the
## lattice's long diagonal. `axial_offset_to_world` is linear, so the sum
## can still be carried in axial and only its LENGTH measured in world —
## which is D-008's tax paid the cheap way.
##
## Endpoints are pinned for the same reason `_smooth_path` pins them: the
## squad is standing on the first point and arrival is tested against the
## last. And a pushed point that would round onto blocked ground is
## dropped rather than clamped, because `_walkable_line` is the guarantee
## and this is only the room-making.
func _pushed_clear(points: PackedVector2Array, tier: int) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var hex_width := maxf(space.hex_size * TorusSpace.SQRT_3, 0.0001)
	var out := points.duplicate()
	for i in range(1, points.size() - 1):
		var cell := space.normalize(space.round_axial(points[i]))
		var away := Vector2.ZERO
		for d in TorusSpace.DIRECTIONS:
			if not is_passable(space.normalize(cell + d), tier):
				away -= Vector2(float(d.x), float(d.y))
		if away == Vector2.ZERO:
			continue
		var reach := space.axial_offset_to_world(away).length()
		if reach <= 0.0:
			continue
		var moved := points[i] + away * (PATH_CLEARANCE * hex_width / reach)
		if is_passable(space.normalize(space.round_axial(moved)), tier):
			out[i] = moved
	return out


## The smoothed path, with any vertex whose line of travel would cross
## ground the squad could not walk on put back where the flow field had
## it (D-20260818, amended for #133/#135).
##
## ## Why testing the VERTEX is not enough
##
## `_smooth_path` already refuses to MOVE a point onto a blocked cell, and
## that was the whole guard when this was written. It is not sufficient,
## and the two rules that landed while this branch sat say so from
## opposite ends:
##
##  * A squad's authoritative cell is `curve.sample_cell()`, which is a
##    point BETWEEN two keyframes far more often than it is one of them.
##    Two vertices can each sit on open ground with the straight line
##    between them clipping the corner of a rock, and the squad is then
##    standing in the rock for as long as it takes to cross.
##    `test_a_blind_squad_still_never_stands_in_a_wall`
##    (D-20260818-pathing-knows-only-what-the-player-knows) is what caught
##    it: discovery-by-touch checks the CELLS the field steps through, and
##    a line drawn between two of them is not one of those cells.
##  * Soldier offsets are pulled back onto walkable ground about the
##    squad's own cell (D-20260818-a-soldier-stands-where-his-squad-could-
##    walk), and that clamp's guaranteed fallback is "the squad's own
##    cell, which is passable by construction". Smoothing is the one thing
##    that could make that sentence false, so it is smoothing's job to
##    keep it true.
##
## `_subdivided` compounds it, because a midpoint it inserts is a point
## nothing has ever tested.
##
## ## Why it retreats to the field's line rather than searching
##
## `raw` is the same polyline at the same resolution with none of the
## smoothing applied — cell centres, and midpoints between ADJACENT cell
## centres. Every point of it is walkable and so is every point between
## two consecutive ones, so reverting always terminates somewhere legal. A
## nudge would have to search, and a search here would be a second router
## quietly disagreeing with the flow field.
func _walkable_line(points: PackedVector2Array, raw: PackedVector2Array,
		tier: int) -> PackedVector2Array:
	if points.size() < 3 or raw.size() != points.size():
		return points

	var out := points.duplicate()
	for _round in range(PATH_CLEARANCE_ROUNDS):
		var reverted := false
		for i in range(1, out.size() - 1):
			if out[i] == raw[i]:
				continue
			if (_segment_clear(out[i - 1], out[i], tier)
					and _segment_clear(out[i], out[i + 1], tier)):
				continue
			out[i] = raw[i]
			reverted = true
		if not reverted:
			return out

	# Still crossing something after the bounded repair: take the field's
	# line whole. A squad snapping round a corner is a worse picture than
	# one wheeling; a squad standing inside a mountain is not a picture
	# problem at all.
	return raw


## Whether a squad walking straight from `a` to `b` in continuous axial
## space stays on ground it could stand on the whole way.
##
## Sampled rather than rasterised, at `TorusSpace.round_axial` — the
## project's ONE answer to "which hex is this fractional axial coordinate
## in", and the one `world_to_cell` goes through. Four samples per cell of
## travel; after refinement these segments are a fraction of a cell long,
## so it is two or three lookups each.
##
## **Not `roundi` per component, which is what `StateCurve.sample_cell`
## does.** The two agree everywhere except on exact half-coordinates,
## where naive rounding lands on a cell that is a NEIGHBOUR OF BOTH the
## cells the step runs between — and `_subdivided` manufactures exactly
## those coordinates, because the midpoint of a step along the (1,-1)
## lattice direction is a pair of halves. Asking the naive question there
## declared the flow field's own line unwalkable, and the repair below
## then reverted a run of points beside an already-smoothed neighbour,
## putting a **78.4 degree** spike in a path whose sharpest genuine corner
## is 60. That the two roundings differ at all is a real inconsistency and
## is not this change's to fix: `sample_cell` disagrees with
## `world_to_cell` on a set of measure zero, which is why nothing has ever
## caught it.
func _segment_clear(a: Vector2, b: Vector2, tier: int) -> bool:
	var d := b - a
	var steps := maxi(1, ceili(d.length() * 4.0))
	for i in range(steps + 1):
		var at := a + d * (float(i) / float(steps))
		if not is_passable(space.normalize(space.round_axial(at)), tier):
			return false
	return true


## PATH_SMOOTHING_PASSES binomial passes with both endpoints pinned. See
## _path_curve() for why. `previous` carries the pre-pass value of the
## neighbour already overwritten, so a pass filters the path it was handed
## rather than half-filtering its own output.
##
## A move is kept only if the squad could WALK both of the segments it
## leaves behind, not merely stand on the point itself
## (D-20260818, amended for #133/#135). The point test was the original
## guard and it is wrong twice over: the squad's own cell is
## `curve.sample_cell()` at any time at all, so the line between two
## keyframes is as authoritative as the keyframes; and refusing a single
## point while its neighbours move puts a SPIKE in the path — measured at
## 82.9 degrees on a lattice whose sharpest genuine corner is 60, which is
## a worse turn than the one the smoothing was called to soften. Testing
## the segments makes a refused point hold its neighbours back with it, so
## the path stays a path.
func _smooth_path(points: PackedVector2Array, tier: int) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := points.duplicate()
	for _pass in range(PATH_SMOOTHING_PASSES):
		var previous := out[0]
		for i in range(1, out.size() - 1):
			var moved := previous * 0.25 + out[i] * 0.5 + out[i + 1] * 0.25
			previous = out[i]
			if (_segment_clear(out[i - 1], moved, tier)
					and _segment_clear(moved, out[i + 1], tier)):
				out[i] = moved
	return out


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
	# Built once for the whole sweep rather than once per stranded squad:
	# this runs with a wall coming down, which is exactly when several
	# squads drop at once.
	var held := _ground_held()
	var widest := _widest_footprint()
	for squad in range(_cell.size()):
		if _tier[squad] != 1 or _alive[squad] <= 0:
			continue
		if buildings != null and buildings.is_walkable_top_cell(_cell[squad]):
			continue
		_tier[squad] = 0
		var spot := space.index(
			_free_cell_near(space.from_index(_cell[squad]), squad, held, widest))
		# Held straight away, so a second squad dropping in the same sweep
		# is not sent to the cell this one just took.
		_hold_ground(held, spot, squad)
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

	# The fatigue economy (D-20260819-tired-men-fight-uphill), replacing
	# the charge deadline outright as the charge entry promised: sprint
	# and fight spend, rest recovers, and the cost LINGERS — a squad
	# cannot charge, rest a moment, and charge again for free.
	var fatigue_dt := 1.0 / float(TICK_HZ)
	for squad in range(_fatigue.size()):
		if _alive[squad] <= 0:
			continue
		var moving := _destination[squad] != _cell[squad]
		var drain := -FATIGUE_RECOVERY
		if is_charging(squad):
			drain = FATIGUE_CHARGE_DRAIN
		elif combat != null and combat.is_engaged(squad):
			drain = FATIGUE_FIGHT_DRAIN
		elif moving and has_stance(squad, STANCE_RUN):
			drain = FATIGUE_RUN_DRAIN
		var was := _fatigue[squad]
		_fatigue[squad] = clampf(was - drain * fatigue_dt, 0.0, 100.0)
		# A sprint ends when the legs give out — with a curve rebuild so
		# the squad slows at the next keyframe, not at the destination.
		if _charge_until.has(squad) and _fatigue[squad] <= CHARGE_EXHAUST_FLOOR:
			_charge_until.erase(squad)
			if moving:
				_rebuild_curve(squad)
		# A runner who crosses the floor drops to a walk the same way.
		elif moving and has_stance(squad, STANCE_RUN) \
				and was > RUN_MIN_FATIGUE and _fatigue[squad] <= RUN_MIN_FATIGUE:
			_rebuild_curve(squad)

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
	_expand_pending_fields_water()  # naval 2.3: and so does the water layer
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

	# A squad that just reached a tower's door hops tiers here (D-076) —
	# after positions are derived and arrivals settle, so it acts on this
	# tick's real position, and before vision/combat see the result.
	_advance_tier_transitions()
	# And a squad that just reached a quay boards here, for the identical
	# reason and in the identical place: on this tick's real position,
	# before vision and combat see the result — so a squad that is aboard
	# is aboard for the whole of the tick in which anything could have
	# seen or shot it.
	last_embarks = _advance_embarks()
	# And a laden hull beside its target puts its cargo ashore. After the
	# embarks so that the two cannot interleave within one tick: a squad
	# boards or lands, never both.
	last_landings = _advance_landings()

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
		# What each side can see, it now knows about the GROUND as well
		# (D-20260818-pathing-knows-only-what-the-player-knows). Folded
		# here, on vision's own cadence and out of vision's own coverage,
		# so no disk is walked twice and pathing knowledge can never be
		# wider than sight.
		#
		# Inside the timed block deliberately: this IS the vision phase,
		# same cadence over the same cells, and `last_vision_usec` should
		# name the whole of it. Said out loud because #105 is an open
		# investigation into an unattributed per-squad rise, and a new cost
		# quietly joining an existing slice is exactly how a number stops
		# meaning what its name says.
		knowledge.absorb(vision, _passable)
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
	combat.apply_skirmish(self, tick_count)
	# Both halves of the combat phase, not just resolve(): the assignment
	# scan is combat work and would otherwise land in the residual.
	# A hull that went down this tick takes its cargo with it (naval 3.2).
	# After combat, because combat is what sinks it, and before anything
	# reads the cargo lists — so a drowned squad is drowned for the whole
	# of the tick in which it died.
	last_drownings = _advance_drownings()

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
			var door := _spawn_cell_near(buildings, at, produced)
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

	# Squads that have arrived settle out of each other's formations
	# (D-060), so an army stands as a body rather than a heap. Only
	# touches squads already at their destination, so it costs nothing
	# while everyone is walking and never interferes with a journey in
	# progress.
	#
	# AFTER combat, deliberately: the pass exempts a squad that has
	# something in reach, and combat is what knows. Run before it, the
	# exemption is a tick stale — which is exactly one tick too late,
	# because the tick a besieging squad arrives is the tick separation
	# would send it back out of range (#104).
	#
	# Its OWN phase, not folded into whichever one it happens to sit next
	# to: it is a hex-disk scan per settled squad now, which is a real
	# share of a tick. `phase_usec_per_squad_update` partitions the tick
	# exactly (D-20260818), so a pass without its own accumulator does not
	# go unmeasured — it goes into `other`, which is the same disappearing
	# act that decision exists to stop.
	var separation_started := Time.get_ticks_usec()
	_separate_arrivals()
	last_separation_usec = Time.get_ticks_usec() - separation_started
	total_separation_usec += last_separation_usec
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
		+ total_combat_usec + total_buildings_usec + total_economy_usec
		+ total_separation_usec)
	return {
		"fields": _mean_usec_per_squad_update(total_fields_usec),
		"curves": _mean_usec_per_squad_update(total_curves_usec),
		"vision": _mean_usec_per_squad_update(total_vision_usec),
		"combat": _mean_usec_per_squad_update(total_combat_usec),
		"buildings": _mean_usec_per_squad_update(total_buildings_usec),
		"production": _mean_usec_per_squad_update(total_production_usec),
		"economy": _mean_usec_per_squad_update(total_economy_usec),
		"separation": _mean_usec_per_squad_update(total_separation_usec),
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
		_curves[squad], sample_at, _alive[squad], _shape[squad], _spacing[squad],
		space, Callable(), PackedByteArray(), _files[squad], facing_angle_of(squad)
	)


## Force an immediate vision rebuild, bypassing
## `vision_recompute_every_ticks`. Tests use this to get a deterministic,
## up-to-date field right after moving squads around, rather than ticking
## an arbitrary number of times and hoping the schedule has caught up.
func recompute_vision_now() -> void:
	vision.rebuild(self, buildings)
	knowledge.absorb(vision, _passable)


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


## Spend a squad founding something. Returns the casualty events
## describing it, or an empty array if there was nothing to consume.
##
## Which buildings cost their builder is data
## (`BuildingDef.consumes_builder`, D-20260823-the-opening-is-a-crew-and-
## a-general); on the shipped roster it is the town centre and nothing
## else.
##
## Consumed when the order is ACCEPTED, not when the building finishes.
## That timing is the whole mechanism: consuming on completion left the
## crew standing for the length of the build, and one crew could queue as
## many town halls as it could click on — which is exactly what the first
## playtest did, three times in a row. Committing the crew to the site
## immediately makes one crew mean one town.
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
## Whose knowledge solves this squad's routes: its owner, or its TEAM
## where it has one, because allies share sight (D-050) and therefore
## share what they have explored. `Vision.group_of_player` is the one
## definition of that grouping — see it for why this is not spelled out
## again here.
func knowledge_group_of(squad: int) -> int:
	return Vision.group_of_player(_owner[squad], teams)


func are_allied(a: int, b: int) -> bool:
	if a == b:
		return true
	var team_a := int(teams.get(a, 0))
	var team_b := int(teams.get(b, 0))
	return team_a != 0 and team_a == team_b


# --- civs (D-047) -----------------------------------------------------

## player id -> the CivDef whose mechanical knobs are in force for them
## (D-047). Empty means "nobody's civ is known", which is a real state
## rather than a broken one — see `CivRoster.effects_of`.
##
## Held here for exactly the reason `teams` is, one line above: the
## MECHANICAL consequences of a civ are read from inside this class's own
## tick (the economy's gather rate) and by callers that already hold the
## simulation (the squad cap). MatchState owns CHOOSING a civ; this owns
## the consequence, and there is ONE handover rather than one per
## mechanism — which matters, because #119's lesson is that the handover
## nothing performs is the dangerous half.
##
## The resolved def rather than the id: the server's `_civ_of` stays the
## one place a player BECOMES a civ, and resolving once at handover keeps
## a roster lookup out of the gather path. A test can also hand a
## synthetic CivDef straight in, the same way every fixture here builds a
## synthetic UnitDef — which is what lets a knob no shipped civ turns yet
## still be exercised.
var civs := {}


## The knobs in force for `player`. Never null, so a caller reads a
## multiplier rather than branching on whether a civ is known.
func civ_effects(player: int) -> CivDef:
	var def = civs.get(player, null)
	return def if def is CivDef else CivRoster.effects_of(&"")
