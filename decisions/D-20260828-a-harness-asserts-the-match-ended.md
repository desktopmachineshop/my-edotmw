### D-20260828 · 2026-08-28 · Accepted — a harness asserts the match ENDED, not only that it started

**Decision:** Two changes to `just ai-ladder`, and one opt-in server flag
that only it passes:

1. **The ladder counts `MATCH_RESULT` lines against the number of matches
   ASKED for** and fails if any are missing, naming the seeds whose
   server exited non-zero. The per-server `|| true` is gone — the exit
   status is kept.
2. **The reported denominator is the asked-for count**, not the number of
   matches that produced a result.
3. **`--stop-after-match=<seconds>`** (server, default −1 = never): once
   the match is decided, stop that many simulated seconds later.
   `ai-ladder` passes 5; nothing else passes it at all.

The stop rule is a pure static `stop_reason(sim_time, run_seconds,
match_over_at, stop_after_match)` rather than a condition inside
`_process`.

**Rationale — the reporting half.** From #224: `just ai-ladder 3 600`
asked for three matches. One started, ran to ~140 s with 37 squads on the
board, and died printing nothing at all. The recipe reported:

    decided: 2 of 2   draws (time cap): 0

**"2 of 2" from a run of three**, with nothing anywhere saying a match had
gone missing. Every existing guard was blind to it by construction: the
started-check passed *because it did start*; the diagnostics grep found
nothing *because a killed process prints no ERROR*; `|| true` discarded
the exit code; and the denominator was counted from `MATCH_RESULT` lines,
so **a vanished match cannot appear in it**.

This is D-107 one layer in. That entry hardened this same recipe against
*"a harness reporting a game that was never played, in the vocabulary of
a game that was played badly"* — and it made the ladder assert that
matches **start**. Nothing asserted they **end**. The standing rule is
therefore worth stating in its general form:

> **Assert both ends.** A harness that checks a thing began, and reads
> its statistics off whatever survived, cannot distinguish "it finished"
> from "it stopped existing". The denominator must come from what was
> ASKED for, never from what came back.

**On the cause of the death itself: deliberately not diagnosed.** The
host was at ~1.2 GB free with 2.8 GB of swap in use and OOM-kills a
native Godot regularly (#153, and three of this session's own runs).
Whatever killed it, the ladder should not have called it a clean 2-of-2 —
which is the point, and the reason the failure message names 137 as
usually the OOM killer rather than a game defect.

**Rationale — the cost half.** A ladder match decided at 95 s of a 600 s
cap then simulated **505 further seconds** — 84% of that match's wall
clock — of the survivor gathering and producing against nobody, because
`--run-seconds` is checked against `_sim.time` and nothing consulted the
match phase. So `ai-ladder 3 600` cost a flat half hour however fast the
matches decided, which is a direct tax on how often anyone measures the
AI at all.

**Why the flag is opt-in rather than a behaviour change.** A decided match
is a perfectly ordinary thing for a HUMAN to be sitting in — a server
that quit out from under the victory screen would be this change escaping
the harness it was written for. And it keeps every number taken by
`test-load`, `test-scenario` and `test-ai-teams` comparable with what
they measured yesterday: those recipes pass no `--stop-after-match`, so
their windows are untouched. That is the standing "when the opening
changes, every timing tuned against the old one is stale" rule *avoided*
rather than paid.

**Rejected alternatives:**
- *Stopping at `MATCH_OVER` exactly* (rejected — the linger is nearly
  free and leaves room for the end-of-match broadcast and the replay
  flush to land before shutdown; 5 s of simulated time against a 600 s
  cap is not the cost worth optimising).
- *Making `--run-seconds` itself stop on a decided match* (rejected — it
  is the flag every other harness passes, so the change would reach all
  of them, and the ones with fog gates count events over a window they
  chose).
- *Leaving the awk denominator alone because the bash check now catches
  it first* (rejected — the printed line was wrong on its own terms, and
  a second reader of that awk would inherit the same lie. Both are cheap.)

**Consequences:** `ai-ladder` costs less wall clock the more decisive the
AI becomes, which is the right direction for a harness whose whole job is
measuring decisiveness — and it means a run's DURATION is no longer
predictable from `MATCHES x SECONDS`. Quote a ladder result with its cap
exactly as before; the cap is still what truncates an *undecided* match.

**Measured** (`just ai-ladder 2 120`, native, 2026-08-28): 2 of 2 matches
produced a result, `decided: 1 of 2   draws (time cap): 1`. Both paths
were exercised in the one run — match 1 was undecided and ran to its cap
(`reached 120.0s, stopping`), match 2 was decided and stopped early
(`MATCH_OVER winner=1000` at 99.7 s, then `match decided at 99.7s,
stopping 5.1s later`), saving 15 s of a 120 s cap. At #224's own figures
— decided at 95 s of a 600 s cap — the same rule saves ~500 s.

`just test-unit ladder_reports` — 8 tests, and **three were observed to
fail before being trusted** (D-022): making the match clause unreachable
reds the two stop tests and the precedence test, and reverting the awk
denominator reds the reporting test.

**A note for whoever edits the awk:** `awk 'prog' -v x=1 file` treats
`-v` as a FILENAME — the assignment must precede the program text. That
cost a rerun and is pinned by a test.

**Revisit trigger:** if a harness other than the ladder ever wants the
early stop, the flag is already there — but the moment TWO recipes pass
it, the windows they measure stop being comparable with their own
history, and that is a re-measurement rather than a flag flip.

---
