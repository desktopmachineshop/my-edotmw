# D-20260820 · Men gather round what they strike

**Status:** ACCEPTED — from the owner's playtest of the completed RTW
stack (2026-08-20): *"attacks on buildings & resource collection should
apply unit-to-static-object logic like the unit-to-unit melee does —
units should gather round the building they are hitting, not stand in a
line (exception: ranged troops that can reach from their formation)."*
**Extends:** Tier 1 (D-20260818-rome-total-war-formations-in-three-
tiers) to STATIC targets. **Relates to:** D-006 clause 2 as amended
(this is more bounded, one-way render state), D-058 (the gathering
ring), D-20260819-only-men-in-contact-fight (whose combat arithmetic
for buildings deliberately stays aggregate — this entry is the PICTURE
half only).

## Decision

A melee squad striking a static thing — an enemy building, or the
resource node its crew is working — is DRAWN gathered round it: the
render layer deals each man a unique point on the target's perimeter
(`Engagement.ring_points`, pure), and the existing duel pipeline steps
him there, faces him inward and swings his own arm at it. Nothing new:
the perimeter points simply stand in for the "defenders" the duel
machinery already takes, so `engage`'s bounds (MAX_STEP, REAR_LEAN for
men who cannot reach) and `SoldierMotion`'s easing all apply unchanged
— a big squad on a small hut fills the ring and QUEUES, exactly as it
queues behind a melee line.

- **Dealing is one-per-point** (`SoldierMotion.assign`, reused): men
  wrap the full perimeter instead of piling onto the near arc.
- **Ranged squads are exempt** — they can reach from their formation,
  as the owner said, and they keep the squad-level lean and their
  arrows.
- **Outcomes are untouched.** Combat versus buildings stays aggregate
  (the ws3 entry says why); gathering rates are the economy's. This is
  where men STAND, not what they DO.

## Rejected alternatives

- **Authoritative surround** (the sim placing besiegers around the
  footprint). It would re-litigate separation, reach and D-067's siege
  numbers for a picture the render layer can produce alone.
- **Extending the gathering RING formation's radius to the target.**
  The ring is authoritative shape (hashed, replicated); bending it to
  each target's size would put target geometry into the composition
  hash. The render deals with geometry; the shape stays what it is.

## Revisit trigger

Builders raising a wall are the same picture and are NOT covered yet
(the client-side "which site is this squad building" inference does not
exist); when a playtest names them, they join this entry by amendment.
If siege combat ever reads the surround (per-man battering), that is
the ws3 entry's own revisit, not this one's.
