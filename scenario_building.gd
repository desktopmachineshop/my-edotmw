class_name ScenarioBuilding
extends Resource

## One building in a scenario's per-player loadout (D-098).
##
## Position is an OFFSET from the player's home cell, not an absolute
## cell, so the same loadout drops onto any map at any spawn point. The
## applier resolves it to a real cell and nudges it to the nearest free
## passable one, so an offset that lands in water or on top of another
## building still produces a playable world instead of a silent nothing.

## The BuildingDef id — the .tres basename under /buildings/, e.g.
## `town_centre`. Resolved through BuildingSim.def_by_id, the same call
## the server uses, so a scenario cannot name a building the game does
## not have.
@export var building: StringName = &""

## Cells from the player's home. Vector2i(0, 0) is the home cell itself.
@export var offset: Vector2i = Vector2i.ZERO

## Finished and working, versus a construction site the sim still has to
## advance. Default true: a scenario exists to skip the waiting, and a
## test that wants to watch construction should say so explicitly.
@export var complete: bool = true

## Starting health as a fraction of max. 1.0 unless a test wants a
## building that is already hurt — the cheap way to test destruction
## without first spending a minute knocking one down.
@export_range(0.0, 1.0) var health_fraction: float = 1.0


func validate() -> String:
	if building == &"":
		return "building id is empty"
	if BuildingSim.def_by_id(building) == null:
		return "no BuildingDef '%s' under /buildings" % building
	if health_fraction <= 0.0:
		return "health_fraction %f would spawn a destroyed building" % health_fraction
	return ""
