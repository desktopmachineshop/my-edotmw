extends GutTest

## Guards naval cut-list stage 7's done-condition: **a landing happens in
## a played match, and the gate fails when it does not** (#301, §6.2).
##
## Everything here is the REAL simulation, ticked: a dock, a hull at its
## water side, a squad ordered aboard, the laden hull ordered at the far
## shore. No test double, no hand-set `_cargo`, no calling `disembark`
## directly — because the thing under test is the SEQUENCE, and every one
## of its legs was written by a different stage.
##
## §6 exists because D-076 shipped a feature the estate could not run,
## and #210 then sat undetected. A landing that only ever happens because
## a test called `disembark()` is exactly that failure with a green tick
## on it.


const W := 32
const H := 16
## TWO seas, and the second one is not decoration. The map is a torus
## (D-008), so a single north-south channel separates nothing: land west
## of it and land east of it meet again around the seam, and a squad
## ordered "across" simply walks the long way round.
##
## The first version of this file had one channel, and
## `test_a_land_squad_cannot_simply_walk_across` caught it — the levy
## arrived at x = 17 having never touched water. That premise test is the
## only reason the three crossing tests below mean anything: without it
## they would all have passed over a strait that was not a strait.
##
## Same trap `formation.md` records for the wheeling fixture: *"a wall of
## constant q does not block a torus at all, so the first corner fixture
## had the squad walk the other way round the world and arrive on a dead
## straight path."*
const SEA_FROM := 8
const SEA_TO := 16
const SEA2_FROM := 24
const SEA2_TO := 32


func _world() -> Dictionary:
	var space := TorusSpace.new(W, H, 1.0)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var wet := _is_sea(coord.x)
		passable[index] = 0 if wet else 1
		navigable[index] = 1 if wet else 0
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.buildings = BuildingSim.new(space)
	sim.set_passable(passable)
	sim.set_navigable(navigable)
	return {"sim": sim, "space": space, "passable": passable, "navigable": navigable}


## Which columns are water. Its own function so the two-channel rule is
## stated once and the loop above stays readable.
func _is_sea(x: int) -> bool:
	if x >= SEA_FROM and x < SEA_TO:
		return true
	return x >= SEA2_FROM and x < SEA2_TO


func _def(archetype: StringName) -> UnitDef:
	var d := UnitRoster.for_civ_archetype(&"gravesworn", archetype)
	assert_not_null(d, "setup: a civ must field a %s" % archetype)
	return d


## A dock on the near shore, with its water side in the sea beside it —
## which is what `_quay_for` needs before anybody can board (§3.4: you
## load at a dock and nowhere else).
func _dock(w: Dictionary, at: Vector2i) -> int:
	var sim: SquadSim = w["sim"]
	var def := BuildingSim.def_by_id(&"dock")
	assert_not_null(def, "setup: the shipped dock is where BuildingSim looks for it")
	var id: int = sim.buildings.add_building(def, 1, at, true)
	sim.buildings.set_water_cell(id, (w["space"] as TorusSpace).index(at + Vector2i(1, 0)))
	return id


func _tick(w: Dictionary, seconds: float) -> void:
	var sim: SquadSim = w["sim"]
	for _i in range(int(seconds * SquadSim.TICK_HZ)):
		sim.tick()


# --- the crossing, end to end -------------------------------------------

func test_an_army_crosses_water_and_lands_on_the_far_shore() -> void:
	# THE stage-7 criterion, played rather than asserted about. Dock,
	# hull, board, sail, land — four legs written by four stages, run in
	# one sequence against the real sim.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var space: TorusSpace = w["space"]

	var quay := Vector2i(SEA_FROM - 1, 8)
	_dock(w, quay)
	var hull := sim.add_squad(_def(&"transport"), 1, quay + Vector2i(1, 0))
	assert_eq(sim.tier_of(hull), SquadSim.DOMAIN_WATER,
		"setup: a transport belongs to the water domain (stage 2)")

	var army := sim.add_squad(_def(&"levy"), 1, quay - Vector2i(2, 0))
	var before := sim.alive_of(army)
	assert_gt(before, 0, "setup: the landing party must have men in it")

	# Ordered AT THE HULL. Stage 4 made that the embark order, so this is
	# an ordinary move and no opcode exists for boarding.
	sim.order_move(army, sim.cell_of(hull))
	_tick(w, 20.0)
	assert_eq(sim.alive_of(army), 0, "the party must be aboard, not standing on the quay")
	assert_eq((sim.cargo_of(hull) as Array).size(), 1, "and aboard THIS hull")

	# Ordered AT THE FAR SHORE. A laden hull ordered at land records a
	# landing and performs it when it arrives — the sailing in between is
	# stage 2's flow field, which is what makes this a crossing rather
	# than a hop.
	var beach := Vector2i(SEA_TO, 8)
	assert_true(sim.is_passable(beach), "setup: the far shore must be land")
	sim.order_move(hull, beach)
	_tick(w, 60.0)

	assert_eq((sim.cargo_of(hull) as Array).size(), 0,
		"the hull must have put its cargo ashore")
	var landed := _squads_near(sim, beach, 1, 3)
	assert_gt(landed.size(), 0,
		"A LANDING DID NOT HAPPEN. This is stage 7's exit criterion; a zero here "
		+ "means one of dock/board/sail/land broke, and the legs above say which.")
	assert_eq(sim.alive_of(int(landed[0])), before,
		"a landed squad keeps the men it had — no assault penalty, no bonus (§3.4)")


func test_the_party_is_ashore_on_the_side_it_was_sent_to() -> void:
	# A landing that put the army back where it started would satisfy
	# every count above and be worthless.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var quay := Vector2i(SEA_FROM - 1, 8)
	_dock(w, quay)
	var hull := sim.add_squad(_def(&"transport"), 1, quay + Vector2i(1, 0))
	var army := sim.add_squad(_def(&"levy"), 1, quay - Vector2i(2, 0))

	sim.order_move(army, sim.cell_of(hull))
	_tick(w, 20.0)
	sim.order_move(hull, Vector2i(SEA_TO, 8))
	_tick(w, 60.0)

	var landed := _squads_near(sim, Vector2i(SEA_TO, 8), 1, 3)
	assert_gt(landed.size(), 0, "setup: somebody has to have landed")
	assert_gt((w["space"] as TorusSpace).from_index(
		sim.cell_index_of(int(landed[0]))).x, float(SEA_FROM),
		"the army must be on the FAR side of the water it crossed")


func test_nothing_lands_when_the_hull_never_gets_there() -> void:
	# The gate's other half: it must FAIL when a landing does not happen.
	# Observed by ordering the hull nowhere at all — the cargo stays
	# aboard and the criterion above would go red, which is what makes a
	# green run mean something.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var quay := Vector2i(SEA_FROM - 1, 8)
	_dock(w, quay)
	var hull := sim.add_squad(_def(&"transport"), 1, quay + Vector2i(1, 0))
	var army := sim.add_squad(_def(&"levy"), 1, quay - Vector2i(2, 0))

	sim.order_move(army, sim.cell_of(hull))
	_tick(w, 20.0)
	assert_eq((sim.cargo_of(hull) as Array).size(), 1, "setup: aboard")

	_tick(w, 60.0)
	assert_eq((sim.cargo_of(hull) as Array).size(), 1,
		"a hull nobody ordered ashore keeps its cargo — a landing must be ORDERED, "
		+ "and a criterion that passed without one would be measuring nothing")
	assert_eq(_squads_near(sim, Vector2i(SEA_TO, 8), 1, 3).size(), 0,
		"and nobody is on the far beach")


func test_a_land_squad_cannot_simply_walk_across():
	# The premise the whole feature rests on. If a levy could walk the
	# channel, every test above would pass with no boat involved.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var army := sim.add_squad(_def(&"levy"), 1, Vector2i(SEA_FROM - 2, 8))
	sim.order_move(army, Vector2i(SEA_TO + 1, 8))
	_tick(w, 60.0)
	var at := (w["space"] as TorusSpace).from_index(sim.cell_index_of(army))
	assert_lt(at.x, float(SEA_FROM),
		"a land squad must not cross open water on foot — if it can, this whole "
		+ "feature is measuring a walk")


## Living squads of any owner within `radius` of `at`, excluding hulls.
func _squads_near(sim: SquadSim, at: Vector2i, radius: int, _unused: int) -> Array:
	var out := []
	for squad in range(sim.squad_count()):
		if sim.alive_of(squad) <= 0:
			continue
		if sim.tier_of(squad) == SquadSim.DOMAIN_WATER:
			continue
		if sim.space.distance(sim.cell_of(squad), at) <= radius:
			out.append(squad)
	return out
