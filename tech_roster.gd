extends RefCounted
class_name TechRoster

## Loads the tech tree and the epoch ladder from `/techs/*.tres` and
## `/epochs/*.tres` (`D-20260827-the-tree-is-the-ladder`).
##
## `UnitRoster`'s and `CivRoster`'s sibling, deliberately the same shape so
## there is one pattern to learn — including the caching, which is not a
## micro-optimisation: `UnitRoster.by_id` re-scanned its directory on every
## call and spent 858 ms inside one simulation tick (D-043). The AI asks
## what it could research on a decision tick, so this is on that path.

const TECHS_DIR := "res://techs"
const EPOCHS_DIR := "res://epochs"

static var _cache: Array[TechDef] = []
static var _by_id := {}
static var _by_civ_line := {}
static var _defining := {}
static var _epochs: Array[EpochDef] = []


## Drop the caches. Only for tests that write .tres at runtime.
static func reload() -> void:
	_cache = []
	_by_id = {}
	_by_civ_line = {}
	_defining = {}
	_epochs = []


## Every TechDef, sorted by id so iteration order is stable — the same
## reason `UnitRoster.load_all` sorts. A replay reproduces only if the
## order techs are considered in does not depend on filesystem
## enumeration.
static func load_all() -> Array[TechDef]:
	if not _cache.is_empty():
		return _cache

	var out: Array[TechDef] = []
	var dir := DirAccess.open(TECHS_DIR)
	if dir == null:
		# Not an error: a build with no /techs is a build with no tech
		# tree, and every gate below degrades to "everything is
		# available", which is exactly the game as it shipped before this.
		return out

	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()

	for name in names:
		var def := load("%s/%s" % [TECHS_DIR, name]) as TechDef
		if def == null:
			push_error("TechRoster: %s/%s did not load as a TechDef" % [TECHS_DIR, name])
			continue
		var invalid := def.validate()
		if invalid != "":
			push_error("TechRoster: %s" % invalid)
			continue
		out.append(def)

	_cache = out
	_by_id = {}
	_by_civ_line = {}
	_defining = {}
	for def in out:
		_by_id[def.id] = def
		_by_civ_line[[def.civ, def.line]] = def
		if def.defining:
			var lines: Array = _defining.get(def.epoch, [])
			if not lines.has(def.line):
				lines.append(def.line)
			_defining[def.epoch] = lines
	return out


static func by_id(id: StringName) -> TechDef:
	load_all()
	return _by_id.get(id, null)


## This civ's version of `line`, or null if it has none.
##
## An exact civ match WINS over the neutral trunk, checked explicitly
## rather than by relying on which id sorts first. `UnitRoster` resolves
## by id order and a neutral def therefore SHADOWS every per-civ one —
## which is how the per-civ gatherers went quietly absent for a whole
## change in `D-20260823-the-opening-is-a-crew-and-a-general`. The same
## trap here would silently give every civ the trunk name for a tech that
## six civs each have their own word for, and nothing would fail.
static func for_civ_line(civ: StringName, line: StringName) -> TechDef:
	load_all()
	var own = _by_civ_line.get([civ, line], null)
	if own != null:
		return own
	return _by_civ_line.get([&"neutral", line], null)


## Every line this civ can research at all, sorted.
static func lines_for(civ: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for def in load_all():
		if (def.civ == civ or def.civ == &"neutral") and not out.has(def.line):
			out.append(def.line)
	out.sort()
	return out


## Every tech this civ could ever research, in id order.
static func for_civ(civ: StringName) -> Array[TechDef]:
	var out: Array[TechDef] = []
	for line in lines_for(civ):
		var def := for_civ_line(civ, line)
		if def != null:
			out.append(def)
	out.sort_custom(func(a: TechDef, b: TechDef) -> bool: return a.id < b.id)
	return out


## The LINES on epoch `epoch`'s defining line. Empty for the top rung,
## which defines nothing because nothing is above it.
static func defining_lines(epoch: int) -> Array[StringName]:
	load_all()
	var out: Array[StringName] = []
	for line in _defining.get(epoch, []):
		out.append(line)
	out.sort()
	return out


## Every EpochDef, sorted by index.
static func epochs() -> Array[EpochDef]:
	if not _epochs.is_empty():
		return _epochs

	var out: Array[EpochDef] = []
	var dir := DirAccess.open(EPOCHS_DIR)
	if dir == null:
		return out
	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()
	for name in names:
		var def := load("%s/%s" % [EPOCHS_DIR, name]) as EpochDef
		if def == null:
			push_error("TechRoster: %s/%s did not load as an EpochDef" % [EPOCHS_DIR, name])
			continue
		var invalid := def.validate()
		if invalid != "":
			push_error("TechRoster: %s" % invalid)
			continue
		out.append(def)
	out.sort_custom(func(a: EpochDef, b: EpochDef) -> bool: return a.index < b.index)
	_epochs = out
	return out


## The top rung. 1 when there is no ladder at all, so a build with no
## `/epochs` is permanently in epoch 1 and every gate reads "available" —
## the game as it shipped before the tree.
static func max_epoch() -> int:
	var all := epochs()
	if all.is_empty():
		return 1
	return all[all.size() - 1].index


static func epoch_at(index: int) -> EpochDef:
	for def in epochs():
		if def.index == index:
			return def
	return null


## What a player of `civ` calls epoch `index`. `CivDef.epoch_names` is
## flavour only and may be short or empty; the EpochDef's name is the
## fallback, so a civ that names none still reads sensibly.
static func epoch_name(civ: StringName, index: int) -> String:
	var civ_def := CivRoster.effects_of(civ)
	if index >= 1 and index <= civ_def.epoch_names.size():
		var own: String = civ_def.epoch_names[index - 1]
		if own != "":
			return own
	var def := epoch_at(index)
	return def.display_name if def != null else "Epoch %d" % index
