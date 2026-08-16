extends GutTest

## Guards ground cover (D-100): the props a cell wears, how many, and the two
## rules that let cosmetic clutter exist at all — a prop never hides a unit,
## and an occupied cell stays clear.
##
## All pure. `GroundCover` exists so this file needs no GPU, the same split as
## `RenderCull`, `SelectionPick` and `ResourceVisuals` (D-045, D-061, D-087).
## The half that DOES need a GPU is the picture `just gen-model-preview`
## writes, which is the evidence no assertion in here can stand in for.
##
## Several checks below run against the SHIPPED standard map and the SHIPPED
## meshes rather than a fixture. A cover mechanism that works on a hand-made
## 4-cell map and yields three props on the real one is the defect family this
## project has hit repeatedly (D-066): mechanism right, shipped numbers inert.

const MANIFEST := "res://generated/manifest.json"

const NO_NEIGHBOURS: Array = []

## A full hex ring of one biome, for the fraying checks.
func _ring(biome: int) -> Array:
	return [biome, biome, biome, biome, biome, biome]


func after_each() -> void:
	# A global knob one test turns down must not leak into the next.
	GroundCover.density_scale = 1.0


func _manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


# --- what grows where ---------------------------------------------------


func test_water_grows_nothing() -> void:
	# The one place cover would be visibly, obviously wrong. Both water
	# biomes, every neighbour combination, across many cells.
	for cell in range(300):
		for biome in [TerrainGen.Biome.WATER, TerrainGen.Biome.DEEP_WATER]:
			assert_eq(GroundCover.props_for(biome, _ring(TerrainGen.Biome.GRASSLAND),
				0.9, 0.2, cell, false).size(), 0,
				"a prop grew on open water")


func test_props_come_from_their_own_biome_palette() -> void:
	# With no neighbours there is nothing to fray into, so every prop must be
	# one this biome actually grows.
	for biome in GroundCover.PALETTES:
		var allowed := {}
		for entry in GroundCover.PALETTES[biome]:
			allowed[entry[0]] = true
		for cell in range(400):
			for prop in GroundCover.props_for(biome, NO_NEIGHBOURS, 0.5, 0.4,
					cell, false):
				assert_true(allowed.has(prop["model"]),
					"%s grew on biome %d, which has no such thing"
						% [prop["model"], biome])


## What may never grow where, written out INDEPENDENTLY of the palettes.
##
## The check above reads `PALETTES` for both the question and the answer, so
## it can only catch a picker that reaches into the wrong row — widen a
## palette wrongly and it agrees with you. This table is the actual design
## claim ("a region reads as a place") in a form that can disagree.
const FORBIDDEN := {
	TerrainGen.Biome.FOREST: [&"prop_cactus", &"prop_reeds", &"prop_shell",
		&"prop_driftwood", &"prop_snow_boulder", &"prop_dry_tussock"],
	TerrainGen.Biome.GRASSLAND: [&"prop_cactus", &"prop_reeds", &"prop_shell",
		&"prop_driftwood", &"prop_snow_boulder"],
	TerrainGen.Biome.DRY_GRASSLAND: [&"prop_fern", &"prop_mushrooms",
		&"prop_reeds", &"prop_shell", &"prop_snow_boulder", &"prop_moss_rock"],
	TerrainGen.Biome.BEACH: [&"prop_cactus", &"prop_fern", &"prop_mushrooms",
		&"prop_snow_boulder", &"prop_log"],
	TerrainGen.Biome.MOUNTAIN: [&"prop_reeds", &"prop_shell", &"prop_cactus",
		&"prop_mushrooms", &"prop_driftwood"],
	TerrainGen.Biome.PEAK: [&"prop_reeds", &"prop_shell", &"prop_cactus",
		&"prop_fern", &"prop_wildflowers", &"prop_driftwood"],
}


func test_a_region_never_grows_another_region_s_flora() -> void:
	for biome in FORBIDDEN:
		var banned := {}
		for model in FORBIDDEN[biome]:
			banned[model] = true
		for cell in range(400):
			for prop in GroundCover.props_for(biome, NO_NEIGHBOURS, 0.5, 0.4,
					cell, false):
				assert_false(banned.has(prop["model"]),
					"%s grew on biome %d — that is another region's flora"
						% [prop["model"], biome])


func test_a_region_is_not_one_prop_repeated() -> void:
	var seen := {}
	for cell in range(500):
		for prop in GroundCover.props_for(TerrainGen.Biome.GRASSLAND,
				NO_NEIGHBOURS, 0.5, 0.4, cell, false):
			seen[prop["model"]] = true
	assert_gt(seen.size(), 2,
		"only %d distinct props across 500 grassland cells — that is a texture, "
			% seen.size() + "not ground cover")


func test_boundary_cells_fray_into_the_neighbouring_region() -> void:
	# A grassland cell ringed by dry ground should sometimes grow the dry
	# palette — that fraying is what dissolves the hex the moisture threshold
	# happens to cross — but MOSTLY its own.
	var borrowed := 0
	var own := 0
	var dry := {}
	for entry in GroundCover.PALETTES[TerrainGen.Biome.DRY_GRASSLAND]:
		dry[entry[0]] = true
	var grass := {}
	for entry in GroundCover.PALETTES[TerrainGen.Biome.GRASSLAND]:
		grass[entry[0]] = true

	for cell in range(400):
		for prop in GroundCover.props_for(TerrainGen.Biome.GRASSLAND,
				_ring(TerrainGen.Biome.DRY_GRASSLAND), 0.5, 0.4, cell, false):
			# prop_boulder is in both palettes; it settles neither question.
			if dry.has(prop["model"]) and not grass.has(prop["model"]):
				borrowed += 1
			elif grass.has(prop["model"]) and not dry.has(prop["model"]):
				own += 1
	assert_gt(borrowed, 50, "no fraying: the region boundary will be a hard line")
	assert_gt(own, borrowed, "a cell should still mostly grow its OWN region's props")


func test_a_water_neighbour_is_never_borrowed() -> void:
	# A shoreline cell rolling "deep water" must fall back to its own palette,
	# not come up empty — the same hole ResourceVisuals had to close.
	var allowed := {}
	for entry in GroundCover.PALETTES[TerrainGen.Biome.BEACH]:
		allowed[entry[0]] = true

	var beside_water := 0
	var alone := 0
	for cell in range(300):
		var props := GroundCover.props_for(TerrainGen.Biome.BEACH,
			_ring(TerrainGen.Biome.DEEP_WATER), 0.4, 0.4, cell, false)
		beside_water += props.size()
		alone += GroundCover.props_for(TerrainGen.Biome.BEACH, NO_NEIGHBOURS,
			0.4, 0.4, cell, false).size()
		for prop in props:
			assert_true(allowed.has(prop["model"]),
				"%s appeared on a beach ringed by water" % prop["model"])
	# Equality, not "some survived": a borrow that rolls water and finds no
	# palette must fall BACK, not drop the prop. Counting loosely here would
	# have passed a version that silently thinned every shoreline by a third.
	assert_eq(beside_water, alone,
		"a beach ringed by water grew less cover than the same beach inland")


func test_borrowing_species_does_not_borrow_density() -> void:
	# A beach beside a forest should grow the odd fern, not a forest's worth
	# of them: the count is always the cell's OWN ground.
	var beside_forest := 0
	var alone := 0
	for cell in range(400):
		beside_forest += GroundCover.props_for(TerrainGen.Biome.BEACH,
			_ring(TerrainGen.Biome.FOREST), 0.5, 0.4, cell, false).size()
		alone += GroundCover.props_for(TerrainGen.Biome.BEACH,
			NO_NEIGHBOURS, 0.5, 0.4, cell, false).size()
	assert_eq(beside_forest, alone,
		"a beach next to a forest grew a forest's density of cover")


# --- the two gameplay rules ---------------------------------------------


func test_an_occupied_cell_gets_no_cover() -> void:
	# A node, a building or a wall stands here. The caller decides that — a
	# pure module has no business reading simulation state — so what is
	# checked is that the answer is actually USED.
	var bare := 0
	for cell in range(200):
		assert_eq(GroundCover.props_for(TerrainGen.Biome.FOREST, NO_NEIGHBOURS,
			0.8, 0.4, cell, true).size(), 0,
			"cover grew on a cell that already holds something")
		bare += GroundCover.props_for(TerrainGen.Biome.FOREST, NO_NEIGHBOURS,
			0.8, 0.4, cell, false).size()
	assert_gt(bare, 400,
		"the same cells grew nothing when unoccupied either, so the check above "
			+ "proves nothing")


func test_no_prop_can_hide_a_soldier() -> void:
	# Unit readability is tactical information (D-045). Asserted against the
	# SHIPPED meshes at BOTH ends: every authored prop's real bounding box at
	# maximum scale, against the shortest authored soldier the game ships.
	var manifest := _manifest()
	if manifest.is_empty():
		pass_test("generated/ not built; no cover without models (D-100)")
		return

	var shortest_soldier := INF
	for def in UnitRoster.load_all():
		if def.model_id == &"":
			continue
		var mesh := UnitMesh.mesh_for(def.model_id)
		if mesh != null:
			shortest_soldier = minf(shortest_soldier, mesh.get_aabb().size.y)
	assert_lt(shortest_soldier, INF, "no authored soldier to compare against")

	var props: Dictionary = manifest.get("props", {})
	assert_gt(props.size(), 0, "the manifest lists no props at all")
	for model_id in props:
		var mesh := UnitMesh.mesh_for(StringName(model_id))
		assert_not_null(mesh, "%s is in the manifest but did not load" % model_id)
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		var standing := aabb.size.y * GroundCover.SCALE_MAX
		assert_lte(standing, GroundCover.MAX_PROP_HEIGHT,
			"%s stands %.2f at full scale, over GroundCover.MAX_PROP_HEIGHT"
				% [model_id, standing])
		assert_lt(standing, shortest_soldier * 0.4,
			"%s stands %.2f against a %.2f soldier — cover that tall hides units"
				% [model_id, standing, shortest_soldier])

		# The generator settles every model onto y=0 and the placement module
		# assumes it: a prop authored floating hovers over the whole map.
		assert_almost_eq(aabb.position.y, 0.0, 0.01,
			"%s does not sit on its own base" % model_id)
		# And the manifest's recorded height must be the mesh's real one, or
		# the build-time height gate is guarding a number nobody ships.
		assert_almost_eq(aabb.size.y, float(props[model_id].get("height", -1.0)),
			0.01, "%s: manifest height disagrees with the built mesh" % model_id)


func test_a_prop_renders_the_colour_it_was_painted() -> void:
	# One palette across the whole game, not one per asset pipeline.
	#
	# Props are the only models here whose colour arrives as a glTF MATERIAL —
	# they must, because they are drawn from a MultiMesh and a MultiMesh
	# overrides the vertex COLOR every other authored model relies on. That
	# path is not colour-neutral: Godot's importer converts baseColorFactor
	# linear -> sRGB and nothing converts it back, so an authored 0.36 arrived
	# as albedo 0.63 and every fern rendered frosted next to ground painted
	# with the same numbers. `art/lib/bake.py` pre-compensates; this is what
	# says it still does.
	var manifest := _manifest()
	if manifest.is_empty():
		pass_test("generated/ not built")
		return

	var checked := 0
	for model_id in manifest.get("props", {}):
		var authored: Array = manifest["props"][model_id].get("colours", [])
		var mesh := UnitMesh.mesh_for(StringName(model_id))
		if mesh == null:
			continue
		assert_eq(mesh.get_surface_count(), authored.size(),
			"%s: one surface per authored colour" % model_id)
		for surface in range(mini(mesh.get_surface_count(), authored.size())):
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			assert_not_null(material, "%s surface %d has no material"
				% [model_id, surface])
			if material == null:
				continue
			var want: Array = authored[surface]
			# 2/255 of tolerance: enough for the round trip through the glTF
			# float and back, nowhere near enough to hide a transfer function.
			for channel in range(3):
				assert_almost_eq(material.albedo_color[channel],
					float(want[channel]), 0.008,
					"%s surface %d channel %d: painted %.3f, imported %.3f"
						% [model_id, surface, channel, float(want[channel]),
							material.albedo_color[channel]])
			checked += 1
	assert_gt(checked, 20, "only %d prop surfaces were checked" % checked)


func test_shipped_props_stay_inside_the_prop_triangle_budget() -> void:
	var manifest := _manifest()
	if manifest.is_empty():
		pass_test("generated/ not built")
		return
	# Matches art/scatter/props.py's TRIANGLE_BUDGET. Tens of thousands of
	# these are drawn at once, so this is throughput, not tidiness.
	const PROP_TRIANGLE_BUDGET := 80
	var props: Dictionary = manifest.get("props", {})
	for model_id in props:
		assert_lte(int(props[model_id].get("triangles", 0)), PROP_TRIANGLE_BUDGET,
			"%s is over the prop triangle budget" % model_id)


func test_every_model_a_palette_names_was_actually_built() -> void:
	# A palette naming a model nobody generated is cover that silently thins
	# out in exactly one biome — nothing errors, the picture is just wrong.
	if _manifest().is_empty():
		pass_test("generated/ not built")
		return
	var ids := GroundCover.model_ids()
	assert_gt(ids.size(), 8, "only %d distinct props ship" % ids.size())
	for model_id in ids:
		var path := "res://generated/models/%s.glb" % model_id
		assert_true(ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"%s is named by a palette and does not exist" % path)


func test_every_built_prop_is_actually_used_by_a_palette() -> void:
	# The other direction, and the one that catches the declared-and-unread
	# family: a prop generated, committed, and reachable from nothing.
	var manifest := _manifest()
	if manifest.is_empty():
		pass_test("generated/ not built")
		return
	var used := {}
	for model_id in GroundCover.model_ids():
		used[String(model_id)] = true
	for model_id in manifest.get("props", {}):
		assert_true(used.has(model_id),
			"%s is built and committed and no palette can ever place it" % model_id)


# --- placement ----------------------------------------------------------


func test_placement_stays_inside_its_own_cell() -> void:
	for cell in range(300):
		for prop in GroundCover.props_for(TerrainGen.Biome.FOREST,
				NO_NEIGHBOURS, 0.8, 0.3, cell, false):
			var offset: Vector3 = prop["offset"]
			assert_almost_eq(offset.y, 0.0, 0.0001,
				"offsets are on the ground plane; the client samples height")
			assert_lte(Vector2(offset.x, offset.z).length(), GroundCover.MAX_OFFSET,
				"a prop wandered outside its cell and into its neighbour's")
			assert_between(float(prop["yaw"]), 0.0, TAU, "yaw out of range")
			assert_between(float(prop["scale"]), GroundCover.SCALE_MIN,
				GroundCover.SCALE_MAX, "scale out of range")


func test_props_in_a_cell_do_not_stack() -> void:
	# Every prop of a cell rolls its own position, so two never share one
	# spot — which would read as a single prop and waste the instance.
	var checked := 0
	for cell in range(400):
		var props := GroundCover.props_for(TerrainGen.Biome.FOREST,
			NO_NEIGHBOURS, 0.8, 0.3, cell, false)
		for i in range(props.size()):
			for j in range(i + 1, props.size()):
				var a: Vector3 = props[i]["offset"]
				var b: Vector3 = props[j]["offset"]
				assert_gt(a.distance_to(b), 0.001, "two props at the same spot")
				checked += 1
	assert_gt(checked, 100, "no cell held two props, so this proves nothing")


func test_the_dressing_is_deterministic() -> void:
	# Cosmetic and unreplicated, so nothing enforces agreement between two
	# clients except this being a pure function of the cell.
	for cell in [0, 17, 100, 8063]:
		var a := GroundCover.props_for(TerrainGen.Biome.GRASSLAND,
			_ring(TerrainGen.Biome.FOREST), 0.55, 0.5, cell, false)
		var b := GroundCover.props_for(TerrainGen.Biome.GRASSLAND,
			_ring(TerrainGen.Biome.FOREST), 0.55, 0.5, cell, false)
		assert_eq(a, b, "the same cell dressed itself twice differently")


# --- density ------------------------------------------------------------


func test_density_follows_moisture_and_exposure() -> void:
	var dry_forest := GroundCover.density_for(TerrainGen.Biome.FOREST, 0.30, 0.5)
	var wet_forest := GroundCover.density_for(TerrainGen.Biome.FOREST, 0.95, 0.5)
	assert_gt(wet_forest, dry_forest, "wet forest floor should be the lusher one")

	var low := GroundCover.density_for(TerrainGen.Biome.GRASSLAND, 0.5, 0.10)
	var high := GroundCover.density_for(TerrainGen.Biome.GRASSLAND, 0.5, 0.95)
	assert_gt(low, high, "exposed high ground should be barer than sheltered low")

	assert_eq(GroundCover.density_for(TerrainGen.Biome.WATER, 0.9, 0.2), 0.0)
	assert_gt(GroundCover.density_for(TerrainGen.Biome.FOREST, 0.7, 0.4),
		GroundCover.density_for(TerrainGen.Biome.PEAK, 0.7, 0.9),
		"a peak should be barer than a forest floor")


func test_the_density_knob_is_wired_to_something() -> void:
	# A tunable nothing reads is this project's fourth-most-repeated defect.
	var full := _count_over(300, 1.0)
	var half := _count_over(300, 0.5)
	var off := _count_over(300, 0.0)
	assert_gt(full, 0, "no cover at all at the shipped setting")
	assert_lt(half, full, "halving density changed nothing")
	assert_eq(off, 0, "density_scale = 0 still grew cover")


func _count_over(cells: int, scale: float) -> int:
	GroundCover.density_scale = scale
	var total := 0
	for cell in range(cells):
		total += GroundCover.props_for(TerrainGen.Biome.FOREST, NO_NEIGHBOURS,
			0.8, 0.4, cell, false).size()
	GroundCover.density_scale = 1.0
	return total


func test_a_cell_never_exceeds_the_hard_cap() -> void:
	GroundCover.density_scale = 20.0
	for cell in range(200):
		assert_lte(GroundCover.props_for(TerrainGen.Biome.FOREST, NO_NEIGHBOURS,
			1.0, 0.0, cell, false).size(), GroundCover.MAX_PER_CELL,
			"a cell blew past MAX_PER_CELL; the client sizes buffers from this")


# --- the shipped map ----------------------------------------------------


## Dress the whole Standard map and count what grew, per biome.
##
## Deliberately the map a real match generates (`MapSettings`'s defaults —
## 84x96, seed 1337, the shipped thresholds), not a fixture: a mechanism that
## works on a fixture and does nothing on the shipped map is a defect this
## project has shipped more than once.
func _census() -> Dictionary:
	var settings := MapSettings.new()
	var space := settings.to_space()
	var terrain := settings.to_terrain()

	var count := space.cell_count()
	var biomes := PackedInt32Array()
	var moisture := PackedFloat32Array()
	biomes.resize(count)
	moisture.resize(count)
	# One pass, cached — the client does the same. Sampling a neighbour's
	# biome by calling biome_at again would be six extra noise evaluations per
	# cell, which is the shape of the defect that cost vision 232 µs/squad.
	var elevation := terrain.elevation_field(space)
	for i in range(count):
		var coord := space.from_index(i)
		biomes[i] = terrain.biome_at(space, coord)
		moisture[i] = terrain.moisture_at(space, coord)

	var per_biome := {}
	var biome_cells := {}
	var cells_with_cover := 0
	var vegetated := 0
	var total := 0
	for i in range(count):
		biome_cells[biomes[i]] = int(biome_cells.get(biomes[i], 0)) + 1
		var neighbours: Array = []
		for dir in range(6):
			neighbours.append(biomes[space.neighbor_index(i, dir)])
		var props := GroundCover.props_for(biomes[i], neighbours, moisture[i],
			elevation[i], i, false)
		if GroundCover.BASE_DENSITY.has(biomes[i]):
			vegetated += 1
			if not props.is_empty():
				cells_with_cover += 1
		per_biome[biomes[i]] = int(per_biome.get(biomes[i], 0)) + props.size()
		total += props.size()

	return {"per_biome": per_biome, "biome_cells": biome_cells, "total": total,
		"cells": count, "vegetated": vegetated, "with_cover": cells_with_cover}


func test_the_shipped_map_is_actually_dressed() -> void:
	var census := _census()
	var per_biome: Dictionary = census["per_biome"]
	var biome_cells: Dictionary = census["biome_cells"]
	gut.p("ground cover on the shipped Standard map: %d props over %d cells (%d vegetated)"
		% [census["total"], census["cells"], census["vegetated"]])
	for biome in biome_cells:
		gut.p("  biome %d: %d cells, %d props"
			% [biome, int(biome_cells[biome]), int(per_biome.get(biome, 0))])

	assert_eq(int(per_biome.get(TerrainGen.Biome.WATER, 0)), 0,
		"cover grew on water on the shipped map")
	assert_eq(int(per_biome.get(TerrainGen.Biome.DEEP_WATER, 0)), 0,
		"cover grew on deep water on the shipped map")

	# Every biome that is supposed to carry cover, and actually appears on this
	# map, carries a real amount of it. Per biome rather than one total: a
	# total can be met by one big region while another is bare, which is the
	# failure that stops a region reading as a place.
	#
	# Conditional on the biome being PRESENT because the shipped Standard map
	# at its default seed has no PEAK cells at all and only ~67 MOUNTAIN ones —
	# asserting a fixed floor per biome would be asserting something about that
	# one seed's terrain rather than about cover.
	for biome in GroundCover.BASE_DENSITY:
		var cells: int = int(biome_cells.get(biome, 0))
		if cells == 0:
			continue
		assert_gt(float(per_biome.get(biome, 0)) / float(cells), 1.0,
			"biome %d grew %d props over %d cells — under one per cell is not cover"
				% [biome, int(per_biome.get(biome, 0)), cells])

	var per_vegetated := float(census["total"]) / maxf(1.0, float(census["vegetated"]))
	assert_between(per_vegetated, 2.5, 5.0,
		"props per vegetated cell is %.2f — the owner's brief asks for 3-5"
			% per_vegetated)
	assert_gt(float(census["with_cover"]) / maxf(1.0, float(census["vegetated"])), 0.75,
		"more than a quarter of vegetated cells came up bare")
