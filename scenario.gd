class_name Scenario
extends RefCounted

## Applies a ScenarioDef to a world (D-098).
##
## ALL-STATIC, for the same structural reason `Formation` is: there is
## nowhere to put state, so "the scenario is applied once and then the
## simulation owns everything" is enforced rather than merely intended. A
## scenario is an opening position, not a participant.
##
## Everything here goes through the ordinary public calls —
## `SquadSim.add_squad`, `BuildingSim.add_building`, `Economy.credit`,
## `UnitRoster.for_civ_archetype`, `BuildingSim.def_by_id`. Nothing writes
## a packed array directly and nothing reimplements placement rules the
## server already has. A fixture that builds the world its own way ends up
## measuring its own way of building it, which is precisely how M4's
## `profile` sweep reported 29 ms for code that took 866 ms live.


## Result of applying a scenario to one player, so a caller (and a test)
## can assert on what actually landed rather than assuming.
class Placement:
	var home: Vector2i
	var squads: Array[int] = []
	var buildings: Array[int] = []
	## Entries that could not be placed at all, as human-readable strings.
	## Never silent: a scenario that quietly dropped half its army would
	## look exactly like a simulation that lost it.
	var skipped: Array[String] = []


## Home cells for `count` players.
##
## `separation > 0` overrides the map's scattered spawn points (D-039) and
## walks the players out along the q axis from an anchor, which is what
## puts two armies within reach at t=0. `separation == 0` uses the points
## the map itself produced, i.e. a realistic start.
##
## Wrap-aware throughout: every cell goes through `space.normalize` via
## `index`/`from_index`, and the anchor walk uses plain axial addition,
## which the torus wraps for free.
static func homes(def: ScenarioDef, count: int, space: TorusSpace,
		passable: PackedByteArray, map_points: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if count <= 0:
		return out

	if def.separation <= 0:
		# The realistic case: whatever the map produced. Falls through to
		# the anchor walk only if the map produced nothing, so a scenario
		# is never silently placed on cell 0.
		if not map_points.is_empty():
			for i in range(count):
				out.append(map_points[i % map_points.size()])
			return out

	# Anchor near the middle of the map, then step `separation` cells per
	# player. The middle is arbitrary but deterministic — a scenario must
	# produce the same world twice, exactly as combat must (D-024).
	var anchor := Vector2i(space.width / 2, space.height / 2)
	var step: int = maxi(1, def.separation)
	var taken := {}
	for i in range(count):
		var want := Vector2i(anchor.x + step * i, anchor.y)
		var cell := free_cell_near(space, want, passable, taken,
			maxi(def.placement_slack, step))
		if cell == INVALID:
			# Better a stacked start than no start: the caller reports it.
			cell = space.normalize(want)
		taken[space.index(cell)] = true
		out.append(cell)
	return out


## Sentinel for "no free cell within the slack". Vector2i has no natural
## null and (0,0) is a real cell, so returning it would place armies on
## the map's corner and look like a placement bug rather than a failure.
const INVALID := Vector2i(-1, -1)


## The nearest free, passable cell to `want`, or INVALID.
##
## Walks `TorusSpace.disk_offsets`, which is sorted nearest-first (D-067),
## so "walk outward until one is free" is a thing this may actually do —
## and it never calls `space.distance()` per candidate, which is the
## standing rule after that defect appeared four separate times (vision,
## UnitRoster.by_id, terrain noise, the building scan).
static func free_cell_near(space: TorusSpace, want: Vector2i,
		passable: PackedByteArray, taken: Dictionary, slack: int) -> Vector2i:
	for offset in TorusSpace.disk_offsets(maxi(0, slack)):
		var cell := space.normalize(want + offset)
		var idx := space.index(cell)
		if taken.has(idx):
			continue
		if passable.size() > idx and passable[idx] == 0:
			continue
		return cell
	return INVALID


## Apply one player's loadout. Returns what landed.
##
## `taken` is shared across players by the caller so two players' armies
## cannot be dealt the same cell — the same reason the server keys spawn
## assignment on seat index rather than player id (D-052's collision).
static func apply_player(def: ScenarioDef, player: int, civ: StringName,
		home: Vector2i, sim: SquadSim, buildings: BuildingSim,
		economy: Economy, passable: PackedByteArray,
		taken: Dictionary) -> Placement:
	var out := Placement.new()
	out.home = home
	var space := sim.space

	# Buildings first: they occupy cells, and a squad placed afterwards
	# should stand beside a town centre rather than inside it.
	for entry in def.buildings:
		var bdef := BuildingSim.def_by_id(entry.building)
		if bdef == null:
			out.skipped.append("building '%s' has no def" % entry.building)
			continue
		var cell := free_cell_near(space, home + entry.offset, passable,
			taken, def.placement_slack)
		if cell == INVALID:
			out.skipped.append("building '%s' found no free cell within %d of %s"
				% [entry.building, def.placement_slack, home + entry.offset])
			continue
		taken[space.index(cell)] = true

		# `complete` is add_building's own parameter and `builder` stays
		# -1: nothing founded these, which is true and is exactly the part
		# of the opening a scenario skips.
		var id := buildings.add_building(bdef, player, cell, entry.complete)
		if entry.health_fraction < 1.0:
			# Through `damage()`, not a health setter, and deliberately:
			# damage is what marks the building dirty for replication.
			# `health_fraction` was on the wire, in ClientState and drawn
			# by the panel, and still only ever carried 1.0 because
			# nothing marked a damaged building dirty (D-061) — a scenario
			# that set health some other way would reproduce that bug.
			buildings.damage(id, bdef.max_health * (1.0 - entry.health_fraction))
		out.buildings.append(id)

	for entry in def.squads:
		var udef := UnitRoster.for_civ_archetype(civ, entry.archetype)
		if udef == null:
			out.skipped.append("no '%s' archetype for this civ" % entry.archetype)
			continue
		for n in range(entry.count):
			var cell := free_cell_near(space, home + entry.offset, passable,
				taken, def.placement_slack)
			if cell == INVALID:
				out.skipped.append("squad '%s' found no free cell within %d of %s"
					% [entry.archetype, def.placement_slack, home + entry.offset])
				break
			taken[space.index(cell)] = true
			var id := sim.add_squad(udef, player, cell)
			if entry.alive > 0:
				sim.set_alive(id, mini(entry.alive, udef.squad_size))
			if entry.shape != "":
				# Through set_shape, not the packed array: a player's
				# choice LATCHES against the sim's per-tick suggestion
				# (D-065), and a scenario writing the array directly would
				# be overwritten within 100 ms and look like a wire bug.
				sim.set_shape(id, entry.shape)
			out.squads.append(id)

	if economy != null:
		for pair in [[Economy.ResourceKind.FOOD, def.food],
				[Economy.ResourceKind.WOOD, def.wood],
				[Economy.ResourceKind.GOLD, def.gold],
				[Economy.ResourceKind.STONE, def.stone]]:
			if pair[1] > 0:
				economy.credit(player, pair[0], pair[1])

	return out


## Load a scenario by id from /scenarios. Mirrors `BuildingSim.def_by_id`
## and `UnitRoster.by_id` so there is one discovery convention.
static func by_id(id: StringName) -> ScenarioDef:
	if id == &"":
		return null
	var path := "res://scenarios/%s.tres" % String(id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ScenarioDef


## Every shipped scenario, in a stable order. Used by `just scenarios` and
## by the test that validates all of them.
static func load_all() -> Array[ScenarioDef]:
	var out: Array[ScenarioDef] = []
	var dir := DirAccess.open("res://scenarios")
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for name in names:
		# Godot exports .tres as .tres.remap; both resolve through load().
		if not name.ends_with(".tres") and not name.ends_with(".tres.remap"):
			continue
		var def := load("res://scenarios/%s" % name.trim_suffix(".remap")) as ScenarioDef
		if def != null:
			out.append(def)
	return out
