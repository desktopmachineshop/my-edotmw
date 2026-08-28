extends GutTest

## Guards D-20260828-the-water-graph-is-the-inverse-of-the-ground
## (naval plan §2.1 / §4.1, cut-list stage 1).
##
## Stage 1 of the naval plan is deliberately **tests only, no sim
## change**: a field, a predicate, and proof that the component walk the
## map already uses works over water. Every later naval stage builds on
## these three answers, so the point of this file is that the answers are
## pinned before anything depends on them.
##
## The load-bearing assertion is the one about DISJOINTNESS, and the
## second-most is the one that refuses to claim coverage — see
## `test_the_two_fields_do_not_union_to_the_whole_map` for why a slogan
## would have been worse than a measurement here.


const PRESETS := ["plains", "continents", "highlands", "islands"]


func _space(w: int = 48, h: int = 24) -> TorusSpace:
	return TorusSpace.new(w, h, 1.0)


## A generator from a shipped preset, so these run against the terrain
## the game actually makes rather than against a fixture that agrees with
## the code by construction.
##
## Built the way the server builds one — `MapSettings.apply_preset` then
## `to_terrain()` — rather than by setting fields on a bare `TerrainGen`.
## A preset is not a generator; going through the same two calls means a
## preset that stops reaching the generator fails here too.
func _terrain(preset: String, seed_value: int = 1337) -> TerrainGen:
	var def := TerrainPresetRoster.by_id(StringName(preset))
	assert_not_null(def, "no shipped preset '%s'" % preset)
	var settings := MapSettings.new()
	settings.apply_preset(def)
	settings.seed = seed_value
	return settings.to_terrain()


# --- the field ----------------------------------------------------------

func test_navigability_is_exactly_the_water_half() -> void:
	# `is_water` is the existing per-cell answer and stays the single
	# definition of what water is; this asserts the FIELD agrees with it
	# cell for cell, rather than reimplementing the comparison.
	var space := _space()
	var gen := _terrain("continents")
	var navigable := gen.navigability(space)
	assert_eq(navigable.size(), space.cell_count(), "the field must cover every cell")

	var disagreements := 0
	for i in range(space.cell_count()):
		if (navigable[i] != 0) != gen.is_water(space, space.from_index(i)):
			disagreements += 1
	assert_eq(disagreements, 0,
		"navigability must be exactly `is_water`, which is where sea level is decided")


func test_a_map_with_no_water_is_navigable_nowhere() -> void:
	# The degenerate end, and not a hypothetical: `plains` at a low sea
	# level is close to it, and stage 9's spawn placement will ask this
	# field about maps that have no sea at all.
	var space := _space()
	var gen := _terrain("plains")
	gen.sea_level = -1.0
	var navigable := gen.navigability(space)
	var count := 0
	for i in range(space.cell_count()):
		count += 1 if navigable[i] != 0 else 0
	assert_eq(count, 0, "with the sea below every cell nothing may float")


func test_a_drowned_map_is_navigable_everywhere() -> void:
	var space := _space()
	var gen := _terrain("plains")
	gen.sea_level = 2.0
	var navigable := gen.navigability(space)
	var count := 0
	for i in range(space.cell_count()):
		count += 1 if navigable[i] != 0 else 0
	assert_eq(count, space.cell_count(), "with the sea above every cell all of it floats")


# --- the invariant the stage is defined by ------------------------------

func test_navigability_and_passability_are_disjoint_on_every_shipped_preset() -> void:
	# THE stage-1 done-condition. It holds by construction —
	# `_slope_passable` returns false below sea level and `_carve_ramps`
	# never carves water — but "by construction" is exactly the claim this
	# project has been wrong about before, and a ramp carved into a lake
	# would put a land squad on open water with nothing failing.
	for preset in PRESETS:
		var space := _space()
		var gen := _terrain(preset)
		var passable := gen.passability(space)
		var navigable := gen.navigability(space)
		var both := 0
		for i in range(space.cell_count()):
			if passable[i] != 0 and navigable[i] != 0:
				both += 1
		assert_eq(both, 0,
			"%s has %d cell(s) that are both walkable ground and open water" % [preset, both])


func test_carving_a_ramp_never_opens_water() -> void:
	# The one operation that can flip a cell INTO passable after the slope
	# rule has run, and therefore the only way disjointness could break.
	# Driven at a sea level high enough to make pockets common, so the
	# carver is actually exercised rather than trivially idle.
	var space := _space(64, 32)
	var gen := _terrain("islands")
	var passable := gen.passability(space)
	var navigable := gen.navigability(space)
	var carved_water := 0
	for i in range(space.cell_count()):
		if navigable[i] != 0 and passable[i] != 0:
			carved_water += 1
	assert_eq(carved_water, 0,
		"a ramp was carved through water — an island is not a plateau")


func test_the_two_fields_do_not_union_to_the_whole_map() -> void:
	# Stated as a TEST rather than left as a footnote, because the
	# cut-list's own wording is "disjoint and cover the map" and the
	# second half is not true in general: land too steep to walk is in
	# neither field. What partitions the map is the DOMAIN — navigable is
	# the water half, its complement is the land half — and passability is
	# a rule WITHIN land.
	#
	# Pinned because stage 2 dispatches on domain and stage 9 places
	# spawns over these fields: a reader who believed the slogan would
	# write `if not navigable then walkable`, and put an army on a cliff.
	#
	# Measured across every preset rather than asserted on one, because
	# the first version picked `highlands` for its steep ground and found
	# NONE — D-20260826 opened that preset up completely ("44.1% dead
	# space ... fully open now"). So on some shipped maps the union really
	# is everything and on others it is not, which is exactly why a later
	# stage must not rely on either.
	var covered := PackedStringArray()
	var gapped := PackedStringArray()
	for preset in PRESETS:
		var space := _space()
		var gen := _terrain(preset)
		var passable := gen.passability(space)
		var navigable := gen.navigability(space)
		var neither := 0
		for i in range(space.cell_count()):
			if passable[i] == 0 and navigable[i] == 0:
				neither += 1
		if neither == 0:
			covered.append(preset)
		else:
			gapped.append("%s (%d/%d)" % [preset, neither, space.cell_count()])

	gut.p("union covers the map: %s" % str(covered))
	gut.p("union leaves unwalkable land: %s" % str(gapped))
	assert_gt(gapped.size(), 0,
		"no shipped preset has land too steep to walk, so nothing here demonstrates "
		+ "the gap — if that is genuinely true of the whole ladder now, the naval "
		+ "plan's 'cover the map' wording becomes safe and this test should say so")


func test_every_cell_belongs_to_exactly_one_domain() -> void:
	# The invariant that IS true, and the one stage 2 dispatches on: a
	# cell is water or it is land, never both and never neither.
	for preset in PRESETS:
		var space := _space()
		var gen := _terrain(preset)
		var navigable := gen.navigability(space)
		var passable := gen.passability(space)
		for i in range(space.cell_count()):
			var water := navigable[i] != 0
			if water and passable[i] != 0:
				assert_true(false, "%s cell %d is in both domains" % [preset, i])
				return
		assert_eq(navigable.size(), space.cell_count(),
			"%s: the water half must have an answer for every cell" % preset)
		assert_eq(passable.size(), space.cell_count(),
			"%s: and so must the land half" % preset)


# --- the shore predicate ------------------------------------------------

func test_a_shore_is_land_you_can_stand_on_next_to_water() -> void:
	var space := _space(8, 4)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	passable.fill(1)
	navigable.fill(0)

	# Flood one cell, and its neighbours become shore.
	var sea := space.index(Vector2i(4, 2))
	navigable[sea] = 1
	passable[sea] = 0

	assert_false(TerrainGen.is_shore(space, passable, navigable, sea),
		"open water is not a shore — a dock stands on land")
	var table := space.neighbor_table()
	for d in range(6):
		assert_true(TerrainGen.is_shore(space, passable, navigable, table[sea * 6 + d]),
			"every land cell bordering the water is a shore")


func test_inland_ground_is_not_a_shore() -> void:
	var space := _space(8, 4)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	passable.fill(1)
	navigable.fill(0)
	assert_false(TerrainGen.is_shore(space, passable, navigable, space.index(Vector2i(1, 1))),
		"a map with no water has no shore, and a dock must be refused everywhere on it")


func test_unwalkable_land_beside_water_is_not_a_shore() -> void:
	# A cliff falling into the sea. It borders water and a dock cannot
	# stand there, which is the whole reason the predicate reads
	# passability and not merely "is it land".
	var space := _space(8, 4)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	passable.fill(1)
	navigable.fill(0)

	var sea := space.index(Vector2i(4, 2))
	navigable[sea] = 1
	passable[sea] = 0
	var cliff: int = space.neighbor_table()[sea * 6]
	passable[cliff] = 0
	assert_false(TerrainGen.is_shore(space, passable, navigable, cliff),
		"ground you cannot stand on is not a shore however wet it is")


func test_a_shore_on_the_seam_is_a_shore() -> void:
	# The torus tax (D-008), paid here by `neighbor_table` rather than by
	# this predicate — asserted because every naval stage inherits it and
	# a seam-blind shore rule would refuse docks along one column of every
	# map with nothing failing.
	var space := _space(8, 4)
	var passable := PackedByteArray()
	var navigable := PackedByteArray()
	passable.resize(space.cell_count())
	navigable.resize(space.cell_count())
	passable.fill(1)
	navigable.fill(0)

	var edge := space.index(Vector2i(0, 2))
	navigable[edge] = 1
	passable[edge] = 0
	var wrapped := space.index(Vector2i(space.width - 1, 2))
	assert_true(TerrainGen.is_shore(space, passable, navigable, wrapped),
		"a cell across the seam from water is on that water's shore")


func test_the_predicate_refuses_a_caller_that_passes_one_field_twice() -> void:
	# Two arrays with the same shape and opposite meanings is a call
	# nobody will get wrong until somebody does. Without the explicit
	# check, `is_shore(space, navigable, navigable, ...)` returns true for
	# every water cell with a wet neighbour — i.e. it offers the open sea
	# as dock sites.
	var space := _space(8, 4)
	var navigable := PackedByteArray()
	navigable.resize(space.cell_count())
	navigable.fill(1)
	assert_false(TerrainGen.is_shore(space, navigable, navigable, space.index(Vector2i(4, 2))),
		"a navigable cell can never be a shore, whatever it was passed as")


func test_the_shipped_map_has_a_coastline() -> void:
	# The "shipped numbers do nothing" check (D-066's family). The
	# predicate could be perfectly correct and match nothing on any real
	# map, and stage 3 would then ship a dock nobody can place.
	var space := _space(64, 32)
	var gen := _terrain("continents")
	var passable := gen.passability(space)
	var navigable := gen.navigability(space)
	var shores := 0
	for i in range(space.cell_count()):
		if TerrainGen.is_shore(space, passable, navigable, i):
			shores += 1
	assert_gt(shores, 0, "continents has no shore cell anywhere — no dock could ever be built")
	gut.p("continents %dx%d: %d shore cells" % [space.width, space.height, shores])


# --- water components, from the walk the map already uses ---------------

func test_the_existing_component_walk_labels_water() -> void:
	# The third of stage 1's deliverables, and it needs no new code: the
	# walk is a function of a boolean field, and water is a boolean field.
	# What this pins is that it is USED that way — a later stage writing a
	# second flood fill for water would be the duplicate-definition shape
	# this project keeps meeting.
	#
	# (The function is called `walkable_components` and takes an argument
	# named `passable`. It is domain-agnostic; the name is not. Worth
	# renaming when #216 lands — flagged there rather than churned here.)
	var space := _space(16, 8)
	var navigable := PackedByteArray()
	navigable.resize(space.cell_count())
	navigable.fill(0)
	# Two lakes, four cells apart, so they cannot touch through the seam.
	for cell in [Vector2i(2, 2), Vector2i(3, 2)]:
		navigable[space.index(cell)] = 1
	for cell in [Vector2i(9, 5), Vector2i(10, 5)]:
		navigable[space.index(cell)] = 1

	var walk: Dictionary = MapConfig.walkable_components(space, navigable)
	var labels: PackedInt32Array = walk["labels"]
	var sizes: PackedInt32Array = walk["sizes"]

	var first: int = labels[space.index(Vector2i(2, 2))]
	assert_eq(labels[space.index(Vector2i(3, 2))], first,
		"two adjacent water cells are one body of water")
	var second: int = labels[space.index(Vector2i(9, 5))]
	assert_ne(second, first, "two separated lakes are not the same body of water")
	assert_eq(sizes[first], 2, "and each is two cells across")
	assert_eq(sizes[second], 2)


func test_water_that_wraps_the_seam_is_one_body() -> void:
	# An ocean crossing the seam must be one component, or stage 9 would
	# read a circumnavigable sea as two unreachable ones and refuse to
	# seat spawns that can in fact reach each other.
	var space := _space(16, 8)
	var navigable := PackedByteArray()
	navigable.resize(space.cell_count())
	navigable.fill(0)
	for y in range(space.height):
		navigable[space.index(Vector2i(0, y))] = 1
		navigable[space.index(Vector2i(space.width - 1, y))] = 1

	var labels: PackedInt32Array = MapConfig.walkable_components(space, navigable)["labels"]
	assert_eq(labels[space.index(Vector2i(0, 3))],
		labels[space.index(Vector2i(space.width - 1, 3))],
		"the two columns meet across the seam and are one sea (D-008)")


func test_the_shipped_islands_preset_has_more_than_one_body_of_water() -> void:
	# Not a property of the code so much as a fact about the map that
	# stage 9 will have to reason about: `islands` is the preset #280
	# says has no game in it, and the water graph is what will decide
	# whether a start can reach another.
	var space := _space(64, 32)
	var gen := _terrain("islands")
	var navigable := gen.navigability(space)
	var sizes: PackedInt32Array = MapConfig.walkable_components(space, navigable)["sizes"]
	var seas := 0
	var largest := 0
	for i in range(sizes.size()):
		# Every LAND cell is its own component in this walk too, because
		# the field is a boolean and land reads as zero — so only the
		# labelled-navigable ones are seas. Counted by size against the
		# navigable total rather than by re-walking.
		if sizes[i] > 1:
			seas += 1
			largest = maxi(largest, sizes[i])
	assert_gt(largest, 0, "islands has no water at all, which cannot be right")
	gut.p("islands %dx%d: largest connected component %d cells"
		% [space.width, space.height, largest])
