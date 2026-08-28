### D-20260828 · 2026-08-28 · Accepted — artifacts are written where the build can write

**Decision:** every file this project PRODUCES — replays, capture
screenshots, preview renders, the terrain preview PNG — is written
through **`ArtifactPath`**, which resolves one base: `res://artifacts`
when the process is running from a checkout, `user://artifacts` when it
is an exported build. A path handed in from outside (a recipe's
`--out=res://artifacts/…`, the server's port-stamped replay name) is
REBASED rather than rejected, so nothing outside this file needs to learn
a second vocabulary.

From issue #201, found on the first ever exported build (#178):

```
ERROR: Could not create directory: 'res://artifacts'.
ERROR: ReplayLog: could not create res://artifacts (error 2)
server: listening on 0.0.0.0:24395 — map default, tick 10 Hz
```

The match then played through to a decided end. `res://` is a read-only
virtual filesystem inside the `.pck`, so **an exported build has no
replays at all** — against D-016, which makes replays the curve log and
the primary desync-forensics tool, and against D-094 criterion 1, which
wants a Steam build people can report faults from.

**Rationale.** #201 named the choice: a checkout keeps `res://artifacts`
and only a build redirects, or everything moves to `user://` and ~10
recipes learn where that is. The first is taken, for three reasons.

- **Every recipe, doc and habit keeps working.** `just replay-info`,
  `just test-client`'s screenshot, `artifacts/models-godot.png`, the
  `.gitignore` entry and every "LOOK AT artifacts/…" line in the justfile
  are unchanged, and unchanged *by construction* rather than by having
  been checked: `rebase` is the identity function when the base is
  `res://artifacts`.
- **The branch is in ONE function**, not at ten call sites. The
  alternative's "one path everywhere" is only one path if every writer
  remembers it; this project's most-repeated defect is a rule that is
  written down and not read.
- **A dev artifact and a shipped artifact want different homes anyway.**
  A preview PNG that a human is told to look at belongs beside the
  checkout that made it. A replay from a player's machine belongs
  somewhere the OS says an application may write.

**Why the feature tag and not a probe.** `OS.has_feature("template")` is
exactly the question: the editor binary running a checkout reports
"editor", an exported game reports "template". Probing by attempting a
write would answer the same question more slowly, and would also answer
"redirect" for a checkout somebody made read-only — a different fault,
which deserves to be reported rather than silently worked around.

**Rejected alternatives.**

- *Move everything to `user://`.* Honest, and it costs every recipe a
  `godot --headless --path . --eval` or an OS-specific path guess to find
  its own output. The instrument this project relies on most is a human
  looking at a PNG; making that PNG hard to find is a real cost paid
  against a purely aesthetic gain.
- *Leave the previews on `res://` and fix only `replay_log.gd`.* That is
  the smallest change and it re-creates the class: the next writer added
  is written the way the writers around it are written. The scanning test
  below only means something if the rule is uniform.
- *Fall back to `user://` when a `res://` write fails.* Two mechanisms
  for one question, and the fallback would fire for read-only checkouts
  and full disks too, hiding both.

**Consequences.**

- `ReplayLog.open_for_write` resolves its own path and REPORTS it — the
  server now prints `server: recording replay to <path> (<real path>)`,
  and prints `server: NOT recording a replay` with the error when it
  cannot, at start-up and again in the shutdown summary. #201's real
  complaint is not the missing directory, it is that **nothing later said
  the recording never happened**; a `push_error` in a release build goes
  nowhere a player can see.
- `tests/test_artifact_path.gd` scans every `.gd` for a `res://artifacts`
  literal and fails unless that file also names `ArtifactPath`. This is
  D-106's caller-exists test, and it carries D-106's own caveat: it
  covers the writers it can see, and a writer that builds its path from
  pieces is invisible to it.
- The `user://` half **cannot be exercised from the editor binary**, so
  the pure mapping (`rebase`) is tested directly against both bases
  rather than through `resolve()`. A rule whose interesting case nothing
  runs is this project's oldest trap; splitting the pure half out is the
  cheapest honest answer available short of exporting a build in CI.
- Nothing on the wire, in the simulation or in the recipes changes. A
  checkout writes byte-identical files to byte-identical paths.

**Revisit trigger.** An exported build that needs to write something a
player is meant to FIND (a saved game — D-092 says there are none; a log
bundle for a bug report; a screenshot key). That is a different question
— where a user's files live and how they are surfaced in-game — and it
should be decided as one rather than by extending this mapping.
