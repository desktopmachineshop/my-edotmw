extends GutTest

## Every shipped script must actually COMPILE.
##
## This exists because `just test-unit` was green at 360 tests while
## `client.gd` had a parse error and the game window rendered a grey box.
## Twice in one session. The suite tests simulation classes — TorusSpace,
## SquadSim, Combat, Formation — and never loads the client, because the
## client needs a GPU and cannot be exercised headless (D-014).
##
## But "cannot be RUN headless" is not "cannot be PARSED headless", and
## the distinction is the whole bug: a parse error is exactly the class of
## fault that a GUI-only file will hide until someone launches it by hand.
## `test-client` does catch it, but it takes minutes and needs Docker,
## which makes it the wrong place for a mistake that costs a second to
## find.
##
## Godot's `load()` returns null for a script that failed to parse, which
## is all this needs.


func _compiles_in(directory: String, floor_count: int) -> void:
	var dir := DirAccess.open(directory)
	assert_not_null(dir, "%s is unreadable" % directory)
	if dir == null:
		return

	var checked := 0
	for file_name in dir.get_files():
		var name := String(file_name).trim_suffix(".remap")
		if not name.ends_with(".gd"):
			continue
		var script = load("%s/%s" % [directory, name])
		assert_not_null(script, ("%s failed to parse — the whole file is dead, "
			+ "and nothing else in this suite would have noticed") % name)

		# `load()` is not enough on its own. It returns null for a SYNTAX
		# error but a perfectly good object for a script that parsed and
		# then failed to COMPILE — an unresolved identifier, a call to a
		# method that does not exist, a const that became a function and
		# left a dangling reference. Those are the ones that actually
		# happen, and `can_instantiate()` is what tells them apart.
		#
		# Found by perturbing this guard and watching it pass while 26
		# tests silently disappeared.
		if script != null:
			assert_true(script.can_instantiate(),
				("%s parsed but does not compile — GUT will skip it silently "
				+ "and the suite will report success with its assertions gone") % name)
		checked += 1

	# Guard against the guard passing vacuously: if the directory walk
	# ever stops finding scripts, this test would report success while
	# checking nothing at all.
	assert_gt(checked, floor_count,
		"only %d scripts checked in %s — the scan is not finding them" % [checked, directory])


func test_every_script_in_the_project_root_compiles() -> void:
	_compiles_in("res:/" + "/", 15)


func test_every_test_script_compiles() -> void:
	# The tests themselves, because GUT SILENTLY SKIPS a test file it
	# cannot parse. That is worse than the production case this guard was
	# written for: a broken script under /tests does not fail the suite, it
	# quietly removes its own assertions and the total drops.
	#
	# It happened twice — once when `ReplayLog.read_all` did not exist and
	# the count went 337 -> 325, and again here when a const became a
	# function and left a dangling reference, taking it 372 -> 364. Both
	# times the suite reported "all tests passed".
	_compiles_in("res://tests", 15)
