extends GutTest

## Guards D-20260817-recipe-args-are-positional (#89): a recipe argument
## `just` could not use must FAIL, not be swallowed.
##
## `just` takes recipe arguments positionally, so `NAME=value` after a
## recipe name binds the whole string to the recipe's FIRST parameter.
## Every consumer then reads it with `int()`, which is 0 for anything it
## cannot parse — so `just quick-test SANDBOX=1` launched with
## `--seed=SANDBOX=1` (seed 0, sandbox off) and `just run-server AI=3`
## seated zero opponents, both silently, both prescribed by this
## project's own docs.
##
## Unlike test_multi_agent_isolation.gd's scans, most of this file
## EXECUTES the scripts under test: recipe-arg.sh and instance-id.sh are
## plain shell precisely so a GUT test can watch them reject a bad value
## rather than assert that some text is present in the justfile. The one
## scan here is the "assert the caller exists" check D-106 wrote down —
## a guard nothing calls is the defect it is guarding against.


## Runs a line of shell and returns {"code": int, "out": String}.
## Tries the shells in the order the runtimes provide them: /bin/bash in
## the container (the supported way to run this suite), then whatever
## `bash` PATH resolves to on a native run.
func _bash(line: String) -> Dictionary:
	for shell in ["/bin/bash", "bash", "/usr/bin/bash"]:
		var out := []
		var code := OS.execute(shell, ["-c", line], out, true)
		if code != -1:
			return {"code": code, "out": "\n".join(PackedStringArray(out))}
	return {"code": -1, "out": ""}


func _script(name: String) -> String:
	return ProjectSettings.globalize_path("res://%s" % name)


## `bash recipe-arg.sh <args>` with every argument single-quoted.
func _check(args: Array) -> Dictionary:
	var quoted := PackedStringArray()
	for arg in args:
		quoted.append("'%s'" % str(arg))
	return _bash("bash '%s' %s" % [_script("recipe-arg.sh"), " ".join(quoted)])


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func before_all() -> void:
	# A shell that cannot be started would make every execution test
	# below pass vacuously, which is the one failure mode this project
	# has paid for repeatedly. Fail loudly instead.
	var probe := _bash("echo alive")
	assert_eq(probe["code"], 0,
		"this file needs a POSIX shell — run the suite through `just test-unit` (docker)")


# --- the value that used to be swallowed ------------------------------

func test_a_name_equals_value_argument_is_rejected() -> void:
	# The exact invocation CLAUDE.md prescribed: `just quick-test
	# SANDBOX=1`, which binds "SANDBOX=1" to SEED.
	var result := _check(["int", "SEED", "SANDBOX=1"])
	assert_eq(result["code"], 1, "SEED=\"SANDBOX=1\" must fail the recipe")
	assert_true(str(result["out"]).contains("POSITIONALLY"),
		"the failure must name the trap, not merely reject the value: %s" % result["out"])

	# And the sibling found while fixing it: `just run-server AI=3`.
	result = _check(["int", "AI", "AI=3"])
	assert_eq(result["code"], 1, "AI=\"AI=3\" must fail the recipe")


func test_usable_values_pass_silently() -> void:
	for case in [["int", "SEED", "1337"], ["int", "DURATION", "-1"],
			["int", "N", "0"], ["num", "SECONDS", "0.6"],
			["num", "HEIGHT", "14"], ["enum", "SANDBOX", "auto", "0", "1", "auto"],
			["enum", "LOBBY", "0", "0", "1"]]:
		var result := _check(case)
		assert_eq(result["code"], 0, "%s must be accepted" % [case])
		assert_eq(str(result["out"]).strip_edges(), "",
			"an accepted value must print nothing: %s" % result["out"])


func test_unusable_values_fail() -> void:
	for case in [["int", "SEED", ""], ["int", "SEED", "1.5"],
			["int", "SEED", "twelve"], ["num", "SECONDS", "1.2.3"],
			["num", "SECONDS", "-"], ["enum", "SANDBOX", "yes", "0", "1", "auto"]]:
		var result := _check(case)
		assert_eq(result["code"], 1, "%s must be rejected" % [case])


func test_misusing_the_checker_is_its_own_exit_code() -> void:
	# 2, not 1: a recipe calling this wrongly is a bug in the recipe, and
	# must not read as "the user typed something bad".
	assert_eq(_check(["int", "SEED"])["code"], 2, "too few arguments is a misuse")
	assert_eq(_check(["float", "SEED", "1"])["code"], 2, "an unknown kind is a misuse")


# --- the guard actually being called ----------------------------------

## Splits a recipe declaration line into (name, parameter tokens), or
## returns an empty array if the line is not a recipe declaration.
## The colon that ends the parameter list is the first one OUTSIDE
## quotes — `MAP="res://maps/default.tres"` contains two of its own.
func _declaration(line: String) -> Array:
	if line.is_empty() or line[0] == " " or line[0] == "\t" or line[0] == "#":
		return []
	if line.contains(":="):
		return []
	var in_quote := false
	var colon := -1
	for i in line.length():
		var c := line[i]
		if c == "\"":
			in_quote = not in_quote
		elif c == ":" and not in_quote:
			colon = i
			break
	if colon <= 0:
		return []
	var tokens := line.substr(0, colon).split(" ", false)
	if tokens.size() == 0:
		return []
	var name_re := RegEx.new()
	name_re.compile("^[A-Za-z_][A-Za-z0-9_-]*$")
	if name_re.search(tokens[0]) == null:
		return []
	return [tokens[0], Array(tokens).slice(1)]


func test_every_numeric_recipe_argument_is_checked() -> void:
	var lines := _read("res://justfile").split("\n")
	var int_re := RegEx.new()
	int_re.compile("^-?[0-9]+$")
	var num_re := RegEx.new()
	num_re.compile("^-?[0-9]*\\.[0-9]+$")

	var recipe := ""
	var pending: Array = []          # [param_name] still to find a check for
	var checked := 0
	var seen_recipes := 0

	for raw in lines:
		var line := String(raw).replace("\r", "")
		var decl := _declaration(line)
		if decl.is_empty():
			# Inside a recipe body: does this line check a pending param?
			for param in pending.duplicate():
				var call_re := RegEx.new()
				call_re.compile("recipe-arg\\.sh (int|num|enum) %s\\b" % param)
				if call_re.search(line) != null:
					pending.erase(param)
					checked += 1
			continue
		# A new declaration ends the previous recipe: anything still
		# pending was never validated.
		assert_eq(pending, [],
			"recipe `%s` takes numeric argument(s) %s and never checks them with recipe-arg.sh"
			% [recipe, pending])
		recipe = decl[0]
		pending = []
		seen_recipes += 1
		for token in decl[1]:
			var param := String(token)
			var default := ""
			var eq := param.find("=")
			if eq == -1:
				# No default at all — every one of these in this justfile
				# is a count or a duration (`test-load N DURATION`).
				pending.append(param)
				continue
			default = param.substr(eq + 1).replace("\"", "")
			param = param.substr(0, eq)
			if int_re.search(default) != null or num_re.search(default) != null:
				pending.append(param)
	assert_eq(pending, [],
		"recipe `%s` takes numeric argument(s) %s and never checks them with recipe-arg.sh"
		% [recipe, pending])

	# The scan itself must be doing something: a parser that matched no
	# recipes would report a clean justfile forever.
	assert_gt(seen_recipes, 20, "the justfile scan parsed almost no recipes — it is broken")
	assert_gt(checked, 10, "the justfile scan found almost no checks — it is broken")
	gut.p("justfile: %d recipes parsed, %d numeric arguments checked" % [seen_recipes, checked])


# --- which checkouts get the dev build --------------------------------

func test_agent_worktrees_resolve_to_the_dev_build() -> void:
	# The regression: AO worker worktrees branch `ao/<project>/<session>`,
	# which sanitises to `ao-...` and matched no `claude-*` case, so every
	# agent silently launched without D-077's sandbox.
	for name in ["ao-my-edotmw-49-root", "claude-session-abc", "playtest-branch"]:
		var result := _bash("EDOTMW_INSTANCE=%s bash '%s' agent" % [name, _script("instance-id.sh")])
		assert_eq(result["code"], 0, "instance-id.sh agent must succeed for %s" % name)
		assert_eq(str(result["out"]).strip_edges(), "1",
			"instance %s is not the human's own checkout and must get the dev build" % name)


func test_the_humans_own_checkout_does_not() -> void:
	for name in ["main", "master"]:
		var result := _bash("EDOTMW_INSTANCE=%s bash '%s' agent" % [name, _script("instance-id.sh")])
		assert_eq(str(result["out"]).strip_edges(), "0",
			"the default branch is the human's own checkout and must NOT default into sandbox")


func test_the_dev_build_can_be_overridden_explicitly() -> void:
	var path := _script("instance-id.sh")
	var off := _bash("EDOTMW_INSTANCE=ao-x EDOTMW_AGENT=0 bash '%s' agent" % path)
	assert_eq(str(off["out"]).strip_edges(), "0", "EDOTMW_AGENT=0 must force the plain build")
	var on := _bash("EDOTMW_INSTANCE=main EDOTMW_AGENT=1 bash '%s' agent" % path)
	assert_eq(str(on["out"]).strip_edges(), "1", "EDOTMW_AGENT=1 must force the dev build")


func test_quick_test_resolves_sandbox_through_the_one_definition() -> void:
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("bash instance-id.sh agent"),
		"quick-test must ask instance-id.sh whether this is an agent worktree (D-095: nothing re-derives identity)")
	assert_false(justfile.contains("claude-*)"),
		"the justfile must not pattern-match agent branch names itself — that whitelist is what went stale (#89)")
	assert_true(justfile.contains("--sandbox=$sandbox"),
		"quick-test must pass the resolved sandbox flag to the server")
