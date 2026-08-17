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
