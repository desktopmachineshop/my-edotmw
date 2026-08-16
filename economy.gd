extends RefCounted
class_name Economy

## The gathering economy (D-028): biome-derived depleting nodes, private
## wallets, and round-trip hauling by GATHERER SQUADS.
##
## ## Why squads gather, and why that matters
##
## A full gathering economy would normally collide head-on with D-005,
## which forbids per-unit pathfinding and per-unit production queues,
## because villagers are per-unit entities. Modelling a worker crew as **a
## squad with a job** dissolves that: one curve, one flow-field path, one
## network entity, output scaling with `alive` so casualties cut income
## naturally, and fog gating for free. D-005 is affirmed here, not
## excepted.
##
## ## Where the state lives
##
## Node stock and wallets are dictionaries rather than packed arrays.
## D-009's packed-array rule is about the ~1,000-squad hot set; nodes are
## sparse (a fraction of cells) and wallets are per PLAYER, so neither is
## on the path that rule exists to protect. Per-squad haul state is keyed
## by squad id for the same reason — only gatherer squads have any.

enum ResourceKind { FOOD, WOOD, GOLD, STONE }
const RESOURCE_COUNT := 4

## Phases of the haul cycle (D-028's round trip).
enum Phase { TO_NODE, GATHERING, TO_DROP_OFF }

## Stock in one TREE (a wood or food node). Sized so a single shipped
## gatherer squad (5 alive x 0.35/s = 1.75/s) works a tree out in about a
## minute — trees are many and individually small now, so a forest is
## consumed tree by tree, visibly, rather than one marker quietly ticking
## down for half an hour. Change the shipped gatherer numbers and this
## must move with them; test_economy pins the relationship.
const TREE_STOCK := 105

## Stock in a gold or stone node. These stay few and rich — an ore seam is
## a place you go to and hold (the D-039 reasoning), not scenery, and a
## one-minute gold node would trivialise the map's contested spots.
const RICH_STOCK := 2400

## How far a crew looks for the next tree of the same kind when the one it
## was working runs out. Covers a forest's internal gaps without silently
## marching workers across the map to ground the player never chose.
const RETARGET_RADIUS := 8

var space: TorusSpace

# cell index -> { "kind": Resource, "remaining": int }
var nodes := {}

# player -> PackedInt32Array of RESOURCE_COUNT totals
var wallets := {}

# squad id -> { "node": int (cell index), "phase": Phase, "carrying": int,
#               "kind": Resource }
var _hauls := {}

## Cells whose node ran dry since the last drain — the server turns these
## into wire events so clients can fell the tree they drew there. Appended
## the moment `remaining` hits zero, drained with `take_depleted()`;
## nothing in the simulation reads it back.
var _depleted := []


func _init(p_space: TorusSpace = null) -> void:
	space = p_space if p_space != null else TorusSpace.new()


## Build the node field from terrain (D-037).
##
## Placement is derived, not authored, and deterministic: the same seed
## gives the same nodes, so replays reproduce an economy exactly.
##
## ## Trees are a density field now, not a stride
##
## The old version sampled every Nth cell and let biome pick the kind,
## which made resources a uniform sprinkle — a forest held exactly as many
## wood nodes per acre as a prairie held food. Now each biome rolls its
## own densities, shaped by the SAME moisture field the biome
## classification reads: a forest's wet heart is near-solid trees, its dry
## edge thins out, grassland carries scattered groves that thicken toward
## the forest line, dry country keeps a few hardy trees, and a beach gets
## the odd palm. The result is dense woods, ragged treelines and lone
## trees, all from one noise field nothing here had to invent.
##
## Gold stays a rare find in dry country. Stone moves to the mountain FOOT
## — the old version put it on MOUNTAIN/PEAK cells, which passability()
## marks unwalkable, so every naturally placed stone node was scenery a
## crew would march at and stall against forever (the AI grew a whole
## give-up mechanism against exactly these). A foot cell is walkable by
## construction.
##
## The per-cell roll hashes the QUADRANT-LOCAL position, not the absolute
## index, for the reason the stride version learned the hard way: symmetric
## terrain is not enough on its own, and deriving the roll from the local
## position makes the field inherit the map's symmetry by construction
## (D-036).
func generate(terrain: TerrainGen, symmetry_order: int = 1) -> void:
	nodes.clear()

	var repeats := maxi(1, symmetry_order)
	var quadrant_width := maxi(1, space.width / repeats)
	var quadrant_height := maxi(1, space.height / repeats)

	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var local := (coord.x % quadrant_width) + (coord.y % quadrant_height) * quadrant_width
		var roll := _roll(terrain.noise_seed, local)

		var kind := _roll_kind(terrain, coord, roll)
		if kind < 0:
			continue
		nodes[index] = {"kind": kind, "remaining": stock_for(kind)}


## What (if anything) grows on this cell, given one deterministic roll in
## [0, 1). Densities are cumulative within a branch: a cell that misses its
## first chance falls through to the next band of the same roll, so one
## roll decides everything and the bands cannot overlap.
func _roll_kind(terrain: TerrainGen, coord: Vector2i, roll: float) -> int:
	var biome := terrain.biome_at(space, coord)

	# Mountain-foot stone first: it outranks the ground biome's own table,
	# because a foot cell IS a grassland/dry/forest cell — that is what
	# makes it walkable — and stone has nowhere else to live.
	if biome != TerrainGen.Biome.MOUNTAIN and biome != TerrainGen.Biome.PEAK \
			and biome != TerrainGen.Biome.WATER and biome != TerrainGen.Biome.DEEP_WATER:
		if _touches_mountain(terrain, coord) and roll < 0.25:
			return ResourceKind.STONE

	match biome:
		TerrainGen.Biome.FOREST:
			# Wet heart near-solid, dry edge thinned: density rides the
			# same moisture that classified the cell as forest at all.
			var f := clampf((terrain.moisture_at(space, coord) - TerrainGen.MOISTURE_FOREST)
				/ (1.0 - TerrainGen.MOISTURE_FOREST), 0.0, 1.0)
			if roll < lerpf(0.65, 0.98, f):
				return ResourceKind.WOOD
		TerrainGen.Biome.GRASSLAND:
			# Groves thicken toward the forest line (m -> MOISTURE_FOREST),
			# orchards sit in the mid-moisture band where neither extreme
			# claims the ground.
			var g := clampf((terrain.moisture_at(space, coord) - TerrainGen.MOISTURE_DRY)
				/ (TerrainGen.MOISTURE_FOREST - TerrainGen.MOISTURE_DRY), 0.0, 1.0)
			var wood := 0.05 + 0.22 * g * g
			var food := 0.05 + 0.16 * (1.0 - absf(g - 0.5) * 2.0)
			if roll < wood:
				return ResourceKind.WOOD
			if roll < wood + food:
				return ResourceKind.FOOD
		TerrainGen.Biome.DRY_GRASSLAND:
			if roll < 0.10:
				return ResourceKind.WOOD
			if roll < 0.10 + 0.017:
				return ResourceKind.GOLD
		TerrainGen.Biome.BEACH:
			if roll < 0.10:
				return ResourceKind.WOOD
	return -1


## Does this cell border the mountains? Neighbours only — stone reads as
## sitting AT the rock face, and one ring keeps it as rare as the terrain's
## mountain perimeter.
func _touches_mountain(terrain: TerrainGen, coord: Vector2i) -> bool:
	for neighbour in space.neighbors(coord):
		var b := terrain.biome_at(space, neighbour)
		if b == TerrainGen.Biome.MOUNTAIN or b == TerrainGen.Biome.PEAK:
			return true
	return false


## Starting stock by kind: trees small and quick, ore rich and held.
static func stock_for(kind: int) -> int:
	if kind == ResourceKind.WOOD or kind == ResourceKind.FOOD:
		return TREE_STOCK
	return RICH_STOCK


## Deterministic roll in [0, 1) from (seed, cell). Combat._roll_unit's
## FNV-style mixing, and for the same reason: integer ops only, so it is
## bit-identical on every machine, and no single multiply can overflow a
## 64-bit int (D-024's determinism argument).
const _FNV_OFFSET_BASIS := 0x811C9DC5
const _FNV_PRIME := 0x01000193


static func _roll(seed_value: int, cell_local: int) -> float:
	var h := _FNV_OFFSET_BASIS
	h = ((h ^ (seed_value & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (cell_local & 0xFFFFFFFF)) * _FNV_PRIME) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * _FNV_PRIME) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / float(0x1000000)


## Make the starts approximately fair on an ASYMMETRIC map (D-036,
## revised). Quadrant symmetry made fairness exact and the map boring;
## random terrain makes it interesting and unfair. This is the middle
## course: generate freely, then guarantee every spawn a minimum quota of
## each resource within reach.
##
## Where a quota is short, a node is placed on the nearest passable cell
## regardless of biome. That deliberately overrides biome derivation — a
## player with no forest in reach still needs wood, and "fair" beats
## "geologically tidy" when the alternative is losing at map-generation
## time. Deterministic: it walks cells in index order, so replays and both
## sides of the wire agree.
func balance_for_spawns(spawns: Array, passable: PackedByteArray,
		radius: int, quota: int) -> void:
	for spawn in spawns:
		# REACHABLE cells, not merely nearby ones.
		#
		# This used to count and place on anything passable inside the
		# radius, which on a map with water is not the same thing: a spawn
		# behind a channel got its guaranteed resources on the far bank.
		# One AI seat in a 700 s ladder match gathered NOTHING — food and
		# wood still at their starting 220 each — while running 13 worker
		# crews and giving up on 43 nodes it could not walk to. Its
		# guarantee had been satisfied on the other side of the water.
		#
		# Same defect as the AI's own `_nearest_node_of_kind`: distance
		# mistaken for reachability. Fixed here as well as there, because
		# a node nobody can reach is not a resource, it is scenery.
		var walkable := _reachable_from(spawn, passable, radius)
		for kind in range(RESOURCE_COUNT):
			var found := 0
			for index in walkable:
				if nodes.has(index) and int(nodes[index]["kind"]) == kind:
					found += 1
			if found >= quota:
				continue

			# Short: top up on the nearest free ground the spawn can WALK
			# to. `walkable` is already in flood-fill order, which is
			# nearest-first, and already excludes water and the far bank.
			for index in walkable:
				if found >= quota:
					break
				if nodes.has(index):
					continue
				if space.distance(spawn, space.from_index(index)) < 2:
					continue  # leave room for the town hall itself
				nodes[index] = {"kind": kind, "remaining": stock_for(kind)}
				found += 1


## Cells within `radius` of `from` that a squad can actually WALK to,
## nearest first.
##
## A flood fill rather than a disk, because passability is not the same as
## reachability: a cell across a channel is close and unreachable, and
## treating the two as equivalent is what put one spawn's guaranteed
## resources on the far bank of a river.
##
## Bounded by radius so this stays cheap — it runs once per spawn at map
## generation, never per tick. Deterministic: cells are enqueued in
## `TorusSpace.neighbors` order, so replays and both sides of the wire
## agree about where resources ended up.
func _reachable_from(from: Vector2i, passable: PackedByteArray, radius: int) -> Array:
	var start := space.index(from)
	var seen := {start: true}
	var queue := [from]
	var out := [start]
	var head := 0

	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for neighbour in space.neighbors(cell):
			var index := space.index(neighbour)
			if seen.has(index):
				continue
			if space.distance(from, neighbour) > radius:
				continue
			if index < passable.size() and passable[index] == 0:
				continue
			seen[index] = true
			queue.append(neighbour)
			out.append(index)
	return out


## Node positions and kinds for the wire, without their stock.
##
## `only` restricts the result to specific cells — the caller passes the
## ones a given player has actually seen (D-061). Called with no argument
## this returns EVERY node, which is exactly the leak that made it
## necessary: knowing where every resource sits from the moment you join
## tells you where an opponent must expand and where to raid, without
## scouting for any of it.
func node_entries(only: Array = []) -> Array:
	if not only.is_empty():
		var picked := []
		for cell in only:
			if nodes.has(cell):
				picked.append({"cell": cell, "kind": int(nodes[cell]["kind"])})
		return picked
	return _all_node_entries()


func _all_node_entries() -> Array:
	var out := []
	for cell in nodes:
		out.append({"cell": cell, "kind": int(nodes[cell]["kind"])})
	return out


func node_count() -> int:
	return nodes.size()


func has_node(cell_index: int) -> bool:
	return nodes.has(cell_index) and int(nodes[cell_index]["remaining"]) > 0


func remaining_at(cell_index: int) -> int:
	return int(nodes[cell_index]["remaining"]) if nodes.has(cell_index) else 0


func kind_at(cell_index: int) -> int:
	return int(nodes[cell_index]["kind"]) if nodes.has(cell_index) else -1


## Wallets are PRIVATE (D-028): replicated to their owner and nobody else.
## Knowing an opponent's stockpile tells you what they are about to field,
## which is the same class of knowledge D-003's horizon clipping and
## D-004's fog exist to withhold.
func wallet_of(player: int) -> PackedInt32Array:
	if not wallets.has(player):
		var fresh := PackedInt32Array()
		fresh.resize(RESOURCE_COUNT)
		wallets[player] = fresh
	return wallets[player]


func amount(player: int, kind: int) -> int:
	return wallet_of(player)[kind]


func credit(player: int, kind: int, quantity: int) -> void:
	var wallet := wallet_of(player)
	wallet[kind] += quantity
	wallets[player] = wallet


## Can `player` afford this cost table, and if so, spend it. Returns false
## and spends nothing when they cannot — production has to be all or
## nothing, or a player ends up with a half-paid barracks.
func try_spend(player: int, food: int, wood: int, gold: int, stone: int) -> bool:
	var wallet := wallet_of(player)
	var cost := [food, wood, gold, stone]
	for kind in range(RESOURCE_COUNT):
		if wallet[kind] < cost[kind]:
			return false
	for kind in range(RESOURCE_COUNT):
		wallet[kind] -= cost[kind]
	wallets[player] = wallet
	return true


## Order a squad to work a node. Returns false if the squad cannot gather
## or the cell holds nothing.
func order_gather(sim: SquadSim, squad: int, cell_index: int) -> bool:
	var def := sim.def_of(squad)
	if def == null or def.carry_capacity <= 0:
		return false
	if not has_node(cell_index):
		return false
	_hauls[squad] = {
		"node": cell_index,
		"phase": Phase.TO_NODE,
		"carrying": 0,
		"kind": kind_at(cell_index),
	}
	sim.force_move(squad, space.from_index(cell_index))
	return true


func is_gathering(squad: int) -> bool:
	return _hauls.has(squad)


func carrying(squad: int) -> int:
	return int(_hauls[squad]["carrying"]) if _hauls.has(squad) else 0


func phase_of(squad: int) -> int:
	return int(_hauls[squad]["phase"]) if _hauls.has(squad) else -1


## Advance every haul one tick. Returns the players whose wallets changed,
## so the caller replicates only those.
##
## The cycle is deliberately explicit rather than emergent: march to the
## node, gather until full, march to the nearest drop-off, unload, repeat.
## Every leg is an ordinary squad move order, so it uses the same flow
## fields, the same curves and the same replication as any other movement
## (D-005, D-003) — an economy squad is a squad with a job, not a new kind
## of thing that moves differently.
func tick(sim: SquadSim, buildings: BuildingSim, dt: float) -> Array:
	var changed := {}

	for squad in _hauls.keys():
		if squad >= sim.squad_count() or sim.alive_of(squad) <= 0:
			_hauls.erase(squad)
			continue

		var haul: Dictionary = _hauls[squad]
		var def := sim.def_of(squad)
		if def == null:
			continue

		match int(haul["phase"]):
			Phase.TO_NODE:
				# Another crew may have finished the tree while this one was
				# still walking to it — retarget en route rather than letting
				# the crew arrive at a stump and stand there.
				if not has_node(int(haul["node"])):
					if not _retarget(sim, squad, haul):
						_hauls.erase(squad)
						continue
				elif sim.cell_index_of(squad) == int(haul["node"]):
					haul["phase"] = Phase.GATHERING
			Phase.GATHERING:
				_gather(sim, squad, haul, def, dt, buildings)
			Phase.TO_DROP_OFF:
				_try_unload(sim, squad, haul, buildings, changed)

		# A crew standing at a node works AROUND it; a crew on the road
		# walks spread out (D-058). Suggested every tick rather than on the
		# transition, because `suggest_shape` ignores a no-op — so this
		# costs nothing on the ticks where nothing changed, and cannot be
		# left wrong by a phase change that took some other path out.
		# A released crew goes back to walking order too — a worked-out
		# node erases the haul, and leaving them ringed around a bare patch
		# would be the one case this misses.
		#
		# SUGGEST, not set: a player who has chosen this crew's formation
		# outranks the automatic switch. Asserting it here every tick is
		# exactly what made the formation buttons look inert on workers.
		var working := _hauls.has(squad) and int(haul["phase"]) == Phase.GATHERING
		sim.suggest_shape(squad, "ring" if working else "sparse")

		# Only write back a haul that still exists. A helper above may have
		# ended it — a worked-out node releases its crew — and assigning
		# unconditionally here would resurrect the entry it had just
		# erased, leaving the squad parked on an empty patch forever.
		if _hauls.has(squad):
			_hauls[squad] = haul

	return changed.keys()


func _gather(sim: SquadSim, squad: int, haul: Dictionary, def: UnitDef,
		dt: float, buildings: BuildingSim) -> void:
	var cell := int(haul["node"])
	if not has_node(cell):
		# Worked out. With trees a minute deep a crew retires one every
		# haul cycle or so, and making the player re-issue the same order
		# per tree would be pure micro tax — so the crew walks itself to
		# the nearest still-standing node of the SAME kind nearby. Same
		# kind, because "chop wood" silently becoming "pick apples" is the
		# substitution bug the AI already had to have fixed
		# (_nearest_node_of_kind's header). Nothing nearby releases the
		# crew, exactly as before; the player picks somewhere new.
		if not _retarget(sim, squad, haul):
			_hauls.erase(squad)
		return

	# Output scales with the crew that is actually left (D-028). This is
	# the whole reason gatherers are squads: casualties cut income without
	# any special case.
	# Fractional progress CARRIES, exactly as combat carries fractional
	# damage. Rounding each tick's take up instead made a half-strength
	# crew gather the same as a full one — both produced "less than one
	# unit this tick", and ceil turned both into one.
	var rate := def.gather_rate * float(sim.alive_of(squad)) * dt
	haul["fraction"] = float(haul.get("fraction", 0.0)) + rate
	var whole := int(floor(float(haul["fraction"])))
	if whole <= 0:
		return
	haul["fraction"] = float(haul["fraction"]) - float(whole)

	var taken := mini(whole, remaining_at(cell))
	taken = mini(taken, def.carry_capacity - int(haul["carrying"]))
	if taken <= 0:
		return

	nodes[cell]["remaining"] = remaining_at(cell) - taken
	haul["carrying"] = int(haul["carrying"]) + taken
	if remaining_at(cell) <= 0:
		# The tree comes down. The entry stays in `nodes` (a depleted cell
		# is still not a place to start another node) — this list is how
		# the server learns to tell clients about the felling.
		_depleted.append(cell)

	if int(haul["carrying"]) >= def.carry_capacity:
		var drop_off := _nearest_drop_off(sim, buildings, sim.owner_of(squad),
			sim.cell_of(squad))
		if drop_off.x < 0:
			return  # nowhere to take it; keep standing on the node
		haul["phase"] = Phase.TO_DROP_OFF
		sim.force_move(squad, drop_off)


func _try_unload(sim: SquadSim, squad: int, haul: Dictionary,
		buildings: BuildingSim, changed: Dictionary) -> void:
	var here := sim.cell_of(squad)
	var drop_off := _nearest_drop_off(sim, buildings, sim.owner_of(squad), here)
	if drop_off.x < 0:
		return
	if space.distance(here, drop_off) > 1:
		return

	var player := sim.owner_of(squad)
	credit(player, int(haul["kind"]), int(haul["carrying"]))
	changed[player] = true
	haul["carrying"] = 0

	# Straight back out to the node, if there is anything left in it —
	# or to the nearest surviving tree of the same kind if not.
	if has_node(int(haul["node"])):
		haul["phase"] = Phase.TO_NODE
		sim.force_move(squad, space.from_index(int(haul["node"])))
	elif not _retarget(sim, squad, haul):
		_hauls.erase(squad)


## Point a crew whose tree ran out at the nearest surviving node of the
## same kind within RETARGET_RADIUS. Returns false if none stands.
##
## Searches outward from the WORKED NODE, not from the squad — the crew
## may be at the drop-off when the decision is made, and "nearest to the
## depot" would slowly walk the whole operation home. `disk_offsets` is
## sorted nearest-first (D-067 made that true for exactly this walk-
## outward pattern), and the search is deterministic, so server and
## replay agree on where every crew goes next.
func _retarget(sim: SquadSim, squad: int, haul: Dictionary) -> bool:
	var from := space.from_index(int(haul["node"]))
	var kind := int(haul["kind"])
	for offset in TorusSpace.disk_offsets(RETARGET_RADIUS):
		var cell := space.index(from + offset)
		if has_node(cell) and kind_at(cell) == kind:
			haul["node"] = cell
			haul["phase"] = Phase.TO_NODE
			sim.force_move(squad, space.from_index(cell))
			return true
	return false


## Nodes that ran dry since the last call, for the wire. Draining hands
## ownership to the caller — the server encodes them once and the list
## must not replay next tick.
func take_depleted() -> Array:
	var out := _depleted
	_depleted = []
	return out


## Nearest completed drop-off building this player owns, or (-1, -1).
func _nearest_drop_off(sim: SquadSim, buildings: BuildingSim, player: int,
		from: Vector2i) -> Vector2i:
	if buildings == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for i in range(buildings.building_count()):
		if buildings.owner_of(i) != player or not buildings.is_complete(i):
			continue
		var def := buildings.def_of(i)
		if def == null or not def.is_drop_off:
			continue
		var cell := buildings.cell_of(i)
		var d := space.distance(from, cell)
		if d < best_distance:
			best_distance = d
			best = cell
	return best
