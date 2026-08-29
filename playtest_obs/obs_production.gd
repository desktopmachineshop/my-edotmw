extends SceneTree

## OBSERVATION HARNESS for playtest ticket #37 (production, costs, squad
## cap, rally points).
##
## Drives the REAL server handlers (`server._handle_order_produce`,
## `_handle_order_rally`) over a LoopbackPeer, the way tests/test_civ_knobs.gd
## established is legitimate: a Node never added to the tree does not run
## `_ready()`, so no socket and no scene tree are needed. That matters
## here because #37's regressions were all in the ORDER path, not the
## arithmetic: the D-038 ownership cache refused orders to produced
## squads, and D-061's rally order was never sent at all.
##
## What it CANNOT see, and what therefore stays with the owner: whether
## the rally marker draws on the ground, whether the n/cap readout on the
## HUD matches, and whether a refusal is legible on screen. Those are
## client.gd pixels.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_production.gd

const W := 32
const H := 16


func _initialize() -> void:
	print("OBS37: begin")
	_every_listed_unit_is_producible()
	_costs_are_deducted_once_and_all_or_nothing()
	_cap_refuses_with_feedback()
	_rally_is_obeyed_by_squads_nobody_touched()
	print("OBS37: end")
	quit()


## A server far enough along to answer orders, and no further.
## Same shape as tests/test_civ_knobs.gd's fixture.
func _server_for(civ: StringName, cap: int, rich := true) -> Dictionary:
	var server = load("res://server.gd").new()
	var space := TorusSpace.new(W, H, 1.0)
	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	server._sim.set_passable(p)

	server._match = MatchState.new()
	server._match.squad_cap = cap
	server._match.add_player(1)
	server._match.phase = MatchState.Phase.RUNNING
	server._civs[1] = civ
	server._hand_civs_to_sim()

	var made := {}
	for bid in [&"town_centre", &"barracks"]:
		var bdef := BuildingSim.def_by_id(bid)
		if bdef == null:
			continue
		made[bid] = server._buildings.add_building(bdef, 1, Vector2i(6 + made.size() * 8, 8), true)

	if rich:
		for kind in range(Economy.RESOURCE_COUNT):
			server._economy.credit(1, kind, 1000000)

	var peer := LoopbackPeer.new()
	server._ai_clients[peer] = {"player": 1, "visible": {}}
	return {"server": server, "peer": peer, "b": made, "space": space}


func _notice(w: Dictionary) -> String:
	return w["peer"].state.last_notice


# --- 1. everything a building lists must be producible -----------------

func _every_listed_unit_is_producible() -> void:
	print("")
	print("OBS37 ROSTER - every archetype each building lists, for every civ.")
	print("  'resolved' = the civ fields it (D-047 lets a civ field a subset,")
	print("  so a blank is expected, not a fault). 'queued' = the REAL server")
	print("  handler accepted the order.")
	for civ_def in CivRoster.load_all():
		var w := _server_for(civ_def.id, 400)
		var server = w["server"]
		var made: Dictionary = w["b"]
		var lines := []
		for bid in made.keys():
			var bdef := BuildingSim.def_by_id(bid)
			for archetype in bdef.produces:
				var unit := UnitRoster.for_civ_archetype(civ_def.id, archetype)
				if unit == null:
					continue
				var before: int = server._buildings.queue_length(made[bid])
				server._handle_order_produce(w["peer"], NetProtocol.encode_order_produce(
					BuildingSim.wire_id(made[bid]), String(archetype)))
				var after: int = server._buildings.queue_length(made[bid])
				var ok: bool = after > before
				lines.append("%s:%s=%s" % [bid, archetype, "ok" if ok else
					("REFUSED(%s)" % _notice(w))])
		print("  %-14s %s" % [civ_def.id, " ".join(lines)])


# --- 2. costs ----------------------------------------------------------

func _costs_are_deducted_once_and_all_or_nothing() -> void:
	print("")
	print("OBS37 COSTS - deducted exactly once, and all-or-nothing when short.")
	for civ_def in CivRoster.load_all():
		var w := _server_for(civ_def.id, 400)
		var server = w["server"]
		var barracks: int = w["b"].get(&"barracks", -1)
		if barracks < 0:
			continue
		var unit: UnitDef = null
		for archetype in BuildingSim.def_by_id(&"barracks").produces:
			var u := UnitRoster.for_civ_archetype(civ_def.id, archetype)
			if u != null and not u.is_general:
				unit = u
				break
		if unit == null:
			continue
		var before: PackedInt32Array = server._economy.wallet_of(1).duplicate()
		server._handle_order_produce(w["peer"], NetProtocol.encode_order_produce(
			BuildingSim.wire_id(barracks), String(unit.archetype)))
		var after: PackedInt32Array = server._economy.wallet_of(1).duplicate()
		var spent := [before[0] - after[0], before[1] - after[1],
			before[2] - after[2], before[3] - after[3]]
		var want := [unit.cost_food, unit.cost_wood, unit.cost_gold, unit.cost_stone]
		var exact := spent == want

		# Now the all-or-nothing half: a wallet one unit short in the
		# single most expensive resource this unit needs.
		var poor := _server_for(civ_def.id, 400, false)
		var pserver = poor["server"]
		var pbar: int = poor["b"].get(&"barracks", -1)
		for kind in range(Economy.RESOURCE_COUNT):
			pserver._economy.credit(1, kind, want[kind])
		# take one away from whichever resource it actually needs
		for kind in range(Economy.RESOURCE_COUNT):
			if want[kind] > 0:
				pserver._economy.credit(1, kind, -1)
				break
		var pbefore: PackedInt32Array = pserver._economy.wallet_of(1).duplicate()
		pserver._handle_order_produce(poor["peer"], NetProtocol.encode_order_produce(
			BuildingSim.wire_id(pbar), String(unit.archetype)))
		var pafter: PackedInt32Array = pserver._economy.wallet_of(1).duplicate()
		var untouched: bool = pbefore == pafter
		var refused: bool = pserver._buildings.queue_length(pbar) == 0
		print("  %-14s %-24s spent=%s want=%s exact=%s | one short: refused=%s wallet untouched=%s notice=%s"
			% [civ_def.id, unit.id, spent, want, exact, refused, untouched,
			   _notice(poor) if _notice(poor) != "" else "<none>"])


# --- 3. the squad cap --------------------------------------------------

func _cap_refuses_with_feedback() -> void:
	print("")
	print("OBS37 SQUAD CAP - the refusal, and whether it names the civ's OWN cap.")
	for civ_def in CivRoster.load_all():
		var base_cap := 6
		var w := _server_for(civ_def.id, base_cap)
		var server = w["server"]
		var barracks: int = w["b"].get(&"barracks", -1)
		var unit: UnitDef = null
		for archetype in BuildingSim.def_by_id(&"barracks").produces:
			var u := UnitRoster.for_civ_archetype(civ_def.id, archetype)
			if u != null and not u.is_general:
				unit = u
				break
		if unit == null or barracks < 0:
			continue
		var effective: int = server._match.squad_cap_for(server._sim, 1)
		# Fill the roster to exactly the cap with real squads.
		for i in range(effective):
			server._sim.add_squad(unit, 1, Vector2i(2 + i % 20, 2 + i / 20))
		var accepted_at_cap := false
		server._handle_order_produce(w["peer"], NetProtocol.encode_order_produce(
			BuildingSim.wire_id(barracks), String(unit.archetype)))
		accepted_at_cap = server._buildings.queue_length(barracks) > 0
		print("  %-14s base cap %d -> civ cap %d (bonus %d) | order at cap accepted=%s | notice=%s"
			% [civ_def.id, base_cap, effective, civ_def.squad_cap_bonus,
			   accepted_at_cap, _notice(w) if _notice(w) != "" else "<none>"])


# --- 4. rally ----------------------------------------------------------

func _rally_is_obeyed_by_squads_nobody_touched() -> void:
	print("")
	print("OBS37 RALLY - set through the server's own order handler, then a")
	print("  squad is PRODUCED and never touched again. Its destination must")
	print("  become the rally cell (the D-038 regression refused orders to")
	print("  produced squads; the D-061 one never sent the rally at all).")
	var civ_def: CivDef = CivRoster.load_all()[0]
	var w := _server_for(civ_def.id, 400)
	var server = w["server"]
	var barracks: int = w["b"][&"barracks"]
	var space: TorusSpace = w["space"]
	var rally_cell := Vector2i(20, 3)

	server._handle_order_rally(w["peer"], NetProtocol.encode_order_rally(
		BuildingSim.wire_id(barracks), space.index(rally_cell)))
	var stored: Vector2i = server._buildings.rally_of(barracks)
	print("  rally set through _handle_order_rally: stored=%s wanted=%s match=%s"
		% [stored, rally_cell, stored == rally_cell])

	var unit: UnitDef = null
	for archetype in BuildingSim.def_by_id(&"barracks").produces:
		var u := UnitRoster.for_civ_archetype(civ_def.id, archetype)
		if u != null and not u.is_general:
			unit = u
			break
	var before_count: int = server._sim.squad_count()
	server._match.instant_build = true
	server._handle_order_produce(w["peer"], NetProtocol.encode_order_produce(
		BuildingSim.wire_id(barracks), String(unit.archetype)))
	# Tick until the squad appears, then a little longer so its order lands.
	var appeared := -1
	for i in range(600):
		server._sim.tick()
		if server._sim.squad_count() > before_count and appeared < 0:
			appeared = i
			break
	if appeared < 0:
		print("  >>> nothing was produced in 60s; queue=%d"
			% server._buildings.queue_length(barracks))
		return
	var spawned: int = server._sim.squad_count() - 1
	var dest_now: Vector2i = server._sim.destination_of(spawned)
	print("  produced %s as squad %d after %.1fs at %s, destination=%s (rally %s) obeys=%s"
		% [unit.id, spawned, appeared * 0.1, server._sim.cell_of(spawned),
		   dest_now, rally_cell, dest_now == rally_cell])
	# And it must actually WALK there.
	for i in range(1200):
		server._sim.tick()
		if server._sim.cell_of(spawned) == rally_cell:
			break
	print("  after walking: at %s, arrived=%s"
		% [server._sim.cell_of(spawned), server._sim.cell_of(spawned) == rally_cell])
	print("  n/cap readout inputs: living_squad_count=%d squad_cap_for=%d"
		% [server._sim.living_squad_count(1),
		   server._match.squad_cap_for(server._sim, 1)])
