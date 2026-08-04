extends RefCounted
class_name TerrainPresetRoster

## Loads the data-driven civ list from /civs/*.tres (D-047).
##
## Exists so the server, the client, the lobby and the tests all discover
## presets the same way — the same role `UnitRoster` plays for units, and
## deliberately the same shape so there is one pattern to learn.
##
## Cached from the first call, like UnitRoster. That caching is not a
## micro-optimisation: `UnitRoster.by_id` re-scanned its directory on
## every call and spent 858 ms inside a single simulation tick when twenty
## players finished a unit at once (D-043). Anything resolving definitions
## on the hot path caches, and /civs is read-only at runtime.

const PRESETS_DIR := "res://terrain"

static var _cache: Array[TerrainPreset] = []
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
static func load_all() -> Array[TerrainPreset]:
	if not _cache.is_empty():
		return _cache

	var out: Array[TerrainPreset] = []
	var dir := DirAccess.open(PRESETS_DIR)
	if dir == null:
		push_error("TerrainPresetRoster: %s is missing or unreadable" % PRESETS_DIR)
		return out

	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()

	for name in names:
		var def := load("%s/%s" % [PRESETS_DIR, name]) as TerrainPreset
		if def == null:
			push_error("TerrainPresetRoster: %s/%s did not load as a TerrainPreset" % [PRESETS_DIR, name])
			continue
		var invalid := def.validate()
		if invalid != "":
			push_error("TerrainPresetRoster: %s" % invalid)
			continue
		out.append(def)

	_cache = out
	_by_id = {}
	for def in out:
		_by_id[def.id] = def
	return out


static func by_id(id: StringName) -> TerrainPreset:
	load_all()
	return _by_id.get(id, null)


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def in load_all():
		out.append(def.id)
	return out


