extends GutTest

## Guards D-093 and #181: exactly ONE script names Steam, and absent Steam
## costs Steam features rather than the game.
##
## This is the falsifiable-by-grep pattern D-046 criterion 3 established
## (no script names a civ) and D-086 reused (no script builds its own
## lighting rig). It is this project's proven mechanism for keeping a rule
## true after everyone stops looking, and it is what lets D-021 — "GDScript
## only, no C#" — be amended by exactly one category without the amendment
## becoming a hole.
##
## ## The scan reads CODE, not prose, and that is not a loosening
##
## Three shipped files already contain the word: `client.gd` and
## `squad_sim.gd` describe a routed squad fleeing "under its own steam",
## and `net_protocol.gd` explains that "Steam's rolling updates make mixed
## versions routine" as the rationale for the protocol version. All three
## are correct and none of them calls anything. D-093's rule is about
## CALLS — an English word in a comment cannot reach Steamworks — so
## comment lines are stripped before the scan.
##
## The hole that leaves is a doc comment that LOOKS like a call, which is
## worth strictly less than the false positives the naive version would
## produce: a guard that fires on "under its own steam" is a guard people
## learn to edit rather than obey, and this project has already recorded
## exactly that failure once (#204's `--name "{{TARGET}}"`).

const BOUNDARY := "res://platform.gd"


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## `text` with every whole-line comment removed. Not a general GDScript
## parser and does not pretend to be — a trailing `# ...` on a line of
## code is left alone, which is the safe direction: it can only make the
## scan stricter.
func _code_only(text: String) -> String:
	var kept := PackedStringArray()
	for line in text.split("\n"):
		if not String(line).strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


## Every `.gd` this project owns. Deliberately not `addons/` — GUT is
## vendored and not ours to police.
func _project_scripts() -> PackedStringArray:
	var found := PackedStringArray()
	for name in DirAccess.get_files_at("res://"):
		if name.ends_with(".gd"):
			found.append("res://" + name)
	for name in DirAccess.get_files_at("res://tests"):
		if name.ends_with(".gd"):
			found.append("res://tests/" + name)
	return found


# --- one script names Steam --------------------------------------------

func test_only_the_boundary_names_steam() -> void:
	var offenders := PackedStringArray()
	for path in _project_scripts():
		if path == BOUNDARY or path == "res://tests/test_steam_boundary.gd":
			continue
		var code := _code_only(_read(path))
		if code.contains("Steam") or code.contains("GodotSteam") or code.contains("steamworks"):
			offenders.append(path)
	assert_eq(offenders, PackedStringArray(),
		("only %s may name Steam (D-093). These do: %s. Everything Steamworks "
		+ "reaches this project through the boundary, or D-021's amendment is a hole.")
		% [BOUNDARY, ", ".join(offenders)])


func test_the_boundary_exists_and_names_it_once() -> void:
	var code := _code_only(_read(BOUNDARY))
	assert_true(code.contains("SINGLETON := \"Steam\""),
		"the boundary must name the singleton in exactly one constant")
	# Every DETECTION and every CALL must go through that constant, never
	# through a literal of its own — the point of a boundary is that one
	# place decides what "Steam is present" means, rather than three call
	# sites each deciding for themselves.
	#
	# Deliberately not "the word appears once": #184 added
	# `display_name()`, which returns the word as USER-FACING PROSE so
	# that #187's lobby UI can put it on a button without naming it
	# itself. That is a second legitimate literal, and a count would have
	# forbidden it — the rule is about reaching Steamworks, not about the
	# word.
	for reach in ["Engine.has_singleton(", "ClassDB.class_exists(", "Engine.get_singleton("]:
		var at := code.find(reach)
		while at >= 0:
			var argument := code.substr(at + reach.length(), 12)
			assert_true(argument.begins_with("SINGLETON"),
				"%s must be called with SINGLETON, not a literal — found %s"
				% [reach, argument])
			at = code.find(reach, at + 1)


# --- absent Steam costs Steam, never the game --------------------------

func test_steam_is_absent_here_and_that_is_the_point() -> void:
	# D-094 criterion 7 asks for this to be ASSERTED rather than assumed.
	# Every automated context this repo has is Steam-less — docker, CI,
	# the bots, this suite — which is the right way round: the fallback is
	# the constantly-exercised path.
	assert_false(Platform.available(),
		"the test estate must run with no Steam present (D-093's fallback rule)")


func test_every_answer_is_safe_with_no_steam() -> void:
	# Not "does not crash" — that is what a stub would give. These are the
	# specific values the callers to come are entitled to rely on.
	assert_eq(Platform.steam_id(), 0,
		"absent Steam must report NO identity, never a made-up one: D-090 rebinds a "
		+ "seat by SteamID, and a seat rebound by a fabricated id is a seat anybody could claim")
	assert_eq(Platform.persona_name(), "",
		"and no name either")


func test_the_boundary_is_gated_on_availability_everywhere() -> void:
	# The failure this catches is a function that reaches for the
	# singleton without asking whether there is one — which crashes only
	# on the machines that have no Steam, i.e. every machine that runs
	# this suite, and none of the ones a Steam feature is developed on.
	var code := _code_only(_read(BOUNDARY))
	var singleton_uses := code.count("Engine.get_singleton(SINGLETON)")
	var guards := code.count("if not available():")
	assert_true(guards >= singleton_uses,
		"%d call(s) reach the Steam singleton but only %d guard on available()"
		% [singleton_uses, guards])


# --- the pin ------------------------------------------------------------

func test_the_godotsteam_version_is_pinned_beside_the_engine_version() -> void:
	# A mismatched pair fails at LOAD, not at build — on a player's
	# machine rather than on the builder's. So the pairing is written
	# down even though nothing enforces it yet.
	assert_true(FileAccess.file_exists("res://.godotsteam-version"),
		".godotsteam-version must exist beside .godot-version")
	assert_false(Platform.pinned_version().is_empty(),
		"and the boundary must be able to read it")


func test_doctor_reports_steam_without_requiring_it() -> void:
	# D-093's own consequence: "`just doctor` learns to report Steam
	# availability". Reported, never required — the same rule the art
	# tooling and the export templates are reported under.
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("godotsteam_version := `cat .godotsteam-version`"),
		"the pin doctor prints must be READ from .godotsteam-version, never typed into a recipe")
	var doctor := _recipe_body(justfile, "doctor:")
	assert_true(doctor.contains("{{godotsteam_version}}"),
		"doctor must print the pin")
	assert_true(doctor.contains("platform.gd"),
		"and must name the boundary as what decides availability, rather than deciding itself")
	# And it must not FAIL on absent Steam, which would make every
	# Steam-less context — that is, all of them — fail preflight.
	assert_false(doctor.to_lower().contains("fail: steam"),
		"absent Steam is not a preflight failure (D-093's fallback rule)")


func test_nothing_in_the_container_or_the_recipes_needs_steam() -> void:
	# "The entire existing test estate runs Steam-less by construction"
	# is D-093's claim; this is the check that it stays true as recipes
	# and images change.
	for path in ["res://Dockerfile", "res://docker-compose.yml"]:
		var text := _read(path)
		assert_false(text.to_lower().contains("steam"),
			"%s must not need Steam — docker has none and never will (D-093)" % path)


func _recipe_body(justfile: String, declaration: String) -> String:
	var body := ""
	var inside := false
	for raw in justfile.split("\n"):
		var line := String(raw).replace("\r", "")
		if not inside:
			if line.begins_with(declaration):
				inside = true
			continue
		if not line.is_empty() and not line.begins_with(" ") and not line.begins_with("\t"):
			break
		body += line + "\n"
	assert_true(inside, "no recipe declared as `%s` in the justfile" % declaration)
	return body
