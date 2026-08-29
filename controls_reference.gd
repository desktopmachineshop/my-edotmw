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
		# FIRST, and one row, and it stays first as it grows.
		#
		# Adding it LAST is where it went initially, and the controls
		# screen's own fit test went red at 731 px against a 720-high
		# window — the fifth group landed in the column that had already
		# spent sixteen rows on buildings and units. That is precisely the
		# revisit trigger `D-20260828-the-controls-are-written-down-once`
		# named, firing on the very next change, which is what a measured
		# guard is for.
		#
		# It also reads better here: somebody opening this screen because
		# they are lost should be told there is a manual before being
		# handed thirty keys.
		{
			"title": "Reference",
			"rows": [
				[manual_key(), "Open the manual"],
			],
		},
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
			"rows": _build_rows() + _train_rows() + _gather_row() + [
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


## The GATHER key, listed only when a player can actually press it.
##
## `client.gd` has a hand-written `KEY_G` branch that sends idle workers
## at the node under the cursor — and that branch was UNREACHABLE, because
## `G` was also in `BUILD_KEYS` and the build table is consulted first
## (#302, found by writing this file). The screen therefore documented `G`
## as a garrison wall: it says what pressing a key DOES, and a screen
## documenting the intent would have made that bug the player's fault.
##
## #302 is resolved now — `garrison_wall` moved to `J` and `farm` took `O`
## (#363) — so `G` gathers. Rather than swap one hard-coded answer for
## another, the row is DERIVED FROM THE COLLISION ITSELF: if the gather
## key is in `BUILD_KEYS` the build table wins and there is nothing to
## list; if it is not, gather is reachable and gets a row.
##
## That is what makes this correct on both sides of the fix, on a branch
## that has #363's re-allocation and on one that does not — and it is why
## #363 needed no other edit here, the build rows being derived already.
static func _gather_row() -> Array:
	var key := gather_key()
	if key == "" or _key_table("BUILD_KEYS").has(key):
		return []
	return [[key, "Gather: send idle workers to the node under the cursor"]]


## The gather key, read off `client.gd` rather than guessed.
##
## Prefers a named constant if the client grows one, and otherwise reads
## the letter out of the branch it is actually dispatched from — so this
## reports the key that WORKS rather than the key somebody meant.
static func gather_key() -> String:
	var script := load("res://client.gd") as GDScript
	if script == null:
		return ""
	var constants := script.get_script_constant_map()
	if constants.has("GATHER_KEY"):
		return String(constants["GATHER_KEY"])
	var source := script.source_code
	var marker := "if event.keycode == KEY_"
	var at := source.find(marker)
	while at >= 0:
		var letter := source.substr(at + marker.length(), 1)
		var rest := source.substr(at, 220)
		if rest.contains("_gather_selected()"):
			return letter
		at = source.find(marker, at + 1)
	return ""


static func _rows_from(table: Dictionary, describe: Callable) -> Array:
	var keys := table.keys()
	keys.sort()
	var out := []
	for key in keys:
		out.append([String(key), String(describe.call(table[key]))])
	return out


## The manual's key, read off `client.gd`'s own constant (#305) — the
## same discipline as the build and train rows below, for the same
## reason: a screen that told a player the wrong key is worse than no
## screen. Empty if the constant is renamed, which the tests catch.
static func manual_key() -> String:
	var script := load("res://client.gd") as GDScript
	if script == null:
		return ""
	return String(script.get_script_constant_map().get("MANUAL_KEY", ""))


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
