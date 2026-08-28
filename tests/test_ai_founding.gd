extends GutTest

## An AI seat founds a town centre even when its spawn cell is blocked
## (#217).
##
## The reported failure: a seat whose spawn cell held a resource node
## never founded — not late, ever. `AiPlayer._found_town` computed its
## site from `ClientState.spawn_cell_of(player)`, which never moves, so
## every five-second retry re-sent the identical refused order for the
## whole match. `buildings=0`, `peak_wood=200` against a 150-wood hall,
## eliminated as soon as its two opening squads died — and reported by
## the ladder as a decisive win for the other side.
##
## D-107 made the AI retry. Nothing made it retry ANYWHERE ELSE, which is
## the gap. Its sibling `_raise_buildings` has varied its site since it
## was written (`_site_beside`), so the town-centre path was the only
## build in the file that retried a constant cell.
##
## ## Driven through the real server, on purpose
##
## The AI's orders go through `server._dispatch` exactly as
## `_seat_ai` wires them (D-051), so `_build_refusal` is the thing
## refusing here rather than a stand-in — a test that modelled the
## refusal itself would prove the AI retries and say nothing about
## whether it retries past the rule that actually blocked it.
##
## "server.gd needs a socket and a scene tree" is true of `_ready()`, not
## of the file (`test_civ_knobs.gd` sets out why), and `LoopbackPeer` is
## the server's own stand-in for a socket.

const W := 32
const H := 16
const HOME := Vector2i(8, 8)


## A server far enough along to answer a build order, with one AI seat
## wired the way `_seat_ai` wires one, and nothing else.
func _world() -> Dictionary:
	var server = load("res://server.gd").new()
	autofree(server)
	var space := TorusSpace.new(W, H, 1.0)

	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy

	server._match = MatchState.new()
	server._match.squad_cap = 40
	server._match.phase = MatchState.Phase.RUNNING

	var civ: StringName = CivRoster.ids()[0]
	var brain := AiPlayer.new(1000, civ)
	server._civs[1000] = civ
	server._match.add_ai_player(1000, civ, 0)
	server._hand_civs_to_sim()

	var peer := LoopbackPeer.new(brain.state)
	brain.send = func(packet: PackedByteArray) -> void:
		server._dispatch(peer, packet)
	server._ai_clients[peer] = {"player": 1000, "visible": {}}

	# The crew that founds, standing on its own start. Resolved through
	# `built_by` like the AI itself does, so this names no unit and no civ
	# (D-047) — and so it keeps working when the roster moves under it,
	# which is the fixture lesson `docs/status/the-opening.md` records.
	var hall := BuildingSim.def_by_id(&"town_centre")
	var crew := _founder_def(civ, hall)
	assert_not_null(crew, "this civ fields nothing that may found a town centre")
	server._sim.add_squad(crew, 1000, HOME)

	for kind in range(Economy.RESOURCE_COUNT):
		server._economy.credit(1000, kind, 100000)

	var starts: Array[Vector2i] = [HOME]
	server._spawn_points = starts
	return {"server": server, "brain": brain, "peer": peer, "space": space, "hall": hall}


func _founder_def(civ: StringName, hall: BuildingDef) -> UnitDef:
	for def in UnitRoster.load_all():
		if def.civ != civ and String(def.civ) != "neutral":
			continue
		if BuildingSim.can_build(hall, def.archetype):
			return def
	return null


## Replicate to the AI the way the server's own loop does. The seat has to
## learn where its start IS (the WELCOME carries `spawns`) and what stands
## on the ground (`NODES`), because both are inputs to the decision under
## test.
func _feed(w: Dictionary) -> void:
	var server = w["server"]
	var brain: AiPlayer = w["brain"]
	var visible: Array = server._sim.visible_to(1000)
	brain.state.handle_packet(NetProtocol.encode_welcome(
		1000, W, H, visible, server._spawn_points.map(
			func(cell: Vector2i) -> int: return w["space"].index(cell)), 40))
	brain.state.handle_packet(NetProtocol.encode_squad_info(
		server._sim.squad_info_entries(visible)))
	brain.state.handle_packet(NetProtocol.encode_nodes(_visible_nodes(server)))
	for packet in server._sim.replicator.collect_for_client(
			1000, server._sim.time, visible):
		brain.state.handle_packet(NetProtocol.encode_curve(packet["bytes"]))


## Every node, because in these fixtures the AI's own crew is standing on
## them — the server's own gating (`node_entries(only)`) would give the
## same answer here, and asking for it would need the vision plumbing this
## fixture deliberately does not stand up.
func _visible_nodes(server) -> Array:
	return server._economy.node_entries()


## Let the AI think and the world turn, for `seconds` of match time.
func _play(w: Dictionary, seconds: float) -> void:
	var server = w["server"]
	var brain: AiPlayer = w["brain"]
	var steps := int(seconds * SquadSim.TICK_HZ)
	for _i in range(steps):
		server._sim.tick()
		_feed(w)
		brain.set_time(server._sim.time)
		brain.update(server._sim.time)


## A resource node on a cell, written the way `Economy.generate` writes
## one. There is no public setter — nodes are generated, never placed —
## and inventing one for a test would be a second way to make a node.
func _plant(server, index: int) -> void:
	server._economy.nodes[index] = {
		"kind": Economy.ResourceKind.WOOD,
		"remaining": server._economy.stock_for(Economy.ResourceKind.WOOD),
	}


func _halls_owned(w: Dictionary) -> int:
	var server = w["server"]
	var count := 0
	for i in range(server._buildings.building_count()):
		if server._buildings.owner_of(i) == 1000 and not server._buildings.is_destroyed(i):
			count += 1
	return count


# --- the report ---------------------------------------------------------

## The clean case, so the blocked one below cannot pass by accident: with
## nothing on the start, the seat founds.
func test_an_ai_on_clear_ground_founds_its_town_centre() -> void:
	var w := _world()
	_play(w, 20.0)
	assert_eq(_halls_owned(w), 1,
		"an AI on empty ground must found a hall, or this file is measuring nothing")


## #217 itself. Observed to fail before the fix: on `main` this reports 0
## halls after two hundred seconds of match time, because every retry
## re-sends the same refused cell.
func test_an_ai_whose_start_holds_a_resource_node_still_founds() -> void:
	var w := _world()
	var server = w["server"]
	_plant(server, w["space"].index(HOME))
	assert_true(server._economy.has_node(w["space"].index(HOME)),
		"the node must actually be on the start, or nothing is being blocked")

	_play(w, 40.0)
	assert_eq(_halls_owned(w), 1,
		"an AI whose spawn cell is blocked must found somewhere else, not retry it forever")


## ...and it settles NEXT TO its start rather than wherever it can. A
## founding that wanders is a different bug wearing this one's fix: the
## seat's start is where the map decided the player belongs, and a hall
## planted across the valley gives up D-104's fairness guarantee.
func test_the_hall_it_founds_instead_is_still_at_home() -> void:
	var w := _world()
	var server = w["server"]
	_plant(server, w["space"].index(HOME))
	_play(w, 40.0)
	assert_eq(_halls_owned(w), 1, "nothing was founded, so the distance below means nothing")

	for i in range(server._buildings.building_count()):
		if server._buildings.owner_of(i) != 1000:
			continue
		var at: Vector2i = server._buildings.cell_of(i)
		assert_lte(w["space"].distance(at, HOME), AiPlayer.FOUND_SEARCH_RADIUS,
			"the hall went up at %s, %d cells from the start" % [
				at, w["space"].distance(at, HOME)])


## A whole ring of blocked ground, not one cell — the fix must walk
## OUTWARD rather than merely take a neighbour. This is the shape D-104's
## fairness pass can actually produce, since it tops resources up near
## starts.
func test_an_ai_walled_in_by_nodes_founds_beyond_them() -> void:
	var w := _world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	for offset in TorusSpace.disk_offsets(1):
		_plant(server, space.index(HOME + offset))

	_play(w, 60.0)
	assert_eq(_halls_owned(w), 1,
		"a start ringed by nodes must still be settled, one ring further out")
	for i in range(server._buildings.building_count()):
		var at: Vector2i = server._buildings.cell_of(i)
		assert_gt(space.distance(at, HOME), 1,
			"the hall went up at %s, which is inside the blocked ring" % at)


# --- the site chooser, on its own ---------------------------------------

## `_found_site` answers a DIFFERENT cell each time it is asked after a
## refusal, and never one it has reason to doubt. Driven directly because
## the loop above cannot show WHICH mechanism moved the site — a fix that
## happened to succeed on its first retry would pass every test above.
func test_the_site_advances_on_every_refused_attempt() -> void:
	var w := _world()
	var server = w["server"]
	var brain: AiPlayer = w["brain"]
	_plant(server, w["space"].index(HOME))
	server._sim.tick()
	_feed(w)

	var seen := {}
	for attempt in range(6):
		var site: Vector2i = brain._found_site(brain._founder())
		assert_false(seen.has(site),
			"attempt %d returned %s again — this is #217" % [attempt, site])
		assert_ne(site, HOME,
			"attempt %d returned the blocked start itself" % attempt)
		seen[site] = true
		brain._found_attempts += 1
	assert_eq(seen.size(), 6, "six attempts should have named six sites")


## And it does NOT wander when there is nothing wrong with home: the first
## attempt on clear ground is the start itself. Without this the test
## above passes for a fix that simply never sites a hall at home.
func test_the_first_attempt_on_clear_ground_is_home_itself() -> void:
	var w := _world()
	var brain: AiPlayer = w["brain"]
	w["server"]._sim.tick()
	_feed(w)
	assert_eq(brain._found_site(brain._founder()), HOME,
		"with nothing in the way the seat should settle exactly where the map put it")


## The site chooser must not run out. The first version of this fix
## skipped `_found_attempts` acceptable cells and fell through to `home`
## once it passed the end of the list, which quietly rebuilt #217 after
## about a dozen refusals — and a real match reached it: on
## `maps/ladder.tres` at seed 7 a seat sent its twelfth attempt at 56 s
## and every attempt from then on at the same blocked start. Found by
## instrumenting a played match, not by a test, which is why this one
## exists now.
func test_the_search_cycles_rather_than_falling_back_to_the_blocked_start() -> void:
	var w := _world()
	var server = w["server"]
	var brain: AiPlayer = w["brain"]
	_plant(server, w["space"].index(HOME))
	server._sim.tick()
	_feed(w)

	# Far past the number of cells in the search disk, so a version that
	# walked off the end is guaranteed to have done so.
	for attempt in range(200):
		brain._found_attempts = attempt
		assert_ne(brain._found_site(brain._founder()), HOME,
			"attempt %d fell back to the blocked start" % attempt)


## ...and cycling means it comes round again, which is the property that
## matters for a refusal that CLEARS later — an enemy claim razed, a node
## worked out. A chooser that only ever moved outward would never re-offer
## the cell that became free.
func test_a_cycled_site_comes_round_again() -> void:
	var w := _world()
	var brain: AiPlayer = w["brain"]
	_plant(w["server"], w["space"].index(HOME))
	w["server"]._sim.tick()
	_feed(w)

	brain._found_attempts = 0
	var first: Vector2i = brain._found_site(brain._founder())
	var period := 0
	for attempt in range(1, 400):
		brain._found_attempts = attempt
		if brain._found_site(brain._founder()) == first:
			period = attempt
			break
	assert_gt(period, 1, "the chooser never returned to its first site")
	brain._found_attempts = period * 2
	assert_eq(brain._found_site(brain._founder()), first,
		"the cycle is not a cycle — two periods on should be the first site again")
