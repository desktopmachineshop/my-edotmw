# D-20260818 · 2026-08-18 · Accepted — a load-test bot builds a barracks and trains soldiers, and the verdict fails if it never sends one anywhere

**Decision:** `test-load`'s bots raise a building that TRAINS something,
train a military archetype from it, and the verdict gains a hard gate —
`raid_orders > 0` — that fails a run in which no army was ever ordered
anywhere. What to build and what to ask a building for lives in
`bot_build_plan.gd`, all-static and pure, `bot_patrol.gd`'s sibling.

Four clauses:

1. **A harness that never exercises the thing it claims to test must say
   so.** `raid_orders` is a gate, not a metric — the same principle as the
   casualty, conceal and reveal conditions D-026 criterion 9 put there,
   and for the same reason: a run in which nobody was sent anywhere proves
   nothing about an engagement between armies, however clean the rest of
   the verdict looks.
2. **Nothing names a building or a unit.** Both are data ids. The bot asks
   `BuildingSim.all_defs()` for something its crews can raise that
   `produces` anything, and asks that building for the first archetype it
   makes which this civ fields. A roster that grows a stable widens what a
   bot builds with no code change, and `tests/test_bot_build_plan.gd`
   fails if any building id appears in the module's source.
3. **The economy needs a brake.** One `squad_cap` covers workers and
   soldiers alike (D-033), so a bot that trains gatherers forever fills
   the cap with them and fields nothing. `MAX_HAULING_CREWS` is that
   brake, and it skips the ARCHETYPE rather than the building, so a
   barracks is unaffected by a full worker roster.
4. **Affordability is checked before ordering, not left to the server.**
   The cost is charged on ARRIVAL (`server.gd::_finish_build`), so an
   unaffordable build order is a crew walking ten cells to be turned away
   — and the bot cannot tell that from a crew still walking.

## Rationale

Filed as #123 while fixing #69/#84
(D-20260817-load-test-bots-must-manoeuvre), and left out of that change
deliberately because it could not be validated by the run that change had
to pass.

`bot_client.gd::_issue_order` builds a `raid_pool` — the squads free to be
sent anywhere — by excluding the founding party and every squad the haul
loop has claimed. **That pool was empty on every tick of every match**, so
the function returned at `if raid_pool.is_empty(): return` before issuing
a single raid order, for the whole run, for every run there has ever been.
The chain is mundane and entirely in shipped data:

1. a bot only ever built a **town centre** — the opening move was its only
   `encode_build`;
2. `buildings/town_centre.tres` has `produces = [&"gatherers"]` and
   nothing else;
3. `_put_gatherers_to_work` claims every squad with `carry_capacity > 0`,
   which is every squad a bot could own.

So everything below that branch — the middle-of-map raid, the home leg,
`ORDERS_PER_RAID_PHASE`, the jitter — was written, correct, called, and
unreachable. **This is D-061's harder variant of the declared-and-unread
family:** a grep for uncalled public members finds none of it, because the
pool is built, the branch is taken, and the pool is empty. Nothing failed,
because a load test whose bots never fight still connects, replicates,
hashes and reports a clean verdict.

What that cost, concretely: `test-load` exercised the economy, buildings,
fog, replication and incidental combat, and did NOT exercise military
production, an engagement between two real armies,
`UnitDef.damage_vs_buildings`, D-067's "one squad cannot raze a defended
building, two can", or **most of `/units`** — a run only ever fielded
`founders` and `gatherers`, both `civ = &"neutral"`.

That last one deserves saying plainly, because it looked covered and was
not: `test-load`'s CIVS_FIELDED check passes on a run where no
civ-specific unit exists at all, because `server.gd::_civs_fielded()`
counts by the PLAYER's civ, not the unit's. Two civs were reported
"fielded" every run while the roster's civ half went untouched.

### Why the gate is `raid_orders`, not "soldiers exist"

Because the issue is that the raid path never RAN, and a squad standing in
a barracks proves nothing about that. `military_squads` is reported beside
it for exactly the reason `patrol_legs` is reported beside
`reveal_events`: "there was nothing to send" and "there was something and
it was never sent" are different faults with the same symptom, and telling
them apart is what the last three sessions on this harness were spent on.

### Why not lengthen the raid instead of building an army

Considered and rejected: reserving hauling crews for the raid rotation
would make the pool non-empty without any of the coverage above. Crews
have `damage = 1.0` against a militia's 9.5, so "two armies meeting" would
be a caricature — the exact shape D-066 warns about, where a test proves
the mechanism and says nothing about whether the shipped numbers do
anything.

## Numbers

Timings on the current default map, measured on this branch:

Four bots on the shipped 168x194 map, native runtime (Docker Desktop was
down on the host), same worktree, same session. `test-load` is Docker-only,
so these were taken with the same server and the same bots driven by hand —
`run-server` and `run-bots`, both of which have native paths.

| build | duration | military_peak | raid_orders | casualties | conceal / reveal | verdict |
|---|---|---|---|---|---|---|
| pre-#123 behaviour | 300 s | **0** | **0** | 66 | 205 / 166 | **failed** |
| this change | 300 s | 5 | 66 | 154 | 125 / 105 | ok |
| this change | 420 s | 5 | 172 | 320 | 290 / 256 | ok |

0 desyncs, 0 building desyncs and 0 dropped ticks in all three.

**Read the perturbation row first, because it is the one that matters.**
Every other counter in it is HIGHER than the passing run — more conceals,
more reveals, more nodes felled, more buildings known — and it still fails.
That is the whole of what #123 is about: a harness that looks thoroughly
exercised while never once putting an army on the map. One bot in that run
even raised a second building at 259 s and trained nothing from it, which
is the old behaviour exactly.

Timings that set the duration, from the two passing runs:

| | earliest | latest |
|---|---|---|
| second building finished | 100 s | 205 s |
| first soldier fielded | 135 s | 226 s |

So **300 s is the floor and 420 s is the recommendation**: the gate passes
at 300 s, but a bot whose barracks lands late has barely any army time
left, and `raid_orders` went 66 -> 172 for the extra two minutes.

**Two of four bots do not reach a barracks even at 420 s, and that is not
this change.** A town hall costs 150 wood out of a 180-220 opening bank and
hauling round trips are long on the doubled map. One bot in particular
banks exactly one 60-wood delivery and then stops — wallet `[172, 90, 0, 0]`
at the end of every run measured, before and after this change alike. Its
crews are alive and assigned; something in the haul cycle stalls. Recorded
here rather than chased, because it predates this work and the gate does
not depend on it.

The per-squad and worst-tick figures from these runs are NOT quoted. The
host was running nine other agents' Godot processes throughout and the
server reports 364-511 us/squad against the ~60 a quiet host gives — that
is contention, and nothing in this change is per-tick on the server.

### Four defects found on the way, none by the instrument that found the last

Each was invisible to every counter that existed before it, and each was
caught by a field added for the previous one. They are listed because the
pattern is the point: **a bot has four separate places that tell a squad
what to do, and every one of them is a chance for two of them to disagree.**

1. **The builder was re-tasked by the haul loop.** The build order erased
   the crew's gather assignment — a crew told to build has stopped hauling
   (D-034) — which left it looking IDLE, so the next pass sent it to a tree
   and cancelled the build three seconds after issuing it. Over a 600 s run
   three of four bots ordered a barracks repeatedly and one ever finished
   one, at 586 s, with wood peaking at 850. It was never affordability.
   Found by the per-bot `build=` field.
2. **The builder was re-tasked by the RAID pool.** The fix for (1) held the
   builder out of the haul loop and the builder picker — three of the four
   sites — and missed `raid_pool`, where the crew now read as idle instead.
   Found by `raid_orders=149` sitting beside `military_squads=0` in one
   line.
3. **The gate could be met by the wrong squad.** (2) made the run pass:
   `raid_orders` counted orders to a hauling crew nobody meant to raid
   with. A gate met by an accident rather than the thing it names is the
   vacuous pass D-022's audit block exists for, so `raid_orders` counts
   only orders to a squad that fights.
4. **A load-test bot never learns its own civ.** `server.gd` broadcasts the
   lobby only while `phase == LOBBY`, and `test-load` starts a match
   without one — so `ClientState.civ_of` answers `""` for every bot in
   every run there has ever been. Resolving production strictly per civ
   therefore matched `gatherers` (`civ = &"neutral"`, so they match
   anybody) and nothing else: barracks standing at 137 s and 193 s,
   `military_peak=0`, town centre making crews forever. Found by
   `second_building_at` and `first_soldier_at` disagreeing.

The general fact worth carrying: **anything a client learns only from the
lobby is absent in a bot.** The fix was not to plumb the civ through but to
notice that D-047 already makes it unnecessary — the wire carries an
archetype and the SERVER resolves it, so the local civ lookup was only ever
answering "is this a hauler", which every civ answers identically.

## Rejected alternatives

- **Have the bots run `AIPlayer`.** Zero duplication, and wrong for the
  same reason it was wrong for the patrol: `bot_client.gd`'s scripted
  scenario is deliberate (its header has said so since M2), and the AI's
  first attack is ~171 s (D-107), so the fog and combat gates would come
  to depend on AI strength rather than on the harness.
- **Name the barracks.** Shorter, and it stops finding the building the
  moment the roster grows a second one. `ai_player.gd` discovers it from
  the defs and has done since M6.
- **Let the server refuse an unaffordable build.** It does, on arrival —
  which is a crew that walked there for nothing and a bot that cannot tell
  why.

## Consequences

- `test-load`'s documented duration is bounded below by military
  production, not by the town hall: a barracks is 150 wood and 25 s on top
  of a 40 s hall, and the crews to pay for it arrive later still.
  `docs/status/load-testing.md` carries the measured number.
- A run now fails if the bots never raid. That is a NEW way for the load
  test to go red, and it is meant to be: it has been silently true for
  every run in the project's history.
- The scouting detachment still comes out of the ECONOMY rather than the
  army (D-20260817-load-test-bots-must-manoeuvre's revisit trigger). Left
  that way on purpose: crews exist long before soldiers do, so scouting
  from them starts the fog manoeuvre far earlier in a run, and military
  squads land in `raid_pool` by construction because
  `BotPatrol.assign` takes the EARLIEST squads as scouts.

## Revisit trigger

- `raid_orders` going to zero on an unmodified tree — the bots have
  stopped fielding an army again, and the first thing to check is whether
  the run reached military production at all (`military_squads` is
  reported beside it).
- A second building in the roster that `produces` something and is
  `built_by` gatherers. `wanted_building` returns the first it finds in
  `BuildingSim.all_defs()` order, which is fine for one and arbitrary for
  two.
- The bots gaining a reason to spend stone or gold. They gather WOOD only
  today, so a building costing anything else is unaffordable forever and
  `can_afford` would silently never pass.
