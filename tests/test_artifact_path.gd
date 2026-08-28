extends GutTest

## Guards `artifact_path.gd` — that everything this project WRITES lands
## somewhere the running build can write (#201,
## D-20260828-artifacts-are-written-where-the-build-can-write).
##
## The defect: `res://` is a real directory in a checkout and a read-only
## virtual filesystem inside an exported build's `.pck`, and every writer
## targeted `res://artifacts/`. The first ever exported build therefore
## played a complete, correct match and recorded no replay at all, with
## the only notice a `push_error` at start-up.
##
## The half that matters most cannot be run from here: this suite runs in
## the editor binary, which is by definition the checkout case. So the
## mapping is split — `rebase()` is pure and takes its destination as an
## argument, and both destinations are tested directly. A rule whose
## interesting case nothing exercises is the vacuous check this project
## has paid for repeatedly (D-022's audit block).

const SOME_FILES := [
	"res://artifacts/replay-24395.edmw",
	"res://artifacts/replay-24395-match2.edmw",
	"res://artifacts/models-godot.png",
	"res://artifacts/client-frame.png",
	"res://artifacts/terrain-3d.png",
]


# --- the two bases -----------------------------------------------------

func test_a_checkout_writes_exactly_where_every_recipe_looks() -> void:
	# The clause the whole decision rests on: in a checkout this is the
	# identity function, so `just replay-info`, every `--out=` in the
	# justfile and every "LOOK AT artifacts/..." line keep working without
	# having been individually checked.
	for path in SOME_FILES:
		assert_eq(ArtifactPath.rebase(path, ArtifactPath.RES_BASE), path,
			"a checkout leaves %s alone" % path)
	assert_eq(ArtifactPath.rebase(ArtifactPath.RES_BASE, ArtifactPath.RES_BASE),
		ArtifactPath.RES_BASE, "the base itself is unchanged")


func test_a_build_writes_somewhere_it_can() -> void:
	# The case #201 is about, and the case this process cannot BE.
	for path in SOME_FILES:
		var moved := ArtifactPath.rebase(path, ArtifactPath.USER_BASE)
		assert_true(moved.begins_with(ArtifactPath.USER_BASE + "/"),
			"%s is rebased into user:// (got %s)" % [path, moved])
		assert_eq(moved.get_file(), path.get_file(),
			"the file name survives the move")
	assert_eq(ArtifactPath.rebase(ArtifactPath.RES_BASE, ArtifactPath.USER_BASE),
		ArtifactPath.USER_BASE, "the bare directory rebases too")


func test_nothing_else_is_touched() -> void:
	# A rewrite that caught more than it meant to would silently move the
	# things this game READS — the maps, the units, the shaders — which is
	# a far worse failure than the one being fixed.
	for path in ["res://maps/default.tres", "res://units/levy.tres",
			"res://artifacts-elsewhere/x.png", "user://saves/x.dat",
			"C:/tmp/shot.png", "/tmp/shot.png", "artifacts/x.png", ""]:
		assert_eq(ArtifactPath.rebase(path, ArtifactPath.USER_BASE), path,
			"%s is not an artifact path" % path)


func test_this_process_is_a_checkout_and_says_so() -> void:
	# Pins the tag reading itself. If this ever fails in the test estate,
	# the resolution rule has inverted and every recipe is writing
	# somewhere nobody is looking.
	assert_true(ArtifactPath.writes_into_the_checkout(),
		"the editor binary running a checkout writes into the checkout")
	assert_eq(ArtifactPath.base(), ArtifactPath.RES_BASE)
	assert_eq(ArtifactPath.of("replay-1.edmw"),
		"res://artifacts/replay-1.edmw")
	for path in SOME_FILES:
		assert_eq(ArtifactPath.resolve(path), path,
			"resolve() is the identity here")


# --- the writers -------------------------------------------------------

func test_every_writer_goes_through_the_rule() -> void:
	# D-106's caller-exists test: every other check here can pass while a
	# writer quietly keeps its own hardcoded path, which is exactly the
	# state #201 found. Carries D-106's own caveat — it covers the
	# literals it can see, and a path assembled from pieces is invisible
	# to it.
	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 40, "the scan found the project's scripts")
	var missing: Array = []
	for path in scripts:
		var path_str := String(path)
		if path_str == "res://artifact_path.gd" or path_str.begins_with("res://tests/"):
			continue
		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		if text.contains("res://artifacts") and not text.contains("ArtifactPath"):
			missing.append(path_str)
	assert_eq(missing, [],
		"a script naming res://artifacts must resolve it through "
		+ "ArtifactPath, or an exported build writes into a read-only "
		+ "filesystem and says nothing (#201)")


func test_the_replay_the_shipped_build_records_is_resolved() -> void:
	# server.gd is the one writer a PLAYER's machine runs, and D-016 makes
	# it the primary desync-forensics tool. Named specifically rather than
	# left to the scan above, because it is the reason the rule exists.
	var handle := FileAccess.open("res://server.gd", FileAccess.READ)
	assert_not_null(handle)
	var text := handle.get_as_text()
	handle.close()
	assert_true(text.contains("ArtifactPath"),
		"the server resolves its replay path")
	assert_true(text.contains("NOT recording a replay"),
		"a server that could not open a replay says so — the actual "
		+ "complaint in #201 is that nothing later said the recording "
		+ "never happened")


# --- the directory -----------------------------------------------------

func test_ensure_dir_for_makes_the_directory_and_reports_failure() -> void:
	var probe := "user://artifacts-test-%d/deep/file.txt" % Time.get_ticks_usec()
	assert_eq(ArtifactPath.ensure_dir_for(probe), OK,
		"a writable target is created")
	assert_true(DirAccess.dir_exists_absolute(probe.get_base_dir()),
		"the directory is really there")
	var written := FileAccess.open(probe, FileAccess.WRITE)
	assert_not_null(written, "and a file can be opened in it")
	if written != null:
		written.close()
	DirAccess.remove_absolute(probe)
	DirAccess.remove_absolute(probe.get_base_dir())
	DirAccess.remove_absolute(probe.get_base_dir().get_base_dir())

	assert_eq(ArtifactPath.ensure_dir_for("res://artifacts/x.png"), OK,
		"an existing directory is not an error")


func test_describe_names_a_place_a_person_can_open() -> void:
	# `user://` is not somewhere anyone can look, and the whole point of
	# the log line is that a player reporting "there is no replay" has an
	# answer.
	var described := ArtifactPath.describe(ArtifactPath.of("replay-1.edmw"))
	assert_true(described.contains("replay-1.edmw"), "names the file")
	assert_gt(described.length(), ArtifactPath.of("replay-1.edmw").length(),
		"and says where that really is")


func test_a_replay_writes_where_a_BUILD_would_put_it() -> void:
	# As close to the exported case as an editor binary can get: the tag
	# decides res:// vs user://, and this drives the whole writer chain —
	# directory creation, header, a record, read-back — against the
	# user:// side that only a build takes. Without it, "a build writes to
	# user://" would be a claim about a string rather than about a file.
	var space := TorusSpace.new(16, 8, 1.0)
	var target := ArtifactPath.rebase(
		"res://artifacts/replay-probe-%d.edmw" % Time.get_ticks_usec(),
		ArtifactPath.USER_BASE)
	assert_true(target.begins_with("user://"), "the probe really is user://")

	var log := ReplayLog.new()
	assert_eq(log.open_for_write(target, 10.0, space), OK,
		"a replay opens where a build would write it")
	assert_eq(log.path, target, "and remembers where that was")
	assert_eq(log.open_error, "", "with nothing to report")

	var curve := StateCurve.new()
	curve.append_cell(0.0, Vector2i(1, 1), space)
	curve.append_cell(1.0, Vector2i(2, 1), space)
	log.record(0.0, 42, 1, curve)
	log.close()

	var replay := ReplayLog.read(target)
	assert_false(replay.is_empty(), "and it reads back as a replay")
	assert_eq(replay["records"].size(), 1, "with the record in it")
	DirAccess.remove_absolute(target)


func test_a_replay_that_cannot_be_written_says_why() -> void:
	# #201's actual complaint: the build's failure was a push_error at
	# start-up and nothing afterwards said the recording never happened.
	var log := ReplayLog.new()
	var err := log.open_for_write("user://", 10.0, TorusSpace.new(16, 8, 1.0))
	assert_ne(err, OK, "a directory is not a replay file")
	assert_ne(log.open_error, "", "and the reason is kept for the caller")
	assert_false(log.is_open())
	# It reports loudly as well as returning the error — in a checkout that
	# push_error is what a developer sees; in a build it is what the
	# server's own printed line replaces.
	assert_push_error_count(1, "the failure is reported exactly once")


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "tools" or sub == "addons":
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))
