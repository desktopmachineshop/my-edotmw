extends GutTest

## Guards #282: the controls are written down, in one place, and what is
## written down is what the code does.
##
## A stranger who installed the alpha met a lobby, then a map, with
## nothing anywhere telling them that WASD pans or that right-click
## orders. D-094 criterion 10 — a human playing end to end through an
## installed build — cannot be discharged honestly against a game whose
## controls are undocumented, which is why the gap assessment filed this
## as a **blocker** rather than as polish.
##
## The interesting failure here is not "the screen is missing". It is a
## screen that documents the INTENT rather than the behaviour, which
## turns a bug into the player's fault — so the build and train rows are
## derived from `client.gd`'s own tables, and this file checks the
## derivation rather than the prose.


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func _client_constant(name: String) -> Dictionary:
	var script := load("res://client.gd") as GDScript
	var constants := script.get_script_constant_map()
	assert_true(constants.has(name), "client.gd must still declare %s" % name)
	return constants.get(name, {})


# --- the shape ---------------------------------------------------------

func test_every_group_has_a_title_and_rows() -> void:
	var groups := ControlsReference.groups()
	assert_gt(groups.size(), 0, "there must be some controls")
	for group in groups:
		assert_false(String(group["title"]).is_empty(), "every group is titled")
		assert_gt((group["rows"] as Array).size(), 0,
			"%s must list something" % group["title"])


func test_every_row_is_a_key_and_a_description() -> void:
	for row in ControlsReference.rows():
		assert_eq((row as Array).size(), 2, "a row is [keys, what it does]: %s" % [row])
		assert_false(String(row[0]).strip_edges().is_empty(), "every row names a key")
		assert_false(String(row[1]).strip_edges().is_empty(),
			"and says what it does: %s" % row[0])


func test_no_binding_is_listed_twice() -> void:
	# Two rows for one key is either a copy-paste or a real collision, and
	# #302 is the standing proof that this game HAS a real collision
	# (`G` is a build key and has a dead gather branch). This catches the
	# documentation version of that; it cannot catch the code version,
	# which is what #302 asks for.
	var seen := {}
	for row in ControlsReference.rows():
		var key := String(row[0])
		assert_false(seen.has(key),
			"%s is listed twice: '%s' and '%s'" % [key, seen.get(key, ""), row[1]])
		seen[key] = String(row[1])


# --- it says what the code does ---------------------------------------

func test_the_essential_controls_are_all_there() -> void:
	# #282's own minimum. Named individually rather than counted, because
	# "there are twenty rows" is satisfied by twenty wrong ones.
	var text := ""
	for row in ControlsReference.rows():
		text += "%s|%s\n" % [row[0], row[1]]
	for needed in ["W A S D", "Q / E", "Mouse wheel", "Left-click", "Right-click",
			"Ctrl + 1…9", "Escape"]:
		assert_true(text.contains(needed),
			"the controls screen must mention %s — a stranger has no other way to learn it" % needed)


func test_every_build_key_the_client_binds_is_documented() -> void:
	# Derived, not copied: nine buildings, edited whenever the roster
	# moves, is exactly where a hand-written list goes stale. If this ever
	# fails, `ControlsReference._key_table` has lost its grip on the
	# client's constant and the screen is silently missing its build rows.
	var bound := _client_constant("BUILD_KEYS")
	assert_gt(bound.size(), 0, "Setup: the client binds some build keys")
	var documented := ""
	for row in ControlsReference.rows():
		documented += String(row[0]) + "|"
	for key in bound:
		assert_true(documented.contains(String(key) + "|"),
			"%s builds %s and is not on the controls screen" % [key, bound[key]])


func test_every_train_key_the_client_binds_is_documented() -> void:
	var bound := _client_constant("TRAIN_KEYS")
	assert_gt(bound.size(), 0, "Setup: the client binds some train keys")
	var documented := ""
	for row in ControlsReference.rows():
		documented += String(row[0]) + "|"
	for key in bound:
		assert_true(documented.contains(String(key) + "|"),
			"%s trains %s and is not on the controls screen" % [key, bound[key]])


func test_build_rows_name_the_building_rather_than_its_id() -> void:
	# `town_centre` on a controls screen is a database row, not an
	# instruction. The display name is what the rest of the HUD calls it.
	var bound := _client_constant("BUILD_KEYS")
	var text := ""
	for row in ControlsReference.rows():
		text += String(row[1]) + "\n"
	for key in bound:
		var def := BuildingSim.def_by_id(bound[key])
		if def == null:
			continue
		assert_true(text.contains(def.display_name),
			"the %s key should name the %s" % [key, def.display_name])
	assert_false(text.contains("town_centre"),
		"a controls screen must not show a def id")


func test_train_rows_name_an_archetype_not_one_civs_units() -> void:
	# Six civs share this screen (D-047). Naming a civ's unit would be
	# right for a sixth of the players and wrong for the rest.
	var text := ""
	for row in ControlsReference.rows():
		text += String(row[1]) + "\n"
	for civ_only in ["Hill Thralls", "Ember Bombard", "Barrow Shades", "Gatebreakers"]:
		assert_false(text.contains(civ_only),
			"the controls screen must not name one civ's units (%s)" % civ_only)


func test_the_dead_gather_shortcut_is_not_documented_as_working() -> void:
	# #302: `G` is in BUILD_KEYS and also has a hand-written gather branch
	# BELOW the build table, so the build wins and the gather shortcut is
	# unreachable. This screen says what pressing G actually does.
	#
	# A controls screen that documented the intent would turn that bug
	# into the player's fault — they would press G, get a garrison wall,
	# and conclude they had misread the screen.
	# Asserted on BOTH sides of #302, because the branch this test used to
	# take when the key moved was `pass_test("revisit this row")` — which
	# is a check that stops checking at exactly the moment the thing it
	# guards changes. #363 moved `garrison_wall` to `J` and `farm` to `O`,
	# so that moment has arrived, and the test has to survive it rather
	# than announce it.
	var bound := _client_constant("BUILD_KEYS")
	var gather := ControlsReference.gather_key()
	assert_ne(gather, "", "client.gd must still dispatch a gather key somewhere")

	var says := ""
	for row in ControlsReference.rows():
		if String(row[0]) == gather:
			says = String(row[1]).to_lower()

	if bound.has(gather):
		# The build table is consulted first, so the build wins and the
		# gather branch below it is unreachable. Say what pressing it
		# DOES: a screen documenting the intent would turn the bug into
		# the player's fault.
		assert_false(says.contains("gather"),
			("%s builds %s today, because BUILD_KEYS is checked before the "
			+ "gather branch (#302). Documenting it as gather is a lie.")
			% [gather, bound[gather]])
		assert_ne(says, "", "and it must still be listed as the build key it is")
	else:
		# #302 resolved: nothing steals the key, so gather is reachable
		# and a player must be told it exists.
		assert_true(says.contains("gather"),
			("%s is no longer stolen by BUILD_KEYS, so gather is reachable "
			+ "and belongs on the controls screen — found '%s'")
			% [gather, says])


# --- it fits on the screen --------------------------------------------

func test_the_controls_screen_fits_the_smallest_window_it_is_meant_to() -> void:
	# The guard the PICTURE had to stand in for. The first version dealt
	# groups two-per-column, which put "Building and training" — sixteen
	# rows, nine buildings and five units — in a column that had already
	# spent five on Orders. The last rows and the CLOSE BUTTON ran off the
	# bottom of a 720-high window, and nothing but looking would have said
	# so.
	#
	# Measured in a REAL tree, the same technique `test_lobby_layout.gd`
	# uses and for the same reason: theme fonts do not resolve off-tree,
	# so an off-tree measurement is a confident wrong answer.
	var client: Node3D = autofree(load("res://client.gd").new())
	client._build_controls_screen()
	var layer: CanvasLayer = client._controls_layer
	client.remove_child(layer)
	add_child_autofree(layer)
	layer.visible = true
	await get_tree().process_frame
	await get_tree().process_frame

	# The centred column holds everything: title, the two columns of
	# groups, and Close.
	var centre: Control = null
	for child in layer.get_children():
		if child is CenterContainer:
			centre = child
	assert_not_null(centre, "the screen must have a centred column")
	if centre == null:
		return
	var wanted: float = (centre.get_child(0) as Control).get_combined_minimum_size().y
	# HudLayout.REFERENCE is 1280x720, the smallest window this game lays
	# itself out against and the one `test-client` renders at.
	assert_lte(wanted, HudLayout.REFERENCE.y,
		("the controls screen wants %d px and the smallest window is %d — the last "
		+ "rows and the Close button would be off the bottom")
		% [int(wanted), int(HudLayout.REFERENCE.y)])
	gut.p("controls screen: %d px wanted against %d available" % [
		int(wanted), int(HudLayout.REFERENCE.y)])


# --- and both menus show it -------------------------------------------

func test_both_menus_reach_the_controls() -> void:
	# The caller-exists check (D-106's rule as a test), and here it is the
	# whole ticket: a controls list nothing displays is precisely the gap
	# being closed.
	var client := _read("res://client.gd")
	assert_true(client.contains("ControlsReference.groups()"),
		"client.gd must build the controls screen from the one list")
	assert_true(client.contains("_toggle_controls"),
		"and offer a way to open it")
	# Two entry points, because a player who has not connected yet cannot
	# reach the in-game menu, and one who is mid-match will not go back to
	# the main menu to read them.
	assert_true(client.contains("_build_main_menu") and client.contains("_build_game_menu"),
		"Setup: both menus exist")
	var controls_buttons := client.count("_styled_button(\"Controls\"")
	assert_eq(controls_buttons, 2,
		"both the main menu and the in-game menu must offer Controls, found %d"
		% controls_buttons)
