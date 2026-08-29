extends GutTest

## Guards #305: the in-game manual, and the rule that keeps it honest.
##
## The manual has two halves and they fail differently, so this file is in
## two halves too.
##
## The GENERATED half cannot be stale, and the tests for it check that it
## is genuinely derived rather than checking what it currently says. A
## test asserting "Hearth Levy has 85 health" would be a second copy of
## the roster — the exact defect the generated half exists to avoid, moved
## into the test suite.
##
## The PROSE half CAN be stale, and the staleness guard is the deliverable
## the owner asked for: a gameplay PR that moves a rule and forgets the
## page it describes goes red. That guard is itself observed to fail
## below, because this project does not trust a check it has not watched
## go red (D-022's audit block).


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func _unit(overrides: Dictionary) -> UnitDef:
	var def := UnitDef.new()
	def.id = &"probe"
	def.display_name = "Probe"
	def.squad_size = 20
	def.health = 100.0
	def.damage = 10.0
	def.attack_interval = 1.0
	def.cost_food = 50
	for key in overrides:
		def.set(key, overrides[key])
	return def


func _civ(id: StringName, overrides: Dictionary = {}) -> CivDef:
	var def := CivDef.new()
	def.id = id
	def.display_name = String(id).capitalize()
	for key in overrides:
		def.set(key, overrides[key])
	return def


# --- the registry ------------------------------------------------------


func test_every_page_is_titled_summarised_and_ordered() -> void:
	var pages := Manual.pages()
	assert_gt(pages.size(), 4, "a manual with four pages is a leaflet")
	var seen := {}
	for entry in pages:
		var id := String(entry["id"])
		assert_false(id.is_empty(), "every page has an id")
		assert_false(seen.has(id), "%s is registered twice" % id)
		seen[id] = true
		assert_false(String(entry["title"]).strip_edges().is_empty(),
			"%s has no title" % id)
		assert_false(String(entry["summary"]).strip_edges().is_empty(),
			"%s has no summary — the contents list shows it" % id)
		assert_true(entry["kind"] == Manual.GENERATED or entry["kind"] == Manual.PROSE,
			"%s is neither generated nor prose, and there is no third kind" % id)


func test_the_contents_list_is_in_a_deliberate_order() -> void:
	# Sorted by `order`, ties broken on id. Stability matters for the same
	# reason it does in UnitRoster: `DirAccess` enumeration order is not a
	# promise, and a contents list that reshuffled between launches would
	# be unusable.
	var pages := Manual.pages()
	for i in range(1, pages.size()):
		var before: Dictionary = pages[i - 1]
		var after: Dictionary = pages[i]
		assert_true(int(before["order"]) < int(after["order"])
			or (int(before["order"]) == int(after["order"])
				and String(before["id"]) < String(after["id"])),
			"%s must not come before %s" % [before["id"], after["id"]])


func test_every_registered_page_has_something_on_it() -> void:
	# The caller-exists rule (D-106) pointed at content: a page in the
	# contents list that opens blank is worse than a page that is missing,
	# because the player goes looking for it.
	for entry in Manual.pages():
		var built := Manual.page(entry["id"])
		assert_false(String(built["title"]).is_empty(),
			"%s has no title when opened" % entry["id"])
		var sections: Array = built["sections"]
		assert_gt(sections.size(), 0, "%s opens empty" % entry["id"])
		var content := 0
		for section in sections:
			if section["kind"] == "table":
				content += (section["rows"] as Array).size()
			else:
				for line in section["lines"]:
					if String(line).strip_edges() != "":
						content += 1
		assert_gt(content, 0, "%s has sections but nothing in them" % entry["id"])


func test_every_prose_page_loads_and_validates() -> void:
	var pages := Manual.prose_pages()
	assert_gt(pages.size(), 0, "there are hand-written pages")
	for def in pages:
		assert_eq(def.validate(), "", "%s is not a valid page" % def.id)


# --- the staleness guard ------------------------------------------------


func test_every_prose_page_is_stamped_against_the_rules_it_describes() -> void:
	# THE guard #305 asks for. A gameplay PR that moves a rule and leaves
	# the page describing it untouched goes red here, naming the page.
	#
	# Re-read the page before re-stamping. `just build-manual` will renew
	# the stamp without asking, which is the one thing it cannot check for
	# you — but it is this failure that tells you which page to open, and
	# that is the whole mechanism.
	for def in Manual.prose_pages():
		var expected: String = def.expected_stamp()
		assert_eq(def.stamp, expected,
			("manual page '%s' is stamped against a different version of %s "
			+ "than the one in this tree. Read the page, fix what has stopped "
			+ "being true, then run `just build-manual`.")
			% [def.id, ", ".join(def.sources)])


func test_every_source_a_page_names_still_exists() -> void:
	# Separate from the stamp on purpose. A renamed decision entry and a
	# changed rule both mismatch the hash, and they want different things
	# from the reader — one is a path to fix, the other is prose to
	# rewrite.
	for def in Manual.prose_pages():
		var missing: Array = def.missing_sources()
		assert_eq(missing.size(), 0,
			"manual page '%s' names sources that are not there: %s"
			% [def.id, ", ".join(missing)])


func test_the_stamp_notices_a_source_changing() -> void:
	# The guard, observed to fail. Every check in this project has to be
	# watched go red before it is trusted (D-022's audit block), and a
	# staleness test is the shape most likely to pass vacuously — a hash
	# over nothing compares equal to a hash over nothing forever.
	var path := "user://manual-stamp-probe.txt"
	var page := ManualPageDef.new()
	page.sources = [path]

	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string("the rout threshold is 25")
	handle.close()
	var before: String = page.expected_stamp()

	handle = FileAccess.open(path, FileAccess.WRITE)
	handle.store_string("the rout threshold is 30")
	handle.close()
	var after: String = page.expected_stamp()

	assert_ne(before, after,
		"a source changing must change the stamp, or the guard is decorative")
	assert_eq(before.length(), 64, "a sha256 in hex")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_stamp_notices_a_source_being_renamed_away() -> void:
	# The path is fed BEFORE the contents (art/build.py's rule), so a page
	# stamped against a decision entry that has since been renamed is a
	# page stamped against nothing — and says so.
	var here := ManualPageDef.new()
	here.sources = ["res://combat.gd"]
	var gone := ManualPageDef.new()
	gone.sources = ["res://combat_renamed_away.gd"]
	assert_ne(here.expected_stamp(), gone.expected_stamp(),
		"a source that has moved must not hash the same as one that has not")


func test_the_stamp_is_blind_to_line_endings() -> void:
	# A worktree created before `* text=auto eol=lf` still holds CRLF on
	# disk until its owner runs the settle (D-20260818-every-file-has-a-
	# line-ending-rule). Hashing raw bytes would red this whole guard on
	# those machines for a difference git does not consider a change at
	# all — and a check that red-flags a good tree is worse than no check,
	# because the next person raises it until it passes.
	var lf := "user://manual-stamp-lf.txt"
	var crlf := "user://manual-stamp-crlf.txt"
	var handle := FileAccess.open(lf, FileAccess.WRITE)
	handle.store_string("one\ntwo\nthree\n")
	handle.close()
	handle = FileAccess.open(crlf, FileAccess.WRITE)
	handle.store_string("one\r\ntwo\r\nthree\r\n")
	handle.close()

	# Same NAME on both sides, because the path is part of the hash.
	var page := ManualPageDef.new()
	page.sources = [lf]
	var as_lf: String = page.expected_stamp()
	page.sources = [crlf]
	var as_crlf_path: String = page.expected_stamp()
	assert_ne(as_lf, as_crlf_path, "Setup: different paths hash differently")

	# So compare contents at one path, rewritten.
	handle = FileAccess.open(lf, FileAccess.WRITE)
	handle.store_string("one\r\ntwo\r\nthree\r\n")
	handle.close()
	page.sources = [lf]
	assert_eq(page.expected_stamp(), as_lf,
		"the same text with different line endings must stamp the same")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lf))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(crlf))


func test_no_prose_page_quotes_a_constant_that_does_not_exist() -> void:
	# `{Combat.CHAIN_ROUT_MORALE_LOSS}` is resolved from combat.gd's own
	# constant map, so prose that quotes a number quotes the real one. A
	# renamed or deleted constant leaves the token in the rendered page,
	# which is visibly broken but only to somebody who opens it.
	for def in Manual.prose_pages():
		var bad: Array = Manual.unresolved_tokens(def.body)
		assert_eq(bad.size(), 0,
			"manual page '%s' writes %s, which resolves to nothing"
			% [def.id, ", ".join(bad)])


func test_a_quoted_constant_is_the_one_the_game_uses() -> void:
	# Observed to fail in the other direction: the substitution has to
	# actually substitute, or every page quoting a number silently ships
	# the token.
	var text := "flank costs {Combat.FLANK_MORALE_MULT}, rear {Combat.REAR_MORALE_MULT}"
	var resolved := Manual.resolve_constants(text)
	assert_false(resolved.contains("{"), "the tokens must be gone: %s" % resolved)
	assert_true(resolved.contains(str(Combat.FLANK_MORALE_MULT)),
		"and be replaced with combat.gd's own number: %s" % resolved)


func test_at_least_one_page_actually_quotes_a_constant() -> void:
	# Otherwise the whole substitution mechanism is dead code passing its
	# own tests — the declared-and-unread family, in the guard rather than
	# the feature (#184 found exactly that in the Steam boundary).
	var quoting := 0
	for def in Manual.prose_pages():
		if def.body.contains("{Combat.") or def.body.contains("{SquadSim."):
			quoting += 1
	assert_gt(quoting, 0,
		"no page quotes a script constant, so nothing exercises the substitution")


# --- the generated half is genuinely generated -------------------------


func test_the_troops_page_lists_every_unit_the_game_ships() -> void:
	# Derived rather than pinned: the assertion is that the page and the
	# roster agree, not that either says anything in particular.
	var text := ""
	for section in Manual.troop_sections():
		if section["kind"] != "table":
			continue
		for row in section["rows"]:
			text += String(row[0]) + "\n"
	for def in UnitRoster.load_all():
		assert_true(text.contains(def.display_name),
			"%s is in the game and not in the manual" % def.display_name)


func test_a_units_numbers_come_from_its_def() -> void:
	# The perturbation the shipped roster cannot show: change the def,
	# and the derived figure changes with it.
	var weak := _unit({"damage": 10.0})
	var strong := _unit({"damage": 40.0})
	assert_gt(Manual.power(strong), Manual.power(weak),
		"more damage must be more power")
	assert_eq(Manual.dps(weak), 200.0, "20 men x 10 damage / 1.0s")
	assert_eq(Manual.effective_health(weak), 2000.0, "20 men x 100 health")
	# D-072: V = sqrt(DPS x EHP).
	assert_almost_eq(Manual.power(weak), sqrt(200.0 * 2000.0), 0.01,
		"V is D-072's formula, not an approximation of it")


func test_the_price_of_a_unit_is_read_off_its_four_costs() -> void:
	assert_eq(Manual.price(_unit({"cost_food": 48, "cost_wood": 0})), "48f")
	assert_eq(Manual.price(_unit({"cost_food": 40, "cost_wood": 20})), "40f 20w")
	assert_eq(Manual.price(_unit({"cost_food": 0, "cost_stone": 30})), "30s")
	assert_eq(Manual.price(_unit({"cost_food": 0})), "free",
		"a unit that costs nothing says so rather than showing an empty cell")
	# D-072's RP weights gold and stone at 1.5.
	assert_eq(Manual.resource_points(_unit({"cost_food": 10, "cost_gold": 10})), 25.0)


func test_the_counter_table_and_its_inverse_agree() -> void:
	# Two directions of one fact — "who hits harder" and "what to be
	# afraid of" — inverted from the same data rather than written twice,
	# because two hand-written lists of one relation is the pair that
	# comes to disagree (D-058/D-065's family).
	var forward := ""
	var backward := ""
	for section in Manual.counter_sections():
		if section["kind"] != "table":
			continue
		var into := forward if String(section["heading"]).begins_with("Who") else backward
		for row in section["rows"]:
			into += " | ".join(row) + "\n"
		if String(section["heading"]).begins_with("Who"):
			forward = into
		else:
			backward = into
	for def in UnitRoster.load_all():
		if not Manual.is_fighting(def):
			continue
		for armour in def.bonus_vs:
			if float(def.bonus_vs[armour]) <= 1.0:
				continue
			assert_true(forward.contains(def.display_name),
				"%s has a bonus and is missing from the counter table" % def.display_name)
			assert_true(backward.contains(def.display_name),
				"%s has a bonus and nothing is warned about it" % def.display_name)


func test_a_buildings_role_is_read_off_its_fields() -> void:
	# Never off its id. `opening_brief.gd`'s discipline: the founding
	# building is the one that spends its builder, so a renamed or second
	# one needs no edit.
	var founder := BuildingDef.new()
	founder.consumes_builder = true
	assert_true(Manual.building_role(founder).contains("spends the crew"))
	var shop := BuildingDef.new()
	shop.is_drop_off = true
	assert_true(Manual.building_role(shop).contains("deliver"))
	var tower := BuildingDef.new()
	tower.damage = 60.0
	tower.attack_range = 6.0
	assert_true(Manual.building_role(tower).contains("shoots"))


func test_the_formations_page_says_who_may_actually_use_each_shape() -> void:
	# Reachability is two conditions and the server checks both, so the
	# page reads both. Driven with synthetic defs, because the shipped
	# data currently exercises only two of the three answers (#309).
	var everyones := FormationDef.new()
	everyones.id = &"probe_offered"
	everyones.offered = true
	assert_eq(Manual.formation_users(everyones), "Any squad")

	var nobodys := FormationDef.new()
	nobodys.id = &"probe_ungranted"
	nobodys.offered = false
	assert_eq(Manual.formation_users(nobodys), "Not granted to any troops",
		"a formation no unit grants is a control the player does not have, "
		+ "and the page has to say so rather than omitting the row")


func test_the_formations_page_reports_the_shipped_grants() -> void:
	# The other half, against real data: whatever the roster grants, the
	# page says. This is the assertion that will change on its own when
	# #309 is fixed, which is the point of deriving it.
	for def in FormationRoster.load_all():
		var says := Manual.formation_users(def)
		if def.offered:
			assert_eq(says, "Any squad", "%s is offered to everyone" % def.id)
			continue
		var granters := []
		for unit in UnitRoster.load_all():
			if unit.formations.has(def.id):
				granters.append(unit.display_name)
		if granters.is_empty():
			assert_eq(says, "Not granted to any troops",
				"%s is granted by nobody and the page must say so" % def.id)
		else:
			for name in granters:
				assert_true(says.contains(name),
					"%s grants %s and is not listed" % [name, def.id])


# --- a civ's advantages are MEASURED -----------------------------------


func test_a_knob_above_standard_reads_as_an_advantage() -> void:
	# The claim follows the number, in both directions, so a balance PR
	# that reverses a knob reverses the sentence with nothing edited.
	var fast := _civ(&"probe_fast", {"production_speed": 1.5})
	var slow := _civ(&"probe_slow", {"production_speed": 0.5})
	var plain := _civ(&"probe_plain")
	var peers := [fast, slow, plain]

	var fast_says := CivStanding.measure(fast, peers, [])
	assert_true(_says(fast_says["advantages"], "50% faster"),
		"1.5x production is an advantage stated as a percentage: %s"
		% str(fast_says["advantages"]))
	assert_false(_says(fast_says["disadvantages"], "Trains"),
		"and not also a disadvantage")

	var slow_says := CivStanding.measure(slow, peers, [])
	assert_true(_says(slow_says["disadvantages"], "50% slower"),
		"0.5x production is a disadvantage: %s" % str(slow_says["disadvantages"]))

	var plain_says := CivStanding.measure(plain, peers, [])
	assert_false(_says(plain_says["advantages"], "Trains"),
		"a civ at the schema default claims nothing about training")
	assert_false(_says(plain_says["disadvantages"], "Trains"),
		"in either direction")


func test_the_squad_cap_and_gather_knobs_read_the_same_way() -> void:
	var wide := _civ(&"probe_wide", {"squad_cap_bonus": 4, "gather_speed": 1.15})
	var says := CivStanding.measure(wide, [wide, _civ(&"probe_other")], [])
	assert_true(_says(says["advantages"], "4 squads more"),
		"the cap bonus is stated in squads: %s" % str(says["advantages"]))
	assert_true(_says(says["advantages"], "15% faster"),
		"the gather knob is stated as a percentage: %s" % str(says["advantages"]))


func test_an_exclusive_troop_type_is_counted_not_declared() -> void:
	var mine := _civ(&"probe_mine")
	var theirs := _civ(&"probe_theirs")
	var roster := [
		_unit({"id": &"a", "civ": &"probe_mine", "archetype": &"levy"}),
		_unit({"id": &"b", "civ": &"probe_mine", "archetype": &"bombard"}),
		_unit({"id": &"c", "civ": &"probe_theirs", "archetype": &"levy"}),
	]
	var says := CivStanding.measure(mine, [mine, theirs], roster)
	assert_true(_says(says["advantages"], "only civ that fields bombard"),
		"an archetype one civ has is derived from a count: %s" % str(says["advantages"]))

	var theirs_says := CivStanding.measure(theirs, [mine, theirs], roster)
	assert_false(_says(theirs_says["advantages"], "only civ"),
		"and the civ without it claims nothing")


func test_a_missing_common_troop_type_reads_as_a_disadvantage() -> void:
	var lacking := _civ(&"probe_lacking")
	var peers := [lacking, _civ(&"probe_one"), _civ(&"probe_two")]
	var roster := [
		_unit({"id": &"a", "civ": &"probe_lacking", "archetype": &"levy"}),
		_unit({"id": &"b", "civ": &"probe_one", "archetype": &"levy"}),
		_unit({"id": &"c", "civ": &"probe_one", "archetype": &"cavalry"}),
		_unit({"id": &"d", "civ": &"probe_two", "archetype": &"levy"}),
		_unit({"id": &"e", "civ": &"probe_two", "archetype": &"cavalry"}),
	]
	var says := CivStanding.measure(lacking, peers, roster)
	assert_true(_says(says["disadvantages"], "no cavalry"),
		"two of three civs field cavalry, so lacking it is worth saying: %s"
		% str(says["disadvantages"]))


func test_troops_that_cannot_rout_are_reported_from_the_troop_data() -> void:
	var fearless := _civ(&"probe_fearless")
	var normal := _civ(&"probe_normal")
	var roster := [
		_unit({"id": &"a", "civ": &"probe_fearless", "archetype": &"levy",
			"rout_threshold": 0.0, "morale_loss_per_casualty": 0.0}),
		_unit({"id": &"b", "civ": &"probe_fearless", "archetype": &"spearmen",
			"rout_threshold": 0.0, "morale_loss_per_casualty": 0.0}),
		_unit({"id": &"c", "civ": &"probe_normal", "archetype": &"levy"}),
		_unit({"id": &"d", "civ": &"probe_normal", "archetype": &"spearmen"}),
	]
	var says := CivStanding.measure(fearless, [fearless, normal], roster)
	assert_true(_says(says["advantages"], "never rout"),
		"every fighting unit at zero morale means the civ never routs: %s"
		% str(says["advantages"]))

	# ONE fearless unit is a fact about a unit, not about a civ.
	var mixed := _civ(&"probe_mixed")
	var mixed_roster := roster.duplicate()
	mixed_roster.append(_unit({"id": &"e", "civ": &"probe_mixed", "archetype": &"levy",
		"rout_threshold": 0.0, "morale_loss_per_casualty": 0.0}))
	mixed_roster.append(_unit({"id": &"f", "civ": &"probe_mixed", "archetype": &"heavy"}))
	var mixed_says := CivStanding.measure(mixed, [mixed, normal], mixed_roster)
	assert_false(_says(mixed_says["advantages"], "never rout"),
		"a civ with one fearless unit and one ordinary one does not claim it")


func test_a_civ_that_matches_the_field_claims_nothing_it_has_not_earned() -> void:
	# The margin doing its job. Two civs differing by 1% are the same civ
	# for this purpose, and a page that said otherwise would train its
	# reader to skip it.
	var a := _civ(&"probe_a", {"gather_speed": 1.0})
	var b := _civ(&"probe_b", {"gather_speed": 1.01})
	var says := CivStanding.measure(b, [a, b], [])
	assert_true(_says(says["advantages"], "Gathers"),
		"Setup: a knob above the schema default IS reported, however small")
	# But a roster comparison, which is the margin's domain, is not.
	var roster := [
		_unit({"id": &"x", "civ": &"probe_a", "archetype": &"levy", "move_speed": 3.0}),
		_unit({"id": &"y", "civ": &"probe_a", "archetype": &"heavy", "move_speed": 3.0}),
		_unit({"id": &"z", "civ": &"probe_b", "archetype": &"levy", "move_speed": 3.03}),
		_unit({"id": &"w", "civ": &"probe_b", "archetype": &"heavy", "move_speed": 3.03}),
	]
	var close := CivStanding.measure(b, [a, b], roster)
	assert_false(_says(close["advantages"], "Fast"),
		"1%% quicker is not 'fast': %s" % str(close["advantages"]))


func test_the_shipped_civs_each_say_something() -> void:
	# Against real data, and the only thing it can honestly assert is that
	# the derivation produces SOMETHING for every civ. Asserting what a
	# particular civ is good at would be a second copy of the balance
	# data, which is the defect this whole design avoids.
	var civs := CivRoster.load_all()
	var roster := UnitRoster.load_all()
	assert_gt(civs.size(), 1, "Setup: there are civs to compare")
	for civ in civs:
		var says := CivStanding.measure(civ, civs, roster)
		var total: int = (says["advantages"] as Array).size() \
			+ (says["disadvantages"] as Array).size()
		assert_gt(total, 0,
			("%s is measurably identical to every other civ, which is either "
			+ "a balance finding or a broken derivation") % civ.id)


func _says(claims: Array, fragment: String) -> bool:
	for claim in claims:
		if String(claim).contains(fragment):
			return true
	return false


# --- it fits, and both menus reach it ----------------------------------


func test_the_manual_cannot_push_its_own_close_button_off_the_screen() -> void:
	# `test_controls_reference.gd` measures whether the controls screen
	# FITS, because it does not scroll and a fifth group took it to 731 px
	# against 720. The same measurement here is near-vacuous — the frame
	# asks for 132 px of a 720-high window — and it is vacuous for a
	# reason worth asserting instead of a number worth printing: the
	# contents list and the page BOTH scroll, so no page can be tall
	# enough to push anything off.
	#
	# A check that cannot fail is the thing this project's own audit block
	# forbids (D-022), so this asserts the PROPERTY that makes the screen
	# safe rather than the consequence of it. Replace either
	# ScrollContainer with a plain box and the troops page — seven civs of
	# tables — takes the Close button off the bottom, and this goes red.
	var client: Node3D = autofree(load("res://client.gd").new())
	client._build_manual_screen()
	var layer: CanvasLayer = client._manual_layer
	client.remove_child(layer)
	add_child_autofree(layer)
	layer.visible = true
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(client._manual_scroll is ScrollContainer,
		"the page must scroll, or a long table pushes Close off the bottom")
	assert_true(client._manual_contents.get_parent() is ScrollContainer,
		"and so must the contents list, because pages are added by dropping "
		+ "a .tres in a folder and the list must not be what stops working")

	var frame: Control = null
	for child in layer.get_children():
		if child is MarginContainer:
			frame = child
	assert_not_null(frame, "the manual must have a framed column")
	if frame == null:
		return
	var wanted: float = frame.get_combined_minimum_size().y
	assert_lte(wanted, HudLayout.REFERENCE.y,
		("the manual's fixed chrome wants %d px and the smallest window is "
		+ "%d — the Close button would be off the bottom before any page "
		+ "was even drawn") % [int(wanted), int(HudLayout.REFERENCE.y)])
	gut.p("manual chrome: %d px wanted against %d available (the pages scroll)"
		% [int(wanted), int(HudLayout.REFERENCE.y)])


func test_every_page_has_a_way_in() -> void:
	# #282's lesson as a test: when a layout gets tighter the question is
	# never "what still fits", it is "what can no longer be REACHED". A
	# page in the registry with no button is a page that exists and cannot
	# be opened.
	var client: Node3D = autofree(load("res://client.gd").new())
	client._build_manual_screen()
	var layer: CanvasLayer = client._manual_layer
	client.remove_child(layer)
	add_child_autofree(layer)
	await get_tree().process_frame

	var labels := []
	for child in client._manual_contents.get_children():
		if child is Button:
			labels.append((child as Button).text)
	for entry in Manual.pages():
		assert_true(labels.has(String(entry["title"])),
			"%s is in the manual and has no button in the contents list"
			% entry["title"])
	assert_eq(labels.size(), Manual.pages().size(),
		"and the list has no buttons for pages that do not exist")


func test_both_menus_reach_the_manual() -> void:
	# D-106's caller-exists rule, and here it is the ticket: a manual
	# nothing opens is the gap being closed.
	var client := _read("res://client.gd")
	assert_true(client.contains("Manual.pages()"),
		"client.gd must build the contents list from the one registry")
	assert_true(client.contains("_toggle_manual"), "and offer a way to open it")
	var buttons := client.count("_styled_button(\"Help\"")
	assert_eq(buttons, 2,
		"both the main menu and the in-game menu must offer Help, found %d"
		% buttons)


func test_the_page_is_drawn_from_sections_rather_than_reformatted() -> void:
	# The renderer has two cases and no parser, which is what makes the
	# fit above a property of the DATA rather than of the drawing code.
	# A third `kind` appearing here means client.gd has a case it silently
	# does not draw.
	for entry in Manual.pages():
		for section in Manual.page(entry["id"])["sections"]:
			assert_true(section["kind"] == "text" or section["kind"] == "table",
				"%s has a '%s' section, which nothing draws"
				% [entry["id"], section["kind"]])
			if section["kind"] == "table":
				var columns: Array = section["columns"]
				for row in section["rows"]:
					assert_eq((row as Array).size(), columns.size(),
						"%s has a row of %d cells under %d columns"
						% [entry["id"], (row as Array).size(), columns.size()])
