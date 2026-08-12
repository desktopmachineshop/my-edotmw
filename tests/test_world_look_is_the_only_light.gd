extends GutTest

## Guards D-080: `world_look.gd` is the one definition of the client's
## lighting rig.
##
## Before D-080, `client.gd`, `bench_render.gd` and `model_preview.gd` each
## built their own `DirectionalLight3D` and `Environment` inline —
## `bench_render.gd` an exact copy, `model_preview.gd` a near-copy kept in
## sync by hand. That is how the shipping rig and the benchmark rig drift
## apart, which `bench_render.gd`'s own header calls out: "a benchmark
## camera that is merely similar measures a similar game." The same is
## true of the light.
##
## Modelled on test_civs.gd's `test_no_script_mentions_a_civ_id` and
## test_formations_are_data.gd, for the same reason those exist: the rule
## is only real if breaking it fails, so this scans source text rather
## than trusting the convention to hold on its own.


## Files allowed to construct a `DirectionalLight3D` or `Environment`
## directly. `world_look.gd` is the implementation; tests assert things
## about the data, which sometimes means constructing it.
const EXEMPT_PREFIXES := ["res://tests/", "res://addons/"]
const EXEMPT_FILES := ["res://world_look.gd"]


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


func test_no_script_outside_world_look_builds_the_lighting_rig() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10, "Found almost no scripts — the walk is broken, not the code clean")

	# Word-boundary regexes so "WorldEnvironment.new(" — a distinct node
	# type this file's callers still construct themselves — does not
	# false-positive as "Environment.new(".
	var light_re := RegEx.new()
	light_re.compile("\\bDirectionalLight3D\\.new\\(")
	var env_re := RegEx.new()
	env_re.compile("\\bEnvironment\\.new\\(")

	var offences: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str in EXEMPT_FILES:
			continue
		var exempt := false
		for prefix in EXEMPT_PREFIXES:
			if path_str.begins_with(prefix):
				exempt = true
				break
		if exempt:
			continue

		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()

		if light_re.search(text) != null:
			offences.append("%s constructs DirectionalLight3D directly — use WorldLook.make_sun()" % path_str)
		if env_re.search(text) != null:
			offences.append("%s constructs Environment directly — use WorldLook.make_environment()" % path_str)

	assert_eq(offences, [],
		"Only world_look.gd may define what the lighting rig looks like")
