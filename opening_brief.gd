class_name OpeningBrief
extends RefCounted

## What a squad is FOR, in one line, and what a player should do first
## (#284, and #282's banner reads the same answers).
##
## All-static and pure, the D-061 split: the selection panel needs a GPU,
## and "which of my two squads founds the town" does not. It is also the
## half that is easy to get wrong in a way nothing notices — a line that
## names the wrong squad is worse than no line, because a player will
## believe it.
##
## ## The problem
##
## Since `D-20260823-the-opening-is-a-crew-and-a-general` a player opens
## with a **gatherer crew and a general**. Only the crew can found a town
## centre; the general can build nothing at all. Nothing on screen said
## which was which, so the opening is a coin flip — and guessing wrong
## does not fail loudly, it just quietly does nothing while the other
## player's economy starts.
##
## ## Everything here is DERIVED, and that is the whole design
##
## No archetype is named anywhere in this file. "Can this squad found the
## town centre" is asked of `BuildingSim.can_build` against the shipped
## `BuildingDef.built_by` — the one source of truth that already
## expresses "the general builds nothing" by listing it nowhere. "Is this
## a general" is `UnitDef.is_general`.
##
## So a civ that fields a different founder, or a roster where the general
## gains a building, changes what the player is told with no edit here —
## which is D-046 criterion 3's rule applied to prose, and the reason
## `tests/test_opening_brief.gd` asserts against the SHIPPED roster
## rather than a fixture.


## The building whose founding SPENDS its builder — the town centre, and
## by `tests/test_opening.gd`'s own assertion the only one.
##
## Found by its rule rather than by its id, so this file names no
## building either. Null if the roster ever has none, and every caller
## treats that as "there is nothing to say".
static func founding_building() -> BuildingDef:
	for def in BuildingSim.all_defs():
		if def != null and def.consumes_builder:
			return def
	return null


## Whether a squad of this unit can found the opening town centre.
##
## Asked of `BuildingSim.can_build` — the same call the ORDER gate makes,
## so the panel cannot promise something the server will refuse. That
## equivalence is the point: a hint derived from a second rule is a hint
## that eventually lies.
static func can_found(def: UnitDef) -> bool:
	if def == null:
		return false
	var town := founding_building()
	if town == null:
		return false
	return BuildingSim.can_build(town, def.archetype)


## One line saying what this squad is for, or "" when it needs no
## explanation.
##
## Only the two openers get one. An archer does not need to be told it is
## an archer, and a panel that editorialised about every unit would be
## noise a player learns to skip — which would take the two lines that
## matter with it.
static func role_line(def: UnitDef) -> String:
	if def == null:
		return ""
	if def.is_general:
		# Said as what it CANNOT do, because that is the half that costs
		# a player their opening. Its own value is real but is a morale
		# aura (D-20260819-a-general-holds-the-line) nothing on screen
		# would show anyway.
		return "Commands your army. Cannot build."
	if can_found(def):
		var town := founding_building()
		return "Founds your %s — and is spent doing it." % town.display_name.to_lower()
	return ""


## What the player should do RIGHT NOW, given what they own, or "" when
## there is nothing to say.
##
## `owned` is the unit def of each living squad this player has. Deriving
## from what they HOLD rather than from a match clock is what makes this
## survive a player who founded late, lost their crew, or resettled after
## being razed (which D-20260823 made possible) — a timed tutorial would
## be wrong in all three.
##
## Returns "" once one stands, because a standing hint that never goes
## away is a hint a player stops reading.
##
## The parameter is `has_founding_building`, not `has_town_centre`: this
## file names no building anywhere, and a parameter that did would
## undercut the rule even as prose. `tests/test_opening_brief.gd` scans
## for it.
static func first_objective(owned: Array, has_founding_building: bool) -> String:
	if has_founding_building:
		return ""
	var town := founding_building()
	if town == null:
		return ""
	var founder: UnitDef = null
	for def in owned:
		if def is UnitDef and can_found(def):
			founder = def
			break
	if founder == null:
		# They own nothing that can found one. Saying so is still worth
		# more than silence: it is the state a razed player is in, and
		# the answer ("train a crew") is not obvious.
		return "No squad you own can found a %s — you need a %s." % [
			town.display_name.to_lower(), _gatherer_name(owned)]
	return "Select your %s and build a %s. Your general cannot." % [
		founder.display_name, town.display_name]


## A name for the kind of unit that founds, for a player who has none.
## Falls back to the plain word rather than inventing an archetype.
static func _gatherer_name(owned: Array) -> String:
	for def in owned:
		if def is UnitDef and can_found(def):
			return def.display_name
	return "gathering crew"
