extends SceneTree

## OBSERVATION HARNESS for playtest ticket #36 (economy).
##
## Real terrain, real `Economy.generate` node placement, real gatherer
## defs, ticked through `SquadSim.tick()` at the shipping 10 Hz — so the
## haul cycle measured here is the one a match runs.
##
## What it CANNOT see, and what stays with the owner: the tip-and-sink
## felling ANIMATION, the HUD resource readouts, and whether a haul cycle
## is legible to watch. Those are pixels.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_economy.gd

const TICK := 1.0 / 10.0
const KIND_NAMES := ["food", "wood", "gold", "stone"]


func _initialize() -> void:
	print("OBS36: begin")
	var w := _world()
	if w.is_empty():
		print("OBS36: could not stand a world up")
		quit()
		return
	_node_census(w)
	_haul_cycle(w)
	_tree_timing()
	_retarget()
	_storehouse_shortens_hauls()
	print("OBS36: end")
	quit()


## A real generated world: terrain, passability and biome-derived nodes,
## assembled the way server.gd assembles them.
func _world() -> Dictionary:
	var map: MapConfig = load("res://maps/default.tres")
	var width := 84
	var height := 96
	if map != null:
		width = map.width
		height = map.height
	var space := TorusSpace.new(width, height, 1.0)
	var terrain := TerrainGen.new()
	terrain.noise_seed = 1337
	var passable := terrain.passability(space)
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.set_passable(passable)
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var economy := Economy.new(space)
	economy.generate(terrain, 1)
	sim.economy = economy
	return {"space": space, "sim": sim, "buildings": buildings,
		"economy": economy, "terrain": terrain, "passable": passable}


func _gatherer() -> UnitDef:
	for d in UnitRoster.load_all():
		if d.gather_rate > 0.0 and d.carry_capacity > 0:
			return d
	return null


func _node_census(w: Dictionary) -> void:
	var economy: Economy = w["economy"]
	print("")
	print("OBS36 NODES - what the shipped default map actually grows.")
	var by_kind := [0, 0, 0, 0]
	var stock := [0, 0, 0, 0]
	for e in economy.node_entries():
		var k := int(e["kind"])
		if k >= 0 and k < 4:
			by_kind[k] += 1
			stock[k] += economy.remaining_at(int(e["cell"]))
	for k in range(4):
		print("  %-6s nodes=%-6d total stock=%d" % [KIND_NAMES[k], by_kind[k], stock[k]])
	print("  all four kinds present: %s"
		% [by_kind[0] > 0 and by_kind[1] > 0 and by_kind[2] > 0 and by_kind[3] > 0])


## Find a node of a kind, plus a walkable cell near it.
func _find_node(w: Dictionary, kind: int) -> int:
	var economy: Economy = w["economy"]
	for e in economy.node_entries():
		if int(e["kind"]) == kind and economy.remaining_at(int(e["cell"])) > 0:
			return int(e["cell"])
	return -1


func _haul_cycle(w: Dictionary) -> void:
	print("")
	print("OBS36 HAUL CYCLE - one crew per resource kind, watched through a")
	print("  full round trip. Deposits must be DISCRETE (the stockpile jumps")
	print("  on arrival at the drop-off, not continuously while gathering).")
	var gath := _gatherer()
	if gath == null:
		print("  no gatherer def in the roster")
		return
	for kind in range(4):
		var space: TorusSpace = w["space"]
		var sim := SquadSim.new(space, CurveReplicator.new())
		sim.set_passable(w["passable"])
		var buildings := BuildingSim.new(space)
		sim.buildings = buildings
		var economy := Economy.new(space)
		economy.generate(w["terrain"], 1)
		sim.economy = economy

		var node_cell := _find_node({"economy": economy}, kind)
		if node_cell < 0:
			print("  %-6s: no node of this kind on the map" % KIND_NAMES[kind])
			continue
		var at := space.from_index(node_cell)
		# Drop-off two cells away so the round trip is short and legible.
		var tc := BuildingSim.def_by_id(&"town_centre")
		var home := _walkable_near(w, at, 3)
		buildings.add_building(tc, 1, home, true)
		var squad := sim.add_squad(gath, 1, home)
		var ok := economy.order_gather(sim, squad, node_cell)
		if not ok:
			print("  %-6s: order_gather refused" % KIND_NAMES[kind])
			continue

		var wallet_steps := []
		var phases := []
		var last_amount := economy.amount(1, kind)
		var last_phase := -99
		var t := 0.0
		var deposits := 0
		while t < 240.0:
			sim.tick()
			t += TICK
			var ph := economy.phase_of(squad)
			if ph != last_phase:
				phases.append("%.1fs:%s" % [t, ["TO_NODE", "GATHERING", "TO_DROP_OFF"][ph] if ph >= 0 else "none"])
				last_phase = ph
			var now := economy.amount(1, kind)
			if now != last_amount:
				deposits += 1
				wallet_steps.append("%.1fs:+%d" % [t, now - last_amount])
				last_amount = now
			if deposits >= 2:
				break
		print("  %-6s node %s: phases %s" % [KIND_NAMES[kind], at, " -> ".join(phases)])
		print("         deposits %s (discrete=%s), wallet now %d"
			% [" ".join(wallet_steps), deposits > 0 and wallet_steps.size() == deposits,
			   economy.amount(1, kind)])


func _walkable_near(w: Dictionary, at: Vector2i, radius: int) -> Vector2i:
	var space: TorusSpace = w["space"]
	var passable: PackedByteArray = w["passable"]
	for offset in TorusSpace.disk_offsets(radius):
		var c := space.normalize(at + offset)
		var i := space.index(c)
		if i < passable.size() and passable[i] == 1:
			return c
	return at


func _tree_timing() -> void:
	print("")
	print("OBS36 TREE - how long one shipped crew takes to work a tree out.")
	print("  D-087 sizes TREE_STOCK (%d) so this is about 60s; economy.gd's"
		% Economy.TREE_STOCK)
	print("  own header says a change to the gatherer must move it.")
	var gath := _gatherer()
	for civ_def in CivRoster.load_all():
		var g := UnitRoster.for_civ_archetype(civ_def.id, &"gatherers")
		if g == null:
			continue
		var space := TorusSpace.new(24, 12, 1.0)
		var sim := SquadSim.new(space, CurveReplicator.new())
		var p := PackedByteArray()
		p.resize(space.cell_count())
		p.fill(1)
		sim.set_passable(p)
		var buildings := BuildingSim.new(space)
		sim.buildings = buildings
		var economy := Economy.new(space)
		sim.economy = economy
		# The simulation must be TOLD the civ, exactly as server.gd's
		# _hand_civs_to_sim() does (#158) — Economy._gather reads
		# sim.civ_effects(player).gather_rate(). A fixture that skipped this
		# would measure every civ at the default 1.0 and report a wired knob
		# as unwired.
		sim.civs[1] = CivRoster.effects_of(civ_def.id)
		# One tree, placed by hand so the timing is about the CREW.
		var node_cell := space.index(Vector2i(12, 6))
		economy.nodes[node_cell] = {"kind": Economy.ResourceKind.WOOD,
			"remaining": Economy.TREE_STOCK}
		var tc := BuildingSim.def_by_id(&"town_centre")
		buildings.add_building(tc, 1, Vector2i(10, 6), true)
		var squad := sim.add_squad(g, 1, Vector2i(11, 6))
		economy.order_gather(sim, squad, node_cell)
		var t := 0.0
		var felled_at := -1.0
		while t < 400.0:
			sim.tick()
			t += TICK
			if not economy.has_node(node_cell) or economy.remaining_at(node_cell) <= 0:
				felled_at = t
				break
		print("  %-14s %-24s alive=%d rate=%.2f/s x civ %.2f -> tree out in %s"
			% [civ_def.id, g.id, sim.alive_of(squad), g.gather_rate,
			   civ_def.gather_speed,
			   ("%.1fs" % felled_at) if felled_at > 0 else "NOT within 400s"])


func _retarget() -> void:
	print("")
	print("OBS36 RETARGET - when a tree runs out, the crew must take the")
	print("  nearest surviving node of the SAME KIND within %d cells, and"
		% Economy.RETARGET_RADIUS)
	print("  give up if there is none. Never wood-to-food.")
	print("  Read by watching which node LOSES STOCK after the first is gone,")
	print("  because the crew's current node is private to Economy.")
	var g := _gatherer()
	var cases: Array[Array] = [
		["same kind 3 cells away", Economy.ResourceKind.WOOD, 3],
		["same kind 12 cells away (outside radius)", Economy.ResourceKind.WOOD, 12],
		["FOOD 3 cells away (wrong kind)", Economy.ResourceKind.FOOD, 3],
		["nothing else on the map", -1, 0],
	]
	for c in cases:
		var label: String = c[0]
		var other_kind: int = c[1]
		var distance: int = c[2]
		var space := TorusSpace.new(60, 30, 1.0)
		var sim := SquadSim.new(space, CurveReplicator.new())
		var p := PackedByteArray()
		p.resize(space.cell_count())
		p.fill(1)
		sim.set_passable(p)
		var buildings := BuildingSim.new(space)
		sim.buildings = buildings
		var economy := Economy.new(space)
		sim.economy = economy

		var first := space.index(Vector2i(30, 15))
		economy.nodes[first] = {"kind": Economy.ResourceKind.WOOD, "remaining": 8}
		var second := -1
		if other_kind >= 0:
			second = space.index(Vector2i(30 + distance, 15))
			economy.nodes[second] = {"kind": other_kind, "remaining": 200}
		var second_start := economy.remaining_at(second) if second >= 0 else 0

		var tc := BuildingSim.def_by_id(&"town_centre")
		buildings.add_building(tc, 1, Vector2i(28, 15), true)
		var squad := sim.add_squad(g, 1, Vector2i(29, 15))
		economy.order_gather(sim, squad, first)

		var gone_at := -1.0
		var t := 0.0
		while t < 300.0:
			sim.tick()
			t += TICK
			if gone_at < 0.0 and not economy.has_node(first):
				gone_at = t
			if gone_at > 0.0 and t > gone_at + 120.0:
				break
		var took_second := second >= 0 			and economy.remaining_at(second) < second_start
		var verdict := "gave up"
		if took_second:
			verdict = "moved to the %s node" % KIND_NAMES[other_kind]
		print("  %-42s first node gone at %s | %s | still gathering=%s"
			% [label, ("%.1fs" % gone_at) if gone_at > 0 else "never",
			   verdict, economy.is_gathering(squad)])


func _storehouse_shortens_hauls() -> void:
	print("")
	print("OBS36 STOREHOUSE - the same grove worked with and without a")
	print("  nearer drop-off. Income over a fixed 180s window.")
	var g := _gatherer()
	for with_store in [false, true]:
		var space := TorusSpace.new(60, 30, 1.0)
		var sim := SquadSim.new(space, CurveReplicator.new())
		var p := PackedByteArray()
		p.resize(space.cell_count())
		p.fill(1)
		sim.set_passable(p)
		var buildings := BuildingSim.new(space)
		sim.buildings = buildings
		var economy := Economy.new(space)
		sim.economy = economy
		# Town centre at one end, grove 18 cells away.
		var tc := BuildingSim.def_by_id(&"town_centre")
		buildings.add_building(tc, 1, Vector2i(6, 15), true)
		if with_store:
			var store := BuildingSim.def_by_id(&"storehouse")
			buildings.add_building(store, 1, Vector2i(22, 15), true)
		for i in range(6):
			economy.nodes[space.index(Vector2i(24 + i % 3, 14 + i / 3))] = \
				{"kind": Economy.ResourceKind.WOOD, "remaining": Economy.TREE_STOCK}
		var squad := sim.add_squad(g, 1, Vector2i(7, 15))
		economy.order_gather(sim, squad, space.index(Vector2i(24, 14)))
		var t := 0.0
		while t < 180.0:
			sim.tick()
			t += TICK
		print("  storehouse=%-5s wood banked in 180s: %d"
			% [with_store, economy.amount(1, Economy.ResourceKind.WOOD)])
