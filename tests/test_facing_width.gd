extends GutTest

## Guards D-20260819-facing-and-width-are-orders: the two new replicated
## squad values ride the wire and the hash exactly as shape does (the
## D-058/D-065 lesson — open the encoder and look), the facing resolver
## obeys "path while moving, order while standing", and width actually
## buys frontage (the tactical claim, measured through Tier 2's own
## contact count).

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"facing_test"
	d.squad_size = 24
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.attack_range = 1.5
	return d


# --- the wire ----------------------------------------------------------

func test_the_orders_round_trip() -> void:
	var facing := NetProtocol.decode_order_facing(
		NetProtocol.encode_order_facing(7, 1024))
	assert_eq(int(facing["squad"]), 7)
	assert_eq(int(facing["facing"]), 1024)

	var width := NetProtocol.decode_order_width(
		NetProtocol.encode_order_width(9, 6))
	assert_eq(int(width["squad"]), 9)
	assert_eq(int(width["files"]), 6)


func test_squad_info_carries_facing_and_files() -> void:
	var entries := NetProtocol.decode_squad_info(NetProtocol.encode_squad_info([
		{"id": 1, "def_id": "x", "alive": 10, "shape": "line",
			"facing": 2048, "files": 6},
		{"id": 2, "def_id": "x", "alive": 10, "shape": "line"},
	]))
	assert_eq(int(entries[0]["facing"]), 2048)
	assert_eq(int(entries[0]["files"]), 6)
	assert_eq(int(entries[1]["facing"]), -1,
		"never-ordered survives the wire as the sentinel, not as north")
	assert_eq(int(entries[1]["files"]), 0)


func test_the_hash_reads_both_and_the_two_machines_agree() -> void:
	var sim := _sim()
	# A ROSTER def: the client resolves SQUAD_INFO through UnitRoster and
	# refuses one it does not know — the same fixture trap test_corpses
	# already paid for.
	var squad := sim.add_squad(UnitRoster.first(), 1, Vector2i(5, 5))
	sim.tick()

	var state := ClientState.new()
	var visible := sim.visible_to(1)
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, visible))
	state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))
	assert_eq(state.composition_hash(), sim.composition_hash(visible),
		"agreement before any order")

	var before := sim.composition_hash(visible)
	sim.set_facing(squad, 1024)
	sim.set_files(squad, 6)
	assert_ne(sim.composition_hash(visible), before,
		"the hash must SEE facing and width, or a drift would be silent")

	# The client that missed the rebroadcast disagrees — that is the
	# desync check working — and the one that received it agrees again.
	assert_ne(state.composition_hash(), sim.composition_hash(visible))
	state.handle_packet(NetProtocol.encode_squad_info(sim.squad_info_entries(visible)))
	assert_eq(state.composition_hash(), sim.composition_hash(visible),
		"one SQUAD_INFO later the two machines agree bit for bit — "
		+ "including the angle, reconstructed from the same integer")


# --- the facing resolver ----------------------------------------------

func test_a_standing_squad_faces_its_order_and_a_marching_one_its_path() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_def(), 1, Vector2i(5, 5))
	sim.tick()

	# Half a turn: the march below heads +x, so the ordered facing must
	# NOT — the first version ordered a quarter turn, which IS +x, and
	# the marching assertion compared a squad to itself.
	var ordered := TAU * 2048.0 / 4096.0
	sim.set_facing(squad, 2048)
	var standing := sim.soldier_transforms(squad)
	var forward: Vector3 = standing[0].basis * Vector3(0, 0, 1)
	var wanted := Vector3(sin(ordered), 0.0, cos(ordered))
	assert_almost_eq(forward.dot(wanted), 1.0, 0.01,
		"a standing squad faces exactly where it was told to")

	# March it somewhere. Mid-march the path owns the facing — wheeling,
	# pace and the whole turning model depend on that.
	sim.order_move(squad, Vector2i(15, 5))
	for _i in range(6):
		sim.tick()
	var marching := sim.soldier_transforms(squad)
	var march_forward: Vector3 = marching[0].basis * Vector3(0, 0, 1)
	assert_lt(march_forward.dot(wanted), 0.99,
		"a marching squad faces its path, not its old order")


# --- width buys frontage ----------------------------------------------

func test_width_changes_the_formation_and_the_footprint() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_def(), 1, Vector2i(5, 5))
	sim.tick()
	var narrow_radius: float = Formation.footprint("line", 24, 1.0, 4)["radius"]
	var wide_radius: float = Formation.footprint("line", 24, 1.0, 24)["radius"]
	assert_gt(wide_radius, narrow_radius,
		"a single-rank line is wider than a four-file column — and the "
		+ "cache key must carry files, or the second answer is the first")

	sim.set_files(squad, 24)
	var wide := sim.soldier_transforms(squad)
	sim.set_files(squad, 4)
	var deep := sim.soldier_transforms(squad)
	var wide_span := _x_span(wide)
	var deep_span := _x_span(deep)
	assert_gt(wide_span, deep_span,
		"the ordered width reaches the derived soldiers")


func test_width_buys_contact() -> void:
	# The tactical claim, measured through Tier 2's own arithmetic: the
	# same 24 men, ordered wide, land more of themselves in reach of the
	# same enemy line than ordered deep.
	var sim := _sim()
	var attacker := sim.add_squad(_def(), 1, Vector2i(5, 5))
	var defender := sim.add_squad(_def(), 2, Vector2i(5, 7))
	sim.set_files(defender, 24)
	sim.tick()

	sim.set_files(attacker, 24)
	var wide_contact := Engagement.contact_count(
		sim.soldier_transforms(attacker), sim.soldier_transforms(defender),
		Engagement.contact_reach(1.5))
	sim.set_files(attacker, 3)
	var deep_contact := Engagement.contact_count(
		sim.soldier_transforms(attacker), sim.soldier_transforms(defender),
		Engagement.contact_reach(1.5))
	assert_gt(wide_contact, deep_contact,
		"widening is an attack: more men in reach (%d wide vs %d deep)"
			% [wide_contact, deep_contact])


func test_orders_are_clamped_and_zero_restores_the_default() -> void:
	var sim := _sim()
	var squad := sim.add_squad(_def(), 1, Vector2i(5, 5))
	sim.set_facing(squad, 99999)
	assert_eq(sim.facing_of(squad), 4095, "facing clamps to the last step")
	sim.set_files(squad, 999)
	assert_eq(sim.files_of(squad), 255, "files clamp to a byte")
	sim.set_files(squad, 0)
	assert_eq(sim.files_of(squad), 0, "zero is 'the formation's default'")
	# And a files order beyond the squad's strength forms what the squad
	# can actually form — clamped in the GEOMETRY, so a squad that takes
	# casualties later never forms a line with holes.
	var offsets_full := Formation.slot_offset("line", 0, 12, 1.0, 200)
	var offsets_ranked := Formation.slot_offset("line", 0, 12, 1.0, 12)
	assert_eq(offsets_full, offsets_ranked,
		"200 files on 12 men is 12 files")


func _x_span(transforms: Array[Transform3D]) -> float:
	var lo := INF
	var hi := -INF
	for t in transforms:
		lo = minf(lo, t.origin.x)
		hi = maxf(hi, t.origin.x)
	return hi - lo
