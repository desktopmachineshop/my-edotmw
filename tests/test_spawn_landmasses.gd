extends GutTest

## What `gate-check.sh naval` keys its skip on (#351, #301).
##
## Guards `server.gd`'s SPAWN_LANDMASSES marker, which is the ONE thing
## that can tell two identical-looking runs apart: an AI that correctly
## wanted no navy because every enemy was walkable, and an AI that wanted
## no navy on an archipelago. `wants_navy=0` is what both report, so the
## gate may not read it — the map has to answer, and this is the map's
## answer.
##
## Deliberately not asserting a fixed number per preset: generated
## terrain moves when the generator does, and a test pinning "islands is
## 4" would go red on a terrain tuning change that broke nothing. What is
## pinned is the ARITHMETIC and the two ends that carry meaning — a
## single component reads 1, and starts in different components read
## more than 1.

const SEED := 1337


func _landmasses(points: Array, space: TorusSpace,
		passable: PackedByteArray) -> int:
	var comps := MapConfig.walkable_components(space, passable)
	var labels: PackedInt32Array = comps["labels"]
	var seen := {}
	for point in points:
		var index := space.index(point)
		if index >= 0 and index < labels.size() and labels[index] >= 0:
			seen[labels[index]] = true
	return seen.size()


func test_starts_on_one_component_count_as_one_landmass() -> void:
	# An open map with no water at all: every start is walkable to every
	# other, which is exactly the run where a skip is honest.
	var space := TorusSpace.new(24, 12)
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)
	var points: Array = [Vector2i(0, 0), Vector2i(8, 4), Vector2i(16, 8)]
	assert_eq(_landmasses(points, space, passable), 1,
		"three starts on one continent are one landmass")


func test_starts_on_separate_components_count_separately() -> void:
	# TWO channels, not one: a single band of water separates nothing on a
	# torus, and a fixture with one would report 1 while looking like 2.
	# The same trap that let three of my stage 7 crossing tests pass over
	# a strait that was not one.
	var space := TorusSpace.new(24, 12)
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)
	for r in range(space.height):
		passable[space.index(Vector2i(6, r))] = 0
		passable[space.index(Vector2i(18, r))] = 0

	var west := Vector2i(2, 4)
	var east := Vector2i(12, 4)
	var comps := MapConfig.walkable_components(space, passable)
	var labels: PackedInt32Array = comps["labels"]
	assert_ne(labels[space.index(west)], labels[space.index(east)],
		"premise: the two channels really do separate the halves")

	assert_eq(_landmasses([west, east], space, passable), 2,
		"starts either side of the water are two landmasses")


func test_an_unplaced_start_is_not_counted_as_a_landmass() -> void:
	# A start on an impassable cell has no component. Counting it as one
	# would make an unseated map look like an archipelago and turn the
	# gate's skip into a spurious #351 report.
	var space := TorusSpace.new(24, 12)
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)
	passable[space.index(Vector2i(3, 3))] = 0
	assert_eq(_landmasses([Vector2i(3, 3)], space, passable), 0,
		"a start nobody can stand on is no landmass")


func test_the_shipped_maps_report_their_topology() -> void:
	# Not an assertion about any preset's number — a printout, so whoever
	# aims a naval run knows which map can produce a crossing at all.
	# The one thing asserted is that the arithmetic runs on real terrain.
	for map_path in ["res://maps/ladder.tres", "res://maps/default.tres"]:
		var cfg: MapConfig = load(map_path)
		if cfg == null:
			continue
		for preset in ["continents", "islands"]:
			var settings := MapSettings.new()
			settings.width = cfg.width
			settings.height = cfg.height
			settings.seed = SEED
			settings.player_slots = 4
			settings.apply_preset(TerrainPresetRoster.by_id(StringName(preset)))
			var space := TorusSpace.new(settings.width, settings.height)
			var fields: TerrainFields = settings.to_terrain().build_fields(space)
			var passable: PackedByteArray = fields.passable
			var points := settings.to_spawn_config().spawn_points(passable)
			var count := _landmasses(points, space, passable)
			gut.p("%s %s %dx%d: %d start(s), %d landmass(es)" % [
				map_path.get_file(), preset, settings.width,
				settings.height, points.size(), count])
			assert_true(count >= 0, "topology is computable on real terrain")
