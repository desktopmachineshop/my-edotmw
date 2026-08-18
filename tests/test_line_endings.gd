extends GutTest

## Guards #118: every tracked file has an EXPLICIT line-ending answer in
## .gitattributes.
##
## "Unspecified" is not neutral — it means "ask the machine", and the dev
## machine has core.autocrlf=true. .gitattributes named five patterns for
## six milestones, so ~940 tracked files were checked out CRLF while
## Godot's importer rewrites the ones it owns (.import/.tres/.tscn/.uid)
## with LF. The result is ~140 files that `git status` calls modified and
## `git diff` shows nothing for, which stops `git rebase` starting at all.
##
## Same shape as test_multi_agent_isolation.gd's hardcoded-literal scans:
## the property is only real if losing it FAILS. Godot cannot ask git what
## it thinks, so this file re-implements the one rule that matters —
## last-match-wins over the patterns actually written — and then checks it
## against the files actually on disk.

# Directories that are not tracked (see .gitignore) plus Godot's own cache.
# Everything else under res:// is repository content.
const SKIPPED_DIRS := [
	".git", ".godot", ".godot-container", ".mono", "__pycache__",
	"artifacts", "tools", "venv", ".venv",
]

# Patterns this matcher understands. gitattributes also allows path
# patterns ("art/**/*.py"), and silently ignoring one would make this
# whole test vacuous — so an unrecognised pattern is a failure, not a skip.
const BASENAME_ONLY := true


class Rule:
	var pattern: String
	var attrs: Dictionary

	func _init(p: String, a: Dictionary) -> void:
		pattern = p
		attrs = a


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## .gitattributes, in file order. Later rules win, which is why order is
## kept rather than collapsed into a dictionary.
func _rules() -> Array:
	var rules := []
	for raw in _read("res://.gitattributes").split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		var attrs := {}
		for i in range(1, parts.size()):
			var token := String(parts[i])
			if token == "binary":
				# The `binary` macro is exactly `-text -diff`.
				attrs["text"] = "unset"
				attrs["diff"] = "unset"
			elif token.contains("="):
				var kv := token.split("=", true, 1)
				attrs[String(kv[0])] = String(kv[1])
			elif token.begins_with("-"):
				attrs[token.substr(1)] = "unset"
			else:
				attrs[token] = "set"
		rules.append(Rule.new(String(parts[0]), attrs))
	return rules


func _matches(pattern: String, path: String) -> bool:
	if pattern.contains("/"):
		return path.match(pattern)
	return path.get_file().match(pattern)


## What git would resolve for `path`, last match wins per attribute.
func _resolve(rules: Array, path: String) -> Dictionary:
	var out := {}
	for rule in rules:
		if _matches(rule.pattern, path):
			out.merge(rule.attrs, true)
	return out


## A file is answered if it is declared binary, or given an eol.
func _is_answered(attrs: Dictionary) -> bool:
	if attrs.get("text", "") == "unset":
		return true
	return attrs.has("eol")


func _walk(dir_path: String, found: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var child := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not SKIPPED_DIRS.has(entry):
				_walk(child, found)
		else:
			found.append(child)
		entry = dir.get_next()
	dir.list_dir_end()


func test_every_file_in_the_repo_has_an_explicit_line_ending_rule() -> void:
	var rules := _rules()
	assert_gt(rules.size(), 0, ".gitattributes must contain rules")

	var files := []
	_walk("res://", files)
	assert_gt(files.size(), 100,
		"the walk found almost nothing — it is not looking at the repo")

	# Report by EXTENSION rather than by path: 138 unanswered .import files
	# are one defect, and a list of 138 paths hides that.
	var unanswered := {}
	for path in files:
		if not _is_answered(_resolve(rules, path)):
			var ext: String = String(path).get_extension()
			unanswered[ext if not ext.is_empty() else String(path).get_file()] = path

	assert_eq(unanswered.size(), 0,
		"these file kinds fall through to the machine's core.autocrlf: %s"
		% [unanswered.keys()])


func test_the_catch_all_never_wins_over_a_rule_that_was_bought_with_an_incident() -> void:
	var rules := _rules()

	# Each of these exists because a guess was wrong once. The catch-all is
	# FIRST in the file so they still win; moving it to the end would take
	# `binary` off every .glb without anything failing until a model broke.
	var expected := {
		"res://gui_entrypoint.sh": "lf",          # CRLF shebang, in-container
		"res://Dockerfile": "lf",
		"res://justfile": "lf",
		"res://art/build.py": "lf",               # manifest source_hash
		"res://bootstrap.ps1": "crlf",            # fresh-clone entry point
	}
	for path in expected:
		var attrs := _resolve(rules, path)
		assert_eq(attrs.get("eol", ""), expected[path],
			"%s must be pinned to %s" % [path, expected[path]])

	for path in [
		"res://generated/models/militia.glb",
		"res://generated/vat/militia.exr",
		"res://generated/textures/terrain_atlas.png",
		"res://addons/gut/fonts/CourierPrime-Regular.ttf",
		"res://addons/gut/source_code_pro.fnt",
	]:
		var attrs := _resolve(rules, path)
		assert_eq(attrs.get("text", ""), "unset",
			"%s must stay binary — a CRLF substitution in it corrupts silently" % path)


func test_every_pattern_written_is_one_this_scan_can_read() -> void:
	# If a future rule uses a path pattern, the basename matcher above would
	# quietly stop applying it and this whole file would go vacuously green
	# — the failure mode CLAUDE.md's "observe every check fail" rule exists
	# for. Fail loudly instead, and teach _matches() the new shape.
	for rule in _rules():
		var pattern: String = rule.pattern
		var readable := not pattern.contains("/") or pattern.contains("*")
		assert_true(readable,
			"_matches() cannot resolve the pattern '%s' — teach it before adding it"
			% pattern)
