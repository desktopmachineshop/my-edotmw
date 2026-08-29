class_name MainMenu
extends RefCounted

## What the pre-connection screen DECIDES, with none of what it draws
## (#180, and `decisions/D-20260827-a-client-starts-before-it-connects.md`).
##
## All-static and pure, the same split as `hud_layout.gd`,
## `lobby_layout.gd`, `battle_line.gd` and `selection_pick.gd`, and for the
## same reason (D-061): `client.gd` needs a GPU and a window, and the two
## questions here need neither. Both of them are also the kind that is
## wrong in a way nothing notices — an address parsed slightly differently
## from the CLI's, or a menu that appears in front of `just test-client`
## and photographs itself.
##
## Deliberately NOT a third layout module. The menu is four controls; it
## is laid out by `LobbyLayout`'s own scale and margins, because it is the
## same kind of screen — a full-page document, fitted to its content
## rather than magnified over a world (see that file's header for why the
## HUD's reference is the wrong one for this).


## The port a bare hostname means. The CLI's own default, so typing
## "127.0.0.1" into the box and passing `--address=127.0.0.1` reach the
## same server. Kept here rather than read from `client.gd` so this file
## stays loadable on its own; `tests/test_main_menu.gd` asserts the two
## agree, which is the half that could silently drift.
const DEFAULT_PORT := 4433

const MIN_PORT := 1
const MAX_PORT := 65535


## Split "host", "host:port", "[::1]:port" or "::1" into an address and a
## port.
##
## Returns `{ok, address, port, error}`. `error` is written for a PLAYER
## — this is the one place in the client where a typo is the expected
## input, so "Enter an address" beats a parse failure, and a port that is
## not a number must not read as a hostname that happens to contain a
## colon.
##
## **The colon is split from the RIGHT, and only when what follows is a
## number.** An IPv6 literal is mostly colons: splitting from the left
## would turn `::1` into host "" port ":1", and splitting from the right
## unconditionally would turn it into host "::" port "1" — a plausible,
## entirely wrong endpoint, which is `int()`-strips-non-digits (D-20260817)
## wearing a different hat.
static func parse_endpoint(text: String, default_port: int = DEFAULT_PORT) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return _bad("Enter an address, for example 127.0.0.1:%d" % default_port)

	# Bracketed IPv6, the one unambiguous form: [::1] or [::1]:24395.
	if trimmed.begins_with("["):
		var close := trimmed.find("]")
		if close < 0:
			return _bad("Unclosed [ in the address — an IPv6 address looks like [::1]:%d" % default_port)
		var host := trimmed.substr(1, close - 1)
		var rest := trimmed.substr(close + 1)
		if host.strip_edges().is_empty():
			return _bad("No address between the brackets")
		if rest.is_empty():
			return _ok(host, default_port)
		if not rest.begins_with(":"):
			return _bad("Expected :port after ] — for example [::1]:%d" % default_port)
		return _with_port(host, rest.substr(1))

	var colons := trimmed.count(":")
	if colons == 0:
		return _ok(trimmed, default_port)
	if colons > 1:
		# A bare IPv6 literal. It cannot carry a port without brackets —
		# that is what brackets are for — so the whole string is the
		# address and the default port stands.
		return _ok(trimmed, default_port)

	var parts := trimmed.split(":", true, 1)
	if String(parts[0]).strip_edges().is_empty():
		return _bad("No address before the : — try 127.0.0.1:%d" % default_port)
	return _with_port(String(parts[0]), String(parts[1]))


## Whether this launch should skip the menu and connect straight away,
## and to what.
##
## The rule is **"was a connection asked for on the command line"**, not
## "is there a default" — `--address` has defaulted to 127.0.0.1 since the
## client existed, so a rule reading the resolved value would autoconnect
## every launch and the menu would be unreachable. `just run-client` and
## `just test-client` both pass `--address` and `--port` explicitly, so
## they keep working unattended, which is #180's own condition.
##
## `--run-seconds` (capture mode) counts too, and on its own: a headless
## screenshot run has nobody to press Join, and a menu drawn in front of
## it would photograph itself. `EDOTMW_SERVER_ADDRESS` counts as well —
## inside the compose network the server is a hostname, and that env var
## is how `test-client` reaches it.
static func autoconnect(args: Dictionary, server_address_env: String,
		default_address: String, default_port: int) -> Dictionary:
	# `--menu=1` forces the screen, and it exists for exactly one caller:
	# `just menu-shot`, which has to PHOTOGRAPH the menu and therefore
	# needs capture mode (`--run-seconds`) without capture mode's
	# autoconnect. This project's own rule is that every screen somebody
	# looks at gets an instrument aimed at it deliberately — `test-client`
	# frames a spawn and structurally cannot show cliffs, forests, the fog
	# edge or, now, this.
	#
	# `=1`, not a bare `--menu`, because `CmdArgs.parse` only records
	# `--key=value` and silently DROPS anything else. The first version of
	# this was a bare flag, and the recipe rendered a menu carrying "could
	# not reach server:4433" — the flag ignored, the env address used, the
	# connection failed, and the failure path put the menu on screen
	# anyway. Every check passed and the picture was wrong, which is this
	# project's oldest lesson and the reason `menu-shot` exists at all.
	if int(args.get("menu", 0)) == 1:
		return {"connect": false, "address": default_address, "port": default_port}
	var asked := args.has("address") or args.has("port") \
		or args.has("run-seconds") or not server_address_env.is_empty()
	var address := String(args.get("address",
		server_address_env if not server_address_env.is_empty() else default_address))
	var port := int(args.get("port", default_port))
	return {"connect": asked, "address": address, "port": port}


## How the endpoint reads back to a player — the title bar, the menu's own
## "last joined" line, and the settings file. Always `host:port`, because
## a remembered address with no port is an address that reconnects
## somewhere else the day the port changes (D-095 gives every worktree its
## own).
static func format_endpoint(address: String, port: int) -> String:
	if address.contains(":") and not address.begins_with("["):
		return "[%s]:%d" % [address, port]
	return "%s:%d" % [address, port]


## The window title, for a client that is connected to `endpoint` or (with
## an empty one) connected to nothing.
##
## Here rather than in `client.gd` because it is a string, and because
## `_ready()` used to build it once and never again — so a client that
## reconnected somewhere else kept naming the server it had left. The
## instance half is D-095's: several agents run clients on one desktop and
## the title is how the human tells two identical windows apart.
static func window_title(instance: String, endpoint: String) -> String:
	var title := "eDotMW"
	if not instance.is_empty():
		title += " — %s" % instance
	title += "  [%s]" % (endpoint if not endpoint.is_empty() else "not connected")
	return title


static func _with_port(host: String, port_text: String) -> Dictionary:
	var trimmed_port := port_text.strip_edges()
	if not trimmed_port.is_valid_int():
		return _bad("\"%s\" is not a port number" % trimmed_port)
	var port := int(trimmed_port)
	if port < MIN_PORT or port > MAX_PORT:
		return _bad("Port %d is outside %d-%d" % [port, MIN_PORT, MAX_PORT])
	return _ok(host.strip_edges(), port)


static func _ok(address: String, port: int) -> Dictionary:
	return {"ok": true, "address": address, "port": port, "error": ""}


static func _bad(message: String) -> Dictionary:
	return {"ok": false, "address": "", "port": 0, "error": message}
