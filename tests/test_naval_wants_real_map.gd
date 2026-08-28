extends GutTest

## Does the naval predicate fire on a REAL generated map (#351)?
##
## The gap between `tests/test_ai_naval.gd` and a played ladder match.
## Those tests hand `needs_ships` hand-built component labels, which
## proves the rule and says nothing about whether generated terrain ever
## produces inputs that satisfy it — and the whole of #351 was the
## predicate being right and never firing.
##
## So this generates the shipped map at a water preset, takes a REAL
## spawn point, and asks the real question with the real numbers.


func _islands(width: int, height: int, seed_value: int) -> Dictionary:
	var def := TerrainPresetRoster.by_id(&"islands")
	assert_not_null(def, "the islands preset must still exist")
	var settings := MapSettings.new()
	settings.apply_preset(def)
	settings.width = width
	settings.height = height
	settings.seed = seed_value
	var space := TorusSpace.new(width, height, 1.0)
	var terrain := settings.to_terrain()
	var passable := terrain.passability(space)
	var components: Dictionary = MapConfig.walkable_components(space, passable)
	return {"space": space, "settings": settings, "passable": passable,
		"labels": components["labels"], "sizes": components["sizes"]}


func test_a_real_islands_map_offers_somewhere_worth_sailing_to() -> void:
	# The precondition for legs 2 and 3 of the naval gate's acceptance. If
	# a generated water map has only one landmass worth having, no AI can
	# ever want a navy on it however correct the predicate — which is what
	# `maps/ladder.tres` at islands turned out to be.
	var w := _islands(168, 194, 1337)
	var sizes: PackedInt32Array = w["sizes"]
	var minimum := int(w["settings"].min_spawn_landmass)

	var worthwhile := 0
	var largest := 0
	for i in range(sizes.size()):
		largest = maxi(largest, sizes[i])
		if sizes[i] >= minimum:
			worthwhile += 1
	gut.p("islands 168x194 seed 1337: %d landmasses >= %d cells, largest %d"
		% [worthwhile, minimum, largest])
	assert_gt(worthwhile, 1,
		"a water map must offer more than one landmass worth settling, or naval "
		+ "is unreachable on it whatever the AI decides")


func test_an_ai_at_a_real_spawn_point_wants_a_navy() -> void:
	# The predicate, against generated terrain and a real start rather
	# than a fixture. `has_scouted` true and no known enemy is the state
	# #351 deadlocked on: the AI has looked, found nobody, and there is
	# somewhere it cannot walk to.
	var w := _islands(168, 194, 1337)
	var settings: MapSettings = w["settings"]
	var spawns: Array = settings.to_spawn_config().spawn_points(w["passable"])
	assert_gt(spawns.size(), 0, "the map must seat somebody at all")

	var home: int = (w["space"] as TorusSpace).index(spawns[0])
	assert_true(AiNaval.needs_ships(w["labels"], home, [], true,
			w["sizes"], settings.min_spawn_landmass),
		"an AI that has scouted its own island and found nobody, with other "
		+ "landmasses it cannot walk to, must want ships — this is the live "
		+ "form of #351 and the precondition for the gate's passing leg")


func test_the_same_ai_before_scouting_still_wants_nothing() -> void:
	# The guard, on the same real map: the fix must not have turned into
	# "build a navy on any water map".
	var w := _islands(168, 194, 1337)
	var settings: MapSettings = w["settings"]
	var spawns: Array = settings.to_spawn_config().spawn_points(w["passable"])
	var home: int = (w["space"] as TorusSpace).index(spawns[0])
	assert_false(AiNaval.needs_ships(w["labels"], home, [], false,
			w["sizes"], settings.min_spawn_landmass),
		"before it has looked, an AI concludes nothing from its ignorance")


func test_the_shipped_default_map_offers_nothing_worth_sailing_to() -> void:
	# 88's measurement, turned into a check: `continents` has 8-16
	# landmasses a squad cannot walk to, and NOT ONE of them can hold a
	# start. If "there is land I cannot reach on foot" were the whole
	# clause, every AI on the map people actually play would fund a dock
	# and a transport to reach an uninhabitable rock — the "no navy on
	# ignorance" guard defeated through the new door instead of the old.
	#
	# What stops it is the size filter, which reuses D-104's own
	# min_spawn_landmass rather than inventing a threshold.
	var settings := MapSettings.new()
	var cfg: MapConfig = load("res://maps/default.tres")
	settings.width = cfg.width
	settings.height = cfg.height
	settings.seed = 1337
	settings.player_slots = 20
	settings.apply_preset(TerrainPresetRoster.by_id(&"continents"))
	var space := TorusSpace.new(settings.width, settings.height)
	var fields: TerrainFields = settings.to_terrain().build_fields(space)
	var passable: PackedByteArray = fields.passable
	var config := settings.to_spawn_config()
	var points := config.spawn_points(passable)
	assert_gt(points.size(), 0, "premise: the shipped map seats somebody")

	var comps := MapConfig.walkable_components(space, passable)
	var labels: PackedInt32Array = comps["labels"]
	var sizes: PackedInt32Array = comps["sizes"]
	var home := space.index(points[0])

	var elsewhere := 0
	var mine := AiNaval.component_of(labels, home)
	for label in range(sizes.size()):
		if label != mine and sizes[label] >= config.min_spawn_landmass:
			elsewhere += 1
	gut.p("default continents %dx%d: %d component(s) >= %d cells besides home" % [
		settings.width, settings.height, elsewhere, config.min_spawn_landmass])

	# Scouted, nobody found — the one state that can reach the new clause.
	assert_false(AiNaval.needs_ships(labels, home, [], true, sizes,
		config.min_spawn_landmass),
		"no AI may fund a navy to reach rocks nobody could start on")


func test_a_caller_that_forgets_the_sizes_gets_no_navy_rather_than_always() -> void:
	# The trap under the clause. `land_sizes` and `min_landmass` are
	# optional, and an empty sizes array must not read as "every
	# component qualifies" — that turns a forgotten argument into a
	# fleet, which is the D-055 family with an outbound invoice.
	# `bot_naval.gd` calls needs_ships with three arguments today.
	var space := TorusSpace.new(24, 12)
	var passable := PackedByteArray()
	passable.resize(space.cell_count())
	passable.fill(1)
	for r in range(space.height):
		passable[space.index(Vector2i(6, r))] = 0
		passable[space.index(Vector2i(18, r))] = 0
	var comps := MapConfig.walkable_components(space, passable)
	var labels: PackedInt32Array = comps["labels"]
	var home := space.index(Vector2i(2, 4))

	assert_false(AiNaval.needs_ships(labels, home, [], true),
		"unknown sizes must decide nothing, the same way ignorance does")
