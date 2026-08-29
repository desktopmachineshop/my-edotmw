class_name HostLink
extends RefCounted

## The CLIENT end of an in-process connection (D-088, #182).
##
## `loopback_peer.gd`'s mirror image. That one carries packets from the
## server to a client inside the same process; this one carries a
## client's ORDERS back, and together they are the whole of "the host's
## client is connected to the host's server".
##
## Its entire job is to match `ENetPacketPeer.send`'s shape, so the ~30
## sites in `client.gd` that order a squad, produce a unit or set a
## formation are byte-for-byte the same code whether the player is
## hosting or joined over a socket. That is the same trick — and the same
## payoff — as D-051's: no branch in the ordering path means a host
## cannot accidentally be given a rule a guest does not have, and the
## difference would have been invisible.
##
## Deliberately NOT an ENetPacketPeer subclass, for the reason
## `loopback_peer.gd` gives at more length: several places legitimately
## treat a peer as a real socket, and an impostor that passes a type
## check is a null cast waiting to happen. Nothing casts this; it is
## reached only through `client.gd`'s `_peer`, which is untyped.

## Where a packet goes. Set once, at construction, by the server that
## created it — so a client cannot point its own orders somewhere else.
var _sink: Callable


func _init(p_sink: Callable) -> void:
	_sink = p_sink


## Matches ENetPacketPeer.send's signature so callers cannot tell the
## difference. Channel and flags are accepted and ignored: there is no
## wire here, so ordering is trivially preserved and delivery cannot fail
## — which is exactly why an in-process host must never be used to prove
## the transport works (D-042).
func send(_channel: int, packet: PackedByteArray, _flags: int = 0) -> int:
	if _sink.is_valid():
		_sink.call(packet)
	return OK


## The client says goodbye through these on its way out. There is no
## socket to close: the host ENDING the match is what tears the server
## down, and that is client.gd's decision (D-088 accepts its consequence
## with eyes open — host-quit kills the match for everyone). Present so
## the client's exit path needs no branch.
func peer_disconnect_now(_data: int = 0) -> void:
	pass


func peer_disconnect(_data: int = 0) -> void:
	pass
