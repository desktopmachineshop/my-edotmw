# D-20260819 · Morale reads the fight: flank shock, chain rout, pursuit

**Status:** ACCEPTED — workstream 4 of
D-20260818-battle-quality-outranks-player-count (exit criterion 4).
**Extends:** D-019 (morale and routing are the RTW half) and D-024
(morale stays a per-squad scalar; nothing here is per-soldier).
**Reads:** D-20260819-only-men-in-contact-fight's geometry.
**Relates to:** D-050 (allies), D-016 (all of it must replay).

## Why this exists

The gap analysis's largest finding: our morale model reads exactly one
input — own casualties — where RTW's reads a dozen, and that difference
is most of why RTW battles END. Envelopment here grinds instead of
breaking (Tier 2 gave it attrition, not terror); every squad's morale is
an island, so no battle cascades to a decision; and a rout is a pause,
not a defeat, because a fleeing squad suffers nothing for having fled.

## Decision — three terms, all squad-level scalars in `combat.gd`

1. **Flank and rear shock.** When casualties land, the defender's morale
   loss is multiplied by where the blow came from: frontal ×1, flank
   ×`FLANK_MORALE_MULT` (1.5), rear ×`REAR_MORALE_MULT` (2.5). The
   aspect is a pure function (`Engagement.aspect`) of the defender's
   derived facing (`Formation.heading` — the same facing the soldiers
   are drawn with) and the wrap-aware direction to the attacker: front
   and rear are ~70° cones (|dot| ≥ 0.34), everything between is flank.
   DAMAGE is untouched — Tier 2's frontage already prices the geometry
   in blood; this term prices it in terror, which is what makes
   envelopment break a line rather than merely out-trade it.

2. **Chain rout.** The moment a squad routs, every ALLIED squad within
   `CHAIN_ROUT_RADIUS_CELLS` (8) loses `CHAIN_ROUT_MORALE_LOSS` (12)
   morale — and if that pushes one below its own threshold it routs by
   the same machinery, fleeing the same attacker, cascading. Watching
   friends break is what decides battles; the cascade is bounded because
   a squad can only rout once (`is_routed` guards re-entry) and the
   radius scan reuses the tick's cell buckets with
   `TorusSpace.disk_offsets` (the standing any-radius-scan rule).
   Allied means `are_allied` (D-050) — your own squads included.

3. **Pursuit.** A routed defender takes ×`PURSUIT_DAMAGE_MULT` (2.0)
   damage. A fleeing squad neither faces nor fights back; catching it is
   left emergent — a faster pursuer stays in reach, a slower one drops
   out — so "a faster pursuer cuts down a router" costs no new movement
   mechanic at all. This is what turns a rout from a pause into a
   defeat, and with it the ROUT-RALLY ping-pong (break, jog, rally,
   return, unharmed) stops being free.

## Why constants, not data — for now

The three multipliers and the chain radius are `combat.gd` constants in
`ROUT_FLEE_MULTIPLIER`'s existing style: universal battle rules, the
same for every civ and unit, with no shipped design asking to vary
them. The moment a civ identity or unit role wants one (a phalanx that
shrugs flank shock, troops immune to chain panic), that is a
`UnitDef`/`CivDef` schema addition through D-010's log — declarative
knobs, never a per-civ branch (D-047) — and this entry gets the
amendment. Premature schema is how D-070's ~130-file cost starts early.

## What this deliberately does not do

- No per-soldier anything. Facing is the squad's derived heading; the
  aspect is one dot product per casualty event.
- No general's aura, no fatigue, no terrain-height morale — workstreams
  11–12, each with its own entry.
- No new wire. Morale was never replicated (clients see its
  consequences as routs, which already replicate); nothing here changes
  that.
- No change to WHEN a squad rallies (D-024's recovery/rally margin
  stands) — only to how it gets broken and what fleeing costs.

## Exit criteria (written before the code)

1. Rear engagement breaks an otherwise identical squad sooner than
   frontal, with a roster def, in a whole encounter — red if the aspect
   term is removed.
2. One squad breaking measurably drains a nearby ally and not a distant
   one — red if the chain term is removed — and a marginal ally is
   TIPPED into routing by it (the cascade is real, not just a debuff).
3. A routed defender dies faster than a fighting one under identical
   attack — red if the pursuit term is removed.
4. `Engagement.aspect` is pure, classifies front/flank/rear correctly,
   and pays the torus tax (an attacker across the seam is classified by
   the wrapped direction, not the canonical one).
5. Determinism survives: the existing same-seed-twice battle test still
   passes with all three terms live (D-016).
6. `just test-load` stays clean, with the combat phase quoted at its
   squad count — and any fog-gate wobble read window-before-fault,
   since rout cascades change the pace of a fight again.

## Revisit trigger

If playtests read battles as DECIDING too fast (one bad skirmish
cascading an army), the first lever is `CHAIN_ROUT_MORALE_LOSS`, the
second the radius; both are one-line data edits with this entry
amended. If a design wants morale visible to the PLAYER (a wavering
indicator), that is a wire addition and its own decision — morale
leaving the server is not a tuning change.
