# D-20260817 · 2026-08-17 · Accepted — a selection holds only squads this client can still command

**Decision:** the client's live selection and every stored control group
are filtered, once per frame, against `ClientState.owns` — the set the
state layer has maintained since M1. `selection_roster.gd` is the pure
half (`SelectionRoster.living`, `SelectionRoster.living_groups`);
`client.gd._prune_selection` is the caller, and it runs immediately after
the packets that could have killed something and before anything counts,
draws or orders what `_selected` holds.

Three clauses:

1. **Liveness is `owns()`, not `alive_of() > 0`.** Membership of
   `ClientState.squads` is already the one definition of "a squad this
   client may command", and it is what every `encode_*` gates on — so a
   selection filtered this way can never contain a squad whose order
   would be silently dropped. `alive_of()` is wrong in two directions: it
   reads 0 for a squad whose SQUAD_INFO has not landed yet
   (`squads_awaiting_composition`), which would evict a freshly-produced
   squad, and it reads 0 for a concealed squad whose composition has
   moved into `_ghosts` (D-025).
2. **A group keeps its survivors.** Losing one squad out of eight must
   not cost the player the group. A group that empties out entirely is
   erased rather than kept as an empty array — recall treats a missing
   group and an empty one identically, so keeping the key would only make
   `has()` lie.
3. **Groups are pruned on the same frame pass as the live selection, not
   only on recall.** A control group is a selection a player put away; it
   has no business ageing differently from the one on screen, and
   filtering only at the recall keypress would oblige every future reader
   of `_control_groups` to remember to filter for itself.

## Rationale

Reported by the owner from playtest P03 (issue #88, step 6), whose pass
criterion says dead members are **silently dropped**. A squad wiped in
combat stayed in the selection and in any control group it belonged to:
recall the group after the death and the panel reads "2 squads / 0
soldiers", with a chip sitting at 0/36.

**The state layer already knew, and the client never asked.**
`client_state.gd` has removed a wiped squad from `squads` since M1, under
a comment that names this exact consequence — *"the GUI offers a dead
squad for selection ... a client that knows better should not be sending
the order at all"*. `client.gd` never consumed the fact. `_selected` was
appended to and cleared and never filtered; Ctrl+N stored a plain
`_selected.duplicate()`; recall handed back
`_control_groups.get(group, []).duplicate()` verbatim.

So this is the **declared-and-unread family with the reader missing
rather than the writer** — `BuildingSim.damage` (D-055), `UnitDef.cost`,
the three `CivDef` knobs, the client's explored set (D-106). Nothing
failed, because nothing was wrong: the order paths go through
`ClientState.encode_*`, every one of which refuses a squad this client
does not own, and the server refuses again from the sim (D-002). The
whole defect is display and input hygiene. That is also why it survived
to a playtest — it is invisible to every counter, and the only instrument
that can see it is somebody selecting two squads and getting one of them
killed.

**Why a pure module rather than three inline filters.** `client.gd` is
native-only (D-014), so a filter written inline is a filter with no test
— which is the state the code was already in. The same split
`selection_pick.gd` and `render_cull.gd` use applies exactly: the
interesting failure mode is set arithmetic over `ClientState` and needs
no GPU to be wrong. `ClientState` is the argument for the reason
`TerrainFog.rebuild` takes one (D-106's 2026-08-17 amendment): when a
rule cannot be tested where it lives, that is a fact about where it
lives.

**Why a frame pass rather than only fixing the recall.** The issue names
the recall as the visible half and `_selected` as the same bug one step
less obvious: a plain selection whose member dies while it is selected
ghosts identically, and there is no keypress in that path to hang a
filter on. A single pruning step covers both, and makes every downstream
reader — the panel title, the chip strip, the selection rings, the order
loops, `_selection_can_gather`, `_shared_squad_actions` — correct by
construction rather than by each remembering to check.

## Rejected alternatives

- **Filter at the readers (panel, chips, orders).** The issue's literal
  suggestion, and it fixes the reported reading. Rejected because there
  are eight-odd readers of `_selected` in `client.gd` and a ninth is one
  playtest away; the defect being fixed *is* a reader that was never
  written. One writer is the smaller surface.
- **Prune inside `ClientState` when it removes the squad.** Selection is
  entirely client-side and the wire carries no selection (D-002/D-034);
  putting UI state in the class the bots also run would give
  `bot_client.gd` a `_selected` it has no use for.
- **Drop a control group wholesale once any member dies.** Simplest to
  write, and strictly worse than the bug — a player who loses one squad
  out of eight loses the group.
- **Keep an emptied group as an empty array.** Behaviourally identical on
  recall; rejected only so `_control_groups.has()` keeps meaning "the
  player still has this group".
- **Use `alive_of(squad) > 0` as the predicate.** The obvious reading of
  "dead", and it introduces two new cases (see clause 1) in exchange for
  agreeing with `owns()` everywhere it matters.

## Consequences

- New file `selection_roster.gd`; `client.gd` gains `_prune_selection`,
  `_store_control_group` and `_recall_control_group` (the last two
  extracted from `_handle_key`'s Ctrl+N branch, which is what made them
  reachable from a test at all).
- Cost is one pass over the selection and the stored groups per frame —
  at most a few dozen ints, on the client only. **Nothing per-tick,
  nothing on the wire, nothing on the server**; `squad_sim.gd`,
  `combat.gd` and `vision.gd` are untouched, so no per-squad number
  moves.
- `tests/test_selection_roster.gd` guards it in three layers: the pure
  module, the real `client.gd` driven through actual SQUAD_COMBAT
  packets (instantiated and never added to the tree — the
  `test_return_to_lobby.gd` trick), and a source scan asserting the
  caller exists. **All three were observed red before the fix**: the
  pass-through perturbation of `living()` fails 9 of 14, and restoring
  `client.gd`'s pre-fix wiring verbatim fails 5 of 14 with the reported
  symptom ("Recall handed the panel a corpse", "The panel would read '2
  squads'").
- P03's step-6 criterion is satisfiable; it was failing on this alone.

## Revisit trigger

A future feature putting something into `_selected` that `owns()` would
not accept — an enemy squad for an inspect panel, or a spectator view —
at which point the predicate needs to become "commandable by this client"
explicitly rather than by coincidence. Also: any second place that stores
a squad id across frames (a rally list, a queued order, a saved camera
bookmark) needs the same pass, and the source scan in
`tests/test_selection_roster.gd` only asserts that `client.gd` calls
`SelectionRoster.living` at all — it cannot see a new store that forgot.
