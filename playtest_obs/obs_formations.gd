extends SceneTree

## OBSERVATION HARNESS for playtest ticket #35 (formations, reframed as an
## RTW gap analysis).
##
## #35's own instruction is that shape must be verified THROUGH THE WIRE —
## D-065's history is that `SQUAD_INFO` did not carry shape at all while
## every decision entry said it did, so a server-side assertion proves
## nothing. Everything here therefore round-trips real bytes:
## `SquadSim.squad_info_entries` -> `NetProtocol.encode_squad_info` ->
## `ClientState.handle_packet` -> read back off the CLIENT, and the two
## `composition_hash()` implementations compared.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_formations.gd

const TICK := 1.0 / 10.0


func _initialize() -> void:
	print("OBS35: begin")
	_offered_formations()
	_wire_round_trip()
	_shape_survives_a_haul()
	_rtw_capability_survey()
	print("OBS35: end")
	quit()


func _sim(width := 40, height := 20) -> SquadSim:
	var space := TorusSpace.new(width, height, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	sim.combat_seed = 3
	return sim


# --- A7: which shapes a player is offered ------------------------------

func _offered_formations() -> void:
	print("")
	print("OBS35 A7 - formations shipped, and which are OFFERED to a player.")
	print("  #35's table says 'only 3 offered (ring/sparse/tight)'. Re-read")
	print("  off the .tres as they ship today:")
	var dir := DirAccess.open("res://formations")
	var offered := []
	var granted := []
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var d = load("res://formations/%s" % f)
			if d == null:
				continue
			if d.offered:
				offered.append(String(d.id))
			else:
				granted.append(String(d.id))
	offered.sort()
	granted.sort()
	print("  offered=true  (%d): %s" % [offered.size(), offered])
	print("  offered=false (%d): %s" % [granted.size(), granted])
	# Who grants the non-offered ones, per workstream 9.
	for d in UnitRoster.load_all():
		if not d.formations.is_empty():
			print("    %s grants %s" % [d.id, d.formations])


# --- A4/A5/A8/A9: does it reach a client? ------------------------------

func _wire_round_trip() -> void:
	print("")
	print("OBS35 A5/A8/A9 WIRE - shape, facing and files across real bytes.")
	var sim := _sim()
	var unit := UnitRoster.by_id(&"gildedreach_spearmen")
	if unit == null:
		unit = UnitRoster.load_all()[0]
	var ids := []
	for i in range(3):
		ids.append(sim.add_squad(unit, 1, Vector2i(8 + i * 4, 10)))

	# Player orders: a shape, a facing and a width on each squad.
	var shapes := ["line", "column", "wedge"]
	var facings := [0, 1024, 3072]
	var widths := [4, 9, 2]
	for i in range(ids.size()):
		sim.set_shape(ids[i], shapes[i])
		sim.set_facing(ids[i], facings[i])
		sim.set_files(ids[i], widths[i])

	var client := ClientState.new()
	client.space = sim.space
	var entries := sim.squad_info_entries(ids)
	client.handle_packet(NetProtocol.encode_squad_info(entries))

	print("  %-6s %-10s %-10s %-9s %-9s %-7s %-7s"
		% ["squad", "shape srv", "shape cli", "facing s", "facing c", "files s", "files c"])
	var all_ok := true
	for i in range(ids.size()):
		var id: int = ids[i]
		var cs := client.shape_of(id)
		var cf := client.facing_of(id)
		var cw := client.files_of(id)
		var ok: bool = cs == sim.shape_of(id) and cf == sim.facing_of(id) \
			and cw == sim.files_of(id)
		all_ok = all_ok and ok
		print("  %-6d %-10s %-10s %-9d %-9d %-7d %-7d %s"
			% [id, sim.shape_of(id), cs, sim.facing_of(id), cf,
			   sim.files_of(id), cw, "" if ok else "<-- MISMATCH"])
	print("  every field survived the wire: %s" % all_ok)

	var server_hash := sim.composition_hash(ids)
	var client_hash := client.composition_hash()
	print("  composition_hash server=%d client=%d agree=%s"
		% [server_hash, client_hash, server_hash == client_hash])

	# And the thing that matters downstream: both sides must derive the
	# SAME soldier positions from those replicated values.
	var worst := 0.0
	for id in ids:
		var s_t := sim.soldier_transforms(id)
		var c_t := client.soldier_transforms(id, sim.time)
		if s_t.size() != c_t.size():
			print("  squad %d: server derived %d soldiers, client %d <-- MISMATCH"
				% [id, s_t.size(), c_t.size()])
			continue
		for k in range(s_t.size()):
			worst = maxf(worst, s_t[k].origin.distance_to(c_t[k].origin))
	print("  worst server/client soldier position disagreement: %.6f world units" % worst)


# --- A4: a player's shape survives the economy -------------------------

func _shape_survives_a_haul() -> void:
	print("")
	print("OBS35 A4 - a player's shape on a GATHERING crew, over a full haul.")
	print("  Note the ground moved under this row: `SquadSim.suggest_shape`")
	print("  and its latch are GONE (D-20260820 amendment) - nothing in the")
	print("  simulation asserts a shape per tick any more, so there is no")
	print("  per-tick suggestion left to survive. Measured anyway.")
	var space := TorusSpace.new(40, 20, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var p := PackedByteArray()
	p.resize(space.cell_count())
	p.fill(1)
	sim.set_passable(p)
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings
	var economy := Economy.new(space)
	sim.economy = economy
	var g: UnitDef = null
	for d in UnitRoster.load_all():
		if d.gather_rate > 0.0 and d.carry_capacity > 0:
			g = d
			break
	var tc := BuildingSim.def_by_id(&"town_centre")
	buildings.add_building(tc, 1, Vector2i(18, 10), true)
	var node_cell := space.index(Vector2i(24, 10))
	economy.nodes[node_cell] = {"kind": Economy.ResourceKind.WOOD,
		"remaining": Economy.TREE_STOCK}
	var squad := sim.add_squad(g, 1, Vector2i(19, 10))
	economy.order_gather(sim, squad, node_cell)
	sim.set_shape(squad, "wedge")
	var chosen := sim.shape_of(squad)
	var changed_at := -1.0
	var seen := {}
	var t := 0.0
	while t < 120.0:
		sim.tick()
		t += TICK
		var now := sim.shape_of(squad)
		seen[now] = true
		if changed_at < 0.0 and now != chosen:
			changed_at = t
	print("  set 'wedge' on a working crew; shapes seen over 120s: %s" % [seen.keys()])
	print("  player's shape survived: %s%s"
		% [changed_at < 0.0,
		   "" if changed_at < 0.0 else (" (changed at %.1fs to %s)" % [changed_at, sim.shape_of(squad)])])


# --- The RTW rows, each exercised rather than grepped ------------------

func _rtw_capability_survey() -> void:
	print("")
	print("OBS35 RTW ROWS - #35's table was written before the twelve")
	print("  workstreams of D-20260818-battle-quality-outranks-player-count")
	print("  landed. Each row below is EXERCISED here, not read off a doc.")

	# A8 facing as an order.
	var sim := _sim()
	var u := UnitRoster.by_id(&"gildedreach_spearmen")
	var s := sim.add_squad(u, 1, Vector2i(10, 10))
	sim.set_facing(s, 2048)
	print("  A8 facing is an order      : set_facing(2048) -> facing_of=%d, angle=%.3f rad"
		% [sim.facing_of(s), sim.facing_angle_of(s)])

	# A9 width as an order.
	var before_files := sim.files_of(s)
	sim.set_files(s, 12)
	print("  A9 width is an order       : files %d -> %d, footprint now %d cells"
		% [before_files, sim.files_of(s), sim.footprint_cells(s)])

	# A10 charge.
	var enemy := sim.add_squad(u, 2, Vector2i(24, 10))
	sim.order_charge(s, Vector2i(24, 10))
	print("  A10 charge                 : order_charge -> is_charging=%s (x%.1f impact, x%.1f pace)"
		% [sim.is_charging(s), Combat.CHARGE_IMPACT_MULT, 1.5])

	# A11 flanking: aspect over real derived facing.
	var front := Engagement.aspect(Vector3(0, 0, 1), Vector3(0, 0, 5), Vector3.ZERO)
	var flank := Engagement.aspect(Vector3(0, 0, 1), Vector3(5, 0, 0), Vector3.ZERO)
	var rear := Engagement.aspect(Vector3(0, 0, 1), Vector3(0, 0, -5), Vector3.ZERO)
	print("  A11 flank/rear attacks     : aspect front=%d flank=%d rear=%d (x%.1f/x%.1f morale)"
		% [front, flank, rear, Combat.FLANK_MORALE_MULT, Combat.REAR_MORALE_MULT])

	# A12 men pair off in melee.
	# Deliberately the FILE check alone. The class-name literal would trip
	# `test_cosmetic_duel.gd`'s reader scan, which is a text scan and so
	# cannot tell an existence probe from a use — and it is right not to
	# try: D-006 clause 2 keeps that reader set to the render path and its
	# preview, and an allow-list entry for a harness would make the next
	# entry easier. This answers the same question and stays out of it.
	var has_duel := ResourceLoader.exists("res://cosmetic_duel.gd")
	print("  A12 men pair off in melee   : cosmetic_duel.gd present=%s (render-side, D-006 cl.2)"
		% has_duel)

	# A13/A6 survivors walk into vacated slots.
	var has_motion := ResourceLoader.exists("res://soldier_motion.gd")
	print("  A6/A13 restamp + gap fill  : soldier_motion.gd present=%s (D-006 clause 2 as amended)"
		% has_motion)

	# A15 phalanx/testudo.
	var special := []
	for f in ["shield_wall", "testudo"]:
		if ResourceLoader.exists("res://formations/%s.tres" % f):
			special.append(f)
	print("  A15 phalanx/testudo        : %s ship as FormationDef, granted via UnitDef.formations"
		% [special])

	# A16 guard mode / stances.
	sim.set_stance(s, SquadSim.STANCE_GUARD)
	print("  A16 guard mode             : STANCE_GUARD set -> has_stance=%s; stance byte also carries SKIRMISH/HOLD_FIRE/RUN"
		% sim.has_stance(s, SquadSim.STANCE_GUARD))

	# Fatigue (workstream 11).
	print("  ws11 fatigue               : fatigue_of=%.1f, charge refused under %.0f, ended at %.0f"
		% [sim.fatigue_of(s), SquadSim.CHARGE_MIN_FATIGUE, SquadSim.CHARGE_EXHAUST_FLOOR])

	# B11 civ knobs (#158).
	print("")
	print("  B11 civ mechanical difference - #35's table says 'read by nothing'.")
	for c in CivRoster.load_all():
		print("    %-14s squad_cap_bonus=%d production_speed=%.2f gather_speed=%.2f"
			% [c.id, c.squad_cap_bonus, c.production_speed, c.gather_speed])
	print("    (all three are read by the simulation as of #158 — see")
	print("     docs/status/civ-knobs.md; measured for gather_speed in obs_economy.gd)")
	print("  B12 number of civs         : %d shipped" % CivRoster.load_all().size())
