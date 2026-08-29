extends SceneTree

## OBSERVATION HARNESS for playtest ticket #207 (civ differentiation).
##
## Not a fix and not a test: it stages the parts of #207 that are NUMBERS
## through the simulation's own objects — `UnitRoster`, `CivRoster`,
## `SquadSim`, `Combat`, `Economy`, `MatchState` and the real
## `server._handle_order_produce` — and prints what happened.
##
## The ticket's question is whether six civs FEEL different. A bot cannot
## answer that. What a bot CAN answer, and what this covers:
##
## - does each civ field exactly its own roster (leakage is fully
##   bot-observable);
## - is there a MEASURABLE difference between two civs' versions of the
##   same archetype, or are they the same troops wearing two names;
## - do the two live `CivDef` knobs (gravesworn's cap+production,
##   gildedreach's gather) produce the effect their identity claims, and
##   HOW BIG is it;
## - do the four knob-less civs differ by anything but their unit list;
## - does "fearless" show up in a FIGHT rather than only in
##   `tests/test_fearless.gd`.
##
## What stays with the owner: whether any of those differences read at the
## table, and whether two capsule-tier armies are tellable apart in a
## melee. See docs/playtests/207-bot-findings.md.
##
## THE FIXTURE LESSON THIS FILE INHERITS (docs/playtests/README.md): a
## harness that skips the civ handover reports a wired knob as dead. Every
## world built here sets `sim.civs[player]` to a RESOLVED `CivDef`, which
## is what `server._hand_civs_to_sim()` does. And squads are ordered AT
## each other's own cell, never past one another.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_civs.gd

const W := 40
const H := 20
const TICK := 1.0 / 10.0

## #207's own table of who fields what, transcribed so a leak is checked
## against the TICKET rather than against the roster checking itself.
const EXPECTED := {
	"stoneblood": ["levy", "heavy", "breaker", "skirmishers"],
	"gravesworn": ["levy", "spearmen", "shades", "engine"],
	"thornwood": ["levy", "archers", "greatbow", "cavalry"],
	"windmarch": ["levy", "cavalry", "bowriders", "skirmishers"],
	"gildedreach": ["levy", "spearmen", "archers", "cavalry", "sellswords", "engine"],
	"emberdeep": ["levy", "heavy", "archers", "bombard", "ram"],
}


func _initialize() -> void:
	print("OBS207: begin")
	_the_opening()
	_seats_versus_starts()
	_roster_leakage()
	_shared_archetype_spread()
	_same_archetype_duels()
	_the_two_live_knobs()
	_the_knobless_four()
	_fearless_in_a_fight()
	_rout_reachability()
	_told_apart()
	print("OBS207: end")
	quit()


# --- world ------------------------------------------------------------

func _sim(seed_value: int) -> SquadSim:
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	sim.combat_seed = seed_value
	return sim


## The handover `server._hand_civs_to_sim()` performs. Skipping it is how
## a previous pass measured every civ's gather rate as identical and very
## nearly filed a working feature as dead.
func _seat(sim: SquadSim, player: int, civ: StringName) -> void:
	sim.civs[player] = CivRoster.effects_of(civ)


func _civs() -> Array:
	var out := []
	for id in CivRoster.ids():
		out.append(String(id))
	out.sort()
	return out


# --- 0. can each civ even open? ---------------------------------------

## A player opens with one gatherer crew, one general and NO BASE
## (D-20260823-the-opening-is-a-crew-and-a-general). The crew's first job
## is to found the town hall, which costs wood.
##
## With no base there is also NO DROP-OFF, and `Economy._try_unload`
## returns without crediting when `_nearest_drop_off` finds none. So a
## player's wood cannot rise by gathering until something to unload at
## exists — and the only two drop-offs in the roster are the town centre
## itself and the storehouse.
##
## A civ whose `starting_wood` is under the town centre's cost therefore
## cannot open by the ordinary route at all.
func _the_opening() -> void:
	print("")
	print("OBS207 OPENING - can each civ afford the town hall it must found?")
	var hall := BuildingSim.def_by_id(&"town_centre")
	var store := BuildingSim.def_by_id(&"storehouse")
	if hall == null:
		print("  no town centre in the roster")
		return
	print("  town centre costs %d wood; storehouse (the other drop-off) costs %d." % [
		hall.cost_wood, store.cost_wood if store != null else -1])
	print("  %-12s %6s %6s %8s %s" % ["civ", "wood", "need", "can_open", "note"])
	for civ in _civs():
		var def := CivRoster.by_id(StringName(civ))
		if def == null:
			continue
		var can := def.starting_wood >= hall.cost_wood
		var note := ""
		if not can:
			if store != null and def.starting_wood >= store.cost_wood:
				note = "storehouse first (%d wood) then gather %d — a human can, the AI never does" % [
					store.cost_wood, hall.cost_wood - (def.starting_wood - store.cost_wood)]
			else:
				note = "cannot reach a drop-off at all"
		print("  %-12s %6d %6d %8s %s" % [
			civ, def.starting_wood, hall.cost_wood, "yes" if can else "NO", note])


# --- 0b. seats against starting positions -----------------------------

## `just ai-ladder N SECONDS 6` seats six players. Whether the map has six
## starting positions to give them is a different question, and
## `MatchState._seats_changed()` REVERTS `player_slots` when the map
## refuses the higher count — which is correct, and leaves the seats
## seated anyway, sharing starts.
func _seats_versus_starts() -> void:
	print("")
	print("OBS207 SEATS - starting positions each shipped map will actually give,")
	print("  as the seat count rises. `_seats_changed` reverts a count the map")
	print("  refuses, so 'slots' below is what the match really generates.")
	for map_path in ["res://maps/ladder.tres", "res://maps/default.tres"]:
		var config: MapConfig = load(map_path)
		if config == null:
			continue
		var line := "  %-24s %dx%d authored_slots=%d :" % [
			map_path.get_file(), config.width, config.height, config.player_slots]
		for seats in [2, 4, 6, 8]:
			var state := MatchState.new()
			state.map_settings = MapSettings.from_map(config)
			for i in range(seats):
				state.add_ai_player(1000 + i, &"")
			line += "  %d seats->%d slots" % [seats, state.map_settings.player_slots]
		print(line)
	print("  A seat past the slot count shares another seat's start. The two")
	print("  that share never found a base in any ladder match measured here.")

	# The same call the server makes at start-up, on the same terrain, so
	# the number below is the number a match generates rather than an
	# estimate of it. `--ai=6` on the ladder map is what
	# `just ai-ladder N SECONDS 6` runs.
	print("")
	print("  The REAL search, on real terrain, for the ladder map at 6 slots:")
	for seed_value in [1, 2, 3]:
		var settings := MapSettings.from_map(load("res://maps/ladder.tres"))
		settings.pin_seed(seed_value)
		settings.apply_preset(TerrainPresetRoster.by_id(settings.preset))
		settings.player_slots = 6
		var passable := settings.to_terrain().passability(settings.to_space())
		var config := settings.to_spawn_config()
		var points := config.spawn_points(passable)
		print("    seed %d: player_slots=%d -> %d starting positions   validate_spawns: %s" % [
			seed_value, config.player_slots, points.size(),
			("\"\" (silent)" if config.validate_spawns(passable) == ""
				else config.validate_spawns(passable))])


# --- 1. roster leakage -------------------------------------------------

func _roster_leakage() -> void:
	print("")
	print("OBS207 ROSTER - what each civ actually resolves, against #207's table.")
	print("  A leak shows as an archetype resolving to another civ's def, or as")
	print("  a civ fielding something the ticket does not list for it.")
	var leaks := 0
	for civ in _civs():
		var listed: Array[StringName] = UnitRoster.archetypes_for(StringName(civ))
		var combat := []
		var support := []
		for a in listed:
			var def := UnitRoster.for_civ_archetype(StringName(civ), a)
			if def == null:
				continue
			# The def that comes back must belong to this civ or be shared.
			if String(def.civ) != civ and String(def.civ) != "neutral":
				print("  LEAK %s asked for %s and got %s (civ %s)" % [
					civ, a, def.id, def.civ])
				leaks += 1
			if def.gather_rate > 0.0 or def.is_general:
				support.append(String(a))
			else:
				combat.append(String(a))
		combat.sort()
		var want: Array = EXPECTED.get(civ, []).duplicate()
		want.sort()
		var same: bool = combat == want
		print("  %-12s combat=%s support=%s matches_ticket=%s" % [
			civ, combat, support, same])
		if not same:
			print("               ticket said %s" % [want])

	# The other direction: does any archetype resolve for a civ the ticket
	# does not give it? Asked over the union the barracks offers, which is
	# what a build menu walks.
	print("")
	print("OBS207 ROSTER - the barracks offers a UNION; who resolves each entry.")
	var barracks := BuildingSim.def_by_id(&"barracks")
	if barracks != null:
		for archetype in barracks.produces:
			var can := []
			for civ in _civs():
				if UnitRoster.for_civ_archetype(StringName(civ), archetype) != null:
					can.append(civ)
			print("  %-12s fielded by %d: %s" % [archetype, can.size(), can])
	print("  leaks=%d" % leaks)


# --- 2. the shared archetypes, side by side ---------------------------

func _shared_archetype_spread() -> void:
	print("")
	print("OBS207 SPREAD - every civ's version of a SHARED archetype.")
	print("  D-072's V = sqrt(DPS x EHP), RP = food + wood + 1.5*(gold+stone),")
	print("  both per SQUAD, so a cheap numerous squad and a dear elite one are")
	print("  compared the way a player buys them.")
	for archetype in [&"levy", &"skirmishers", &"cavalry", &"archers",
			&"spearmen", &"heavy", &"gatherers"]:
		var rows := []
		for civ in _civs():
			var def := UnitRoster.for_civ_archetype(StringName(civ), archetype)
			if def == null:
				continue
			rows.append({"civ": civ, "def": def})
		if rows.size() < 2:
			continue
		print("")
		print("  %s - fielded by %d civ(s)" % [archetype, rows.size()])
		print("    %-12s %-24s %3s %6s %6s %5s %6s %7s %7s %6s" % [
			"civ", "def", "n", "hp", "dmg", "rng", "spd", "V", "RP", "V/RP"])
		for row in rows:
			var def: UnitDef = row["def"]
			var v := _power(def)
			var rp := _price(def)
			print("    %-12s %-24s %3d %6.1f %6.2f %5.2f %6.2f %7.1f %7.1f %6.3f" % [
				row["civ"], def.id, def.squad_size, def.health, def.damage,
				def.attack_range, def.move_speed, v, rp,
				v / maxf(1.0, rp)])
		_spread_note(rows)


## How far apart the extremes of one archetype are. The ticket's question
## is whether the tuning difference is PERCEPTIBLE; a spread of a few per
## cent is a number nobody could feel, and that is worth saying plainly.
func _spread_note(rows: Array) -> void:
	var lo := 1e30
	var hi := -1e30
	var lo_civ := ""
	var hi_civ := ""
	for row in rows:
		var v := _power(row["def"])
		if v < lo:
			lo = v
			lo_civ = row["civ"]
		if v > hi:
			hi = v
			hi_civ = row["civ"]
	if lo <= 0.0:
		return
	print("    spread: %.2fx from %s (%.1f) to %s (%.1f)" % [
		hi / lo, lo_civ, lo, hi_civ, hi])


func _power(def: UnitDef) -> float:
	var interval := maxf(0.01, def.attack_interval)
	var dps := def.damage * float(def.squad_size) / interval
	var ehp := def.health * float(def.squad_size)
	return sqrt(maxf(0.0, dps) * maxf(0.0, ehp))


func _price(def: UnitDef) -> float:
	return float(def.cost_food + def.cost_wood) \
		+ 1.5 * float(def.cost_gold + def.cost_stone)


# --- 3. the same archetype, fought against itself ---------------------

func _same_archetype_duels() -> void:
	print("")
	print("OBS207 DUELS - civ A's levy against civ B's levy, and so on.")
	print("  Flat equal ground, both ordered onto the other's own start cell,")
	print("  6 seeds, played BOTH ways round so the lower-id advantage #38")
	print("  looked for cannot masquerade as a civ difference.")
	print("  margin = winner's surviving fraction; a pairing that is genuinely")
	print("  even reads ~0.0 and splits its wins.")
	for archetype in [&"levy", &"cavalry", &"skirmishers"]:
		var have := []
		for civ in _civs():
			if UnitRoster.for_civ_archetype(StringName(civ), archetype) != null:
				have.append(civ)
		if have.size() < 2:
			continue
		print("")
		print("  --- %s ---" % archetype)
		for i in range(have.size()):
			for j in range(i + 1, have.size()):
				_duel_pair(archetype, String(have[i]), String(have[j]))


func _duel_pair(archetype: StringName, civ_a: String, civ_b: String) -> void:
	var da := UnitRoster.for_civ_archetype(StringName(civ_a), archetype)
	var db := UnitRoster.for_civ_archetype(StringName(civ_b), archetype)
	if da == null or db == null:
		return
	var wins_a := 0
	var wins_b := 0
	var draws := 0
	var frac_a := 0.0
	var frac_b := 0.0
	var runs := 0
	for seed_value in range(1, 4):
		for a_first in [true, false]:
			var r := _fight(da, db, civ_a, civ_b, seed_value, a_first)
			runs += 1
			frac_a += float(r["frac_a"])
			frac_b += float(r["frac_b"])
			match int(r["winner"]):
				1:
					wins_a += 1
				2:
					wins_b += 1
				_:
					draws += 1
	frac_a /= maxf(1.0, float(runs))
	frac_b /= maxf(1.0, float(runs))
	var verdict := "even"
	if wins_a >= runs - 1 and wins_a > wins_b:
		verdict = "%s WINS" % civ_a
	elif wins_b >= runs - 1 and wins_b > wins_a:
		verdict = "%s WINS" % civ_b
	elif wins_a != wins_b:
		verdict = "leans %s" % (civ_a if wins_a > wins_b else civ_b)
	print("    %-12s vs %-12s  %d-%d-%d  survivors %.2f / %.2f  %s" % [
		civ_a, civ_b, wins_a, wins_b, draws, frac_a, frac_b, verdict])


func _fight(da: UnitDef, db: UnitDef, civ_a: String, civ_b: String,
		seed_value: int, a_first: bool, max_seconds: float = 180.0) -> Dictionary:
	var sim := _sim(seed_value)
	_seat(sim, 1, StringName(civ_a))
	_seat(sim, 2, StringName(civ_b))
	var cell_a := Vector2i(14, 10)
	var cell_b := Vector2i(20, 10)
	var sa := -1
	var sb := -1
	if a_first:
		sa = sim.add_squad(da, 1, cell_a)
		sb = sim.add_squad(db, 2, cell_b)
	else:
		sb = sim.add_squad(db, 2, cell_b)
		sa = sim.add_squad(da, 1, cell_a)
	var start_a := sim.alive_of(sa)
	var start_b := sim.alive_of(sb)
	# AT each other's own cell (README's second lesson), not past.
	sim.order_attack_move(sa, cell_b)
	sim.order_attack_move(sb, cell_a)

	var t := 0.0
	while t < max_seconds:
		sim.tick()
		t += TICK
		if sim.alive_of(sa) <= 0 or sim.alive_of(sb) <= 0:
			break
	var alive_a := sim.alive_of(sa)
	var alive_b := sim.alive_of(sb)
	var winner := 0
	if alive_a > 0 and alive_b <= 0:
		winner = 1
	elif alive_b > 0 and alive_a <= 0:
		winner = 2
	return {
		"winner": winner,
		"frac_a": float(alive_a) / maxf(1.0, float(start_a)),
		"frac_b": float(alive_b) / maxf(1.0, float(start_b)),
		"seconds": t,
	}


# --- 4. the two live knobs --------------------------------------------

func _the_two_live_knobs() -> void:
	print("")
	print("OBS207 KNOBS - the three CivDef fields, as the simulation reads them.")
	print("  %-12s %5s %6s %6s | %s" % [
		"civ", "cap+", "prod", "gath", "what that is worth"])
	var base_cap := 40
	for civ in _civs():
		var def := CivRoster.effects_of(StringName(civ))
		print("  %-12s %5d %6.2f %6.2f | cap %d->%d, a 10 s train takes %.2f s, a 1.0/s crew gathers %.2f/s" % [
			civ, def.squad_cap_bonus, def.production_speed, def.gather_speed,
			base_cap, def.squad_cap(base_cap), def.production_time(10.0),
			def.gather_rate(1.0)])

	_quantity_identity()
	_economy_identity()


## Gravesworn's claim is QUANTITY. Three things feed it and only two are
## knobs, so the honest measure is what a fixed bank BUYS and how long it
## takes to arrive, not the knob in isolation.
func _quantity_identity() -> void:
	print("")
	print("OBS207 QUANTITY - what 1000 food buys each civ, and how fast.")
	print("  squads and SOLDIERS both, because 'quantity' is bodies on the")
	print("  field rather than entries in a list.")
	print("  %-12s %-24s %5s %6s %7s %7s %8s %7s" % [
		"civ", "levy", "n", "cost", "squads", "men", "train_s", "cap"])
	for civ in _civs():
		var def := UnitRoster.for_civ_archetype(StringName(civ), &"levy")
		if def == null:
			continue
		var effects := CivRoster.effects_of(StringName(civ))
		var cost := maxi(1, def.cost_food)
		var squads := 1000 / cost
		var sim := _sim(1)
		_seat(sim, 1, StringName(civ))
		var match_state := MatchState.new()
		match_state.squad_cap = 40
		print("  %-12s %-24s %5d %6d %7d %7d %8.1f %7d" % [
			civ, def.id, def.squad_size, cost, squads, squads * def.squad_size,
			effects.production_time(def.build_time),
			match_state.squad_cap_for(sim, 1)])


## Gildedreach's claim is ECONOMY. Measured by running the REAL haul cycle
## for two civs with identical crews on identical ground, because
## `gather_speed` is applied per tick inside `Economy._gather` and a
## multiplier read off the .tres proves only that the number exists.
func _economy_identity() -> void:
	print("")
	print("OBS207 ECONOMY - the real haul cycle, 240 s, one crew, one node,")
	print("  one drop-off two cells away. Same ground, same node, same tick.")
	print("  %-12s %-24s %5s %8s %8s %9s" % [
		"civ", "gatherers", "n", "rate", "banked", "vs median"])
	var banked := {}
	for civ in _civs():
		banked[civ] = _haul_for(String(civ))
	var values := []
	for civ in banked:
		values.append(int(banked[civ]["delivered"]))
	values.sort()
	var median: int = values[values.size() / 2] if not values.is_empty() else 1
	for civ in _civs():
		var row: Dictionary = banked[civ]
		print("  %-12s %-24s %5d %8.3f %8d %8.2fx" % [
			civ, row["def"], row["n"], row["rate"], row["delivered"],
			float(row["delivered"]) / maxf(1.0, float(median))])


func _haul_for(civ: String) -> Dictionary:
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	var buildings := BuildingSim.new(space)
	var economy := Economy.new(space)
	sim.buildings = buildings
	sim.economy = economy
	_seat(sim, 1, StringName(civ))

	var node_cell := Vector2i(20, 10)
	economy.nodes[space.index(node_cell)] = {
		"kind": Economy.ResourceKind.WOOD, "remaining": 1000000,
	}
	var hall := BuildingSim.def_by_id(&"town_centre")
	buildings.add_building(hall, 1, Vector2i(18, 10), true)
	var crew := UnitRoster.for_civ_archetype(StringName(civ), &"gatherers")
	if crew == null:
		return {"def": "<none>", "n": 0, "rate": 0.0, "delivered": 0}
	var squad := sim.add_squad(crew, 1, node_cell)
	economy.order_gather(sim, squad, space.index(node_cell))
	for i in range(2400):  # 240 s at the shipping 10 Hz
		sim.tick()
	return {
		"def": String(crew.id),
		"n": crew.squad_size,
		"rate": CivRoster.effects_of(StringName(civ)).gather_rate(crew.gather_rate),
		"delivered": economy.amount(1, Economy.ResourceKind.WOOD),
	}


# --- 5. the four with no knobs ----------------------------------------

func _the_knobless_four() -> void:
	print("")
	print("OBS207 PROFILE - each civ's roster as a whole, for the four that")
	print("  have no knob at all. If two civs' columns are the same shape,")
	print("  they are one army with two unit lists.")
	print("  %-12s %5s %7s %7s %7s %7s %7s %7s %6s" % [
		"civ", "defs", "meanV", "maxV", "meanRP", "V/RP", "reach", "speed", "siege"])
	for civ in _civs():
		var defs := UnitRoster.for_civ(StringName(civ))
		var total_v := 0.0
		var max_v := 0.0
		var total_rp := 0.0
		var reach := 0.0
		var speed := 0.0
		var siege := 0.0
		var n := 0
		for def in defs:
			if def.gather_rate > 0.0 or def.is_general:
				continue
			n += 1
			var v := _power(def)
			total_v += v
			max_v = maxf(max_v, v)
			total_rp += _price(def)
			reach = maxf(reach, def.attack_range)
			speed = maxf(speed, def.move_speed)
			siege = maxf(siege, def.damage_vs_buildings)
		if n == 0:
			continue
		print("  %-12s %5d %7.1f %7.1f %7.1f %7.3f %7.2f %7.2f %6.2f" % [
			civ, n, total_v / float(n), max_v, total_rp / float(n),
			(total_v / float(n)) / maxf(1.0, total_rp / float(n)),
			reach, speed, siege])


# --- 6. fearless, in a fight ------------------------------------------

func _fearless_in_a_fight() -> void:
	print("")
	print("OBS207 FEARLESS - every civ's levy put under the SAME beating, and")
	print("  watched for a rout. `tests/test_fearless.gd` proves gravesworn")
	print("  CANNOT rout; the ticket asks whether that shows in a fight, which")
	print("  it only does if the others DO rout under the same pressure.")
	print("  %-12s %-24s %9s %8s %8s %8s" % [
		"civ", "levy", "threshold", "routed", "at_s", "left"])
	# One hammer for everybody: a squad that beats a levy badly without
	# wiping it in a single round — `alive <= 0` returns before the rout
	# check, which is the vacuity `tests/test_fearless.gd` records.
	var hammer := UnitRoster.for_civ_archetype(&"stoneblood", &"heavy")
	if hammer == null:
		print("  no hammer in the roster")
		return
	for civ in _civs():
		var def := UnitRoster.for_civ_archetype(StringName(civ), &"levy")
		if def == null:
			continue
		var sim := _sim(7)
		_seat(sim, 1, StringName(civ))
		_seat(sim, 2, &"stoneblood")
		var cell_a := Vector2i(14, 10)
		var cell_b := Vector2i(17, 10)
		var victim := sim.add_squad(def, 1, cell_a)
		var beater := sim.add_squad(hammer, 2, cell_b)
		var start := sim.alive_of(victim)
		sim.order_attack_move(victim, cell_b)
		sim.order_attack_move(beater, cell_a)
		var t := 0.0
		var routed_at := -1.0
		while t < 120.0:
			sim.tick()
			t += TICK
			if routed_at < 0.0 and sim.is_routed(victim):
				routed_at = t
			if sim.alive_of(victim) <= 0 or sim.alive_of(beater) <= 0:
				break
		print("  %-12s %-24s %9.1f %8s %8s %8d/%d" % [
			civ, def.id, def.rout_threshold,
			"yes" if routed_at >= 0.0 else "NO",
			("%.1f" % routed_at) if routed_at >= 0.0 else "-",
			sim.alive_of(victim), start])


## Why the fight above answers less than it looks like it does.
##
## Morale falls by a FLAT `morale_loss_per_casualty` per man lost, while
## this roster's squads run from 3 men to 48. So the number of casualties
## needed to reach `rout_threshold` is a constant, and for any squad
## smaller than that constant it is unreachable: the squad is wiped out
## before it can be frightened. That is "fearless" arrived at by
## arithmetic, in civs that never asked for it.
func _rout_reachability() -> void:
	print("")
	print("OBS207 ROUT REACH - casualties needed to reach the threshold, against")
	print("  the men available to supply them. need = (morale - threshold) /")
	print("  morale_loss_per_casualty. need >= n means the squad CANNOT rout.")
	print("  %-26s %4s %7s %6s %6s %8s %8s %s" % [
		"def", "n", "morale", "thr", "loss", "need", "need/n", "can rout?"])
	var never := []
	var total := 0
	for def in UnitRoster.load_all():
		if def.gather_rate > 0.0 or def.is_general:
			continue
		total += 1
		var need := INF
		if def.morale_loss_per_casualty > 0.0:
			need = (def.morale - def.rout_threshold) / def.morale_loss_per_casualty
		var can := need < float(def.squad_size)
		if not can and def.morale_loss_per_casualty > 0.0:
			never.append(String(def.id))
		print("  %-26s %4d %7.0f %6.1f %6.1f %8s %8s %s" % [
			def.id, def.squad_size, def.morale, def.rout_threshold,
			def.morale_loss_per_casualty,
			"inf" if need == INF else ("%.1f" % need),
			"inf" if need == INF else ("%.2f" % (need / maxf(1.0, float(def.squad_size)))),
			"yes" if can else "NEVER"])
	print("")
	print("  %d of %d combat defs can never rout. Gravesworn's four are BY DESIGN" % [
		never.size() + 4, total])
	print("  (rout_threshold 0, #191). These %d are not, and belong to five other civs:" % never.size())
	print("    %s" % [never])


# --- 8. telling two armies apart --------------------------------------

func _told_apart() -> void:
	print("")
	print("OBS207 LOOK - what a bot can say about criterion 5, which is")
	print("  otherwise the owner's. Player COLOUR is per player (D-052) and")
	print("  is not the civ's; what the civ decides is the MODEL, and four of")
	print("  six wear the primitive capsule for everything.")
	print("  %-12s %-9s %-28s %s" % ["civ", "colour", "authored models", "primitive-tier archetypes"])
	for civ in _civs():
		var cdef := CivRoster.by_id(StringName(civ))
		var authored := []
		var primitive := []
		for def in UnitRoster.for_civ(StringName(civ)):
			if String(def.model_id) == "":
				primitive.append(String(def.archetype))
			elif not authored.has(String(def.model_id)):
				authored.append(String(def.model_id))
		print("  %-12s %-9s %-28s %s" % [
			civ,
			("#%s" % cdef.colour.to_html(false)) if cdef != null else "-",
			authored if not authored.is_empty() else ["<none>"],
			primitive])
	print("")
	print("  Civ colour is NOT what a player sees in a melee — D-052 gives the")
	print("  colour to the PLAYER, so two seats of the same civ are different")
	print("  colours and two seats of different civs may be adjacent hues. The")
	print("  civ's contribution to telling armies apart is its MODELS, and the")
	print("  table above is the whole of it.")
