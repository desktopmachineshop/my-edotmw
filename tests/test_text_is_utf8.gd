extends GutTest

## Every shipped text file decodes as UTF-8 (#236).
##
## Seven files — the six fantasy civs and one AI profile — carried a raw
## **`0x97`**, the Windows-1252 em dash, where the prose plainly meant
## `—`. Godot does not fail on that; it substitutes U+FFFD. So the civ
## blurb a player reads in the lobby carried a replacement character on
## SIX OF SIX shipped civs, the AI difficulty description carried one too,
## and every headless run printed several lines of
##
##     Unicode parsing error, some characters were replaced with <?>:
##     Invalid UTF-8 leading byte (97)
##
## before it got to work. Nothing failed. A parse-noise line is exactly
## the kind of thing a log scan learns to ignore.
##
## ## Why this is a scan and not seven fixed files
##
## The seven were fixed in this same change, and fixing them is worth
## nothing on its own: the bytes arrive by paste, from an editor that
## helpfully autocorrects a hyphen, and they will arrive again the next
## time somebody writes a unit description. Naming the seven would close
## an incident. Scanning every file closes the FAMILY — which is the
## difference this project's own record keeps insisting on (D-055's
## uncalled members, D-106's caller-exists scan, the line-ending rule
## that covered five patterns and missed the other 940).
##
## ## Why the whole tree rather than /civs
##
## The same paste can land in a unit, a formation, a scenario, a map, a
## shader or a script. The decoder does not care which directory it is
## in, so neither does this.

## Directories that hold no shipped text, or hold text this rule cannot
## speak for. `tools/` is a fetched toolchain, `.godot*` are caches,
## `generated/` and `art/source/` are binary build products and Blender
## files.
const SKIP_DIRS := ["tools", "addons", "generated", ".godot", ".git",
	"artifacts", "venv"]

## Suffixes that are BINARY by design — a byte outside UTF-8 in one of
## these is not a defect, it is the file.
const BINARY_SUFFIXES := [".glb", ".exr", ".png", ".jpg", ".jpeg", ".ttf",
	".blend", ".wav", ".ogg", ".zip", ".pck", ".edmw", ".uid"]

## What the shipped text actually is. Extended deliberately rather than
## scanning everything: a file type nobody has thought about yet should
## have to be added on purpose.
const TEXT_SUFFIXES := [".tres", ".tscn", ".gd", ".gdshader", ".gdshaderinc",
	".godot", ".json", ".cfg", ".md", ".sh", ".ps1", ".py", ".yml", ".yaml"]


func test_every_shipped_text_file_decodes_as_utf8() -> void:
	var scanned := 0
	var offenders := []
	for path in _text_files("res://"):
		scanned += 1
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			continue
		var where := _first_bad_byte(bytes)
		if where >= 0:
			offenders.append("%s: byte 0x%02X at offset %d"
				% [path, bytes[where], where])

	assert_gt(scanned, 200,
		"the scan found the project's text files, or it is proving nothing")
	assert_eq(offenders, [],
		"every shipped text file must decode as UTF-8 — Godot does not "
		+ "fail on a stray Windows-1252 byte, it substitutes U+FFFD, so a "
		+ "player reads a replacement character and nothing goes red (#236)")


func test_the_civ_and_ai_prose_a_player_reads_is_clean() -> void:
	# The seven that were actually wrong, named so a regression in them is
	# reported as itself rather than as one line of a long list. Six civs
	# and one AI profile — every civ that ships.
	for path in ["res://ai/cautious.tres", "res://civs/emberdeep.tres",
			"res://civs/gildedreach.tres", "res://civs/gravesworn.tres",
			"res://civs/stoneblood.tres", "res://civs/thornwood.tres",
			"res://civs/windmarch.tres"]:
		var bytes := FileAccess.get_file_as_bytes(path)
		assert_false(bytes.is_empty(), "%s exists" % path)
		assert_eq(_first_bad_byte(bytes), -1, "%s decodes as UTF-8" % path)
		# And the text really did survive the fix, rather than the byte
		# being deleted: an em dash is three bytes of UTF-8.
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains(char(0xFFFD)),
			"%s holds no replacement character" % path)


func test_the_scan_would_notice_a_bad_byte() -> void:
	# The perturbation, in-process: a check nobody has seen fail is
	# vacuous by this project's law, and the natural way to break this one
	# is to write a bad file, which a test has no business doing to the
	# tree. So the DECODER is perturbed instead.
	var good := "summary = \"holds walls — and brings them down\"".to_utf8_buffer()
	assert_eq(_first_bad_byte(good), -1, "a real em dash is fine")

	var bad := PackedByteArray()
	bad.append_array("summary = \"holds walls ".to_utf8_buffer())
	bad.append(0x97)      # the Windows-1252 em dash, verbatim
	bad.append_array(" and brings them down\"".to_utf8_buffer())
	assert_eq(_first_bad_byte(bad), 23,
		"the byte that shipped in seven files is found, at its offset")

	# The other shapes a truncated or mangled paste takes.
	assert_ne(_first_bad_byte(PackedByteArray([0xC3])), -1,
		"a lead byte with no continuation")
	assert_ne(_first_bad_byte(PackedByteArray([0x80])), -1,
		"a continuation byte with no lead")
	assert_ne(_first_bad_byte(PackedByteArray([0xE2, 0x80])), -1,
		"two thirds of an em dash")
	assert_eq(_first_bad_byte(PackedByteArray([0xE2, 0x80, 0x94])), -1,
		"all three of one")


## The offset of the first byte that is not part of a valid UTF-8
## sequence, or -1.
##
## Written out rather than handed to `get_string_from_utf8`, which
## SUBSTITUTES rather than reporting — the very behaviour that let this
## ship. A checker that used it would be asserting against the thing it
## is meant to catch.
func _first_bad_byte(bytes: PackedByteArray) -> int:
	var i := 0
	var size := bytes.size()
	while i < size:
		var b := bytes[i]
		var length := 0
		if b < 0x80:
			length = 1
		elif b >= 0xC2 and b <= 0xDF:
			length = 2
		elif b >= 0xE0 and b <= 0xEF:
			length = 3
		elif b >= 0xF0 and b <= 0xF4:
			length = 4
		else:
			return i        # 0x80-0xC1 and 0xF5+ can never lead
		if i + length > size:
			return i
		for k in range(1, length):
			var continuation := bytes[i + k]
			if continuation < 0x80 or continuation > 0xBF:
				return i
		i += length
	return -1


func _text_files(root: String) -> Array:
	var out := []
	_walk(root, out)
	return out


func _walk(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or SKIP_DIRS.has(sub):
			continue
		_walk(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		var lower := normalised.to_lower()
		var binary := false
		for suffix in BINARY_SUFFIXES:
			if lower.ends_with(suffix):
				binary = true
				break
		if binary:
			continue
		for suffix in TEXT_SUFFIXES:
			if lower.ends_with(suffix):
				out.append(path.path_join(normalised))
				break
