extends RefCounted
class_name BotNaval

## When a load-test bot's crew sails, and where (naval plan §6.3, #301
## stage 7).
##
## `bot_patrol.gd`'s sibling and its shape exactly: all-static and pure,
## so the half of the load test with the interesting failure mode is
## testable without a server. That file's own header gives the reason,
## and #69/#84 gave it teeth — both of `bot_client.gd`'s movement
## mechanisms were dead at once for a milestone, and the aggregate
## counters could not say so.
##
## ## What this is FOR
##
## `test-load`'s new naval gate is worth nothing unless a bot actually
## embarks and lands through the real wire. That is the whole argument of
## §6.3, and it is D-076's gap stated as a requirement rather than
## discovered later: a feature the estate cannot run is a feature nobody
## will notice breaking.
##
## ## Legs are EVENTS, not timestamps
##
## The same rule `bot_patrol.gd` had to learn (#69/#84,
## D-20260817-load-test-bots-must-manoeuvre): a leg ends when the thing
## it was waiting for HAPPENS — the crew is aboard, the hull is beside
## the far shore — with a timeout only as a backstop. Boundaries stated
## as wall-clock go stale the moment the opening, the map or the walking
## speed changes, and this project has re-learned that three times.


## The legs of a bot's crossing, in order.
enum Leg {
	ASHORE,    ## waiting for a hull to exist and be reachable
	BOARDING,  ## ordered aboard, waiting to actually be cargo
	AT_SEA,    ## aboard, ordered to the far shore
	LANDED,    ## put ashore; the crossing is done
}


## A leg that has made no progress for this long is abandoned and retried.
##
## A BACKSTOP, not the mechanism — see the header. Generous, because the
## thing it guards against is a bot silently wedged rather than a bot
## being slow, and a tight number here would make the gate flap on a
## loaded host exactly as `test-load`'s own timings have before.
const LEG_TIMEOUT := 45.0


## Whether a bot should try to cross at all.
##
## Deliberately the same question `AiNaval.needs_ships` asks, and asked
## the same way — off what the client KNOWS. A bot that crossed because
## the map file said "islands" would be exercising a code path no player
## can reach, and the gate built on it would prove nothing.
static func should_cross(land_labels: PackedInt32Array, home: int,
		enemy_cells: Array) -> bool:
	return AiNaval.needs_ships(land_labels, home, enemy_cells)


## The next leg, given what is true now.
##
## Pure: the same facts always give the same answer, and there is no
## per-bot state here for a stale leg to hide in. `elapsed` is how long
## the current leg has been running, and only ever sends a leg BACKWARDS
## — a timeout retries, it never advances.
static func next_leg(current: int, hull_ready: bool, aboard: bool,
		ashore_at_target: bool, elapsed: float) -> int:
	if ashore_at_target:
		return Leg.LANDED
	if aboard:
		# Already cargo: nothing that happens at sea can un-board a squad
		# short of the hull sinking, which removes the cargo with it
		# (§3.2) and is therefore not a leg this decides.
		return Leg.AT_SEA
	if current == Leg.BOARDING and elapsed < LEG_TIMEOUT:
		return Leg.BOARDING
	if hull_ready:
		return Leg.BOARDING
	return Leg.ASHORE


## Whether this leg has been stuck long enough to be worth reporting.
##
## Its own question rather than folded into `next_leg`, because the
## VERDICT needs to distinguish "no landing happened" from "no landing
## happened and here is the leg it died on". `landings = 0` is what a
## bot that never sailed, a broken transport and an unplayed match all
## report, and a gate that cannot tell them apart sends somebody reading
## the whole feature.
static func is_stuck(elapsed: float) -> bool:
	return elapsed >= LEG_TIMEOUT


## A human-readable name for a leg, for the per-bot log line.
##
## `test-load`'s own lesson: read the PER-BOT lines before any of the
## sums, because a total cannot say "one of them is not doing the thing"
## — which is what three of the five defects behind #69/#84 turned out to
## be.
static func leg_name(leg: int) -> String:
	match leg:
		Leg.ASHORE: return "ashore"
		Leg.BOARDING: return "boarding"
		Leg.AT_SEA: return "at-sea"
		Leg.LANDED: return "landed"
	return "unknown"
