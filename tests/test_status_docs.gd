extends GutTest

## The imported docs may not name things that do not exist (#291,
## `D-20260828-an-imported-doc-names-the-code-it-is-about`).
##
## `CLAUDE.md` `@`-imports all 31 files under `docs/status/` — 3,372 lines
## — into every session's context, which makes them **instruction-grade**
## rather than narrative. A wrong sentence there is handed to every worker
## on the project before they read a line of code.
##
## ## What this guards, and what it deliberately cannot
##
## It guards **reference integrity**: every decision id, file path and
## `Class.member` an imported doc names must exist. That catches the drift
## class where code is renamed or deleted and the docs are not — the class
## a scan can settle completely.
##
## It does **not** guard truth. A paraphrase like *"it retries against a
## different site now"* names nothing and asserts behaviour, and no scan
## over English can check it. The decision entry records the two
## mechanical checks that were tried and rejected for that class, with the
## measurements — a noisy guard is worse than none, because the next
## person weakens it until it passes.
##
## ## Why the allowlist carries reasons, and is itself checked
##
## Docs legitimately name things that were DELETED — that is what a
## history entry is for. Each such name is listed once, with why, and
## `test_the_allowlist_has_not_rotted` fails if an allowlisted name comes
## back into existence. An allowlist nobody prunes is how a scan becomes
## decoration.

const IMPORTED_DIR := "res://docs/status"
const GROUND_RULES := "res://CLAUDE.md"
const DECISIONS_DIR := "res://decisions"

## Names an imported doc may use although nothing by that name exists.
## Every entry is a thing the docs describe in the PAST tense; adding one
## means writing the reason beside it.
const ABSENT_ON_PURPOSE := {
	"D-YYYYMMDD-slug.md":
		"the naming TEMPLATE in decisions/README.md's rules, not a file",
	"gatherers.tres":
		"the neutral gatherer def D-20260823 deleted; the docs record that "
		+ "a neutral def would shadow every per-civ one",
	"units/founders.tres":
		"deleted by D-20260823; the-opening.md records it as the roster "
		+ "change that broke four test fixtures",
	"static_defence.gd":
		"folded into ai_investment.gd by #365's reconciliation; "
		+ "ai-fortification.md names it in the sentence that says it is "
		+ "GONE, which is precisely what a history entry is for",
}

## Directories a source scan must not walk: the engine's cache, the
## vendored test framework, and the gitignored toolchain.
const SKIP_DIRS := [".godot", ".git", "addons", "tools", ".import"]


func _imported_docs() -> Array:
	var out := [GROUND_RULES]
	var dir := DirAccess.open(IMPORTED_DIR)
	assert_not_null(dir, "docs/status is missing — the imported set is not empty")
	if dir == null:
		return out
	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".md"):
			names.append(normalised)
	names.sort()
	for name in names:
		out.append("%s/%s" % [IMPORTED_DIR, name])
	return out


func _text_of(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _all_imported_text() -> String:
	var out := ""
	for path in _imported_docs():
		out += _text_of(path) + "\n"
	return out


## Every tracked file's project path and its bare name, so a doc may
## write either `docs/status/m4.md` or just `combat.gd`.
func _project_files(path: String, paths: Dictionary, names: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or SKIP_DIRS.has(String(sub)):
			continue
		_project_files(path.path_join(sub), paths, names)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		var full := path.path_join(normalised)
		paths[full.trim_prefix("res://")] = true
		names[normalised] = true


func _every_source_line() -> String:
	var scripts := []
	_all_scripts("res://", scripts)
	var out := ""
	for path in scripts:
		out += FileAccess.get_file_as_string(path)
	return out


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or SKIP_DIRS.has(String(sub)):
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))


# --- decision ids ------------------------------------------------------

## Every `D-...` the imported docs cite must resolve. Dated ids are a
## file; legacy `D-NNN` ids may live INSIDE a sibling entry, which
## `decisions/README.md` rule 4 records explicitly — so those are searched
## for rather than looked up.
##
## Observed to fail before it was trusted: adding a citation to a
## `D-20260101-nothing` reds it.
func test_every_decision_the_imported_docs_cite_exists() -> void:
	var text := _all_imported_text()
	var dir := DirAccess.open(DECISIONS_DIR)
	assert_not_null(dir, "decisions/ is missing")
	if dir == null:
		return

	var entry_names := []
	var all_entries := ""
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if not normalised.ends_with(".md"):
			continue
		entry_names.append(normalised)
		all_entries += FileAccess.get_file_as_string(
			"%s/%s" % [DECISIONS_DIR, normalised])

	var dated := RegEx.create_from_string("D-[0-9]{8}-[a-z0-9-]+")
	var checked := 0
	for m in dated.search_all(text):
		var id := m.get_string()
		checked += 1
		var found := false
		for name in entry_names:
			if name.begins_with(id):
				found = true
				break
		assert_true(found, "an imported doc cites %s and no decision file starts with it" % id)

	var legacy := RegEx.create_from_string("\\bD-[0-9]{3}\\b")
	for m in legacy.search_all(text):
		var id := m.get_string()
		checked += 1
		var named := false
		for name in entry_names:
			if name.begins_with(id):
				named = true
				break
		assert_true(named or all_entries.contains(id),
			"an imported doc cites %s and it appears nowhere in decisions/" % id)

	assert_gt(checked, 100,
		"far fewer decision citations than expected — the scan is not reading the docs")


# --- file paths --------------------------------------------------------

## Every backticked thing shaped like a file must be one. This is the
## check that catches a rename: `cliff_class_of` was deleted by
## D-20260826 and terrain.md says so in the past tense, which is fine —
## a doc naming a file that USED to exist as though it still does is not.
func test_every_file_the_imported_docs_name_exists() -> void:
	var paths := {}
	var names := {}
	_project_files("res://", paths, names)
	assert_gt(names.size(), 200, "the project scan found almost nothing — it is not walking")

	var shaped := RegEx.create_from_string(
		"`([A-Za-z0-9_/\\.\\-]+\\.(gd|tres|gdshader|gdshaderinc|sh|py|md|tscn))`")
	var checked := 0
	for m in shaped.search_all(_all_imported_text()):
		var named := m.get_string(1)
		if ABSENT_ON_PURPOSE.has(named) or ABSENT_ON_PURPOSE.has(named.get_file()):
			continue
		checked += 1
		assert_true(paths.has(named) or names.has(named.get_file()),
			"an imported doc names `%s`, which is not in the project" % named)
	assert_gt(checked, 50, "too few file references found — the pattern is not matching")


## The allowlist must stay a list of things that are genuinely gone. An
## entry whose name exists again is a stale exemption hiding a real check,
## which is how a scan quietly stops scanning.
func test_the_allowlist_has_not_rotted() -> void:
	var paths := {}
	var names := {}
	_project_files("res://", paths, names)
	for entry in ABSENT_ON_PURPOSE:
		var named := String(entry)
		assert_false(paths.has(named) or names.has(named.get_file()),
			"`%s` is allowlisted as absent and exists again — drop the exemption" % named)
		assert_gt(String(ABSENT_ON_PURPOSE[entry]).length(), 20,
			"every exemption carries its reason; `%s` has none worth reading" % named)


# --- symbols -----------------------------------------------------------

## Every backticked `Class.member` an imported doc names must have its
## member somewhere in the source. Deliberately checks the MEMBER and not
## the pair: `TerrainChunk.height_at` is written in the docs and declared
## as `func height_at`, so requiring the dotted form would fail on every
## true reference. It catches the case that matters — a member that no
## longer exists under any name.
func test_every_symbol_the_imported_docs_name_exists() -> void:
	var source := _every_source_line()
	assert_gt(source.length(), 100000, "the source scan read almost nothing")

	var shaped := RegEx.create_from_string("`([A-Z][A-Za-z0-9_]+)\\.([a-z_][A-Za-z0-9_]*)`")
	var checked := 0
	for m in shaped.search_all(_all_imported_text()):
		var member := m.get_string(2)
		if ABSENT_ON_PURPOSE.has(m.get_string(0).replace("`", "")):
			continue
		checked += 1
		assert_true(source.contains(member),
			"an imported doc names `%s.%s` and `%s` appears in no script" % [
				m.get_string(1), member, member])
	assert_gt(checked, 40, "too few symbol references found — the pattern is not matching")


# --- the imported set itself -------------------------------------------

## `CLAUDE.md` must actually import every status doc. A file nobody
## imports is not instruction-grade and is not this test's business; a
## file that EXISTS and is not imported is a doc the ground rules
## silently dropped, which is the same defect one level up.
func test_claude_md_imports_every_status_doc() -> void:
	var rules := _text_of(GROUND_RULES)
	var dir := DirAccess.open(IMPORTED_DIR)
	if dir == null:
		return
	var count := 0
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if not normalised.ends_with(".md"):
			continue
		count += 1
		assert_true(rules.contains("@docs/status/%s" % normalised),
			"docs/status/%s exists and CLAUDE.md does not import it" % normalised)
	assert_gt(count, 20, "the status directory is far smaller than expected")
