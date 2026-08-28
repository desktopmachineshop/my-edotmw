extends GutTest

## Guards D-20260828-morale-is-a-fraction-of-the-squad (#266).
##
## `morale_loss_per_casualty` was a flat per-man number -- 4.0 on every
## shipped def but gravesworn's -- while this roster runs from 3 men to
## 48. Flat, the casualties needed to break are a CONSTANT:
##
##     need = (morale - rout_threshold) / morale_loss_per_casualty
##          = (100 - 25) / 4.0 = 18.75
##
## so **any squad of 18 men or fewer was annihilated before it could be
## frightened**. Not rarely -- never, at any level of beating, from any
## direction, with recovery disabled entirely. Measured: 12 of 27 combat
## defs, including EVERY cavalry def in the game and the whole of
## stoneblood's non-levy roster.
##
## The check this file really is, and the one #266 asks for: **no
## non-fearless def may be unroutable.** It is a property of the shipped
## data crossed with the schema, which is why nothing owned it before.

## Fearless by design (#191): `rout_threshold 0` and
## `morale_loss_per_casualty 0`, verified structurally by
## `tests/test_fearless.gd`. Resolved by PROPERTY, not by civ name -- no
## test may name a civ (D-046 criterion 3), and a def that becomes
## fearless later is covered automatically.
func _is_fearless(def: UnitDef) -> bool:
	return def.morale_loss_per_casualty <= 0.0


func _combat_defs() -> Array:
	var out := []
	for def in UnitRoster.load_all():
		if def.archetype == &"gatherers":
			continue
		out.append(def)
	return out


func test_every_non_fearless_def_can_actually_be_broken() -> void:
	# THE defect. A squad that dies before it breaks makes D-019's whole
	# morale system inert for that unit, and with it every mechanic built
	# on top: flank and rear shock, chain shock from a breaking ally, the
	# routed-defender damage multiplier, and a general's aura -- which
	# halves chain shock for squads that could not be shocked.
	var unroutable := PackedStringArray()
	var checked := 0
	for def in _combat_defs():
		if _is_fearless(def):
			continue
		checked += 1
		var need: float = def.casualties_to_rout()
		if need >= float(def.squad_size):
			unroutable.append("%s (%d men, needs %.1f casualties)"
				% [def.id, def.squad_size, need])
	assert_gt(checked, 0, "no non-fearless def was examined, so this proves nothing")
	assert_eq(unroutable.size(), 0,
		"def(s) that are annihilated before they can be frightened: %s"
			% ", ".join(unroutable))


func test_the_fearless_are_still_unroutable_and_that_is_the_point() -> void:
	# The control. Scaling must not accidentally give the deathless court
	# a breaking point -- and the defect being fixed is that eleven other
	# units were silently sharing its one distinguishing feature.
	var fearless := 0
	for def in _combat_defs():
		if not _is_fearless(def):
			continue
		fearless += 1
		assert_eq(def.casualties_to_rout(), INF,
			"%s is meant to be fearless and has acquired a breaking point" % def.id)
	assert_gt(fearless, 0,
		"no shipped def is fearless any more, so #191's identity has gone")


func test_breaking_point_is_a_FRACTION_of_the_squad_not_a_count() -> void:
	# The property that makes the fix a rule rather than 27 numbers: a
	# six-man breaker and a forty-eight-man levy must break at comparable
	# attrition. Without it the next squad-size change re-opens the whole
	# defect, which is exactly why per-def numbers were rejected.
	var fractions := []
	for def in _combat_defs():
		if _is_fearless(def) or def.squad_size <= 0 or def.is_general:
			continue
		var reach: float = def.casualties_to_rout()
		fractions.append(reach / float(def.squad_size))
	assert_gt(fractions.size(), 5, "too few defs to compare")
	var lowest: float = fractions[0]
	var highest: float = fractions[0]
	for f in fractions:
		lowest = minf(lowest, f)
		highest = maxf(highest, f)
	# Not equality: `morale` and `rout_threshold` are per-def knobs a civ
	# may legitimately vary, and `gildedreach_sellswords` already does
	# (morale 120, so it breaks at 0.66 of itself where a levy breaks at
	# 0.52). What must not survive is the spread a FLAT number produces
	# over a roster of 3-to-48-man squads, which ran from 0.39 to "never".
	assert_lt(highest - lowest, 0.25,
		"squads break at wildly different fractions of themselves (%.2f to %.2f), "
			% [lowest, highest]
		+ "so the loss is still behaving like a flat count")


func test_the_general_is_the_only_unit_that_barely_breaks() -> void:
	# Generals are excluded from the spread above, and the exception is
	# MEASURED here rather than assumed. They ship morale 160 against a
	# rout threshold of 18 in an eight-man command party, so they break
	# only when almost the whole retinue is down -- which is
	# `D-20260819-a-general-holds-the-line` working: a general's DEATH is
	# the morale event, and one that fled at ordinary attrition would
	# undermine the aura it exists to project.
	#
	# Stated as a bound rather than hidden by the exclusion, so a future
	# def that quietly acquires general-like steadfastness without being
	# a general fails here.
	for def in _combat_defs():
		if _is_fearless(def) or def.squad_size <= 0:
			continue
		var reach: float = def.casualties_to_rout()
		var fraction := reach / float(def.squad_size)
		if def.is_general:
			assert_gt(fraction, 0.75,
				"%s is a general and breaks at %.2f of itself, which is ordinary-troop steadfastness"
					% [def.id, fraction])
		else:
			assert_lt(fraction, 0.75,
				"%s is not a general and breaks only at %.2f of itself"
					% [def.id, fraction])


func test_a_reference_sized_squad_is_unchanged() -> void:
	# The clause that makes this a normalisation rather than a retune. A
	# squad of the reference size behaves exactly as it did before, so the
	# shipped 4.0 keeps its meaning and only the spread around it moves.
	var def := UnitDef.new()
	def.squad_size = int(UnitDef.MORALE_REFERENCE_SQUAD)
	def.morale_loss_per_casualty = 4.0
	assert_almost_eq(def.morale_loss_for(1), 4.0, 0.001,
		"a reference-sized squad's morale loss has moved, so this is a retune")
	assert_almost_eq(def.morale_loss_for(3), 12.0, 0.001,
		"the loss is no longer linear in casualties")


func test_a_smaller_squad_feels_each_loss_more() -> void:
	# The direction, stated so a sign error cannot pass. Losing one of six
	# must hurt more than losing one of forty-eight.
	var small := UnitDef.new()
	small.squad_size = 6
	small.morale_loss_per_casualty = 4.0
	var large := UnitDef.new()
	large.squad_size = 48
	large.morale_loss_per_casualty = 4.0
	assert_gt(small.morale_loss_for(1), large.morale_loss_for(1),
		"a six-man squad shrugs off a death that a forty-eight-man squad feels")


func test_a_zero_size_def_does_not_divide_by_it() -> void:
	var def := UnitDef.new()
	def.squad_size = 0
	def.morale_loss_per_casualty = 4.0
	assert_almost_eq(def.morale_loss_for(2), 8.0, 0.001,
		"a def with no squad size must fall back to the flat number, not divide by zero")


func test_both_combat_paths_go_through_the_applied_accessor() -> void:
	# `D-20260823-a-civs-knobs-are-read-by-the-simulation`'s rule: a knob
	# is read through an applied function, never as a raw field. Both
	# readers are in combat, and the scaling written out twice is two
	# copies of one rule free to drift.
	var handle := FileAccess.open("res://combat.gd", FileAccess.READ)
	assert_not_null(handle, "combat.gd could not be read")
	if handle == null:
		return
	var source := handle.get_as_text()
	assert_false(source.contains("morale_loss_per_casualty"),
		"combat still reads the raw field somewhere, so one path is unscaled")
	assert_true(source.contains("morale_loss_for("),
		"combat must go through the applied accessor")
