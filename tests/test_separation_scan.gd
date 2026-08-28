extends GutTest

## Guards the narrowed separation scan (#304).
##
## `SquadSim._crowded` and `_free_cell_near` used to scan a disk sized by
## `footprint_cells(asking) + widest` — radii inherited from #104, when
## clearance was footprint-based. `D-20260821-a-fight-loosens-a-formation`
## reverted clearance to D-060's flat ONE cell and the radii derived from
## it were not re-read, so a settled line squad walked ~469 offsets per
## tick where 7 could possibly matter.
##
## **Nothing was ever wrong** — an over-scan gives the same answer — which
## is why no test caught it and why the guard here has to be about the
## RELATIONSHIP rather than about any observable behaviour:
##
## - `_clearance_bound()` must bound `_clearance()` over the real roster.
##   If clearance becomes variable again and the bound does not follow,
##   the scan starts MISSING blockers, which is a correctness bug rather
##   than a slow one. That is the failure this file exists to prevent.
## - and separation must still do its job, so the narrowing is checked to
##   have changed the cost and not the outcome.

const W := 24
const H := 12


func _sim() -> SquadSim:
	var space := TorusSpace.new(W, H, 1.0)
	var sim := SquadSim.new(space, CurveReplicator.new())
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)
	sim.set_passable(passable)
	return sim


func test_the_bound_actually_bounds_the_rule() -> void:
	# THE guard. The scan radius is derived from `_clearance_bound()`, so
	# a clearance larger than the bound would be a blocker the scan never
	# looks at — two squads standing inside each other with nothing
	# failing.
	var sim := _sim()
	var defs := UnitRoster.load_all()
	assert_gt(defs.size(), 2, "vacuous with almost no roster")

	var squads: Array[int] = []
	for i in range(mini(defs.size(), 12)):
		squads.append(sim.add_squad(defs[i], 1 + (i % 2), Vector2i(2 + i, 4)))

	var bound: int = sim._clearance_bound()
	assert_gt(bound, 0, "a bound of zero would scan nothing at all")
	for a in squads:
		for b in squads:
			if a == b:
				continue
			assert_lte(sim._clearance(a, b), bound,
				"clearance(%d,%d) exceeds the bound the scan is sized by" % [a, b])


func test_two_squads_on_one_cell_are_still_separated() -> void:
	# The behaviour the narrowing must not have changed. D-060's rule:
	# two settled squads do not share a centre cell.
	var sim := _sim()
	var defs := UnitRoster.load_all()
	var here := Vector2i(8, 6)
	var first := sim.add_squad(defs[0], 1, here)
	var second := sim.add_squad(defs[0], 1, here)
	# Several ticks, not one: separation re-DESTINATIONS the loser and
	# rebuilds its curve, so the squad WALKS to the cell it was given.
	# `cell_of` samples that curve, so a single tick shows it still
	# standing where it was — measured on the pre-change tree too, so this
	# is the mechanism and not the narrowing.
	for _i in range(30):
		sim.tick()
	assert_ne(sim.cell_of(first), sim.cell_of(second),
		"two settled squads must not share a cell")


func test_a_lone_squad_is_left_where_it_stands() -> void:
	# The other half: separation only moves a squad that is actually
	# crowded. A narrower scan that reported crowding where there is none
	# would shove squads around for no reason.
	var sim := _sim()
	var defs := UnitRoster.load_all()
	var here := Vector2i(8, 6)
	var alone := sim.add_squad(defs[0], 1, here)
	for _i in range(30):
		sim.tick()
	assert_eq(sim.cell_of(alone), here,
		"a squad with nobody near it must not be moved")
