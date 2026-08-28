extends RefCounted
class_name AiPlayer

## A computer opponent occupying a lobby seat (D-051).
##
## ## It cannot see through fog, structurally
##
## The AI does not read `SquadSim`. It holds a real `ClientState`, and the
## server feeds it the **same packets a human client receives**, through
## the same `_replicate()` loop and the same `visible_to(player)` gate
## (D-025). Its knowledge is therefore a subset of its vision by
## construction rather than by promise — there is no code path by which it
## could learn about a squad the server did not send it.
##
## That is the same reasoning that made `bot_client.gd` drive the real
## `ClientState`: a stand-in can pass while the thing itself is broken.
## Here the stakes are higher, because an AI that quietly saw everything
## would not look like a bug. It would look like a good AI.
##
## ## Its orders go through the same door too
##
## Decisions become real `NetProtocol` packets handed to the server's own
## dispatcher, so every rule a human is held to — ownership read from the
## sim, the squad cap, affordability, the match being running — applies
## unchanged. An AI that called into the simulation directly could do
## things no human could, and nobody would notice until they wondered why
## it never ran out of food.
##
## ## What this is not
##
## Not a good AI. It founds a town, gathers, trains, and attacks what it
## can see. It is a real opponent rather than a scripted demo, and it is
## deliberately simple: D-046 makes AI players a shipped feature, so this
## is the floor to build on, not the ceiling.

## How this seat plays: the intervals and thresholds that used to be
## constants here (D-20260818-ai-profiles-are-data).
##
## Three of them carried a comment promising they would "become a profile
## field in the next slice (D-053)" for two milestones — and D-053 was
## never written. This is that slice. The rationale for each number moved
## to `ai_profile.gd` with the field; what is left here is the reading.
##
## Never null: the schema's defaults are the constants this file used to
## hold, so an AI seated before /ai is readable plays exactly the AI that
## shipped rather than crashing on its first think.
var profile: AiProfileDef = AiProfileRoster.default()

var player: int = 0
var civ: StringName = &""
var state := ClientState.new()

## Sandbox mode's "economy only" toggle (dev testing), set by server.gd
## from MatchState.ai_economy_only at seating and updated live on every
## later toggle. Town-founding, building, training and gathering are
## unaffected; only `_fight` is skipped, and `_train` is held to
## "gatherers" so an economy-only AI never quietly stockpiles an idle
## army it will never use either.
var economy_only: bool = false

## Where this AI's orders go. Set by the server to its own dispatcher, so
## a packet from here takes the identical path to one off the wire.
var send: Callable = Callable()

var _next_think := 0.0
var _found_at := 0.0
var _attack_at := 0.0
var _train_at := 0.0


func _init(p_player: int = 0, p_civ: StringName = &"") -> void:
	player = p_player
	civ = p_civ


## Called once per server tick. Returns immediately unless it is time to
## think, so the cost of an AI seat is a float comparison on most ticks.
func update(now: float) -> void:
	if now < _next_think or not send.is_valid():
		return
	_next_think = now + profile.think_interval

	# Nothing at all until the match is actually running.
	#
	# The server ticks AI seats from the moment they are created, which in a
	# no-lobby match (`--ai=n`) is before anybody has connected and while the
	# match is still in Phase.LOBBY. `_found_town` therefore fired on the
	# FIRST tick, `server._validated_squad` dropped the order on its
	# not-running guard without a word, and the AI — which latched on the
	# SEND — spent its one founding attempt into a closed door and sat on its
	# founding party for the rest of the game. Every match against AI
	# opponents, on every map, was against opponents that did nothing.
	#
	# Read from this AI's own ClientState rather than from the server, which
	# is the whole of D-051: an AI knows what a client in its seat knows, and
	# a client is told the phase (S2C_LOBBY, D-048). Nothing here reaches for
	# a fact a human player could not have.
	if not match_running():
		return

	_record_stats()
	_report_refusals()
	_forget_dead_assignments()
	_drop_unreachable_assignments()
	_scout_for_what_it_lacks()
	_found_town()
	_raise_buildings()
	_research(now)
	_fortify()
	_hold_the_gates()
	_train()
	_put_gatherers_to_work()
	if not economy_only:
		# Before `_fight`, deliberately: the raid pool is what sails, and
		# an AI that spent it marching at an enemy it cannot walk to
		# would never have a squad free to board.
		_go_to_sea()
		_fight(now)


## Whether this AI's own client believes the match has begun.
##
## `welcomed` alone is not enough: a client in a lobby is welcomed too
## (server.gd sends one with no squads so the HUD has a map size), so the
## phase has to come from the lobby message. `in_lobby()` answers false
## when no seat list has arrived at all, which is the right default — a
## seatless AI is a test fixture, not a lobby.
func match_running() -> bool:
	return state.welcomed and not state.in_lobby()


## Put up the buildings the AI needs to exist as an opponent (D-053).
##
## Without this it is an economy simulator: the town centre's `produces`
## list is gatherers only, so every request for a military archetype is
## refused server-side and it never fields a soldier in any match. The
## ladder's first baseline showed exactly that — workers == squads,
## attacks == 0, across every run.
##
## Wants are read from the shipped BuildingDefs rather than named here, so
## a building added as a .tres is something the AI can learn to build
## without touching this file — the same rule that keeps it civ-agnostic
## (D-047).
func _raise_buildings() -> void:
	var builder := _idle_builder()
	if builder < 0:
		return

	for def in _wanted_buildings():
		if _owned_building_count(def.id) >= _wanted_count(def):
			continue
		if not _can_afford(def):
			# SAVE for it rather than falling through to something
			# cheaper. Skipping ahead is how it ended up with a storehouse
			# and no barracks: the barracks costs 150 wood, the storehouse
			# less, so every time it could not afford the thing that makes
			# soldiers it bought the thing that does not — and spent the
			# wood that would have bought the barracks.
			return
		# Beside the BUILDER, not beside home. The server refuses a build
		# order whose squad is more than a few cells from the site, and
		# gatherers spend their lives away from home hauling — siting near
		# home meant the order was refused whenever the builder happened to
		# be out, which is most of the time. One AI built a barracks and
		# the other did not, on the same code, purely by where its workers
		# were standing.
		var site := _site_beside(builder)
		if site.x < 0:
			return
		var order := state.encode_build(builder, String(def.id), site)
		if order.is_empty():
			return
		# Hold this worker off hauling until the order lands, or the
		# gather order issued a second later cancels the build.
		_builder_squad = builder
		_builder_busy_until = state_time() + profile.think_interval * 3.0
		print("server: AI_BUILD player=%d %s at %s" % [player, def.id, site])
		send.call(order)
		return


## What to build UNCONDITIONALLY, in priority order: anything that trains
## soldiers first, because that is what makes this a game, then anything
## that shortens a haul.
##
## DEFENCE IS NOT ON THIS LIST, and that is #337's other half.
##
## It used to be. Every wall, gate and tower passes `can_build(gatherers)`
## and produces nothing, so they all landed in `support` and were built in
## `all_defs()` order — which is alphabetical, so the AI's second building
## was a `garrison_gate`. That is wrong twice over. It is 110 stone the AI
## could not gather (see `_kinds_below_floor`), so the queue stalled
## behind it forever; and even paid for, ONE wall segment on a
## pseudo-random cell two steps from whichever gatherer happened to be
## nearest is not a wall. It is a rock in a field, bought with the wood
## that would have trained soldiers.
##
## A wall is a shape, in a place, against somebody. That is a different
## question from "what do I not have yet", and it is asked in `_fortify()`
## against a threat model. This list answers the unconditional question
## and nothing else.
##
## Found by RULE rather than by id, as before: `WallPlan.is_wall_like`
## and a positive `damage` are fields, so a civ shipping its own wall or
## its own tower is picked up here with no edit (D-047).
func _wanted_buildings() -> Array:
	var military := []
	var support := []
	# This civ's defs, not every def
	# (`D-20260827-a-research-site-is-a-building`). The research sites are
	# per-civ, so `all_defs()` would have this AI trying to raise five
	# other civs' forges — and the server refusing each one, silently, on
	# every think.
	for def in BuildingSim.defs_for_civ(civ):
		if def.id == &"town_centre":
			continue
		if not BuildingSim.can_build(def, &"gatherers"):
			continue
		# A building behind a tech is not a building it can want yet.
		if not state.has_tech(def.requires_tech):
	for def in BuildingSim.all_defs():
		if def.consumes_builder:
			continue
		if not BuildingSim.can_build(def, &"gatherers"):
			continue
		if WallPlan.is_wall_like(def) or def.damage > 0.0:
		# A shore building is raised by the NAVAL INVESTMENT or not at
		# all (`_raise_dock`). This list is indiscriminate — every def a
		# gatherer may build, in cost order — so a dock was going up as
		# ordinary infrastructure on seats that had never wanted a navy
		# (#351: `docks=1` beside `wants_navy=0 ships_peak=0`).
		#
		# The wasted wood is the small half. §6.2's vacuity ladder gates
		# FIRST on "no dock was ever built", so a dock nobody meant would
		# carry the gate past its first leg and make it name the WRONG
		# one — and a check that lies about which thing broke is worse
		# than one that only says something did.
		#
		# By `needs_shore` rather than by id, so the next shore building
		# inherits the rule instead of rediscovering it (D-047: no script
		# names a civ; the same reasoning applies to naming a def).
		if def.needs_shore:
			continue
		if def.produces.size() > 0:
			military.append(def)
		else:
			support.append(def)
	return military + support


## How many of this building the AI wants standing. One of everything, and
## `profile.farms_wanted` FIELDS (D-20260828-food-is-grown-not-only-found)
## — a farm is the one building whose point is that there are several,
## because its output is a rate and the only way to raise a rate is to own
## more of them.
##
## Asked of the DEF rather than of an id, so a civ that ships its own field
## (or a later woodlot) is covered without this file learning a name — the
## same rule that keeps civs out of every other script (D-046 criterion 3).
func _wanted_count(def: BuildingDef) -> int:
	if Economy.grows_kind(def) >= 0 and def.grow_per_second > 0.0:
		return profile.farms_wanted
	return 1


func _owned_building_count(def_id: StringName) -> int:
	var count := 0
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) == player and String(info["def_id"]) == String(def_id) \
				and not bool(info["destroyed"]):
			count += 1
	return count


func _can_afford(def: BuildingDef) -> bool:
	if state.wallet.size() < 4:
		return false
	return state.wallet[0] >= def.cost_food and state.wallet[1] >= def.cost_wood \
		and state.wallet[2] >= def.cost_gold and state.wallet[3] >= def.cost_stone


## A gatherer to do the building. Gatherers are the builders (see the
## shipped BuildingDefs' `built_by`), so this competes with hauling — one
## is spared only once there are enough to spare.
func _idle_builder() -> int:
	var gatherers := _squads_matching(func(def): return def.carry_capacity > 0)
	if gatherers.size() < 2:
		return -1
	return int(gatherers[0])


## A free cell a short way from the builder, so the order is in reach.
func _site_beside(builder: int) -> Vector2i:
	if state.space == null:
		return Vector2i(-1, -1)
	var home := state.squad_cell(builder, state_time())
	if home.x < 0:
		return Vector2i(-1, -1)
	var offsets := TorusSpace.disk_offsets(2)
	if offsets.is_empty():
		return Vector2i(-1, -1)
	# Deterministic, so a replay reproduces where it built (D-016).
	var pick: Vector2i = offsets[(player * 7 + _buildings_placed * 5 + 1) % offsets.size()]
	_buildings_placed += 1
	return state.space.normalize(home + pick)


func _squads_matching(predicate: Callable) -> Array:
	var out := []
	for squad in _own_squads():
		var def := UnitRoster.by_id(StringName(state.composition[squad]["def_id"]))
		if def != null and predicate.call(def):
			out.append(squad)
	return out


var _buildings_placed := 0

# --- what this seat did about defence (#337) ---------------------------
#
# Reported in AI_STATS and gated on by `just ai-ladder`. `defences_ordered`
# is an INTENT and `defences_standing_peak` is the OUTCOME, and both are
# here because they are different faults with the same symptom: an AI that
# never decided to fortify and one whose every build order was refused
# both report zero defences standing. D-107's lesson, applied at the
# instrument rather than only at the latch.
var defences_ordered := 0

## Sites already asked for, and when they may be asked for again. Bounded
## by the screen's width, so this cannot grow.
var _defence_tried := {}

## How long a defence order is given to become a building before the site
## is offered again. Long, because the builder walks: the screen stands
## `WallPlan.STANDOFF_CELLS` out and a crew starts wherever it was
## hauling. A bound on a FAILURE rather than a difficulty knob, so it is a
## constant — the same line `StaticDefence.THREAT_CELLS` draws.
const DEFENCE_RETRY_SECONDS := 45.0
var defences_standing_peak := 0
var gate_orders := 0
var gates_sealed := 0

## Own buildings destroyed, and own buildings seen taking damage. Both
## feed `StaticDefence.pressure`, and both are DERIVED from the replicated
## building state this seat already receives rather than from a new wire
## field — a client can see its own buildings' `health_fraction` (D-076's
## amendment made it actually move), so nothing new crosses the wire.
var buildings_lost := 0
var attacks_survived := 0

## Own DEFENCES seen taking damage or destroyed — "a wall was fought
## over", separately from "a building was attacked".
##
## Separate because the ladder gate #337 asks for is about the WALL. A
## seat whose town centre was shelled while its wall stood untouched has
## not exercised D-076 at all, and `attacks_survived` cannot tell the two
## apart — which is the vacuous-gate shape this project keeps paying for
## (`test-client`'s casualty gate is satisfied by founding a town hall).
var defences_fought := 0
var _building_health := {}
var _buildings_seen := {}

## The worker currently committed to a build order, held off hauling
## until the order has had time to land.
var _builder_squad := -1
var _builder_busy_until := 0.0


## How long to wait before trying to found again. An order can be refused
## for reasons a client cannot see (D-034's notices say why, but only after
## the fact), and the fix for "the one attempt was lost" must not become
## "attempt every second forever".
const FOUND_RETRY := 5.0

## How far from home the founding search will wander (#217). Small on
## purpose: a hall is a base, and a seat driven ten cells off its own
## start is a worse outcome than a seat that takes a few more seconds to
## settle. 4 is 61 cells — far more than D-104's fairness pass can block,
## since it tops resources up within `fairness_radius` (9) of a start but
## nowhere near densely enough to fill a disk.
const FOUND_SEARCH_RADIUS := 4

## How many founding orders have been refused, or at least not yet seen to
## land. Drives `_found_site` one acceptable cell further out each time,
## which is the whole of the retry: D-107 made the AI ask again and this
## makes it ask somewhere else. Never reset — a hall exists or it does
## not, and `_found_town` returns early once one does.
var _found_attempts := 0


## The opening every player makes: plant the town hall
## (D-20260823-the-opening-is-a-crew-and-a-general). The gatherer crew is
## spent doing it (`BuildingDef.consumes_builder`), so the AI holds only
## its general until the hall starts producing.
##
## ## Latched on the TOWN, not on the send
##
## This used to set `_founded = true` on the line before `send.call(order)`
## — an attempt counted as a success. An order the server dropped was
## therefore indistinguishable from one it accepted, and the AI never tried
## again: with the seat thinking before the match was running (see
## `update`), every AI in every match sat on its founding party forever.
##
## Removing the latch outright is the other wrong answer, and was measured
## as such: with no latch the AI re-sends forever and the log fills with
## "cannot build a Town Centre" once it holds nothing that may. (The
## measurement was taken when that meant "the founding party is spent";
## since D-20260823-the-opening-is-a-crew-and-a-general it means the crew
## is spent and only the general is left. Same shape, same spam.) Two
## conditions bound it instead, and both are things the AI can SEE — it
## stops when the town centre exists, and it cannot start when it holds no
## squad allowed to found one. Between them there is nothing to spam.
##
## ## And the retry has to vary the SITE (#217)
##
## D-107 made the AI retry. Nothing made it retry anywhere ELSE: the site
## was `spawn_cell_of(player)`, which never moves, so a seat whose spawn
## cell happened to hold a resource node re-sent the identical refused
## order every five seconds for the whole match — no buildings, no
## production, banked wood it never spent, eliminated the moment its two
## opening squads died. Measured on `maps/ladder.tres` at seed 2:
## `buildings=0 peak_wood=200` against a 150-wood hall, and a match the
## ladder reported as a decisive win. D-087 puts thousands of nodes on the
## shipped map and D-104's fairness pass deliberately tops resources up
## NEAR starts, so this is a likely opening rather than an exotic one.
##
## `_found_site` is the fix, and `_report_refusals`' dedupe on message
## text is why nobody saw it: the log carried ONE refusal line for a loop
## that ran for the whole match.
func _found_town() -> void:
	if _owned_building_count(&"town_centre") > 0:
		return
	if state_time() < _found_at:
		return
	var squad := _founder()
	if squad < 0:
		return
	var site := _found_site(squad)
	if site.x < 0:
		return
	var order := state.encode_build(squad, "town_centre", site)
	if order.is_empty():
		return
	_found_at = state_time() + FOUND_RETRY
	_found_attempts += 1
	# Hold the crew off hauling until the order lands, exactly as
	# `_raise_buildings` does for every other build. Founders had no carry
	# capacity, so nothing else ever wanted them; the crew is a gatherer,
	# and `_put_gatherers_to_work` runs later in this same think — without
	# this it re-claims the crew and the gather order cancels the founding
	# it was just sent to do (the #123 defect, one seat over).
	_builder_squad = squad
	_builder_busy_until = state_time() + profile.think_interval * 3.0
	send.call(order)


## Where to plant the town hall this attempt (#217).
##
## Home first, then outward — `TorusSpace.disk_offsets` is sorted
## nearest-first (D-067), so this takes the closest cell it has no reason
## to doubt, and "walk outward until you find one" is the idiom that table
## already exists for. The seat's own spawn is what home means, so a
## successful founding still lands where the map put the player.
##
## Two mechanisms, and the ORDER of them is the point:
##
## 1. **Skip what this AI can SEE is blocked.** `ClientState.nodes` is
##    fog-gated and the AI's own opening squads are standing on its spawn,
##    so the node that actually caused #217 is one the AI knows about. That
##    makes the common case converge on the FIRST attempt rather than after
##    a walk outward.
## 2. **Then skip one more acceptable cell per failed attempt.** This is
##    what makes the retry a retry. The AI cannot model every refusal the
##    server can issue — steep ground and water are not on this client at
##    all (`terrain_passable` is set by `client.gd` and never for an AI
##    seat), and an enemy's no-build claim (D-062) may be under fog — so
##    checking only what it knows would rebuild #217 for every reason it
##    does not. Advancing the site on each refusal converges regardless of
##    WHY, which is the property that matters.
##
## Deriving passability here was rejected: it would mean a full terrain
## pass per AI seat at match start, to answer a question the widening
## retry already answers in a few seconds. The node check earns its place
## only because it is a Dictionary lookup against data the AI already
## holds for its economy.
##
## Falls back to home when nothing in range is acceptable, rather than
## returning "nowhere": the server owns the rules (D-002) and has the last
## word, and an AI that stopped asking would be back to `buildings=0`.
func _found_site(squad: int) -> Vector2i:
	var home := state.spawn_cell_of(player)
	if home.x < 0:
		home = state.squad_cell(squad, state_time())
	if home.x < 0 or state.space == null:
		return Vector2i(-1, -1)

	var sites: Array[Vector2i] = []
	for offset in TorusSpace.disk_offsets(FOUND_SEARCH_RADIUS):
		var cell := state.space.normalize(home + offset)
		if _looks_buildable(cell):
			sites.append(cell)
	if sites.is_empty():
		return home
	# WRAPPED, not walked off the end. The first version returned `home`
	# once `_found_attempts` passed the number of acceptable cells, which
	# quietly rebuilt #217 after about a dozen refusals — and a real match
	# reached that: `--map=ladder --seed=7 --ai=4` had a seat sending its
	# twelfth attempt at 56 s and every attempt from then on at the same
	# blocked start. Cycling instead keeps the retry a retry for as long as
	# the match lasts, which also covers a refusal that CLEARS later — an
	# enemy claim razed, a node worked out — since the site comes round
	# again.
	return sites[_found_attempts % sites.size()]


## Whether this AI has any reason to believe a hall cannot go here.
##
## Deliberately only what the AI KNOWS, and deliberately optimistic about
## the rest — the same asymmetry
## `D-20260818-pathing-knows-only-what-the-player-knows` chose for
## terrain belief, and for the same reason: being wrongly refused costs
## one retry, and refusing yourself costs the match.
func _looks_buildable(cell: Vector2i) -> bool:
	var index := state.space.index(cell)
	if state.nodes.has(index):
		return false
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if bool(info["destroyed"]):
			continue
		if state.space.index(info["cell"]) == index:
			return false
	return true


## A squad of this AI's that may actually found a town centre, or -1.
##
## Asked of the shipped BuildingDef's `built_by` rather than named here, so
## this file still names no unit and no civ (D-047) — and so it answers
## "nothing I hold may settle" correctly the moment it is true (the crew
## spent, the general being no builder), which is what stops the retry
## above from ever becoming a spin.
func _founder() -> int:
	var def := BuildingSim.def_by_id(&"town_centre")
	if def == null:
		return -1
	for squad in _own_squads():
		var unit := UnitRoster.by_id(StringName(state.composition[squad]["def_id"]))
		if unit != null and BuildingSim.can_build(def, unit.archetype):
			return squad
	return -1


## Train from anything finished. Asks by ARCHETYPE, so this file names no
## unit and works for any civ (D-047) — including one added tomorrow.
func _train() -> void:
	if state_time() < _train_at:
		return
	# Counted in GATHERERS, not in squads.
	#
	# Measuring against total squads meant every soldier trained made it
	# want another worker, so workers grew until they filled the squad cap
	# (D-033) and the army could never be built. The ladder showed 15
	# squads of which 15 were workers.
	# Summed as SOLDIERS, because that is what gathers — a headcount
	# target survives the roster changing crew size under it.
	var worker_soldiers := 0
	for squad in _squads_matching(func(def): return def.carry_capacity > 0):
		worker_soldiers += state.alive_of(squad)
	# LATCHED, with hysteresis — the boundary is not a safe place to sit.
	#
	# The default target is 110 soldiers and a crew is 5, so it is met at
	# exactly 22 squads. A single casualty anywhere drops the count to
	# 109, the test flips back to "make gatherers", and the AI spends the
	# rest of the match rebuilding one worker instead of an army. One
	# ladder seat did exactly that: 22 squads, all workers, three buildings,
	# 1,680 wood banked and not one soldier trained in 700 seconds — while
	# its opponent on the same code reached 44 squads and attacked 59
	# times.
	#
	# So: once the economy has EVER been staffed, stay switched. It only
	# goes back if the workforce is genuinely gutted (a raid, not a
	# scratch), which is the case where rebuilding really is the priority.
	if worker_soldiers >= profile.gatherer_soldiers_wanted:
		_economy_staffed = true
	elif worker_soldiers < float(profile.gatherer_soldiers_wanted) * 0.6:
		_economy_staffed = false

	# economy_only (sandbox mode, dev testing) holds this at "gatherers"
	# regardless of staffing — an AI that never fights has no use for a
	# standing army, and one is not just wasted, it is an idle squad cap
	# entry a real test scenario might want spent on more workers instead.
	var wanted := &"gatherers" if economy_only or not _economy_staffed \
		else _military_archetype()
	if wanted == &"":
		return

	# Decide WHAT first, then find a building that can make it.
	#
	# This used to pick the first building it owned, ask that for whatever
	# it wanted, and return either way — so with a town centre and a
	# barracks it asked the town centre for soldiers, was refused
	# server-side, and returned. It never reached the barracks, and never
	# trained a soldier in any match on the ladder even after learning to
	# build one.
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) != player or bool(info["destroyed"]):
			continue
		if float(info["progress"]) < 1.0:
			continue
		var building_def := BuildingSim.def_by_id(StringName(info["def_id"]))
		if building_def == null or not building_def.produces.has(wanted):
			continue
		# One order at a time, not one per think.
		#
		# It used to ask every second while its worker count was under
		# target, so dozens of orders queued before the first finished and
		# it blew past the target into the squad cap (D-033) — 54 orders,
		# 15 workers, no room left for an army. A player watches the queue;
		# this is the same restraint expressed as a cooldown.
		_train_at = state_time() + profile.train_cooldown
		send.call(NetProtocol.encode_order_produce(int(wire_id), wanted))
		return


## Some archetype this civ actually fields, chosen from the roster rather
## than named here. A civ without cavalry trains whatever it does have.
## How long the AI waits before re-offering a tech the server refused.
##
## A constant rather than a profile knob, for `FOUND_RETRY`'s reason: it
## bounds a FAILURE, and a difficulty setting able to make an AI spam or
## stop researching is a way to ship a broken opponent by data entry.
const RESEARCH_RETRY := 12.0

## line -> the time this AI may next offer it. Latched on the REFUSAL, not
## on the send: a granted tech turns up in `state.techs` and drops out of
## `available()` by itself, so success needs no flag at all. D-107's rule
## — "latch on the effect, not the send" — with the effect being a tech
## the AI can SEE it holds.
var _research_retry := {}

## Techs this AI has ordered and seen land. A metric, read off its own
## ClientState rather than counted here, for the same reason.
var techs_ordered: int = 0


## Climb the tree (`D-20260827-the-tree-is-the-ladder`).
##
## Without this the AI is permanently in epoch 1: `requires_tech` gates
## most of the roster, so an AI that never researched would field levies
## and gatherers for ninety minutes against an opponent fielding its
## signature. Every ladder number would then measure the AI not knowing
## the tree existed — the shape of D-107, where ten minutes of nothing was
## read as an AI weakness for a whole milestone.
##
## Priority is DEFINING first, then cheapest. Defining first is what makes
## the AI a ladder opponent at all; cheapest-among-the-rest keeps it from
## banking indefinitely toward one expensive branch while a cheap one sits
## affordable.
func _research(now: float) -> void:
	if not state.welcomed or civ == &"":
		return
	var view := state.research_view()
	var candidates := view.available(player, civ)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: TechDef, b: TechDef) -> bool:
		if a.defining != b.defining:
			return a.defining
		if a.resource_points() != b.resource_points():
			return a.resource_points() < b.resource_points()
		# Ids, so two techs of equal price are considered in an order that
		# reproduces — a replay of an AI match has to be that match.
		return a.id < b.id)

	for tech in candidates:
		if float(_research_retry.get(tech.line, 0.0)) > now:
			continue
		if not _can_afford_tech(tech):
			continue
		var at := _research_site(tech.research_at)
		if at < 0:
			continue
		send.call(NetProtocol.encode_order_research(at, String(tech.line)))
		_research_retry[tech.line] = now + RESEARCH_RETRY
		techs_ordered += 1
		return


## Can this AI pay for `tech` right now, given its profile's appetite?
##
## A defining tech only has to be affordable. Anything else has to be
## affordable `1 / research_bias` times over, so a low-bias profile keeps
## a war chest and a high-bias one spends it — a deterministic threshold
## rather than a roll, because a replay has to reproduce (D-016).
func _can_afford_tech(tech: TechDef) -> bool:
	if state.wallet.size() < 4:
		return false
	var margin := 1.0
	if not tech.defining:
		margin = 1.0 / maxf(profile.research_bias, 0.05)
	return float(state.wallet[0]) >= float(tech.cost_food) * margin \
		and float(state.wallet[1]) >= float(tech.cost_wood) * margin \
		and float(state.wallet[2]) >= float(tech.cost_gold) * margin \
		and float(state.wallet[3]) >= float(tech.cost_stone) * margin


## A finished building of `archetype` this AI owns, as a WIRE id, or -1.
##
## Reads the client's own building list, like everything else here does —
## an AI knows what a client in its seat knows (D-051). `progress` at 1.0
## is the client's own signal that a building is complete; asking the
## server would be reaching for a fact a human player could not have.
func _research_site(archetype: StringName) -> int:
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) != player or bool(info["destroyed"]):
			continue
		if float(info.get("progress", 0.0)) < 0.999:
			continue
		# A SHORT queue is fine to join — one queue holds both kinds
		# (D-20260827), so research waiting behind a unit or two is what
		# should happen. Requiring an IDLE building looked right and was
		# measurably wrong: a town centre trains gatherers continuously,
		# so it is never idle, and the load-test bots with the same guard
		# ordered research not once in a 300 s run.
		if (info.get("queue", []) as Array).size() > 2:
			continue
		var def := BuildingSim.def_by_id(StringName(info["def_id"]))
		if def != null and BuildingSim.archetype_of_def(def) == archetype:
			return int(wire_id)
	return -1


func _military_archetype() -> StringName:
	# Only something a building it OWNS can actually make.
	#
	# Without this it picked the old founding party's archetype — a
	# fighting unit with no carry capacity, so it passed every test for
	# "military" — and asked the barracks for it. Barracks did not make
	# them, so the order was never sent and it trained nothing but
	# gatherers for the entire match, with a finished barracks standing
	# there. The ladder showed 15 squads, 15 workers, 0 attacks.
	#
	# A GENERAL is skipped for a related reason with a different shape. A
	# town centre produces one, it has damage and no carry capacity, and
	# the server allows only one alive per player
	# (D-20260819-a-general-holds-the-line) — and as of
	# D-20260823-the-opening-is-a-crew-and-a-general every player STARTS
	# with theirs. So an AI that picked it here would spend every training
	# cooldown, for the whole match, on an order refused before it reached
	# a unit. By FIELD, not by name, the same discipline
	# `bot_build_plan.gd` already uses.
	for archetype in _producible_archetypes():
		var def := UnitRoster.for_civ_archetype(civ, archetype)
		# And not one still behind a tech
		# (`D-20260827-the-tree-is-the-ladder`). Skipped by FIELD, like
		# the two above it, and for the same reason: an order the server
		# refuses spends a whole training cooldown. This picker takes the
		# FIRST match, so without the filter it would work only by
		# accident of `barracks.produces` starting with the one ungated
		# archetype.
		if def != null and not state.has_tech(def.requires_tech):
			continue
		if def != null and def.damage > 1.0 and def.carry_capacity <= 0 \
				and not def.is_general:
			return archetype
	return &""


## Every archetype some finished building of this player's can produce.
## Read from the shipped BuildingDefs, so a building added as a .tres
## widens the AI's options with no code change.
func _producible_archetypes() -> Array:
	var out := []
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) != player or bool(info["destroyed"]):
			continue
		if float(info["progress"]) < 1.0:
			continue
		var building_def := BuildingSim.def_by_id(StringName(info["def_id"]))
		if building_def == null:
			continue
		for archetype in building_def.produces:
			if not out.has(archetype):
				out.append(archetype)
	return out


func _own_squads() -> Array:
	var out := []
	for squad in state.squads:
		if state.alive_of(squad) > 0:
			out.append(squad)
	return out


## Send gatherers at the nearest resource the AI knows about. It only
## knows about nodes the server told it, which is the point.
func _put_gatherers_to_work() -> void:
	# Fields count as work sites (D-20260828-food-is-grown-not-only-found).
	# Guarding on `state.nodes` alone would have made an AI that had farmed
	# the whole map's forests out stand its crews down beside its own
	# harvest — the exact end state #159 is about.
	var fields := _own_fields()
	if state.space == null or (state.nodes.is_empty() and fields.is_empty()):
		return
	var gatherers := _squads_matching(func(def): return def.carry_capacity > 0)
	if gatherers.is_empty():
		return

	# Workers are SHARED between the resources that are short, not all
	# sent after whichever is scarcest right now.
	#
	# Sending everyone at one kind worked while crews were 16-strong and
	# there were seven of them. With 5-man crews there are twenty-odd
	# productions, each spending food, so food never climbed back over its
	# floor — every worker chased food forever, wood never reached 150,
	# and the barracks was unreachable. The ladder showed it exactly:
	# 20.7 squads of which 20.7 were workers, one building, never attacked.
	#
	# A worker joins whichever short resource has the FEWEST already on it,
	# so the crew spreads across what is actually needed and no single
	# demand can starve the rest.
	var short := _kinds_below_floor()
	var on_kind := {}
	for kind in short:
		on_kind[kind] = 0
	for squad in _assigned:
		var at := int(_assigned[squad])
		var kind := int(state.nodes.get(at, fields.get(at, -1)))
		if on_kind.has(kind):
			on_kind[kind] = int(on_kind[kind]) + 1

	for squad in gatherers:
		# The worker that was just told to build is left alone. Re-issuing
		# a gather order a second later cancelled the build it had only
		# just been given, which is why the barracks never went up even
		# when the order was accepted.
		if squad == _builder_squad and state_time() < _builder_busy_until:
			continue
		# Already hauling something useful — leave it be. Re-issuing every
		# second restarted the round trip forever, so nothing was ever
		# delivered.
		if squad == _resource_scout and state_time() < _scout_leg_until:
			continue
		if _assigned.has(squad):
			continue

		# Whichever short resource is currently least attended.
		var wanted_kind := _scarcest_kind()
		var fewest := 1 << 30
		for kind in short:
			if int(on_kind[kind]) < fewest:
				fewest = int(on_kind[kind])
				wanted_kind = kind

		var cell := _nearest_node_of_kind(state.squad_cell(squad, state_time()), wanted_kind)
		if cell < 0:
			continue
		_assigned[squad] = cell
		_assigned_at[squad] = state_time()
		if on_kind.has(wanted_kind):
			on_kind[wanted_kind] = int(on_kind[wanted_kind]) + 1
		send.call(NetProtocol.encode_order_gather(squad, cell))


## Go and LOOK for a resource it needs and has never seen (D-061).
##
## Resource positions are fog-gated now: a client is told about a node
## when it comes into view, not at join. Before that the AI knew the whole
## map's resources from the first tick, so this was unnecessary — and the
## measurement says plainly that it no longer is. With gating on, an AI's
## `peak_wood` sat at its STARTING 180 for a whole match and `substituted`
## climbed to 17: every worker asking for wood was handed food instead,
## because no wood node had ever been seen.
##
## Deliberately cheap. One worker at a time, sent to a waypoint on a
## widening spiral out from home, and only while something it wants is
## genuinely unknown. It is not a search algorithm — walking anywhere new
## reveals nodes, because vision does the discovering.
const SCOUT_LEG_SECONDS := 25.0


func _scout_for_what_it_lacks() -> void:
	if state.space == null or not state.welcomed:
		return

	# TWO reasons to walk somewhere new, and the second one is why this
	# is not called `_scout_for_resources` any more.
	#
	# A missing RESOURCE was the original trigger, and it stops the moment
	# a node of each needed kind has been seen — which is right for the
	# economy and made `_scout_leg` a measure of HUNGER rather than of
	# looking. #351's naval question reads that counter to answer "have I
	# searched", and on a rich island an AI satisfied its economy in two
	# legs and never scouted again: 3 buildings, 29 squads, `scout_legs=2`
	# after ten minutes, and so it never concluded it had run out of
	# world. The predicate was right and the number under it did not mean
	# what its name said.
	#
	# A missing ENEMY is the second, and it makes the counter honest: an
	# AI that does not know where anybody is has something to look for,
	# whatever its wallet says. It stops at `SCOUTED_ENOUGH_LEGS` rather
	# than running forever, because past that point the answer is "I have
	# looked and there is nobody here" — which is exactly what
	# `AiNaval.needs_ships` is waiting to hear.
	var missing := -1
	for kind in _kinds_below_floor():
		if _nearest_known_of_kind(kind) < 0:
			missing = kind
			break
	var unfound_enemy := _known_enemy_cells().is_empty() 		and _scout_leg < SCOUTED_ENOUGH_LEGS
	if missing < 0 and not unfound_enemy:
		_resource_scout = -1
		return

	# Let the current leg finish before picking a new direction, or the
	# scout pivots every think and never actually covers ground.
	if _resource_scout >= 0 and state_time() < _scout_leg_until \
			and state.alive_of(_resource_scout) > 0:
		return

	var crews := _squads_matching(func(def): return def.carry_capacity > 0)
	if crews.size() < 2:
		return  # too few to spare one

	# The LAST crew, so scouting does not fight `_idle_builder` over the
	# first one — losing the builder to exploration is how the barracks
	# stops being built.
	_resource_scout = int(crews[-1])
	_scout_leg_until = state_time() + SCOUT_LEG_SECONDS
	_assigned.erase(_resource_scout)
	_assigned_at.erase(_resource_scout)

	var home := state.spawn_cell_of(player)
	if home.x < 0:
		home = state.squad_cell(_resource_scout, state_time())
	if home.x < 0:
		return

	# A widening spiral: each leg turns and steps further out, so the
	# scout sweeps new ground rather than pacing the same line.
	_scout_leg += 1
	var radius := 6 + _scout_leg * 5
	var angle := float(_scout_leg) * 2.39996  # golden angle, so legs spread
	var target := state.space.normalize(home + Vector2i(
		roundi(cos(angle) * float(radius)), roundi(sin(angle) * float(radius))))

	scout_legs += 1
	send.call(state.encode_order(_resource_scout, target))


## The nearest node of a kind this AI has actually been shown, or -1.
## Unlike `_nearest_node_of_kind` this does NOT fall back to another kind
## — the whole question here is whether the wanted kind is known at all.
func _nearest_known_of_kind(kind: int) -> int:
	var fields := _own_fields()
	for cell in fields:
		if not _exhausted.has(int(cell)) and int(fields[cell]) == kind:
			return int(cell)
	for cell in state.nodes:
		if _exhausted.has(int(cell)):
			continue
		if int(state.nodes[cell]) == kind:
			return int(cell)
	return -1


## Give up on a node a crew cannot actually reach.
##
## `_nearest_node_of_kind` ranks by DISTANCE, which on a torus with water
## is not the same as reachability: the nearest wood may be across a
## channel, and a crew sent there walks as far as it can and stops. It
## stays `_assigned` forever, so it is never reconsidered and never
## gathers — while the AI reports a full complement of workers.
##
## That is what the ladder was showing: `substituted=0`, so wood nodes
## WERE found and crews WERE sent, and `peak_wood` never moved off its
## starting 180 in any match. Food happened to be reachable and looked
## perfectly healthy alongside it.
##
## A timeout rather than a reachability query, because the flow field is
## the only thing that truly knows and asking it per candidate node per
## think is the `distance()`-per-cell defect again. If a crew has not
## arrived after this long, the node is unreachable in practice —
## whatever the reason — and that is the useful definition.
const UNREACHABLE_AFTER := 40.0


func _drop_unreachable_assignments() -> void:
	for squad in _assigned.keys():
		var since := state_time() - float(_assigned_at.get(squad, state_time()))
		if since < UNREACHABLE_AFTER:
			continue
		var target := int(_assigned[squad])
		# Arrived at some point? Then it is working, just slowly.
		if state.space != null and state.squad_cell(squad, state_time()) \
				== state.space.from_index(target):
			_assigned_at[squad] = state_time()
			continue
		print("server: AI_UNREACHABLE player=%d gave up on node %d" % [player, target])
		unreachable_nodes += 1
		_exhausted[target] = true
		_assigned.erase(squad)
		_assigned_at.erase(squad)


## The resources currently under their floor, PLUS whatever the next
## thing this AI wants to buy is short of. Food always qualifies, so a
## crew is never left with nothing to do when everything is stocked.
##
## That second clause is #337's root cause, and it was worth more than the
## walls it was filed about.
##
## This list was FOOD and WOOD, full stop — so the AI never gathered stone
## or gold in any match that has ever been played. Every wall, gate and
## tower in the roster costs stone, so every one of them was unaffordable
## forever; and because `_raise_buildings` SAVES for what it cannot afford
## rather than skipping it, the alphabetically-first support building
## (`garrison_gate`, 110 stone) stalled the queue behind it and the AI
## never built a storehouse either.
##
## Measured on `main` before this change, `just ai-ladder 1 300 2`:
## **buildings~2.0 on both seats** — a town centre and a barracks, for the
## whole match. The wall half of D-076 was not merely unexercised by the
## ladder; it was unreachable by the economy.
##
## So an AI gathers what its NEXT PURCHASE costs. Naval stage 7 inherits
## the fix rather than rediscovering it: a dock is another building whose
## price is not food.
func _kinds_below_floor() -> Array:
	var out := []
	if state.wallet.size() >= 4:
		if state.wallet[1] < profile.wood_floor:
			out.append(Economy.ResourceKind.WOOD)
	var short := _shortfall_for_next_purchase()
	if short >= 0 and not out.has(short):
		out.append(short)
	out.append(Economy.ResourceKind.FOOD)
	return out


## Which resource the thing this AI is saving for is most short of, or -1.
##
## "The thing it is saving for" is `_wanted_buildings()`'s first unbuilt
## entry — the same list `_raise_buildings` walks, so the economy is
## always working toward the purchase the build step is waiting on. Two
## copies of "what do I want next" is the pair that comes to disagree
## (D-058/D-065's family), which is why this asks rather than deciding.
func _shortfall_for_next_purchase() -> int:
	if state.wallet.size() < Economy.RESOURCE_COUNT:
		return -1
	for def in _wanted_buildings():
		if _owned_building_count(def.id) > 0:
			continue
		return StaticDefence.scarcest_shortfall(state.wallet, StaticDefence.cost_of(def))
	# And then whatever DEFENCE it intends to buy, because defences are
	# deliberately not on `_wanted_buildings` (see that function) and an
	# economy that did not know about them would never gather the stone
	# they cost — which is #337's root cause coming back through the door
	# the fix opened. Measured: with walls off the unconditional list, the
	# shortfall went to -1 the moment the storehouse was up and stone
	# income stopped again.
	var defence := _next_defence_wanted()
	if defence != null:
		return StaticDefence.scarcest_shortfall(state.wallet,
			StaticDefence.cost_of(defence))
	return -1


## The defensive building this seat would buy next, or null if it does not
## want one. Asks `_fortify`'s own question, so the economy and the build
## step cannot disagree about what is being saved for.
func _next_defence_wanted() -> BuildingDef:
	if not StaticDefence.wants_to_invest(_threat_report(), _economy_report(),
			profile.defence_appetite, _defences_standing(), DEFENCES_CAP):
		return null
	var tower := WallPlan.cheapest_defensive_tower(&"gatherers")
	if tower != null and _owned_building_count(tower.id) == 0:
		return tower
	return WallPlan.cheapest_wall(false)


## Which resource to send the next worker after.
##
## It used to send every worker at the NEAREST node whatever it held, so
## if wood happened to be closer nobody ever gathered food — and gatherers
## cost food. The economy stalled at four squads with "Cannot afford
## Gatherers" and stayed there for the whole match.
##
## Food first, because it buys the workers that buy everything else; then
## wood, because that is what a barracks costs.
func _scarcest_kind() -> int:
	if state.wallet.size() < 4:
		return Economy.ResourceKind.FOOD
	if state.wallet[0] < profile.food_floor:
		return Economy.ResourceKind.FOOD
	if state.wallet[1] < profile.wood_floor:
		return Economy.ResourceKind.WOOD
	return Economy.ResourceKind.FOOD


## Every FIELD this AI may put a crew on: cell -> kind. Its own and its
## allies' (D-050), which is `ClientState.farm_cells`' own filter, so the
## AI cannot ask for an order the server would refuse.
##
## Derived from buildings it already knows about, so it costs nothing and
## obeys fog by construction — an AI seat is a client without a socket
## (D-051) and learns about a field exactly when a human would.
func _own_fields() -> Dictionary:
	return state.farm_cells(true)


func _nearest_node_of_kind(from: Vector2i, kind: int) -> int:
	var best := -1
	var best_distance := 1 << 30
	var fallback := -1
	var fallback_distance := 1 << 30
	# Fields first, and by the same distance ranking as everything else —
	# a farm beside the town hall beats a forest across the map on its own
	# merits, and nothing here has to prefer one on purpose.
	var fields := _own_fields()
	for cell in fields:
		var field_index := int(cell)
		if _exhausted.has(field_index):
			continue
		var fd := state.space.distance(from, state.space.from_index(field_index))
		if int(fields[cell]) == kind and fd < best_distance:
			best_distance = fd
			best = field_index
		elif fd < fallback_distance:
			fallback_distance = fd
			fallback = field_index
	for cell in state.nodes:
		var index := int(cell)
		if _exhausted.has(index):
			continue
		var d := state.space.distance(from, state.space.from_index(index))
		if int(state.nodes[cell]) == kind and d < best_distance:
			best_distance = d
			best = index
		elif d < fallback_distance:
			fallback_distance = d
			fallback = index
	# Something is better than idling if the wanted kind is all gone —
	# but COUNT it, because this silently substitutes a different resource
	# and that is what hid the AI gathering zero wood for a whole session.
	# Every worker asked for wood, none was among the nodes it had seen,
	# and each was quietly handed a food node instead. The wallet showed a
	# healthy 3,248 food beside a starting 180 wood, and nothing anywhere
	# said the substitution had happened.
	if best < 0 and fallback >= 0:
		substituted_kind += 1
	return best if best >= 0 else fallback


## Nodes the server has said are empty, and squads currently hauling.
##
## The AI is told "Nothing to gather there" (D-034's notices) and used to
## ignore it, so a worker sent at a depleted node kept being sent at the
## same depleted node forever.
var _exhausted := {}
var _assigned := {}


## Attack-move the army at the nearest enemy it can SEE. Nothing here
## consults the simulation — `state.composition` holds exactly what the
## server chose to tell this player, so an enemy sitting in fog is not a
## target because the AI does not know it exists.
func _fight(now: float) -> void:
	if state.space == null or now < _attack_at:
		return

	var army := []
	for squad in _own_squads():
		var def := UnitRoster.by_id(StringName(state.composition[squad]["def_id"]))
		if def != null and def.damage > 1.0 and def.carry_capacity <= 0:
			army.append(squad)
	# How much army it masses before it moves is a profile field
	# (D-20260818-ai-profiles-are-data): at two it dribbles pairs across
	# the map, at four it turns up as an army. It is the half of pacing a
	# defender FEELS — the other half is when the army exists at all,
	# which is `gatherer_soldiers_wanted` and the train cooldown.
	if army.size() < profile.attack_squads_minimum:
		return

	var target := _enemy_target()
	if target.x < 0:
		# Nothing in sight — go and LOOK.
		#
		# Without this the AI waits to be found. Spawns are far apart and
		# vision is a few cells, so two AI can spend an entire match a
		# short walk from each other and never meet: the ladder ran match
		# after match to the time cap with armies standing still and
		# `attacks=0`. It already knows every spawn cell from the welcome
		# message (D-036) — it simply never went to one.
		target = _next_place_to_look()
		if target.x < 0:
			return

	# Where the army was actually SENT, judged after the fact (#119).
	#
	# Deliberately not a second copy of `_hostile`: this asks what stands
	# on the cell the order names, so it answers "did this AI march on a
	# friend" from the OUTCOME rather than from the code path that chose
	# it. A check that re-ran the filter would be green whenever the filter
	# was green, which is precisely the thing under test.
	if _allies_only_at(target):
		ally_objectives += 1
	# Attacked in a body rather than one squad at a time, so the AI
	# arrives as an army instead of feeding itself in piecemeal.
	_attack_at = now + profile.think_interval * profile.attack_regroup_thinks
	attacks_launched += 1
	if first_attack_at < 0.0:
		first_attack_at = now
		# How BIG the first attack was, not merely when it landed. #93 is
		# about an attack arriving before a human's opening is finished,
		# and "at 171 s" is only half of that sentence — a person can be
		# asked whether they could have held 40 men at three minutes, and
		# cannot be asked anything useful about a bare timestamp.
		for squad in army:
			first_attack_soldiers += state.alive_of(squad)
	for squad in army:
		var order := state.encode_attack_move(squad, target)
		if not order.is_empty():
			send.call(order)


## The clock the AI samples curves against. Its ClientState has no frame
## loop of its own, so the server's simulation time is the honest answer.
var _now := 0.0


func state_time() -> float:
	return _now


func set_time(now: float) -> void:
	_now = now


# --- what the ladder measures (D-054) ---------------------------------
#
# Tracked by the AI itself rather than dug out of the simulation, for the
# same reason it reads the world through a ClientState: these are the
# numbers as the PLAYER experienced them. An economy stat pulled from
# SquadSim would describe a game this AI could not see.

var peak_squads: int = 0
var peak_workers: int = 0
var buildings_raised: int = 0
var peak_enemy_buildings_known: int = 0

## Why production stopped, counted rather than reasoned about. See
## _report_refusals for why this exists.
var afford_refusals: int = 0
var cap_refusals: int = 0
## Largest total stockpile this AI ever sat on. A big idle pile alongside
## a small army is the signature of a THROUGHPUT limit; a floor near zero
## is the signature of a real economy limit.
var peak_stockpile: int = 0
var peak_food: int = 0
var peak_wood: int = 0
## How often a worker asked for one resource and was handed another,
## because none of the wanted kind was among the nodes this AI has seen.
var substituted_kind: int = 0
## Nodes given up on because no crew could reach them.
var unreachable_nodes: int = 0
## How many exploration legs the AI walked looking for a resource.
var scout_legs: int = 0
## Latched once the economy has been staffed, so a single casualty at the
## boundary cannot send the AI back to building workers forever.
var _economy_staffed := false
var _resource_scout := -1
var _scout_leg_until := 0.0
var _scout_leg := 0
## squad -> when it was given its current gather order.
var _assigned_at := {}
var attacks_launched: int = 0
var first_attack_at: float = -1.0
## How many soldiers marched in that first attack. Recorded when it is
## ordered rather than reconstructed later, because the army that sets off
## is not the army that arrives — and the question #93 asks is what the
## defender was hit BY.
var first_attack_soldiers: int = 0

## How many attack objectives landed on a friend (#119). Zero is the only
## acceptable value, and it is only EVIDENCE of anything alongside
## `allies_seen` below: an AI that never had a teammate in sight cannot
## have marched on one, and would report the same zero.
var ally_objectives: int = 0

## The most allied-but-not-own things this AI could see at once — squads
## and standing buildings. The vacuity guard for the counter above, and
## the check that D-050's shared vision actually reached this seat: on the
## `--lobby=0` path the simulation was never handed the seats' teams at
## all before #119, so a teamed AI saw exactly what a free-for-all one
## did and every alliance-shaped assertion about it passed for free.
var peak_allies_seen: int = 0


func _record_stats() -> void:
	_note_landings()
	var squads := _own_squads()
	peak_squads = maxi(peak_squads, squads.size())

	var workers := 0
	for squad in squads:
		var def := UnitRoster.by_id(StringName(state.composition[squad]["def_id"]))
		if def != null and def.carry_capacity > 0:
			workers += 1
	peak_workers = maxi(peak_workers, workers)

	var mine := 0
	var theirs := 0
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if bool(info["destroyed"]):
			continue
		if int(info["owner"]) == player:
			mine += 1
		elif _hostile(int(info["owner"])):
			theirs += 1
	buildings_raised = maxi(buildings_raised, mine)

	# Has it ever LAID EYES on an opponent's base? Making buildings the
	# attack objective changed the ladder by literally nothing — every
	# stat identical to three significant figures, which is not a small
	# effect but no effect, so the branch cannot be running. This is the
	# measurement that says whether that is because it never finds one.
	# Buildings are persistent-explored (D-030), so once seen this only
	# ever grows and a peak is the honest summary.
	#
	# Counted through `_hostile`, because the instrument built to diagnose
	# the targeting shared the targeting's blind spot: every non-own
	# building was `theirs`, so an ally's town — the nearest known building
	# a teamed AI has, and the one it was marching on — reported as an
	# opponent's base FOUND. `mine` stays an ownership test on purpose:
	# `buildings_raised` counts what this seat put up, not what its team
	# did.
	peak_enemy_buildings_known = maxi(peak_enemy_buildings_known, theirs)

	# What defence has cost this seat, and what it has standing. Both are
	# read off the buildings the server already sends it: a client sees its
	# own buildings' health (D-076's amendment made `health_fraction`
	# actually move, having carried a constant 1.0 for a milestone), so
	# there is no new wire field here and no second data-hiding mechanism.
	var defences := 0
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) != player:
			continue
		var def := BuildingSim.def_by_id(StringName(String(info["def_id"])))
		var is_defence := WallPlan.is_static_defence(def)
		if bool(info["destroyed"]):
			if _buildings_seen.has(wire_id) and not bool(_buildings_seen[wire_id]):
				buildings_lost += 1
				# A wall that was pulled down was fought over by
				# definition, and it is the one case `health_fraction`
				# cannot report: a building destroyed between two thinks
				# never shows an intermediate value.
				if is_defence:
					defences_fought += 1
				_buildings_seen[wire_id] = true
			continue
		_buildings_seen[wire_id] = false
		if is_defence:
			defences += 1
		var health := float(info.get("health_fraction", 1.0))
		if _building_health.has(wire_id) and health < float(_building_health[wire_id]) - 0.001:
			attacks_survived += 1
			if is_defence:
				defences_fought += 1
		_building_health[wire_id] = health
	defences_standing_peak = maxi(defences_standing_peak, defences)

	# Friends in sight, counted the same way and for the opposite reason
	# (#119): `ally_objectives=0` says nothing at all unless this AI had an
	# ally it could actually have marched on.
	var allies := 0
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if bool(info["destroyed"]) or int(info["owner"]) == player:
			continue
		if not _hostile(int(info["owner"])):
			allies += 1
	for id in state.composition:
		var owner := int(state.composition[id].get("owner", 0))
		if owner == player or state.alive_of(id) <= 0:
			continue
		if not _hostile(owner):
			allies += 1
	peak_allies_seen = maxi(peak_allies_seen, allies)

	var stockpile := 0
	for i in range(state.wallet.size()):
		stockpile += state.wallet[i]
	peak_stockpile = maxi(peak_stockpile, stockpile)
	# Per-resource peaks: a total says the economy is running, and says
	# nothing about WHICH resource a stalled build is waiting on. The AI
	# saves for a barracks (150 wood) and a big food pile looks identical
	# to a healthy economy from the total alone.
	if state.wallet.size() >= 2:
		peak_food = maxi(peak_food, state.wallet[0])
		peak_wood = maxi(peak_wood, state.wallet[1])


## One line the ladder can parse. Structured markers, not prose — the
## same rule the load test's verdict follows.
func stats_line() -> String:
	return "AI_STATS player=%d civ=%s profile=%s team=%d squads_peak=%d workers_peak=%d buildings=%d enemy_buildings_seen=%d allies_seen=%d ally_objectives=%d attacks=%d first_attack=%.1f first_attack_soldiers=%d peak_stockpile=%d peak_food=%d peak_wood=%d substituted=%d unreachable=%d scout_legs=%d afford_refusals=%d cap_refusals=%d epoch=%d techs=%d techs_ordered=%d defences_ordered=%d defences_standing=%d gate_orders=%d gates_sealed=%d buildings_lost=%d attacks_survived=%d defences_fought=%d wants_navy=%d docks=%d ships_peak=%d embarks=%d landings=%d naval_step=%s" % [
		player, civ, profile.id, _own_team(), peak_squads, peak_workers, buildings_raised,
		peak_enemy_buildings_known, peak_allies_seen, ally_objectives,
		attacks_launched, first_attack_at, first_attack_soldiers,
		peak_stockpile, peak_food, peak_wood, substituted_kind, unreachable_nodes, scout_legs, afford_refusals, cap_refusals,
		# The ladder half (D-20260827). `techs` is read off this AI's own
		# ClientState rather than counted here, so it reports what the AI
		# can SEE it holds — the D-107 rule, and it is what separates "it
		# never asked" (techs_ordered 0) from "it asked and was refused"
		# (techs_ordered high, techs 0). Those are different faults with
		# the same symptom.
		state.epoch, state.techs.size(), techs_ordered,
		defences_ordered, defences_standing_peak, gate_orders, gates_sealed,,
		1 if wants_navy else 0, docks, ships_peak, embarks, landings, naval_step]


## The side this seat is on, as the AI itself understands it — read off
## the seat list it was sent, not off the simulation. A teamed harness
## that read the team from the server would be asking the wrong process:
## the question is whether the AI, a client (D-051), knows.
func _own_team() -> int:
	for seat in state.lobby.get("seats", []):
		if int(seat["player"]) == player:
			return int(seat.get("team", 0))
	return 0


# --- what it is thinking (D-054) --------------------------------------
#
# The server tells a client WHY an order was refused (D-034's notices),
# and until now the AI was the only client with nobody reading them. Two
# rounds of ladder work changed nothing because every failure was landing
# in a field no log ever printed. This is the instrument, not a
# workaround: the same "read the log rather than theorise" that found an
# 858 ms filesystem walk in D-043.

var _last_notice_seen := ""


func _report_refusals() -> void:
	if state.last_notice == "" or state.last_notice == _last_notice_seen:
		return
	_last_notice_seen = state.last_notice
	print("server: AI_REFUSED player=%d — %s" % [player, state.last_notice])

	# Counted, not just printed, so the ladder can answer "was it short of
	# MONEY or short of BUILD SLOTS?" with a number.
	#
	# That question was answered by argument once already and the argument
	# was wrong: raising squad_cap 15 -> 40 was expected to hit an economy
	# wall, on the reasoning that a fixed 7 gatherers could not fund 33
	# military squads. There is no upkeep in this game — a unit costs a
	# one-time price and nothing drains per tick — so a worker count cannot
	# cap army SIZE at all, only the rate of buying. The real ceiling is
	# one barracks producing serially at 5-16 s a squad.
	if state.last_notice.contains("afford"):
		afford_refusals += 1
	elif state.last_notice.contains("cap") or state.last_notice.contains("limit"):
		cap_refusals += 1

	# React, not just report. "Nothing to gather there" means a node it is
	# standing on is empty; without clearing the assignment the same
	# worker is sent at the same empty node forever.
	if state.last_notice.contains("gather"):
		for squad in _assigned:
			_exhausted[int(_assigned[squad])] = true
		_assigned.clear()


## Forget the assignment of any squad that no longer exists, so a dead
## worker does not hold a node reservation for the rest of the match.
func _forget_dead_assignments() -> void:
	var living := {}
	for squad in _own_squads():
		living[int(squad)] = true
	for squad in _assigned.keys():
		if not living.has(int(squad)):
			_assigned.erase(squad)


## Where to send the army, or (-1,-1) if it has seen nothing.
##
## An enemy BUILDING outranks any enemy squad, however far away, and that
## ordering is the whole point rather than a tie-break.
##
## The first version simply took the nearest enemy thing. Every ladder
## match then ended in a draw at the time cap while the AI attacked
## eighteen to twenty-one times: a scout wandering near its base always
## scored better than the opponent's town, so the army chased skirmishers
## back and forth across the map forever. Killing squads also settles
## nothing on its own — the buildings behind them keep producing
## replacements, so an AI that only ever fights squads is fighting a
## respawning enemy by choice.
##
## Buildings are the objective for the reason a human would give: they do
## not run away, they are where the replacements come from, and D-033
## ends a match on squads AND buildings. Marching at one engages whatever
## defends it on the way, because this is an attack-MOVE — the skirmishers
## still get fought, they just stop setting the agenda.
##
## ## What counts as an enemy
##
## Both scans go through `_hostile`, not through an ownership test. They
## used to compare owners, which reads "not mine" as "theirs" — and a
## TEAMMATE is neither. See `_hostile` for what that cost.
func _enemy_target() -> Vector2i:
	var from := state.spawn_cell_of(player)

	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if not _hostile(int(info["owner"])) or bool(info["destroyed"]):
			continue
		var cell := state.space.from_index(int(info["cell"]))
		var d := state.space.distance(from, cell)
		if d < best_distance:
			best_distance = d
			best = cell
	if best.x >= 0:
		return best

	for id in state.composition:
		if not _hostile(int(state.composition[id].get("owner", 0))):
			continue
		if state.alive_of(id) <= 0:
			continue
		var cell := state.squad_cell(id, state_time())
		var d := state.space.distance(from, cell)
		if d < best_distance:
			best_distance = d
			best = cell
	return best


## Somebody this AI may actually fight (D-050).
##
## THE one definition, asked by every scan that used to compare owners.
## `ClientState.are_allied` is the client's mirror of the simulation's own
## rule, and it answers true for a player against itself — so this single
## test replaces the ownership check rather than sitting beside it, and
## there is no second condition left to drift out of agreement with the
## first.
##
## This file contained no reference to teams at all until the fix, which
## is the declared-and-unread family CLAUDE.md warns about wearing its
## other face: the RULE was written, tested and enforced everywhere it
## mattered — `combat.gd` gates all three damage paths on it — and the AI
## was simply never told. What that looked like from a chair: an allied
## AI marching its whole army onto a teammate's town centre and milling
## there for the rest of the match, because friendly fire is correctly
## refused, so the objective never clears and the nearest-first scan
## re-picks the same one forever. A livelock, not a mis-click, and the
## symptom of the correct rule meeting the incorrect targeting.
func _hostile(who: int) -> bool:
	return not state.are_allied(who, player)


## Does `cell` hold friends and nothing else? (#119)
##
## The measurement that says #83 has come back. It is deliberately about
## the GROUND rather than about the decision: an objective is counted
## against this AI when something friendly stands on the cell it ordered
## its army to and nothing hostile does. So it is satisfied by an ally's
## town centre and by an ally's squad, whether the target came from
## `_enemy_target` or from the scouting fallback — the two sites #83 had
## to fix — and it cannot be satisfied by an enemy hall an ally happens to
## be standing next to, which is what the "and nothing hostile" half is
## for.
##
## `are_allied(player, player)` is true, so its OWN base counts as
## friendly here too. Marching an army onto your own town is the same
## mistake wearing a different hat, and there is no reason for the
## instrument to be able to tell them apart.
func _allies_only_at(cell: Vector2i) -> bool:
	var friends := false
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if bool(info["destroyed"]):
			continue
		if state.space.from_index(int(info["cell"])) != cell:
			continue
		if _hostile(int(info["owner"])):
			return false
		friends = true
	for id in state.composition:
		if state.alive_of(id) <= 0:
			continue
		if state.squad_cell(id, state_time()) != cell:
			continue
		if _hostile(int(state.composition[id].get("owner", 0))):
			return false
		friends = true
	return friends


## Somewhere it has not looked. Other players' starting cells first —
## that is where an opponent's town is, and it was told them all at join
## (D-036) — then a wander so it does not stall if those are cleared.
##
## Its OWN TEAM's homes are skipped, not just its own. With shared vision
## (D-050) a teammate's start is the one place on the map guaranteed to
## hold nothing the AI has not already been shown, so a leg spent there is
## a leg spent by construction learning nothing.
func _next_place_to_look() -> Vector2i:
	if state.space == null or state.spawn_cells.is_empty():
		return Vector2i(-1, -1)

	var friendly := _friendly_homes()
	for i in range(state.spawn_cells.size()):
		var index := (i + _look_at) % state.spawn_cells.size()
		var cell := state.space.from_index(state.spawn_cells[index])
		if friendly.has(cell) or _looked.has(index):
			continue
		_looked[index] = true
		_look_at = index + 1
		return cell

	# Everywhere known has been visited and nobody was home: start over,
	# because what it saw is now stale rather than wrong.
	_looked.clear()
	return Vector2i(-1, -1)


## The starting cells of this AI and its teammates, as a set.
##
## Read off the SEAT LIST through `spawn_cell_of`, never by repeating the
## seat-index arithmetic here — that copy is exactly what sent every AI to
## found its capital on somebody else's spawn (see
## `ClientState.spawn_cell_of`). Its own home comes back from the same
## call, so an AI with no teammates gets precisely the set this used to
## test for.
func _friendly_homes() -> Dictionary:
	var out := {}
	var home := state.spawn_cell_of(player)
	if home.x >= 0:
		out[home] = true
	for seat in state.lobby.get("seats", []):
		var who := int(seat["player"])
		if not state.are_allied(who, player):
			continue
		var cell := state.spawn_cell_of(who)
		if cell.x >= 0:
			out[cell] = true
	return out


## Spawn cells already visited, so it does not march on the same empty
## corner forever.
var _looked := {}
var _look_at := 0

# --- static defence (#337, D-076's standing gap) ------------------------
#
# `decisions/D-20260828-an-ai-that-fortifies.md`. D-076 shipped walls,
# gates and a walkable wall-top tier, and its own entry recorded that
# **no AI builds or uses any of it, so `just ai-ladder` cannot exercise
# the feature at all** — the defect class that left `BuildingSim.damage()`
# uncalled for two milestones (D-055).
#
# The decision half is `static_defence.gd`, which names no wall and is
# shared with naval stage 7 (#301). The geometry half is `wall_plan.gd`.
# What is here is the seat: reading its own threat, spending, and USING
# what it built.


## How many defensive buildings this seat will own, ever.
##
## A wall is a means and the army is the end. Without a cap an AI whose
## threat pressure stays high — which is every AI in a match it is losing
## — keeps buying masonry until it has fortified itself out of the game.
## The screen plus one tower is the whole investment.
const DEFENCES_CAP := WallPlan.SEGMENTS + 1


## Raise static defence when the threat and the wallet both argue for it.
##
## Runs AFTER `_raise_buildings`, so the barracks is never outbid: that
## step returns having spent, and this one is reached on a later think.
func _fortify() -> void:
	if state.space == null:
		return
	var standing := _defences_standing()
	var threat := _threat_report()
	var economy := _economy_report()
	if not StaticDefence.wants_to_invest(threat, economy,
			profile.defence_appetite, standing, DEFENCES_CAP):
		return

	var builder := _idle_builder()
	if builder < 0:
		return

	# A tower first, and it is not a preference. A wall does nothing to an
	# attacker; a tower shoots one. D-066 is the standing warning that a
	# defence whose numbers do nothing is a feature that is absent, and the
	# tower is the only member of this family with a `damage` at all.
	var tower := WallPlan.cheapest_defensive_tower(&"gatherers")
	if tower != null and _owned_building_count(tower.id) == 0 and _pay_for(tower):
		_place_defence(builder, tower, _defence_site(tower))
		return
	# NOT `return` when the tower is unaffordable. That is the SAVE-rather-
	# than-skip rule, and it is right for the barracks — where skipping
	# ahead buys a storehouse with the wood the barracks needed — and
	# wrong here: a wall segment is 30 wood and 40 stone against a tower's
	# 40 and 120, so saving for the tower means a seat under attack builds
	# nothing at all for the rest of the match. Measured: a seat with
	# `buildings_lost=2 attacks_survived=43` ordered zero defences.

	# Then the screen, gate first (`WallPlan.screen` returns it first,
	# because it is the cell squarely on the approach).
	var wall := WallPlan.cheapest_wall(false)
	var gate := WallPlan.cheapest_wall(true)
	if wall == null:
		return
	var cells := _screen_cells()
	if cells.is_empty():
		return
	var next := _next_screen_cell(cells)
	if next.x < 0:
		return
	var def := gate if (gate != null and next == cells[0]) else wall
	if not _pay_for(def):
		return
	# One order per site, then WAIT for it to appear.
	#
	# Without this the AI re-issues the same refused order every think
	# forever, because `_next_screen_cell` looks for a building that a
	# refusal means will never be there. Measured on a real teamed match:
	# **40 orders, 1 standing.** That is D-107's lesson in the other
	# direction — not a latch on an intent read as an outcome, but no
	# latch at all, so an intent was repeated instead of being checked.
	#
	# The timeout is generous because a builder WALKS: the screen stands
	# five cells out and a crew starts wherever it was hauling.
	var index := state.space.index(next)
	if _defence_tried.has(index) and state_time() < float(_defence_tried[index]):
		return
	_defence_tried[index] = state_time() + DEFENCE_RETRY_SECONDS
	_place_defence(builder, def, next)


## Every defensive building this seat has standing — walls, gates and
## anything that shoots. Read off its own `ClientState`, like everything
## else the AI knows.
func _defences_standing() -> int:
	var count := 0
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) != player or bool(info["destroyed"]):
			continue
		var def := BuildingSim.def_by_id(StringName(String(info["def_id"])))
		if def == null:
			continue
		if WallPlan.is_static_defence(def):
			count += 1
	return count


## What this seat believes about the danger it is in.
##
## Everything here comes from its own `ClientState` — the packets the
## server chose to send it through `visible_to` (D-025). An AI that read
## the simulation would fortify against an army it could not see, and
## D-051's whole point is that it cannot.
func _threat_report() -> Dictionary:
	var home := _home_cell()
	var near := 0
	var nearest := -1
	if home.x >= 0 and state.space != null:
		for id in state.composition:
			var owner := int(state.composition[id].get("owner", 0))
			if owner == player or state.alive_of(id) <= 0 or not _hostile(owner):
				continue
			var cell := state.squad_cell(id, state_time())
			if cell.x < 0:
				continue
			var away := state.space.distance(home, cell)
			if nearest < 0 or away < nearest:
				nearest = away
			if away <= StaticDefence.THREAT_CELLS:
				near += 1
		for wire_id in state.buildings:
			var info: Dictionary = state.buildings[wire_id]
			if bool(info["destroyed"]) or not _hostile(int(info["owner"])):
				continue
			var away := state.space.distance(home,
				state.space.from_index(int(info["cell"])))
			if nearest < 0 or away < nearest:
				nearest = away
	# The horizon is HALF THE WAY to the nearest other start: that is this
	# seat's own ground, and the distance a threat has to be inside before
	# it is this seat's problem. Relative rather than fixed, because a flat
	# radius contributed nothing on the shipped ladder map — the starts are
	# further apart than any constant worth having.
	var horizon := 0
	var neighbour := _nearest_other_start()
	if home.x >= 0 and neighbour.x >= 0 and state.space != null:
		horizon = state.space.distance(home, neighbour) / 2
	return {
		"hostiles_near": near,
		"nearest_hostile": nearest,
		"horizon": horizon,
		"enemy_base_known": peak_enemy_buildings_known > 0,
		"buildings_lost": buildings_lost,
		"attacks_survived": attacks_survived,
	}


func _economy_report() -> Dictionary:
	var army := 0
	for squad in _own_squads():
		var def := UnitRoster.by_id(StringName(state.composition[squad]["def_id"]))
		if def != null and def.carry_capacity <= 0:
			army += 1
	var military := 0
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) != player or bool(info["destroyed"]):
			continue
		var def := BuildingSim.def_by_id(StringName(String(info["def_id"])))
		if def != null and not def.produces.is_empty() and not def.consumes_builder:
			military += 1
	return {"military_buildings": military, "army_squads": army}


## Affordability WITH the economy's floors held back, so a wall is never
## bought with the wood a barracks was waiting on.
func _pay_for(def: BuildingDef) -> bool:
	var floors := PackedInt32Array()
	floors.resize(Economy.RESOURCE_COUNT)
	floors[Economy.ResourceKind.FOOD] = profile.food_floor
	floors[Economy.ResourceKind.WOOD] = profile.wood_floor
	return StaticDefence.can_afford_with_reserve(state.wallet,
		StaticDefence.cost_of(def), floors)


## The screen this seat would raise, against whatever it is most afraid
## of. Recomputed rather than remembered: the threat moves, and a screen
## laid against a raider who has since gone home is a screen facing the
## wrong way with no way to notice.
func _screen_cells() -> Array:
	var home := _home_cell()
	if home.x < 0:
		return []
	var threat := _nearest_hostile_cell()
	if threat.x < 0:
		return []
	# Blocked is anything the server will refuse: a cell with a building on
	# it, and any cell inside a HOSTILE building's `no_build_radius`
	# (D-062 — nobody hostile may found inside it).
	#
	# The second half is not tidiness. On a scenario where the bases start
	# close, a screen five cells toward the enemy lands inside their claim,
	# every order is refused, and the AI spends the match ordering walls
	# that never appear. The refusal is a rule the AI can READ — it can see
	# their buildings — so asking anyway is asking to be told no.
	var blocked := {}
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if bool(info["destroyed"]):
			continue
		var at := int(info["cell"])
		blocked[at] = true
		if not _hostile(int(info["owner"])):
			continue
		var def := BuildingSim.def_by_id(StringName(String(info["def_id"])))
		if def == null or def.no_build_radius <= 0:
			continue
		var centre := state.space.from_index(at)
		for offset in TorusSpace.disk_offsets(def.no_build_radius):
			blocked[state.space.index(centre + offset)] = true
	return WallPlan.screen(state.space, home, threat, blocked)


## The first cell of the screen with nothing on it yet.
func _next_screen_cell(cells: Array) -> Vector2i:
	var taken := {}
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) == player and not bool(info["destroyed"]):
			taken[int(info["cell"])] = true
	for cell in cells:
		if not taken.has(state.space.index(cell)):
			return cell
	return Vector2i(-1, -1)


## Where a tower goes: between home and the threat, but INSIDE the screen,
## so it covers the gate rather than standing in front of it.
func _defence_site(def: BuildingDef) -> Vector2i:
	var home := _home_cell()
	if home.x < 0:
		return Vector2i(-1, -1)
	var threat := _nearest_hostile_cell()
	if threat.x < 0:
		return home
	var inside := WallPlan.screen(state.space, home, threat, {}, 1,
		maxi(1, WallPlan.STANDOFF_CELLS - 2))
	if inside.is_empty():
		return home
	return inside[0]


func _nearest_hostile_cell() -> Vector2i:
	var home := _home_cell()
	if home.x < 0 or state.space == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_away := 1 << 30
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if bool(info["destroyed"]) or not _hostile(int(info["owner"])):
			continue
		var cell := state.space.from_index(int(info["cell"]))
		var away := state.space.distance(home, cell)
		if away < best_away:
			best_away = away
			best = cell
	for id in state.composition:
		var owner := int(state.composition[id].get("owner", 0))
		if owner == player or state.alive_of(id) <= 0 or not _hostile(owner):
			continue
		var cell := state.squad_cell(id, state_time())
		if cell.x < 0:
			continue
		var away := state.space.distance(home, cell)
		if away < best_away:
			best_away = away
			best = cell
	if best.x < 0:
		# Nothing seen yet. The starting positions were sent at join
		# (D-036) and an opponent's town is at one of them, so a seat that
		# has met nobody still knows which way trouble comes from. Same
		# source `_next_place_to_look` scouts toward, for the same reason.
		return _nearest_other_start()
	return best


func _nearest_other_start() -> Vector2i:
	var home := _home_cell()
	if home.x < 0 or state.space == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_away := 1 << 30
	for index in state.spawn_cells:
		var cell := state.space.from_index(int(index))
		if cell == home:
			continue
		var away := state.space.distance(home, cell)
		if away < best_away:
			best_away = away
			best = cell
	return best


func _home_cell() -> Vector2i:
	var home := state.spawn_cell_of(player)
	if home.x >= 0:
		return home
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) == player and not bool(info["destroyed"]):
			return state.space.from_index(int(info["cell"]))
	return Vector2i(-1, -1)


func _place_defence(builder: int, def: BuildingDef, site: Vector2i) -> void:
	if site.x < 0:
		return
	var order := state.encode_build(builder, String(def.id), site)
	if order.is_empty():
		return
	_builder_squad = builder
	_builder_busy_until = state_time() + profile.think_interval * 3.0
	defences_ordered += 1
	print("server: AI_FORTIFY player=%d %s at %s" % [player, def.id, site])
	send.call(order)


## SEAL a gate that hostiles are standing at; let it go back to AUTO when
## they are gone.
##
## This is the USING half of #337, and getting it right meant throwing the
## obvious version away.
##
## The obvious version was "set every gate to AUTO", and it is **vacuous**:
## `BuildingSim._gate_mode`'s own comment says new gates start in auto
## mode, so an AI that ordered AUTO would send a packet that changed
## nothing, and a ladder gate counting those packets would have passed
## against an AI that never used a gate at all. That is precisely the
## shape of check this project forbids — the whole reason #337 exists is
## that a feature can look exercised and not be.
##
## What is NOT vacuous is closing it. An auto gate opens whenever one of
## the owner's own squads is within `AUTO_GATE_RADIUS` — which includes a
## squad fighting an attacker on the doorstep, so at the exact moment a
## gate matters most it stands open for whoever is winning that fight.
## Sealing it is a decision, it is reversible, and it uses both gate
## opcodes rather than one.
##
## Latched on the EFFECT — the gate's replicated `gate_mode` and
## `gate_open` coming back — never on having sent the packet. D-107 is the
## standing reason: a latch that records an INTENT is eventually read as a
## record of an outcome, and reading one that way cost this project every
## AI match it had ever played.
func _hold_the_gates() -> void:
	if state.space == null:
		return
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) != player or bool(info["destroyed"]):
			continue
		var def := BuildingSim.def_by_id(StringName(String(info["def_id"])))
		if def == null or not def.is_gate:
			continue

		var cell := state.space.from_index(int(info["cell"]))
		var besieged := _hostiles_within(cell, GATE_SEAL_CELLS) > 0
		var mode := int(info.get("gate_mode", BuildingSim.GATE_MODE_AUTO))
		var open := bool(info.get("gate_open", false))

		if besieged:
			# Two orders, and both are needed: MANUAL alone leaves it
			# however the auto pass last set it, which under an attack is
			# open. The server refuses a state order on a gate still in
			# auto mode, so the mode has to land first — which it does on
			# an earlier think, because this reads the mode BACK before
			# asking to close.
			if mode != BuildingSim.GATE_MODE_MANUAL:
				gate_orders += 1
				send.call(NetProtocol.encode_order_gate_mode(
					int(wire_id), BuildingSim.GATE_MODE_MANUAL))
				continue
			if open:
				gate_orders += 1
				gates_sealed += 1
				print("server: AI_GATE player=%d sealed %d" % [player, int(wire_id)])
				send.call(NetProtocol.encode_order_gate_state(int(wire_id), false))
			continue

		# Clear. Hand it back to the auto rule rather than leaving it
		# shut: a gate a player's own army cannot get through is a wall
		# they paid extra for.
		if mode != BuildingSim.GATE_MODE_AUTO:
			gate_orders += 1
			send.call(NetProtocol.encode_order_gate_mode(
				int(wire_id), BuildingSim.GATE_MODE_AUTO))


## How near a hostile has to be to a gate before it is worth shutting.
##
## Smaller than `StaticDefence.THREAT_CELLS`, which is the radius at which
## a threat argues for BUILDING something. Shutting a gate is a reaction
## to somebody at the door; fortifying is a response to somebody in the
## region, and one number for both would either seal the gates all match
## or never seal them at all.
const GATE_SEAL_CELLS := 6


func _hostiles_within(cell: Vector2i, cells: int) -> int:
	var count := 0
	for id in state.composition:
		var owner := int(state.composition[id].get("owner", 0))
		if owner == player or state.alive_of(id) <= 0 or not _hostile(owner):
			continue
		var where := state.squad_cell(id, state_time())
		if where.x < 0:
			continue
		if state.space.distance(cell, where) <= cells:
			count += 1
	return count
