**Use `just test-load 4 420`** on the current default map. 300 s is the
floor — it clears every gate, but a bot whose barracks lands late has
almost no army time left (D-20260818-load-test-bots-must-field-an-army).
**The gate is `just test-load`. The LOOP is `just test-scenario`, and as
of D-20260818-the-fast-loop-carries-the-gate it makes the same log
comparisons the gate does** — fog gating of squads (D-026 criterion 6's
load half), fog gating of resource positions (D-061) and both civs having
fielded something (D-046 criterion 10). They lived inline in `test-load`
and were copied nowhere, so for three milestones the recipe anybody
actually ran between gate runs asserted none of them. Iterating on the
fast one no longer means asserting less; `gate-check.sh` is the one
definition and `tests/test_gate_checks.gd` fails if the two drift.

**What each costs.** Measured 2026-08-18 on `main` at 1e6ba9c, in an
isolated worktree (D-095), on a host running eleven other agents' docker
containers:

| recipe | wall clock | what it covers |
|---|---|---|
| `just test-scenario siege 4 15` | **25 s** warm, **2 min 55 s** cold | everything downstream of the opening |
| `just test-scenario developed 4 60` | 3 min 57 s | as above at REAL spawn separation — see below |
| `just test-load 4 300` | **5 min 11 s** | the loop's coverage PLUS founding, production and real spawn distance |

**Read those as wall clock, not as verdicts.** The gate run FAILED on
`main` at `conceal_events=0 reveal_events=0`, and so did the cold loop
run. That is neither the duration nor this change: the bots had stopped
manoeuvring at all (#69/#84, fixed by
`D-20260817-load-test-bots-must-manoeuvre` on its own branch).

**Owed: a second CLEAN loop run.** One warm `siege 4 15` came back clean
in 25 s and that is one run, which this file's own rule says is not a
measurement. The host's docker daemon went down before a repeat could be
taken. Take it before quoting 25 s as settled.

Three caveats on those numbers, all of which cost time to learn:

- **A wall clock here is a statement about the HOST as much as the
  recipe.** The same `test-scenario siege 4 15` measured 25 s warm and
  2 min 55 s cold (a docker image build), and one `just up` measured 5 s
  and 24 s an hour apart with nothing changed. The DURATION is the honest
  part; the rest is contention. Same lesson as M6's worst-tick figures
  and the terrain session's `bench-render` absolutes.
- **The LOOP's own fog gate is as marginal as the gate's on `main`.**
  Two `siege 4 15` runs back to back reported `reveal_events=0` (fail)
  and then `1` (clean). Same cause as above; a scenario simply reaches
  the question in twenty-five seconds instead of five minutes, which is
  the whole argument for iterating there.
- **A scenario at REAL spawn separation does not buy the gate back.**
  `test-scenario developed 4 60` — `developed` is the one shipped
  scenario with `separation = 0` — reports `casualties_applied=0
  conceal_events=0 reveal_events=0`. Real spawn distance means a real
  march, and the march is what costs five minutes. Only skipping the
  opening buys it back, which is what `separation` already does.

**Do not shorten the gate's DURATION to make it cheaper.** D-031's trap
is exactly that: `4 40` was the recommendation here for a whole milestone
and could not have passed. A duration that no longer reaches contact
fails honestly, and that is the check working. Run the LOOP more and the
GATE less.

**Use `just test-load 4 150`** — and know before you run it that **the
verdict's `reveal_events` gate is currently failing on `main` itself, and
no duration fixes it.** Measured 2026-08-16 on `main` at f5142fc, and on
a branch off it, in an isolated worktree per D-095:

**The `reveal_events` gate was unreachable on `main` for a day and is
fixed** (D-20260817-load-test-bots-must-manoeuvre, #69/#84). If you are
reading an old branch's failure, or an older copy of this file, the short
version is: the gate was never wrong — **the bots had stopped manoeuvring
at all**, so there was no return leg for it to count.

Both of `bot_client.gd`'s movement mechanisms were dead at once. The
rally/recall pair was a ONE-SHOT at t=0 s and t=8 s, written when a player
started with twelve squads; under D-031's opening a bot owns exactly one
squad then — the founding party, which is at that moment walking off to
plant a town hall and being consumed by it. And the raid alternation is
unreachable: a bot only ever builds a town centre, a town centre
`produces` gatherers only, and the haul loop claimed every crew, so
`raid_pool` was empty on every tick. Four bases quietly chopping wood. The
server log said so plainly and nobody had read it that way — four squads,
eight flow fields and a byte-identical packet count from 20 s to 50 s.

**The map doubling of 2026-08-17 (84×96 → 168×194) makes the gate pass
without fixing any of that, and that is worth being explicit about.** A
`4 300` run on the new map reported `reveal_events=63` where the old map
reported 0 or 1 — because more of a bigger map goes unseen, so hauling
crews wander in and out of each other's vision by accident far more often.
That is the gate satisfied by luck at a larger scale, not by a squad
deliberately breaking contact and returning, and a criterion met by
accident is the shape D-022's audit block was written about. The
manoeuvre is performed now rather than hoped for.

**Read the PER-BOT lines the verdict prints before reading any of the
sums.** Every counter in the VERDICT line is a total across four bots, and
a total cannot say "one of them is not doing the thing" — which is what
three of the five defects behind #69/#84 turned out to be. One run of
`BOT player=…` answered what four runs of aggregates had not.

**Three standing rules come out of it, all already written down here or in
`decisions/`, all paid for again:**

- **When the opening changes, every timing tuned against the old one is
  stale.** Third instance, after `test-load 4 40` and `test-client`'s 15 s
  default. Leg boundaries in `bot_patrol.gd` are events now — the scout
  arrived — with a timeout only as a backstop.
- **A single green run is not a measurement.** This file once said
  "`4 150` is clean" on the strength of one run reporting
  `reveal_events=10`; four subsequent runs across two trees reported 0. If
  you are about to write a duration here, run it more than once.
- **Latch on the effect, not the send** (D-107). A bot's town hall order
  used to set a "done" flag the instant the packet left, so a REFUSED
  opening — a forest on the start, which D-087's 1,920 nodes make likely —
  left that bot with no hall, no crews and no scouts for the whole run
  while its own flag said the opening was handled. **`bot_client.gd`'s
  `_found_town_hall` retries against a different site now**
  (`offsets[_build_attempts % offsets.size()]`), until a building it owns
  actually appears. Two of four bots were failing to found before this
  was noticed.

  **Read that as a fact about the BOT and not about the AI**, because the
  unattributed version of this sentence cost two people a wrong
  conclusion (#291). #217 quoted it as evidence that `ai_player.gd`
  retried at a different site and did not — and the gap assessment
  repeated the error. The sentence was true the whole time; it named
  neither the file nor which of the two actors it described, and both
  readers supplied the wrong one. `ai_player.gd` gained the same
  behaviour separately, in #217.

What the bots do now: a share of each one's army (at most one squad in
two, at most two) is held out of the economy and walks in on a neighbour
until they can see it and back out until they cannot, over and over. It
starts from a bot's SECOND hauling crew, so a run that ends before
production has delivered two produces no reveals by construction. The
geometry — 8 cells in, 20 cells out, against a town centre that sees 11
and shoots 6 — is in the decision and asserted against the shipped
resources by `tests/test_bot_patrol.gd`.

- **Duration follows the MAP, and the map doubled on 2026-08-17.**
  Marching time scales with LINEAR size, not area, so the ~150 s that was
  marginal before is roughly 300 s of equivalent marching now. The gates
  that get harder are the contact-dependent ones —
  `casualties_applied`, `conceal_events`, `reveal_events`; the fog
  coverage gates get *easier*, because more of a bigger map goes unseen.
  Re-measure before writing a number here.
- **A reveal needs a conceal AND a return.** `reveal_events` counts a
  squad re-entering vision after leaving it, so it is the LAST of the fog
  criteria to be satisfied and the first to fail.
- **The fog gates are reached MUCH earlier since the opening changed**
  (D-20260823-the-opening-is-a-crew-and-a-general). Every player now
  starts with a general as well as a crew, so a bot has a squad to scout
  and raid with from tick one instead of waiting on a town hall, then
  production, then a second hauling crew. One `4 120` run on 2026-08-23
  came back `VERDICT ok` with `conceal_events=105 reveal_events=77`,
  where this page records `4 300` *failing* at `0/0` and `4 480` as the
  first clean run on the same map. **That is one run, which this page's
  own rule says is not a measurement** — read the direction, not the
  number, and do not rewrite the recommended DURATION off it until
  somebody has repeated it.
- **A town hall takes 40 seconds and the crew that founds it is spent on
  it**, so a player's ECONOMY does not start until production does. The
  ~90 s `soldiers=0` floor this note used to carry is STALE as of
  D-20260823-the-opening-is-a-crew-and-a-general: every player now opens
  with a general as well as a crew, so a bot fields a military squad from
  tick one and `military_peak`/`first_soldier_at` latch immediately. Read
  a `soldiers=0` now as a genuine fault rather than as the opening.
  Everything downstream — the barracks at 100-205 s, the first *trained*
  soldier at 135-226 s — is unchanged, because the economy's timings did
  not move.
- Spawns are scattered at a minimum spacing (D-039) and the load test's
  server generates the map file's 20 starts, not one per bot — it has no
  lobby, so D-20260817-starting-positions-follow-the-seats does not apply
  to it. The four bots take seats 0–3, and how far apart those land is a
  property of the map and seed rather than of the bot count. That spread
  is why the patrol's boundaries are stated in the WATCHER's terms rather
  than as "am I home yet": on a tight pair, home is inside the
  neighbour's vision.

- **`4 300` stops satisfying the fog gates once squads wheel round bends
  rather than snapping round them** (D-20260818, #101). Measured A/B on
  one host, native, seed 1337, default map: `conceal_events` 6 -> 1 and
  `reveal_events` 5 -> 0, taking the verdict from ok to failed, while
  `casualties_applied` stayed at 36 and desyncs stayed at 0 — armies
  cross vision boundaries fewer times inside a fixed window, not less
  correctly. **`4 480` on the same tree is clean**: `VERDICT ok`, 0
  desyncs over 1,920 checks, 0 dropped ticks, `casualties_applied=60
  conceal_events=20 reveal_events=5 ghosts_peak=16 nodes_felled=254`.
  This is the "when the opening changes, every timing tuned against the
  old one is stale" rule again, applied to how fast an army walks rather
  than to the build order — and it is the third thing on this page to
  move that duration, so read a `conceal_events` failure as a question
  about DURATION before reading it as a fault in the change under test.

  **Those two numbers were taken BEFORE that branch was rebased**, on a
  tree whose smoothed paths cut the corners of obstacles
  (`D-20260818-a-squad-wheels-it-does-not-snap`'s rebase amendment). The
  direction is unchanged — wheeling slows an army that turns, so a fixed
  window holds fewer vision crossings — but treat `480` as the shape of
  the answer rather than a measurement until it is re-run.

**The bots field an ARMY now** (D-20260818-load-test-bots-must-field-an-army,
#123), and the verdict gates on their having used it. Until this landed,
`raid_pool` — the squads free to be sent anywhere — was empty on every tick
of every match, so `_issue_order` returned before issuing a single raid
order, for every run there has ever been. A bot only built a town centre, a
town centre `produces` gatherers only, and the haul loop claimed every crew.

So `test-load` did not exercise military production, an engagement between
two real armies, `UnitDef.damage_vs_buildings`, D-067's raze rule, or most
of `/units` — a run only ever fielded `founders` and `gatherers`, both
`civ = &"neutral"`. **The CIVS_FIELDED check passed throughout**, because
`_civs_fielded()` counts by the PLAYER's civ rather than the unit's: two
civs were reported fielded every run while the roster's civ half went
untouched. Worth knowing before trusting any other count on this page.

Two new keys in the verdict: `raid_orders` is a GATE (a run where no ARMY
was sent anywhere fails — orders to a hauling crew do not count, and an
early version that counted them passed on a crew nobody meant to raid
with), and `military_peak` is the metric beside it, because "there was
nothing to send" and "there was something and it was never sent" are
different faults with the same symptom.

Measured on the shipped map: a barracks finishes at **100-205 s** and the
first soldier is fielded at **135-226 s**, so nothing below ~250 s tests
any of it. **Two of four bots do not reach a barracks even at 420 s** — a
town hall costs 150 wood out of a 180-220 opening bank and hauling round
trips are long on the doubled map. One bot reliably banks a single 60-wood
delivery and then stalls, wallet `[172, 90, 0, 0]`, in every run measured
before and after that change; its crews are alive and assigned. Unexplained
and pre-existing, so worth knowing before reading a low `military_peak` as
a regression.

**A bot never learns its own civ.** `server.gd` broadcasts the lobby only
while there IS one and `test-load` starts a match without one, so
`ClientState.civ_of` answers `""` for every bot in every run. Anything a
client normally learns from the lobby is simply absent here — which cost a
run to find, because resolving production per civ matched `gatherers`
(`civ = &"neutral"`, so it matches anybody) and nothing else, leaving
barracks standing and `military_peak=0`. The wire carries an ARCHETYPE and
the server resolves it per civ (D-047), so a bot does not need to know.

**A scenario's gates are scoped to what that scenario CONTAINS, since
2026-08-28** (`D-20260828-a-scenarios-gates-are-what-it-contains`, #230).
`just test-scenario clash` could not pass at all, and the bot's own line
said why in one breath: **`military=5` and `military_peak=0`**. The whole
reporting spine — `military_peak`, `first_soldier_at`, `raid_orders`,
`scouts_peak`, `patrol_legs` — was gated on having identified a FOUNDING
CREW, and `clash` ships none.

Three things worth carrying, and the third is the one that is not about
scenarios at all:

- **A vacuous FAILURE is as bad as a vacuous pass.** `clash` places no
  buildings, so the verdict's `buildings_known > 0` clause could not be
  satisfied there however healthy the run was. It failed identically
  every time, which is precisely how the next person learns to ignore the
  result. The gates are asked of the `ScenarioDef` now — and a scenario
  with no buildings gates on the ARMY it was given instead, because
  dropping a check and adding nothing is a relaxation.
- **`clash` cannot prove PEAK fog gating, and now says so.**
  `gate-check.sh fog-squads` asks that even the most-informed client knows
  fewer squads than the server simulates *at every moment*; `clash`'s
  armies converge, so somebody ends up having seen everything —
  **measured 10 of 10 at two bots and 20 of 20 at four**.
  `ScenarioDef.proves_fog_gating` is `false` there, it rides the server's
  `SCENARIO` marker, and `test-scenario` prints the skip WITH ITS REASON
  rather than taking it quietly. `fog-nodes` still runs unconditionally
  and the verdict still gates on conceal/reveal, so fog is asserted
  either way. **`test-load`'s own gate block is unchanged.**
- **That gate used to PASS on `clash`, and only because the bots were
  broken.** They never marched, so two armies 8 cells apart against a
  12-unit vision range never saw each other. *A check can be green
  because the thing it checks never happened* — the same shape as every
  vacuous pass in D-022's audit block, found here by fixing the harness
  and watching a green gate turn red.

Measured 2026-08-28 (docker): `test-scenario clash 2 60` **clean** where
it could not pass before — `casualties_applied=294 conceal_events=21
reveal_events=13 raid_orders=37 military_peak=10`, 0 desyncs over 115
checks. `test-load 4 120` unaffected and clean: all three gate checks
green, `fog-squads` gating 18 of 32 squads, 0 desyncs over 472 checks,
**154.07 µs/squad at 32 squads** (quote it with the count — and with the
host, which OOM-kills docker on this machine).
