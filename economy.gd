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

## One cell in this many becomes a node.
##
## This said "sparse on purpose" at 11 and was not sparse: measured on the
## shipped 84x96 map it produced 467 nodes across 8,064 cells — one per
## seventeen — which is the lawn the comment claimed to be avoiding.
##
## At 45 the same map gets about a hundred. Nodes become places you go to
## and hold rather than scenery you happen to be standing on, which is
## also what makes a hotspot worth fighting over (the same reasoning as
## D-039's scattered spawns).
const NODE_EVERY := 95

## Starting stock in a node, before `alive`-scaled gathering eats it.
##
## Raised in step with NODE_EVERY so the map's TOTAL resource is roughly
## unchanged — about 420k either way. Fewer, richer nodes is a different
## map, not a poorer one: the economy still supports the same army, it
## just concentrates where that army has to walk to get it. Cutting the
## count without this would have quietly starved every match.
const NODE_STOCK := 3600

var space: TorusSpace

# cell index -> { "kind": Resource, "remaining": int }
var nodes := {}

# player -> PackedInt32Array of RESOURCE_COUNT totals
var wallets := {}

# squad id -> { "node": int (cell index), "phase": Phase, "carrying": int,
#               "kind": Resource }
var _hauls := {}


func _init(p_space: TorusSpace = null) -> void:
	space = p_space if p_space != null else TorusSpace.new()


## Build the node field from terrain (D-037).
##
## Placement is derived, not authored, and deterministic: the same seed
## gives the same nodes, so replays reproduce an economy exactly. Because
## terrain is quadrant-symmetric (D-036), the node field inherits that
## symmetry for free — all four players get identical resources without
## anything here knowing about fairness.
func generate(terrain: TerrainGen, symmetry_order: int = 2) -> void:
	nodes.clear()

	# Which cells are candidates is decided from the QUADRANT-LOCAL
	# position, not the absolute cell index. Symmetric terrain is not
	# enough on its own: sampling every Nth absolute index picks a
	# different pattern in each quadrant unless N happens to divide the
	# quadrant stride, and the first version of this shipped 149
	# asymmetric nodes on a perfectly symmetric map. Deriving the sample
	# from the local position makes the field inherit the map's symmetry
	# by construction, the same way the map inherits its own (D-036).
	var repeats := maxi(1, symmetry_order)
	var quadrant_width := maxi(1, space.width / repeats)
	var quadrant_height := maxi(1, space.height / repeats)

	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var local := (coord.x % quadrant_width) + (coord.y % quadrant_height) * quadrant_width
		if local % NODE_EVERY != 0:
			continue
		var kind := _kind_for(terrain.biome_at(space, coord))
		if kind < 0:
			continue
		nodes[index] = {"kind": kind, "remaining": NODE_STOCK}


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
		for kind in range(RESOURCE_COUNT):
			var found := 0
			for offset in TorusSpace.disk_offsets(radius):
				var index := space.index(spawn + offset)
				if nodes.has(index) and int(nodes[index]["kind"]) == kind:
					found += 1
			if found >= quota:
				continue

			# Short: top up on the nearest free, walkable ground.
			for offset in TorusSpace.disk_offsets(radius):
				if found >= quota:
					break
				var index := space.index(spawn + offset)
				if nodes.has(index):
					continue
				if index < passable.size() and passable[index] == 0:
					continue
				if space.distance(spawn, space.from_index(index)) < 2:
					continue  # leave room for the town hall itself
				nodes[index] = {"kind": kind, "remaining": NODE_STOCK}
				found += 1


## Biome to resource. Water and beach yield nothing — you cannot chop a
## lake — which is also what keeps nodes off the cells squads cannot walk
## to (terrain passability, D-007).
static func _kind_for(biome: int) -> int:
	match biome:
		TerrainGen.Biome.FOREST:
			return ResourceKind.WOOD
		TerrainGen.Biome.MOUNTAIN, TerrainGen.Biome.PEAK:
			return ResourceKind.STONE
		TerrainGen.Biome.GRASSLAND:
			return ResourceKind.FOOD
		TerrainGen.Biome.DRY_GRASSLAND:
			return ResourceKind.GOLD
		_:
			return -1


## Node positions and kinds for the wire, without their stock.
func node_entries() -> Array:
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
				if sim.cell_index_of(squad) == int(haul["node"]):
					haul["phase"] = Phase.GATHERING
			Phase.GATHERING:
				_gather(sim, squad, haul, def, dt, buildings)
			Phase.TO_DROP_OFF:
				_try_unload(sim, squad, haul, buildings, changed)

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
		# Worked out. The squad stops rather than standing on an empty
		# patch forever; the player picks somewhere new.
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

	# Straight back out to the node, if there is anything left in it.
	if has_node(int(haul["node"])):
		haul["phase"] = Phase.TO_NODE
		sim.force_move(squad, space.from_index(int(haul["node"])))
	else:
		_hauls.erase(squad)


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
