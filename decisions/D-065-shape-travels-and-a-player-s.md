### D-065 · 2026-08-04 · Accepted — shape travels, and a player's choice latches
**Decision:** Two fixes to D-058, which shipped its server half only.

1. **`SQUAD_INFO` carries `shape`.** It never did. The client resolved
   shape from `UnitDef.formation_shape`, which was correct before D-058
   made shape mutable and was never revisited.
2. **A player order latches.** `SquadSim.set_shape` (the player's entry
   point, via `ORDER_FORMATION`) marks the squad chosen; the simulation's
   own switching goes through the new `SquadSim.suggest_shape`, which
   ignores a chosen squad. The economy now suggests rather than sets.

**Rationale:** the reported symptom was "the formation buttons don't
change the formation of the workers". There were two independent causes
and the second one hid behind the first.

*Workers specifically:* `Economy._tick_hauls` asserted `ring`/`sparse` on
every gathering crew every tick, so a player's choice was undone within
100 ms — one tick. The button worked perfectly and its effect lasted less
than a frame.

*Everybody, invisibly:* shape was not on the wire at all, so no client
ever learned about any shape change. D-058's own text says the server
"resends ordinary `SQUAD_INFO` — the message that already carries shape".
It did not carry shape. The server-side plumbing it describes
(`take_shape_dirty`, per-client visibility filtering, the no-op guard) is
all real, correct, and was sending a message with the field missing.

**This was also a live desync**, not only a cosmetic bug. Shape is in
`composition_hash`: the server hashed the real shape, the client hashed
the UnitDef's. Every gathering crew that reached a node — which is every
gathering crew — put its owner into permanent disagreement with the
server. A test now reproduces it (`test_client_state.gd`), and it fails
by exactly one desync before the fix.

**Why latch rather than let the sim keep switching:** the automatic
ring-while-working switch is a convenience for crews nobody has an
opinion about. A player who presses a button has an opinion, and a rule
that silently reverts a direct order is worse than no rule. The cost is
stated plainly: a crew you have shaped by hand stops auto-switching for
the rest of the match. That is the deal the button makes.

**Rejected alternatives:**
- *Clearing the latch on the next gather order* (rejected — "sometimes
  your order sticks" is harder to learn than "it sticks").
- *Hiding the formation buttons for gatherers* (rejected — it makes the
  symptom go away by removing the feature, and leaves the wire bug).
- *Sending shape in the curve stream* (rejected — that is D-058's own
  revisit trigger, and it fires on bandwidth evidence, which does not
  exist. `SQUAD_INFO` per change is still the cheap answer).
- *Deriving shape on the client from replicated haul phase* (rejected —
  D-058 already rejected replicating the phase, and this bug is not a
  reason to reopen it).

**Consequences:** `SQUAD_INFO` grew a length-prefixed string per squad —
a handful of bytes on a message sent per change, not per tick. Replays
are the wire format byte-for-byte (D-016), so **replay files recorded
before this change no longer decode**. `D-059`'s "ring means working"
client-side inference is now defeatable: a player who parks workers in
`ring` on the road gets the working animation while they walk. Cosmetic,
one-way, and left alone.

**Revisit trigger:** if any future system wants to change a squad's shape
automatically (a shield wall on contact, skirmishers spreading under
fire), it must use `suggest_shape` — and if such a rule is important
enough that it should override a player, that is a real design decision
and belongs here, not in a call site.

---
