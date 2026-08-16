extends GutTest

## Guards D-102 — the in-match player scoreboard.
##
## Three claims, in the order the information travels:
##
## 1. `MatchState` knows how every player stands, including the part a
##    single `winner` id gets wrong (a TEAM can win — D-050);
## 2. that standing reaches the client, which is the half that did not
##    exist: elimination was a server-side `print` and the wire carried
##    none of it, so the client's own defeat screen recorded, correctly,
##    that it "structurally cannot know whether hjalmar is still fighting
##    or already out";
## 3. `Scoreboard.rows` says who is who — and refuses to say how big an
##    enemy's army is, because that is fog (D-004/D-025) and a menu is
##    not an exemption from it.
##
## `client.gd` itself is not reachable from GUT (D-014), which is exactly
## why the deciding is in `scoreboard.gd` and the drawing is not.

const W := 32
const H := 16


# --- MatchState: how a player stands ----------------------------------

func _match_of_two() -> MatchState:
	var m := MatchState.new()
	m.require_admin_start = true
	m.civ_rng.seed = 7
	m.add_player(1)
	m.add_player(2)
	m.start_match()
	return m


## A sim in which `player` owns `squads` living squads and nobody else
## owns anything — enough for `MatchState.update` to decide elimination.
func _sim_owned_by(owners: Array) -> SquadSim:
	var sim := SquadSim.new(TorusSpace.new(W, H, 1.0))
	var def := UnitRoster.first()
	for i in range(owners.size()):
		sim.add_squad(def, int(owners[i]), Vector2i(2 + i * 3, 2))
	return sim


func test_a_player_is_playing_until_something_says_otherwise() -> void:
	var m := _match_of_two()
	assert_eq(m.standing_of(1), MatchState.Standing.PLAYING)
	assert_eq(m.standing_of(2), MatchState.Standing.PLAYING)


func test_a_player_with_nothing_left_reads_as_eliminated() -> void:
	var m := _match_of_two()
	var sim := _sim_owned_by([1, 2])
	assert_true(m.update(sim).is_empty(), "Nobody is out while both have squads")

	sim.eliminate_player(2)
	m.update(sim)
	assert_eq(m.standing_of(2), MatchState.Standing.ELIMINATED)
	assert_eq(m.standing_of(1), MatchState.Standing.VICTOR,
		"The last player standing has won, not merely survived")


## The mistake this exists to stop: `winner` holds ONE player id, and a
## team of two both won. Reading standing as `player == winner` would
## leave one of the victors marked as still playing forever.
func test_both_members_of_a_winning_team_read_as_victors() -> void:
	var m := MatchState.new()
	m.require_admin_start = true
	m.civ_rng.seed = 7
	for player in [1, 2, 3]:
		m.add_player(player)
	m.set_team(1, 0, 1)
	m.set_team(2, 1, 1)
	m.start_match()

	var sim := _sim_owned_by([1, 2, 3])
	sim.teams = m.team_map()
	sim.eliminate_player(3)
	m.update(sim)

	assert_true(m.is_finished(), "A team left standing alone ends the match")
	assert_eq(m.standing_of(1), MatchState.Standing.VICTOR)
	assert_eq(m.standing_of(2), MatchState.Standing.VICTOR,
		"Both allies won — only one of them can be `winner`")


func test_the_scoreboard_annotates_seats_without_writing_on_them() -> void:
	var m := _match_of_two()
	var sim := _sim_owned_by([1, 2])
	sim.eliminate_player(2)
	m.update(sim)

	var board := m.scoreboard()
	assert_eq(board.size(), m.seats.size(), "Every seat is on the board")
	assert_eq(int(board[1]["standing"]), MatchState.Standing.ELIMINATED)
	assert_eq(String(board[0]["name"]), String(m.seats[0]["name"]),
		"The board is the seat list, not a second one")
	assert_false(m.seats[1].has("standing"),
		"Annotating the board must not write match state onto the lobby's seats")


## Found by reading a `--lobby=0` server's log while verifying this
## change, which is the only place it could have been found.
##
## D-102 makes `_broadcast_lobby` fire mid-match for the first time, and
## that function has always mirrored `_match.map_settings` into the
## server's own `_settings` on the way through. Harmless for every caller
## that came before it — they all ran in the lobby — and wrong the moment
## it runs mid-match on a server that never HAD a lobby: the world was
## built from command-line arguments, this field is untouched defaults,
## and the running match's dimensions would have been quietly replaced
## with a different map's.
func test_a_running_match_is_not_the_authority_on_map_settings() -> void:
	var m := MatchState.new()
	m.require_admin_start = true
	m.add_player(1)
	assert_true(m.owns_map_settings(), "A lobby is choosing the world")

	m.add_player(2)
	m.start_match()
	assert_false(m.owns_map_settings(),
		"The world is built; these settings describe a map that may not be it")

	m.return_to_lobby()
	assert_true(m.owns_map_settings(), "Choosing starts again with the next lobby")


# --- the wire ---------------------------------------------------------

## The half that was missing. `MatchState` has known who is out since
## D-033; nothing put it on the wire, so no client could draw it.
func test_standing_survives_the_wire() -> void:
	var seats := [
		{"kind": "human", "player": 1, "civ": "legion", "team": 1, "name": "Player 1",
			"standing": MatchState.Standing.VICTOR},
		{"kind": "ai", "player": 2, "civ": "northmen", "team": 0, "name": "AI 2",
			"standing": MatchState.Standing.ELIMINATED},
	]
	var decoded := NetProtocol.decode_lobby(
		NetProtocol.encode_lobby(1, seats, {}, int(MatchState.Phase.RUNNING)))

	assert_eq(int(decoded["seats"][0]["standing"]), MatchState.Standing.VICTOR)
	assert_eq(int(decoded["seats"][1]["standing"]), MatchState.Standing.ELIMINATED)
	# The fields that were already there must still be, in the right seats
	# — a byte inserted in the wrong place decodes as plausible nonsense.
	assert_eq(String(decoded["seats"][1]["civ"]), "northmen")
	assert_eq(String(decoded["seats"][1]["name"]), "AI 2")
	assert_eq(int(decoded["seats"][0]["team"]), 1)
	assert_eq(String(decoded["seats"][1]["kind"]), "ai")


func test_a_seat_with_no_standing_encodes_as_playing() -> void:
	# Every caller that predates the scoreboard means exactly this.
	var decoded := NetProtocol.decode_lobby(NetProtocol.encode_lobby(1, [
		{"kind": "human", "player": 1, "civ": "legion", "team": 0, "name": "Player 1"},
	]))
	assert_eq(int(decoded["seats"][0]["standing"]), MatchState.Standing.PLAYING)


# --- Scoreboard.rows: who is who --------------------------------------

## A client that has been told about a four-seat match: itself (player 1,
## team 1), an ally (2, team 1), and two enemies (3 and 4).
func _client(standings := {}) -> ClientState:
	var state := ClientState.new()
	var seats := []
	for entry in [[1, "legion", 1, "human"], [2, "northmen", 1, "ai"],
			[3, "legion", 2, "human"], [4, "northmen", 0, "ai"]]:
		seats.append({
			"kind": String(entry[3]), "player": int(entry[0]), "civ": String(entry[1]),
			"team": int(entry[2]), "name": "Player %d" % int(entry[0]),
			"standing": int(standings.get(int(entry[0]), MatchState.Standing.PLAYING)),
		})
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, PackedInt32Array()))
	state.handle_packet(NetProtocol.encode_lobby(1, seats, {},
		int(MatchState.Phase.RUNNING)))
	return state


## Tell the client about squads it can see, through the real SQUAD_INFO
## path rather than by writing `composition` directly — the same reason
## `test_client_state.gd` drives the protocol instead of the fields.
func _sees(state: ClientState, squads: Array) -> void:
	var def := UnitRoster.first()
	var entries := []
	for squad in squads:
		entries.append({
			"id": int(squad[0]), "def_id": String(def.id), "alive": int(squad[2]),
			"shape": String(def.formation_shape), "owner": int(squad[1]),
		})
	state.handle_packet(NetProtocol.encode_squad_info(entries))


func test_every_player_is_listed_with_colour_civ_and_team() -> void:
	var state := _client()
	var rows := Scoreboard.rows(state)

	assert_eq(rows.size(), 4, "Every seat in the match is on the board")
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		# The whole complaint: a colour on the field that cannot be mapped
		# to a name. Same one definition every other surface draws from
		# (D-052), so the board cannot disagree with the army.
		assert_eq(row["colour"], state.colour_of(int(row["player"])),
			"The swatch must be the colour that player's army wears")
	assert_eq(String(rows[0]["civ"]), "legion")
	assert_eq(int(rows[1]["team"]), 1)
	assert_eq(String(rows[1]["kind"]), "ai")
	assert_true(bool(rows[0]["is_you"]), "This client is player 1")
	assert_true(bool(rows[1]["is_ally"]), "Player 2 shares team 1")
	assert_false(bool(rows[2]["is_ally"]), "Player 3 is on the other team")
	assert_false(bool(rows[3]["is_ally"]), "Team 0 is free-for-all, not an alliance")


func test_rows_are_in_seat_order_because_seat_order_is_colour_order() -> void:
	var players := []
	for row in Scoreboard.rows(_client()):
		players.append(int(row["player"]))
	assert_eq(players, [1, 2, 3, 4],
		"Sorting the board would put the swatches in an order matching nothing else")


## The fog rule (D-004/D-025). This client can SEE an enemy squad — it was
## told about it — and the board must still refuse to total it, because
## what it has been told is whatever its vision covers and not that
## player's army.
func test_an_enemys_army_size_is_withheld_even_when_its_squads_are_visible() -> void:
	var state := _client()
	_sees(state, [[0, 1, 12], [1, 1, 9], [2, 2, 20], [3, 3, 30], [4, 4, 8]])
	var rows := Scoreboard.rows(state)

	assert_eq(int(rows[0]["squads"]), 2, "Your own army is yours to count")
	assert_eq(int(rows[0]["soldiers"]), 21)
	assert_eq(int(rows[1]["squads"]), 1, "An ally's squads are always visible (D-050)")
	assert_eq(int(rows[1]["soldiers"]), 20)
	assert_eq(int(rows[2]["squads"]), Scoreboard.UNKNOWN,
		"An enemy's army size is a fog bypass, menu or not")
	assert_eq(int(rows[2]["soldiers"]), Scoreboard.UNKNOWN)
	assert_eq(int(rows[3]["squads"]), Scoreboard.UNKNOWN)


## UNKNOWN is not zero. "That player has no army left" is precisely the
## claim fog exists to stop a client from making.
func test_a_withheld_column_reads_as_a_dash_not_a_zero() -> void:
	assert_eq(Scoreboard.column_text(Scoreboard.UNKNOWN), "—")
	assert_eq(Scoreboard.column_text(0), "0")
	assert_eq(Scoreboard.column_text(7), "7")


func test_a_dead_squad_is_not_counted() -> void:
	var state := _client()
	_sees(state, [[0, 1, 12], [1, 1, 0]])
	var rows := Scoreboard.rows(state)
	assert_eq(int(rows[0]["squads"]), 1, "A wiped-out squad is not a squad")
	assert_eq(int(rows[0]["soldiers"]), 12)


## Eliminated players stay listed (D-033). A board that shortened would
## lose the colour-to-name mapping it exists to provide, for exactly the
## player the reader most wants to identify.
func test_an_eliminated_player_is_still_listed_and_marked() -> void:
	var state := _client({3: MatchState.Standing.ELIMINATED})
	var rows := Scoreboard.rows(state)
	assert_eq(rows.size(), 4)
	assert_eq(int(rows[2]["standing"]), MatchState.Standing.ELIMINATED)
	assert_eq(Scoreboard.standing_text(int(rows[2]["standing"])), "Eliminated")
	assert_eq(Scoreboard.standing_text(int(rows[0]["standing"])), "Playing")


func test_standing_text_covers_every_standing() -> void:
	# Three values on the wire must be three values on screen: an
	# eliminated player drawn as "Playing" is this whole entry's failure
	# mode at one remove.
	var seen := {}
	for standing in [MatchState.Standing.PLAYING, MatchState.Standing.ELIMINATED,
			MatchState.Standing.VICTOR]:
		seen[Scoreboard.standing_text(standing)] = true
	assert_eq(seen.size(), 3, "Every standing needs its own words")


## End to end, through the real packet a server sends: a match state with
## a player knocked out, encoded, decoded by a real ClientState, read by
## the board. This is the chain that did not exist — every link but the
## last one was already built and connected to nothing.
func test_an_elimination_reaches_the_board_through_the_wire() -> void:
	var m := _match_of_two()
	var sim := _sim_owned_by([1, 2])
	sim.eliminate_player(2)
	m.update(sim)

	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(1, W, H, PackedInt32Array()))
	state.handle_packet(NetProtocol.encode_lobby(m.admin_player, m.scoreboard(), {},
		int(m.phase)))

	var rows := Scoreboard.rows(state)
	assert_eq(rows.size(), 2)
	assert_eq(int(rows[1]["standing"]), MatchState.Standing.ELIMINATED,
		"The client must be told who is out — it cannot see it through fog")
	assert_eq(int(rows[0]["standing"]), MatchState.Standing.VICTOR)
	assert_false(state.in_lobby(),
		"A finished match is not a lobby — the board is drawn over a world")
