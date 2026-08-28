class_name ControlsReference
extends RefCounted

## THE list of what the controls do (#282, D-094 criterion 10).
##
## A stranger who installs the alpha meets a lobby, then a map, and until
## this existed **nothing anywhere told them that WASD pans or that
## right-click orders**. D-094's criterion 10 — a human playing end to
## end through an installed build — cannot be discharged honestly against
## a game whose controls are undocumented, which is why the gap
## assessment filed it as a blocker rather than as polish.
##
## All-static and pure, the D-061 split, and this one has a second reason
## beyond testability: the **main menu** and the **in-game menu** both
## show it, and two hand-written lists of the same bindings is a pair that
## comes to disagree. There is one list.
##
## ## Two rules for editing this file
##
## **Document what the code DOES, not what it should do.** Writing this
## required enumerating every binding, which is how #302 was found — `G`
## is in `BUILD_KEYS` *and* has a hand-written gather branch below it, so
## the build table wins and the gather shortcut is unreachable. This file
## says `G` builds a garrison wall, because that is what pressing it
## does. A controls screen that documents the intent rather than the
## behaviour is worse than none: it turns a bug into the player's fault.
##
## **The build and train rows are DERIVED**, from `client.gd`'s own
## `BUILD_KEYS` and `TRAIN_KEYS` tables, so a letter that moves cannot
## leave this screen behind. They are the two groups where drift was
## certain — nine buildings and five units, edited whenever the roster
## moves.


## One group of bindings: a heading and a list of `[keys, what it does]`.
## Ordered as a player meets them — look around, choose things, order
## them about, then the specialised verbs.
##
## Everything here is bound in `client.gd`'s `_handle_key`,
## `_unhandled_input` or `_pan_camera`; nothing is aspirational.
static func groups() -> Array:
	return [
		{
			"title": "Camera",
			"rows": [
				["W A S D", "Pan, relative to the way the camera faces"],
				["Q / E", "Turn the view (the compass snaps back to north)"],
				["Ctrl + wheel", "Turn the view"],
				["Mouse wheel", "Zoom in and out"],
			],
		},
		{
			"title": "Selecting",
			"rows": [
				["Left-click", "Select a squad or building"],
				["Left-drag", "Box-select"],
				["Shift + click", "Add to the selection"],
				["Ctrl + 1…9", "Store the selection as a group"],
				["1…9", "Recall that group"],
			],
		},
		{
			"title": "Orders",
			"rows": [
				["Right-click", "Move there — or attack what is there"],
				["Right-drag", "Form a battle line along the stroke: position, facing and width in one motion"],
				["Ctrl + right-drag", "The same, as an attack-move"],
				["Alt + right-click", "Face the selection at that point without moving it"],
				["X", "Stop"],
			],
		},
		{
			"title": "Building and training",
			"rows": _build_rows() + _train_rows() + [
				["V", "While placing a building, turn it to the next of six sides"],
				["Escape", "Cancel a placement — or open the menu when there is none"],
			],
		},
	]


## Every binding as one flat list, for a test that wants to check them
## all without knowing the grouping.
static func rows() -> Array:
	var out := []
	for group in groups():
		out.append_array(group["rows"])
	return out


## The build keys, read from the client's own table so a letter that
## moves cannot leave this screen behind.
##
## Sorted by the KEY, because a player scanning for a letter is scanning
## alphabetically, and because dictionary order in GDScript is insertion
## order — which would make this screen's rows depend on the order
## somebody happened to add buildings in.
static func _build_rows() -> Array:
	return _rows_from(_key_table("BUILD_KEYS"), func(id: StringName) -> String:
		var def := BuildingSim.def_by_id(id)
		return "Build %s" % (def.display_name if def != null else String(id)))


static func _train_rows() -> Array:
	return _rows_from(_key_table("TRAIN_KEYS"), func(id: StringName) -> String:
		# An ARCHETYPE, not a def: which troops that is depends on the
		# civ (D-047), and a controls screen shared by six civs must not
		# name one civ's units.
		return "Train %s" % String(id).capitalize().to_lower())


static func _rows_from(table: Dictionary, describe: Callable) -> Array:
	var keys := table.keys()
	keys.sort()
	var out := []
	for key in keys:
		out.append([String(key), String(describe.call(table[key]))])
	return out


## One of `client.gd`'s key tables, read off the script rather than
## copied. Empty if the constant is ever renamed — which shows up as a
## controls screen missing its build rows, and is caught by
## `tests/test_controls_reference.gd` rather than by a player.
static func _key_table(name: String) -> Dictionary:
	var script := load("res://client.gd") as GDScript
	if script == null:
		return {}
	var constants := script.get_script_constant_map()
	if not constants.has(name):
		return {}
	return constants[name]
