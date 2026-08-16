extends GutTest

## Guards the forest-visuals rework: species follow the ground, boundary
## trees fray into the neighbouring region's species, every model id the
## picker can hand out actually exists on disk, and a felled tree's
## animation runs to completion. All pure — ResourceVisuals exists so this
## file needs no GPU (the RenderCull/SelectionPick split, D-045/D-061).
##
## The placement block at the bottom guards the second half of D-087: a
## node cell grows a STAND of trees on their own offsets, not one tree on
## the lattice point. Those checks can say a forest is off the grid,
## clumped and interlocking; they cannot say it looks like woodland. That
## is `just gen-forest-preview`'s picture, and it is the evidence — this
## defect shipped with every number healthy.

const NO_NEIGHBOURS: Array = []


func test_non_wood_kinds_wear_their_fixed_models() -> void:
	assert_eq(ResourceVisuals.model_for(Economy.ResourceKind.FOOD,
		TerrainGen.Biome.GRASSLAND, NO_NEIGHBOURS, 0.5, 7), &"resource_food")
	assert_eq(ResourceVisuals.model_for(Economy.ResourceKind.GOLD,
		TerrainGen.Biome.DRY_GRASSLAND, NO_NEIGHBOURS, 0.2, 7), &"resource_gold")
	assert_eq(ResourceVisuals.model_for(Economy.ResourceKind.STONE,
		TerrainGen.Biome.GRASSLAND, NO_NEIGHBOURS, 0.5, 7), &"resource_stone")


func test_species_follow_the_ground() -> void:
	# The point of the whole exercise: a desert grows arid types, a forest
	# does not, and neither wears the other's trees.
	for cell in range(200):
		var arid := String(ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.DRY_GRASSLAND, NO_NEIGHBOURS, 0.2, cell))
		assert_true(arid.begins_with("tree_acacia") or arid.begins_with("tree_saguaro"),
			"%s grew on dry ground — arid types only there" % arid)

		var forest := String(ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.7, cell))
		assert_false(forest.begins_with("tree_acacia") or forest.begins_with("tree_saguaro")
			or forest.begins_with("tree_palm"),
			"%s grew in temperate forest — that is desert flora" % forest)

		var beach := String(ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.BEACH, NO_NEIGHBOURS, 0.4, cell))
		assert_true(beach.begins_with("tree_palm"), "%s grew on a beach" % beach)


func test_wet_forest_swaps_toward_willow_and_cypress() -> void:
	var wet := {}
	for cell in range(300):
		wet[ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.9, cell)] = true
	var found_wet := false
	for id in wet:
		if String(id).begins_with("tree_willow") or String(id).begins_with("tree_swamp_cypress"):
			found_wet = true
	assert_true(found_wet, "The wettest forest ground should grow willow or cypress")


func test_a_forest_is_not_a_wall_of_clones() -> void:
	# Variety is the reason 50 variant models exist: many cells of the same
	# biome must spread across species AND numbered variants.
	var seen := {}
	for cell in range(500):
		seen[ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.7, cell)] = true
	assert_gt(seen.size(), 8,
		"only %d distinct models across 500 forest cells — that is wallpaper" % seen.size())


func test_boundary_trees_borrow_the_neighbouring_species() -> void:
	# A grassland cell whose neighbours are all dry ground should sometimes
	# grow the desert's trees — that fraying is what dissolves the hex
	# threshold line — but MOSTLY its own.
	var borrowed := 0
	var own := 0
	var dry_ring: Array = [TerrainGen.Biome.DRY_GRASSLAND, TerrainGen.Biome.DRY_GRASSLAND,
		TerrainGen.Biome.DRY_GRASSLAND, TerrainGen.Biome.DRY_GRASSLAND,
		TerrainGen.Biome.DRY_GRASSLAND, TerrainGen.Biome.DRY_GRASSLAND]
	for cell in range(400):
		var id := String(ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.GRASSLAND, dry_ring, 0.5, cell))
		if id.begins_with("tree_acacia") or id.begins_with("tree_saguaro"):
			borrowed += 1
		else:
			own += 1
	assert_gt(borrowed, 40, "no fraying: the region boundary will be a hard line")
	assert_gt(own, borrowed, "a cell should still mostly grow its OWN region's trees")


func test_water_neighbours_are_never_borrowed() -> void:
	var ring: Array = [TerrainGen.Biome.WATER, TerrainGen.Biome.WATER,
		TerrainGen.Biome.WATER, TerrainGen.Biome.WATER,
		TerrainGen.Biome.WATER, TerrainGen.Biome.WATER]
	for cell in range(200):
		var id := String(ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.GRASSLAND, ring, 0.5, cell))
		assert_true(id.begins_with("tree_oak") or id.begins_with("tree_poplar")
			or id.begins_with("tree_birch") or id.begins_with("tree_willow"),
			"%s: a lakeside tree rolled 'water' and wore something arbitrary" % id)


func test_every_model_the_picker_can_hand_out_exists_on_disk() -> void:
	# The picker builds ids from species-name strings; a typo would fail
	# silently at runtime as capsules (mesh_for returns null on a missing
	# file). Walk every pool crossed with every variant and check the .glb
	# is really there.
	var pools: Array = [ResourceVisuals.FOREST_SPECIES, ResourceVisuals.WET_FOREST_SPECIES,
		ResourceVisuals.GRASS_SPECIES, ResourceVisuals.ARID_SPECIES,
		ResourceVisuals.BEACH_SPECIES]
	for pool in pools:
		for species in pool:
			for variant in range(ResourceVisuals.VARIANTS):
				var path := "res://generated/models/tree_%s_%d.glb" % [species, variant]
				assert_true(ResourceLoader.exists(path) or FileAccess.file_exists(path),
					"%s is missing — the picker will hand out capsules" % path)


func test_the_choice_is_deterministic_per_cell() -> void:
	# Cosmetic, but two clients dressing the same map differently would
	# read as a desync in every bug report. Same inputs, same tree.
	for cell in [0, 17, 100, 9999]:
		assert_eq(
			ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
				TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.7, cell),
			ResourceVisuals.model_for(Economy.ResourceKind.WOOD,
				TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.7, cell))
		assert_eq(ResourceVisuals.yaw_for(cell), ResourceVisuals.yaw_for(cell))
		assert_eq(ResourceVisuals.scale_for(Economy.ResourceKind.WOOD, cell),
			ResourceVisuals.scale_for(Economy.ResourceKind.WOOD, cell))
		# The whole cell, not just one roll of it — the client caches this
		# per chunk and rebuilds a chunk whenever its membership changes, so
		# a rebuild that redressed the cell would shuffle a standing forest.
		assert_eq(
			ResourceVisuals.trees_for(Economy.ResourceKind.WOOD,
				TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.7, cell),
			ResourceVisuals.trees_for(Economy.ResourceKind.WOOD,
				TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.7, cell),
			"the same cell grew a different wood the second time")


func test_standing_pose_stays_in_bounds() -> void:
	for cell in range(200):
		var yaw := ResourceVisuals.yaw_for(cell)
		assert_between(yaw, 0.0, TAU, "yaw out of range")
		var scale := ResourceVisuals.scale_for(Economy.ResourceKind.WOOD, cell)
		assert_between(scale, ResourceVisuals.SCALE_MIN, ResourceVisuals.SCALE_MAX,
			"scale out of range")
		var axis := ResourceVisuals.tip_axis_for(cell)
		assert_almost_eq(axis.y, 0.0, 0.0001, "a tree tips about a HORIZONTAL axis")
		assert_almost_eq(axis.length(), 1.0, 0.0001)


# --- placement ----------------------------------------------------------
#
# A forest read as ranks and files because every tree stood at the exact
# centre of its cell, one apiece: the hex lattice showing through the
# dressing. These are the checks on the two things that fixed it — trees
# stand OFF the lattice point, and a cell grows several of them — plus the
# bounds that keep it a rendering-only change.


func test_no_tree_stands_on_its_cell_centre() -> void:
	# The defect itself. Every tree used to be exactly here, and a player
	# could count along the rows.
	#
	# The floor is asserted as a NUMBER as well as through the constant: a
	# MIN_OFFSET of zero would satisfy "at least MIN_OFFSET from the
	# centre" trivially and put the whole forest back on the lattice.
	assert_gt(ResourceVisuals.MIN_OFFSET, 0.1,
		"trees may stand on the cell centre again — that IS the grid")
	var checked := 0
	for cell in range(400):
		for tree in ResourceVisuals.trees_for(Economy.ResourceKind.WOOD,
				TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.7, cell):
			var offset: Vector3 = tree["offset"]
			assert_almost_eq(offset.y, 0.0, 0.0001,
				"offsets are on the ground plane; the client samples height")
			assert_gte(Vector2(offset.x, offset.z).length(),
				ResourceVisuals.MIN_OFFSET,
				"a tree stood on the lattice point — that is the grid, redrawn")
			checked += 1
	assert_gt(checked, 800, "only %d trees grew over 400 cells" % checked)


func test_a_tree_never_leaves_its_own_cell() -> void:
	# The bound that makes an offset safe without a passability check: a
	# pointy-top hex's inradius is sqrt(3)/2 of hex_size, so a tree inside
	# that radius is on its own cell's ground — it cannot wander onto water
	# or over the cliff next door, and it stays nearer its own cell's
	# centre than any other's, which is what the click test ranks by.
	assert_lt(ResourceVisuals.MAX_OFFSET, sqrt(3.0) / 2.0,
		"trees may now stand outside the cell the node actually occupies")
	assert_lte(ResourceVisuals.ORE_MAX_OFFSET, ResourceVisuals.MAX_OFFSET,
		"ore wanders further than the bound the check below uses")
	for kind in [Economy.ResourceKind.WOOD, Economy.ResourceKind.FOOD,
			Economy.ResourceKind.GOLD, Economy.ResourceKind.STONE]:
		for cell in range(300):
			for tree in ResourceVisuals.trees_for(kind, TerrainGen.Biome.FOREST,
					NO_NEIGHBOURS, 0.7, cell):
				var offset: Vector3 = tree["offset"]
				assert_lte(Vector2(offset.x, offset.z).length(),
					ResourceVisuals.MAX_OFFSET + 0.0001,
					"a tree wandered out of its cell")


func test_a_node_cell_grows_a_stand_not_a_single_tree() -> void:
	# One tree per cell is placement at hex resolution, and no amount of
	# jitter hides a lattice you can count along. Several per cell is the
	# lever that makes a forest denser than the node grid allows.
	var total := 0
	var most := 0
	var alone := 0
	for cell in range(500):
		var trees := ResourceVisuals.trees_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.8, cell)
		total += trees.size()
		most = maxi(most, trees.size())
		if trees.size() == 1:
			alone += 1
		assert_gt(trees.size(), 0, "a node cell drew nothing at all")
		assert_lte(trees.size(), ResourceVisuals.MAX_PER_CELL,
			"a cell blew past MAX_PER_CELL; the client sizes MultiMeshes from this")
	assert_gt(float(total) / 500.0, 2.0,
		"%.2f trees per forest cell — that is still one tree per cell with "
			% (float(total) / 500.0) + "a rounding error")
	# Clumps AND clearings: a uniform three everywhere is the same lattice
	# at a different spacing.
	assert_gt(most, 3, "no cell grew a thicket")
	assert_gt(alone, 20, "no cell grew a lone tree; the wood has no thin patches")


func test_two_trees_in_a_cell_do_not_stack() -> void:
	# Each tree takes its own sector of the cell, so two never land on one
	# spot — which would read as a single fat tree and waste the instance.
	var checked := 0
	for cell in range(400):
		var trees := ResourceVisuals.trees_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.8, cell)
		for i in range(trees.size()):
			for j in range(i + 1, trees.size()):
				assert_gt((trees[i]["offset"] as Vector3).distance_to(
					trees[j]["offset"] as Vector3), 0.1,
					"two trees at the same spot")
				checked += 1
	assert_gt(checked, 200, "no cell held two trees, so this proves nothing")


func test_a_stand_is_not_one_tree_repeated() -> void:
	# Species and variant roll per TREE, not per cell: a cell of four
	# identical models at four sizes is a clone stamp, not a stand.
	var mixed := 0
	var stands := 0
	for cell in range(400):
		var trees := ResourceVisuals.trees_for(Economy.ResourceKind.WOOD,
			TerrainGen.Biome.FOREST, NO_NEIGHBOURS, 0.8, cell)
		if trees.size() < 2:
			continue
		stands += 1
		var seen := {}
		for tree in trees:
			seen[tree["model"]] = true
		if seen.size() > 1:
			mixed += 1
	assert_gt(stands, 100, "not enough multi-tree cells to say anything")
	assert_gt(float(mixed) / float(stands), 0.6,
		"only %.0f%% of stands held more than one model" % (100.0 * mixed / stands))


func test_ore_is_one_seam_that_stays_put() -> void:
	# The contrast that says the count is about CANOPIES overlapping. A
	# seam is one object, it keeps the old size range, and it barely moves:
	# a player clicks a seam to gather from it, and the click test works
	# from the cell, so a boulder drawn most of a cell away would lie about
	# where the node is.
	for kind in [Economy.ResourceKind.GOLD, Economy.ResourceKind.STONE]:
		for cell in range(200):
			var seams := ResourceVisuals.trees_for(kind,
				TerrainGen.Biome.DRY_GRASSLAND, NO_NEIGHBOURS, 0.3, cell)
			assert_eq(seams.size(), 1, "a cell grew a copse of gold seams")
			assert_lte(Vector2(seams[0]["offset"].x, seams[0]["offset"].z).length(),
				ResourceVisuals.ORE_MAX_OFFSET + 0.0001, "a seam wandered")
			assert_between(float(seams[0]["scale"]), ResourceVisuals.ORE_SCALE_MIN,
				ResourceVisuals.ORE_SCALE_MAX, "ore scale out of range")


func test_how_many_trees_grow_follows_the_ground() -> void:
	# The shape of the table, tested where it is a float — through the
	# integer count this would be testing the spread roll instead.
	assert_gt(ResourceVisuals.expected_trees(TerrainGen.Biome.FOREST, 0.7),
		ResourceVisuals.expected_trees(TerrainGen.Biome.GRASSLAND, 0.7),
		"parkland should be thinner than forest")
	assert_gt(ResourceVisuals.expected_trees(TerrainGen.Biome.GRASSLAND, 0.7),
		ResourceVisuals.expected_trees(TerrainGen.Biome.DRY_GRASSLAND, 0.7),
		"dry ground should be the thinnest stand of the three")
	assert_gt(ResourceVisuals.expected_trees(TerrainGen.Biome.FOREST, 0.95),
		ResourceVisuals.expected_trees(TerrainGen.Biome.FOREST, 0.25),
		"wet forest should be the denser one")
	# A wood node can be placed on ground with no entry (a fairness top-up
	# puts one anywhere walkable) and must still grow something.
	assert_gt(ResourceVisuals.expected_trees(TerrainGen.Biome.MOUNTAIN, 0.5), 0.0,
		"a node on unlisted ground drew a bare cell")


func test_canopies_actually_interlock_on_the_shipped_map() -> void:
	# The design claim, against the SHIPPED map, the SHIPPED node placement
	# and the SHIPPED meshes: a canopy should touch its neighbours' rather
	# than sit in its own clear ring. A hard gap around every tree is most
	# of what made a wood read as a grid, and the constants that close it
	# (count, offset, scale) are exactly the ones D-066 warns can be right
	# in mechanism and inert in value.
	var canopy := _mean_canopy_width()
	if canopy <= 0.0:
		pass_test("generated/ not built; no authored canopies to measure")
		return

	var forest := _forest_census()
	var positions: Array = forest["positions"]
	gut.p("%d wood nodes grew %d trees on the shipped map (%.2f per cell); "
		% [forest["cells"], positions.size(), forest["per_cell"]]
		+ "mean canopy %.2f world units" % canopy)
	assert_gt(forest["per_cell"], 2.0,
		"%.2f trees per wood node on the shipped map" % forest["per_cell"])

	# Nearest-neighbour distance per tree, against the canopy width the
	# models actually ship at. Under that, two canopies overlap.
	#
	# Bucketed by canopy width and scanned over the 3x3 neighbourhood, not
	# a pairwise sweep: this runs over every tree on the shipped map, and
	# the pairwise version is the same O(n^2) shape that cost vision 232
	# µs/squad. A neighbour further than one bucket is further than a
	# canopy anyway, which is the only question being asked.
	var buckets := {}
	for i in range(positions.size()):
		var key := _bucket(positions[i], canopy)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)

	var touching := 0
	var lattice := 0
	for i in range(positions.size()):
		var here: Vector2 = positions[i]
		var key := _bucket(here, canopy)
		var nearest := INF
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for j in buckets.get(Vector2i(key.x + dx, key.y + dy), []):
					if i == j:
						continue
					var d := here.distance_to(positions[j] as Vector2)
					nearest = minf(nearest, d)
					if d < 0.001:
						lattice += 1
		if nearest < canopy:
			touching += 1
	var share := float(touching) / maxf(1.0, float(positions.size()))
	gut.p("  %.0f%% of trees have a neighbour inside a canopy width" % (100.0 * share))
	assert_eq(lattice, 0, "two trees drawn at exactly the same world position")
	assert_gt(share, 0.75,
		"only %.0f%% of trees touch a neighbour — the wood still has a hard gap "
			% (100.0 * share) + "around every canopy")


func _bucket(at: Vector2, size: float) -> Vector2i:
	return Vector2i(int(floor(at.x / size)), int(floor(at.y / size)))


## Every wood node the shipped Standard map generates, dressed, as world XZ
## positions. The real map and the real `Economy.generate`, not a fixture:
## a placement rule that looks fine on a hand-made patch and does nothing
## on the map a match actually plays is the defect family this project has
## shipped more than once (D-066).
func _forest_census() -> Dictionary:
	var settings := MapSettings.new()
	var space := settings.to_space()
	var terrain := settings.to_terrain()
	var economy := Economy.new(space)
	economy.generate(terrain)

	var positions: Array = []
	var cells := 0
	for entry in economy.node_entries():
		if int(entry["kind"]) != Economy.ResourceKind.WOOD:
			continue
		var cell := int(entry["cell"])
		var coord := space.from_index(cell)
		var neighbours: Array = []
		for neighbour in space.neighbors(coord):
			neighbours.append(terrain.biome_at(space, neighbour))
		var trees := ResourceVisuals.trees_for(Economy.ResourceKind.WOOD,
			terrain.biome_at(space, coord), neighbours,
			terrain.moisture_at(space, coord), cell)
		cells += 1
		var world := space.to_world(coord)
		for tree in trees:
			var offset: Vector3 = tree["offset"]
			positions.append(Vector2(world.x + offset.x * space.hex_size,
				world.z + offset.z * space.hex_size))
	return {"positions": positions, "cells": cells,
		"per_cell": float(positions.size()) / maxf(1.0, float(cells))}


## How wide an authored tree stands, averaged over the pools, at the middle
## of the shipped scale range. Measured off the meshes rather than written
## down: the whole point is what the game DRAWS, and a number copied from
## the art pipeline would drift the first time a model changed.
func _mean_canopy_width() -> float:
	var total := 0.0
	var count := 0
	for species in ResourceVisuals.FOREST_SPECIES:
		for variant in range(ResourceVisuals.VARIANTS):
			var mesh := UnitMesh.mesh_for(StringName("tree_%s_%d" % [species, variant]))
			if mesh == null:
				continue
			var size := mesh.get_aabb().size
			total += maxf(size.x, size.z)
			count += 1
	if count == 0:
		return 0.0
	return (total / float(count)) \
		* (ResourceVisuals.SCALE_MIN + ResourceVisuals.SCALE_MAX) / 2.0


func test_a_tree_tips_then_sinks_then_finishes() -> void:
	var start := ResourceVisuals.fall_pose(Economy.ResourceKind.WOOD, 0.0)
	assert_almost_eq(float(start["angle"]), 0.0, 0.0001, "a felling starts upright")
	assert_almost_eq(float(start["sink"]), 0.0, 0.0001)
	assert_false(bool(start["done"]))

	var mid := ResourceVisuals.fall_pose(Economy.ResourceKind.WOOD,
		ResourceVisuals.TIP_SECONDS * 0.5)
	assert_between(float(mid["angle"]), 0.01, PI / 2.0 - 0.01, "mid-fall it is leaning")

	var down := ResourceVisuals.fall_pose(Economy.ResourceKind.WOOD,
		ResourceVisuals.TIP_SECONDS)
	assert_almost_eq(float(down["angle"]), PI / 2.0, 0.0001, "the crash ends horizontal")

	var gone := ResourceVisuals.fall_pose(Economy.ResourceKind.WOOD,
		ResourceVisuals.TIP_SECONDS + ResourceVisuals.SINK_SECONDS + 0.1)
	assert_true(bool(gone["done"]), "the animation must END or felled trees leak nodes")
	assert_almost_eq(float(gone["sink"]), ResourceVisuals.SINK_DEPTH, 0.0001)


func test_the_crash_accelerates() -> void:
	# The read of a cut tree: a slow lean and a fast crash. Equal time
	# steps late in the tip must cover more angle than early ones.
	var early := float(ResourceVisuals.fall_pose(Economy.ResourceKind.WOOD,
		ResourceVisuals.TIP_SECONDS * 0.25)["angle"])
	var late := float(ResourceVisuals.fall_pose(Economy.ResourceKind.WOOD,
		ResourceVisuals.TIP_SECONDS)["angle"]) \
		- float(ResourceVisuals.fall_pose(Economy.ResourceKind.WOOD,
			ResourceVisuals.TIP_SECONDS * 0.75)["angle"])
	assert_gt(late, early, "the fall should accelerate, not glide down evenly")


func test_ore_sinks_without_tipping() -> void:
	var mid := ResourceVisuals.fall_pose(Economy.ResourceKind.GOLD, 0.5)
	assert_almost_eq(float(mid["angle"]), 0.0, 0.0001, "a gold seam does not tip over")
	assert_gt(float(mid["sink"]), 0.0)
	assert_true(bool(ResourceVisuals.fall_pose(Economy.ResourceKind.STONE,
		ResourceVisuals.ORE_SINK_SECONDS + 0.1)["done"]))
