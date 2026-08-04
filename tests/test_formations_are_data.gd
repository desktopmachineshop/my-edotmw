extends GutTest

## Guards D-058's data half: formations are /formations/*.tres, not a list
## in a script.
##
## The first version of D-058 shipped with `Formation.PLAYER_SHAPES` as a
## const Array and the ranks, spacing multipliers and scatter amount as
## literals inside the geometry functions. Every one of those is a tuning
## number somebody balancing the game should be able to move without
## editing a script — which is D-010's whole premise and the reason this
## project is editable without the Godot GUI.
##
## Modelled on the test that no script names a civ (D-046 criterion 3),
## and for the same reason: the rule is only real if breaking it fails.


func test_the_roster_is_not_empty_and_offers_a_choice() -> void:
	assert_gt(FormationRoster.load_all().size(), 0,
		"no formations under /formations — every squad would fall back to a line")
	assert_gt(FormationRoster.offered().size(), 1,
		"a player is offered fewer than two formations, so there is no choice to make")


func test_every_formation_names_an_implemented_kind() -> void:
	# A .tres naming a kind nothing implements would fall through
	# `Formation._offset_for`'s default and silently stack the squad into a
	# line, with only a push_error nobody reads.
	for def in FormationRoster.load_all():
		var a := Formation.slot_offset(String(def.id), 3, 20, 1.0)
		var b := Formation.slot_offset(String(def.id), 9, 20, 1.0)
		assert_ne(a, b,
			"'%s' (kind '%s') put two soldiers in the same place — is that kind implemented?" % [
				def.id, def.kind])


func test_no_script_hardcodes_the_offered_formation_list() -> void:
	# The specific regression: a second copy of the offered set living in
	# client.gd or server.gd would drift from the files, and the two sides
	# would disagree about what a player may order.
	var offered := FormationRoster.offered_ids()
	assert_gt(offered.size(), 0, "nothing offered, so nothing to check")

	var dir := DirAccess.open("res:/" + "/")
	assert_not_null(dir, "res:// unreadable")
	if dir == null:
		return

	for file_name in dir.get_files():
		var name := String(file_name).trim_suffix(".remap")
		if not name.ends_with(".gd"):
			continue
		# formation.gd and formation_roster.gd are allowed to know the
		# fallback id; they are the implementation.
		if name in ["formation.gd", "formation_roster.gd", "formation_def.gd"]:
			continue
		var source := FileAccess.get_file_as_string("res://%s" % name)
		if source == "":
			continue

		# A script listing two or more offered ids together is building its
		# own copy of the roster. One mention is a legitimate default or a
		# comment; a list is the thing being banned.
		var mentions := 0
		for id in offered:
			if source.contains('"%s"' % id):
				mentions += 1
		assert_lt(mentions, offered.size(),
			("%s names every offered formation — that is a second copy of the "
			+ "roster, and it will drift from /formations") % name)
