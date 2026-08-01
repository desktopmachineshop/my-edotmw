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
	for amortised in [true, false]:
		print("profile: --- count sweep, amortised=%s ---" % ("yes" if amortised else "no"))
		print("profile: count,us_per_squad,us_vision,us_combat,ms_per_tick,ms_worst_tick,fields_built")
		for count in COUNTS:
			_run(config, int(count),
				SquadSim.DEFAULT_FIELD_CELLS_PER_TICK if amortised else -1)

	_map_sweep()
	_derive_sweep(config)
	quit(0)


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

		var def := UnitRoster.by_id(&"militia")
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
	for size in MAP_SIZES:
		var space := TorusSpace.new(size.x, size.y, 1.0)
		var sim := SquadSim.new(space, CurveReplicator.new())
		sim.set_passable(TerrainGen.new().passability(space))
		sim.destination_quantum = quantum
		sim.field_cells_per_tick = cells_per_tick

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
	var defs := [UnitRoster.by_id(&"militia"), UnitRoster.by_id(&"archers")]
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
