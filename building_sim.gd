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
## Seconds this building takes to raise, for ITS owner's civ (#270).
## Banked at placement rather than read off the def per tick, so the
## progress a client draws and the progress the server keeps agree.
var _build_time := PackedFloat32Array()
var _last_attack_tick := PackedInt32Array()  # -1 = never fired

## Player-assigned focus-fire target (a squad id), or -1 for "automatic —
## nearest enemy in range" (Combat._find_squad_near's default). Set by
## C2S_ORDER_BUILDING_TARGET; cleared automatically when the target dies
## (Combat.resolve_buildings). Server-only — not replicated, since only the
## owner can set it and nothing downstream needs to know a target is manual
## versus automatic, only who it currently is.
var _forced_target := PackedInt32Array()

# --- continuous placement (D-096) -------------------------------------
#
# `_cell` above stays the ANCHOR — the cell this structure's centre falls
# in — because everything that buckets by cell (combat targeting, vision
# stamping, the minimap, selection) is unchanged and must stay that way.
# These two carry the rest of the pose: a sub-cell displacement in WORLD
# units, and a continuous rotation in radians. True position is
# `space.to_world(cell) + offset`, which `world_position_of` is the one
# definition of.
#
# A wall's effect on the simulation is DERIVED from that pose by
# `span_cells` rather than being `_cell` alone — see D-096 on why deriving
# it is what stops a wall looking solid while having a hole in it.
var _offset_x := PackedFloat32Array()
var _offset_z := PackedFloat32Array()
var _angle := PackedFloat32Array()

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
## Matches any cell the building's BODY covers as of D-096, not only its
## anchor — otherwise a wall laid across three cells could be built over on
## two of them, and a click on its visible end would find nothing there.
func building_at(cell: Vector2i) -> int:
	var index := space.index(cell)
	for i in range(_cell.size()):
		if _destroyed[i] == 0 and span_cells(i).has(index):
			return i
	return -1


## Cells that living buildings stand on, for the simulation's passability
## (D-007). A squad should walk AROUND a town hall, not through it.
##
## Every cell a body COVERS as of D-096, not just its anchor cell — a wall
## laid at an angle across three cells occupies all three.
func occupied_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(_cell.size()):
		if _destroyed[i] == 0:
			out.append_array(span_cells(i))
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
## `builder` is the squad that founded this, or -1. Recorded because a
## def may CONSUME its builder (`BuildingDef.consumes_builder`,
## D-20260823-the-opening-is-a-crew-and-a-general): the crew that founds
## a town becomes the settlement rather than wandering off from it.
## `facing` means one of two things depending on `def`, decided here rather
## than trusted from the caller.
##
## For the ACCESS TOWER it stays one of `TorusSpace.DIRECTIONS`' 6 sides
## (wrapped into 0..5): its door has to open onto an actual neighbouring
## cell a squad can stand in (`door_cell_of` calls `space.neighbor_index`),
## so a continuous angle would have nothing to point at.
##
## For everything else — the rest of the wall family included, as of D-096
## — it is a continuous byte (0-255, `PlacementJitter.yaw_byte` /
## `radians_of_byte`). Walls used to wrap to 0..5 here alongside the tower,
## which is precisely what locked a wall run to six angles; D-096 unpicks
## that, and `_angle` below is the radians it decodes to.
##
## `offset` is the sub-cell displacement in WORLD units (D-096) — where
## inside `at` this structure actually stands. Zero means dead centre,
## which is what every non-wall building and every existing caller gets.
## `build_time` is how long the OWNER'S CIV takes to raise this, resolved
## by the caller (`CivDef.construction_time`, D-047) exactly as `enqueue`
## already takes its production time -- and stored as REAL SECONDS for
## the same reason: construction progress is replicated, and a multiplier
## applied per tick would make the bar a client draws disagree with the
## server. Negative means "the def's own time", which is every caller
## that has no civ to ask.
func add_building(def: BuildingDef, owner: int, at: Vector2i, complete := false,
		builder: int = -1, facing: int = 0, offset: Vector2 = Vector2.ZERO,
		build_time: float = -1.0) -> int:
	var id := _cell.size()
	_build_time.append(maxf(build_time if build_time >= 0.0 else def.build_time, 0.001))
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
	var wraps_to_hex_direction := def.is_access_tower
	_facing.append(posmod(facing, 6) if wraps_to_hex_direction else posmod(facing, 256))
	_angle.append(_angle_from_facing(def, _facing[id]))
	_offset_x.append(offset.x)
	_offset_z.append(offset.y)
	return id


## Radians for a stored `facing`, per the two meanings documented on
## `add_building`. The one place the byte-vs-hex-direction split is turned
## into an actual angle, so a caller can never pick the wrong divisor.
static func _angle_from_facing(def: BuildingDef, facing: int) -> float:
	if def.is_access_tower:
		return float(posmod(facing, 6)) * TAU / 6.0
	return float(posmod(facing, 256)) * TAU / 256.0


## Continuous rotation in radians. With this as `rotation.y`, the mesh's
## local +X (its long axis, for a wall segment) points along
## `(cos, 0, -sin)` — the convention `client.gd`'s `_angle_of_offset`
## established and `span_cells` below depends on.
func angle_of(building: int) -> float:
	return _angle[building] if building >= 0 and building < _angle.size() else 0.0


## Sub-cell displacement in world units (D-096).
func offset_of(building: int) -> Vector2:
	if building < 0 or building >= _offset_x.size():
		return Vector2.ZERO
	return Vector2(_offset_x[building], _offset_z[building])


## Where this building actually stands, as opposed to which cell it is
## filed under. THE definition — anything drawing, aiming at, or measuring
## against a building should come through here rather than re-deriving it
## from `cell_of` and getting the pre-D-096 answer.
func world_position_of(building: int) -> Vector3:
	if building < 0 or building >= _cell.size():
		return Vector3.ZERO
	var base := space.to_world(space.from_index(_cell[building]))
	return base + Vector3(_offset_x[building], 0.0, _offset_z[building])


## Every cell this building's body actually covers (D-096).
##
## For anything but a wall-family segment this is just its own cell — a
## town hall has never spanned more than one, and `footprint_radius` is a
## separate no-build claim rather than a body.
##
## For a wall segment it is the cells its CENTRELINE passes through,
## sampled along the segment's own long axis. That is what makes a wall
## drawn at an arbitrary angle block every cell it visibly crosses instead
## of only the one its midpoint happens to land in — the walk-through-a-
## solid-wall failure D-096 exists to prevent.
##
## Sampled rather than solved analytically: the step below is well under a
## hex's flat-to-flat width, so no cell along the line can be stepped over,
## and a handful of `world_to_cell` calls per segment is far cheaper than
## the polygon clip the exact version would need. Walls are placed rarely
## and this is not on the tick path — `server._refresh_passability` calls
## it when something is built or destroyed, not every frame.
func span_cells(building: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if building < 0 or building >= _cell.size():
		return out
	var def := _defs[building]
	# The ACCESS TOWER is deliberately excluded even though it is
	# footprint_radius 0. It is a point structure with a door, not a linear
	# one: `door_cell_of` puts the climb point on a NEIGHBOURING cell, so a
	# tower that spanned two cells would swallow its own door and a squad
	# could never descend. Its mesh is also roughly square (2.6 x 2.6), so
	# sampling "along its long axis" as if it were a wall was meaningless
	# in the first place. Caught by test_wall_top's descend test.
	if def.footprint_radius != 0 or def.is_access_tower or def.mesh_size == Vector3.ZERO:
		out.append(_cell[building])
		return out

	var angle := _angle[building]
	var direction := Vector3(cos(angle), 0.0, -sin(angle))
	var half_length := def.mesh_size.x * 0.5
	var anchor := space.from_index(_cell[building])
	var sub_cell := Vector3(_offset_x[building], 0.0, _offset_z[building])

	# Distance from each nearby cell's CENTRE to the segment, rather than
	# walking the segment and asking which cell each step lands in.
	#
	# The walk was the first attempt and it was wrong in a way worth
	# recording: a step small enough to never skip a cell does not exist.
	# A line can clip a hex CORNER in a sliver of any thickness, so any
	# fixed step misses some cell it genuinely crosses — the D-096 gap test
	# found 26 such cells on one diagonal run. Sampling can only ever be
	# approximately right here; a distance test is exactly right.
	#
	# The threshold is the hex CIRCUMRADIUS, and that specific choice is
	# what makes gaps impossible: if the segment touches a hex at all then
	# some point of that hex lies on the segment, and no point of a hex is
	# further than the circumradius from its own centre — so the centre is
	# necessarily within that distance of the segment. Erring outward is
	# also the safe direction: over-blocking by a sliver is invisible,
	# while under-blocking is a hole an army walks through.
	#
	# `disk_offsets` rather than `distance()` per candidate, per the
	# standing rule this project has re-learned four times (vision, combat,
	# UnitRoster, terrain noise). It is sorted nearest-first (D-067), which
	# this does not need but does not mind.
	var reach := half_length + space.hex_size
	var radius := ceili(reach / (space.hex_size * TorusSpace.SQRT_3)) + 1
	for offset in TorusSpace.disk_offsets(radius):
		var cell := space.normalize(anchor + offset)
		# Wrap-aware by construction: `world_delta` takes the short way
		# round, and the sub-cell offset shifts the segment's true centre
		# off the anchor's own centre.
		var to_cell := space.world_delta(anchor, cell) - sub_cell
		var along := clampf(to_cell.dot(direction), -half_length, half_length)
		if (to_cell - direction * along).length() <= space.hex_size:
			out.append(space.index(cell))
	return out


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
## As of D-096 this returns every cell a segment's body crosses, not just
## its anchor — the whole point of continuous placement is that a wall
## drawn at an angle stops the squad it visibly stands in front of.
func blocking_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(_cell.size()):
		if _destroyed[i] == 1:
			continue
		if _defs[i].is_gate and _gate_open[i] == 1:
			continue
		if _defs[i].footprint_radius == 0 and _progress[i] < 1.0:
			continue
		out.append_array(span_cells(i))
	return out


## Cells belonging to a complete, living, `walkable_top` building — the
## tier-1 (wall-top) passable network (D-076). A destroyed or still-under-
## construction structure contributes nothing: you cannot stand on rubble
## or scaffolding.
func walkable_top_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(_cell.size()):
		if _destroyed[i] == 0 and _progress[i] >= 1.0 and _defs[i].walkable_top:
			# Every cell the walkway actually runs over (D-096), so a
			# tier-1 route follows an angled wall instead of stopping at
			# whichever cell each segment is filed under.
			out.append_array(span_cells(i))
	return out


## Whether `cell` (a cell INDEX) is currently part of the tier-1 walkable
## network (D-076) — a single-cell check for order-time inference, where
## allocating the whole `walkable_top_cells()` array would be wasted work.
func is_walkable_top_cell(cell: int) -> bool:
	for i in range(_cell.size()):
		if _destroyed[i] == 0 and _progress[i] >= 1.0 and _defs[i].walkable_top \
				and span_cells(i).has(cell):
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
##
## `build_time` is the time the OWNER'S CIV takes, resolved by the caller
## (`CivDef.production_time`, D-047) exactly as the caller already
## resolves the archetype against that civ. Passed in rather than looked
## up here, and stored as REAL SECONDS rather than as a rate: the queue's
## head counts down at one second per second on the wire, and the client
## draws the countdown from it (D-003). A civ multiplier applied per tick
## instead would make every client's "— 12s" wrong for the fast civ.
func enqueue(building: int, def: UnitDef, instant: bool = false,
		build_time: float = -1.0) -> void:
	if build_time < 0.0:
		build_time = def.build_time
	if not _queues.has(building):
		_queues[building] = []
	(_queues[building] as Array).append({
		"def_id": def.id, "remaining": 0.001 if instant else maxf(build_time, 0.001),
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
			# The rest of the pose (D-096) — without this a client knows
			# which cell a wall is filed under but not where along it the
			# wall actually stands, and would draw every segment back at
			# its cell centre.
			"offset_x": _offset_x[id],
			"offset_z": _offset_z[id],
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


## May a squad of this ARCHETYPE construct `def`? (D-031's rule; the
## roster it gates changed in
## D-20260823-the-opening-is-a-crew-and-a-general.)
##
## The rule reads one way only, from `BuildingDef.built_by`, so there is a
## single source of truth. That is also what expresses "the general builds
## nothing": no def lists it, so every building refuses it without needing
## a second, builder-side list to be kept in step with this one.
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
		# The OWNER'S civ's time, banked when the site was placed (D-047).
		var build_time: float = _build_time[i]
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


## Raze everything `player` owns, returning the building ids razed.
##
## `SquadSim.eliminate_player`'s sibling, and it exists because that one
## on its own stopped being enough (#292, #318). D-033's rule is that a
## disconnect wipes the abandoned army and the ORDINARY defeat rule
## notices, so "defeated" keeps exactly one definition — and that rule
## became "no living squads AND no living buildings" when
## D-20260823-the-opening-is-a-crew-and-a-general added the buildings
## clause, for the unrelated and correct reason that a crew is consumed
## by the town hall it founds.
##
## Nothing failed. Both halves were right on their own; the wipe simply
## stopped wiping enough, and a quitter's undefended base kept them
## "standing" so the match could not be won. The same shape as D-065: a
## consequence that stopped being true when something underneath it
## moved.
##
## Razed through `damage()` rather than by setting `_destroyed`, so a
## client applies this exactly as it applies any other destruction —
## dirty flag, then `S2C_BUILDING_INFO`. A second message for "the owner
## left" would be a second thing to keep in step with the first, and
## D-030's ever-revealed set means every client that has ever SEEN the
## base needs telling, including ones that cannot see it now.
##
## Unfinished buildings go too: the elimination rule counts what is not
## destroyed, not what is complete, so a half-built hall left standing
## would keep its absent owner in the match just as a finished one does.
func eliminate_player(player: int) -> Array:
	var razed := []
	for i in range(_cell.size()):
		if _owner[i] == player and _destroyed[i] == 0:
			# INF rather than the current health: `damage` clamps at zero
			# and this must not depend on `_health` being read correctly
			# for a building that may never have finished construction.
			if damage(i, INF):
				razed.append(i)
	return razed


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
