extends GutTest

## A squad WHEELS; it does not snap (D-20260818).
##
## Two claims, and they are the same claim from either end:
##
##   * the formation's facing varies continuously along a path, so the
##     block does not flip 60 degrees between one frame and the next;
##   * no soldier is ever asked to move faster than his own move_speed to
##     hold his place while it turns — the owner's rule from #101.
##
## Both are measured through the REAL path: a real SquadSim, real flow
## fields, real shipped UnitDefs. A caricature def would prove the
## mechanism and say nothing about whether the shipped numbers move
## anybody (M6's lesson), and hand-built curves would not exercise the
## lattice artefact that is most of the defect.
##
## Everything here stays inside D-006 clause 1: facing is still derived
## from the curve by a pure function, and the turn is paid for in the
## curve's own keyframe TIMES. Nothing accumulates anywhere.

# Wide enough that walking the other way round the torus is never the
# short route past the obstacle below — on a narrower map the flow field
# takes the long way round the world instead, and arrives on a dead
# straight path with no corner in it at all.
const W := 64
const H := 24

# Sampling step for measuring a soldier's speed. Short enough to catch a
# single frame's worth of snap, long enough not to be float noise.
const DT := 0.02

# The slack allowed over move_speed. A segment's pace is set from the
# curvature at the vertices bounding it, while the facing chord sweeps
# continuously across them, so the two line up to within a segment rather
# than exactly. This is a few percent, not a factor.
const SPEED_TOLERANCE := 1.05

# The obstacle the corner fixtures walk round, and the route past it.
const BLOB := Vector2i(15, 6)
const FROM := Vector2i(8, 6)
const TO := Vector2i(23, 6)

# A destination off the six lattice directions, so the flow field has to
# staircase its way there.
const DIAGONAL := Vector2i(24, 18)


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _militia() -> UnitDef:
	var def := UnitRoster.by_id(&"legion_militia")
	assert_not_null(def, "setup: the shipped militia def must load")
	return def


## Fastest any one soldier moves, in world units per second, sampled
## along `seconds` of the squad's CURRENT curve.
##
## Both samples come from the same curve, so this measures the motion the
## curve describes rather than the step a re-path makes when it restarts
## from the squad's rounded cell.
func _peak_soldier_speed(sim: SquadSim, squad: int, seconds: float) -> float:
	# Distances are taken across the SEAM (the nearest lattice copy), or a
	# squad wrapping the torus reads as a soldier crossing the map in one
	# frame. `sample_world` wraps the coordinate rather than the motion
	# (D-035), so that jump is a rendering fact, not a speed.
	var copies := sim.space.lattice_offsets()
	var peak := 0.0
	var t := sim.time
	while t < sim.time + seconds:
		var a := sim.soldier_transforms(squad, t)
		var b := sim.soldier_transforms(squad, t + DT)
		if a.size() == b.size():
			for i in range(a.size()):
				var step := INF
				for copy in copies:
					step = minf(step, a[i].origin.distance_to(b[i].origin + copy))
				peak = maxf(peak, step / DT)
		t += DT
	return peak


## Largest turn the squad's facing makes between two consecutive samples,
## in degrees, over `seconds` of its current curve.
func _peak_facing_step(sim: SquadSim, squad: int, seconds: float) -> float:
	var curve := sim.curve_of(squad)
	var peak := 0.0
	var t := sim.time
	while t < sim.time + seconds:
		var a := Formation.heading(curve, t)
		var b := Formation.heading(curve, t + DT)
		peak = maxf(peak, rad_to_deg(absf(a.angle_to(b))))
		t += DT
	return peak


## Walk a squad the whole way to `to`, ticking, and hand each tick to
## `probe` — which returns a number to take the maximum of.
##
## The whole journey rather than one window, because where the flow field
## puts a corner is its business: sampling two seconds out of the middle
## measured a straight stretch and called the defect fixed.
func _worst_over_journey(sim: SquadSim, squad: int, to: Vector2i,
		probe: Callable) -> float:
	var worst := 0.0
	for _i in range(600):
		sim.tick()
		worst = maxf(worst, float(probe.call(sim, squad)))
		if sim.cell_of(squad) == to:
			break
	return worst


func _all_passable(sim: SquadSim) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(sim.space.cell_count())
	p.fill(1)
	return p


## An obstacle sitting on the straight route, so the path has a corner in
## it that is a real change of direction rather than a lattice artefact.
##
## A blob rather than a wall, and that is not arbitrary: a wall of
## constant q does not block a torus at all — the squad simply walks the
## other way round the world and arrives on a dead straight path with no
## corner in it, which is how the first version of this fixture measured
## nothing while looking like it measured a corner.
func _barrier(sim: SquadSim) -> PackedByteArray:
	var p := _all_passable(sim)
	for dq in range(-3, 4):
		for dr in range(-3, 4):
			var cell := Vector2i(BLOB.x + dq, BLOB.y + dr)
			if sim.space.distance(BLOB, cell) <= 3:
				p[sim.space.index(sim.space.normalize(cell))] = 0
	return p


# --- the owner's rule -------------------------------------------------

func test_no_soldier_outruns_his_own_speed_on_a_lattice_march() -> void:
	# The everyday case: a destination off the six lattice directions, so
	# the flow field has to staircase its way there and the route changes
	# direction without the squad's journey doing anything of the sort.
	var sim := _sim()
	sim.set_passable(_all_passable(sim))
	var def := _militia()
	var squad := sim.add_squad(def, 1, FROM)
	sim.order_move(squad, DIAGONAL)

	var peak := _worst_over_journey(sim, squad, DIAGONAL,
		func(s: SquadSim, q: int) -> float: return _peak_soldier_speed(s, q, 0.1))
	gut.p("diagonal march: peak soldier speed %.2f vs move_speed %.2f" % [peak, def.move_speed])
	assert_lt(peak, def.move_speed * SPEED_TOLERANCE,
		"a soldier is outrunning his own move_speed to hold formation")


func test_no_soldier_outruns_his_own_speed_rounding_a_real_corner() -> void:
	var sim := _sim()
	sim.set_passable(_barrier(sim))

	var def := _militia()
	var squad := sim.add_squad(def, 1, FROM)
	sim.order_move(squad, TO)

	var peak := _worst_over_journey(sim, squad, TO,
		func(s: SquadSim, q: int) -> float: return _peak_soldier_speed(s, q, 0.1))
	gut.p("corner: peak soldier speed %.2f vs move_speed %.2f" % [peak, def.move_speed])
	assert_lt(peak, def.move_speed * SPEED_TOLERANCE,
		"a soldier is outrunning his own move_speed rounding a corner")


# --- continuity of facing ---------------------------------------------

func test_facing_never_steps_as_the_route_changes_direction() -> void:
	# The other half of the same defect: where the route changes direction,
	# facing derived straight off the polyline flips in ONE FRAME and the
	# whole rigid block flips with it. That is the "jumping around" from
	# #101, and it is what a soldier's speed measurement above sees as a
	# number; this one names it directly.
	#
	# On the obstacle route rather than the open one, because a hex flow
	# field walks in RUNS of one lattice direction rather than alternating
	# cell by cell — an open march can be a single run with no direction
	# change in it at all to catch.
	var sim := _sim()
	sim.set_passable(_barrier(sim))
	var squad := sim.add_squad(_militia(), 1, FROM)
	sim.order_move(squad, TO)

	var step := _worst_over_journey(sim, squad, TO,
		func(s: SquadSim, q: int) -> float: return _peak_facing_step(s, q, 0.1))
	gut.p("corner: peak facing step %.2f degrees per %.0f ms" % [step, DT * 1000.0])
	assert_lt(step, 4.0,
		"facing is stepping rather than turning — the formation snaps with it")


# --- the coupling that makes it safe ----------------------------------

func test_the_facing_chord_fits_in_what_a_client_holds() -> void:
	# Facing is derived on BOTH sides from the same curve, but the client's
	# copy is clipped to [now, now + horizon] (D-003). The chord is a
	# LENGTH of path, so what matters is how much path fits in that window
	# — and the answer is worst for the slowest unit in the game walking at
	# the slowest pace SquadSim will ever set it to. Reaching past that
	# would give the server one facing and the client another.
	var replicator := CurveReplicator.new()
	var slowest := INF
	for def in UnitRoster.load_all():
		slowest = minf(slowest, def.move_speed)
	assert_lt(slowest, INF, "setup: the roster must have units in it")

	var crawl := (slowest / TorusSpace.SQRT_3) * SquadSim.MIN_TURNING_SPEED
	var held := crawl * replicator.horizon_seconds
	gut.p("slowest crawl holds %.2f cells of curve; the chord asks for %.2f" % [
		held, Formation.HEADING_ARC])
	assert_lt(Formation.HEADING_ARC, held,
		"the facing chord reaches past the curve a client is sent")


# --- the path is still the field's path --------------------------------

func test_smoothing_never_puts_a_squad_on_impassable_ground() -> void:
	# Smoothing moves the squad's centre off the cell centres the field
	# walked. It may make a nicer line through those cells; it may not
	# invent a route through anything the field refused.
	var sim := _sim()
	var passable := _barrier(sim)
	sim.set_passable(passable)
	var squad := sim.add_squad(_militia(), 1, FROM)
	sim.order_move(squad, TO)

	for _i in range(400):
		sim.tick()
		var cell := sim.cell_of(squad)
		assert_true(passable[sim.space.index(cell)] != 0,
			"the squad walked onto impassable ground at %s" % cell)
		if cell == TO:
			break


# --- what it costs the wire -------------------------------------------

func test_a_straight_march_buys_no_extra_keyframes() -> void:
	# Splitting a path finer is how a bend gets resolved, and every split
	# is keyframes on the wire (D-003). So it has to be paid for only
	# where there is a bend: an open march must cost exactly what it cost
	# before any of this existed, which is one keyframe per cell the flow
	# field walked.
	var sim := _sim()
	sim.set_passable(_all_passable(sim))
	var def := _militia()
	var squad := sim.add_squad(def, 1, FROM)
	sim.order_move(squad, DIAGONAL)

	var cells_per_second := def.move_speed / (sim.space.hex_size * TorusSpace.SQRT_3)
	var most := ceili(sim.curve_lookahead_seconds * cells_per_second) + 1

	var worst := int(_worst_over_journey(sim, squad, DIAGONAL,
		func(s: SquadSim, q: int) -> float: return float(s.curve_of(q).key_count())))
	gut.p("open march: worst %d keyframes against a ceiling of %d" % [worst, most])
	assert_lte(worst, most,
		"a straight march is paying keyframes for a bend it does not have")


func test_a_bend_costs_keyframes_but_a_bounded_number_of_them() -> void:
	# And where it IS paid, it stays bounded: PATH_REFINEMENTS halvings,
	# so at worst 2^n segments where there was one. A number that ran away
	# here would be a bandwidth regression nothing else in the suite could
	# see.
	var sim := _sim()
	sim.set_passable(_barrier(sim))
	var def := _militia()
	var squad := sim.add_squad(def, 1, FROM)
	sim.order_move(squad, TO)

	var cells_per_second := def.move_speed / (sim.space.hex_size * TorusSpace.SQRT_3)
	var walked := ceili(sim.curve_lookahead_seconds * cells_per_second)
	var ceiling := walked * int(pow(2, SquadSim.PATH_REFINEMENTS)) + 1

	var worst := int(_worst_over_journey(sim, squad, TO,
		func(s: SquadSim, q: int) -> float: return float(s.curve_of(q).key_count())))
	gut.p("round an obstacle: worst %d keyframes against a ceiling of %d" % [worst, ceiling])
	assert_lte(worst, ceiling,
		"path refinement is splitting further than it is allowed to")


# --- the tactical property that falls out of it ------------------------

func test_the_further_a_formation_reaches_the_longer_it_takes_to_turn() -> void:
	# The turn is charged as the arc the OUTERMOST soldier walks, so how
	# long a squad takes to come round a corner is a property of how far
	# its formation reaches from the point it rotates about. That is the
	# tactical weight the formation buttons never had, and it is the same
	# arithmetic as the rule above rather than a second mechanism.
	#
	# Which SHAPE reaches furthest is deliberately read rather than
	# assumed: a squad rotates about its curve point, which sits at the
	# front rank, so a deep column swings its rear further than a wide line
	# swings its flank — 7.33 against 5.27 on the shipped militia.
	var line := Formation.turn_lever("line", 36, 0.9)
	var column := Formation.turn_lever("column", 36, 0.9)
	assert_ne(line, column, "setup: the two shapes must reach different distances")

	var short_seconds := _corner_seconds("line" if line < column else "column")
	var long_seconds := _corner_seconds("column" if line < column else "line")
	gut.p("corner cost: lever %.2f took %.1f s, lever %.2f took %.1f s" % [
		minf(line, column), short_seconds, maxf(line, column), long_seconds])
	assert_gt(long_seconds, short_seconds,
		"a formation that reaches further should take longer round a corner")


## Seconds a squad of `shape` takes to walk a fixed route with a corner in
## it. Everything except the formation is held constant.
func _corner_seconds(shape: String) -> float:
	var sim := _sim()
	sim.set_passable(_barrier(sim))

	var def: UnitDef = _militia().duplicate()
	def.formation_shape = shape
	var squad := sim.add_squad(def, 1, FROM)
	sim.order_move(squad, TO)
	for _i in range(1200):
		sim.tick()
		if sim.cell_of(squad) == TO:
			break
	return sim.time
