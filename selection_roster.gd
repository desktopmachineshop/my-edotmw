class_name SelectionRoster
extends RefCounted

## Which of a client's selected squads are still alive to command, and the
## same answer for every stored control group.
##
## All-static and pure, for the reason `selection_pick.gd` and
## `render_cull.gd` are: the client cannot run headless (D-014), but the
## half with the interesting failure mode — a wiped squad still being
## counted — is set arithmetic over `ClientState` and needs no GPU to be
## wrong. `ClientState` is the argument for the reason `TerrainFog.rebuild`
## takes one (D-106's 2026-08-17 amendment): a rule that cannot be tested
## where it lives is a fact about where it lives.
##
## ## The bug this closes (#88, playtest P03)
##
## `ClientState` has pruned a wiped squad out of `squads` since M1, with a
## comment saying the point is that "the GUI offers a dead squad for
## selection ... a client that knows better should not be sending the order
## at all". `client.gd` never consumed that fact. `_selected` was appended
## to and cleared and never filtered, and Ctrl+N stored a plain
## `duplicate()` of it, so a control group kept its dead members for the
## rest of the match. Recall the group after a wipe and the panel reads
## "2 squads / 0 soldiers", with a chip sitting at 0/36.
##
## Nothing failed, because nothing was wrong on the wire: the order paths
## already go through `ClientState.encode_*`, every one of which refuses a
## squad this client does not own, and the server refuses again from the
## sim (D-002). It was a display and input-hygiene defect only — the
## declared-and-unread family with the reader missing rather than the
## writer.
##
## ## Liveness is `owns()`, not `alive_of() > 0`
##
## `ClientState.owns` — membership of `squads` — is already the one
## definition of "a squad this client may command", and it is what the
## encoders gate on, so using it here means the selection can never contain
## a squad whose order would be silently dropped. `alive_of()` is the wrong
## test in two directions: it reads 0 for a squad whose SQUAD_INFO has not
## landed yet (`squads_awaiting_composition`), which would evict a
## freshly-produced squad, and it reads 0 for a concealed squad whose
## composition has moved into `_ghosts` (D-025) — which cannot happen to
## your own army today, and should not become a way to lose a selection if
## it ever does.


## The subset of `ids` this client can still command, in the order given.
##
## A copy: callers hold these arrays across frames, and pruning in place
## would mutate a stored control group as a side effect of drawing the
## panel.
static func living(ids: Array, state: ClientState) -> Array:
	var kept := []
	if state == null:
		return kept
	for id in ids:
		if state.owns(int(id)):
			kept.append(int(id))
	return kept


## Every stored control group, pruned the same way.
##
## A group keeps its SURVIVORS rather than being dropped wholesale — losing
## one squad out of eight must not cost a player the group, which is the
## behaviour that would make this fix worse than the bug. A group that
## empties out entirely is erased instead of kept as an empty array: recall
## treats a missing group and an empty one identically (it selects
## nothing), so keeping the key would only leave `has()` lying about what
## the player still has.
static func living_groups(groups: Dictionary, state: ClientState) -> Dictionary:
	var kept := {}
	for group in groups.keys():
		var survivors := living(groups[group] as Array, state)
		if not survivors.is_empty():
			kept[group] = survivors
	return kept
