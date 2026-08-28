extends GutTest

## Every shipped text asset is valid UTF-8 (#231, #214,
## D-20260828-a-summary-is-shown-or-it-is-deleted).
##
## Seven files — all six `civs/*.tres` and `ai/cautious.tres` — carried a
## raw Windows-1252 `0x97` (an em dash) inside a `summary` field. Godot
## reads `.tres` as UTF-8, so the byte was never the character it was
## meant to be: the engine printed
##
##     Unicode parsing error … Invalid UTF-8 leading byte (97)
##
## twelve times on every load of the civ roster — server, client, bot and
## test run alike — and the string arrived with a replacement character
## where the dash should have been.
##
## Nothing failed. Two reasons, and both are this project's recurring
## shapes rather than anything to do with encoding:
##
## - the field was **declared and unread** (D-055's family, sixth
##   instance), so the corruption had no visible surface at all;
## - the engine's complaint is one line of noise in a log **nothing
##   gates on**, and this project has already been bitten by scanning for
##   the absence of bad news instead of asserting the presence of good
##   (D-022's audit block).
##
## So the guard is a SOURCE SCAN, because a source scan is the only thing
## that can see a defect no behaviour depends on. It covers a CLASS of
## files rather than the seven that happened to be wrong — D-106's own
## caveat is that a caller-exists scan only covers the callers it names,
## and the same applies here.
##
## Observed to fail before being trusted: putting a `0x97` back into any
## one of those `summary` fields reds this file.

const SUFFIXES := [".tres", ".gd", ".tscn", ".gdshader", ".gdshaderinc"]

## Directories that are not ours to police. `addons/` is vendored GUT and
## `tools/` is gitignored portable binaries.
const SKIP := ["res://addons", "res://tools", "res://.godot", "res://generated"]


func _is_ours(path: String) -> bool:
	for prefix in SKIP:
		if path.begins_with(prefix):
			return false
	return true


func _text_files(from: String, out: Array) -> void:
	var dir := DirAccess.open(from)
	if dir == null:
		return
	for name in dir.get_files():
		# Godot renames imported assets, but text assets keep their names.
		# `.remap` and `.import` are build products and not authored here.
		for suffix in SUFFIXES:
			if name.ends_with(suffix):
				out.append(from.path_join(name))
				break
	for name in dir.get_directories():
		if name.begins_with("."):
			continue
		var child := from.path_join(name)
		if _is_ours(child):
			_text_files(child, out)


## Whether these bytes decode as UTF-8, asked WITHOUT going through
## Godot's own reader.
##
## `FileAccess.get_as_text()` REPLACES an undecodable byte with U+FFFD and
## carries on, which is exactly how this survived: every consumer got a
## plausible string. Reading the raw buffer and validating it by hand is
## the only way to ask the question the engine answers by papering over.
func _is_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	var n := bytes.size()
	while i < n:
		var b := bytes[i]
		var extra := 0
		if b < 0x80:
			extra = 0
		elif b >= 0xC2 and b <= 0xDF:
			extra = 1
		elif b >= 0xE0 and b <= 0xEF:
			extra = 2
		elif b >= 0xF0 and b <= 0xF4:
			extra = 3
		else:
			return false  # 0x80-0xC1 and 0xF5+ are never a leading byte
		if i + extra >= n:
			return false
		for k in range(1, extra + 1):
			var c := bytes[i + k]
			if c < 0x80 or c > 0xBF:
				return false
		i += extra + 1
	return true


func test_every_shipped_text_asset_is_valid_utf8() -> void:
	var files := []
	_text_files("res://", files)
	assert_gt(files.size(), 100,
		"Setup: the scan found almost nothing, so it is proving nothing")

	var bad := []
	for path in files:
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			continue
		if not _is_utf8(bytes):
			bad.append(path)
	assert_eq(bad, [],
		"these files are not UTF-8; Godot replaces the byte with U+FFFD and says so "
		+ "in a log nobody gates on (#231)")


func test_the_checker_would_actually_notice_a_cp1252_em_dash() -> void:
	# The byte that was in all seven files, and the one it should have
	# been. A validator that accepted both would pass this whole file
	# vacuously — which is the failure mode D-022's audit block exists
	# for, and it is cheaper to assert than to re-break a shipped file.
	var cp1252 := PackedByteArray([0x61, 0x97, 0x62])       # "a<0x97>b"
	var utf8 := PackedByteArray([0x61, 0xE2, 0x80, 0x94, 0x62])  # "a—b"
	assert_false(_is_utf8(cp1252), "0x97 alone is not a legal UTF-8 leading byte")
	assert_true(_is_utf8(utf8), "and the real em dash must pass")


func test_the_seven_files_that_were_wrong_are_named_and_clean() -> void:
	# Named explicitly as well as scanned, because the scan is the guard
	# and this is the regression: if the class check is ever narrowed,
	# these seven still have to be checked.
	var was_wrong := [
		"res://civs/emberdeep.tres", "res://civs/gildedreach.tres",
		"res://civs/gravesworn.tres", "res://civs/stoneblood.tres",
		"res://civs/thornwood.tres", "res://civs/windmarch.tres",
		"res://ai/cautious.tres",
	]
	for path in was_wrong:
		var bytes := FileAccess.get_file_as_bytes(path)
		assert_gt(bytes.size(), 0, "%s should be readable" % path)
		assert_true(_is_utf8(bytes), "%s is still not UTF-8" % path)
