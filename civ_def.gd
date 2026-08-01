extends Resource
class_name CivDef

## A civilization, as data (D-047). New civs are added as .tres files
## under /civs/, never as script subclasses or branches.
##
## ## What is NOT here, on purpose
##
## The unit roster. A civ's units are DERIVED from which files under
## /units/ name it, so adding a `.tres` gives that civ a type and there is
## no register here that can disagree with the files. `CivDef` carries
## only what is genuinely civ-level.
##
## ## Mechanical asymmetry lives here, and it must stay declarative
##
## D-046's governing constraint: mechanical differences are expressed as
## parameters the engine already interprets, NEVER as a per-civ branch. A
## civ wanting a new mechanic adds a knob that every civ has and turns it
## — one more field below, applied uniformly — so the third civ is still
## a text file and D-015's "4-6 civilizations at launch" stays a content
## job rather than six engineering projects.
##
## The test that keeps this honest is that no `.gd` file may mention a civ
## id at all (D-046 criterion 3). If a mechanic ever genuinely resists
## being a parameter, record it and amend D-046 rather than quietly
## writing the branch.

@export var id: StringName
@export var display_name: String = ""

## Flavour, not mechanics — shown in the lobby so a player choosing a civ
## knows what they are picking.
@export_multiline var summary: String = ""

## What a player of this civ starts with (D-028's reasoning: a player
## starting empty could never begin, because gatherers cost food and food
## comes from gatherers).
@export var starting_food: int = 250
@export var starting_wood: int = 200
@export var starting_gold: int = 0
@export var starting_stone: int = 0

## Added to the map's shared squad ceiling (D-033).
##
## A mechanical difference, expressed as data: a civ built on numbers can
## field more squads than one built on quality. Every civ has this knob;
## most will leave it at zero.
##
## Deliberately additive rather than a multiplier, so the map keeps the
## final say on scale — D-033's cap exists to bound total squad count,
## which is the axis the architecture is sensitive to (D-018), and a
## multiplier would let a civ definition quietly rewrite that budget.
@export var squad_cap_bonus: int = 0

## Multiplies production speed. Above 1.0 trains faster.
##
## The other half of a numbers civ: cheaper, weaker troops are only
## actually a strategy if you can get them into the field before the
## expensive ones arrive.
@export var production_speed: float = 1.0

## Multiplies gathering rate. The economy knob, for a civ whose identity
## is expansion rather than either army model.
@export var gather_speed: float = 1.0


## Returns "" if valid, else the reason. Called at load so a broken civ
## fails loudly rather than producing a subtly wrong match.
func validate() -> String:
	if id == &"":
		return "civ has no id"
	if production_speed <= 0.0 or gather_speed <= 0.0:
		return "civ %s has a non-positive speed multiplier" % id
	if starting_food < 0 or starting_wood < 0 or starting_gold < 0 or starting_stone < 0:
		return "civ %s has a negative starting stockpile" % id
	return ""


func is_valid() -> bool:
	return validate() == ""
