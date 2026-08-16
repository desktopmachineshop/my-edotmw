class_name ScenarioWorld
extends RefCounted

## A complete, ready-to-tick world for a test, with no server, no socket
## and no match opening (D-098).
##
##     var w := ScenarioWorld.build("clash")
##     w.tick(2.0)
##     assert_lt(w.sim.alive_of(w.squads_of(2)[0]), 20)
##
## That is the whole setup for a combat test. The equivalent through the
## real opening is a server, four bots, a town hall at 40 seconds, a
## production queue and two armies walking toward each other across a
## 128x64 map — about two minutes before the thing under test exists.
##
## The pieces are assembled in the SAME ORDER and with the same wiring as
## `server.gd` does it: SquadSim over a TorusSpace, a BuildingSim handed
## to the sim, an Economy handed to the sim, a Vision, a seeded combat
## RNG. Where the server would consult a lobby or a socket, this does not
## — that is the only difference, and it is the point.
##
## What this deliberately does NOT do is run the opening, so it can never
## catch a bug in founding, production or spawn placement. `just test-load
## 4 120` still does, and is still the gate.


var space: TorusSpace
var sim: SquadSim
var buildings: BuildingSim
var economy: Economy
var replicator: CurveReplicator
var passable: PackedByteArray
var terrain: TerrainGen


## The sim's OWN Vision, never a second one. SquadSim constructs and ticks
## it (`squad_sim.gd:165`), and a fixture that made its own would be
## stamping a field the simulation never reads — green tests over an
## object the real game does not use.
var vision: Vision:
	get: return sim.vision if sim != null else null

## Player id -> the Scenario.Placement it got.
var placements := {}
## The scenario this was built from, so a test can assert against the
## loadout instead of hardcoding a copy of it.
var def: ScenarioDef


## Build a world from a scenario id (`res://scenarios/<id>.tres`) or from
## a ScenarioDef built inline by the test.
##
## `players` defaults to 2 because most things worth testing need an
## opponent: a lone player's squads never fight, and fog gates nothing
## when there is nothing to hide.
##
## `flat` defaults to true — every cell passable, no terrain generation.
## Terrain gen is the single most expensive part of standing a world up
## and almost nothing under test depends on it; pass `false` when the
## thing under test is terrain, pathing around water, or biome-derived
## resources.
static func build(scenario, players: int = 2, width: int = 32,
		height: int = 16, flat: bool = true, seed_value: int = 1337) -> ScenarioWorld:
	var d: ScenarioDef = scenario if scenario is ScenarioDef else Scenario.by_id(StringName(str(scenario)))
	if d == null:
		push_error("ScenarioWorld: no scenario '%s'" % scenario)
		return null
	var why := d.validate()
	if why != "":
		push_error("ScenarioWorld: %s" % why)
		return null

	var w := ScenarioWorld.new()
	w.def = d
	w.space = TorusSpace.new(width, height, 1.0)
	w.replicator = CurveReplicator.new()
	w.sim = SquadSim.new(w.space, w.replicator)

	if flat:
		w.passable = PackedByteArray()
		w.passable.resize(w.space.cell_count())
		w.passable.fill(1)
	else:
		# Built the way the server builds it (server.gd:267) — one
		# TerrainGen, passability derived from it, the resource field
		# derived from the same biomes. Two instances would be two sources
		# of truth about the same ground.
		w.terrain = TerrainGen.new()
		w.terrain.noise_seed = seed_value
		w.passable = w.terrain.passability(w.space)
	w.sim.set_passable(w.passable)

	w.buildings = BuildingSim.new(w.space)
	w.sim.buildings = w.buildings

	w.economy = Economy.new(w.space)
	if not flat and w.terrain != null:
		w.economy.generate(w.terrain, 1)
	w.sim.economy = w.economy

	# Seeded, never wall-clock: a scenario that produced a different
	# battle each run would be useless as a test fixture for the same
	# reason it would be useless as a replay (D-024, D-016).
	w.sim.combat_seed = seed_value

	# Players are numbered from 1, as the server numbers humans.
	var civs := CivRoster.load_all()
	var taken := {}
	var homes := Scenario.homes(d, players, w.space, w.passable, [])
	for i in range(players):
		var player := i + 1
		# Round-robin the roster rather than naming a civ: no .gd file in
		# this project may name one, and a fixture that always played the
		# same civ would exercise half the roster (D-046 criterion 10 is
		# the load test's version of the same rule).
		var civ: StringName = civs[i % civs.size()].id if not civs.is_empty() else &""
		w.placements[player] = Scenario.apply_player(d, player, civ,
			homes[i], w.sim, w.buildings, w.economy, w.passable, taken)

	w.stamp_vision()
	return w


## Advance the world by `seconds` of simulated time, at the real 10 Hz
## tick (D-020) — not one big step. A single 2-second tick would resolve
## combat rounds and movement in a way no live server ever does, and a
## fixture that ticks differently from the server is a fixture that
## measures something else.
func tick(seconds: float) -> void:
	# `SquadSim.tick()` takes no delta on purpose — it advances one fixed
	# 10 Hz step and owns its own clock (D-020, D-023). Passing seconds
	# here and converting is what keeps a test readable ("two seconds of
	# fighting") without inventing a variable timestep the server does not
	# have.
	for _i in range(int(round(seconds * SquadSim.TICK_HZ))):
		sim.tick()


## Re-stamp every player's vision, through the sim's own call
## (`SquadSim.recompute_vision_now`) rather than reaching into Vision.
## The server does this on a schedule and on join; a test that has just
## moved something and wants fog to agree calls it.
func stamp_vision() -> void:
	sim.recompute_vision_now()


## The squads a player owns, in id order.
func squads_of(player: int) -> Array[int]:
	var out: Array[int] = []
	for id in range(sim.squad_count()):
		if sim.owner_of(id) == player:
			out.append(id)
	return out


## The buildings a player owns, in id order.
func buildings_of(player: int) -> Array[int]:
	var out: Array[int] = []
	for id in range(buildings.building_count()):
		if buildings.owner_of(id) == player:
			out.append(id)
	return out


## Every placement problem across every player, as one list. A test
## asserts this is empty; a scenario that silently dropped half its army
## would otherwise look like a simulation that lost it.
func skipped() -> Array[String]:
	var out: Array[String] = []
	for p in placements.keys():
		for s in placements[p].skipped:
			out.append("player %d: %s" % [p, s])
	return out
