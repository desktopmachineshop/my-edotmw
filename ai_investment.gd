extends RefCounted
class_name AiInvestment

## When an AI spends on a capability it has not got yet, what it costs,
## and which step of getting it is next (#365, reconciling #337's walls
## and #301 stage 7's navy).
##
## ## Why this file is one file
##
## Two workers were each told to share "the AI invests in static defence"
## machinery and, unable to see each other's trees, built it twice on the
## same day: `static_defence.gd` (#348) and this file's first version
## (#342). Gap I4 of `docs/plans/gap-assessment-2.md`, and the third-party
## reconciliation is `decisions/D-20260828-one-ai-investment.md`.
##
## Neither was wrong, and neither was sufficient — they had answered
## DIFFERENT HALVES of the question and each assumed the other half was
## the easy part:
##
## | | #348 `StaticDefence` | #342 `AiInvestment` |
## |---|---|---|
## | is now the moment? | a measured pressure model | a boolean trigger |
## | how readily? | appetite as a threshold on the case | `commitment > 0` |
## | can I pay? | reserve, price, scarcest shortfall | — |
## | what is next? | — | ordered steps, progress, share |
##
## So the merge is not a coin flip between two designs; it is one
## mechanism with both halves, and the SPLIT it needed — the case is the
## domain's, the threshold is shared — is what neither had. See
## `wants_to_invest`.
##
## ## What it deliberately is not
##
## Not a planner, a goal stack or a behaviour tree. It answers three
## questions from what the caller supplies — is there a case, can I pay,
## which step is next — and holds no state. Everything clever stays in
## the caller, where it can be read beside the rest of that feature's
## reasoning; the alternative is a framework that has to be understood
## before either feature can be.
##
## **Nothing here names a wall, a gate, a tower, a dock, a ship or the
## sea**, and `tests/test_ai_investment.gd` enforces that with a source
## scan, because "this file knows nothing about walls" is not something a
## behavioural test can see. The geometry lives with the feature
## (`wall_plan.gd`, `ai_naval.gd`).
##
## All-static and pure, like `bot_build_plan.gd` and `bot_patrol.gd`, for
## the same structural reason: there is nowhere to put per-seat state, so
## the half of an AI with the interesting failure mode is testable without
## a server, a socket or five minutes of docker.
##
## ## The rules, and what each is protecting against
##
## Every one of these exists because the OPPOSITE is a way to ship a
## broken opponent, and two of them are measured rather than argued.

## Fortifying before there is an army is a loss, not a trade.
##
## Measured on `main` at the time of writing: a ladder seat builds
## **exactly two buildings in a 300 s match** — its town centre and its
## barracks — and a 1v1 hits the time cap with neither side attacking.
## The barracks is what turns an economy into a player (D-053's own
## reasoning), and a wall bought instead of one is a wall the enemy walks
## round on their way to an undefended town.
##
## So: nothing static until something that TRAINS is standing. This is the
## precondition, not a weighting — no appetite, however high, buys past
## it.
const NEEDS_A_MILITARY_BUILDING := true

## The FLOOR on how near a hostile has to be before its presence is a
## reason to fortify rather than to chase it.
##
## A floor rather than the answer, because "near" is relative to how far
## apart the starts are: on the shipped ladder map two seats are further
## apart than any fixed radius, so a flat number contributed exactly
## nothing to every case ever computed. Callers pass their own horizon
## (`threat.horizon`) and this is the minimum it can be.
##
## Still a constant rather than a profile field: this is a bound on a
## FAILURE, and a difficulty setting able to make an AI fortify against
## somebody it saw once, forever, is a way to ship a broken opponent by
## data entry. `ai_profile.gd` draws the same line for `FOUND_RETRY`.
const THREAT_CELLS := 22

## An AI holds back this much of each floor for the economy before it
## spends on defence, on top of the price itself.
##
## Without it, the first spare 40 stone goes into a wall segment and the
## barracks queue stops — which is the same "bought the cheap thing
## because it could not afford the important one" failure `ai_player.gd`
## records for the storehouse.
const RESERVE_SHARE := 0.5

## What KNOWING WHERE THE ENEMY IS is worth, on its own.
##
## This is the term the first version did not have, and leaving it out is
## why that version never fired in a real match. It modelled fortifying as
## a response to being HIT — so the only seat with a case was the one
## already losing, which by then had no barracks and so failed the
## precondition. Measured over two 300 s and one 420 s ladder run:
## `defences_ordered=0` on every seat, while one of them reported
## `buildings_lost=2 attacks_survived=43`.
##
## Players do not wall when they are bleeding. They wall when they know
## who their neighbour is and intend to hold ground. Contact is therefore
## a case in itself, and everything above it is urgency.
##
## The value is chosen so that contact ALONE clears the shipped default
## appetite and nothing lower: the default opponent fortifies on contact,
## a more defensive profile sooner and on less, a more aggressive one only
## under real pressure. That is a statement about what a difficulty MEANS,
## not a number fitted to make a gate pass — and the difference matters
## the next time somebody moves it.
##
## (Stated without naming a profile, because no `.gd` may:
## `tests/test_ai_profiles.gd` scans for the ids and does not strip
## comments, and that guard caught this comment's first draft. Which is
## the guard working — the same rule that makes adding a fourth
## difficulty a `.tres` and not a code change.)
const CONTACT_CASE := 0.5


## The case for spending on static defence right now, as 0.0 to 1.0.
##
## `threat` and `economy` are plain dictionaries so that a land caller and
## a naval one can each supply what their domain knows without either
## learning the other's types. Missing keys read as "no evidence", which
## is the safe direction: an absent key can only ever LOWER the pressure,
## so a caller that has not been taught to report something new does not
## start fortifying because of it.
##
## Keys read from `threat`:
##   `hostiles_near`      hostile squads within THREAT_CELLS of home, now
##   `nearest_hostile`    cells to the nearest KNOWN hostile thing, -1 unknown
##   `buildings_lost`     own buildings destroyed so far this match
##   `attacks_survived`   times an own building has taken damage
##
## Keys read from `economy`:
##   `military_buildings` own buildings that train something
##   `army_squads`        own squads that are not haulers
static func threat_pressure(threat: Dictionary, economy: Dictionary) -> float:
	if NEEDS_A_MILITARY_BUILDING and int(economy.get("military_buildings", 0)) <= 0:
		return 0.0

	var case := 0.0

	# Contact. Knowing where an enemy base is means being in a war with
	# somebody, and that is the ordinary reason a player fortifies.
	if bool(threat.get("enemy_base_known", false)):
		case += CONTACT_CASE

	# Somebody is HERE. The strongest evidence there is, and the only one
	# that does not depend on remembering anything.
	var near := int(threat.get("hostiles_near", 0))
	if near > 0:
		case += minf(0.4, 0.2 * float(near))

	# Somebody is close enough to arrive, measured against the caller's
	# own horizon rather than a fixed radius — see THREAT_CELLS.
	var horizon := maxi(THREAT_CELLS, int(threat.get("horizon", 0)))
	var nearest := int(threat.get("nearest_hostile", -1))
	if nearest >= 0 and nearest <= horizon:
		case += 0.3 * (1.0 - float(nearest) / float(horizon))

	# It has already cost me something. Buildings are persistent-explored
	# (D-030) and losses do not un-happen, so this only ever grows — which
	# is right: a player who has been raided once should stay fortified.
	case += minf(0.3, 0.15 * float(threat.get("buildings_lost", 0)))
	case += minf(0.2, 0.1 * float(threat.get("attacks_survived", 0)))

	# An army in the field is the alternative use of the same wallet, and
	# a big one is a reason to spend LESS on things that cannot chase.
	# Bounded well under CONTACT_CASE, deliberately: a dominant player
	# should build fewer walls, not become unable to build any.
	var army := int(economy.get("army_squads", 0))
	case -= minf(0.2, 0.02 * float(army))

	return clampf(case, 0.0, 1.0)


## Whether to spend, given a CASE for it, how readily this opponent
## invests (`appetite`, 0.0 = never, 1.0 = at the first sign) and how much
## is standing already.
##
## THE RECONCILIATION IS THIS SIGNATURE (#365). Both original designs got
## half of it:
##
## - `StaticDefence.wants_to_invest` computed the case ITSELF from a
##   threat report, so the only investment it could gate was a defensive
##   one. A naval caller would have had to describe "there is an enemy I
##   cannot walk to" as a threat, which it is not.
## - `AiInvestment.should_invest(wanted, commitment)` took a BOOLEAN
##   trigger, so it could gate anything and could express nothing:
##   no degrees, no cap, and a knob that had to mean "never/always" at
##   the same time as meaning "how much".
##
## Splitting the CASE from the THRESHOLD is what lets one mechanism serve
## both. The domain computes its own case — `threat_pressure` for
## something that cannot chase, reachability for something across water —
## and this decides whether it is enough. Neither original had that split,
## which is why neither could actually be the other's caller.
##
## `standing`/`cap` bound the investment: a wall is a means and the army
## is the end, so an AI that kept building while the pressure stayed high
## would fortify itself out of the match. **A `cap` of 0 means the
## investment is not counted in standing things at all** — a plan of
## steps (dock, hull, embark, landing) is finished by its last step rather
## than by a number, and `next_step` is what ends it.
static func wants_to_invest(case: float, appetite: float,
		standing: int, cap: int) -> bool:
	if appetite <= 0.0:
		return false
	if cap > 0 and standing >= cap:
		return false
	# A case of ZERO is not a small case, it is no case — and without this
	# line an appetite of 1.0 buys a wall against nobody, because
	# `0.0 >= 1.0 - 1.0` is true. Found by the test that says a
	# precondition is a precondition rather than a weighting, which is
	# what an observed-to-fail guard is for.
	if case <= 0.0:
		return false
	# Appetite is HOW MUCH OF THE CASE this opponent needs before it acts:
	# 1.0 invests at the first sign, 0.5 wants half a case, 0.0 never.
	# Monotone in both arguments and statable in one sentence, which the
	# first version was not — it was an arithmetic knot that happened to
	# produce plausible numbers, and a threshold nobody can state is a
	# threshold nobody can tune.
	return case >= 1.0 - appetite


## Whether `wallet` can pay `cost` and still leave the economy its floors.
##
## The floors are the caller's (`AiProfileDef.food_floor`/`wood_floor` for
## the AI), and only a SHARE of them is held back: holding the whole floor
## means never fortifying at all, because the floor is where the economy
## is trying to sit rather than a surplus it climbs above.
##
## `cost` and `wallet` are indexed by `Economy.ResourceKind`, which is the
## order every wallet in this project uses.
static func can_afford_with_reserve(wallet: PackedInt32Array,
		cost: PackedInt32Array, floors: PackedInt32Array) -> bool:
	if wallet.size() < Economy.RESOURCE_COUNT or cost.size() < Economy.RESOURCE_COUNT:
		return false
	for i in range(Economy.RESOURCE_COUNT):
		var reserve := 0
		if i < floors.size():
			reserve = int(round(float(floors[i]) * RESERVE_SHARE))
		if wallet[i] < cost[i] + reserve:
			return false
	return true


## A building's price as a wallet-shaped array, so callers do not each
## write out the same four fields in the same order.
static func cost_of(def: BuildingDef) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Economy.RESOURCE_COUNT)
	if def == null:
		return out
	out[Economy.ResourceKind.FOOD] = def.cost_food
	out[Economy.ResourceKind.WOOD] = def.cost_wood
	out[Economy.ResourceKind.GOLD] = def.cost_gold
	out[Economy.ResourceKind.STONE] = def.cost_stone
	return out


## Which resource a player is SHORT of for `cost`, or -1 if it can pay.
##
## This is the half #337 turned out to hinge on, and it is worth saying
## why it lives in the shared file rather than in the walls one.
##
## Every wall, gate and tower in the roster costs STONE, and the AI's
## resource priorities were a fixed list of food and wood — so the whole
## stone half of the economy was unreachable to it and every static
## defence in the game was unaffordable forever. Measured: a ladder seat
## builds exactly two buildings in a 300 s match. Naval's docks and shore
## defences will hit the identical wall the moment stage 7 asks for one,
## because a dock is another building whose price is not food.
##
## So the rule is: an AI gathers what its NEXT PURCHASE costs. Returning
## the scarcest shortfall rather than the first makes a two-resource price
## converge instead of alternating.
static func scarcest_shortfall(wallet: PackedInt32Array,
		cost: PackedInt32Array) -> int:
	var worst := -1
	var gap := 0
	if wallet.size() < Economy.RESOURCE_COUNT or cost.size() < Economy.RESOURCE_COUNT:
		return -1
	for i in range(Economy.RESOURCE_COUNT):
		var short := cost[i] - wallet[i]
		if short > gap:
			gap = short
			worst = i
	return worst


# --- what getting it takes, and how much of the army it claims -----------
#
# #342's half, unchanged except that `should_invest` is gone: it is
# `wants_to_invest` above with the case fixed at 1.0 and no cap, and two
# functions answering one question is what #365 exists to end.

## A step of an investment. `done` is a Callable taking no arguments and
## returning bool — "is this already true?" — and `act` is what to do
## when it is not.
##
## `label` is not decoration: it is what the harness counts and what a
## human reads when a gate reports which leg broke. `landings = 0` is
## what a free-for-all, an unplayed match and a broken transport all
## report, so the step names are how a zero says WHICH.
static func step(label: String, done: Callable, act: Callable) -> Dictionary:
	return {"label": label, "done": done, "act": act}


## The first step that is not done yet, or an empty Dictionary when the
## investment is complete.
##
## In ORDER, and short-circuiting: an AI that trained a transport before
## it had a dock to train it from would spend the money and get nothing.
## The order is the plan.
static func next_step(steps: Array) -> Dictionary:
	for entry in steps:
		var done: Callable = entry["done"]
		if not done.call():
			return entry
	return {}


## How far through an investment the AI has got, for the stats line.
##
## Reported rather than merely used, because "the AI is doing nothing"
## and "the AI is stuck on step 2" look identical from outside — and
## D-076's gap was invisible for sixteen days precisely because nothing
## reported it.
static func progress(steps: Array) -> int:
	var done_count := 0
	for entry in steps:
		var done: Callable = entry["done"]
		if not done.call():
			break
		done_count += 1
	return done_count


## How many of `available` squads this investment may claim.
##
## Rounded DOWN, with a floor of ONE whenever the commitment is above
## zero: an investment allowed to take a fraction that rounds to zero is
## an investment that reports itself active and never moves, which is the
## shape of every silent AI gap this file exists to prevent.
##
## Zero commitment is the one case that returns zero, and it has to be
## checked HERE rather than left to the caller. The first version said
## "a caller that wants none never reaches here" and `AiNaval.sailing_party`
## reached here with 0.0 on its very first test — a profile that had
## declined to sail put one squad to sea anyway. The rule and the
## guard belong in the same function.
static func share_of(available: int, commitment: float) -> int:
	if available <= 0 or commitment <= 0.0:
		return 0
	return clampi(int(floor(float(available) * clampf(commitment, 0.0, 1.0))), 1, available)
