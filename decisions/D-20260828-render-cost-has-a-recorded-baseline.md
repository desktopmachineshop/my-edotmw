### D-20260828 · 2026-08-28 · Accepted — render cost has a recorded baseline, and counts gate while milliseconds report

**Decision:** the client render benchmark writes its run as data,
`bench/baseline.json` records one such run with the tree it was measured
against, and `BenchBaseline` compares the two. **A deterministic COUNT
that moves is a failure; a millisecond that moves is a report.** A
FINGERPRINT of the map, the roster, the built assets and the render path
decides which of those two a difference even is: numbers taken against a
different tree are stale, not regressed.

Three recipes, and they are three different questions:

| recipe | needs | question | exit |
|---|---|---|---|
| `just bench-stale [STRICT]` | nothing (headless, seconds) | is the recorded number about THIS tree? | 0, or 1 with `STRICT=1` |
| `just bench-check [COUNTS] [FRAMES] [STRICT]` | a real GPU (D-014) | did a gated count move? | **1** if a count moved |
| `just bench-record [COUNTS] [FRAMES]` | a real GPU | record it, naming the adapter | — |

From #286. **#229 was a 3x client render regression found months late by
a human playing the game**, and #240 then found the benchmark had not
measured the client at all since the RTW programme. Both are one absence:
there was no recorded number for anything to be compared against, and
nothing said a measurement was owed when the map ladder moved.

## Why counts gate and milliseconds do not

**Given the same map, roster, viewport and render path, a run counts the
same things every time.** How many soldiers the roster fields, how many
survive culling and LOD, how many draw calls reach the GPU, how many
squads are fighting — all deterministic, and all of them move exactly
when the world or the render path moves.

Milliseconds do not. **In the very first pair of runs taken with this
mechanism — same build, same machine, minutes apart — the wall clock
moved 13.2% while every gated count was identical.** That is the whole
argument in one observation, and it is the rule the gap assessment
(PR #265 §5.2) states for CI in as many words: *publish milliseconds,
gate on counts*. This project has already gone red on a wall-clock gate
with nothing wrong — D-106's amendment, written two commits before it
happened.

So the report prints every millisecond delta, shouts (`TIME!`) past 15%,
and decides nothing. A ten-times-slower frame passes this check and says
so loudly; the thing that fails it is a count nobody meant to move.

## Why a fingerprint, and why stale outranks changed

A count that moved because somebody added a unit is not a regression. It
is a baseline that needs re-recording. Without that distinction the first
roster change would report a fault, and the second would teach everyone
to ignore the check — D-022's audit block arriving from the other
direction: not a check that passes vacuously, but one that fails so
uselessly it gets muted.

`fingerprint()` hashes the map's dimensions, the roster (ids, squad
sizes, model ids), `generated/manifest.json`, Godot's version, and the
**source of the render path itself** — a named list of files in
`RENDER_PATH_SOURCES`. Change any of them and the recorded numbers are
about a different renderer. `stale` therefore outranks `changed`, and the
report says which part moved.

**That list is data, and it can go stale in the other direction**: a
module renamed out from under it silently stops being watched, which is
the declared-and-unread family aimed at a config file. A test asserts
every path in it exists; nothing can assert that it is complete.

## What runs where, and the interface CI depends on (#290)

`bench-check` needs a real GPU and takes minutes; `bench-stale` needs
nothing and takes seconds. That is not a compromise, it is the honest
split — and it makes the per-PR half possible at all:

- **On a pull request: `just bench-stale`.** It cannot tell you the
  client got slower. It CAN tell you that nobody has measured since the
  map, the roster, the assets or the render path last moved, which is
  precisely what #229 lacked. Non-strict by default, so it reports
  without blocking a PR that legitimately touches `formation.gd`.
- **Nightly, on hardware somebody can name: `just bench-check`**, whose
  exit code is a genuine gate on counts, plus `--strict=1` on the stale
  half if the nightly wants an owed measurement to be a failure.

The contract #290 may rely on, and which this entry is the place to
change:

- `bench_render.gd --json=<res:// path>` writes the run;
  `artifacts/bench-latest.json` is what `bench-check` uses and is the
  artifact to upload.
- `bench/baseline.json` is committed, is format `version 1`, and names
  the `adapter` it came from.
- Exit codes: **1** = a gated count moved (or, with `STRICT=1`, the
  baseline is stale). **0** = everything else, including "no baseline
  yet" and "ten times slower".
- The report is one block on stdout beginning `bench-check:` and ending
  with a one-line verdict, so a log scan can find it without parsing.

**A run recorded headless is refused.** Godot's dummy display makes the
cull pass everything and reports zero draw calls — measured: 250 squads
draws 155 of them with a GPU and 250 headless. The committed baseline
carries `headless: false` and a test asserts it.

## Rejected alternatives

- **Gating on milliseconds with a tolerance.** Tried in spirit and
  refused on the first pair of runs: ±13% on identical code. Any
  tolerance wide enough to survive this host is wide enough to miss the
  kind of regression #229 was.
- **Normalising times against a reference workload in the same run.**
  Attractive and unfalsifiable: it assumes the reference and the
  measured work scale together on unknown hardware, and when it says
  "1.4x" nobody can tell whether that is the build or the assumption.
- **A baseline per adapter, all committed.** Every machine that ran it
  would add a file, and the counts — the half that actually gates — are
  identical in all of them. One baseline, one adapter named, times
  compared only when the adapter matches.
- **Making `bench-stale` strict by default.** It would fail every PR
  touching a render file until somebody re-recorded on hardware they may
  not have. Loud by default, blocking on request.

## Consequences

- **`bench-record` is a deliberate human act** and says so: it overwrites
  a committed file with numbers from one machine. Re-recording to make a
  red check green is how this becomes a rubber stamp, and the recipe
  prints that warning rather than trusting it to be remembered.
- The first baseline is **Intel(R) Iris(R) Xe Graphics**, 250 and 1,000
  squads, 90 frames, the shipped 168×194 map. Every number in it is
  integrated graphics — D-085's discrete-GPU trigger is still armed, and
  a discrete re-record would replace this file wholesale rather than
  adding to it.
- `bench-check` at 250 and 1,000 squads costs about **four minutes** on
  this hardware, which is why it is nightly rather than per-PR.

## Revisit trigger

A count that is deterministic today becoming host-dependent — the
viewport size is the one to watch, since the cull reads it and CI
runners will not share this machine's window. If that happens the fix is
to pin the viewport in the benchmark, not to widen the gate.

---

**Amendment, 2026-08-28 — one slot per ADAPTER, because a single file made
recording on a second machine destructive** (#285).

`bench/baseline.json` was one file. A frame time is a statement about
hardware — this entry's own first rule — so recording on different
hardware would have **overwritten the numbers every figure in
`docs/status/client-render.md` is quoted against**, silently, in a commit
whose message says "recorded". #285 books scarce hardware time on a
discrete GPU against exactly that file, so the trap was live rather than
hypothetical.

Baselines are now `bench/baseline-<adapter slug>.json`, and the existing
file **moved** into the Intel Iris Xe slot rather than being re-recorded:
a pure rename, 0 insertions, 0 deletions, so the history those figures
are compared against is the same bytes.

- **`bench-record` no longer names the file.** It passes `--record=1` and
  the RUN derives the slot from the adapter it just measured on, because
  that is the only thing that knows. A recipe naming the file would be
  naming hardware it has not asked about.
- **`bench-check` compares a run against ITS OWN slot**, chosen from the
  adapter the run reports. Where no slot matches — every first run on new
  hardware, #285 included — **the counts still gate**, against whichever
  slot exists, because a count is a property of the map, the roster and
  the render path and has nothing to do with the GPU. The milliseconds
  are not compared and the report says so, twice: once for the missing
  slot and once from `compare`'s existing cross-hardware note.
- **`bench-stale` reads every slot**, since staleness is a question about
  the TREE: one machine's numbers can predate a roster change while
  another's do not, and reading a single file would call the tree fresh
  on the strength of whichever it happened to open.
- **The slug is ugly and injective on purpose.** "Intel(R) Iris(R) Xe
  Graphics" becomes `intel-r-iris-r-xe-graphics`; stripping `(R)` would
  be a rule about one vendor's punctuation, and two adapters differing
  only in what it stripped would then share a slot — the failure this
  exists to prevent, arriving through the fix. A test enumerates six real
  adapter names and asserts no two collide.

**This closes the trap structurally rather than by a flag somebody has to
remember** — a different adapter physically cannot write another's file —
which is the same argument #359 settled for the artifact-writer rule.

Observed to fail before being trusted, all three:

| perturbation | what happened |
|---|---|
| a slot whose FILENAME disagrees with its own `adapter` field | red: *"must be the slot its own adapter name resolves to"* |
| a run from hardware with no slot | counts compared and gated, milliseconds refused, both said out loud |
| the same run with one COUNT moved | **exit 1** — foreign hardware does not weaken the gate |

And the end-to-end one: `just bench-record 100 30` wrote
`bench/baseline-intel-r-iris-r-xe-graphics.json` and touched nothing
else. (That temporary recording was restored to the committed bytes
afterwards — a 100-squad, 30-frame run is not a baseline.)
