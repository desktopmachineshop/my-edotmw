extends RefCounted
class_name TerrainFog

## What the GROUND knows, per cell, for one client (D-102).
##
## The sibling of `vision.gd` on the other side of the wire, and deliberately
## shaped like it: a field stamped once per refresh from whatever this player
## can see, then read O(1) per query. Vision decides what the server SENDS;
## this decides how the terrain already in front of the player is DRAWN.
##
## ## Why the ground needs its own fog at all
##
## D-004 and D-025 define fog of war as curve gating — entity state withheld on
## the wire. Terrain is not entity state: it is derived client-side from the map
## settings (D-049), identical for every player, and there is nothing about it to
## withhold. So the ground fell outside the fog mechanism entirely and was drawn
## fully lit from the first frame, with every test and number green, for six
## milestones. See D-102 for the decision, and issue #58 for the playtest that
## found it.
##
## Three states, not two, which is the part a boolean `_explored` set could not
## express:
##
##   UNEXPLORED  never seen        — black
##   EXPLORED    seen, not now     — dim; what the player REMEMBERS is there
##   VISIBLE     seen right now    — full
##
## The middle one is the whole point. Two states would either black out ground
## the player has scouted (throwing away the map they earned) or light ground
## they are not currently watching (claiming knowledge they do not have).
##
## ## Purely presentational, and that is load-bearing
##
## Nothing here is authoritative and nothing here reaches the wire. A client that
## computed its ground fog wrongly would draw the map wrongly and could not gain
## an advantage: squads, buildings and node depletion are all gated server-side
## (D-004/D-025/D-030/D-087) and are simply not in the packet. That is what lets
## this be derived locally — the same argument D-006 makes about soldier
## positions and `client.gd`'s explored set already made about the minimap.
##
## ## Wrap-awareness (D-008)
##
## Every cell written goes through `TorusSpace.index()`, and reveals walk
## `TorusSpace.disk_offsets()` — the same cached, nearest-first hex disk
## `vision.gd` and `combat.gd` use, and for the same standing reason: a radius
## scan reaches for `disk_offsets` before it reaches for `distance()`.

## Level values, in the order "less known" to "more known" so `maxi()` is the
## right way to merge two claims about a cell.
const UNEXPLORED := 0
const EXPLORED := 1
const VISIBLE := 2

## How brightly the ground is drawn at each level, indexed by the level.
##
## Unexplored is exactly zero rather than nearly zero: the shader multiplies
## ALBEDO by this, and albedo zero is black under any light the rig throws at it
## (D-086 has sky ambient as well as a sun, so "dark" and "unlit" are not the
## same thing here).
##
## Explored is high enough to read the biome and the shape of the coast — the
## player is meant to still have the map they scouted — and low enough that the
## eye separates it from live ground at a glance, which is the information it
## actually carries.
const SHADES: Array[float] = [0.0, 0.45, 1.0]

## The shader uniform the baked field is bound to. Named here rather than at the
## call site so `shaders/terrain.gdshader`, `TerrainChunk.set_fog` and the test
## that checks they agree all read one definition.
const SHADER_PARAM := "fog"

## Blur weight of a cell's own level against each of its six neighbours, applied
## once when baking (`_blurred`).
##
## Without it the transition from black to lit is exactly ONE CELL wide, and
## D-096 measured what a one-cell transition at high contrast looks like: the
## contour follows the hex edges and the boundary comes out visibly scalloped —
## and unexplored-against-visible is a stronger contrast than any biome pair on
## the map. Two neighbours' worth of self-weight spreads it over about three
## cells, which the texture's own bilinear filtering then smooths further.
##
## The cost of being wrong here is only ever cosmetic: blurring can light a cell
## the player has not scouted by an eighth, and terrain is public information.
const BLUR_SELF := 2.0

var space: TorusSpace

## Per cell, one of UNEXPLORED/EXPLORED/VISIBLE. A flat array rather than
## Vision's dictionary because this one is read for EVERY cell when baking, not
## for the handful a query asks about — the two files pick the shape their own
## access pattern wants, which is the same reasoning vision.gd's own comment
## gives for going the other way.
var levels := PackedByteArray()

## cell -> its six neighbours, built once. Baking walks the whole map, and
## `TorusSpace.neighbor_index` is a `from_index` plus an `index` plus six
## `posmod`s per call — 8,192 cells times six of those, several times a second,
## is the same shape as the per-cell `distance()` call vision.gd was built to
## avoid.
var _neighbours := PackedInt32Array()

var _shades := PackedFloat32Array()
var _bytes := PackedByteArray()
var _image: Image = null


func _init(for_space: TorusSpace) -> void:
	space = for_space
	var cells := space.cell_count()
	levels.resize(cells)
	levels.fill(UNEXPLORED)
	_shades.resize(cells)
	_bytes.resize(cells)
	_neighbours.resize(cells * 6)
	for i in range(cells):
		var coord := space.from_index(i)
		for d in range(6):
			_neighbours[i * 6 + d] = space.index(coord + TorusSpace.DIRECTIONS[d])


## Start a refresh: everything currently VISIBLE drops back to EXPLORED, and the
## reveals that follow raise back whatever is still in sight.
##
## Demoted rather than cleared, which is the persistent half — ground stays
## remembered forever once seen, exactly as `BuildingSim`'s ever-revealed set
## does (D-030), and for the same reason: terrain does not move.
func forget_visible() -> void:
	for i in range(levels.size()):
		if levels[i] == VISIBLE:
			levels[i] = EXPLORED


## Mark the hex disk of `radius` cells around `centre` as visible now.
func reveal(centre: Vector2i, radius: int) -> void:
	for offset in TorusSpace.disk_offsets(maxi(radius, 0)):
		levels[space.index(centre + offset)] = VISIBLE


func level_at(cell_index: int) -> int:
	return levels[posmod(cell_index, levels.size())]


## Whether this player has ever seen the cell. The question the minimap asks,
## and the reason it does not need to know about the third state to keep working.
func is_explored(cell_index: int) -> bool:
	return level_at(cell_index) != UNEXPLORED


## The field as a one-byte-per-cell image, ready for the terrain shader.
##
## FORMAT_R8, one texel per cell, laid out exactly like `TorusSpace.index` — row
## y*width + x — so the mesh's fog UVs (see `TerrainChunk.fog_uv`) address it by
## cell without a second convention anywhere.
##
## The same Image is refilled and returned each time, so a caller holding an
## `ImageTexture` can `update()` it rather than rebuilding a texture four times a
## second.
func bake() -> Image:
	_blurred()
	for i in range(_shades.size()):
		_bytes[i] = int(round(clampf(_shades[i], 0.0, 1.0) * 255.0))
	if _image == null:
		_image = Image.create_from_data(space.width, space.height, false,
			Image.FORMAT_R8, _bytes)
	else:
		_image.set_data(space.width, space.height, false, Image.FORMAT_R8, _bytes)
	return _image


## Shade per cell, each averaged with its six neighbours (see `BLUR_SELF`).
func _blurred() -> void:
	var total := BLUR_SELF + 6.0
	for i in range(levels.size()):
		var sum := SHADES[levels[i]] * BLUR_SELF
		for d in range(6):
			sum += SHADES[levels[_neighbours[i * 6 + d]]]
		_shades[i] = sum / total


## World-units range to a whole number of cells, through the SAME conversion
## `Vision._range_in_cells` uses. The client's fog has to cover the cells the
## server's vision covers — a client that rounded differently would draw a lit
## disk one ring wider or narrower than the one it is actually being told about,
## and enemies would appear on ground the player is looking at as dark.
static func radius_in_cells(for_space: TorusSpace, world_range: float) -> int:
	var hex_width := for_space.hex_size * TorusSpace.SQRT_3
	if hex_width <= 0.0:
		return 0
	return floori(world_range / hex_width)
