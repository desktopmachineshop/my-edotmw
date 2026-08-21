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


# --- amortised flow-field builds, D-040 -------------------------------

func test_an_order_wave_under_a_tight_budget_still_arrives() -> void:
	# The whole point of amortisation: spreading a BFS across ticks may
	# delay a squad, and must never lose its order.
	#
	# The failure mode this is written against is specific and was a real
	# risk in the implementation: _rebuild_curve's give-up rule reads "the
	# field cannot move this squad" as "the destination is unreachable"
	# and cancels the order. On an UNFINISHED field that is true of every
	# squad the wavefront has not reached yet, so a single misordered
	# check would silently cancel an entire order wave.
	var sim := _sim()
	sim.field_cells_per_tick = 30  # a small fraction of one 512-cell field

	var destinations := [
		Vector2i(28, 2), Vector2i(4, 13), Vector2i(20, 9),
		Vector2i(12, 3), Vector2i(1, 8), Vector2i(25, 14),
	]
	var squads := []
	for i in range(destinations.size()):
		squads.append(sim.add_squad(_def(), 1, Vector2i(i * 2, 0)))
	for i in range(squads.size()):
		sim.order_move(squads[i], destinations[i])

	_tick_for(sim, 30.0)

	for i in range(squads.size()):
		assert_eq(sim.cell_of(squads[i]), destinations[i],
			"Squad %d never arrived — its order was dropped, not merely delayed" % i)
	assert_gt(sim.field_waits, 0,
		"No squad ever waited, so the tight budget was not actually exercised")


func test_a_quiet_tick_builds_its_field_outright() -> void:
	# Amortisation must be invisible in ordinary play. One new destination
	# with the default budget finishes in the tick it is asked for, so a
	# single squad given an order paths immediately, exactly as before.
	var sim := _sim()
	var squad := sim.add_squad(_def(), 1, Vector2i(0, 0))
	sim.order_move(squad, Vector2i(20, 10))
	sim.tick()

	assert_eq(sim.field_waits, 0, "A lone order should not have to wait for its field")
	assert_true(sim.curve_of(squad).key_count() > 1,
		"The squad should have a real path after one tick, not a single keyframe")


func test_a_walled_off_destination_is_still_given_up_on() -> void:
	# The give-up rule must survive amortisation. "Not reached yet" and
	# "no path" are different, and the new wait must not swallow the
	# second one — a squad re-pathing forever was a real defect (D-038).
	var sim := _sim()
	var passable := PackedByteArray()
	passable.resize(sim.space.cell_count())
	passable.fill(1)
	# Wall the destination in on every side.
	var dest := Vector2i(10, 6)
	var dest_index := sim.space.index(dest)
	for dir in range(6):
		passable[sim.space.neighbor_index(dest_index, dir)] = 0
	sim.set_passable(passable)

	var squad := sim.add_squad(_def(), 1, Vector2i(0, 0))
	sim.order_move(squad, dest)
	# Long enough to walk the whole way there and find out.
	# D-20260818-pathing-knows-only-what-the-player-knows moved WHEN this
	# fires, not whether: the wall is now discovered rather than known from
	# the first tick, so the squad marches up to it before giving up. The
	# claim under test is unchanged — once it has given up it must stay
	# given up, or it re-paths every tick forever.
	_tick_for(sim, 20.0)

	assert_ne(sim.cell_of(squad), dest, "The destination is walled off; nothing should reach it")
	var rebuilt := sim.curves_rebuilt
	_tick_for(sim, 3.0)
	assert_eq(sim.curves_rebuilt, rebuilt,
		"The squad is still re-pathing every tick — the give-up rule stopped firing")


func test_a_gate_opening_lets_a_given_up_order_resume() -> void:
	# The playtest bug this guards: a squad ordered through a closed gate
	# hit the SAME give-up path test_a_walled_off_destination_is_still_
	# given_up_on exercises, and — before this fix — that was permanent.
	# A gate is passability that changes at runtime, unlike the wall
	# above, so "unreachable when I asked" must not mean "unreachable
	# forever": set_passable (what a gate opening actually calls) has to
	# give the order a real second chance.
	var sim := _sim()
	var passable := PackedByteArray()
	passable.resize(sim.space.cell_count())
	passable.fill(1)
	var dest := Vector2i(10, 6)
	var dest_index := sim.space.index(dest)
	for dir in range(6):
		passable[sim.space.neighbor_index(dest_index, dir)] = 0
	sim.set_passable(passable)

	var squad := sim.add_squad(_def(), 1, Vector2i(0, 0))
	sim.order_move(squad, dest)
	_tick_for(sim, 3.0)
	assert_ne(sim.cell_of(squad), dest, "setup: the destination starts walled off")

	# The gate opens: passability changes so the destination is reachable
	# again, exactly like blocking_cells() no longer reporting an open
	# gate's cell.
	for dir in range(6):
		passable[sim.space.neighbor_index(dest_index, dir)] = 1
	sim.set_passable(passable)
	_tick_for(sim, 20.0)

	assert_eq(sim.cell_of(squad), dest,
		"the squad should have resumed its original order once the way opened, "
		+ "not stayed abandoned where it gave up")


# --- squads take up room (D-060) ---------------------------------------

func test_squads_ordered_to_one_point_do_not_end_up_stacked() -> void:
	# Reported from a real game: twenty squads could sit on one cell in a
	# single heap. Separation happens on ARRIVAL, not by spreading
	# destinations — see _separate_arrivals for why that distinction is
	# load-bearing.
	#
	# The map is 64x32 rather than the file's usual 32x16 because squads
	# claim the ground they actually cover now (#104): eight of these need
	# six cells between each pair, and eight disks of radius five do not
	# fit in 512 cells. A toy map that cannot hold the squads would have
	# been testing the give-up branch, not the rule.
	var space := TorusSpace.new(64, 32, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := UnitRoster.first()

	var squads := []
	for i in range(8):
		squads.append(sim.add_squad(def, 1, Vector2i(2 + i, 2)))
	for squad in squads:
		sim.order_move(squad, Vector2i(32, 16))

	for _i in range(600):
		sim.tick()

	var seen := {}
	for squad in squads:
		var cell := sim.cell_index_of(squad)
		assert_false(seen.has(cell),
			"squads %s and %d are standing on the same cell" % [seen.get(cell, "?"), squad])
		seen[cell] = squad


func test_a_displaced_squad_steps_aside_rather_than_teleporting() -> void:
	# D-060 says the displaced squad takes "the nearest free cell". It did
	# not: `_free_cell_near` walks `TorusSpace.disk_offsets`, which
	# enumerates dq-major from -radius rather than by distance, so the
	# first free cell it met was up to four cells away and always in the
	# same direction. Two squads ordered onto one point ended up four cells
	# apart, which is how a second melee squad sent at a building landed
	# outside its own reach and stood there for the rest of the match.
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := UnitRoster.first()

	var first := sim.add_squad(def, 1, Vector2i(4, 8))
	var second := sim.add_squad(def, 1, Vector2i(6, 8))
	sim.order_move(first, Vector2i(16, 8))
	sim.order_move(second, Vector2i(16, 8))

	for _i in range(600):
		sim.tick()

	var apart := space.distance(sim.cell_of(first), sim.cell_of(second))
	# The contract since D-20260821-a-fight-loosens-a-formation (the
	# owner's call, reverting #104's ally half): D-060's original rule —
	# no two settled squads share a CENTRE CELL — and nothing more.
	# Overlapping formations are resolved at the individual DRAWN man by
	# the cross-squad jostle, not by teleporting a whole squad sideways.
	assert_gte(apart, 1,
		"two settled squads may overlap but never share a centre cell")


# --- squads hold distinct centres; their men sort out the rest ---------

func test_settled_squads_keep_distinct_centres_and_nothing_more() -> void:
	# This test carried #104's footprint rule (playtest P06's "units all
	# pile on top of each other"). D-20260821-a-fight-loosens-a-formation
	# reverted that by the owner's call: displacing a whole allied squad
	# by two footprints IS the "whole squad snaps or moves" a player
	# sees, and overlap is resolved at the individual DRAWN man now (the
	# cross-squad jostle). What the SIM still guarantees — and what this
	# test now guards — is D-060's original rule: distinct centre cells,
	# so stacking is never total.
	var space := TorusSpace.new(64, 32, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := UnitRoster.by_id(&"legion_militia")
	assert_not_null(def, "setup: the shipped militia def should exist")

	var squads := []
	for i in range(4):
		squads.append(sim.add_squad(def, 1, Vector2i(4 + i * 2, 4)))
	for squad in squads:
		sim.order_move(squad, Vector2i(32, 16))

	for _i in range(900):
		sim.tick()

	for a in squads:
		for b in squads:
			if a >= b:
				continue
			assert_gte(space.distance(sim.cell_of(a), sim.cell_of(b)), 1,
				"squads %d and %d share a centre cell — even loosened "
					% [a, b]
				+ "battle order never stacks two squads on one point")


func test_a_squad_claims_the_room_its_formation_actually_covers() -> void:
	# `Formation.footprint` has computed this since selection needed it,
	# and the simulation had never read it. If the two ever disagree the
	# separation rule is back to guessing, so they are pinned to each
	# other here rather than in prose.
	var space := TorusSpace.new(64, 32, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := UnitRoster.by_id(&"legion_militia")
	var squad := sim.add_squad(def, 1, Vector2i(8, 8))

	var world: float = Formation.footprint(
		sim.shape_of(squad), sim.alive_of(squad), def.formation_spacing)["radius"]
	assert_eq(sim.footprint_cells(squad),
		ceili(world / (TorusSpace.SQRT_3 * space.hex_size)),
		"the simulation's idea of how much room a squad takes must be "
		+ "Formation.footprint's, converted to cells")
	assert_true(sim.footprint_cells(squad) >= 2,
		"a %d-strong line covers %.2f world units and must therefore claim more "
			% [sim.alive_of(squad), world]
		+ "than the single cell separation used to guarantee")


func test_an_enemy_is_not_pushed_out_of_its_own_attack_range() -> void:
	# Found by test_wall_top going red while this was being written, and
	# worth its own check: applying footprint clearance to ENEMIES as well
	# shoves a squad about eight cells off the opponent it has just
	# reached — and a melee `attack_range` is under two world units, a
	# little over ONE cell. No engagement could ever land. Enemies keep
	# D-060's original one cell; interpenetrating them is what a fight
	# looks like.
	var space := TorusSpace.new(64, 32, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := UnitRoster.by_id(&"legion_militia")

	var mine := sim.add_squad(def, 1, Vector2i(20, 10))
	var theirs := sim.add_squad(def, 2, Vector2i(20, 10))
	_tick_for(sim, 4.0)

	var apart := space.distance(sim.cell_of(mine), sim.cell_of(theirs))
	assert_true(apart <= 1,
		"two enemy squads settled %d cells apart — a melee squad reaches a " % apart
		+ "little over one cell, so anything more than D-060's original one "
		+ "puts every engagement out of reach")


func test_a_working_gatherer_crew_is_not_moved_by_footprint_separation() -> void:
	# The exemption that had to survive the rewrite: several crews on one
	# node is normal, and separating them once produced an economy with 22
	# gatherer squads and a stockpile that never rose above its starting
	# value. Crews HOLD ground now — an arriving squad goes round them —
	# but are still never the ones that move.
	var space := TorusSpace.new(64, 32, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var economy := Economy.new(space)
	sim.economy = economy
	var def := UnitRoster.by_id(&"gatherers")

	var node := Vector2i(20, 10)
	var node_index := space.index(node)
	economy.nodes[node_index] = {
		"kind": Economy.ResourceKind.WOOD, "remaining": 500,
	}

	var crews := []
	for _i in range(3):
		var crew := sim.add_squad(def, 1, node)
		assert_true(economy.order_gather(sim, crew, node_index),
			"setup: a gatherer crew standing on a node can work it")
		crews.append(crew)

	for _i in range(20):
		sim.tick()

	for crew in crews:
		assert_true(economy.is_gathering(crew),
			"setup: crew %d should still be on its haul" % crew)
		assert_eq(sim.cell_of(crew), node,
			"crew %d was shoved off the node it is working" % crew)


func test_separation_does_not_cost_extra_flow_fields() -> void:
	# The regression the first attempt caused, and the reason separation
	# moved to arrival: spreading DESTINATIONS gave twenty squads twenty
	# different goals and therefore twenty flow fields, destroying D-007's
	# per-destination sharing — the whole scaling claim.
	var space := TorusSpace.new(32, 16, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var def := UnitRoster.first()

	var squads := []
	for i in range(12):
		squads.append(sim.add_squad(def, 1, Vector2i(2, 2 + (i % 8))))
	var before := sim.fields_built
	for squad in squads:
		sim.order_move(squad, Vector2i(20, 9))
	for _i in range(60):
		sim.tick()

	assert_lt(sim.fields_built - before, 4,
		"twelve squads sharing one destination built %d flow fields — "
		% (sim.fields_built - before) + "per-destination sharing (D-007) is broken")
