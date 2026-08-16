extends GutTest

## Guards D-097 — a cliff is the passability boundary, drawn.
##
## The rule the whole feature rests on is that the wall is a DRAWING of the
## predicate the flow field already routes around, never a second prettier one.
## Two definitions of "where walking stops" that could disagree is how this
## project has been bitten before, so the first test here is simply that
## `passable` and the class the mesher steps between are the same predicate.
##
## The risk the feature introduces is stated in D-097 and bounded here: the
## ground sampler now has a discontinuity, and soldiers spill slightly outside
## their squad's cell. If a sampler call near a cliff ever returned the height
## of the ground ABOVE it, an army would climb the mountainside it cannot walk
## on, with every number green.


func _shipped_space() -> TorusSpace:
	var config := load("res://maps/default.tres") as MapConfig
	assert_not_null(config, "maps/default.tres did not load")
	return config.to_space()


## A generator whose features fit a toy map (D-105).
##
## Feature size is a number of CELLS now, not a fraction of the map, so a
## 16-cell-wide map at shipped tuning holds half of one landmass and has no
## passability boundary anywhere on it — nothing to draw a cliff on, and the
## tests below correctly reported proving nothing. A toy map needs toy features,
## so this asks for `TARGET_FEATURE_CELLS`-wide ones explicitly rather than
## inheriting a number calibrated for an 84-cell-wide world.
##
## The alternative was to run these on the shipped map, which is 63x the cells
## and several seconds of `build_fields` per test for no extra coverage: what is
## under test is the SKIRT, and a skirt does not know how big its map is.
const TARGET_FEATURE_CELLS := 4.0


func _toy_terrain(space: TorusSpace) -> TerrainGen:
	var terrain := TerrainGen.new()
	terrain.elevation_frequency = TerrainGen.REFERENCE_WIDTH / TARGET_FEATURE_CELLS
	terrain.moisture_frequency = terrain.elevation_frequency
	assert_gt(TerrainGen.effective_frequency(space, terrain.elevation_frequency), 2.0,
		"a toy map must still hold at least a couple of features, or these tests prove nothing")
	return terrain


# --- one predicate, drawn ------------------------------------------------


func test_the_class_the_mesher_steps_between_is_passability_itself() -> void:
	var space := _shipped_space()
	var terrain := TerrainGen.new()
	var fields := terrain.build_fields(space)
	var passable := terrain.passability(space)

	assert_eq(fields.cliff_class.size(), space.cell_count())
	for i in range(space.cell_count()):
		var walkable := fields.cliff_class[i] == int(TerrainGen.CliffClass.LAND)
		assert_eq(walkable, passable[i] == 1,
			"cell %d: the drawn class and the pathed predicate disagree, so the "
				% i + "cliff would stand somewhere the flow field does not stop")


## Water and mountain are both impassable, and must NOT share a class: a corner
## where a lake meets a peak would otherwise average sea level with rock and
## hang the surface halfway up the mountainside.
func test_water_and_mountain_are_different_classes() -> void:
	assert_ne(TerrainGen.cliff_class_of(TerrainGen.Biome.WATER),
		TerrainGen.cliff_class_of(TerrainGen.Biome.PEAK))
	assert_eq(TerrainGen.cliff_class_of(TerrainGen.Biome.DEEP_WATER),
		TerrainGen.cliff_class_of(TerrainGen.Biome.WATER))
	assert_eq(TerrainGen.cliff_class_of(TerrainGen.Biome.MOUNTAIN),
		TerrainGen.cliff_class_of(TerrainGen.Biome.PEAK))
	for biome in [TerrainGen.Biome.BEACH, TerrainGen.Biome.GRASSLAND,
			TerrainGen.Biome.DRY_GRASSLAND, TerrainGen.Biome.FOREST]:
		assert_eq(TerrainGen.cliff_class_of(biome), TerrainGen.CliffClass.LAND,
			"biome %d must be walkable ground" % biome)


# --- the corner pairing, checked geometrically ---------------------------


## `TerrainChunk.edge_corners` says which corner index each side of a shared
## edge files the same physical point under, and the skirt reads both sides'
## heights through it. The arithmetic is a rotation of a reflection and reads
## like a typo either way, so it is checked against the actual positions.
func test_edge_corners_names_corners_that_coincide() -> void:
	var space := TorusSpace.new(16, 8)
	var cell := Vector2i(5, 3)
	for direction in range(6):
		var neighbour := cell + TorusSpace.DIRECTIONS[direction]
		for pair in TerrainChunk.edge_corners(direction):
			var ours := _corner_world(space, cell, int(pair[0]))
			var theirs := _corner_world(space, neighbour, int(pair[1]))
			assert_lt(ours.distance_to(theirs), 0.001,
				"direction %d: our corner %d and their corner %d are %.3f apart, "
					% [direction, pair[0], pair[1], ours.distance_to(theirs)]
				+ "so a skirt built from them would read the wrong heights")


## The same claim for `TerrainGen.corner_partners`, which the corner normal uses.
func test_corner_partners_names_corners_that_coincide() -> void:
	var space := TorusSpace.new(16, 8)
	var cell := Vector2i(4, 4)
	for corner in range(6):
		var partners := TerrainGen.corner_partners(corner)
		var here := _corner_world(space, cell, corner)
		var a := cell + TorusSpace.DIRECTIONS[posmod(1 - corner, 6)]
		var b := cell + TorusSpace.DIRECTIONS[posmod(-corner, 6)]
		assert_lt(here.distance_to(_corner_world(space, a, partners.x)), 0.001,
			"corner %d: partner .x is the wrong corner of the (1-k) neighbour"
				% corner)
		assert_lt(here.distance_to(_corner_world(space, b, partners.y)), 0.001,
			"corner %d: partner .y is the wrong corner of the (-k) neighbour"
				% corner)


static func _corner_world(space: TorusSpace, cell: Vector2i, corner: int) -> Vector3:
	var angle := TAU * (float(corner) / 6.0) - PI / 6.0
	return space.axial_offset_to_world(Vector2(cell)) + Vector3(
		space.hex_size * cos(angle), 0.0, space.hex_size * sin(angle))


# --- the skirt exists, on the SHIPPED map --------------------------------


## The failure this project keeps paying for: the mechanism is correct, the
## shipped numbers do nothing, and every other line of output looks healthy.
## D-097's first attempt drew 87 faces on the whole 8,064-cell map because the
## natural step at a passability boundary is a fifth of a world unit.
func test_the_shipped_map_draws_a_non_trivial_number_of_cliffs() -> void:
	var space := _shipped_space()
	var stats := TerrainChunk.build_all(space, TerrainGen.new(), 16)
	var quads := int(stats["cliff_quads"])
	gut.p("cliff faces on the shipped map: %d" % quads)
	assert_gt(quads, 200,
		"only %d cliff faces on the whole shipped map — the mechanism is built "
			% quads + "and the ground still has no visible edge anywhere")


## A cliff must be somewhere a squad's route stops, not merely somewhere steep.
## Every skirt is checked against `passability` itself: the two cells whose
## shared edge it stands on must differ in class.
func test_every_cliff_stands_on_a_passability_boundary() -> void:
	var space := TorusSpace.new(16, 8)
	var terrain := _toy_terrain(space)
	var fields := terrain.build_fields(space)

	var boundary_edges := 0
	var same_class_steps := 0
	for i in range(space.cell_count()):
		for direction in range(6):
			var j := space.neighbor_index(i, direction)
			var stepped := false
			for pair in TerrainChunk.edge_corners(direction):
				var mine := fields.height(i, 1 + int(pair[0]))
				var yours := fields.height(j, 1 + int(pair[1]))
				if absf(mine - yours) > TerrainChunk.SKIRT_EPSILON:
					stepped = true
			if not stepped:
				continue
			if fields.cliff_class[i] == fields.cliff_class[j]:
				same_class_steps += 1
			else:
				boundary_edges += 1

	assert_eq(same_class_steps, 0,
		"%d edges step between two cells of the SAME class — the surface is "
			% same_class_steps
		+ "tearing somewhere the simulation sees no boundary at all")
	assert_gt(boundary_edges, 0, "no stepped edges at this seed; nothing proved")


## Every stepped edge gets exactly ONE rock face — no more, no fewer.
##
## Fewer is a hole in the world: the two ground surfaces stop at different
## heights and you see through the gap into the sky. More is invisible, which is
## worse in its own way — two coincident quads cost geometry and z-fight, and
## nothing about the picture says so. Each cell emitting only three of its six
## directions is what makes it exactly one, and that is a constant nothing else
## checks.
func test_every_stepped_edge_gets_exactly_one_rock_face() -> void:
	var space := _shipped_space()
	var terrain := TerrainGen.new()
	var fields := terrain.build_fields(space)

	var stepped := 0
	for i in range(space.cell_count()):
		for direction in range(6):
			var j := space.neighbor_index(i, direction)
			for pair in TerrainChunk.edge_corners(direction):
				if absf(fields.height(i, 1 + int(pair[0]))
						- fields.height(j, 1 + int(pair[1]))) > TerrainChunk.SKIRT_EPSILON:
					stepped += 1
					break
	# Counted from both ends above, so each edge appears twice.
	@warning_ignore("integer_division")
	var edges := stepped / 2

	var drawn := int(TerrainChunk.build_all(space, terrain, 16)["cliff_quads"])
	assert_eq(drawn, edges,
		"%d edges step but %d rock faces were built — a shortfall is a hole you "
			% [edges, drawn]
		+ "can see the sky through, a surplus is two quads in the same place")


# --- the risk D-097 names: the sampler's discontinuity -------------------


## The band test. For every PASSABLE cell, the ground sampler must stay on that
## cell's OWN drawn surface — at its centre and at every one of its six edge
## midpoints, which is where a soldier standing at the edge of its squad's cell
## actually is.
##
## The band is the cell's own seven vertex heights, not a tolerance pulled from
## the air. Ordinary sloping ground already moves the sampler by half a world
## unit between a centre and an edge — the first version of this test used the
## centre height as the datum and failed on plain hillsides, which measured the
## slope rather than the hazard. The hazard is `round_axial` naming the cell on
## the far side of a step: `cliff_rise` is 2.0 world units, so that lands far
## outside the range this asserts.
func test_the_sampler_stays_on_the_walkable_plateau_beside_a_cliff() -> void:
	var space := _shipped_space()
	var terrain := TerrainGen.new()
	var fields := terrain.build_fields(space)
	var surface := fields.surface

	var checked := 0
	var beside_a_cliff := 0

	for i in range(space.cell_count()):
		if fields.passable[i] != 1:
			continue
		var cell := space.from_index(i)
		var centre := space.to_world(cell)

		var low := INF
		var high := -INF
		for vertex in range(TerrainGen.SURFACE_STRIDE):
			var h := surface[i * TerrainGen.SURFACE_STRIDE + vertex]
			low = minf(low, h)
			high = maxf(high, h)

		var cliff_above := -INF
		for direction in range(6):
			var j := space.neighbor_index(i, direction)
			if fields.passable[j] != 1:
				beside_a_cliff += 1
				cliff_above = maxf(cliff_above,
					surface[j * TerrainGen.SURFACE_STRIDE])

		var probes: Array[Vector3] = [centre]
		for corner in range(6):
			# The midpoint of each hex EDGE — the furthest a soldier drifts from
			# its cell while still belonging to it.
			var a := _corner_world(space, Vector2i.ZERO, corner)
			var b := _corner_world(space, Vector2i.ZERO, (corner + 1) % 6)
			probes.append(centre + (a + b) * 0.5 * 0.98)

		for probe in probes:
			var sampled := TerrainChunk.height_at(space, surface, probe.x, probe.z)
			assert_between(sampled, low - 0.001, high + 0.001,
				"cell %s is walkable and drawn between %.3f and %.3f, but the "
					% [cell, low, high]
				+ "sampler returns %.3f at %s — that is another cell's surface"
					% [sampled, probe])
			checked += 1

	assert_gt(checked, 0)
	assert_gt(beside_a_cliff, 100,
		"only %d walkable cells touch impassable ground on the shipped map, so "
			% beside_a_cliff + "this test barely exercised the case it exists for")


## The same hazard stated the blunt way, for the cells where it can bite: a
## soldier standing anywhere in a cell beside a mountain must never be lifted
## onto the mountain's tier.
func test_no_walkable_cell_samples_the_top_of_the_cliff_beside_it() -> void:
	var space := _shipped_space()
	var terrain := TerrainGen.new()
	var fields := terrain.build_fields(space)
	var surface := fields.surface

	var tested := 0
	for i in range(space.cell_count()):
		if fields.passable[i] != 1:
			continue
		var cell := space.from_index(i)
		var centre := space.to_world(cell)
		for direction in range(6):
			var j := space.neighbor_index(i, direction)
			if fields.cliff_class[j] != int(TerrainGen.CliffClass.HIGH):
				continue
			tested += 1
			var top := surface[j * TerrainGen.SURFACE_STRIDE]
			# Half the rise: comfortably above any ordinary slope and
			# comfortably below the mountain tier.
			var ceiling := top - terrain.cliff_rise * 0.5
			for corner in range(6):
				var a := _corner_world(space, Vector2i.ZERO, corner)
				var b := _corner_world(space, Vector2i.ZERO, (corner + 1) % 6)
				var probe := centre + (a + b) * 0.5 * 0.98
				assert_lt(
					TerrainChunk.height_at(space, surface, probe.x, probe.z),
					ceiling,
					"a soldier at the edge of walkable cell %s samples the "
						% cell + "mountain's own tier (%.3f)" % top)
	assert_gt(tested, 0,
		"no walkable cell on the shipped map touches a mountain; the test "
		+ "proved nothing")


# --- the tunables are read ----------------------------------------------


## `cliff_rise` and `cliff_min_step` must both be CONNECTED to something. A
## shipped knob that nothing reads is this project's fourth-most-repeated
## defect, and two of them here would leave the ground exactly as flat as it was
## while the code looked finished.
func test_the_cliff_tunables_change_the_surface() -> void:
	# The SMALLEST SHIPPED map (Skirmish), at shipped tuning, rather than a toy
	# one. `cliff_rise` only has anything to add where the natural step at a
	# passability boundary falls BELOW `cliff_min_step`, and that is a property
	# of the gradient — which since D-105 is a property of feature size in cells
	# and nothing else. Toy features are steep enough that every boundary already
	# clears the threshold on its own, so the rise measurably does nothing and
	# this test would report the defect it exists to catch.
	var space := TorusSpace.new(42, 48)

	var flat := TerrainGen.new()
	flat.cliff_rise = 0.0
	flat.cliff_min_step = 1000.0
	var carved := TerrainGen.new()

	var flat_quads := int(TerrainChunk.build_all(space, flat, 16)["cliff_quads"])
	var carved_quads := int(TerrainChunk.build_all(space, carved, 16)["cliff_quads"])

	assert_eq(flat_quads, 0,
		"a threshold nothing can exceed still produced %d cliffs" % flat_quads)
	assert_gt(carved_quads, 0,
		"the shipped settings produce no cliffs on a Skirmish map")

	# And the rise specifically: with the same threshold, lifting the impassable
	# tier must draw more. The margin is thin on the smallest map — 82 faces
	# against 77 — because most of a coastline clears `cliff_min_step` without
	# any help; it is deterministic rather than close, and setting cliff_rise to
	# 0.0 is exactly what it catches.
	var unlifted := TerrainGen.new()
	unlifted.cliff_rise = 0.0
	var unlifted_quads := int(TerrainChunk.build_all(space, unlifted, 16)["cliff_quads"])
	assert_gt(carved_quads, unlifted_quads,
		"cliff_rise changed nothing: %d cliffs with it, %d without"
			% [carved_quads, unlifted_quads])


## Nothing above the water line may move because of any of this. Elevation and
## passability are the simulation's, and D-097 is a rendering change — the same
## split D-084 established and the reason this could land without touching the
## wire at all.
func test_the_simulation_sees_no_change() -> void:
	var space := _shipped_space()
	var carved := TerrainGen.new()
	var flat := TerrainGen.new()
	flat.cliff_rise = 0.0
	flat.cliff_min_step = 1000.0
	flat.pillow = 1.0

	var a := carved.elevation_field(space)
	var b := flat.elevation_field(space)
	var pa := carved.passability(space)
	var pb := flat.passability(space)
	for i in range(space.cell_count()):
		assert_eq(a[i], b[i], "elevation changed at cell %d" % i)
		assert_eq(pa[i], pb[i], "passability changed at cell %d" % i)
