extends RefCounted
class_name NodePlacement

## The queue of resource-node cells waiting to be DRAWN, and the per-frame
## budget that drains it (D-20260818-node-placement-is-budgeted).
##
## Growing a node cell is not cheap: `client.gd`'s `_place_node` samples the
## terrain, classifies the biome, classifies its SIX neighbours' biomes and
## then generates a stand of trees, each with its own terrain sample — 87 us
## per cell measured on the shipped map, 666 ms for all 7,664 of its nodes.
## Every cell the server revealed since the last frame used to be placed in
## the frame it arrived, so a squad cresting a hill into a wood paid the lot
## at once and dropped a frame.
##
## Same shape as D-040's flow-field fix, which is where the rule comes from:
## budget the WORK UNIT and keep partial progress, rather than doing a whole
## batch in one slice. A half-drawn forest is safe to look at — it is simply
## incomplete, and it completes over the next few frames.
##
## The budget counts CELLS, not milliseconds, deliberately. A wall-clock
## budget makes the amount of work done depend on how loaded the host is, so
## two runs of the same match draw different worlds; this project has already
## paid once for gating on milliseconds (D-106's amendment) and the rule that
## came out of it — assert WORK, not time — applies to spending it too.
##
## Holds only the WAITING set. What has actually been drawn is
## `client.gd`'s `_node_placed`, which owns the scene-tree record for each
## cell, and what is KNOWN is `ClientState.nodes`. Three sets, one owner
## each: the defect this file replaces guarded placement with
## `_state.nodes.size() != _node_placed.size()`, a size comparison standing
## in for set equality, which a budget makes actively wrong — placed lags
## known by construction now.


## How many cells to draw per frame. 24 x 87 us is ~2 ms of a 16.7 ms frame,
## which leaves room for the rest of the client at the scale M10 is aiming
## at; a reveal of 300 cells finishes in a fifth of a second rather than in
## one 26 ms hitch.
const PER_FRAME := 24

## Cell index -> true, in reveal order. A Dictionary rather than an Array
## because a cell felled before it was ever drawn has to leave the queue
## O(1) (see `forget`), and GDScript Dictionaries keep insertion order, so
## it is still a queue.
var _pending := {}


## The server revealed these cells (`ClientState.take_revealed()`). Already
## queued cells collapse, so a re-send cannot make a cell wait twice.
func reveal_all(cells: Array) -> void:
	for cell in cells:
		_pending[int(cell)] = true


## The next slice to draw, at most `budget` cells, oldest reveal first. The
## returned cells leave the queue: the caller draws them this frame.
func take(budget: int) -> Array[int]:
	var out: Array[int] = []
	if budget <= 0:
		return out
	for cell in _pending:
		out.append(int(cell))
		if out.size() >= budget:
			break
	# Erasing inside the loop above would invalidate the iteration.
	for cell in out:
		_pending.erase(cell)
	return out


## This cell is no longer anything to draw — worked out before its turn came
## up. Without this a queued cell would still be drawn (a stand of trees on a
## stump), and the server sends no second depletion event to take it back
## down: the felling was reported once, for a tree this client had not got
## round to growing.
func forget(cell: int) -> void:
	_pending.erase(cell)


## Nothing is waiting. Distinct from "nothing is known" — used by the
## sandbox readout to say whether the world has caught up with the wire.
func is_settled() -> bool:
	return _pending.is_empty()


func pending_count() -> int:
	return _pending.size()


## A match ended: the scene tree that would have drawn these is going away.
func clear() -> void:
	_pending.clear()
