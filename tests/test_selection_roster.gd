extends GutTest

## Guards `selection_roster.gd` and its wiring — a squad that is wiped out
## leaves the selection and every control group it belonged to (#88, found
## in playtest P03 step 6, whose pass criterion says dead members are
## silently dropped).
##
## Same split as `test_selection_pick.gd` and `test_render_cull.gd`: the
## client cannot run headless (D-014), so the ranking lives in a pure
## all-static class and is tested directly. The wiring half is tested the
## way `test_return_to_lobby.gd` tests the client's node lifetime — the
## REAL `client.gd`, instantiated and never added to the tree, driven
## through the packets a server would actually send. That is the only shape
## of test that can see this bug: `SelectionRoster` can be perfect while
## nothing calls it, which is precisely the state `client.gd` was in.
##
## Nothing here is about the wire. `ClientState.encode_*` already refuses a
## squad this client does not own and the server refuses again from the sim
## (D-002), so a corpse in `_selected` never produced a bad order — it
## produced "2 squads / 0 soldiers" in the panel, and a control group that
## kept its dead for the rest of the match.


const MILITIA := "gildedreach_levy"


## A client that owns three militia squads, welcomed onto a small map.
func _client_state(alive: int = 36) -> ClientState:
	var state := ClientState.new()
	state.handle_packet(NetProtocol.encode_welcome(
		1, 16, 8, PackedInt32Array([0, 1, 2]), [], 40, 0))
	var entries := []
	for id in [0, 1, 2]:
		entries.append({
			"id": id, "def_id": MILITIA, "alive": alive,
			"shape": "line", "owner": 1,
		})
	state.handle_packet(NetProtocol.encode_squad_info(entries))
	return state


## The server telling this client that `squad` is down to `alive` men —
## the ONLY channel that changes `alive` after spawn (D-024), and therefore
## the only way a squad can die from the client's point of view.
func _casualties(state: ClientState, squad: int, alive: int) -> void:
	state.handle_packet(NetProtocol.encode_squad_combat(
		10, [{"id": squad, "alive": alive, "routed": false}]))


# --- the pure half ----------------------------------------------------

func test_a_wiped_squad_leaves_the_selection() -> void:
	var state := _client_state()
	_casualties(state, 1, 0)
	assert_eq(SelectionRoster.living([0, 1, 2], state), [0, 2],
		"The squad the server just wiped is still selected")


func test_a_hurt_squad_stays() -> void:
	# The mirror, and the one that would make this fix worse than the bug:
	# losing men is not losing the squad.
	var state := _client_state()
	_casualties(state, 1, 1)
	assert_eq(SelectionRoster.living([0, 1, 2], state), [0, 1, 2],
		"One man left is still a squad a player can order")


func test_order_is_kept() -> void:
	# `_selected` is appended to in click order and the panel's chip strip
	# reads it in that order, so pruning may not quietly reshuffle it.
	var state := _client_state()
	_casualties(state, 0, 0)
	assert_eq(SelectionRoster.living([2, 0, 1], state), [2, 1])


func test_a_squad_this_client_never_owned_is_not_selectable_either() -> void:
	# `owns()` is the predicate, not "has a composition" — an enemy squad
	# has one of those. Nothing puts an enemy in `_selected` today; this
	# pins the definition so nothing can start.
	var state := _client_state()
	state.handle_packet(NetProtocol.encode_squad_info([
		{"id": 9, "def_id": MILITIA, "alive": 36, "shape": "line", "owner": 2},
	]))
	assert_eq(SelectionRoster.living([0, 9], state), [0])


func test_pruning_does_not_mutate_what_it_was_given() -> void:
	# Callers hold these arrays across frames — a control group IS one of
	# them. Pruning in place would edit a stored group as a side effect of
	# drawing the panel.
	var state := _client_state()
	_casualties(state, 1, 0)
	var original := [0, 1, 2]
	SelectionRoster.living(original, state)
	assert_eq(original, [0, 1, 2], "living() must return a copy, not filter in place")


func test_a_group_keeps_its_survivors() -> void:
	var state := _client_state()
	_casualties(state, 1, 0)
	var groups := SelectionRoster.living_groups({1: [0, 1], 2: [2]}, state)
	assert_eq(groups.get(1, []), [0], "Losing one squad out of two must not cost the group")
	assert_eq(groups.get(2, []), [2], "A group that lost nobody is untouched")


func test_a_group_that_is_wiped_out_stops_existing() -> void:
	var state := _client_state()
	_casualties(state, 0, 0)
	_casualties(state, 1, 0)
	var groups := SelectionRoster.living_groups({1: [0, 1], 2: [2]}, state)
	assert_false(groups.has(1),
		"An empty group recalls nothing either way — keeping the key only makes has() lie")
	assert_true(groups.has(2))


func test_a_null_state_selects_nothing() -> void:
	# `_prune_selection` runs every frame, including before a match exists.
	assert_eq(SelectionRoster.living([0, 1], null), [])


# --- the wiring, through the real client -------------------------------
#
# `client.gd` is native-only, but selection is arithmetic over ClientState
# and the control-group table is a plain Dictionary — neither needs a GPU
# or a window. The script is instantiated and NEVER added to the tree, so
# `_ready()` (which opens a socket) does not run. Same trick, and the same
# justification, as test_return_to_lobby.gd's terrain-lifetime tests.


## The real `client.gd`, with three squads it owns and a control group.
## Freed by GUT rather than by hand.
func _client_with_a_group() -> Node3D:
	var client: Node3D = autofree(load("res://client.gd").new())
	client._state = _client_state()
	client._selected = [0, 1]
	client._store_control_group(1)
	assert_eq(client._control_groups.get(1, []), [0, 1],
		"Setup: the group should hold both squads")
	return client


func test_the_reported_repro_recall_a_group_after_a_squad_is_wiped() -> void:
	# P03 step 6, exactly: two squads in a group, one wiped in combat,
	# press 1. The HUD reported the group's original size with the dead
	# squad's soldiers contributing 0 — its title counts `_selected.size()`
	# and its detail sums `alive_of()`.
	var client := _client_with_a_group()
	_casualties(client._state, 0, 0)

	client._recall_control_group(1)
	assert_eq(client._selected, [1], "Recall handed the panel a corpse")

	var strength := 0
	for squad in client._selected:
		strength += client._state.alive_of(squad)
	assert_eq(client._selected.size(), 1, "The panel would read '2 squads'")
	assert_eq(strength, 36, "...with the dead squad contributing 0 soldiers")


func test_the_frame_pass_prunes_the_live_selection_too() -> void:
	# The control group is what makes the bug easy to see; a plain
	# selection whose member dies while it is selected ghosts identically,
	# and there is no keypress in that path to hang a filter on.
	var client := _client_with_a_group()
	_casualties(client._state, 1, 0)

	client._prune_selection()
	assert_eq(client._selected, [0],
		"A squad that died while selected is still in the selection")


func test_the_frame_pass_prunes_stored_groups_too() -> void:
	# A group is a selection the player put away. Filtering only on recall
	# would leave it stale in the meantime — and every future reader of
	# `_control_groups` would have to remember to filter for itself.
	var client := _client_with_a_group()
	_casualties(client._state, 0, 0)

	client._prune_selection()
	assert_eq(client._control_groups.get(1, []), [1],
		"The stored group still holds the wiped squad")


func test_storing_a_group_stores_only_the_living() -> void:
	# Input is delivered BEFORE `_process`, so Ctrl+1 can run on a frame
	# whose prune has not happened yet.
	var client := _client_with_a_group()
	_casualties(client._state, 0, 0)
	client._selected = [0, 1]
	client._store_control_group(2)
	assert_eq(client._control_groups.get(2, []), [1])


func test_a_surviving_selection_is_left_alone() -> void:
	# The prune runs on every frame of every match. Perturbing a selection
	# nothing happened to would be a far worse bug than the one being
	# fixed.
	var client := _client_with_a_group()
	client._selected = [2, 0, 1]
	client._prune_selection()
	assert_eq(client._selected, [2, 0, 1])
	assert_eq(client._control_groups.get(1, []), [0, 1])


# --- the caller ---------------------------------------------------------


## The test that would have caught #88, and the only one here that could.
##
## Every other check in this file can pass while the HUD counts corpses,
## because a mechanism with no caller fails nothing — `ClientState` has
## pruned `squads` on a wipe since M1, with a comment saying the point was
## that "the GUI offers a dead squad for selection", and `client.gd` simply
## never read it. That is the same shape as `BuildingSim.damage` (D-055),
## `UnitDef.cost`, the three `CivDef` knobs, and the client's explored set
## (D-106) — so, as there, this asserts the CALLER exists.
func test_something_outside_selection_roster_actually_prunes() -> void:
	var scripts: Array = []
	_all_scripts("res://", scripts)
	assert_gt(scripts.size(), 10, "Found almost no scripts — the walk is broken, not the code clean")

	var callers: Array = []
	for script_path in scripts:
		var path_str := String(script_path)
		if path_str == "res://selection_roster.gd" or path_str.begins_with("res://tests/"):
			continue
		var handle := FileAccess.open(path_str, FileAccess.READ)
		if handle == null:
			continue
		var text := handle.get_as_text()
		handle.close()
		if text.contains("SelectionRoster.living"):
			callers.append(path_str)

	assert_true(callers.has("res://client.gd"),
		"client.gd must filter its selection and its control groups — a prune "
		+ "nothing calls is exactly the defect #88 reports")


func _all_scripts(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_all_scripts(path.path_join(sub), out)
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".gd"):
			out.append(path.path_join(normalised))
