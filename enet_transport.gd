class_name EnetTransport
extends NetTransport

## The transport this game has always used (#184).
##
## A thin wrapper, and thin on purpose: every byte that has ever crossed
## this project's wire went through `ENetConnection` exactly as it does
## here, so adding the seam beside it cannot have changed what ENet does.
## That is what makes `just test-load` a meaningful check of this
## refactor rather than a formality — if the numbers move, the wrapper is
## wrong.
##
## D-042 chose reliable-ordered ENet on measured evidence (peak RTT
## 14 ms, peak loss 0.98%, 0 desyncs, reliable delivery genuinely
## absorbing loss rather than idling) and rejected unreliable-with-resend.
## Nothing here revisits that; it only gives the choice a name so a
## second choice can exist beside it.

## The connection itself. Public because ENet TELEMETRY is legitimately
## ENet-specific: `server.gd`'s `_sample_transport` reads per-peer RTT,
## packet loss and throttle out of it for D-042's numbers, and those are
## statistics of THIS transport rather than of transports in general.
## Steam's equivalents are different quantities with different meanings,
## and pretending otherwise in a shared interface would produce a table
## whose columns do not compare.
var connection: ENetConnection = null

## What this end is, for `describe()`. A server says where it listens; a
## client says what it dialled.
var _what := "enet (unopened)"


## Listen for remote players. Returns a transport whose `is_open()` says
## whether the port was actually bound — the caller reports the failure,
## because only it knows what to do about it.
static func listen(port: int, max_clients: int, channels: int) -> EnetTransport:
	var out := EnetTransport.new()
	var host := ENetConnection.new()
	var err := host.create_host_bound("0.0.0.0", port, max_clients, channels)
	if err != OK:
		out._what = "enet (could not bind udp %d, error %d)" % [port, err]
		return out
	out.connection = host
	out._what = "enet listening on 0.0.0.0:%d" % port
	return out


## Dial a server. The peer is returned separately because the caller
## needs it immediately — this is the one asymmetry with `listen`, and it
## is ENet's: a connecting host has exactly one peer and knows it before
## the connection completes.
static func connect_to(address: String, port: int, channels: int) -> Dictionary:
	var out := EnetTransport.new()
	var host := ENetConnection.new()
	var err := host.create_host(1, channels)
	if err != OK:
		out._what = "enet (could not create host, error %d)" % err
		return {"transport": out, "peer": null}
	var peer := host.connect_to_host(address, port, channels)
	if peer == null:
		out._what = "enet (could not reach %s:%d)" % [address, port]
		return {"transport": out, "peer": null}
	out.connection = host
	out._what = "enet to %s:%d" % [address, port]
	return {"transport": out, "peer": peer}


func poll() -> Array:
	if connection == null:
		return [EVENT_NONE, null]
	var event := connection.service(0)
	# ENet's constants are this class's constants, value for value — see
	# net_transport.gd's header for why the vocabulary was kept rather
	# than invented.
	return [int(event[0]), event[1]]


func close() -> void:
	if connection != null:
		connection.destroy()
		connection = null


func is_open() -> bool:
	return connection != null


func describe() -> String:
	return _what
