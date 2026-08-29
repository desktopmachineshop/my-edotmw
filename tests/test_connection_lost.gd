extends GutTest

## Guards #162 — a client that loses its server SAYS SO.
##
## The reported symptom was a frozen window. It was not frozen: the
## server had shut down (correctly, per D-075's "no humans, no server"),
## and the client kept its window, kept burning ~44% of a core and kept
## drawing a world that could no longer change. `client: disconnected`
## went to stdout and nowhere a player can see. From the chair that is
## indistinguishable from a hang.
##
## The interesting half of this is testable without a GPU or a window,
## which is the point D-075's 2026-08-16 amendment had to make once
## already: "client.gd is unreachable from GUT" is true of what it DRAWS,
## and false of its node lifetime. Reading it too widely is how the
## second match after a return to the lobby came up with no terrain at
## all for a milestone. So the script is instantiated and driven
## directly, never added to the tree — `_ready()` opens a socket.
##
## What is NOT covered here is whether the panel READS well, which is the
## owner's playtest, and the pre-connection main menu, which is #180 —
## that ticket names this issue as its sibling and is where the message
## eventually lands.


## The real `client.gd`, built as far as this needs and no further.
## Freed by GUT; the overlay is its child and goes with it.
func _client() -> Node3D:
	var client: Node3D = autofree(load("res://client.gd").new())
	client._state = ClientState.new()
	client._build_connection_lost_screen()
	return client


func test_the_screen_exists_before_it_is_needed() -> void:
	# Built at start-up rather than on demand, because the moment it is
	# needed there is no server left to ask for anything — and a client
	# that had to construct an overlay while reacting to a dropped socket
	# is a client that can fail to show one.
	var client := _client()
	assert_not_null(client._connection_lost_layer,
		"the connection-lost overlay must be built up front")
	assert_false(client._connection_lost_layer.visible,
		"and must not be showing until the connection is actually lost")

	# And `_ready` must be the one building it. The helper above calls
	# the builder itself, so this test would otherwise pass on a client
	# that never builds one at all — the caller-exists rule again, and
	# `_ready` opens a socket, so it is read rather than run.
	var source := FileAccess.get_file_as_string("res://client.gd")
	var ready_at := source.find("func _ready")
	assert_gt(ready_at, 0, "there must be a _ready to scan")
	var body := source.substr(ready_at, source.find("
func ", ready_at + 10) - ready_at)
	assert_true(body.contains("_build_connection_lost_screen()"),
		"_ready must build the overlay: by the time it is needed there is no server "
		+ "left to ask for anything, and a client reacting to a dropped socket must "
		+ "not also be constructing the thing that reports it")


func test_losing_the_server_shows_the_player_something() -> void:
	var client := _client()
	client._ever_connected = true
	client._on_connection_lost()

	assert_true(client._connection_lost_layer.visible,
		"a client with no server must say so on screen, not only on stdout")
	assert_true(client._connection_lost_headline.text.to_lower().contains("connection"),
		"the headline must name what happened")


func test_a_server_that_never_answered_says_that_instead() -> void:
	# A connect attempt that is never answered arrives as the SAME ENet
	# event as a server going away, and "it went away" and "there was
	# never one there" are different things to tell a player. Cheap to
	# distinguish; #180 owns the screen this eventually becomes.
	var client := _client()
	client._server_endpoint = "127.0.0.1:25051"
	client._ever_connected = false
	client._on_connection_lost()

	assert_true(client._connection_lost_layer.visible, "it must still be said")
	assert_true(client._connection_lost_detail.text.contains("127.0.0.1:25051"),
		"a client that never reached anybody should name what it could not reach")


func test_the_overlay_blocks_input_so_no_order_goes_down_a_dead_socket() -> void:
	# This is the rule, not a detail of the styling. The client sends
	# orders from ~20 `_peer.send` sites; guarding each one would be the
	# same rule written twenty times, which is how it comes to be written
	# wrongly once. A backdrop that takes the mouse is one place.
	var client := _client()
	var backdrop: ColorRect = null
	for child in client._connection_lost_layer.get_children():
		if child is ColorRect:
			backdrop = child
	assert_not_null(backdrop, "the overlay needs a backdrop to catch clicks with")
	if backdrop != null:
		assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_STOP,
			"the backdrop must swallow clicks — the defeat screen deliberately does "
			+ "not, because that match is still running and this one has no server")


func test_saying_it_twice_is_a_no_op() -> void:
	# ENet reports a disconnect from `service()`, which runs every frame,
	# so without the latch the whole body re-runs sixty times a second —
	# including the `push_warning` an unattended capture takes instead of
	# the panel, which would then flood the log the run is judged by.
	#
	# Asserted through a consequence rather than a counter: hide the
	# overlay by hand between the two calls, and a second call that did
	# any work would put it back.
	var client := _client()
	client._on_connection_lost()
	assert_true(client._connection_lost_layer.visible, "setup: the first call must show it")

	client._connection_lost_layer.visible = false
	client._on_connection_lost()
	assert_false(client._connection_lost_layer.visible,
		"the second disconnect event must do nothing at all — the body runs once")


func test_an_unattended_capture_is_not_covered_up() -> void:
	# `just test-client` renders a frame and CHECKS THE PIXELS — a banner
	# across it would change what every one of those checks measures, and
	# the run has a console verdict to report into instead. Same rule as
	# the HUD scale tests measuring design units rather than screenshots:
	# an instrument must not be altered by the thing it is instrumenting.
	var client := _client()
	client._run_seconds = 30.0
	client._on_connection_lost()
	assert_false(client._connection_lost_layer.visible,
		"a capture run must keep drawing what it was asked to draw")


func test_the_overlay_survives_the_match_it_was_showing_over() -> void:
	# `_teardown_match()` frees the terrain, the squads and the buildings.
	# If it took this overlay too, losing the server DURING a match — the
	# only way this ever happens — would clear the message off the screen
	# a frame after it appeared. The same class of defect as the second
	# match's terrain being parented to a freed node.
	var client := _client()
	client._on_connection_lost()
	client._teardown_match()
	assert_not_null(client._connection_lost_layer,
		"the overlay is not part of the match and must outlive it")
	assert_true(client._connection_lost_layer.visible,
		"and must still be saying so afterwards")


func test_the_disconnect_event_actually_calls_it() -> void:
	# Every test above drives `_on_connection_lost()` directly, so every
	# one of them would still pass with NOTHING CALLING IT — which is this
	# project's most-repeated defect (D-055's uncalled `damage()`, D-106's
	# unread `_explored`) and exactly why that file's guard is a scan for
	# the caller. `_service_network` wants a live ENetConnection, so the
	# caller is asserted by reading it.
	var source := FileAccess.get_file_as_string("res://client.gd")
	assert_false(source.is_empty(), "could not read client.gd to scan it")
	var at := source.find("ENetConnection.EVENT_DISCONNECT")
	assert_gt(at, 0, "there must be a disconnect branch to scan")
	var ends := source.find("ENetConnection.EVENT_RECEIVE", at)
	assert_gt(ends, at, "the disconnect branch must be followed by the receive branch")
	var branch := source.substr(at, ends - at)
	assert_true(branch.contains("_on_connection_lost()"),
		"the disconnect branch must tell the PLAYER — a print goes to stdout, and "
		+ "the reported symptom was a window that said nothing at all")

