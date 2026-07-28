extends SceneTree

## Headless load-test bot (see justfile `run-bots` / `test-load`).
##
## Runs N virtual clients inside a single process rather than N
## processes, per the M0 planning session's memory-budget analysis: on
## the current dev hardware (16 GB RAM), N separate Godot headless
## processes is both slower to spin up and a much heavier footprint than
## N lightweight virtual-client objects sharing one process/one network
## stack. This also gives more faithful multi-client network behavior
## than testing against a single connection.
##
## STATUS: M0 stub. Connection/scripted-behavior logic is not
## implemented yet — that lands with the netcode work in M1. This file
## exists now so the `--headless --script bot_client.gd` invocation,
## CLI arg parsing, and virtual-client fan-out shape are settled before
## M1 fills in real behavior.

const DEFAULT_SERVER_ADDRESS := "127.0.0.1"
const DEFAULT_SERVER_PORT := 4433


class VirtualClient:
	var index: int
	var server_address: String
	var server_port: int

	func _init(p_index: int, p_address: String, p_port: int) -> void:
		index = p_index
		server_address = p_address
		server_port = p_port

	func connect_and_run() -> void:
		# M1 TODO: open a real connection to the server, then drive
		# scripted behavior (move orders, production, etc.) per the
		# test scenario. Currently a no-op placeholder.
		print("[bot %d] would connect to %s:%d (not implemented until M1)" % [index, server_address, server_port])


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())

	var client_count: int = args.get("clients", 1)
	var address: String = args.get("address", DEFAULT_SERVER_ADDRESS)
	var port: int = args.get("port", DEFAULT_SERVER_PORT)

	print("bot_client.gd: spawning %d virtual client(s) against %s:%d" % [client_count, address, port])

	var clients: Array[VirtualClient] = []
	for i in range(client_count):
		var vc := VirtualClient.new(i, address, port)
		clients.append(vc)
		vc.connect_and_run()

	quit(0)


## Minimal `--key=value` CLI parser for user args (after `--`).
## Example: godot --headless --script bot_client.gd -- --clients=20 --address=127.0.0.1 --port=4433
func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				var key := kv[0]
				var value := kv[1]
				if value.is_valid_int():
					parsed[key] = value.to_int()
				else:
					parsed[key] = value
	return parsed
