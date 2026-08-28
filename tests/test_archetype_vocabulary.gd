extends GutTest

## Guards that an archetype LABEL promises something (#332).
##
## An archetype is the word the build menu shows and the word the wire
## carries: the client sends an ARCHETYPE and the server resolves it per
## civ (D-047). So a player who trains "skirmishers" for one civ and then
## plays another is entitled to get broadly the same kind of troops.
##
## `skirmishers` covered two units that were not the same kind of thing
## at all:
##
##   stoneblood_skirmishers  "Cragthrowers"  12 men  110 hp  reach 5.5  missile
##   windmarch_skirmishers   "Harriers"      24 men   48 hp  reach 1.9  cavalry
##
## One shoots across three hexes; the other can only reach the cell in
## front of it. Under one label, in one menu.
##
## Resolved by renaming the melee one to what the design already called
## it: `docs/plans/fantasy-civs.md` names the unit **Harriers** and its
## `display_name` has said so all along — only the archetype and the def
## id still said "skirmishers". `skirmishers` keeps its classical meaning
## (the missile one), which is what #332 suggested.
##
## The checks below are deliberately narrow. An archetype SHOULD vary
## between civs — that is D-047's whole point, and `docs/status/civ-knobs.md`
## exists because it did not vary enough. What must not vary is what the
## word MEANS.


## Every archetype the roster fields, with its defs.
func _by_archetype() -> Dictionary:
	var out := {}
	for def in UnitRoster.load_all():
		var key := String(def.archetype)
		if not out.has(key):
			out[key] = []
		out[key].append(def)
	return out


## ARMOUR CLASS is deliberately NOT checked here, and finding that out
## cost a red run worth recording.
##
## The obvious sibling to the range check below is "an archetype is one
## role", keyed on `armour_class`. Written, it failed on THREE archetypes
## — `skirmishers`, and also `general` and `levy` — because **windmarch is
## all-cavalry by design**: `docs/plans/fantasy-civs.md` says "every unit
## is `armour_class cavalry` — the entire civ is countered by spears, and
## that is the deliberate cost of an all-mounted roster".
##
## So that guard would have forced a shipped civ identity to change to
## satisfy a test. Class variation across an archetype is legitimate and
## is #268's territory, which carries a documented allow-list for exactly
## this. This file asserts the narrower thing #332 is actually about: not
## what a unit is countered by, but whether the WORD tells a player how it
## fights.


func test_an_archetype_fights_at_one_range() -> void:
	# The half a player feels first, and the one `armour_class` alone
	# cannot catch: whether the unit reaches the cell in front of it or
	# shoots across the map.
	#
	# The line is ONE HEX (`TorusSpace.SQRT_3`), which is the same
	# threshold `test_every_armed_unit_can_reach_an_adjacent_cell` uses —
	# below it a unit can only attack its own cell, above it the unit is
	# a shooter. Tuning reach between civs is fine and expected; crossing
	# that line is a different unit.
	var hex := TorusSpace.SQRT_3
	var offenders := []
	for archetype in _by_archetype():
		var melee := []
		var missile := []
		for def in _by_archetype()[archetype]:
			if def.damage <= 0.0:
				continue
			if def.attack_range < hex * 2.0:
				melee.append(String(def.id))
			else:
				missile.append(String(def.id))
		if not melee.is_empty() and not missile.is_empty():
			offenders.append("%s: melee %s vs ranged %s" % [archetype, str(melee), str(missile)])
	assert_eq(offenders.size(), 0,
		("one label cannot mean both 'walks up and hits it' and 'shoots it "
		+ "from three hexes away': %s") % str(offenders))


func test_the_roster_still_fields_several_civs_per_shared_archetype() -> void:
	# The anti-vacuity guard, and it is not decoration: both checks above
	# pass trivially if every archetype has exactly ONE def, which is what
	# a lazy "fix" would produce — rename each unit's archetype to its own
	# id and the suite goes green while the build menu becomes a list of
	# twenty-two singletons.
	var shared := 0
	for archetype in _by_archetype():
		if _by_archetype()[archetype].size() > 1:
			shared += 1
	assert_gt(shared, 3,
		"only %d archetypes are shared between civs — the checks above would "
			% shared + "be passing on a roster with no shared vocabulary at all")


func test_every_archetype_the_barracks_offers_is_fielded_by_somebody() -> void:
	# `barracks.produces` is the UNION of every civ's archetypes (#191), so
	# a renamed archetype that nobody updated leaves a word in the menu
	# that resolves to nothing for every civ — silence rather than a
	# failure, which is this project's most-repeated defect shape.
	var fielded := _by_archetype()
	var orphans := []
	for def in BuildingSim.all_defs():
		for archetype in def.produces:
			if not fielded.has(String(archetype)):
				orphans.append("%s offers %s" % [def.id, archetype])
	assert_eq(orphans.size(), 0,
		"these are offered by a building and fielded by no civ: %s" % str(orphans))


func test_every_fielded_combat_archetype_is_offered_somewhere() -> void:
	# The other direction: a unit whose archetype no building produces is
	# unbuildable, which is how a rename half-done goes unnoticed.
	# Gatherers and generals come from the town centre; anything else a
	# civ fields must be reachable from some building's list.
	var offered := {}
	for def in BuildingSim.all_defs():
		for archetype in def.produces:
			offered[String(archetype)] = true
	var unreachable := []
	for archetype in _by_archetype():
		if not offered.has(archetype):
			unreachable.append(archetype)
	assert_eq(unreachable.size(), 0,
		"these archetypes are fielded but no building trains them: %s" % str(unreachable))
