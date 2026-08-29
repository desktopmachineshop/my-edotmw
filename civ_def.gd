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

## How fast this civ RAISES BUILDINGS, as a divisor on
## `BuildingDef.build_time` (#270). `production_speed`'s sibling for the
## other verb.
@export var build_speed: float = 1.0

## How fast this civ's squads MARCH, as a multiplier on each unit's own
## `move_speed` (#270).
@export var march_speed: float = 1.0

## Per-resource gather multipliers, indexed by `Economy.ResourceKind`
## (food, wood, gold, stone). EMPTY means `gather_speed` applies to all
## four, which is what five of six civs want; a civ that is rich in one
## resource and poor in another gives all four (#270).
@export var gather_speed_by_kind: Array[float] = []


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
## How many squads this civ may field, from the map's `base`.
##
## FLOORED at one. `squad_cap_bonus` may now be negative -- a quality civ
## is FEWER and better, and before #270 the knob only meaningfully went
## up, so "strong from few well-held sites" was inexpressible and such a
## civ simply paid more per squad for the same forty. A floor because a
## cap of zero is a civ that cannot play, which is a data entry away.
func squad_cap(base: int) -> int:
	return maxi(1, base + squad_cap_bonus)


## How long this civ takes to train a unit whose def says `base`.
##
## `validate()` refuses a non-positive multiplier, so this cannot divide
## by zero on any civ the roster loaded — and a default-constructed
## CivDef, which is what an unknown civ resolves to, carries 1.0.
func production_time(base: float) -> float:
	return base / production_speed


## How fast this civ's gatherers work a node of `kind` whose def says
## `base`.
##
## Per RESOURCE since #270: "wood-rich, gold-poor" is not a smaller
## number, it is four numbers, and one scalar over all four cannot say
## it. An empty table means the scalar applies to everything, which is
## what every civ did before and what five of six still do -- so the
## default costs nothing and reads identically.
##
## `kind` is `Economy.ResourceKind`, passed by the one caller that has it
## anyway. Negative or out of range falls back to the scalar rather than
## erroring: a node kind this civ has no opinion about is the ordinary
## case, not a fault.
func gather_rate(base: float, kind: int = -1) -> float:
	if kind >= 0 and kind < gather_speed_by_kind.size():
		return base * float(gather_speed_by_kind[kind])
	return base * gather_speed


## How long this civ takes to RAISE a building whose def says `base`.
##
## The sibling of `production_time`, and separate from it because they are
## different verbs: `production_speed` divides `UnitDef.build_time` and so
## only ever touches units, which left a fortification civ unable to
## fortify any faster than anybody else (#270).
##
## Resolved by the caller and stored as REAL SECONDS on the building, for
## the same reason `BuildingSim.enqueue` takes its time as a parameter: a
## multiplier applied per tick would make the progress a client draws
## disagree with the progress the server keeps.
func construction_time(base: float) -> float:
	return base / build_speed


## How fast this civ's squads MARCH, from a def's own `move_speed`.
##
## Army-wide, at the civ level, because a mobility identity that lives
## only in four `.tres` files cannot say "this host redeploys faster than
## it fights" (#270) -- it can only make individual units quick, which is
## a different claim.
##
## Applied once when a squad is created, where `SquadSim` already latches
## its cells-per-second, so it costs nothing per tick.
func march_rate(base: float) -> float:
	return base * march_speed


## Returns "" if valid, else the reason. Called at load so a broken civ
## fails loudly rather than producing a subtly wrong match.
func validate() -> String:
	if id == &"":
		return "civ has no id"
	if production_speed <= 0.0 or gather_speed <= 0.0 \
			or build_speed <= 0.0 or march_speed <= 0.0:
		return "civ %s has a non-positive speed multiplier" % id
	for rate in gather_speed_by_kind:
		if float(rate) <= 0.0:
			return "civ %s has a non-positive per-resource gather rate" % id
	if gather_speed_by_kind.size() not in [0, 4]:
		return "civ %s must give a gather rate for every resource or for none" % id
	if starting_food < 0 or starting_wood < 0 or starting_gold < 0 or starting_stone < 0:
		return "civ %s has a negative starting stockpile" % id
	return ""


func is_valid() -> bool:
	return validate() == ""
