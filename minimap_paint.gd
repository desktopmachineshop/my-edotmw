extends RefCounted
class_name MinimapPaint

## What the minimap paints on top of the terrain, and how much of it
## (D-101) — the pure half of the minimap, split out the same way
## `RenderCull`, `SelectionPick`, `HudLayout` and `GroundCover` were
## (D-045, D-061, D-063, D-100). The client keeps the image work; the
## decision about WHAT belongs on the minimap lives here and is testable
## headless, because the client itself is not (D-014).
##
## ## The defect this file was written for
##
## `_update_minimap` painted terrain, squad dots and resource nodes, and
## made no pass over `_state.buildings` at all. Town centres, barracks,
## towers, storehouses and walls — the player's own included — appeared
## nowhere on the minimap, for the whole of the game's life so far.
##
## That is worse than a missing convenience. Buildings are the only thing
## a client knows PERSISTENTLY: D-030 keeps a building forever once it has
## been shown one, frozen at last-known while out of vision, precisely
## because a building does not move and so has no positional staleness to
## represent. Squads ghost and disappear; buildings stay. The minimap is
## therefore the one view able to show a player the difference between
## what they can see and what they merely KNOW — and it was showing the
## one half that does not persist. A playtest could not judge
## "buildings once seen stay on the map, squads do not" because there was
## nothing on the minimap to watch persist.
##
## ## Two rules, and both are the point
##
## **Buildings are painted unconditionally on current visibility.** Not
## gated on `_explored` the way resource nodes are, and not gated on
## vision. Knowing about a building IS the state being drawn — the client
## only ever holds one because the server showed it (D-004 gates the wire,
## so there is nothing here to leak), and a base that vanished from the
## minimap when the scout walked home would be showing current vision, a
## thing the minimap already shows in three other ways.
##
## **A building's size on the minimap comes from data, never from a list
## of ids** (D-010). `BuildingDef.no_build_radius` already says how much
## ground a building claims (D-062) — a town centre claims a settlement's
## worth, a wall claims its own footprint — so the hierarchy a player
## reads is the hierarchy the design already declared. Adding a civ's own
## town hall never means editing this file.


## A squad's dot, in cells. 2x2 rather than a single pixel because the
## minimap image is one pixel per cell (a shipped map is 84x96 drawn into
## 216 screen px), so one cell is barely over two screen pixels.
const SQUAD_CELLS := 2

## An ordinary building: a barracks, a tower, a wall segment. The same
## size as a squad dot deliberately — a wall chain then reads as a line
## two cells thick rather than a blob, and nothing outweighs an army
## except the thing an army is fought over.
const BUILDING_CELLS := 2

## A settlement-scale building — in the shipped data, the town centre and
## nothing else. Bigger than a squad, because "where is my base" is the
## most common question anyone asks a minimap and the answer should not be
## the same size as a militia dot.
const SETTLEMENT_CELLS := 3

## The `no_build_radius` at or above which a building reads as a
## settlement. Shipped values: town centre 6, barracks/storehouse/tower 3,
## walls and gates 0.
const SETTLEMENT_CLAIM := 4

## How far an EXPLORED minimap pixel is pulled back toward
## `HudTheme.BG_VOID` (see `fogged`).
##
## Chosen against the darkest and the brightest biome rather than by eye on
## one of them: at 0.55 the deepest water goes from roughly (20, 51, 107)
## to (20, 33, 56) — still plainly water, still plainly above the
## unexplored (10, 9, 7) — while snow drops far enough that a remembered
## peak cannot be mistaken for one a scout is standing on. Below about 0.35
## the step stops reading at all, which was the original report.
##
## Deliberately its own number rather than `TerrainFog.SHADES[EXPLORED]`
## (0.45): that one multiplies ALBEDO on lit 3D ground, this one blends a
## flat pixel toward a UI colour. Tying them together would make either
## view's tuning silently retune the other.
const EXPLORED_DIM := 0.55

## How far UNEXPLORED sits below `HudTheme.BG_VOID` itself. The value the
## minimap has always drawn unexplored ground at; named here so all three
## tones are stated in one place.
const UNEXPLORED_DIM := 0.5


## def id -> cells across. Memoised from ONE `BuildingSim.all_defs()` walk
## rather than a `def_by_id` per building per repaint: the minimap redraws
## at 4 Hz over every building a client knows, and a ResourceLoader call
## on that path is the shape of defect that cost 858 ms of a tick budget
## in M4 (`UnitRoster.by_id`) and a frame in M5 (terrain noise). /buildings
## is read-only at runtime, so this is memoisation with no correctness
## cost — the same argument `BuildingSim._all_cache` makes.
static var _size_cache := {}


## How many cells across this building draws. Unknown ids — a def this
## build does not ship, which a mixed-version match can produce — fall
## back to the ordinary size rather than vanishing.
static func building_size(def_id: StringName) -> int:
	if _size_cache.is_empty():
		for def in BuildingSim.all_defs():
			_size_cache[def.id] = (SETTLEMENT_CELLS
				if def.no_build_radius >= SETTLEMENT_CLAIM
				else BUILDING_CELLS)
	return int(_size_cache.get(def_id, BUILDING_CELLS))


## The marks the minimap paints for a client's known buildings, in paint
## order (by wire id, so a repaint is stable and two overlapping walls do
## not flicker between frames).
##
## Takes `ClientState.buildings` as it stands — cell as a torus index,
## owner as a player number — and resolves neither, because both need
## state a pure module has no business holding: the space to unwrap the
## cell with, and the seat list to colour the owner from.
##
## Destroyed buildings are dropped. They stay in `ClientState.buildings`
## as tombstones (the client is told a building died, not that it should
## forget it existed), and a razed base that kept its minimap footprint
## would be reporting an enemy that is no longer there.
static func building_marks(buildings: Dictionary) -> Array:
	var marks := []
	var ids := buildings.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = buildings[id]
		if bool(info.get("destroyed", false)):
			continue
		marks.append({
			"cell": int(info.get("cell", 0)),
			"owner": int(info.get("owner", 0)),
			"size": building_size(StringName(info.get("def_id", ""))),
		})
	return marks


## The image pixels a mark of `size` cells covers, wrapped onto the torus:
## a blob on the right edge belongs on the left one too (D-008's tax,
## cheap for once). Odd sizes centre on the cell; even sizes start at it,
## which is what the squad dot has always done and is why a 2-cell mark
## still lands where its owner stands.
static func footprint(cell: Vector2i, size: int, width: int, height: int) -> Array:
	var out := []
	if width <= 0 or height <= 0:
		return out
	var span := maxi(size, 1)
	var origin := -((span - 1) / 2)
	for dy in range(span):
		for dx in range(span):
			out.append(Vector2i(
				posmod(cell.x + origin + dx, width),
				posmod(cell.y + origin + dy, height)))
	return out


## What fog does to a minimap pixel that would otherwise be `colour`
## (D-20260817), given that cell's `TerrainFog` level.
##
## The minimap drew TWO states while the ground drew three. `TerrainFog`
## already computes all three per client (D-106) — this file only decides
## what they LOOK like on a 1px-per-cell image, which is a different
## question from what they look like on lit 3D ground and needs its own
## answer: `TerrainFog.SHADES` multiplies albedo and bottoms out at pure
## black, which is right under a sky but wrong for a widget that has
## always drawn unexplored as `BG_VOID`.
##
## Three rules, and each is the point:
##
## **VISIBLE is the colour UNTOUCHED**, so fog only ever subtracts.
## `TerrainGen.biome_color` is the single source of truth for what this map
## looks like (D-083) and the minimap, the preview PNG and the 3D ground
## all read it. Brightening live cells would put a colour on the minimap
## that no other view of the same map has.
##
## **EXPLORED lerps toward `HudTheme.BG_VOID`** rather than multiplying
## down. A multiply puts the darkest biome — `DEEP_WATER`, (0.08, 0.20,
## 0.42) — close enough to the unexplored tone that deep ocean a player HAS
## scouted reads as ocean they have not. The lerp lands it near (20, 33,
## 56) against (10, 9, 7), and makes "remembered" literally partway back to
## "never seen", so the three tones sit on one line.
##
## **UNEXPLORED ignores `colour` entirely.** Ground nobody has scouted must
## not leak its biome through the fog.
##
## Takes a colour rather than a cell so the ground and a remembered
## resource node shade identically: a node a scout walked past three
## minutes ago should be exactly as faded as the ground it stands on, or
## the dot reads as live intelligence. Buildings are the deliberate
## exception and are painted unfogged — see `building_marks`.
static func fogged(colour: Color, level: int) -> Color:
	match level:
		TerrainFog.VISIBLE:
			return colour
		TerrainFog.EXPLORED:
			return colour.lerp(HudTheme.BG_VOID, EXPLORED_DIM)
		_:
			return HudTheme.BG_VOID.darkened(UNEXPLORED_DIM)
