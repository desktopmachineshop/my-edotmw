extends GutTest

## Guards that server-sent state goes to EVERY peer, not just the sockets
## (#253).
##
## `server._recipients()` is THE definition of "every peer that receives
## server-sent state" — sockets and AI seats alike (D-051: an AI is a
## client without a socket, held to every rule a human is). Its own doc
## comment already records two drifts away from it: `_replicate` merged in
## `_ai_clients` while `_broadcast_squad_info` iterated `_clients` alone.
##
## `_handle_chat` was the third. It cost nothing visible, because an AI
## does not read chat — which is exactly why it survived. It stops being
## free the moment a non-socket peer is a HUMAN, which is what #182's
## in-process host is: the hosting player saw no chat at all, including
## their own.
##
## Three instances of one mistake, and the only thing standing between it
## and a fourth was a paragraph of prose. This is that paragraph made
## mechanical, in the style of `test_civs.gd`'s no-script-names-a-civ scan
## and `test_multi_agent_isolation.gd`'s literal scan.
##
## The exceptions are few and each has a reason a test can NAME, which is
## the point — an allowlist whose entries cannot be justified is a mute
## button.

## Functions permitted to iterate `_clients` directly and send, with why.
## Adding a name here is a deliberate act and should be argued in review.
const SOCKET_ONLY := {
	# ENet transport statistics are a property of a SOCKET. An AI seat has
	# no round-trip time, no packet loss and no throttle.
	"_sample_transport_stats":
		"ENet statistics belong to sockets and have no meaning for an AI seat",
}


func _server_source() -> String:
	var handle := FileAccess.open("res://server.gd", FileAccess.READ)
	assert_not_null(handle, "server.gd must be readable")
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## Every `func name(...)` in the file, as {name: body}. Crude but exact
## enough for a scan: GDScript functions start in column 0.
func _functions(source: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("(?m)^func ([a-zA-Z0-9_]+)")
	var hits := re.search_all(source)
	for i in range(hits.size()):
		var start: int = hits[i].get_start()
		var end: int = hits[i + 1].get_start() if i + 1 < hits.size() else source.length()
		out[hits[i].get_string(1)] = source.substr(start, end - start)
	return out


func test_no_broadcast_iterates_clients_directly() -> void:
	var source := _server_source()
	var functions := _functions(source)
	assert_gt(functions.size(), 10, "the scan found almost no functions — it is not reading server.gd")

	var offenders := []
	for name in functions:
		var body: String = functions[name]
		if not body.contains("in _clients"):
			continue
		# A loop that does not SEND is not a broadcast — reading player
		# ids or clearing a per-connection baseline is legitimate and
		# common.
		if not body.contains(".send("):
			continue
		if SOCKET_ONLY.has(name):
			continue
		offenders.append(name)

	assert_eq(offenders.size(), 0,
		("these send to _clients alone, so an AI seat — and any non-socket "
		+ "HUMAN — never receives it. Route through _recipients(): %s") % str(offenders))


func test_the_allowlist_earns_its_entries() -> void:
	# An allowlist nobody checks is a mute button. Every name in it must
	# still exist and must still be a direct-iteration site — otherwise it
	# is a stale exemption quietly covering whatever takes that name next.
	var functions := _functions(_server_source())
	for name in SOCKET_ONLY:
		assert_true(functions.has(name),
			"SOCKET_ONLY names %s, which no longer exists — remove it" % name)
		if functions.has(name):
			assert_true(String(functions[name]).contains("in _clients"),
				"SOCKET_ONLY exempts %s, which no longer iterates _clients — remove it" % name)
		assert_gt(String(SOCKET_ONLY[name]).length(), 20,
			"%s's exemption must say WHY, in words a reviewer can disagree with" % name)


func test_recipients_is_still_the_union() -> void:
	# The scan above is worth nothing if `_recipients()` itself stops
	# including the AI seats — that is the same defect one level up, and
	# it would make every routed call wrong at once.
	var source := _server_source()
	var functions := _functions(source)
	assert_true(functions.has("_recipients"), "server.gd must define _recipients")
	var body: String = functions.get("_recipients", "")
	assert_true(body.contains("_clients"), "_recipients must include the sockets")
	assert_true(body.contains("_ai_clients"), "_recipients must include the AI seats")


func test_chat_reaches_every_peer() -> void:
	# The specific instance, asserted where it lives rather than only by
	# the scan: a scan proves the shape, this names the feature.
	var functions := _functions(_server_source())
	assert_true(functions.has("_handle_chat"), "server.gd must handle chat")
	var body: String = functions.get("_handle_chat", "")
	assert_true(body.contains("_recipients()"),
		"chat must be relayed through _recipients(), or AI seats and any "
		+ "non-socket human never hear it (#253)")
