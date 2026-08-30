extends GutTest

## Guards D-20260830-a-ship-takes-up-its-own-water.
##
## From a playtest (2026-08-30): "the boats are appearing on top of each
## other. It looks like model collision size doesn't match unit visual
## size." Two causes, both invisible to every number, both guarded here:
##
## - Every water def left `formation_spacing` at the schema default of
##   1.0 — a SOLDIER's shoulder spacing — while the hull primitive is a
##   1.5 x 3.0 box (`PrimitiveUnit.HULL_SIZE`). A squad's own hulls
##   interpenetrated by construction, and nothing anywhere tied a def's
##   drawn size to its spacing. The guard below enumerates the CLASS
##   (every def drawn as a hull), per D-106's caveat that a check naming
##   one instance only covers the instance it names.
##
## - `_separate_arrivals` exempted every non-ground tier. The comment
##   said wall-top (D-076) and the condition said `_tier != 0`, written
##   before DOMAIN_WATER existed — so two ship squads sent to one spot
##   settled on ONE CELL with zero clearance. D-060's original "no two
##   settled squads share a centre cell" never applied to water at all.
##   Clearance stays D-20260821's one cell, deliberately: this restores
##   the ground guarantee to ships, it does not re-litigate the owner's
##   call that ally overlap beyond that is resolved at the drawn level.

const W := 24
const H := 12


## The channel fixture from test_naval_domain.gd: land, a wide strip of
## water, land. On a torus a single strip only separates the two shores
## because it is WIDE — that file's own header records the walk-round-
## the-seam trap, and this fixture keeps its proportions.
func _world() -> Dictionary:
	var space := TorusSpace.new(W, H, 1.0)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	for index in range(space.cell_count()):
		var coord := space.from_index(index)
		var wet := coord.x >= 4 and coord.x < 20
		passable[index] = 0 if wet else 1
		navigable[index] = 1 if wet else 0
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.buildings = BuildingSim.new(space)
	sim.set_passable(passable)
	sim.set_navigable(navigable)
	return {"sim": sim, "space": space}


func _hull() -> UnitDef:
	var d := UnitRoster.for_civ_archetype(&"gravesworn", &"warship")
	assert_not_null(d, "Setup: a civ fields a warship")
	return d


# --- 1. the data half: a hull's spacing clears the hull ----------------

func test_every_hull_def_spaces_at_least_a_hull_apart() -> void:
	# The hull rotates with the squad's facing, so the spacing that
	# guarantees two neighbouring slots never interpenetrate at ANY
	# facing is the hull's horizontal diagonal, not its length.
	var clearance := Vector2(
		PrimitiveUnit.HULL_SIZE.x, PrimitiveUnit.HULL_SIZE.z).length()
	var hulls := 0
	for def in UnitRoster.load_all():
		if def.mesh_primitive != "hull":
			continue
		hulls += 1
		assert_gte(def.formation_spacing, clearance,
			"%s is drawn as a %.1f-long hull and spaces its slots %.1f apart — "
			% [def.id, PrimitiveUnit.HULL_SIZE.z, def.formation_spacing]
			+ "its own hulls interpenetrate (D-20260830)")
	assert_gt(hulls, 0,
		"Setup: the roster fields hull-drawn defs at all — an empty loop "
		+ "is the vacuous pass D-022's audit block is about")


# --- 2. the sim half: two ship squads do not share a cell --------------

func test_two_ship_squads_sent_to_one_spot_settle_on_different_cells() -> void:
	var w := _world()
	var sim: SquadSim = w["sim"]
	var target := Vector2i(12, 6)
	var a := sim.add_squad(_hull(), 1, Vector2i(8, 6))
	var b := sim.add_squad(_hull(), 1, Vector2i(8, 8))
	sim.order_move(a, target)
	sim.order_move(b, target)
	for _i in range(160):
		sim.tick()
	var cell_a := sim.cell_of(a)
	var cell_b := sim.cell_of(b)
	assert_ne(cell_a, cell_b,
		"two ship squads ordered to one spot settled on ONE cell — the "
		+ "separation pass is exempting DOMAIN_WATER again (D-20260830)")
	assert_true(sim.is_navigable(cell_a),
		"squad a settled on %s, which is not water" % cell_a)
	assert_true(sim.is_navigable(cell_b),
		"a displaced ship must be displaced onto WATER — squad b stands "
		+ "on %s, which is not navigable" % cell_b)


func test_a_lone_ship_is_not_displaced_by_its_own_arrival() -> void:
	# Control: separation now SEES water squads, and a rule that shoves a
	# squad with nobody near it is a different bug wearing this fix.
	var w := _world()
	var sim: SquadSim = w["sim"]
	var target := Vector2i(12, 6)
	var a := sim.add_squad(_hull(), 1, Vector2i(8, 6))
	sim.order_move(a, target)
	for _i in range(160):
		sim.tick()
	assert_eq(sim.cell_of(a), target,
		"a lone ship should settle exactly where it was sent")
