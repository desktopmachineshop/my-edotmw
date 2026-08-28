extends GutTest

## Guards that no keyboard letter is claimed twice (#302).
##
## `client.gd` resolves a keypress in a fixed order: a few hand-written
## `event.keycode == KEY_x` branches, then `BUILD_KEYS`, then
## `TRAIN_KEYS`, then a few more hand-written branches. Whichever comes
## first wins, silently.
##
## `G` was claimed by BOTH `BUILD_KEYS["G"] = garrison_wall` and the
## hand-written gather branch below the tables, so **gather was
## unreachable from the keyboard** — and the file had predicted exactly
## that in two separate comments:
##
##   "a letter added to BUILD_KEYS or TRAIN_KEYS silently steals it from
##    here"
##   "L/K/G/F/U avoid WASD, Q/E and every existing BUILD_KEYS/TRAIN_KEYS
##    letter"
##
## The second comment checked the new letters against the two TABLES and
## not against the hand-written branches, so `G` passed the check it was
## measured against and collided with the one nobody enumerated. This is
## why the fix is a test rather than a third comment: the ordering has now
## been reasoned about in prose twice and got it wrong both times.
##
## It is also D-061's harder variant — `_gather_selected()` has a caller
## in the orders column, so a grep for uncalled members finds nothing.
## The rule is fully written and the caller is unreachable.

const CLIENT := "res://client.gd"


func _constants() -> Dictionary:
	var script: GDScript = load(CLIENT)
	assert_not_null(script, "client.gd must load")
	return script.get_script_constant_map()


func _source() -> String:
	var handle := FileAccess.open(CLIENT, FileAccess.READ)
	assert_not_null(handle, "client.gd must be readable")
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func test_no_letter_is_claimed_twice() -> void:
	# THE check. Every claim on a letter, from all three sources, in one
	# place — which is the thing that did not exist and is why `G` could be
	# taken twice with two comments arguing it could not.
	var consts := _constants()
	var claims := {}
	var clashes := []

	for source in ["BUILD_KEYS", "TRAIN_KEYS", "RESERVED_KEYS"]:
		assert_true(consts.has(source), "client.gd must declare %s" % source)
		if not consts.has(source):
			continue
		for key in consts[source]:
			var letter := String(key)
			if claims.has(letter):
				clashes.append("%s claimed by %s AND %s (%s wins — it is consulted first)"
					% [letter, claims[letter], source, claims[letter]])
			else:
				claims[letter] = source

	assert_eq(clashes.size(), 0,
		"a letter claimed twice makes the later claim UNREACHABLE: %s" % str(clashes))


func test_gather_has_a_key_a_player_can_actually_press() -> void:
	# The specific defect, asserted as an outcome rather than as an
	# arrangement: whatever letter gather ends up on, pressing it must not
	# be intercepted by the build or train tables first.
	var consts := _constants()
	var reserved: Dictionary = consts.get("RESERVED_KEYS", {})
	var gather_letter := ""
	for key in reserved:
		if String(reserved[key]).contains("gather"):
			gather_letter = String(key)
	assert_ne(gather_letter, "", "some reserved key must be gather's")
	assert_false(Dictionary(consts.get("BUILD_KEYS", {})).has(gather_letter),
		"the build table consulted first must not own gather's letter (%s)" % gather_letter)
	assert_false(Dictionary(consts.get("TRAIN_KEYS", {})).has(gather_letter),
		"nor the train table (%s)" % gather_letter)


func test_every_hand_written_key_branch_is_declared() -> void:
	# The half that keeps this honest as the file grows. A new
	# `event.keycode == KEY_J` branch added below the tables would collide
	# silently again, and the check above cannot see it unless the letter
	# is DECLARED. So: every hand-written single-letter branch in
	# `_handle_key` must appear in RESERVED_KEYS.
	#
	# Restricted to single LETTERS on purpose — KEY_ESCAPE, KEY_0..KEY_9
	# and modifier combinations are not letters and cannot collide with a
	# table keyed by `OS.get_keycode_string`.
	var source := _source()
	var start := source.find("func _handle_key")
	assert_true(start >= 0, "setup: _handle_key must exist to scan")
	if start < 0:
		return
	var end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, (end - start) if end > start else -1)

	var re := RegEx.new()
	re.compile("keycode == KEY_([A-Z])\\b")
	var reserved: Dictionary = _constants().get("RESERVED_KEYS", {})
	var undeclared := []
	for hit in re.search_all(body):
		var letter := hit.get_string(1)
		if not reserved.has(letter):
			undeclared.append(letter)

	assert_eq(undeclared.size(), 0,
		"these keys are handled in _handle_key but not declared in RESERVED_KEYS, "
		+ "so nothing can notice a table stealing them: %s" % str(undeclared))


func test_the_wall_family_still_has_its_keys() -> void:
	# #302's fix moves a letter, and a fix that quietly dropped a binding
	# would pass every check above. D-076's five wall pieces must each keep
	# a key of their own.
	var build: Dictionary = _constants().get("BUILD_KEYS", {})
	var bound := {}
	for key in build:
		bound[String(build[key])] = String(key)
	for piece in ["wall", "gate", "garrison_wall", "garrison_gate", "wall_tower"]:
		assert_true(bound.has(piece), "D-076's %s must still be on a key" % piece)
