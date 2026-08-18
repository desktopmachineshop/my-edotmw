### D-058 · 2026-08-04 · Accepted — formation is a player's choice, and replicated state
**Decision:** A squad's formation is chosen by the player from three
options offered for every unit — **sparse**, **tight**, **ring** — and is
mutable, replicated squad state rather than a fixed property of its
UnitDef. Gatherers switch themselves: **ring while working a node,
sparse while walking**, decided by the SIMULATION.

`line`, `column` and `wedge` remain implemented for .tres defaults; they
are simply not offered in the UI.

**Rationale:** shape was set once at spawn from `UnitDef.formation_shape`
and never changed, so a gathering crew stood in the same order whether it
was marching or working — it looked like a squad that happened to be near
a resource rather than one working it.

**The part that made this more than a UI change:** shape is an input to
`Formation.slot_offset`, so it decides where every soldier in the squad
stands, and it is part of `composition_hash`. A client that missed a
change would draw the squad in the wrong shape AND report a desync on a
perfectly healthy system. So changing it needs the same treatment
`alive` gets: `SquadSim.take_shape_dirty()` mirrors
`BuildingSim.take_dirty()`, and the server resends ordinary `SQUAD_INFO`
— the message that already carries shape — for changed squads only,
filtered per client by visibility.

`set_shape` ignores a no-op deliberately. That is what lets the economy
assert the right shape every tick without generating wire traffic; without
it a gathering crew would resend its composition ten times a second to
every client that can see it, and D-003's zero-cost-when-idle claim would
be false for the whole economy.

**Why the sim decides the gatherer switch, not the client:** the haul
phase is not replicated, so a client physically cannot infer it. The
alternative — replicating the phase so the client could switch shape
cosmetically — is strictly more wire traffic for the same picture, and
would put a second copy of the rule on the untrusted side.

**Rejected alternatives:**
- *Client-side cosmetic shape override* (rejected — D-006 clause 2 allows
  cosmetic offsets that are never read back, but shape is hashed, so a
  local override would desync).
- *A new wire message for formation* (rejected — `SQUAD_INFO` already
  carries shape; a second message would be a second thing to keep in step
  with the hash).
- *Formation as a UnitDef property only* (rejected — that is what it was).

**Consequences:** any future system that wants a squad to change shape —
a shield wall on contact, skirmishers spreading under fire — now has the
plumbing, and needs no new protocol. Note the cost is per CHANGE, so a
mechanic that toggles shape every tick would be expensive; that is a
reason to make such a rule hysteretic, not a reason to avoid it.

**Revisit trigger:** if formation changes ever become frequent enough
that `SQUAD_INFO` resends show up in the bandwidth figures (D-041's
595 B/client/s), move shape into the curve stream instead of the discrete
one.

---

---

**Amended 2026-08-18 — all six shapes are offered.** The owner set the
project's formation target explicitly during playtest P09 (#35): *"I want
Rome Total War formation behaviours. Sacrifice some performance now to get
it."* Choosing line versus column versus wedge is core to that game, so
the clause above — "`line`, `column` and `wedge` remain implemented for
.tres defaults; they are simply not offered in the UI" — is superseded.
All six `.tres` now carry `offered = true`.

**What this does and does not buy.** It makes the six shapes *choosable*;
it does not make them behave as RTW's do. Wedge without a charge mechanic
is a triangle that walks, and line without adjustable width is one fixed
frontage. Those are rows A9/A10 of #35's gap table and need the D-006
amendment, not a data flag. This change is worth making on its own only
because the shapes were already implemented, already replicated and
already validated server-side — nothing was built for it.

**It was not the one-line data change it looked like.** The commands grid
is `ACTION_COLUMNS × ACTION_ROWS` and held three formations plus Stop plus
Gather, five of six. Six formations is eight buttons, and `action_slot`
clamps nothing — buttons seven and eight would have been positioned below
the panel's own bottom edge, drawn over the world. `ACTION_COLUMNS` is 4
now, which seats eight WITHOUT moving `actions_column_width`: that width
is bounded by the chip strip's reservation and can already reach zero on a
narrow window, so widening the column would have taken the eighth button
out of a squad's order chips. The cost is button width instead. See
`hud_layout.gd`'s note above `ACTION_ROWS` for why a third row was not the
answer either.

**The general shape of that, which is why it is written down:** a flag
whose name says "is this offered to the player" had a layout constant
sized around its current value, in another file, with no link between
them. Nothing asserted the two agreed, and the failure would have been
invisible to every test — two buttons drawn off the bottom of a panel are
exactly the "numbers right, picture wrong" class this project has now hit
in terrain, in unit colour and in box winding.
