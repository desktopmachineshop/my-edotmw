# CI — what runs, when, and the red we watched each gate produce

Added for #290. Three workflows in `.github/workflows/`.

**Read the observed-red table first.** It is the point of this document.
By this project's own law a check nobody has seen fail is vacuous
(D-022's audit block), and automation makes green cheaper to trust and no
cheaper to earn. Every gate below was deliberately broken, watched to go
red, and restored — and doing that found **four defects in the pipeline
itself**, one of which was a workflow reporting a green job over a red
suite.

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

| # | gate | perturbation | observed | run |
|---|---|---|---|---|
| 1 | `just test-unit` fails the job | reintroduced #215's `militia` fixture in `tests/test_combat.gd` | `Failing Tests 1`, job **failure** | [33146995515] |
| 2 | a dirty tree fails the job | appended a line to `project.godot` before the check | `test-unit` green, **"The tree is clean after a Godot recipe" failed** | [33147239818] |
| 3 | the nightly's `test-load` verdict fails the job | ran it at **duration 20**, too short to reach the fog gates | `test-load: bots exited with status 1`, job **failure** | [33147951934] |
| 4 | the weekly import canary catches an OOM | set the `test` service's `mem_limit` to **512m** | ``error: recipe `_import` failed with exit code 137`` — the exact signature of #223 | [33147430956] |

Gate 4 is worth reading twice: **the job built to catch #223 caught
#223**, reproducing its exit code from a memory ceiling, on a runner, in
a minute.

Gates 3 and 4 could not be observed through `workflow_dispatch`, because
that trigger only works once a workflow is on the default branch. They
were observed by giving both workflows a temporary `pull_request:`
trigger, which was removed before this branch was finished. **After
merge, use `workflow_dispatch` — that is what it is there for.**

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
