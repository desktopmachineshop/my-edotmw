extends GutTest

## Guards D-20260828-a-report-is-made-not-sent (#288): a tester can turn
## what happened into one attachable file, and that file discloses
## exactly what it says it discloses.
##
## Two halves, and the second is the one with teeth. The SELECTION and the
## TEXT are static and pure, so they are checked directly — which files
## would go in, what the manifest says, what the system report contains.
## Then a scan asserts the CALLERS exist, because every behavioural test
## here would still pass with nothing in the client able to reach any of
## it, which is the D-055/D-106 family this project keeps meeting.
##
## The privacy assertions are the point of the file rather than a
## flourish. `testers.md` promises no telemetry and no account; a bundle
## that quietly carried a user name or opened a socket would break that
## promise in the one direction nobody would check.


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func _write(path: String, text: String) -> void:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(handle, "could not write the fixture %s" % path)
	if handle != null:
		handle.store_string(text)
		handle.close()


## A throwaway directory holding files with controlled modification
## times, so "newest first" is a claim this file can actually make.
func _dir_with(tag: String, names: Array) -> String:
	var dir := "user://report-%s" % tag
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, name])
	for name in names:
		_write("%s/%s" % [dir, name], "contents of %s\n" % name)
		# Written one at a time with a real wait between, because the
		# ordering under test is by MODIFICATION TIME and the filesystem
		# reports that in whole seconds. Files written in one burst all
		# share a timestamp and would make any ordering assertion pass by
		# luck — the vacuous-pass shape, applied to a fixture.
		OS.delay_msec(1100)
	return ProjectSettings.globalize_path(dir)


# --- selection ----------------------------------------------------------

func test_the_newest_files_come_first() -> void:
	# A bundle that carried the alphabetically-last replay instead of the
	# one the player just recorded would be worse than carrying none: it
	# would look like it worked.
	var dir := _dir_with("order", ["b.edmw", "a.edmw", "c.edmw"])
	var got := ReportBundle.newest_files(dir, ".edmw", 3)
	assert_eq(got.size(), 3, "all three should be found")
	assert_true(String(got[0]).ends_with("c.edmw"),
		"the newest file must come first, and it is not the last alphabetically")
	assert_true(String(got[2]).ends_with("b.edmw"), "and the oldest last")


func test_only_the_newest_few_are_taken() -> void:
	# An attachment, not a download. The engine rotates logs and a
	# long-lived install has many.
	var dir := _dir_with("cap", ["a.edmw", "b.edmw", "c.edmw"])
	assert_eq(ReportBundle.newest_files(dir, ".edmw", 2).size(), 2)


func test_a_directory_that_does_not_exist_is_not_an_error() -> void:
	# The report that matters most is "it will not start", from a machine
	# that has played nothing. A bundle must still be produced there.
	assert_eq(ReportBundle.newest_files("user://report-nothing-here", ".edmw", 3).size(), 0)


func test_replays_are_picked_by_the_extension_replays_actually_have() -> void:
	# Found by running it. The first version looked for `.log` in the
	# artifacts directory — which in a checkout is full of `test-load`
	# console logs, so the bundle carried two of those and NO replay at
	# all, while reporting that it had packed "replays".
	#
	# Driven through `sources()` rather than through the picking helper,
	# and that is the whole point of this test: the bug was the call site
	# passing the wrong extension, and a test of the helper watched it
	# happen and stayed green. Observed — this file passed 17/17 with the
	# defect reintroduced, until `sources()` took its directories as
	# arguments so it could be pointed at a fixture.
	assert_eq(ReplayLog.SUFFIX, ".edmw", "the replay extension moved")
	var replays := _dir_with("kinds", ["test-load-server.log", "replay-4433.edmw"])
	var logs := _dir_with("kindlogs", ["godot.log"])

	var got := ReportBundle.sources(logs, replays)
	var packed := PackedStringArray()
	for entry in got:
		packed.append(String(entry["zip_path"]))
	assert_true(packed.has("replays/replay-4433.edmw"),
		"the replay must be packed: %s" % str(packed))
	assert_false(packed.has("replays/test-load-server.log"),
		"a console log sitting in the artifacts directory is not a replay: %s" % str(packed))
	assert_true(packed.has("logs/godot.log"), "and the engine log still comes from the log dir")


func test_every_packed_file_says_what_it_is() -> void:
	# The manifest is generated from these notes, so an entry with none
	# would list a file under a blank explanation — and the whole reason
	# the bundle is legible is that a tester can read what they are
	# about to send.
	var replays := _dir_with("notes", ["replay-4433.edmw"])
	var logs := _dir_with("noteslogs", ["godot.log"])
	for entry in ReportBundle.sources(logs, replays):
		assert_false(String(entry["note"]).strip_edges().is_empty(),
			"%s is packed with no explanation" % String(entry["zip_path"]))


# --- what the bundle says about itself ----------------------------------

func test_the_name_carries_the_build_version() -> void:
	# A report that arrives with no covering note still has to say which
	# build it came from — the same reason every package zip's filename
	# does.
	var name := ReportBundle.bundle_name("0.1.0-alpha", "20260828-120000")
	assert_true(name.contains("0.1.0-alpha"), "the filename must name the build")
	assert_true(name.ends_with(".zip"))


func test_a_missing_version_does_not_produce_a_nameless_file() -> void:
	assert_true(ReportBundle.bundle_name("", "20260828-120000").contains("unknown"),
		"an unknown version must be said rather than left blank")


func test_the_manifest_names_every_file_and_what_is_in_it() -> void:
	var entries := [
		{"zip_path": "logs/godot.log", "source": "x", "note": "console output"},
		{"zip_path": "replays/replay-4433.edmw", "source": "y", "note": "a replay"},
	]
	var text := ReportBundle.manifest_text(entries, "0.1.0-alpha")
	assert_true(text.contains("logs/godot.log"), "every file must be listed")
	assert_true(text.contains("replays/replay-4433.edmw"))
	assert_true(text.contains("system.txt"),
		"including the one the bundle generates, which a reader cannot otherwise account for")
	assert_true(text.contains("0.1.0-alpha"), "and the build it came from")


func test_the_manifest_says_the_bundle_was_not_sent() -> void:
	# The load-bearing sentence. A player who believes a "report a
	# problem" button transmitted something has been misled by this
	# feature even though it did nothing — so the file says otherwise in
	# the first paragraph.
	var text := ReportBundle.manifest_text([], "0.1.0-alpha")
	assert_true(text.to_lower().contains("nothing was sent"),
		"the manifest must say plainly that nothing left the machine")


func test_the_manifest_warns_what_a_log_contains() -> void:
	# "You decide whether to attach it" is only a real decision if the
	# non-obvious contents are named. A log carries the server address
	# and, on Windows, the user's name inside every engine path.
	#
	# Driven through `sources()` so the note under test is the REAL one.
	# The first version handed `manifest_text` an entry carrying the
	# warning it then asserted was present — a test supplying the answer
	# it checks for, which stayed green when the disclosure was deleted
	# from the code. Third instance of that shape in this session's work;
	# it is worth suspecting any test that builds its own input.
	var logs := _dir_with("warn", ["godot.log"])
	var replays := _dir_with("warnreplays", ["replay-4433.edmw"])
	var text := ReportBundle.manifest_text(
		ReportBundle.sources(logs, replays), "0.1.0-alpha")
	assert_true(text.contains("server address"),
		"a log's contents must be disclosed, not left to be discovered")
	assert_true(text.to_lower().contains("user name"),
		"including the user name Windows puts inside every path the engine prints")


func test_an_empty_bundle_says_so_rather_than_looking_complete() -> void:
	var text := ReportBundle.manifest_text([], "0.1.0-alpha")
	assert_true(text.to_lower().contains("no logs or replays"),
		"a bundle with nothing in it must say so — that fact is itself a report")


# --- what the system report discloses -----------------------------------

func test_the_system_report_is_stable_for_one_machine() -> void:
	# Sorted, so two reports from one machine differ only where the
	# machine differs. Same rule as package_zip.gd's sorted entries.
	var facts := {"platform": "Windows", "cpu": "some cpu", "build": "0.1.0-alpha"}
	var text := ReportBundle.system_report(facts)
	assert_lt(text.find("build"), text.find("cpu"), "keys must be sorted")
	assert_lt(text.find("cpu"), text.find("platform"))
	assert_eq(text, ReportBundle.system_report(facts.duplicate()),
		"the same facts must produce the same report")


func test_the_probe_collects_hardware_and_not_identity() -> void:
	# THE privacy assertion. `testers.md` promises no account and no
	# telemetry; a system report is exactly where a user name, a machine
	# name or an IP would arrive without anybody deciding to add one.
	var facts := ReportBundle.probe()
	assert_true(facts.has("cpu") and facts.has("platform") and facts.has("build"),
		"a report must be enough to reproduce a performance problem: %s" % str(facts))

	var forbidden := [OS.get_environment("USERNAME"), OS.get_environment("USER"),
		OS.get_environment("COMPUTERNAME"), OS.get_environment("HOSTNAME")]
	var text := ReportBundle.system_report(facts)
	for value in forbidden:
		if String(value).strip_edges().length() < 3:
			continue  # an unset variable is not evidence of anything
		assert_false(text.contains(String(value)),
			"the system report discloses '%s', which is identity and not hardware" % value)


func test_the_system_report_does_not_pass_off_a_dummy_adapter_as_a_gpu() -> void:
	# Headless has a dummy rendering server. Asking it anyway would put
	# "Dummy" in a report where a maintainer reads a graphics card, which
	# is worse than the line being absent.
	if DisplayServer.get_name() != "headless":
		return
	assert_false(ReportBundle.probe().has("gpu"),
		"a headless process has no adapter to report and must not invent one")


# --- the callers, without which none of the above is reachable ----------

func test_both_menus_can_reach_it() -> void:
	# Every test above would pass with nothing in the client wired to any
	# of it. The pre-connect menu matters as much as the in-match one:
	# the reports hardest to act on come from somebody who never got INTO
	# a match, and they have no other screen.
	#
	# Counted as CONNECTIONS and a DEFINITION rather than as occurrences
	# of the name: the first version counted the bare identifier and went
	# red on a doc comment that mentioned it, which is the cry-wolf guard
	# this session already had to fix once in `test_multi_agent_isolation`.
	var client := _read("res://client.gd")
	assert_eq(client.count("pressed.connect(_on_report_a_problem_pressed)"), 2,
		"both menus must connect the button — the pre-connect one and the in-match one")
	assert_eq(client.count("func _on_report_a_problem_pressed"), 1,
		"and there must be exactly one handler, so the two cannot come to write "
		+ "different bundles")
	assert_true(client.contains("ReportBundle.write("),
		"and the handler must actually write a bundle")


func test_the_client_never_sends_the_bundle_anywhere() -> void:
	# The promise, asserted rather than trusted. This is the one property
	# of the feature that a reviewer cannot check by using it — a silent
	# upload looks exactly like no upload.
	var bundle := _read("res://report_bundle.gd")
	for forbidden in ["HTTPRequest", "HTTPClient", "ENetConnection", "peer.send",
			"TCPServer", "StreamPeer", "PacketPeer", "UPNP"]:
		assert_false(bundle.contains(forbidden),
			"report_bundle.gd must not be able to transmit: found '%s'" % forbidden)


func test_the_recipe_exists_and_can_preview_without_writing() -> void:
	# "What would you send" is a question a tester is entitled to ask
	# before they send it, and answering it by building a zip and
	# unpacking it again would be a different answer.
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("report-bundle LIST="),
		"there must be a report-bundle recipe with a preview mode")
	assert_true(justfile.contains("recipe-arg.sh enum LIST"),
		"LIST must go through recipe-arg.sh, or `LIST=1` binds silently (#89)")
	var script := _read("res://make_report.gd")
	assert_true(script.contains("args.get(\"list\""),
		"the entry point must read the flag as a VALUE — CmdArgs only parses "
		+ "--key=value, and a bare --list is dropped, which wrote the bundle it "
		+ "was asked to preview")


func test_the_runbook_and_the_tester_page_both_say_how_to_report() -> void:
	# The other half of #288, and the half a tester actually meets. A
	# button nobody is told about is a button nobody presses.
	var testers := _read("res://docs/alpha/testers.md")
	assert_true(testers.contains("Report a problem"),
		"testers.md must name the button by the text on it")
	var runbook := _read("res://docs/alpha/runbook.md")
	assert_true(runbook.to_lower().contains("report a problem"),
		"the runbook must tell the session host what to ask testers for")
