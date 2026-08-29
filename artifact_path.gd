extends RefCounted
class_name ArtifactPath

## WHERE this project writes the files it produces — replays, capture
## screenshots, preview renders (#201).
##
## `res://` is a real directory in a checkout and a READ-ONLY virtual
## filesystem inside the `.pck` of an exported build. Every writer here
## targeted `res://artifacts/`, so the first ever exported build printed
##
##     ERROR: Could not create directory: 'res://artifacts'.
##     ERROR: ReplayLog: could not create res://artifacts (error 2)
##
## and then played a complete, correct match with **no replay at all**.
## D-016 says replays ARE the curve log and are the primary
## desync-forensics tool; in a shipped build there were none, and the only
## notice was a `push_error` at start-up, which in a release build goes
## nowhere a player can see.
##
## ## The rule
##
## One base, decided once, here: a checkout keeps `res://artifacts` and a
## build writes to `user://artifacts`. Every recipe, every doc and
## `just replay-info` therefore keep finding files exactly where they look
## for them today, and the branch lives in one function instead of at ten
## call sites.
##
## `resolve()` REWRITES rather than demanding callers assemble paths, so a
## path handed in from outside — `--screenshot=res://artifacts/frame.png`,
## `--out=res://artifacts/models-godot.png`, a replay name built from a
## port number — lands somewhere writable without every recipe learning a
## second vocabulary.
##
## ## Why the feature tag rather than trying and seeing
##
## `OS.has_feature("template")` is exactly the question being asked: the
## editor binary running a checkout gets "editor", an exported game gets
## "template". Probing by attempting a write would answer the same
## question more slowly and would also answer YES on a checkout somebody
## made read-only, which is a different fault and should be reported as
## one rather than silently redirected.
##
## All-static: there is no state a caller could get out of step with, and
## a resolved path is a pure function of the path it came from.

const RES_BASE := "res://artifacts"
const USER_BASE := "user://artifacts"


## True when this process can write inside the project directory — i.e.
## anything running from a checkout, which is the whole dev estate.
static func writes_into_the_checkout() -> bool:
	return not OS.has_feature("template")


## The artifacts directory this process may actually write to.
static func base() -> String:
	return RES_BASE if writes_into_the_checkout() else USER_BASE


## `name` inside the artifacts directory. For a caller composing a fresh
## path rather than rewriting one it was handed.
static func of(file_name: String) -> String:
	return "%s/%s" % [base(), file_name]


## The writable form of `path`.
##
## Anything under `res://artifacts` is rebased; everything else — an
## absolute OS path a recipe passed, a `user://` path, a path inside the
## project that is genuinely meant to be read — is returned untouched.
## Identity in a checkout, by construction, which is what keeps the whole
## test estate and every recipe working unchanged.
static func resolve(path: String) -> String:
	return rebase(path, base())


## The pure half of `resolve`, with the destination supplied. Split out
## because the interesting case — what an exported build does — cannot be
## reached from a test running in the editor binary, and a rule nothing
## can exercise is the vacuous check this project keeps paying for.
static func rebase(path: String, to_base: String) -> String:
	if to_base == RES_BASE:
		return path
	if path == RES_BASE:
		return to_base
	if path.begins_with(RES_BASE + "/"):
		return to_base + path.substr(RES_BASE.length())
	return path


## Make sure the directory `path` lives in exists. Returns OK, or the
## error, which every caller must report rather than write into the void:
## the whole of #201 is a writer that failed at start-up and nothing
## later saying the file was never written.
static func ensure_dir_for(path: String) -> Error:
	var dir := path.get_base_dir()
	if dir == "" or DirAccess.dir_exists_absolute(dir):
		return OK
	return DirAccess.make_dir_recursive_absolute(dir)


## Where a path actually is on this machine, for a log line. A player
## reporting "there is no replay" needs somewhere to look, and
## `user://` is not a place anyone can open.
static func describe(path: String) -> String:
	var real := ProjectSettings.globalize_path(path)
	if real == "" or real == path:
		return path
	return "%s (%s)" % [path, real]
