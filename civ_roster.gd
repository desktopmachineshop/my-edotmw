extends RefCounted
class_name CivRoster

## Loads the data-driven civ list from /civs/*.tres (D-047).
##
## Exists so the server, the client, the lobby and the tests all discover
## civs the same way — the same role `UnitRoster` plays for units, and
## deliberately the same shape so there is one pattern to learn.
##
## Cached from the first call, like UnitRoster. That caching is not a
## micro-optimisation: `UnitRoster.by_id` re-scanned its directory on
## every call and spent 858 ms inside a single simulation tick when twenty
## players finished a unit at once (D-043). Anything resolving definitions
## on the hot path caches, and /civs is read-only at runtime.

const CIVS_DIR := "res://civs"

static var _cache: Array[CivDef] = []
static var _by_id := {}


## Drop the cache. Only for tests that write .tres files at runtime.
static func reload() -> void:
	_cache = []
	_by_id = {}


## Every civ, sorted by id so iteration order is stable.
##
## Stability matters for the same reason it does in UnitRoster: a random
## civ draw (D-048) and a replay both have to reproduce, and neither can
## if the order depends on filesystem enumeration.
static func load_all() -> Array[CivDef]:
	if not _cache.is_empty():
		return _cache

	var out: Array[CivDef] = []
	var dir := DirAccess.open(CIVS_DIR)
	if dir == null:
		push_error("CivRoster: %s is missing or unreadable" % CIVS_DIR)
		return out

	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()

	for name in names:
		var def := load("%s/%s" % [CIVS_DIR, name]) as CivDef
		if def == null:
			push_error("CivRoster: %s/%s did not load as a CivDef" % [CIVS_DIR, name])
			continue
		var invalid := def.validate()
		if invalid != "":
			push_error("CivRoster: %s" % invalid)
			continue
		out.append(def)

	_cache = out
	_by_id = {}
	for def in out:
		_by_id[def.id] = def
	return out


static func by_id(id: StringName) -> CivDef:
	load_all()
	return _by_id.get(id, null)


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def in load_all():
		out.append(def.id)
	return out


## Resolve a lobby seat's civ choice to an actual civ (D-048).
##
## `RANDOM` picks uniformly from the whole list. Uniform is a decision,
## not an accident: "unbiased toward any specific civ for now" is the
## stated intent, so there is no weighting, and a test asserts the
## distribution is actually flat rather than trusting that it is.
##
## Seeded rather than free-running, because a replay has to reproduce the
## draw (D-016) — a match whose civs differed on replay would not be a
## replay of that match.
const RANDOM := &"random"


static func resolve(choice: StringName, rng: RandomNumberGenerator) -> StringName:
	var all := ids()
	if all.is_empty():
		return &""
	if choice != RANDOM and _by_id.has(choice):
		return choice
	return all[rng.randi_range(0, all.size() - 1)]
