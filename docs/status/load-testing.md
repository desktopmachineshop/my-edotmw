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

| tree | duration | conceal | reveal | verdict |
|---|---|---|---|---|
| `main` alone | 150 s | 16 | **1** | clean, by one event |
| `main` alone | 210 s | 15 | **0** | FAIL |
| branch | 150 s | 15 | **0** | FAIL |
| branch | 150 s (repeat) | 15 | **0** | FAIL |
| branch | 210 s | 15 | **0** | FAIL |

Four of five fail, on BOTH trees, with `main`'s 210 s run numerically
identical to the branch's. **So a `reveal_events=0` failure right now is
not yours** — that is **issue #69**, which reports the same thing on the
previous base too. Check against `main` in its own worktree before
spending an hour on your diff. Squads are still being CONCEALED 15 times
a run and `ghosts_peak` is 15; it is the return leg that has stopped
happening, and `bot_client.gd`'s scripted phases are the suspect rather
than fog itself (the same counter reaches 11 in a `test-client` scenario
run).

**A single green run is not a measurement, and this file has just been
caught by that.** It said "`4 150` is clean" on the strength of one run
that reported `reveal_events=10`; four subsequent runs across two trees
report 0. If you are about to write a duration into this file, run it
more than once.

`4 120` is stale regardless: three runs there reported `conceal_events=2`,
which is the fog half barely running at all.

- **`4 300` measured clean on the new default map, 2026-08-17**, one run:
  0 desyncs, 0 dropped ticks, worst tick 44.9 ms, `conceal_events=63
  reveal_events=63 casualties_applied=36 nodes_felled=135`. Note
  `reveal_events` — the gate that has been failing intermittently on
  `main` (issue #69) — is now satisfied by a factor of 60, because a
  bigger map means squads actually leave and re-enter vision. One run is
  not a measurement (see above), but it is the number to start from.
- **The default map doubled on 2026-08-17 (84×96 → 168×194), so every
  duration on this page is now a floor rather than a recommendation.**
  Marching time scales with LINEAR size, not area, so the ~150 s that was
  marginal before is roughly 300 s of equivalent marching now. The gates
  that get harder are the contact-dependent ones —
  `casualties_applied`, `conceal_events`, `reveal_events`; the fog
  coverage gates get *easier*, because more of a bigger map goes unseen.
  Re-measure before writing a number here, and read the "a single green
  run is not a measurement" paragraph above first.
- Spawns are far apart even on the old map, so four armies cannot reach
  each other quickly. A short run fails with `casualties_applied=0
  conceal_events=0 reveal_events=0` — the verdict correctly reporting
  that combat and fog never happened rather than passing vacuously.
- **A reveal needs a conceal AND a return.** `reveal_events` counts a
  squad re-entering vision after leaving it, so it is the LAST of the fog
  criteria to be satisfied and the first to fail. It is also the one
  currently failing on `main` — see the table above before reading a zero
  there as a fault in your own change.
- **A town hall takes 40 seconds and the founding party is spent on it
  (D-031), so a player owns no soldiers until production finishes.** Any
  run shorter than ~90 s reports `soldiers=0` and fails, and that is the
  check working, not a bug. `4 40` was the recommendation here for a
  whole milestone and could not have passed since D-031 landed;
  `test-client`'s 15 s default had the same problem. **When the opening
  changes, every timing tuned against the old one is stale** — that
  applies to the load test, the capture scenario, and any scripted bot
  phase.
