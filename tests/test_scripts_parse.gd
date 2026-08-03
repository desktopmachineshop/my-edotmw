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


func test_every_script_in_the_project_root_compiles() -> void:
	var dir := DirAccess.open("res://")
	assert_not_null(dir, "res:// is unreadable")

	var checked := 0
	for file_name in dir.get_files():
		var name := String(file_name).trim_suffix(".remap")
		if not name.ends_with(".gd"):
			continue
		var script = load("res://%s" % name)
		assert_not_null(script, ("%s failed to parse — the whole file is dead, "
			+ "and nothing else in this suite would have noticed") % name)
		checked += 1

	# Guard against the guard passing vacuously: if the directory walk
	# ever stops finding scripts, this test would report success while
	# checking nothing at all.
	assert_gt(checked, 15,
		"only %d scripts were checked — the scan is not finding the project" % checked)
