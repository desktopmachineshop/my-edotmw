# D-20260823-the-opening-is-a-crew-and-a-general

**Date:** 2026-08-23 · **Status:** Accepted · **Issue:** #190

**Supersedes D-031's opening** (one founding party, consumed by the town
hall it founds). D-031's *construction* rules — placement validation,
build reach, progress as a curve — are untouched and still cited by that
ID.

## Decision

1. **A player starts with ONE gatherer crew and ONE general, and no
   base.** The founding party is gone: `*_founders` is removed from the
   roster and every script, test and bot. Where to settle is still the
   first decision of the match; who makes it changed.
2. **Gatherers are per-civ, not universal** — the same rule D-047 already
   applies to fighting units. The neutral `units/gatherers.tres` is
   replaced by one `.tres` per civ (`legion_gatherers`,
   `northmen_gatherers`), each with its own stats, all sharing
   `archetype = &"gatherers"` so every existing archetype-keyed path
   (production, `built_by`, the wire) is unchanged.
3. **The town hall is founded by the crew, and founding it consumes the
   crew.** The rule is the **PAIR** — a builder the def admits, founding
   a def that spends its founder — not the building alone.
   `buildings/town_centre.tres` lists `gatherers` in `built_by`, and
   which buildings cost their founder is DATA:
   `BuildingDef.consumes_builder` (schema addition, default `false`, town
   centre `true`). `_finish_build` therefore names no unit and no
   building, and re-asks `can_build` before spending anyone. Every other
   building still costs the builder nothing — the M7 playtest fix
   ("`_finish_build` consumed ANY builder") keeps its scope by
   construction.
4. **The general is the escort, not a builder — and it is not a new
   entity.** The three questions the issue left open are each answered
   below, and the first one is answered by the codebase rather than by
   this entry.

   **a. Squad or single soldier? A SQUAD, and specifically an
   EIGHT-MAN one — not a one-man squad.** The hero already existed:
   D-20260819-a-general-holds-the-line shipped per-civ `*_general` defs
   (`squad_size = 8`), a 10-cell morale aura, a death shock worth twice a
   chain rout, and a one-alive-per-player production gate. This entry
   moves *when a player gets one* from mid-game production to tick zero;
   it invents nothing. A one-man squad would be the cheap way to satisfy
   D-006 if the entity had to be built, and it is not the cheapest way to
   satisfy it *here*: an eight-man squad satisfies D-006 identically
   (position is still a pure function of the squad curve and the slot
   index; there is still no per-soldier state anywhere), and shrinking
   the shipped def to one man would change combat, the aura, the death
   shock and every ladder number taken against it — a re-balance
   disguised as a schema convenience. **The general is also a squad for a
   reason a one-man version would lose: at `squad_size` 1, one unlucky
   casualty roll deletes the hero, and D-024 rolls casualties
   stochastically.** If a one-man hero is ever wanted it is its own
   decision, with its own measurements.

   **b. What happens when it dies? A MORALE event, never elimination.**
   The existing general-death chain shock (`combat.gd`, worth twice an
   ordinary chain rout, cascading through the same machinery) is the
   whole consequence. Defeat keeps D-033's one definition — no living
   squads AND no living buildings — which is what lets this be *asserted*
   rather than trusted: `MatchState` does not know what a general is, and
   `tests/test_opening.gd` kills one and checks the owner is still
   playing. Elimination-on-hero-death was rejected: it would make a
   single unlucky casualty roll end a match that D-056 wants to run one
   to two hours, and it would hand every opponent a two-minute win
   condition the moment armies meet.

   **c. Can it build? NOTHING.** It is listed in no `built_by`, so every
   building refuses it with no second, builder-side list to keep in step,
   and a test asks that of *every* shipped def rather than a sample. The
   alternative — letting the hero found the town hall as well — was
   rejected because it makes the crew optional in the opening and turns
   settling back into something any squad does wherever it stands.
5. **Consumption happens when the build COMMITS (order accepted in
   reach, or arrival for a walked order), not when construction
   completes.** The issue's phrasing says "completes a town hall";
   commit-time is kept deliberately, because consume-on-completion is a
   measured exploit, not a hypothetical — D-027's first playtest founded
   three town halls in about five seconds off one founding party while
   it stood waiting for the first to finish. One crew, one town.

## Rationale

- The founding party was a bespoke unit whose whole existence encoded one
  opening move. Handing that move to the economy unit every RTS player
  already understands removes a roster special case, and handing the
  opening's defence to the general gives the shipped general (produced,
  until now, only mid-game) a role from tick one.
- Per-civ gatherers close a hole in D-047: "the same type is not the same
  troops in two armies" was true of every unit except the one every
  player fields most of. Legion coloni are fewer, costlier, tougher, and
  carry organised loads; northmen thralls are more numerous, cheaper and
  quicker on their feet with smaller loads. Both sit inside the pinned
  economy bands (a crew works a tree out in 45–75 s; 1–6 food per head).
- A consequence worth naming: **a razed player can resettle.** Founders
  existed only at spawn, so a lost town centre was permanent; any
  gatherer crew can now found a new hall (150 wood, crew consumed). The
  elimination rule needs no change — a player with crews and no hall was
  already alive.

## Rejected alternatives

- **Consume-on-completion** — the D-027 playtest exploit above.
- **A hardcoded `def.id == &"town_centre"` check in `_finish_build`** —
  works, but puts a building name in the server where a def field can
  carry it (D-010), and the M7 "consumed ANY builder" defect argues for
  the rule being visible on the def it applies to.
- **Scoping consumption to the DEF alone, without re-asking
  `can_build`** — this was the first version here, and it was measured
  wrong rather than argued wrong: handed a general and a town centre,
  `_finish_build` spent the general. `built_by` refuses that at the order
  gate, so nothing shipped could reach it — which is *precisely* the
  argument that let the consume-any-builder bug live for four
  milestones. Every other rule in that function is re-checked on arrival
  for the same reason.
- **A one-man hero squad** — see decision 4a. Cheap if the entity had to
  be invented, and it did not; it would re-balance a shipped def and put
  the hero one casualty roll from death.
- **Keeping a neutral gatherers.tres as a fallback beside the per-civ
  ones** — `UnitRoster.for_civ_archetype` returns the first match in id
  order, and `gatherers` sorts before `legion_gatherers`, so the neutral
  def would shadow every per-civ one and the feature would be quietly
  absent (the D-055 family). Removed outright; a civ without a gatherer
  def is a roster bug a test now catches.

## Consequences

- `server._spawn_squads_for` spawns the crew at the seat's start and the
  general on the nearest free cell beside it (`Scenario.free_cell_near`,
  the same placement helper scenarios use).
- The AI opens correctly by construction: `_founder()` already asks
  `built_by`, so it founds with its crew and keeps its general. New:
  `_found_town` marks the crew as the busy builder the way
  `_raise_buildings` always has — the crew has carry capacity now, and
  the gather loop would otherwise cancel the founding order it was just
  given (the #123 defect, one seat over).
- The load-test bots pick their founder by `built_by` instead of
  `state.squads[0]`, and every bot fields a MILITARY squad (the general)
  from tick one — `military_peak`/`first_soldier_at` latch early and
  honestly, and the old "~90 s before anybody owns a soldier" floor in
  the test-load notes is stale (see `docs/status/load-testing.md`).
- Every timing tuned against the founder opening is stale on principle
  (the standing rule). The hall still takes 40 s and gatherer production
  still follows it, so the ECONOMY's timings barely move; what changed
  is that an army exists at t=0.
- `test-client`'s capture verdict still sees a casualty from founding —
  the crew consumption reports through the same casualty path founders
  did (D-045's known caveat is unchanged).
- The founders ART (`art/source/founders.blend`, `art/units/__init__.py`
  entry, `generated/` model+VAT) is deliberately left in place: `bpy` is
  blocked host-wide by the Windows Application Control policy
  (D-20260819-a-casualty-is-visible), so any edit under `art/` reds the
  staleness test with no way to rebuild. The model is orphaned — no def
  names it — and removing it is a one-commit cleanup for whoever next
  runs `just build-assets`.

## The load test, measured

`just test-load 4 120` on this branch, 2026-08-23, on the owner's laptop
with other agents' containers live, default map (168x194 = 32,592 cells),
docker runtime:

```
VERDICT ok — 4/4 bots connected, 0 desyncs over 476 state-hash checks,
casualties_applied=42 conceal_events=105 reveal_events=77 ghosts_peak=36
patrol_legs=26 scouts_peak=8 raid_orders=60 military_peak=4
buildings_known=8 building_desyncs=0 nodes_felled=27
gate-check(fog-squads): 19 of 40 squads gated even from the best-informed client
gate-check(fog-nodes):  4,860 of 5,565 nodes gated
gate-check(civs):       2 of 2 civilisations fielded squads
server: ticks=1392 dropped_ticks=0 us/squad=114.12 at 40 squads
        (fields 28.77, combat 37.51, vision 18.46, buildings 8.73,
         curves 10.20, economy 5.70, separation 3.72, production 2.73)
        worst_tick=104.4ms field_waits=127
server: MEMORY 57.8 MB static, 62.6 MB peak — 4 players, 40 squads
```

**Three things in that, and the first is the surprising one.**

- **The fog gates are reached at 120 s now, and were not before.**
  `docs/status/load-testing.md` records `4 300` as *failing*
  `conceal_events=0 reveal_events=0` on the current map and `4 480` as
  the first clean run; this is `105` and `77` at **120 s**. The cause is
  this change and is not luck: every bot fields a general from tick one,
  so `BotPatrol.assign` has a squad to scout with and `raid_pool` has one
  to raid with immediately, instead of waiting on a town hall, then
  production, then a second hauling crew. The manoeuvre D-20260817 built
  now starts at the beginning of the run rather than near the end of it.
- **`military_peak=4` is exactly one per bot — the opening generals, and
  nothing trained.** At 120 s no bot reached a barracks, which matches
  what `load-testing.md` already records (a barracks finishes at
  100–205 s). So this run also *demonstrates* the caveat written into
  `bot_client._raid_orders`: `raid_orders=60` was satisfied entirely by
  the opening army. The gate still says "an army was sent somewhere" and
  no longer implies "production delivered".
- **`worst_tick=104.4 ms` is marginally over D-020's 100 ms budget with
  `dropped_ticks=0`.** Recorded rather than glossed. It is not obviously
  this change — `us/squad=114.12 at 40 squads` sits against the 167.7 at
  48 squads `docs/status/m10-plan.md` records for the same map, and this
  host was running other agents' containers throughout, which is exactly
  the contention M6's discarded worst-tick figures were about. Worth a
  clean re-measurement on an idle machine before anyone reads it as a
  regression.

**This is ONE run**, and this repo's own rule is that a single green run
is not a measurement — `load-testing.md` says so in the voice of having
been burned by it. Read the direction (the fog gates are reached far
earlier) as the result; do not quote `120` as the new floor until
somebody has run it more than once.

## Verification, and what it cost to get honest

`just test-unit` on this branch matches `main` exactly: **14 failures on
both**, the same set, none of them this change. Thirteen are the WSL
`execvpe(/bin/bash)` shell-outs in `test_gate_checks` / `test_host_budget`
/ `test_recipe_args`, which fail under the NATIVE runtime on this host and
pass in docker; the fourteenth is
`test_two_squads_of_any_line_troop_but_light_skirmishers_can_take_a_tower`
for `northmen_spearmen`, already recorded as open in
`docs/status/formation.md` since the wheeling change. The branch adds 9
tests and takes passing from 1,132 to 1,141.

**Both new rules were observed to fail before being trusted** (the
standing rule):

- `consumes_builder = false` on the town centre reds
  `test_founding_a_town_hall_spends_the_crew` (crew alive, no casualty
  event) and `test_exactly_one_shipped_building_costs_its_builder`.
- `consumes_builder = true` on the barracks reds
  `test_exactly_one_shipped_building_costs_its_builder` and
  `test_a_general_may_build_nothing_and_is_never_spent`.

**And the scoped test failed to fail, first time.** It skipped any def
with `consumes_builder` set, so widening the flag to the barracks removed
the barracks from its loop instead of reding it — green, on exactly the
regression it exists to catch. **A check that filters on the field it is
checking cannot see that field go wrong.** It names the town centre as
the single exception now and reds correctly. That is this project's
"observe the check fail" rule earning its keep on the same day it was
followed.

**Four unit-test FIXTURES broke, none of them on the rule under test**,
and the shape is worth carrying. `UnitRoster.first()` and "the first
roster def matching a predicate" both used to land on `founders`, purely
because `f` sorts before `g` and `l`. With that file gone they landed on
an ARCHER (which may build nothing — so an AI fixture asserting "the AI
did something" went red) and on a GENERAL (whose morale aura is not what
a frontage experiment measures, and whose eight men lose a fight two
militia squads would win). A fifth went RISKY rather than red:
`test_an_economy_only_ai_never_sends_an_attack_move` inspected zero
packets and passed vacuously, which GUT flagged and a human might not
have. **A fixture that takes "whatever sorts first" is pinned to a roster
ORDERING, not to a unit** — all five now name the archetype they mean.

## Revisit trigger

- **The fantasy-civs pivot landing.** This entry deliberately does NOT
  block on it: the per-civ gatherers are authored against the CURRENTLY
  shipped civs (legion, northmen) so the change lands standalone and
  green. **The gatherer set GROWS with the pivot** — one `.tres` per civ
  is now a standing requirement, so every civ the pivot adds needs one
  or it cannot open at all, and `tests/test_opening.gd`'s
  `test_every_civ_can_actually_open` is what says so out loud rather
  than leaving a seat to spawn nothing. Their identities should be
  re-authored against the pivot's frame at the same time; nothing in
  code names either def, so that is a data change.
- Any second building wanting `consumes_builder` — at that point decide
  whether partial-refund or confirmation UI is owed, because "this order
  spends a squad" stops being a one-off the tutorial can carry.
- M9's upkeep economy (D-068): a starting general with upkeep changes
  the opening bank arithmetic this entry leaves untouched.
