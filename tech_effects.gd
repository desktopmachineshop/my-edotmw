extends RefCounted
class_name TechEffects

## Applies a player's researched techs to a definition
## (`D-20260827-the-tree-is-the-ladder`).
##
## ALL-STATIC and pure, for `formation.gd`'s reason: there is nowhere to
## put per-player state, so "the same techs give the same army" is
## enforced by construction rather than documented.
##
## ## Why this is the ONLY place a tech's effect is applied
##
## `SquadSim._defs[squad]` holds a `UnitDef` reference per squad, and
## `combat.gd`, `vision.gd`, `economy.gd` and `squad_sim.gd` read
## `def.damage`, `def.vision_range`, `def.move_speed` and the rest off that
## reference at roughly forty sites. Handing those sites a def with the
## modifiers already baked in means **not one of the forty changes** — and,
## far more importantly, there is no forty-first site that could be added
## later having forgotten to apply techs. The alternative (an
## `effective_damage(player, def)` helper called at each site) is the same
## defect class as the D-038 ownership cache: a rule that must be
## remembered at every call.
##
## ## Adds run before multiplies, always
##
## A field's result is `(base + Σ add) × Π multiply` over every effect
## every held tech contributes. That makes a player's army a function of
## WHICH techs they hold and not of the ORDER they researched them in —
## worth more than an ordered pipeline's expressiveness, because it means
## two players holding the same techs field bit-identical troops and a
## replay cannot diverge on research order.

## Integer fields, rounded after the arithmetic rather than truncated at
## each step — `cost_food` ×0.92 twice must not be two floors.
const _INT_FIELDS: Array[StringName] = [
	&"carry_capacity", &"cost_food", &"cost_wood", &"cost_gold",
	&"cost_stone", &"no_build_radius", &"squad_cap_bonus",
]


static func resolve_unit(base: UnitDef, techs: Array) -> UnitDef:
	if base == null or techs.is_empty():
		return base
	var out := base.duplicate() as UnitDef
	_apply(out, techs, base.archetype, "unit")
	return out


## `archetype` is passed in rather than read off the def, because
## `BuildingDef.archetype` falls back to the def's own id and the caller
## already has `BuildingSim.archetype_of`. One definition of that fallback.
static func resolve_building(base: BuildingDef, techs: Array,
		archetype: StringName) -> BuildingDef:
	if base == null or techs.is_empty():
		return base
	var out := base.duplicate() as BuildingDef
	_apply(out, techs, archetype, "building")
	return out


## Civ effects have no archetype to match on — a civ knob is civ-wide by
## definition — so every civ effect applies and `target` is ignored.
static func resolve_civ(base: CivDef, techs: Array) -> CivDef:
	if base == null or techs.is_empty():
		return base
	var out := base.duplicate() as CivDef
	_apply(out, techs, &"*", "civ")
	return out


## Gather (add, multiply) per field across every tech, then write once.
##
## Techs are visited in id order so the float arithmetic is bit-identical
## on the server and on the client, which resolve the same set
## independently. Addition is not associative in floats, and two machines
## summing one set in two orders can differ in the last bit — the same
## reasoning `TerrainGen.corner_cells` sorts its three owners for.
static func _apply(out: Object, techs: Array, archetype: StringName,
		kind: String) -> void:
	var sorted := techs.duplicate()
	sorted.sort_custom(func(a: TechDef, b: TechDef) -> bool: return a.id < b.id)

	var adds := {}
	var mults := {}
	for tech in sorted:
		var effects: Array = []
		match kind:
			"unit":
				effects = (tech as TechDef).unit_effects
			"building":
				effects = (tech as TechDef).building_effects
			"civ":
				effects = (tech as TechDef).civ_effects
		for effect in effects:
			var e := effect as TechEffect
			if e == null or (kind != "civ" and not e.applies_to(archetype)):
				continue
			if e.mode == "multiply":
				mults[e.field] = float(mults.get(e.field, 1.0)) * e.value
			else:
				adds[e.field] = float(adds.get(e.field, 0.0)) + e.value

	var fields := {}
	for f in adds:
		fields[f] = true
	for f in mults:
		fields[f] = true
	for field in fields:
		var current: Variant = out.get(String(field))
		if current == null:
			# Cannot happen for a validated tech — TechEffect.validate
			# probes the schema — but a silently skipped field would be
			# the exact defect the closed vocabulary exists to prevent.
			push_error("TechEffects: no property '%s' to modify" % field)
			continue
		var value := (float(current) + float(adds.get(field, 0.0))) \
			* float(mults.get(field, 1.0))
		if _INT_FIELDS.has(field):
			out.set(String(field), int(round(value)))
		else:
			out.set(String(field), value)
