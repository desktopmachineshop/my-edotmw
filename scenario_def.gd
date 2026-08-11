class_name ScenarioDef
extends Resource

## A mid-game world, as DATA (D-076).
##
## The problem this solves: the real opening is slow on purpose. A player
## starts with one founding party and no base, a town hall takes 40
## seconds and consumes the founders (D-031), production runs after that,
## and spawns are scattered far apart on a 128x64 map (D-039). So the
## cheapest honest test of anything downstream of the opening costs about
## two minutes of waiting before the thing under test even exists.
##
## A scenario says "start here instead": bases already standing, armies
## already within reach of each other, wallets already full. It is applied
## through the REAL SquadSim / BuildingSim / Economy calls the server uses
## — never a parallel re-implementation. That distinction is the whole
## reason this is trustworthy: M4's `profile` sweep reported a healthy
## 29 ms for code that spent 866 ms in a live server, because the sweep
## resolved its UnitDefs once at setup and the server did not. A harness
## that builds the world its own way measures its own way of building it.
##
## What a scenario CANNOT see, by construction: founding, production
## timing, and the opening itself. Those are exactly what it skips. So
## `just test-load 4 120` keeps running the real opening and stays the
## gate a change must pass — a scenario is for iterating, not for
## declaring something works.

## Stable id. Also what `--scenario=<id>` names, and what the server
## prints so no run can silently be a scenario run.
@export var id: StringName = &""

## What this scenario is FOR, in one line. Shown by `just scenarios`.
@export var description: String = ""

## Buildings every player starts with, placed relative to their home.
@export var buildings: Array[ScenarioBuilding] = []

## Squads every player starts with, placed relative to their home.
@export var squads: Array[ScenarioSquad] = []

## Starting wallet: food, wood, gold, stone. A scenario about combat
## should not also be a scenario about saving up.
@export var food: int = 0
@export var wood: int = 0
@export var gold: int = 0
@export var stone: int = 0

## Cells between neighbouring players' homes, or 0 to use the map's own
## scattered spawn points (D-039).
##
## This is the setting that makes a combat test finish in seconds. Real
## spawns are deliberately far apart, so two armies need a minute of
## walking to meet; `separation: 8` puts them within reach at t=0. It
## overrides the map's spawn points rather than adjusting them, because
## "near each other" is not a property any real map has.
@export var separation: int = 0

## How far from an intended cell the applier may look for a free passable
## one. Offsets are authored against no particular terrain, so some will
## land in water; this bounds the search rather than letting a scenario
## silently place a town centre far from where it was written.
@export var placement_slack: int = 6


## Empty string when usable. Checked by the server before it applies
## anything and by a test over every shipped scenario, so a broken
## scenario file fails loudly at load rather than producing a half-built
## world that looks like a simulation bug.
func validate() -> String:
	if id == &"":
		return "scenario id is empty"
	if buildings.is_empty() and squads.is_empty():
		return "scenario '%s' spawns nothing at all" % id
	if separation < 0:
		return "separation %d is negative" % separation
	if placement_slack < 0:
		return "placement_slack %d is negative" % placement_slack
	for b in buildings:
		if b == null:
			return "scenario '%s' has a null building entry" % id
		var why := b.validate()
		if why != "":
			return "scenario '%s': %s" % [id, why]
	for s in squads:
		if s == null:
			return "scenario '%s' has a null squad entry" % id
		var why := s.validate()
		if why != "":
			return "scenario '%s': %s" % [id, why]
	return ""


## Total squads this scenario gives one player — what a test asserts
## against without re-deriving the sum from the loadout.
func squad_count() -> int:
	var n := 0
	for s in squads:
		n += s.count
	return n
