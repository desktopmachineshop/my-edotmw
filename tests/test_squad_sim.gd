extends GutTest

## Guards the simulation layer: D-005 (squads atomic), D-009 (packed
## arrays, no scene tree), D-020 (10 Hz), D-023 (explicit tick driver),
## and the integration of all of it with D-003's replication.
##
## The integration tests at the bottom are the actual M1 proof — the
## earlier files test the parts in isolation, these test that a squad
## ordered across the map arrives, replicates while moving, and goes
## silent when it stops.

const W := 32
const H := 16


func _sim() -> SquadSim:
	return SquadSim.new(TorusSpace.new(W, H, 1.0), CurveReplicator.new())


func _def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"test_infantry"
	d.squad_size = 12
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	return d


func _tick_for(sim: SquadSim, seconds: float) -> void:
	for _i in range(int(seconds * SquadSim.TICK_HZ)):
		sim.tick()


# --- structure -------------------------------------------------------

func test_tick_rate_is_ten_hz() -> void:
	assert_eq(SquadSim.TICK_HZ, 10.0, "D-020 fixes the sim tick at 10 Hz")


func test_one_tick_advances_time_by_one_hundred_milliseconds() -> void:
	var sim := _sim()
	sim.tick()
	assert_almost_eq(sim.time, 0.1, 0.0001)
	assert_eq(sim.tick_count, 1)


func test_sim_runs_without_a_scene_tree() -> void:
	# D-023's point: the sim is driven by an explicit accumulator, so it
	# steps in a plain loop. If this ever requires a SceneTree, replay
	# playback and these tests both break.
	var sim := _sim()
	sim.add_squad(_def(), 1, Vector2i(0, 0))
	for _i in range(50):
		sim.tick()
	assert_eq(sim.tick_count, 50)


func test_squad_state_is_not_nodes() -> void:
	# D-009 asserted structurally: SquadSim is a RefCounted holding packed
	# arrays, never one Node per squad.
	#
	# Checked at runtime via ClassDB rather than with `sim is Node` —
	# the latter is a *parse* error today ("Expression is of type SquadSim
	# so it can't be of type Node"), which is a stronger guarantee than
	# this test, but one that would vanish the moment someone changed the
	# base class. This assertion survives that change and fails loudly.
	var sim := _sim()
	assert_false(ClassDB.is_parent_class(sim.get_class(), "Node"),
		"SquadSim must not derive from Node (D-009) — got %s" % sim.get_class())
	for _i in range(100):
		sim.add_squad(_def(), 1, Vector2i(randi() % W, randi() % H))
	assert_eq(sim.squad_count(), 100)


# --- movement --------------------------------------------------------

func test_new_squad_starts_idle_at_its_spawn_cell() -> void:
	var sim := _sim()
	var id := sim.add_squad(_def(), 1, Vector2i(5, 5))
	assert_eq(sim.cell_of(id), Vector2i(5, 5))
	assert_true(sim.is_idle(id), "A squad with no order should be idle")


func test_ordered_squad_reaches_its_destination() -> void:
	var sim := _sim()
	var id := sim.add_squad(_def(), 1, Vector2i(2, 2))
	sim.order_move(id, Vector2i(12, 6))

	_tick_for(sim, 30.0)

	assert_eq(sim.cell_of(id), Vector2i(12, 6), "Squad should arrive at its ordered destination")
	assert_true(sim.is_idle(id), "An arrived squad should be idle again")


func test_squad_takes_the_short_way_across_the_seam() -> void:
	# The end-to-end version of the wrap tests: a squad ordered to a cell
	# just across the seam should arrive quickly, not lap the map.
	var sim := _sim()
	var id := sim.add_squad(_def(), 1, Vector2i(W - 2, 8))
	sim.order_move(id, Vector2i(1, 8))

	_tick_for(sim, 5.0)

	assert_eq(sim.cell_of(id), Vector2i(1, 8),
		"A squad should cross the seam in a few seconds, not lap the map")


func test_squad_speed_is_derived_from_unit_def() -> void:
	var slow := _def()
	slow.move_speed = 1.0
	var fast := _def()
	fast.move_speed = 7.0

	var sim := _sim()
	var slow_id := sim.add_squad(slow, 1, Vector2i(0, 4))
	var fast_id := sim.add_squad(fast, 1, Vector2i(0, 10))
	sim.order_move(slow_id, Vector2i(20, 4))
	sim.order_move(fast_id, Vector2i(20, 10))

	_tick_for(sim, 3.0)

	var slow_progress := sim.space.distance(Vector2i(0, 4), sim.cell_of(slow_id))
	var fast_progress := sim.space.distance(Vector2i(0, 10), sim.cell_of(fast_id))
	assert_gt(fast_progress, slow_progress, "A faster UnitDef should cover more ground")


func test_re_ordering_mid_march_redirects_the_squad() -> void:
	var sim := _sim()
	var id := sim.add_squad(_def(), 1, Vector2i(0, 0))
	sim.order_move(id, Vector2i(20, 0))
	_tick_for(sim, 2.0)

	sim.order_move(id, Vector2i(4, 12))
	_tick_for(sim, 30.0)

	assert_eq(sim.cell_of(id), Vector2i(4, 12), "A re-ordered squad should honour the new destination")


func test_flow_fields_are_shared_per_destination_not_per_squad() -> void:
	# D-007's scaling claim, asserted by counting builds.
	var sim := _sim()
	var ids := []
	for i in range(20):
		ids.append(sim.add_squad(_def(), 1, Vector2i(i, 0)))

	for id in ids:
		sim.order_move(id, Vector2i(15, 8))

	assert_eq(sim.fields_built, 1,
		"20 squads sharing one destination should build ONE flow field, not 20")


func test_distinct_destinations_build_distinct_fields() -> void:
	var sim := _sim()
	var a := sim.add_squad(_def(), 1, Vector2i(0, 0))
	var b := sim.add_squad(_def(), 1, Vector2i(1, 0))
	sim.order_move(a, Vector2i(10, 4))
	sim.order_move(b, Vector2i(20, 10))
	assert_eq(sim.fields_built, 2)


# --- casualties (D-006 clause 3) -------------------------------------

func test_casualties_reduce_derived_soldiers_without_touching_the_curve() -> void:
	var sim := _sim()
	var id := sim.add_squad(_def(), 1, Vector2i(6, 6))

	assert_eq(sim.soldier_transforms(id).size(), 12)

	var curve_before := sim.curve_of(id)
	sim.set_alive(id, 7)

	assert_eq(sim.soldier_transforms(id).size(), 7,
		"Soldier count should follow the alive count with no extra bookkeeping")
	assert_eq(sim.curve_of(id), curve_before,
		"Casualties must not invalidate the squad curve — soldiers are derived, not networked")


# --- replication integration (the M1 proof) --------------------------

func test_moving_squad_replicates_and_idle_squad_goes_silent() -> void:
	var sim := _sim()
	var id := sim.add_squad(_def(), 1, Vector2i(1, 1))
	var visible := sim.visible_to(1)

	# Drain the spawn delivery.
	sim.replicator.collect_for_client(1, sim.time, visible)

	sim.order_move(id, Vector2i(18, 9))

	var moving_bytes := 0
	for _i in range(60):
		sim.tick()
		moving_bytes += CurveReplicator.total_bytes(
			sim.replicator.collect_for_client(1, sim.time, visible))
	assert_gt(moving_bytes, 0, "A marching squad must replicate")

	# Let it arrive and settle.
	_tick_for(sim, 40.0)
	assert_true(sim.is_idle(id), "Squad should have arrived")
	for _i in range(5):
		sim.tick()
		sim.replicator.collect_for_client(1, sim.time, visible)

	var idle_bytes := 0
	for _i in range(30):
		sim.tick()
		idle_bytes += CurveReplicator.total_bytes(
			sim.replicator.collect_for_client(1, sim.time, visible))

	assert_eq(idle_bytes, 0,
		"An arrived squad must cost zero bandwidth — the whole point of D-003")


func test_client_derives_the_same_soldier_positions_the_server_has() -> void:
	# D-006's central claim, end to end: the server sends only squad
	# curves, and the client reconstructs soldier positions that match.
	var sim := _sim()
	var id := sim.add_squad(_def(), 1, Vector2i(3, 3))
	sim.order_move(id, Vector2i(14, 7))
	_tick_for(sim, 2.0)

	var packets := sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1))
	assert_gt(packets.size(), 0, "The squad should have replicated by now")

	var decoded := CurveReplicator.decode_packet(packets[0]["bytes"])
	var client_curve: StateCurve = decoded["curve"]
	var client_space := TorusSpace.new(W, H, 1.0)

	var server_soldiers := sim.soldier_transforms(id)
	var client_soldiers := Formation.soldier_transforms(
		client_curve, sim.time, sim.alive_of(id), "line", 1.0, client_space)

	assert_eq(server_soldiers.size(), client_soldiers.size())
	for i in range(server_soldiers.size()):
		assert_almost_eq(client_soldiers[i].origin.x, server_soldiers[i].origin.x, 0.001,
			"Soldier %d x diverges between server and client" % i)
		assert_almost_eq(client_soldiers[i].origin.z, server_soldiers[i].origin.z, 0.001,
			"Soldier %d z diverges between server and client" % i)


func test_mass_order_is_absorbed_by_the_replication_budget() -> void:
	# D-003's named spike risk, at the sim level: order every squad at
	# once and confirm no tick blows the budget.
	var sim := _sim()
	sim.replicator.byte_budget_per_tick = 2048

	var ids := []
	for i in range(200):
		ids.append(sim.add_squad(_def(), 1, Vector2i(i % W, (i / W) % H)))
	var visible := sim.visible_to(1)

	for id in ids:
		sim.order_move(id, Vector2i(16, 8))

	for tick in range(100):
		sim.tick()
		var sent := CurveReplicator.total_bytes(
			sim.replicator.collect_for_client(1, sim.time, visible))
		assert_lte(sent, sim.replicator.byte_budget_per_tick,
			"Tick %d sent %d bytes against a %d budget" % [tick, sent, sim.replicator.byte_budget_per_tick])


func test_per_squad_update_cost_is_measurable() -> void:
	# D-012 requires per-squad update cost be measurable and swappable
	# from M1, even though LOD itself is M5. This asserts the measurement
	# exists and is plausible — not a performance threshold, which would
	# be a flaky assertion on shared CI hardware.
	var sim := _sim()
	for i in range(200):
		sim.add_squad(_def(), 1, Vector2i(i % W, (i / W) % H))
	for _i in range(20):
		sim.tick()

	assert_gt(sim.tick_count, 0)
	assert_gte(sim.mean_usec_per_squad_update(), 0.0,
		"Per-squad update cost must be measurable from M1 (D-012)")
	gut.p("mean usec per squad-update: %f (200 squads, 20 ticks)" % sim.mean_usec_per_squad_update())


# --- configuration invariants ----------------------------------------

func test_lookahead_must_exceed_the_replication_horizon() -> void:
	# The sim writes `curve_lookahead_seconds` of path into each curve; the
	# replicator only ships `horizon_seconds` of it. If the horizon is
	# raised past the lookahead — a natural thing to try while tuning —
	# clients run out of curve between updates and squads stutter, with
	# nothing anywhere explaining why. Previously this was a comment.
	var sim := _sim()
	assert_true(sim.is_valid(), "Default configuration should be valid: %s" % sim.validate())

	sim.replicator.horizon_seconds = sim.curve_lookahead_seconds
	assert_false(sim.is_valid(), "Equal lookahead and horizon leaves no margin and must be rejected")

	sim.replicator.horizon_seconds = sim.curve_lookahead_seconds + 1.0
	assert_false(sim.is_valid(), "A horizon beyond the lookahead must be rejected")
	assert_string_contains(sim.validate(), "horizon")


func test_invalid_configuration_is_reported_on_first_tick() -> void:
	# Validated lazily rather than at construction, because callers
	# legitimately set horizon and lookahead after wiring the two together.
	var sim := _sim()
	sim.replicator.horizon_seconds = 99.0
	sim.tick()
	assert_push_error_count(1, "A bad lookahead/horizon pairing should be reported once")

	# ...and only once, not every tick.
	for _i in range(5):
		sim.tick()
	assert_push_error_count(1, "The configuration complaint should not repeat every tick")


func test_squad_info_entries_describe_what_the_server_spawned() -> void:
	var sim := _sim()
	var def := _def()
	var id := sim.add_squad(def, 1, Vector2i(2, 2))

	var entries := sim.squad_info_entries([id])
	assert_eq(entries.size(), 1)
	assert_eq(int(entries[0]["id"]), id)
	assert_eq(String(entries[0]["def_id"]), String(def.id))
	assert_eq(int(entries[0]["alive"]), def.squad_size)


func test_composition_hash_tracks_casualties() -> void:
	# Once combat lands in M2, a client that misses a casualty event will
	# derive the wrong formation. The hash must notice.
	var sim := _sim()
	var id := sim.add_squad(_def(), 1, Vector2i(2, 2))
	var before := sim.composition_hash([id])

	sim.set_alive(id, sim.alive_of(id) - 1)
	assert_ne(sim.composition_hash([id]), before,
		"Losing a soldier must change the composition hash")
