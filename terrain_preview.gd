extends SceneTree

## Fast terrain-gen iteration loop (`just gen-terrain-preview`).
##
## Runs fully headless, so it deliberately does NOT render a viewport —
## `--headless` has no rendering device, and a preview that needed one
## would be unusable in exactly the environment this project develops in
## (D-014). Instead it writes the biome field directly to a PNG with
## Image, one pixel per cell, which is both faster than rendering and
## honest about what it is showing.
##
## It also builds every chunk mesh at the requested chunk size and reports
## the cost. That is the measurement D-017 defers its chunk-size decision
## to: run this at a few sizes and compare, rather than guessing.

const DEFAULT_MAP := "res://maps/default.tres"
const DEFAULT_CHUNK_SIZE := 16
## Resolved through `ArtifactPath`, because `res://` is read-only inside
## an exported build (#201). The identity in a checkout.
const OUTPUT_DIR := "res://artifacts"


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var map_path := String(args.get("map", DEFAULT_MAP))
	var chunk_size := int(args.get("chunk-size", DEFAULT_CHUNK_SIZE))
	var out_path := String(args.get("out", "%s/terrain-preview.png" % OUTPUT_DIR))
	# One pixel per cell is unreadable at typical map sizes, so upscale
	# with nearest-neighbour — the point is to see cell boundaries, not to
	# smooth them away.
	var pixel_scale := maxi(1, int(args.get("pixel-scale", 8)))

	var config := load(map_path) as MapConfig
	if config == null:
		push_error("gen-terrain-preview: could not load MapConfig from %s" % map_path)
		quit(1)
		return

	var invalid := config.validate()
	if invalid != "":
		push_error("gen-terrain-preview: map %s is invalid: %s" % [map_path, invalid])
		quit(1)
		return

	var space := config.to_space()
	var terrain := TerrainGen.new()

	print("gen-terrain-preview: map %s (%dx%d cells), chunk size %d" % [
		config.id, space.width, space.height, chunk_size])

	# --- biome image -------------------------------------------------
	var image_started := Time.get_ticks_usec()
	var image := Image.create(space.width, space.height, false, Image.FORMAT_RGB8)
	var water_cells := 0
	for r in range(space.height):
		for q in range(space.width):
			var cell := Vector2i(q, r)
			image.set_pixel(q, r, terrain.biome_color(space, cell))
			if terrain.is_water(space, cell):
				water_cells += 1
	var image_usec := Time.get_ticks_usec() - image_started

	if pixel_scale > 1:
		image.resize(space.width * pixel_scale, space.height * pixel_scale,
			Image.INTERPOLATE_NEAREST)

	out_path = ArtifactPath.resolve(out_path)
	var dir_error := ArtifactPath.ensure_dir_for(out_path)
	if dir_error != OK:
		push_error("terrain_preview: could not create %s (error %d)"
			% [out_path.get_base_dir(), dir_error])
	var save_error := image.save_png(out_path)
	if save_error != OK:
		push_error("gen-terrain-preview: could not write %s (error %d)" % [out_path, save_error])
		quit(1)
		return

	var water_fraction := float(water_cells) / float(space.cell_count())
	print("gen-terrain-preview: wrote %s (%dx%d px, %dx scale) in %.1f ms — %.1f%% water" % [
		out_path, space.width * pixel_scale, space.height * pixel_scale, pixel_scale,
		image_usec / 1000.0, water_fraction * 100.0])

	# --- chunking cost (D-017) ---------------------------------------
	var stats := TerrainChunk.build_all(space, terrain, chunk_size)
	print("gen-terrain-preview: %d chunks (%dx%d grid), %d verts, %d tris, built in %.1f ms" % [
		stats["chunks"], (stats["grid"] as Vector2i).x, (stats["grid"] as Vector2i).y,
		stats["vertices"], stats["triangles"], float(stats["build_usec"]) / 1000.0])
	print("gen-terrain-preview: %.1f verts/chunk — vary --chunk-size to compare (D-017 is decided by this measurement, not by guessing)" % [
		float(stats["vertices"]) / float(maxi(stats["chunks"], 1))])

	# The cliff faces (D-097), reported next to the passability count they
	# are a drawing of. A skirt count of zero on the shipped map would mean
	# the mechanism is built and the ground still has no visible edge —
	# which is the "mechanism right, shipped numbers do nothing" failure,
	# and it looks identical to success in every other line here.
	print("gen-terrain-preview: %d cliff faces drawn at passability boundaries" % [
		stats["cliff_quads"]])

	# --- passability, which is what pathfinding actually consumes -----
	var passable := terrain.passability(space)
	var blocked := 0
	for i in range(passable.size()):
		if passable[i] == 0:
			blocked += 1
	print("gen-terrain-preview: %d of %d cells impassable (%.1f%%)" % [
		blocked, space.cell_count(), 100.0 * float(blocked) / float(space.cell_count())])

	# --- resource nodes, and how much walkable ground they leave open ---
	#
	# The counts alone cannot answer the question a player asks ("is there
	# any open country?"), because a node only matters where somebody could
	# have walked or built: 7,694 nodes on a map that is a fifth water is a
	# different picture from the same number on dry land. So the share of
	# PASSABLE cells that hold no node is reported next to the totals, and
	# the FOREST biome's own share separately — a forest heart at 98% trees
	# is invisible in a whole-map average dominated by open grassland.
	var economy := Economy.new(space)
	economy.generate(terrain, config.symmetry_order)
	var by_kind := PackedInt32Array()
	by_kind.resize(Economy.RESOURCE_COUNT)
	var open_passable := 0
	var forest_cells := 0
	var forest_nodes := 0
	for i in range(space.cell_count()):
		var held: bool = economy.nodes.has(i)
		if held:
			by_kind[int(economy.nodes[i]["kind"])] += 1
		if passable[i] != 0 and not held:
			open_passable += 1
		if terrain.biome_at(space, space.from_index(i)) == TerrainGen.Biome.FOREST:
			forest_cells += 1
			if held:
				forest_nodes += 1
	var walkable_cells := space.cell_count() - blocked
	print("gen-terrain-preview: %d resource nodes — %d food, %d wood, %d gold, %d stone" % [
		economy.node_count(), by_kind[Economy.ResourceKind.FOOD], by_kind[Economy.ResourceKind.WOOD],
		by_kind[Economy.ResourceKind.GOLD], by_kind[Economy.ResourceKind.STONE]])
	print("gen-terrain-preview: %d of %d walkable cells are open ground (%.1f%%) — a node is ground nobody can build on" % [
		open_passable, walkable_cells, 100.0 * float(open_passable) / float(maxi(walkable_cells, 1))])
	print("gen-terrain-preview: forest biome %d cells, %d hold a node (%.1f%% wooded)" % [
		forest_cells, forest_nodes, 100.0 * float(forest_nodes) / float(maxi(forest_cells, 1))])

	quit(0)


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
