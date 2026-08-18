# D-20260818 · 2026-08-18 · Accepted — an AI's difficulty is data, and it is never a cheat

**Decision:** how an AI *plays* is an `AiProfileDef` `.tres` under `/ai/`,
resolved through `AiProfileRoster` and held by `AiPlayer` as `profile`.
`ai_player.gd` keeps no tuning constant that a profile could have carried,
and **no `.gd` file may name a profile id** — the same criterion that
keeps civs data (D-046 criterion 3 / D-047), tested the same way.

Five clauses:

1. **A profile changes what the AI DECIDES, never what it KNOWS or what
   it is GIVEN.** Every field is a threshold or an interval inside the
   brain. D-051's structure — a real `ClientState` fed fog-gated packets,
   orders through the server's own dispatcher — is untouched, so a harder
   AI is one that plays better, not one that sees more. A resource or
   vision bonus is rejected on those grounds; if a handicap is ever
   wanted it belongs in the **lobby**, as an explicit setting a player can
   see, not inside the brain where it would be indistinguishable from
   skill.
2. **The schema defaults ARE the shipped constants.** `AiProfileDef.new()`
   with nothing loaded reproduces `ai_player.gd`'s previous behaviour
   exactly, and `ai/balanced.tres` is those defaults written out. A
   missing or unreadable `/ai` therefore costs *difficulty*, never the
   game — the same fallback shape as an empty `model_id` meaning "use the
   capsule" (D-081).
3. **`balanced` is bit-for-bit today's AI.** That is what makes every
   ladder figure taken before this decision comparable to one taken after
   it. A profile change that also moved the baseline would leave the
   ladder measuring two things at once, which is how M6 ended up with an
   unattributed 40.8 → ~77 µs/squad rise it still cannot explain.
4. **Not every constant is a difficulty knob.** `FOUND_RETRY`,
   `UNREACHABLE_AFTER` and `SCOUT_LEG_SECONDS` stay constants: they bound
   a *failure*, and a difficulty setting that can starve an AI of its
   opening is not a difficulty setting, it is a way to ship a broken
   opponent by data entry. `FOOD_FLOOR`/`WOOD_FLOOR` are lifted because
   the code asked for them, but **every shipped profile carries the same
   floors** — a floor is where the economy stalls, and moving one without
   measuring is how the AI spent a whole session gathering zero wood
   (D-054's `substituted` counter).
5. **The ordering of the levels is a HYPOTHESIS until the ladder says
   otherwise.** "Relentless beats Cautious" is a claim about a game nobody
   has played yet. The measurement half of this decision exists so that
   sentence can become a number with a cap attached, and the shipped
   values are a starting point to be moved by evidence.

## The levels

Three ship. Adding a fourth is adding a file.

| id | think | gatherer soldiers | train cooldown | squads before it commits | regroup (thinks) |
|---|---|---|---|---|---|
| `cautious` | 2.0 s | 150 | 9.0 s | 2 | 12 |
| `balanced` | 1.0 s | 110 | 5.0 s | 2 | 8 |
| `relentless` | 0.5 s | 80 | 3.0 s | 4 | 6 |

`balanced` is the row that already existed. The other two move the two
things a human actually feels: **when the army starts existing** (the
gatherer target is the switch from economy to soldiers, and the cooldown
is the ramp after it) and **what arrives when it does** (the commit
threshold — `cautious` dribbles two squads at a time, `relentless` masses
four). `think_interval` is a reaction-time axis rather than a pacing one
and is deliberately mild: it is what will matter once the AI reacts to
being attacked, which today it does not.

## Rationale

Playing 1 human vs 3 AI, the AI's attack lands before the human's opening
is finished (#93, from playtest #30). Every rule it plays by is a human's
rule, so this is not a defect — it is that **there is exactly one AI, it
plays one way, at one speed, and that speed is tuned against nothing a
human experiences.** `quick-test` seats three of them, so three
identically-ramping economies converge on one player.

The knobs to turn were already named and already in the wrong place.
`THINK_INTERVAL`, `GATHERER_SOLDIERS_WANTED` and `TRAIN_COOLDOWN` each
carried a comment saying "becomes a profile field in the next slice
(D-053)" — and **D-053 was never written** (D-061 records it as one of
several IDs cited by code that do not exist). This entry is that slice,
and it pays the debt rather than adding a fourth citation to a decision
nobody made.

**Why data rather than an enum with three branches.** The identical
argument as D-047's: an enum makes the fourth difficulty an engineering
task and puts the tuning numbers where a person balancing the game cannot
reach them without editing a script. The test that keeps it honest is a
source scan for profile ids, which is the check that actually failed for
civs before `CivDef` existed.

**Why the profile is disjoint from `CivDef`.** `CivDef.squad_cap_bonus`,
`production_speed` and `gather_speed` are shipped with non-default values
and read by nothing — the fourth declared-and-unread instance, recorded in
`docs/status/m9-plan.md`. #93 asks that profile work "either wire them up
or delete them, not add a parallel set beside them". No field here
duplicates one of those: they are *civ identity* applied by the
simulation to what a player of that civ gets, while these are *how a brain
decides*. Wiring them remains M9's item and is deliberately not done here
— it changes the balance of every match, human matches included, and
would land inside the one measurement this decision needs to stay clean.

## How strength will be MEASURED

Three instruments, in increasing order of how much they are to be
believed.

1. **`just ai-ladder` profile vs profile.** The recipe takes a `PROFILES`
   argument — a comma-separated list dealt round-robin across the AI
   seats, exactly as civs already are — and reports, per seat: its
   profile, its win count, its economy peaks and its time to first
   attack. "Relentless beats Cautious" is then a win rate over N matches at
   a stated cap. **Quote every ladder result with its cap** (the standing
   rule): a stronger opponent lengthens matches, and a truncated match
   reads as a draw.
2. **A pacing metric the ladder can print but the ladder does not
   settle.** `AI_STATS` carries `first_attack` (when) and now
   `first_attack_soldiers` (how big). Those two numbers are the ones #93
   is actually about — "attacked at 171 s by 40 men" is a sentence a
   human can be asked whether they could have survived, where "2 of 3
   decided" is not.
3. **A human playing it.** The observation that opened #93 is the exact
   class the ladder is blind to (D-055: every ladder match drew at the cap
   and it was read as an AI weakness for several rounds while the real
   cause was that nothing could destroy a building). **Where the ladder
   and a human session disagree, believe the human session.**

The third leg of #93's pacing metric — *what the defender could plausibly
have had by then* — is deliberately not attempted here. It is not
derivable inside an AI seat, which knows only what it was sent; it is a
question about a build order, and it belongs with the human-facing
playtest that answers it.

**Known blind spot, narrowed on 2026-08-18 by
D-20260818-allied-ai-is-exercised-by-something (#119), which landed
first:** the ladder is still a free-for-all, so a profile-vs-profile win
rate says nothing about how a profile plays *beside an ally*. What #119
adds is `just test-ai-teams`, a real teamed all-AI match — and this
decision hangs its own end-to-end check there rather than growing a
second harness. See the amendment below.

## Increments

This entry is the shape; only the first increment is built.

1. **Profiles are data, and the ladder can pair them.** *(this change)*
   `AiProfileDef`, `AiProfileRoster`, `/ai/*.tres`, `AiPlayer.profile`,
   `--ai-profiles=` on the server, `PROFILES` on `just ai-ladder`,
   `profile=` and `first_attack_soldiers=` in `AI_STATS`.
2. **Per-seat selection in the lobby**, beside civ and team, so a 20-seat
   match can mix them (D-048/D-089). Needs a seat field on the wire and a
   control in the lobby UI; `MatchState` seating and `NetProtocol`'s seat
   encoding are the whole of it.
3. **Behaviour, one axis at a time, each measured on the ladder before
   the next starts**: defence and garrison, target selection by weakness
   rather than by distance, army composition read from the counter
   triangle (D-032), retreat on morale (D-019), scouting as a decision,
   formations (D-058), walls and gates (D-076).
4. **Pacing chosen against D-056's 1–2 hour target** rather than emerging
   from a cooldown, once (3) has changed what a match looks like.

Reconnection handing a seat to an AI (D-090) and Steam seat-fill (D-089)
are M8's and stay there.

## Rejected alternatives

- **A `difficulty: int` on the AI seat, branched on in `ai_player.gd`.**
  The fourth difficulty becomes a programming task and the numbers live
  where a balancer cannot see them. Rejected for D-047's reasons.
- **Resource, vision or build-speed bonuses at higher difficulty.** The
  standard RTS answer, and it breaks the one property that makes an AI
  win here mean anything (D-051, D-046 criterion 9). An AI that quietly
  saw more would not look like a bug; it would look like a good AI.
- **Making `balanced` "a bit better than today" while we are in here.**
  Tempting and quietly fatal: the baseline every existing ladder number
  was taken against would move, and no later measurement could be
  compared to an earlier one. Improvements go in a *new* profile, or in
  increment 3 where they are measured on their own.
- **Per-seat profiles in the lobby in this increment.** Real, wanted, and
  a wire change plus a UI change plus a seating change on files three
  other branches are editing this week. It is increment 2 for merge-train
  reasons, not design ones.
- **Deleting the unread `CivDef` knobs while here.** Out of scope for
  #93 and a balance change to every match; M9 owns them.

## Consequences

- `ai_player.gd` reads `profile.*` where it read a `const`. The constants
  that stay are the three failure bounds in clause 4.
- `AI_STATS` gains two fields. It is a structured marker line, parsed by
  `just ai-ladder`'s awk; adding fields is safe, reordering is not.
- The no-lobby server path gains `--ai-profiles=`. Absent, every seat
  takes the default profile and nothing about a run changes — which is
  what keeps `test-load`, `test-scenario` and the existing ladder
  invocation measuring the same AI they measured yesterday.
- An unknown profile id on the command line is a **refusal to start**,
  not a silent fallback, for D-20260817-recipe-args-are-positional's
  reason: a plausible wrong world is worse than no world.

## Revisit trigger

- A ladder run at a stated cap shows the three profiles are **not**
  ordered by strength (clause 5 explicitly expects this may happen). The
  fix is new numbers in the `.tres`, not new code.
- A profile field turns out to need a per-civ answer — then it is a
  `CivDef` knob interacting with a profile, and D-047's "one knob every
  civ has" rule applies to it before it is written.
- Any proposal to give a difficulty level information or resources a
  human seat would not get. That reopens clause 1 and needs D-051 amended
  first, in public.

## Amendment, 2026-08-18 — rebased onto #119's harness

Two things changed when this landed after
`D-20260818-allied-ai-is-exercised-by-something`.

**1. `PROFILES` is `ai-ladder`'s FIFTH argument, not its fourth.** #119
took the fourth for `TEAMS` and its own entry documents
`just ai-ladder 3 600 4 2`. Two branches each adding "one more positional
argument" is precisely the trap
D-20260817-recipe-args-are-positional exists to close — one of them
lands second and every invocation written against the other now means
something else, silently. Ordering was decided by which entry shipped
first, not by which reads better.

**2. A played match now asserts the difficulty ARRIVED.**
`just test-ai-teams … PROFILES` deals difficulties across its seats and
fails if any seat reports no profile, or if a list naming more than one
produces only one at the table.

That check exists because the unit tests cannot reach the question.
They prove a profile field changes a **decision** — four of them, each
observed red first. Nothing proved a profile survives the **seating
path**: `server.gd` resolves the list, records it per player and hands it
to a brain across three seating doors, and every one of those steps could
drop it while every test stayed green and every AI quietly played the
same way. That is this project's declared-and-unread family with a
difficulty setting in it, and #119's finding — *the one configuration
that breaks a thing is very often the one nothing runs* — is the reason
to put the check in the harness that plays real matches rather than in a
new one nobody would run either.

It is deliberately hung on the **teamed** harness rather than on the
ladder: `test-ai-teams` already deals something per-seat, already runs a
mid-game scenario so it costs a minute rather than ten, and already fails
loudly. The ladder reports; this one asserts.

### Measured, 2026-08-18, after the rebase

`just test-ai-teams 1 60 4 2 clash cautious,relentless` — **60 s cap**,
ladder map, four AI across two sides:

| seat | profile | attacks | ally_objectives |
|---|---|---|---|
| 1000 | cautious | 3 | 0 |
| 1001 | relentless | 16 | 0 |
| 1002 | cautious | 3 | 0 |
| 1003 | relentless | 12 | 0 |

Clean verdict, both difficulties at the table, and the two behave
differently in a real teamed match rather than only in a unit test — the
regroup window is 6 thinks at 0.5 s against 12 at 2.0 s, so the harder
profile re-orders its army roughly eight times as often. **That is a
behaviour difference at a 60 s cap and not a strength result**; who wins
is still the open question clause 5 reserves.

**And the run that failed first is the more useful one.** On the recipe's
default `siege` scenario the same command reported *"2 AI seat-match(es)
never attacked anything"*: `siege` hands each seat TWO military squads,
`relentless` masses FOUR before it commits, and at that cap it never had
four. The harness gate is right — a seat that never committed proves
nothing about what it would have aimed at — and neither side should be
tuned to suit the other: `clash` starts five squads a seat, which clears
the highest threshold that ships. Recorded in the recipe's header,
because the next person to pair profiles will meet it. It is CLAUDE.md's
standing "when the opening changes, every timing tuned against the old
one is stale" rule arriving from a new direction: **the opening a HARNESS
hands out is an opening too.**

Both new gates were observed to fail before being trusted, by doctoring
that same log: stripping `profile=` gives *"4 AI seat-match(es) reported
no profile at all"*, and collapsing both difficulties to one gives
*"2 difficulties were dealt and only 1 reached the table"*. The
undoctored log passes.
