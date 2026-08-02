extends RefCounted
class_name PlayerColours

## One colour per player, for telling armies apart (D-052).
##
## Colour used to come from `UnitDef.mesh_color`, which meant it described
## the unit TYPE: every spearman on the map was the same grey whoever
## owned him. That is fine in a screenshot and useless in a battle — the
## first thing a player needs to read off the screen is whose units those
## are, and the roster is the second.
##
## ## Twenty, because that is the ceiling
##
## D-018 targets 20 concurrent players, so the palette has exactly twenty
## entries and no wrap-around: a wrapping palette would put two players in
## the same colour in precisely the largest, most confusing match. If the
## player ceiling ever rises, this list has to grow with it, and
## `count()` exists so a test can say so rather than a player discovering
## it mid-game.
##
## Chosen to stay distinguishable against the terrain palette (greens,
## sands, blues) and from each other — no two neighbours in hue, and
## nothing so dark it reads as shadow or so pale it reads as beach.

const PALETTE := [
	Color(0.85, 0.20, 0.18),  # red
	Color(0.20, 0.42, 0.88),  # blue
	Color(0.95, 0.78, 0.12),  # gold
	Color(0.55, 0.22, 0.75),  # violet
	Color(0.95, 0.48, 0.10),  # orange
	Color(0.10, 0.70, 0.62),  # teal
	Color(0.92, 0.45, 0.70),  # pink
	Color(0.45, 0.75, 0.15),  # lime
	Color(0.62, 0.36, 0.16),  # brown
	Color(0.30, 0.85, 0.95),  # cyan
	Color(0.75, 0.10, 0.45),  # magenta
	Color(0.15, 0.35, 0.45),  # slate
	Color(0.98, 0.62, 0.48),  # salmon
	Color(0.35, 0.28, 0.68),  # indigo
	Color(0.70, 0.85, 0.30),  # chartreuse
	Color(0.88, 0.88, 0.92),  # white
	Color(0.52, 0.52, 0.55),  # grey
	Color(0.20, 0.55, 0.30),  # forest
	Color(0.80, 0.65, 0.90),  # lilac
	Color(0.25, 0.20, 0.22),  # charcoal
]


static func count() -> int:
	return PALETTE.size()


## The colour for a seat position. Keyed by SEAT INDEX rather than player
## id: ids are not contiguous — AI seats are numbered from 1000 (D-051) —
## so indexing by id would either collide or leave gaps in the palette.
##
## Out of range returns the last entry rather than wrapping. Wrapping
## would silently give two players the same colour; this at least makes a
## twenty-first player look wrong rather than look like somebody else.
static func of_index(index: int) -> Color:
	if index < 0:
		return PALETTE[0]
	if index >= PALETTE.size():
		return PALETTE[PALETTE.size() - 1]
	return PALETTE[index]
