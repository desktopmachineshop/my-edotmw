extends RefCounted
class_name MatchState

## Match lifecycle and victory (D-033) — lobby, running, finished.
##
## ## Why this is not in server.gd
##
## `server.gd` needs a live `ENetConnection` to do anything at all, which
## a GUT test cannot practically stand up (the same reason `test_fog.gd`
## hand-drives the replication order rather than calling `_replicate`).
## Match rules are exactly the part worth testing — "who has lost" and
## "is it over" are easy to get subtly wrong and impossible to notice in a
## smoke run — so they live here, headless and driven by the server, in
## the same shape `Combat` and `Vision` are driven by `SquadSim`.
##
## ## Elimination is a squad question, not a connection question
##
## A player is out when they have nothing left that can fight, which this
## reads from the simulation rather than tracking separately. Disconnect
## is handled as a *cause* of elimination rather than a second concept:
## the server zeroes that player's squads, and the ordinary rule then
## notices. One definition of "defeated", not two that can disagree.

enum Phase { LOBBY, RUNNING, FINISHED }

## How many players must connect before the match starts. 1 keeps the
## single-client development flows (`run-client`, `test-client`) working:
## with one registered player the victory rule below never fires, so a
## solo session behaves exactly as it did before matches existed.
var players_expected: int = 1

## Hard per-player squad ceiling (D-033), set from MapConfig.squad_cap.
##
## **One ceiling covers military and gatherer squads alike.** Every
## villager crew is an army slot not spent — that is the
## economy-versus-army trade made structural rather than left to a balance
## number, and it bounds total squad count, which is the axis the
## architecture is actually sensitive to (D-018).
##
## Enforced here rather than at each production site precisely because
## there will be more than one of those: a town centre making gatherers
## and a barracks making soldiers. A cap only one path respected would be
## worse than no cap, because a player would hit it without being able to
## explain their own economy.
var squad_cap: int = 15

var phase: Phase = Phase.LOBBY
var winner: int = -1

# player id -> { "eliminated": bool, "connected": bool }
var _players := {}


func player_count() -> int:
	return _players.size()


func has_player(player: int) -> bool:
	return _players.has(player)


func is_eliminated(player: int) -> bool:
	return _players.has(player) and bool(_players[player]["eliminated"])


## Players still in the match — registered and not eliminated.
func active_players() -> Array:
	var out := []
	for player in _players:
		if not bool(_players[player]["eliminated"]):
			out.append(player)
	out.sort()
	return out


## Register a joining player. Returns true if this join started the match.
func add_player(player: int) -> bool:
	if not _players.has(player):
		_players[player] = {"eliminated": false, "connected": true}
	else:
		_players[player]["connected"] = true
	return _start_if_ready()


func _start_if_ready() -> bool:
	if phase != Phase.LOBBY:
		return false
	if _players.size() < players_expected:
		return false
	phase = Phase.RUNNING
	return true


## Mark a player as having lost its connection. Deliberately does NOT
## eliminate on its own — the caller zeroes that player's squads and the
## ordinary elimination rule notices on the next update, so "defeated"
## has exactly one definition.
func mark_disconnected(player: int) -> void:
	if _players.has(player):
		_players[player]["connected"] = false


## Re-evaluate elimination and victory against the simulation. Returns the
## players eliminated by THIS call, so the caller can announce them
## without diffing state itself.
##
## Only runs while the match is RUNNING: a player who has not spawned yet
## during LOBBY has zero squads, and eliminating them for it would end the
## match before it began.
func update(sim: SquadSim) -> Array:
	var newly_eliminated := []
	if phase != Phase.RUNNING:
		return newly_eliminated

	for player in _players:
		if bool(_players[player]["eliminated"]):
			continue
		if sim.living_squad_count(player) <= 0:
			_players[player]["eliminated"] = true
			newly_eliminated.append(player)

	newly_eliminated.sort()
	_check_victory()
	return newly_eliminated


## One player left standing ends the match.
##
## Guarded on having had at least two players in the first place. Without
## that, a solo session — the development flow this class must not break —
## would be declared won the instant it started, and a match that nobody
## else ever joined would report a "winner" who beat no one.
func _check_victory() -> void:
	if phase != Phase.RUNNING or _players.size() < 2:
		return
	var active := active_players()
	if active.size() > 1:
		return
	phase = Phase.FINISHED
	winner = active[0] if active.size() == 1 else -1


## May `player` field another squad? Counts LIVING squads, so losing an
## army frees the slots it occupied — the cap is a ceiling on what stands
## on the map, not a lifetime quota.
##
## Deliberately takes the simulation rather than a running tally: a
## separate counter is a second definition of "how many squads does this
## player have", and this project has been bitten before by two
## definitions of the same fact drifting apart.
func has_squad_capacity(sim: SquadSim, player: int) -> bool:
	return sim.living_squad_count(player) < squad_cap


func is_running() -> bool:
	return phase == Phase.RUNNING


func is_finished() -> bool:
	return phase == Phase.FINISHED


## Human-readable, for the server log and the load test's verdict.
func describe() -> String:
	match phase:
		Phase.LOBBY:
			return "lobby (%d/%d players)" % [_players.size(), players_expected]
		Phase.RUNNING:
			return "running (%d active of %d)" % [active_players().size(), _players.size()]
		_:
			return "finished (winner=%d)" % winner
