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


## How a player stands in this match, for the in-match scoreboard (D-102).
##
## Public information, unlike anything about a player's ARMY: who is still
## in the match is a fact every player can already infer from the match
## ending, and hiding it only means nobody can read the board.
enum Standing { PLAYING, ELIMINATED, VICTOR }


## `player`'s standing. The one definition — the wire carries this and
## nothing recomputes it client-side.
##
## VICTOR is "still standing when the match finished", NOT `player ==
## winner`. `winner` holds a single id, and a TEAM can win (D-050): asking
## whether a player equals it would mark one of two victorious allies as
## still playing forever, in the one moment the board is read hardest.
func standing_of(player: int) -> int:
	if is_eliminated(player):
		return Standing.ELIMINATED
	if phase == Phase.FINISHED:
		return Standing.VICTOR
	return Standing.PLAYING


## The seat list with each seat's standing attached (D-102).
##
## Seats annotated rather than a second list keyed by player, so the thing
## that goes on the wire is the thing the client already holds — colour is
## derived from SEAT ORDER (D-052), and a standings list that could be
## ordered differently would be a second definition of who sits where.
##
## Copies, because a caller must not be able to write a standing back onto
## a seat: `seats` is the lobby's own state, and `start_match` reads
## `seat["choice"]` off it.
func scoreboard() -> Array:
	var out := []
	for seat in seats:
		var entry: Dictionary = seat.duplicate()
		entry["standing"] = standing_of(int(seat["player"]))
		out.append(entry)
	return out


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
	_register(player)
	_seat_human(player)
	return _start_if_ready()


## Register an AI participant and give it an AI SEAT. Returns true if this
## seating started the match.
##
## The AI twin of `add_player`, and it exists because there was only one
## door. `server.gd`'s `_seat_ai` registered every command-line AI
## (`--ai=N`: `quick-test`, `run-server AI=3`) through `add_player`, which
## seats a *human* — so a seat that was an AI in every other respect
## carried `kind: "human"`, and because those seats are created before any
## human connects, the FIRST AI also took `admin_player`. Nothing failed:
## the match played, and the lobby it came back to (D-075) was held by a
## computer that will never press start.
##
## `add_ai` below is the lobby COMMAND — the same seating plus a
## permission check. The check belongs on the command, not on the seating,
## which is why the two are separate and why this one has no `by_player`.
## `team` is the side this seat is dealt, for the command-line path that
## has no admin to choose one (`--ai-teams`, #119). It is a PARAMETER of
## seating rather than a `set_team` call afterwards because seating the
## last seat is what starts the match: a side set a line later would be
## set on a seat whose `team_map()` had already gone to the simulation.
## `set_team` stays the lobby's door and stays admin-only.
func add_ai_player(player: int, civ: StringName, team: int = 0) -> bool:
	_register(player)
	_seat_ai(player, civ, team)
	return _start_if_ready()


func _register(player: int) -> void:
	if not _players.has(player):
		_players[player] = {"eliminated": false, "connected": true}
	else:
		_players[player]["connected"] = true


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

## Seeded from the MAP SEED by `reseed_civ_rng`, so a Random civ draw
## reproduces on replay (D-016) and a pinned seed reproduces the whole
## match setup rather than only the terrain (D-100).
var civ_rng := RandomNumberGenerator.new()

## The map-independent half of that seed — `hash(MapConfig.id)`, set by
## the server. Kept separate from the map seed so two maps of the same
## seed still draw differently, and so this class needs no MapConfig.
var civ_seed_base: int = 0


## Point `civ_rng` at the seed currently chosen.
##
## Called whenever that seed can have changed: at startup, and on the way
## back to the lobby. The draw is a function of the map seed, which is the
## rule that makes "same seed, same match" true of the civs as well as the
## ground — before D-100 this was seeded from a `--seed` argument that
## defaulted to 0 while the map's own default was 1337, so a lobby's
## Random seats resolved to the same civs every single match.
func reseed_civ_rng() -> void:
	civ_rng.seed = civ_seed_base + map_settings.seed


func _seat_human(player: int) -> void:
	for seat in seats:
		# Any seat, not just a human one: an AI registered with the match
		# must not also acquire a human seat beside itself.
		if int(seat["player"]) == player:
			return
	seats.append({
		"kind": "human", "player": player,
		"civ": CivRoster.RANDOM, "team": 0, "name": "Player %d" % player,
	})
	_seats_changed()
	# Not `if admin_player <= 0`. That asked "is the chair empty", which is
	# the same question as "is anybody in it who can actually use it" only
	# for as long as nothing but a human can sit down — and an AI seated
	# from the command line did, for four milestones. This asks the
	# question that was meant, through the one function that answers it, so
	# a lobby already held by an AI is repaired by the first human to
	# arrive rather than stuck for the life of the server.
	_reassign_admin_if_needed()


## Seat an AI. Idempotent on `player`, like `_seat_human` and for the same
## reason: the same brain must not acquire a second seat beside itself.
##
## Deliberately does NOT touch `admin_player`. An AI never presses start,
## so a lobby it holds is a lobby nobody can leave — which is exactly what
## `add_player`-seated AI produced.
##
## `_seats_changed` fires HERE rather than at each caller (#103): both
## doors onto AI seating go through this function, so starting positions
## following the seats is structural for the command-line path and the
## lobby command alike, rather than a call each of them has to remember.
func _seat_ai(player: int, civ: StringName, team: int = 0) -> void:
	for seat in seats:
		if int(seat["player"]) == player:
			return
	seats.append({
		"kind": "ai", "player": player,
		"civ": civ, "team": clampi(team, 0, MAX_TEAMS), "name": "AI %d" % player,
	})
	_seats_changed()


func is_admin(player: int) -> bool:
	return player > 0 and player == admin_player


## The lobby's "add AI player" command. Returns the seat index, or -1 if
## refused.
##
## Only the admin may do this, and the check lives here rather than in the
## server so it is testable without a socket — the same reason the rest of
## MatchState does (see this file's header).
##
## The SEATING is `_seat_ai`, shared with `add_ai_player`, because the two
## ways of seating an AI producing different seat records is precisely the
## bug this pair replaced.
func add_ai(by_player: int, civ: StringName, player_id: int) -> int:
	if phase != Phase.LOBBY or not is_admin(by_player):
		return -1
	_seat_ai(player_id, civ)
	return seat_of(player_id)


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
	_seats_changed()
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


## Which spawn point this player starts on, given how many exist.
##
## SEAT INDEX, never the player id — the same rule and the same reason as
## D-052's colours. AI players are numbered from 1000 (D-051, sharing the
## human id space on purpose), so `(player - 1) % point_count` collides:
## with 20 points it sends player 1 and player 1001 to the same cell.
## That shipped, and a human and an AI spawned on top of each other in a
## real game.
##
## Seats are numbered 0..n-1 contiguously however players are numbered, so
## keying on them makes the collision unrepresentable rather than merely
## unlikely. Lives here rather than in server.gd because server.gd needs a
## live ENet host to exercise and this needs to be testable.
##
## Falls back to the player id for an unseated player — nothing does that
## today, but a future reconnect path might, and returning a usable start
## beats crashing.
func spawn_index(player: int, point_count: int) -> int:
	return spawn_index_in(seats, player, point_count)


## The same arithmetic, over a seat list that need not be this one's.
##
## Static, and the seat list is a parameter, because THE CLIENT NEEDS THIS
## TOO. `ClientState.spawn_cell_of` used to reimplement it as
## `(player - 1) % point_count` under a doc comment claiming it "mirrors
## server.gd's own wrap … so both sides answer this the same way". It did
## mirror it, right up until the server started keying on the seat — and
## then the two silently disagreed for every AI player, whose ids start at
## 1000 (D-051). An AI asked where its own home was, was told a DIFFERENT
## player's spawn, and founded its capital there.
##
## A copy of a rule is a copy that can drift, and this one did. The client
## holds the seat list already (S2C_LOBBY, D-048) and it is the SAME list
## in the SAME order, so there is no reason for a second definition to
## exist. This is the one.
static func spawn_index_in(seat_list: Array, player: int, point_count: int) -> int:
	if point_count <= 0:
		return 0
	var seat := -1
	for i in range(seat_list.size()):
		if int(seat_list[i]["player"]) == player:
			seat = i
			break
	var index := seat if seat >= 0 else player - 1
	return index % point_count


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
		# Remember the CHOICE before the draw overwrites it, so returning
		# to the lobby can put it back (see return_to_lobby, D-075).
		seat["choice"] = seat["civ"]
		seat["civ"] = CivRoster.resolve(StringName(seat["civ"]), civ_rng)
	phase = Phase.RUNNING
	return true


## Take a match back to the lobby (D-075). The one backwards edge in this
## phase machine.
##
## It exists because "leave match" has to land somewhere. Leaving used to
## be a disconnect, and a disconnect cannot come back — the seat was torn
## down and there was nothing to return TO.
##
## Seats SURVIVE, which is what makes the next match one click away
## instead of a relaunch. Everything a match WROTE on them does not:
##
## - A seat that chose Random gets its choice back. `start_match`
##   overwrites `civ` with the draw, so without this the second match
##   would silently re-field the first one's civs and "Random" would mean
##   "random once, ever".
## - Registration is cleared, because it is per-match. Carrying the
##   dictionary over would bring an `eliminated` flag into a match its
##   player has not played yet, and whoever lost the first match would
##   begin the second already defeated. `server.gd` re-registers every
##   seat from `_on_match_started`, humans and AI alike.
##
## Returns true only if this actually left a match, so a caller can tell
## a real return from a no-op on a lobby that never started.
func return_to_lobby() -> bool:
	if phase == Phase.LOBBY:
		return false
	phase = Phase.LOBBY
	winner = -1
	_players.clear()
	for seat in seats:
		seat["civ"] = seat.get("choice", seat["civ"])

	# The next match is a NEW PLACE, unless somebody pinned the seed
	# (D-100). This is the same defect as the Random seat two lines above,
	# in the terrain: without it, "play again" hands back the map just
	# played, for as long as the server stays up, and nothing looks wrong.
	# A pinned seed deliberately keeps its map — and re-seeding the civ
	# draw unconditionally is what makes that pin reproduce the whole
	# setup, civs included, rather than only the ground.
	if not map_settings.seed_pinned:
		map_settings.roll_seed()
	reseed_civ_rng()
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
			_seats_changed()
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
	if active.size() > 1 and not _all_allied(active):
		return

	# A TEAM can win, not only a lone player (D-050). Without this a 2v2
	# never ends: two allies are still two active players, so the match
	# would run forever with nobody left to fight.
	phase = Phase.FINISHED
	winner = active[0] if active.size() >= 1 else -1


## Whether everyone still standing is on the same side.
func _all_allied(players: Array) -> bool:
	for a in players:
		for b in players:
			if not are_allied(int(a), int(b)):
				return false
	return true


## Same rule the simulation uses (SquadSim.are_allied): team 0 is not a
## team, so two players who both chose "none" are enemies. One definition
## would be better than two — this one exists because MatchState decides
## victory before the sim has been handed the teams, and both must agree.
func are_allied(a: int, b: int) -> bool:
	if a == b:
		return true
	var team_a := team_of(a)
	var team_b := team_of(b)
	return team_a != 0 and team_a == team_b


func team_of(player: int) -> int:
	for seat in seats:
		if int(seat["player"]) == player:
			return int(seat.get("team", 0))
	return 0


## player -> team, for handing to the simulation at match start.
func team_map() -> Dictionary:
	var out := {}
	for seat in seats:
		out[int(seat["player"])] = int(seat.get("team", 0))
	return out


## Choose a side. Same permissions as choosing a civ: your own seat, or
## an AI seat if you are the host — and enforced here rather than by the
## client's UI, because the client is not trusted (D-002).
func set_team(by_player: int, seat_index: int, team: int) -> bool:
	if phase != Phase.LOBBY:
		return false
	if seat_index < 0 or seat_index >= seats.size():
		return false
	if team < 0 or team > MAX_TEAMS:
		return false
	var seat: Dictionary = seats[seat_index]
	var own: bool = seat["kind"] == "human" and int(seat["player"]) == by_player
	var admins_ai: bool = seat["kind"] == "ai" and is_admin(by_player)
	if not (own or admins_ai):
		return false
	seat["team"] = team
	return true


## Sides available in the lobby. 0 is "no team" — free-for-all.
const MAX_TEAMS := 4


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


# --- map settings, chosen in the lobby (D-049) -------------------------

## The world this lobby is about to generate. Admin-only to change, and
## meaningless once the match has started.
var map_settings := MapSettings.new()

## The option key that asks for a NEW seed rather than setting one
## (D-100). Named here because `client.gd` sends it — two spellings of a
## key that only ever meet at run time is a button that silently does
## nothing, which is the failure mode D-065 records.
const REROLL_OPTION := "reroll_seed"

## What `player_slots` is allowed to be, whoever is deriving it. Two is
## `MapSettings.validate`'s own floor; the ceiling is D-018's 20-player
## target with room above it.
const MIN_PLAYER_SLOTS := 2
const MAX_PLAYER_SLOTS := 24


## Starting positions follow the SEATS (#103): a map is generated for the
## players who are actually in the lobby, not for a number somebody set.
##
## Called from every site that adds or removes a seat, which is the whole
## of the derivation — there is no setter for `player_slots` any more, so
## a stale value cannot survive a seat change and there is no UI control
## whose answer disagrees with the seat list.
##
## Clamped rather than trusted: `MapSettings.validate` refuses fewer than
## two starts, and a one-seat lobby is an ordinary state on the way to a
## match. A change that leaves the map unable to seat everyone is REVERTED
## instead of applied — the same rollback `set_map_option` does, and the
## same tolerance the server already has for a short-seated map (it warns
## and plays on, sharing starts). Refusing to seat a player because the
## map is small would be a worse answer than a warning.
func _seats_changed() -> void:
	var wanted := clampi(seats.size(), MIN_PLAYER_SLOTS, MAX_PLAYER_SLOTS)
	if map_settings.player_slots == wanted:
		return
	var before := map_settings.player_slots
	map_settings.player_slots = wanted
	if not map_settings.is_valid():
		map_settings.player_slots = before



## Adjust one setting. Returns true if anything actually changed.
##
## Admin-only and validated HERE: a slider is a suggestion from an
## untrusted client (D-002), and a sea level above the mountain line
## would generate a world with no passable ground at all — every squad
## stranded, every flow field empty. The UI greying out a control is not
## a rule.
func set_map_option(by_player: int, key: String, value: float) -> bool:
	if phase != Phase.LOBBY or not is_admin(by_player):
		return false

	var before := map_settings.to_dict()
	# `to_dict` is the wire payload and carries no pin flag (see
	# MapSettings.seed_pinned), so the rollback below would quietly
	# unpin a seed the admin had chosen.
	var pinned_before := map_settings.seed_pinned
	match key:
		"size":
			var sizes := MapSettings.sizes()
			var index := clampi(int(value), 0, sizes.size() - 1)
			map_settings.width = int(sizes[index]["width"])
			map_settings.height = int(sizes[index]["height"])
		# No "player_slots" case: starting positions are DERIVED from the
		# seat list (`_seats_changed`), not chosen. A setter here would be
		# a knob whose value the next join silently overwrote, which is
		# the declared-and-unread family with the reads and writes swapped.
		"seed":
			map_settings.pin_seed(int(value))
		REROLL_OPTION:
			# The value is ignored: the SERVER draws the number (D-100).
			# Letting the client send one it had rolled itself would put
			# the map in the hands of whoever is host, and would also pin
			# the seed — a rerolled lobby that then stopped rerolling.
			map_settings.roll_seed()
		"preset":
			var ids := TerrainPresetRoster.ids()
			if ids.is_empty():
				return false
			map_settings.apply_preset(
				TerrainPresetRoster.by_id(ids[posmod(int(value), ids.size())]))
		_:
			# Every terrain slider, through the ONE definition of how far
			# each may travel (`MapSettings.slider_bounds`, #125). Four
			# `clampf` calls used to live here with the ranges written out
			# again, which is how the lobby came to draw travel this
			# function refused — and `set_slider` returns false for a key
			# that is not a slider at all, so an unknown option is still
			# refused exactly as it was.
			if not map_settings.set_slider(key, value):
				return false

	# Refuse the change rather than the match: an unplayable combination
	# is rejected at the moment it is made, so nobody discovers it by
	# pressing start.
	if not map_settings.is_valid():
		map_settings = MapSettings.from_dict(before)
		map_settings.seed_pinned = pinned_before
		return false
	return map_settings.to_dict() != before


# --- sandbox mode, for dev testing ---------------------------------------

## Whether cheat commands (C2S_CHEAT_*) are accepted at all this match.
## Set from the server's own --sandbox=1 launch flag, or toggled by the
## admin from the lobby — or LIVE, mid-match, unlike map settings: this is
## deliberately not locked to the lobby phase, since the whole point is
## iterating on a running match without restarting the server.
var sandbox := false

## While true, every NEW construction/production order completes
## instantly rather than over its ordinary build_time. Read by
## server.gd's `_finish_build`/`_handle_order_produce` at the moment of
## creation, not by the sim's tick loop — costs nothing while off, and
## never rewrites anything already in progress when flipped on.
var instant_build := false

## While true, every AI player skips combat entirely
## (`AiPlayer.economy_only`) — town-founding, building, training and
## gathering continue unaffected. Applied directly to the live AiPlayer
## instances by server.gd the moment this is toggled.
var ai_economy_only := false

## Whether the world grows resource nodes at all. Consulted by
## server.gd's `_build_world` at GENERATION time, so flipping it takes
## effect on the next map regen (the panel says so beside the Regen
## button) — a live bulk node clear would need either a fog-violating
## broadcast or a ghost forest of stale trees (D-087's conceal
## semantics), and regen is one click away on the same panel
## (D-20260821-the-sandbox-panel-runs-the-world).
var resources_enabled := true


## Admin-only toggle for one of the sandbox flags above. `key` is
## "sandbox", "instant_build", "ai_economy_only" or "resources" — a tiny
## generic message in the same spirit as `set_map_option`'s key/value
## pairing, rather than one opcode per flag. Not phase-gated on purpose —
## see `sandbox`'s own doc.
func set_sandbox_option(by_player: int, key: String, enabled: bool) -> bool:
	if not is_admin(by_player):
		return false
	match key:
		"sandbox":
			sandbox = enabled
		"instant_build":
			instant_build = enabled
		"ai_economy_only":
			ai_economy_only = enabled
		"resources":
			resources_enabled = enabled
		_:
			return false
	return true


## The first seat hostile to `player`, or -1 when nobody is — the enemy
## the sandbox panel's "spawn for the ENEMY" cheats resolve to
## (D-20260821). First-hostile rather than a picker on purpose: right
## for the solo-vs-AI session the panel serves, and a client never names
## a player id on the wire, so it cannot aim a cheat at an arbitrary
## seat.
func enemy_of(player: int) -> int:
	for seat in seats:
		var other := int(seat["player"])
		if other != player and not are_allied(player, other):
			return other
	return -1
