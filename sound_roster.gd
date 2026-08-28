extends RefCounted
class_name SoundRoster

## Loads `/audio/*.tres` in a stable order (#344).
##
## The sibling of `unit_roster.gd` and `civ_roster.gd`, and deliberately
## the same shape: adding a sound is adding a FILE, and nothing in code
## learns its name. A test fails if any `.gd` names a `.wav`.
##
## Cached, for `UnitMesh`'s reason: a roster re-read from disk per lookup
## is the M4 `by_id` defect with a smaller constant, and this one is
## consulted on every casualty event.

const DIR := "res://audio"

static var _by_event := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_by_event.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		# No audio directory is a legitimate state — a clone that has not
		# run `just build-audio`, or a headless run that wants none. The
		# game must lose SOUND, never function (D-064's designed
		# degradation, and the same rule `model_id` empty follows).
		return
	var names := []
	for file in dir.get_files():
		# .remap appears in exported builds; .import never does for a
		# .tres. Take the resource name either way.
		var name := String(file)
		if name.ends_with(".remap"):
			name = name.substr(0, name.length() - 6)
		if name.ends_with(".tres"):
			names.append(name)
	names.sort()   # stable order — server, client and tests agree
	for name in names:
		var def := load(DIR + "/" + name) as SoundDef
		if def == null or String(def.event) == "":
			continue
		# FIRST wins, and the order is sorted, so a duplicate event is
		# resolved deterministically rather than by directory order.
		if not _by_event.has(def.event):
			_by_event[def.event] = def


## The cue for an event, or null when nothing answers it. Null is not an
## error: an event with no sound is silence, which is what an incomplete
## table should sound like rather than a crash.
static func by_event(event: StringName) -> SoundDef:
	_load()
	return _by_event.get(event, null)


## Every event the table answers, sorted. For tests and for the settings
## screen; nothing in the hot path needs it.
static func events() -> Array:
	_load()
	var out := _by_event.keys()
	out.sort()
	return out


## Drop the cache. Tests that write a temporary table need this; nothing
## in a running match should call it.
static func reload() -> void:
	_loaded = false
	_by_event.clear()
