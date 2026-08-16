extends SceneTree

## Prints every shipped scenario (D-098) — what `just scenarios` runs.
##
## Reads them through `Scenario.load_all()`, the same call the server and
## the test fixture use, so this listing cannot drift from what
## `--scenario` will actually accept.

func _init() -> void:
	var all := Scenario.load_all()
	if all.is_empty():
		print("no scenarios found under res://scenarios")
		quit(1)
		return

	print("Mid-game scenarios — `just test-scenario <id>` or `--scenario=<id>`:")
	print("")
	for def in all:
		var bad := def.validate()
		var status := "" if bad == "" else "  [INVALID: %s]" % bad
		print("  %-12s %d squads, %d buildings, separation %s%s" % [
			def.id, def.squad_count(), def.buildings.size(),
			"map spawns" if def.separation <= 0 else str(def.separation) + " cells",
			status])
		print("               %s" % def.description)
		print("")

	print("A scenario skips the opening, so it can never catch a bug in")
	print("founding, production or spawn placement. `just test-load 4 120`")
	print("still does, and is still the gate.")
	quit(0)
