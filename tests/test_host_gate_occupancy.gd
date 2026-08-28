extends GutTest

## Guards D-20260827-the-gate-charges-work-not-launchers (#153): the
## admission gate's ledger and the machine's actual occupancy must be
## reconcilable, and a disagreement must be loud.
##
## The gate's accounting unit was a PID; the thing that occupies this host
## is a CONTAINER, and the two part company — a launcher exits, the reaper
## drops its slot, and the container it started carries on. Measured on
## the day it was found: `edotmw-ao-my-edotmw-10-root-quick-test` Up 2
## hours against `host-gate: 0 holder(s), 0 MB charged`, on a machine with
## 733 MB free and 2.9 GB of swap in use. That INVERTS the feature —
## before the gate an overloaded host was obvious, and a stale container
## now makes the ledger read empty.
##
## Executed rather than scanned, for the reason `test_gate_checks.gd`
## gives: the gate is a script, so a test can drive it and watch it get
## the answer wrong. Docker is STUBBED — a `docker` on PATH that prints a
## fixture — because the rule under test is what the gate DOES with an
## answer, and a test needing real containers could neither create the
## interesting case nor run on a machine with the daemon down.
##
## `test_host_budget.gd` holds this feature's SCAN half (the read-only
## contract, and that every recipe declares its class); this file holds
## the behaviour. Both are needed: a scan cannot see the reaper reasoning
## wrongly, and these would pass on a gate that had quietly grown a
## `docker rm`.


func _bash(line: String) -> Dictionary:
	for shell in ["/bin/bash", "bash", "/usr/bin/bash"]:
		var out := []
		var code := OS.execute(shell, ["-c", line], out, true)
		if code != -1:
			return {"code": code, "out": "\n".join(PackedStringArray(out))}
	return {"code": -1, "out": ""}


func _repo() -> String:
	return ProjectSettings.globalize_path("res://").rstrip("/")


## Write a file, contents exactly as given.
##
## `FileAccess`, not `echo` through the shell, and that is the whole
## reason this helper exists. A fixture built by echoing into a file
## crosses GDScript, `OS.execute` and bash, and the quoting does not
## survive: the stub below came out as `[ $1 = ps ]` — an unquoted `$1`
## that errors with no argument and prints nothing, which looks exactly
## like a gate that never asked docker anything. Godot writes bytes.
func _write(path: String, text: String) -> void:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(handle, "could not write the fixture %s" % path)
	if handle != null:
		handle.store_string(text)
		handle.close()


## A throwaway gate directory with a stubbed `docker` in front of it.
##
## `running` is the fixture the stub prints for `docker ps`, so a test
## changes what is running on this machine by writing one file.
func _sandbox(tag: String) -> String:
	var dir := ProjectSettings.globalize_path("user://gate-%s" % tag)
	var made := _bash("rm -rf '%s' && mkdir -p '%s/bin' '%s/gate'" % [dir, dir, dir])
	assert_eq(int(made["code"]), 0, "could not make the sandbox: %s" % made["out"])
	_running(dir, "")

	# The stub does not test its argument, because it does not need to:
	# the gate's only docker verb is `ps`, and `test_host_budget.gd`'s
	# allowlist is what keeps that true. `${X:-/dev/null}` is what stops
	# `cat` reading stdin and hanging if the variable is ever unset.
	var stub := dir + "/bin/docker"
	_write(stub, "#!/bin/sh\ncat ${FAKE_PS:-/dev/null} 2>/dev/null\nexit 0\n")
	var wrote := _bash("chmod +x '%s'" % stub)
	assert_eq(int(wrote["code"]), 0, "could not make the stub executable: %s" % wrote["out"])

	# Prove the stub answers BEFORE anything relies on it. A fixture that
	# silently reports nothing looks exactly like the gate failing to ask,
	# and three of the seven tests below expect an empty answer — so
	# without this, a broken stub reads as "mostly passing" instead of
	# "the harness is not running". Same rule as the gate's own vacuity
	# guards.
	_running(dir, "edotmw-probe")
	var probe := _bash(("PATH=\"%s/bin:$PATH\" FAKE_PS='%s/running' "
		+ "docker ps --filter 'name=^edotmw-' --format '{{.Names}}' 2>&1") % [dir, dir])
	assert_true(String(probe["out"]).contains("edotmw-probe"),
		("the docker stub does not answer in this environment — dir '%s', "
		+ "exit %d, output '%s'") % [dir, int(probe["code"]), probe["out"]])
	_running(dir, "")
	return dir


## A holder file for a process that is NOT running.
##
## pid 999999 rather than a pid this test kills: the reaper asks
## `kill -0`, and a pid just killed could be recycled between writing the
## lock and reading it.
func _dead_holder(dir: String, instance: String) -> void:
	_write("%s/gate/medium.999999.%s.lock" % [dir, instance],
		"pid=999999\nclass=medium\ncost_mb=1300\ninstance=%s\nlabel=quick-test\nstarted=1\n"
		% instance)


## What `docker ps` will report. One name, or "" for a quiet machine.
func _running(dir: String, name: String) -> void:
	_write(dir + "/running", "" if name == "" else name + "\n")


func _gate(dir: String, args: String) -> Dictionary:
	# `started=1` is 1970, i.e. far past the max-hold backstop — raised
	# here so these exercise the pid/container reasoning rather than the
	# backstop, which is a separate rule with its own test.
	# PATH in DOUBLE quotes: single ones would set it to the literal
	# string "$PATH" and the stub would be the only executable on it.
	return _bash(("cd '%s' && PATH=\"%s/bin:$PATH\" FAKE_PS='%s/running' "
		+ "EDOTMW_GATE_DIR='%s/gate' EDOTMW_GATE_MAX_HOLD=99999999999 "
		+ "bash host-gate.sh %s 2>&1") % [_repo(), dir, dir, dir, args])


func _locks(dir: String) -> String:
	var listing := _bash("ls '%s/gate' 2>/dev/null" % dir)
	return String(listing["out"]).strip_edges()


func _has_a_shell() -> bool:
	var probe := _bash("echo ok")
	var ok := int(probe["code"]) == 0 and String(probe["out"]).contains("ok")
	assert_true(ok,
		"this file needs a POSIX shell — run the suite through `just test-unit` (docker)")
	return ok


# --- the reaper ---------------------------------------------------------

func test_a_slot_stays_charged_while_the_work_it_admitted_is_still_running() -> void:
	# #153 itself. The launcher is gone; its container is not; the memory
	# is still resident whatever the process table says.
	if not _has_a_shell():
		return
	var dir := _sandbox("kept")
	_dead_holder(dir, "test-inst-a")
	_running(dir, "edotmw-test-inst-a-quick-test")

	var result := _gate(dir, "reap")
	assert_eq(int(result["code"]), 0, "reap must not fail: %s" % result["out"])
	assert_ne(_locks(dir), "",
		"the slot was released while its container was still up — the budget then "
		+ "reads this machine as emptier than it is, which is the whole of #153")
	assert_true(String(result["out"]).contains("still running"),
		"and it must SAY so: the silent under-count is what took an hour to find "
		+ "and got two live sessions misread as dead")
	assert_eq(String(_gate(dir, "charged")["out"]).strip_edges(), "1300",
		"a kept slot must still be charged, or keeping it buys nothing")


func test_the_slot_goes_when_the_container_does() -> void:
	# The half that stops this wedging the machine: a holder kept for a
	# container must be released when that container is.
	if not _has_a_shell():
		return
	var dir := _sandbox("released")
	_dead_holder(dir, "test-inst-a")
	_running(dir, "edotmw-test-inst-a-quick-test")
	_gate(dir, "reap")
	assert_ne(_locks(dir), "", "setup: the slot should have been kept")

	_running(dir, "")
	var result := _gate(dir, "reap")
	assert_eq(_locks(dir), "",
		"a dead launcher with nothing running must be reaped exactly as before")
	assert_true(String(result["out"]).contains("reaped"), "and must say it reaped it")
	assert_eq(String(_gate(dir, "charged")["out"]).strip_edges(), "0")


func test_an_instance_does_not_own_another_instances_containers() -> void:
	# `ao-my-edotmw-8` must not match `edotmw-ao-my-edotmw-81-...`. Getting
	# this wrong holds a slot for ever on somebody else's work — and it is
	# the same class of matching mistake `just reap-orphans` was twice
	# caught making in the other, destructive direction, which is why the
	# rule here is a prefix ending at a dash rather than a suffix regex.
	if not _has_a_shell():
		return
	var dir := _sandbox("prefix")
	_dead_holder(dir, "ao-my-edotmw-8")
	_running(dir, "edotmw-ao-my-edotmw-81-root-server-1")

	_gate(dir, "reap")
	assert_eq(_locks(dir), "",
		"instance 'ao-my-edotmw-8' claimed a container belonging to '...-81'")


func test_a_missing_docker_fails_open() -> void:
	# No docker, a stopped daemon, a query that hangs: all must answer
	# "nothing is running", so the gate degrades to exactly what it did
	# before this existed. Wedging every agent on the machine because
	# `docker ps` was slow would be a worse bug than the one being fixed.
	if not _has_a_shell():
		return
	var dir := _sandbox("nodocker")
	_dead_holder(dir, "test-inst-a")
	_running(dir, "edotmw-test-inst-a-quick-test")

	var result := _bash(("cd '%s' && PATH='/usr/bin:/bin' EDOTMW_GATE_DIR='%s/gate' "
		+ "EDOTMW_GATE_MAX_HOLD=99999999999 bash host-gate.sh reap 2>&1")
		% [_repo(), dir])
	assert_eq(int(result["code"]), 0,
		"the gate must not fail without docker: %s" % result["out"])
	assert_eq(_locks(dir), "",
		"with no way to ask, the gate must reap on the pid exactly as it used to")


# --- the report ---------------------------------------------------------

func test_a_container_nobody_is_charged_for_is_reported_loudly() -> void:
	# The other half of the invariant. A container the gate never admitted,
	# or whose holder has since gone, is memory the admission rule cannot
	# see. `just up` leaves one on purpose, so this is a REPORT and not a
	# refusal — but it has to be said where people already look, which is
	# `just doctor` and `just host-status`.
	if not _has_a_shell():
		return
	var dir := _sandbox("loose")
	_running(dir, "edotmw-somebody-else-server-1")

	var result := _gate(dir, "occupancy")
	assert_true(String(result["out"]).contains("edotmw-somebody-else-server-1"),
		"occupancy must name what is running")
	assert_true(String(result["out"]).contains("NOT charged"),
		"and must say plainly that nothing is paying for it")


func test_a_quiet_machine_says_the_two_agree() -> void:
	# The negative case, so a reader can tell "reconciled" from "the check
	# printed nothing because it is broken" — the vacuous pass this
	# project has paid for more than once.
	if not _has_a_shell():
		return
	var dir := _sandbox("quiet")
	var result := _gate(dir, "occupancy")
	assert_true(String(result["out"]).contains("agree"),
		"a clean machine must say so rather than printing nothing at all")


func test_status_reconciles_without_being_asked() -> void:
	# `just doctor` and `just host-status` both call `status`, and neither
	# is going to grow a second call somebody has to remember to make.
	if not _has_a_shell():
		return
	var dir := _sandbox("status")
	_running(dir, "edotmw-somebody-else-server-1")
	var result := _gate(dir, "status")
	assert_true(String(result["out"]).contains("edotmw-somebody-else-server-1"),
		"status must include the occupancy report — it is the surface people read")
