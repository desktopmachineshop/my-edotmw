extends RefCounted
class_name TerrainKnowledge

## What one SIDE believes the ground to be, and therefore what its squads
## are allowed to path through
## (D-20260818-pathing-knows-only-what-the-player-knows).
##
## The rule this file exists to make structural: **the simulation may
## never route, or refuse to route, a squad using terrain its owner has
## not discovered.** Flow fields were solved against the sim's single
## ground-truth passability array, so a squad ordered across the map
## rounded lakes and mountain ranges nobody had ever seen, and an order
## into an unexplored pocket that happened to be sealed was refused on the
## tick it was given — both from data the player does not have.
##
## ## Belief is OPTIMISTIC, and that is the whole design
##
## One byte per cell per side: 0 means "this side has observed that cell
## and it is blocked", non-zero means anything else — known open, or never
## looked at. Unknown ground therefore reads PASSABLE, which is what makes
## a squad take the shortest route it has no reason to doubt, walk into
## the truth, and re-plan. Fog can be hiding a ramp; the honest answer to
## "is there a way through" is "try it".
##
## That gives the invariant every refusal downstream leans on:
##
##     believed-passable ⊇ truly-passable
##
## so **belief-unreachable implies truly-unreachable** — a side can only
## ever be refused an order that was genuinely impossible, never one that
## would have worked. Erring the other way is the failure mode the owner
## called out as the noticeable one: marching somewhere and finding a dead
## end is a mistake a player understands making, being told "no" about
## ground they cannot see is not.
##
## The one seam in that invariant is passability that CHANGES: a gate
## (D-076) seen closed and later opened out of sight stays believed-shut
## until somebody looks again. That is fog behaviour rather than a bug —
## the client still draws the structure it last saw (D-030) — and
## `observe()` repairs it in BOTH directions the moment the cell is
## covered again, so a side is never wrong about ground it can currently
## see.
##
## ## Keyed by SIDE, not by player
##
## Allies share sight (D-050), so they share belief: the key is
## `Vision.group_of_player`, the same grouping `Vision` stamps coverage
## into, because two definitions of "who knows what" would eventually
## disagree and the symptom would be an ally's army pathing differently
## from yours through the same explored ground.
##
## ## Cost
##
## `absorb()` walks the coverage `Vision` has already stamped — no second
## disk scan — and the per-cell work is two packed-array reads and a
## compare, inside the `Belief` class so the byte write is in place (see
## `Belief.observe`). A side with nothing known holds no array at all and
## `believed_passable()` returns empty, which `FlowField` reads as "fully
## open": a bare sim with no terrain pays literally nothing.


## One side's belief.
##
## Named `Belief` rather than the more natural `Side` because Godot has a
## built-in `Side` enum (SIDE_LEFT and friends) and an inner class of that
## name shadows it into a parse error several files away.
##
## A class rather than a bare `PackedByteArray` in the dictionary because
## packed arrays are copy-on-write VALUE types in GDScript: a caller that
## fetched one out of `_sides`, wrote a cell and dropped it would silently
## mutate a copy and lose the discovery. Held as a member and written only
## from methods of this class, the write is in place and cannot be lost.
class Belief:
	## One byte per cell. 0 = this side has seen that this cell is blocked.
	var believed := PackedByteArray()

	## How many cells this side has changed its mind about, ever.
	var discoveries: int = 0

	func _init(cell_count: int) -> void:
		believed.resize(cell_count)
		believed.fill(1)

	## Fold one rebuild's coverage into belief. Both directions: a cell
	## this side can see now is known now, which is what repairs a gate
	## that opened since it was last looked at.
	##
	## The loop lives here rather than in the caller so `believed` is a
	## direct member on every write — see this class's doc.
	func observe(coverage: Dictionary, truth: PackedByteArray) -> void:
		for cell in coverage:
			var index := int(cell)
			if index >= believed.size():
				continue
			var open: int = 1 if truth[index] != 0 else 0
			if believed[index] == open:
				continue
			believed[index] = open
			discoveries += 1

	func learn(cell: int, open: bool) -> bool:
		var value: int = 1 if open else 0
		if cell < 0 or cell >= believed.size() or believed[cell] == value:
			return false
		believed[cell] = value
		discoveries += 1
		return true


var _sides := {}

## Cells any side has changed its mind about, ever. Instrumentation, in
## the style of `SquadSim.field_waits`: if this is zero in a match with
## terrain then nothing is being discovered and the whole mechanism is
## dead code, which is precisely the failure this project keeps finding.
var discoveries: int = 0


## What `group` may plan a route through — the array `FlowField.begin`
## wants. Empty when this side has never observed a blocked cell, which
## `FlowField` reads as "every cell passable": correct by construction,
## since a side that knows nothing believes everything.
func believed_passable(group: int) -> PackedByteArray:
	var side: Belief = _sides.get(group, null)
	if side == null:
		return PackedByteArray()
	return side.believed


func believes_passable(group: int, cell: int) -> bool:
	var side: Belief = _sides.get(group, null)
	if side == null:
		return true
	if cell < 0 or cell >= side.believed.size():
		return true
	return side.believed[cell] != 0


## Fold every side's current sight into its belief.
##
## Reads the coverage `Vision.rebuild` has just stamped rather than
## re-walking the disks, so this costs one pass over cells somebody is
## already looking at. `truth` empty means "no terrain in this sim", and
## then there is nothing to know.
func absorb(vision: Vision, truth: PackedByteArray) -> void:
	if vision == null or truth.is_empty():
		return
	var coverage := vision.coverage_by_group()
	for group in coverage:
		var side := _side_for(int(group), truth.size())
		var before := side.discoveries
		side.observe(coverage[group], truth)
		discoveries += side.discoveries - before


## Discovery by TOUCH: `group` has just tried to put a squad on `cell` and
## found out what it is. Returns true if this changed anything.
##
## The safety net under the whole scheme, and not merely a nicety — a unit
## with no vision at all (`vision_range` 0) would otherwise never learn
## anything, and a squad must never actually stand in a mountain however
## optimistic its plan was.
func discover(group: int, cell: int, open: bool, cell_count: int) -> bool:
	if cell_count <= 0:
		return false
	var side := _side_for(group, cell_count)
	if not side.learn(cell, open):
		return false
	discoveries += 1
	return true


func _side_for(group: int, cell_count: int) -> Belief:
	var side: Belief = _sides.get(group, null)
	if side != null and side.believed.size() == cell_count:
		return side
	side = Belief.new(cell_count)
	_sides[group] = side
	return side
