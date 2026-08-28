extends GutTest

## Guards D-095: parallel dev instances (one per agent worktree) are
## isolated — compose project, container names and published host port
## all derive from the ONE identity in instance-id.sh.
##
## Before D-095 every worktree shared compose project "edotmw" and UDP
## port 4433, so any agent's `just down` removed every agent's
## containers, and a client could silently connect to whichever server
## held 4433 — CLAUDE.md records a load-test failure mis-diagnosed for
## exactly that reason ("check for a stray server before believing a
## load-test failure"). These are text scans in the style of
## test_civs.gd's no-script-names-a-civ rule: the isolation is only real
## if hardcoding the shared literals back in FAILS.


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func test_identity_is_derived_from_the_one_script() -> void:
	var script := _read("res://instance-id.sh")
	assert_true(script.contains("EDOTMW_INSTANCE"),
		"instance-id.sh must honour the explicit sharing override")
	assert_true(script.contains("EDOTMW_PORT"),
		"instance-id.sh must honour the explicit port override")

	var justfile := _read("res://justfile")
	assert_true(justfile.contains("`bash instance-id.sh name`"),
		"the justfile's instance name must come from instance-id.sh, not a re-derivation")
	assert_true(justfile.contains("`bash instance-id.sh port`"),
		"the justfile's port must come from instance-id.sh, not a re-derivation")


func test_every_compose_invocation_is_scoped_to_this_instance() -> void:
	var justfile := _read("res://justfile")

	# Any `docker compose -p <something>` where <something> is not the
	# derived {{compose_project}} rebinds a recipe to a shared (or at
	# least foreign) project — the pre-D-095 `-p edotmw` bug.
	var project_re := RegEx.new()
	project_re.compile("docker compose -p (?!\\{\\{compose_project\\}\\})\\S+")
	var offence := project_re.search(justfile)
	assert_null(offence,
		"a compose invocation is not scoped to {{compose_project}}: %s"
		% (offence.get_string() if offence != null else ""))

	# Explicit CONTAINER names collide across worktrees unless prefixed
	# with the per-instance project.
	#
	# Scanned PER LINE, and only on lines that actually invoke docker.
	# `--name` is not a docker-only token: `art/attach_kit.py --name
	# "{{TARGET}}"` hands a .blend id to a Python script, and the
	# whole-file scan matched THAT — leaving this guard red on `main` for
	# something that is not an isolation hole at all (#209). The claim
	# here is about CONTAINERS, so it has to ask about containers: a
	# guard that cries wolf gets muted, and the next person to genuinely
	# hardcode a container name would read the red as the known noise.
	var name_re := RegEx.new()
	name_re.compile("--name (?!\\{\\{compose_project\\}\\})\\S+")
	for line in justfile.split("\n"):
		if not line.contains("docker"):
			continue
		offence = name_re.search(line)
		assert_null(offence,
			"a named container is not prefixed with {{compose_project}}: %s"
			% (offence.get_string() if offence != null else ""))

	# The stray-container sweep in `down` must be scoped the same way, or
	# it force-removes other agents' one-off containers.
	var label_re := RegEx.new()
	label_re.compile("com\\.docker\\.compose\\.project=(?!\\{\\{compose_project\\}\\})")
	offence = label_re.search(justfile)
	assert_null(offence,
		"the down sweep's label filter is not scoped to {{compose_project}}")


func test_host_port_is_per_instance_not_hardcoded() -> void:
	var compose := _read("res://docker-compose.yml")
	assert_true(compose.contains("${EDOTMW_HOST_PORT"),
		"the server's published host port must come from EDOTMW_HOST_PORT")

	# A literal "NNNN:4433/udp" mapping would pin every instance to one
	# host port again.
	var hardcoded_re := RegEx.new()
	hardcoded_re.compile("\"\\d+:4433/udp\"")
	assert_null(hardcoded_re.search(compose),
		"docker-compose.yml hardcodes the published host port")

	var justfile := _read("res://justfile")
	assert_true(justfile.contains("export EDOTMW_HOST_PORT := port"),
		"the justfile must export the derived port for compose to publish")

	# No recipe may hand a client/bot the historical shared port as a
	# literal — endpoints go through {{port}} / the PORT parameter.
	var literal_port_re := RegEx.new()
	literal_port_re.compile("--port=4433")
	assert_null(literal_port_re.search(justfile),
		"a recipe hardcodes --port=4433 instead of the derived {{port}}")


func test_client_titles_itself_with_its_instance() -> void:
	# The rule is real; where it LIVES moved — the same shape as
	# `test_agent_quick_launch_defaults_to_sandbox` below. #180 gave the
	# client a state in which it is NOT connected, so the title is
	# rewritten on every connection rather than built once in `_ready()`,
	# and it goes through `_set_title` (which guards a null window, so a
	# GUT test can drive the file at all). The old scan looked for a
	# literal `get_window().title`.
	#
	# What replaces it is STRICTER, not looser: it asserts the instance
	# actually reaches the title, where the old one only asserted that
	# some `.title` assignment existed somewhere in a 10,000-line file.
	var client := _read("res://client.gd")
	assert_true(client.contains("args.get(\"instance\""),
		"the client must accept --instance so the launcher can label the window")
	assert_true(client.contains("window.title = MainMenu.window_title(_instance"),
		"the client must put the instance in its title bar (D-095)")
	var menu := _read("res://main_menu.gd")
	assert_true(menu.contains("instance.is_empty()"),
		"and the one definition of that title must actually use the instance")


func test_agent_quick_launch_defaults_to_sandbox() -> void:
	# The rule is real; where it LIVES moved. This used to assert the
	# justfile contained `claude-*) sandbox=1` — a whitelist of agent
	# branch prefixes, which silently stopped matching when the harness
	# started branching `ao/<project>/<session>` and left every agent
	# worktree without its dev tools (#89). The resolution is
	# `instance-id.sh agent` now, so it is executed rather than scanned:
	# see tests/test_recipe_args.gd.
	var justfile := _read("res://justfile")
	assert_true(justfile.contains("bash instance-id.sh agent"),
		"quick-test must resolve SANDBOX=auto through instance-id.sh, not its own pattern match")
	assert_true(justfile.contains("--sandbox=$sandbox"),
		"quick-test must pass the resolved sandbox flag to the server")
