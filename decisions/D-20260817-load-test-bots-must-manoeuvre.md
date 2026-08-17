# D-20260817 · 2026-08-17 · Accepted — a load-test bot must MANOEUVRE, and the manoeuvre lives outside the bot

**Decision:** `test-load`'s `reveal_events` gate stays, and the bots are
fixed to satisfy it. A share of every bot's army is held out of the
economy as a scouting detachment which walks in on a neighbour until they
can see it and back out until they cannot, repeatedly, for the whole
match. The rules for that cycle live in `bot_patrol.gd` — all-static and
pure, like `formation.gd` and `scoreboard.gd` — so the half of the load
test with the interesting failure mode is testable without an ENet host,
a server, or two minutes of docker.

Five clauses:

1. **The gate is right; the bots were wrong.** `reveal_events > 0` is
   D-026 criterion 9: a run in which nothing was ever hidden and shown
   again proves nothing about fog. Retiring it because it started failing
   is the shape this project has been bitten by before (see D-022's audit
   block, and the justfile's own note about the `desync` scan that passed
   vacuously for a whole milestone).
2. **One split, two halves, no squad in both.** `BotPatrol.assign`
   returns `{scouts, workers}` from one pass. The defect being replaced
   was two independent filters disagreeing about who owned a squad.
3. **Leg boundaries are events, not timestamps.** A leg ends when the
   scout has arrived — something the bot can observe — with a timeout only
   as a backstop. The predecessor was a pair of absolute times and it is
   the third instance of a timing tuned against an opening that later
   changed.
4. **Both boundaries are stated in the WATCHER's terms.** What the verdict
   counts is the neighbour losing sight of the scout and finding it again,
   so "far enough out that they have lost me" is the actual condition and
   "am I home yet" only approximates it — see the rationale for the map on
   which it stops approximating it at all.
5. **The standoff is a DESTINATION, not a distance to notice having
   reached.** A bot cannot see where its own squad is to better than a
   second, so any safety margin that depends on it noticing promptly is
   not a margin. Measured, below.

## Rationale

Reported twice, independently: **#69** (2026-08-16, from `test-load` as
the standing gate for #64) and **#84** (2026-08-17, from verifying #60 on
`main`). Same signature both times, on unmodified `main`: everything the
verdict wants is present — 4/4 bots connected, 0 desyncs, 0 building
desyncs, casualties in the 150s, buildings known and agreeing — and
`reveal_events=0` is the only unmet condition. It passed roughly one run
in four or five, by a margin of exactly one event.

Both reports guessed at bot behaviour and both were right to. The bots had
stopped manoeuvring **at all**, for two independent reasons:

- **The rally/recall pair was a one-shot in the opening.**
  `RALLY_AT_SECONDS := 0.0` and `RECALL_AT_SECONDS := 8.0` date from
  f493018 (M2/M3), when a player started with twelve squads. D-031 made
  the opening a single founding party, so from then on the whole
  conceal-and-return mechanism fired once, in the window where a bot owns
  exactly one squad — the founder — which is at that moment walking off to
  plant a town hall and being consumed by it. It never ran again for the
  rest of the match. **This is exactly the trap CLAUDE.md already names:**
  *"when the opening changes, every timing tuned against the old one is
  stale"*, previously paid for by `test-load 4 40` and by `test-client`'s
  15 s default.
- **The raid alternation is unreachable.** `_issue_order` builds a
  `raid_pool` that excludes the founding party and every squad the haul
  loop has claimed. A bot only ever builds a **town centre**, a town
  centre `produces` **gatherers only**
  (`buildings/town_centre.tres`), and `_put_gatherers_to_work` claims
  every crew that can carry. So `raid_pool` is empty on every tick after
  the founder is spent, and the function returns before issuing a single
  move order.

So the whole match was four bases quietly chopping wood, and the server's
own log says so without ambiguity — from a `just test-load 4 120` run on
`main` at d6a5f9b:

```
tick=100 time=10.0s squads=4 clients=4 sent= 8704B fields=8
tick=200 time=20.0s squads=4 clients=4 sent=14092B fields=8
tick=300 time=30.0s squads=4 clients=4 sent=14092B fields=8
tick=400 time=40.0s squads=4 clients=4 sent=14092B fields=8
tick=500 time=50.0s squads=4 clients=4 sent=14092B fields=8
```

Four squads, eight flow fields and a **byte-identical** packet count for
thirty seconds: nothing on the map was moving or being ordered anywhere.
The conceals that did occur were hauling crews drifting past each other,
which is why there were two of them and why a return leg was a coin flip.

**This is the declared-and-unread family in D-061's harder variant.** The
raid code is written, correct, and has a caller; the caller is simply
unreachable. A grep for uncalled public members finds nothing here — the
pool is built, the branch is taken, the pool is empty. Nothing failed
loudly, because a load test whose bots stand still still connects,
replicates, hashes and reports.

### Why not just lengthen the run

Because the owner measured it and it does not help: `main` at 210 s
produces the same 15 conceals and the same zero reveals as at 150 s
(#69's first comment). Nothing was going to arrive later, because nothing
was moving.

### Why not retire the gate

Option 3 in #84 — report `reveal_events` instead of gating it — is the
cheapest and the weakest, and #84 says so itself. The gate had found a
real defect; it was doing its job.

### Why the boundaries are the watcher's, not the scout's

The first version of this cycle withdrew to the bot's own start and called
the leg finished on arrival. Simulated against the four starts the load
test's own server hands its four bots, one pair produced **zero** reveals:
starts scatter at a minimum spacing of 12 cells (D-039) and two of those
four were **13 cells apart**, against a town centre's `vision_range` of 20
world units — **11 cells**. A scout at base is one cell outside the
watcher's vision at best, and the slop in "arrived" puts it back inside.
The withdrawal has to be defined as *out of their sight*, and
`withdrawal_target` pushes the destination past home when home is not far
enough.

(That 13 was the 84x96 default. The map doubled to 168x194 the same day
and the tightest pair is 17 cells now — still inside `WITHDRAW_CELLS`, and
still not something any of this code can know in advance, which is the
point of stating the rule in the watcher's terms rather than in cells of
map.)

That failure is the one worth carrying forward: **the simulation found it,
before any of it ran against a server.** A version tested only by the
120-second docker loop would have shipped with one of the four generators
silently dead, which is precisely the flaky-at-zero behaviour #69 reports.

### And the one the simulation could NOT find: a client does not know where its own squads are

The first version that ran against a server sent scouts to the neighbour's
start and relied on `leg_done` to turn them around at the standoff. The
start is passable and reachable by construction, where a computed cell nine
short of it can be open water — which read as the safer choice and was not.

A bot samples its own squads through `ClientState.squad_cell(squad, now)`,
where `now` is a clock it accumulates itself frame by frame (exactly as
`client.gd` does), against a curve `CurveReplicator` clipped to a
**one-second horizon**. So "where is my scout" is about a second stale, and
at the shipped gatherer's 1.96 cells/s that is two cells of overshoot. Two
cells past a 9-cell standoff is 7, against a town centre that shoots at 6.

Measured on `just test-load 4 120`, against the same run with the manoeuvre
otherwise identical:

| | casualties | conceal | reveal | patrol legs | verdict |
|---|---|---|---|---|---|
| `main` (no manoeuvre) | 56 | 2 | **0** | — | FAILED |
| standoff as a detection | 164 | 9 | 3 | 7 | ok |
| standoff as a destination | *see below* | | | | |

The middle row is the tell: casualties nearly TRIPLED and one player was
eliminated inside two minutes. The scouts were walking into the guns
instead of coming home, and the economy went with them — `nodes_felled`
fell from 14 to 5 and no bot ever staffed more than one scout.

So the overshoot is absorbed by **where the squad is sent**. The
destination is the observation post itself; `SquadSim._apply_move_order`
already resolves a destination nobody can stand on to the nearest cell
they can — which is exactly the objection that had made the start look
safer, already answered, at the one site all four order paths share.

**The general form is worth more than the fix:** a margin that depends on
noticing in time is not a margin on a system with a wire in it. Put the
bound where the authority is.

### And a third, also only findable by running it: which scout decides

`leg_done` first judged the leg on whichever scout was **nearest the
current destination**. That reads as strictly the more robust rule — one
crew stuck in a lake cannot stall the cycle — and it thrashes. With two
scouts in different places, the one nearest the outward post has arrived
at the moment the one nearest the withdrawal point is still standing at
base, so each leg is satisfied by a *different* squad the instant it
begins and the cycle flips every frame. Measured: **`patrol_legs=1077`**
in a 120 s run, against 10 for the same code judging one squad.

The lead scout decides now. They are all given the same order, so one of
them describes the cycle perfectly well, and `LEG_TIMEOUT_SECONDS` covers
the case the rejected rule was reaching for.

`patrol_legs` is in the verdict line **because of this**: the run before
it was added reported `reveal_events=1` and looked like a marginal pass,
and there was no way to tell a patrol that never staffed from one flipping
twenty times a second. Both of the last two defects here were invisible
until the manoeuvre itself was counted.

### And a fourth, found by the PER-BOT line: half the bots never founded

Every counter above is a sum across four bots, and a sum hides "one of
them is not doing the thing". Printing them per bot took one run to answer
what four runs of aggregates had not:

```
BOT player=1 squads=1  buildings=0 town_hall_ordered=true scouts_peak=0 legs=0 conceal=0 reveal=0
BOT player=2 squads=12 buildings=1 town_hall_ordered=true scouts_peak=2 legs=4 conceal=2 reveal=1
BOT player=3 squads=10 buildings=1 town_hall_ordered=true scouts_peak=2 legs=6 conceal=1 reveal=0
BOT player=4 squads=1  buildings=1 town_hall_ordered=true scouts_peak=0 legs=0 conceal=6 reveal=5
```

Player 1 **sent its town hall order, was refused, and never asked again**
— `buildings=0` beside `town_hall_ordered=true`. So it never produced a
crew, never staffed a scout, and the neighbour watching it (player 4) had
nothing to see. Two of the four patrol generators were dead, and the gate
was passing on the other two.

`_town_hall_ordered` was set on the `peer.send`, which is **D-107's own
lesson with the names changed**: *a latch that records an INTENT will
eventually be read as a record of an OUTCOME. Latch on the effect —
something the actor can SEE — or do not latch.* D-107 was written about
`_founded = true` sitting one line above `send.call(order)` in
`ai_player.gd`; this is the same line of code in the load-test bot, and
the refusal it swallows is entirely likely on a start, since D-087 put
1,920 resource nodes on the map and `_build_refusal` rejects a site with
one on it.

The bot now retries until a building it owns appears in `state.buildings`
— which the server files when construction STARTS, so the retry stops
while the hall is still going up — and each attempt asks for a different
site, walking outward from home through `TorusSpace.disk_offsets`, which
D-067 made nearest-first for exactly this. Retrying the same refused cell
would have been a loop rather than a fix.

**And the retry's own first version was unreachable**, which is worth
recording because it is the same shape a third time in one change. It sat
where the old latch had, *below* `raid_pool` — and `raid_pool` excludes
the founding party, as it must, or a raid order cancels the build it is
walking to. So a bot whose only squad IS that founder built an empty pool
and returned before ever reaching the retry: unreachable for exactly the
bot that needed it. The per-bot line said so in one run —
`build_attempts=1 buildings=0`, a bot that asked once and never got
another turn. The opening runs before the pool is built now.

## Numbers

`STANDOFF_CELLS := 8` and `WITHDRAW_CELLS := 20`, against the shipped
`buildings/town_centre.tres` on the shipped map:

| | world units | cells |
|---|---|---|
| town centre `vision_range` | 20.0 | 11 |
| town centre `attack_range` | 12.1 | 6 |
| scout standoff | — | **8** |
| scout withdrawal | — | **20** |

8 is inside the watcher's sight and outside its guns, which is what makes
the scout both SEEN and SURVIVING — a crew is 5 men at 35 HP against 42
damage a shot, so a scout that walked onto the start would not come back
and the reveal half of the gate would be unreachable for a brand new
reason. It sits near the middle of the band (6, 11] rather than at either
end, because the cell a scout actually parks on is the post resolved
through `_approachable` and can be a cell or two off when the computed one
is water. 20 is comfortably past 11, with room for one of the watcher's
own crews (10 world units of sight, ~5 cells) to have wandered toward us.

`tests/test_bot_patrol.gd` asserts both bounds against the resources
themselves rather than against those comments — D-066's rule, that a
mechanism being right says nothing about whether the shipped numbers do
anything — and asserts them per neighbour PAIR on the shipped map, since
the post is computed from each pair's own geometry.

## Rejected alternatives

- **Lengthen `test-load`'s duration.** Measured not to work (above), and
  it would re-set the stale-timing trap rather than clear it.
- **Report `reveal_events` rather than gating it.** Retires a check that
  had just caught something.
- **Give the bots a real army: barracks, then military production.** This
  is the honest fix for the *raid* half, and it is deliberately NOT in
  this change. A barracks costs 150 wood and 25 s on top of a 40 s town
  hall and the crews to pay for it; measured on this branch, a bot's
  second hauling crew exists at ~65 s of a 120 s run, so military
  production cannot be reached inside the duration the gate is quoted at
  and could not be validated by the run this change has to pass. Filed as
  **#123**.
- **Have the bots run `AIPlayer`.** Zero duplication, and wrong: the AI's
  first attack is ~171 s (D-107's first honest ladder figure), so a 120 s
  load run would see less contact, not more — and the fog gates would come
  to depend on AI strength. `bot_client.gd`'s scripted scenario is
  deliberate, and its own header has said so since M2.
- **Compute the observation post as a cell and order the scout there.**
  A cell nine short of a start on the wrapped line can be open water. The
  destination stays the start itself — passable and reachable by
  construction — and stopping short is a decision about a squad the bot
  can see.

## Consequences

- Scouting is paid for out of gathering: at most one squad in two, and at
  most two per bot. A bot patrols from its **second** crew onward, which
  is ~65 s into a run on the shipped map.
- `test-load`'s fog counters get much larger and much less interesting
  individually — the patrol is a designed generator of conceal/reveal
  pairs, not an accident. That is the point: the gate becomes
  deterministic rather than flaky-at-zero.
- `bot_client.gd` loses `RALLY_AT_SECONDS`, `RECALL_AT_SECONDS`,
  `SCOUT_SQUADS_PER_BOT`, `_issue_rally_order`, `_issue_recall_order`,
  `_home_cell`, `_rallied` and `_recalled`.
- The raid alternation stays and now excludes the detachment as well as
  the working crews, but remains unreachable until bots build a barracks.
  Its `raid_pool.is_empty()` branch says so in as many words and cites
  #123, so the next reader finds the gap stated rather than having to
  re-derive it.

## Revisit trigger

- A bot gains an army (a barracks and military production). The
  detachment should then come out of the army rather than out of the
  economy, and the raid alternation becomes reachable — at which point
  whether both mechanisms are still wanted is a live question.
- `reveal_events` returning to zero on an unmodified tree. The patrol is
  supposed to make it deterministic; a zero means something else broke,
  and the first thing to check is whether the run reached ~65 s of match
  time at all.
- The shipped town centre's `vision_range` or `attack_range` changing:
  `STANDOFF_CELLS` sits between them and the test will say so.
