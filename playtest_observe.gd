extends SceneTree

## Headless OBSERVATION for the visual/infra playtest tickets.
##
## Not a test and deliberately not in `tests/` — it asserts nothing and
## fails nothing. It drives the game's own pure modules over the shipped
## data and PRINTS what they answer, so a playtest report can quote a
## number instead of an impression. Where a question is arithmetic
## (does a HUD element clip off a 3440x1440 window, does an order across
## the seam path the short way round) an instrument that answers it beats
## a human squinting at a screenshot, and the human's time is better
## spent on the half that genuinely needs eyes.
##
## Run one topic at a time:
##
##     tools/godot.exe --headless --path . --script playtest_observe.gd -- --topic=hud
##
## Topics: hud (#46), seam (#32), lod (#47), civs (#207), terrain (#48).

func _init() -> void:
	var topic := "all"
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text.begins_with("--topic="):
			topic = text.trim_prefix("--topic=")
	if topic == "hud" or topic == "all":
		_hud()
	if topic == "seam" or topic == "all":
		_seam()
	if topic == "lod" or topic == "all":
		_lod()
	if topic == "civs" or topic == "all":
		_civs()
	if topic == "terrain" or topic == "all":
		_terrain()
	quit(0)


# ---------------------------------------------------------------- #46 HUD

## Sweep window sizes and report, per size, everything #46's second and
## third pass criteria ask about: does anything leave the window, does
## anything overlap anything else, how much of the window is chrome, and
## can the chip strip still reach every train order (the trap
## D-20260817-selection-bar-three-columns names — a cap that hides a
## CONTROL rather than a label).
func _hud() -> void:
	print("=== HUD sweep (#46) ===")
	var sizes := [
		Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440),
		Vector2(3840, 2160), Vector2(1152, 648), Vector2(1024, 600),
		Vector2(800, 600), Vector2(3440, 1440), Vector2(1280, 1024),
		Vector2(900, 1600), Vector2(1920, 550), Vector2(640, 480),
	]
	var floor_size := HudLayout.min_window_size()
	print("HUD: min_window_size = %dx%d, scale clamp [%.2f, %.2f], reference %s, magnify above %s"
		% [floor_size.x, floor_size.y, HudLayout.MIN_SCALE, HudLayout.MAX_SCALE,
			HudLayout.REFERENCE, HudLayout.MAGNIFY_ABOVE])
	print("HUD: window          scale  design       panel%%  chrome%%  offscreen  overlaps  chips(cap/collapse)")
	for size in sizes:
		var scale := HudLayout.scale_for(size)
		var design := HudLayout.design_size(size)
		# The minimap the client asks for is square-ish and derived from the
		# ring; a fixed plausible size is enough to exercise the layout.
		var rects := HudLayout.compute(design, Vector2(180.0, 180.0))
		var offscreen := PackedStringArray()
		for key in rects:
			var rect: Rect2 = rects[key]
			if rect.position.x < -0.5 or rect.position.y < -0.5 \
					or rect.position.x + rect.size.x > design.x + 0.5 \
					or rect.position.y + rect.size.y > design.y + 0.5:
				offscreen.append(String(key))
		var overlaps := _hud_overlaps(rects)
		var panel: Rect2 = rects["panel"]
		var panel_share := panel.size.y / maxf(design.y, 1.0) * 100.0
		var chrome := (rects["resource_bar"] as Rect2).size.y + panel.size.y
		var chrome_share := chrome / maxf(design.y, 1.0) * 100.0
		var strip := HudLayout.chip_strip_rect(panel, true)
		print("HUD: %5dx%-5d  %.3f  %5.0fx%-5.0f  %5.1f  %6.1f  %-9s  %-8s  %d/%d" % [
			size.x, size.y, scale, design.x, design.y, panel_share,
			chrome_share,
			"none" if offscreen.is_empty() else ",".join(offscreen),
			"none" if overlaps.is_empty() else ",".join(overlaps),
			HudLayout.chip_capacity(strip), HudLayout.chip_collapse_at(strip)])
	# The build menu's real demand: the largest `produces` list any shipped
	# building has. A strip that seats fewer than this hides an ORDER.
	var wanted := _largest_produces()
	print("HUD: largest shipped produces list = %d (the chip strip must reach every one)"
		% wanted)
	print("HUD: clock  0s=%s  61s=%s  3661s=%s" % [HudLayout.clock_text(0.0),
		HudLayout.clock_text(61.0), HudLayout.clock_text(3661.0)])
	print("HUD: n/cap  0/40=%s  12/40=%s  44/44=%s" % [
		HudLayout.squad_count_text(0, 40), HudLayout.squad_count_text(12, 40),
		HudLayout.squad_count_text(44, 44)])


## Which named rects genuinely intersect. The panel legitimately abuts the
## ring on a short window (the layout clamps it below), so only a real
## area overlap is reported.
func _hud_overlaps(rects: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var keys := rects.keys()
	keys.sort()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			# The minimap sits INSIDE the ring by construction, and the
			# status/menu/resource readouts sit inside the bar.
			if _nested(keys[i], keys[j]):
				continue
			var hit := a.intersection(b)
			if hit.size.x > 0.5 and hit.size.y > 0.5:
				out.append("%s~%s" % [keys[i], keys[j]])
	return out


func _nested(a: String, b: String) -> bool:
	var pairs := [["minimap", "ring"], ["menu_button", "resource_bar"],
		["status", "resource_bar"], ["menu_button", "status"]]
	for pair in pairs:
		if (a == pair[0] and b == pair[1]) or (a == pair[1] and b == pair[0]):
			return true
	return false


func _largest_produces() -> int:
	var most := 0
	var dir := DirAccess.open("res://buildings")
	if dir == null:
		return most
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var def := load("res://buildings/%s" % file) as BuildingDef
		if def == null:
			continue
		most = maxi(most, def.produces.size())
	return most


# --------------------------------------------------------------- #32 seam

## The seam questions that are arithmetic rather than pictures: does an
## order across the wrap line path the SHORT way, does the minimap wrap a
## footprint that straddles it, and how many lattice copies does the
## world offer for a thing standing on the line.
func _seam() -> void:
	print("=== Seam observations (#32) ===")
	var config := load("res://maps/default.tres") as MapConfig
	if config == null:
		print("seam: no default map")
		return
	var space := config.to_space()
	print("seam: map %dx%d = %d cells, hex_size=%.2f" % [space.width,
		space.height, space.cell_count(), space.hex_size])

	# 1. Short-way distance. TorusSpace is the one definition every mover
	#    reads (D-008), so if this is wrong nothing downstream can be right.
	var near_left := Vector2i(1, 4)
	var near_right := Vector2i(space.width - 2, 4)
	var across := space.distance(near_left, near_right)
	print("seam: q-wrap  %s -> %s  torus distance = %d cells (the long way is about %d)"
		% [near_left, near_right, across, space.width - across])
	var top := Vector2i(10, 1)
	var bottom := Vector2i(10, space.height - 2)
	var down := space.distance(top, bottom)
	print("seam: r-wrap  %s -> %s  torus distance = %d cells (the long way is about %d)"
		% [top, bottom, down, space.height - down])

	# 2. A flow field solved to a destination just over the seam. The
	#    field is what a squad actually follows, so walking it IS the
	#    route: a path length near the torus distance crossed the seam, a
	#    path length near the map width went the long way round.
	var terrain := TerrainGen.new()
	var fields := terrain.build_fields(space)
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	for i in range(space.cell_count()):
		passable[i] = fields.passable[i]
	_seam_route(space, passable, Vector2i(2, 4), Vector2i(space.width - 3, 4),
		"q", fields)
	_seam_route(space, passable, Vector2i(20, 2), Vector2i(20, space.height - 3),
		"r", fields)

	# 3. Minimap wrap: a footprint straddling the seam must come back
	#    inside the image on both sides. `MinimapPaint.footprint` is the
	#    one definition of what gets painted.
	var straddle := MinimapPaint.footprint(Vector2i(0, 6), 4, space.width,
		space.height)
	var xs := PackedInt32Array()
	for cell in straddle:
		xs.append(cell.x)
	var lo := space.width
	var hi := -1
	var out_of_bounds := 0
	for x in xs:
		lo = mini(lo, x)
		hi = maxi(hi, x)
		if x < 0 or x >= space.width:
			out_of_bounds += 1
	print("seam: minimap footprint of a 4-cell building at (0,6): %d cells, x from %d to %d, %d outside the image"
		% [straddle.size(), lo, hi, out_of_bounds])
	print("seam:   both sides present: %s"
		% [lo == 0 and hi == space.width - 1])

	# 4. Lattice copies — the mechanism that closed the copy-choice bug
	#    class (D-20260818). Nine, and a squad on the line is entitled to
	#    be drawn at every one that is on screen.
	print("seam: lattice offsets per entity = %d (D-035's nine copies)"
		% space.lattice_offsets().size())
	var steps := space.lattice_steps()
	print("seam: lattice steps = %s and %s" % [steps[0], steps[1]])


## Solve a field to `to` and walk it from `from`, reporting whether the
## route it produced is the short way round.
func _seam_route(space: TorusSpace, passable: PackedByteArray, want_from: Vector2i,
		want_to: Vector2i, axis: String, fields: TerrainFields) -> void:
	var from := _walkable_near(space, fields, want_from)
	var to := _walkable_near(space, fields, want_to)
	if from.x < 0 or to.x < 0:
		print("seam: %s — no walkable pair either side of the seam on this map" % axis)
		return
	var field := FlowField.new()
	field.build(space, to, passable)
	var path := field.path_from(space.index(from))
	var straight := space.distance(from, to)
	var span := space.width if axis == "q" else space.height
	print("seam: %s seam route %s -> %s: %d steps, torus distance %d, long way would be about %d"
		% [axis, from, to, path.size(), straight, span - straight])
	if path.size() > 0:
		var verdict := "SHORT way" if path.size() < span / 2 else "LONG way"
		print("seam:   reachable=%s, took the %s round"
			% [field.is_reachable(space.index(from)), verdict])
	else:
		print("seam:   no path — reachable=%s" % field.is_reachable(space.index(from)))


func _walkable_near(space: TorusSpace, fields: TerrainFields,
		want: Vector2i) -> Vector2i:
	for offset in TorusSpace.disk_offsets(8):
		var cell := space.normalize(want + offset)
		if fields.passable[space.index(cell)] == 1:
			return cell
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- #47 LOD

## "Distant squads draw THINNER, never smaller" (D-045) is #47's fourth
## pass criterion. The tiers are a constant in `client.gd`; what makes the
## claim true is that a thinned squad still asks `Formation.slot_offset`
## for its REAL size, so its frontage does not shrink. Both halves are
## reported here: the tiers as data, and the frontage measured through
## `Formation` at full and thinned counts.
func _lod() -> void:
	print("=== Render LOD (#47) ===")
	var client_script := load("res://client.gd")
	var tiers: Array = client_script.LOD_TIERS
	for tier in tiers:
		print("LOD: past %8.1f world units, at most %d soldiers drawn"
			% [float(tier["distance"]), int(tier["soldiers"])])
	var def := UnitRoster.first()
	if def == null:
		print("LOD: no unit def to measure frontage with")
		return
	# Footprint is what a player reads as the unit's size on the ground, and
	# what selection, culling and separation all size themselves from. The
	# claim under test is that it is asked for the squad's REAL strength, so
	# a thinned squad keeps its frontage.
	print("LOD: measuring %s (shape=%s spacing=%.2f)"
		% [def.id, def.formation_shape, def.formation_spacing])
	for alive in [36, 12, 5]:
		var span: Dictionary = Formation.footprint(def.formation_shape, alive,
			def.formation_spacing)
		print("LOD: a squad of %-2d -> radius %.2f, lever %.2f"
			% [alive, float(span["radius"]), float(span["lever"])])
	print("LOD: the tiers cap how many men are DRAWN; `alive` is untouched, so"
		+ " a distant squad keeps the radius of its true strength.")


# --------------------------------------------------------------- #207 civs

## What the six shipped civs actually differ by, for the replacement
## civ-differentiation ticket.
func _civs() -> void:
	print("=== Civs (#207) ===")
	var civs := CivRoster.load_all()
	print("civs: %d shipped" % civs.size())
	for civ in civs:
		var roster := PackedStringArray()
		for def in UnitRoster.load_all():
			if def.civ == civ.id:
				roster.append(String(def.archetype))
		roster.sort()
		print("civs: %-13s cap+%d prod=%.2f gather=%.2f  food=%d wood=%d  roster=%s"
			% [civ.id, civ.squad_cap_bonus, civ.production_speed,
				civ.gather_speed, civ.starting_food, civ.starting_wood,
				",".join(roster)])


# ------------------------------------------------------------- #48 terrain

## How the impassable set is SHAPED, which is what decides whether a rock
## face reads as a wall or as a shard lying on the grass.
##
## D-097 draws one face per stepped edge and
## `D-20260826-passable-means-flat-enough-to-cross` decides which edges
## those are. A blocked cell in the middle of a ridge contributes to a
## wall; a blocked cell whose six neighbours are all walkable contributes
## a six-sided lump with nothing to belong to. Both are the same code and
## the same truthful drawing — only the SHAPE of the set differs, and the
## set is what moved when the rule changed.
func _terrain() -> void:
	print("=== Terrain shape (#48) ===")
	var config := load("res://maps/default.tres") as MapConfig
	if config == null:
		print("terrain: no default map")
		return
	# Every shipped /terrain preset on the shipped map size, through the ONE
	# place a MapSettings becomes a TerrainGen (`to_terrain`), so this is the
	# generator the server runs rather than this file's idea of it.
	for id in TerrainPresetRoster.ids():
		var settings := MapSettings.new()
		settings.apply_preset(TerrainPresetRoster.by_id(id))
		_terrain_shape(String(id), config, settings)


func _terrain_shape(name: String, config: MapConfig, settings: MapSettings) -> void:
	var space := config.to_space()
	var fields := settings.to_terrain().build_fields(space)
	var blocked := 0
	var isolated := 0
	var thin := 0
	var stepped_edges := 0
	for i in range(space.cell_count()):
		if fields.passable[i] == 1:
			continue
		blocked += 1
		var open := 0
		for direction in range(6):
			if fields.passable[space.neighbor_index(i, direction)] == 1:
				open += 1
		stepped_edges += open
		if open == 6:
			isolated += 1
		elif open >= 5:
			thin += 1
	var cells := space.cell_count()
	print("terrain: %-10s %dx%d = %d cells" % [name, space.width, space.height, cells])
	print("terrain:   blocked %d (%.1f%%), of which ISOLATED (all six neighbours walkable) %d (%.1f%% of blocked), near-isolated %d"
		% [blocked, 100.0 * blocked / maxi(cells, 1), isolated,
			100.0 * isolated / maxf(blocked, 1.0), thin])
	print("terrain:   stepped edges (one rock face each) %d — %.2f per blocked cell"
		% [stepped_edges, float(stepped_edges) / maxf(blocked, 1.0)])
