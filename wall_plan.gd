extends RefCounted
class_name WallPlan

## Where a wall goes, and where its gate goes (#337).
##
## `static_defence.gd` answers WHETHER to fortify and is domain-free so
## naval stage 7 can share it. This file is the other half — the part that
## knows what a wall is — and it is walls-only on purpose.
##
## All-static and pure, so the half with the interesting failure mode is
## testable without a server: `bot_patrol.gd`'s split, for `bot_patrol.gd`'s
## reason.
##
## ## A screen, not a ring, and that is arithmetic rather than taste
##
## A ring at radius 4 is 24 cells on a hex grid, and `wall.tres` costs 30
## wood and 40 stone — so an enclosure is **720 wood and 960 stone**
## before a single gate. Matches on the shipped ladder map are decided in
## a few minutes; nothing can afford that, and an AI that tried would
## spend its whole economy on masonry and field no army.
##
## What IS affordable is an ARC across the way the enemy comes: five
## segments is 150 wood and 200 stone, which a running economy reaches.
## That is also the shape that is worth anything at this match length — a
## wall's job here is to make an attack go somewhere the defender chose,
## not to make the base airtight.
##
## ## Everything is wrap-aware because everything goes through TorusSpace
##
## Bearings come from `space.delta`, which is the wrap-aware difference,
## and directions are compared in WORLD space through
## `space.axial_offset_to_world` — so no angle is computed on raw axial
## numbers, and a screen laid against a threat on the other side of the
## seam faces the short way round. That is the recurring torus tax
## (D-008), paid here rather than discovered later.

## Where the screen stands, in cells from home.
##
## Far enough out that the wall is not part of the town's own footprint
## and an attacker meets it before the buildings; near enough that a
## builder walks there and back without abandoning the economy, and that
## the arc still covers the approach rather than a horizon.
const STANDOFF_CELLS := 5

## How wide a screen gets. Five is a real obstacle at this match length
## and 150 wood / 200 stone of masonry; the cap is what stops an AI whose
## threat pressure stays high from fortifying itself out of the match.
const SEGMENTS := 5


## The cells of a screen facing `threat`, nearest the bearing first.
##
## Built from the MIDDLE outward, which matters: an AI raises one segment
## per think and may be interrupted by anything, so a half-built screen
## has to be a screen with short ends rather than a fence with a hole in
## the middle of the road.
##
## `blocked` is the cells that already refuse a building — impassable
## ground, and anything standing. Cells in it are skipped rather than
## shifting the arc: a wall that stops at a cliff is a wall that reaches
## the cliff, and impassable ground was already doing the wall's job.
static func screen(space: TorusSpace, home: Vector2i, threat: Vector2i,
		blocked: Dictionary = {}, segments: int = SEGMENTS,
		standoff: int = STANDOFF_CELLS) -> Array:
	var out := []
	if space == null or segments <= 0 or standoff <= 0:
		return out
	var bearing := _bearing(space, home, threat)
	if bearing == Vector3.ZERO:
		return out

	# The ring at `standoff`, scored by how squarely each cell sits on the
	# line home -> threat. `disk_offsets` is sorted nearest-first (D-067),
	# so the ring is its tail; taking `hex_length` explicitly says what is
	# wanted rather than relying on where the tail begins.
	var scored := []
	for offset in TorusSpace.disk_offsets(standoff):
		if TorusSpace.hex_length(offset) != standoff:
			continue
		var direction := space.axial_offset_to_world(Vector2(offset))
		if direction.length() <= 0.0:
			continue
		scored.append({"offset": offset, "score": direction.normalized().dot(bearing)})
	if scored.is_empty():
		return out
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))

	for entry in scored:
		if out.size() >= segments:
			break
		var cell: Vector2i = space.normalize(home + Vector2i(entry["offset"]))
		if blocked.has(space.index(cell)):
			continue
		out.append(cell)
	return out


## Which cell of a screen should be the GATE: the one squarely on the
## bearing, which `screen` already returns first.
##
## On the approach rather than off to one side, and that is deliberate
## twice over. It is where the defender's own army marches out, which is
## what makes an auto-opening gate worth having at all (D-076). And it is
## where an attacker arrives, which is what makes the wall a thing that
## gets FOUGHT OVER rather than walked past — the ladder gate #337 asks
## for cannot be satisfied by a wall nobody ever touches.
static func gate_index(cells: Array) -> int:
	return 0 if not cells.is_empty() else -1


## The direction a screen faces, in world space, wrap-aware.
##
## Through `space.delta` and `space.axial_offset_to_world` rather than any
## arithmetic on raw axial numbers: on a torus the difference of two
## coordinates is not the direction between them, and a bearing taken the
## long way round puts the wall on the wrong side of the town. Returns
## ZERO when the two cells coincide, which every caller reads as "no
## threat to face".
static func _bearing(space: TorusSpace, from: Vector2i, to: Vector2i) -> Vector3:
	var difference := space.delta(from, to)
	if difference == Vector2i.ZERO:
		return Vector3.ZERO
	var world := space.axial_offset_to_world(Vector2(difference))
	if world.length() <= 0.0:
		return Vector3.ZERO
	return world.normalized()


## What the whole screen costs, so a caller can decide before it starts
## rather than stalling half way through with a hole in the road.
##
## An AI that could afford segment one and not segment two would leave the
## worst possible object on the map: a wall short enough to walk round,
## bought with the wood that would have trained soldiers.
static func cost_of_screen(wall: BuildingDef, gate: BuildingDef,
		segments: int = SEGMENTS) -> PackedInt32Array:
	var total := PackedInt32Array()
	total.resize(Economy.RESOURCE_COUNT)
	if wall == null or segments <= 0:
		return total
	var wall_cost := StaticDefence.cost_of(wall)
	var gate_cost := StaticDefence.cost_of(gate if gate != null else wall)
	for i in range(Economy.RESOURCE_COUNT):
		total[i] = gate_cost[i] + wall_cost[i] * (segments - 1)
	return total


## The cheapest shipped def that BLOCKS ground, and the cheapest that is a
## GATE — found by their rules, never by id.
##
## D-076 ships five members of the wall family and a civ or a mod may ship
## more; naming `wall` and `gate` here would be the hardcoded list that
## `bot_build_plan.gd`'s header and D-047 both forbid. Cheapest by D-072's
## RP — the project's one exchange rate between resources — so the choice
## follows the data when the roster's prices move.
##
## A wall segment is a building that TAKES PART IN NO OTHER RULE: it
## trains nothing, receives nothing, founds nothing, shoots nothing and is
## not a door (`is_access_tower`). Every one of those is a field, so a
## sixth wall added tomorrow is found and a defensive tower is not.
static func cheapest_wall(gate_wanted: bool) -> BuildingDef:
	var best: BuildingDef = null
	var best_points := 0.0
	for def in BuildingSim.all_defs():
		if def.is_gate != gate_wanted:
			continue
		if not is_wall_like(def):
			continue
		var points := _points(def)
		if best == null or points < best_points:
			best = def
			best_points = points
	return best


## Anything bought FOR defence: a wall segment, a gate, or something that
## shoots and does nothing else.
##
## The second clause needs all of it. A first version asked only
## `damage > 0`, and the TOWN CENTRE shoots (D-076's tower family is not
## the only thing with a `damage`) — so every seat reported a defence
## standing before it had built one, and the investment cap was already
## one-sixth spent on the building the match starts around. Caught by a
## real ladder run reporting `defences_ordered=0 defences_standing=1`,
## which is a pair that cannot both be true.
static func is_static_defence(def: BuildingDef) -> bool:
	if def == null:
		return false
	if is_wall_like(def):
		return true
	return def.damage > 0.0 and def.produces.is_empty() \
		and not def.consumes_builder and not def.is_drop_off


static func is_wall_like(def: BuildingDef) -> bool:
	if def == null:
		return false
	return def.produces.is_empty() and not def.is_drop_off 		and not def.consumes_builder and not def.is_access_tower 		and def.damage <= 0.0


## The cheapest building that SHOOTS — the first thing worth buying with
## defensive money, because unlike a wall it does something to an attacker
## who is already inside.
##
## Same discipline: found by `damage > 0` rather than by name, so a civ's
## own tower is picked up with no edit here (D-047).
static func cheapest_defensive_tower(builder: StringName) -> BuildingDef:
	var best: BuildingDef = null
	var best_points := 0.0
	for def in BuildingSim.all_defs():
		if def.damage <= 0.0 or def.attack_range <= 0.0:
			continue
		if not def.produces.is_empty() or def.consumes_builder:
			continue
		if not BuildingSim.can_build(def, builder):
			continue
		var points := _points(def)
		if best == null or points < best_points:
			best = def
			best_points = points
	return best


static func _points(def: BuildingDef) -> float:
	# D-072's RP, the project's one exchange rate between resources.
	return def.cost_food + def.cost_wood + 1.5 * (def.cost_gold + def.cost_stone)
