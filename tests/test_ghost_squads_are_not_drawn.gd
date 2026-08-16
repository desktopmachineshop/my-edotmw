extends GutTest

## Guards D-099: a concealed squad is not drawn, and the ghost-render path
## that used to draw it is gone.
##
## Two halves, because the rule has two failure modes and they are opposite.
##
## 1. **The dead path stays dead.** D-026 criterion 11's visual half asked for
##    a squad ghost to be drawn faded; D-099 supersedes that with "not drawn at
##    all". Everything behind the fade — `PrimitiveUnit.set_ghost`, the
##    StandardMaterial3D alpha branch, `unit_anim_ghost.gdshader` — was
##    unreachable for two milestones with nothing failing, which is this
##    project's one structurally invisible defect class (see CLAUDE.md on
##    declared-and-unread members). It is deleted; this scan is what keeps it
##    from drifting back in without a decision.
##
## 2. **The hiding is still there.** A ghost is not skipped by omission: its
##    node holds whatever transforms the live pass last gave it, so leaving it
##    untouched renders a frozen, fully opaque squad — "drawn as though it were
##    live", the state D-026 criterion 11 was written to rule out, reached by a
##    different route. Both draw paths (the 3D view and the minimap) must
##    actively skip it.
##
## Source text rather than behaviour, for the same reason
## test_world_look_is_the_only_light.gd and test_civs.gd's
## `test_no_script_mentions_a_civ_id` are: `client.gd` needs a GPU and a live
## server (D-014), so the rule is only real here if reading the file can break
## it.

const CLIENT := "res://client.gd"
const GHOST_SHADER := "res://shaders/unit_anim_ghost.gdshader"

## Tests construct what they assert about; addons are vendored.
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


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## The CODE of `func <name>(`, up to the next top-level `func`, with comment
## lines dropped. Coarse on purpose: it should survive anything moving inside
## the function and break only when the guard leaves it.
##
## Comments are stripped because the first draft of this test did not, and the
## perturbation run caught it — the ghost pass's own comment names
## `ghost_squad_ids()`, so deleting the loop underneath it left the check
## green. A test that a comment can satisfy is exactly the vacuous check
## D-022's audit rule exists to prevent.
func _function_code(text: String, name: String) -> String:
	var start := text.find("func %s(" % name)
	if start < 0:
		return ""
	var end := text.find("\nfunc ", start + 1)
	var body := text.substr(start, -1 if end < 0 else end - start)

	var code := ""
	for line in body.split("\n"):
		if String(line).strip_edges().begins_with("#"):
			continue
		code += String(line) + "\n"
	return code


func test_no_script_carries_the_squad_ghost_render_path() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10,
		"Found almost no scripts — the walk is broken, not the code clean")

	var patterns := {
		"set_ghost(": "the ghost material toggle",
		"_set_ghost_look": "the client's ghost styling call",
		"unit_anim_ghost": "the transparent VAT shader variant",
	}

	var offences: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		var exempt := false
		for prefix in EXEMPT_PREFIXES:
			if path_str.begins_with(prefix):
				exempt = true
				break
		if exempt:
			continue

		var text := _read(path_str)
		for needle in patterns:
			if text.contains(String(needle)):
				offences.append("%s still carries %s ('%s')" % [
					path_str, patterns[needle], needle])

	assert_eq(offences, [],
		"A concealed squad is not drawn (D-099), so nothing may style one")
	assert_false(FileAccess.file_exists(GHOST_SHADER),
		"%s draws a squad D-099 says is not drawn" % GHOST_SHADER)


func test_the_three_d_pass_hides_a_concealed_squad() -> void:
	var code := _function_code(_read(CLIENT), "_refresh_squads")
	assert_ne(code, "", "client.gd has no _refresh_squads — this test is stale")
	var pass_index := code.find("ghost_squad_ids()")
	assert_gt(pass_index, -1,
		"_refresh_squads must visit the ghosts to hide them (D-099); leaving "
		+ "one untouched draws it frozen and opaque, not gone")
	if pass_index < 0:
		return
	assert_true(code.substr(pass_index).contains("visible = false"),
		"_refresh_squads must set a ghost's node invisible (D-099)")


func test_the_minimap_skips_a_concealed_squad() -> void:
	var code := _function_code(_read(CLIENT), "_update_minimap")
	assert_ne(code, "", "client.gd has no _update_minimap — this test is stale")
	assert_true(code.contains("is_ghost("),
		"the minimap must ask whether a squad is a ghost before plotting it "
		+ "(D-099) — the 3D view and the minimap agree or fog leaks on one")
