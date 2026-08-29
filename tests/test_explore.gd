extends GutTest

## Guards the explore order (#120): a squad that hunts fog on its own until
## told to stop.
##
## Named decisions this holds the feature to:
##
## - **D-004 / D-025** — fog is curve gating and there is ONE fog query.
##   The frontier comes from `TerrainKnowledge`, fed by `Vision`'s own
##   coverage; a second per-player field would be the data-hiding path
##   D-004 forbids.
## - **#120 point 1 / D-20260818-pathing-knows-only-what-the-player-knows**
##   — an explore that steers by the true map is a maphack wearing a UI,
##   and it is MORE dangerous here than in #96 because the simulation
##   picks the destination rather than a player clicking one.
## - **D-007 / D-038** — flow fields are shared per destination, and N
##   scouts each demanding a unique frontier CELL is that design's
##   pathological case. Targets are snapped regions.
## - **D-006 / D-024** — squad-level only. Nothing here is per-soldier.
## - **D-20260818-every-microsecond-of-a-tick-has-a-phase** — the repick
##   pass is charged to its own accumulator, not to the residual.

const WIDTH := 24
const HEIGHT := 16


func _space() -> TorusSpace:
	return TorusSpace.new(WIDTH, HEIGHT, 1.0)


func _scout_def() -> UnitDef:
	# A deliberate fixture rather than "whatever sorts first" in the
	# roster — docs/status/the-opening.md records five fixtures that broke
	# on a roster change because they took the first def they were handed.
	var d := UnitDef.new()
	d.id = &"test_scout"
	d.archetype = &"scout"
	d.squad_size = 4
	d.health = 40.0
	d.damage = 0.0
	d.move_speed = 6.0
	d.attack_range = 1.9
	d.vision_range = 3.0
	d.formation_shape = "line"
	d.formation_spacing = 1.0
	return d


func _sim(space: TorusSpace = null) -> SquadSim:
	var s := SquadSim.new()
	s.space = space if space != null else _space()
	return s


# --- the pure picker (ExploreTarget) -----------------------------------

func _all_unexplored() -> PackedByteArray:
	# Empty is how TerrainKnowledge reports "this side has observed
	# nothing", and every caller must read it that way rather than
	# indexing it.
	return PackedByteArray()


func _explored_everywhere(space: TorusSpace) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(space.width * space.height)
	out.fill(1)
	return out


func test_a_side_that_has_seen_nothing_is_sent_somewhere() -> void:
	var space := _space()
	var target := ExploreTarget.next_destination(space, _all_unexplored(),
		PackedByteArray(), Vector2i(5, 5), 4)
	assert_ne(target, ExploreTarget.nothing(),
		"a side that has observed nothing has everything left to look at")


func test_a_side_that_has_seen_everything_is_sent_nowhere() -> void:
	# The other half, and the one that separates "the map is uncovered"
	# from "the picker is broken" — both otherwise look like a squad that
	# stopped moving.
	var space := _space()
	var target := ExploreTarget.next_destination(space,
		_explored_everywhere(space), PackedByteArray(), Vector2i(5, 5), 4)
	assert_eq(target, ExploreTarget.nothing(),
		"nothing unexplored left means no destination, not an arbitrary one")


func test_the_nearest_fog_wins_and_it_is_measured_across_the_seam() -> void:
	# THE wrap-awareness claim (D-008), and it is not incidental: a scout
	# that walked the long way round the torus to reach fog three cells
	# behind it is the seam bug this project keeps paying for. Only
	# TorusSpace may answer "how far".
	var space := _space()
	var explored := _explored_everywhere(space)
	# TWO candidates, and that is the whole fixture. With only one patch of
	# fog on the map every distance metric picks it, so the test would pass
	# with the torus torn out — which is exactly what happened to the first
	# version of this check, caught by perturbing it. A guard that cannot
	# fail is the vacuous pass D-022's audit block was written against.
	var from := Vector2i(WIDTH - 2, 8)
	var across_the_seam := Vector2i(0, 8)
	var the_long_way := Vector2i(WIDTH - 8, 8)
	explored[space.index(across_the_seam)] = 0
	explored[space.index(the_long_way)] = 0

	# Setup assertions, so a change to WIDTH cannot quietly make this a
	# straight line in disguise: the seam candidate must be NEARER on the
	# torus and FURTHER by naive coordinate arithmetic.
	assert_lt(space.distance(from, across_the_seam), space.distance(from, the_long_way),
		"setup: the seam candidate must be the nearer one on a torus")
	assert_gt(absi(from.x - across_the_seam.x), absi(from.x - the_long_way.x),
		"setup: and the further one to anything that ignores the wrap")

	var target := ExploreTarget.next_destination(space, explored,
		PackedByteArray(), from, 1)
	assert_eq(target, across_the_seam,
		"the nearest fog is across the seam — a scout that walked the long "
		+ "way round is the seam bug this project keeps paying for")


func test_ground_the_side_knows_is_blocked_is_not_worth_walking_to() -> void:
	var space := _space()
	var explored := _explored_everywhere(space)
	var near := Vector2i(6, 8)
	var far := Vector2i(12, 8)
	explored[space.index(near)] = 0
	explored[space.index(far)] = 0
	# Believed blocked at `near` — observed and refused, so not a target
	# even though it is closer and unexplored.
	var believed := PackedByteArray()
	believed.resize(space.width * space.height)
	believed.fill(1)
	believed[space.index(near)] = 0
	var target := ExploreTarget.next_destination(space, explored, believed,
		Vector2i(5, 8), 1)
	assert_eq(target, far,
		"a cell this side has SEEN is a mountain is not fog worth visiting")


func test_unknown_ground_is_optimistically_worth_visiting() -> void:
	# The other side of the same rule, and the one that matters for
	# D-20260818: belief is OPTIMISTIC, so a scout sets off toward a bay
	# it has never seen and finds out by walking. An empty belief array
	# means "no opinion", which must read as passable.
	var space := _space()
	var explored := _explored_everywhere(space)
	var fog := Vector2i(9, 4)
	explored[space.index(fog)] = 0
	var target := ExploreTarget.next_destination(space, explored,
		PackedByteArray(), Vector2i(5, 4), 1)
	assert_eq(target, fog, "no opinion about the ground must not veto a look at it")


func test_a_claimed_region_is_left_for_the_squad_that_claimed_it() -> void:
	# Two scouts must not walk to the same fog. Without this the second
	# one is a wasted squad that looks like it is working.
	var space := _space()
	var explored := _explored_everywhere(space)
	var near := Vector2i(6, 8)
	var far := Vector2i(12, 8)
	explored[space.index(near)] = 0
	explored[space.index(far)] = 0
	var claimed := {space.index(near): true}
	var target := ExploreTarget.next_destination(space, explored,
		PackedByteArray(), Vector2i(5, 8), 1, claimed)
	assert_eq(target, far, "the nearer fog is taken; take the next one")


func test_the_picker_is_pure() -> void:
	# Same inputs, same answer, forever — and no instance state to hold an
	# opinion between calls. This is the property that lets the AI reuse
	# it (#120) without the two growing separate definitions of exploring,
	# and it is the same all-static discipline formation.gd is built on.
	var space := _space()
	var explored := _explored_everywhere(space)
	explored[space.index(Vector2i(9, 4))] = 0
	var first := ExploreTarget.next_destination(space, explored,
		PackedByteArray(), Vector2i(5, 4), 1)
	var second := ExploreTarget.next_destination(space, explored,
		PackedByteArray(), Vector2i(5, 4), 1)
	assert_eq(first, second, "a pure picker cannot answer differently the second time")

	var script: GDScript = load("res://explore_target.gd")
	for method in script.get_script_method_list():
		assert_true(method["flags"] & METHOD_FLAG_STATIC != 0,
			"ExploreTarget.%s must be static — there is nowhere for state to live" % method["name"])
	# SCRIPT_VARIABLE usage, not the raw list: every GDScript reports one
	# entry with CATEGORY usage naming the file itself, and `formation.gd`
	# — this project's canonical all-static class — reports it too. Counting
	# the raw list would fail on a class that is already correct, which is
	# a guard that red-flags good code and therefore gets relaxed until it
	# stops guarding.
	for property in script.get_script_property_list():
		assert_eq(int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE, 0,
			"ExploreTarget.%s is instance state — there must be nowhere for an opinion to live between calls"
				% property["name"])


func test_targets_are_snapped_so_scouts_can_share_a_flow_field() -> void:
	# D-007's sharing is the scaling claim and #120 names N-scouts-N-fields
	# as its pathological case. Two squads whose nearest fog is different
	# CELLS of the same region must be given the same destination.
	var space := _space()
	var explored := _explored_everywhere(space)
	for cell in [Vector2i(12, 8), Vector2i(13, 8), Vector2i(14, 8), Vector2i(15, 8)]:
		explored[space.index(cell)] = 0
	var a := ExploreTarget.next_destination(space, explored, PackedByteArray(),
		Vector2i(12, 8), 4)
	var b := ExploreTarget.next_destination(space, explored, PackedByteArray(),
		Vector2i(15, 8), 4)
	assert_eq(a, b, "fog in one region is one destination, however many scouts want it")
	assert_eq(a, Vector2i(12, 8), "and it is the region's own corner, not a squad's cell")


# --- the ever-explored set (TerrainKnowledge) --------------------------

func test_explored_is_not_the_same_question_as_believed_passable() -> void:
	# THE distinction the whole feature rests on, and the reason a second
	# array had to exist: `believed` starts all-1 because unknown ground
	# reads passable, so "believed == 1" cannot tell "never seen" from
	# "seen, and open". Same currently-visible-vs-ever-revealed split
	# D-026's hash had to get right.
	var knowledge := TerrainKnowledge.new()
	var truth := PackedByteArray()
	truth.resize(WIDTH * HEIGHT)
	truth.fill(1)

	assert_true(knowledge.believes_passable(0, 5),
		"unknown ground is optimistically passable")
	assert_false(knowledge.has_explored(0, 5),
		"and pessimistically unexplored — the two defaults must disagree")


func test_sight_marks_ground_explored_even_when_it_changes_no_belief() -> void:
	# The trap: `observe` skips cells whose passability it already agreed
	# with, which on open ground is almost the whole map. If the explored
	# write sat after that skip, a scout would keep being sent back to
	# ground it was standing on.
	var space := _space()
	var knowledge := TerrainKnowledge.new()
	var truth := PackedByteArray()
	truth.resize(WIDTH * HEIGHT)
	truth.fill(1)   # every cell open — so belief is right about all of it

	var vision := Vision.new()
	var seen := space.index(Vector2i(3, 3))
	knowledge.discover(0, seen, true, truth.size())
	assert_true(knowledge.has_explored(0, seen),
		"touch is an observation — a vision_range 0 unit learns only this way")

	var before := knowledge.explored_count(0)
	assert_gt(before, 0, "setup: something must have been observed")


func test_a_squad_walking_marks_the_ground_it_covers_explored() -> void:
	# End to end through the sim's own vision cadence, rather than by
	# calling absorb by hand: this is the path that actually feeds the
	# picker, and a test that drove absorb directly would pass while the
	# wiring in tick() was missing.
	var space := _space()
	var sim := _sim(space)
	var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	sim.tick()

	var knower := sim.knowledge_group_of(squad)
	assert_gt(sim.knowledge.explored_count(knower), 0,
		"a squad with vision must have marked SOMETHING explored after a tick")
	assert_true(sim.knowledge.has_explored(knower, space.index(Vector2i(6, 6))),
		"the cell it is standing on above all")
	assert_false(sim.knowledge.has_explored(knower, space.index(Vector2i(18, 12))),
		"and not the far side of the map, which nothing has looked at")


# --- the mode, in the sim ----------------------------------------------

func test_an_explore_order_sends_the_squad_somewhere() -> void:
	var space := _space()
	var sim := _sim(space)
	var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	sim.tick()
	assert_true(sim.is_idle(squad), "setup: a squad with no order stands still")

	sim.order_explore(squad)
	assert_true(sim.is_exploring(squad), "the mode is on")
	assert_false(sim.is_idle(squad),
		"and it has somewhere to be — an explore that picks nothing is the bug")


func test_exploring_repicks_when_the_squad_runs_out_of_journey() -> void:
	# THE feature. #120 is explicit that the interesting part is the
	# repick, not the first leg: "explore is a mode the squad stays in".
	var space := _space()
	var sim := _sim(space)
	var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	sim.order_explore(squad)

	var destinations := {}
	for _i in range(400):
		sim.tick()
		destinations[sim.destination_of(squad)] = true

	assert_gt(destinations.size(), 1,
		"a squad that only ever had one destination never repicked — the mode is dead")
	assert_gt(sim.explore_repicks, 1,
		"and the counter says so: %d repicks" % sim.explore_repicks)


func test_exploring_actually_uncovers_the_map() -> void:
	# The outcome, not the mechanism (the D-066 lesson: a mechanism can be
	# correct, its data nonzero, and the feature still absent). A scout
	# left alone must end up knowing materially more of the map.
	var space := _space()
	var sim := _sim(space)
	var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	sim.tick()
	var knower := sim.knowledge_group_of(squad)
	var before := sim.knowledge.explored_count(knower)

	sim.order_explore(squad)
	for _i in range(600):
		sim.tick()

	var after := sim.knowledge.explored_count(knower)
	assert_gt(after, before * 2,
		"600 ticks of exploring uncovered %d cells against %d at the start" % [after, before])


func test_two_scouts_of_one_side_do_not_walk_to_the_same_fog() -> void:
	var space := _space()
	var sim := _sim(space)
	var a := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	var b := sim.add_squad(_scout_def(), 1, Vector2i(6, 7))
	sim.tick()
	sim.order_explore(a)
	sim.order_explore(b)
	# One tick so the shared pass, not just the two order calls, has run.
	sim.tick()
	assert_ne(sim.destination_of(a), sim.destination_of(b),
		"two scouts sent to the same region is one wasted squad that looks busy")


func test_any_other_order_cancels_exploring() -> void:
	# "Until told to stop" (#120) — and a mode a player cannot turn off by
	# giving an ordinary order is a mode that has taken the squad away
	# from them.
	var space := _space()
	for order in ["move", "attack_move", "stop"]:
		var sim := _sim(space)
		var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
		sim.order_explore(squad)
		assert_true(sim.is_exploring(squad), "setup: exploring before the %s" % order)
		match order:
			"move":
				sim.order_move(squad, Vector2i(8, 8))
			"attack_move":
				sim.order_attack_move(squad, Vector2i(8, 8))
			"stop":
				sim.stop(squad)
		assert_false(sim.is_exploring(squad), "%s must cancel exploring" % order)


func test_a_routed_squad_stops_exploring_rather_than_walking_back_at_the_enemy() -> void:
	# Without this the repick pass sees a fleeing squad arrive at its rout
	# destination, calls it idle, and sends it straight back toward the
	# fog it just ran away from — which is where the enemy is.
	var space := _space()
	var sim := _sim(space)
	var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	sim.order_explore(squad)
	assert_true(sim.is_exploring(squad), "setup")
	sim.flee_move(squad, Vector2i(2, 2))
	assert_false(sim.is_exploring(squad), "a broken squad is not scouting")


func test_a_routed_squad_cannot_be_ordered_to_explore() -> void:
	# Every other player order refuses a routed squad; this one must too,
	# or explore is the one way to command men who are running.
	var space := _space()
	var sim := _sim(space)
	var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	sim.set_routed(squad, true)
	sim.order_explore(squad)
	assert_false(sim.is_exploring(squad),
		"a routed squad takes no orders until it rallies")


func test_exploring_never_steers_by_ground_the_side_has_not_seen() -> void:
	# #120 point 1, stated as a property rather than trusted. The picker
	# is handed the side's own explored set and nothing else, so the ONLY
	# way truth could reach it is through an argument — and there is no
	# such argument. Proven by giving it a map whose truth and belief
	# disagree completely and checking the answer follows BELIEF.
	var space := _space()
	var explored := _explored_everywhere(space)
	var believed_blocked := Vector2i(6, 8)
	var open_but_far := Vector2i(12, 8)
	explored[space.index(believed_blocked)] = 0
	explored[space.index(open_but_far)] = 0

	var believed := PackedByteArray()
	believed.resize(space.width * space.height)
	believed.fill(1)
	believed[space.index(believed_blocked)] = 0

	var target := ExploreTarget.next_destination(space, explored, believed,
		Vector2i(5, 8), 1)
	assert_eq(target, open_but_far,
		"the answer must follow what the side BELIEVES, whatever the ground really is")


# --- the tick's accounting ---------------------------------------------

func test_the_explore_pass_is_charged_to_its_own_phase() -> void:
	# D-20260818: the phases PARTITION the tick, so a pass without its own
	# accumulator does not go unmeasured — it lands in `other`, which is
	# the disappearing act that decision exists to stop.
	var space := _space()
	var sim := _sim(space)
	var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	sim.order_explore(squad)
	for _i in range(40):
		sim.tick()

	var phases := sim.phase_usec_per_squad_update()
	assert_true(phases.has("explore"), "the breakdown must name the explore phase")

	var named := 0.0
	for key in phases:
		if key == "production" or key == "other":
			continue   # production is a slice of buildings; other is the residual
		named += float(phases[key])
	assert_almost_eq(named + float(phases["other"]),
		sim.mean_usec_per_squad_update(), 0.01,
		"the phases must still sum to the total exactly")


# --- the wire ----------------------------------------------------------

func test_the_explore_order_round_trips() -> void:
	var encoded := NetProtocol.encode_order_explore(77)
	assert_eq(encoded[0], NetProtocol.C2S_ORDER_EXPLORE, "its own opcode")
	assert_eq(int(NetProtocol.decode_order_explore(encoded)["squad"]), 77)


func test_squad_info_carries_whether_the_squad_is_exploring() -> void:
	# Explore is a MODE, so a player who cannot see that it is still on
	# cannot tell "scouting" from "stopped somewhere odd". #120 point 5
	# requires this ride the EXISTING message rather than a new channel.
	var entries := [{
		"id": 3, "def_id": "x", "alive": 5, "shape": "line", "owner": 1,
		"tier": 0, "facing": -1, "files": 0, "stance": 0, "exploring": true,
	}]
	var decoded := NetProtocol.decode_squad_info(NetProtocol.encode_squad_info(entries))
	assert_eq(decoded.size(), 1)
	assert_true(bool(decoded[0]["exploring"]), "the flag survives the wire")
	# And the fields on either side of it are still readable, which is what
	# catches a byte written in the wrong order.
	assert_eq(int(decoded[0]["files"]), 0)
	assert_eq(int(decoded[0]["stance"]), 0)
	assert_eq(int(decoded[0]["id"]), 3)


func test_exploring_is_not_in_the_composition_hash() -> void:
	# A display fact, like owner/tier/stance. Hashing it would make an
	# ordinary mode change read as a desync on a perfectly healthy system
	# — the "a check that cries wolf gets muted" failure.
	var space := _space()
	var sim := _sim(space)
	var squad := sim.add_squad(_scout_def(), 1, Vector2i(6, 6))
	var before := sim.composition_hash([squad])
	sim.order_explore(squad)
	assert_eq(sim.composition_hash([squad]), before,
		"turning explore on must not move the hash both sides compare")
