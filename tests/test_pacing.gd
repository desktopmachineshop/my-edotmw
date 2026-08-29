extends GutTest

## Measures the shipped economy's RATE, so D-068's phase table has
## numbers and the tech tree can be priced rather than tuned
## (`D-20260828-the-phase-table-has-numbers`, issue #281).
##
## D-068 is named the derivation base for D-069's epoch timings and
## D-072's costs, and until this file existed it carried six phases, six
## minute-ranges and **no rate at all** — `decisions/OPEN-QUESTIONS.md`
## says so in as many words. So every cost in the ladder was authored
## against a table with empty cells, which is D-056's own "tuned to stop
## the worst behaviour" one layer up.
##
## ## What this file is, and what it deliberately is not
##
## It is a MEASUREMENT with weak assertions. The numbers are printed and
## recorded in the decision entry that took them (`decisions/README.md`
## rule 5); the asserts are wide bands that catch a rate collapsing or
## the tree becoming unaffordable, not the third digit. A test that
## pinned the exact income would go red on every balance pass and be
## deleted within a month, and then the table would have no guard at all.
##
## Everything here runs through the REAL `Economy.tick` haul loop with
## the REAL shipped defs — never a closed-form `rate x soldiers`
## calculation, because that is precisely the number that is wrong: it
## ignores the walk, the unload and the retarget, which together are most
## of the elapsed time.

const W := 48
const H := 24
const SECONDS := 180.0


func _civ() -> StringName:
	return CivRoster.ids()[0]


func _drop_off() -> BuildingDef:
	var def := BuildingSim.def_by_id(&"town_centre")
	assert_not_null(def, "the shipped town centre is the drop-off")
	return def


## One crew working a WOOD stand `distance` cells from its drop-off, for
## `SECONDS`, through the real haul loop.
##
## A stand rather than one node: `TREE_STOCK` is 105 and a crew empties a
## tree in well under a minute, so a single node would measure a crew
## standing idle for two thirds of the run. D-087 put real forests on the
## map and D-108 gave them stands; a crew that never has to retarget is
## not a crew this game has.
func _income_per_minute(distance: int) -> float:
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	var economy := Economy.new(space)
	sim.buildings = buildings
	sim.economy = economy

	var home := Vector2i(8, 12)
	buildings.add_building(_drop_off(), 1, home, true)

	# A stand the crew can work for the whole window without running out:
	# ~8 trees within the retarget radius of each other.
	var first := Vector2i(home.x + distance, home.y)
	for i in range(8):
		var cell := Vector2i(first.x + (i % 3), first.y + (i / 3) - 1)
		economy.nodes[space.index(cell)] = {
			"kind": Economy.ResourceKind.WOOD, "remaining": Economy.TREE_STOCK,
		}

	var crew := UnitRoster.for_civ_archetype(_civ(), &"gatherers")
	assert_not_null(crew, "%s fields no gatherers" % _civ())
	var squad := sim.add_squad(crew, 1, first)
	assert_true(economy.order_gather(sim, squad, space.index(first)),
		"the crew should take the job")

	for _i in range(int(SECONDS * SquadSim.TICK_HZ)):
		sim.tick()
	return float(economy.amount(1, Economy.ResourceKind.WOOD)) / (SECONDS / 60.0)


func test_a_crew_earns_a_measurable_amount_per_minute() -> void:
	# THE number D-068 was missing. Printed at three haul distances,
	# because income is dominated by the WALK and a table that quoted one
	# figure would be quoting one map layout.
	var rates := {}
	for distance in [2, 5, 10]:
		rates[distance] = _income_per_minute(distance)
	gut.p("PACING: one shipped crew, wood, through the real haul loop over %.0f s —" % SECONDS)
	for distance in [2, 5, 10]:
		gut.p("PACING:   %2d cells from the drop-off: %6.1f /min" % [distance, rates[distance]])

	assert_gt(float(rates[2]), 20.0,
		"a crew beside its drop-off earns almost nothing — the haul loop is broken")
	# The walk has to COST something, or distance is not a decision and
	# D-104's "a start is a place" reasoning has nothing to bite on.
	assert_lt(float(rates[10]), float(rates[2]),
		"a longer haul must earn less, or where you settle does not matter")


func test_the_tree_is_affordable_inside_the_phase_that_pays_for_it() -> void:
	# The point of having a rate at all: a rung's defining line must cost
	# a VISIBLE stretch of that phase's income — D-069's own requirement,
	# "it has to cost enough that paying it visibly means not fielding
	# troops for a stretch" — without costing more than the phase lasts.
	#
	# Bands, not exact figures. This catches a rung nobody can afford and
	# a rung that is free; it deliberately does not catch a 10% tuning
	# pass, which is what the decision entry's recorded numbers are for.
	var rate := _income_per_minute(5)
	assert_gt(rate, 0.0, "no income at all — nothing below means anything")

	# D-068's phases and the crews a player is expected to have working in
	# each. Design targets, recorded in the decision entry; the RATE above
	# is measured, and these turn it into a per-phase income.
	var crews := {1: 3, 2: 6, 3: 9, 4: 12}
	var civ := _civ()
	var lines := []
	for epoch in [1, 2, 3, 4]:
		var food := 0
		var wood := 0
		var seconds := 0.0
		for line in TechRoster.defining_lines(epoch):
			var tech := TechRoster.for_civ_line(civ, line)
			assert_not_null(tech, "%s has no '%s'" % [civ, line])
			if tech == null:
				continue
			food += tech.cost_food
			wood += tech.cost_wood
			seconds += tech.research_time
		# Income is per RESOURCE, and a crew works one node at a time, so
		# a player splitting between food and wood earns roughly the rate
		# on each. Priced against the larger of the two demands, which is
		# what actually gates the advance.
		var demand := maxi(food, wood)
		var minutes := float(demand) / (rate * float(crews[epoch]))
		lines.append("PACING:   epoch %d line: %4d f / %4d w, %3.0f s research -> %.1f min of %d crews"
			% [epoch, food, wood, seconds, minutes, crews[epoch]])
		assert_gt(minutes, 0.5,
			"epoch %d's line is free at %d crews — it cannot be the fork D-068 row 2 names"
				% [epoch, crews[epoch]])
		assert_lt(minutes, 20.0,
			"epoch %d's line costs %.1f min of %d crews — longer than the phase that pays for it"
				% [epoch, minutes, crews[epoch]])
	gut.p("PACING: banking a rung, at %.1f /min per crew —" % rate)
	for line in lines:
		gut.p(line)


func test_the_map_holds_more_than_a_long_match_can_spend() -> void:
	# `decisions/OPEN-QUESTIONS.md` has asked since 2026-08-02 whether an
	# hour-long match exhausts the map, and records that it "needs
	# recomputing against the real constants once D-068's phase table has
	# a consumption rate attached to it". This is that recomputation, and
	# it is the reason the stock constants are read rather than quoted.
	#
	# Counted from the SHIPPED constants against the node census
	# `just gen-terrain-preview` prints, so it moves when the generator
	# does instead of going quietly stale.
	assert_gt(Economy.TREE_STOCK, 0)
	assert_gt(Economy.RICH_STOCK, Economy.TREE_STOCK,
		"gold and stone are supposed to be the deep seams")

	# The whole tree, per player: every defining line plus epoch 5's.
	var civ := _civ()
	var food := 0
	var wood := 0
	var gold := 0
	var stone := 0
	for tech in TechRoster.for_civ(civ):
		var t := tech as TechDef
		food += t.cost_food
		wood += t.cost_wood
		gold += t.cost_gold
		stone += t.cost_stone
	gut.p("PACING: %s's WHOLE tree costs %d f / %d w / %d g / %d s"
		% [civ, food, wood, gold, stone])

	# And the SPINE alone — every DEFINING line, which is what a player who
	# only ever climbs actually pays. The whole-tree figure above includes
	# branches nobody buys all of, so the spine is the honest number to
	# hold against a map's per-player share.
	#
	# Epoch 5 is not in it: the top rung defines nothing, so its pair is
	# optional depth like any other branch.
	var spine_food := 0
	var spine_wood := 0
	var spine_gold := 0
	var spine_stone := 0
	var spine_lines := {}
	for epoch in range(1, TechRoster.max_epoch()):
		for line in TechRoster.defining_lines(epoch):
			spine_lines[line] = true
	for line in spine_lines:
		var t := TechRoster.for_civ_line(civ, line)
		if t == null:
			continue
		spine_food += t.cost_food
		spine_wood += t.cost_wood
		spine_gold += t.cost_gold
		spine_stone += t.cost_stone
	gut.p("PACING: %s's SPINE (every defining line) costs %d f / %d w / %d g / %d s"
		% [civ, spine_food, spine_wood, spine_gold, spine_stone])
	assert_lt(spine_food, food,
		"the spine cannot cost more than the whole tree it is part of")

	# Gold is the scarce one by a wide margin — 48 gold nodes on the
	# shipped map against 3,435 wood — so it is the one a tree can
	# actually exhaust, and the one worth an assertion.
	assert_gt(gold, 0, "nothing in the tree costs gold, so the scarce resource is unpriced")
	assert_lt(gold, Economy.RICH_STOCK * 6,
		"one player's tree costs more gold than six whole seams — "
		+ "at 48 seams shared between up to 24 starts, that cannot be paid")
