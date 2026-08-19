# D-20260819 · A formation is a fighting style, not just a shape

**Status:** ACCEPTED — workstream 9 of
D-20260818-battle-quality-outranks-player-count. **Extends:** D-058
(formations as data — the schema grows, the split stays) and
D-20260819-morale-reads-the-fight (the aspect the shock term computes is
the aspect the defence reads). **Relates to:** D-047 (civ flavour
through unit data, never a branch), D-032 (the counter triangle — these
multipliers are the defender's half of the same idea).

## Decision

`FormationDef` gains five mechanical knobs, every one defaulting to 1.0
so every existing formation is bit-for-bit unchanged:

- `taken_front`, `taken_flank`, `taken_rear` — damage-taken multipliers
  by the blow's aspect, the same `Engagement.aspect` the morale shock
  already computes. A phalanx-style wall is hard from the front AND
  still soft from behind, in one schema.
- `missile_taken` — damage taken from missile-class attackers.
- `pace_scale` — movement speed while in the formation. Protection
  costs mobility or it is simply the best button.

Combat computes the aspect ONCE per landed attack and both consumers —
the morale multiplier and the taken multiplier — read the same answer;
two aspect computations would eventually disagree at a cone boundary.

**Two specials ship**, both `.tres` and nothing else: `shield_wall`
(grid, tight, front 0.5 / missile 0.75 / pace 0.6) and `testudo` (square
grid, missile 0.35 / front 0.8 / pace 0.5). Neither is globally
offered — **`UnitDef` gains `formations: Array[StringName]`**, extra
formations granted to that unit beyond the offered base set, which is
how a civ's spearmen know the shield wall and another's do not without
any script naming either (D-047's discipline; the civ test still
passes). The server validates an ordered shape against offered-or-
granted, not offered alone.

## Rejected alternatives

- **Formation bonuses as flat armour numbers on UnitDef.** The whole
  point is that the DEFENCE is directional and belongs to the chosen
  ORDER, not the man — a testudo you flank is a box of slow men.
- **A charge-resist knob now.** The charge multiplies contact damage,
  so `taken_front` already resists a frontal charge; a second knob
  would double-dip until a playtest shows the need.
- **Per-formation attack bonuses.** Offence already has the counter
  triangle and contact; giving shapes damage would relitigate D-032
  through the back door.

## Revisit trigger

If the ladder or playtests show a special dominating (everyone in
shield wall always), the levers are its own numbers — data, one file.
If a formation ever needs a knob per OPPONENT class beyond missile,
that is `bonus_vs`' shape and should reuse its dictionary form rather
than growing five more floats.
