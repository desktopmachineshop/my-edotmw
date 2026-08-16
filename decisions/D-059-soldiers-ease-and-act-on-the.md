### D-059 · 2026-08-04 · Accepted — soldiers ease and act, on the render path only
**Decision:** The client eases each soldier toward his authoritative slot
rather than snapping (`soldier_motion.gd`), and displaces soldiers toward
what their squad is doing — a resource being worked, an enemy being
fought (`CosmeticOffset.decorate_activity`). Both are client-only,
one-way, and never read back.

**Rationale:** two complaints with one cause. A soldier's position is a
pure function of the squad curve and formation (D-006 clause 1), so when
a squad turns every slot rotates in the same instant and the block snaps
round. And a squad standing perfectly still while a resource drains or an
enemy dies looks broken.

**Why this is allowed:** clause 2 permits client-side visual offsets
never read back by simulation, and `cosmetic_offset.gd`'s own header
already named this case — "the authoritative slot snaps, and the render
layer is free to ease toward it."

**Where the line sits, precisely.** `SoldierMotion` holds per-soldier
state, which clause 1 forbids in the SIMULATION and clause 2 permits on
the render path. Three properties keep it legitimate, and a test guards
each: the authoritative transform is unmodified; it is client-only, so
two clients may disagree and nothing notices; nothing reads back out.

It lives in its own file rather than in `CosmeticOffset` because that
class is deliberately pure and static — it has nowhere to put state, and
that is what makes its boundary structural rather than a comment.

**No new protocol.** Activity is inferred from what the client already
has: `shape == "ring"` means a crew is working (D-058 replicates shape),
and enemy squads in vision mean fighting.

**Rejected alternatives:**
- *Easing in the simulation* (rejected — clause 1, and it would put
  soldier positions out of step between client and server).
- *Replicating an activity flag* (rejected — more wire traffic for a
  picture the client can already derive).

**Consequences:** the client now carries per-soldier render state, which
is new. A seam-sized jump snaps rather than easing, or a wrapped squad
would send soldiers streaming across the world (D-035).

**Revisit trigger:** if easing is ever consulted by selection, combat or
the composition hash, the state has stopped being cosmetic and D-006's
trigger has fired.

---
