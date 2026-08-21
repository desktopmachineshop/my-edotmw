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


## One recipe body, from its header line to the next recipe's attribute.
func _recipe_body(header: String) -> String:
	var justfile := _read("res://justfile")
	var at := justfile.find(header)
	assert_true(at > 0, "the recipe %s must exist" % header)
	if at <= 0:
		return ""
	var rest := justfile.substr(at)
	var end := rest.find("\n[doc(")
	return rest.substr(0, end) if end > 0 else rest


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


func test_the_wheel_is_pinned_and_the_application_is_only_checked() -> void:
	# The WHEEL is pinned because it bakes generated/ and D-081 requires two
	# runs to be byte-identical. The APPLICATION is an ordinary desktop
	# install the owner manages, so its version is compared and warned about,
	# never enforced — the mesh API and glTF exporter do move between
	# releases, but that is a reason to bake with the wheel, not a reason to
	# refuse to open a model in the Blender someone happens to have.
	assert_true(FileAccess.file_exists("res://.blender-version"),
		".blender-version must exist — it is the wheel pin")
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("blender_version := `cat .blender-version`"),
		"the justfile's Blender version must come from the pin file")
	assert_true(justfile.contains("bpy=={{blender_version}}"),
		"bootstrap-art must install the PINNED wheel")

	var script := _read(PATH_SH)
	assert_true(script.contains("NOTE:"),
		"blender-path.sh must NOTE a version difference rather than refusing it")


# --- the recipe -------------------------------------------------------


func test_the_gui_opens_the_owners_own_blender() -> void:
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("--python art/gui.py"),
		"just blender-gui must run art/gui.py")

	# An earlier version passed --factory-startup to keep the session pristine.
	# That is isolation a standard desktop tool does not want: it throws away
	# the owner's preferences, add-ons and keymap every launch, and the thing
	# it protected — the bake — does not run here unless the button is pressed.
	#
	# Anchored to the LAUNCH LINE, not the whole file: the recipe's own comment
	# explains why the flag was dropped, and a file-wide scan reads that
	# explanation as the offence. Same trap as `UILayout.box()` above.
	var launch := ""
	for line in justfile.split("\n"):
		if line.contains("--python art/gui.py") and not line.strip_edges().begins_with("#"):
			launch = line
	assert_ne(launch, "", "the blender-gui recipe must have a launch line")
	assert_false(launch.contains("--factory-startup"),
		("just blender-gui must open the owner's OWN Blender, preferences and "
		+ "add-ons included; --factory-startup is isolation a desktop tool "
		+ "does not want. Launch line: %s") % launch)


func test_the_gui_is_not_host_gated() -> void:
	# Every other heavy recipe is admitted against the machine budget
	# (D-20260818) because it is AGENT work competing with other agents.
	# This one is the owner opening their own modelling application, which
	# they can equally launch from the desktop with no queue — so a gate
	# here protects nothing and only puts a wait in front of a double-click.
	#
	# test_host_budget.gd agrees by construction: its rule fires on a body
	# that starts docker or Godot, and this starts neither.
	var body := _recipe_body("blender-gui TARGET=")
	assert_false(body.contains("host-gate.sh acquire"),
		"just blender-gui must not be host-gated; it is a desktop tool, not agent work")


func test_the_repo_does_not_install_or_manage_blender() -> void:
	# The owner's call, and the reason is theirs: models are rebuilt rarely,
	# and a standard desktop tool does not want a repo-pinned private copy of
	# itself. blender-path.sh FINDS an ordinary install; nothing fetches one.
	var justfile := _read("res://justfile")
	assert_false(justfile.contains("bootstrap-blender-gui"),
		"the Blender-download recipe was removed deliberately; do not reintroduce it")

	var body := _recipe_body("blender-gui TARGET=")
	for fetcher in ["curl", "wget", "Invoke-WebRequest", "unzip", "tar -x"]:
		assert_false(body.contains(fetcher),
			"just blender-gui must not fetch or unpack anything (%s)" % fetcher)

	var script := _read(PATH_SH)
	assert_false(script.contains("download.blender.org"),
		("blender-path.sh must not carry a download URL — it finds an installed "
		+ "Blender and, when there is none, says how to install one normally"))
	assert_true(script.contains("install-hint"),
		"blender-path.sh must tell the owner how to install Blender when none is found")
