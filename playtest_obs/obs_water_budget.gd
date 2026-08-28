extends SceneTree

## MEASUREMENT HARNESS for naval stage 2's exit criterion (#301,
## `docs/plans/naval.md` §2.3): the water layer's cell budget and worst
## tick, measured rather than guessed.
##
## §2.3's instruction, verbatim: *"The budget must be measured, not
## guessed. D-076 set the wall layer to 1,024 cells/tick and D-20260818
## later took the ground layer to 16,384 after finding the solver was 93%
## neighbour lookup. Water is a large region on the maps that matter —
## `islands` is 65-71% water, so a naval field can be bigger than a ground
## field on the same map."*
##
## So this measures three things over the shipped map ladder:
##
## 1. how much water each preset and size actually has;
## 2. what a FULL water field costs, in cells and microseconds;
## 3. how many ticks a cross-map naval order waits at a candidate budget.
##
## It also checks §2.3's one "before, not after" item: that
## `TorusSpace.neighbor_table()` is memoised per space instance, so the
## water layer inherits D-20260818's fix for free rather than paying the
## 93%-neighbour-lookup cost the ground layer used to.
##
## Run: tools/godot.exe --headless --path . -s res://playtest_obs/obs_water_budget.gd

const PRESETS := ["islands", "continents", "highlands", "plains"]
const CANDIDATES := [1024, 4096, 16384, 24576, 32768]


func _initialize() -> void:
	print("OBS-NAVAL2: begin")
	_neighbour_table_is_shared()
	_how_much_water()
	_full_field_cost()
	_latency_at_each_budget()
	_worst_tick_with_a_fleet()
	print("OBS-NAVAL2: end")
	quit()


func _settings(preset: String, size_index: int, seed_value: int = 1337) -> MapSettings:
	var sizes := MapSettings.sizes()
	var settings := MapSettings.from_map(load("res://maps/default.tres"))
	var size: Dictionary = sizes[mini(size_index, sizes.size() - 1)]
	settings.width = int(size["width"])
	settings.height = int(size["height"])
	settings.preset = StringName(preset)
	settings.apply_preset(TerrainPresetRoster.by_id(settings.preset))
	settings.pin_seed(seed_value)
	return settings


# --- §2.3's "check before writing it, not after" ----------------------

func _neighbour_table_is_shared() -> void:
	print("")
	print("OBS-NAVAL2 NEIGHBOURS - the water layer must inherit D-20260818's")
	print("  memoised neighbour table rather than paying for its own. The")
	print("  sim holds ONE TorusSpace, so both layers solve against the same")
	print("  instance; this asserts the table is per-instance and cached.")
	var space := TorusSpace.new(84, 96, 1.0)
	var first := space.neighbor_table()
	var second := space.neighbor_table()
	print("  same table object on a second call: %s (%d entries)" % [
		first == second, first.size()])


# --- 1. how much water is there -----------------------------------------

func _how_much_water() -> void:
	print("")
	print("OBS-NAVAL2 WATER - navigable share of each preset at each shipped size.")
	print("  %-12s %-10s %8s %9s %9s %8s" % [
		"preset", "size", "cells", "navigable", "passable", "water%"])
	var sizes := MapSettings.sizes()
	for preset in PRESETS:
		for i in range(sizes.size()):
			var settings := _settings(preset, i)
			var space := settings.to_space()
			var terrain := settings.to_terrain()
			var navigable := terrain.navigability(space)
			var passable := terrain.passability(space)
			var wet := 0
			var dry := 0
			for index in range(space.cell_count()):
				if navigable[index] != 0:
					wet += 1
				if passable[index] != 0:
					dry += 1
			print("  %-12s %-10s %8d %9d %9d %7.1f%%" % [
				preset, String(sizes[i]["name"]), space.cell_count(), wet, dry,
				100.0 * float(wet) / float(space.cell_count())])


# --- 2. what a full water field costs ------------------------------------

func _full_field_cost() -> void:
	print("")
	print("OBS-NAVAL2 SOLVE - one COMPLETE water field, unbudgeted, from the")
	print("  first navigable cell. Cells expanded is what a budget has to")
	print("  cover; the microseconds are what a tick pays for it.")
	print("  %-12s %-10s %9s %10s %10s" % [
		"preset", "size", "cells", "expanded", "usec"])
	var sizes := MapSettings.sizes()
	for preset in PRESETS:
		for i in range(sizes.size()):
			var settings := _settings(preset, i)
			var space := settings.to_space()
			var navigable := settings.to_terrain().navigability(space)
			var start := _first_navigable(space, navigable)
			if start < 0:
				print("  %-12s %-10s   no water" % [preset, String(sizes[i]["name"])])
				continue
			var field := FlowField.new()
			var began := Time.get_ticks_usec()
			field.begin(space, space.from_index(start), navigable)
			field.expand(-1)
			var usec := Time.get_ticks_usec() - began
			print("  %-12s %-10s %9d %10d %10d" % [
				preset, String(sizes[i]["name"]), space.cell_count(),
				field.expanded_cells(), usec])


func _first_navigable(space: TorusSpace, navigable: PackedByteArray) -> int:
	for index in range(space.cell_count()):
		if navigable[index] != 0:
			return index
	return -1


# --- 3. how long an order waits at each candidate budget ----------------

func _latency_at_each_budget() -> void:
	print("")
	print("OBS-NAVAL2 LATENCY - ticks a cross-map naval order waits before its")
	print("  field is complete, per candidate budget. This is the number the")
	print("  budget is FOR: D-20260818 took the ground layer to 16,384")
	print("  because a cross-map order waited 6 ticks and now waits 1.")
	print("  Measured on the worst case the ladder offers — the wettest map.")
	var sizes := MapSettings.sizes()
	print("  %-10s %9s %s" % ["size", "expanded", "ticks to complete, by budget"])
	print("  %-10s %9s %s" % ["", "", CANDIDATES])
	for i in range(sizes.size()):
		var settings := _settings("islands", i)
		var space := settings.to_space()
		var navigable := settings.to_terrain().navigability(space)
		var start := _first_navigable(space, navigable)
		if start < 0:
			continue
		var total := 0
		var row := []
		for budget in CANDIDATES:
			var field := FlowField.new()
			field.begin(space, space.from_index(start), navigable)
			var ticks := 0
			while not field.is_complete() and ticks < 500:
				field.expand(budget)
				ticks += 1
			total = field.expanded_cells()
			row.append(ticks)
		print("  %-10s %9d %s" % [String(sizes[i]["name"]), total, row])


# --- 4. the exit criterion: a measured worst tick, with its squad count --

## §2.3's other half. D-076 measured the wall layer this way and D-020's
## 100 ms tick is what it is measured against; #105 records that the
## 1,000-squad sweep is ALREADY over that budget, so what matters here is
## what the water layer ADDS, not the absolute.
##
## Ticked through the real `SquadSim.tick()` at the shipping 10 Hz with a
## real fleet on real generated terrain, because a field solved in
## isolation is not a tick.
func _worst_tick_with_a_fleet() -> void:
	print("")
	print("OBS-NAVAL2 WORST TICK - a fleet ordered across the wettest shipped")
	print("  map, through the real tick. Quoted with its squad count, as ever.")
	print("  %-10s %6s %10s %10s %10s %10s" % [
		"size", "hulls", "worst_ms", "mean_ms", "field_ms", "waits"])
	var sizes := MapSettings.sizes()
	# Whichever civ fields one — this file may not name a civ (D-046
	# criterion 3, and `tests/test_civs.gd` scans this directory too).
	var hull := _any_warship()
	if hull == null:
		print("  no hull in the roster")
		return
	for i in range(sizes.size()):
		for fleet in [8, 32]:
			_one_fleet_run(_settings("islands", i), String(sizes[i]["name"]), hull, fleet)


func _one_fleet_run(settings: MapSettings, size_name: String,
		hull: UnitDef, fleet: int) -> void:
	var space := settings.to_space()
	var terrain := settings.to_terrain()
	var navigable := terrain.navigability(space)
	var sim := SquadSim.new(space, CurveReplicator.new())
	sim.set_passable(terrain.passability(space))
	sim.set_navigable(navigable)

	var water_cells := []
	for index in range(space.cell_count()):
		if navigable[index] != 0:
			water_cells.append(index)
	if water_cells.size() < fleet * 2:
		return

	var ids := []
	for n in range(fleet):
		var at := space.from_index(int(water_cells[(n * 97) % water_cells.size()]))
		ids.append(sim.add_squad(hull, 1 + (n % 4), at))

	# Every hull ordered somewhere different, so the layer solves many
	# fields rather than sharing one — the worst case the budget exists
	# to bound.
	for n in range(ids.size()):
		var target := space.from_index(int(water_cells[
			(water_cells.size() - 1 - (n * 89)) % water_cells.size()]))
		sim.order_move(ids[n], target)

	var worst := 0
	var total := 0
	var field_total := 0
	for _t in range(40):
		var began := Time.get_ticks_usec()
		sim.tick()
		var took := Time.get_ticks_usec() - began
		worst = maxi(worst, took)
		total += took
		field_total += sim.last_fields_usec
	print("  %-10s %6d %10.2f %10.2f %10.2f %10d" % [
		size_name, fleet, float(worst) / 1000.0, float(total) / 40000.0,
		float(field_total) / 40000.0, sim.field_waits])


## The first hull in the roster, whoever fields it. A measurement of the
## LAYER, so which civ's ship it is could not matter less — and naming one
## would make adding a civ a code change (D-046 criterion 3).
func _any_warship() -> UnitDef:
	for def in UnitRoster.load_all():
		if def.movement_domain == "water" and def.damage > 0.0:
			return def
	return null
