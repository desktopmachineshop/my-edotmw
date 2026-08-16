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

	if not DirAccess.dir_exists_absolute(OUTPUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
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

	quit(0)


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed
