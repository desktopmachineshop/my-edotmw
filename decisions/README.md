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

3. **Never renumber, never edit history in place.** Historical IDs
   D-001–D-108 are FROZEN — code, tests and the justfile cite them, and
   a renumber breaks every citation. Supersede instead, so the rationale
   trail survives. The duplicated legacy IDs stay duplicated; their
   filenames' slugs disambiguate.

4. **Not every cited ID has its own file.** Some legacy decisions
   (e.g. D-028–D-037) were recorded inside sibling entries — milestone
   exit-criteria blocks, amendments — and never had their own heading.
   `grep -rl "D-031" decisions/` finds where an ID actually lives; do
   not conclude a decision is missing because `ls` doesn't show it.

5. **A measurement is recorded in the decision that took it**, dated and
   with its caveats — never as a hand-maintained global count in a
   shared file. The merge train once inherited six rival test-count
   lines, one per branch, none right after the merge. Living prose says
   "run `just test-unit`" instead of quoting a number that is stale by
   construction on any merged tree.

6. **Milestone status lives in `docs/status/`**, one file per milestone
   or topic, imported into `CLAUDE.md`. Edit the file for the thing you
   touched; new standing rules that come out of a change belong in that
   change's decision file first, and in a status file only if agents
   need them loaded every session.

## Open questions

`OPEN-QUESTIONS.md` in this directory. If you need an answer to
something listed there to proceed, surface that rather than guessing —
these are marked open because they genuinely haven't been resolved, not
because they were forgotten.
