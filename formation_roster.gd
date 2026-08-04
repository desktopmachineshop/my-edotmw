extends RefCounted
class_name FormationRoster

## Loads the data-driven formation list from /formations/*.tres (D-058).
##
## Same role and deliberately the same shape as `UnitRoster` and
## `CivRoster`, so there is one pattern to learn: server, client and tests
## all discover formations here.
##
## Cached from the first call, and that is not a micro-optimisation.
## `Formation.slot_offset` runs once per soldier per frame — ~26,600 times
## a frame at D-018's full scale — so a definition lookup that touched the
## filesystem would be the fourth instance of the defect that cost 858 ms
## in a single tick (D-043) and 232 µs/squad in vision (M2). /formations is
## read-only at runtime.

const FORMATIONS_DIR := "res://formations"

static var _cache: Array[FormationDef] = []
static var _by_id := {}


## Drop the cache. Only for tests that write .tres files at runtime.
static func reload() -> void:
	_cache = []
	_by_id = {}


## Every formation, sorted by `order` then id so iteration is stable —
## the same reason UnitRoster sorts.
static func load_all() -> Array[FormationDef]:
	if not _cache.is_empty():
		return _cache

	var out: Array[FormationDef] = []
	var dir := DirAccess.open(FORMATIONS_DIR)
	if dir == null:
		push_error("FormationRoster: %s is missing or unreadable" % FORMATIONS_DIR)
		return out

	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()

	for name in names:
		var def := load("%s/%s" % [FORMATIONS_DIR, name]) as FormationDef
		if def != null:
			out.append(def)
	out.sort_custom(func(a, b):
		if a.order != b.order:
			return a.order < b.order
		return String(a.id) < String(b.id))

	_cache = out
	for def in out:
		_by_id[def.id] = def
	return out


static func by_id(id: StringName) -> FormationDef:
	if _by_id.is_empty():
		load_all()
	return _by_id.get(id, null)


## The formations a PLAYER may choose, in their declared order.
##
## Read by the client to build its buttons and by the server to validate
## an order, so the two cannot disagree about what exists — and neither
## holds a list of its own.
static func offered() -> Array[FormationDef]:
	var out: Array[FormationDef] = []
	for def in load_all():
		if def.offered:
			out.append(def)
	return out


static func offered_ids() -> Array:
	var out := []
	for def in offered():
		out.append(def.id)
	return out
