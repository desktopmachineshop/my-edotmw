extends RefCounted
class_name LoopbackPeer

## A "connection" to a player inside this process — an AI seat (D-051).
##
## It exposes the one method `server.gd` uses to talk to a client,
## `send(channel, packet, flags)`, and hands the bytes straight to a
## `ClientState`. That is the entire trick, and it buys something worth
## more than the twenty lines it costs: the server's replication loop
## needs no branch for AI players, so an AI receives byte-identical
## packets to a human through byte-identical code.
##
## The alternative — giving the AI privileged access to `SquadSim` — would
## have been less code and impossible to trust. Fog would become a promise
## rather than a property, and the failure mode is invisible: an AI that
## sees everything does not look like a bug, it looks like a good AI.
##
## Deliberately NOT a subclass of ENetPacketPeer, and deliberately kept
## out of `_clients`: several places legitimately treat that dictionary's
## keys as real sockets (ENet statistics, the disconnect path, D-075's
## "no humans, no server"), and a duck-typed impostor in there would be a
## null cast waiting to happen.
##
## The lobby broadcast used to be on that list and no longer is. It was
## there by accident rather than by right — an AI seat was told the lobby
## once, at admission, and never again, so it could not learn that the
## match had started. Anything a client is TOLD goes through
## `server._recipients()`; `_clients` is for things a SOCKET has.

var state: ClientState


func _init(p_state: ClientState = null) -> void:
	state = p_state if p_state != null else ClientState.new()


## Matches ENetPacketPeer.send's signature so callers cannot tell the
## difference. Channel and flags are accepted and ignored: there is no
## wire here, so ordering is trivially preserved and delivery cannot fail
## — which is exactly why an AI must never be used to prove the transport
## works (D-042).
func send(_channel: int, packet: PackedByteArray, _flags: int = 0) -> int:
	state.handle_packet(packet)
	return OK
