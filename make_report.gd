extends SceneTree

## `just report-bundle` — write one attachable file, or say what would go
## in it (#288).
##
## Its own entry point for the reason `package_zip.gd` is: a recipe needs
## something `--script` can reach. Unlike that one it DOES use the
## project's own classes (`ReportBundle`, `ArtifactPath`, `BuildVersion`),
## which resolve from the import cache — so the recipe depends on
## `_import` like everything else that names a global class.
##
##   godot --headless --script make_report.gd -- [--out=<file.zip>] [--list=1]
##
## `--list=1` answers "what would you send" without writing anything, which
## is the question a tester is entitled to ask first. It is also what
## makes the recipe useful on a machine that has played nothing: an empty
## list is a true and immediately legible answer.

func _init() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	# `--list=1`, not a bare `--list`: `CmdArgs.parse` only recognises
	# `--key=value` and drops a lone flag silently, so a bare one would
	# have written the bundle it was asked to preview. It did.
	var listing := String(args.get("list", "0")) == "1"

	var sources := ReportBundle.sources()
	print("report: my-edotmw %s" % BuildVersion.string())
	print("report: logs from %s, replays from %s"
		% [ReportBundle.LOG_DIR, ArtifactPath.base()])
	if sources.is_empty():
		# Not an error. A fresh install has played nothing, and a bundle
		# of a system report alone is still worth attaching to "it will
		# not start" — which is the report this most needs to serve.
		print("report: no logs or replays found yet — a bundle would carry the system report only")
	for entry in sources:
		print("  %s  <- %s" % [String(entry["zip_path"]), String(entry["source"])])

	if listing:
		quit(0)
		return

	var out := String(args.get("out", ""))
	if out.is_empty():
		out = ArtifactPath.of(ReportBundle.bundle_name(
			BuildVersion.string(), ReportBundle.stamp_now()))

	var result := ReportBundle.write(out)
	if not bool(result["ok"]):
		push_error("report: %s" % String(result.get("error", "could not write the bundle")))
		quit(1)
		return

	for gone in result["missing"]:
		# Between listing and writing, a log can rotate away. Rare, and
		# said out loud rather than silently producing a shorter bundle
		# than the line above promised.
		print("report: %s disappeared while packing — not included" % String(gone))

	print("report: wrote %s (%d file(s) plus system.txt and MANIFEST.txt)"
		% [ArtifactPath.describe(String(result["path"])), result["entries"].size()])
	print("report: nothing was sent anywhere. Attach it to your report if you want to.")
	quit(0)
