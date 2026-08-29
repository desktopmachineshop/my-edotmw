class_name GameBrowser
extends RefCounted

## What the pre-lobby's game list SAYS, given what the providers found
## (#187, D-089 — lobbies, not matchmaking).
##
## All-static and pure, for the reason `hud_layout.gd`, `battle_line.gd`
## and `scoreboard.gd` are, and the reason #187 asks for it in as many
## words: the interesting failure modes here are a listing that goes
## stale, a row that offers a join it cannot complete, and an ordering
## that hides the game somebody is waiting to join — none of which need a
## socket, a window or a GPU to be wrong, and all of which are invisible
## to a screenshot.
##
## ## What a listing IS
##
## A dictionary, filled by whichever provider found it:
##
##     {
##       "provider": "lan",              # which provider found it
##       "name": "Dave's game",          # what the host calls it
##       "map": "continents 168x194",    # what will be played
##       "players": 2, "seats": 8,       # filled / total
##       "phase": "lobby",               # or "running"
##       "joinable": true,               # the HOST's answer, not ours
##       "protocol": 1,                  # NetProtocol.PROTOCOL_VERSION there
##       "build": "0.4.0",               # display only
##       "address": "192.168.1.5", "port": 4433,
##       "last_seen": 12.4,              # provider clock, seconds
##     }
##
## Every field is OPTIONAL on the way in and defaulted here. This data
## comes off a socket from a machine nobody controls, so a missing key is
## an ordinary Tuesday rather than a crash, and a browser that refuses to
## draw a row because a host runs a build with one more field is a browser
## that fails exactly when it is most needed.

## How long a listing survives without being seen again.
##
## Longer than any provider's poll interval by a wide margin, because the
## cost of the two errors is not symmetric: a row that lingers a few
## seconds after a host quits gives one failed join with a message, while
## a list that flickers as replies arrive out of order is unusable.
const STALE_AFTER := 8.0

## Sort keys, low first. Joinable before not is the whole ordering
## argument: the list exists to be clicked.
const RANK_JOINABLE := 0
const RANK_IN_PROGRESS := 1
const RANK_INCOMPATIBLE := 2
const RANK_FULL := 3


## The identity of a game, so several replies are one row.
##
## The HOST'S OWN token when it sent one, and the endpoint otherwise.
## Never the host's name: names are user-typed, duplicated and
## changeable, and a browser that deduped by one would merge two
## neighbours' games into a single row pointing at whichever replied
## last. Same rule as D-102's — a name is what a lobby SHOWS, and nothing
## may key on it.
##
## The token exists because the endpoint is NOT the identity, which only
## running this found: a machine answers a broadcast on every interface
## it has, so the first real end-to-end run listed one server three times
## — 127.0.0.1, the LAN address and a virtual adapter's — each a
## perfectly valid way to reach the same game. Deduping on the endpoint
## is right for two servers that share a name and wrong for one server
## that has three addresses, and a token settles both.
static func entry_id(entry: Dictionary) -> String:
	var token := String(entry.get("id", "")).strip_edges()
	if not token.is_empty():
		return "%s#%s" % [String(entry.get("provider", "?")), token]
	return "%s:%s:%d" % [
		String(entry.get("provider", "?")),
		String(entry.get("address", "?")),
		int(entry.get("port", 0)),
	]


## Fold what a provider just saw into what the browser already had.
##
## Upsert by `entry_id`, stamping `last_seen` — an entry that is still
## answering keeps its PLACE rather than jumping to the bottom, because a
## list that reorders under the cursor is a list that joins the wrong
## game.
static func merge(known: Array, seen: Array, now: float) -> Array:
	var out: Array = []
	var index := {}
	for entry in known:
		var copy: Dictionary = (entry as Dictionary).duplicate()
		index[entry_id(copy)] = out.size()
		out.append(copy)
	for entry in seen:
		var latest: Dictionary = (entry as Dictionary).duplicate()
		latest["last_seen"] = now
		var id := entry_id(latest)
		if index.has(id):
			# The ENDPOINT is kept from the answer that arrived first,
			# while everything mutable — seats, phase, joinable — takes
			# the newest value. One game answering on three interfaces is
			# three ways to reach it and all of them work from here; the
			# first is as good as any and, unlike "the latest", it does
			# not change under the cursor between one reply and the next.
			var held: Dictionary = out[int(index[id])]
			latest["address"] = held.get("address", latest.get("address", ""))
			latest["port"] = held.get("port", latest.get("port", 0))
			out[int(index[id])] = latest
		else:
			index[id] = out.size()
			out.append(latest)
	return out


## Everything still answering. A host that quit stops replying, and this
## is the only thing that takes its row away.
static func fresh(known: Array, now: float, stale_after: float = STALE_AFTER) -> Array:
	var out: Array = []
	for entry in known:
		if now - float((entry as Dictionary).get("last_seen", -INF)) <= stale_after:
			out.append(entry)
	return out


## May this build join that game, and if not, WHY — in words a player can
## act on.
##
## The version check is #187's own requirement: grey the row out BEFORE a
## doomed join rather than letting the handshake refuse after it. The
## refusal at the far end (#179) is still the authority; this only saves
## the trip, so it is deliberately the SAME comparison and not a cleverer
## one.
static func can_join(entry: Dictionary, local_protocol: int) -> Dictionary:
	var theirs := int(entry.get("protocol", -1))
	if theirs < 0:
		return _no("that game did not say what it speaks", RANK_INCOMPATIBLE)
	if theirs != local_protocol:
		var direction := "newer than yours" if theirs > local_protocol else "older than yours"
		return _no("their build speaks protocol %d, yours speaks %d — theirs is %s"
			% [theirs, local_protocol, direction], RANK_INCOMPATIBLE)
	if not bool(entry.get("joinable", true)):
		# The HOST's answer, taken at face value. A running match with
		# drop-in seats IS joinable (D-089/D-090) and a lobby that has
		# filled is not, and only the host knows which — a browser
		# deciding for itself from `players` and `seats` would be
		# reimplementing seating rules a network away from the seats.
		if String(entry.get("phase", "")) == "running":
			return _no("that match is under way and has no seat free", RANK_IN_PROGRESS)
		return _no("that game is full", RANK_FULL)
	return {"ok": true, "reason": "", "rank": RANK_JOINABLE}


## The list, in the order a player should read it, each row carrying the
## text the menu draws and the endpoint a click connects to.
##
## Rows rather than raw entries because the DECISION — what a row says,
## whether it can be pressed — is the part worth testing, and it must not
## be made a second time in `client.gd` where nothing can see it (D-061).
static func rows(known: Array, local_protocol: int) -> Array:
	var out: Array = []
	for entry in known:
		var listing: Dictionary = entry as Dictionary
		var verdict := can_join(listing, local_protocol)
		out.append({
			"id": entry_id(listing),
			"provider": String(listing.get("provider", "?")),
			"title": _title(listing),
			"detail": _detail(listing),
			"joinable": bool(verdict["ok"]),
			"reason": String(verdict["reason"]),
			"address": String(listing.get("address", "")),
			"port": int(listing.get("port", 0)),
			"rank": int(verdict["rank"]),
		})
	out.sort_custom(func(a, b):
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		if String(a["title"]) != String(b["title"]):
			return String(a["title"]).naturalnocasecmp_to(String(b["title"])) < 0
		# Ties break on the id, which is an endpoint: stable, so a list
		# refreshed several times a second does not shuffle under a
		# cursor.
		return String(a["id"]) < String(b["id"]))
	return out


## The line above the list. Says what is happening, including when the
## honest answer is "nothing yet" — a list that is simply empty reads as
## broken, which is the complaint #162 was filed about one screen over.
static func summary(rows_shown: Array, searching: bool) -> String:
	if rows_shown.is_empty():
		return ("Looking for games on this network…" if searching
			else "No games found on this network.")
	var joinable := 0
	for row in rows_shown:
		if bool((row as Dictionary)["joinable"]):
			joinable += 1
	var plural := "" if rows_shown.size() == 1 else "s"
	if joinable == rows_shown.size():
		return "%d game%s on this network." % [rows_shown.size(), plural]
	return "%d game%s on this network, %d joinable." % [rows_shown.size(), plural, joinable]


static func _title(entry: Dictionary) -> String:
	var given := String(entry.get("name", "")).strip_edges()
	if given.is_empty():
		# An unnamed game is still a game somebody can join, so it gets
		# its endpoint as a name rather than being dropped or drawn blank.
		return "%s:%d" % [String(entry.get("address", "?")), int(entry.get("port", 0))]
	return given


static func _detail(entry: Dictionary) -> String:
	var parts := PackedStringArray()
	var map := String(entry.get("map", "")).strip_edges()
	if not map.is_empty():
		parts.append(map)
	# "2/8 players" once there are seats to fill, and plain "0 players"
	# before there are any. A server with no lobby has no seat list until
	# somebody joins, and "0/0 players" reads as a broken row rather than
	# an empty game — seen in the first real photograph of this list.
	var players := int(entry.get("players", 0))
	var seats := int(entry.get("seats", 0))
	parts.append("%d/%d players" % [players, seats] if seats > 0
		else "%d player%s" % [players, "" if players == 1 else "s"])
	if String(entry.get("phase", "")) == "running":
		parts.append("in progress")
	return "  -  ".join(parts)


static func _no(reason: String, rank: int) -> Dictionary:
	return {"ok": false, "reason": reason, "rank": rank}
