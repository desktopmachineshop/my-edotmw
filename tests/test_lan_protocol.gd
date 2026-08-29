extends GutTest

## Guards `lan_protocol.gd` — the discovery wire (#187).
##
## This socket is reachable by ANYTHING on the network, unlike
## `net_protocol.gd`'s, which only ever hears from a peer that has
## already connected and handshaked (#179). So half of this file is about
## rubbish: a packet that is too short, one that is not ours, one whose
## body is not JSON, one that claims a kind nobody defined. Every one of
## those must be a reason string rather than a crash, because the
## alternative is a game that can be taken down by a stray broadcast.


func test_a_query_round_trips() -> void:
	var decoded := LanProtocol.decode(LanProtocol.encode_query())
	assert_true(bool(decoded["ok"]), "a query we encoded must decode")
	assert_eq(int(decoded["kind"]), LanProtocol.KIND_QUERY)


func test_a_reply_carries_its_metadata_back() -> void:
	var info := {
		"port": 4433, "name": "Dave's game", "map": "continents 168x194",
		"players": 2, "seats": 8, "phase": "lobby", "joinable": true,
		"protocol": 1, "build": "0.4.0",
	}
	var decoded := LanProtocol.decode(LanProtocol.encode_reply(info))
	assert_true(bool(decoded["ok"]))
	assert_eq(int(decoded["kind"]), LanProtocol.KIND_REPLY)
	var back: Dictionary = decoded["info"]
	assert_eq(String(back["name"]), "Dave's game", "text survives, apostrophe included")
	assert_eq(int(back["port"]), 4433)
	assert_eq(int(back["protocol"]), 1)
	assert_true(bool(back["joinable"]))


func test_an_unknown_field_is_carried_rather_than_refused() -> void:
	# The reason the body is JSON at all: a host running tomorrow's build
	# says one more thing about itself, and today's browser must list it
	# rather than discard it. A wire that had to be versioned to gain a
	# field would need a protocol bump to add "has a password".
	var decoded := LanProtocol.decode(LanProtocol.encode_reply(
		{"port": 4433, "something_new": "from a later build"}))
	assert_true(bool(decoded["ok"]), "an unknown field is not an error")
	assert_eq(String((decoded["info"] as Dictionary).get("something_new", "")),
		"from a later build")


func test_the_discovery_port_is_derived_from_the_game_port() -> void:
	# D-095: every worktree already has its own game port, so deriving
	# means two agents' servers cannot answer each other's browsers with
	# nothing to remember. A shipped build plays on 4433.
	assert_eq(LanProtocol.discovery_port(4433), 4434)
	assert_eq(LanProtocol.discovery_port(20001), 20002)
	# And it stays a port whatever it is handed.
	assert_eq(LanProtocol.discovery_port(65535), 65535)
	assert_eq(LanProtocol.discovery_port(-5), 1)


# --- rubbish off the network -------------------------------------------

func test_a_short_packet_is_a_reason_not_a_crash() -> void:
	for size in [0, 1, 4]:
		var packet := PackedByteArray()
		packet.resize(size)
		var decoded := LanProtocol.decode(packet)
		assert_false(bool(decoded["ok"]), "%d bytes is not a packet" % size)
		assert_ne(String(decoded["error"]), "", "and it says why")


func test_somebody_elses_traffic_is_discarded_before_parsing() -> void:
	var decoded := LanProtocol.decode("HTTP/1.1 200 OK".to_utf8_buffer())
	assert_false(bool(decoded["ok"]))
	assert_string_contains(String(decoded["error"]), "magic")


func test_an_unknown_kind_is_refused() -> void:
	var packet := LanProtocol.MAGIC.to_utf8_buffer()
	packet.append(99)
	var decoded := LanProtocol.decode(packet)
	assert_false(bool(decoded["ok"]))
	assert_string_contains(String(decoded["error"]), "kind")


func test_a_reply_whose_body_is_not_a_json_object_is_refused() -> void:
	for body in ["", "[1, 2, 3]", "\"a string\"", "{not json at all"]:
		var packet := LanProtocol.MAGIC.to_utf8_buffer()
		packet.append(LanProtocol.KIND_REPLY)
		packet.append_array(body.to_utf8_buffer())
		var decoded := LanProtocol.decode(packet)
		assert_false(bool(decoded["ok"]), "body %s is not metadata" % body)


func test_metadata_too_large_to_send_is_refused_rather_than_truncated() -> void:
	# A half-serialised reply parses as garbage at the far end, where
	# nobody can see why. The caller can see an empty packet.
	var huge := {"port": 4433, "name": "x".repeat(LanProtocol.MAX_PACKET * 2)}
	assert_eq(LanProtocol.encode_reply(huge).size(), 0,
		"an oversized reply is not sent at all")
	# And the ordinary one is comfortably inside a datagram nobody will
	# fragment.
	var real := LanProtocol.encode_reply({
		"port": 4433, "name": "A reasonably long game name here",
		"map": "continents 336x388", "players": 12, "seats": 24,
		"phase": "running", "joinable": true, "protocol": 1, "build": "0.4.0",
	})
	assert_gt(real.size(), 0)
	assert_lt(real.size(), 512, "a real reply is nowhere near the cap")


func test_the_default_game_name_is_never_empty() -> void:
	# An unnamed game is drawn as its endpoint, which is correct and
	# unfriendly; this is the friendly default and it must exist even in
	# a container with no user name set.
	assert_ne(LanProtocol.default_game_name(), "")
