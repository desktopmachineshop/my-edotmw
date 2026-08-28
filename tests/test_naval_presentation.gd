extends GutTest

## Naval stage 8 — presentation, scaffolded against the PINNED interface
## contract (`docs/plans/naval.md` §7.1) while stage 2 is in flight.
##
## Stage 8's three deliverables are "ship height at sea level; minimap
## check; selection over water", and its exit is a rendered frame with
## ships on water, looked at. That frame needs stages 2, 3 and 6; what
## can be settled now is the arithmetic underneath it, and one of the
## three turns out to be nearly free already:
##
## **The drawn sea is flat.** `TerrainGen.build_fields` clamps every
## vertex of a water cell up to `sea_level` before scaling, so a hull in
## OPEN water lands at the right height through the ordinary ground
## sampler with no special case at all. The defect is at the SHORE: a
## water cell that shares corners with land takes those corners' heights,
## so the interpolated surface climbs the beach and lifts a hull out of
## the sea. That is what `water_height` is for, and the test below
## measures the lift rather than asserting it exists.
##
## Everything here is against the contract's own names — `tier_of`
## returning a domain, `DOMAIN_WATER` — so the rebase when stage 2 lands
## is an import, not a rewrite.

const W := 48
const H := 32
## Raised so the toy map has real SEA on it: at the shipped 0.38 a 48x32
## sample of the default preset came out with four open-water cells, and
## a sweep over four cells proves nothing. The rule under test is about
## where the sea is DRAWN, not how much of it there is.
const TEST_SEA_LEVEL := 0.55


func _terrain() -> Dictionary:
	# A real generated map, because the whole question is what the
	# SHIPPED surface does at a coastline. `islands` is the preset this
	# feature exists for.
	var space := TorusSpace.new(W, H, 1.0)
	var terrain := TerrainGen.new()
	terrain.noise_seed = 1337
	terrain.sea_level = TEST_SEA_LEVEL
	var fields := terrain.build_fields(space)
	return {"space": space, "terrain": terrain, "surface": fields.surface,
		"passable": fields.passable}


func _curve_at(space: TorusSpace, cell: Vector2i) -> StateCurve:
	var curve := StateCurve.new()
	curve.append_cell(0.0, cell, space)
	return curve


func _water_cells(world: Dictionary) -> Array:
	var space: TorusSpace = world["space"]
	var terrain: TerrainGen = world["terrain"]
	var out := []
	for i in range(space.cell_count()):
		var cell := space.from_index(i)
		if terrain.elevation_at(space, cell) < terrain.sea_level:
			out.append(cell)
	return out


func _is_shore_water(world: Dictionary, cell: Vector2i) -> bool:
	var space: TorusSpace = world["space"]
	var terrain: TerrainGen = world["terrain"]
	for offset in TorusSpace.disk_offsets(1):
		if offset == Vector2i.ZERO:
			continue
		var neighbour := space.normalize(cell + offset)
		if terrain.elevation_at(space, neighbour) >= terrain.sea_level:
			return true
	return false


# --- ship height at sea level -------------------------------------------

func test_the_drawn_sea_is_already_flat_in_open_water() -> void:
	# The finding that shapes this whole stage: no special case is needed
	# out at sea, because the mesh clamps water vertices to `sea_level`.
	# Asserted so that a future change to `build_fields` which un-clamps
	# them fails HERE, next to the reason, rather than as ships sunk into
	# the seabed in a screenshot.
	var world := _terrain()
	var space: TorusSpace = world["space"]
	var terrain: TerrainGen = world["terrain"]
	var surface: PackedFloat32Array = world["surface"]
	var plane := terrain.sea_level * terrain.height_scale

	var open := 0
	for cell in _water_cells(world):
		if _is_shore_water(world, cell):
			continue
		open += 1
		var at := space.to_world(cell)
		var fractional := space.world_to_axial(at)
		var height := TerrainChunk.height_in_cell(space, surface, fractional,
			space.round_axial(fractional), space.index(cell))
		assert_almost_eq(height, plane, 0.0001,
			"open water at %s is meshed at the sea plane" % cell)
	assert_gt(open, 20, "the test map has open water, or this proves nothing")


func test_a_shore_cell_lifts_a_hull_out_of_the_sea() -> void:
	# The defect stage 8 exists to fix, MEASURED rather than asserted: a
	# water cell that shares corners with land takes their heights, so the
	# ordinary sampler puts a hull above the waterline. If this ever comes
	# back zero the feature is unnecessary and should be deleted, not kept
	# on faith.
	var world := _terrain()
	var space: TorusSpace = world["space"]
	var terrain: TerrainGen = world["terrain"]
	var surface: PackedFloat32Array = world["surface"]
	var plane := terrain.sea_level * terrain.height_scale

	var worst := 0.0
	var shores := 0
	for cell in _water_cells(world):
		if not _is_shore_water(world, cell):
			continue
		shores += 1
		var at := space.to_world(cell)
		var fractional := space.world_to_axial(at)
		var height := TerrainChunk.height_in_cell(space, surface, fractional,
			space.round_axial(fractional), space.index(cell))
		worst = maxf(worst, height - plane)
	assert_gt(shores, 5, "the test map has a coastline")
	gut.p("worst shore lift: %.4f world units above the sea plane" % worst)
	assert_gt(worst, 0.001,
		"a shore water cell really is meshed above the sea plane — that is "
		+ "what `water_height` is for")


func test_a_ship_is_derived_on_the_water_plane_everywhere() -> void:
	var world := _terrain()
	var space: TorusSpace = world["space"]
	var terrain: TerrainGen = world["terrain"]
	var surface: PackedFloat32Array = world["surface"]
	var passable: PackedByteArray = world["passable"]
	var plane := terrain.sea_level * terrain.height_scale

	var checked := 0
	for cell in _water_cells(world):
		var men := Formation.soldier_transforms_sampled(
			_curve_at(space, cell), 0.0, 12, "line", 1.0, space, Callable(),
			-1, passable, 0, NAN, surface, 0.0, plane)
		assert_eq(men.size(), 12, "a hull draws its men at %s" % cell)
		for man in men:
			# `Transform3D.origin` is float32 and the plane is a double, so
			# "equal" here is equal to the precision the transform can
			# hold — not a tolerance on the rule.
			assert_almost_eq(man.origin.y, plane, 0.0001,
				"every man of a ship at %s floats on the plane" % cell)
			checked += 1
	assert_gt(checked, 200, "the sweep really derived ships")


func test_land_squads_are_untouched() -> void:
	# The scaffold must be invisible to everything that exists today. NAN
	# means "not a ship", and NAN is what every caller has always passed
	# by omission.
	var world := _terrain()
	var space: TorusSpace = world["space"]
	var surface: PackedFloat32Array = world["surface"]
	var passable: PackedByteArray = world["passable"]
	for i in range(0, space.cell_count(), 5):
		var curve := _curve_at(space, space.from_index(i))
		var before := Formation.soldier_transforms_sampled(
			curve, 0.0, 12, "line", 1.0, space, Callable(), -1, passable,
			0, NAN, surface, 0.0)
		var after := Formation.soldier_transforms_sampled(
			curve, 0.0, 12, "line", 1.0, space, Callable(), -1, passable,
			0, NAN, surface, 0.0, NAN)
		assert_eq(after.size(), before.size())
		for k in range(before.size()):
			assert_eq(after[k].origin, before[k].origin,
				"cell %d, man %d is where it always was" % [i, k])


func test_a_ship_ignores_the_land_passability_clamp() -> void:
	# The other half of floating: the passability array describes LAND, so
	# clamping a hull against it would drag a ship toward its own centre
	# the moment it overhung a shoal. Asserted at a shore, where the clamp
	# would otherwise bite.
	var world := _terrain()
	var space: TorusSpace = world["space"]
	var terrain: TerrainGen = world["terrain"]
	var surface: PackedFloat32Array = world["surface"]
	var passable: PackedByteArray = world["passable"]
	var plane := terrain.sea_level * terrain.height_scale

	var shore := Vector2i.ZERO
	var found := false
	for cell in _water_cells(world):
		if _is_shore_water(world, cell):
			shore = cell
			found = true
			break
	assert_true(found, "the test map has a shore water cell")

	var curve := _curve_at(space, shore)
	var afloat := Formation.soldier_transforms_sampled(
		curve, 0.0, 24, "line", 1.0, space, Callable(), -1, passable,
		0, NAN, surface, 0.0, plane)
	var clamped := Formation.soldier_transforms_sampled(
		curve, 0.0, 24, "line", 1.0, space, Callable(), -1, passable,
		0, NAN, surface, 0.0)
	var spread_afloat := 0.0
	var spread_clamped := 0.0
	for i in range(afloat.size()):
		spread_afloat = maxf(spread_afloat,
			Vector2(afloat[i].origin.x, afloat[i].origin.z).length())
		spread_clamped = maxf(spread_clamped,
			Vector2(clamped[i].origin.x, clamped[i].origin.z).length())
	assert_gte(spread_afloat, spread_clamped,
		"a hull keeps its full beam; the land clamp can only pull men in")


# --- the client's half --------------------------------------------------

func test_the_client_derives_the_plane_from_the_replicated_settings() -> void:
	# One expression, from the settings both sides generate the world
	# from — not a constant that would drift from the ground the moment a
	# preset moved.
	var state := ClientState.new()
	assert_true(is_nan(state.water_plane_height()),
		"a client with no map has no sea")
	var settings := MapSettings.new()
	settings.sea_level = 0.4
	settings.height_scale = 2.5
	state.map_settings = settings.to_dict()
	assert_almost_eq(state.water_plane_height(), 1.0, 0.0001,
		"sea_level x height_scale, the same product build_fields uses")


func test_only_a_water_squad_floats() -> void:
	var state := ClientState.new()
	var settings := MapSettings.new()
	settings.sea_level = 0.4
	settings.height_scale = 2.5
	state.map_settings = settings.to_dict()
	state.composition[1] = {"def_id": "levy", "alive": 12, "shape": "line",
		"spacing": 1.0, "owner": 1, "tier": ClientState.DOMAIN_GROUND}
	state.composition[2] = {"def_id": "levy", "alive": 12, "shape": "line",
		"spacing": 1.0, "owner": 1, "tier": ClientState.DOMAIN_WATER}
	state.composition[3] = {"def_id": "levy", "alive": 12, "shape": "line",
		"spacing": 1.0, "owner": 1, "tier": ClientState.DOMAIN_WALL_TOP}
	assert_true(is_nan(state._water_height_for(1)), "a land squad does not float")
	assert_almost_eq(state._water_height_for(2), 1.0, 0.0001, "a ship does")
	assert_true(is_nan(state._water_height_for(3)),
		"and a squad on a wall keeps its walkway bump instead")


func test_the_domain_values_match_the_pinned_contract() -> void:
	# `docs/plans/naval.md` §7.1 pins these on `SquadSim`, which stage 2
	# owns. Until it lands there is nothing to import, so they are named
	# here and compared the moment the real ones exist — a deliberately
	# temporary half-check, and the assertion below is what turns live.
	assert_eq(ClientState.DOMAIN_GROUND, 0)
	assert_eq(ClientState.DOMAIN_WALL_TOP, 1)
	assert_eq(ClientState.DOMAIN_WATER, 2)
	var constants: Dictionary = (SquadSim as Script).get_script_constant_map()
	if constants.has("DOMAIN_WATER"):
		assert_eq(int(constants["DOMAIN_WATER"]), ClientState.DOMAIN_WATER,
			"stage 2 has landed and the two definitions must agree")
		assert_eq(int(constants["DOMAIN_GROUND"]), ClientState.DOMAIN_GROUND)
		assert_eq(int(constants["DOMAIN_WALL_TOP"]), ClientState.DOMAIN_WALL_TOP)
	else:
		gut.p("SquadSim.DOMAIN_* not present yet — stage 2 in flight; this "
			+ "assertion goes live on rebase")


# --- minimap and selection ----------------------------------------------

func test_the_minimap_marks_a_squad_whatever_domain_it_is_in() -> void:
	# Stage 8's "minimap check". `squad_marks` reads `composition`, which
	# is where the owner lives (D-20260817) — a ship is a squad, so it is
	# painted like one. Asserted rather than assumed, because "a ship does
	# not appear on the minimap" is exactly the sort of thing that ships.
	var composition := {
		1: {"owner": 1, "tier": ClientState.DOMAIN_GROUND},
		2: {"owner": 2, "tier": ClientState.DOMAIN_WATER},
	}
	var marks := MinimapPaint.squad_marks(composition)
	assert_eq(marks.size(), 2, "both squads are painted")
	var found := false
	for mark in marks:
		if int(mark["squad"]) == 2:
			found = true
			assert_eq(int(mark["owner"]), 2, "and the ship keeps its owner")
	assert_true(found, "the ship is on the minimap")


func test_a_ship_can_be_picked_where_it_is_drawn() -> void:
	# Stage 8's "selection over water". `SelectionPick` ranks by screen
	# distance against an allowance, so what matters is that a ship is a
	# candidate at the height it is DRAWN at — which, floating, is the
	# water plane rather than the seabed under it.
	var chosen := SelectionPick.choose([
		{"id": 7, "distance": 6.0, "allowance": 30.0},
		{"id": 8, "distance": 25.0, "allowance": 30.0},
	], [])
	assert_eq(int(chosen.get("squad", -1)), 7,
		"the nearer hull wins, exactly as a land squad would")
