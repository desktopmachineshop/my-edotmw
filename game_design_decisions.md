# Game Design Decisions — moved to `decisions/`

The decision log lives in **`decisions/`, one file per decision** — this
stub exists only so the many `game_design_decisions.md D-xxx` citations
in code, tests and the justfile still point somewhere true.

- A legacy ID `D-NNN` lives at `decisions/D-NNN-<slug>.md` (entries that
  never had a title are just `decisions/D-NNN.md`). Some legacy IDs were
  recorded inside sibling entries and have no file of their own —
  `grep -rl "D-031" decisions/` finds where an ID actually lives.
- New decisions are new files named `D-YYYYMMDD-slug.md`. Never append
  to a shared file; never renumber. Full rules: `decisions/README.md`.
- Open questions: `decisions/OPEN-QUESTIONS.md`.
- Why the split: `decisions/D-20260816-decision-docs-split.md` — the old
  single file made every parallel merge conflict by construction.

Do not add entries to this file. It is deliberately small and stable so
it never conflicts again.
