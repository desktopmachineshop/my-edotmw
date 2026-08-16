extends GutTest

## Guards D-036 (quadrant-symmetric generation and derived spawn points)
## and D-037 (biome as simulation data).
##
## ## Why the symmetry test is an exact identity, not a tolerance
##
## M3 places four players on one generated map and needs them to start on
## equal ground. The usual way to get that is to generate freely, score
## each start's surroundings, and reject seeds that come out lopsided —
## a heuristic nobody has designed, giving a statistical guarantee.
##
## Instead the generator walks `axis_repeats` laps around each circle of
## its embedding torus (terrain_gen._sample). Because u and v are ANGLES,
## cell (x, y) and cell (x + width/2, y) map to *literally the same*
## sample point, so the quadrants are bit-identical. That makes fairness a
## property of the generator, and it makes the test an exact equality over
## every cell rather than a fuzzy comparison — which is also why it is
## cheap to run and trivial to see fail.

const W := 64
const H := 32


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _terrain(repeats: int) -> TerrainGen:
	var t := TerrainGen.new()
	t.axis_repeats = repeats
	return t


# --- quadrant symmetry (D-036) ----------------------------------------

func test_quadrants_are_identical_at_every_cell() -> void:
	var space := _space()
	var terrain := _terrain(2)
	var half_w := W / 2
	var half_h := H / 2

	var mismatches := 0
	for y in range(H):
		for x in range(W):
			var here := terrain.elevation_at(space, Vector2i(x, y))
			var across := terrain.elevation_at(space, Vector2i(x + half_w, y))
			var down := terrain.elevation_at(space, Vector2i(x, y + half_h))
			if not (is_equal_approx(here, across) and is_equal_approx(here, down)):
				mismatches += 1

	assert_eq(mismatches, 0,
		"With axis_repeats=2 every cell must equal its counterpart half a map away on both axes — that identity IS the fairness guarantee")


func test_moisture_is_symmetric_too_not_just_elevation() -> void:
	# Resource nodes are derived from biome, and biome reads moisture as
	# well as elevation (terrain_gen.biome_at). Symmetric elevation with
	# asymmetric moisture would give four players identical landforms and
	# different resources — fair-looking and unfair.
	var space := _space()
	var terrain := _terrain(2)
	var mismatches := 0
	for y in range(H):
		for x in range(W):
			var here := terrain.moisture_at(space, Vector2i(x, y))
			var across := terrain.moisture_at(space, Vector2i(x + W / 2, y))
			if not is_equal_approx(here, across):
				mismatches += 1
	assert_eq(mismatches, 0, "Moisture must be symmetric too, or the quadrants yield different resources")


func test_biome_is_symmetric_so_resources_will_be() -> void:
	var space := _space()
	var terrain := _terrain(2)
	var mismatches := 0
	for y in range(H):
		for x in range(W):
			if terrain.biome_at(space, Vector2i(x, y)) != terrain.biome_at(space, Vector2i(x + W / 2, y)):
				mismatches += 1
	assert_eq(mismatches, 0, "Biome must be symmetric — D-037 derives resource nodes from it")


func test_asymmetric_generation_is_not_symmetric() -> void:
	# The counter-test. Without this, the assertions above would pass just
	# as happily against a generator that returned a constant everywhere —
	# a check that cannot distinguish success from vacuity (D-022).
	var space := _space()
	var terrain := _terrain(1)
	var differences := 0
	for y in range(H):
		for x in range(W):
			if not is_equal_approx(
				terrain.elevation_at(space, Vector2i(x, y)),
				terrain.elevation_at(space, Vector2i(x + W / 2, y))):
				differences += 1
	assert_gt(differences, 0,
		"axis_repeats=1 must NOT be quadrant-symmetric, or the symmetry tests above prove nothing")


func test_symmetry_does_not_flatten_the_map() -> void:
	# Symmetric AND wrong is the failure the numeric tests cannot see: a
	# generator returning one value everywhere is perfectly symmetric.
	var space := _space()
	var terrain := _terrain(2)
	var lowest := 1.0
	var highest := 0.0
	for y in range(H):
		for x in range(W):
			var e := terrain.elevation_at(space, Vector2i(x, y))
			lowest = minf(lowest, e)
			highest = maxf(highest, e)
	assert_gt(highest - lowest, 0.2,
		"A symmetric map must still have real terrain relief, not one flat value repeated four times")


# --- random spawn points with minimum spacing (D-039) ------------------

func _config() -> MapConfig:
	var c := MapConfig.new()
	c.width = 128
	c.height = 64
	c.symmetry_order = 2
	c.player_slots = 20
	c.min_spawn_spacing = 12
	return c


func test_the_map_seats_every_slot_it_claims() -> void:
	var config := _config()
	assert_eq(config.spawn_points().size(), 20,
		"Rejection sampling gave up before seating everyone — 20 players would share starts")
	assert_eq(config.player_capacity(), 20)


func test_no_two_spawns_are_closer_than_the_minimum_spacing() -> void:
	# The one guarantee random placement makes. Measured toroidally, so a
	# pair either side of the seam counts as the neighbours they are.
	var config := _config()
	var space := config.to_space()
	var points := config.spawn_points()

	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			var d: float = space.distance(points[i], points[j])
			assert_gte(d, float(config.min_spawn_spacing),
				"Spawns %s and %s are %.1f apart, inside the %d minimum" % [
					points[i], points[j], d, config.min_spawn_spacing])


func test_spawn_points_are_distinct() -> void:
	var seen := {}
	for point in _config().spawn_points():
		assert_false(seen.has(point), "Two players would spawn on the same cell %s" % point)
		seen[point] = true


func test_spawn_layout_is_deterministic_for_a_given_seed() -> void:
	# Replays (D-016) and every client's idea of where people start both
	# depend on this. Random must mean "varies between maps", never
	# "varies between runs of the same map".
	assert_eq(_config().spawn_points(), _config().spawn_points(),
		"Two samplings of the same map disagreed — replays would not reconstruct")


func test_a_different_seed_gives_a_different_layout() -> void:
	# The half of "random" the spacing test cannot see: without this, a
	# generator that returned one fixed well-spaced arrangement forever
	# would pass everything above while giving every match the same
	# neighbours — the exact thing the grid was replaced to stop doing.
	var a := _config()
	var b := _config()
	b.spawn_seed = a.spawn_seed + 1
	assert_ne(a.spawn_points(), b.spawn_points(),
		"Changing the seed did not change where anyone starts")


func test_spawns_never_land_on_impassable_ground() -> void:
	# A grid could be authored onto known-good cells. Random placement
	# cannot, so this is a live failure mode: a start inside a lake is a
	# player who cannot move.
	var config := _config()
	var space := config.to_space()

	var passable := PackedByteArray()
	passable.resize(config.width * config.height)
	for y in range(config.height):
		for x in range(config.width):
			# Drown the left quarter of the map.
			passable[space.index(Vector2i(x, y))] = 0 if x < 32 else 1

	var points := config.spawn_points(passable)
	assert_gt(points.size(), 0, "Nothing was placed at all, so the check below proves nothing")
	for point in points:
		assert_eq(passable[space.index(point)], 1,
			"Spawn %s sits on impassable terrain" % point)


func test_spawns_never_land_on_an_islet_in_open_water() -> void:
	# Passable is necessary and not sufficient (D-104). The reported case:
	# a founding party on a SIX-CELL rock, every cell of it legal ground,
	# and the player dead on arrival because a town hall and the resources
	# to work it do not fit — D-031 makes that opening the whole match.
	#
	# Authored rather than generated so the failure is unambiguous: one
	# continent, and a scatter of rocks that a single-cell test cannot
	# tell apart from it.
	var config := _config()
	config.min_spawn_landmass = 96
	var space := config.to_space()

	var passable := PackedByteArray()
	passable.resize(config.width * config.height)
	for y in range(config.height):
		for x in range(config.width):
			# A continent across the top of the map, sea below it —
			# deliberately too small to seat all twenty, so the sampler
			# keeps looking and the rocks below get their chance.
			passable[space.index(Vector2i(x, y))] = 1 if y < 10 else 0
	# ... and eleven three-cell rocks in that sea, well spaced, which is
	# exactly the ground the sampler used to accept.
	for i in range(11):
		var rock := Vector2i(4 + i * 11, 40)
		for cell in [rock, rock + Vector2i(1, 0), rock + Vector2i(0, 2)]:
			passable[space.index(cell)] = 1

	var points := config.spawn_points(passable)
	assert_gt(points.size(), 0, "Nothing was placed at all, so the check below proves nothing")
	for point in points:
		assert_lt(point.y, 10,
			"Spawn %s stands on a three-cell rock in open sea — legal ground, and a lost player" % point)


func test_a_landmass_minimum_of_zero_accepts_what_it_used_to() -> void:
	# The other half of the check above: without it the sampler cannot see
	# the difference, which is the defect stated as a passing assertion.
	var config := _config()
	config.min_spawn_landmass = 0
	var space := config.to_space()

	var passable := PackedByteArray()
	passable.resize(config.width * config.height)
	for y in range(config.height):
		for x in range(config.width):
			passable[space.index(Vector2i(x, y))] = 1 if y < 10 else 0
	for i in range(11):
		var rock := Vector2i(4 + i * 11, 40)
		for cell in [rock, rock + Vector2i(1, 0), rock + Vector2i(0, 2)]:
			passable[space.index(cell)] = 1

	var on_rocks := 0
	for point in config.spawn_points(passable):
		if point.y >= 10:
			on_rocks += 1
	assert_gt(on_rocks, 0,
		"With the landmass minimum off, rocks should still be accepted — if they are not, the test above passes for some other reason")


func test_the_shipped_islands_preset_seats_nobody_on_a_rock() -> void:
	# The world from the P01 playtest report, generated exactly as the
	# server generates it. Authored terrain proves the rule; this proves
	# the rule fires on ground nobody chose, which is where it mattered —
	# `islands` is ~71% water at these settings and put one start in
	# twenty on six cells.
	var settings := MapSettings.new()
	settings.width = 168
	settings.height = 194
	settings.player_slots = 20
	settings.seed = 1337
	settings.apply_preset(TerrainPresetRoster.by_id(&"islands"))

	var space := settings.to_space()
	var passable := settings.to_terrain().passability(space)
	var points := settings.to_spawn_config().spawn_points(passable)

	assert_eq(points.size(), 20,
		"The reported world seated 20 before the landmass rule and must still seat 20 after it")
	for point in points:
		assert_gte(_landmass(space, passable, point, 96), 96,
			"Spawn %s sits on a %d-cell island" % [
				point, _landmass(space, passable, point, 96)])


## How much walkable ground `from` connects to, counted no further than
## `cap`. Deliberately a second implementation rather than a call to
## MapConfig's: a test that asks the code under test for its own answer
## cannot see it being wrong (D-022's audit).
func _landmass(space: TorusSpace, passable: PackedByteArray, from: Vector2i, cap: int) -> int:
	var seen := {space.index(from): true}
	var queue := [from]
	var head := 0
	while head < queue.size() and seen.size() < cap:
		var at: Vector2i = queue[head]
		head += 1
		for neighbour in space.neighbors(at):
			var index := space.index(neighbour)
			if seen.has(index) or passable[index] == 0:
				continue
			seen[index] = true
			queue.append(neighbour)
	return seen.size()


func test_short_seating_is_reported_rather_than_silently_shared() -> void:
	# The failure this whole change came out of: twenty players wrapped
	# onto four grid seats and stood five-deep, and nothing said so.
	var config := _config()
	var space := config.to_space()

	var passable := PackedByteArray()
	passable.resize(config.width * config.height)
	for y in range(config.height):
		for x in range(config.width):
			# One habitable strip — far too little land for 20 starts 12 apart.
			passable[space.index(Vector2i(x, y))] = 1 if y < 4 else 0

	assert_ne(config.validate_spawns(passable), "",
		"A map that cannot seat its players must say so")
	assert_eq(config.validate_spawns(), "",
		"With no terrain constraint the same map seats everyone")


# --- map validation ----------------------------------------------------

func test_symmetry_order_must_divide_the_map() -> void:
	var config := _config()
	config.width = 127
	assert_false(config.is_valid(), "A width the symmetry order does not divide cannot tile into equal quadrants")


func test_quadrant_height_must_stay_even_for_row_parity() -> void:
	var config := _config()
	# 64x36 is a legal torus (even height) but 36/2 = 18... which IS even.
	# 64x68 -> 34, also even. Use a case where the map is even but the
	# quadrant is not: height 68 with symmetry 2 gives 34 (even), so go to
	# symmetry 2 and height 66 -> 33, odd.
	config.height = 66
	assert_false(config.is_valid(),
		"A quadrant of odd height shifts D-008's row parity across the repeat boundary")


func test_squad_cap_cannot_be_below_the_starting_allotment() -> void:
	var config := _config()
	config.squads_per_player = 12
	config.squad_cap = 8
	assert_false(config.is_valid(), "A player would spawn already over its own cap")


func test_spacing_that_cannot_possibly_fit_is_refused_up_front() -> void:
	# Caught by arithmetic at load, not by rejection sampling quietly
	# returning six points for twenty players.
	var config := _config()
	config.min_spawn_spacing = 40
	assert_false(config.is_valid(),
		"20 starts 40 cells apart do not fit an 8,192-cell map and the config should say so")


func test_the_shipped_default_map_is_valid() -> void:
	var config: MapConfig = load("res://maps/default.tres")
	assert_not_null(config, "maps/default.tres should load as a MapConfig")
	assert_eq(config.validate(), "", "The shipped map must satisfy its own rules")
	assert_eq(config.spawn_points().size(), 20,
		"The shipped map should seat twenty players (D-018's target concurrency)")
