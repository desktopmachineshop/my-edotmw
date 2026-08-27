extends GutTest

## Guards the drawn-men-vs-resources clearance (D-20260821, amended by the
## 2026-08-27 playtest report "authored models don't adhere to collision
## avoidance with resources").
##
## The defect this pins: a node cell draws a STAND of 1-5 trees on
## jittered ring offsets between ResourceVisuals.MIN_OFFSET (0.34) and
## MAX_OFFSET (0.78) of a hex (D-108) — while the avoidance used to carve
## ONE 0.7 disc at the CELL CENTRE, which guards the one spot a tree can
## never stand and leaves the outer half of every stand bare. The discs
## now come from the SAME tree placements the renderer draws, so this
## file asserts the two agree tree by tree.
##
## `client.gd`'s node lifetime and pure helpers are testable off-tree
## (D-075's 2026-08-16 amendment); `_ready()` never runs because the node
## is never added to a tree.

const WOOD := Economy.ResourceKind.WOOD
const STONE := Economy.ResourceKind.STONE


func _client_with_nodes(cells: Dictionary) -> Node3D:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(
		1, 32, 16, PackedInt32Array([0]), [], 40, 0))
	for cell in cells:
		state.nodes[cell] = cells[cell]
	var client: Node3D = autofree(load("res://client.gd").new())
	client._state = state
	return client


func test_every_drawn_tree_gets_its_own_clearance_disc() -> void:
	var client := _client_with_nodes({100: WOOD})
	var discs: Array = client._node_cell_discs(100)
	var trees: Array = client._node_trees_for(
		100, client._state.space.from_index(100), WOOD)
	assert_eq(discs.size(), trees.size(),
		"one disc per drawn trunk — a count mismatch means the clearance "
		+ "and the picture have drifted apart")
	for i in range(trees.size()):
		var tree_at: Vector3 = (trees[i]["offset"] as Vector3) \
			* client._state.space.hex_size
		var disc: Dictionary = discs[i]
		assert_almost_eq(((disc["offset"] as Vector3) - tree_at).length(), 0.0, 0.0001,
			"disc %d is not centred on the trunk the renderer draws there" % i)
		assert_gt(float(disc["radius"]), 0.2,
			"a clearance a man can stand inside is not a clearance")


func test_the_old_single_centre_disc_could_not_have_covered_the_stands() -> void:
	# The regression shape, asserted against shipped placement data rather
	# than argued: find a real stand with a trunk past the old disc's 0.7
	# rim. MAX_OFFSET is 0.78, so such stands exist by construction — if
	# this ever stops finding one, the placement bounds changed and this
	# whole file should be re-read.
	var client := _client_with_nodes({})
	var found_outside := false
	for cell in range(400):
		client._state.nodes[cell] = WOOD
		for tree in client._node_trees_for(
				cell, client._state.space.from_index(cell), WOOD):
			if (tree["offset"] as Vector3).length() \
					* client._state.space.hex_size > 0.7:
				found_outside = true
				break
		if found_outside:
			break
	assert_true(found_outside,
		"no shipped stand puts a trunk past 0.7 of a hex — then the old "
		+ "centred disc was sufficient and the per-trunk rework is noise")


func test_a_skirted_conifer_clears_wider_than_a_held_canopy() -> void:
	# The second half of the playtest report, found by LOOKING at the
	# first fix's render: every trunk was correctly clear and a soldier
	# still stood waist-deep in a pine, because a conifer's foliage
	# reaches the ground where a broadleaf holds its canopy overhead.
	# docs/playtest/p39-resource-clearance-{before,after}.png is the pair.
	# Straight through the shared static with a FOREST biome: the client
	# helper's null-terrain default is GRASSLAND, whose species pool
	# holds no conifer at all.
	var skirted := 0
	var trunked := 0
	for cell in range(400):
		var trees: Array = ResourceVisuals.trees_for(
			WOOD, TerrainGen.Biome.FOREST, [], 0.5, cell)
		var discs: Array = ResourceVisuals.clearance_discs(
			WOOD, TerrainGen.Biome.FOREST, [], 0.5, cell, 1.0)
		for i in range(trees.size()):
			var model := String(trees[i]["model"])
			var per_scale: float = float(discs[i]["radius"]) \
				/ float(trees[i]["scale"])
			var is_skirted := false
			for species in ResourceVisuals.SKIRTED_SPECIES:
				if model.contains(species):
					is_skirted = true
					break
			if is_skirted:
				skirted += 1
				assert_almost_eq(per_scale, ResourceVisuals.SKIRT_CLEARANCE, 0.001,
					"%s should take the skirt clearance" % model)
			else:
				trunked += 1
				assert_almost_eq(per_scale, ResourceVisuals.TRUNK_CLEARANCE, 0.001,
					"%s should take the trunk clearance" % model)
		if skirted > 0 and trunked > 0:
			break
	assert_gt(skirted, 0, "no skirted conifer in 400 cells — the pools moved")
	assert_gt(trunked, 0, "no broadleaf in 400 cells — the pools moved")


func test_an_ore_seam_keeps_one_wide_centred_disc() -> void:
	# Ore wanders at most ORE_MAX_OFFSET (0.35) and a pile is wider than
	# any trunk; the centred disc was already the truth for it.
	var client := _client_with_nodes({64: STONE})
	var discs: Array = client._node_cell_discs(64)
	assert_eq(discs.size(), 1, "one seam, one disc")
	assert_eq((discs[0]["offset"] as Vector3), Vector3.ZERO)
	assert_almost_eq(float(discs[0]["radius"]), 1.0, 0.001)


func test_the_discs_are_cached_per_cell() -> void:
	# `_nearby_node_discs` runs per squad per frame and a stand needs
	# terrain samples — recomputing per call is the distance()-per-cell
	# family. Same-array identity is the assertion, as the roster cache
	# tests do it.
	var client := _client_with_nodes({7: WOOD})
	var first: Array = client._node_cell_discs(7)
	var second: Array = client._node_cell_discs(7)
	assert_true(is_same(first, second),
		"the per-cell discs are rebuilt per call — terrain sampling on "
		+ "the render loop's hottest path")
