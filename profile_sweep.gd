extends SceneTree

## M4's tiered scale sweep (`just profile`).
##
## The load test measures the game as PLAYED, which is the right thing to
## measure and the wrong thing to scale: squad count there is whatever
## production happens to produce, so a run reaches a few dozen squads and
## the per-squad figure is dominated by fixed overhead. D-018 targets
## ~1,000 squads, and no amount of playing gets there in a two-minute run.
##
## So this drives the simulation directly at chosen counts. It is not a
## game — nobody connects, nothing replicates — deliberately: this
## isolates SIMULATION cost, which is the half D-020's budget is stated
## in and the half D-021's GDExtension question turns on.
##
## ## Why a sweep rather than one measurement at 1,000
##
## The shape is the deliverable, not the endpoint. Cost should be LINEAR
## in squad count — every system here is meant to be O(squads x radius) or
## better — so the interesting output is whether µs-per-squad stays flat
## as the count rises. A single point at 1,000 says pass or fail; the
## curve says whether anything is accidentally quadratic, which is the
## defect class that has already been found twice in this project
## (vision's per-cell distance() calls, and combat rebuilding a bucket map
## the squad pass had just built).

const COUNTS := [100, 250, 500, 1000]
const TICKS := 200

## Squads are given destinations across the map so they actually path,
## re-path and fight. A sweep over idle squads would measure almost
## nothing and flatter every system in it.
const MOVE_EVERY_TICKS := 40


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var map_path := String(args.get("map", "res://maps/default.tres"))
	var config: MapConfig = load(map_path)
	if config == null:
		push_error("profile: could not load %s" % map_path)
		quit(1)
		return

	# `--only=<section>` runs one section instead of all four. The whole
	# sweep is minutes of work and the ladder alone is what #304 needs, so
	# iterating on one of them should not mean paying for the other three.
	# Empty is every section, so a bare `just profile` is unchanged.
	var only := String(args.get("only", ""))

	print("profile: %s (%dx%d), %d ticks per count" % [
		config.id, config.width, config.height, TICKS])
	if only == "" or only == "count":
		_count_sweep(config)
	if only == "" or only == "map":
		_map_sweep()
	if only == "" or only == "derive":
		_derive_sweep(config)
	if only == "" or only == "ladder":
		_tick_ladder(config)
	quit(0)


func _count_sweep(config: MapConfig) -> void:
	for amortised in [true, false]:
		print("profile: --- count sweep, amortised=%s ---" % ("yes" if amortised else "no"))
		print("profile: count,us_per_squad,us_vision,us_combat,ms_per_tick,ms_worst_tick,fields_built")
		for count in COUNTS:
			_run(config, int(count),
				SquadSim.DEFAULT_FIELD_CELLS_PER_TICK if amortised else -1)


# --- the steady-state tick ladder (#304) --------------------------------
#
# ## Why the sweep above could not answer #304
#
# `_run` builds a BARE simulation: no `teams`, no `civs`, no `economy`, no
# `buildings`, no `research`. Every one of those is a thing M6 and later
# added, and the sweep cannot see the cost of a system it never
# instantiates. That is not a flaw in the sweep — it isolates SIMULATION
# cost on purpose, and the count table's meaning depends on it not
# changing — it is the reason a separate harness was needed. It is also
# the mechanism behind CLAUDE.md's standing warning that "a green
# `just profile` is not a green server", stated one level more precisely:
# the sweep is green partly because half the server is absent from it.
#
# So this builds the world the SERVER builds, at one matched squad count,
# and turns each suspect off in turn. Every knob defaults to ON, so a bare
# `just profile` measures the shipped configuration and the ladder is
# comparable between runs.
#
# ## Steady state, and why it is not optional here
#
# The first ticks of any run are dominated by flow-field construction —
# every squad is ordered at once and D-040's budget spreads one solve over
# many ticks, so an average taken from tick 0 is an average of a transient
# that never recurs. #105 attributed a whole 84 us/squad rise to exactly
# that phase, and it would swamp the differences this ladder is looking
# for. Counters are therefore SNAPSHOTTED after a warm-up and the ladder
# is the delta.

const LADDER_SQUADS := 120
const LADDER_WARMUP := 120
const LADDER_TICKS := 200
const LADDER_PLAYERS := 4

## One rally per five squads. The count sweep above uses eight for any
## count, which at 120 squads puts fifteen squads on one cell — and
## separation then spends its whole budget shoving them outward past each
## other. Measured: 51-70 us/squad of separation against the 5-8 a real
## `just test-load` run reports. That is a pathological workload, not a
## defect, and a ladder built on it would attribute host noise and pile-up
## to whichever knob happened to be off.
const LADDER_RALLY_POINTS := 24

## Interleaved repeats, and the ladder reports the MINIMUM of them.
##
## Not the mean: this machine runs a dozen other agents' containers, and
## interference only ever ADDS time. The minimum is the closest thing to
## "what this configuration costs when nothing else is happening", and it
## is the statistic that makes a 3 us difference between two knobs
## readable at all. The first version took one pass each and reported
## 209.81 and 272.23 us/squad for the SAME configuration — a 30% spread,
## wider than every effect it was looking for, with knobs turned OFF
## reading as slower.
const LADDER_PASSES := 7


## One configuration of the world, and what it costs per squad-update.
##
## `off` names the suspect to disable, or "" for the shipped
## configuration. Returns the phase ladder in microseconds per
## squad-update, so every column is directly comparable with the
## `us/squad=` line `just test-load` prints.
##
## Terrain and the resource field are passed IN rather than built here:
## both are deterministic, both are expensive, and rebuilding them thirty
## times would put their variance inside the measurement.
func _ladder_run(space: TorusSpace, passable: PackedByteArray,
		terrain: TerrainGen, nodes: Dictionary, off: String) -> Dictionary:
	# `control` is the shipped configuration under another name — the
	# noise-floor row. Nothing below may branch on it.
	if off == "control":
		off = ""
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.set_passable(passable)

	if off != "buildings":
		sim.buildings = BuildingSim.new(space)
	if off != "economy":
		var economy := Economy.new(space)
		economy.terrain = terrain
		economy.nodes = nodes.duplicate(true)
		sim.economy = economy

	var civ_ids := CivRoster.ids()
	for player in range(1, LADDER_PLAYERS + 1):
		# TEAMS: two sides of two. Off means the dictionary the sim reads
		# is empty, which is what every pre-M6 build had.
		if off != "teams":
			sim.teams[player] = 1 + (player % 2)
		# CIV KNOBS: the resolved CivDef the sim reads for squad cap,
		# production and gather rate (D-20260823). Off means the
		# default-constructed CivDef an unknown civ resolves to, which is
		# the pre-#158 behaviour — the knobs present but unread.
		if off != "civ-knobs" and not civ_ids.is_empty():
			sim.civs[player] = CivRoster.effects_of(civ_ids[(player - 1) % civ_ids.size()])
	# RESEARCH is new in D-20260827 and is measured here for the same
	# reason the others are: a cost this branch ADDS belongs in the same
	# table as the costs it is attributing, not exempt from it.
	if off != "research":
		sim.research = ResearchState.new()

	var defs := UnitRoster.load_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF00D
	for i in range(LADDER_SQUADS):
		sim.add_squad(defs[i % defs.size()], 1 + (i % LADDER_PLAYERS), Vector2i(
			rng.randi_range(0, space.width - 1),
			rng.randi_range(0, space.height - 1)))

	# A town centre each, so the buildings pass has something to walk and
	# vision has stationary sources — the shape a real match has.
	if sim.buildings != null:
		var hall := BuildingSim.def_by_id(&"town_centre")
		if hall != null:
			for player in range(1, LADDER_PLAYERS + 1):
				sim.buildings.add_building(hall, player, Vector2i(
					rng.randi_range(0, space.width - 1),
					rng.randi_range(0, space.height - 1)), true)

	var rallies := []
	for r in range(LADDER_RALLY_POINTS):
		rallies.append(Vector2i(
			rng.randi_range(0, space.width - 1),
			rng.randi_range(0, space.height - 1)))

	# Warm up, THEN snapshot. See the header: an average that includes the
	# opening field solves is an average of a transient that never recurs.
	for tick in range(LADDER_WARMUP):
		if tick % MOVE_EVERY_TICKS == 0:
			for squad in range(sim.squad_count()):
				sim.order_move(squad, rallies[squad % LADDER_RALLY_POINTS])
		sim.tick()

	var keys := ["tick", "fields", "curves", "vision", "combat", "buildings",
		"production", "economy", "separation"]
	var before := {}
	for key in keys:
		before[key] = int(sim.get("total_%s_usec" % key))

	var worst := 0
	for tick in range(LADDER_TICKS):
		if tick % MOVE_EVERY_TICKS == 0:
			for squad in range(sim.squad_count()):
				sim.order_move(squad, rallies[squad % LADDER_RALLY_POINTS])
		sim.tick()
		worst = maxi(worst, sim.last_tick_usec)

	var updates := float(LADDER_TICKS * LADDER_SQUADS)
	var out := {"worst_ms": float(worst) / 1000.0}
	for key in keys:
		out[key] = float(int(sim.get("total_%s_usec" % key)) - int(before[key])) / updates
	# The residual is the honest column: whatever the tick spent that no
	# named phase claimed. #105's whole finding was that a tick with only
	# two reported phases hides its cost in the gap between them.
	var named := 0.0
	for key in keys:
		if key != "tick":
			named += float(out[key])
	out["other"] = float(out["tick"]) - named
	return out


## Map sizes the ladder runs the SHIPPED configuration at, 120 squads on
## each.
##
## 128x64 is M4's map, and it is here because it is the control the whole
## question turns on. M4 measured 40.8 us/squad at 120 squads on 8,192
## cells; the shipped map is 32,592. Without this row, every difference
## between that number and today's could be attributed to the feature set
## — which is exactly the invented attribution
## `D-20260818-every-microsecond-of-a-tick-has-a-phase` refused to make.
## Height must be even (D-008).
const LADDER_SIZES := [Vector2i(128, 64), Vector2i(168, 194)]


## The ladder, in two sections: what the MAP costs, and what each FEATURE
## costs. Squad count is held at `LADDER_SQUADS` throughout — the standing
## quote-it-with-the-count rule, applied by never varying it.
func _tick_ladder(config: MapConfig) -> void:
	print("profile: --- tick ladder, map size at %d squads, %d ticks after %d warm-up, best of %d ---"
		% [LADDER_SQUADS, LADDER_TICKS, LADDER_WARMUP, LADDER_PASSES])
	print("profile: cells,us_per_squad,fields,curves,vision,combat,buildings,production,economy,separation,other,ms_worst")
	var by_size := {}
	for _pass in range(LADDER_PASSES):
		for size in LADDER_SIZES:
			var s := TorusSpace.new(int(size.x), int(size.y), 1.0)
			var t := TerrainGen.new()
			t.noise_seed = 1337
			var e := Economy.new(s)
			e.generate(t, 1)
			var row := _ladder_run(s, t.passability(s), t, e.nodes, "")
			if not by_size.has(size) or float(row["tick"]) < float(by_size[size]["tick"]):
				by_size[size] = row
	for size in LADDER_SIZES:
		var row: Dictionary = by_size[size]
		print("profile: %d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.1f" % [
			int(size.x) * int(size.y),
			row["tick"], row["fields"], row["curves"], row["vision"],
			row["combat"], row["buildings"], row["production"], row["economy"],
			row["separation"], row["other"], row["worst_ms"]])

	var space := config.to_space()
	var terrain := TerrainGen.new()
	terrain.noise_seed = 1337
	var passable := terrain.passability(space)
	var template := Economy.new(space)
	template.generate(terrain, 1)

	print("profile: --- tick ladder, %d squads, %d players, %d ticks after %d warm-up, best of %d ---"
		% [LADDER_SQUADS, LADDER_PLAYERS, LADDER_TICKS, LADDER_WARMUP, LADDER_PASSES])
	print("profile: config,us_per_squad,fields,curves,vision,combat,buildings,production,economy,separation,other,ms_worst")

	# `control` is a SECOND run of the shipped configuration under a
	# different label, and it is the most important row in the table.
	#
	# It is the instrument's own error bar. Two runs of identical code,
	# interleaved with everything else, differ only by what the HOST was
	# doing — so the gap between `as shipped` and `control` is the
	# smallest difference this table can resolve, and any knob closer to
	# `as shipped` than that is not measurably anything. Without it a
	# reader has no way to tell a 4% effect from a 4% noise floor, and
	# this project has thrown away two sets of numbers for exactly that
	# reason already (M6's worst-tick figures, and `terrain.md`'s
	# bench-render absolutes).
	var configs := ["", "control", "teams", "economy", "civ-knobs", "buildings", "research"]
	var best := {}
	# INTERLEAVED: every configuration once per pass, so a host that gets
	# busier half way through hits all of them rather than reading as an
	# effect on whichever came last (the rule `docs/status/terrain.md`
	# bought the hard way).
	for _pass in range(LADDER_PASSES):
		for off in configs:
			var row := _ladder_run(space, passable, terrain, template.nodes, off)
			if not best.has(off) or float(row["tick"]) < float(best[off]["tick"]):
				best[off] = row

	for off in configs:
		var row: Dictionary = best[off]
		print("profile: %s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.1f" % [
			off if off != "" else "as shipped",
			row["tick"], row["fields"], row["curves"], row["vision"],
			row["combat"], row["buildings"], row["production"], row["economy"],
			row["separation"], row["other"], row["worst_ms"]])


## Client-side derivation cost — D-006's other half.
##
## D-006 sends squad curves and never soldier positions, so every soldier
## on screen is placed by the CLIENT, every frame, from its squad's curve.
## The bandwidth saving is measured (595 B/client/s at 20 players); the
## CPU it was traded for never was.
##
## Driven through a real ClientState fed by a real CurveReplicator, not by
## calling Formation directly: the question is what a client pays, and a
## client pays for the dictionary walk and the composition lookups too.
##
## The budget is a FRAME, not a tick. A client rendering at 60 fps has
## 16.7 ms for everything, so derivation needs to be a small fraction of
## that — and unlike the server's tick, there is no amortising it: every
## soldier must be somewhere every frame.
func _derive_sweep(config: MapConfig) -> void:
	print("profile: --- client derivation sweep ---")
	print("profile: squads,soldiers,us_per_soldier,ms_per_frame,pct_of_60fps_frame")

	for count in COUNTS:
		var space := config.to_space()
		var sim := SquadSim.new(space, CurveReplicator.new())
		sim.set_passable(TerrainGen.new().passability(space))

		var def := UnitRoster.first()
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xD00D
		for i in range(int(count)):
			sim.add_squad(def, 1, Vector2i(
				rng.randi_range(0, space.width - 1),
				rng.randi_range(0, space.height - 1)))
		for squad in range(sim.squad_count()):
			sim.order_move(squad, Vector2i(
				rng.randi_range(0, space.width - 1),
				rng.randi_range(0, space.height - 1)))

		# Feed a client exactly as the server would.
		var state := ClientState.new()
		var visible := sim.visible_to(1)
		state.handle_packet(NetProtocol.encode_welcome(1, space.width, space.height, visible))
		state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))
		for _i in range(5):
			sim.tick()
			for packet in sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1)):
				state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))

		# Many passes, because one frame's worth is too small to time.
		var passes := 30
		var soldiers := 0
		for _i in range(passes):
			soldiers = state.derive_all(sim.time)

		var per_soldier := state.mean_usec_per_soldier()
		var ms_per_frame := float(state.total_derive_usec) / float(passes) / 1000.0
		print("profile: %d,%d,%.4f,%.3f,%.1f%%" % [
			int(count), soldiers, per_soldier, ms_per_frame,
			ms_per_frame / 16.667 * 100.0])


## Map-size sweep — this is what answers Q8 (D-036/D-021).
##
## Flow-field build is a wrap-aware BFS over EVERY cell, rebuilt per
## destination, and D-021 names it the prime candidate for escaping to
## GDExtension "over 10,000+ cells". That threshold was an estimate
## nobody had measured. Ship map size was therefore an OUTPUT of this
## sweep rather than an input to it: pick the size from where the solver
## actually breaks, not from where it was guessed to.
##
## That direction reversed once D-040 amortised field building and worst
## tick went flat in map size — the solver stopped being what bounds a
## map, and the ladder is set by the zoom cap instead
## (D-20260817-the-zoom-cap-was-modelling-the-wrong-axis). So the sweep
## FOLLOWS the shipped sizes now, and its job is to keep checking that the
## flatness Q8 was closed on still holds where players actually play.
##
## Squad count is held fixed so the only variable is the map.
const MAP_SWEEP_SQUADS := 250


## The sizes swept, taken from the SHIPPED LADDER rather than a list of
## this sweep's own (#108).
##
## It kept its own list — 2,048 to 32,768 cells — and the ladder moved out
## from under it twice, most recently on 2026-08-17
## (D-20260817-the-zoom-cap-was-modelling-the-wrong-axis). By then the
## sweep's LARGEST map was the one every match is played on by default,
## and the top three quarters of what ships, out to 130,368 cells, had
## never been swept at all. Nothing failed: the sweep stayed green and
## kept answering a question about maps nobody plays.
##
## `MapSettings.sizes()` is the one definition of what ships, so a rung
## added to the ladder is a row added here and the two cannot disagree
## again. Every entry it offers is already a legal world — D-008 row
## parity included — which is why nothing is re-validated on the way past.
static func map_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for size in MapSettings.sizes():
		out.append(Vector2i(int(size["width"]), int(size["height"])))
	return out


## How many distinct destinations an order wave produces. A player orders
## groups, not individuals — D-007 shares one field across every squad
## heading to the same place, and that sharing IS the scaling claim.
const RALLY_POINTS := 8


func _map_sweep() -> void:
	# Run each map size with amortisation ON and OFF (D-040), so the
	# comparison is a measurement rather than an argument — and in the SAME
	# process, so host load cannot masquerade as the effect.
	#
	# This replaces the old quantisation A/B, which D-038 already settled:
	# snapping destinations bought ~18% and cost exact arrival, and it
	# stays off. Running it every sweep was paying for an answer already
	# written down.
	for amortised in [true, false]:
		print("profile: --- map sweep, %d squads, amortised=%s ---" % [
			MAP_SWEEP_SQUADS, "yes" if amortised else "no"])
		print("profile: cells,us_per_field,fields_built,us_per_squad,ms_per_tick,ms_worst_tick,builds_deferred,squad_waits")
		_map_sweep_at(1, SquadSim.DEFAULT_FIELD_CELLS_PER_TICK if amortised else -1)


func _map_sweep_at(quantum: int, cells_per_tick: int) -> void:
	for size in map_sizes():
		var space := TorusSpace.new(size.x, size.y, 1.0)
		var sim := SquadSim.new(space, CurveReplicator.new())
		sim.set_passable(TerrainGen.new().passability(space))
		sim.destination_quantum = quantum
		sim.field_cells_per_tick = cells_per_tick

		var defs := UnitRoster.load_all()
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xF00D

		for i in range(MAP_SWEEP_SQUADS):
			sim.add_squad(defs[i % defs.size()], 1 + (i % 4), Vector2i(
				rng.randi_range(0, space.width - 1),
				rng.randi_range(0, space.height - 1)))

		# Worst tick, not just the average. The average hid the problem
		# entirely: a map where one field build costs two thirds of a tick
		# still averages comfortably, because most ticks build nothing.
		var worst_usec := 0
		for tick in range(TICKS):
			if tick % MOVE_EVERY_TICKS == 0:
				# Squads are ordered in GROUPS to shared rally points, the
				# way a player orders an army. Giving each squad its own
				# random destination defeats D-007 sharing entirely and
				# measures a case the design never claimed to handle.
				var rallies := []
				for r in range(RALLY_POINTS):
					rallies.append(Vector2i(rng.randi_range(0, space.width - 1), rng.randi_range(0, space.height - 1)))
				for squad in range(sim.squad_count()):
					sim.order_move(squad, rallies[squad % RALLY_POINTS])
			sim.tick()
			worst_usec = maxi(worst_usec, sim.last_tick_usec)

		var per_field := 0.0
		if sim.fields_built > 0:
			per_field = float(sim.total_field_usec) / float(sim.fields_built)
		print("profile: %d,%.1f,%d,%.2f,%.3f,%.1f,%d,%d" % [
			space.cell_count(), per_field, sim.fields_built,
			sim.mean_usec_per_squad_update(),
			float(sim.total_tick_usec) / float(TICKS) / 1000.0,
			float(worst_usec) / 1000.0,
			sim.field_builds_deferred,
			sim.field_waits,
		])


func _run(config: MapConfig, squad_count: int, cells_per_tick: int) -> void:
	var space := config.to_space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.set_passable(TerrainGen.new().passability(space))
	sim.field_cells_per_tick = cells_per_tick

	# Two sides, so combat actually engages rather than every squad
	# peacefully ignoring every other.
	var defs := UnitRoster.load_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF00D  # fixed: a sweep must be comparable between runs

	for i in range(squad_count):
		var cell := Vector2i(
			rng.randi_range(0, space.width - 1),
			rng.randi_range(0, space.height - 1))
		sim.add_squad(defs[i % defs.size()], 1 + (i % 4), cell)

	# GROUP ordering, matching the map sweep. This used to give every squad
	# its own random destination — the workload D-038's correction already
	# identified as defeating D-007's sharing and measuring a case the
	# design explicitly does not optimise for. The correction was applied
	# to the map sweep and not to this one, so the published count table
	# kept measuring the flawed case for another milestone. Numbers from
	# before this change are not comparable to numbers after it.
	var worst_usec := 0
	for tick in range(TICKS):
		if tick % MOVE_EVERY_TICKS == 0:
			var rallies := []
			for r in range(RALLY_POINTS):
				rallies.append(Vector2i(
					rng.randi_range(0, space.width - 1),
					rng.randi_range(0, space.height - 1)))
			for squad in range(sim.squad_count()):
				sim.order_move(squad, rallies[squad % RALLY_POINTS])
		sim.tick()
		worst_usec = maxi(worst_usec, sim.last_tick_usec)

	var per_squad := sim.mean_usec_per_squad_update()
	var ms_per_tick := float(sim.total_tick_usec) / float(TICKS) / 1000.0
	print("profile: %d,%.2f,%.2f,%.2f,%.3f,%.1f,%d" % [
		squad_count,
		per_squad,
		float(sim.total_vision_usec) / float(TICKS * squad_count),
		float(sim.total_combat_usec) / float(TICKS * squad_count),
		ms_per_tick,
		float(worst_usec) / 1000.0,
		sim.fields_built,
	])


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
