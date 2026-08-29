class_name ExploreTarget
extends RefCounted

## Where a squad hunting fog should go next (#120).
##
## THE one definition of "pick the next unexplored destination", so the
## player's explore order and a future AI scouting behaviour cannot come
## to disagree about what exploring means (D-051 holds an AI to every
## rule a human is; two pickers would be two rules).
##
## All-static and pure, for the same structural reason `formation.gd`,
## `bot_patrol.gd` and `battle_line.gd` are: the half of this feature with
## the interesting failure mode is the CHOICE, and a choice that needs a
## server, a socket and a scene tree to exercise is a choice nobody
## tests. Everything it reads is an argument.
##
## ## It is not omniscient, and that is the whole design (#120 point 1)
##
## An explore that steers by the true map is a maphack wearing a UI —
## #96's defect in a more dangerous form, because here the SIMULATION
## picks the destination rather than a player clicking one. So the only
## map data this file ever sees is the asking side's own:
##
## - `explored` is `TerrainKnowledge.explored_cells(group)` — what this
##   SIDE has observed, ever. Keyed by side because allies share sight
##   (D-050), which is also why an ally revealing your target is a
##   legitimate reason to repick.
## - `believed_passable` is that same side's belief about the ground,
##   which is OPTIMISTIC: unknown ground reads passable
##   (D-20260818-pathing-knows-only-what-the-player-knows). A scout is
##   therefore free to set off toward a bay it has never seen and find
##   out it is water by walking — which is exactly the behaviour that
##   decision wants, and the reason this file must not consult truth to
##   "save" it the trip.
##
## There is no argument here through which ground truth could arrive.
##
## ## Targets are REGIONS, because flow fields are shared (#120 point 2)
##
## D-007's per-destination sharing is the scaling claim, and N scouts each
## demanding their own unique frontier CELL is its pathological case: N
## destinations, N fields, on a map where a squad already waits for a path
## (#107). So a target is snapped to a coarse grid exactly as a rout's is
## (`SquadSim.rout_quantum`, D-038) and for the identical reason — nobody
## chose the exact cell, so precision there is worth nothing and sharing
## is worth a lot.
##
## The snap is bounded by the quantum, which is chosen well inside a
## scout's vision radius: the squad arrives at the region and can SEE the
## frontier it was aimed at, even though it did not stand on it.
##
## ## Cost
##
## One pass over REGIONS, not cells — `(width/q) * (height/q)`, so 2,058
## on the shipped 168x194 map at quantum 4 against 32,592 cells. It runs
## when a squad REPICKS (arrival, or its target stopped being unknown),
## never per tick per squad, and `SquadSim` charges it to its own phase
## so it cannot hide in the residual (D-20260818).
##
## The scan is deliberately whole-map rather than an expanding ring: a
## ring terminates early in the common case and degenerates to a
## `disk_offsets` table the size of the map when the frontier is far,
## which is both the expensive case AND the one a late-game scout is
## always in.


## Nothing worth exploring — returned as the squad's own cell, so a caller
## that ignores the distinction simply orders a squad to stand still.
## `SquadSim` checks it explicitly and leaves the squad idle in explore
## mode, ready to pick again if an ally's map changes or a gate opens.
static func nothing() -> Vector2i:
	return Vector2i(-1, -1)


## The next place this squad should go to uncover ground.
##
## `claimed` maps an already-taken region's cell INDEX to anything, and is
## how two scouts of the same side stop walking to the same fog. It is
## supplied by the caller rather than remembered here — this file holds no
## state, and the sim already knows every squad's destination.
##
## Returns `nothing()` when this side has seen everything it can reach an
## opinion about.
static func next_destination(space: TorusSpace, explored: PackedByteArray,
		believed_passable: PackedByteArray, from: Vector2i, quantum: int,
		claimed: Dictionary = {}) -> Vector2i:
	if space == null:
		return nothing()
	var step: int = maxi(1, quantum)
	# A side that has observed NOTHING has an empty array rather than a
	# zeroed one (see TerrainKnowledge.explored_cells). Everything is
	# unexplored in that case, which is the correct reading and needs no
	# special path below — `_is_explored` answers false for it.
	var best := nothing()
	var best_distance := -1
	var origin := space.normalize(from)

	# Region representatives, scanned in a fixed order so two sims given
	# the same inputs choose the same cell. Determinism matters here for
	# the ordinary reason it matters everywhere in this project: the
	# server is authoritative and a replay must reproduce (D-016).
	for r in range(0, space.height, step):
		for q in range(0, space.width, step):
			var cell := Vector2i(q, r)
			var index := space.index(cell)
			if claimed.has(index):
				continue
			if _is_explored(explored, index):
				continue
			# Believed-blocked ground is not worth walking to even though
			# it is unseen — the side has already been shown it is a
			# mountain. Unknown ground reads passable here, so this
			# rejects only what has actually been observed and refused.
			if not _believes_passable(believed_passable, index):
				continue
			# Toroidal, via TorusSpace and nothing else (D-008): the
			# nearest fog across the seam is nearer than fog the long way
			# round, and a scout that walked the long way round would be
			# the seam bug this project keeps paying for.
			var d := space.distance(origin, cell)
			if best_distance == -1 or d < best_distance:
				best_distance = d
				best = cell
	return best


## True when this side has observed the cell. An EMPTY array means "this
## side has observed nothing", not "index out of range" — see
## `TerrainKnowledge.explored_cells`.
static func _is_explored(explored: PackedByteArray, index: int) -> bool:
	if index < 0 or index >= explored.size():
		return false
	return explored[index] != 0


## Optimism, matching `TerrainKnowledge.believes_passable` exactly: an
## empty or short array means this side has no opinion, and no opinion
## means passable.
static func _believes_passable(believed: PackedByteArray, index: int) -> bool:
	if index < 0 or index >= believed.size():
		return true
	return believed[index] != 0
