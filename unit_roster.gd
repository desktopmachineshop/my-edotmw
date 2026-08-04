extends RefCounted
class_name UnitRoster

## Loads the data-driven unit roster from /units/*.tres (D-010).
##
## Exists so the server, the client, and the tests all discover units the
## same way. Adding a unit means adding a .tres — nothing here or anywhere
## else needs to learn its name.

const UNITS_DIR := "res://units"

## The roster, loaded once per process.
##
## This used to re-scan the directory and re-load every .tres on EVERY
## call, and `by_id` calls it once per lookup. That is a filesystem walk
## in the middle of the simulation tick: `SquadSim.tick` resolves a
## UnitDef for each squad a building finishes, so a tick in which twenty
## players each completed a unit spent **858 ms** — over eight whole tick
## budgets — inside `load_all`.
##
## It hid for a whole milestone because it is invisible to every workload
## that resolves its defs up front. The profiling sweep does exactly that,
## so `just profile` reported a healthy ~29 ms worst tick for the same
## code that spiked to 866 ms in a live match. Only the live server ever
## called by_id at 10 Hz.
##
## The roster is static data — /units is read-only at runtime — so caching
## it is not an optimisation with a correctness cost, it is what the
## original should have done.
static var _cache: Array[UnitDef] = []
static var _by_id := {}


## Drop the cache. Only for tests that write .tres files at runtime; the
## running game never needs it, because /units does not change.
static func reload() -> void:
	_cache = []
	_by_id = {}


## Every UnitDef in /units, sorted by id so iteration order is stable.
## Stability matters: the server picks a default unit from this list, and
## a replay is only reproducible if that pick doesn't depend on filesystem
## enumeration order.
static func load_all() -> Array[UnitDef]:
	if not _cache.is_empty():
		return _cache

	var out: Array[UnitDef] = []
	var dir := DirAccess.open(UNITS_DIR)
	if dir == null:
		push_error("UnitRoster: %s is missing or unreadable" % UNITS_DIR)
		return out

	var names := []
	for file_name in dir.get_files():
		# Exported/imported builds can report a .remap suffix.
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()

	for name in names:
		var def := load("%s/%s" % [UNITS_DIR, name]) as UnitDef
		if def == null:
			push_error("UnitRoster: %s/%s did not load as a UnitDef" % [UNITS_DIR, name])
			continue
		out.append(def)

	_cache = out
	_by_id = {}
	for def in out:
		_by_id[def.id] = def
	return out


## The default unit. Returns a bare UnitDef rather than null if the roster
## is empty, so a missing roster degrades to "wrong stats" rather than a
## crash on connect — with an error logged either way.
static func first() -> UnitDef:
	var all := load_all()
	if all.is_empty():
		push_error("UnitRoster: no UnitDef found in %s — using defaults" % UNITS_DIR)
		return UnitDef.new()
	return all[0]


static func by_id(id: StringName) -> UnitDef:
	load_all()  # populates _by_id on the first call, then costs a branch
	return _by_id.get(id, null)


## Whether a def belongs to `civ` — its own, or shared by everyone.
##
## `neutral` is the shared pool: founders and gatherers are the opening
## and the economy rather than an army type, so every civ fields the same
## ones and only the ARMY archetypes are civ-specific (D-047).
static func _available_to(def: UnitDef, civ: StringName) -> bool:
	return def.civ == civ or def.civ == &"neutral"


## Every unit `civ` may field, in the roster's stable order.
##
## A civ's roster is DERIVED from which unit files name it (D-047), not
## listed in `CivDef`. Adding a `.tres` gives that civ a type, and there
## is no register that can disagree with the files.
static func for_civ(civ: StringName) -> Array[UnitDef]:
	var out: Array[UnitDef] = []
	for def in load_all():
		if _available_to(def, civ):
			out.append(def)
	return out


## This civ's version of an archetype, or null if it does not field one.
##
## THE lookup that keeps every script civ-agnostic (D-046 criterion 3).
## Callers ask for "this player's spearmen" and never for a civ id: the
## client's keybinds, a building's `produces` list and the AI all go
## through here, so one key trains your own civ's spearmen whatever that
## civ happens to call them.
static func for_civ_archetype(civ: StringName, archetype: StringName) -> UnitDef:
	for def in load_all():
		if def.archetype == archetype and _available_to(def, civ):
			return def
	return null


## Which archetypes `civ` can field. Each civ gets a SUBSET (D-047), so
## this is genuinely different per civ rather than a constant list.
static func archetypes_for(civ: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for def in for_civ(civ):
		if not out.has(def.archetype):
			out.append(def.archetype)
	return out
