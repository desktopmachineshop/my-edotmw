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

	## One byte per cell. 1 = this side has OBSERVED this cell, ever.
	##
	## A separate array from `believed`, and it has to be: `believed`
	## starts all-1 because unknown ground reads PASSABLE (the optimism
	## that makes a squad find out by walking), so "believed[c] == 1"
	## cannot distinguish "never seen" from "seen, and open". That is the
	## same currently-visible-vs-ever-revealed distinction D-026's hash
	## had to get right, and #120 names it as the input an explore order
	## needs.
	##
	## Accumulated HERE rather than in a new per-player field, because
	## this is already the object that folds sight into knowledge, on
	## vision's own cadence, out of vision's own coverage — a second fog
	## query is exactly what D-004 forbids. It costs one byte per cell per
	## side and one store inside a loop that was already running.
	var explored := PackedByteArray()

	## How many cells this side has changed its mind about, ever.
	var discoveries: int = 0

	## How many distinct cells this side has ever observed. Instrumentation
	## in `discoveries`' own style: zero on a map with squads on it means
	## the accumulation is dead.
	var explored_cells: int = 0

	func _init(cell_count: int) -> void:
		believed.resize(cell_count)
		believed.fill(1)
		explored.resize(cell_count)
		explored.fill(0)

	## Mark a cell observed. Separated from the passability write because
	## TOUCH (`learn`) discovers one cell without any coverage, and sight
	## (`observe`) covers cells whose passability it already agreed with —
	## both are observations, and only one of them changes `believed`.
	func see(cell: int) -> void:
		if cell < 0 or cell >= explored.size() or explored[cell] != 0:
			return
		explored[cell] = 1
		explored_cells += 1

	## Fold one rebuild's coverage into belief. Both directions: a cell
	## this side can see now is known now, which is what repairs a gate
	## that opened since it was last looked at.
	##
	## The loop lives here rather than in the caller so `believed` is a
	## direct member on every write — see this class's doc.
	func observe(coverage: Dictionary, truth: PackedByteArray) -> void:
		var know_ground := not truth.is_empty()
		for cell in coverage:
			var index := int(cell)
			if index >= believed.size():
				continue
			# SEEING a cell is seeing it, whatever this side knows about
			# the ground under it. Marked before — and independently of —
			# the passability half, because a sim with no terrain array at
			# all (every headless fixture, and any map yet to be
			# generated) still has fog, and an explore order on one would
			# otherwise be told the whole map is unexplored forever and
			# send every scout to the cell it is standing on.
			see(index)
			if not know_ground:
				continue
			var open: int = 1 if truth[index] != 0 else 0
			if believed[index] == open:
				continue
			believed[index] = open
			discoveries += 1

	func learn(cell: int, open: bool) -> bool:
		# Touch is an observation too — a squad with `vision_range` 0
		# learns only this way, and an explore order must not send it back
		# to ground it has already walked over.
		see(cell)
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


## What `group` has ever OBSERVED — one byte per cell, 1 = seen at least
## once. THE input an explore order picks its next destination from
## (#120): the currently-visible field answers "can I see it now", and a
## scout needs "have I ever been shown it".
##
## Empty when this side has never observed anything, which every caller
## must read as "nothing is explored" rather than indexing it.
func explored_cells(group: int) -> PackedByteArray:
	var side: Belief = _sides.get(group, null)
	if side == null:
		return PackedByteArray()
	return side.explored


## Whether `group` has ever observed `cell`. Out of range or unknown side
## reads FALSE — the opposite default from `believes_passable`, and
## deliberately so: unknown ground is optimistically passable (so a squad
## will walk into it) and pessimistically unexplored (so a scout will go
## and look at it). Both defaults push in the same direction.
func has_explored(group: int, cell: int) -> bool:
	var side: Belief = _sides.get(group, null)
	if side == null:
		return false
	if cell < 0 or cell >= side.explored.size():
		return false
	return side.explored[cell] != 0


## How many distinct cells `group` has ever observed. Instrumentation, in
## `discoveries`' style.
func explored_count(group: int) -> int:
	var side: Belief = _sides.get(group, null)
	return 0 if side == null else side.explored_cells


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
## `truth` empty means "no terrain in this sim" — which used to end the
## call. It no longer does: passability is unknowable without truth, but
## what each side has SEEN is not, and the explored set (#120) is fed from
## here. The size the belief arrays are built at then has to come from the
## space rather than from `truth`, which is why `cell_count` exists.
func absorb(vision: Vision, truth: PackedByteArray, cell_count: int = 0) -> void:
	if vision == null:
		return
	var size := truth.size() if not truth.is_empty() else cell_count
	if size <= 0:
		return
	var coverage := vision.coverage_by_group()
	for group in coverage:
		var side := _side_for(int(group), size)
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
