extends GutTest

## Guards #178 / D-094 criterion 1 and
## `decisions/D-20260827-the-build-is-exported-from-one-version.md`:
## `just export` produces the shipping builds from COMMITTED presets, and
## the build version is written down in exactly one place.
##
## Most of this is text scanning, in the style of test_civs.gd's
## no-script-names-a-civ rule and test_multi_agent_isolation.gd's
## no-shared-literals rule, and for the same reason: an export preset and
## a recipe that names it are two files that must agree, with nothing but
## a failed build to say so when they stop. A failed build is a slow
## check and it only fails on the machine that runs it — which, for a
## release step, is by definition not the one that broke it.
##
## The half that is NOT scanning is the version: `BuildVersion.string()`
## is called for real here, against the real project setting, because the
## defect this whole file exists to prevent is a runtime reader and a
## build-time reader disagreeing about which build this is.

const PRESETS := "res://export_presets.cfg"


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


# --- the one version ---------------------------------------------------

func test_the_version_is_declared_once_and_read_from_there() -> void:
	var declared := str(ProjectSettings.get_setting(BuildVersion.SETTING, ""))
	assert_false(declared.is_empty(),
		"project.godot must declare %s — it is THE build version" % BuildVersion.SETTING)
	assert_eq(BuildVersion.string(), declared,
		"BuildVersion must report the project setting, not a copy of it")


func test_the_banner_names_who_is_speaking_and_which_build() -> void:
	var line := BuildVersion.banner("server")
	assert_true(line.begins_with("server: "),
		"the banner must carry the same prefix the rest of that binary's log does: %s" % line)
	assert_true(line.contains(BuildVersion.string()),
		"the banner must contain the version: %s" % line)


func test_a_missing_version_is_said_out_loud_rather_than_left_blank() -> void:
	# A blank version compares EQUAL to another blank version, which is
	# the one answer a version must never give — #179's handshake reports
	# both builds in its refusal, and "your build is , the server is "
	# is the shape of a message nobody can act on.
	assert_false(BuildVersion.string().is_empty(),
		"BuildVersion.string() must never return empty")


func test_no_other_script_writes_a_version_of_its_own() -> void:
	# The D-046-criterion-3 pattern. build_version.gd is the only file
	# allowed to name the setting; anything else naming it is a second
	# reader that can be pointed somewhere else later.
	var offenders := PackedStringArray()
	for path in _project_scripts():
		if path == "res://build_version.gd":
			continue
		if _read(path).contains(BuildVersion.SETTING):
			offenders.append(path)
	assert_eq(offenders, PackedStringArray(),
		"only build_version.gd may name %s; these also do: %s"
		% [BuildVersion.SETTING, ", ".join(offenders)])


func test_the_justfile_reads_the_version_out_of_the_same_file() -> void:
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("build_version := `grep -m1 '^config/version=' project.godot"),
		"the export recipe's version must be read out of project.godot, not typed into the justfile")


# --- the presets and the recipe that names them ------------------------

func test_the_presets_are_committed() -> void:
	assert_true(FileAccess.file_exists(PRESETS),
		"export_presets.cfg must be committed — 'from a clean clone' is the criterion (D-094 #1)")


func test_every_preset_the_recipe_exports_exists_in_the_presets_file() -> void:
	var cfg := _read(PRESETS)
	var justfile := _read("res://justfile")
	for preset in ["Windows Client", "Windows Server", "Linux Server"]:
		assert_true(cfg.contains('name="%s"' % preset),
			"export_presets.cfg has no preset named '%s'" % preset)
		assert_true(justfile.contains('do_export "%s"' % preset),
			"the export recipe does not export '%s'" % preset)


func test_the_recipe_exports_release_builds_only() -> void:
	# Comment lines are stripped first, because this recipe's own comment
	# says the words "--export-debug" while explaining why it does not do
	# that — a scan that read them would fail the very thing it guards.
	var recipe := _uncommented(_recipe_body("export TARGET="))
	assert_true(recipe.contains("--export-release"),
		"the export recipe must produce release builds")
	assert_false(recipe.contains("--export-debug"),
		"a debug export carries the debug template — it is not the build that was tested")


func test_the_export_recipe_imports_first() -> void:
	# CLAUDE.md's standing rule, and the one run-client had to learn the
	# hard way: anything running Godot against this project resolves
	# global class_names out of the import cache, and an export resolves
	# every one of them.
	var recipe := _recipe_body("export TARGET=")
	assert_true(recipe.contains("--path . --import"),
		"the export recipe must import before it exports")


func test_the_templates_are_pinned_to_the_engine() -> void:
	var justfile := _read("res://justfile")
	assert_true(justfile.contains('export_templates_dir := tools_dir + "/editor_data/export_templates/" + godot_version'),
		"export templates must be resolved from .godot-version, never from a version typed into a recipe")
	var pinned := _read("res://.godot-version").strip_edges()
	var recipe := _recipe_body("bootstrap-export-templates:")
	assert_false(recipe.contains(pinned),
		"the templates recipe must not hardcode the engine version (%s) — it comes from .godot-version" % pinned)


func test_the_templates_live_under_tools_so_nuke_is_complete() -> void:
	# bootstrap.ps1 promises a fresh clone installs nothing system-wide
	# and `just nuke` promises to leave pure source. 1.3 GB of export
	# templates in %APPDATA% would quietly break both.
	var justfile := _read("res://justfile")
	assert_true(justfile.contains('tools_dir + "/editor_data/export_templates/'),
		"export templates must live under tools/")
	assert_true(_recipe_body("bootstrap-export-templates:").contains('"{{tools_dir}}/_sc_"'),
		"self-contained mode is what puts them there — the marker must be written")


func test_builds_are_not_committed() -> void:
	var ignored := _read("res://.gitignore")
	assert_true(ignored.contains("build/"),
		".gitignore must cover build/ — a build is derivable from its source")


# --- the two binaries, and which scene each one starts in --------------

func test_both_binaries_print_the_version_at_start() -> void:
	# The caller-exists check (D-106's rule as a test). BuildVersion can
	# be perfectly correct and printed by nobody, which is this project's
	# most-repeated defect.
	for path in ["res://server.gd", "res://client.gd", "res://bot_client.gd"]:
		assert_true(_read(path).contains("BuildVersion.banner("),
			"%s must print its build version at start" % path)


func test_the_server_export_starts_in_the_server_scene() -> void:
	# An exported binary cannot be handed a scene on the command line the
	# way `godot --path . server.tscn` is — its main scene is baked in.
	# The `server` feature tag is the whole mechanism: set it on a preset
	# and project.godot's override picks the other scene. Break either
	# half and the "server" build silently comes up as a CLIENT, which
	# looks like a working export right up to the moment somebody runs it.
	assert_eq(str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"res://client.tscn",
		"the default main scene is the client")
	assert_eq(str(ProjectSettings.get_setting("application/run/main_scene.server", "")),
		"res://server.tscn",
		"the 'server' feature must select the server scene")

	var cfg := _read(PRESETS)
	for block in cfg.split("[preset."):
		if not block.contains("name=\""):
			continue
		var is_server := block.contains('name="Windows Server"') or block.contains('name="Linux Server"')
		var tagged := block.contains('custom_features="server"')
		if is_server:
			assert_true(tagged,
				"a server preset must carry custom_features=\"server\" or it exports the client")
		elif block.contains('name="Windows Client"'):
			assert_false(tagged,
				"the client preset must NOT carry the server feature")


# --- helpers -----------------------------------------------------------

## Every .gd in the project root plus tests/, which is where a stray
## second reader of the version would realistically appear. Deliberately
## not addons/ — GUT is vendored and not ours to police.
func _project_scripts() -> PackedStringArray:
	var found := PackedStringArray()
	for dir in ["res://", "res://tests"]:
		for name in DirAccess.get_files_at(dir):
			if name.ends_with(".gd"):
				found.append("res://" + name if dir == "res://" else dir + "/" + name)
	return found


## The body of one justfile recipe, from its header line to the next
## unindented line. Scanning the whole justfile would let a rule pass
## because some OTHER recipe happens to contain the string.
func _recipe_body(header: String) -> String:
	var lines := _read("res://justfile").split("\n")
	var body := PackedStringArray()
	var inside := false
	for line in lines:
		if inside:
			if line.length() > 0 and not line.begins_with(" ") and not line.begins_with("\t"):
				break
			body.append(line)
		elif line.begins_with(header):
			inside = true
	assert_true(inside, "no recipe found whose header begins '%s'" % header)
	return "\n".join(body)


## The same text with its comment lines removed, for scans where a
## comment EXPLAINING the forbidden thing would otherwise trip the check.
func _uncommented(text: String) -> String:
	var kept := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)
