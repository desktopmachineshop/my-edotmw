extends GutTest

## Guards D-20260818-node-placement-is-budgeted (issue #109): the client grows
## revealed resource-node cells a bounded slice at a time, and grows every one
## of them exactly once.
##
## The defect was not a wrong forest. It was a right one grown all at once:
## every cell the server had revealed since the last frame was placed in the
## frame it arrived, at ~87 us a cell — a terrain sample, a biome
## classification, its six neighbours' biomes, and a stand of trees with a
## sample each. The shipped map carries 7,664 of them, and a squad walking
## into unexplored woodland reveals a great many at once.
##
## So these come in three halves, and the last two are the ones that matter:
##
## 1. **The queue is right** — bounded slices, insertion order, every cell
##    once, and a cell felled before its turn never grown.
## 2. **The queue is FED** — `ClientState` records a reveal as news, not only
##    as knowledge, because the diff it replaces (`nodes.size() !=
##    _node_placed.size()`) is a size comparison standing in for set equality
##    and a budget makes drawn lag known on purpose.
## 3. **The budget is APPLIED** — `client.gd` grows through it and no longer
##    walks the whole known-node dictionary. This project's standing "grep for
##    uncalled public members" rule written as a test: a budget nothing spends
##    fails nothing at all, and the frame it was meant to save is still
##    dropped.


# --- the queue -----------------------------------------------------------


func test_a_burst_is_drawn_a_slice_at_a_time_and_every_cell_once() -> void:
	var queue := NodePlacement.new()
	var burst := []
	for cell in range(500):
		burst.append(cell)
	queue.reveal_all(burst)

	var drawn := {}
	var frames := 0
	while not queue.is_settled():
		var slice := queue.take(NodePlacement.PER_FRAME)
		assert_true(slice.size() <= NodePlacement.PER_FRAME,
			"a frame grew %d cells against a budget of %d" % [
				slice.size(), NodePlacement.PER_FRAME])
		assert_gt(slice.size(), 0, "a frame that grows nothing never drains the queue")
		for cell in slice:
			assert_false(drawn.has(cell), "cell %d was grown twice" % cell)
			drawn[cell] = true
		frames += 1
		assert_lt(frames, 500, "the queue is not draining")

	assert_eq(drawn.size(), 500, "every revealed cell is grown eventually")
	assert_gt(frames, 1, "500 cells in one frame is the defect, not the fix")


func test_the_oldest_reveal_is_grown_first() -> void:
	var queue := NodePlacement.new()
	queue.reveal_all([70, 71, 72])
	queue.reveal_all([80])
	assert_eq(queue.take(4), [70, 71, 72, 80] as Array[int])


func test_a_cell_revealed_twice_waits_once() -> void:
	var queue := NodePlacement.new()
	queue.reveal_all([12, 12, 13])
	assert_eq(queue.pending_count(), 2)
	assert_eq(queue.take(9), [12, 13] as Array[int])


## A node can run dry between the packet that revealed it and the frame that
## would have grown it — the client is deliberately behind now. The server
## reports that felling ONCE, for a tree this client never drew, so a queued
## cell left in place would grow a stand on a stump that nothing ever takes
## back down.
func test_a_cell_felled_before_its_turn_is_never_grown() -> void:
	var queue := NodePlacement.new()
	queue.reveal_all([4, 5, 6])
	queue.forget(5)
	assert_eq(queue.take(9), [4, 6] as Array[int])


func test_a_budget_of_nothing_grows_nothing_and_keeps_the_queue() -> void:
	var queue := NodePlacement.new()
	queue.reveal_all([1, 2])
	assert_eq(queue.take(0), [] as Array[int])
	assert_eq(queue.pending_count(), 2)


func test_a_match_ending_empties_the_queue() -> void:
	var queue := NodePlacement.new()
	queue.reveal_all([1, 2, 3])
	queue.clear()
	assert_true(queue.is_settled())
	assert_eq(queue.take(9), [] as Array[int])


# --- the wire feeds it ---------------------------------------------------


func test_the_wire_reports_a_reveal_as_news_and_the_drain_empties_it() -> void:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_nodes([
		{"cell": 11, "kind": Economy.ResourceKind.WOOD},
		{"cell": 12, "kind": Economy.ResourceKind.STONE}]))

	assert_eq(state.nodes.size(), 2, "knowledge, as before")
	var news: Array = state.take_revealed()
	assert_eq(news, [11, 12], "and the same cells as news, in arrival order")
	assert_eq(state.take_revealed(), [], "drained once, like `felled`")
	assert_eq(state.nodes.size(), 2, "draining the news does not forget the nodes")


func test_a_new_match_starts_with_no_reveals_outstanding() -> void:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_nodes([
		{"cell": 11, "kind": Economy.ResourceKind.WOOD}]))
	state.leave_match()
	assert_eq(state.take_revealed(), [],
		"a reveal from the last match would grow a tree into the new one's world")


# --- and something spends it ---------------------------------------------


## The test that would have caught #109 staying unfixed, and the only one here
## that could.
##
## Every other check above passes against a NodePlacement that no drawing code
## ever calls — the queue would be correct, unspent, and the frame still
## dropped. So this asserts the CALLER, the same shape as
## test_terrain_fog.gd's `set_fog` scan and for the same reason.
func test_the_client_grows_nodes_through_the_budget() -> void:
	var body := _client_function("_refresh_resource_nodes")
	assert_true(body.contains("NodePlacement.PER_FRAME"),
		"client.gd must grow revealed nodes a budgeted slice at a time — a "
		+ "budget nothing spends saves no frames")
	assert_false(body.contains("for cell in _state.nodes"),
		"client.gd must not walk every known node to find the new ones: that "
		+ "is the unbudgeted placement #109 is about, and with a budget in "
		+ "place it also runs on every frame spent catching up")


## One function's source out of client.gd. Reading the file rather than the
## script object because the thing under test is what the code DOES, and
## `client.gd` needs a window and a GPU to do it (D-075) — the lifetime half
## is testable, this is neither lifetime nor pixels.
func _client_function(name: String) -> String:
	var handle := FileAccess.open("res://client.gd", FileAccess.READ)
	assert_not_null(handle, "client.gd must be readable")
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()

	var start := text.find("func %s(" % name)
	assert_gt(start, 0, "client.gd has no %s — the scan is broken, not the code clean" % name)
	if start < 0:
		return ""
	var end := text.find("\nfunc ", start + 1)
	return text.substr(start, -1 if end < 0 else end - start)
