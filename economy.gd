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

## A worked-out VEIN keeps yielding, slowly and forever
## (D-20260828-a-vein-runs-deep-it-does-not-run-out). Gold and stone only:
## a tree is felled when it runs out (D-087) and that felling is drawn on
## the client, so leaving trees alone is what keeps that animation
## truthful.
##
## Derived, not chosen. A heavy squad costs 30 gold, so one vein at 0.25/s
## funds one every two minutes late in a match — a trickle a player plans
## around rather than an income they live on. A tower costs 120 stone, so
## one quarry at 0.4/s funds one every five minutes.
##
## Both are far below a LIVE seam, which a crew takes at ~1.96/s until its
## 2,400 is gone. That gap is the property that matters: the opening is
## still a race for rich ground and the tail is a floor, not a
## replacement.
const DEEP_MINE_PER_SECOND := {
	ResourceKind.GOLD: 0.25,
	ResourceKind.STONE: 0.4,
}

## Ten minutes of regrowth, so a vein left alone buffers a raid or a
## rebuild and no more. Capacity only ever BUFFERS — the income is the
## rate — which is what stops "come back in an hour" being a strategy,
## exactly as `BuildingDef.grow_capacity` does for a field.
const DEEP_MINE_CAPACITY := {
	ResourceKind.GOLD: 150,
	ResourceKind.STONE: 240,
}


## How far a crew looks for the next tree of the same kind when the one it
## was working runs out. Covers a forest's internal gaps without silently
## marching workers across the map to ground the player never chose.
const RETARGET_RADIUS := 8

## Cells whose vein has been worked below its tail capacity and is
## therefore regrowing (D-20260828-a-vein-runs-deep-it-does-not-run-out).
## A cell enters when a crew empties it and never leaves: a vein that has
## been dug once is a deep mine from then on.
##
## Kept as its own set rather than re-derived by scanning `nodes`, which
## holds 5,559 entries on the shipped map against a 10 Hz tick.
var _deep_veins := {}

## The fractional part of what each deep vein has regrown. `remaining` is
## an integer count of things a crew can carry, so without this a 0.25/s
## tail would add floor(0.025) = 0 on every tick, forever — the mechanism
## correct and the shipped numbers doing nothing, which is the defect
## family this project keeps meeting (D-055, D-066).
var _deep_stock := {}

var space: TorusSpace

## The ground the nodes were derived from, remembered by `generate()`.
##
## Kept so the fairness post-pass can tell whether the cell it is about to
## drop a node on is ground that grows the thing (D-104). Not a second
## TerrainGen: the server builds exactly one and hands it here, for the
## reason server.gd states about passability — two instances would be two
## sources of truth about the same ground.
var terrain: TerrainGen

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

## The RENEWABLE half of the ledger
## (D-20260828-food-is-grown-not-only-found): cell index -> { "kind": int,
## "stock": float, "capacity": int, "regrow": float }.
##
## A farm is a work site a crew is ordered onto exactly as it is ordered
## onto a forest — the difference is that its stock GROWS rather than only
## running down, so a match's economy is a rate rather than a fixed pile.
##
## Deliberately NOT in `nodes`. A node is ground the map generator placed
## and the wire reveals; a farm is a BUILDING, already replicated and
## already fog-gated knowledge (D-030), so putting it here would put a
## forest's worth of tree visuals on top of somebody's field and add a
## wire message for a fact both sides already hold.
##
## DERIVED from the buildings by `sync_farms`, never accumulated — see
## that function for why.
var farms := {}


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
## classification reads: a forest's wet heart is dense woodland, its dry
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
func generate(p_terrain: TerrainGen, symmetry_order: int = 1) -> void:
	nodes.clear()
	terrain = p_terrain

	var repeats := maxi(1, symmetry_order)
	var quadrant_width := maxi(1, space.width / repeats)
	var quadrant_height := maxi(1, space.height / repeats)

	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var local := (coord.x % quadrant_width) + (coord.y % quadrant_height) * quadrant_width
		var roll := _roll(terrain.noise_seed, local)

		var kind := _roll_kind(coord, roll)
		if kind < 0:
			continue
		nodes[index] = {"kind": kind, "remaining": stock_for(kind)}


## What (if anything) grows on this cell, given one deterministic roll in
## [0, 1). The first band the roll falls under wins.
func _roll_kind(coord: Vector2i, roll: float) -> int:
	for band in _bands(coord):
		if roll < float(band["below"]):
			return int(band["kind"])
	return -1


## What this cell CAN grow, in the order the roll tests them: an ordered
## list of {kind, below}, where a roll under `below` yields that kind.
##
## THE definition of biome-derived placement (D-087), and it is one table
## rather than two because the fairness post-pass reads it as well
## (D-104): a top-up needs to know whether the ground it is about to land
## on grows the thing at all. Two spellings of the same table would drift,
## and the symptom would be stone outcrops on sand with every number
## green.
##
## ## Why the wood bands are what they are
##
## Every wood band was scaled by 0.60
## (D-20260818-open-country-with-woods-in-it, #94) — a playtest read the
## map as woodland with clearings rather than open country with woods in
## it. Scaling the ENDPOINTS keeps the shape D-087 built (wet hearts
## dense, treelines frayed, lone trees in dry country) and only thins it;
## a flat subtraction or a stride would undo it.
##
## The 0.98 the forest band used to end at was never actually paid: `f`
## reaches 1 only where moisture reaches 1, and over six seeds on the
## shipped map the wettest single forest cell measured f = 0.57-0.73. The
## realised density was the FLOOR — the median forest cell rolled at 0.69
## and the biome came out 70.2% wooded. So this is a change to the floor
## first and the ceiling second, whatever the ceiling reads as.
##
## Note the thresholds are ABSOLUTE cut points tested in order, not
## cumulative widths — the biome's own table is tested from zero even
## when the mountain-foot band above it missed, so a forest cell at the
## rock face is still a forest.
func _bands(coord: Vector2i) -> Array:
	var biome := terrain.biome_at(space, coord)
	var out := []

	# Mountain-foot stone first: it outranks the ground biome's own table,
	# because a foot cell IS a grassland/dry/forest cell, and stone reads
	# as belonging at the rock face. "A foot cell is walkable by
	# construction" stopped being true when passability became the slope
	# rule (D-20260826-passable-means-flat-enough-to-cross) — the foot of a
	# cliff can be its lip seen from below — so walkability is CHECKED now,
	# or D-087's unreachable-scenery defect comes back through this band.
	if biome != TerrainGen.Biome.MOUNTAIN and biome != TerrainGen.Biome.PEAK \
			and biome != TerrainGen.Biome.WATER and biome != TerrainGen.Biome.DEEP_WATER:
		if _touches_mountain(coord) and terrain.passable_at(space, coord):
			out.append({"kind": ResourceKind.STONE, "below": 0.25})

	match biome:
		TerrainGen.Biome.MOUNTAIN, TerrainGen.Biome.PEAK:
			# Walkable high ground grows stone
			# (D-20260826-passable-means-flat-enough-to-cross). D-087 moved
			# stone off mountain cells because they were unreachable
			# scenery; a flat plateau no longer is, and reachable-but-bare
			# ground would be #129's dead space with the fence moved. The
			# sparse spelling on purpose: it answers the LOCAL slope rule,
			# so a carved ramp cell stays bare — a node in a doorway would
			# park a crew in the one cell an army needs.
			if terrain.passable_at(space, coord):
				out.append({"kind": ResourceKind.STONE, "below": 0.08})
		TerrainGen.Biome.FOREST:
			# Wet heart dense, dry edge thinned: density rides the same
			# moisture that classified the cell as forest at all.
			var f := clampf((terrain.moisture_at(space, coord) - TerrainGen.MOISTURE_FOREST)
				/ (1.0 - TerrainGen.MOISTURE_FOREST), 0.0, 1.0)
			out.append({"kind": ResourceKind.WOOD, "below": lerpf(0.39, 0.59, f)})
		TerrainGen.Biome.GRASSLAND:
			# Groves thicken toward the forest line (m -> MOISTURE_FOREST),
			# orchards sit in the mid-moisture band where neither extreme
			# claims the ground.
			var g := clampf((terrain.moisture_at(space, coord) - TerrainGen.MOISTURE_DRY)
				/ (TerrainGen.MOISTURE_FOREST - TerrainGen.MOISTURE_DRY), 0.0, 1.0)
			var wood := 0.03 + 0.132 * g * g
			var food := 0.05 + 0.16 * (1.0 - absf(g - 0.5) * 2.0)
			out.append({"kind": ResourceKind.WOOD, "below": wood})
			out.append({"kind": ResourceKind.FOOD, "below": wood + food})
		TerrainGen.Biome.DRY_GRASSLAND:
			var dry_wood := 0.06
			out.append({"kind": ResourceKind.WOOD, "below": dry_wood})
			# Written off `dry_wood` rather than repeating the number,
			# because gold's own share of this biome is the WIDTH 0.017 and
			# a wood band edited without the cut point above it moving
			# would silently re-price gold (D-20260818's clause 2).
			out.append({"kind": ResourceKind.GOLD, "below": dry_wood + 0.017})
		TerrainGen.Biome.BEACH:
			out.append({"kind": ResourceKind.WOOD, "below": 0.06})
	return out


## Does this cell border the mountains? Neighbours only — stone reads as
## sitting AT the rock face, and one ring keeps it as rare as the terrain's
## mountain perimeter.
func _touches_mountain(coord: Vector2i) -> bool:
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
## Where a quota is short, a node is placed on the nearest ground the
## spawn can walk to that would GROW the thing (D-104), falling back to
## any walkable cell only when the quota cannot otherwise be met — and
## saying so when it does, per CLAUDE.md's no-silent-caps rule.
##
## The fallback is still the right call in the end: a player with no
## forest in reach still needs wood, and "fair" beats "geologically tidy"
## when the alternative is losing at map-generation time. But it used to
## be the FIRST call, biome-blind, which put stone outcrops on grass and
## sand within sight of a start — 38 top-ups on a 20-player islands map,
## none of them on ground that grows what they hold. That flatly
## contradicts D-087, which moved stone to the mountain foot precisely so
## a node reads as belonging to the ground it sits on.
##
## Beach is ranked BELOW other walkable ground rather than merely
## unpreferred: a beach cell borders water by definition, and the authored
## node models span ~2.3-2.6 world units against a ~1.73-unit cell, so a
## rock dropped there visibly overhangs the sea. That is what the P01
## screenshot was actually showing.
##
## Deterministic: it walks cells in index order within each rank, so
## replays and both sides of the wire agree.
func balance_for_spawns(spawns: Array, passable: PackedByteArray,
		radius: int, quota: int) -> void:
	# Counted rather than warned per node: one line saying how much of the
	# guarantee had to be forced onto unsuitable ground is information; one
	# line per node on a 20-player island map is noise.
	var compromised := 0
	var placed := 0

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
			# to, best ground first. `walkable` is already in flood-fill
			# order, which is nearest-first, and already excludes water and
			# the far bank; the rank pass over it is what keeps a stone
			# outcrop off the beach while there is a mountain foot two
			# cells further out.
			#
			# The rank of a cell is recomputed on each pass rather than
			# cached, which reads as the obvious thing to optimise and is
			# not: a dictionary of per-cell ranks measured SLOWER than the
			# repeated `_bands` calls it replaced, because it ranks every
			# reachable cell while this ranks only free ones. The whole
			# pass costs ~0.45 s on a 20-player 168x194 map against ~0.12 s
			# biome-blind, once, at world build — not a tick cost.
			for rank in range(GROUND_RANKS):
				if found >= quota:
					break
				for index in walkable:
					if found >= quota:
						break
					if nodes.has(index):
						continue
					var coord := space.from_index(index)
					if space.distance(spawn, coord) < 2:
						continue  # leave room for the town hall itself
					if int(_ground_ranks(coord)[kind]) != rank:
						continue
					nodes[index] = {"kind": kind, "remaining": stock_for(kind)}
					found += 1
					placed += 1
					if rank > GROUND_NATURAL:
						compromised += 1

	if compromised > 0:
		print("economy: %d of %d fairness top-ups placed on ground that does not grow them — the starts needing them have no better cell in reach" % [
			compromised, placed])


## How well a cell suits a fairness top-up, best first (D-104). The pass
## places every cell of one rank before it looks at the next.
enum { GROUND_NATURAL, GROUND_PLAUSIBLE, GROUND_SHORELINE }
const GROUND_RANKS := 3


## This cell's rank for each resource kind, indexed by ResourceKind.
##
## All four at once because `_bands` reads eight biome samples and the
## caller wants every kind's answer about the same cell — asking per kind,
## per rank pass, put the same question to the same ground twelve times.
func _ground_ranks(coord: Vector2i) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(RESOURCE_COUNT)

	# No terrain means nothing to prefer with, and "natural" everywhere
	# degrades exactly to the biome-blind pass this replaced. Only a caller
	# that skipped `generate()` gets here — every shipped one goes through
	# it.
	if terrain == null:
		return out

	var fallback := GROUND_SHORELINE if terrain.biome_at(space, coord) == TerrainGen.Biome.BEACH \
		else GROUND_PLAUSIBLE
	for kind in range(RESOURCE_COUNT):
		out[kind] = fallback
	for band in _bands(coord):
		if float(band["below"]) > 0.0:
			out[int(band["kind"])] = GROUND_NATURAL
	return out


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


## Which resource a building of this type GROWS, or -1
## (D-20260828-food-is-grown-not-only-found). The one translation from
## `BuildingDef.grows` to `ResourceKind`, so nothing else has to know the
## field is spelled as a string.
static func grows_kind(def: BuildingDef) -> int:
	if def == null:
		return -1
	match def.grows:
		"food":
			return ResourceKind.FOOD
		"wood":
			return ResourceKind.WOOD
		"gold":
			return ResourceKind.GOLD
		"stone":
			return ResourceKind.STONE
		_:
			return -1


## Rebuild the farm registry from the buildings that are actually standing.
##
## DERIVED rather than hooked onto construction, and that is the load-
## bearing choice. A building becomes complete down several paths — an
## ordinary build finishing, the sandbox's instant build, an in-place
## upgrade, `Scenario.apply_player` — and a hook has to be remembered at
## every one of them. #119's finding is that the handover nothing performs
## is the dangerous half, so this asks the buildings instead: whatever is
## living and complete and grows something IS a farm, and nothing else is.
##
## Stock already grown SURVIVES a resync (the same field, still standing,
## has not stopped growing because something else was built) while a razed
## farm's entry does not — its crew then finds no work site and retargets
## or is released, exactly as it does at a worked-out tree.
##
## Called from `server._buildings_changed()`, beside `_refresh_passability()`,
## because both answer the identical question: the set of living buildings
## changed. O(buildings), and only when one is raised or lost.
func sync_farms(buildings: BuildingSim) -> void:
	if buildings == null:
		farms.clear()
		return
	var live := {}
	for i in range(buildings.building_count()):
		if buildings.is_destroyed(i) or not buildings.is_complete(i):
			continue
		var def := buildings.def_of(i)
		var kind := grows_kind(def)
		if kind < 0 or def.grow_per_second <= 0.0:
			continue
		var cell := buildings.cell_index_of(i)
		live[cell] = true
		if farms.has(cell) and int(farms[cell]["kind"]) == kind:
			farms[cell]["capacity"] = def.grow_capacity
			farms[cell]["regrow"] = def.grow_per_second
			farms[cell]["owner"] = buildings.owner_of(i)
			continue
		farms[cell] = {
			"kind": kind,
			"stock": 0.0,
			"capacity": def.grow_capacity,
			"regrow": def.grow_per_second,
			"owner": buildings.owner_of(i),
		}
	for cell in farms.keys():
		if not live.has(cell):
			farms.erase(cell)


## Bring worked-out veins back toward their tail capacity.
##
## Only nodes ALREADY BELOW their tail capacity regrow, so a fresh 2,400
## seam is untouched and the opening plays exactly as it did — the tail is
## a floor under a spent vein, not a slow refill of a rich one.
##
## O(veins that are actually low), because the ones at or above capacity
## are skipped on the first comparison. The dictionary of low veins is
## kept rather than scanning every node: `nodes` is 5,559 entries on the
## shipped map and this runs at 10 Hz, so walking all of it per tick would
## be the per-candidate scan this project keeps paying for (vision's
## `distance()`, `UnitRoster.by_id`, terrain noise, the per-squad building
## scan).
func _regrow_veins(dt: float) -> void:
	for cell in _deep_veins:
		var node: Dictionary = nodes.get(cell, {})
		if node.is_empty():
			continue
		var kind := int(node["kind"])
		var capacity := int(DEEP_MINE_CAPACITY.get(kind, 0))
		if capacity <= 0:
			continue
		var whole := int(node["remaining"])
		if whole >= capacity:
			continue
		var carried := float(_deep_stock.get(cell, 0.0)) \
			+ float(DEEP_MINE_PER_SECOND.get(kind, 0.0)) * dt
		var gained := int(floor(carried))
		_deep_stock[cell] = carried - float(gained)
		if gained > 0:
			node["remaining"] = mini(whole + gained, capacity)


## Whether this node is a VEIN — a mineral a deep mine can keep working.
## Asked of the KIND, so a future resource is covered by adding it to the
## two tables above and nowhere else.
static func is_vein(kind: int) -> bool:
	return DEEP_MINE_PER_SECOND.has(kind)


func has_farm(cell_index: int) -> bool:
	return farms.has(cell_index)


func farm_count() -> int:
	return farms.size()


## Whole units a crew could carry off this farm right now. Floored, because
## `carrying` is an integer count of things — the part-grown remainder stays
## in the ground.
func farm_stock(cell_index: int) -> int:
	if not farms.has(cell_index):
		return 0
	return int(floor(float(farms[cell_index]["stock"])))


## Is this cell somewhere a crew can be put to work — a node or a farm?
## THE question `order_gather`, the haul cycle and `_retarget` all ask;
## `has_node` alone would silently make every farm unworkable.
func is_work_site(cell_index: int) -> bool:
	return has_node(cell_index) or has_farm(cell_index)


## What working this cell yields, or -1. A farm wins the tie because a
## node may not be founded under a building in the first place
## (`server._can_build_at`), so the two cannot genuinely overlap.
func work_kind_at(cell_index: int) -> int:
	if farms.has(cell_index):
		return int(farms[cell_index]["kind"])
	return kind_at(cell_index)


## Who owns the farm at this cell, or -1 for a natural node (nobody owns a
## forest) and for a cell holding nothing.
func farm_owner(cell_index: int) -> int:
	return int(farms[cell_index]["owner"]) if farms.has(cell_index) else -1


## May this SQUAD be put to work here?
##
## A node is unowned ground and anyone may work it — that is D-028 and it
## does not change. A FARM is a building somebody paid for, so it is
## worked by its owner and, per D-050's shared front, by an ally. Without
## this an enemy crew could stand in your fields and haul your harvest
## home, which is a mechanic nobody decided on.
func may_work(sim: SquadSim, squad: int, cell_index: int) -> bool:
	if not is_work_site(cell_index):
		return false
	var owner := farm_owner(cell_index)
	if owner < 0:
		return true
	var who := sim.owner_of(squad)
	return owner == who or sim.are_allied(owner, who)


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
	if not may_work(sim, squad, cell_index):
		return false
	_hauls[squad] = {
		"node": cell_index,
		"phase": Phase.TO_NODE,
		"carrying": 0,
		"kind": work_kind_at(cell_index),
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

	# The renewable half, first: a field grows whether or not anybody is
	# standing in it (D-20260828-food-is-grown-not-only-found), so a crew
	# away hauling is not wasting its farm's rate. Capped at `capacity`,
	# which is what stops "leave it alone all match" being a strategy.
	# O(farms) — a handful per player, nothing like the node dictionary.
	for cell in farms:
		var farm: Dictionary = farms[cell]
		farm["stock"] = minf(float(farm["stock"]) + float(farm["regrow"]) * dt,
			float(farm["capacity"]))

	# And the other renewable half: a VEIN runs deep
	# (D-20260828-a-vein-runs-deep-it-does-not-run-out). A gold or stone
	# node that has been worked out keeps producing at a slow permanent
	# rate rather than dying, so the map's metal budget stops being fixed
	# at generation — 48 gold nodes on the shipped map, one per 679 cells,
	# is a wall inside the first third of a 1-2 hour match (D-056).
	#
	# The site rather than a building, deliberately: a mine a player could
	# raise anywhere would delete map control from the late game, which is
	# the thing D-039's scattered spawns and D-087's ore-on-the-mountain
	# -perimeter exist to create.
	#
	# `_deep_stock` carries the fraction, so a tail is not rounded away
	# tick by tick: at 0.25/s and a 0.1 s tick, an integer-only version
	# would add zero forever.
	_regrow_veins(dt)

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
				if not is_work_site(int(haul["node"])):
					if not _retarget(sim, squad, haul):
						_hauls.erase(squad)
						continue
				elif sim.cell_index_of(squad) == int(haul["node"]):
					haul["phase"] = Phase.GATHERING
			Phase.GATHERING:
				_gather(sim, squad, haul, def, dt, buildings)
			Phase.TO_DROP_OFF:
				_try_unload(sim, squad, haul, buildings, changed)

		# The economy no longer touches a crew's SHAPE at all
		# (D-20260820-men-gather-round-what-they-strike, amended on the
		# owner's follow-up): the ring-while-working switch was a bandaid
		# for the picture, and the render layer now gathers a working
		# crew round its node properly. A crew keeps whatever formation
		# it has — the player's, or its def's.

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
	if not is_work_site(cell):
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
	#
	# The owner's civ scales the crew's rate (`CivDef.gather_speed`,
	# D-047) — applied here, per tick, rather than latched into the haul
	# when the order was given: a latched multiplier is a cached copy of a
	# fact the simulation already holds, which is the shape of the D-038
	# ownership cache that silently refused every produced squad an order.
	var crew_rate := sim.civ_effects(sim.owner_of(squad)).gather_rate(def.gather_rate)
	var rate := crew_rate * float(sim.alive_of(squad)) * dt
	haul["fraction"] = float(haul.get("fraction", 0.0)) + rate
	var whole := int(floor(float(haul["fraction"])))
	if whole <= 0:
		return

	# A FARM is rate-limited by the ground rather than by the crew
	# (D-20260828-food-is-grown-not-only-found): a crew takes whatever has
	# grown, which is normally less than it could carry off. That is the
	# mechanism, not a shortfall — the steady state per farm is its own
	# regrow rate however many crews stand on it.
	var farmed := has_farm(cell)
	var available := farm_stock(cell) if farmed else remaining_at(cell)
	var taken := mini(whole, available)
	taken = mini(taken, def.carry_capacity - int(haul["carrying"]))
	if taken <= 0:
		# The crew did the work and there was nothing to take yet. Keep its
		# part-done unit — spending it here is a silent yield cut, and on a
		# farm it happens every few ticks by construction — but never let it
		# bank more than one, or a crew standing in an unworked field for a
		# minute would strip it the instant a whole unit appears.
		haul["fraction"] = minf(float(haul["fraction"]), 1.0)
		return

	# Only the labour that actually moved something is spent.
	haul["fraction"] = float(haul["fraction"]) - float(taken)
	haul["carrying"] = int(haul["carrying"]) + taken

	if farmed:
		farms[cell]["stock"] = float(farms[cell]["stock"]) - float(taken)
	else:
		nodes[cell]["remaining"] = remaining_at(cell) - taken
		if is_vein(int(nodes[cell]["kind"])):
			# A vein does not die. Once dug out it regrows toward its tail
			# capacity forever, so it never reaches `_depleted` and no
			# felling is ever sent for it — the outcrop stays on the map
			# because it is still there and still being worked.
			_deep_veins[cell] = true
		elif remaining_at(cell) <= 0:
			# The tree comes down. The entry stays in `nodes` (a depleted
			# cell is still not a place to start another node) — this list
			# is how the server learns to tell clients about the felling.
			# A farm never appears here: it is a building, and the client
			# already draws it and already learns when it is razed.
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
	if is_work_site(int(haul["node"])):
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
		# Farms count as work sites here too: a crew whose field is razed
		# steps to the next one exactly as a crew whose tree comes down
		# steps to the next tree, and farms are built in groups. Through
		# `may_work`, so a retarget cannot walk a crew into an enemy's
		# fields — a rule the ORDER path enforces is not enforced until
		# every path that assigns a work site asks the same question.
		if may_work(sim, squad, cell) and work_kind_at(cell) == kind:
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
