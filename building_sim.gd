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

# Ids whose replicated state changed and have not been sent yet.
var _dirty := {}

# building -> Array of { "def_id": StringName, "remaining": float }
var _queues := {}

# Which squad founded each building, or -1. Parallel to the rest.
var _builder := PackedInt32Array()


func _init(p_space: TorusSpace = null) -> void:
	space = p_space if p_space != null else TorusSpace.new()


func building_count() -> int:
	return _cell.size()


## Local id (the array index). Use wire_id() for anything that leaves this
## class and might meet a squad id.
## `builder` is the squad that founded this, or -1. Recorded because
## founders are CONSUMED by the town they found (D-031): the founding
## party becomes the settlement rather than wandering off from it.
func add_building(def: BuildingDef, owner: int, at: Vector2i, complete := false,
		builder: int = -1) -> int:
	var id := _cell.size()
	_builder.append(builder)
	_cell.append(space.index(at))
	_owner.append(owner)
	_defs.append(def)
	_health.append(def.max_health)
	_progress.append(1.0 if complete else 0.0)
	_destroyed.append(0)
	_last_attack_tick.append(-1)
	return id


## The squad that founded this building, or -1. Consumed on completion.
func builder_of(building: int) -> int:
	return _builder[building]


func last_attack_tick_of(building: int) -> int:
	return _last_attack_tick[building]


func set_last_attack_tick(building: int, tick: int) -> void:
	_last_attack_tick[building] = tick


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
func enqueue(building: int, def: UnitDef) -> void:
	if not _queues.has(building):
		_queues[building] = []
	(_queues[building] as Array).append({
		"def_id": def.id, "remaining": maxf(def.build_time, 0.001),
	})


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
		out.append({
			"id": wire_id(id),
			"def_id": String(_defs[id].id),
			"owner": _owner[id],
			"cell": _cell[id],
			"progress": _progress[id],
			"destroyed": _destroyed[id] == 1,
		})
	return out


## Ids whose replicated state changed since the last call, and clears the
## list. Only completion and destruction qualify — the two things a client
## must be told about, one of which is in the hash.
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


## Apply damage. Returns true if this call destroyed the building.
##
## An unfinished building takes damage the same way a finished one does —
## a half-built tower is a real thing standing on the map, not a plan.
func damage(building: int, amount: float) -> bool:
	if _destroyed[building] == 1:
		return false
	_health[building] = maxf(_health[building] - amount, 0.0)
	if _health[building] > 0.0:
		return false
	_destroyed[building] = 1
	_dirty[building] = true
	return true


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
