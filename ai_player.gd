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

## How often the AI reconsiders, in seconds. Ten times slower than the
## simulation tick on purpose — a human does not issue orders at 10 Hz,
## and thinking every tick would spend real CPU to play worse.
const THINK_INTERVAL := 1.0

## How many gatherer squads to field before spending on soldiers.
##
## Was 3, which is why it never fought: three crews haul too slowly to
## reach a barracks' 150 wood inside a match, so it sat at three squads
## with no way to build anything that trains an army. The economy has to
## outrun the first building before the army can exist at all.
##
## Becomes a profile field in the next slice (D-053); it is a constant
## here only until profiles land.
## Counted in SOLDIERS, not squads.
##
## It was 7 SQUADS, which is a number about crews rather than about
## labour — so when gatherer squads went from 16 men to 5 the AI's economy
## silently fell to a third without anyone changing the AI. A target
## expressed in the thing that actually gathers (gather_rate is per living
## soldier, D-028) survives a roster change instead of quietly breaking.
const GATHERER_SOLDIERS_WANTED := 110

## Seconds between production orders, so the queue cannot outrun the
## target the AI is aiming at. A profile field in the next slice.
##
## ## Per ORDER, and that is deliberate — do not "fix" it
##
## Because it gates orders rather than labour, shrinking gatherer crews
## from 16 to 5 tripled the time to staff an economy: the same ~110
## workers now take 22 productions instead of 7, so 110 s of cooldown
## instead of 35 s. First contact moved from 121-160 s to ~326 s.
##
## I flagged that as a bug to fix. It is not: the owner's call is that
## the old ramp was FAR too quick, and a slower build-up is wanted
## (2026-08-04). It pulls the same direction as D-056's 1-2 hour target —
## an opening you can be attacked out of in two minutes is not a strategy
## game, it is a race.
##
## So a future reader finding "the cooldown scales with order count rather
## than headcount" should leave it alone unless the pacing target changes.
## The thing to re-derive when it does is `ai-ladder`'s SECONDS default,
## which has already been stale once for exactly this reason.
const TRAIN_COOLDOWN := 5.0

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
	_next_think = now + THINK_INTERVAL

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
	_scout_for_resources()
	_found_town()
	_raise_buildings()
	_train()
	_put_gatherers_to_work()
	if not economy_only:
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
		if _owned_building_count(def.id) > 0:
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
		_builder_busy_until = state_time() + THINK_INTERVAL * 3.0
		print("server: AI_BUILD player=%d %s at %s" % [player, def.id, site])
		send.call(order)
		return


## What to build, in priority order: anything that trains soldiers first,
## because that is what makes this a game.
func _wanted_buildings() -> Array:
	var military := []
	var support := []
	for def in BuildingSim.all_defs():
		if def.id == &"town_centre":
			continue
		if not BuildingSim.can_build(def, &"gatherers"):
			continue
		if def.produces.size() > 0:
			military.append(def)
		else:
			support.append(def)
	return military + support


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

## The worker currently committed to a build order, held off hauling
## until the order has had time to land.
var _builder_squad := -1
var _builder_busy_until := 0.0


## How long to wait before trying to found again. An order can be refused
## for reasons a client cannot see (D-034's notices say why, but only after
## the fact), and the fix for "the one attempt was lost" must not become
## "attempt every second forever".
const FOUND_RETRY := 5.0


## The opening every player makes: plant the town hall (D-031). The
## founding party is spent doing it, so this happens once and the AI owns
## nothing until production starts.
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
## "gatherers cannot build a Town Centre" once the founders are gone. Two
## conditions bound it instead, and both are things the AI can SEE — it
## stops when the town centre exists, and it cannot start when it holds no
## squad allowed to found one. Between them there is nothing to spam.
func _found_town() -> void:
	if _owned_building_count(&"town_centre") > 0:
		return
	if state_time() < _found_at:
		return
	var squad := _founder()
	if squad < 0:
		return
	var home := state.spawn_cell_of(player)
	if home.x < 0:
		home = state.squad_cell(squad, state_time())
	var order := state.encode_build(squad, "town_centre", home)
	if order.is_empty():
		return
	_found_at = state_time() + FOUND_RETRY
	send.call(order)


## A squad of this AI's that may actually found a town centre, or -1.
##
## Asked of the shipped BuildingDef's `built_by` rather than named here, so
## this file still names no unit and no civ (D-047) — and so it answers
## "the founders are spent" correctly the moment they are, which is what
## stops the retry above from ever becoming a spin.
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
	# The target is 110 soldiers and a crew is 5, so it is met at exactly
	# 22 squads. A single casualty anywhere drops the count to 109, the
	# test flips back to "make gatherers", and the AI spends the rest of
	# the match rebuilding one worker instead of an army. One ladder seat
	# did exactly that: 22 squads, all of them workers, three buildings,
	# 1,680 wood banked and not one soldier trained in 700 seconds — while
	# its opponent on the same code reached 44 squads and attacked 59
	# times.
	#
	# So: once the economy has EVER been staffed, stay switched. It only
	# goes back if the workforce is genuinely gutted (a raid, not a
	# scratch), which is the case where rebuilding really is the priority.
	if worker_soldiers >= GATHERER_SOLDIERS_WANTED:
		_economy_staffed = true
	elif worker_soldiers < GATHERER_SOLDIERS_WANTED * 0.6:
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
		_train_at = state_time() + TRAIN_COOLDOWN
		send.call(NetProtocol.encode_order_produce(int(wire_id), wanted))
		return


## Some archetype this civ actually fields, chosen from the roster rather
## than named here. A civ without cavalry trains whatever it does have.
func _military_archetype() -> StringName:
	# Only something a building it OWNS can actually make.
	#
	# Without this it picked `founders` — a fighting unit with no carry
	# capacity, so it passed every test for "military" — and asked the
	# barracks for them. Barracks do not make founders (only the opening
	# party is), so the order was never sent and it trained nothing but
	# gatherers for the entire match, with a finished barracks standing
	# there. The ladder showed 15 squads, 15 workers, 0 attacks.
	for archetype in _producible_archetypes():
		var def := UnitRoster.for_civ_archetype(civ, archetype)
		if def != null and def.damage > 1.0 and def.carry_capacity <= 0:
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
	if state.space == null or state.nodes.is_empty():
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
		var kind := int(state.nodes.get(int(_assigned[squad]), -1))
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


func _scout_for_resources() -> void:
	if state.space == null or not state.welcomed:
		return

	# Only if something it needs has never been seen. Once a node of that
	# kind is known, ordinary gathering takes over and this stops.
	var missing := -1
	for kind in _kinds_below_floor():
		if _nearest_known_of_kind(kind) < 0:
			missing = kind
			break
	if missing < 0:
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


## The resources currently under their floor. Food always qualifies, so a
## crew is never left with nothing to do when everything is stocked.
func _kinds_below_floor() -> Array:
	var out := []
	if state.wallet.size() >= 4:
		if state.wallet[1] < WOOD_FLOOR:
			out.append(Economy.ResourceKind.WOOD)
	out.append(Economy.ResourceKind.FOOD)
	return out


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
	if state.wallet[0] < FOOD_FLOOR:
		return Economy.ResourceKind.FOOD
	if state.wallet[1] < WOOD_FLOOR:
		return Economy.ResourceKind.WOOD
	return Economy.ResourceKind.FOOD


## Enough food to keep training, and enough wood for the first building
## that makes soldiers. Profile fields in the next slice (D-053).
const FOOD_FLOOR := 180
const WOOD_FLOOR := 200


func _nearest_node_of_kind(from: Vector2i, kind: int) -> int:
	var best := -1
	var best_distance := 1 << 30
	var fallback := -1
	var fallback_distance := 1 << 30
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
	if army.size() < 2:
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

	# Attacked in a body rather than one squad at a time, so the AI
	# arrives as an army instead of feeding itself in piecemeal.
	_attack_at = now + THINK_INTERVAL * 8.0
	attacks_launched += 1
	if first_attack_at < 0.0:
		first_attack_at = now
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


func _record_stats() -> void:
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
	return "AI_STATS player=%d civ=%s squads_peak=%d workers_peak=%d buildings=%d enemy_buildings_seen=%d attacks=%d first_attack=%.1f peak_stockpile=%d peak_food=%d peak_wood=%d substituted=%d unreachable=%d scout_legs=%d afford_refusals=%d cap_refusals=%d" % [
		player, civ, peak_squads, peak_workers, buildings_raised,
		peak_enemy_buildings_known, attacks_launched, first_attack_at,
		peak_stockpile, peak_food, peak_wood, substituted_kind, unreachable_nodes, scout_legs, afford_refusals, cap_refusals]


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
