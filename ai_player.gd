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
const GATHERERS_WANTED := 7

## Seconds between production orders, so the queue cannot outrun the
## target the AI is aiming at. A profile field in the next slice.
const TRAIN_COOLDOWN := 5.0

var player: int = 0
var civ: StringName = &""
var state := ClientState.new()

## Where this AI's orders go. Set by the server to its own dispatcher, so
## a packet from here takes the identical path to one off the wire.
var send: Callable = Callable()

var _next_think := 0.0
var _founded := false
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

	_record_stats()
	_report_refusals()
	_forget_dead_assignments()
	_found_town()
	_raise_buildings()
	_train()
	_put_gatherers_to_work()
	_fight(now)


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


## The opening every player makes: plant the town hall (D-031). The
## founding party is spent doing it, so this happens once and the AI owns
## nothing until production starts.
func _found_town() -> void:
	if _founded or state.squads.is_empty():
		return
	var squad := int(state.squads[0])
	var home := state.spawn_cell_of(player)
	if home.x < 0:
		home = state.squad_cell(squad, state_time())
	var order := state.encode_build(squad, "town_centre", home)
	if order.is_empty():
		return
	_founded = true
	send.call(order)


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
	var workers := _squads_matching(func(def): return def.carry_capacity > 0).size()
	var wanted := &"gatherers" if workers < GATHERERS_WANTED else _military_archetype()
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

	var wanted_kind := _scarcest_kind()
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
		if _assigned.has(squad):
			continue

		var cell := _nearest_node_of_kind(state.squad_cell(squad, state_time()), wanted_kind)
		if cell < 0:
			continue
		_assigned[squad] = cell
		send.call(NetProtocol.encode_order_gather(squad, cell))


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
	# Something is better than idling if the wanted kind is all gone.
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
		else:
			theirs += 1
	buildings_raised = maxi(buildings_raised, mine)

	# Has it ever LAID EYES on an opponent's base? Making buildings the
	# attack objective changed the ladder by literally nothing — every
	# stat identical to three significant figures, which is not a small
	# effect but no effect, so the branch cannot be running. This is the
	# measurement that says whether that is because it never finds one.
	# Buildings are persistent-explored (D-030), so once seen this only
	# ever grows and a peak is the honest summary.
	peak_enemy_buildings_known = maxi(peak_enemy_buildings_known, theirs)


## One line the ladder can parse. Structured markers, not prose — the
## same rule the load test's verdict follows.
func stats_line() -> String:
	return "AI_STATS player=%d civ=%s squads_peak=%d workers_peak=%d buildings=%d enemy_buildings_seen=%d attacks=%d first_attack=%.1f" % [
		player, civ, peak_squads, peak_workers, buildings_raised,
		peak_enemy_buildings_known, attacks_launched, first_attack_at]


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
func _enemy_target() -> Vector2i:
	var from := state.spawn_cell_of(player)

	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) == player or bool(info["destroyed"]):
			continue
		var cell := state.space.from_index(int(info["cell"]))
		var d := state.space.distance(from, cell)
		if d < best_distance:
			best_distance = d
			best = cell
	if best.x >= 0:
		return best

	for id in state.composition:
		if int(state.composition[id].get("owner", 0)) == player:
			continue
		if state.alive_of(id) <= 0:
			continue
		var cell := state.squad_cell(id, state_time())
		var d := state.space.distance(from, cell)
		if d < best_distance:
			best_distance = d
			best = cell
	return best


## Somewhere it has not looked. Other players' starting cells first —
## that is where an opponent's town is, and it was told them all at join
## (D-036) — then a wander so it does not stall if those are cleared.
func _next_place_to_look() -> Vector2i:
	if state.space == null or state.spawn_cells.is_empty():
		return Vector2i(-1, -1)

	for i in range(state.spawn_cells.size()):
		var index := (i + _look_at) % state.spawn_cells.size()
		var cell := state.space.from_index(state.spawn_cells[index])
		if cell == state.spawn_cell_of(player) or _looked.has(index):
			continue
		_looked[index] = true
		_look_at = index + 1
		return cell

	# Everywhere known has been visited and nobody was home: start over,
	# because what it saw is now stale rather than wrong.
	_looked.clear()
	return Vector2i(-1, -1)


## Spawn cells already visited, so it does not march on the same empty
## corner forever.
var _looked := {}
var _look_at := 0
