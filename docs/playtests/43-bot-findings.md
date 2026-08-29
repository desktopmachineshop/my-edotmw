# #43 — a full match vs AI opponents, with pacing observations

Bot-observation pass, 2026-08-27, worktree `ao/my-edotmw-84/root`
(instance `ao-my-edotmw-84-root`, port 27542). Native runtime — the
docker `test` service's 1 GB `mem_limit` OOM-killed a cold import twice
on a host that was down to ~1.2 GB free, so `just bootstrap` +
`EDOTMW_RUNTIME=native` was used throughout. Recorded because it changes
nothing about what was measured and everything about reproducing it.

**Ticket status: LEFT OPEN.** The pacing half is discharged; every pass
criterion that is about *watching* an AI still needs the owner.

---

## Checklist, classified

| # | Ticket item | Class | Outcome |
|---|---|---|---|
| 1 | Play a full match to a decision; note first AI attack | bot-observable (as AI-vs-AI) | done — see below |
| 2 | Watch an AI base: expand, gather all kinds, mixed army, rebuild | **needs a human** | not covered — requires watching a base under fog |
| 3 | AI armies in the field: attack-move, retreat, no pathological behaviour | **needs a human** | partially — idling/no-op behaviour showed up in the logs, see #217 |
| 4 | Note what the AI never does (walls) | bot-observable | confirmed: no AI builds or uses walls; `ai_player.gd` has no wall path |
| 5 | Wall-clock to a decided match and what decided it | bot-observable | done |
| P1 | AI plays by the same rules (no fog-cheating, free resources) | structural | D-051's `LoopbackPeer` gives the AI byte-identical packets; nothing here contradicts it, and nothing here *proves* it either |
| P2 | AI is beatable but not trivially — real pressure at least once | **needs a human** | not covered |
| P3 | No AI stalls into doing nothing for minutes | bot-observable | **FAILED — see #217** |
| P4 | Match reaches a decision without the human manufacturing it | bot-observable | yes, but for the wrong reason in 2 of 3 matches |
| P5 | Pacing recorded for D-056 | bot-observable | done |

---

## What was run

```
EDOTMW_RUNTIME=native ./tools/just.exe ai-ladder 3 600
```

the invocation the ticket asks for. Log: `docs/playtests/logs/ai-ladder.log`.

**The ticket's stated baseline is void.** It expects "~2 of 3 decided at a
600 s cap" and a first attack around 195 s, quoting the 2026-08-16 ladder.
Those numbers were measured against `legion` and `northmen`, which were
**deleted on 2026-08-26** when the six fantasy civs landed (#191,
`docs/status/fantasy-civs.md`). This is the first ladder run on the
current roster, as that file predicted would be needed.

## Result, quoted with its cap

```
ai-ladder: --- results over 3 matches ---
  decided: 2 of 2   draws (time cap): 0
  player 1000  civ=emberdeep   wins=2  squads_peak~17.0 workers_peak~13.5
               buildings~1.5  first_attack~152s with ~34 men
  player 1001  civ=gildedreach wins=0  squads_peak~2.0  workers_peak~1.0
               buildings~0.0  first_attack=never
```

**Read almost none of that as a strength result.** Three things make it
uninterpretable, and finding them is most of this pass's value.

### 1. Two of the three matches were played by one side only (#217)

In seeds 2 and 3, `gildedreach`'s AI never founded a town centre. Its
opening build was refused because a resource node sits on its spawn cell,
and `AiPlayer._found_town()` retries **the same constant cell** every 5 s
forever. `buildings=0`, `attacks=0`, `first_attack=never`,
`squads_peak=2` (its two opening squads) — then eliminated at ~95 s.

Filed as **#217**, with a deterministic one-command repro. The AI already
picks a *different* site when a **barracks** is refused; only the town
centre path retries a constant.

A match won that way is reported by the ladder as a decisive win with
plausible winner statistics. So `emberdeep 2, gildedreach 0` means
"gildedreach was never in two of the games", not "emberdeep is stronger".

### 2. One of the three matches vanished and was reported as clean (#224)

Match 1 (seed 1) — the one where **both** AIs founded normally — started,
ran to ~140 s with 37 squads on the board, and then ended with no output
at all: no stop line, no `MATCH_RESULT`, no `AI_STATS`. The recipe printed
`decided: 2 of 2` for a run of 3.

Filed as **#224**. The cause of the death is unattributed and may well be
host memory pressure rather than a game defect; the *reporting* is the
filed part. D-107 made the ladder assert matches **start**; nothing
asserts they **finish**.

### 3. `--ai=2` only ever seats two of the six civs

Every match seated `1000=emberdeep, 1001=gildedreach` — the roster's first
two in id order, on every seed. So the current ladder cannot produce a
strength ordering across the six civs however many matches it runs.
`docs/status/fantasy-civs.md` names that ordering as "the number to take
next"; it needs `--ai=6`, or per-seat civ selection, to be takeable at all.

---

## Pacing observations for D-056

From the one match that ran with two live opponents (seed 3, 600 s cap):

| measure | value |
|---|---|
| first AI attack | **152.2 s**, with 34 men |
| attacks in the match | 5 |
| winner's peak squads / workers / buildings | 22 / 16 / 2 |
| time to a decision | ~95 s in the two broken matches; the healthy one hit the 600 s cap undecided by elimination |
| worst tick | 19.8 ms of D-020's 100 ms, 0 over budget (2016-cell ladder map) |

**Dead air is real and measurable.** In seed 2 the match was decided at
95 s and the server simulated the remaining **505 s — 84% of the match's
wall clock** — with the survivor gathering against nobody.
`--run-seconds` is checked against `_sim.time` only and never consults the
match phase (server.gd:720). Also filed in **#224**.

Against D-056's 1–2 hour target: nothing here contradicts the standing
finding that matches are far too short, and the one clean data point
(first attack at 152 s) is in line with the old ~171–195 s figures. But
with 2 of 3 matches broken and 1 of 3 vanished, **this run cannot support
a pacing claim beyond that**.

---

## What still needs the owner

Everything that is about *watching*, plus one thing that is about playing
against it:

1. **P2 — is the AI beatable but not trivial?** Requires a human playing
   `quick-test` against 3 AI. Nothing bot-side can rate "real pressure".
2. **Step 2 — does an AI base behave?** Expansion, gathering all four
   kinds, mixed army composition, rebuilding after a raid. Visible only by
   scouting one during a match.
3. **Step 3 — do AI armies look sane in the field?** Idling stacks and
   suicide trickles are the named risks; the logs cannot distinguish "an
   army standing still with a plan" from "an army stuck".
4. **P1 — no observed fog-cheating.** Structurally sound by D-051, and the
   ticket asks for it to be *observed*.

**Do #217 first.** Two of three matches were unplayable because of it, so
any human session run before it is fixed has a good chance of facing an
opponent that never builds anything — which would read as "the AI is
trivially beatable" and be nothing of the kind.

---

## Artifacts

| file | what |
|---|---|
| `docs/playtests/logs/ai-ladder.log` | the full `ai-ladder 3 600` run |
| `docs/playtests/logs/repro-ai-seed2.log` | the 150 s single-seed repro behind #217 |

## Filed from this ticket

- **#217** — AI never founds if its spawn cell holds a resource node
- **#224** — ai-ladder reports a vanished match as "decided: 2 of 2"; server runs the full cap after `MATCH_OVER`
