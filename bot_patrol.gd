class_name BotPatrol
extends RefCounted

## Where a load-test bot's scouting detachment should be heading right now
## (D-20260817-load-test-bots-must-manoeuvre, #69/#84).
##
## `test-load`'s verdict asserts that fog was demonstrably exercised: a
## squad HIDDEN and a squad SHOWN AGAIN (D-026 criterion 9). A reveal needs
## a conceal AND a return, so it is the last fog criterion to be satisfied
## and the first to fail — and it failed on `main` for a day, because the
## bots had stopped manoeuvring at all. Both of `bot_client.gd`'s movement
## mechanisms were dead: the rally/recall pair was a ONE-SHOT scheduled at
## t=0 s and t=8 s, tuned before D-031 made the opening a single founding
## party, so it was spent on the founder while it walked off to build; and
## the raid alternation is unreachable, because a bot only ever builds a
## town centre, a town centre `produces` gatherers only, and every gatherer
## was claimed by the haul loop. The whole match was four bases quietly
## chopping wood, and `just test-load`'s server log says so plainly: four
## squads, eight flow fields and a byte-identical packet count from 20 s to
## 50 s.
##
## So this is the manoeuvre, extracted from the bot rather than left inside
## it. All-static and pure for the same structural reason `formation.gd`
## and `scoreboard.gd` are: there is nowhere to put per-bot state, so the
## half of the load test with the interesting failure mode is testable
## without an ENet host, a server, or two minutes of docker.
##
## The cycle is EVENT-DRIVEN, not scheduled. `bot_client.gd` used two
## absolute timestamps, and this project has now been bitten three times by
## a timing tuned against an opening that later changed (D-031's `4 40`,
## `test-client`'s 15 s default, and the rally pair above). A leg ends when
## something the bot can SEE has happened — the scout arrived — with a
## timeout only as a backstop for one that routed or cannot path.
##
## Both leg boundaries are stated in the WATCHER's terms, not the scout's.
## That is the non-obvious part and it is deliberate: what the verdict
## counts is the neighbour losing sight of the scout and finding it again,
## so "far enough out that they have lost me" is the actual condition, and
## "am I home yet" only approximates it. It stops approximating it at all
## on a tight pair — starts scatter at a minimum SPACING of 12 cells
## (D-039) and a town centre sees 11, so a scout sitting at its own base
## can be in plain view, and a withdrawal that ended there would conceal
## nothing on some pairs and everything on others. How tight the tightest
## pair is depends on the map and the seed, not on anything this file can
## see: 13 cells on the 84x96 default, 17 on the 168x194 one it doubled to
## the same day.


## How many squads a bot holds out of its economy to scout with, and the
## share of the army that may ever be spared. A bot's whole army is hauling
## crews, so scouting is paid for out of gathering and the split has to
## leave a majority working.
const SCOUTS_PER_BOT := 2
const MAX_SCOUT_SHARE := 2  # at most one in this many squads scouts


## How close a scout comes to what it is watching before turning around,
## in CELLS. Both bounds are real, against the shipped town centre
## (`buildings/town_centre.tres`) on the shipped map:
##
##   vision_range 20 world units / hex width sqrt(3) = 11.5 -> 11 cells
##   attack_range 12.1 world units / hex width sqrt(3) =  6.9 ->  6 cells
##
## 8 is inside the first and outside the second — deliberately near the
## middle of that band rather than at either end, because the cell a scout
## actually parks on is the post resolved through
## `SquadSim._approachable`, which can be a cell or two off if the computed
## one is water. Two cells clear of the guns, three inside the sight.
##
## So a scout is SEEN — which is what produces the conceal when it leaves —
## and is not SHOT, which is what lets it come back and produce the reveal.
## A crew is 5 men at 35 HP against 42 damage a shot, so a scout that
## walked onto the start would not return and the reveal half of the gate
## would stay unreachable for a brand new reason. `tests/test_bot_patrol.gd` asserts both bounds against
## the shipped resources rather than against this comment.
##
## It is a DESTINATION, not a distance to notice having reached — see
## `leg_target` for the measured reason, which cost a run to find.
const STANDOFF_CELLS := 8

## And how far back out, before turning around again. Comfortably past the
## 11 cells a town centre sees, with room for a hauling crew of theirs
## (10-unit sight, ~5 cells) to have wandered some way toward us — the
## watcher's coverage is a union, not one disk.
const WITHDRAW_CELLS := 20

## Backstop for a leg that never completes — a routed squad ignores player
## orders (D-024), and an unreachable destination is a thing a torus map
## can hand you. Generous: at the shipped gatherer's 3.4 world units/s
## (1.96 cells/s) this is ~90 cells of walking, further apart than any two
## starts on the shipped map.
const LEG_TIMEOUT_SECONDS := 45.0


## Split a bot's live army into the crews that work and the crews that
## scout.
##
## ONE function rather than two independent filters, because the defect
## this replaces was exactly two filters disagreeing: `_put_gatherers_to_work`
## claimed every crew it could carry with, and the raid pool then excluded
## everything it had claimed, so the pool was empty on every tick of every
## match. A split cannot leave a squad in both halves or in neither.
##
## `founding_squad` is excluded from both: it is walking off to plant a
## town hall, and a move order cancels a pending build (D-031 then consumes
## it). Pass -1 before the opening order has gone out.
static func assign(squads: PackedInt32Array, founding_squad: int) -> Dictionary:
	var available: Array = []
	for squad in squads:
		if squad != founding_squad:
			available.append(squad)
	var wanted := mini(SCOUTS_PER_BOT, available.size() / MAX_SCOUT_SHARE)
	var scouts: Array = []
	var workers: Array = []
	for i in range(available.size()):
		if i < wanted:
			scouts.append(available[i])
		else:
			workers.append(available[i])
	return {"scouts": scouts, "workers": workers}


## The cell the detachment is marching on for `leg`: even legs close on
## what we are watching, odd legs withdraw from it.
##
## Both are DESTINATIONS the standoff is already built into, rather than
## the neighbour's start with `leg_done` trusted to turn the scout around
## in time. That distinction was measured and it matters. A client samples
## its own squads off a clock it accumulates itself (`bot_client.gd`'s
## `now`, exactly as `client.gd` does), and the curve it samples was
## clipped to a one-second horizon by the replicator — so "where is my
## scout" is a second or so stale, which at 1.96 cells/s is two cells of
## overshoot. Two cells past a 9-cell standoff is 7, and the town centre
## shoots at 6. Measured on `test-load 4 120` with the standoff as a
## detection rather than a destination: casualties_applied 56 -> 164, one
## player eliminated, and `reveal_events` still 1, because the scouts were
## walking into the guns instead of coming home.
##
## A computed cell can be open water where a start cannot, which is why
## this was written the other way round first. It is safe anyway:
## `SquadSim._apply_move_order` resolves a destination nobody can stand on
## to the nearest cell they can, precisely so the four call sites that
## order a squad somewhere do not each have to.
static func leg_target(space: TorusSpace, leg: int, home: Vector2i,
		watching: Vector2i) -> Vector2i:
	if leg % 2 == 0:
		return observation_post(space, home, watching)
	return withdrawal_target(space, home, watching)


## Where a scout stands to watch: `STANDOFF_CELLS` short of what it is
## watching, on the wrapped line in from home.
static func observation_post(space: TorusSpace, home: Vector2i,
		watching: Vector2i) -> Vector2i:
	return _along(space, watching, home, STANDOFF_CELLS)


## Where a scout withdraws to: home, unless home is close enough to what it
## was watching that the watcher would still have it in view — in which
## case, far enough past home along the line away from them to be out of
## it.
##
## Without this the tightest pair on a map defeats the whole cycle. Two of
## the four starts a load test used on the 84x96 default were 13 cells
## apart against a town centre's 11 cells of sight, so a scout that
## withdrew to base sat one cell outside their vision at best and inside it
## at worst — and never produced the conceal the reveal depends on. That
## pair is 17 cells apart on the map that replaced it, which is still
## inside `WITHDRAW_CELLS`; the next map will be some other number.
static func withdrawal_target(space: TorusSpace, home: Vector2i,
		watching: Vector2i) -> Vector2i:
	if space == null:
		return home
	if space.distance(home, watching) >= WITHDRAW_CELLS:
		return home
	return _along(space, watching, home, WITHDRAW_CELLS)


## The cell `cells` away from `from`, on the wrapped line toward `toward`.
## Axial arithmetic through `TorusSpace` throughout — a straight line on a
## torus is a thing only `delta` knows how to find (D-008).
static func _along(space: TorusSpace, from: Vector2i, toward: Vector2i,
		cells: int) -> Vector2i:
	if space == null:
		return toward
	var offset := space.delta(from, toward)
	var apart := TorusSpace.hex_length(offset)
	if apart <= 0:
		return space.normalize(from)
	return space.normalize(from + space.round_axial(
		Vector2(offset) * (float(cells) / float(apart))))


## Whether this leg is over: the LEAD scout is where the leg wanted it, or
## it has been walking long enough that it plainly is not going to be.
##
## `scout_cells` is the detachment in order, and only the FIRST of them
## decides. That is the whole of this function's subtlety and it cost a
## load run to learn.
##
## Judging on whichever scout was nearest the current destination looks
## strictly more robust — one crew stuck in a lake cannot stall the cycle —
## and it THRASHES. With two scouts in different places, the one nearest
## the outward post has arrived at the very moment the one nearest the
## withdrawal point is still standing at base, so each leg is satisfied by
## a different squad the instant it begins and the cycle flips on every
## frame. Measured at `patrol_legs=1077` in a 120 s run, against 10 for the
## same code judging one squad.
##
## They are all given the same order, so one of them defines the cycle
## perfectly well, and `LEG_TIMEOUT_SECONDS` is what covers the lead being
## stuck — which is the case the other rule was reaching for.
static func leg_done(space: TorusSpace, scout_cells: Array, leg: int,
		watching: Vector2i, seconds_on_leg: float) -> bool:
	if seconds_on_leg >= LEG_TIMEOUT_SECONDS:
		return true
	if space == null or scout_cells.is_empty():
		return false
	var apart := space.distance(scout_cells[0], watching)
	if leg % 2 == 0:
		return apart <= STANDOFF_CELLS
	return apart >= WITHDRAW_CELLS
