class_name LanDiscovery
extends RefCounted

## The browser's LAN provider: asks the local network what is running and
## collects the answers (#187).
##
## One of the two providers behind `game_browser.gd`'s list. This one
## works TODAY, on any network, with no account and no service — a player
## on the same wifi as a friend sees their game and clicks it. The other
## is the platform's, which needs a platform.
##
## ## The provider contract, which is a duck type on purpose
##
## GDScript has no interfaces, so a provider is an object with five
## methods and this file is the reference implementation of them:
##
##     id() -> String          # "lan" — also the listings' `provider`
##     label() -> String       # what the menu calls this source
##     poll(now: float)        # send what is due, read what arrived
##     take_seen() -> Array    # listings seen since the last call
##     status() -> String      # one line, including why nothing works
##
## `client.gd` holds an ARRAY of these and knows nothing else about any
## of them, which is what makes the platform half a file rather than a
## branch — and is why a Steam-less build has no Steam code path to be
## broken by, it simply has one provider in the array instead of two.
##
## ## The socket half is thin, and testable anyway
##
## Everything that can be wrong without a network — the packet format,
## what a reply means, what happens to a truncated or hostile datagram —
## is in `lan_protocol.gd` and `game_browser.gd`, both pure. What is left
## here is bind, send, receive. `probes` exists so even that is testable:
## a test points a discovery at `127.0.0.1` and gets a real datagram off
## a real socket, with no broadcast (which docker and CI may not carry)
## and no second machine.

const PROVIDER := "lan"

## Where queries go when nobody says otherwise. The limited broadcast
## address, which every LAN carries and no router forwards — a discovery
## packet that left the building would be a privacy problem rather than a
## feature.
const BROADCAST := "255.255.255.255"

## How often to ask. A player is reading a menu, so this is about how
## quickly a game that has just been hosted appears, and 1 s is under the
## time it takes to look at the list. Well under `GameBrowser.STALE_AFTER`,
## so a single dropped reply — this is UDP — never blinks a row out.
const QUERY_INTERVAL := 1.0

var _socket: PacketPeerUDP = null
var _probes := PackedStringArray([BROADCAST])
var _port := 0
var _next_query := -INF
var _seen: Array = []
var _error := ""
var _replies := 0


## Open the socket and start asking. `game_port` is the port games are
## PLAYED on; the discovery port is derived from it (D-095, see
## `LanProtocol.discovery_port`).
##
## Returns OK, or the bind error — reported, never fatal. A machine that
## will not give this an ephemeral UDP port still plays the game; it just
## has no list, which is the same "absent integration costs fidelity"
## rule the platform boundary follows.
func begin(game_port: int, probes := PackedStringArray()) -> Error:
	stop()
	_port = LanProtocol.discovery_port(game_port)
	if not probes.is_empty():
		_probes = _resolved(probes)
	_socket = PacketPeerUDP.new()
	# Port 0: the OS picks. Deliberately NOT the discovery port — two
	# browsers on one machine is the normal dev loop and the normal
	# household, and a fixed port makes the second one fail to bind. See
	# `lan_protocol.gd` for why the whole protocol is shaped by this.
	var err := _socket.bind(0)
	if err != OK:
		_error = "could not open a socket for the game list (error %d)" % err
		_socket = null
		return err
	_socket.set_broadcast_enabled(true)
	_error = ""
	_next_query = -INF
	return OK


## Send what is due and read what arrived. Cheap enough to call every
## frame the menu is up; does nothing at all when it is not, because
## nothing calls it.
func poll(now: float) -> void:
	if _socket == null:
		return
	if now - _next_query >= 0.0:
		_ask()
		_next_query = now + QUERY_INTERVAL
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		# The SENDER's address, not one the packet claims. A machine may
		# say what port it plays on; it may not say where it is, or one
		# reply could point a browser at somebody else's machine.
		var from := _socket.get_packet_ip()
		var decoded := LanProtocol.decode(packet)
		if not bool(decoded["ok"]) or int(decoded["kind"]) != LanProtocol.KIND_REPLY:
			continue
		var listing := _listing_from(decoded["info"] as Dictionary, from)
		if not listing.is_empty():
			_replies += 1
			_seen.append(listing)


## Everything seen since the last call, and then nothing — the browser
## merges these into what it already had (`GameBrowser.merge`), which is
## where staleness and ordering are decided.
func take_seen() -> Array:
	var out := _seen
	_seen = []
	return out


func stop() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_seen = []


func id() -> String:
	return PROVIDER


func label() -> String:
	return "This network"


## One line for the menu, including the reason there is nothing to show.
## "No games found" and "this machine would not give me a socket" look
## identical in a list and are entirely different problems.
func status() -> String:
	if not _error.is_empty():
		return _error
	if _socket == null:
		return "not looking"
	return "asking on port %d, %d repl%s so far" % [_port, _replies,
		"y" if _replies == 1 else "ies"]


## Probe addresses with any NAMES turned into addresses, once, here.
##
## `set_dest_address` wants an address, and a name is what a person
## types — "dave-pc", or a container's service name when a recipe drives
## this across a docker bridge, which is not a LAN and does not have to
## carry a broadcast. Resolved at `begin` rather than per query: a
## lookup is a blocking call, and doing one per second inside a menu's
## frame is how a UI comes to stutter for a reason nobody can find.
##
## A name that does not resolve is DROPPED rather than kept and retried,
## and the broadcast is unaffected — an unreachable probe must not cost
## the list that works.
func _resolved(probes: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for probe in probes:
		var text := String(probe).strip_edges()
		if text.is_empty():
			continue
		if text.is_valid_ip_address():
			out.append(text)
			continue
		var address := IP.resolve_hostname(text, IP.TYPE_IPV4)
		if address.is_empty():
			push_warning("lan_discovery: could not resolve '%s'" % text)
			continue
		out.append(address)
	return out


func _ask() -> void:
	var query := LanProtocol.encode_query()
	for address in _probes:
		# set_dest_address per probe, because a socket has ONE
		# destination and the browser deliberately asks several: the
		# broadcast address in play, and a plain host in a test.
		if _socket.set_dest_address(address, _port) != OK:
			continue
		_socket.put_packet(query)


## A reply becomes a listing, or nothing.
##
## Everything here comes off a socket from a machine nobody controls, so
## the port is the one field that must be sane — it is what a click
## connects to — and every other field is decoration the browser
## already defaults.
func _listing_from(info: Dictionary, from: String) -> Dictionary:
	var port := int(info.get("port", 0))
	if port < 1 or port > 65535 or from.is_empty():
		return {}
	var listing := info.duplicate()
	listing["provider"] = PROVIDER
	listing["address"] = from
	listing["port"] = port
	return listing
