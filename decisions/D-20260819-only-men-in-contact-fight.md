# D-20260819 · Only men in contact fight — Tier 2's contact set

**Status:** ACCEPTED — workstream 3 of
D-20260818-battle-quality-outranks-player-count, and Tier 2 of
D-20260818-rome-total-war-formations-in-three-tiers. **Extends:** D-024
(squad-level stochastic combat — extended, not replaced, exactly as its
Consequences anticipated: "a contact set, rather than an aggregate over
the whole squad"). **Relates to:** D-006 (whose confirmation block makes
this legal in as many words: "the server may compute [soldier positions]
whenever combat needs it and still send nothing"), D-007, D-058,
D-20260818's Tier 1 (cosmetic duels).

## Decision

A squad's damage output per attack is multiplied by its **men in
contact**, not its whole strength. A man is in contact when his nearest
opponent — over both squads' DERIVED soldier positions — is within his
**contact reach**. Everything else in D-024 stands: engagement and
target selection are unchanged (the cell-bucket disk scan), the roll is
the same seeded counter-based function, casualties are integer
decrements with a fractional carry, resolution is server-only, and
nothing new crosses the wire.

Three load-bearing details:

1. **One definition of the pairing, shared by the fight you SEE and the
   fight that RESOLVES.** `engagement.gd` (all-static, pure — the
   Formation family) owns nearest-opponent pairing, the contact reach
   and the contact count. `CosmeticDuel` (Tier 1) now delegates its
   pairing to it, and `combat.gd` reads it for resolution — so the men
   the client draws squaring off are the men the server counts as
   fighting, by construction rather than by two implementations
   agreeing.

2. **Contact reach is `attack_range + 2 × MAX_STEP`, and the slack is
   not padding — it is Tier 1's fiction made load-bearing.** Two engaged
   lines' front ranks stand roughly a cell apart (~1.73 world units at
   hex size 1), which exceeds a melee `attack_range` of 1.5: measured
   man-to-man with no slack, an ENGAGED pair can have a contact count of
   ZERO, and melee deletes itself — the same "separation rule and
   engagement rule are the same arithmetic pointed in opposite
   directions" failure D-067's amendment records. The duel layer already
   draws each man stepping up to `MAX_STEP` toward his opponent (both
   sides step), so the reach a man FIGHTS at is the reach he is DRAWN
   at: `attack_range + 2 × MAX_STEP`. The constants move into
   `Engagement` so combat and the duel cannot drift.

3. **Contact is computed from the ROUND SNAPSHOT, not live state.**
   D-024's simultaneity amendment exists because reading live strength
   mid-round made player 1 win mirror engagements; a contact count
   derived from live `alive` would smuggle exactly that bias back in
   through the formation restamp. Transforms are derived once per squad
   per tick at the round's snapshot strengths and cached for the tick —
   the cache is a per-tick memo of a pure function, not state.

## What falls out, and what deliberately does not

- **Frontage is real.** A wide line lands more men in reach than a deep
  column of the same troops, so it wins the exchange at the point of
  contact — the exit-criterion test plays the whole encounter with a
  real def and asserts the line side keeps more men standing.
- **Envelopment is real, as geometry.** A line laid against a column's
  long flank has more men in reach than one across its narrow front.
  Note what this is NOT: there is no facing term and no flank BONUS
  here — being hit from behind costs extra morale in workstream 4,
  which reads this contact set rather than inventing its own geometry.
- **Ranged squads are unchanged by construction**, not by branch: an
  archer's `attack_range` covers both squads' whole footprints at any
  engagement distance, so his contact count is his strength and the
  arithmetic reduces to D-024's.
- **Buildings stay aggregate on both sides** (building fire at squads,
  squads battering buildings). A building has no soldiers to pair
  against; inventing phantom ones would be caricature data. If siege
  wants frontage later, that is its own decision against D-067's
  numbers.

## Cost

Paid only by squads actually attacking in melee: one transform
derivation per engaged squad per tick (cached across its engagements)
plus one O(attackers × defenders) nearest scan per attack. The lever if
it ever matters is sampling the pairing at reduced resolution, not
caching it across ticks.

**Measured 2026-08-19**, `just test-scenario siege 4 30` A/B against the
branch base, same host back to back, 24 squads packed at separation 10
(the worst case — nearly everything fights): **combat phase 9.59 →
33.19 µs/squad**, whole tick 200.8 → 275.8 µs/squad (the non-combat
share of that delta is more squads surviving to move, not this
mechanic), worst tick 92.9 → 96.1 ms with 0 dropped both sides. Host
was running other agents' containers — treat as the shape, not the
third digit.

Two behavioural findings from the same A/B, both intended in direction:

- **casualties_applied 469 → 698.** Fewer men land per exchange, so
  morale drains slower, squads rout less and stay in the grind — fights
  are longer AND bloodier, which is the RTW shape and points the same
  way as D-056.
- **The siege loop's fog-squads gate is pace-marginal and tipped:** the
  base run passed at `known_squads_max=23` of 24, this branch failed
  twice at 24-of-24 and then passed at 22 — squads that used to die
  young now live long enough to be seen. The standing "read a gate
  failure as a question about the WINDOW before a fault in the change"
  rule (load-testing.md) applies; the gate itself was not touched.

## The Tier 3 collapse trigger, tested from both ends now

The three-tier decision's trigger: if a man must REMEMBER his opponent
across ticks, Tier 2 is not a pure function. Tier 1 probes the visual
half (duels re-target only when their inputs change). This entry adds
the resolution half: the contact count is a pure function of
(curves, shapes, strengths, time), asserted by running it twice on
identical inputs — and a test that ever needs to seed it with "last
tick's pairing" is the trigger firing. The escape is a re-decision,
never a cache.

## Rejected alternatives

- **Squad-centre distance with a frontage FORMULA** (contact ≈
  min(files, opponent files) from shape arithmetic). Cheaper, but a
  second definition of the geometry the duel layer already draws — the
  two would disagree at every corner case (wheeling, terrain clamps,
  partial strengths), and "what you see is not what resolves" is the
  exact gap this tier exists to close.
- **A facing/arc term in the contact test.** Wanted eventually, but it
  belongs to the morale workstream (a rear attack SHOCKS; it does not
  make swords longer). Keeping contact purely metric keeps this entry
  small and the flank term honest.
- **Caching pairings across ticks for cost.** The collapse trigger in
  disguise; explicitly refused.

## Revisit trigger

If test-load shows the contact pass pushing the combat phase over its
share of D-020's tick at scale, sample the pairing (every k-th man
scaled up) before touching the architecture. If a future mechanic needs
the pairing to persist across ticks, stop: that is the three-tier
decision's collapse case, and the choice reopens between Tier 1-only
and Tier 3, with no middle.
