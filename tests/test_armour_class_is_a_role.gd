extends GutTest

## Guards D-20260828-armour-class-is-a-role-not-a-flavour (#268).
##
## `armour_class` is what the counter table reads: `bonus_vs` maps an
## opponent's armour class to a damage multiplier (D-032). Three
## archetypes carried a DIFFERENT class depending on which civ fielded
## them -- `general`, `levy` and `skirmishers` -- and the mechanical
## consequences did not look deliberate:
##
##   - one civ's levy was the only backbone unit in the game that any
##     spearman countered, at the table's strongest multiplier (1.5-1.6),
##     while five civs' levies had one weak counter (archers at 1.3-1.4)
##     and that one had two;
##   - the same civ's general was the only general anywhere that a
##     spearman countered;
##   - and `skirmishers` meant a 12-man 110 HP MISSILE unit at reach 5.5
##     for one civ and a 24-man 48 HP MELEE unit at reach 1.9 for
##     another, so cavalry's `bonus_vs {"missile"}` hit one and not the
##     other. A player who learns "cavalry beat skirmishers" from one civ
##     learns something false about the next.
##
## The roster treated the field as FLAVOUR and the counter table reads it
## as ROLE, and only one of those can be right. Role wins -- and the data
## had already decided: the same civ's own GATHERERS were classed
## `infantry`, so centaur-ness never actually determined armour class.

## Archetypes allowed to carry more than one armour class, each with its
## reason. Not a blanket escape: an entry here is a statement that the
## variation is deliberate and understood.
##
## EMPTY, and that is this list working rather than being unused.
##
## `skirmishers` sat here because the ARCHETYPE NAME was wrong rather than
## the classes: one civ's was a genuine missile unit and another's light
## melee infantry. This entry said the rename was "filed rather than
## smuggled in here" — #332 is that rename (windmarch's melee pair are
## `harriers` now), so the archetype stops varying and comes off, exactly
## as `test_every_documented_exception_is_still_needed` demands.
##
## Leave it empty rather than deleting it. The next archetype to vary
## wants the same escape hatch and the same obligation to justify itself.
const CLASS_MAY_VARY: Array[StringName] = []

## Reach at or above which a unit is shooting rather than swinging.
## Between the longest melee in the roster (2.4) and the shortest missile
## (5.0), so neither end is a knife edge.
const MISSILE_REACH := 3.0


func _combat_defs() -> Array:
	var out := []
	for def in UnitRoster.load_all():
		if def.archetype == &"gatherers":
			continue
		out.append(def)
	return out


func test_one_archetype_means_one_armour_class() -> void:
	# The check #268 asks for, and the one nothing would have noticed the
	# next time: a shared archetype whose class depends on the civ makes
	# the counter triangle mean different things under one build-menu
	# label.
	var classes := {}
	for def in _combat_defs():
		if not classes.has(def.archetype):
			classes[def.archetype] = {}
		classes[def.archetype][def.armour_class] = true

	var drifted := PackedStringArray()
	for archetype in classes:
		if CLASS_MAY_VARY.has(archetype):
			continue
		var seen: Dictionary = classes[archetype]
		if seen.size() > 1:
			drifted.append("%s: %s" % [archetype, seen.keys()])
	assert_eq(drifted.size(), 0,
		"archetype(s) whose armour class depends on the civ fielding them, so the "
		+ "counter table means different things under one label: %s" % ", ".join(drifted))


func test_every_documented_exception_is_still_needed() -> void:
	# An allow-list that outlives its reason is how a rule quietly stops
	# applying. If an archetype on it stops varying, it comes off.
	for archetype in CLASS_MAY_VARY:
		var seen := {}
		for def in _combat_defs():
			if def.archetype == archetype:
				seen[def.armour_class] = true
		assert_gt(seen.size(), 1,
			"%s is excused from the one-class rule and no longer varies -- take it off the list"
				% archetype)


func test_armour_class_matches_what_the_unit_actually_does() -> void:
	# The role check that does not depend on archetype NAMES at all, and
	# so covers the case the allow-list excuses. A unit classed `missile`
	# must be able to shoot; a unit that shoots must not be classed as
	# something cavalry's anti-missile bonus misses.
	for def in _combat_defs():
		if def.armour_class == "missile":
			assert_gte(def.attack_range, MISSILE_REACH,
				"%s is classed missile but swings at reach %.1f, so an anti-missile bonus hits a melee unit"
					% [def.id, def.attack_range])
		if def.attack_range >= MISSILE_REACH:
			assert_ne(def.armour_class, "infantry",
				"%s shoots at reach %.1f and is classed infantry, so the anti-infantry counter hits a shooter"
					% [def.id, def.attack_range])


func test_no_civ_has_a_uniquely_counterable_backbone() -> void:
	# The consequence that made this worth fixing rather than documenting.
	# Every levy in the game must sit in the same class, or one civ's
	# backbone takes a counter multiplier nobody else's does -- and the
	# civ it happened to was already the one losing levy-vs-levy 0 of 6
	# (#267).
	var levy_classes := {}
	for def in _combat_defs():
		if def.archetype == &"levy":
			levy_classes[def.armour_class] = true
	assert_gt(levy_classes.size(), 0, "no levy in the roster, so this proves nothing")
	assert_eq(levy_classes.size(), 1,
		"levies are spread across %s, so at least one civ's backbone is counterable "
			% [levy_classes.keys()]
		+ "in a way the others are not")


func test_a_general_is_a_general_everywhere() -> void:
	# Same argument for the command party, which a player only ever has
	# one of (D-20260819-a-general-holds-the-line) and cannot replace.
	var general_classes := {}
	for def in UnitRoster.load_all():
		if def.is_general:
			general_classes[def.armour_class] = true
	assert_eq(general_classes.size(), 1,
		"generals are spread across %s, so one civ's is counterable and the others are not"
			% [general_classes.keys()])
