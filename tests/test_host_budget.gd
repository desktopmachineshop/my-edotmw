extends GutTest

## Guards D-20260818-dev-work-is-admitted-against-a-host-budget: heavy dev
## work is admitted against a MEASURED memory budget before it runs, so
## several agents sharing one laptop queue instead of thrashing it.
##
## D-095 stopped agents COLLIDING. It did nothing about them STARVING each
## other, and the cost was already written down three times before it was
## named: "Docker Desktop dies under parallel agents" (user memory), M6's
## worst-tick figures discarded because "the host was building containers
## throughout", and terrain.md's bench-render absolute moving 52.1 ms to
## 181.1 ms on an unchanged build.
##
## These are text scans, in the style of test_multi_agent_isolation.gd and
## test_civs.gd's no-script-names-a-civ rule, for the same reason: the
## budget is only real if re-deriving it, or forgetting to declare a
## recipe's class, FAILS.
##
## What this file deliberately does NOT test is the gate's runtime
## behaviour — waiting, reaping, GPU exclusivity. That lives in bash, on a
## real filesystem, and asserting it from GDScript would mean a second
## implementation of the thing under test. It is exercised by
## `bash host-gate.sh` directly; see the decision's exit criteria 3-5.


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func _recipe_bodies() -> Dictionary:
	# name -> body text, for every recipe in the justfile. A recipe starts
	# at a line that begins in column 0 with its name; its body is the
	# indented block that follows.
	var out := {}
	var name_re := RegEx.new()
	name_re.compile("^([a-zA-Z_][a-zA-Z0-9_-]*)(\\s|:)")
	var current := ""
	var body := PackedStringArray()
	for line in _read("res://justfile").split("\n"):
		var m := name_re.search(line)
		if m != null:
			if current != "":
				out[current] = "\n".join(body)
			current = m.get_string(1)
			body = PackedStringArray()
		elif current != "":
			body.append(line)
	if current != "":
		out[current] = "\n".join(body)
	return out


func test_the_budget_has_exactly_one_definition() -> void:
	var budget := _read("res://host-budget.sh")
	assert_true(budget.contains("MemAvailable"),
		"host-budget.sh must prefer MemAvailable where the kernel publishes it")
	assert_true(budget.contains("EDOTMW_HOST_BUDGET_MB"),
		"host-budget.sh must honour the explicit override, as instance-id.sh does")

	# The D-095 rule, applied to memory: nothing else may decide how much
	# of this machine dev work gets. A second definition is how the
	# justfile and the client came to disagree about spawn_seed (D-104).
	var offenders := PackedStringArray()
	for path in ["res://justfile", "res://host-gate.sh", "res://instance-id.sh",
			"res://recipe-arg.sh", "res://bootstrap.ps1"]:
		var text := _read(path)
		if text.contains("MemAvailable") or text.contains("FreePhysicalMemory"):
			offenders.append(path)
	assert_eq(offenders.size(), 0,
		"only host-budget.sh may read the machine's memory — found: %s" % str(offenders))


func test_the_gate_charges_live_holders_rather_than_counting_jobs() -> void:
	# The adaptive form is the decision. A fixed job count was rejected on
	# a measurement: the resident floor moved 1.2 GB inside the profiling
	# hour while free memory fell ANYWAY, because the WSL VM absorbed what
	# was freed. Freed memory never became headroom.
	var budget := _read("res://host-budget.sh")
	assert_true(budget.contains("pool=$(( $(free_mb) + charged ))"),
		"admission must reconstruct the pool from free + charged, not read free alone")
	assert_true(budget.contains("need=$(( charged + cost ))"),
		"a job admitted but not yet grown into its memory must still be charged in full")

	var gate := _read("res://host-gate.sh")
	assert_true(gate.contains("cost_mb"),
		"a holder must record what it is charged, or the pool cannot be reconstructed")


func test_a_dead_holder_cannot_wedge_the_machine() -> void:
	var gate := _read("res://host-gate.sh")
	assert_true(gate.contains("kill -0"),
		"the reaper must key on process liveness — an agent killed mid-run must not hold a slot forever")
	assert_true(gate.contains("EDOTMW_GATE_HELD"),
		"a child recipe must inherit its parent's slot, or test-load deadlocks on its own `up`")
	assert_true(gate.contains("EDOTMW_NO_GATE"),
		"the gate must have a documented off switch — a wrong gate would otherwise stop all work")


func test_the_gate_does_not_touch_another_instances_containers() -> void:
	# D-095's hard rule survives: the gate coordinates, it does not clean
	# up after anybody. Its reaper deletes lock FILES and nothing else.
	var gate := _read("res://host-gate.sh")
	for forbidden in ["docker rm", "docker stop", "docker compose", "docker kill"]:
		assert_false(gate.contains(forbidden),
			"host-gate.sh must never run '%s' — that is D-095's line" % forbidden)


func test_every_recipe_that_runs_real_work_declares_a_class() -> void:
	# The uncalled-member family (CLAUDE.md's M6 lesson) says the gap will
	# be a recipe nobody remembered, not a wrong number: a new gen-* or
	# test-* recipe that skips the gate costs nothing visible and quietly
	# un-gates the machine. So the check is structural — if a body starts
	# a container or a Godot process, it must acquire.
	var exempt := ["_import", "down", "nuke", "doctor", "status", "host-status",
		"host-reap", "host-profile", "reap-orphans", "bootstrap", "bootstrap-art",
		"instance", "default", "scenarios", "replay-info", "build-resource-models"]
	var ungated := PackedStringArray()
	for name in _recipe_bodies():
		if exempt.has(name):
			continue
		var body: String = _recipe_bodies()[name]
		var runs_work := body.contains("docker compose") or body.contains("$godot") \
			or body.contains("{{native_godot}}")
		if runs_work and not body.contains("host-gate.sh acquire"):
			ungated.append(name)
	assert_eq(ungated.size(), 0,
		"these recipes run docker or Godot without declaring a host class: %s" % str(ungated))


func test_import_is_gated_only_when_it_actually_imports() -> void:
	# `_import` is a dependency of nearly everything and skips when nothing
	# changed. Acquiring at the top of it would make every filtered
	# unit-test run queue behind another agent's load test for no reason,
	# so the acquire sits AFTER the skip.
	var body: String = _recipe_bodies().get("_import", "")
	assert_true(body.contains("host-gate.sh acquire"),
		"_import runs Godot, so it must be gated when it does")
	var skip_at := body.find("import: skipped")
	var gate_at := body.find("host-gate.sh acquire")
	assert_true(skip_at >= 0 and gate_at > skip_at,
		"the acquire must come AFTER the skip, or a no-op import waits on the whole machine")


func test_a_gated_recipe_releases_on_every_exit_path() -> void:
	# A trap REPLACES rather than appends in bash, so a recipe that already
	# tore down containers on EXIT and then set a second trap for the gate
	# would silently lose its teardown. The six recipes with their own trap
	# fold the release into it instead; everything else sets its own.
	var missing := PackedStringArray()
	for name in _recipe_bodies():
		var body: String = _recipe_bodies()[name]
		if not body.contains("host-gate.sh acquire"):
			continue
		if not body.contains("host-gate.sh release"):
			missing.append(name)
	assert_eq(missing.size(), 0,
		"these recipes acquire a slot and never release it: %s" % str(missing))

	# Two EXIT traps in ONE recipe body: the second wins and the first is
	# silently lost. This has to be counted per body — a regex over the
	# whole justfile matches two DIFFERENT recipes each holding one trap,
	# which is correct and would fail the check. (Observed: it did.)
	var doubled := PackedStringArray()
	for name in _recipe_bodies():
		var body: String = _recipe_bodies()[name]
		if body.count("' EXIT INT TERM") > 1:
			doubled.append(name)
	assert_eq(doubled.size(), 0,
		"these recipes set two EXIT traps; bash keeps only the last: %s" % str(doubled))
