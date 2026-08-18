D-006 (derived soldier positions) is Accepted and implemented in
`formation.gd`. Its three binding clauses are load-bearing for
everything built so far: soldier position is a **pure function** of
(squad curve, formation shape, slot index, terrain sample) with no
per-soldier integration state; client-side cosmetic offsets are
**one-way** and never read back by simulation; casualty slot
reassignment is **deterministic** (the formation restamps — soldiers
don't walk into a vacated slot). Emergent per-soldier movement of any
kind — local avoidance, collision push-back, jostling — is out of bounds
and is the explicit revisit trigger.

`Formation` is an all-static class on purpose: there is nowhere to put
per-soldier state, so the purity clause is enforced rather than merely
documented. Cosmetic motion lives in its own file (`cosmetic_offset.gd`)
for the same reason — the one-way boundary is structural. Combat's
resolution of Q7 (D-024) satisfies this trivially rather than delicately:
`alive` is the only formation input a death changes, so casualty
reassignment needs no per-soldier identity anywhere, and `Formation`
gained no instance state to support combat.

**Passability is the terrain sample's second half, since 2026-08-18**
(`D-20260818-a-soldier-stands-where-his-squad-could-walk`, #97). A slot
that lands on ground its squad could not path onto is pulled back along
its own offset ray until it lands on ground the squad could; failing
that it stands on the squad's own cell, which is passable by
construction. Reported from a playtest as soldiers standing on the
mountain shelf behind a beach and popping on and off it — and the pop
was 2.0 world units, not a nudge, because D-097 draws the impassable
HIGH class on a lifted tier and `surface_field` stores that RENDERED
height.

Three things worth carrying out of it:

- **An input is not state, and that is the whole D-006 argument.** The
  clamp is a fifth argument to a function that is still static and still
  pure: the same call gives the same answer forever, and a man back on
  open ground gets his full offset again the next frame with no memory of
  having been pushed. Local avoidance, push-back and jostling are still
  out of bounds, and they are out of bounds for a reason this is not —
  they carry per-soldier integration. The test that separates the two
  derives with rock, then without, and asserts the second answer equals
  the pre-clamp one exactly.
- **The array has to be the TERRAIN one, not the simulation's.**
  `SquadSim._passable` has living buildings stamped out of it, and a
  client under fog cannot reproduce that set — clamping against it would
  put the two sides in different places with nothing able to notice, the
  M1 desync from D-022's audit block rebuilt from parts. Terrain
  passability comes from the replicated `MapSettings` (D-049), so both
  sides derive it from identical numbers and a test asserts the client's
  array is byte-identical to the server's.
- **It costs tens of percent of the per-soldier derivation path, and the
  absolutes taken for it are unusable.** Two interleaved best-of-9 A/Bs on
  the shipped map put the clamp at +47% and +81%, on a host running five
  other worktrees' container suites — where a bare `world_to_cell` priced
  at thirty times what that arithmetic can cost. A clean `bench-render`
  A/B on an idle machine is still owed. The lever if M10 wants it back is
  a per-SQUAD footprint test off `TorusSpace.disk_offsets`, not a faster
  per-soldier one; the decision entry says why it is not in this change.
- **The premise that made D-097's cliff lift free was written down and
  false.** It said "nothing stands on impassable ground for the offset to
  disagree with". This is the D-058/D-065 family for the third time: a
  decision entry asserting an invariant is not evidence the invariant
  holds. D-097's own file carries the amendment.
