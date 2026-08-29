extends Resource
class_name ManualPageDef

## A hand-written page of the in-game manual (#305), as data.
##
## The manual has two halves and they rot differently, which is the whole
## reason this schema exists.
##
## The GENERATED half — rosters, stats, counters, buildings, formations —
## is derived from the shipped `.tres` at the moment a player opens the
## page (`manual.gd`). It cannot go stale, because there is no copy of the
## data anywhere for the data to disagree with. That is the same rule
## `TerrainGen.biome_color()` gives the minimap and the preview PNG.
##
## This half is the PROSE — what fog of war is, how morale works, what
## wins a match. Prose cannot be derived, so prose CAN go stale, and this
## project's own history says it will: a status doc, a decision entry and
## a doc comment have each described behaviour that had stopped being true
## (D-055, D-065, D-106, #291). A manual that lies to a player is worse
## than no manual, because they trust it.
##
## So every page carries `sources` — the files whose contents it describes
## — and a `stamp` over them. `just build-manual` computes the stamp;
## `tests/test_manual.gd` recomputes it and FAILS when a source has moved
## and the stamp was not renewed. A gameplay PR that changes the rout
## threshold and forgets the morale page goes red.
##
## ## Why the stamp lives HERE and not in one manifest
##
## `generated/manifest.json` holds ONE hash over ALL of `art/`, and that
## is right there: a bake is one atomic operation and every output comes
## out of one run.
##
## A manual page is not. Pages are stamped against different sources on
## purpose — the fog page is not invalidated by a unit stat change, and
## the roster page is not invalidated by a fog decision. A single hash
## over every source would red EVERY page on any gameplay PR, and a guard
## that fires on things it has nothing to say about is a guard people
## learn to silence rather than obey (#204 records this repo already
## having one of those). A per-page stamp names the page to re-read.
##
## The other half is mechanical: several agents develop this repo in
## parallel (D-095), and a central manifest is a file every one of their
## branches edits. `decisions/README.md` exists because a shared monolith
## made every parallel merge conflict; one file per page is that lesson
## applied.
##
## ## Why a .tres and not a .md
##
## `export_presets.cfg` excludes `*.md` from every shipping build, so a
## manual written in Markdown would be present in the checkout and absent
## from the game — the "works here, missing on a player's machine" failure
## the export work already paid for once. A `.tres` is a resource, ships
## by construction, is plain text, and is directly editable by Claude Code
## without the Godot GUI, which is D-001's premise.

@export var id: StringName

## What the contents list calls this page.
@export var title: String = ""

## Sort order across the whole manual, generated pages included, so a new
## page slots into the reading order without renumbering anything.
## Generated pages take the tens; leave gaps.
@export var order: int = 100

## One line under the title, and the line the contents list shows.
@export var summary: String = ""

## The page itself. Blank lines separate paragraphs; a line beginning
## "## " is a sub-heading. Deliberately not a rich markup language — the
## renderer is a column of Labels, and a manual that needed a parser
## would be a manual nobody could check the fit of.
@export_multiline var body: String = ""

## The files this page DESCRIBES, res:// paths, in any order (the stamp
## sorts them). Data files, decision entries, or both.
##
## Name what would make the page WRONG, not everything it touches. Over-
## naming is the failure mode that makes the guard noise: a page stamped
## against every unit in the roster reds on a cosmetic colour change and
## teaches its next reader to re-stamp without reading.
@export var sources: Array[String] = []

## sha256 over `sources` at the time this page was last read against them.
## Written by `just build-manual`; compared by `tests/test_manual.gd`.
##
## Empty means "never stamped", which the test reports as a failure rather
## than skipping — a page that opted out of the guard by leaving a field
## blank is exactly what the guard is for.
@export var stamp: String = ""


## Returns "" if valid, else the reason. Mirrors CivDef.validate() — a
## broken page fails at load rather than rendering an empty screen.
func validate() -> String:
	if id == &"":
		return "manual page has no id"
	if title.strip_edges() == "":
		return "manual page %s has no title" % id
	if body.strip_edges() == "":
		return "manual page %s has no body" % id
	if sources.is_empty():
		return ("manual page %s names no sources — every prose page is stamped "
			+ "against what it describes, or the staleness guard has nothing "
			+ "to say about it") % id
	return ""


func is_valid() -> bool:
	return validate() == ""


# --- the stamp ---------------------------------------------------------
#
# ONE definition, read by the writer (`manual_stamp.gd`, behind
# `just build-manual`) and by the checker (`tests/test_manual.gd`).
#
# `test_art_assets.gd` deliberately REIMPLEMENTS its equivalent, and that
# is right there: `art/build.py` writes that hash in Python and no
# GDScript can call it, so a second implementation is the only way to
# compare against something. Both halves here are GDScript, so a second
# implementation would buy nothing and could drift — and what the test is
# for is a stale STAMP, never a bug in sha256.


## sha256 over this page's sources: each res:// path, then its bytes, in
## sorted path order.
##
## The path is fed BEFORE the contents, exactly as `art/build.py` does, so
## MOVING a source changes the stamp even when its bytes do not. A page
## stamped against a decision entry that has since been renamed is a page
## stamped against nothing.
##
## Line endings are normalised to LF first. Every source here is text, the
## repo's `.gitattributes` declares LF (D-20260818-every-file-has-a-line-
## ending-rule) — and a worktree created before that rule still holds CRLF
## on disk until its owner runs the settle. Hashing raw bytes would red
## this whole guard on those machines, for a difference git does not
## consider a change at all. That is the "a check that red-flags a good
## tree is worse than no check" rule; the checkout you are standing in
## must not be able to change the answer.
func expected_stamp() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var paths := sources.duplicate()
	paths.sort()
	for path in paths:
		context.update(String(path).to_utf8_buffer())
		if not FileAccess.file_exists(path):
			# A named source that is not there is its own answer, and a
			# distinct one: the stamp changes, the test goes red, and the
			# message says which page names a file that has gone.
			context.update("<missing>".to_utf8_buffer())
			continue
		var text := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
		var bytes := text.to_utf8_buffer()
		# HashingContext.update() errors on an empty buffer, and an empty
		# source file is legal. Feeding nothing is what hashlib does with
		# b"" anyway.
		if bytes.size() > 0:
			context.update(bytes)
	return context.finish().hex_encode()


## Which of this page's sources no longer exist. Reported separately from
## the stamp because "you renamed a decision entry" and "you changed a
## rule" want different answers from the reader, and a bare hash mismatch
## cannot tell them apart.
func missing_sources() -> Array:
	var out := []
	for path in sources:
		if not FileAccess.file_exists(path):
			out.append(String(path))
	return out
