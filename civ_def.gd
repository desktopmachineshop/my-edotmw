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

## The ARCHETYPE this civ is known for — the one unit a player picking it
## should be told about (#283). Shown in the lobby beside `summary`.
##
## An archetype, never a def id, for the reason D-047 gives about
## everything else on the wire: `barracks.produces` lists archetypes and
## the roster resolves one per civ, so naming a def here would be a
## second way of saying which unit a civ fields, free to disagree with
## the first. `UnitRoster.for_civ_archetype(id, signature_unit)` is how
## it is read, and `tests/test_civ_identity.gd` fails if any civ's
## signature does not resolve to a real unit of that civ — so this
## cannot rot into a name nobody fields.
##
## Empty is legal and means "no signature", which is what a civ added
## tomorrow says until somebody decides. The lobby simply shows nothing
## rather than an apology.
@export var signature_unit: StringName = &""

## The civ's colour, used for its swatch and emblem in the lobby.
## Data, like everything else about a civ — a new .tres brings its own
## identity and no script learns a new name (D-046 criterion 3).
@export var colour: Color = Color(0.6, 0.65, 0.75)

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


# --- the knobs, APPLIED ------------------------------------------------
#
# Nothing outside this file reads `squad_cap_bonus`, `production_speed` or
# `gather_speed` directly; everything calls one of the three functions
# below. Two reasons, and the second is why they exist at all:
#
# For a whole milestone these three fields were declared, shipped
# non-default in the data, and read by NOTHING (#158) — the fourth
# instance of this project's declared-and-unread defect class, after
# `UnitDef.cost`, `BuildingDef.cost` and `BuildingSim.damage()` (D-055).
# A knob with exactly one reader is easy to leave with none; a knob whose
# only expression is a named function has a caller you can grep for.
#
# And two of the three are read on BOTH sides of the wire — the server
# spends the production time, the client draws the bar counting it down —
# so `base / production_speed` written out twice is two copies of one rule
# free to drift (the D-058/D-065 family). This is the one copy.


## This civ's squad ceiling, given the map's (D-033).
##
## Additive, per the field's own reasoning: the map keeps the final say on
## scale, which is the axis the architecture is sensitive to (D-018).
func squad_cap(base: int) -> int:
	return base + squad_cap_bonus


## How long this civ takes to train a unit whose def says `base`.
##
## `validate()` refuses a non-positive multiplier, so this cannot divide
## by zero on any civ the roster loaded — and a default-constructed
## CivDef, which is what an unknown civ resolves to, carries 1.0.
func production_time(base: float) -> float:
	return base / production_speed


## How fast this civ's gatherers work a node whose def says `base`.
func gather_rate(base: float) -> float:
	return base * gather_speed


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
