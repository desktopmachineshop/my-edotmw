extends GutTest

## Guards `D-20260827-the-tree-is-the-ladder` and
## `D-20260827-a-research-site-is-a-building`.
##
## The centrepiece is `test_every_civ_can_climb_every_rung`. Everything
## else checks that the data says what `docs/plans/tech-tree.md` says it
## says; that one checks a civ cannot be LOCKED OUT of the ladder by its
## own identity — three civs have no stables and two have no forge, and a
## defining tech behind a building a civ lacks would be a permanent stop
## at that rung with nothing failing.
##
## The reachability check is not hypothetical. The first draft of the tree
## had a real cycle: Windmarch's epoch-2 defining tech was researched at
## the Home Herd, and the Home Herd required that same tech.


const UNIVERSAL_SITES: Array[StringName] = [
	&"town_centre", &"barracks", &"storehouse",
]


func _civs() -> Array[StringName]:
	return CivRoster.ids()


# --- the tree is DATA (D-047's rule, applied to techs) -----------------

const EXEMPT_PREFIXES := ["res://tests/", "res://addons/"]


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))


func test_no_script_names_a_tech_or_an_epoch() -> void:
	# The same scan `tests/test_civs.gd` runs for civ ids, for the same
	# reason: if this fails, adding a tech has stopped being a data change.
	# The fix is never to add the name to an exempt list — it is to find
	# the knob the branch wanted and put it in the schema.
	var names: Array[String] = []
	for tech in TechRoster.load_all():
		names.append(String(tech.id))
		if not names.has(String(tech.line)):
			names.append(String(tech.line))
	for epoch in TechRoster.epochs():
		names.append(epoch.display_name)
	assert_gt(names.size(), 20, "This check is vacuous with almost no techs")

	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10,
		"Found almost no scripts — the walk is broken, not the code clean")

	var offences: Array = []
	for script_path in scripts:
		var exempt := false
		for prefix in EXEMPT_PREFIXES:
			if String(script_path).begins_with(prefix):
				exempt = true
				break
		if exempt:
			continue
		var handle := FileAccess.open(script_path, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		for name in names:
			# Word-ish match: `drill` must not fire on the word "drilled"
			# in a comment, and `holding` must not fire on "holding".
			# Quoted-StringName form is how a script would actually name
			# one, and it is what this is looking for.
			if text.contains('&"%s"' % name):
				offences.append("%s names tech/epoch '%s'" % [script_path, name])

	assert_eq(offences, [],
		"Scripts must not know which techs or epochs exist")


# --- every tech loads and validates ------------------------------------

func test_every_shipped_tech_loads_and_validates() -> void:
	var techs := TechRoster.load_all()
	assert_gt(techs.size(), 40, "the shipped tree is much bigger than this")
	var ids := {}
	for tech in techs:
		assert_eq(tech.validate(), "", "tech %s is invalid" % tech.id)
		assert_ne(tech.display_name, "", "tech %s has no display name" % tech.id)
		assert_false(ids.has(tech.id), "two techs share the id %s" % tech.id)
		ids[tech.id] = true


func test_every_effect_field_is_in_the_closed_vocabulary() -> void:
	# Invariant 5. A typo'd field is a tech that costs resources, fills a
	# bar and does NOTHING — the declared-and-unread family, and the one
	# instance of it that would ship wearing a green verdict.
	var checked := 0
	for tech in TechRoster.load_all():
		for pair in [[tech.unit_effects, "unit"], [tech.building_effects, "building"],
				[tech.civ_effects, "civ"]]:
			for effect in (pair[0] as Array):
				assert_eq((effect as TechEffect).validate(pair[1] as String), "",
					"tech %s has a bad %s effect" % [tech.id, pair[1]])
				checked += 1
	assert_gt(checked, 50, "almost no effects were checked — the walk is broken")


func test_every_effect_target_is_a_real_archetype() -> void:
	# The other half of the same defect: a valid FIELD aimed at an
	# archetype nothing fields is a tech that also does nothing.
	var unit_archetypes := {&"*": true}
	for def in UnitRoster.load_all():
		unit_archetypes[def.archetype] = true
	var building_archetypes := {&"*": true}
	for def in BuildingSim.all_defs():
		building_archetypes[BuildingSim.archetype_of_def(def)] = true

	var offences: Array = []
	for tech in TechRoster.load_all():
		for effect in tech.unit_effects:
			if not unit_archetypes.has((effect as TechEffect).target):
				offences.append("%s targets unit archetype '%s', which nothing fields"
					% [tech.id, (effect as TechEffect).target])
		for effect in tech.building_effects:
			if not building_archetypes.has((effect as TechEffect).target):
				offences.append("%s targets building archetype '%s', which does not exist"
					% [tech.id, (effect as TechEffect).target])
	assert_eq(offences, [], "a tech aimed at nothing is a tech that does nothing")


# --- the ladder ---------------------------------------------------------

func test_every_civ_fields_every_defining_line() -> void:
	# Invariant 1, and the one that matters most: a civ with no tech for a
	# defining line can never leave that epoch. The ladder locked by
	# identity is not asymmetry — it is a bug with a story attached.
	var top := TechRoster.max_epoch()
	assert_gt(top, 1, "there is no ladder at all")
	var offences: Array = []
	for civ in _civs():
		for epoch in range(1, top):
			var lines := TechRoster.defining_lines(epoch)
			assert_gt(lines.size(), 0, "epoch %d defines nothing" % epoch)
			for line in lines:
				if TechRoster.for_civ_line(civ, line) == null:
					offences.append("%s has no '%s' and can never leave epoch %d"
						% [civ, line, epoch])
	assert_eq(offences, [])


func test_every_defining_tech_is_researched_somewhere_that_civ_has() -> void:
	# Invariant 3. The trunk half of every line sits on a universal site;
	# a civ's own arc tech may sit anywhere IT has, because it is authored
	# per civ. Either way the site must exist for that civ, or the tech is
	# unreachable and so is every rung above it.
	var offences: Array = []
	for civ in _civs():
		for epoch in range(1, TechRoster.max_epoch()):
			for line in TechRoster.defining_lines(epoch):
				var tech := TechRoster.for_civ_line(civ, line)
				if tech == null:
					continue
				var site := BuildingSim.for_civ_archetype(civ, tech.research_at)
				if site == null:
					offences.append("%s researches '%s' at '%s', which it cannot build"
						% [civ, tech.id, tech.research_at])
	assert_eq(offences, [])


func test_every_tech_is_researched_at_a_building_that_exists() -> void:
	var offences: Array = []
	for civ in _civs():
		for tech in TechRoster.for_civ(civ):
			var site := BuildingSim.for_civ_archetype(civ, (tech as TechDef).research_at)
			if site == null:
				offences.append("%s: '%s' is researched at '%s', which it has no def for"
					% [civ, (tech as TechDef).id, (tech as TechDef).research_at])
	assert_eq(offences, [], "a tech at a building a civ lacks is a tech that civ cannot reach")


func test_every_tech_is_reachable_from_a_fresh_start() -> void:
	# Invariant 2, and the check that caught a real cycle in the tree's
	# first draft: Windmarch's epoch-2 defining tech was researched at the
	# Home Herd, and the Home Herd required that same tech.
	#
	# Simulates the whole climb rather than walking the graph — grant
	# everything currently researchable, advance the epoch, repeat, and
	# assert it terminates having granted the lot. That is exactly what a
	# player does, so a tech this cannot reach is a tech nobody can.
	for civ in _civs():
		var view := ResearchState.new()
		var all := TechRoster.for_civ(civ)
		var granted := 0
		var rounds := 0
		while rounds < 64:
			rounds += 1
			var available := view.available(0, civ)
			# A building's own `requires_tech` gates the SITE, so a tech
			# at a site whose gate is not yet held is genuinely not
			# available yet — model that, or this passes on a tree a
			# player could not actually walk.
			var startable := []
			for tech in available:
				var site := BuildingSim.for_civ_archetype(civ, (tech as TechDef).research_at)
				if site != null and view.unlocked(0, site.requires_tech):
					startable.append(tech)
			if startable.is_empty():
				break
			for tech in startable:
				view.grant(0, (tech as TechDef).line)
				granted += 1
		assert_eq(granted, all.size(),
			"%s can reach only %d of its %d techs — something is cyclic or stranded"
				% [civ, granted, all.size()])
		assert_eq(view.epoch_of(0, civ), TechRoster.max_epoch(),
			"%s cannot reach the top rung" % civ)


func test_completing_a_defining_line_is_what_advances_the_epoch() -> void:
	# The decision's headline: there is no age-up button.
	var civ := _civs()[0]
	var view := ResearchState.new()
	assert_eq(view.epoch_of(0, civ), 1, "everyone starts at the bottom")

	var lines := TechRoster.defining_lines(1)
	assert_gt(lines.size(), 1,
		"a one-tech 'line' is a button with extra steps — the point is a sequence")

	# Grant all but one: still epoch 1. This is the half that would pass
	# vacuously if `epoch_of` counted "any" instead of "every".
	for i in range(lines.size() - 1):
		view.grant(0, lines[i])
	assert_eq(view.epoch_of(0, civ), 1,
		"an incomplete line must not advance the epoch")
	view.grant(0, lines[lines.size() - 1])
	assert_eq(view.epoch_of(0, civ), 2, "completing the line IS the age-up")


func test_an_epoch_cannot_be_skipped() -> void:
	# Granting a later rung's line while missing an earlier one must not
	# read as having climbed past it. Unreachable through the ordinary
	# gate, and a scenario granting an arbitrary set could do it.
	var civ := _civs()[0]
	var view := ResearchState.new()
	for line in TechRoster.defining_lines(2):
		view.grant(0, line)
	assert_eq(view.epoch_of(0, civ), 1,
		"epoch 2's line means nothing while epoch 1's is unfinished")


func test_a_tech_above_your_epoch_is_refused() -> void:
	var civ := _civs()[0]
	var view := ResearchState.new()
	var late: TechDef = null
	for tech in TechRoster.for_civ(civ):
		if (tech as TechDef).epoch >= 3:
			late = tech
			break
	assert_not_null(late, "no tech sits above epoch 2 — the ladder is flat")
	assert_ne(view.can_research(0, civ, late.line), "",
		"epoch gates techs; a fresh player may not start a rung-3 tech")


# --- the costs are D-069's, and must stay so ---------------------------

func test_each_defining_line_sums_to_the_advance_it_replaces() -> void:
	# Invariant 7. D-069 derived these four totals from D-068's phase
	# table; this decision SPLIT them across two techs and re-derived
	# nothing. A test is what stops the halves drifting apart until the
	# sum is a number nobody chose.
	var expected := {
		1: {"f": 500, "w": 300, "g": 0, "s": 0, "t": 90.0},
		2: {"f": 800, "w": 500, "g": 200, "s": 0, "t": 120.0},
		3: {"f": 1200, "w": 800, "g": 500, "s": 0, "t": 150.0},
		4: {"f": 1800, "w": 1200, "g": 900, "s": 400, "t": 180.0},
	}
	for civ in _civs():
		for epoch in expected:
			var f := 0
			var w := 0
			var g := 0
			var s := 0
			var t := 0.0
			for line in TechRoster.defining_lines(epoch):
				var tech := TechRoster.for_civ_line(civ, line)
				assert_not_null(tech, "%s has no '%s'" % [civ, line])
				if tech == null:
					continue
				f += tech.cost_food
				w += tech.cost_wood
				g += tech.cost_gold
				s += tech.cost_stone
				t += tech.research_time
			var want: Dictionary = expected[epoch]
			assert_eq(f, int(want["f"]), "%s epoch %d food" % [civ, epoch])
			assert_eq(w, int(want["w"]), "%s epoch %d wood" % [civ, epoch])
			assert_eq(g, int(want["g"]), "%s epoch %d gold" % [civ, epoch])
			assert_eq(s, int(want["s"]), "%s epoch %d stone" % [civ, epoch])
			assert_almost_eq(t, float(want["t"]), 0.01,
				"%s epoch %d research time" % [civ, epoch])


# --- the research sites -------------------------------------------------

func test_no_research_site_is_neutral() -> void:
	# Invariant 4. A neutral def SHADOWS every per-civ one under id-order
	# resolution — which is how the per-civ gatherers went quietly absent
	# in D-20260823-the-opening-is-a-crew-and-a-general. A neutral
	# `stables.tres` would hand three civs a stables they are supposed not
	# to have, and nothing would fail.
	var sites := {}
	for tech in TechRoster.load_all():
		if not UNIVERSAL_SITES.has(tech.research_at):
			sites[tech.research_at] = true
	assert_gt(sites.size(), 0, "no non-universal research site exists — the branches are gone")
	for def in BuildingSim.all_defs():
		var archetype := BuildingSim.archetype_of_def(def)
		if sites.has(archetype):
			assert_ne(def.civ, &"neutral",
				"%s is a neutral '%s' and shadows every civ's own" % [def.id, archetype])


func test_the_holes_in_the_building_list_are_real() -> void:
	# The decision's headline claim, asserted rather than described: some
	# civs genuinely cannot research some branches. If this ever passes
	# vacuously — every civ having every site — the asymmetry has been
	# quietly tidied away and the identity with it.
	var non_universal := {}
	for tech in TechRoster.load_all():
		if not UNIVERSAL_SITES.has(tech.research_at):
			non_universal[tech.research_at] = true

	var missing := 0
	var have_all := 0
	for civ in _civs():
		var lacks := false
		for archetype in non_universal:
			if BuildingSim.for_civ_archetype(civ, archetype) == null:
				lacks = true
				missing += 1
		if not lacks:
			have_all += 1
	assert_gt(missing, 0, "every civ has every research site — the asymmetry is gone")
	assert_gt(have_all, 0, "no civ has every site — 'breadth' is nobody's identity")


func test_a_civ_is_only_offered_its_own_buildings() -> void:
	var civs := _civs()
	assert_gt(civs.size(), 1, "vacuous with one civ")
	for civ in civs:
		for def in BuildingSim.defs_for_civ(civ):
			assert_true(def.civ == civ or def.civ == &"neutral",
				"%s is offered %s, which belongs to %s" % [civ, def.id, def.civ])


func test_the_archetype_fallback_leaves_every_shipped_building_alone() -> void:
	# `BuildingDef.archetype` defaults empty and falls back to `id`, which
	# is the whole reason adding it edited none of the nine defs that
	# shipped before it.
	for def in BuildingSim.all_defs():
		if def.archetype == &"":
			assert_eq(BuildingSim.archetype_of_def(def), def.id,
				"%s has no archetype and does not fall back to its id" % def.id)


# --- the units behind the tree -----------------------------------------

func test_every_units_gate_is_a_line_that_civ_can_research() -> void:
	# A unit gated on a line its own civ has no tech for is a unit nobody
	# can ever build — the same shape as the defining-line hole, one level
	# down, and equally invisible to every other check.
	var offences: Array = []
	for def in UnitRoster.load_all():
		if def.requires_tech == &"":
			continue
		var civ := def.civ
		if civ == &"neutral":
			continue
		if TechRoster.for_civ_line(civ, def.requires_tech) == null:
			offences.append("%s needs '%s', which %s cannot research"
				% [def.id, def.requires_tech, civ])
	assert_eq(offences, [])


func test_the_opening_is_not_gated() -> void:
	# The safe default, asserted: every gatherer, general and levy is
	# producible at epoch 1, so the opening, every scenario and every bot
	# behave exactly as they did before the tree existed.
	for def in UnitRoster.load_all():
		if def.carry_capacity > 0 or def.is_general or def.archetype == &"levy":
			assert_eq(def.requires_tech, &"",
				"%s is part of the opening and must not be gated" % def.id)


func test_every_civs_signature_sits_behind_a_tech() -> void:
	# Issue #206's explicit ask, and the reason unit gates are on TECHS
	# rather than on an epoch number: an epoch gate is not a decision,
	# because everybody climbs.
	#
	# A civ's signature is the archetype only IT fields, which is derived
	# rather than listed — a list here would be a second source of truth
	# for `/units` (`civ_def.gd`'s own argument).
	var fielded_by := {}
	for def in UnitRoster.load_all():
		if def.civ == &"neutral":
			continue
		var civs: Array = fielded_by.get(def.archetype, [])
		if not civs.has(def.civ):
			civs.append(def.civ)
		fielded_by[def.archetype] = civs

	var exclusives := 0
	for def in UnitRoster.load_all():
		var civs: Array = fielded_by.get(def.archetype, [])
		if civs.size() != 1 or def.carry_capacity > 0 or def.is_general:
			continue
		exclusives += 1
		assert_ne(def.requires_tech, &"",
			"%s is %s's signature and is buildable from the first minute"
				% [def.id, def.civ])
	assert_gt(exclusives, 4, "almost no exclusive units found — the walk is broken")


func test_mounted_and_siege_are_produced_at_their_own_sites() -> void:
	# The second half of "a civ without the building cannot walk that
	# branch". Without the production move the BRANCH is optional and the
	# UNITS are not, so a civ with no forge would still field engines.
	var barracks := BuildingSim.def_by_id(&"barracks")
	assert_not_null(barracks)
	for archetype in [&"cavalry", &"bowriders", &"engine", &"ram", &"bombard", &"breaker"]:
		assert_false(barracks.produces.has(archetype),
			"the barracks still trains %s — the branch buys nothing" % archetype)

	# And every gated unit has SOMEWHERE its civ can train it.
	var offences: Array = []
	for def in UnitRoster.load_all():
		if def.civ == &"neutral":
			continue
		var found := false
		for building in BuildingSim.defs_for_civ(def.civ):
			if building.produces.has(def.archetype):
				found = true
				break
		if not found:
			offences.append("%s (%s) is trained nowhere its civ can build"
				% [def.id, def.archetype])
	assert_eq(offences, [])


# --- the epoch ladder itself -------------------------------------------

func test_the_epochs_load_and_are_contiguous() -> void:
	var epochs := TechRoster.epochs()
	assert_gt(epochs.size(), 1, "there is no ladder")
	for i in range(epochs.size()):
		assert_eq(epochs[i].index, i + 1, "epoch indices must be 1..n with no gaps")
		assert_eq(epochs[i].validate(), "", "epoch %d is invalid" % epochs[i].index)


func test_every_civ_names_every_rung_in_its_own_words() -> void:
	# `CivDef.epoch_names` is flavour and nothing mechanical reads it —
	# which is exactly why it would rot unnoticed. The arc table in
	# docs/plans/fantasy-civs.md is the civ's whole development story and
	# it is the thing a player actually reads on advancing.
	var top := TechRoster.max_epoch()
	for civ in _civs():
		var def := CivRoster.by_id(civ)
		assert_eq(def.epoch_names.size(), top,
			"%s names %d of %d rungs" % [civ, def.epoch_names.size(), top])
		for i in range(top):
			assert_ne(TechRoster.epoch_name(civ, i + 1), "",
				"%s has no name for rung %d" % [civ, i + 1])
