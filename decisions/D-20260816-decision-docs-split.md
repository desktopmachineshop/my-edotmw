### D-20260816-decision-docs-split · 2026-08-16 · Accepted — decisions are one file each, and IDs are date+slug

**Decision:** The single-file decision log and CLAUDE.md's monolithic
status narrative are split so that parallel branches stop conflicting by
construction:

- Every decision entry moved verbatim into `decisions/<ID>-<slug>.md`,
  one file each. `game_design_decisions.md` remains as a stub pointer so
  the ~200 existing citations in code, tests and the justfile still
  resolve. The split was verified byte-identical: concatenating the new
  files in original order reproduces the old section exactly.
- New decisions are new files named `D-YYYYMMDD-slug` — an ID that is
  unique the moment it is written, with no central counter to race on.
  Legacy IDs D-001–D-108 are frozen, never renumbered.
- CLAUDE.md's `## Current status` narrative (1,004 of its 1,660 lines)
  moved verbatim into `docs/status/*.md`, one file per milestone or
  topic, pulled back into CLAUDE.md via `@docs/status/<file>` imports —
  so every session still loads the same guidance, but a branch touching
  fog and a branch touching spawns now edit different files.
- The full rules live in `decisions/README.md`.

**Rationale:** Nearly every parallel merge conflicted on these two
files, and the causes were structural, not bad luck. (1) Sequential
D-NNN IDs were allocated by reading the file, which cannot see branches
in flight: the history holds eight renumber commits, a coordinator
manually pre-assigning D-099–D-106 to seven open PRs, one decision
renumbered twice, and three IDs (D-087, D-096, D-097) shipped
double-assigned anyway. D-107's own numbering note concluded "the
highest heading in this file has never been the highest number in
force". Renumbering is worse than the conflicts: code comments cite
D-numbers, so every renumber risks doc/code drift. (2) "New entries go
at the top of section 1" made every pair of parallel decision entries
collide at the same anchor lines of an 8,300-line file. (3) The status
narrative was rewritten by nearly every branch and embeds numbers that
are stale by definition on a merged tree — the merge train found "six
rival test-count lines, one per branch, none of them right".

**Rejected alternatives:**

- **`merge=union` in `.gitattributes`** — silently drops conflict
  markers and interleaves prose; the 2026-08-16 merge train tried
  union-merging and its own commit records the human cleanup it needed.
- **Append-at-bottom instead of top** — both branches still insert at
  the same anchor; it only makes union-merge slightly less wrong.
- **Issue/PR numbers as decision IDs** — centrally allocated and
  collision-free, but not all work has an issue, and a PR number does
  not exist when the decision is written. Date+slug needs no external
  allocator at all.
- **A committed index of decisions** — a new hand-maintained shared
  file is a new conflict magnet and a new stale-file class.
  `ls decisions/` and grep are the index.
- **Scrubbing stale numbers out of the moved prose** — editorial rework
  of 9,000 lines risks mangling guidance for zero conflict benefit; the
  no-global-counts rule applies going forward instead.

**Consequences:** Doc conflicts now only occur when two branches amend
the SAME decision or the same status topic — which is a genuine
disagreement worth a human look. The 463 KB monolith is gone; agents
grep `decisions/` instead of paging one file. Existing citations keep
working through the stub and frozen IDs. Two formats coexist (D-NNN
legacy, D-YYYYMMDD-slug new); that is deliberate — uniformity would
cost either a mass renumber or a revived central counter.

**Revisit trigger:** If two same-day decisions collide on a slug more
than rarely, lengthen the slug convention. If `@import` handling of
`docs/status/` files ever stops loading them into sessions, fold the
status files back into CLAUDE.md before agents start working without
the guidance.
