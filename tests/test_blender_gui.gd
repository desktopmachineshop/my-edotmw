extends GutTest

## Guards D-20260821-the-blender-gui-is-a-window-on-the-generators.
##
## The GUI exists so the owner can LOOK at a model from an angle they chose
## and scrub its animation. The risk it introduces is the one D-081 rejected
## outright: a second place assets can come from. `art/gui.py` builds the
## scene by calling the same generators `art/build.py` calls, and if it ever
## grows geometry of its own, `generated/` stops being reproducible from
## `art/` while every existing check stays green — the manifest hashes art/'s
## SOURCES, so a shape authored in a GUI session is invisible to it.
##
## These are text scans in the style of test_civs.gd's no-script-names-a-civ
## rule and test_multi_agent_isolation.gd's: the rule is only real if breaking
## it FAILS. They are deliberately cheap and need neither Blender nor the bpy
## wheel — the running check that the GUI script actually builds a scene is
## `art/gui.py --check`, which does need the wheel and therefore cannot live
## here (D-081: a clone that has never run bootstrap-art is a working game).

const GUI := "res://art/gui.py"
const PATH_SH := "res://blender-path.sh"


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## Strips docstrings and comments, so the prose ABOUT the rule cannot satisfy
## or violate the scan for the rule. `art/gui.py`'s header says the words
## "box()" and "prism()" while explaining that it must not call them, and a
## naive scan would read its own documentation as the offence.
func _code_only(source: String) -> String:
	var out := ""
	var in_doc := false
	for raw in source.split("\n"):
		var line: String = raw
		var fence := line.count("\"\"\"")
		if in_doc:
			if fence > 0:
				in_doc = false
			continue
		if fence == 1:
			in_doc = true
			continue
		if fence >= 2:
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out


# --- the GUI owns no geometry ------------------------------------------


func test_the_gui_builds_nothing_of_its_own() -> void:
	var code := _code_only(_read(GUI))

	# The strongest form of the rule: it cannot call the primitives because it
	# never BINDS the module that defines them.
	#
	# Matched as import statements, not as a bare mention: `art.lib.geom`
	# appears quoted in the GUI's RELOAD_ORDER, and it has to — reloading the
	# generators in dependency order is what makes "edit a primitive, press
	# Rebuild, see it" work, and `geom` must be first or `soldier` keeps the
	# old `box` bound and the edit is invisible. A name in a reload list is
	# not a call site.
	for form in ["import art.lib.geom", "geom import", "from .geom", "from ..lib.geom"]:
		assert_false(code.contains(form),
			("art/gui.py binds the primitives (`%s`) — it must assemble through "
			+ "the generators, never reach for geom itself (D-081)") % form)

	# And the calls themselves. Matched with a boundary rather than as a bare
	# substring: `UILayout.box()` is Blender's framed sub-layout and shares a
	# name with `geom.box()` by coincidence, so an un-anchored scan reports
	# the panel drawing code as an art defect.
	for primitive in ["box", "prism", "rotate_geometry"]:
		var call_re := RegEx.new()
		call_re.compile("(?<![.\\w])" + primitive + "\\s*\\(")
		var hit := call_re.search(code)
		assert_null(hit,
			("art/gui.py calls %s() — geometry must come from art/'s generators, "
			+ "or generated/ has a second source of truth (D-081)") % primitive)

	# A Part or Model constructed here is the same defect one level up: it
	# would be a model art/build.py cannot produce.
	for constructor in ["Model(", "Part("]:
		assert_false(code.contains(constructor),
			"art/gui.py constructs %s directly — it must assemble through the generators" % constructor)


func test_the_gui_writes_only_through_the_real_build() -> void:
	var code := _code_only(_read(GUI))

	# Baking is allowed, but ONLY by invoking art/build.py, which is what
	# enforces the triangle budgets, writes the manifest and re-imports.
	# Calling the writers directly would skip all three.
	for writer in ["write_glb(", "write_vat(", "write_prop_glb(", "write_atlas("]:
		assert_false(code.contains(writer),
			("art/gui.py calls %s directly — it must bake by calling art.build.main(), "
			+ "which is what applies the triangle budget and writes the manifest") % writer)

	assert_true(code.contains("art.build"),
		"art/gui.py's Bake operator must go through art/build.py")


func test_the_gui_shows_what_the_bake_bakes() -> void:
	var code := _code_only(_read(GUI))

	# `flatten` splits one vertex per triangle corner and its ORDER is the
	# contract between the mesh and the VAT column. A GUI that rebuilt that
	# from model.parts would be a second implementation of the contract, free
	# to drift — and the drift shows as a model that previews right and
	# animates wrong.
	assert_true(code.contains("flatten(model)"),
		"art/gui.py must build its mesh from bake.flatten, not from its own walk of model.parts")
	assert_true(code.contains("bake_frames("),
		"art/gui.py's timeline must come from bake_frames — the same frames the VAT stores")


func test_the_frame_handler_is_detached_before_the_process_ends() -> void:
	var code := _code_only(_read(GUI))

	# Measured on the bpy wheel at 4.5.12: a frame_change_post handler left
	# registered makes the interpreter hang FOREVER at shutdown. The same
	# script exits in 1 s without one. Everything has already printed by
	# then, so the symptom is a script that finishes its work and refuses to
	# end — which reads as a slow build, not as a leak.
	assert_true(code.contains("def detach("),
		"art/gui.py must offer detach(); see its docstring for the shutdown hang")
	assert_true(code.contains("detach()"),
		"art/gui.py's --check path must call detach() or the process never exits")


# --- one definition of where Blender is --------------------------------


func test_blender_path_is_the_one_definition() -> void:
	var script := _read(PATH_SH)
	assert_true(script.contains("EDOTMW_BLENDER"),
		"blender-path.sh must honour an explicit override, as instance-id.sh does")
	assert_true(script.contains(".blender-version"),
		"blender-path.sh must read the version pin rather than carrying its own")

	var justfile := _read("res://justfile")
	assert_true(justfile.contains("bash blender-path.sh find"),
		"the justfile must resolve Blender through blender-path.sh, not re-derive it")


func test_nothing_else_hardcodes_a_blender_binary_or_download() -> void:
	# The same shape as D-095's no-shared-literals rule. A second place that
	# knows where Blender lives is a second place that goes stale when the
	# pin moves, and blender-path.sh is the one that `just doctor` reports.
	var offenders: Array[String] = []
	for path in ["res://justfile", "res://bootstrap.ps1", "res://Dockerfile",
			"res://docker-compose.yml"]:
		if not FileAccess.file_exists(path):
			continue
		var text := _read(path)
		if text.contains("download.blender.org"):
			offenders.append(path + " (hardcodes the download URL)")
		if text.contains("Program Files/Blender") or text.contains("Blender.app"):
			offenders.append(path + " (hardcodes an install location)")
	assert_eq(offenders, [] as Array[String],
		"only blender-path.sh may know where Blender comes from: %s" % [offenders])


func test_the_version_pin_is_shared_by_the_wheel_and_the_application() -> void:
	# They are two different programs and must be one version: the mesh API,
	# the glTF exporter and the EXR writer all move between releases, so a
	# model shaped in one and baked by the other is only accidentally the
	# same model.
	assert_true(FileAccess.file_exists("res://.blender-version"),
		".blender-version must exist — it is the one pin for both")
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("blender_version := `cat .blender-version`"),
		"the justfile's Blender version must come from the pin file")
	assert_true(justfile.contains("bpy=={{blender_version}}"),
		"bootstrap-art must install the PINNED wheel")
	assert_true(justfile.contains("blender-{{blender_version}}"),
		"bootstrap-blender-gui must unpack the PINNED application")


# --- the recipe -------------------------------------------------------


func test_the_gui_recipe_starts_from_factory_settings() -> void:
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("--factory-startup"),
		("just blender-gui must launch with --factory-startup: a personal add-on "
		+ "that changes colour space or unit scale would make the GUI disagree "
		+ "with the bake for reasons nothing in this repo can see"))
	assert_true(justfile.contains("--python art/gui.py"),
		"just blender-gui must run art/gui.py")


func test_the_gui_is_gated_but_not_exclusive() -> void:
	var justfile := _read("res://justfile")
	var at := justfile.find("blender-gui TARGET=")
	assert_true(at > 0, "the blender-gui recipe must exist")
	if at <= 0:
		return
	var body := justfile.substr(at, 2200)

	# Gated: it is ~1.3 GB on a laptop that rarely has 2.4 GB free
	# (D-20260818-dev-work-is-admitted-against-a-host-budget).
	assert_true(body.contains("host-gate.sh acquire medium 'blender-gui'"),
		"just blender-gui must be admitted against the host budget")

	# NOT exclusive. `gpu` is exclusive machine-wide because two simultaneous
	# render MEASUREMENTS on one integrated GPU are two useless measurements.
	# This measures nothing, and holding the slot would stop the owner
	# comparing a model against the running game — or let another agent's
	# bench-render lock them out of looking at art at all.
	assert_false(body.contains("acquire gpu 'blender-gui'"),
		"just blender-gui must not take the exclusive gpu slot; it measures nothing")


func test_the_gate_release_does_not_replace_a_teardown_trap() -> void:
	# A bash `trap ... EXIT` REPLACES, it does not append — the defect
	# test_host_budget.gd was written for. blender-gui launches no
	# containers, so its single EXIT trap must be the gate release and
	# nothing else; more than one would mean one of them never runs.
	var justfile := _read("res://justfile")
	var at := justfile.find("blender-gui TARGET=")
	if at <= 0:
		return
	var body := justfile.substr(at, 2200)
	var end := body.find("bootstrap-blender-gui")
	if end > 0:
		body = body.substr(0, end)
	assert_eq(body.count("trap "), 1,
		"blender-gui must have exactly one EXIT trap (the gate release) — a second one replaces the first")
