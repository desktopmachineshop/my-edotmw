extends GutTest

## Who an auto-mode gate opens for (D-076, #210).
##
## An auto gate opened for **its owner's** squads and for nobody else, so
## a teammate stood at a closed gate and had to walk round the wall — or
## could not get through at all if the wall was closed. The site compared
## owner ids where `SquadSim.are_allied` is what the rest of the
## simulation asks: `combat.gd` calls it in five places, and `client.gd`
## and `ai_player.gd` call it too.
##
## It reads as an omission rather than a decision. D-076 specifies
## *"auto-open when the owner's own squads are near"* and mentions teams
## nowhere; D-050 (allies share vision) predates it. So it is the same
## shape as #83 (the AI marched an army onto a teammate's town centre) and
## #82 (the minimap painted an ally in the enemy tone) — a raw owner
## comparison beside a codebase that compares teams everywhere else, with
## nothing failing.
##
## ## Why this file did not exist
##
## `test_wall_top.gd` and `test_wall_run.gd` are thorough about the tier
## rules, the climb, the run geometry and the seam — and neither contains
## the word `gate`. `test_buildings.gd` round-trips `set_gate_open` and
## never exercises `_update_auto_gates`. So nothing went red on the
## omission and nothing would have gone red on a fix.
##
## Driven through the server's own `_update_auto_gates` rather than a
## reimplementation of it, for the reason `test_civ_knobs.gd` sets out:
## "server.gd needs a socket and a scene tree" is true of `_ready()`, not
## of the file.

const W := 32
const H := 16
const GATE_AT := Vector2i(10, 8)


func _unit() -> UnitDef:
	var d := UnitDef.new()
	d.id = &"test_squad"
	d.archetype = &"levy"
	d.squad_size = 4
	d.health = 10.0
	d.damage = 0.0
	d.attack_range = 0.0
	d.vision_range = 4.0
	d.move_speed = 3.0
	return d


## A server holding one complete gate in AUTO mode, and nothing else.
func _world() -> Dictionary:
	var server = load("res://server.gd").new()
	autofree(server)
	var space := TorusSpace.new(W, H, 1.0)

	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._sim.buildings = server._buildings
	server._match = MatchState.new()
	server._match.phase = MatchState.Phase.RUNNING

	var gate_def := _gate_def()
	assert_not_null(gate_def, "no shipped BuildingDef is a gate")
	var gate: int = server._buildings.add_building(gate_def, 1, GATE_AT, true)
	server._buildings.set_gate_mode(gate, BuildingSim.GATE_MODE_AUTO)

	return {"server": server, "space": space, "gate": gate}


## Asked of the shipped data rather than named here (D-010), so this file
## names no building and keeps working if the gate is ever re-authored.
func _gate_def() -> BuildingDef:
	for def in BuildingSim.all_defs():
		if def.is_gate:
			return def
	return null


## Run the gate check. It only looks every `AUTO_GATE_CHECK_TICKS`, so the
## tick counter has to land on a multiple — asked of the server's own
## constant rather than a number written here, which is the whole reason
## the constant is reachable.
func _check(w: Dictionary) -> void:
	var server = w["server"]
	while server._sim.tick_count % server.AUTO_GATE_CHECK_TICKS != 0:
		server._sim.tick()
	server._update_auto_gates()


func _stand(w: Dictionary, player: int) -> int:
	return w["server"]._sim.add_squad(_unit(), player, GATE_AT + Vector2i(1, 0))


func _is_open(w: Dictionary) -> bool:
	return w["server"]._buildings.is_gate_open(w["gate"])


# --- the three cases, and the two controls that keep them honest -------

## The control D-076 already had: the owner's own squad opens it. Without
## this, a fix that opened every gate for everybody would pass the ally
## case below and break the enemy one only by luck.
func test_a_gate_opens_for_its_owners_squad() -> void:
	var w := _world()
	_stand(w, 1)
	_check(w)
	assert_true(_is_open(w), "a gate must open for the player who built it")


## #210. Observed to fail before the fix: with `owner_of(squad) == owner`
## the gate stays shut and the ally walks round the wall.
func test_a_gate_opens_for_an_allys_squad() -> void:
	var w := _world()
	var server = w["server"]
	server._sim.teams = {1: 1, 2: 1}
	_stand(w, 2)
	_check(w)
	assert_true(_is_open(w),
		"an ally standing at the gate must be let through — D-050 shares their sight, "
		+ "and a wall that shuts them out is a wall between teammates")


## And still not for an enemy, which is the half that makes a gate mean
## anything. A fix that reached for `!= owner` or dropped the test would
## pass both cases above and fail here.
func test_a_gate_stays_shut_for_an_enemy() -> void:
	var w := _world()
	var server = w["server"]
	server._sim.teams = {1: 1, 2: 2}
	_stand(w, 2)
	_check(w)
	assert_false(_is_open(w), "an enemy must not open the gate by standing at it")


## Team 0 is explicitly NOT a team (D-050), so two players both on it are
## not allies and the gate must stay shut. This is the case every AI
## fixture in the estate sits in (#119), so getting it wrong would be
## invisible to `just ai-ladder`.
func test_team_zero_is_not_a_team_at_a_gate_either() -> void:
	var w := _world()
	var server = w["server"]
	server._sim.teams = {1: 0, 2: 0}
	_stand(w, 2)
	_check(w)
	assert_false(_is_open(w),
		"team 0 is not a team — two players on it must not open each other's gates")


## An empty `teams` is what every un-teamed match has, and it must behave
## as team 0 does rather than as an error.
func test_a_match_with_no_teams_at_all_keeps_gates_shut_to_others() -> void:
	var w := _world()
	_stand(w, 2)
	_check(w)
	assert_false(_is_open(w), "with no teams declared, another player is not an ally")


## The gate CLOSES again when the ally leaves, or "opens for an ally" is
## really "opens once and never shuts".
func test_a_gate_shuts_again_when_the_ally_walks_away() -> void:
	var w := _world()
	var server = w["server"]
	var space: TorusSpace = w["space"]
	server._sim.teams = {1: 1, 2: 1}
	var ally := _stand(w, 2)
	_check(w)
	assert_true(_is_open(w), "the gate should be open, or the close below proves nothing")

	# 600 ticks (a minute of match time) for a seven-cell walk, because a
	# move waits on a flow field solved under D-040's per-tick cell budget
	# before it starts covering ground. 200 was not enough and the test
	# read as "the gate never shuts" — a fixture measuring the solver's
	# warm-up rather than the rule.
	var away := space.normalize(GATE_AT + Vector2i(0, 7))
	server._sim.order_move(ally, away)
	for _i in range(600):
		server._sim.tick()
	assert_eq(server._sim.cell_of(ally), away,
		"the ally never actually left, so the gate closing below would prove nothing")
	server._update_auto_gates()
	assert_false(_is_open(w), "the gate must shut once the ally is no longer near it")


## The server asks the SIMULATION, and the handover is what makes the
## rule real. `SquadSim.teams` is what `combat.gd` reads, and #119's whole
## finding is that the handover nothing performs is the dangerous half —
## a gate opening for allies the simulation does not believe in would be
## that defect wearing this fix.
func test_the_handover_of_teams_is_what_opens_the_gate() -> void:
	var w := _world()
	var server = w["server"]
	_stand(w, 2)
	_check(w)
	assert_false(_is_open(w),
		"before the simulation is told, player 2 is not an ally")

	server._sim.teams = {1: 1, 2: 1}
	server._update_auto_gates()
	assert_true(_is_open(w),
		"handing the teams over is what makes them allies — nothing else changed")
