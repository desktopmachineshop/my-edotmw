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

**And the squad-level answer to "units all pile on top of each other"
(D-20260818, #104, from playtest P06).** Separation on arrival (D-060)
enforced exactly one rule — no two settled squads share a CENTRE CELL —
while a 36-strong line formation is roughly eleven cells across. The
guarantee was an order of magnitude short of the geometry, so squads
ordered to the same area overlapped almost completely. Clearance is
`footprint_cells(a) + footprint_cells(b)` now, which for two lines is
very nearly shoulder to shoulder.

Three things worth carrying:

- **The number already existed and the simulation had never read it.**
  `Formation.footprint` is correct, cached, and was called only by
  `client.gd` — for the selection marker and the click test. That is the
  declared-and-under-read family (D-055, D-106) in a variant the usual
  grep cannot find: the member IS read, by the CLIENT, for DRAWING, and
  never by the simulation for the rule it would enforce. **The marker was
  drawn at the squad's true size and therefore visibly overlapped its
  neighbours — the picture was telling the truth and nobody read it as a
  bug report.**
- **The request was for per-soldier collision and that is still out of
  bounds.** D-006 names local avoidance, push-back and jostling as its
  revisit trigger, and the same visible outcome is reachable at squad
  level with no per-soldier state at all. The two look near-identical on
  screen; only one is legal here.
- **Marching squads stay exempt on purpose, and that is now an answered
  question rather than an undiscovered one.** Columns crossing still
  interpenetrate, because shoving a squad aside mid-journey is the
  per-tick avoidance D-006 rules out. Accepted for now; the decision
  entry carries the revisit trigger.
- **The footprint rule is for ALLIES. Enemies keep D-060's one cell**,
  and finding out why cost a red test in a file the change never touched.
  A melee `attack_range` is a little over one cell, so separating a squad
  from its opponent by its own footprint shoves every engagement out of
  reach and **no melee can ever land** — the squad arrives, is declared
  crowded, is sent eight cells back, and repeats. The only check that saw
  it was a *setup* assertion in `test_wall_top.gd` ("defender climbed"),
  because every test written for the spacing rule puts its squads under
  one owner and every combat test places its squads already adjacent.
  Then `test_buildings.gd` — D-067's own guard — reported the ALLIED half
  of the same thing in its own words: *"two squads dealt 1560 against one
  squad's 1461 — the second squad is not in the fight"*. Two squads
  battering one town centre must BOTH be within reach of it, so
  separating them from EACH OTHER deletes D-067's shipped rule. A squad
  with something in reach is exempt outright now (`Combat.is_engaged`),
  and the pass runs after combat so that it can be — the tick a besieger
  arrives is the tick separation would have sent it away.

  **A separation rule and an engagement rule are the same arithmetic
  pointed in opposite directions, and separation is the one that gives
  way.** When a change makes squads keep their distance, go and read the
  mechanics whose whole job is to close it — combat range, siege,
  gathering, wall access. Each is a position a squad NEEDS, and a spacing
  rule that does not know about one of them quietly deletes the feature.
