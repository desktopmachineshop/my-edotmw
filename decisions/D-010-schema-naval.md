# D-010 schema log — naval

Part of **D-010** (data-driven definitions). The decision, the rules for
adding to this log, and the index of the other schema logs live in
[`D-010.md`](D-010.md); this file is only the log for naval.

**Append at the END. Never reorder, never edit an entry in place.** One
file per workstream is what stops four branches conflicting on one
monolith — see `README.md` rule 1, which this split exists to make D-010
obey.

**Scope:** the water domain — the fields naval adds to `UnitDef`
and `BuildingDef`. See `docs/plans/naval.md`.

---

- **2026-08-28 — added `UnitDef.movement_domain: String = "ground"`
  (enum `ground`/`water`) and `UnitDef.transport_capacity: int = 0`.**
  Naval, #301 and `docs/plans/naval.md` §2.2/§5, stage 6 (content).
  Both default to what every existing unit already is, so all 39 shipped
  land `.tres` are unchanged.

  `movement_domain` is a DOMAIN rather than an `is_ship` flag because
  `SquadSim._tier` gains a third value and the three are mutually
  exclusive by construction: a ship is never on a wall, and a land squad
  is never on open water except as cargo, which is not in the world at
  all. `transport_capacity` counts SQUADS rather than soldiers, because a
  carried squad is removed from the world whole — there is no partial
  load and so nothing to count in men.

  **Added by stage 6 rather than by stage 2, which the cut-list assigns
  `movement_domain` to, and the reason is worth recording.** Ten ship
  `.tres` land in this stage, and a `.tres` naming a property its schema
  lacks does not fail — the value is silently dropped and reads as the
  default, which is the declared-and-unread family with the writer
  missing instead of the reader. Both fields have a reader the same day:
  `tests/test_naval_roster.gd` screens by `movement_domain` (and asserts
  every land unit is `ground`) and prices transports on
  `transport_capacity` per resource point. Stage 2 consumes
  `movement_domain` for pathing; it does not need to add it.

