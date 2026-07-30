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


# --- derived spawn points (D-036) -------------------------------------

func _config() -> MapConfig:
	var c := MapConfig.new()
	c.width = 128
	c.height = 64
	c.symmetry_order = 2
	c.spawn_offset = Vector2i(16, 8)
	return c


func test_spawn_points_are_one_per_quadrant_at_the_same_offset() -> void:
	var config := _config()
	var points := config.spawn_points()

	assert_eq(points.size(), 4, "A symmetry_order of 2 seats four players")
	assert_eq(config.player_capacity(), 4)

	# Every spawn must sit at the same position WITHIN its quadrant —
	# that, plus identical quadrant terrain, is the whole fairness claim.
	var quadrant_width := config.width / config.symmetry_order
	var quadrant_height := config.height / config.symmetry_order
	for point in points:
		assert_eq(point.x % quadrant_width, config.spawn_offset.x,
			"Spawn %s is not at the configured offset within its quadrant" % point)
		assert_eq(point.y % quadrant_height, config.spawn_offset.y,
			"Spawn %s is not at the configured offset within its quadrant" % point)


func test_spawn_points_are_distinct() -> void:
	var seen := {}
	for point in _config().spawn_points():
		assert_false(seen.has(point), "Two players would spawn on the same cell %s" % point)
		seen[point] = true


func test_spawn_terrain_is_identical_for_every_player() -> void:
	# The claim that actually matters, tested end to end rather than
	# inferred from the two properties separately: whatever the terrain is
	# under player 0's start, it is the same under everyone else's.
	var config := _config()
	var space := config.to_space()
	var terrain := _terrain(config.symmetry_order)
	var points := config.spawn_points()

	var reference := terrain.elevation_at(space, points[0])
	for i in range(1, points.size()):
		assert_almost_eq(terrain.elevation_at(space, points[i]), reference, 0.0001,
			"Player %d starts on different ground than player 0" % i)


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


func test_spawn_offset_must_lie_inside_one_quadrant() -> void:
	var config := _config()
	config.spawn_offset = Vector2i(64, 8)  # exactly one quadrant wide
	assert_false(config.is_valid(), "An offset outside the quadrant would not tile symmetrically")


func test_the_shipped_default_map_is_valid() -> void:
	var config: MapConfig = load("res://maps/default.tres")
	assert_not_null(config, "maps/default.tres should load as a MapConfig")
	assert_eq(config.validate(), "", "The shipped map must satisfy its own rules")
	assert_eq(config.spawn_points().size(), 4, "The shipped map should seat four players (D-015)")
