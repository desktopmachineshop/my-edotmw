class_name ScenarioDef
extends Resource

## A mid-game world, as DATA (D-098).
##
## The problem this solves: the real opening is slow on purpose. A player
## starts with one gatherer crew, one general and no base, a town hall
## takes 40 seconds and consumes the crew that founds it
## (D-20260823-the-opening-is-a-crew-and-a-general), production runs after
## that, and spawns are scattered far apart (D-039). So the
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

## Whether a run of this scenario can prove FOG GATING in the sense
## `gate-check.sh fog-squads` means it: even the single most-informed
## client knows FEWER squads than the server simulates, at every moment of
## the run.
##
## True for anything resembling a real match, and FALSE for a scenario
## whose armies all converge on one another — because that comparison is
## about the PEAK, and the moment every army meets, the best-informed
## client has seen everything there is. `clash` is exactly that scenario
## by construction: "two armies already within reach" is a description of
## armies that will shortly all be in one place.
##
## This does NOT mean such a scenario proves nothing about fog. `clash`
## reports `conceal_events=137 reveal_events=86` over a 4-bot run — squads
## leaving and re-entering vision constantly — and the bots' own verdict
## gates on both. What it cannot support is the stronger peak-knowledge
## comparison, and `test-scenario` says which one it skipped rather than
## skipping it quietly (gate-check.sh's own header: "a comparison that
## silently skips is the vacuous pass D-022's audit was written against").
##
## Worth knowing before changing it: this became FALSE for `clash` only
## once the load-test bots started actually fighting there (#230). While
## they sat still, `clash`'s armies were 8 cells apart against a 12-unit
## vision range and never saw each other, so the peak comparison passed on
## a run in which nothing happened — a gate satisfied by the bots being
## broken.
@export var proves_fog_gating: bool = true

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
