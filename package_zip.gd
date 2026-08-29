extends SceneTree

## Zip a directory, using the engine this project already pins (#183).
##
## `just package` needs to produce one file a tester downloads, and the
## obvious tool is not available: `zip` is not on Git Bash's PATH on
## Windows, `Compress-Archive` is PowerShell-only, and adding either as a
## dependency would break the promise that a fresh clone needs nothing
## but `bootstrap.ps1`. Godot ships `ZIPPacker`, Godot is already pinned
## (D-001) and already required by every recipe that produced the thing
## being packed — so the packer is the same binary as the exporter.
##
## Deliberately its own script rather than a branch inside another one:
## it is reached by `--script`, which means no main scene, no window and
## no import of the project's own classes, so it runs in about a second.
##
##   godot --headless --script package_zip.gd -- --dir=<folder> --out=<file.zip>
##
## Paths are OS paths, not `res://`: the thing being packed is a BUILD,
## which lives outside the project's virtual filesystem.

func _init() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var dir := String(args.get("dir", ""))
	var out := String(args.get("out", ""))
	if dir.is_empty() or out.is_empty():
		push_error("package_zip.gd: needs --dir=<folder> --out=<file.zip>")
		quit(2)
		return
	if not DirAccess.dir_exists_absolute(dir):
		push_error("package_zip.gd: no such directory: %s" % dir)
		quit(1)
		return

	var packer := ZIPPacker.new()
	if packer.open(out) != OK:
		push_error("package_zip.gd: could not write %s" % out)
		quit(1)
		return

	# Sorted, so two packages of one build list their files in the same
	# order — the same reason `art/build.py` iterates sorted (D-081).
	# A zip whose entry order depends on the filesystem is a zip whose
	# checksum moves for no reason anybody can see.
	var files := _files_under(dir, "")
	files.sort()
	var written := 0
	for relative in files:
		var handle := FileAccess.open(dir.path_join(relative), FileAccess.READ)
		if handle == null:
			push_error("package_zip.gd: could not read %s" % relative)
			packer.close()
			quit(1)
			return
		packer.start_file(relative)
		packer.write_file(handle.get_buffer(handle.get_length()))
		packer.close_file()
		handle.close()
		written += 1
	packer.close()
	print("package_zip.gd: wrote %d file(s) into %s" % [written, out])
	quit(0)


## Every file under `root`, as paths relative to it, recursing. Returns
## paths with `/` separators whatever the platform uses, because that is
## what a zip entry is.
func _files_under(root: String, prefix: String) -> PackedStringArray:
	var found := PackedStringArray()
	var here := root if prefix.is_empty() else root.path_join(prefix)
	for name in DirAccess.get_files_at(here):
		found.append(name if prefix.is_empty() else prefix + "/" + name)
	for name in DirAccess.get_directories_at(here):
		var child := name if prefix.is_empty() else prefix + "/" + name
		found.append_array(_files_under(root, child))
	return found
