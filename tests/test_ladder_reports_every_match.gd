extends GutTest

## Guards #224 — `just ai-ladder` must report every match it was ASKED
## for, and a decided match must stop rather than simulate its winner
## against nobody for the rest of the cap.
##
## Two halves, and they are guarded two different ways for the reason
## D-107's entry gives about this recipe: it is the harness the project
## most depends on for "is the AI any good", and it spent three
## milestones answering that question about matches that were never
## played. D-107 made it assert that matches START. Nothing asserted they
## END — so a run of three in which one match died mid-way reported
## `decided: 2 of 2`, a denominator counted from the survivors, in which
## a vanished match cannot appear by construction.
##
##   - the STOP rule is arithmetic and lives in `Server.stop_reason`,
##     pure and static, so it is tested here directly. It sits inside
##     `_process`, which needs a scene tree, a socket and a world; the
##     part with the behaviour is four floats
##     (`docs/status/civ-knobs.md`'s "that is true of `_ready()`, not of
##     the file", and D-106's "when a rule cannot be tested where it
##     lives, that is a fact about where it lives");
##   - the RECIPE half is a source scan, because the alternative is
##     executing `just ai-ladder`, which is a heavy multi-minute run.
##     A scan is what D-106's caller-exists test does, with the same
##     caveat it carries: it only covers what it names.

const RECIPE := "res://justfile"

## `server.gd` declares no `class_name`, so the static is reached through
## the script object — the same way `test_buildings.gd` reaches the rest
## of the server.
var _server := load("res://server.gd")


func _justfile() -> String:
	var handle := FileAccess.open(RECIPE, FileAccess.READ)
	assert_not_null(handle, "the justfile must be readable")
	if handle == null:
		return ""
	return handle.get_as_text()


## The ai-ladder recipe body, so a scan cannot be satisfied by a line in
## `test-ai-teams` — which has its own started-check and is not what #224
## is about. Ends at the next recipe, i.e. the next line starting in
## column zero that is not blank or a comment.
func _ladder_recipe() -> String:
	var text := _justfile()
	var start := text.find("\nai-ladder ")
	assert_true(start >= 0, "the justfile no longer has an `ai-ladder` recipe")
	if start < 0:
		return ""
	var body := text.substr(start + 1)
	var lines := body.split("\n")
	var out := PackedStringArray()
	for i in range(lines.size()):
		var line := lines[i]
		if i > 0 and line != "" and not line.begins_with(" ") \
				and not line.begins_with("\t") and not line.begins_with("#"):
			break
		out.append(line)
	return "\n".join(out)


# --- the recipe reports every match it was asked for -------------------

func test_the_ladder_asserts_matches_FINISHED_not_merely_started() -> void:
	# The started-check has been there since D-107. This is its mirror,
	# and its absence is the whole of #224.
	var recipe := _ladder_recipe()
	assert_true(recipe.contains("server: MATCH_RESULT"),
		"the ladder must count MATCH_RESULT lines — a match that started and "
		+ "then died prints none, and nothing else in the recipe can see that")
	assert_true(recipe.contains("$finished") and recipe.contains("{{MATCHES}} - finished"),
		"the ladder must compare results against the matches ASKED for and say how many vanished")


func test_the_ladder_keeps_the_exit_status_of_every_server_it_runs() -> void:
	# `|| true` discarded it, so a server killed from outside — which is
	# how #224's missing match probably died — left no trace anywhere.
	var recipe := _ladder_recipe()
	assert_false(recipe.contains('>> "$log" 2>&1 || true'),
		"the ladder still throws away the server's exit status with `|| true`")
	assert_true(recipe.contains("status=$?") and recipe.contains("died="),
		"the ladder must record which seeds exited non-zero, or a failure cannot name them")


func test_the_reported_denominator_is_what_was_asked_for() -> void:
	# `decided: %d of %d ... matches - draws, matches` is self-referential:
	# `matches` counts MATCH_RESULT lines, so the denominator is the number
	# of matches that survived and a lost match is invisible in it.
	var recipe := _ladder_recipe()
	assert_true(recipe.contains("asked={{MATCHES}}"),
		"the awk must be handed the number of matches ASKED for")
	assert_true(recipe.contains("matches - draws, asked, draws"),
		"the `decided: N of M` line must divide by the asked-for count, not by the survivors")
	# gawk reads `-v` only BEFORE the program text; after it, `-v` is a
	# FILENAME. This cost a rerun, so it is pinned.
	assert_true(recipe.contains("awk -v asked={{MATCHES}} '"),
		"`-v` must precede the awk program, or awk tries to open a file called `-v`")


# --- a decided match stops (server.gd stop_reason) ---------------------

func test_a_decided_match_stops_without_running_out_the_cap() -> void:
	# #224's second half, in its own numbers: match over at 95 s of a
	# 600 s cap, and 505 further seconds were simulated.
	assert_eq(_server.stop_reason(96.0, 600.0, 95.0, 5.0), "",
		"one second after the win is not five — it must keep going")
	assert_ne(_server.stop_reason(100.0, 600.0, 95.0, 5.0), "",
		"five seconds after the win, a ladder match must stop rather than simulate 500 more")
	assert_true(_server.stop_reason(100.0, 600.0, 95.0, 5.0).contains("match decided"),
		"and it must say WHY it stopped, or the log reads like a truncated run")


func test_a_match_still_running_stops_only_on_the_cap() -> void:
	assert_eq(_server.stop_reason(300.0, 600.0, -1.0, 5.0), "",
		"an undecided match must run to its cap")
	assert_true(_server.stop_reason(600.0, 600.0, -1.0, 5.0).contains("reached"),
		"an undecided match must still stop at the cap")


func test_every_other_harness_measures_the_window_it_always_did() -> void:
	# `--stop-after-match` is opt-in and negative by default. This is the
	# clause that keeps `test-load`, `test-scenario` and `test-ai-teams`
	# comparable with every number recorded before #224 — the standing
	# "when the opening changes, every timing tuned against the old one is
	# stale" rule, avoided rather than paid.
	assert_eq(_server.stop_reason(300.0, 600.0, 95.0, -1.0), "",
		"a harness that does not opt in must not stop early just because the match ended")
	assert_true(_server.stop_reason(600.0, 600.0, 95.0, -1.0).contains("reached"),
		"and it must still stop at its cap")


func test_a_player_hosted_server_never_stops_by_itself() -> void:
	# No `--run-seconds` and no `--stop-after-match`: a human sitting in
	# the victory screen must not have the server quit out from under
	# them. That is this change escaping the harness it was written for,
	# and it is the reason the flag is opt-in rather than the behaviour
	# being changed for everyone.
	assert_eq(_server.stop_reason(0.0, -1.0, -1.0, -1.0), "")
	assert_eq(_server.stop_reason(9999.0, -1.0, 95.0, -1.0), "",
		"a decided match on a player-hosted server must keep running")


func test_the_match_clause_outranks_the_cap_and_says_so() -> void:
	# Both conditions true at once: the message must name the match, not
	# the cap, or a ladder log reports every early finish as a timeout —
	# which is exactly the vocabulary confusion D-107 was written about.
	var reason: String = _server.stop_reason(600.0, 600.0, 95.0, 5.0)
	assert_true(reason.contains("match decided"),
		"a decided match that also reached its cap reported: %s" % reason)
