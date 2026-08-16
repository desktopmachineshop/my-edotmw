### D-098 · 2026-08-11 (renumbered 2026-08-16) · Accepted — tests start mid-game, from a scenario
**Decision:** A **scenario** is a mid-game world described as data
(`/scenarios/*.tres`), applied through the game's own calls, and usable
two ways: in-process by a GUT test, and by the real server via
`--scenario=<id>`.

1. **`ScenarioDef`** holds a per-player loadout — buildings, squads,
   wallet — plus `separation`, how far apart to place neighbouring
   players. `ScenarioBuilding` and `ScenarioSquad` are its entries.
2. **Placement is RELATIVE.** Entries carry an offset from the player's
   home cell, never an absolute cell, so one loadout drops onto any map.
   `placement_slack` bounds how far the applier may nudge an offset that
   lands in water or on another building.
3. **Squads name an ARCHETYPE, never a unit and never a civ**, resolved
   per player through `UnitRoster.for_civ_archetype` — so one scenario
   plays for every civ.
4. **`Scenario` is all-static**, like `Formation`: a scenario is an
   opening position, not a participant, and there is nowhere for it to
   keep state.
5. **One applier for both worlds.** `Scenario.apply_player` is called by
   `ScenarioWorld.build` (tests) and by `server.gd:_spawn_squads_for`
   (live). A scenario cannot mean one thing in a unit test and another on
   a server.
6. **Nothing is dropped in silence.** Unplaceable entries land in
   `Placement.skipped`, which the server prints as `SCENARIO_SKIPPED` and
   `test-scenario` fails on.
7. **A scenario run is identifiable in its log** — `server: SCENARIO
   id=… seats=… separation=…` — and `test-scenario` greps for exactly
   that.
8. **`just test-load 4 120` keeps playing the real opening and stays the
   gate.** A scenario is for iterating.

**Rationale:** The opening is slow on purpose and the cost compounds. A
player starts with one founding party and no base, a town hall takes 40 s
and consumes the founders (D-031), production follows, and spawns are
scattered far apart (D-039). So the cheapest honest integration test of
anything downstream cost ~150 s of waiting before the thing under test
existed. Measured, before and after, on the same machine:

| loop | before | after |
|---|---|---|
| full unit suite | 39 s | 29 s |
| one unit test file | 39 s | **11 s** |
| integration with combat, fog and buildings | ~150 s | **31 s** (at DURATION=15; ~50 s at the default 30) |

The unit suite was already spawning directly into `SquadSim`; what it
lacked was a shared fixture (32 files, each re-inventing its own
scaffolding — `test_buildings.gd` alone had 48 `.new()` calls) and any
way to run less than all 491 tests.

**Rejected alternatives:**
- **A parallel lightweight simulation for tests.** The fast path would
  then be a different program from the shipped one. This is the exact
  shape of M4's `profile` sweep reporting 29 ms for code that spent
  866 ms live, because the sweep resolved its UnitDefs once at setup and
  the server did not. Where a harness and a live run disagree, believe
  the live run — so do not build a harness that CAN disagree.
- **Scenarios as GDScript builders only.** More expressive, but "unit
  stats, civ configs, terrain-gen parameters: plain text, not hardcoded"
  is a standing rule, and a scenario is exactly that kind of data. The
  builder path remains available by constructing a `ScenarioDef` inline.
- **Letting scenarios replace the slow run.** Rejected with the user:
  nothing would then exercise founding, production timing or the opening
  end to end, which is the class of gap this log keeps recording.
- **Sizing scenario homes on `players_expected`.** Tried, and wrong: it
  defaults to 1 and `just up` does not raise it, so four bots all indexed
  into one home and four armies spawned in a pile. It looked healthy —
  bots connected, casualties were HIGHER — because they started on top of
  each other. Homes are sized on the map's own seat count instead, making
  the number of joiners irrelevant rather than load-bearing.

**Consequences:**
- `just test-unit FILTER [TEST]` maps to GUT's own `-gselect` /
  `-gunit_test_name`; `_import` is skipped when no source is newer than a
  stamp taken BEFORE the previous import, printed when skipped and
  overridable with `EDOTMW_FORCE_IMPORT=1`. That cache is the one piece
  here that could produce a confidently wrong answer, which is why it is
  conservative, loud, and was tested by editing a file and confirming the
  edit is seen.
- A scenario cannot catch a bug in founding, production or spawn
  placement — it skips them. That is stated in the file header, in
  `just scenarios`, and in CLAUDE.md, because a fixture whose blind spot
  is undocumented eventually gets trusted for what it cannot see.
- Three scenarios ship: `clash` (armies in reach, no buildings),
  `siege` (a defended base plus an attacker, for D-067's razing rule),
  `developed` (a working base and a full wallet — the default start for
  feature work).

**Revisit trigger:** a scenario is needed that varies DURING a match
rather than at t=0 (scripted events, timed reinforcements) — clause 4's
all-static applier is what to re-examine first; or `test-scenario`
becomes the thing people quote instead of `test-load`, which is clause 8
failing in practice rather than in principle.

**Amendment, 2026-08-16 (merge):** this entry was written as D-076 and is
renumbered to **D-098** here. It was authored in parallel with the work
that became main's D-075 (lobby return) and D-076 (walls and gates), on a
branch that had forked before either existed, so both numbers were spent
by the time it merged. **Two agents working the same log will collide on
the next free number, and neither can see the other** — so a number is
only really claimed once it is on main, and reconciling that is a merge
step, not a mistake. Nothing but the heading changed.

**It then happened again, in the hour between the two merges.** This
entry was renumbered to D-096, and by the time the branch was pushed
main had spent D-096 *and* D-097 — so it moved again, to D-098. Which is
the rule stated above being demonstrated rather than merely written down:
**picking "the next free number" from your own checkout is a guess, and
it goes stale while you work.** The right moment to fix a number is the
merge, against a freshly fetched main, and not before.

**Main currently carries three duplicate pairs** — two D-087s (M8 scope
vs. forests), two D-096s (continuous ground vs. continuous wall
placement) and two D-097s (cliffs vs. contestable build sites) — each
pair authored on a different branch and merged without either side
seeing the other. They are recorded here rather than renumbered in
passing: this log's whole workflow rests on an ID naming exactly one
decision, and every cross-reference elsewhere in the repo resolves
through that ID. Reconciling them is its own task, and a deliberate one.

The same fork produced a **second, independent implementation of instance
isolation** — checkout-derived names, a `$HOME` port registry with atomic
claims, `dev` pinned to 4433 and protected from an implicit `just down`,
and a `just instances` listing. D-095 landed first and is the one in
force; that implementation was dropped whole at merge rather than
half-merged, because two derivations of one identity is precisely the
failure D-095 exists to prevent. **What it had and D-095 does not is
recorded here so it can be reconsidered on its own merits, not
rediscovered a third time:** a registry makes a port collision impossible
rather than merely unlikely (D-095 hashes into 10,000 ports and does not
check), and refusing an implicit teardown of the human's instance is a
guard D-095 has no equivalent of.
