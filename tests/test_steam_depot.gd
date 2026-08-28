extends GutTest

## Guards D-20260828-a-depot-upload-is-validated-before-it-is-authenticated
## (#185, D-094 criterion 2): everything a live Steam upload depends on is
## checked WITHOUT a credential, so the first authenticated run is the only
## step that has not already been rehearsed.
##
## Executed rather than scanned, for the reason `test_gate_checks.gd`
## gives: `steam-depot.sh` is a script precisely so a test can drive it and
## watch it get the answer wrong. Nothing here needs Steam, steamcmd, an
## app id, a login or a network — which is the property under test, not a
## convenience of the harness.
##
## Fixtures are written with `FileAccess`, never by echoing through the
## shell. That cost a session to learn on `test_host_gate_occupancy.gd`:
## quoting does not survive GDScript -> OS.execute -> bash -> echo, and a
## fixture that comes out subtly wrong looks exactly like the thing under
## test misbehaving.
##
## What this file deliberately does NOT test is that Steam accepts the
## upload. That needs a partner account, an app fee and an app id nobody
## has yet (#185 says so outright), and it is the one step
## `just steam-upload live` exists to make short.


func _bash(line: String) -> Dictionary:
	for shell in ["/bin/bash", "bash", "/usr/bin/bash"]:
		var out := []
		var code := OS.execute(shell, ["-c", line], out, true)
		if code != -1:
			return {"code": code, "out": "\n".join(PackedStringArray(out))}
	return {"code": -1, "out": ""}


func _repo() -> String:
	return ProjectSettings.globalize_path("res://").rstrip("/")


func _has_a_shell() -> bool:
	var probe := _bash("echo ok")
	var ok := int(probe["code"]) == 0 and String(probe["out"]).contains("ok")
	assert_true(ok,
		"this file needs a POSIX shell — run the suite through `just test-unit` (docker)")
	return ok


func _write(path: String, text: String) -> void:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(handle, "could not write the fixture %s" % path)
	if handle != null:
		handle.store_string(text)
		handle.close()


## A stand-in for `just export`'s output: the build directory, with the
## subdirectories the depot layout names and a byte in each.
##
## Deliberately NOT the real `build/`, which may or may not have been
## exported on this machine — a test that passed only after somebody ran a
## 267 MB export would be a test nobody runs.
func _build_dir(tag: String, subdirs: Array) -> String:
	var dir := ProjectSettings.globalize_path("user://steam-%s" % tag)
	var made := _bash("rm -rf '%s' && mkdir -p '%s'" % [dir, dir])
	assert_eq(int(made["code"]), 0, "could not make the fixture build dir: %s" % made["out"])
	for sub in subdirs:
		var at := "%s/%s" % [dir, sub]
		assert_eq(int(_bash("mkdir -p '%s'" % at)["code"]), 0, "could not make %s" % at)
		_write(at + "/my-edotmw", "not really a binary\n")
	return dir


## Run `steam-depot.sh` with an environment, and nothing else set.
##
## `env -u` on every variable this feature reads, so a developer who
## happens to have real Steam settings exported cannot make these pass —
## or fail — for a reason that is not in the test.
func _depot(build_dir: String, env: Dictionary, args: String) -> Dictionary:
	var cleared := "env"
	for name in ["EDOTMW_STEAM_APP_ID", "EDOTMW_STEAM_DEPOT_WINDOWS",
			"EDOTMW_STEAM_DEPOT_LINUX_SERVER", "EDOTMW_STEAM_BRANCH",
			"EDOTMW_STEAM_USER", "EDOTMW_STEAMCMD", "EDOTMW_BUILD_DIR"]:
		cleared += " -u %s" % name
	var assignments := "EDOTMW_BUILD_DIR='%s'" % build_dir
	for key in env:
		assignments += " %s='%s'" % [key, env[key]]
	return _bash("cd '%s' && %s %s bash steam-depot.sh %s 2>&1"
		% [_repo(), cleared, assignments, args])


## The smallest environment that is actually uploadable.
func _good() -> Dictionary:
	return {"EDOTMW_STEAM_APP_ID": "480", "EDOTMW_STEAM_DEPOT_WINDOWS": "481"}


# --- the happy path, first, so the refusals below mean something -------

func test_a_complete_configuration_validates_with_no_credential_anywhere() -> void:
	# THE property this feature exists for. No steamcmd, no login, no
	# network, no app that exists — and every rule a live upload depends
	# on has still been checked.
	if not _has_a_shell():
		return
	var build := _build_dir("ok", ["windows"])
	var result := _depot(build, _good(), "validate")
	assert_eq(int(result["code"]), 0,
		"a complete configuration must validate without authenticating: %s" % result["out"])
	assert_true(String(result["out"]).contains("app 480"),
		"and must say what it validated, not merely exit 0")


# --- the refusals, each watched failing --------------------------------

func test_a_missing_app_id_is_refused_by_name() -> void:
	if not _has_a_shell():
		return
	var build := _build_dir("noapp", ["windows"])
	var result := _depot(build, {"EDOTMW_STEAM_DEPOT_WINDOWS": "481"}, "validate")
	assert_eq(int(result["code"]), 1, "an upload with no app id must be refused")
	assert_true(String(result["out"]).contains("EDOTMW_STEAM_APP_ID"),
		"and must name the variable to set, not merely complain")


func test_an_app_id_that_is_not_a_number_is_refused() -> void:
	# `cmd_args.gd`'s lesson, one layer out: a value that is silently
	# coerced is worse than one that is rejected. A non-numeric app id
	# does not fail — it uploads to app 0.
	if not _has_a_shell():
		return
	var build := _build_dir("badapp", ["windows"])
	var env := _good()
	env["EDOTMW_STEAM_APP_ID"] = "my-game"
	var result := _depot(build, env, "validate")
	assert_eq(int(result["code"]), 1, "a non-numeric app id must be refused")
	assert_true(String(result["out"]).contains("not a number"),
		"and must say why: %s" % result["out"])


func test_the_public_branch_is_refused() -> void:
	# The rule with the largest blast radius in this file. On Steam,
	# `default` is the branch every owner of the app receives, so setting
	# a build live there is publishing — and D-087 is explicit that M8 is
	# Steam-READY and not launched. The mistake is one word long and
	# cannot be undone from a worktree.
	if not _has_a_shell():
		return
	var build := _build_dir("public", ["windows"])
	for name in ["default", "public", "Default"]:
		var env := _good()
		env["EDOTMW_STEAM_BRANCH"] = name
		var result := _depot(build, env, "validate")
		assert_eq(int(result["code"]), 1,
			"branch '%s' would publish to every owner and must be refused" % name)
		assert_true(String(result["out"]).contains("EVERY owner"),
			"and must say what it would have done: %s" % result["out"])


func test_a_private_branch_name_is_accepted() -> void:
	# The mirror, so the rule above is a rule and not a ban on branches.
	if not _has_a_shell():
		return
	var build := _build_dir("private", ["windows"])
	var env := _good()
	env["EDOTMW_STEAM_BRANCH"] = "playtest-2026"
	assert_eq(int(_depot(build, env, "validate")["code"]), 0,
		"an ordinary private branch name must be allowed")


func test_a_depot_with_nothing_exported_into_it_is_refused() -> void:
	# The failure an owner will actually hit: `just steam-upload` before
	# `just export`, or after a `just nuke`. Uploading an empty depot
	# SUCCEEDS on Steam and ships a build with no game in it.
	if not _has_a_shell():
		return
	var build := _build_dir("empty", [])
	var result := _depot(build, _good(), "validate")
	assert_eq(int(result["code"]), 1, "a depot with no content must be refused")
	assert_true(String(result["out"]).contains("just export"),
		"and must say what to run: %s" % result["out"])


func test_every_problem_is_reported_in_one_run() -> void:
	# Collected rather than short-circuited. Somebody setting this up for
	# the first time has several things unset at once, and a checker that
	# reports one per run turns a five-minute setup into five runs.
	if not _has_a_shell():
		return
	var build := _build_dir("many", [])
	var result := _depot(build, {"EDOTMW_STEAM_BRANCH": "default"}, "validate")
	var text := String(result["out"])
	assert_true(text.contains("EDOTMW_STEAM_APP_ID"), "the app id must be reported")
	assert_true(text.contains("EVERY owner"), "the branch must be reported in the SAME run")
	assert_true(text.contains("EDOTMW_STEAM_DEPOT_WINDOWS"),
		"and the missing depot too: %s" % text)


# --- what gets written -------------------------------------------------

func test_the_vdfs_name_the_app_the_depot_and_the_private_branch() -> void:
	if not _has_a_shell():
		return
	var build := _build_dir("vdf", ["windows"])
	var out := build + "/steam"
	var env := _good()
	env["EDOTMW_STEAM_BRANCH"] = "alpha"
	var result := _depot(build, env, "vdf '%s'" % out)
	assert_eq(int(result["code"]), 0, "generating the VDFs must succeed: %s" % result["out"])

	var app_vdf := FileAccess.get_file_as_string(out + "/app_build_480.vdf")
	assert_false(app_vdf.is_empty(), "no app build script was written")
	assert_true(app_vdf.contains("\"appid\" \"480\""), "the app build must name the app")
	assert_true(app_vdf.contains("\"setlive\" \"alpha\""),
		"it must set the build live on the branch that was asked for")
	assert_true(app_vdf.contains("\"481\""), "and must reference the depot's own script")

	var depot_vdf := FileAccess.get_file_as_string(out + "/depot_build_481.vdf")
	assert_false(depot_vdf.is_empty(), "no depot build script was written")
	assert_true(depot_vdf.contains("\"DepotID\" \"481\""), "the depot must name itself")
	assert_true(depot_vdf.contains("windows"),
		"and must root itself at what `just export` produced: %s" % depot_vdf)


func test_the_upload_is_stamped_with_the_one_build_version() -> void:
	# #185's "done when" is that the installed build prints the version
	# the recipe uploaded. That is only checkable if the upload carries
	# it — and it must be the SAME source of truth `build_version.gd`
	# reads, never a second one (D-20260827-the-build-is-exported-from-one-version).
	if not _has_a_shell():
		return
	var version := ""
	for line in FileAccess.get_file_as_string("res://project.godot").split("\n"):
		if line.begins_with("config/version="):
			version = line.split("\"")[1]
	assert_false(version.is_empty(), "project.godot must carry a version to stamp with")

	var build := _build_dir("stamp", ["windows"])
	var out := build + "/steam"
	assert_eq(int(_depot(build, _good(), "vdf '%s'" % out)["code"]), 0)
	var app_vdf := FileAccess.get_file_as_string(out + "/app_build_480.vdf")
	assert_true(app_vdf.contains(version),
		"the build description must carry version '%s', or an uploaded build cannot "
		% version + "be matched against the binary a player is running")


func test_nothing_written_contains_a_credential() -> void:
	# A VDF is a file on disk that outlives the run, and the obvious way
	# to make steamcmd unattended is to put the password in it. The
	# script never reads one, and this is what keeps that true when
	# somebody later adds a field to make a stubborn login work.
	if not _has_a_shell():
		return
	var build := _build_dir("secret", ["windows"])
	var out := build + "/steam"
	var env := _good()
	env["EDOTMW_STEAM_USER"] = "some-account"
	assert_eq(int(_depot(build, env, "vdf '%s'" % out)["code"]), 0)

	for name in ["app_build_480.vdf", "depot_build_481.vdf"]:
		var text := FileAccess.get_file_as_string("%s/%s" % [out, name])
		assert_false(text.to_lower().contains("password"),
			"%s mentions a password" % name)
		assert_false(text.contains("some-account"),
			"%s carries the login — a build script is not a place for one" % name)


func test_the_optional_server_depot_appears_only_when_it_is_configured() -> void:
	# D-088 puts the authoritative simulation in the host's process, so a
	# tester installs a client and nothing else. A second depot exists
	# because `just export` already produces the binary and
	# official-dedicated-later will want it — opt-in, so it is not a
	# depot nothing installs.
	if not _has_a_shell():
		return
	var build := _build_dir("twodepots", ["windows", "linux-server"])
	var out := build + "/steam"

	assert_eq(int(_depot(build, _good(), "vdf '%s'" % out)["code"]), 0)
	# COUNTED, not checked by name. The first version of this asserted
	# that `depot_build_482.vdf` was absent — and a bug that gives an
	# unconfigured depot some OTHER id writes `depot_build_999.vdf` and
	# passes. Observed: it did. A test that names the id it expects to be
	# missing cannot see a depot invented under a different one.
	assert_eq(_depot_scripts(out), 1,
		"only the configured depot may be written, and it is the app build that "
		+ "decides what gets uploaded — an extra one under any id is an upload")
	assert_true(FileAccess.get_file_as_string(out + "/app_build_480.vdf").contains("\"481\""))

	var env := _good()
	env["EDOTMW_STEAM_DEPOT_LINUX_SERVER"] = "482"
	assert_eq(int(_depot(build, env, "vdf '%s'" % out)["code"]), 0)
	assert_eq(_depot_scripts(out), 2, "a configured depot must be written")
	assert_true(FileAccess.file_exists(out + "/depot_build_482.vdf"),
		"and under the id it was configured with")
	assert_true(FileAccess.get_file_as_string(out + "/app_build_480.vdf").contains("\"482\""),
		"and must be referenced by the app build")


## How many depot build scripts were written, whatever they are called.
func _depot_scripts(dir: String) -> int:
	var n := 0
	for name in DirAccess.get_files_at(dir):
		if String(name).begins_with("depot_build_") and String(name).ends_with(".vdf"):
			n += 1
	return n


func test_a_configuration_that_cannot_upload_writes_no_vdf() -> void:
	# Generating first and checking afterwards would leave a valid-looking
	# build script on disk for an invalid configuration — and the next
	# person to run steamcmd by hand would use it.
	if not _has_a_shell():
		return
	var build := _build_dir("novdf", ["windows"])
	var out := build + "/steam"
	var env := _good()
	env["EDOTMW_STEAM_BRANCH"] = "default"
	var result := _depot(build, env, "vdf '%s'" % out)
	assert_eq(int(result["code"]), 1, "an invalid configuration must not generate")
	assert_false(FileAccess.file_exists(out + "/app_build_480.vdf"),
		"a refused configuration left a build script behind")


# --- the recipe, and where it stops ------------------------------------

func test_the_recipe_is_dry_by_default_and_live_must_be_typed() -> void:
	# An upload is outward-facing and cannot be taken back from a
	# worktree. Same rule as `just reap-orphans`, which dry-runs unless
	# APPLY=1 and was twice caught proposing to delete live containers.
	var justfile := FileAccess.get_file_as_string("res://justfile")
	assert_true(justfile.contains("steam-upload MODE=\"dry\""),
		"steam-upload must default to a dry run")
	assert_true(justfile.contains("recipe-arg.sh enum MODE"),
		"MODE must go through recipe-arg.sh, or `MODE=live` binds silently (#89)")


func test_the_recipe_validates_before_it_looks_for_a_credential() -> void:
	# The ordering IS the feature: a dry run that checked less than a
	# live one would be a rehearsal of a different performance. Asserted
	# by position, because the two are the same three lines in both
	# modes and only the tail differs.
	var justfile := FileAccess.get_file_as_string("res://justfile")
	var recipe_at := justfile.find("steam-upload MODE=")
	assert_gt(recipe_at, 0, "there must be a steam-upload recipe to read")
	var validate_at := justfile.find("steam-depot.sh validate", recipe_at)
	var login_at := justfile.find("EDOTMW_STEAM_USER", recipe_at)
	assert_gt(validate_at, recipe_at, "the recipe must validate")
	assert_true(login_at > validate_at,
		"the recipe reaches for a login before it has validated anything")


func test_no_password_is_ever_passed_to_steamcmd() -> void:
	# Steam Guard makes an unattended password login fail anyway on a
	# machine that has not been trusted, so a password on the command
	# line would be a secret in a process list that does not even remove
	# the prompt. The documented path is one interactive login and a
	# cached sentry.
	var justfile := FileAccess.get_file_as_string("res://justfile")
	var script := FileAccess.get_file_as_string("res://steam-depot.sh")
	for text in [justfile, script]:
		assert_false(text.contains("EDOTMW_STEAM_PASSWORD"),
			"a Steam password must never be an environment variable this repo reads")

	# The login is immediately followed by the build command, so there is
	# nowhere for a second credential argument to sit. Asserted as the
	# whole invocation rather than as an absence, because "no password
	# anywhere" is satisfied by a recipe that does not run steamcmd at
	# all — which would pass while the feature was missing.
	assert_true(justfile.contains("+login \"$EDOTMW_STEAM_USER\" +run_app_build"),
		"the live upload must log in with a username and nothing else")
