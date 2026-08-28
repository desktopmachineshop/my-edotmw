class_name TechDef
extends Resource

## One researchable technology, as data
## (`D-20260827-the-tree-is-the-ladder`). New techs are `.tres` files
## under `/techs/`, never new scripts — and no `.gd` file may name a tech
## id, a tech line or an epoch, exactly as none may name a civ (D-047,
## D-046 criterion 3).
##
## ## The `line` / `civ` split IS `UnitDef`'s `archetype` / `civ` split
##
## A `TechDef` is ONE CIV'S VERSION of a line, the way a `UnitDef` is one
## civ's version of an archetype. `siegecraft` is one line and four files
## — the giant-kin call it *Quarried Heads*, the deathless court *Grave-tar
## Payloads*, the free cities *Engineers' Retainer*, the deep holds
## *Runeforged Charges*. One schema field, four `.tres`, the same
## mechanical knob, and no script the wiser: `tests/test_civs.gd` forbids
## naming a civ id even in a comment, which is why the folks above are
## described rather than named. `docs/plans/tech-tree.md` has the table.
##
## A `civ = neutral` tech is the shared TRUNK: one file, every civ
## researches it, same name for everybody. A per-civ tech SHADOWS the
## trunk for that civ.
##
## Everything that refers to a tech — a prerequisite, a unit's
## `requires_tech`, an epoch's defining set — names a LINE, never an id.
## That is what lets those references be written once for six civs.
##
## ## Completing an epoch's defining line IS the age-up
##
## There is no age-up button. `defining` marks a tech as part of its
## epoch's line; when a player holds every defining line of epoch N, they
## are in epoch N+1. D-069's advance gate was a payment, and a payment has
## exactly one decision in it — the tree gives a rung an interior.

## File-unique — by convention `<civ>_<line>` for a per-civ tech and just
## the line for a trunk one. Nothing references this; everything
## references `line`.
@export var id: StringName

## What a player reads. The in-world name, in this civ's own words.
@export var display_name: String = ""

## Flavour: what it MEANS, not what it does. The numbers are below.
@export_multiline var description: String = ""

## The shared mechanical identity — `UnitDef.archetype`'s exact analogue.
@export var line: StringName = &""

## `neutral` is the shared trunk. A per-civ file shadows it for that civ;
## `TechRoster.for_civ_line` prefers an exact civ match explicitly rather
## than relying on id order, because relying on id order is what made a
## whole feature quietly absent in
## `D-20260823-the-opening-is-a-crew-and-a-general`.
@export var civ: StringName = &"neutral"

## Earliest epoch at which research may START
## (`D-20260828-the-epoch-ladder`). Epoch gates TECHS; techs gate
## everything else — one gate per question, so there is nowhere for
## two answers to disagree (which is why `UnitDef.epoch`, proposed by
## D-070, is deliberately NOT in the schema).
@export var epoch: int = 1

## On this epoch's defining line. Hold every defining LINE of epoch N and
## you are in epoch N+1 — that is the whole advance rule
## (`D-20260828-the-epoch-ladder`).
##
## What a rung's line COSTS, in minutes of the income of the phase that
## pays for it, is `D-20260828-the-phase-table-has-numbers`.
@export var defining: bool = false

## The building ARCHETYPE that researches this — `BuildingDef.archetype`,
## which falls back to the def's own id.
##
## A civ that has no such building cannot walk this branch, and that is
## civ identity with no knob attached
## (`D-20260827-a-research-site-is-a-building`). The rule that keeps a
## hole from LOCKING a civ out of the ladder: a `defining` tech's site
## must be one that civ actually has, and a test asserts it.
@export var research_at: StringName = &"town_centre"

## Prerequisite LINES. Acyclic and reachable-from-nothing for every civ —
## also a test, because the first draft of the tree had a real cycle in
## it: one civ's epoch-2 arc tech was researched at a building that
## required that same tech.
@export var requires: Array[StringName] = []

@export var cost_food: int = 0
@export var cost_wood: int = 0
@export var cost_gold: int = 0
@export var cost_stone: int = 0

## Seconds, scaled by `CivDef.production_time` like a unit's build time —
## so a civ that trains fast also researches fast, through the one
## definition of that knob rather than a second copy of it.
@export var research_time: float = 30.0

@export var unit_effects: Array[TechEffect] = []
@export var building_effects: Array[TechEffect] = []
@export var civ_effects: Array[TechEffect] = []


## Returns "" if valid, else the reason. Called at load by `TechRoster`,
## so a broken tech fails loudly rather than researching and doing
## nothing.
func validate() -> String:
	if id == &"":
		return "tech has no id"
	if line == &"":
		return "tech %s has no line" % id
	if epoch < 1:
		return "tech %s is in epoch %d" % [id, epoch]
	if research_time <= 0.0:
		return "tech %s researches in %f seconds" % [id, research_time]
	if cost_food < 0 or cost_wood < 0 or cost_gold < 0 or cost_stone < 0:
		return "tech %s has a negative cost" % id
	if requires.has(line):
		return "tech %s requires its own line" % id
	if unit_effects.is_empty() and building_effects.is_empty() \
			and civ_effects.is_empty() and not defining:
		# A defining tech is allowed to be pure ladder — its effect is the
		# epoch. Anything else with no effects is a tech that costs
		# resources and does nothing, which is the exact defect the closed
		# vocabulary exists to prevent, arriving by omission instead.
		return "tech %s has no effects and does not define an epoch" % id
	for pair in [[unit_effects, "unit"], [building_effects, "building"],
			[civ_effects, "civ"]]:
		for effect in (pair[0] as Array):
			if effect == null:
				return "tech %s has a null %s effect" % [id, pair[1]]
			var why: String = (effect as TechEffect).validate(pair[1] as String)
			if why != "":
				return "tech %s: %s" % [id, why]
	return ""


func is_valid() -> bool:
	return validate() == ""


## Total resource points, D-072's RP weighting. Used by the AI to compare
## a tech against troops it could buy instead, and by the tests that
## assert a rung's two halves sum to D-069's advance row.
func resource_points() -> int:
	return cost_food + cost_wood + int(round(1.5 * float(cost_gold + cost_stone)))
