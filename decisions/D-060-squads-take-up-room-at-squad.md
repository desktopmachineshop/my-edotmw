### D-060 · 2026-08-04 · Accepted — squads take up room, at squad granularity
**Decision:** Squads that have ARRIVED do not share a cell: the
higher-id one settles onto the nearest free cell
(`SquadSim._separate_arrivals`). Movement in transit is unchanged, and
there is no per-soldier collision.

**Rationale:** twenty squads could occupy one cell and render as a single
heap, so an army had no physical extent.

**Why not per-soldier collision, which is what was asked for:** D-006
names it specifically — "local avoidance, collision push-back, jostling"
each give a soldier integration state and fire the revisit trigger. That
purity is what lets client and server agree on 40,000 soldier positions
without sending any of them; it is not a small thing to trade for
spacing. The GOAL — armies taking up room rather than heaping — is a
squad-level property, and squads are the atomic unit (D-005), so it is
achievable without touching the keystone.

**The first attempt was wrong and an existing test caught it.** Spreading
DESTINATIONS at order time gave twenty squads twenty different goals, so
they built twenty flow fields instead of sharing one — destroying D-007's
per-destination sharing, which is the entire scaling claim, and undoing
what `_quantise` (D-038) exists to enforce. Separation therefore happens
on ARRIVAL: travel keeps one destination and one field, and the pile-up
is resolved only where it shows.

**Rejected alternatives:**
- *Per-tick separation of overlapping squads* (rejected for now — needs
  per-squad integration state and a curve rebuild every time two units
  brush, which is a real cost against D-020's tick budget and a real
  design decision, not something to slip in under a rendering fix).
- *Per-soldier collision* (rejected — D-006's explicit revisit trigger).

**Consequences:** squads still walk THROUGH each other in transit, and
two already-overlapping squads are not pushed apart. Both are visible and
neither is fixed here.

**Revisit trigger:** if formations need to hold a line against each other
— a shield wall that genuinely blocks — squad-level separation is not
enough and D-006 has to be reopened deliberately.

---

**Amendment, 2026-08-18 — the clearance was an order of magnitude short
(see `D-20260818-squads-separate-by-their-footprints.md`).** "Do not
share a cell" is one cell of separation between squads that are eleven
cells wide, so this decision's own goal — armies with a physical extent —
was not actually reached: squads ordered to one place overlapped almost
completely. Everything above still stands (arrival-time, squad-granular,
one destination and one flow field, no per-soldier collision); only the
required distance changes, to `Formation.footprint`'s radius for each of
the two squads, summed.
