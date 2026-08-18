extends GutTest

## Guards D-20260818-the-sweep-follows-the-ladder (#108): `just profile`
## must sweep the sizes the game actually ships.
##
## The sweep is this project's only authority on how the simulation
## SCALES — a live match cannot reach D-018's ~1,000 squads, so every
## scaling claim in M4's status file comes from here. It kept its OWN list
## of map sizes, and the shipped ladder moved twice underneath it: by
## 2026-08-17 the sweep's largest map (32,768 cells) was the DEFAULT one
## players get and the top three quarters of the ladder — up to 130,368
## cells — had never been swept at all.
##
## Nothing failed, which is the point. The sweep was green throughout and
## answering a question about maps nobody plays: the declared-and-unread
## family (CLAUDE.md's standing warning) applied to an INSTRUMENT rather
## than to a mechanic. Two lists that must agree, written down twice.
##
## `MapSettings.sizes()` is the one definition of what ships, so this file
## asserts the sweep is derived from it rather than merely equal to it
## today — adding a rung to the ladder must add a row to the sweep.


func _sweep_sizes() -> Array:
	var sweep: GDScript = load("res://profile_sweep.gd")
	assert_true(sweep.has_method("map_sizes"),
		"profile_sweep.gd must expose the sizes it sweeps, or nothing can check them")
	return sweep.map_sizes()


func test_sweep_covers_every_shipped_size() -> void:
	var swept := _sweep_sizes()
	for entry in MapSettings.sizes():
		var size := Vector2i(int(entry["width"]), int(entry["height"]))
		assert_true(swept.has(size),
			"the shipped %s map (%dx%d = %d cells) is never swept" % [
				entry["name"], size.x, size.y, size.x * size.y])


## The ladder's ends, spelled out, because they are the claim the exit
## criterion is written in (D-20260817-m10-scale-optimisation, 5).
func test_sweep_spans_the_shipped_cell_range() -> void:
	var smallest := 1 << 30
	var largest := 0
	for size in _sweep_sizes():
		smallest = mini(smallest, size.x * size.y)
		largest = maxi(largest, size.x * size.y)
	assert_eq(smallest, 8064, "the sweep must start at the Skirmish map")
	assert_eq(largest, 130368, "the sweep must reach the Huge map")


## Every swept size must be a LEGAL world, not just a pair of numbers —
## D-008's row parity above all, since an odd height makes the torus
## neighbour arithmetic wrong rather than merely unusual.
func test_every_swept_size_is_a_playable_world() -> void:
	for size in _sweep_sizes():
		var space := TorusSpace.new(size.x, size.y, 1.0)
		assert_eq(space.validate(), "",
			"%dx%d is not a world the game would generate" % [size.x, size.y])
