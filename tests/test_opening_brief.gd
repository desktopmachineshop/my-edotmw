extends GutTest

## Guards #284: the opening is a gatherer crew AND a general, only the
## crew can found, and until now nothing on screen said which was which.
##
## The failure this prevents is quiet. Ordering the general to build does
## not error at the player — the order is simply refused server-side
## (`BuildingDef.built_by` lists the general nowhere), so a new player
## clicks, nothing happens, and their economy has not started while the
## other player's has. A coin flip with no feedback either way.
##
## Everything asserted here is against the SHIPPED roster, because the
## whole design of `opening_brief.gd` is that it names no archetype and
## no building — it asks the same `BuildingSim.can_build` the ORDER gate
## asks. A fixture would prove the arithmetic and say nothing about
## whether the panel tells the truth about the game people play.


func _defs_of(civ: StringName) -> Dictionary:
	var out := {}
	for archetype in [&"gatherers", &"general", &"levy"]:
		out[archetype] = UnitRoster.for_civ_archetype(civ, archetype)
	return out


# --- the two openers, on the shipped data -----------------------------

func test_every_civs_crew_is_told_that_it_founds_and_is_spent() -> void:
	for civ in CivRoster.ids():
		var crew := UnitRoster.for_civ_archetype(civ, &"gatherers")
		assert_not_null(crew, "%s must field a gathering crew — it is the opening" % civ)
		if crew == null:
			continue
		assert_true(OpeningBrief.can_found(crew),
			"%s's crew must be able to found the town centre" % civ)
		var line := OpeningBrief.role_line(crew)
		assert_false(line.is_empty(),
			"%s's crew must say what it is for" % civ)
		# D-20260823 keeps consume-on-COMMIT deliberately, and a player who
		# does not know their crew is spent plans an opening that cannot
		# happen. It is the half of the rule that surprises people.
		assert_true(line.to_lower().contains("spent"),
			"and must say it is spent doing it: %s" % line)


func test_every_civs_general_is_told_that_it_cannot_build() -> void:
	for civ in CivRoster.ids():
		var general := UnitRoster.for_civ_archetype(civ, &"general")
		assert_not_null(general, "%s must field a general — it is the other half of the opening" % civ)
		if general == null:
			continue
		assert_false(OpeningBrief.can_found(general),
			"%s's general must NOT be able to found anything (D-20260823)" % civ)
		var line := OpeningBrief.role_line(general)
		assert_true(line.to_lower().contains("cannot build"),
			"%s's general must say so outright: %s" % [civ, line])


func test_ordinary_troops_are_not_editorialised_about() -> void:
	# A panel that explained every unit would be noise a player learns to
	# skip — and it would take the two lines that matter with it.
	for civ in CivRoster.ids():
		var levy := UnitRoster.for_civ_archetype(civ, &"levy")
		if levy == null:
			continue
		assert_eq(OpeningBrief.role_line(levy), "",
			"%s's levy needs no explanation" % civ)


func test_the_line_agrees_with_the_rule_the_server_enforces() -> void:
	# The equivalence that makes this safe: the panel asks the same
	# `BuildingSim.can_build` against the same `built_by` the ORDER gate
	# does. A hint derived from a second rule is a hint that eventually
	# lies, and this project has that defect on file more than once
	# (D-058/D-065).
	var town := OpeningBrief.founding_building()
	assert_not_null(town, "the roster must have a building that spends its founder")
	for civ in CivRoster.ids():
		for archetype in [&"gatherers", &"general", &"levy", &"archers"]:
			var def := UnitRoster.for_civ_archetype(civ, archetype)
			if def == null:
				continue
			assert_eq(OpeningBrief.can_found(def),
				BuildingSim.can_build(town, def.archetype),
				"%s/%s: the panel and the order gate must agree" % [civ, archetype])


func test_the_founding_building_is_found_by_its_rule_not_its_name() -> void:
	# `opening_brief.gd` names no building. It looks for the one that
	# SPENDS its builder, which `tests/test_opening.gd` separately asserts
	# is exactly one — so a second one becomes a design decision rather
	# than a silently-wrong hint.
	var town := OpeningBrief.founding_building()
	assert_not_null(town)
	assert_true(town.consumes_builder,
		"the founding building is the one that spends its builder")
	# Comment lines are stripped first, the same precedent
	# `test_steam_boundary.gd` set: the rule is that CODE must not name a
	# building or an archetype, and prose explaining why it does not is
	# not a violation. A guard that fired on its own explanation is a
	# guard people delete the explanation to satisfy.
	var source := _uncommented(_read("res://opening_brief.gd"))
	assert_false(source.contains("town_centre"),
		"opening_brief.gd must not name a building id")
	for archetype in ["gatherers", "&\"general\"", "militia", "levy"]:
		assert_false(source.contains(archetype),
			"opening_brief.gd must not name an archetype (%s) — D-046 criterion 3" % archetype)


# --- what to do first --------------------------------------------------

func test_the_first_objective_names_the_squad_that_can_actually_do_it() -> void:
	var crew := UnitRoster.for_civ_archetype(&"emberdeep", &"gatherers")
	var general := UnitRoster.for_civ_archetype(&"emberdeep", &"general")
	var town := OpeningBrief.founding_building()

	var line := OpeningBrief.first_objective([crew, general], false)
	assert_true(line.contains(crew.display_name),
		"the objective must name the crew: %s" % line)
	assert_true(line.contains(town.display_name),
		"and what to build: %s" % line)
	assert_false(line.contains(general.display_name),
		"and must not name the general as the thing to select: %s" % line)


func test_the_objective_goes_away_once_there_is_a_town_centre() -> void:
	# A standing hint that never leaves is a hint a player stops reading —
	# and then does not read the next one either.
	var crew := UnitRoster.for_civ_archetype(&"emberdeep", &"gatherers")
	assert_eq(OpeningBrief.first_objective([crew], true), "",
		"once the town centre stands there is nothing to say")


func test_a_player_with_no_founder_is_told_what_they_need() -> void:
	# The state a razed player is in. D-20260823 made resettling possible
	# — any crew can found a new hall — and silence here would leave
	# somebody who has just lost their base with no idea it is allowed.
	var general := UnitRoster.for_civ_archetype(&"emberdeep", &"general")
	var line := OpeningBrief.first_objective([general], false)
	assert_false(line.is_empty(), "a player who cannot found must still be told something")
	assert_true(line.to_lower().contains("no squad"),
		"and told plainly that nothing they own can do it: %s" % line)


func test_nothing_is_said_when_there_is_nothing_to_say() -> void:
	assert_eq(OpeningBrief.role_line(null), "")
	assert_false(OpeningBrief.can_found(null))
	assert_eq(OpeningBrief.first_objective([], true), "")


# --- and the panel actually says it ------------------------------------

func test_the_selection_panel_shows_the_role() -> void:
	# The caller-exists check (D-106's rule as a test). This whole file is
	# about a fact that was true and invisible; computing a better one and
	# not drawing it would be the same bug with more steps.
	var client := _read("res://client.gd")
	assert_true(client.contains("OpeningBrief.role_line("),
		"client.gd must show a selected squad's role in the opening")
	assert_true(client.contains("OpeningBrief.first_objective("),
		"and must show what to do first, in the banner slot")


## The same text with whole-line comments removed, for scans where a
## comment explaining the forbidden thing would otherwise trip the check.
func _uncommented(text: String) -> String:
	var kept := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text
