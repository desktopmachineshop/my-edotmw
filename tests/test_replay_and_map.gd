extends GutTest

## Guards D-016 (replays ARE the curve log) and the map data (D-008's
## row parity, enforced at the data level so a bad .tres fails the suite
## rather than misaligning the seam at runtime).

const W := 32
const H := 16
const REPLAY_PATH := "user://test-replay.edmw"


func after_each() -> void:
	if FileAccess.file_exists(REPLAY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REPLAY_PATH))


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"replay_test"
	d.squad_size = 8
	d.move_speed = 3.5
	return d


# --- map data ---------------------------------------------------------

func test_every_map_tres_loads_and_is_valid() -> void:
	var dir := DirAccess.open("res://maps")
	assert_not_null(dir, "res://maps should exist")
	if dir == null:
		return

	var found := 0
	for file_name in dir.get_files():
		var normalised := file_name.trim_suffix(".remap")
		if not normalised.ends_with(".tres"):
			continue
		found += 1
		var path := "res://maps/%s" % normalised
		var config := load(path) as MapConfig
		assert_not_null(config, "%s should load as a MapConfig" % path)
		if config == null:
			continue
		# The row-parity rule (D-008) bites here: an odd height in a .tres
		# would otherwise only show up as a misaligned seam in play.
		assert_eq(config.validate(), "", "%s is invalid: %s" % [path, config.validate()])
		assert_eq(config.height % 2, 0, "%s has an odd height, breaking D-008 row parity" % path)

	assert_gt(found, 0, "No map .tres files found in res://maps")


func test_map_config_rejects_an_odd_height() -> void:
	var config := MapConfig.new()
	config.width = 32
	config.height = 15
	assert_false(config.is_valid(), "An odd-height map must be rejected")


func test_map_config_delegates_geometry_to_torus_space() -> void:
	# One definition of a legal torus, not two.
	var config := MapConfig.new()
	config.width = 1
	config.height = 16
	assert_eq(config.validate(), config.to_space().validate())


# --- replay format ----------------------------------------------------

func test_replay_roundtrips_curves() -> void:
	var space := _space()
	var log := ReplayLog.new()
	assert_eq(log.open_for_write(REPLAY_PATH, 10.0, space), OK)

	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(1, 1), space)
	curve.append_cell(1.0, Vector2i(2, 1), space)
	curve.append_cell(2.0, Vector2i(3, 1), space)

	log.record(0.0, 42, 1, curve)
	log.close()

	var replay := ReplayLog.read(REPLAY_PATH)
	assert_eq(int(replay["width"]), W)
	assert_eq(int(replay["height"]), H)
	assert_almost_eq(float(replay["tick_hz"]), 10.0, 0.001)
	assert_eq(replay["records"].size(), 1)

	var restored: StateCurve = replay["records"][0]["curve"]
	assert_eq(restored.key_count(), curve.key_count())
	assert_eq(restored.sample_cell(2.0, space), Vector2i(3, 1))


func test_replay_uses_the_same_serialization_as_the_wire() -> void:
	# D-016's point: one format, so a replay cannot describe something the
	# network never sent.
	var space := _space()
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(4, 4), space)
	curve.append_cell(1.0, Vector2i(5, 4), space)

	var log := ReplayLog.new()
	log.open_for_write(REPLAY_PATH, 10.0, space)
	log.record(0.5, 7, 3, curve)
	log.close()

	var from_replay: StateCurve = ReplayLog.read(REPLAY_PATH)["records"][0]["curve"]
	var from_wire := StateCurve.from_bytes(curve.to_bytes())

	assert_eq(from_replay.to_bytes(), from_wire.to_bytes(),
		"Replay and wire encodings must be byte-identical")


func test_reading_a_non_replay_file_fails_cleanly() -> void:
	var file := FileAccess.open(REPLAY_PATH, FileAccess.WRITE)
	file.store_string("this is definitely not a replay")
	file.close()

	var replay := ReplayLog.read(REPLAY_PATH)
	assert_eq(replay.size(), 0, "A non-replay file should read as empty, not crash")
	# The error is part of the contract, not incidental noise: a replay
	# that silently reads as empty would be discovered only when someone
	# needed it to diagnose a desync.
	assert_push_error_count(1, "Reading a non-replay should report exactly one error")


func test_truncated_replay_keeps_what_it_can() -> void:
	# The interesting case: a server killed mid-write (Ctrl-C on a load
	# test). A partial replay of a crash is exactly what you want back.
	var space := _space()
	var log := ReplayLog.new()
	log.open_for_write(REPLAY_PATH, 10.0, space)
	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(1, 1), space)
	log.record(0.0, 1, 1, curve)
	log.record(0.1, 2, 1, curve)
	log.close()

	var whole := FileAccess.get_file_as_bytes(REPLAY_PATH)
	var truncated := whole.slice(0, whole.size() - 6)
	var out := FileAccess.open(REPLAY_PATH, FileAccess.WRITE)
	out.store_buffer(truncated)
	out.close()

	var replay := ReplayLog.read(REPLAY_PATH)
	assert_gt(replay["records"].size(), 0,
		"A truncated replay should still yield its complete records")


func test_reconstruct_at_returns_state_as_of_a_time() -> void:
	var space := _space()
	var log := ReplayLog.new()
	log.open_for_write(REPLAY_PATH, 10.0, space)

	var early := StateCurve.new()
	early.append_cell(0.0, Vector2i(1, 1), space)
	var late := StateCurve.new()
	late.append_cell(5.0, Vector2i(9, 9), space)

	log.record(0.0, 1, 1, early)
	log.record(5.0, 1, 2, late)
	log.close()

	var replay := ReplayLog.read(REPLAY_PATH)

	var at_two := ReplayLog.reconstruct_at(replay, 2.0)
	assert_eq((at_two[1] as StateCurve).sample_cell(0.0, space), Vector2i(1, 1),
		"At t=2 the squad should still be described by its first curve")

	var at_ten := ReplayLog.reconstruct_at(replay, 10.0)
	assert_eq((at_ten[1] as StateCurve).sample_cell(5.0, space), Vector2i(9, 9),
		"At t=10 the later curve should have replaced it")


# --- replay integrated with the sim -----------------------------------

func test_sim_records_a_replayable_log_of_a_march() -> void:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var log := ReplayLog.new()
	assert_eq(log.open_for_write(REPLAY_PATH, SquadSim.TICK_HZ, space), OK)
	sim.replay = log

	var id := sim.add_squad(_def(), 1, Vector2i(2, 2))
	sim.order_move(id, Vector2i(20, 10))
	for _i in range(200):
		sim.tick()
	var final_cell := sim.cell_of(id)
	log.close()

	var replay := ReplayLog.read(REPLAY_PATH)
	assert_gt(replay["records"].size(), 1,
		"A march should produce several curve records as the path is extended")

	# Replaying to the end must put the squad where the sim left it —
	# this is what makes the log a replay rather than a diagnostic dump.
	var state := ReplayLog.reconstruct_at(replay, sim.time)
	assert_true(state.has(id), "The replay should describe the squad")
	var replayed: StateCurve = state[id]
	assert_eq(replayed.sample_cell(sim.time, space), final_cell,
		"Replayed position at the final time should match the simulation")


func test_idle_squad_adds_no_replay_records() -> void:
	# Replays inherit D-003's zero-cost-when-idle property for free, which
	# is why D-016 calls capture "nearly free".
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var log := ReplayLog.new()
	log.open_for_write(REPLAY_PATH, SquadSim.TICK_HZ, space)
	sim.replay = log

	sim.add_squad(_def(), 1, Vector2i(4, 4))
	var after_spawn := log.records_written

	for _i in range(100):
		sim.tick()

	assert_eq(log.records_written, after_spawn,
		"An idle squad should not append replay records every tick")
	log.close()
