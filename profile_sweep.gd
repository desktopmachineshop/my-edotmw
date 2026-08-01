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

	print("profile: %s (%dx%d), %d ticks per count" % [
		config.id, config.width, config.height, TICKS])
	print("profile: count,us_per_squad,us_vision,us_combat,ms_per_tick,fields_built")

	for count in COUNTS:
		_run(config, int(count))

	_map_sweep()
	quit(0)


## Map-size sweep — this is what answers Q8 (D-036/D-021).
##
## Flow-field build is a wrap-aware BFS over EVERY cell, rebuilt per
## destination, and D-021 names it the prime candidate for escaping to
## GDExtension "over 10,000+ cells". That threshold was an estimate
## nobody had measured. Ship map size is therefore an OUTPUT of this
## sweep rather than an input to it: pick the size from where the solver
## actually breaks, not from where it was guessed to.
##
## Squad count is held fixed so the only variable is the map.
const MAP_SIZES := [
	Vector2i(64, 32), Vector2i(128, 64), Vector2i(192, 96), Vector2i(256, 128),
]
const MAP_SWEEP_SQUADS := 250

## How many distinct destinations an order wave produces. A player orders
## groups, not individuals — D-007 shares one field across every squad
## heading to the same place, and that sharing IS the scaling claim.
const RALLY_POINTS := 8


func _map_sweep() -> void:
	# Run each map size with quantisation OFF and ON, so the comparison is
	# a measurement rather than an argument.
	for quantum in [1, 4]:
		print("profile: --- map sweep, %d squads, destination_quantum=%d ---" % [MAP_SWEEP_SQUADS, quantum])
		print("profile: cells,us_per_field,fields_built,us_per_squad,ms_per_tick,ms_worst_tick")
		_map_sweep_at(int(quantum))


func _map_sweep_at(quantum: int) -> void:
	for size in MAP_SIZES:
		var space := TorusSpace.new(size.x, size.y, 1.0)
		var sim := SquadSim.new(space, CurveReplicator.new())
		sim.set_passable(TerrainGen.new().passability(space))
		sim.destination_quantum = quantum

		var defs := [UnitRoster.by_id(&"militia"), UnitRoster.by_id(&"archers")]
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
		print("profile: %d,%.1f,%d,%.2f,%.3f,%.1f,%d" % [
			space.cell_count(), per_field, sim.fields_built,
			sim.mean_usec_per_squad_update(),
			float(sim.total_tick_usec) / float(TICKS) / 1000.0,
			float(worst_usec) / 1000.0,
			sim.field_builds_deferred,
		])


func _run(config: MapConfig, squad_count: int) -> void:
	var space := config.to_space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.set_passable(TerrainGen.new().passability(space))

	# Two sides, so combat actually engages rather than every squad
	# peacefully ignoring every other.
	var defs := [UnitRoster.by_id(&"militia"), UnitRoster.by_id(&"archers")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF00D  # fixed: a sweep must be comparable between runs

	for i in range(squad_count):
		var cell := Vector2i(
			rng.randi_range(0, space.width - 1),
			rng.randi_range(0, space.height - 1))
		sim.add_squad(defs[i % defs.size()], 1 + (i % 4), cell)

	for tick in range(TICKS):
		if tick % MOVE_EVERY_TICKS == 0:
			for squad in range(sim.squad_count()):
				sim.order_move(squad, Vector2i(
					rng.randi_range(0, space.width - 1),
					rng.randi_range(0, space.height - 1)))
		sim.tick()

	var per_squad := sim.mean_usec_per_squad_update()
	var ms_per_tick := float(sim.total_tick_usec) / float(TICKS) / 1000.0
	print("profile: %d,%.2f,%.2f,%.2f,%.3f,%d" % [
		squad_count,
		per_squad,
		float(sim.total_vision_usec) / float(TICKS * squad_count),
		float(sim.total_combat_usec) / float(TICKS * squad_count),
		ms_per_tick,
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
