# D-20260818 · 2026-08-18 · Accepted — allied AI is exercised by something

**Decision:** a teamed all-AI match can be run from a command line, the
seats' sides reach the *simulation* on every path a match can start from,
and there is one harness whose job is to fail when an AI marches on a
friend. Four clauses:

1. **`--ai-teams=T` on the server.** The `--ai=N` seats are dealt across
   T sides, and the side goes on at **seating time**, through
   `MatchState.add_ai_player(player, civ, team)`. `set_team` stays the
   lobby's door and stays admin-only.
2. **`_sim.teams = _match.team_map()` on BOTH start paths**, through one
   function, `Server._hand_teams_to_sim()`. It prints `SIM_TEAMS` from
   `_sim.teams` itself, so a harness asking "did teams reach the
   simulation" reads the simulation.
3. **`just test-ai-teams` is the harness.** Real server, real AI clients,
   a scenario world (D-098), several seeds. It fails on an attack
   objective that landed on a friend — and equally on any of the four
   ways that finding could be vacuous.
4. **`just ai-ladder` takes a `TEAMS` argument, defaulting to 0.** The
   default run is the free-for-all every ladder number so far was
   measured on, so those numbers stay comparable (D-054), and
   `MATCH_RESULT` carries `team=` because a TEAM can win.

## Rationale

#83 was an AI that read "not mine" as "hostile", so an allied AI parked
its whole army on its teammate's town centre and milled there for the
rest of the match. It shipped for a milestone.
D-20260817-an-ai-knows-who-its-allies-are fixed the targeting and said
plainly what it had not fixed: **allied AI behaviour was exercised by
nothing.** This entry is that gap (#119), and it is the more interesting
half, because the fix was five lines and the gap was three separate
absences stacked on each other:

- **No door.** `MatchState.set_team` is lobby-and-admin-only by design,
  and a headless run has no admin. So a teamed AI match could not be
  asked for at all. `just ai-ladder` being a free-for-all was not a
  choice about what to measure; it was the only thing that could be
  expressed.
- **No handover.** Teams reached `SquadSim.teams` in exactly one place —
  inside `_on_match_started`, the lobby path. `_note_match_started`, the
  `--lobby=0` path that the ladder, `test-load` and `test-scenario` all
  run, did not. Dormant, because nothing without a lobby had ever had a
  team to hand over. **Adding clause 1 alone is what makes it live**, and
  the failure it produces is worse than #83's: every seat list and every
  client agrees two players are allies while the simulation has never
  heard of it, so allies share no sight (D-050) and shoot each other
  (D-024).
- **No instrument.** Nothing anywhere counted an AI aiming at a friend,
  so even a teamed match played by hand would have looked fine in the
  log.

Measured, rather than argued: with the handover removed and everything
else in place (a one-line experiment, 60 s, 4 seats), `allies_seen`
across the four seats fell from ~12.0/10.0/13.7/9.3 to 2.0/3.0/3.0/3.0.
That is D-050's shared vision not happening, in an ostensibly teamed
match, with nothing in the log saying so.

## The acceptance test, which is the point of the entry

CLAUDE.md's standing rule is that **every check must be observed to fail
before it is trusted**, and a harness built for a bug that has already
been fixed is exactly where that rule earns its keep. So the #83 fix was
reverted locally — `_enemy_target`'s two scans put back to the ownership
tests they had before — and the harness run against it.

| tree | matches | ally objectives | seats offending | verdict |
|---|---|---|---|---|
| #83 fix REVERTED | 1 × 90 s | 1 | 1 of 4 | FAILED |
| #83 fix REVERTED | 3 × 90 s | **13** | 2 of 4 | **FAILED** |
| #83 fix restored | 3 × 90 s | **0** | 0 of 4 | clean |
| teams handover removed | 1 × 60 s | 0 | — | **FAILED** (no `SIM_TEAMS`) |

The same worlds, the same seeds, the same `allies_seen` — 12.0/10.0/
13.7/9.3 against 12.0/9.7/13.3/9.3 — so the two runs differ in the
finding and in nothing else.

**The first row is why the harness plays several seeds.** One seed found
one offending seat of four. The bug fires when an ALLY is the nearest
thing an AI knows about, and spawn points are scattered at
`min_spawn_spacing` (D-039), so which neighbour a seat gets is a property
of the SEED, not of the seating. A harness that catches its bug in a
quarter of cases is not a harness. Note also that both offending seats
were on the same side: with the fix reverted, seats 1000 and 1002 offend
and 1001/1003 never do, which is placement, not asymmetry in the code.

## What the harness asserts, and why each line is there

An `ally_objectives=0` is worth nothing on its own — it is what a
free-for-all reports, what a match that never started reports, and what
an AI that never attacked reports. So the verdict fails on all of these
first:

| gate | the vacuity it closes |
|---|---|
| N matches left the lobby | the ladder reported three milestones of unplayed matches as draws (D-107) |
| `SIM_TEAMS` in every match, T sides, none on 0 | the simulation, not the seat list, is what has to know |
| every seat saw an ally, **per match** | an AI with no teammate in sight cannot march on one |
| every seat attacked, **per match** | an AI that picked no objective cannot have picked a bad one |
| `ally_objectives == 0` | the finding |

`AiPlayer.ally_objectives` judges the ORDER, not the decision: it asks
what stands on the cell the army was sent to (`_allies_only_at`), and
counts it when something friendly does and nothing hostile does. A check
that re-ran `_hostile` would be green exactly whenever `_hostile` was
green, which is the thing under test. It covers both sites #83 had to fix
— `_enemy_target` and the scouting fallback — because both end in an
ordered cell.

It is a SCENARIO run (D-098) because #83 needs an AI with an army, a
teammate with a base, and both in sight: the real opening spends ~170 s
producing that. `siege` hands every seat a town centre, a tower and two
militia on the first tick, so three seeded matches cost ~5 minutes
instead of ~30.

## Rejected alternatives

- **A teamed variant of `just ai-ladder` and nothing else** — the shape
  #83 suggested. The ladder is a MEASUREMENT: it wants a long cap, many
  matches and averages, and the answer to "did an AI attack its ally" is
  not an average. It would also have taken 20 minutes to answer a
  question a 90-second scenario answers. The ladder does gain `TEAMS` and
  does fail on an ally objective — it should not report an economy curve
  for an army parked on a teammate — but the harness is separate.
- **A GUT test playing a teamed match through `ScenarioWorld`.** Fast,
  and blind in the one place that mattered: `_sim.teams` is assigned in
  `server.gd`, which a GUT test does not run. A test that hands the sim
  its own teams proves the sim, not the server — the "necessary but not
  sufficient" note under D-006 again.
- **Assert `ally_objectives` inside `_enemy_target`.** The instrument
  would then share the code path it measures, which is precisely the
  defect #83's own metric had (`peak_enemy_buildings_known` counted an
  ally's town as an enemy base found).
- **Deal sides in blocks (seats 0,1 vs 2,3) so allies are adjacent.**
  Adjacency in the SEAT LIST is not adjacency on the MAP — spawn points
  are scattered (D-039), so neither dealing makes an ally reliably
  nearest. Several seeds is the honest answer; block dealing would have
  looked like one and been a coincidence.
- **Make `--ai-teams` set the teams after seating, next to the other
  match setup.** Seating the last seat is what starts the match
  (`_start_if_ready`), so the side would be set on a seat whose
  `team_map()` had already gone to the simulation. It is a parameter of
  seating for that reason.

## Consequences

- **Nothing changes in a free-for-all.** `--ai-teams` defaults to 0,
  `team_map()` is then all zeros, and `SquadSim.are_allied` reads 0 as
  free-for-all — identical to the empty dictionary the no-lobby path had.
  `just ai-ladder` with no TEAMS argument runs exactly the match it ran
  before, so D-054's recorded numbers stay comparable.
- **The dormant gap is closed on every no-lobby path, not just the
  ladder's.** `test-load` and `test-scenario` go through
  `_note_match_started` too; they have no teams today, and if they ever
  get one it will now arrive.
- `AI_STATS` grows `team=`, `allies_seen=` and `ally_objectives=`;
  `MATCH_RESULT` grows `team=`. Both are parsed by recipes, and
  `tests/test_allied_ai_is_exercised.gd` pins the field names for that
  reason.
- The ladder reports per-team wins when teams are in play. Without it a
  2v2 credits one of two allies with a victory both won, and a side that
  took every match reads as a 1-in-4 win rate.
- `tests/test_allied_ai_is_exercised.gd` — 14 tests: the seating door,
  the ordering (a side is on the seat before the match starts), a team of
  survivors ending the match, both start paths handing teams over (read
  out of `server.gd`'s source, the D-106 "assert the caller exists"
  instrument, because `server.gd` needs a socket), and the instrument's
  own true/false cases including "an ally standing on an enemy's hall is
  not an offence".
- Cost: `just test-ai-teams` is ~5 minutes at its defaults (3 × 90 s).
  It is not on any other recipe's path.

## What this does NOT fix

- **`client.gd`'s human click targeting has the same "not mine means
  hostile" shape** (two sites, noted in #119). Much less serious — the
  server refuses a forced target on an ally, and a human can see who they
  clicked — so it is a UI affordance offering an illegal order, not a
  livelock. Separate.
- **No AI builds or uses walls** (D-076), so `ai-ladder` still cannot
  exercise that feature. Same family as this one, still open.
- The harness proves an AI does not AIM at a friend. It does not prove
  two allied AI cooperate — there is no cooperation in `ai_player.gd` to
  test.

## Revisit trigger

An AI gaining any behaviour that depends on having an ally — a shared
objective, a defensive commitment to a teammate's base, a rally on an
ally's front. The harness's gates are about not attacking a friend, which
is the floor; the first cooperative behaviour is what makes it the wrong
question. Also: `test-load` or `test-scenario` acquiring teams, which is
when clause 2 stops being a guard on a path nobody uses.
