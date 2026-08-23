extends GutTest

## Guards D-20260819-a-casualty-is-visible: the wire's `fell` flag, the
## client's casualty-site drain, and the corpse ledger's cap, eviction and
## derived fall phase. Also holds the layer's D-006 clause 2 boundary in
## both directions (nothing simulation-side reads the corpse classes, and
## client.gd actually feeds them — the D-055 caller-exists rule).
##
## The RENDER half — MultiMeshes, the tip-over, fog dimming — is checked
## by looking at `just gen-duel-preview`'s picture, because a headless
## MultiMesh stores nothing (D-20260817-fog-covers-props) and an assertion
## here about instance data would pass vacuously forever.

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _fighter_def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"corpse_test_fighter"
	d.squad_size = 10
	d.health = 20.0
	d.damage = 50.0
	d.attack_interval = 0.1
	d.attack_range = 3.0
	d.morale = 1000.0
	return d


# --- the wire (fell flag) ---------------------------------------------

func test_the_wire_carries_fell_and_defaults_it_false() -> void:
	var wire := NetProtocol.encode_squad_combat(7, [
		{"id": 1, "alive": 8, "routed": false, "fell": true},
		# No key at all — consume_squad and eliminate_player build their
		# events without one, and the encoder must read that as false
		# rather than crash or invent a body.
		{"id": 2, "alive": 0, "routed": false},
	])
	var events: Array = NetProtocol.decode_squad_combat(wire)["events"]
	assert_true(bool(events[0]["fell"]), "combat's word survives the wire")
	assert_false(bool(events[1]["fell"]),
		"an event that never said fell decodes as not-fallen — a founding "
		+ "party spent on a town hall must not leave bodies at the door")


func test_combat_marks_its_casualties_fell() -> void:
	var sim := _sim()
	sim.add_squad(_fighter_def(), 1, Vector2i(5, 5))
	sim.add_squad(_fighter_def(), 2, Vector2i(6, 5))
	# Collected PER TICK: last_combat_events holds only the latest tick's,
	# and with these defs the whole fight resolves on the first one.
	var saw_fall := false
	for _i in range(5):
		sim.tick()
		for event in sim.last_combat_events:
			if bool(event.get("fell", false)):
				saw_fall = true
	assert_true(saw_fall,
		"an engagement's casualty events carry fell=true, or no corpse "
		+ "can ever be laid")


func test_a_consumed_squad_does_not_fall() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_fighter_def(), 1, Vector2i(5, 5))
	var events := sim.consume_squad(squad)
	assert_eq(events.size(), 1, "consumption reports through the casualty path")
	assert_false(bool(events[0].get("fell", false)),
		"a founding party is spent, not slain (D-031) — its event must "
		+ "never claim bodies")


# --- the client drain --------------------------------------------------

## The def must come from the ROSTER: the client resolves SQUAD_INFO
## through UnitRoster.by_id and refuses a def it does not know — the trap
## test_client_state.gd's own fixture comment names, met here first-hand
## (a synthetic def left composition empty and every drain test red).
func _client_with_squad() -> Dictionary:
	var sim := _sim()
	var def := UnitRoster.first()
	var squad := sim.add_squad(def, 1, Vector2i(5, 5))
	sim.tick()
	var state := ClientState.new()
	var visible := sim.visible_to(1)
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, visible))
	state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))
	return {"state": state, "squad": squad, "size": sim.alive_of(squad)}


func test_the_drain_records_only_when_a_renderer_is_reading() -> void:
	var setup := _client_with_squad()
	var state: ClientState = setup["state"]
	var squad: int = setup["squad"]
	var size: int = setup["size"]

	# Bots never set the flag; their drain must stay empty or a load test
	# leaks a list for the length of a run.
	state.handle_packet(NetProtocol.encode_squad_combat(1,
		[{"id": squad, "alive": size - 2, "routed": false, "fell": true}]))
	assert_eq(state.take_casualty_sites().size(), 0,
		"nothing is recorded while record_corpses is off")

	state.record_corpses = true
	state.handle_packet(NetProtocol.encode_squad_combat(2,
		[{"id": squad, "alive": size - 5, "routed": false, "fell": true}]))
	var sites := state.take_casualty_sites()
	assert_eq(sites.size(), 1, "one event, one site")
	assert_eq(int(sites[0]["before"]), size - 2, "the strength the men fell FROM")
	assert_eq(int(sites[0]["after"]), size - 5, "the strength the restamp keeps")
	assert_eq(state.take_casualty_sites().size(), 0, "drained means drained")


func test_men_who_did_not_fall_leave_no_site() -> void:
	var setup := _client_with_squad()
	var state: ClientState = setup["state"]
	state.record_corpses = true
	state.handle_packet(NetProtocol.encode_squad_combat(1,
		[{"id": int(setup["squad"]), "alive": 0, "routed": false}]))
	assert_eq(state.take_casualty_sites().size(), 0,
		"a consumed or wiped squad leaves no bodies — that is the whole "
		+ "reason the wire says fell at all")


# --- the ledger --------------------------------------------------------

func _record_op(ops: Array) -> Dictionary:
	# The op that SETS the newly added record is always last.
	return ops[ops.size() - 1]


func test_the_ledger_appends_densely_per_bucket() -> void:
	var ledger := CorpseLedger.new(8)
	var a1 := _record_op(ledger.add(&"m_a", 1, Transform3D(), 0.0, Vector2.ZERO))
	var b1 := _record_op(ledger.add(&"m_b", 1, Transform3D(), 0.1, Vector2.ZERO))
	var a2 := _record_op(ledger.add(&"m_a", 1, Transform3D(), 0.2, Vector2.ZERO))
	assert_eq(int(a1["index"]), 0)
	assert_eq(int(b1["index"]), 0, "buckets are independent")
	assert_eq(int(a2["index"]), 1, "a bucket appends densely")
	assert_eq(ledger.count(), 3)


func test_the_cap_evicts_the_oldest_across_buckets() -> void:
	var ledger := CorpseLedger.new(2)
	ledger.add(&"m_a", 1, Transform3D(), 0.0, Vector2.ZERO)
	ledger.add(&"m_a", 1, Transform3D(), 1.0, Vector2.ZERO)
	# Full. The third corpse is in ANOTHER bucket; the oldest (m_a index 0)
	# must go, its bucket staying dense via swap-remove.
	var ops := ledger.add(&"m_b", 2, Transform3D(), 2.0, Vector2.ZERO)
	assert_eq(ledger.count(), 2, "the cap holds")

	var key_a := CorpseLedger.bucket_key(&"m_a", 1)
	var records_a := ledger.bucket_records(key_a)
	assert_eq(records_a.size(), 1, "one of the two m_a corpses was evicted")
	assert_eq(int(records_a[0]["index"]), 0,
		"the survivor moved into the vacated slot — the bucket stays dense")
	assert_almost_eq(float(records_a[0]["time"]), 1.0, 0.001,
		"and the survivor is the YOUNGER one; eviction is oldest-first")

	# The ops must describe that move and the shrink, in replayable order.
	var kinds := ops.map(func(op): return String(op["op"]))
	assert_true(kinds.has("shrink"), "the renderer is told the bucket shrank")
	assert_eq(kinds.back(), "set", "and where the newcomer goes")


func test_evicting_a_buckets_last_entry_emits_no_move() -> void:
	var ledger := CorpseLedger.new(1)
	ledger.add(&"m_a", 1, Transform3D(), 0.0, Vector2.ZERO)
	var ops := ledger.add(&"m_b", 1, Transform3D(), 1.0, Vector2.ZERO)
	# Evicting m_a's only record needs no move op — just the shrink, then
	# the newcomer's set.
	assert_eq(ops.size(), 2)
	assert_eq(String(ops[0]["op"]), "shrink")
	assert_eq(int(ops[0]["count"]), 0)


func test_the_fall_phase_is_derived_and_clamped() -> void:
	var record := {"time": 10.0}
	assert_almost_eq(CorpseLedger.fall_phase(record, 10.0), 0.0, 0.001)
	assert_almost_eq(
		CorpseLedger.fall_phase(record, 10.0 + CorpseLedger.FALL_SECONDS / 2.0),
		0.5, 0.001)
	assert_almost_eq(CorpseLedger.fall_phase(record, 99.0), 1.0, 0.001,
		"a settled corpse holds its final frame forever")
	assert_almost_eq(CorpseLedger.fall_phase(record, 5.0), 0.0, 0.001,
		"and a clock earlier than the event pins to the start, not garbage")


func test_a_settled_corpse_leaves_the_falling_set() -> void:
	var ledger := CorpseLedger.new(8)
	ledger.add(&"m_a", 1, Transform3D(), 0.0, Vector2.ZERO)
	assert_eq(ledger.falling(0.5).size(), 1, "mid-fall: animated")
	assert_eq(ledger.falling(99.0).size(), 1,
		"the final frame is emitted exactly once")
	assert_eq(ledger.falling(99.1).size(), 0,
		"then a settled battlefield costs zero writes per frame")


# --- the boundary (D-006 clause 2, both directions) --------------------

func test_simulation_never_reads_the_dead_and_the_client_buries_them() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	var readers: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str.begins_with("res://tests/") \
				or path_str == "res://corpse_ledger.gd" \
				or path_str == "res://corpse_layer.gd":
			continue
		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		if text.contains("CorpseLedger") or text.contains("CorpseLayer"):
			readers.append(path_str)

	assert_true(readers.has("res://client.gd"),
		"client.gd must actually lay the bodies down — every other test "
		+ "here passes while nothing on screen falls (the D-055 rule)")
	for reader in readers:
		assert_true(String(reader) == "res://client.gd"
			or String(reader) == "res://duel_preview.gd",
			("only the render path and its preview may touch the corpse "
			+ "classes — %s reading them is a cosmetic record one call from "
			+ "an outcome, D-20260819's own revisit trigger") % reader)


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))
