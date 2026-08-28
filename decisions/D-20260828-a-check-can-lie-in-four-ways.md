# D-20260828 · 2026-08-28 · Accepted — a check can lie in four ways, and the law only names one of them

**Decision:** this project's oldest testing law — **"observe every check
fail before it is trusted"** (D-022's audit block, M1) — is kept and
**generalised**. Observing a check fail is the only test of a check; the
law already says so. What it does not say is **what you must perturb**,
and for three of the four ways a check can lie, perturbing the CODE finds
nothing.

The four modes, each with the instance that produced it:

| mode | the check said | the real state |
|---|---|---|
| **fails open** | yes | it did not know |
| **cannot fail** | pass | it was asserting its own premise |
| **internally consistent about a world that did not happen** | a healthy run | a *different* run |
| **an unresolved value flowing downstream as a valid one** | zero, or nothing | unparseable |

**All four fail by saying nothing.** The system is silent, and silence
reads as fine. That is why four workers spent most of a day hunting a
refusal in a system whose failure mode was the absence of one.

## What to perturb, per mode

**1. Fails open — perturb the ARGUMENTS.** Omit one. Pass an empty
collection. Pass the default.

`AiNaval._worthwhile_land_elsewhere` read `if label >= land_sizes.size()
or land_sizes[label] >= min_landmass`, so a component whose size the
caller had not supplied answered **yes**. The filter existed, was
correct, and was reachable by OMISSION: `bot_naval.gd` calls
`needs_ships` with three of six arguments and sits one default away from
funding a fleet for every rock on the map. No test of the rule finds
this, because every test of the rule passes the sizes.

**2. Cannot fail — perturb the CODE.** This is the mode D-022's law
already names, and there the law works.

A caller-exists scan asserted the source contained
`_print_seat_landmasses(` — which the function's own **definition**
satisfies, so deleting the call site left it green. Its sibling asserted
a marker's banner rather than the keys its consumer actually greps. Both
were found by breaking the thing they guarded and watching them not fire.

**3. Internally consistent about a world that did not happen — perturb
the ENVIRONMENT.** Delete the file. Refuse the run. Kill the process.

`ai-ladder` and `test-load` write fixed artifact paths and truncate at
start, so a run that never starts leaves the PREVIOUS run's log in place
— and a stale log is not corrupt. Everything in it agrees with everything
else in it; it simply belongs to a different run. One worker read a 150 s
log as a 300 s run and was saved only by the server line reporting
`time=148.6s`. Another queued a run for 1300 s that never started and was
one grep from re-reporting an older result as fresh.

**Reading the duration the log CLAIMS is necessary and NOT sufficient**,
and that limit was found by watching this very rule fail an hour after
it was written. It catches a TRUNCATED run read as a full one — the
`148.6s`-against-300 case. It does NOT catch a COMPLETE OLDER run read
as a new one: a monitor reported a result whose log honestly said
`time=1200.0s` under the right cap, and the file was byte-identical to a
run banked ninety minutes earlier. A stale log is not merely consistent;
it can be consistent AND complete AND correct, about the wrong run.

What separates those two cases is not content at all — it is IDENTITY:
a timestamp, a byte-comparison against the previous copy, or a per-run
path. That is #389's actual fix, and it is why the duration check is a
stopgap rather than the answer.

**4. An unresolved value flowing downstream — perturb the INPUT TYPE.**
Hand it a non-number, a binary byte, an empty string.

`grep` prints `Binary file <path> matches` **instead of the matches** on
non-text input, **and exits 0 doing it**. Downstream, `[ "$x" -eq 0 ]` on
that string fails to stderr and returns non-zero — which inside an `if`
is indistinguishable from a legitimate "no". In `gate-check.sh` it was
worse than reading zero: the comparisons errored and the script ran on to
its **success** line, reporting "a landing happened" on a match with no
dock in it. **A gate that reports a pass on a log it cannot read is worse
than no gate.**

## Consequences

- **Every value parsed out of a log and then compared arithmetically is
  checked before it is trusted.** `gate-check.sh` uses `grep -a` and
  refuses any marker that is not digits, naming the key that was
  unreadable. Either fix alone closes one cause; the pair closes the
  class.
- **A test that constructs its own input is testing the constructor.**
  The sharpest instance: a fixture set `ClientState.terrain_passable`,
  which is assigned by `client.gd` and `bench_render.gd` and by nothing
  an AI runs. The test passed 36/36 while every AI in every match failed,
  because the constructed input did not merely duplicate production — it
  **contradicted** it.
- **A skip condition may never be computed by the thing under test.**
  `gate-check.sh naval` skipped on the AI's own `wants_navy`, which is
  what a correct decision and #351's defect both report. It keys on map
  topology now.
- **Prefer a deterministic fixture to a probable one.** Verifying #381's
  fix from a ladder run had a 34% chance of containing the case at all,
  so a green would have meant "the case did not arise". Perturbing the
  input makes the case certain.
- **A number without the frame it was taken in is not a measurement.**
  This project already says it twice — quote a µs figure with its squad
  count, a ladder result with its cap. Add: quote a pid with the tool
  that printed it (`ps -W` and `tasklist` disagree by design), and quote
  a log's numbers with the duration that log claims.

## Rejected

**A fifth mode for "the code was never called".** That is D-055's
declared-and-unread family and it has its own coverage; these four are
about a check that RUNS and lies.

**Making this a test rather than a rule.** No test can assert that a
future check was perturbed. The estate is otherwise excellent at exactly
the one mode it already names, and the gap was in what people knew to
try — which is a documentation problem, and documentation being behind
was itself a finding of this review.

## Credit

Co-derived with worker 88 across the naval chain's round-2 review. The
four-mode synthesis and the "all four fail by saying nothing" framing are
theirs; the per-mode perturbations and the instances come from both of
us. Worker 87 supplied the corollary below.

## Related

- **D-022**'s audit block — the law this extends.
- **D-20260828-you-are-most-dangerous-immediately-after-understanding**
  — WHEN the lie tends to get written: inside a fix, by the person who
  has just understood the mechanism.
- **D-20260828-read-what-a-metric-counts-not-what-it-is-called** —
  the companion. A check built on a mislabelled metric inherits the lie
  while doing nothing wrong itself, and that family is NOT perturbable,
  which is why it is a separate entry rather than a fifth mode here.
- **#389** (fixed artifact paths), **#390** (a native run outliving its
  slot), **#386** (a renderer-only field read by headless code).
- **Host load invalidates milliseconds, not strings** (worker 87). A
  correctness check is not a measurement, so it need not wait behind
  another worker's timing run — but it is not free either: a *heavy*
  correctness check still holds a memory admission. `--run-seconds` is
  SIMULATED time (`server.gd:774` compares against `_sim.time`), so a
  starved host changes a match's wall clock and not its verdict.
