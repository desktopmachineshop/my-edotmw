class_name ScenarioSquad
extends Resource

## One entry in a scenario's per-player squad loadout (D-098).
##
## Names an ARCHETYPE, never a unit id and never a civ. `militia` means
## "whatever this player's civilization fields as militia", resolved
## through `UnitRoster.for_civ_archetype` — the same call the server's own
## opening uses. That is what lets one scenario file play for every civ,
## and it is why no scenario needs to name a civ (which a test forbids in
## .gd files anyway).

## The archetype: `gatherers`, `militia`, `general`, ... See
## `UnitRoster.archetypes_for(civ)` for what a given civ fields.
@export var archetype: StringName = &""

## How many squads of it.
@export var count: int = 1

## Cells from the player's home cell. Squads beyond the first fan out
## around this offset, nearest free cell first, so `count: 5` does not
## stack five squads on one cell.
@export var offset: Vector2i = Vector2i.ZERO

## Survivors, or -1 for a full-strength squad. A scenario that wants to
## test routing or a last stand can start a squad already bloodied
## instead of spending a minute of simulated combat getting there.
@export var alive: int = -1

## Formation shape override, or "" for the UnitDef's own. A player's
## choice of shape is latched state the sim must not overwrite (D-065),
## so a scenario that sets it is exercising the same latch a player's
## button does.
@export var shape: String = ""


func validate() -> String:
	if archetype == &"":
		return "archetype is empty"
	if count <= 0:
		return "count %d spawns nothing" % count
	if alive == 0:
		return "alive 0 spawns a dead squad — use count 0 to spawn none"
	return ""
