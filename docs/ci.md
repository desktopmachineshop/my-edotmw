# CI — what runs, when, and the red we watched each gate produce

Added for #290. Three workflows in `.github/workflows/`.

**Read the observed-red table first.** It is the point of this document.
By this project's own law a check nobody has seen fail is vacuous
(D-022's audit block), and automation makes green cheaper to trust and no
cheaper to earn. Every gate below was deliberately broken, watched to go
red, and restored — and doing that found **four defects in the pipeline
itself**, one of which was a workflow reporting a green job over a red
suite.

## The second reason, which is not "catch what nobody ran"

#290 was filed on eleven incidents in which `main` sat red and an
unrelated worker eventually noticed. That is a real reason and it is the
weaker one.

> Beyond catching what nobody ran, CI is a reader who cannot inherit your
> derivation. An author cannot re-derive their own claim — they remember
> the derivation, so re-reading the field returns the meaning already in
> mind. CI has no memory to substitute.

(That framing is 88's, from a cluster of five wrong readings found in one
day — the write-up is on #350 and the entry is
`D-20260828-read-what-a-metric-counts-not-what-it-is-called`.)

The case for it from this file's own author, because it is the one that
should be least reassuring:

**`[exited with code 0]` was printed over a recipe that had failed with
exit code 1.** A backgrounded `just test-unit 2>&1 | tail` reported
success while the host gate had timed out after 1834 s and the suite had
never run at all. The pipe returns *`tail`'s* status. That is the
identical defect this workflow's `defaults.run.shell: bash` exists to fix
— written up thirty lines above, by the same person, hours earlier — and
it was not re-derived on sight. It was **recognised**: "exit 0, fine."
An exit code whose *name* says the pipeline succeeded and whose *value*
is the last element's status is
`read-what-a-metric-counts-not-what-it-is-called` with a shell builtin in
place of a game field.

### `pipefail` is necessary and not sufficient

The obvious lesson from that miss is "set `pipefail`", and it is half a lesson.
Measured in this shell rather than reasoned about — the four cases are 81's,
reproduced here before being written down:

```
set -o pipefail; false | tail        -> 1    pipefail catches the PIPE
                 false | tail        -> 0    the trap above
set -o pipefail; false; true | tail  -> 0    pipefail is BLIND to a CHAIN
set -eo pipefail; false; true | tail -> aborts at `false`
```

`pipefail` changes a **pipeline's** status to that of its first failing element.
It does nothing for a `;` **chain**, where `$?` is simply the last command's, so
an earlier failure is masked whatever `pipefail` says. `set -e`, or an explicit
check, covers that half. GitHub's `shell: bash` supplies **both** — it runs
`bash --noprofile --norc -eo pipefail {0}` — which is why this workflow's own
header says `-eo pipefail` and not `pipefail`.

Worth spelling out because **`set -o pipefail` reads like a complete answer and
is half of one**: a guard that is correct about the case it covers and silent
about the neighbouring one, which is the shape of everything else in this
section.

And the same witness applies again, one level down: the shell commands used to
investigate the incident above were written as
`set -o pipefail; git fetch …; …; cmd | tail` — the chain form, half-covered, by
the author of this paragraph while writing it.

### And the limit of the argument, which belongs beside it and not after it

**CI could not have caught that one.** It was not a defect in the tree;
it was a defect in how a run was read. No workflow sits between an author
and their own terminal.

So the rule the pipeline supports rather than replaces: **when no machine
sits between you and the claim, the second reader has to be the primary
data itself.** Read the log, not the status. The only reason that miss
was caught is that this project already requires it — "a green run is not
the same as a run that happened", which is D-022's audit block, and which
is older than any of this automation.

A corollary for anything with a `##[error]` or an `assert` message in it:
**a guard's message has to survive being skimmed by somebody who already
believes they know what it says.** Two of the day's five misreadings were
of guard text that was not unclear and was not being read — it was being
confirmed against what the reader already thought it said.

### "Is this failure mine?" — compare the FIGURES, not the test name

A PR's checks run on the **merge commit**, so a red base makes every open PR red
and hands each author a failure that is not theirs, carrying an instruction to
fix and push. That is not hypothetical: it happened to #273 and to this PR, and
in one case a documentation-only change was told to fix a combat regression.

There is a one-comparison answer, and it is free (88's, from the same day's
cluster):

> A failure inherited from your base reproduces its **numbers exactly** — the
> same data and the same seed produce the same arithmetic. A failure your change
> caused, or interacts with, will not.

#273's margins were **−0.67 and −0.68**, byte-identical to the run on `main`
fifteen minutes earlier. That settled the question before any bisect.

Three conditions, because the rule is sharp only inside them:

- **the base must itself be red on the same test.** If the base is green there
  are no base figures to match, and identical-to-nothing proves nothing;
- **the measurement must be deterministic.** Here it is by construction —
  `test_counters_are_felt.gd` sets `sim.combat_seed` and sweeps fixed seeds
  (`1000 + s * 7919`). Against a fixture that is timing- or host-dependent the
  comparison says nothing in either direction;
- **strength scales with how many independent figures match.** One margin
  agreeing to two decimals could be luck; two, from different pairings, is not.

And its limit, which its author states rather than leaving to be found: **it
works only where a failure carries a measurement.** A bare assertion — a missing
key, a vacuous-table guard — has no figures to compare, and there the question
falls back to reading the log and checking the base's own history.

## The workflows

| workflow | when | runtime | what it is for |
|---|---|---|---|
| `test-unit.yml` | every PR, every push to `main` | **native** | the eleven-incidents gate |
| `nightly.yml` | 03:00 UTC + dispatch | docker (load) / native (pictures) | `test-load 4 120` and the picture recipes |
| `docker-estate.yml` | Mondays 04:00 UTC + dispatch | **docker** | the #223 canary |

**Every scheduled workflow also has `workflow_dispatch`.** That is not
convenience. A schedule nobody can trigger is a schedule nobody can watch
fail, so a dispatch trigger is what makes the observed-red rule
satisfiable at all. Do not remove it.

### Why the PR gate is native

Two reasons and the second is the real one. A native run needs no image
build, and **this repo is private, so Actions minutes are billed**. And
the twelve shell-out tests (`test_gate_checks`, `test_recipe_args`,
`instance-id.sh`'s three) that fail under `EDOTMW_RUNTIME=native` on a
dev machine fail there because Godot's `OS.execute("bash", …)` resolves
to the **WSL relay on Windows**. On a Linux runner `bash` is bash.

That was a hypothesis when the workflow was written and it is now
measured: **1250/1250 under native on `ubuntu-latest`**, run
[33146509293], 3 min 19 s. The native gap is a *Windows* artifact, not a
native one.

If that ever stops being true this workflow goes red on exactly those
twelve, and the fix is one line — `EDOTMW_RUNTIME: docker` — which is
also measured green (1250/1250, and 1273/1273 with #273's explore tests).

### Why `bench-render` is NOT in the nightly

#290 asks for a nightly bench-render delta. **It is deliberately absent**,
and this is the one place the brief was not followed literally.

`bench-render` is native and needs a **real GPU** (D-014), and D-086's
standing rule is that *a frame time without hardware attached is not a
number anyone can use*. A GitHub-hosted runner has no GPU. Running it
there would publish an llvmpipe figure that **looks like a measurement
and is not** — a green verdict over a dead mechanism, which is the exact
failure this project keeps paying for, wearing the costume of diligence.

Three options were put to the worker who owns #286 (the render-baseline
mechanics):

1. a self-hosted runner on the owner's machine — rejected here: it
   collides with `host-budget.sh`/D-095 and that laptop is already
   saturated;
2. measure only what is honest without a GPU — **counts and work units,
   not milliseconds** (this project's own "publish milliseconds, gate on
   counts" rule);
3. keep `bench-render` a HUMAN recipe and have CI detect when
   `generated/`, the shipped map or the render path **changed** and say
   so loudly — which closes #286's actual complaint ("nothing triggers a
   bench-render pass when X changes") without pretending a GPU exists.

The seam agreed with the pipeline: **CI calls a recipe by name and
uploads its artifacts; the comparison lives in the recipe.** A delta rule
buried in YAML would be a second definition of what a regression is, and
this project has paid for second definitions repeatedly (D-058/D-065,
D-096). Until #286 lands that recipe, the nightly measures what it can
and this section records why the rest is missing.

## The observed red — every gate, with its run

The rule: perturb the thing the gate guards, watch it fail, restore.
Recorded here because CI is exactly where this gets skipped.

| # | gate | perturbation | run |
|---|---|---|---|
| 1 | `just test-unit` fails the job | reintroduced #215's `militia` fixture in `tests/test_combat.gd` | [33146995515] |
| 2 | a dirty tree fails the job | appended a line to `project.godot` before the check | [33147239818] |
| 3 | the nightly's `test-load` verdict fails the job | ran it at **duration 20**, too short to reach the fog gates | [33147951934] |
| 4 | the weekly import canary catches an OOM | set the `test` service's `mem_limit` to **512m** | [33147430956] |

**What each one printed**, quoted rather than linked. A GitHub run log
EXPIRES — 90 days by default, artifacts sooner — so a table of URLs is
evidence with a timer on it, and the whole point of this section is that
the evidence outlives the person who took it. The links are a
convenience; the text below is the record.

```text
1  Failing Tests 1 / Passing Tests 1249, job conclusion: failure
   [Failed]: Some civ should field the 'militia' archetype

2  just test-unit: success
   step "The tree is clean after a Godot recipe": failure
   ::error::A Godot recipe left the working tree dirty —
            see D-20260818-every-file-has-a-line-ending-rule
   project.godot | 1 +

3  test-load: bots exited with status 1
     (see artifacts/test-load-bots.log)
   error: recipe `test-load` failed with exit code 1

4  error: recipe `_import` failed with exit code 137
   ##[error]Process completed with exit code 137.
```

Gate 4 is worth reading twice: **the job built to catch #223 caught
#223**, reproducing its exit code from a memory ceiling, on a runner, in
a minute.

Gates 3 and 4 could not be observed through `workflow_dispatch`, because
that trigger only works once a workflow is on the default branch. They
were observed by giving both workflows a temporary `pull_request:`
trigger, which was removed before this branch was finished. **After
merge, use `workflow_dispatch` — that is what it is there for.**

### Observe the red on a SCRATCH branch, not on the PR branch

Learned immediately, and at someone else's expense. Observing these four
gates left four **deliberately red runs in this PR's own history**, and
an automated watcher promptly reported the PR as "CI is failing" and
linked run [33146995515] — which is gate 1's evidence, doing exactly what
it was made to do. The PR was green at HEAD throughout.

That will happen to **every** PR that follows this project's law, because
the law requires producing a red run and CI history is per branch. So:

> **Push perturbations to a throwaway branch** (`<your-branch>/observe`,
> no PR), record the run URLs here, and let the PR branch carry only the
> real work.

A run URL is permanent and does not care which branch produced it, so the
evidence is exactly as good and nobody has to explain a red badge to a
robot. If you do observe on the PR branch anyway, say so in the PR body
with the run ids, so a reviewer can tell intent from breakage.

## Four defects this exercise found in the pipeline itself

Every one was invisible to a green badge and found only by insisting on
the red.

- **A failing suite reported a GREEN job.** `just test-unit 2>&1 | tee
  log` returns *tee's* exit status, and GitHub's default shell has `-e`
  but **not** `pipefail`. Run [33146765563] reported `Failing Tests 1`
  and `conclusion: success`. This is D-022's audit block rebuilt in CI —
  `test-load` once reported clean while every bot had exited non-zero.
  Fixed with `defaults.run.shell: bash` (which is `bash -eo pipefail`) in
  all three workflows. **If you add a workflow, keep that block.**
- **A reporting step gated the job.** When `test-load` died before
  writing its log, the "Publish the verdict" step's `sed` exited 2 under
  `pipefail` and failed *beside* the real failure, burying which was
  which. Reporting is not a gate; both summary steps now tolerate a
  missing log.
- **`docker-compose.yml` pinned `cpus: 4` and a hosted runner has 2.**
  Docker refuses outright — *"range of CPUs is from 0.01 to 2.00"* — so
  `just up` could not start and **no docker recipe could run on CI at
  all**. This is the CPU half of #223's runner-sizing question and nobody
  had asked it. The quota is now `${EDOTMW_CPUS_SERVER:-4}` /
  `${EDOTMW_CPUS_BOTS:-2}`, parameterised exactly like the published host
  port and defaulting to precisely what it was, so nothing local changes.
- **`test-client` cannot reach its own gate on a 2-CPU runner at the
  default 90 s.** It reported `conceal_events=0 reveal_events=0` while
  passing locally: the verdict gates on a bot wandering out of vision,
  which happens on the MATCH's clock while the capture window is fixed
  wall clock, so slower hardware eats the margin. The weekly runs it at
  **180 s**. Lengthening the run rather than weakening the check is the
  direction this project already took when the tooled gatherer pushed the
  same gate over its margin (60 → 90) — this is that rule applied to the
  **hardware** instead of to an asset.

And one process note, paid for in a wasted run: **two perturbations at
once destroy attribution.** The 512m ceiling and the duration-20 nightly
were pushed together, and the nightly then failed with exit 137 from the
*memory* perturbation rather than from its verdict. Perturb one gate at a
time.

## An unexpected benefit: CI is a quieter instrument than the laptop

Not a design goal, and worth recording because this project has thrown
away three milestones' worth of figures to host contention.

The nightly's own first green run [33148263012] reported **133.22
µs/squad at 33 squads, worst tick 22.2 ms, 0 dropped ticks, 0 desyncs
over 472 state-hash checks**. Two `test-load 4 120` runs taken on the
owner's laptop the same day, on the same code, reported **144.26 and
195.23 µs/squad at 32 squads** with worst ticks of **69.4 ms and
196.5 ms** — a 35% spread from contention alone.

A CI runner is a dedicated machine running nothing else. That does not
make it the right instrument for everything (it has 2 CPUs and no GPU),
but for a per-squad cost or a worst tick it is **less noisy than the
machine this project has been measuring on**. Quote a figure with where
it was taken, as ever.

## Runner sizing (#223)

Measured rather than assumed, which was #223's substantive objection.

| | measured | limit |
|---|---|---|
| `_import` peak | **1.052 GiB** | `test` service, 2g |
| `test-unit` peak | **987 MiB** | same |
| runner memory | 16 GB | — |
| runner CPUs | **2** | the constraint that actually bit |

Memory fits with room. **CPU did not**, and that is the half nobody had
looked at. The revisit trigger for memory is ~1.6 GiB — `generated/` is
what grows, so a new archetype's VAT is the event to watch.

## Keeping the actions current

The `actions/*` versions are deliberately on their current majors
(`checkout@v7`, `cache@v6`, `upload-artifact@v7`). The first runs of this
pipeline used `@v4` and every one of them printed:

```
Node.js 20 is deprecated. The following actions target Node.js 20 but are
being forced to run on Node.js 24
```

A forced runtime is a deprecation with a date on it, and a brand-new
pipeline shipping known future breakage is the sort of thing that later
reads as "CI broke and nobody knows why". Bumped while the pipeline was
still being watched, which is the cheapest moment it will ever be.

## Cost

The repo is **private**, so minutes are billed. Three levers are already
applied and should not be quietly removed:

- **`concurrency` with `cancel-in-progress`** on the PR gate — a branch
  pushed three times in a minute costs one run, not three. The same
  reasoning `host-gate.sh` applies to the laptop, applied to the bill.
- **`tools/` and the Godot import are cached.** The import cache is
  correctness-neutral: Godot's own import tracking is md5-based, so an
  unchanged file is skipped because its hash matches, not because a key
  did.
- **The nightly skips when `main` has not moved in 24 h.** Re-measuring
  an unchanged tree burns billed minutes to learn nothing.
  `workflow_dispatch` always forces it.

Rough shape at the time of writing: the PR gate is **~3–4 minutes**, the
nightly ~15–25, the weekly ~20–30.

## Two things the pipeline deliberately does not do

Both from this project's own record.

- **It does not gate on wall-clock timings.** D-106's amendment records a
  "cost does not scale with map size" test going red on a loaded host
  with nothing wrong, two commits after the warning was written.
  Milliseconds are **published** to the run summary; the gates are on
  counts and exit codes.
- **It does not assert about a picture.** The preview recipes fail on
  their own terms (nothing drawn, a palette naming a model that did not
  load, two byte-identical frames) and their output is uploaded for a
  human to glance at. Every one of the last three milestones' worst
  defects — soldiers inside terrain, forests as ranks and files, tools
  rendering bright red, the minimap crop — was invisible to every counter
  and visible in a frame. The images are produced so a person can look,
  not so a robot can pronounce.

## What is deliberately NOT on the PR gate

`test-scenario siege 4 15` is in the gap assessment's proposed matrix and
is not here. It needs docker, so it would add an image build to the
gate every PR pays for, and the orchestrator's brief for #290 is
`test-unit` on PR and push. It runs inside the nightly's coverage via
`test-load`, which makes the same `gate-check.sh` comparisons
(D-20260818-the-fast-loop-carries-the-gate). Add it if PR-level
integration coverage turns out to be worth the minutes — that is a cost
decision, not a technical one.

[33146509293]: https://github.com/desktopmachineshop/my-edotmw/actions/runs/33146509293
[33146765563]: https://github.com/desktopmachineshop/my-edotmw/actions/runs/33146765563
[33146995515]: https://github.com/desktopmachineshop/my-edotmw/actions/runs/33146995515
[33147239818]: https://github.com/desktopmachineshop/my-edotmw/actions/runs/33147239818
[33147430956]: https://github.com/desktopmachineshop/my-edotmw/actions/runs/33147430956
[33147951934]: https://github.com/desktopmachineshop/my-edotmw/actions/runs/33147951934
[33148263012]: https://github.com/desktopmachineshop/my-edotmw/actions/runs/33148263012
