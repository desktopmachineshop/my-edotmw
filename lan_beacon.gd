class_name LanBeacon
extends RefCounted

## The SERVER's half of LAN discovery: it answers when asked (#187).
##
## `lan_discovery.gd`'s mirror image, and as small as it looks — bind the
## derived discovery port, and reply to every query with what this game
## currently is. It holds no state about who asked: discovery is a
## question and an answer, never a subscription, so a browser that closes
## costs nothing and a server that dies stops answering, which is exactly
## how a row leaves a list (`GameBrowser.fresh`).
##
## ## What it says, and what it must not
##
## The metadata is what a player needs in order to CHOOSE — a name, a
## map, how full it is, whether it can be joined, and which protocol it
## speaks so an incompatible build is greyed out before a doomed join
## (#187, #179). It carries no seat list, no player names beyond the
## host's own game name, and no state from inside the match: this socket
## answers anybody on the network, and fog of war is not a thing to relax
## for a menu (D-004).
##
## `describe` is supplied by the caller as a Callable rather than read
## from a `MatchState` here, because the beacon must not be a second
## place that decides what a lobby's seat count is. `server.gd` owns that
## answer and hands it over, freshly, per reply.

var _socket: PacketPeerUDP = null
var _port := 0
var _describe: Callable = Callable()
var _error := ""
var _answered := 0


## Start answering on the discovery port derived from `game_port`.
##
## Returns OK or the bind error. A FAILURE HERE IS NOT FATAL and callers
## must treat it that way: a server that cannot open its discovery socket
## still hosts a match perfectly, it just cannot be found by browsing —
## and the one context where that bind reliably fails is a second server
## on one machine, which is a dev arrangement rather than a player's.
func begin(game_port: int, describe: Callable) -> Error:
	stop()
	_port = LanProtocol.discovery_port(game_port)
	_describe = describe
	_socket = PacketPeerUDP.new()
	var err := _socket.bind(_port)
	if err != OK:
		_error = "could not bind discovery port %d (error %d)" % [_port, err]
		_socket = null
		return err
	# The queries this answers arrive as broadcasts, and a socket that
	# has not enabled broadcast does not receive them on every platform.
	_socket.set_broadcast_enabled(true)
	_error = ""
	return OK


## Answer everything waiting. Called from the server's own frame, and it
## is deliberately a poll rather than a thread: one datagram per browser
## per second is not worth a concurrency model, and this is a process
## whose whole job is a 10 Hz tick it must not miss (D-020, D-023).
func poll() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var from := _socket.get_packet_ip()
		var from_port := _socket.get_packet_port()
		var decoded := LanProtocol.decode(packet)
		if not bool(decoded["ok"]) or int(decoded["kind"]) != LanProtocol.KIND_QUERY:
			continue
		if not _describe.is_valid():
			continue
		var info = _describe.call()
		if typeof(info) != TYPE_DICTIONARY:
			continue
		# Freshly, per reply: a cached description is how a browser comes
		# to show a lobby that filled up a minute ago.
		var reply := LanProtocol.encode_reply(info as Dictionary)
		if reply.is_empty():
			# Over the cap. Reported rather than truncated — a
			# half-serialised reply parses as garbage at the far end,
			# where nobody can see why.
			push_warning("lan_beacon: reply metadata is too large to send")
			continue
		# UNICAST back to whoever asked, on the port they asked FROM.
		# Not a broadcast: a reply is for one browser, and broadcasting
		# it would wake every machine on the network for each query.
		if _socket.set_dest_address(from, from_port) != OK:
			continue
		_socket.put_packet(reply)
		_answered += 1


func stop() -> void:
	if _socket != null:
		_socket.close()
	_socket = null


## True once the socket is open. Named for what a caller wants to know,
## and false is an ordinary state rather than an error.
func listening() -> bool:
	return _socket != null


func port() -> int:
	return _port


func answered() -> int:
	return _answered


func status() -> String:
	if not _error.is_empty():
		return _error
	if _socket == null:
		return "not answering"
	return "answering on port %d (%d asked)" % [_port, _answered]
