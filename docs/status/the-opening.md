**A player opens with ONE gatherer crew and ONE general, and no base**
(D-20260823-the-opening-is-a-crew-and-a-general, issue #190,
2026-08-23). This **supersedes D-031's founding party**; D-031's
construction rules — placement validation, build reach, progress as a
curve — are untouched and still cited by that ID.

What changed, in one table:

| | before | now |
|---|---|---|
| opening squads | one `founders` party | one gatherer crew + one general |
| who may found a town hall | `founders` | `gatherers` (`built_by`) |
| who is consumed by founding | `founders`, by an archetype check in `server.gd` | whoever founds a def with `consumes_builder` — the town centre and nothing else |
| gatherers | one `neutral` def for every civ | one `.tres` per civ (D-047's rule, finally applied to the unit every player fields most of) |
| `units/founders.tres` | shipped | gone, with every reference |

Six things to know before touching any of it:

- **Consumption is the PAIR, and half of it is data.** `_finish_build`
  spends a builder only when the def says founding costs its founder
  (`BuildingDef.consumes_builder`, default `false`, town centre `true`)
  AND `built_by` admits that builder — `can_build` is re-asked there.
  That keeps the M7 playtest fix ("`_finish_build` consumed ANY builder
  unconditionally, and every gatherer that finished a wall silently
  vanished") scoped by construction rather than by an archetype
  comparison somebody has to remember to narrow.
  `tests/test_opening.gd` asserts the count of shipped defs that spend
  their builder is exactly one; a second is a design decision, not a
  `.tres` edit.
  **The re-check is not belt-and-braces, and it was measured rather than
  argued.** The first version gated on the def alone, and handed a
  general and a town centre it spent the general — `built_by` refuses
  that at the ORDER gate, so nothing shipped could reach it, which is
  precisely the argument that let the consume-any-builder bug live for
  four milestones. Every other rule in that function (ground, enemy
  claims, footprints, cost) is re-checked on arrival for the same
  reason: a builder walks, and the world moves while it does.
- **The crew builds the hall, then joins it — spend-at-COMPLETION since
  2026-08-30** (`D-20260830-the-crew-builds-the-hall-then-joins-it`,
  owner's call, superseding this entry's spend-at-commit clause). The
  crew stands its build through, BOUND — every order to it is refused at
  `_validated_squad`, the one gate — and is consumed the tick the hall
  completes; a razed site frees it. The exploit spend-at-commit existed
  for (D-027's three halls in five seconds off one free-standing party)
  is closed by the LOCK instead: a crew that takes no orders cannot
  found a second hall. One crew, one town, still. Net economics are
  unchanged — dead-during-construction and locked-during-construction
  gather equally little — so timings tuned against the opening stay
  put.
- **The general builds nothing and is never spent**, and its death is a
  MORALE event (`combat.gd`'s chain shock,
  D-20260819-a-general-holds-the-line), never an elimination. Defeat
  keeps its one definition — no living squads AND no living buildings
  (D-033) — which is what lets that be asserted rather than trusted.
- **A razed player can resettle now.** Founders existed only at spawn, so
  a lost town centre was permanent; any gatherer crew can found a new
  hall for 150 wood and itself. The elimination rule needed no change — a
  player with crews and no hall was already alive.
- **A NEUTRAL def shadows every per-civ one.**
  `UnitRoster.for_civ_archetype` returns the first match in id order and
  `gatherers` sorts before `legion_gatherers`, so leaving a neutral
  `gatherers.tres` beside the per-civ files would have made the whole
  feature quietly absent (the D-055 family). It is removed outright, and
  a test asserts each civ's gatherer names its own civ.
- **Timings tuned against the founder opening are stale**, per the
  standing rule — but less than usual, because the ECONOMY's shape did
  not move. What moved is that **an army exists at t=0**: `test-load`'s
  old "~90 s before anybody owns a soldier" floor is gone (see
  `docs/status/load-testing.md`), a bot's `military_peak` latches
  immediately, and the AI must not spend its training cooldowns asking
  for a second general — `ai_player._military_archetype` skips
  `is_general` by FIELD for exactly that reason, the same discipline
  `bot_build_plan.gd` already used.

**`test-load`'s `raid_orders` gate now says less than it used to, and
that is written down rather than left to be discovered.** #123 made it a
GATE because `raid_pool` was empty on every tick of every match; it still
says "an army was sent somewhere", and it no longer implies "a barracks
finished and trained something", because the opening general is a
fighting squad from tick one. **`military_peak = 1` per bot is the
opening; production is `military_peak` above that**, with
`first_soldier_at` beside it. Deliberately not turned into a new gate:
the shipped map already leaves two of four bots short of a barracks at
420 s, so gating on it would fail honest runs, and finding the duration
that does not is a measurement this change did not take.

**`test-client`'s casualty gate is UNCHANGED by this, and still broken
the way D-045 recorded.** It gates on `casualties_applied > 0`, and
consuming the opening crew reports through the casualty path exactly as
consuming the founding party did — so it is still satisfied by founding a
town hall with no fighting anywhere. Neither newly broken nor fixed.
**The fix is cheaper than it was**, though, and worth naming for whoever
takes it: `D-20260819-a-casualty-is-visible` put a `fell` byte on the
wire that separates men who died by violence from men spent founding, and
`ClientState` already decodes it — it is only routed into
`_casualty_sites` (and only when `record_corpses` is set) rather than
counted. A `casualties_fell` counter beside `casualties_applied` would
make that gate mean what it says. **It was deliberately not done here:
`test-client` is docker-only, the host gate was saturated, and tightening
a check nobody can watch fail is the thing this project forbids.**

**Two callers had to stop picking `state.squads[0]` as their builder.**
The load-test bot and `test-client`'s capture client both did, which was
correct while the opening was one squad and is a coin toss now — half the
time it names the general, whose build order is refused forever. Both ask
`BuildingDef.built_by` instead. That is the generic lesson worth carrying:
**an index into "my squads" is a guess about the roster, and the roster
moved.**

**Four test fixtures broke on this, and none of them was about the rule
under test.** `UnitRoster.first()` and "the first roster def matching a
predicate" both used to land on `founders`, purely because `f` sorts
before `g` and `l`; with that file gone they land on an ARCHER (which may
build nothing) and on a GENERAL (whose morale aura is not what a frontage
experiment measures). A fifth went RISKY rather than red — an
"AI never sends X" test that inspected zero packets. **A fixture that
takes "whatever sorts first" is pinned to a roster ORDERING, not to a
unit.** All five name the archetype they mean now, and it is worth
grepping for the pattern before the next roster change.

**Open, and deliberately so: the fantasy-civs pivot.** The two per-civ
gatherers here (Coloni, Thralls) are authored against the historical
roster frame because that is what ships. Issue #190 names the pivot
explicitly — re-author them against whatever frame lands, and the
mechanics above are unaffected, since nothing in code names either def.

**Also left alone on purpose: the founders ART.**
`art/source/founders.blend`, its `art/units/__init__.py` entry and the
built `generated/` model and VAT are orphaned — no def names them — and
they stay because `bpy` is blocked host-wide by the Windows Application
Control policy (D-20260819-a-casualty-is-visible), so any edit under
`art/` reds the staleness test with no way to rebuild. It is a
one-commit cleanup for whoever next runs `just build-assets`.
