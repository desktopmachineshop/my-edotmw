# D-20260819 · Tired men, and men fighting uphill

**Status:** ACCEPTED — workstream 11 of
D-20260818-battle-quality-outranks-player-count. **Amends:**
D-20260819-a-charge-is-spent-on-its-impact (fatigue replaces the
interim expiry deadline, as promised there) and
D-20260819-stances-are-standing-orders (walk/run arrives here, priced).
**Relates to:** D-024 (both terms are squad scalars), D-084/world-look
(elevation acquiring tactical meaning is the named revisit — see below).

## Decision, in two halves

**Fatigue** — one server-only per-squad scalar, 0..100, starting fresh:

- Drains: **charging −12/s**, **fighting −2/s** (any tick the squad
  landed or received a blow), **running −6/s** (the new stance bit,
  below). Recovers **+4/s** otherwise. No wire: the panel indicator is
  its own decision, exactly as morale visibility is.
- Effects: damage output scales by `0.5 + 0.5 × fatigue/100` — an
  exhausted squad hits at half strength; a **charge order is refused
  (degrades to attack-move) below 40 fatigue**, and the sprint itself
  now ends when fatigue crosses 25 — **replacing the CHARGE_TICKS
  deadline outright**. The cost now LINGERS: a squad cannot charge,
  rest, and charge again for free, which the deadline never priced.
- **RUN** joins the stance byte (bit 8): pace ×1.3 while fatigue holds
  above 20, draining as above. With fatigue priced, run is a real
  choice instead of the free lever ws7 refused to ship.

**Height** — attacking downhill hits harder, uphill softer:

- The sim gains a read-only `elevation` field (set from the server's
  own `TerrainGen.elevation_field`, absent in bare test sims — absent
  means flat, multiplier 1, so every existing test is untouched).
- When attacker and defender cells differ by at least
  `HEIGHT_STEP` (0.05 of the elevation field's range): **×1.15
  downhill, ×0.85 uphill** on damage. Discrete per-cell elevation on
  the SERVER only — D-084's "the picture interpolates, the simulation
  does not" split survives untouched, and the world-look entry's
  warning that its rendering freedom "stops being free the moment
  elevation acquires tactical meaning" is hereby paid: the SIM reads
  the discrete field both sides already agree on, never the
  interpolated surface.

## Rejected alternatives

- **Replicating fatigue now.** A wavering/tired indicator is a UI
  truth-disclosure decision (who may see an enemy's exhaustion?), not a
  tuning knob; shipping the scalar server-only first keeps this entry
  small and honest.
- **Elevation as a morale term too.** One mechanic per entry; if
  holding the high ground should also steady men, that is a measured
  playtest argument away, one multiplier, its own amendment.
- **Slope-of-path movement costs.** Real, and enormous: it reprices
  every flow field. Out of scope; noted for M10's successors.

## Revisit trigger

If the ladder shows charge-spam still profitable (drain too cheap) or
armies arriving permanently exhausted (recovery too slow), the four
rates are data-shaped constants in one place. If anyone wants fatigue
per SOLDIER, that is D-006's revisit, not a knob.
