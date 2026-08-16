class_name Scoreboard
extends RefCounted

## Who is in this match, and what each player is entitled to know about
## them (D-102).
##
## All-static and pure, for the reason `selection_pick.gd` and
## `hud_layout.gd` are: drawing the board needs a GPU and `client.gd`
## cannot be reached from GUT (D-014), but "which colour is whose" and
## "may this player be shown that number" are neither of those things.
## The half that was actually missing is the half that is testable.
##
## ## The gap this closes
##
## Every ingredient was already on the client. Seats carry name, civ and
## team and survive the whole match (`ClientState.lobby`); `colour_of` is
## the one definition every surface already draws from (D-052). A player
## still could not learn which colour was whose once the lobby closed, so
## the colours were on screen and unreadable — a feature only half
## delivered, in the same family as the "mechanism correct, shipped
## numbers do nothing" defects this project keeps meeting.
##
## ## Identity is public; strength is not
##
## Name, kind, civ, team and colour are LOBBY facts. Everyone chose them
## in front of everyone else, so listing them leaks nothing and gates
## nothing.
##
## Army size is not a lobby fact, and a scoreboard that showed it for
## every player would be a fog bypass with a friendly face (D-004/D-025)
## — the maphack this project's architecture is specifically built to
## make impossible, shipped as a menu. So the strength columns are
## derived from `ClientState.composition`, which holds exactly what the
## server chose to send: this player's own squads, its allies' (always
## visible, D-050), and whatever enemy squads its vision currently
## covers. An enemy's counts would therefore be a partial number dressed
## as a total, so they are reported as UNKNOWN and drawn as a dash.
##
## Deriving instead of asking the server is the point: there is no packet
## carrying another player's army size, so no future caller can leak one.
##
## ## What standing costs, and why it is on the wire
##
## `standing` is the one thing here the client cannot derive. Fog means
## it only ever sees squads it can see, so "is that player still in the
## match" is unanswerable locally — the client's own defeat screen says
## so in as many words. It comes from `MatchState.standing_of`, on the
## seat, and this module only reads it.

## A strength column this player may not be shown. Not 0, which is a
## real and very different claim — "that player has no army left" is
## exactly what fog exists to stop a client from knowing.
const UNKNOWN := -1


## One row per seat, in SEAT ORDER.
##
## Seat order is colour order (D-052), so sorting by score or by name
## would put the swatches in an order that matches nothing else on
## screen — and mapping a colour on the field back to a name is the whole
## reason this board exists.
static func rows(state: ClientState) -> Array:
	var out := []
	var seats: Array = state.lobby.get("seats", [])
	# One pass over `composition` for the whole board, not one per seat.
	# Twenty seats against a client's visible squads is small, but a scan
	# per row is the shape this project keeps having to undo (vision's
	# `distance()` per cell, `UnitRoster.by_id` per produced squad), and
	# it is cheaper to not write it than to find it later.
	var tally := _tally(state)
	for seat in seats:
		var player := int(seat["player"])
		var is_you: bool = player == state.player
		# `are_allied` is the client's mirror of the sim's own rule,
		# including the part that is easy to get wrong: team 0 is not a
		# team, so an FFA lobby is not one big alliance.
		var is_ally: bool = not is_you and state.are_allied(state.player, player)
		var entitled: bool = is_you or is_ally
		out.append({
			"player": player,
			"name": String(seat.get("name", "Player %d" % player)),
			"kind": String(seat.get("kind", "human")),
			"civ": String(seat.get("civ", "")),
			"team": int(seat.get("team", 0)),
			"colour": state.colour_of(player),
			"standing": int(seat.get("standing", MatchState.Standing.PLAYING)),
			"is_you": is_you,
			"is_ally": is_ally,
			"squads": int(tally.get(player, EMPTY)["squads"]) if entitled else UNKNOWN,
			"soldiers": int(tally.get(player, EMPTY)["soldiers"]) if entitled else UNKNOWN,
		})
	return out


const EMPTY := {"squads": 0, "soldiers": 0}


## player -> {squads, soldiers}, counted the way `ClientState` counts this
## client's own (`living_squad_count`) — from `composition`, never from a
## list of ids that only ever grows.
##
## Ghosts are excluded by construction: a concealed squad leaves
## `composition` entirely and lives in `_ghosts`, and counting a
## last-known ghost would report an army that may not exist any more.
static func _tally(state: ClientState) -> Dictionary:
	var out := {}
	for id in state.composition:
		var entry: Dictionary = state.composition[id]
		var owner := int(entry.get("owner", 0))
		var alive := maxi(int(entry.get("alive", 0)), 0)
		if not out.has(owner):
			out[owner] = {"squads": 0, "soldiers": 0}
		if alive > 0:
			out[owner]["squads"] += 1
			out[owner]["soldiers"] += alive
	return out


## What a standing reads as on the board.
##
## Here rather than in `client.gd` so the mapping is testable and so
## `MatchState.Standing`'s three values cannot quietly become two on
## screen — an eliminated player drawn as merely "playing" is the failure
## this whole entry exists to prevent, at one remove.
static func standing_text(standing: int) -> String:
	match standing:
		MatchState.Standing.ELIMINATED:
			return "Eliminated"
		MatchState.Standing.VICTOR:
			return "Victory"
		_:
			return "Playing"


## A strength column as text. UNKNOWN is a dash, not a zero — the board
## says "you are not entitled to this", never "there is none".
static func column_text(value: int) -> String:
	return "—" if value == UNKNOWN else str(value)
