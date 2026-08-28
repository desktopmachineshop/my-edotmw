extends GutTest

## Where a produced squad appears, and who owns it (#132).
##
## From a lobby playtest, 2026-08-18: *"gatherers built in player's town
## hall came out of an enemy town hall"*. The issue was filed explicitly
## NOT reproduced — read from the code, the path does not permit it — and
## CLAUDE.md's standing rule is that a check must be observed to fail
## before it is trusted. So this file does two things and is honest about
## which is which:
##
## 1. It drives the REAL production path end to end — `server.
##    _handle_order_produce`, `BuildingSim.advance_production`,
##    `SquadSim.tick`'s spawn — against two players' town halls, and
##    asserts the produced squad's OWNER and its CELL both come from the
##    building that was enqueued at. Every one of those assertions has
##    been observed to fail against a deliberately broken server (the
##    perturbations are named on each test).
## 2. It pins the id-space hazard CLAUDE.md flags as standing — `SquadSim`
##    and `BuildingSim` both mint ids from their own array length, and
##    only `wire_id()` keeps them apart — because a raw-id crossover is
##    the one mechanism that would produce the reported symptom literally.
##
## What it does NOT do is reproduce the report. It could not be
## reproduced, and this file is the record of that: the production path
## reads position and owner from the SAME building index, so a squad
## appearing at an enemy hall would also be owned by that enemy, which is
## not what was reported. See the issue for the one observation that would
## split the remaining candidates.
##
## Testable at all for the reason `test_civ_knobs.gd` sets out: "server.gd
## needs a socket and a scene tree" is true of `_ready()`, not of the
## file, and `LoopbackPeer` is the server's own stand-in for a socket
## (D-051).

const W := 64
const H := 32

## Far enough apart that no spawn ring can reach from one to the other:
## `SquadSim._spawn_cell_near` searches `disk_offsets(4)`, so 21 cells is
## the reported session's own hall separation and five times the reach.
const HALL_A := Vector2i(8, 8)
const HALL_B := Vector2i(29, 8)


## Two players, a completed town centre each, and enough in both wallets
## that affordability is never what refuses an order.
func _world() -> Dictionary:
	var server = load("res://server.gd").new()
	var space := TorusSpace.new(W, H, 1.0)

	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy

	server._match = MatchState.new()
	server._match.squad_cap = 40
	for player in [1, 2]:
		server._match.add_player(player)
		server._civs[player] = CivRoster.load_all()[0].id if not CivRoster.load_all().is_empty() else &""
	server._match.phase = MatchState.Phase.RUNNING
	server._hand_civs_to_sim()

	var hall := BuildingSim.def_by_id(&"town_centre")
	assert_not_null(hall, "the shipped town centre is where BuildingSim looks for it")
	var a: int = server._buildings.add_building(hall, 1, HALL_A, true)
	var b: int = server._buildings.add_building(hall, 2, HALL_B, true)

	var peers := {}
	for player in [1, 2]:
		for kind in range(Economy.RESOURCE_COUNT):
			server._economy.credit(player, kind, 100000)
		var peer := LoopbackPeer.new()
		server._ai_clients[peer] = {"player": player, "visible": {}}
		peers[player] = peer

	# Never added to the tree (that is what keeps `_ready()` — and its
	# socket — out of these tests), so nothing else will free it.
	autofree(server)

	return {
		"server": server, "space": space, "peers": peers,
		"hall": {1: a, 2: b}, "def": hall,
	}


## Something a town centre makes for this civ, never the general — one
## living general per player is its own production gate, and a refusal
## there would read as this bug rather than as that rule.
func _producible(server, player: int, hall_def: BuildingDef) -> UnitDef:
	for archetype in hall_def.produces:
		var unit := UnitRoster.for_civ_archetype(server._civ_of(player), archetype)
		if unit != null and not unit.is_general:
			return unit
	return null


func _produce(w: Dictionary, player: int, building: int, unit: UnitDef) -> void:
	w["server"]._handle_order_produce(w["peers"][player],
		NetProtocol.encode_order_produce(BuildingSim.wire_id(building), String(unit.archetype)))


## Run the sim until the queue empties, or give up loudly.
func _tick_until_produced(w: Dictionary, building: int) -> void:
	var server = w["server"]
	for _i in range(6000):
		if server._buildings.queue_length(building) == 0 and server._sim.squad_count() > 0:
			return
		server._sim.tick()
	fail_test("nothing was produced in ten minutes of simulated time")


# --- the report, asserted the way it was described ---------------------

## The whole of #132 in one assertion pair: a squad trained at MY hall is
## MINE and stands at MY hall.
##
## Observed to fail: making `SquadSim.tick`'s production block read
## `_spawn_cell_near(buildings, at + 1)` puts the crew at the enemy hall
## and reds the distance assertion; making it `owner_of(at + 1)` reds the
## ownership one. Those two perturbations are the two halves of the
## report, and they are the reason this is a pair rather than one check —
## "my gatherers at their hall" and "their gatherers at their hall" are
## different faults with the same first sentence.
func test_a_squad_trained_at_my_hall_is_mine_and_stands_at_my_hall() -> void:
	var w := _world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	var unit := _producible(server, 1, w["def"])
	assert_not_null(unit, "this civ's town centre makes nothing")

	_produce(w, 1, w["hall"][1], unit)
	assert_eq(server._buildings.queue_length(w["hall"][1]), 1,
		"the order should have been accepted, or nothing below is measuring production")
	_tick_until_produced(w, w["hall"][1])

	assert_eq(server._sim.squad_count(), 1, "exactly one squad was paid for")
	assert_eq(server._sim.owner_of(0), 1, "the squad belongs to the player who paid for it")

	var at: Vector2i = server._sim.cell_of(0)
	var to_mine := space.distance(at, HALL_A)
	var to_theirs := space.distance(at, HALL_B)
	assert_lte(to_mine, 4,
		"a recruit steps out of the door: %s is %d cells from its own hall" % [at, to_mine])
	assert_gt(to_theirs, to_mine,
		"%s is nearer the ENEMY hall (%d) than its own (%d) — this is the report" % [
			at, to_theirs, to_mine])


## The other side of it: neither hall's production can be aimed at the
## other's. Ownership is checked at the ORDER gate, so a client cannot
## enqueue at a building it does not own however it addresses it.
##
## Observed to fail with `server.gd`'s `owner_of(building) != player`
## refusal removed: the order is accepted and a squad appears at the
## enemy's hall.
func test_a_player_cannot_train_at_an_enemy_hall() -> void:
	var w := _world()
	var server = w["server"]
	var unit := _producible(server, 1, w["def"])

	_produce(w, 1, w["hall"][2], unit)
	# The refusal is a `push_error` on purpose (server.gd), so claiming it
	# here is both how GUT is told the error was wanted AND a second
	# assertion: the server must say WHY, not drop the order quietly.
	assert_push_error("does not own",
		"the server must report the refusal, not swallow it")
	assert_eq(server._buildings.queue_length(w["hall"][2]), 0,
		"an order aimed at an enemy building must be refused, not queued")
	assert_eq(server._buildings.queue_length(w["hall"][1]), 0,
		"...and must not be redirected to a building the player DOES own")


## Both players producing at once, which is the state the report was made
## in and the one an index defect would surface in: two queues, two
## buildings, one `advance_production` pass over a Dictionary.
##
## Observed to fail with `advance_production` returning a fixed
## `{"building": 0}` instead of its own key — the exact shape of the
## crossover the issue's third candidate describes. That perturbation is
## also what showed the first version of this test to be vacuous; see the
## comment on the ownership pass below.
func test_two_halls_producing_at_once_keep_their_own_recruits() -> void:
	var w := _world()
	var server = w["server"]
	var space: TorusSpace = w["space"]

	for player in [1, 2]:
		var unit := _producible(server, player, w["def"])
		assert_not_null(unit, "player %d's town centre makes nothing" % player)
		_produce(w, player, w["hall"][player], unit)

	for _i in range(6000):
		if server._sim.squad_count() >= 2:
			break
		server._sim.tick()
	assert_eq(server._sim.squad_count(), 2, "both players paid for a squad")

	# Asked per PLAYER, not per squad. The first version of this test read
	# each squad's owner and then measured against that owner's hall,
	# which cannot see the failure it was written for: a production pass
	# that reports one fixed building key gives BOTH recruits to player 1
	# at player 1's hall, and every per-squad assertion passes. Observed —
	# `advance_production` returning `{"building": 0}` left this test green
	# until it was rewritten this way, which is precisely the vacuity
	# D-022's audit block is about.
	var seen := {}
	for squad in range(2):
		seen[server._sim.owner_of(squad)] = squad
	for player in [1, 2]:
		assert_true(seen.has(player),
			"player %d paid for a squad and does not own one — production reached the wrong building" % player)
	if seen.size() < 2:
		return

	for player in [1, 2]:
		var home: Vector2i = HALL_A if player == 1 else HALL_B
		var away: Vector2i = HALL_B if player == 1 else HALL_A
		var at: Vector2i = server._sim.cell_of(int(seen[player]))
		assert_lte(space.distance(at, home), 4,
			"player %d's squad stands %d cells from its own hall" % [
				player, space.distance(at, home)])
		assert_gt(space.distance(at, away), space.distance(at, home),
			"player %d's squad stands nearer the other player's hall" % player)


## A rally point is where a recruit WALKS, never where it appears. Worth
## pinning because it is the one thing in this path that can legitimately
## send a squad far from the hall that made it, so a future reader
## chasing this report again does not mistake a rally for a spawn.
func test_a_rally_point_moves_a_recruit_but_does_not_spawn_it_there() -> void:
	var w := _world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	var far := space.normalize(HALL_A + Vector2i(0, 12))
	server._buildings.set_rally(w["hall"][1], far)

	var unit := _producible(server, 1, w["def"])
	_produce(w, 1, w["hall"][1], unit)
	_tick_until_produced(w, w["hall"][1])

	var at: Vector2i = server._sim.cell_of(0)
	assert_lte(space.distance(at, HALL_A), 4,
		"a rally point is a destination, not a spawn: %s" % at)
	assert_eq(server._sim.destination_of(0), far,
		"...and the recruit is walking to it")


# --- the id-space hazard the report points at (CLAUDE.md, standing) ----

## `SquadSim` and `BuildingSim` both mint ids from their own array
## length, so squad 0 and building 0 both exist, and only
## `BuildingSim.wire_id`/`local_id` keep them apart on the wire. That is
## the one mechanism that would produce the reported symptom literally, so
## the boundary is pinned rather than trusted: a squad's wire id must
## never be readable as a building's.
func test_a_squads_id_can_never_be_read_as_a_buildings() -> void:
	var w := _world()
	var server = w["server"]
	var unit := _producible(server, 1, w["def"])
	_produce(w, 1, w["hall"][1], unit)
	_tick_until_produced(w, w["hall"][1])

	for squad in range(server._sim.squad_count()):
		assert_false(BuildingSim.is_building_id(squad),
			"squad %d's id reads as a building's" % squad)
		assert_eq(BuildingSim.local_id(squad), -1,
			"squad %d's id decodes to a building" % squad)
	for building in range(server._buildings.building_count()):
		assert_eq(BuildingSim.local_id(BuildingSim.wire_id(building)), building,
			"building %d does not survive the wire round trip" % building)


## And the ORDER gate refuses a raw local id, which is what a crossover
## would look like arriving from a client: building 0's local id is 0,
## and 0 is also a perfectly good squad id.
##
## Observed to fail with `_handle_order_produce`'s `building < 0` guard
## removed — `local_id(0)` is -1, and `_owner[-1]` is the LAST building
## in the array on a Godot packed array, which is very often somebody
## else's.
func test_a_raw_local_id_is_not_a_valid_produce_target() -> void:
	var w := _world()
	var server = w["server"]
	var unit := _producible(server, 1, w["def"])

	server._handle_order_produce(w["peers"][1],
		NetProtocol.encode_order_produce(w["hall"][1], String(unit.archetype)))
	for building in [w["hall"][1], w["hall"][2]]:
		assert_eq(server._buildings.queue_length(building), 0,
			"a raw local id must name nothing, not the building at that array slot")
