extends RefCounted
class_name TerrainFog

## What the GROUND knows, per cell, for one client (D-106).
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
## milestones. See D-106 for the decision, and issue #58 for the playtest that
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

## Cells stamped VISIBLE since the last `forget_visible`, and the same list from
## the refresh before it. Held so both halves of a refresh cost what is being
## LOOKED AT rather than what the map contains: `forget_visible` demotes only
## these, and `bake` diffs the two to find what needs re-shading.
##
## Duplicates are allowed — overlapping vision disks stamp a cell more than once
## — because both readers are idempotent over them, and de-duplicating on the
## way in would cost a dictionary insert per cell per refresh to save nothing.
var _stamped := PackedInt32Array()
var _previously_stamped := PackedInt32Array()

## Whether `bake` has ever run. The first one has no previous state to diff
## against and must shade the whole map.
var _baked := false

## How many cells the last `bake` re-shaded.
##
## Exposed because "a refresh costs what the player is LOOKING at, not what the
## map contains" is a claim about WORK, and the test that first guarded it
## measured the CLOCK instead: it timed a Standard-map refresh against a Huge one
## and asserted the ratio. That gate went red with nothing wrong — the same code
## measured 2.73 vs 2.61 ms on a quiet host and 7.81 vs 20.61 ms while eleven
## branches were being built beside it.
##
## Which is exactly the failure this project's own note warns about, committed by
## the comment warning about it: a tight timing gate on a shared machine gets
## muted rather than fixed. So the property is asserted on this counter, which is
## deterministic, and the milliseconds are reported instead of gated.
var cells_shaded_last_bake := 0


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


## Restamp the whole field from what this client can currently see — the mirror
## of `Vision.rebuild`, and deliberately the same shape: everything visible a
## moment ago drops back to remembered, then every seeing thing stamps its disk.
##
## Lives here rather than in `client.gd` because `client.gd` needs a scene tree
## and a GPU and is therefore unreachable from GUT, while `ClientState` is
## explicitly the headless half of the client (see its header). The first
## version of this WAS in `client.gd`, and it shipped with allied buildings
## excluded — a bug no test could have been written against without this move.
func rebuild(state: ClientState, now: float) -> void:
	# The sandbox's full visibility (D-20260821). The server is already
	# sending this player everything; without this the GROUND would stay
	# black around it, which is the fog half of the same flag rather than
	# a second mechanism.
	#
	# Checked BEFORE `forget_visible` and latched, so a flag somebody
	# leaves on does not re-stamp the whole map four times a second
	# (`FOG_INTERVAL`): once everything is VISIBLE, nothing is changing,
	# and the honest way to say so is to stamp nothing. The latch clears
	# the moment the flag does, and the ordinary path below then
	# re-derives the real field from scratch.
	stamps_last_rebuild = 0
	if state != null and state.reveal_all():
		if _revealed_everything:
			return
		forget_visible()
		for cell in range(levels.size()):
			reveal_cell(cell)
		_revealed_everything = true
		stamps_last_rebuild = levels.size()
		return
	_revealed_everything = false

	forget_visible()
	if state == null or state.space == null:
		return

	# Allies reveal ground too (D-050). Both loops below ask the same question
	# in the same way: `friendly_squads` is already team-aware, and the
	# buildings loop goes through `are_allied` rather than comparing owners.
	#
	# It did compare owners, for exactly one review cycle. The server stamps
	# buildings into the TEAM's shared coverage (`Vision._group_of`), so an
	# owner test made the client's fog strictly NARROWER than the vision the
	# server gates on: an ally's town hall lit nothing, its base rendered black,
	# and enemy squads standing in it drew fully lit on top of the dark ground.
	for squad in state.friendly_squads():
		if not state.curves.has(squad) or not state.composition.has(squad):
			continue
		if state.alive_of(squad) <= 0:
			continue
		var def := UnitRoster.by_id(StringName(state.composition[squad]["def_id"]))
		if def == null:
			continue
		reveal(state.squad_cell(squad, now), radius_in_cells(space, def.vision_range))

	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if bool(info["destroyed"]):
			continue
		if not state.are_allied(state.player, int(info["owner"])):
			continue
		var building_def := BuildingSim.def_by_id(StringName(info["def_id"]))
		if building_def == null:
			continue
		reveal(state.space.from_index(int(info["cell"])),
			radius_in_cells(space, building_def.vision_range))
	stamps_last_rebuild = _stamped.size()


## Start a refresh: everything currently VISIBLE drops back to EXPLORED, and the
## reveals that follow raise back whatever is still in sight.
##
## Demoted rather than cleared, which is the persistent half — ground stays
## remembered forever once seen, exactly as `BuildingSim`'s ever-revealed set
## does (D-030), and for the same reason: terrain does not move.
##
## Walks the cells stamped since the LAST call rather than the whole map, which
## is what keeps a refresh proportional to how much is being looked at instead
## of to how big the map is. `_stamped` is also what `bake` diffs to find the
## cells whose shade needs recomputing.
func forget_visible() -> void:
	for i in _stamped:
		if levels[i] == VISIBLE:
			levels[i] = EXPLORED
	_previously_stamped = _stamped
	_stamped = PackedInt32Array()


## Mark the hex disk of `radius` cells around `centre` as visible now.
##
## A NEGATIVE radius stamps nothing at all, which is not the same as zero
## stamping the centre cell. That distinction mirrors `Vision._stamp`, which
## returns early on a non-positive range and otherwise floors — see
## `radius_in_cells`.
func reveal(centre: Vector2i, radius: int) -> void:
	if radius < 0:
		return
	for offset in TorusSpace.disk_offsets(radius):
		var i := space.index(centre + offset)
		levels[i] = VISIBLE
		_stamped.append(i)


## Whether the whole map is currently stamped VISIBLE by the sandbox's
## reveal-all flag — the latch that keeps that flag from re-stamping
## every cell on every refresh. False in every real match.
var _revealed_everything := false


## Stamp one cell VISIBLE, with the same accounting `reveal` does per
## disk — so the re-shade counting the D-106 cost test reads stays
## truthful whichever door a cell came through.
func reveal_cell(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= levels.size():
		return
	levels[cell_index] = VISIBLE
	_stamped.append(cell_index)


## How many cells the LAST `rebuild` call itself stamped — zero when a
## refresh found nothing to do. Distinct from `stamped_count()` below,
## which is the standing set: the first version of the reveal-all latch
## test read that one and could not tell "stamped nothing this time" from
## "everything is still stamped from last time".
var stamps_last_rebuild := 0


## How many cells the last refresh stamped. Exposed for the same reason
## `cells_shaded_last_bake` is: "a refresh costs what is being looked at"
## is a claim about WORK, and a test that measured the clock instead went
## red on a loaded host with nothing wrong.
func stamped_count() -> int:
	return _stamped.size()


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
## Only the cells whose level actually changed are re-shaded — see `_rebake`.
## The first bake has nothing to diff against and does the whole map.
func bake() -> Image:
	if _baked:
		_rebake(_changed_since_last_bake())
	else:
		_rebake(_all_cells())
		_baked = true
	if _image == null:
		_image = Image.create_from_data(space.width, space.height, false,
			Image.FORMAT_R8, _bytes)
	else:
		_image.set_data(space.width, space.height, false, Image.FORMAT_R8, _bytes)
	return _image


## Cells whose level differs from what the last bake saw: those stamped then and
## not now (VISIBLE dropped to EXPLORED), and those stamped now and not then.
## A cell in both sets was visible before and is visible still.
##
## This is what stops a refresh costing the map rather than the motion. The full
## passes it replaces were fine at the Standard map's 8,064 cells and not at the
## Huge preset's 32,592, on a frame M5 and M7 both measured as CPU-bound — and
## the cost test could not have seen it, because it only ever loaded the
## Standard map. Same lesson as D-040's per-tick cell budget: bound the work by
## what changed, not by what exists.
func _changed_since_last_bake() -> PackedInt32Array:
	var seen := {}
	for i in _previously_stamped:
		seen[i] = 1
	for i in _stamped:
		seen[i] = int(seen.get(i, 0)) | 2
	var out := PackedInt32Array()
	for i in seen:
		if int(seen[i]) != 3:
			out.append(i)
	return out


func _all_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(levels.size())
	for i in range(levels.size()):
		out[i] = i
	return out


## Re-shade `changed` and every neighbour of it, then convert those to bytes.
##
## The neighbour ring is not optional: a cell's drawn shade is the average of
## its own level and its six neighbours' (see `BLUR_SELF`), so a cell that
## changed alters seven shades, not one. Leaving the ring out is the kind of
## optimisation that looks right and leaves a one-cell halo of stale fog behind
## a moving army — which is why `tests/test_terrain_fog.gd` asserts an
## incremental bake is byte-identical to a from-scratch one.
func _rebake(changed: PackedInt32Array) -> void:
	var dirty := {}
	for i in changed:
		dirty[i] = true
		for d in range(6):
			dirty[_neighbours[i * 6 + d]] = true

	cells_shaded_last_bake = dirty.size()

	var total := BLUR_SELF + 6.0
	for i in dirty:
		var sum := SHADES[levels[i]] * BLUR_SELF
		for d in range(6):
			sum += SHADES[levels[_neighbours[int(i) * 6 + d]]]
		_shades[i] = sum / total
		_bytes[i] = int(round(clampf(_shades[i], 0.0, 1.0) * 255.0))


## World-units range to a disk radius in cells, through the SAME conversion
## `Vision._range_in_cells` uses, and with the same treatment of the edge case.
##
## The client's fog has to cover the cells the server's vision covers — a client
## that rounded differently would draw a lit disk one ring wider or narrower than
## the one it is actually being told about, and enemies would appear on ground
## the player is looking at as dark.
##
## Returns -1, not 0, for a range that sees nothing: `Vision._stamp` returns
## early on a non-positive range and stamps NOT EVEN the origin cell, while any
## positive range under one hex still floors to a radius-0 disk — which is the
## origin cell. Zero and nothing are different answers here, so `reveal` is told
## which one this is rather than being handed a 0 that means both.
static func radius_in_cells(for_space: TorusSpace, world_range: float) -> int:
	var cells := Vision._range_in_cells(for_space, world_range)
	if cells <= 0.0:
		return -1
	return floori(cells)
