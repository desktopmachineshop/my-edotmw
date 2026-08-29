class_name NetTransport
extends RefCounted

## What the server and the client need of a transport, and nothing more
## (#184, D-094 criterion 5).
##
## ENet has been the only one since M1, so "the transport" and
## "`ENetConnection`" were the same object and `server.gd` reached into
## it directly. D-088 adds a second — Steam sockets, for the relay — and
## D-093 says Steam may be named in exactly one file. This is the shape
## both satisfy, so neither end has to know which it got.
##
## ## The contract, and why it is exactly this
##
## **Reliable and ORDERED, on every channel this game uses.** D-042
## measured that curve packets carry no sequence number, so in-order
## delivery is load-bearing rather than an optimisation: a transport that
## reorders even rarely produces precisely the desync class the
## state-hash machinery exists to catch. That decision chose to hold the
## transport to the contract instead of adding sequencing the protocol
## was measured not to need — which means a new transport has to be
## *held* to it, and `tests/test_transport_ordering.gd` is where.
##
## **Event shape is ENet's**, deliberately: the same five constants with
## the same meanings, so the existing `_service_network` loops on both
## sides did not have to be rewritten to gain a second implementation.
## A seam that forced its own vocabulary on the incumbent would have made
## this change a rewrite of the netcode rather than an addition beside
## it, and the netcode is the part that is proven.
##
## **Peers are duck-typed to `ENetPacketPeer.send`'s shape**, which is
## the same trick `loopback_peer.gd` (D-051) and `host_link.gd` (#182)
## already rely on. Three implementations now agree on it; that is what
## makes "the host, an AI seat and a remote player take one code path"
## true rather than aspirational.
##
## ## What a subclass must promise
##
## - `poll()` returns `[type, peer]` and NEVER blocks. `EVENT_NONE` means
##   "nothing right now", and the caller loops until it sees one.
## - a peer's `send(channel, packet, flags)` delivers reliably and in
##   order, or the subclass does not satisfy this class.
## - `close()` is idempotent and safe to call on a transport that never
##   opened.

## Mirrors `ENetConnection`'s event constants, value for value. Named
## here so a caller can switch on them without naming a transport.
const EVENT_ERROR := -1
const EVENT_NONE := 0
const EVENT_CONNECT := 1
const EVENT_DISCONNECT := 2
const EVENT_RECEIVE := 3


## One event, or `[EVENT_NONE, null]`. Never blocks.
func poll() -> Array:
	push_error("NetTransport.poll: subclass responsibility")
	return [EVENT_NONE, null]


## Stop listening / disconnect. Idempotent.
func close() -> void:
	pass


## Whether this transport is usable. A transport that could not open
## reports false rather than pretending, so the caller can say why.
func is_open() -> bool:
	return false


## One line naming what this is, for a log a bug report will quote. The
## transport is the first thing to suspect when two machines disagree,
## and "which one was it" must not be a guess.
func describe() -> String:
	return "unknown transport"
