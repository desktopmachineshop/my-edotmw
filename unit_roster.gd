extends RefCounted
class_name UnitRoster

## Loads the data-driven unit roster from /units/*.tres (D-010).
##
## Exists so the server, the client, and the tests all discover units the
## same way. Adding a unit means adding a .tres — nothing here or anywhere
## else needs to learn its name.

const UNITS_DIR := "res://units"


## Every UnitDef in /units, sorted by id so iteration order is stable.
## Stability matters: the server picks a default unit from this list, and
## a replay is only reproducible if that pick doesn't depend on filesystem
## enumeration order.
static func load_all() -> Array[UnitDef]:
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
	for def in load_all():
		if def.id == id:
			return def
	return null
