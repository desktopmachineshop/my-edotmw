# D-20260826-a-squad-wears-more-than-one-model

**Date:** 2026-08-26 · **Status:** Accepted

From the owner, supplying the rest of the dwarf roster's models:
*"the hero/general squad should have one general a few other dwarfs with
mixed weapons"* and *"the cannon type thing should have 1 cannon and 3
tenders (same as the crossbow people)"*. Neither is expressible when a
squad is one MultiMesh wearing one model — which every squad has been
since D-009.

## Decision

1. **`UnitDef` grows two render-only fields** (schema change, against
   D-010): `slot_models` names the models of the LEADING formation slots
   (a hero squad's slot 0 is its general; a cannon crew's slot 0 is the
   gun carriage), and `model_mix` is dealt round-robin across every slot
   past them, so a retinue reads as dwarfs with mixed kit rather than
   eight copies of one man. Both default empty — every shipped `.tres`
   keeps meaning exactly what it meant, resolving to `model_id`.
2. **`PrimitiveUnit` draws one MultiMesh per DISTINCT model**, all under
   one `_body` composite node. Slots are grouped at `rebuild`; transforms
   and per-soldier custom data are routed through two small index arrays
   (drawn index → group, group-local instance). Still a handful of draw
   calls per squad, never a node per soldier — D-009 is bent from "one
   MultiMesh per squad" to "one per (squad, model)", not repealed.
3. **The simulation never hears about any of this.** `alive`, casualties,
   combat, the wire and the composition hash all operate on counts
   exactly as before (D-024); which slot wears which mesh changes no
   outcome, so the fields are read by the renderer and by nothing on the
   server. A "cannon" that must DIE separately from its crew would be a
   sim feature and a new decision — this is deliberately not that.

## Why the leader is slot 0, and why that is safe under LOD

`Formation.soldier_transforms_sampled` picks drawn slots as
`i * alive / n`, so drawn index 0 is ALWAYS slot 0: the one soldier the
squad is about — the general, the gun — survives every thinning tier and
is the last thing a distant squad shows. The remaining drawn indices deal
`model_mix` in drawn order, so a background dwarf may swap which mix
entry he wears as detail changes; that is cosmetic, no outcome reads it
(D-006 clause 2), and it buys the routing a load-bearing property: the
written instances of every group form a PREFIX of its buffer, which is
what `visible_instance_count` requires.

## Why the mirrors needed no work

`LatticeCopies` already recurses into composites — a forest chunk is a
Node3D of one MultiMesh per species, and the mirror machinery was built
for exactly that shape. Wrapping the groups in one `_body` node and
mirroring THAT is the whole seam story; a mixed squad wraps like a
uniform one with zero new lattice code.

## Mixed squads and clips

A mixed squad's members do not share a clip table: the tenders' body
bakes the base four, the gun carriage bakes only identical rest-pose
frames. Every write therefore resolves its VAT row PER GROUP through
`UnitMesh.clip_index` — the same guard that keeps a four-clip militia off
its normals rows keeps a rig-less cannon on its rest pose while its crew
walks. Nothing new: the manifest's per-model clip list has carried this
since M7.

## Rejected alternatives

- **A separate "leader" node beside the squad.** A second render path
  for one soldier — its own culling, LOD, selection and seam handling,
  all of which the MultiMesh path already has. The copy-choice bug class
  (D-20260818) was closed by having ONE way to draw things; a special
  node reopens it.
- **Per-instance mesh switching in the shader.** MultiMesh draws one
  mesh; there is no per-instance mesh, and faking one with a merged
  über-mesh and vertex masking would spend VAT columns this pipeline is
  already short of (16,384 limit, D-20260825).
- **Making the cannon its own one-man squad chained to a crew squad.**
  Two squads means two curves, two orders, two selection targets and a
  formation-keeping problem the simulation would have to solve; the
  owner asked for one unit.

## Consequences

- `tests/test_squad_models.gd` covers the routing: leader survives
  thinning, groups' written instances stay a prefix, empty fields keep
  the old single-group behaviour, and `model_for_slot` is pure/static so
  the test asks the same function the renderer uses.
- The first users are `units/*_general.tres` (thane + mixed retinue) and
  `units/cannon.tres` (gun + three tenders) — see
  D-20260826-the-dwarf-roster-wears-supplied-models.
- A group whose model is missing falls back to the primitive capsule for
  THAT group only; a fresh clone still runs, as D-064 requires.

## Revisit trigger

- Any request for a squad member with its own HEALTH, DEATH or ORDERS
  (e.g. "kill the crew, capture the gun") — that is per-soldier identity,
  which D-024 deliberately does not have, and it reopens this as a
  simulation decision rather than a render one.
- A profiler showing group count multiplying draw calls at scale — the
  mitigations are capping distinct models per squad (the mix is dealt,
  so the cap is the deal's), not abandoning the mechanism.
