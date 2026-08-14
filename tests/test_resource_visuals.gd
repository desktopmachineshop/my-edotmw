extends GutTest

## Guards the forest-visuals rework: species follow the ground, boundary
## trees fray into the neighbouring region's species, every model id the
## picker can hand out actually exists on disk, and a felled tree's
## animation runs to completion. All pure — ResourceVisuals exists so this
## file needs no GPU (the RenderCull/SelectionPick split, D-045/D-061).

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
		assert_eq(ResourceVisuals.scale_for(cell), ResourceVisuals.scale_for(cell))


func test_standing_pose_stays_in_bounds() -> void:
	for cell in range(200):
		var yaw := ResourceVisuals.yaw_for(cell)
		assert_between(yaw, 0.0, TAU, "yaw out of range")
		var scale := ResourceVisuals.scale_for(cell)
		assert_between(scale, ResourceVisuals.SCALE_MIN, ResourceVisuals.SCALE_MAX,
			"scale out of range")
		assert_lt(ResourceVisuals.SCALE_MAX, 1.0,
			"trees at full model size merge every dense forest into one blob — "
			+ "the source canopies are wider than a cell")
		var axis := ResourceVisuals.tip_axis_for(cell)
		assert_almost_eq(axis.y, 0.0, 0.0001, "a tree tips about a HORIZONTAL axis")
		assert_almost_eq(axis.length(), 1.0, 0.0001)


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
