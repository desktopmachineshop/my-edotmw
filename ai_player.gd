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

## Squads kept back to gather rather than sent to fight.
const GATHERERS_WANTED := 3

var player: int = 0
var civ: StringName = &""
var state := ClientState.new()

## Where this AI's orders go. Set by the server to its own dispatcher, so
## a packet from here takes the identical path to one off the wire.
var send: Callable = Callable()

var _next_think := 0.0
var _founded := false
var _attack_at := 0.0


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
	_found_town()
	_train()
	_put_gatherers_to_work()
	_fight(now)


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
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) != player or bool(info["destroyed"]):
			continue
		if float(info["progress"]) < 1.0:
			continue
		var wanted := &"gatherers" if _own_squads().size() < GATHERERS_WANTED else _military_archetype()
		if wanted == &"":
			continue
		send.call(NetProtocol.encode_order_produce(int(wire_id), wanted))
		return


## Some archetype this civ actually fields, chosen from the roster rather
## than named here. A civ without cavalry trains whatever it does have.
func _military_archetype() -> StringName:
	for archetype in UnitRoster.archetypes_for(civ):
		var def := UnitRoster.for_civ_archetype(civ, archetype)
		if def != null and def.damage > 1.0 and def.carry_capacity <= 0:
			return archetype
	return &""


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
	var gatherers := []
	for squad in _own_squads():
		var def := UnitRoster.by_id(StringName(state.composition[squad]["def_id"]))
		if def != null and def.carry_capacity > 0:
			gatherers.append(squad)
	if gatherers.is_empty():
		return

	for squad in gatherers:
		var from := state.squad_cell(squad, state_time())
		var best := -1
		var best_distance := 1 << 30
		for cell in state.nodes:
			var d := state.space.distance(from, state.space.from_index(int(cell)))
			if d < best_distance:
				best_distance = d
				best = int(cell)
		if best >= 0:
			send.call(NetProtocol.encode_order_gather(squad, best))


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

	var target := Vector2i(-1, -1)
	for id in state.composition:
		if int(state.composition[id].get("owner", 0)) == player:
			continue
		if state.alive_of(id) <= 0:
			continue
		target = state.squad_cell(id, state_time())
		break
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
	for wire_id in state.buildings:
		var info: Dictionary = state.buildings[wire_id]
		if int(info["owner"]) == player and not bool(info["destroyed"]):
			mine += 1
	buildings_raised = maxi(buildings_raised, mine)


## One line the ladder can parse. Structured markers, not prose — the
## same rule the load test's verdict follows.
func stats_line() -> String:
	return "AI_STATS player=%d civ=%s squads_peak=%d workers_peak=%d buildings=%d attacks=%d first_attack=%.1f" % [
		player, civ, peak_squads, peak_workers, buildings_raised,
		attacks_launched, first_attack_at]
