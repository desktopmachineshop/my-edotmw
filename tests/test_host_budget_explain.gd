extends GutTest

## Guards that a refusal EXPLAINS the comparison it actually made (#254).
##
## `fits()` decides on `pool - reserve >= need`. `explain()` printed
## `pool` with the reserve NOT taken off, so a refusal read, verbatim:
##
##   not enough memory: free=2268MB charged=4100MB reserve=768MB
##                      pool=6370MB need=5600MB
##
## `pool=6370` against `need=5600` says there is room and the gate refused
## anyway. The real comparison is `6370 - 768 = 5602 >= 5600`, which
## passes by 2 MB. The message was RIGHT and its presentation was not, and
## it cost the reporter a whole diagnosis concluding the gate was broken.
##
## Same family as this project's other reporting defects: a number that is
## correct and labelled as something it is not. The fix prints the value
## the comparison uses, and keeps free/charged/reserve beside it so
## nothing is hidden.
##
## Executed rather than scanned, because the defect is ARITHMETIC — a
## source scan asserting "the string contains a minus sign" would be a
## guard that cannot see the bug it is named after.
##
## Needs a POSIX shell: under `EDOTMW_RUNTIME=native` on Windows, Godot's
## `OS.execute("bash", …)` resolves to the WSL relay and cannot see the
## Windows path. Run the suite through `just test-unit` (docker), where
## this passes — the same known gap `test_gate_checks.gd` carries.

const BUDGET := "host-budget.sh"


func _bash(line: String) -> Dictionary:
	for shell in ["/bin/bash", "bash", "/usr/bin/bash"]:
		var out := []
		var code := OS.execute(shell, ["-c", line], out, true)
		if code != -1:
			return {"code": code, "out": "\n".join(PackedStringArray(out)).strip_edges()}
	return {"code": -1, "out": ""}


## Run host-budget.sh with the machine's memory and the reserve PINNED, so
## the arithmetic is deterministic and does not depend on what else is
## running on the host — which is the whole point of those two overrides.
func _budget(args: String, free_mb: int, reserve_mb: int) -> Dictionary:
	var dir := ProjectSettings.globalize_path("res://")
	return _bash("cd '%s' && EDOTMW_HOST_BUDGET_MB=%d EDOTMW_HOST_RESERVE_MB=%d bash %s %s"
		% [dir, free_mb, reserve_mb, BUDGET, args])


func _skip_without_bash() -> bool:
	var probe := _bash("echo ok")
	if int(probe["code"]) != 0 or not String(probe["out"]).contains("ok"):
		pass_test("this file needs a POSIX shell — run the suite through `just test-unit` (docker)")
		return true
	return false


func _number_after(text: String, key: String) -> int:
	var re := RegEx.new()
	re.compile("%s=(-?[0-9]+)MB" % key)
	var hit := re.search(text)
	return int(hit.get_string(1)) if hit != null else -999999


func test_the_number_explain_prints_is_the_number_fits_compares() -> void:
	# THE defect, as an equation rather than as a string. Swept across the
	# boundary so the check cannot pass by luck on one lucky pair.
	if _skip_without_bash():
		return
	var cost := int(String(_budget("cost medium", 4000, 768)["out"]))
	assert_gt(cost, 0, "setup: `medium` must cost something")

	var checked := 0
	for free_mb in [1000, 1500, 2000, 2500, 3000, 4000, 6000]:
		for charged in [0, 1300, 2600]:
			var reserve := 768
			var fits := int(_budget("fits medium %d" % charged, free_mb, reserve)["code"]) == 0
			var text := String(_budget("explain medium %d" % charged, free_mb, reserve)["out"])
			assert_ne(text, "", "explain must say something")

			var available := _number_after(text, "available")
			var need := _number_after(text, "need")
			assert_ne(available, -999999,
				"explain must print the value actually compared, as `available` — got: %s" % text)
			assert_ne(need, -999999, "explain must print `need` — got: %s" % text)

			# The claim: reading the printed line the way a human reads it
			# gives the same verdict the gate reached.
			assert_eq(available >= need, fits,
				("explain says available=%d need=%d (so %s) while fits says %s "
				+ "— free=%d charged=%d reserve=%d. THIS is the defect: a "
				+ "refusal that reads as arithmetic which should have passed.")
					% [available, need, "ROOM" if available >= need else "no room",
						"ROOM" if fits else "no room", free_mb, charged, reserve])
			checked += 1
	assert_gt(checked, 10, "the sweep must actually have run")


func test_the_sweep_straddles_the_boundary() -> void:
	# A sweep that never changes its answer proves nothing — it would pass
	# with `fits` hardwired to true. Both verdicts must appear in it.
	if _skip_without_bash():
		return
	var seen_room := false
	var seen_refusal := false
	for free_mb in [1000, 1500, 2000, 2500, 3000, 4000, 6000]:
		for charged in [0, 1300, 2600]:
			if int(_budget("fits medium %d" % charged, free_mb, 768)["code"]) == 0:
				seen_room = true
			else:
				seen_refusal = true
	assert_true(seen_room, "setup: some pair in the sweep must be admitted")
	assert_true(seen_refusal, "setup: some pair in the sweep must be refused")


func test_the_parts_are_still_shown() -> void:
	# `available` alone would hide WHY. The reserve is the term that was
	# invisible in the comparison; it must stay visible in the message, or
	# the fix trades one unreadable line for another.
	if _skip_without_bash():
		return
	var text := String(_budget("explain medium 1300", 2000, 768)["out"])
	for part in ["free=", "charged=", "reserve=", "available=", "need="]:
		assert_true(text.contains(part),
			"a refusal must still show %s — got: %s" % [part, text])
