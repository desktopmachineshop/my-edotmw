class_name TechEffect
extends Resource

## ONE modifier a researched tech applies
## (`D-20260827-the-tree-is-the-ladder`).
##
## The sub-resource of `TechDef`, the way `ScenarioSquad` is a
## sub-resource of `ScenarioDef`. A tech's whole mechanical content is a
## list of these, so a tech is data all the way down and there is nowhere
## for a per-civ branch to hide (D-047).
##
## ## The field vocabulary is CLOSED, and that is the point
##
## `field` must name one of the constants below. An unknown name is a
## LOAD ERROR, not a line that quietly does nothing — because a tech whose
## effect is a typo would be this project's fifth declared-and-unread
## defect (after `UnitDef.cost`, `BuildingDef.cost`, `BuildingSim.damage()`
## and the three `CivDef` knobs), and this one would ship wearing a green
## verdict: the tech researches, the resources are spent, the bar fills,
## and nothing changes.
##
## `validate()` checks the name against the list AND against the schema
## itself — `UnitDef.new().get(field)` answers null for a property that
## does not exist — so the list cannot drift away from the resource it
## describes without a test going red.

## The unit ARCHETYPE this applies to, or `*` for every archetype. Never a
## unit id and never a civ: a tech is resolved per civ already, and
## naming an id here would make a shared trunk tech unable to be shared.
@export var target: StringName = &"*"

## The stat, from one of the three closed lists below.
@export var field: StringName = &""

## `add` is applied before `multiply`, ALWAYS, across every tech a player
## holds — see `TechEffects.resolve_unit`. That makes a player's army a
## function of WHICH techs they have and not of the ORDER they researched
## them in, which is worth more than the extra expressiveness of an
## ordered pipeline: two players holding the same techs field identical
## troops, and a replay cannot diverge on research order.
@export_enum("add", "multiply") var mode: String = "add"

@export var value: float = 0.0


## Fields a tech may modify on a `UnitDef`.
##
## What is NOT here matters more than what is:
##
## - `squad_size`, `formation_shape`, `formation_spacing` — the client
##   derives soldier geometry from these, and `composition_hash` reads
##   shape and spacing. Shape and spacing happen to be replicated
##   (D-058/D-065) so a tech touching them would probably be safe;
##   `squad_size` is not replicated at all and would desync every client
##   of the player who researched it. Fenced together, because "probably
##   safe" is not a thing to leave on the near side of a wire boundary.
## - `model_id`, `slot_models`, `model_mix`, `mesh_primitive` — the client
##   resolves these itself from (civ, archetype), so a server-side change
##   would draw a different army from the one that exists.
## - `armour_class`, `bonus_vs` — D-032's counter triangle is a design
##   invariant, not a stat, and `bonus_vs` is a Dictionary that "add 0.3"
##   has no meaning for without naming a key.
## - `archetype`, `civ`, `id`, `is_general` — identity. A tech that changed
##   what a unit IS would break every lookup keyed on it.
const UNIT_FIELDS: Array[StringName] = [
	&"damage", &"health", &"attack_range", &"attack_interval",
	&"move_speed", &"vision_range", &"morale",
	&"morale_recovery_per_second", &"rout_threshold", &"rout_rally_margin",
	&"damage_vs_buildings", &"gather_rate", &"carry_capacity",
	&"cost_food", &"cost_wood", &"cost_gold", &"cost_stone", &"build_time",
]

## Fields a tech may modify on a `BuildingDef`.
const BUILDING_FIELDS: Array[StringName] = [
	&"max_health", &"damage", &"attack_range", &"attack_interval",
	&"vision_range", &"build_time", &"no_build_radius",
	&"top_range_bonus", &"top_vision_bonus",
	&"cost_food", &"cost_wood", &"cost_gold", &"cost_stone",
]

## Fields a tech may modify on a `CivDef` — the three knobs
## `D-20260823-a-civs-knobs-are-read-by-the-simulation` wired up, and no
## others. A tech raising one goes through `CivDef`'s applied functions
## like everything else does.
const CIV_FIELDS: Array[StringName] = [
	&"squad_cap_bonus", &"production_speed", &"gather_speed",
]


## Returns "" if valid for `kind` ("unit", "building" or "civ"), else why.
func validate(kind: String) -> String:
	if field == &"":
		return "effect has no field"
	var permitted: Array[StringName] = UNIT_FIELDS
	var probe: Object = UnitDef.new()
	match kind:
		"building":
			permitted = BUILDING_FIELDS
			probe = BuildingDef.new()
		"civ":
			permitted = CIV_FIELDS
			probe = CivDef.new()
		"unit":
			pass
		_:
			return "unknown effect kind '%s'" % kind
	if not permitted.has(field):
		return "'%s' is not a %s field a tech may modify" % [field, kind]
	# The list and the schema must agree. `Object.get` answers null for a
	# property that does not exist, so a field renamed in `unit_def.gd`
	# and not here fails loudly instead of silently applying to nothing.
	if probe.get(String(field)) == null:
		return "%s has no property '%s' — the vocabulary has drifted from the schema" \
			% [kind, field]
	if mode == "multiply" and value <= 0.0:
		return "'%s' multiplies by %f — a non-positive multiplier zeroes or inverts a stat" \
			% [field, value]
	if target == &"":
		return "effect on '%s' has an empty target (use * for every archetype)" % field
	return ""


## Does this effect apply to `archetype`?
func applies_to(archetype: StringName) -> bool:
	return target == &"*" or target == archetype
