extends GutTest

## Guards fog of war: D-025 (the vision field, reveal, conceal), D-004
## (curve gating and nothing else), D-003 (no intent leakage — reveal
## must not leak the past or the future either), and D-006's protocol
## obligation (a client cannot derive soldiers for a squad it was never
## described, so reveal must carry composition). Specifically written
## against D-026's exit criteria 5, 6, 7, 8 and 9:
##
##  5. SquadSim.visible_to() is a real per-player set from D-025's vision
##     field — no second data-hiding mechanism.
##  6. Fog is proven to hide FROM THE WIRE: a client receives zero curve
##     bytes for an out-of-vision enemy squad, measured in bytes.
##  7. Reveal is a true-position pop-in; conceal is a stale flagged ghost,
##     announced explicitly; no synthetic catch-up curve anywhere.
##  8. The desync check stays meaningful under fog: client and server hash
##     the same set, ghosts excluded by construction.
##  9. Every check here was observed to fail before being trusted (see the
##     final report, not this file — perturbed and reverted by hand, the
##     same posture test_combat.gd's header documents for its own suite).
##
## ## Why squads here reuse a REAL roster id
##
## ClientState._handle_squad_info resolves formation shape/spacing through
## UnitRoster.by_id(def_id) — a synthetic def_id the roster has never
## heard of makes that lookup fail and silently drops the composition
## (see NetProtocol.encode_squad_info's header on why guessing was
## rejected). So `_def()` below reuses "militia"'s real id, but pins
## shape/spacing to match militia.tres's actual values so client and
## server still agree on those two fields — everything else (vision_range
## above all, plus combat/speed stats) is fully under this file's control
## regardless of what militia.tres says, because SquadSim.def_of() always
## returns the exact UnitDef object passed to add_squad(), never a fresh
## roster lookup.


const W := 48
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


## vision_range and move_speed are world units, matching UnitDef's own
## fields. attack_range/damage default to zero so squads built by this
## helper never accidentally engage each other — these tests are about
## vision, not combat, and a stray engagement would be a confound, not a
## feature. Tests that DO want combat (the hash-under-casualties test)
## override attack_range/damage explicitly after construction.
func _def(vision_range: float, move_speed: float = 3.5, attack_range: float = 0.0, damage: float = 0.0) -> UnitDef:
	var d := UnitDef.new()
	# A real roster id, taken from the roster rather than named: a
	# synthetic def_id would fail ClientState._handle_squad_info's
	# UnitRoster lookup and silently drop the composition. Reading it from
	# the roster keeps that true however the shipped units change.
	var real := UnitRoster.first()
	d.id = real.id
	d.formation_shape = real.formation_shape
	d.formation_spacing = real.formation_spacing
	d.squad_size = 10
	d.health = 20.0
	d.move_speed = move_speed
	d.vision_range = vision_range
	d.attack_range = attack_range
	d.damage = damage
	d.attack_interval = 0.1
	d.morale = 100.0
	d.rout_threshold = 25.0
	d.rout_rally_margin = 15.0
	d.morale_recovery_per_second = 2.0
	d.morale_loss_per_casualty = 4.0
	d.damage_variance = 0.0
	return d


## World-units -> cells, mirroring Vision._range_in_cells's own
## conversion — duplicated locally rather than reaching into that
## underscore-prefixed static, the same posture test_combat.gd takes
## toward Combat's private range helper.
func _world_range_to_cells(sim: SquadSim, world_range: float) -> float:
	var hex_width := sim.space.hex_size * TorusSpace.SQRT_3
	return world_range / hex_width if hex_width > 0.0 else 0.0


## Mirrors server.gd's _replicate() for ONE client: reveal composition ->
## conceal events -> curves -> combat events -> state hash, in that order
## (D-025, D-026 criterion 7/8). Returns the new "visible" baseline
## dictionary to pass back in on the next call — this IS server.gd's
## per-client bookkeeping, hand-driven here the same way
## test_client_state.gd's _connect/_pump hand-drive the rest of the
## protocol without spinning up a real ENet host (server.gd itself needs a
## live Node/ENetConnection to run, which is not practical to exercise
## headless from a GUT test — see D-014's client-side equivalent note).
func _replicate_one(sim: SquadSim, state: ClientState, player: int, previous_visible: Dictionary) -> Dictionary:
	var visible := sim.visible_to(player)
	var visible_set := {}
	for id in visible:
		visible_set[id] = true

	var revealed := []
	for id in visible_set:
		if not previous_visible.has(id):
			revealed.append(id)
	if not revealed.is_empty():
		var entries := sim.squad_info_entries(revealed)
		if not entries.is_empty():
			state.handle_packet(NetProtocol.encode_squad_info(entries))

	var concealed := []
	for id in previous_visible:
		if not visible_set.has(id):
			concealed.append(id)
	if not concealed.is_empty():
		state.handle_packet(NetProtocol.encode_squad_conceal(sim.tick_count, concealed))

	for packet in sim.replicator.collect_for_client(player, sim.time, visible):
		state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))

	var combat_events := sim.last_combat_events
	if not combat_events.is_empty():
		var visible_events := []
		for event in combat_events:
			if visible_set.has(int(event["id"])):
				visible_events.append(event)
		if not visible_events.is_empty():
			state.handle_packet(NetProtocol.encode_squad_combat(sim.tick_count, visible_events))

	state.handle_packet(NetProtocol.encode_state_hash(sim.tick_count, sim.composition_hash(visible)))

	return visible_set


func _connect_one(sim: SquadSim, player: int, own_squads: Array) -> ClientState:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(player, W, H, own_squads))
	return state


# --- fog hides, measured in bytes (D-026 criterion 6) -------------------

func test_fog_hides_out_of_vision_enemy_squad_measured_in_bytes() -> void:
	var sim := _sim()
	var a := sim.add_squad(_def(6.0), 1, Vector2i(2, 2))
	var b := sim.add_squad(_def(6.0), 2, Vector2i(20, 8))
	sim.recompute_vision_now()

	var visible := sim.visible_to(1)
	assert_true(visible.has(a), "A player's own squad is always visible to itself")
	assert_false(visible.has(b), "An enemy squad far outside vision must not be in visible_to()")

	sim.order_move(a, Vector2i(10, 2))
	sim.order_move(b, Vector2i(21, 8))

	var b_bytes := 0
	for _i in range(30):
		sim.tick()
		visible = sim.visible_to(1)
		assert_false(visible.has(b), "B should remain hidden for this whole run")
		for packet in sim.replicator.collect_for_client(1, sim.time, visible):
			if int(packet["id"]) == b:
				b_bytes += (packet["bytes"] as PackedByteArray).size()

	assert_eq(b_bytes, 0,
		"A client outside a squad's vision must receive literally zero bytes for it — byte-level, not 'chose not to draw it'")

	# Positive control: A itself, re-ordered (a fresh curve version, so a
	# send is guaranteed regardless of window timing) and visible, DOES
	# produce bytes — otherwise the zero above would be measuring a
	# replicator that sends nothing to anyone, which would prove nothing
	# about fog specifically.
	sim.order_move(a, Vector2i(30, 12))
	sim.tick()
	var a_bytes := CurveReplicator.total_bytes(
		sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1)))
	assert_gt(a_bytes, 0, "This test proves nothing if even a moving, visible squad sends zero bytes")


# --- reveal does not leak (D-003, D-025 part 2) --------------------------

func test_reveal_leaks_neither_past_nor_future() -> void:
	var sim := _sim()
	var horizon := sim.replicator.horizon_seconds
	var a := sim.add_squad(_def(6.0), 1, Vector2i(0, 0))
	var b := sim.add_squad(_def(6.0), 2, Vector2i(30, 8))
	sim.order_move(b, Vector2i(2, 8))
	sim.recompute_vision_now()

	assert_false(sim.visible_to(1).has(b), "Setup: B should start out of player 1's vision")

	# Let B accrue real history while hidden.
	for _i in range(20):
		sim.tick()
		sim.replicator.collect_for_client(1, sim.time, sim.visible_to(1))
	assert_false(sim.visible_to(1).has(b), "Setup: B should still be hidden after 2s of marching")

	# Send A toward B's actual (fixed) destination, not a snapshot of B's
	# CURRENT position — B keeps moving after this point, and chasing a
	# stale snapshot risks the two converging on where B USED to be after
	# B has already moved on, never actually coming within range of each
	# other before the tick budget runs out. Both converging on the same
	# known final cell guarantees they eventually end up close.
	sim.order_move(a, Vector2i(2, 8))

	var revealed_packet = null
	var reveal_now := 0.0
	for _i in range(300):
		sim.tick()
		var visible := sim.visible_to(1)
		var packets := sim.replicator.collect_for_client(1, sim.time, visible)
		if visible.has(b):
			reveal_now = sim.time
			for packet in packets:
				if int(packet["id"]) == b:
					revealed_packet = packet
			break

	assert_not_null(revealed_packet, "B should eventually enter player 1's vision")
	var decoded := CurveReplicator.decode_packet(revealed_packet["bytes"])
	var curve: StateCurve = decoded["curve"]

	assert_gte(curve.start_time(), reveal_now - 0.0001,
		"A revealed squad's curve must not describe any time before the reveal — no history leak")
	assert_lte(curve.end_time(), reveal_now + horizon + 0.0001,
		"A revealed squad's curve must not extend past the horizon — no intent leak, same as any other squad")


# --- ghost behaviour (D-025 part 3) --------------------------------------

func test_ghost_freezes_on_conceal_and_is_replaced_wholesale_on_reveal() -> void:
	var sim := _sim()
	var a := sim.add_squad(_def(6.0), 1, Vector2i(5, 5))
	var b := sim.add_squad(_def(6.0), 2, Vector2i(6, 5))  # adjacent: starts visible
	sim.recompute_vision_now()
	assert_true(sim.visible_to(1).has(b), "Setup: B should start visible to player 1 (adjacent)")

	var state := _connect_one(sim, 1, [a])
	var visible := _replicate_one(sim, state, 1, {})

	assert_false(state.is_ghost(b), "B should be live at first, not a ghost")
	assert_true(state.composition.has(b))
	var alive_before := state.alive_of(b)

	# Send B far away so it leaves vision. Vector2i(25, 5) rather than
	# somewhere past the map's midpoint: the flow field takes the shortest
	# wrapped path, and a destination near the seam's midpoint on the OTHER
	# side of A would route B past/through A's own cell first — still
	# correct, just a confusing transient to reason about. 25 is closer
	# going forward than wrapping backward through A, so B's distance from
	# A increases monotonically.
	sim.order_move(b, Vector2i(25, 5))
	var concealed := false
	for _i in range(200):
		sim.tick()
		visible = _replicate_one(sim, state, 1, visible)
		if state.is_ghost(b):
			concealed = true
			break

	assert_true(concealed, "B should eventually leave vision and become a ghost")
	assert_false(state.composition.has(b), "A ghost must not remain in live composition")
	assert_eq(int(state.ghost_info(b)["alive"]), alive_before,
		"A ghost's last-known strength should be exactly what it was at conceal time")
	assert_true(state.ghost_squad_ids().has(b))

	# The client's LAST live curve, received the tick before conceal, is
	# clipped up to [that tick, that tick + horizon] — so it legitimately
	# keeps interpolating its already-known tail for up to horizon_seconds
	# after conceal before it truly holds still. That is correct (D-025
	# part 2 in reverse: the client only ever knew a bounded future, and
	# plays out exactly that much, no more). So let the tail run out
	# first, THEN snapshot "frozen" — the freeze claim is about what
	# happens once the client has exhausted what it was told, not about
	# the instant conceal fires.
	var horizon_ticks := ceili(sim.replicator.horizon_seconds * SquadSim.TICK_HZ) + 2
	for _i in range(horizon_ticks):
		sim.tick()
		visible = _replicate_one(sim, state, 1, visible)
	assert_true(state.is_ghost(b), "B should still be a ghost while its curve tail plays out")

	var frozen_cell := state.squad_cell(b, sim.time)
	var ghost_snapshot := state.ghost_info(b).duplicate()
	for _i in range(30):
		sim.tick()
		visible = _replicate_one(sim, state, 1, visible)
	assert_eq(state.squad_cell(b, sim.time), frozen_cell,
		"A concealed squad's curve must not update while hidden, once its last-known tail has played out")
	assert_eq(state.ghost_info(b)["alive"], ghost_snapshot["alive"],
		"A ghost must not receive further updates while hidden")
	assert_true(state.is_ghost(b), "B should still be a ghost — it moved further away, not back into range")

	# Bring B back into range.
	sim.order_move(b, sim.cell_of(a))
	var revealed := false
	for _i in range(400):
		sim.tick()
		visible = _replicate_one(sim, state, 1, visible)
		if state.composition.has(b):
			revealed = true
			break

	assert_true(revealed, "B should be revealed again once back in range")
	assert_false(state.is_ghost(b), "Re-reveal must replace the ghost wholesale, not merge into it")
	assert_eq(state.ghost_info(b), {}, "A revealed squad must have no leftover ghost entry")


# --- hash agreement across a conceal/reveal cycle (D-026 criterion 8) ---

func test_hash_agreement_survives_conceal_casualties_and_reveal() -> void:
	# Player 1 (the client under test) has one squad, A, stationary. Player
	# 2 owns B, which starts ADJACENT to A (live, revealed) and is then
	# marched far away to fight D (player 3) entirely out of player 1's
	# vision — so B genuinely goes live -> concealed (a real client-side
	# ghost) -> takes casualties while hidden -> is revealed again. This is
	# the exact sequence D-025's ghost-in-the-hash failure mode needs: a
	# test that never creates a ghost in the first place (e.g. one where
	# the squad is simply never revealed until the end) cannot exercise the
	# bug at all.
	var sim := _sim()
	var a := sim.add_squad(_def(6.0), 1, Vector2i(0, 0))

	var defender_def := _def(6.0, 3.5, 3.0, 0.0)  # deals nothing back
	defender_def.health = 5.0
	defender_def.squad_size = 30
	var b := sim.add_squad(defender_def, 2, Vector2i(1, 0))  # adjacent to A: starts visible

	# Tuned so B takes REPEATED PARTIAL casualties (roughly 2 every ~10
	# ticks) once it reaches D, rather than being wiped out in one round —
	# the point is proving reveal carries the CURRENT, partly reduced
	# strength, not merely "dead vs. alive".
	var attacker_def := _def(6.0, 3.5, 3.0, 1.0)
	attacker_def.attack_interval = 1.0  # once per second, not every tick
	var d := sim.add_squad(attacker_def, 3, Vector2i(30, 8))
	sim.recompute_vision_now()

	assert_true(sim.visible_to(1).has(b), "Setup: B should start visible to player 1 (adjacent to A)")

	var state := _connect_one(sim, 1, [a])
	var visible := _replicate_one(sim, state, 1, {})
	assert_eq(state.composition_hash(), sim.composition_hash(sim.visible_to(1)),
		"Hashes must agree at the start")
	assert_eq(state.desync_count, 0)

	# March B toward D — far enough that it leaves player 1's vision along
	# the way, then fights D entirely off player 1's screen.
	sim.order_move(b, Vector2i(31, 8))

	var saw_ghost := false
	var alive_when_ghosted := -1
	for _i in range(300):
		sim.tick()
		visible = _replicate_one(sim, state, 1, visible)
		assert_eq(state.desync_count, 0,
			"Hashes must keep agreeing tick by tick as B leaves vision and fights, hidden")
		if state.is_ghost(b):
			if not saw_ghost:
				saw_ghost = true
				alive_when_ghosted = sim.alive_of(b)
			# Stop once B has taken at least one casualty WHILE hidden —
			# not merely been concealed.
			if sim.alive_of(b) < alive_when_ghosted:
				break

	assert_true(saw_ghost, "B must actually have been concealed (a real ghost) at some point")
	assert_lt(sim.alive_of(b), alive_when_ghosted,
		"Setup is only meaningful if B actually took casualties while hidden, not merely while unseen")
	assert_false(state.composition.has(b), "B must still be a ghost to player 1 while this is happening")

	# Bring B back toward A so it is revealed again, weakened.
	var alive_at_return := sim.alive_of(b)
	sim.order_move(b, sim.cell_of(a))
	var revealed := false
	for _i in range(400):
		sim.tick()
		visible = _replicate_one(sim, state, 1, visible)
		assert_eq(state.desync_count, 0,
			"Hashes must keep agreeing tick by tick on B's way back, while still a ghost")
		if state.composition.has(b):
			revealed = true
			break

	assert_true(revealed, "B should eventually be revealed again to player 1")
	assert_false(state.is_ghost(b), "A revealed squad must no longer be a ghost")
	assert_lte(state.alive_of(b), alive_at_return,
		"Reveal must carry B's CURRENT (post-casualty) strength, not its pre-conceal strength")
	assert_eq(state.composition_hash(), sim.composition_hash(sim.visible_to(1)),
		"Hashes must agree immediately after reveal")
	assert_eq(state.desync_count, 0)

	# Keep running a while longer to be sure agreement holds, not just at
	# the instant of reveal.
	for _i in range(20):
		sim.tick()
		visible = _replicate_one(sim, state, 1, visible)
		assert_eq(state.composition_hash(), sim.composition_hash(sim.visible_to(1)),
			"Hashes must keep agreeing as the run continues after reveal")
	assert_eq(state.desync_count, 0,
		"A correctly-informed client must never desync across a full reveal/conceal/casualty/reveal cycle")


# --- wrap-awareness (D-008) ----------------------------------------------

func test_vision_is_wrap_aware_across_the_seam() -> void:
	var sim := _sim()
	var a := sim.add_squad(_def(4.0), 1, Vector2i(W - 1, 8))

	# Just across the seam: short way around is 2 cells, the naive
	# unwrapped distance would be W - 2 (46) cells.
	var near := sim.add_squad(_def(4.0), 2, Vector2i(1, 8))
	sim.recompute_vision_now()

	assert_eq(sim.space.distance(Vector2i(W - 1, 8), Vector2i(1, 8)), 2,
		"Setup: the seam-crossing distance should be short, not almost the width of the map")
	assert_true(sim.visible_to(1).has(near),
		"An enemy just across the seam within vision range must be visible — D-008 wrap-awareness")

	# The same enemy moved to a cell that is genuinely far even the SHORT
	# way around must drop out of vision.
	sim.order_move(near, Vector2i(W / 2, 8))
	var far_ticks := 0
	while sim.visible_to(1).has(near) and far_ticks < 400:
		sim.tick()
		far_ticks += 1
		if far_ticks % 3 == 0:
			sim.recompute_vision_now()

	sim.recompute_vision_now()
	assert_false(sim.visible_to(1).has(near),
		"The same enemy moved genuinely out of range (mid-map, no seam shortcut) must no longer be visible")


# --- the field agrees with brute force -----------------------------------

func test_vision_field_agrees_with_a_brute_force_reference_over_every_cell() -> void:
	# Deliberately small so an exhaustive per-cell brute-force check is
	# cheap: this test is about correctness of the O(1) field against the
	# definition it is optimising, not about scale.
	var space := TorusSpace.new(16, 8, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = 13

	var by_owner := {1: [], 2: []}
	for owner in [1, 2]:
		for i in range(3):
			var vision_range := rng.randf_range(2.0, 10.0)
			var cell := Vector2i(rng.randi_range(0, space.width - 1), rng.randi_range(0, space.height - 1))
			var def := _def(vision_range)
			by_owner[owner].append(sim.add_squad(def, owner, cell))

	sim.recompute_vision_now()

	var mismatches := 0
	for owner in [1, 2]:
		for cy in range(space.height):
			for cx in range(space.width):
				var cell := Vector2i(cx, cy)
				var idx := space.index(cell)
				var expected := false
				for squad in by_owner[owner]:
					var def: UnitDef = sim.def_of(squad)
					var range_cells := _world_range_to_cells(sim, def.vision_range)
					if space.distance(sim.cell_of(squad), cell) <= range_cells:
						expected = true
						break
				var actual := sim.vision.is_visible(owner, idx)
				if actual != expected:
					mismatches += 1

	assert_eq(mismatches, 0,
		"The O(1) vision field must agree with a brute-force per-pair reference at every cell")
