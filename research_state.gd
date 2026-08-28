extends RefCounted
class_name ResearchState

## What each player has RESEARCHED, and therefore which epoch they are in
## and what their troops are made of
## (`D-20260827-the-tree-is-the-ladder`).
##
## Server-authoritative. A client holds one of these too, containing its
## OWN player's lines and its allies' — never an enemy's, because what an
## opponent has researched is exactly the thing a scout is for, and a
## client that hashed an upgrade it was never told about would desync a
## perfectly healthy system (D-099's ghost rule, pointed at a different
## field).
##
## Holds no scene tree, no socket and no rendering, so a GUT test drives
## the real thing rather than a stand-in.

## player -> { line: true }
var _lines := {}

## player -> { line: true } — started, not yet finished. A second building
## may not begin a line already in progress, and this is where that is
## known. Per PLAYER, because a tech is researched once for a player and
## not once per building.
var _pending := {}

## Memoised resolved defs, dropped whole for a player when that player
## completes anything. player -> { cache_key: Resource }
var _resolved := {}


func reset() -> void:
	_lines = {}
	_pending = {}
	_resolved = {}


func has(player: int, line: StringName) -> bool:
	return (_lines.get(player, {}) as Dictionary).has(line)


func is_pending(player: int, line: StringName) -> bool:
	return (_pending.get(player, {}) as Dictionary).has(line)


func lines_of(player: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for line in (_lines.get(player, {}) as Dictionary):
		out.append(line)
	out.sort()
	return out


func begin(player: int, line: StringName) -> void:
	var pending: Dictionary = _pending.get(player, {})
	pending[line] = true
	_pending[player] = pending


## Give a started line back — a cancelled queue, a razed research site.
func abandon(player: int, line: StringName) -> void:
	(_pending.get(player, {}) as Dictionary).erase(line)


## The one writer. Dropping the whole resolved cache for this player is
## what makes techs RETROACTIVE without any call site knowing: the next
## `unit_def()` for any archetype re-resolves, and the server re-points
## `SquadSim._defs` for squads that already exist.
func grant(player: int, line: StringName) -> void:
	var held: Dictionary = _lines.get(player, {})
	held[line] = true
	_lines[player] = held
	(_pending.get(player, {}) as Dictionary).erase(line)
	_resolved.erase(player)


## Every TechDef this player holds, resolved against their civ.
func techs_of(player: int, civ: StringName) -> Array:
	var out: Array = []
	for line in lines_of(player):
		var def := TechRoster.for_civ_line(civ, line)
		if def != null:
			out.append(def)
	return out


## Which epoch this player is in. 1 until they complete a defining line.
##
## Consecutive from the bottom on purpose: holding epoch 3's defining
## techs while missing epoch 2's does not put you in epoch 4. It cannot
## happen through the ordinary gate (`can_research` refuses a tech above
## your epoch), but a scenario granting an arbitrary set could, and
## "highest complete rung" would then read as a rung you skipped.
func epoch_of(player: int, civ: StringName) -> int:
	var top := TechRoster.max_epoch()
	var at := 1
	while at < top:
		var lines := TechRoster.defining_lines(at)
		if lines.is_empty():
			break
		for line in lines:
			# A defining line this civ has no tech for would strand it
			# here forever; `tests/test_tech_tree.gd` asserts that cannot
			# happen, and the check is not repeated per tick.
			if not has(player, line):
				return at
		at += 1
	return at


## Why this player may not start `line` right now, or "" if they may.
##
## The server owns the rules so it owns the explanation (`server._notify`'s
## reasoning) — a client inventing its own refusal text would be a second
## copy of these rules, free to drift.
func can_research(player: int, civ: StringName, line: StringName) -> String:
	var def := TechRoster.for_civ_line(civ, line)
	if def == null:
		return "Your people have no such craft"
	if has(player, line):
		return "%s is already known" % def.display_name
	if is_pending(player, line):
		return "%s is already being researched" % def.display_name
	if def.epoch > epoch_of(player, civ):
		return "%s belongs to a later age" % def.display_name
	for needed in def.requires:
		if not has(player, needed):
			var prior := TechRoster.for_civ_line(civ, needed)
			return "%s needs %s first" % [def.display_name,
				prior.display_name if prior != null else String(needed)]
	return ""


## Every tech this player could start right now, in id order.
func available(player: int, civ: StringName) -> Array:
	var out: Array = []
	for def in TechRoster.for_civ(civ):
		if can_research(player, civ, (def as TechDef).line) == "":
			out.append(def)
	return out


## Is `requires_tech` satisfied? Empty means always — the safe default
## that keeps every shipped `.tres` producible without being edited.
func unlocked(player: int, line: StringName) -> bool:
	return line == &"" or has(player, line)


# --- resolved definitions ---------------------------------------------
#
# One memo per (player, def). Cleared for a player by `grant`, which is
# what makes retroactivity free. Keyed by the BASE def's id rather than by
# archetype, because a caller may legitimately ask about a def that is not
# this player's own (the sandbox spawner, a scenario).


func unit_def(player: int, civ: StringName, base: UnitDef) -> UnitDef:
	if base == null:
		return null
	var cache: Dictionary = _resolved.get(player, {})
	var key := "u:%s" % base.id
	if cache.has(key):
		return cache[key]
	var out := TechEffects.resolve_unit(base, techs_of(player, civ))
	cache[key] = out
	_resolved[player] = cache
	return out


func building_def(player: int, civ: StringName, base: BuildingDef,
		archetype: StringName) -> BuildingDef:
	if base == null:
		return null
	var cache: Dictionary = _resolved.get(player, {})
	var key := "b:%s" % base.id
	if cache.has(key):
		return cache[key]
	var out := TechEffects.resolve_building(base, techs_of(player, civ), archetype)
	cache[key] = out
	_resolved[player] = cache
	return out


func civ_def(player: int, base: CivDef) -> CivDef:
	if base == null:
		return null
	var cache: Dictionary = _resolved.get(player, {})
	var key := "c:%s" % base.id
	if cache.has(key):
		return cache[key]
	var out := TechEffects.resolve_civ(base, techs_of(player, base.id))
	cache[key] = out
	_resolved[player] = cache
	return out
