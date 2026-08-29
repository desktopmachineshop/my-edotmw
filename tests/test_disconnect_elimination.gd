extends GutTest

## Guards D-20260828-leaving-a-match-leaves-nothing-behind (#292, #318).
##
## D-033's rule is that a disconnect wipes the abandoned army and the
## ORDINARY defeat rule notices, so "defeated" keeps exactly one
## definition. `server.gd`'s comment on the wipe still says so.
##
## The ordinary rule stopped being "no living squads" when
## D-20260823-the-opening-is-a-crew-and-a-general added the buildings
## clause — for an unrelated and correct reason: a crew that founds a
## town hall is consumed by it, so a player making the right opening move
## would otherwise be declared beaten with their hall standing. That
## change silently broke the disconnect path's stated guarantee, and the
## comment asserting the guarantee stayed.
##
## Nothing failed, because both halves are correct on their own. The
## symptom is a match that cannot be won: a quitter's undefended base
## keeps them "active", `_check_victory` never fires, and the remaining
## player has a chore to march across the map and perform before the game
## will end.
##
## Every test here plays the disconnect the way `server.gd` plays it —
## `mark_disconnected` then the wipe then `update` — rather than calling
## the elimination rule directly. A test that asserted the RULE would
## have passed throughout: the rule was never wrong.


const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _unit() -> UnitDef:
	var def := UnitRoster.first()
	assert_not_null(def, "no units are shipped at all")
	return def


## A running two-player match with a live world behind it.
func _world() -> Dictionary:
	var space := _space()
	var sim := SquadSim.new(space, CurveReplicator.new())
	var buildings := BuildingSim.new(space)
	sim.buildings = buildings

	var match_state := MatchState.new()
	match_state.require_admin_start = false
	match_state.civ_rng.seed = 42
	match_state.add_player(1)
	match_state.add_player(2)
	assert_eq(match_state.phase, MatchState.Phase.RUNNING,
		"setup: two players should have started the match")

	return {"space": space, "sim": sim, "buildings": buildings, "match": match_state}


func _give(w: Dictionary, player: int, at: Vector2i, with_building: bool) -> void:
	var sim: SquadSim = w["sim"]
	sim.add_squad(_unit(), player, at)
	if with_building:
		var def := BuildingSim.def_by_id(&"town_centre")
		assert_not_null(def, "the shipped town centre is where BuildingSim looks for it")
		# `true` completes it: an unfinished building is a different
		# question and the reported bug is about a base that is standing.
		(w["buildings"] as BuildingSim).add_building(def, player, at + Vector2i(3, 0), true)


## Exactly what `server.gd`'s disconnect handler does, in its order.
func _disconnect(w: Dictionary, player: int) -> void:
	(w["match"] as MatchState).mark_disconnected(player)
	(w["sim"] as SquadSim).eliminate_player(player)
	(w["buildings"] as BuildingSim).eliminate_player(player)


func _tick_the_rule(w: Dictionary) -> Array:
	return (w["match"] as MatchState).update(w["sim"], w["buildings"])


# --- the reported bug ---------------------------------------------------

func test_a_player_who_quits_owning_a_building_is_eliminated() -> void:
	# #292 and #318, which are one defect. Before the fix this reported
	# `p2 squads=0 buildings=1 eliminated=false phase=RUNNING` — the
	# abandoned squad correctly dead, the base still standing, and the
	# match unwinnable.
	var w := _world()
	_give(w, 1, Vector2i(4, 4), true)
	_give(w, 2, Vector2i(20, 4), true)
	_tick_the_rule(w)
	assert_false((w["match"] as MatchState).is_eliminated(2),
		"setup: nobody is beaten while both are standing")

	_disconnect(w, 2)
	_tick_the_rule(w)

	assert_eq((w["sim"] as SquadSim).living_squad_count(2), 0,
		"the abandoned army goes, as it always did")
	assert_eq((w["buildings"] as BuildingSim).living_building_count(2), 0,
		"and so does the abandoned base — this is the half that was missing")
	assert_true((w["match"] as MatchState).is_eliminated(2),
		"a player who left owns nothing, so the ordinary rule must call them beaten")


func test_the_remaining_player_wins_rather_than_running_to_the_cap() -> void:
	# The cost, stated as the thing a player experiences. A 1v1 where one
	# side rage-quits ran to the time cap, because `_check_victory` needs
	# one side standing and a disconnected ghost with a town centre counts
	# as standing.
	var w := _world()
	_give(w, 1, Vector2i(4, 4), true)
	_give(w, 2, Vector2i(20, 4), true)
	_tick_the_rule(w)

	_disconnect(w, 2)
	_tick_the_rule(w)

	var m: MatchState = w["match"]
	assert_eq(m.phase, MatchState.Phase.FINISHED, "the match must end")
	assert_eq(m.winner, 1, "and the player still standing must win it")


func test_it_is_reported_as_an_elimination_the_moment_it_happens() -> void:
	# `update` returns who it eliminated so the caller can announce it
	# without diffing state. A quitter who is eliminated silently would
	# leave the scoreboard (D-102) claiming they are still playing.
	var w := _world()
	_give(w, 1, Vector2i(4, 4), true)
	_give(w, 2, Vector2i(20, 4), true)
	_tick_the_rule(w)

	_disconnect(w, 2)
	var newly: Array = _tick_the_rule(w)
	assert_true(newly.has(2), "the player who left must be announced, not just marked")


# --- the wipe itself ----------------------------------------------------

func test_the_wipe_takes_only_the_leaver_s_buildings() -> void:
	# The obvious way to get this wrong, and the one that would end a
	# match for the wrong player.
	var w := _world()
	_give(w, 1, Vector2i(4, 4), true)
	_give(w, 2, Vector2i(20, 4), true)

	_disconnect(w, 2)
	assert_eq((w["buildings"] as BuildingSim).living_building_count(1), 1,
		"the remaining player keeps their base")
	assert_eq((w["buildings"] as BuildingSim).living_building_count(2), 0)


func test_an_unfinished_building_goes_too() -> void:
	# A base half-built when its owner quit is still theirs, still
	# occupies the ground, and would still keep them "standing" — the
	# elimination rule counts what is not destroyed, not what is
	# complete.
	var w := _world()
	_give(w, 1, Vector2i(4, 4), true)
	var buildings: BuildingSim = w["buildings"]
	var def := BuildingSim.def_by_id(&"town_centre")
	buildings.add_building(def, 2, Vector2i(20, 4), false)
	(w["sim"] as SquadSim).add_squad(_unit(), 2, Vector2i(20, 6))

	_disconnect(w, 2)
	assert_eq(buildings.living_building_count(2), 0,
		"an unfinished base is still a base standing on the field")


func test_the_razing_is_reported_through_the_ordinary_building_path() -> void:
	# So a client applies it exactly as it applies any other destruction:
  	# dirty flag, then `S2C_BUILDING_INFO`. Inventing a second message for
	# "the owner left" would be a second thing to keep in step with the
	# first, and D-030's ever-revealed set means every client that has
	# ever seen the base needs telling.
	var w := _world()
	_give(w, 1, Vector2i(4, 4), true)
	_give(w, 2, Vector2i(20, 4), true)
	var buildings: BuildingSim = w["buildings"]
	buildings.take_dirty()  # clear what founding marked

	var razed: Array = buildings.eliminate_player(2)
	assert_eq(razed.size(), 1, "the wipe must say what it destroyed")
	var dirty := buildings.take_dirty()
	assert_true(dirty.has(razed[0]),
		"a razed building must be marked dirty, or no client is ever told")


func test_wiping_twice_destroys_nothing_further() -> void:
	# `_on_disconnect` can be reached more than once for one peer, and a
	# razing that reported work the second time would tell every client
	# about a destruction that did not happen.
	var w := _world()
	_give(w, 1, Vector2i(4, 4), true)
	_give(w, 2, Vector2i(20, 4), true)
	var buildings: BuildingSim = w["buildings"]

	assert_eq(buildings.eliminate_player(2).size(), 1, "setup: the first wipe razes the base")
	assert_eq(buildings.eliminate_player(2).size(), 0,
		"a second wipe has nothing left to destroy and must say so")


func test_wiping_a_player_who_owns_nothing_is_quiet() -> void:
	var w := _world()
	_give(w, 1, Vector2i(4, 4), true)
	assert_eq((w["buildings"] as BuildingSim).eliminate_player(7).size(), 0,
		"a player with no buildings is not a special case")


func test_the_ground_a_razed_base_stood_on_comes_back() -> void:
	# Rubble is walkable. The tick already refreshes passability when
	# combat destroys something; a disconnect happens OUTSIDE the tick, so
	# without its own refresh the last player would be left pathing round
	# an invisible wall where an abandoned town hall used to be — and it
	# would look like a pathfinding bug.
	var w := _world()
	var buildings: BuildingSim = w["buildings"]
	_give(w, 2, Vector2i(20, 4), true)

	var occupied_before := buildings.occupied_cells().size()
	assert_gt(occupied_before, 0, "setup: a standing base occupies ground")
	buildings.eliminate_player(2)
	assert_eq(buildings.occupied_cells().size(), 0,
		"a razed base stops occupying the ground it stood on")


# --- the caller, without which none of it happens ------------------------

func test_the_server_wipes_the_buildings_when_a_player_leaves() -> void:
	# Every test above drives the wipe directly and would pass with
	# nothing in `server.gd` calling it — which is exactly the state the
	# repository was in. `_on_disconnect` wants a live ENet peer, so the
	# caller is asserted by reading it.
	var source := FileAccess.get_file_as_string("res://server.gd")
	assert_false(source.is_empty(), "could not read server.gd to scan it")
	var at := source.find("_sim.eliminate_player(player)")
	assert_gt(at, 0, "there must be a squad wipe on the disconnect path to scan around")
	var nearby := source.substr(maxi(at - 1200, 0), 2400)
	assert_true(nearby.contains("_buildings.eliminate_player(player)"),
		"the disconnect path must wipe the buildings too, or a quitter with a base "
		+ "standing is never eliminated and the match cannot be won (#292, #318)")
	assert_true(nearby.contains("_refresh_passability()"),
		"and must give the ground back — a disconnect happens outside the tick that "
		+ "would otherwise notice")


func test_the_comment_no_longer_claims_a_rule_that_moved() -> void:
	# The comment on the wipe asserted "MatchState's ordinary 'no living
	# squads' rule notices" long after the rule became "no living squads
	# AND no living buildings". That is D-065's family — a comment
	# describing a consequence that stopped being true when something
	# underneath it moved — and it is what made the defect survive
	# reading.
	var source := FileAccess.get_file_as_string("res://server.gd")
	assert_false(source.contains("ordinary \"no living squads\" rule"),
		"server.gd still describes the pre-D-20260823 elimination rule")
