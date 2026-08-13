extends RefCounted
class_name BuildingSim

## Buildings — the second networked entity class (D-029, D-031).
##
## A sibling of `SquadSim`, not a merger into it. Squads and buildings
## share almost no per-tick logic: a building never moves, so destination,
## speed, formation, morale, routing and the damage/attack accumulators
## are all squad-only, while construction progress and a production queue
## have no squad equivalent. Merging them would reproduce the "which kind
## of entity is row i" ambiguity under a different name, in a language
## with no generics to resolve it.
##
## ## The id space, which is where the danger is
##
## `SquadSim.add_squad` mints an id as `_cell.size()` — the id IS the
## array index. A `BuildingSim` doing the same starts at 0 too, so the
## first squad and the first building are both entity 0. Anything that
## funnels both through one `CurveReplicator`, one `ReplayLog` key, or one
## `composition_hash` entry list would then have a building silently
## corrupt a squad's record: no error, no crash, just wrong state — the
## same invisible-corruption class that has now twice been caught late in
## this project (D-022's audit, D-026's review).
##
## Two defences, deliberately belt and braces:
##
## 1. Buildings keep their own replicator, their own client-side
##    dictionaries and their own wire opcodes, so the two id spaces never
##    meet in the ordinary path. `CurveReplicator` and `ReplayLog` are
##    already entity-agnostic — they key on whatever integer they are
##    handed — so this costs nothing but discipline.
## 2. `wire_id()` offsets building ids far above any plausible squad count
##    (D-018 targets ~1,000 squads at full scale), so *if* some future
##    code does need one unified entity id, it gets an unambiguous answer
##    instead of a collision.

## Far above D-018's ~1,000-squad full-scale target, so a wire id can
## never be mistaken for a squad id even by code that forgot the
## distinction exists.
const BUILDING_ID_OFFSET := 1_000_000

var space: TorusSpace

# --- packed state (D-009), one entry per building --------------------
var _cell := PackedInt32Array()
var _owner := PackedInt32Array()
var _defs: Array[BuildingDef] = []
var _health := PackedFloat32Array()
var _progress := PackedFloat32Array()  # 0..1; 1.0 means complete
var _destroyed := PackedByteArray()
var _last_attack_tick := PackedInt32Array()  # -1 = never fired

## Player-assigned focus-fire target (a squad id), or -1 for "automatic —
## nearest enemy in range" (Combat._find_squad_near's default). Set by
## C2S_ORDER_BUILDING_TARGET; cleared automatically when the target dies
## (Combat.resolve_buildings). Server-only — not replicated, since only the
## owner can set it and nothing downstream needs to know a target is manual
## versus automatic, only who it currently is.
var _forced_target := PackedInt32Array()

# --- gates and the wall-top access tower (D-076) ----------------------

const GATE_MODE_MANUAL := 0
const GATE_MODE_AUTO := 1

## Whether a gate is currently passable. Meaningful only when
## `def.is_gate`; every non-gate building carries a harmless 0 here and is
## never read through this array (blocking_cells() below only consults it
## for gates).
var _gate_open := PackedByteArray()

## GATE_MODE_MANUAL or GATE_MODE_AUTO. New gates start in auto mode — the
## ergonomic default, switchable per-building from the selection HUD.
var _gate_mode := PackedByteArray()

## Which hex side (an index into `TorusSpace.DIRECTIONS`, 0-5) THIS
## building faces, chosen at placement and rotatable in the placement
## ghost before confirming. Stored per INSTANCE, not on the shared
## `BuildingDef` — a def is one Resource per archetype, so a per-placement
## choice like this can't live there (see `BuildingDef.is_access_tower`'s
## doc, which explains it for the one def that also gives facing
## mechanical meaning). Every building has one, defaulting to 0 (east) —
## for most buildings this is purely cosmetic mesh rotation; for an
## access tower it is also the door (`door_cell_of`).
var _facing := PackedInt32Array()

# Ids whose replicated state changed and have not been sent yet.
var _dirty := {}

# building -> Array of { "def_id": StringName, "remaining": float }
var _queues := {}

# Which squad founded each building, or -1. Parallel to the rest.
var _builder := PackedInt32Array()

## Where each building sends what it produces, as a cell index, or -1 for
## "not set" — in which case `rally_of` answers with the default.
##
## A produced squad used to appear at `cell + (1, 0)`, one hex from the
## building's centre, which is INSIDE the 2.4-wide box drawn on a 1.73-wide
## hex: units materialised standing in the wall of the thing that made
## them. They now spawn clear of it and walk to this point.
var _rally := PackedInt32Array()

## How far in front of a building its default rally point sits, in cells.
## Far enough that a squad standing there is visibly outside the building
## rather than leaning against it.
const DEFAULT_RALLY_CELLS := 3


## Where this building sends what it produces.
##
## Defaults to a few cells "in front", which for a building with no facing
## means a fixed direction — arbitrary, but it has to be deterministic
## because both sides derive it, and consistent so a player learns where
## their troops appear.
func rally_of(building: int) -> Vector2i:
	if building < 0 or building >= _cell.size():
		return Vector2i.ZERO
	if _rally[building] >= 0:
		return space.from_index(_rally[building])
	return space.normalize(space.from_index(_cell[building])
		+ Vector2i(DEFAULT_RALLY_CELLS, 0))


## The living building standing on a cell, or -1.
##
## Linear over buildings rather than a cell->building map, because there
## are orders of magnitude fewer buildings than cells and a map would be a
## second source of truth to keep in step with `_cell`. If building counts
## ever reach the thousands this is the thing to index.
func building_at(cell: Vector2i) -> int:
	var index := space.index(cell)
	for i in range(_cell.size()):
		if _destroyed[i] == 0 and _cell[i] == index:
			return i
	return -1


## Cells that living buildings stand on, for the simulation's passability
## (D-007). A squad should walk AROUND a town hall, not through it.
func occupied_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(_cell.size()):
		if _destroyed[i] == 0:
			out.append(_cell[i])
	return out


func set_rally(building: int, cell: Vector2i) -> void:
	if building < 0 or building >= _cell.size():
		return
	_rally[building] = space.index(cell)
	_dirty[building] = true


func _init(p_space: TorusSpace = null) -> void:
	space = p_space if p_space != null else TorusSpace.new()


func building_count() -> int:
	return _cell.size()


## Local id (the array index). Use wire_id() for anything that leaves this
## class and might meet a squad id.
## `builder` is the squad that founded this, or -1. Recorded because
## founders are CONSUMED by the town they found (D-031): the founding
## party becomes the settlement rather than wandering off from it.
## `facing` is which of `TorusSpace.DIRECTIONS`' 6 sides this instance
## faces (0 if unspecified) — cosmetic mesh rotation for most buildings,
## and also the door for an access tower (D-076).
func add_building(def: BuildingDef, owner: int, at: Vector2i, complete := false,
		builder: int = -1, facing: int = 0) -> int:
	var id := _cell.size()
	_builder.append(builder)
	_rally.append(-1)
	_cell.append(space.index(at))
	_owner.append(owner)
	_defs.append(def)
	_health.append(def.max_health)
	_progress.append(1.0 if complete else 0.0)
	_destroyed.append(0)
	_last_attack_tick.append(-1)
	_forced_target.append(-1)
	_gate_open.append(0)
	_gate_mode.append(GATE_MODE_AUTO)
	_facing.append(posmod(facing, 6))
	return id


## The squad that founded this building, or -1. Consumed on completion.
func builder_of(building: int) -> int:
	return _builder[building]


func last_attack_tick_of(building: int) -> int:
	return _last_attack_tick[building]


func set_last_attack_tick(building: int, tick: int) -> void:
	_last_attack_tick[building] = tick


func forced_target_of(building: int) -> int:
	return _forced_target[building]


func set_forced_target(building: int, target: int) -> void:
	_forced_target[building] = target


func is_gate_open(building: int) -> bool:
	return _gate_open[building] == 1


## Flips a gate's passable state and marks it dirty for replication. Does
## NOT itself refresh SquadSim's passability — the caller (server.gd) does
## that once, after deciding the new state, the same way it already does
## after any other building-set change.
func set_gate_open(building: int, open: bool) -> void:
	var value := 1 if open else 0
	if _gate_open[building] == value:
		return
	_gate_open[building] = value
	_dirty[building] = true


func gate_mode(building: int) -> int:
	return _gate_mode[building]


func set_gate_mode(building: int, mode: int) -> void:
	if _gate_mode[building] == mode:
		return
	_gate_mode[building] = mode
	_dirty[building] = true


## Which way this building's mesh should face when rendered (0-5, an index
## into `TorusSpace.DIRECTIONS`) — cosmetic for most buildings, and also
## the door direction for an access tower. Always a real value, never -1;
## see `access_direction_of` for the tower-only "does this door exist"
## question.
func facing_of(building: int) -> int:
	return _facing[building]


## The chosen door facing for an access tower, or -1 if `building` is not
## one — `is_access_tower` is what gives `facing_of`'s value door meaning
## at all, so this stays a separate, narrower question from that one.
func access_direction_of(building: int) -> int:
	return _facing[building] if _defs[building].is_access_tower else -1


## The chosen door facing for a living access-tower standing on `cell`
## (a cell INDEX, not a Vector2i), or -1 if there is none — no tower
## there, or the building there isn't an access tower (D-076). Linear
## scan, same shape and same justification as `building_at`: orders of
## magnitude fewer buildings than cells.
func access_direction_at(cell: int) -> int:
	for i in range(_cell.size()):
		if _destroyed[i] == 0 and _cell[i] == cell and _defs[i].is_access_tower:
			return _facing[i]
	return -1


## Cells a LIVING building currently blocks GROUND movement through
## (D-076). Differs from occupied_cells() in two ways — an open gate still
## stands there (still occupies its cell for placement/combat/
## occupied_cells() purposes) but a squad can walk through it while it is
## open, and (playtest fix) a wall-family segment under construction
## doesn't block AT ALL yet. Walls are built in long drag-built chains,
## and blocking on founding could seal the builder itself into a pocket
## with no path to the next segment in its own queue — reported as
## gatherers trapped against the wall they were still building.
## footprint_radius == 0 is the established wall-family signal (see
## client.gd's _snapped_placement_cell); once complete
## (`_progress >= 1.0`) a segment blocks exactly as before, including
## against its own builder — that's what a gate is for.
## server._refresh_passability() reads this, not occupied_cells(), to
## build the ground-passable array.
func blocking_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(_cell.size()):
		if _destroyed[i] == 1:
			continue
		if _defs[i].is_gate and _gate_open[i] == 1:
			continue
		if _defs[i].footprint_radius == 0 and _progress[i] < 1.0:
			continue
		out.append(_cell[i])
	return out


## Cells belonging to a complete, living, `walkable_top` building — the
## tier-1 (wall-top) passable network (D-076). A destroyed or still-under-
## construction structure contributes nothing: you cannot stand on rubble
## or scaffolding.
func walkable_top_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(_cell.size()):
		if _destroyed[i] == 0 and _progress[i] >= 1.0 and _defs[i].walkable_top:
			out.append(_cell[i])
	return out


## Whether `cell` (a cell INDEX) is currently part of the tier-1 walkable
## network (D-076) — a single-cell check for order-time inference, where
## allocating the whole `walkable_top_cells()` array would be wasted work.
func is_walkable_top_cell(cell: int) -> bool:
	for i in range(_cell.size()):
		if _cell[i] == cell and _destroyed[i] == 0 and _progress[i] >= 1.0 and _defs[i].walkable_top:
			return true
	return false


## The GROUND cell (a cell index) that must be occupied to climb onto or
## descend from this access tower's tier-1 cell, or -1 if `building` is
## not a living, complete access tower with a door direction set (D-076).
## The tower's OWN cell is always part of `walkable_top_cells()` too
## (`is_access_tower` implies `walkable_top`), so the door cell is the
## single ground-side entry point into the network — never any other cell
## adjacent to any wall segment.
func door_cell_of(building: int) -> int:
	if building < 0 or building >= _cell.size():
		return -1
	if _destroyed[building] == 1 or _progress[building] < 1.0:
		return -1
	var def := _defs[building]
	if not def.is_access_tower:
		return -1
	return space.neighbor_index(_cell[building], _facing[building])


## The access tower whose door cell is `cell` (a cell index), or -1 if
## none does (D-076) — the single question climbing needs answered: "is
## the squad standing on some tower's one door cell right now, and if so
## which tower." Linear scan, same shape and justification as
## `building_at`: orders of magnitude fewer buildings than cells.
func access_tower_at_door(cell: int) -> int:
	for i in range(_cell.size()):
		if door_cell_of(i) == cell:
			return i
	return -1


## Local id -> the id this building is known by anywhere a squad id could
## also appear. See the header for why this offset exists.
static func wire_id(local_id: int) -> int:
	return BUILDING_ID_OFFSET + local_id


## Inverse of wire_id. Returns -1 if the id is not a building's.
static func local_id(wire: int) -> int:
	return wire - BUILDING_ID_OFFSET if wire >= BUILDING_ID_OFFSET else -1


static func is_building_id(wire: int) -> bool:
	return wire >= BUILDING_ID_OFFSET


## Can this building make that unit at all? Data again (D-010): the
## `produces` list on the BuildingDef, never a match statement here.
## A building site cannot produce, and neither can rubble.
## `produces` lists ARCHETYPES, not unit ids (D-047).
##
## That is what lets one set of buildings serve every civ: a barracks
## offers "spearmen", and which spearmen you get depends on who is asking.
## The caller resolves the archetype against the acting player's civ, so a
## client cannot even name another civ's unit — criterion 4 of D-046 is
## structural here rather than a check that could be forgotten.
func can_produce(building: int, archetype: StringName) -> bool:
	if is_destroyed(building) or not is_complete(building):
		return false
	var def := def_of(building)
	return def != null and def.produces.has(archetype)


## Queue a unit. The CALLER has already taken the payment and checked the
## squad cap — this only records what was bought, so there is one place
## that decides affordability rather than two that can disagree.
## `instant` (sandbox's instant_build, dev testing only): queues at a
## near-zero remaining time instead of `def.build_time`, so
## `advance_production` finishes it on the very next call rather than
## needing a separate same-tick completion path of its own.
func enqueue(building: int, def: UnitDef, instant: bool = false) -> void:
	if not _queues.has(building):
		_queues[building] = []
	(_queues[building] as Array).append({
		"def_id": def.id, "remaining": 0.001 if instant else maxf(def.build_time, 0.001),
	})
	# The queue is replicated now, so a change to it has to reach clients
	# — otherwise a player queues a unit and the panel shows nothing.
	_dirty[building] = true


func queue_length(building: int) -> int:
	return (_queues[building] as Array).size() if _queues.has(building) else 0


## Advance every queue one tick. Returns [{building, def_id}] for units
## finished this tick, because BuildingSim has no SquadSim to spawn them
## into — the caller does that, the same shape advance_construction uses.
##
## Production is per BUILDING, not per unit: D-005 forbids per-unit
## production queues, and this is a queue of SQUADS at a structure.
func advance_production(dt: float) -> Array:
	var done := []
	for building in _queues:
		if is_destroyed(building):
			continue
		var queue: Array = _queues[building]
		if queue.is_empty():
			continue
		var head: Dictionary = queue[0]
		head["remaining"] = float(head["remaining"]) - dt
		if float(head["remaining"]) <= 0.0:
			queue.pop_front()
			done.append({"building": building, "def_id": head["def_id"]})
			# Queue shortened — tell clients, or the panel keeps showing a
			# unit that already walked out of the door.
			_dirty[building] = true
		else:
			queue[0] = head
		_queues[building] = queue
	return done


## Load a BuildingDef by id, the way UnitRoster.by_id does for units.
static func def_by_id(id: StringName) -> BuildingDef:
	var path := "res://buildings/%s.tres" % String(id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as BuildingDef


## Buildings `player` can see: its own always, plus any standing in a cell
## its vision currently covers. Same shape as SquadSim.visible_to, and it
## feeds the same per-client gating (D-004).
func visible_to(player: int, vision: Vision) -> Array:
	var ids := []
	for i in range(_cell.size()):
		if _owner[i] == player or (vision != null and vision.is_visible(player, _cell[i])):
			ids.append(i)
	return ids


## Wire entries for BUILDING_INFO, in wire ids.
func info_entries(ids: Array) -> Array:
	var out := []
	for id in ids:
		if id < 0 or id >= _cell.size():
			continue
		var queue: Array = _queues.get(id, [])
		var queued_ids := []
		for item in queue:
			queued_ids.append(String(item["def_id"]))
		out.append({
			"id": wire_id(id),
			"def_id": String(_defs[id].id),
			"owner": _owner[id],
			"cell": _cell[id],
			"progress": _progress[id],
			"destroyed": _destroyed[id] == 1,
			# For the selection panel. A fraction rather than an absolute,
			# so the client needs no copy of max_health to draw a bar.
			"health_fraction": _health[id] / maxf(_defs[id].max_health, 0.001),
			"head_remaining": float(queue[0]["remaining"]) if not queue.is_empty() else 0.0,
			"queue": queued_ids,
			# So the client can draw where troops will muster.
			"rally": space.index(rally_of(id)),
			# D-076. Harmless defaults (false/MANUAL) on every non-gate
			# building — sent uniformly rather than conditionally, matching
			# how other building-specific fields already ride along.
			"gate_open": _gate_open[id] == 1,
			"gate_mode": _gate_mode[id],
			# D-076 amendment: every building carries a facing now, not
			# just the access tower's door — the client needs it to render
			# the same rotation the player chose at placement.
			"facing": _facing[id],
		})
	return out


## Ids whose replicated state changed since the last call, and clears the
## list. Completion, destruction, damage, and any change to the production
## queue — the things a client must be told about, one of which is in the
## hash and the rest of which the selection panel draws.
##
## Still event-driven, never per tick: a building sitting idle marks
## nothing, so D-003's zero-bandwidth-when-idle claim holds even though
## this now carries health and a queue.
##
## Exists so a building whose state changes AFTER a client already knows
## it still gets resent. Without it, destruction would silently diverge
## the building hash, and it would do so only in matches long enough for
## something to be destroyed — the worst kind of bug to find late.
func take_dirty() -> Array:
	var out := _dirty.keys()
	_dirty.clear()
	out.sort()
	return out


## May a squad of `unit_def_id` construct `def`? (D-031.)
##
## The rule reads one way only, from `BuildingDef.built_by`, so there is a
## single source of truth. That is also what expresses "founders may build
## ONLY the town hall": founders are listed on the town centre and on
## nothing else, so every other building refuses them without needing a
## second, builder-side list to be kept in step with this one.
static func can_build(def: BuildingDef, unit_def_id: StringName) -> bool:
	if def == null:
		return false
	if def.built_by.is_empty():
		return true
	return def.built_by.has(unit_def_id)


func cell_of(building: int) -> Vector2i:
	return space.from_index(_cell[building])


func cell_index_of(building: int) -> int:
	return _cell[building]


func owner_of(building: int) -> int:
	return _owner[building]


func def_of(building: int) -> BuildingDef:
	return _defs[building]


func health_of(building: int) -> float:
	return _health[building]


func progress_of(building: int) -> float:
	return _progress[building]


func is_complete(building: int) -> bool:
	return _progress[building] >= 1.0 and _destroyed[building] == 0


func is_destroyed(building: int) -> bool:
	return _destroyed[building] == 1


## Advance construction on every unfinished building. Returns the ids that
## COMPLETED on this call, so the caller can announce them without
## diffing state itself — the same shape MatchState.update uses.
func advance_construction(dt: float) -> Array:
	var completed := []
	for i in range(_cell.size()):
		if _destroyed[i] == 1 or _progress[i] >= 1.0:
			continue
		var build_time: float = maxf(_defs[i].build_time, 0.001)
		_progress[i] = minf(_progress[i] + dt / build_time, 1.0)
		if _progress[i] >= 1.0:
			completed.append(i)
			_dirty[i] = true
	return completed


## How finely a SURVIVING building's health replicates, as steps of full
## health.
##
## Health has to be quantised for the same reason construction progress is
## not streamed at all (D-003): a besieged building takes damage every
## attack cooldown, and marking each scratch dirty would resend its whole
## entry several times a second per attacker — the per-tick snapshot this
## project exists to avoid. A 32nd of full health is finer than the bar
## drawn on screen resolves, and it bounds a building's entire life to at
## most 32 health messages plus one for its death.
const HEALTH_REPLICATION_STEPS := 32.0


## Apply damage. Returns true if this call destroyed the building.
##
## An unfinished building takes damage the same way a finished one does —
## a half-built tower is a real thing standing on the map, not a plan.
##
## SURVIVING damage marks the building dirty too, not only fatal damage.
## It did not, and the effect on screen was that a building's health was
## replicated exactly twice — 100% when first revealed, and never again
## until it vanished. A player watching their town centre being torn down
## saw a full green bar until the moment it was rubble, so there was no
## way to tell a raid from a rout, or to know a building needed help while
## helping it was still possible. `take_dirty`'s own doc comment has said
## "completion, destruction, damage" since it was written; damage was the
## one of the three that never happened.
func damage(building: int, amount: float) -> bool:
	if _destroyed[building] == 1:
		return false
	var before := _health[building]
	_health[building] = maxf(before - amount, 0.0)
	if _health[building] > 0.0:
		var full := maxf(_defs[building].max_health, 0.001)
		if _health_step(before, full) != _health_step(_health[building], full):
			_dirty[building] = true
		return false
	_destroyed[building] = 1
	_dirty[building] = true
	return true


## Which replication step a health value falls in. Its own function so the
## two calls in `damage` cannot drift apart.
func _health_step(health: float, full: float) -> int:
	return int(floor(clampf(health / full, 0.0, 1.0) * HEALTH_REPLICATION_STEPS))


func living_building_count(player: int) -> int:
	var n := 0
	for i in range(_cell.size()):
		if _owner[i] == player and _destroyed[i] == 0:
			n += 1
	return n


## Ids a player still has standing. Elimination (D-033) will need this
## once buildings can produce: a player with no squads but a live barracks
## is not yet beaten.
func ids_of(player: int) -> Array:
	var out := []
	for i in range(_cell.size()):
		if _owner[i] == player and _destroyed[i] == 0:
			out.append(i)
	return out


## Composition entries for the hash, in wire ids (D-029/D-030).
##
## Deliberately excludes health and construction progress, for exactly the
## reason `NetProtocol.composition_hash` excludes position: both vary
## continuously and a client legitimately lags a tick behind, so hashing
## them would report a desync for a system working as designed. What is
## hashed is what is delivered as discrete reliable facts — identity,
## owner, kind, and whether it is still standing.
func composition_entries(ids: Array) -> Array:
	var out := []
	for id in ids:
		if id < 0 or id >= _cell.size():
			continue
		out.append({
			"id": wire_id(id),
			"alive": 0 if _destroyed[id] == 1 else 1,
			"shape": String(_defs[id].id),
			"spacing": float(_owner[id]),
		})
	return out


func composition_hash(ids: Array) -> int:
	return NetProtocol.composition_hash(composition_entries(ids))


## Every shipped BuildingDef, sorted by id so iteration order is stable
## (the same reason UnitRoster.load_all sorts).
##
## Cached: the AI asks what it could build on a decision tick, and
## `by_id` above hits ResourceLoader every call. A directory walk inside
## a think loop is the shape of defect that cost a whole tick budget in
## D-043 — /buildings is read-only at runtime, so this is memoisation
## with no correctness cost.
static var _all_cache: Array[BuildingDef] = []


static func all_defs() -> Array[BuildingDef]:
	if not _all_cache.is_empty():
		return _all_cache

	var out: Array[BuildingDef] = []
	var dir := DirAccess.open("res://buildings")
	if dir == null:
		push_error("BuildingSim: res://buildings is missing or unreadable")
		return out

	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()

	for name in names:
		var def := load("res://buildings/%s" % name) as BuildingDef
		if def != null:
			out.append(def)
	_all_cache = out
	return out
