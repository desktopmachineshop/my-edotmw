# Decisions — one file per decision

This directory is the living decision log for my-edotmw, split from the
old single-file `game_design_decisions.md` (see
`D-20260816-decision-docs-split.md` for why). `CLAUDE.md` is the
condensed ground-rules summary of this directory — if the two ever
disagree, the decision file wins and `CLAUDE.md` needs updating.

Format per entry: **ID · Date · Status · Decision · Rationale · Rejected
alternatives · Consequences · Revisit trigger**.

Status is one of:

- **Accepted** — settled, build against it
- **Provisional** — best current call, but explicitly cheap to overturn;
  has a revisit trigger
- **Superseded by D-xxx** — kept for history, no longer in force

## Some of these entries describe code that is NOT on `main` yet

**`docs/plans/decision-manifest.md` says which, and which PR each one's
code is waiting in.** Read it before assuming an entry's code is in the
game.

Sixty-nine entries were landed ahead of their implementations (#364),
because after one cycle this directory was **70 entries behind** the open
PR queue and a session reading it had no way to know. That cost a real
duplication: two workers were told to share a design, could not see each
other's branches, and built it twice (gap I4,
`docs/plans/gap-assessment-2.md`).

The trade is deliberate and it inverts a familiar hazard. This project's
standing warning is that **a decision entry is not evidence the code does
what it says** (D-065, D-058, D-106) — and that warning was written for
entries describing code that had *stopped* being true. These describe
code that has not *arrived* yet, which is the safer direction only
because the manifest names them. If the manifest is ever out of date,
this paragraph is a lie; re-run
`docs/plans/decisions-ahead.gen.py` rather than trusting either.

## The rules (each bought with a real merge-train incident)

1. **One decision, one file.** A new decision is a NEW file in this
   directory. Never append to a shared file — two branches adding
   decisions must be unable to conflict textually. Amendments to an
   existing decision go inside that decision's own file, so a conflict
   there means two branches genuinely amended the same decision — a real
   disagreement git is right to surface.

2. **New IDs are `D-YYYYMMDD-slug`** — the date the decision is made
   plus a short kebab-case slug, e.g. `D-20260816-decision-docs-split`.
   The filename is `<ID>.md` and code comments cite the full ID. This
   replaces sequential `D-NNN` numbering, which required knowing the
   highest number in force — unknowable from any one branch. The old
   scheme produced at least eight renumber commits, a manual
   pre-assignment of IDs to in-flight PRs, and three IDs (D-087, D-096,
   D-097) that ended up assigned twice *and shipped that way*. If two
   same-day decisions collide on a slug, the collision is a visible
   add/add conflict on one small file, not a silent double-assignment.

3. **A RUNNING log is split by workstream, not kept in one file.**
   Rule 1 applies to logs as hard as it applies to decisions, and D-010's
   schema log was the one place still breaking it — six open PRs were
   appending to the same block at once (#366). Its log is now
   `D-010-schema-<workstream>.md`, one per workstream, with `D-010.md`
   as the index; a new workstream adds a FILE and one row to that table
   rather than a paragraph to somebody else's log.

   The file is chosen by WORKSTREAM, not by schema: a field naval adds
   to `UnitDef` is logged in the naval file. Splitting by schema would
   put naval, techs and a plain unit-stat change back in one file, which
   is the monolith with extra steps.

4. **Never renumber, never edit history in place.** Historical IDs
   D-001–D-108 are FROZEN — code, tests and the justfile cite them, and
   a renumber breaks every citation. Supersede instead, so the rationale
   trail survives. The duplicated legacy IDs stay duplicated; their
   filenames' slugs disambiguate.

5. **Not every cited ID has its own file.** Some legacy decisions
   (e.g. D-028–D-037) were recorded inside sibling entries — milestone
   exit-criteria blocks, amendments — and never had their own heading.
   `grep -rl "D-031" decisions/` finds where an ID actually lives; do
   not conclude a decision is missing because `ls` doesn't show it.

6. **A measurement is recorded in the decision that took it**, dated and
   with its caveats — never as a hand-maintained global count in a
   shared file. The merge train once inherited six rival test-count
   lines, one per branch, none right after the merge. Living prose says
   "run `just test-unit`" instead of quoting a number that is stale by
   construction on any merged tree.

7. **Milestone status lives in `docs/status/`**, one file per milestone
   or topic, imported into `CLAUDE.md`. Edit the file for the thing you
   touched; new standing rules that come out of a change belong in that
   change's decision file first, and in a status file only if agents
   need them loaded every session.

## Open questions

`OPEN-QUESTIONS.md` in this directory. If you need an answer to
something listed there to proceed, surface that rather than guessing —
these are marked open because they genuinely haven't been resolved, not
because they were forgotten.
