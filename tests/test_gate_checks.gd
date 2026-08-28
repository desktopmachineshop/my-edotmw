extends GutTest

## Guards D-20260818-the-fast-loop-carries-the-gate (#112): every log
## comparison `just test-load` makes, `just test-scenario` makes too.
##
## `test-load` costs five minutes a run on the current default map, so
## the loop anybody iterates in is `test-scenario` (~25 s). That is only
## honest if the fast loop proves what the gate proves minus the opening
## it deliberately skips — and it did not. `test-scenario`'s header says
## "the checks follow test-load's shape"; of test-load's four it had
## copied one. Fog gating of squads, fog gating of resource positions and
## both civilisations fielding something were asserted by the five-minute
## recipe alone, which in practice means by nothing anybody ran.
##
## Two halves, and the second is the one with teeth:
##
##   - the checks are a plain script, so this file can EXECUTE
##     gate-check.sh and watch it reject a bad run — the same reason
##     recipe-arg.sh and instance-id.sh are scripts rather than recipe
##     bodies, which the test estate cannot reach at all;
##   - and a scan asserting the CALLER exists in both recipes, which is
##     D-106's rule written down as a test. Every execution test below
##     would still pass with the fast loop calling none of them.


func _bash(line: String) -> Dictionary:
	for shell in ["/bin/bash", "bash", "/usr/bin/bash"]:
		var out := []
		var code := OS.execute(shell, ["-c", line], out, true)
		if code != -1:
			return {"code": code, "out": "\n".join(PackedStringArray(out))}
	return {"code": -1, "out": ""}


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## Writes a throwaway log and returns its absolute path.
func _log(name: String, body: String) -> String:
	var path := "user://gate-check-%s.log" % name
	var handle := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(handle, "could not write the fixture log %s" % path)
	if handle != null:
		handle.store_string(body)
		handle.close()
	return ProjectSettings.globalize_path(path)


func _check(args: Array) -> Dictionary:
	var quoted := PackedStringArray()
	for arg in args:
		quoted.append("'%s'" % str(arg))
	return _bash("bash '%s' %s" % [
		ProjectSettings.globalize_path("res://gate-check.sh"), " ".join(quoted)])


func before_all() -> void:
	# A shell that cannot be started would make every execution test here
	# pass vacuously, which is the one failure mode this project has paid
	# for repeatedly. Fail loudly instead.
	var probe := _bash("echo alive")
	assert_eq(probe["code"], 0,
		"this file needs a POSIX shell — run the suite through `just test-unit` (docker)")


# --- the comparisons themselves ---------------------------------------

func test_a_gated_run_passes_and_says_what_it_proved() -> void:
	# The numbers are a real `test-scenario siege 4 15` run.
	var bots := _log("ok-bots", "known_squads_max=11 nodes_known_max=128\n")
	var server := _log("ok-server",
		"FOG_TOTAL_SQUADS=32\nFOG_TOTAL_NODES=7694\nCIVS_FIELDED 2 of 2 — stoneblood=16, gravesworn=16\n")

	var result := _check(["fog-squads", bots, server])
	assert_eq(result["code"], 0, "a gated run must pass: %s" % result["out"])
	assert_true(str(result["out"]).contains("known_squads_max=11"),
		"the pass must quote what it compared, not merely say ok: %s" % result["out"])

	assert_eq(_check(["fog-nodes", bots, server])["code"], 0, "resource gating must pass")
	assert_eq(_check(["civs", server])["code"], 0, "two civs fielded must pass")


func test_an_ungated_run_fails() -> void:
	# The regression this exists to catch is M1's own visible_to() stub:
	# a client that knows every squad the server simulates.
	var bots := _log("open-bots", "known_squads_max=32 nodes_known_max=7694\n")
	var server := _log("open-server", "FOG_TOTAL_SQUADS=32\nFOG_TOTAL_NODES=7694\n")

	assert_eq(_check(["fog-squads", bots, server])["code"], 1,
		"knowing every simulated squad is not fog gating anything")
	assert_eq(_check(["fog-nodes", bots, server])["code"], 1,
		"knowing every resource node is D-061's leak, not a pass")


func test_one_civ_fails() -> void:
	var server := _log("one-civ", "CIVS_FIELDED 1 of 2 — stoneblood=32\n")
	assert_eq(_check(["civs", server])["code"], 1,
		"a match in which one roster never played must fail (D-046 criterion 10)")


func test_a_missing_marker_is_a_failure_not_a_skip() -> void:
	# The whole point. A comparison that finds nothing to compare and
	# says nothing is indistinguishable from one that passed — the
	# vacuous-pass shape D-022's audit block was written against, and the
	# reason `test-load`'s verdict fails when zero hash checks ran.
	var quiet := _log("quiet", "nothing structured in here at all\n")
	var server := _log("totals", "FOG_TOTAL_SQUADS=32\nFOG_TOTAL_NODES=7694\n")

	assert_eq(_check(["fog-squads", quiet, server])["code"], 1,
		"no known_squads_max means the comparison never ran")
	assert_eq(_check(["fog-squads", server, quiet])["code"], 1,
		"no FOG_TOTAL_SQUADS means the comparison never ran")
	assert_eq(_check(["fog-nodes", quiet, server])["code"], 1,
		"no nodes_known_max means the comparison never ran")
	assert_eq(_check(["civs", quiet])["code"], 1,
		"no CIVS_FIELDED marker means the comparison never ran")


func test_misusing_the_checker_is_its_own_exit_code() -> void:
	# 2, not 1: a recipe calling this wrongly is a bug in the recipe and
	# must not read as "the run under test was bad". Same split as
	# recipe-arg.sh.
	assert_eq(_check(["fog-squads"])["code"], 2, "too few arguments is a misuse")
	assert_eq(_check(["what", "a", "b"])["code"], 2, "an unknown check is a misuse")


# --- the checks actually being called, in BOTH recipes ----------------

## The body of one recipe, as text. A recipe ends at the next line that
## starts in column 0 and is not blank — comments included, since a
## recipe's own trailing comment belongs to whatever comes after it.
func _recipe_body(justfile: String, declaration: String) -> String:
	var lines := justfile.split("\n")
	var body := ""
	var inside := false
	for raw in lines:
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


## Which gate-check.sh checks a recipe body runs.
##
## The INVOCATION, not the name: `bash gate-check.sh <check>`. Matching
## the filename alone picked the word after it out of the prose comment
## above the calls, which would fail this file for a reason that is not
## the one it is about.
func _checks_in(body: String) -> Array:
	var re := RegEx.new()
	re.compile("bash gate-check\\.sh ([a-z-]+)")
	var found: Array = []
	for m in re.search_all(body):
		var name := m.get_string(1)
		if not found.has(name):
			found.append(name)
	found.sort()
	return found


func test_the_fast_loop_makes_every_check_the_gate_makes() -> void:
	var justfile := _read("res://justfile")
	var gate := _checks_in(_recipe_body(justfile, "test-load "))
	var loop := _checks_in(_recipe_body(justfile, "test-scenario "))

	assert_gt(gate.size(), 0,
		"`test-load` runs no gate-check.sh check at all — the gate has lost its comparisons")
	for check in gate:
		assert_true(loop.has(check),
			("`test-load` checks '%s' and `test-scenario` does not. The fast loop is the one "
			+ "people run between gate runs; a property only the five-minute recipe asserts is "
			+ "one nothing asserts (#112).") % check)


func test_neither_recipe_reimplements_a_shared_comparison() -> void:
	# Drift back is the failure mode: a copy inline in one recipe passes
	# the test above while the two answers diverge. The markers belong to
	# gate-check.sh alone.
	var justfile := _read("res://justfile")
	for marker in ["FOG_TOTAL_SQUADS", "FOG_TOTAL_NODES", "CIVS_FIELDED",
			"known_squads_max", "nodes_known_max"]:
		# Naming a marker in a comment is fine; GREPPING for it is the
		# copy. Reading one is what the recipes must not do themselves.
		# `.` does not match a newline in Godot's RegEx, so this cannot
		# reach across lines into an unrelated recipe.
		var re := RegEx.new()
		re.compile("grep.*%s" % marker)
		assert_null(re.search(justfile),
			("the justfile greps %s itself — that comparison lives in gate-check.sh, "
			+ "so both recipes get the same answer") % marker)
	var script := _read("res://gate-check.sh")
	for marker in ["FOG_TOTAL_SQUADS", "FOG_TOTAL_NODES", "CIVS_FIELDED",
			"known_squads_max", "nodes_known_max"]:
		assert_true(script.contains(marker),
			"gate-check.sh must be the one place %s is read" % marker)


# --- the naval gate's skip is TOPOLOGY, not the AI's answer ------------
#
# #351: `wants_navy=0` is reported both by an AI that correctly declined
# to sail (every enemy walkable) and by an AI that declined to sail on an
# archipelago, which is the defect. Keying the skip on it lets the thing
# under test excuse itself from the test. SEAT_LANDMASSES is the map's
# own answer, and these pin that the gate reads it.

func test_the_naval_gate_skips_when_the_starts_share_one_landmass() -> void:
	var server := _log("naval-one-island",
		"SEAT_LANDMASSES seats=8 landmasses=1 sea_components=1
"
		+ "AI_STATS wants_navy=0 docks=0 ships_peak=0 embarks=0 landings=0\n")
	var got := _check(["naval", server])
	assert_eq(got["code"], 0,
		"one landmass means no crossing was available, so zero landings is correct")
	assert_string_contains(got["out"], "one landmass")


func test_the_naval_gate_fails_when_a_crossing_was_available_and_declined() -> void:
	# The #351 run. Byte-identical to the skip above except the topology.
	var server := _log("naval-archipelago",
		"SEAT_LANDMASSES seats=8 landmasses=3 sea_components=1
"
		+ "AI_STATS wants_navy=0 docks=0 ships_peak=0 embarks=0 landings=0\n")
	var got := _check(["naval", server])
	assert_ne(got["code"], 0,
		"an AI that cannot walk to its enemy and declines to sail is #351, not a skip")
	assert_string_contains(got["out"], "#351")


func test_the_naval_gate_refuses_to_skip_without_the_topology() -> void:
	# An older server, or one whose marker regressed, must not buy a free
	# pass. A skip nobody can justify is the vacuous skip this exists to
	# prevent — so absence fails rather than defaulting to "land map".
	var server := _log("naval-no-marker",
		"AI_STATS wants_navy=0 docks=0 ships_peak=0 embarks=0 landings=0\n")
	var got := _check(["naval", server])
	assert_ne(got["code"], 0, "no topology means no earned skip")
	assert_string_contains(got["out"], "SEAT_LANDMASSES")


func test_the_naval_gate_still_names_the_first_missing_leg() -> void:
	# The ordered vacuity ladder survives the topology gate in front of
	# it: a run that wanted a navy and built no dock must still say so,
	# rather than being swallowed by the new branch.
	var server := _log("naval-no-dock",
		"SEAT_LANDMASSES seats=8 landmasses=3 sea_components=1
"
		+ "AI_STATS wants_navy=1 docks=0 ships_peak=0 embarks=0 landings=0\n")
	var got := _check(["naval", server])
	assert_ne(got["code"], 0, "a wanted navy with no dock is still a failure")
	assert_string_contains(got["out"], "no dock was ever built")


func test_the_naval_gate_passes_on_a_landing() -> void:
	var server := _log("naval-landing",
		"SEAT_LANDMASSES seats=8 landmasses=3 sea_components=1
"
		+ "AI_STATS wants_navy=1 docks=1 ships_peak=1 embarks=1 landings=1\n")
	var got := _check(["naval", server])
	assert_eq(got["code"], 0, "a landing on an archipelago is the pass")
	assert_string_contains(got["out"], "a landing happened")


func test_the_server_prints_the_topology_the_gate_reads() -> void:
	# D-106's caller-exists rule. Every test above would pass with
	# `server.gd` printing no marker at all — and then every real run
	# would fail on the absent-marker branch, which is safe but useless.
	# This is the half that says the two ends are joined.
	#
	# The KEYS, not the marker's name: `gate-check.sh` greps `landmasses=`
	# and `sea_components=`, so those are what must exist. Asserting the
	# banner would pass while the numbers behind it were renamed.
	var source := _read("res://server.gd")
	assert_string_contains(source, "landmasses=%d",
		"server.gd must print the landmass count the naval gate keys on")
	assert_string_contains(source, "sea_components=%d",
		"and the sea-component count, which is what makes a crossing "
		+ "SUFFICIENT rather than merely required")


func test_there_is_one_topology_marker_and_not_two() -> void:
	# Worker 88's SEAT_LANDMASSES superseded a SPAWN_LANDMASSES this file
	# briefly keyed on. Two markers answering one question is the shape
	# this project keeps paying for — they agree until they do not, and
	# the gate reads whichever it was written against.
	var source := _read("res://server.gd")
	assert_false(source.contains("SPAWN_LANDMASSES"),
		"the superseded marker must be gone, not merely unread")
	var gate := _read("res://gate-check.sh")
	assert_false(gate.contains("SPAWN_LANDMASSES"),
		"and the gate must not still be looking for it")


func test_the_naval_gate_reads_the_best_seat_not_the_last_one() -> void:
	# A real isles run reported wants_navy=1 for seat 1000 and 0 for seat
	# 1001, and the gate declared that NO seat wanted a navy — because
	# `marker` takes the last occurrence, which is right for a marker
	# printed once a match and silently wrong for one printed once a
	# player. It would have masked the dock failure underneath with a
	# #351 report that was not true, which is a gate lying in the
	# direction of the defect it exists to find.
	var server := _log("naval-two-seats",
		"SEAT_LANDMASSES seats=8 landmasses=3 sea_components=1
"
		+ "AI_STATS player=1000 wants_navy=1 docks=1 ships_peak=1 embarks=1 landings=1\n"
		+ "AI_STATS player=1001 wants_navy=0 docks=0 ships_peak=0 embarks=0 landings=0\n")
	var got := _check(["naval", server])
	assert_eq(got["code"], 0,
		"one seat crossing is a landing, whatever the other seat did")
	assert_string_contains(got["out"], "a landing happened")


func test_a_seat_that_wanted_a_navy_is_not_erased_by_a_seat_that_did_not() -> void:
	# The same defect pointed at the ordered ladder rather than at the
	# skip: the gate must name the leg the keenest seat stopped at, not
	# the one the last-printed seat never started.
	var server := _log("naval-wanted-no-dock",
		"SEAT_LANDMASSES seats=8 landmasses=3 sea_components=1
"
		+ "AI_STATS player=1000 wants_navy=1 docks=0 ships_peak=0 embarks=0 landings=0\n"
		+ "AI_STATS player=1001 wants_navy=0 docks=0 ships_peak=0 embarks=0 landings=0\n")
	var got := _check(["naval", server])
	assert_ne(got["code"], 0, "a wanted navy with no dock is a failure")
	assert_string_contains(got["out"], "no dock was ever built")


func test_a_log_with_a_stray_byte_is_still_read_and_never_falsely_passes() -> void:
	# A FALSE GREEN, found by accident on a real ai-ladder log.
	#
	# `grep` prints "Binary file <path> matches" INSTEAD OF THE MATCHES
	# when its input is not text, and one stray byte — a crash dump, a
	# truncated write, an engine backtrace — is enough. Every `[ ... -eq
	# ]` downstream then failed with "integer expected", and because a
	# failed test is not a failed script, the gate ran on to its success
	# line and exited 0. It reported "a landing happened" on a match with
	# no dock in it.
	#
	# A gate that reports a pass on a log it cannot read is worse than no
	# gate at all, which is why this is fixed twice over: `grep -a` keeps
	# the output text, and `require_number` refuses anything that is not
	# digits.
	var path := "user://gate-check-binary.log"
	var handle := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(handle, "could not write the binary fixture")
	if handle == null:
		return
	handle.store_string(
		"SEAT_LANDMASSES seats=8 landmasses=3 sea_components=1\n"
		+ "AI_STATS wants_navy=1 docks=0 ships_peak=0 embarks=0 landings=0\n")
	handle.store_8(0)
	handle.store_8(1)
	handle.store_string("engine backtrace\n")
	handle.close()

	var got := _check(["naval", ProjectSettings.globalize_path(path)])
	assert_ne(got["code"], 0,
		"a run with no dock must fail even when the log carries a stray "
		+ "byte — the gate may not pass because it could not read")
	assert_string_contains(got["out"], "no dock was ever built",
		"and it must still name the leg, rather than failing vaguely")
