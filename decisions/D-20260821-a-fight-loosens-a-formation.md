# D-20260821 · A fight loosens a formation, and men adjust as men

**Status:** ACCEPTED — the owner's playtest reading of the surrounded
siege (2026-08-21): *"units still teleport and jump around... RTW
wouldn't snap units into formation once they were in a fight — they
needed to back off / be manually commanded back into formation once
loosened. Use unit-to-unit collision... have individual units adjust
rather than the whole squad snap or move."* **Amends:**
D-20260818-squads-separate-by-their-footprints (the ally half is
reverted, by the owner's call, in that file). **Extends:** D-006 as
amended (all three render mechanisms below live inside the amendment's
bounded/one-way/outcome-blind clauses), D-20260820 (whose static marks
this makes sticky).

## What was actually jumping, and the four answers

1. **The perimeter deal flipped frame to frame.** The one-point-per-man
   assignment was recomputed from the CURRENT slots every frame, and
   slots drift — so a man's mark hopped along the wall as he walked.
   The deal is CACHED per (squad, target, strength) now — per-soldier
   render memory, exactly what the amendment legalised — and only
   recomputed when the target or the strength actually changes. A held
   mark is a held man.
2. **Transitions over six units TELEPORTED.** `SNAP_DISTANCE` existed
   for seam crossings (a whole map width in one frame); a new
   engagement's far-side mark also cleared it and men blinked there.
   The threshold rises to 12 — every legitimate retarget WALKS, and a
   seam jump is still a hundred times the threshold.
3. **Whole squads snapped apart.** #104's ally rule displaced an
   arriving SQUAD by the sum of two footprints — the exact "whole squad
   snap or move" the owner named. Allies revert to D-060's original
   one-cell centre rule (enemies were always there); overlap is now
   resolved where the owner asked for it —
4. **— at the individual man.** The jostle goes CROSS-SQUAD: drawn men
   of overlapping squads push each other apart, each still bounded to
   `MAX_RENDER_DRIFT` of his own mark, using the previous frame's drawn
   positions of neighbours (one frame of lag, invisible at 7 px/man).
   Squads may stand on each other; their men sort it out, which is what
   a crowded battle looks like.

Re-forming stays a COMMAND: a marching squad leaves the engagement
path entirely (it always did), so ordering a loosened squad to move is
what re-forms it — the RTW grammar the owner described, delivered by
the mode boundary that already existed rather than a new rule.

## Rejected alternatives

- **Authoritative per-man collision.** Still D-006 clause 1's line:
  outcome-bearing per-soldier state reopens 40k-entities-vs-divergence,
  and nothing here needs it — the sim's cell-level rules stand.
- **Hysteresis timers on the engagement mode.** Tried on paper; the
  flip-jumps died with the cached deal and the walk threshold, and a
  timer would add invisible state for a symptom two purer fixes remove.
  Revisit if mode flicker is still visible in play.

## Revisit trigger

If cross-squad jostle at a big pile-up shows up in frame time, the
neighbour gather goes bucketed before the pass goes cheaper. If the
owner reports squads NOT re-forming crisply on command, the re-form
path gets its own explicit order handling rather than more stickiness.
