# D-20260828 · A carried squad is cargo, and cargo is not in the world

**Date:** 2026-08-28
**Status:** Accepted (the owner's directive, #301). Design only — no code.
**Issue:** #301, which asks for embark/disembark semantics and marks the
vision question explicitly as *"(decide)"*.
**Design doc:** `docs/plans/naval.md` §3
**Builds on:** `D-20260828-water-is-a-second-movement-domain`

## Decision

**A squad that boards a ship leaves the world.** It has no cell, no
curve, no formation, no derived soldiers, **no vision stamp of its own**,
and **no entry in `visible_to` for anybody — including its owner**. It is
a property of the ship carrying it, replicated on that ship's own
`SQUAD_INFO` as a `cargo` list of `{def_id, alive}`.

It still counts against the squad cap. It is an army slot you are using.

**If the ship sinks, the cargo drowns**, reported through the ordinary
casualty path with `D-20260819-a-casualty-is-visible`'s `fell` byte set.

**You load at a dock and you land anywhere.** Embarking is a two-leg
order in `_begin_tier_crossing`'s exact shape — walk to the dock's land
cell, then one explicit hop into a waiting transport's cargo.
Disembarking is one leg — the ship sails to the navigable cell nearest
the ordered land cell and the cargo hops out onto passable land around
it.

`UnitDef.transport_capacity` (int, default 0) is how many squads a hull
carries.

## Rationale

### Why cargo is invisible even to its owner — and why that is the safe answer, not the awkward one

The server hashes exactly `visible_to(player)`; the client hashes exactly
what it treats as live (D-026 criterion 8). **D-099 already paid for
getting this wrong once:** a ghost must never be folded into
`composition_hash()`, because a client that counted its own ghosts would
hash a strictly larger set and desync **on a perfectly healthy system**.

Cargo is the same shape with the roles reversed — a squad the owner knows
exists and the world does not contain. Any design where the owner's
client treats cargo as live requires both sides to agree on a special
case, forever, in two codebases. **Excluding cargo from `visible_to` on
both sides makes the hashes agree by construction**, with no rule anybody
has to remember and no way for a future caller to break it.

The owner does not lose the information: cargo rides on the ship's
`SQUAD_INFO`, which is an addition to a message that already exists —
D-003 and D-025's standing rule that the curve/info path is EXTENDED,
never duplicated. The HUD draws it in the ship's selection panel.

### Why no vision stamp

#301 left this open. Deciding it "none" follows from the above: a vision
stamp is a per-player field written from squad positions, and cargo has
no position. Giving it the ship's position would be inventing one — and
it would mean loading a scout onto a barge silently widened the barge's
sight, a rule a player cannot see operating. The ship sees for itself,
with its own `vision_range`, which is a number on a `.tres` a player can
be told about.

### Why sinking kills the cargo, when D-076 chose the opposite for walls

D-076's `_evict_stranded_tier1_squads` drops a squad off a destroyed wall
**alive**, and its reason is explicit: *"an invisible instant-kill on top
of losing the structure would be a second, worse punishment nobody asked
for."*

**That reason does not transfer, and the difference is physical.** A
squad on a razed wall is standing on ground that still exists underneath
it. A squad on a sunk transport is in open water it could never have
entered on its own — there is nowhere to evict it to that it was ever
entitled to stand.

The design consequence matters more than the fiction: if cargo survived
its carrier, transports would be strictly better than not using them, a
naval interception would cost the attacker nothing, and warships would
have no job. **The risk of the crossing is what makes the warship a
unit.**

### Why you load at a dock and land anywhere

D-076 faced the symmetrical question and chose "one door", after
explicitly rejecting "climb from any adjacent cell" because *"it makes a
wall's LINE pointless — an attacker could climb up from outside anywhere
along it."*

**There is no line to defend at sea.** A rule that only let you land
where a dock already stood would mean you can only invade an island the
enemy has already settled — on `islands`, the map this feature exists
for, that is a contradiction rather than a constraint.

So the asymmetry is deliberate and each half has its own reason:
**loading is a logistics operation you build for; landing is the
attack.** It is also what every game in the genre does, which is weak
evidence on its own and worth noting is at least not surprising to a
player.

### Why the hop is explicit, and not a walk

This is D-006 clause 1, and it is the same argument D-076 made for
climbing: a squad's position is a pure function of
`(curve, formation, slot, terrain sample)`. An embark that interpolated —
a squad half on the quay and half aboard — needs a partial-embark value
to live somewhere, and there is nowhere legal for it. One teleporting hop
(`_teleport_curve`) has no intermediate state to store.

## Rejected alternatives

- **Cargo is visible to its owner only.** The obvious UX answer and the
  one that reintroduces D-099's desync class. Rejected on the hash
  argument above, which is structural rather than a matter of care.
- **Cargo rides at the ship's cell as a real squad.** Then it is
  targetable, stamps vision, derives soldiers standing on water, and
  needs a rule excluding it from combat that every future caller must
  know. Every one of those is a special case; "not in the world" is none.
- **Sinking ejects survivors onto the nearest shore.** Removes the risk
  that gives warships a purpose (above), and invents a teleport a player
  did not order.
- **Disembark only at a dock.** Symmetrical with D-076 and it deletes the
  feature on the only map that needs it.
- **Ship-to-ship transfer, and loading from any beach.** Not rejected on
  principle — simply not needed for the feature to be playable, and each
  is a new transition surface. Deliberately out of the first cut.
- **A capacity measured in SOLDIERS rather than squads.** More
  realistic, and it makes a 48-strong Corpse Levy and an 8-strong Young
  Giants squad price differently to carry. Rejected for v1 because
  squads are this project's atomic unit everywhere else (D-005), and a
  soldier-denominated capacity would be the only place that is not true.
  Named as a revisit trigger.

## Consequences

- **One schema addition** (D-010 log): `UnitDef.transport_capacity`.
- **One wire addition**: `SQUAD_INFO` gains `cargo` for ships. No new
  message, no new opcode.
- **`composition_hash()` needs no cargo clause**, which is the whole
  point — cargo is absent from `visible_to` on both sides, so the two
  sets are equal without either side knowing about the case. **A test
  must assert a hash match with cargo aboard**, and be observed to fail
  with cargo folded in.
- **The squad cap counts cargo**, so loading an army does not free slots
  to build another one.
- **A drowned squad reports `fell = 1`**, so `test-client`'s casualty
  gate and the corpse ledger see real deaths rather than consumption.
  Corpses are laid at slots that no longer exist in the world — the
  ledger takes positions from the formation restamp, so cargo deaths
  produce **no corpses**, which is correct (nobody saw them die) and
  should be stated in the ledger's own comment rather than discovered.
- **The AI and the bots must both exercise this**, and the gates that
  prove they do are in the design doc §6. `embarks` and `landings` are
  the counters; a zero must fail on the specific leg that broke.

## Revisit trigger

- **Capacity in soldiers.** If squad sizes across the roster diverge
  enough that "one squad" is an unfair unit of shipping — Gravesworn's
  48-strong levy against Stoneblood's 8 giants is already 6:1 — this is
  where that is reopened.
- **A player asking to see their loaded army on the map.** The answer is
  a HUD affordance on the ship, not a change to `visible_to`; if that
  proves insufficient in a playtest, the desync argument above is what
  any alternative has to defeat.
- **Any second thing that carries a squad** — a siege tower, a portal, a
  garrisoned building. Cargo would stop being a naval concept and want
  its own home rather than a field on the ship's info.
