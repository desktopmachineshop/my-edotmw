extends RefCounted
class_name AiProfileRoster

## Loads the data-driven AI profile list from /ai/*.tres
## (D-20260818-ai-profiles-are-data).
##
## Same role and deliberately the same shape as `CivRoster` and
## `FormationRoster`, so there is one pattern to learn: the server, the
## lobby and the tests all discover difficulty levels here, and none of
## them holds a list of its own.
##
## Cached from the first call, like every other roster. `AiPlayer.update`
## reads its profile on every think — once a second per AI seat, twenty
## seats at D-018's target — and a definition lookup that touched the
## filesystem is the defect that spent 858 ms inside one simulation tick
## (D-043). /ai is read-only at runtime.

const PROFILES_DIR := "res://ai"

static var _cache: Array[AiProfileDef] = []
static var _by_id := {}
static var _fallback: AiProfileDef = null


## Drop the cache. Only for tests that write .tres files at runtime.
static func reload() -> void:
	_cache = []
	_by_id = {}


## Every profile, easiest first, then by id so iteration is stable — the
## same reason CivRoster sorts. A lobby list whose order depended on
## filesystem enumeration would reorder itself between machines.
static func load_all() -> Array[AiProfileDef]:
	if not _cache.is_empty():
		return _cache

	var out: Array[AiProfileDef] = []
	var dir := DirAccess.open(PROFILES_DIR)
	if dir == null:
		# Not an error worth quitting over: the schema defaults are the
		# constants the AI shipped with, so a missing /ai costs difficulty
		# and never the game (D-081's empty-model_id rule, applied here).
		push_warning("AiProfileRoster: %s is missing — every AI plays the built-in default"
				% PROFILES_DIR)
		return out

	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()

	for name in names:
		var def := load("%s/%s" % [PROFILES_DIR, name]) as AiProfileDef
		if def == null:
			push_error("AiProfileRoster: %s/%s did not load as an AiProfileDef"
				% [PROFILES_DIR, name])
			continue
		var invalid := def.validate()
		if invalid != "":
			push_error("AiProfileRoster: %s" % invalid)
			continue
		out.append(def)

	out.sort_custom(func(a, b):
		if a.order != b.order:
			return a.order < b.order
		return String(a.id) < String(b.id))

	_cache = out
	_by_id = {}
	for def in out:
		_by_id[def.id] = def
	return out


static func by_id(id: StringName) -> AiProfileDef:
	load_all()
	return _by_id.get(id, null)


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def in load_all():
		out.append(def.id)
	return out


## The profile a seat gets when nobody chose one.
##
## Read off the DATA (`is_default`) rather than named here, because no
## script may name a profile id — the same rule that keeps `civ_roster.gd`
## free of civ names (D-046 criterion 3). If no file claims the default,
## the schema's own values answer, which is the built-in AI.
static func default() -> AiProfileDef:
	for def in load_all():
		if def.is_default:
			return def
	if _fallback == null:
		_fallback = AiProfileDef.new()
	return _fallback


## Deal a command line's `--ai-profiles=a,b` across `count` AI seats,
## round-robin, exactly as `--ai` deals civs.
##
## Returns an empty array if any name is not a shipped profile, so the
## caller REFUSES TO START rather than seating a plausible wrong
## opponent. That is D-20260817-recipe-args-are-positional's lesson on
## the far side of the boundary: a silent fallback here would mean a
## ladder run reporting a pairing it never played.
static func resolve_list(spec: String, count: int) -> Array[AiProfileDef]:
	var out: Array[AiProfileDef] = []
	if count <= 0:
		return out

	var wanted: Array[AiProfileDef] = []
	for raw in spec.split(",", false):
		var name := String(raw).strip_edges()
		if name == "":
			continue
		var def := by_id(StringName(name))
		if def == null:
			return []
		wanted.append(def)

	if wanted.is_empty():
		wanted.append(default())
	for i in range(count):
		out.append(wanted[i % wanted.size()])
	return out
