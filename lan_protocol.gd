class_name LanProtocol
extends RefCounted

## THE definition of how a game announces itself on a local network, and
## how a browser asks (#187's LAN half).
##
## `net_protocol.gd`'s little sibling, and deliberately a SEPARATE wire:
## that one is the match — curves, orders, fog — spoken over a connected
## ENet channel to a peer that has already joined. This one is spoken to
## machines that have not, and its entire vocabulary is "is anybody
## there" and "yes, here is what I am". Two packet kinds, no state, no
## session.
##
## ## Why a query and a reply rather than a broadcast announcement
##
## The obvious shape is a server shouting every few seconds and clients
## listening on a well-known port. It does not survive the DEV LOOP: two
## clients on one machine both want to listen, and a UDP port cannot be
## bound twice in one machine's default configuration — Godot exposes no
## SO_REUSEPORT. So the browser would work for one player per computer,
## which is precisely the configuration every test of it is run in.
##
## Asking instead puts the fixed port on the SERVER, where there is
## genuinely one per machine per instance, and lets every browser bind an
## ephemeral port it does not have to agree with anybody about. It is also
## quieter: nothing is on the wire while nobody is looking at a menu.
##
## ## The metadata is JSON, and the packet is capped
##
## The sim wire is packed binary because it runs at 10 Hz for hours
## (D-003). This runs when a human is reading a menu. What it needs
## instead is to gain a field without a version bump — seats, phase, a
## password flag, whatever the browser learns to show — so the body is
## JSON and unknown keys are ignored by construction. The cap is real,
## though: a UDP datagram past the path MTU fragments, and a fragmented
## discovery reply is one that arrives on some networks and not others.

## Four bytes that say this is ours, so a browser on a busy network
## discards somebody else's traffic before parsing it rather than after.
const MAGIC := "eDMW"

## Packet kinds. A byte rather than a string, because the one thing this
## header must never do is need parsing to be rejected.
const KIND_QUERY := 0
const KIND_REPLY := 1

## The whole datagram, header included. Well under any path MTU: a
## fragmented reply is a game that appears on some networks and not
## others, which is worse than one that never appears at all.
const MAX_PACKET := 1024

## How the discovery port is derived from the port a game is played on.
##
## DERIVED rather than a second constant, and that is D-095 doing its
## job: every worktree already gets its own game port from
## `instance-id.sh`, so deriving from it means two agents' dev servers
## cannot answer each other's browsers, with nothing to remember and no
## new literal in any recipe. A shipped build plays on 4433 and is
## discovered on 4434.
static func discovery_port(game_port: int) -> int:
	return clampi(game_port + 1, 1, 65535)


## "Is anybody there?"
##
## Carries no version. A query that refused to parse on a version
## mismatch would make an old browser invisible to a new server, which is
## the exact case the browser exists to REPORT — a listing greyed out
## with "their build is newer than yours" beats a machine that answers
## nothing (#187: grey out incompatible lobbies BEFORE a doomed join).
static func encode_query() -> PackedByteArray:
	var packet := MAGIC.to_utf8_buffer()
	packet.append(KIND_QUERY)
	return packet


## "Yes, and here is what I am." `info` is the metadata a browser shows.
##
## Returns an EMPTY packet if the metadata will not fit, rather than a
## truncated one: a half-JSON reply parses as garbage on the far side,
## and the caller can see and report an empty answer.
static func encode_reply(info: Dictionary) -> PackedByteArray:
	var packet := MAGIC.to_utf8_buffer()
	packet.append(KIND_REPLY)
	packet.append_array(JSON.stringify(info).to_utf8_buffer())
	if packet.size() > MAX_PACKET:
		return PackedByteArray()
	return packet


## What a packet is, or why it is nothing.
##
## Never trusts its input: this socket is reachable by anything on the
## network, so every field is checked and a bad packet is a reason string
## rather than an exception. Returns
## `{"ok": bool, "kind": int, "info": Dictionary, "error": String}`.
static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.size() < MAGIC.length() + 1:
		return _bad("packet is too short to be ours")
	for i in range(MAGIC.length()):
		if packet[i] != MAGIC.unicode_at(i):
			return _bad("not our magic")
	var kind := int(packet[MAGIC.length()])
	if kind == KIND_QUERY:
		return {"ok": true, "kind": KIND_QUERY, "info": {}, "error": ""}
	if kind != KIND_REPLY:
		return _bad("unknown packet kind %d" % kind)
	if packet.size() > MAX_PACKET:
		return _bad("reply is longer than %d bytes" % MAX_PACKET)
	var body := packet.slice(MAGIC.length() + 1)
	# A JSON INSTANCE, not `JSON.parse_string`. The static helper pushes
	# an engine error on every malformed document, and this parses
	# datagrams from anybody on the network: one hostile sender would
	# fill a server's log at line rate, which is a denial of service
	# through a diagnostic. The instance returns an error code and says
	# nothing.
	var reader := JSON.new()
	if reader.parse(body.get_string_from_utf8()) != OK:
		return _bad("reply body is not JSON")
	if typeof(reader.data) != TYPE_DICTIONARY:
		return _bad("reply body is not a JSON object")
	return {"ok": true, "kind": KIND_REPLY, "info": reader.data as Dictionary, "error": ""}


static func _bad(reason: String) -> Dictionary:
	return {"ok": false, "kind": -1, "info": {}, "error": reason}


## What a game calls itself when nobody named it.
##
## The machine's own user name, because that is what a player scanning a
## list on their own network recognises — and it is already on both
## machines, so it needs no account, no service and no typing. Falls back
## to the game's name rather than to an empty string: an unnamed row is
## drawn as its endpoint (`GameBrowser._title`), which is correct and
## unfriendly.
##
## NOT an identity. Nothing keys on it, exactly as nothing keys on a
## persona name (D-102's rule, and `Platform.persona_name`'s);
## it is a label on a row.
static func default_game_name() -> String:
	for key in ["USERNAME", "USER", "LOGNAME"]:
		var who := OS.get_environment(key).strip_edges()
		if not who.is_empty():
			return "%s's game" % who
	return "eDotMW game"
