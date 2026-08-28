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
	# Scoped to docker invocations, which it was not: `--name` is an
	# ordinary flag and the art tooling takes one
	# (`art/attach_kit.py --name "{{TARGET}}"`), so the bare scan went red
	# on a Blender argument that has nothing to do with D-095 — and a
	# guard that cries wolf is a guard somebody eventually relaxes rather
	# than reads. The rule itself is unchanged: every docker `--name` must
	# carry {{compose_project}}, and all three real ones sit on the same
	# line as their `docker compose`.
	var name_re := RegEx.new()
	name_re.compile("docker[^\n]*--name (?!\\{\\{compose_project\\}\\})\\S+")
	offence = name_re.search(justfile)
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
	var client := _read("res://client.gd")
	assert_true(client.contains("args.get(\"instance\""),
		"the client must accept --instance so the launcher can label the window")
	assert_true(client.contains("get_window().title"),
		"the client must put the instance in its title bar (D-095)")


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
