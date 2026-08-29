# D-20260828 · The import's ceiling is the whole docker estate's ceiling

**Status:** ACCEPTED. **Closes:** #223 (and #153, the same fault filed
earlier). **Relates to:** D-014 (the containerised runtime),
D-20260818-dev-work-is-admitted-against-a-host-budget (the class costs
this was feared to invalidate), D-081 (`generated/` is committed).

## The fault

`just _import` under `EDOTMW_RUNTIME=docker` was reliably SIGKILLed
(exit 137), and **every docker recipe depends on `_import`** — so
`test-unit`, `test-load`, `test-scenario` and `test-client` were all
down at once. The project's own gate could not be run at all; every
worker was falling back to `EDOTMW_RUNTIME=native`, which has a
12-test shell-out gap and no `test-load` path whatever.

Reproduced here before changing anything, sampling the container every
15 s:

```
45.33MiB / 1GiB
579.2MiB / 1GiB
579.0MiB / 1GiB
578.8MiB / 1GiB
937.9MiB / 1GiB
gone —  error: recipe `_import` failed with exit code 137
```

It died at 33%, reimporting **`p39-resource-clearance-before.png`** — a
documentation screenshot in `docs/playtest/`.

## The decision

Two changes, and **both are load-bearing** — which was measured, not
assumed.

1. **`docs/.gdignore`.** Nothing under `docs/` is a game resource:
   `grep -rn "res://docs"` over every `.gd`, `.tscn`, `.tres` and `.py`
   returns nothing, and the only mentions of `docs/playtest` in the
   tree are prose in two test headers. 19 MB of screenshots were being
   opened, decoded and re-encoded on every import for nobody. The 42
   orphaned `.import` files go with it. This is the trick
   `bootstrap-art` already uses for `tools/`.
2. **The `test` service's `mem_limit` 1g -> 2g**, matching `server` and
   `client-test`, which were already 2g.

## Why the .gdignore alone is not enough — the measurement

After excluding `docs/`, the import completes, and its peak is
**1.052 GiB**. That is *above* the old 1 GiB ceiling. Had the ignore
landed on its own the import would still have been killed, a little
later and with a different file named in the log — which would have
read as a second, unrelated bug.

| | before | after |
|---|---|---|
| import outcome | SIGKILL at 33% | completes |
| import peak | 1.000 GiB (the ceiling) | 1.052 GiB |
| import steps | full walk | 102 |
| `test-unit` peak | never reached | 987 MiB |

## The host budget does NOT change, and that was the open question

#223's substantive objection was that `host-budget.sh`'s class costs
(`medium 1300`, `heavy 1500`) were calibrated against these limits, so
doubling one without re-measuring would let the gate admit jobs the
machine cannot hold — the exact failure that decision exists to
prevent.

Re-measured rather than argued: the import peaks at **1.052 GiB** and
the suite at **987 MiB**, both inside `medium`'s 1300 MB. So the class
cost is still right and is deliberately left alone.

**A `mem_limit` is a ceiling, not a reservation.** The steady figure
through the whole run is ~580 MiB; the container only approaches the
limit during the reimport burst. Raising a ceiling does not change what
a job costs the host — which is why the budget is calibrated against
*measured* WSL VM growth (`+1,246 MB` for `test-unit`) and not against
compose limits. The two numbers were never the same quantity; #223 was
right to ask, and the answer is that they are independent.

## What this cost, and the rule

**The thing that broke the entire docker estate was documentation.**
`generated/` grew and `docs/playtest/` grew, and neither growth was
visible to anything: no test measures import memory, `git` reports a
committed PNG as an ordinary file, and the failure surfaced three
milestones later as `exit 137` in a recipe that mentions neither.

> **A committed asset that nothing loads still costs every import.**
> Anything added under a directory Godot walks is charged to every
> docker recipe in the project, forever, whether or not a single line
> of code refers to it.

`docs/` is now fenced off structurally, so adding the next fifty
screenshots is free.

## Rejected

- **Raising `medium` to cover 2 GB.** It would have been the honest
  move if the measurement had asked for it. It does not, and inflating
  a class cost on a laptop that sits at 1.5-2.4 GB free would idle
  every other agent for nothing.
- **`.gdignore` without the limit change.** Measured insufficient — see
  the table. This is the one alternative that looks obviously
  sufficient and is not.
- **Un-committing `generated/`.** D-081 requires a fresh clone to play
  without installing anything; that is not up for renegotiation here.

## Revisit trigger

If the import peak passes ~1.6 GiB the ceiling needs re-examining
*and* the `medium` class cost genuinely does too — at that point they
stop being independent. `generated/` is the thing that grows, so a new
archetype's VAT is the event to watch.
