# D-20260818 · Rome: Total War formation behaviour, in three tiers

**Status:** PROPOSED — not accepted, not implemented. Written for the
owner to approve or reject.

**Amends:** D-006 (derived soldier positions), whose corrected revisit
trigger this pulls. **Relates to:** D-019 (formations and morale are the
RTW half), D-024 (squad-level stochastic combat), D-058 (formation is a
player's choice).

## Why this exists

The owner set the target during playtest P09 (#35):

> I want Rome Total War formation behaviours. Sacrifice some performance
> now to get it.

and then asked the question that decides the whole shape of it:

> also individual unit tracing i think is required to get true motion and
> unit to unit combat in fights??

Yes — and that is precisely D-006's corrected revisit trigger, which names
"emergent per-soldier movement: local avoidance, collision push-back,
soldiers physically jostling, neighbours pathing into a vacated slot".
So this cannot be decided by implementing something; it has to be decided
first.

## What is actually missing, measured against the code

Surveyed 2026-08-18 on `origin/main`. Present: wheeling with the inside
men slowed (D-20260818), formation held on the march, morale and routing
per squad (D-019), shape replicated and hashed, footprint separation for
settled allies. Absent: **player-set facing** (no opcode; facing is
derived from the path), **player-set width/depth** (ranks and files are
constants in `.tres`), **charge** (no such mechanic anywhere), **flanking
or rear attacks** (`combat.gd` contains no facing term at all), **men
pairing off in melee** (`AnimationState.clip_for` is applied per SQUAD via
`set_clip_data(squad_id, ...)`, so every man in a fighting squad plays one
attack clip in unison, at the air), phalanx/testudo, guard mode.

The marching is largely solved. The FIGHT is barely started.

## Decision (proposed): three tiers, and the line is drawn between 2 and 3

**Tier 1 — cosmetic duels. Legal under D-006 today; no amendment needed.**
During a melee the render layer pairs each man with an opponent, turns him
to face it, steps him into contact and animates him against it. Outcomes,
wire and server are untouched. D-006 clause 2 already permits exactly this
("cosmetic offsets are one-way"), and `cosmetic_offset.gd` states outright
that these values are "NOT required to match between machines — nothing
depends on it agreeing". Cost is client frame time, which is the
performance the owner offered to spend. This is the single largest visual
gap to RTW and it needs nothing from this document.

**Tier 2 — derived pairing that combat READS.** The pairing becomes a pure
function of replicated squad state (both curves, both shapes, slot
indices, the seeded RNG D-024 already has). Server and client then agree
by construction and still send nothing — D-006's own confirmation block
allows this in as many words: "if a soldier's position is a pure function
of replicated squad state, the server may compute it whenever combat needs
it and still send nothing." Frontage becomes real: only men in contact
fight, so a wide line beats a deep column at the point of contact, and
flanking falls out of the geometry rather than being a bonus bolted on.

Binding constraint if this is taken: it must be a FUNCTION, never an
accumulation. The moment a pairing persists across ticks as stored state,
it is Tier 3 wearing Tier 2's clothes.

**Tier 3 — genuinely emergent per-soldier movement.** Men walk into
vacated slots, chase routers, shove past each other. This requires
integration state per soldier and breaks clause 1 outright. D-006 names
the only two ways out: network ~40,000 entities, or accept divergence.

**Proposed: take Tier 1 and Tier 2. Do not take Tier 3.**

## Why Tier 3 is refused, and it is not the frame budget

The obvious objection to Tier 3 is cost, and cost is real — RTW ran ~10,000
men on one machine with no netcode; D-018 targets 40,000 across 20
networked players. But cost is not the argument, because the owner has
explicitly offered performance, and because a fight only ever involves the
few squads in contact, so per-soldier work in a melee is affordable even
at scale.

The argument is **fairness**. This is a 20-player game, so combat outcome
cannot depend on where anybody's camera is pointing. CLAUDE.md's standing
LOD plan — "combat resolution, economy simulation and tick rate all vary
by proximity to player attention" — is safe for RENDERING and becomes a
fairness defect the moment outcomes vary by attention. Tier 3 without LOD
is unaffordable at 1,000 squads; Tier 3 with LOD means two players watching
the same battle from different distances can see it resolve differently.
Tier 1 and Tier 2 both dodge this: Tier 1 because outcomes do not depend on
it at all, Tier 2 because the pairing is a pure function of replicated
state and so is identical for every observer regardless of who is looking.

## Consequences

- D-006 clauses 1 and 2 are **unchanged**. This proposal deliberately
  stays inside them; that is the point of stopping at Tier 2.
- D-024 needs extending for Tier 2 (a contact set, rather than an
  aggregate over the whole squad) but not replacing: resolution stays
  squad-level, stochastic, server-only and seeded.
- Facing, width/depth, charge and guard mode (#35 rows A8–A10, A16) are
  ORDINARY features once Tier 2 exists — they need a wire opcode and UI,
  not an architectural change. They are listed here only because the gap
  survey found them together, not because they depend on this decision.
- **`squad_cap` interacts with this** (D-068 already reverts it to an
  engineering ceiling). Nothing here changes it.

## Rejected alternatives

- **Go straight to Tier 3, accept divergence because it is "only
  cosmetic".** Rejected: once men pair off emergently, the pairing is
  what a player reads the fight from. Two clients disagreeing about who
  is fighting whom is not cosmetic, whatever the outcome arithmetic says.
- **Per-soldier authoritative positions on the wire.** Rejected on D-006's
  original ground, unchanged: ~40x the netcode budget, and D-003's curve
  sync does not rescue it because nothing is idle in a melee.
- **Keep aggregate combat and improve only the animation.** That is Tier 1
  alone, and it is worth doing on its own merits — but it leaves frontage
  meaningless, which is most of what makes RTW formations tactical.

## Revisit trigger

If Tier 2's derived pairing turns out to need per-soldier state to look
right — specifically, if a man must REMEMBER which opponent he was fighting
last tick to avoid visibly re-targeting every 100 ms — then Tier 2 is not
expressible as a pure function and the choice collapses back to Tier 1 or
Tier 3, with no middle. Test this early; it is the assumption the whole
proposal rests on.

## Status of the exit criteria

Not written. If this is accepted, it needs criteria in the D-026/D-044
style — written down before the code — and they must include a criterion
that a human plays a battle and says the fight reads as a fight, per
D-085's criterion 14 and the lesson that "landed" and "meets the criteria"
are different claims.
