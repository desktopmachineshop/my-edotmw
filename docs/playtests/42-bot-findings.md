# #42 — match lifecycle: victory, elimination, leave-to-lobby

Bot-observation pass, 2026-08-27, worktree `ao/my-edotmw-84/root`.
Drives the real `MatchState.update()` — the function the server calls
every tick to decide elimination and victory — over a real `SquadSim` and
`BuildingSim`, plus the real transitions `return_to_lobby()` /
`start_match()`.

**Ticket status: LEFT OPEN.** The elimination rule and the phase
transitions are discharged; everything about what a *player is told*, and
the no-humans shutdown, needs the owner.

**Overlap declared, not touched:** #157 (building state desyncs in the
second match after returning to the lobby) is owned by another worker.
Cross-referenced below; deliberately not investigated or fixed here.

---

## Checklist, classified

| # | Ticket item | Class | Outcome |
|---|---|---|---|
| 1 | Play to a WIN; note what the game tells you and what you can do after | **needs a human** | server-side transition verified only |
| 2 | Play to a LOSS; same observations | **needs a human** | as above |
| 3 | ESC → leave to lobby mid-match; start a fresh match without restarting | server-side **PASS** / **UI needs a human** | |
| 4 | After leaving as the only human, the match/server does not run on | **needs a human / a live server** | not covered — see below |
| 5 | Rematch starts clean, no leakage | server-side **PASS** / **client state is #157** | |
| P1 | Win and loss clearly announced, at the right moment, to the right player | **needs a human** | the standing values are correct server-side |
| P2 | Elimination matches the rule | bot-observable | **PASS** |
| P3 | Leave-to-lobby works from any match state, including while dead | server-side **PASS** / **UI needs a human** | |
| P4 | No-humans shuts the match down | **needs a human** | not covered |
| P5 | Rematch starts clean | server-side **PASS**, client-side is **#157** | |

---

## P2. The elimination rule — PASS in all four states

`playtest_obs/obs_lifecycle.gd`, log `docs/playtests/logs/obs42-lifecycle.log`.
D-033: a player is out with **no living squads AND no living buildings**.
All four combinations, driven through the real `MatchState.update()`:

```
squads=true  buildings=true  -> eliminated=false  standing=PLAYING
squads=true  buildings=false -> eliminated=false  standing=PLAYING
squads=false buildings=true  -> eliminated=false  standing=PLAYING
squads=false buildings=false -> eliminated=true   standing=ELIMINATED
```

Exactly the rule as written — and the two "one of the two survives" rows
are the ones that matter, since they are what lets a razed player resettle
(`docs/status/the-opening.md`).

**Observed live as well.** In real AI matches
(`docs/playtests/logs/ai-ladder.log`, `docs/playtests/logs/repro-ai-seed2.log`) the server
printed `MATCH_ELIMINATED player=1001` followed by `MATCH_OVER
winner=1000`, and the scoreboard's `standing` field is populated
(D-102's one thing that had to go on the wire). So elimination fires in a
real match, not only in a fixture.

## 3, 5 / P3, P5. Lobby round trip — PASS server-side

```
start  phase=RUNNING players=2 seats=2 admin=1
return_to_lobby() -> true,  phase now LOBBY,  winner reset to -1
start_match()     -> true,  phase now RUNNING
is_running=true,  eliminated flags cleared: p1=false p2=false
```

RUNNING → LOBBY → RUNNING with the winner and both elimination flags
reset. `tests/test_return_to_lobby.gd` covers the client-side node
lifetime half (the milestone of matches with no terrain, D-075's
2026-08-16 amendment).

**This does not clear #157.** That bug is the *client's* carried-over
`known_buildings` set — D-030's ever-revealed set, which `_return_to_lobby`
drops the `visible` baseline for and not `known_buildings`, against a
client whose building ids restart at 0 (`docs/status/sandbox.md`). Nothing
here touches it, by instruction.

## The victory fixture, and why its result is not reported as one

The harness also staged a razing-to-victory. It **did not** resolve: the
victim's town centre finished at full health and every attacker died.
That turned out to be the same effect as **#227** — the victim had a
defending squad standing on the attackers' approach, which absorbs the
assault entirely while the town centre shoots for free. It is a finding
about siege, filed under #39, and says nothing about the lifecycle rules.

Recorded because the raw output (`finished at never, winner=-1`) reads
like a victory-detection failure and is not one. Victory detection is
demonstrated instead by the live AI matches above.

---

## What still needs the owner — most of this ticket

1. **Steps 1 and 2 — win and loss on screen.** What is announced, when,
   to whom, and what you can do afterwards. Nothing bot-side can rate an
   announcement.
2. **Step 3's UI half** — the ESC menu's leave-to-lobby, including
   **while dead**, which P3 calls out specifically.
3. **Step 4 / P4 — no-humans shuts the match down (D-075).** Not covered
   at all here: it needs a real server with a real human client that then
   disconnects. The AI-only ladder runs have no humans by construction, so
   they cannot exercise the rule.
4. **Step 5's client half** — resources, squads and fog not leaking into
   the rematch. Expect **#157** to show up here; if you see building
   desyncs in the second match, that is it, and it is owned elsewhere.

A note on sequencing: `docs/status/sandbox.md` records that the sandbox
panel's **Regen map** button makes #157 reproducible in one click. If you
are playtesting this ticket before #157 is fixed, that is the fastest way
to confirm you are looking at the known bug rather than a new one.

---

## Artifacts

| file | what |
|---|---|
| `docs/playtests/logs/obs42-lifecycle.log` | elimination table, victory fixture, lobby round trip |
| `docs/playtests/logs/ai-ladder.log`, `docs/playtests/logs/repro-ai-seed2.log` | live `MATCH_ELIMINATED` / `MATCH_OVER` |
| `playtest_obs/obs_lifecycle.gd` | the harness |

## Filed from this ticket

None. The lifecycle rules that are bot-observable all passed; #157
already covers the known rematch defect.
