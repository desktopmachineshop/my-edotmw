extends RefCounted
class_name ReportBundle

## One file a tester can attach to a bug report (#288).
##
## The alpha runbook gets a build installed and `testers.md` tells people
## what to look for — and then somebody who hits a bug has to find a log
## directory by hand, know that replays exist at all, and remember to say
## what GPU they have. Most of that does not happen, and the report that
## arrives is "it broke". This turns all of it into one action.
##
## ## The rule this is built around: it CREATES, it never SENDS
##
## `testers.md` promises "no telemetry, no account, and no analytics".
## That promise is kept literally: nothing here opens a socket. The
## bundle is written to disk, the player is told where it is, and THEY
## decide whether to attach it. An automatic upload would be a better
## feedback channel and a broken promise, and the promise is worth more
## at this stage than the reports.
##
## The same reason the bundle carries a MANIFEST naming every file and
## what is in it, including the two things that are not obvious: a log
## contains the address of the server you joined, and — on Windows — your
## user name, because it is part of every path the engine prints. Saying
## so is what makes "you decide whether to attach it" a real decision
## rather than a formality.
##
## ## What is here and what is not
##
## The SELECTION and the TEXT are static and pure — which files would go
## in, what the manifest says, how the system report reads — so they are
## testable headless without writing a zip or owning a GPU. The IO is
## `write()`, one function, and it is thin on purpose.
##
## Deliberately NOT included: anything the player has not already
## produced by playing. No screenshot is taken (the frame at the moment
## of a bug is rarely the frame that shows it, and a player who wants one
## has a key for it), no settings file, no save (there are none, D-092).

## Where Godot writes its own logs. Not configurable here: this is the
## engine's `debug/file_logging/log_path` and there is one of it.
const LOG_DIR := "user://logs"

## How many log files to carry. The engine rotates, and the current one
## plus a few predecessors covers "it broke, then I restarted and it
## broke again" without turning an attachment into a download.
const MAX_LOGS := 5

## How many replays. One is the match they are reporting on; the second
## is the one before it, which is what you want when the answer is "it
## started in the previous match".
const MAX_REPLAYS := 2


## The name a bundle gets. Carries the build version, so a report that
## arrives without a covering note still says which build it came from —
## the same reason every package zip's filename does
## (D-20260828-the-alpha-loop-is-a-zip-and-a-runbook).
##
## `stamp` is passed in rather than read from the clock, because a pure
## function that names a file is testable and `Time.get_datetime_string_from_system()`
## is not.
static func bundle_name(version: String, stamp: String) -> String:
	var safe_version := version if not version.is_empty() else "unknown"
	return "my-edotmw-report-%s-%s.zip" % [safe_version, stamp]


## A filename-safe stamp for right now. The one impure helper, kept apart
## from `bundle_name` so the naming rule can be tested without it.
static func stamp_now() -> String:
	return Time.get_datetime_string_from_system(false, false) \
		.replace(":", "").replace("-", "").replace("T", "-")


## The newest `count` files under `dir` matching `suffix`, newest first.
##
## Sorted by MODIFICATION TIME rather than by name. Log names are
## timestamped and would sort correctly; replay names are not, and a
## bundle that carried the alphabetically-last replay instead of the one
## the player just recorded would be worse than carrying none — it would
## look like it worked.
static func newest_files(dir: String, suffix: String, count: int) -> PackedStringArray:
	var found: Array = []
	var listing := DirAccess.open(dir)
	if listing == null:
		return PackedStringArray()
	for name in listing.get_files():
		if not String(name).ends_with(suffix):
			continue
		var path := "%s/%s" % [dir, name]
		found.append({"path": path, "at": FileAccess.get_modified_time(path)})
	found.sort_custom(func(a, b): return int(a["at"]) > int(b["at"]))
	var out := PackedStringArray()
	for entry in found:
		if out.size() >= count:
			break
		out.append(String(entry["path"]))
	return out


## Everything that would go into a bundle, as `{zip_path, source, note}`.
##
## Its own function, and public, because it is what the tests and
## `just report-bundle 1` read: "what would you send" is a question a
## tester is entitled to ask before they send it, and answering it by
## building a zip and unpacking it again would be a different answer.
##
## The two directories are ARGUMENTS with real defaults, so a test can
## point this at fixtures. That is not tidiness: the first version took
## none, so the only testable part was the file-picking helper — and the
## bug that actually shipped was this function passing it `.log` where
## replays are `.edmw`, which no test of the helper can see. A defect at
## a CALL SITE needs the call site under test.
static func sources(log_dir: String = LOG_DIR, replay_dir: String = "") -> Array:
	if replay_dir.is_empty():
		replay_dir = ArtifactPath.base()
	var out: Array = []
	for path in newest_files(log_dir, ".log", MAX_LOGS):
		out.append({
			"zip_path": "logs/%s" % path.get_file(),
			"source": path,
			"note": "console output — includes the server address you joined"
				+ ", and on Windows your user name inside file paths",
		})
	for path in newest_files(replay_dir, ReplayLog.SUFFIX, MAX_REPLAYS):
		out.append({
			"zip_path": "replays/%s" % path.get_file(),
			"source": path,
			"note": "a replay: the curve log for one match (D-016)",
		})
	return out


## The system report, from facts a caller supplies.
##
## Injected rather than read, so the text is testable and so the list of
## what this discloses is visible in one place — `probe()` below is the
## only thing that touches `OS` and `RenderingServer`.
static func system_report(facts: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("my-edotmw — system report")
	lines.append("")
	# Sorted, so two reports from one machine differ only where the
	# machine differs. Same rule as package_zip.gd's sorted entries.
	var keys := facts.keys()
	keys.sort()
	for key in keys:
		lines.append("%-22s %s" % [str(key), str(facts[key])])
	lines.append("")
	lines.append("No user name, account, machine name or network address is collected here.")
	lines.append("The LOG files in this bundle are a different matter — see MANIFEST.txt.")
	return "\n".join(lines) + "\n"


## What this machine is, for the report above.
##
## Every value is about the HARDWARE and the BUILD. Deliberately absent:
## `OS.get_environment("USERNAME")`, the machine name, and anything about
## the network. A report should be enough to reproduce a performance
## problem and no more.
static func probe() -> Dictionary:
	var facts := {
		"build": BuildVersion.string(),
		"engine": "%s" % Engine.get_version_info().get("string", "unknown"),
		"platform": OS.get_name(),
		"os version": OS.get_version(),
		"cpu": OS.get_processor_name(),
		"cpu threads": OS.get_processor_count(),
		"display server": DisplayServer.get_name(),
	}
	var memory := OS.get_memory_info()
	if memory.has("physical") and int(memory["physical"]) > 0:
		facts["memory"] = "%d MB" % (int(memory["physical"]) / 1048576)
	# The adapter is the single most useful line in a performance report
	# and the most likely to be absent: a headless process has a dummy
	# rendering server, and asking it anyway would put "Dummy" in a
	# report as if it were a graphics card.
	if DisplayServer.get_name() != "headless":
		facts["gpu"] = RenderingServer.get_video_adapter_name()
		facts["gpu driver"] = RenderingServer.get_video_adapter_api_version()
	return facts


## The note that travels with the bundle.
##
## Written for the person who OPENS it as much as the one who sends it:
## a maintainer should be able to tell from this file alone what they
## have been given, and a tester should be able to read it before
## deciding to attach anything.
static func manifest_text(entries: Array, version: String) -> String:
	var lines := PackedStringArray()
	lines.append("my-edotmw problem report — build %s" % version)
	lines.append("")
	lines.append("You made this file. Nothing was sent anywhere: this game has no")
	lines.append("telemetry and no account, and this bundle exists only on your disk")
	lines.append("until you choose to attach it.")
	lines.append("")
	lines.append("Please say what happened alongside it. What you were doing and what")
	lines.append("you expected is worth more than any file in here.")
	lines.append("")
	lines.append("WHAT IS IN THIS FILE")
	lines.append("")
	if entries.is_empty():
		lines.append("  (nothing but this note and the system report — no logs or replays")
		lines.append("   were found, which is itself worth mentioning in your report)")
	# Grouped by note, so five log files carry one explanation rather than
	# five copies of it. This is the one file in the bundle a human reads
	# before deciding whether to send it, and a wall of repetition is a
	# wall people stop reading — which would defeat the whole point of
	# saying what is in here.
	var seen := PackedStringArray()
	for entry in entries:
		var note := String(entry["note"])
		if seen.has(note):
			continue
		seen.append(note)
		for other in entries:
			if String(other["note"]) == note:
				lines.append("  %s" % String(other["zip_path"]))
		lines.append("      %s" % note)
		lines.append("")
	lines.append("  system.txt")
	lines.append("      your OS, CPU, memory and graphics adapter, and the build version")
	lines.append("")
	lines.append("WHAT IS NOT IN IT")
	lines.append("")
	lines.append("  No account, no machine name, no screenshot, no keystrokes, and")
	lines.append("  nothing about anything other than this game.")
	return "\n".join(lines) + "\n"


## Write the bundle. The only function here that touches the disk.
##
## Returns `{ok, path, entries, missing}` — `missing` being sources that
## vanished between `sources()` and the write, which is rare and worth
## reporting rather than silently shipping a short bundle.
static func write(dest: String) -> Dictionary:
	var version := BuildVersion.string()
	var entries := sources()

	var err := ArtifactPath.ensure_dir_for(dest)
	if err != OK:
		return {"ok": false, "path": dest, "entries": [], "missing": [],
			"error": "could not create the folder for %s (error %d)" % [dest, err]}

	var packer := ZIPPacker.new()
	if packer.open(dest) != OK:
		return {"ok": false, "path": dest, "entries": [], "missing": [],
			"error": "could not write %s" % dest}

	var written: Array = []
	var missing: Array = []
	for entry in entries:
		var bytes := FileAccess.get_file_as_bytes(String(entry["source"]))
		if bytes.is_empty() and not FileAccess.file_exists(String(entry["source"])):
			missing.append(String(entry["source"]))
			continue
		packer.start_file(String(entry["zip_path"]))
		packer.write_file(bytes)
		packer.close_file()
		written.append(entry)

	packer.start_file("system.txt")
	packer.write_file(system_report(probe()).to_utf8_buffer())
	packer.close_file()

	# LAST, so it describes what actually went in rather than what was
	# meant to. A manifest listing a file the bundle does not contain is
	# worse than no manifest — it sends whoever opens it looking for
	# something that was never there.
	packer.start_file("MANIFEST.txt")
	packer.write_file(manifest_text(written, version).to_utf8_buffer())
	packer.close_file()
	packer.close()

	return {"ok": true, "path": dest, "entries": written, "missing": missing}
