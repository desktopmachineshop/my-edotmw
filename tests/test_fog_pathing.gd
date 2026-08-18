extends GutTest

## Guards D-20260818-pathing-knows-only-what-the-player-knows: a squad may
## not route around, or be refused because of, terrain its owner has never
## seen.
##
## The defect these were written against (#96, from playtest P06) was not a
## wrong flow field. It was a perfectly correct one, solved against the
## sim's single ground-truth passability array — so fog hid the terrain
## visually while movement quietly acted on the whole map. Nothing failed,
## and no counter anywhere could see it: the paths were optimal, the
## refusals were accurate, and both were derived from data the player did
## not have.
##
## Two halves, matching the two halves of the issue:
##
## 1. **Routing** — the route is planned as though unknown ground is
##    passable, and re-planned on discovering it is not.
## 2. **Refusal** — an order is refused only once the KNOWN map proves it
##    impossible, never on the tick it was given.

const W := 40
const H := 20


func _sim() -> SquadSim:
	return SquadSim.new(TorusSpace.new(W, H, 1.0), CurveReplicator.new())


func _def() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"test_scout"
	d.squad_size = 12
	d.move_speed = 3.5
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	return d


## A def that can see nothing at all, so the only thing it can ever learn
## is what it walks into. The safety net under optimistic pathing has to
## hold for this unit too.
func _blind_def() -> UnitDef:
	var d := _def()
	d.id = &"test_blind"
	d.vision_range = 0.0
	return d


func _open(sim: SquadSim) -> PackedByteArray:
	var passable := PackedByteArray()
	passable.resize(sim.space.cell_count())
	passable.fill(1)
	return passable


## Seal `dest` in behind a ring of blocked cells, the same shape
## test_squad_sim's give-up tests use.
func _seal(sim: SquadSim, passable: PackedByteArray, dest: Vector2i) -> void:
	var dest_index := sim.space.index(dest)
	for dir in range(6):
		passable[sim.space.neighbor_index(dest_index, dir)] = 0


## A full column of blocked cells between the squad and its destination,
## with one gap far to the south. Ground truth says "go through the gap";
## a side that has seen nothing says "straight ahead".
func _walled_with_a_gap(sim: SquadSim) -> PackedByteArray:
	var passable := _open(sim)
	for r in range(H):
		passable[sim.space.index(Vector2i(12, r))] = 0
	passable[sim.space.index(Vector2i(12, 0))] = 1
	return passable


func _tick_for(sim: SquadSim, seconds: float) -> void:
	for _i in range(int(seconds * SquadSim.TICK_HZ)):
		sim.tick()


# --- refusal: only what the player knows may say no --------------------

func test_an_order_into_an_unexplored_pocket_is_attempted_not_refused() -> void:
	# The reported symptom, at its sharpest: order a squad into a pocket
	# that turns out to be sealed and it refused INSTANTLY, before any of
	# its own squads had been near the obstruction that makes it
	# impossible. The player is told no on the strength of a wall they have
	# never seen.
	var sim := _sim()
	var passable := _open(sim)
	var dest := Vector2i(24, 10)
	_seal(sim, passable, dest)
	sim.set_passable(passable)

	var squad := sim.add_squad(_def(), 1, Vector2i(2, 10))
	sim.order_move(squad, dest)
	sim.tick()

	assert_eq(sim.destination_of(squad), dest,
		"the order was cancelled on the tick it was given, from a wall nobody has seen")
	assert_true(sim.curve_of(squad).key_count() > 1,
		"the squad should have a real path to walk, not a single keyframe")


func test_the_march_ends_in_a_refusal_once_the_wall_is_discovered() -> void:
	# ...and the other half of the same rule: discovery must actually
	# settle it. A squad that keeps optimistically re-pathing forever is
	# D-003's invalidation storm, which is what the give-up rule was
	# written to prevent — narrowing its INPUT to what the player knows
	# must not widen its behaviour to "never give up".
	var sim := _sim()
	var passable := _open(sim)
	var dest := Vector2i(24, 10)
	_seal(sim, passable, dest)
	sim.set_passable(passable)

	var squad := sim.add_squad(_def(), 1, Vector2i(2, 10))
	sim.order_move(squad, dest)
	_tick_for(sim, 30.0)

	assert_ne(sim.cell_of(squad), dest, "the destination is sealed; nothing should reach it")
	assert_true(sim.knowledge.discoveries > 0,
		"the squad marched the whole way and learned nothing about the ground")
	var rebuilt := sim.curves_rebuilt
	_tick_for(sim, 5.0)
	assert_eq(sim.curves_rebuilt, rebuilt,
		"the squad is still re-pathing every tick — the give-up rule stopped firing")


# --- routing: the shortest route nobody has reason to doubt ------------

func test_a_squad_marches_toward_an_unseen_wall_instead_of_around_it() -> void:
	# A wall the player has never seen must not bend the route: the squad
	# takes the shortest way it has no reason to doubt, which means it
	# closes on the wall rather than setting off around it.
	var sim := _sim()
	sim.set_passable(_walled_with_a_gap(sim))

	var start := Vector2i(6, 10)
	var squad := sim.add_squad(_def(), 1, start)
	sim.order_move(squad, Vector2i(18, 10))
	_tick_for(sim, 2.0)

	# Two seconds of walking: an omniscient field would already have turned
	# the squad south toward the gap at r=0.
	var here := sim.cell_of(squad)
	assert_eq(here.y, start.y,
		"the squad turned aside for a wall its owner has never seen")
	assert_true(here.x > start.x, "the squad should have set off toward its destination")


func test_the_route_bends_once_the_wall_has_been_seen() -> void:
	# ...and the same wall, once discovered, is routed around — the whole
	# point of re-planning on discovery. Given long enough the squad finds
	# the gap and arrives, which no amount of optimism could do on its own.
	var sim := _sim()
	sim.set_passable(_walled_with_a_gap(sim))

	var squad := sim.add_squad(_def(), 1, Vector2i(6, 10))
	var dest := Vector2i(18, 10)
	sim.order_move(squad, dest)
	_tick_for(sim, 90.0)

	assert_eq(sim.cell_of(squad), dest,
		"the squad never found the gap — discovery is not re-routing")
	assert_true(sim.route_discoveries > 0,
		"it arrived without discovering anything, so the wall was never in its way")


# --- the safety net ----------------------------------------------------

func test_a_blind_squad_still_never_stands_in_a_wall() -> void:
	# Optimism is allowed to plan a route into a mountain. It is never
	# allowed to put soldiers inside one — and a unit with no vision at all
	# has nothing but touch to learn from, so this is the case that proves
	# the discovery-by-touch net rather than sight doing the work.
	var sim := _sim()
	sim.set_passable(_walled_with_a_gap(sim))

	var squad := sim.add_squad(_blind_def(), 1, Vector2i(6, 10))
	sim.order_move(squad, Vector2i(18, 10))
	for _i in range(900):
		sim.tick()
		assert_true(sim.is_passable(sim.cell_of(squad)),
			"a squad stood on ground nothing can stand on, at %s" % sim.cell_of(squad))


# --- knowledge is per SIDE (D-050) -------------------------------------

func test_allies_share_one_field_and_strangers_do_not() -> void:
	# D-007's sharing claim is what keying fields on knowledge threatens,
	# so the sharing that was ever load-bearing has to survive: everyone
	# who shares sight shares the field. Allies do (D-050); two unallied
	# players genuinely have different answers and must pay for both.
	var sim := _sim()
	sim.set_passable(_open(sim))
	sim.teams = {1: 1, 2: 1, 3: 2}
	var a := sim.add_squad(_def(), 1, Vector2i(2, 10))
	var b := sim.add_squad(_def(), 2, Vector2i(3, 10))
	var built_before := sim.fields_built
	sim.order_move(a, Vector2i(20, 10))
	sim.order_move(b, Vector2i(20, 10))
	assert_eq(sim.fields_built - built_before, 1,
		"two allies walking to the same cell solved two fields — D-050 sharing lost")

	var c := sim.add_squad(_def(), 3, Vector2i(4, 10))
	sim.order_move(c, Vector2i(20, 10))
	assert_eq(sim.fields_built - built_before, 2,
		"a stranger's squad reused a field solved from someone else's knowledge")
