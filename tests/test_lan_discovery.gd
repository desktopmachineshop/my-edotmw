extends GutTest

## Guards the two ends of LAN discovery over a REAL socket (#187).
##
## `test_lan_protocol.gd` proves the packets and `test_game_browser.gd`
## proves the list; this proves that a beacon and a browser in one
## process actually find each other — bind, send, receive, and the fields
## that only exist once a datagram has crossed a socket, which is where
## the sender's ADDRESS comes from.
##
## It probes 127.0.0.1 rather than broadcasting, which is why it can run
## at all: `LanDiscovery.begin` takes its probe addresses precisely so
## the socket half is testable in docker and in CI, neither of which can
## be relied on to carry a broadcast. The cost is honest and worth
## stating — **this exercises everything except the broadcast itself**,
## and a network that drops broadcasts would still show an empty list.


## Ports to try, spread by process id so two agents running this suite at
## the same time do not collide (D-095's problem, on a socket the
## justfile does not manage).
func _candidate_ports() -> Array:
	var base := 41000 + (OS.get_process_id() % 900) * 8
	var out := []
	for i in range(8):
		out.append(base + i * 2)
	return out


## A beacon listening on some port, or null if the machine would give us
## none of them. Returns [beacon, game_port].
func _beacon_on_any_port(describe: Callable) -> Array:
	for game_port in _candidate_ports():
		var beacon := LanBeacon.new()
		if beacon.begin(game_port, describe) == OK:
			return [beacon, game_port]
	return []


func _describe(port: int) -> Callable:
	return func() -> Dictionary:
		return {
			"port": port, "name": "A test game", "map": "toy 8x8",
			"players": 1, "seats": 4, "phase": "lobby", "joinable": true,
			"protocol": NetProtocol.PROTOCOL_VERSION,
			"build": BuildVersion.string(),
		}


## Poll both ends until the browser has something, or the budget runs
## out. Real datagrams on a loopback are delivered in microseconds, so
## this is a safety net rather than a wait — and it is a COUNT of polls
## rather than a wall-clock sleep, because a timing gate on a loaded host
## is this project's own recorded way to go red with nothing wrong
## (D-106's amendment).
func _exchange(beacon: LanBeacon, browser: LanDiscovery, polls: int = 200) -> Array:
	var seen: Array = []
	var now := 0.0
	for i in range(polls):
		browser.poll(now)
		beacon.poll()
		browser.poll(now)
		seen.append_array(browser.take_seen())
		if not seen.is_empty():
			return seen
		# Past the query interval, so a second query goes out if the
		# first one's answer has not arrived yet.
		now += LanDiscovery.QUERY_INTERVAL
		OS.delay_msec(1)
	return seen


func test_a_browser_finds_a_beacon_on_this_machine() -> void:
	var made := _beacon_on_any_port(func() -> Dictionary: return {})
	assert_false(made.is_empty(),
		"this machine gave us no UDP port at all — nothing below can be trusted")
	if made.is_empty():
		return
	var beacon: LanBeacon = made[0]
	var game_port: int = made[1]
	beacon.stop()

	# Re-begin with a describe that knows its own port.
	beacon = LanBeacon.new()
	assert_eq(beacon.begin(game_port, _describe(game_port)), OK)
	var browser := LanDiscovery.new()
	assert_eq(browser.begin(game_port, PackedStringArray(["127.0.0.1"])), OK)

	var seen := _exchange(beacon, browser)
	assert_eq(seen.size(), 1, "the beacon answered exactly once per query")
	if seen.is_empty():
		browser.stop()
		beacon.stop()
		return
	var listing: Dictionary = seen[0]
	assert_eq(String(listing["provider"]), LanDiscovery.PROVIDER)
	assert_eq(String(listing["name"]), "A test game")
	assert_eq(int(listing["port"]), game_port, "the port a click would connect to")
	assert_eq(String(listing["address"]), "127.0.0.1",
		"the address comes from the DATAGRAM, not from anything the reply claims")
	assert_gt(beacon.answered(), 0, "and the beacon counted the question")

	# And the whole point: it becomes a joinable row.
	var rows := GameBrowser.rows(
		GameBrowser.merge([], seen, 1.0), NetProtocol.PROTOCOL_VERSION)
	assert_eq(rows.size(), 1)
	assert_true(bool((rows[0] as Dictionary)["joinable"]),
		"a game found on this machine, on this build, can be joined")

	browser.stop()
	beacon.stop()


func test_a_reply_cannot_send_a_browser_somewhere_else() -> void:
	# A reply is trusted about what a game IS and never about where it
	# is. A machine that could name the endpoint could point every
	# browser on the network at a third party's address — so the address
	# comes from the datagram and a claimed one is ignored.
	var made := _beacon_on_any_port(func() -> Dictionary:
		return {"port": 4433, "address": "203.0.113.7", "name": "Liar",
			"protocol": NetProtocol.PROTOCOL_VERSION})
	assert_false(made.is_empty(), "this machine gave us no UDP port")
	if made.is_empty():
		return
	var beacon: LanBeacon = made[0]
	var browser := LanDiscovery.new()
	assert_eq(browser.begin(made[1], PackedStringArray(["127.0.0.1"])), OK)
	var seen := _exchange(beacon, browser)
	assert_eq(seen.size(), 1, "it did answer")
	if not seen.is_empty():
		assert_eq(String((seen[0] as Dictionary)["address"]), "127.0.0.1",
			"the address is where the packet CAME FROM, not what it claims")
	browser.stop()
	beacon.stop()


func test_a_reply_a_browser_cannot_use_is_dropped() -> void:
	# A machine that answers with no port — an older build, a bug, or
	# somebody else's protocol that happens to share our magic — must not
	# produce a row that connects nowhere.
	var made := _beacon_on_any_port(func() -> Dictionary:
		return {"name": "No port here"})
	assert_false(made.is_empty(), "this machine gave us no UDP port")
	if made.is_empty():
		return
	var beacon: LanBeacon = made[0]
	var game_port: int = made[1]
	var browser := LanDiscovery.new()
	assert_eq(browser.begin(game_port, PackedStringArray(["127.0.0.1"])), OK)

	var seen := _exchange(beacon, browser, 40)
	assert_eq(seen.size(), 0, "a reply with no endpoint is not a listing")
	assert_gt(beacon.answered(), 0,
		"and it really did answer — this is a DROP, not a missed exchange")

	browser.stop()
	beacon.stop()


func test_a_beacon_ignores_replies_so_two_of_them_cannot_storm() -> void:
	# Two servers on one network hear each other's replies. If a reply
	# looked like a question, every pair of servers would answer each
	# other for ever at line rate. The kind byte is what prevents it, and
	# this is the check that it does.
	var made := _beacon_on_any_port(_describe(4433))
	assert_false(made.is_empty(), "this machine gave us no UDP port")
	if made.is_empty():
		return
	var beacon: LanBeacon = made[0]
	var game_port: int = made[1]

	var speaker := PacketPeerUDP.new()
	assert_eq(speaker.bind(0), OK)
	assert_eq(speaker.set_dest_address("127.0.0.1",
		LanProtocol.discovery_port(game_port)), OK)
	speaker.put_packet(LanProtocol.encode_reply({"port": 4433}))
	# Rubbish too, while there is a socket pointed at it: this port is
	# reachable by anything on the network.
	speaker.put_packet("GET / HTTP/1.1".to_utf8_buffer())
	speaker.put_packet(PackedByteArray([1, 2]))
	for i in range(20):
		beacon.poll()
		OS.delay_msec(1)
	assert_eq(beacon.answered(), 0, "a beacon answers questions, and those were not")
	assert_eq(speaker.get_available_packet_count(), 0, "so nothing came back")

	speaker.close()
	beacon.stop()


func test_a_browser_with_no_beacon_finds_nothing_and_says_so() -> void:
	var browser := LanDiscovery.new()
	# A port nothing is listening on. `begin` binds an EPHEMERAL port, so
	# this cannot fail for being in use — which is the whole reason the
	# protocol asks rather than announces.
	assert_eq(browser.begin(_candidate_ports()[7] + 101,
		PackedStringArray(["127.0.0.1"])), OK)
	for i in range(20):
		browser.poll(float(i) * LanDiscovery.QUERY_INTERVAL)
		OS.delay_msec(1)
	assert_eq(browser.take_seen().size(), 0)
	assert_string_contains(browser.status(), "asking",
		"and it says what it is doing, so an empty list is not a mystery")
	browser.stop()


func test_two_browsers_on_one_machine_both_work() -> void:
	# THE case that shaped the protocol: a fixed listening port for
	# browsers would make the second one fail to bind, and two clients on
	# one machine is the normal dev loop and an ordinary household.
	var first := LanDiscovery.new()
	var second := LanDiscovery.new()
	assert_eq(first.begin(4433, PackedStringArray(["127.0.0.1"])), OK)
	assert_eq(second.begin(4433, PackedStringArray(["127.0.0.1"])), OK,
		"a second browser on the same machine must also open a socket")
	first.stop()
	second.stop()


func test_a_probe_that_is_a_name_is_resolved_and_a_bad_one_is_dropped() -> void:
	# A person types a name; `set_dest_address` wants an address. And a
	# probe that cannot be resolved must not cost the browser the
	# broadcast that works, which is why it is dropped rather than kept.
	var browser := LanDiscovery.new()
	assert_eq(browser.begin(4433, PackedStringArray(["localhost"])), OK,
		"a name that resolves is usable")
	browser.stop()
	assert_eq(browser.begin(4433, PackedStringArray(
		["no-such-host.invalid", "127.0.0.1"])), OK,
		"and one that does not is not fatal")
	# Observed rather than asserted structurally: `_resolved` is private,
	# so what is checked here is that the object still works afterwards.
	browser.poll(0.0)
	assert_eq(browser.take_seen().size(), 0)
	browser.stop()


# --- the provider contract ---------------------------------------------

func test_both_providers_answer_the_same_five_methods() -> void:
	# GDScript has no interfaces, so the duck type is asserted rather than
	# declared. `client.gd` holds an array of these and calls exactly
	# these — a provider missing one is a crash the moment a platform
	# appears, i.e. on the owner's machine and on nobody else's.
	var providers: Array = [LanDiscovery.new()]
	var boundary := load("res://platform.gd")
	assert_not_null(boundary, "the platform boundary script must exist (#181)")
	# Absent here — every automated context this repo has is
	# platform-less, which is the point (D-093) — so the stub is
	# instantiated directly to check its shape.
	assert_null(boundary.lobby_provider(),
		"with no platform there is no provider, and the menu lists no source for it")
	providers.append(boundary.LobbyProvider.new())
	for provider in providers:
		for method in ["id", "label", "poll", "take_seen", "status"]:
			assert_true(provider.has_method(method),
				"%s must answer %s()" % [provider, method])
		assert_ne(String(provider.id()), "", "a provider names itself")
		assert_ne(String(provider.label()), "", "and says what to call it in the menu")
		assert_eq(typeof(provider.take_seen()), TYPE_ARRAY)
		assert_ne(String(provider.status()), "")
