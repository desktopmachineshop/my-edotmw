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
	_seat_human(player)
	return _start_if_ready()


func _start_if_ready() -> bool:
	if phase != Phase.LOBBY:
		return false
	# The admin starts the match (D-048). `players_expected` survives as
	# the automatic path for the development flows — `run-client` and
	# `test-client` have nobody to press the button — and is bypassed
	# entirely once a lobby has an admin who can.
	if require_admin_start and admin_player > 0:
		return false
	if _players.size() < players_expected:
		return false
	return start_match()


# --- lobby: seats, admin, civs (D-048) --------------------------------

## Whether the match waits for an admin to start it. False keeps the
## single-client development flows behaving exactly as they did before
## the lobby existed.
var require_admin_start := false

## The seat list. Each is
## {kind: "human"|"ai", player: int, civ: StringName, name: String}.
##
## `civ` is the CHOICE, which may be `CivRoster.RANDOM`; it is resolved to
## a real civ only when the match starts, so a lobby can show "Random"
## right up until the moment it means something.
var seats: Array = []

## The player who may seat AI, set their civs, and start. 0 when no human
## has joined yet.
##
## The first human to connect, passing to the lowest-numbered remaining
## human when they leave. Deterministic on purpose: "whoever happens to be
## next" would make the same disconnection produce different lobbies, and
## a replay could not reconstruct which of them was in charge.
var admin_player: int = 0

## Seeded at construction by the caller, so a Random civ draw reproduces
## on replay (D-016).
var civ_rng := RandomNumberGenerator.new()


func _seat_human(player: int) -> void:
	for seat in seats:
		if seat["kind"] == "human" and int(seat["player"]) == player:
			return
	seats.append({
		"kind": "human", "player": player,
		"civ": CivRoster.RANDOM, "name": "Player %d" % player,
	})
	if admin_player <= 0:
		admin_player = player


func is_admin(player: int) -> bool:
	return player > 0 and player == admin_player


## Seat an AI. Returns the new seat index, or -1 if refused.
##
## Only the admin may do this, and the check lives here rather than in the
## server so it is testable without a socket — the same reason the rest of
## MatchState does (see this file's header).
func add_ai(by_player: int, civ: StringName, player_id: int) -> int:
	if phase != Phase.LOBBY or not is_admin(by_player):
		return -1
	seats.append({
		"kind": "ai", "player": player_id,
		"civ": civ, "name": "AI %d" % player_id,
	})
	return seats.size() - 1


## Remove an AI seat. Humans cannot be removed this way — a player leaves
## by disconnecting, and letting the admin evict people is a moderation
## feature nobody asked for.
func remove_ai(by_player: int, seat_index: int) -> bool:
	if phase != Phase.LOBBY or not is_admin(by_player):
		return false
	if seat_index < 0 or seat_index >= seats.size():
		return false
	if seats[seat_index]["kind"] != "ai":
		return false
	seats.remove_at(seat_index)
	return true


## Choose a civ. A human may only set their OWN seat; the admin may also
## set any AI seat.
##
## Enforced here, not merely hidden in the client's UI: the client is not
## trusted (D-002), and "the button was greyed out" is not a rule.
func set_civ(by_player: int, seat_index: int, civ: StringName) -> bool:
	if phase != Phase.LOBBY:
		return false
	if seat_index < 0 or seat_index >= seats.size():
		return false
	var seat: Dictionary = seats[seat_index]
	var own: bool = seat["kind"] == "human" and int(seat["player"]) == by_player
	var admins_ai: bool = seat["kind"] == "ai" and is_admin(by_player)
	if not (own or admins_ai):
		return false
	if civ != CivRoster.RANDOM and CivRoster.by_id(civ) == null:
		return false
	seat["civ"] = civ
	return true


func seat_of(player: int) -> int:
	for i in range(seats.size()):
		if int(seats[i]["player"]) == player:
			return i
	return -1


## Resolve every seat's choice and begin. Returns true if the match
## started.
##
## Random is resolved HERE rather than at selection time, so a player can
## see "Random" in the lobby and still not know what they will get — and
## so the draw lands inside the seeded sequence a replay reconstructs.
func start_match() -> bool:
	if phase != Phase.LOBBY:
		return false
	for seat in seats:
		seat["civ"] = CivRoster.resolve(StringName(seat["civ"]), civ_rng)
	phase = Phase.RUNNING
	return true


## Admin-triggered start. Separate from start_match so the permission
## check cannot be skipped by a caller that only wanted to start it.
func request_start(by_player: int) -> bool:
	if not is_admin(by_player):
		return false
	if seats.size() < 2:
		return false  # a lobby of one is not a match
	return start_match()


## The civ a player ended up with, or "" if they have no seat.
func civ_of(player: int) -> StringName:
	var index := seat_of(player)
	if index < 0:
		return &""
	return StringName(seats[index]["civ"])


## Hand the admin role on when the current one leaves. Lowest remaining
## human, so the outcome does not depend on dictionary order.
func _reassign_admin_if_needed() -> void:
	for seat in seats:
		if seat["kind"] == "human" and int(seat["player"]) == admin_player:
			return
	var best := 0
	for seat in seats:
		if seat["kind"] != "human":
			continue
		var player := int(seat["player"])
		if best == 0 or player < best:
			best = player
	admin_player = best


## Remove a human's seat entirely (they disconnected during the lobby).
func remove_human_seat(player: int) -> void:
	for i in range(seats.size()):
		if seats[i]["kind"] == "human" and int(seats[i]["player"]) == player:
			seats.remove_at(i)
			break
	_reassign_admin_if_needed()


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
func update(sim: SquadSim, buildings: BuildingSim = null) -> Array:
	var newly_eliminated := []
	if phase != Phase.RUNNING:
		return newly_eliminated

	for player in _players:
		if bool(_players[player]["eliminated"]):
			continue

		# Defeated means having nothing left to fight OR build with.
		#
		# Squads alone are not the test, and getting that wrong ended
		# matches instantly: founders are consumed by the town hall they
		# found (D-031), so a player who made the correct opening move had
		# zero squads for a moment and was declared beaten while their
		# hall stood there ready to produce. A base is a way back into the
		# game; an empty map is not.
		if sim.living_squad_count(player) > 0:
			continue
		if buildings != null and buildings.living_building_count(player) > 0:
			continue

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
