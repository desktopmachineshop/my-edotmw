# D-20260818 · dev work is admitted against a host budget

**Date:** 2026-08-18
**Status:** Provisional — **BUILT.** The exit criteria below were written
before the code, in the M10 pattern, and the record of which of them are
discharged is at the bottom of this entry rather than assumed. The
measurements are recorded here because a measurement belongs in the
decision that took it (`decisions/README.md` rule 5).

## Context

**D-095 made parallel agents unable to COLLIDE. It did not make them
unable to STARVE each other.** Every checkout derives its own compose
project, container names and host UDP port, so `just down` here cannot
remove anybody else's containers — and that is the whole of the
isolation. There is no mechanism anywhere that limits how many agents run
a Godot workload at the same moment, and the machine they share is one
laptop.

The symptom is already written down, three times, unnamed. The user
memory note `native-runtime-fallback` records "Docker Desktop dies under
parallel agents". `docs/status/m6.md` records worst-tick figures thrown
away because "the host was building containers throughout".
`docs/status/terrain.md` records a `bench-render` absolute that moved
52.1 ms → 181.1 ms on an unchanged build over three hours of a loaded
host. Three milestones have already paid for host contention in discarded
measurements, and none of them named the cause as a thing to fix.

## What the machine actually is (measured 2026-08-18)

| | |
|---|---|
| CPU | 13th Gen Intel Core i5-13500H — 12 cores / 16 threads |
| RAM | **15.6 GB** |
| GPU | Intel Iris Xe (integrated; the only GPU, and D-014 makes it the client's) |
| Disk | 261 GB free of 475 GB |

**Disk is not a constraint and should not be optimised.** 51 worktrees,
245 docker images and 205 build-cache entries together account for
684.8 MB of images (layers are shared, so the per-instance image name
D-095 mints is nearly free) plus 1.24 GB of build cache. **RAM is the
constraint.** Nothing else came close.

## What is resident before any dev work runs

Read from AO's own session table and the process list, same day:

- **22 live sessions** — 1 orchestrator, 21 workers, of which **4 active
  and 17 idle**. (47 further worker sessions are terminated.)
- **22 `claude` processes: 3.62 GB**, mean 164 MB, min 76 MB, max 470 MB
- 21 `node` processes: 505 MB · `agent-orchestrator` + `ao`: 867 MB ·
  Chrome/Edge/WebView2: ~2.4 GB · idle WSL VM (`vmmemWSL`): 1.8–2.0 GB
- **available memory sat between 1,495 MB and 2,433 MB for the entire
  profiling session** — the machine is at 85–90% memory utilisation
  *before any recipe is run at all*.

**An idle session costs what an active one costs**, ~190 MB (claude +
node), whether it is working or has been parked for a day. The 17 idle
workers are ~3.2 GB — **more than the entire free pool**. That is not a
pipeline problem and the pipeline cannot fix it; it is recorded here
because it sets the budget everything else has to live inside.

## What one dev activity costs

Sampled at 1.5 s intervals with a system-wide counter walk
(`host-sample.ps1`, committed with this entry so the numbers above have a
reproducible instrument; exit criterion 7 wraps it in a recipe). `WSL Δ`
is the growth of the `vmmemWSL` working set over the run, which is what a
docker recipe actually costs the host: the container's own footprint is
small and the VM's is not.

| activity | wall | CPU mean / max | avail RAM min | WSL Δ | class |
|---|---|---|---|---|---|
| baseline, no dev work | — | 14.0% / 28% | 1,735 MB | — | — |
| `test-unit` (890 tests, 56 scripts) | **162 s** (73.3 s inside GUT) | 14.0% / 41% | 1,546 MB | **+1,246 MB** | medium |
| `test-load 4 60` | **68 s** | 18.3% / **98%** | 1,495 MB | **+1,240 MB** | heavy |
| `gen-terrain-preview` (warm cache) | **8 s** (4.8 s meshing, 143 chunks) | 12.8% / 41% | 1,638 MB | +586 MB | light |

Caveats, all of which matter more than the third digit:

- **Every absolute here was taken on a host running 22 agent sessions.**
  That is deliberate — they are the numbers dev work actually gets on
  this machine — but they are not clean-room figures and must not be
  compared with any taken on a quiet host.
- **The resident floor MOVED mid-session** (29 → 22 `claude` processes,
  −1.2 GB) **and available memory FELL anyway** (2,364 → 2,083 MB mean),
  because the WSL VM absorbed what was freed. *Freed memory never became
  headroom.* This is the strongest single argument against a fixed
  "max N jobs" cap: the floor such a cap would be sized against does not
  hold still.
- `test-load 4 60` **exited 1** with `conceal_events=0 reveal_events=0`.
  That is the documented duration gate working, not a regression:
  `docs/status/load-testing.md` says a run under ~90 s fails by
  construction and the current map wants `4 300`. 60 s was chosen to
  price the cost class cheaply; a real `4 300` costs ~5x the wall clock
  at the same memory shape.
- **`run-client` and `bench-render` were NOT profiled.** Launching the
  game unprompted is against a standing instruction, so the GPU class is
  asserted from D-086/M5 rather than measured here. It is also the one
  class that cannot be shared at all: there is a single integrated GPU.
- `build-assets` was not profiled — it needs the ~1 GB `bpy` venv this
  worktree does not have. Recorded as unpriced, not as cheap.
- The `gen-terrain-preview` row is a **warm** run. `test-unit`'s 162 s
  includes a compose build check and a cold-ish import; the same recipe
  warm is far cheaper. **First-run cost is per worktree**, so across 51
  worktrees it is paid 51 times, and it is the part of the pipeline most
  worth caching independently of any gating.

## The finding

**~1.25 GB per concurrent docker recipe against ~2.0 GB of free memory:
the machine has room for exactly ONE heavy recipe at a time**, and none
at all if two agents happen to start together — which, with 4 active
workers and no coordination, is a coin flip rather than an unlucky day.

**And CPU is not the binding constraint.** Only `test-load` ever touched
the ceiling (98%, for seconds, during image export and bot startup);
everything else sat under 41% of 16 threads. A balancer that gated on
cores or load average would admit exactly the jobs that then thrash.
**Gate on memory.**

## Decision

1. **One definition of the host budget, and nothing may re-derive it.**
   `host-budget.sh`, the sibling of `instance-id.sh` — same rule, same
   reason. It answers three questions and no others: how much memory dev
   work may use, how much is free right now, and what this recipe's class
   costs. `EDOTMW_HOST_BUDGET_MB` overrides it for the one case the
   budget is deliberately broken, exactly as `EDOTMW_INSTANCE` does.

2. **The budget is measured, not constant.** Admission asks
   `available_mb - reserve >= class_cost_mb`, because the resident floor
   was measured drifting by 1.2 GB inside one hour. A constant job cap is
   the thing this decision rejects.

3. **Weight classes, not one mutex.** A single global lock would put
   `just instance` behind a 300 s load test.
   - `gpu` — exclusive, machine-wide: `run-client`, `bench-render`,
     `quick-test`, `lobby`. One integrated GPU; two clients at once is
     not a slowdown, it is two useless measurements. (`lobby-shot` was
     listed here while planning and shipped as `medium`: it is software-
     rasterised and headless, so it contends for memory, not the GPU.)
   - `heavy` — `test-load`, `test-scenario`, `ai-ladder`, `test-client`,
     `profile`, and `up`/`run-server` (held for the container's life)
   - `medium` — `test-unit`, `build-assets`, the `gen-*` previews
   - `free` — `instance`, `status`, `doctor`, `scenarios`, `replay-info`,
     `down`. Never gated: a teardown that queues behind the thing it is
     tearing down is a deadlock with a progress message.

4. **Queue, and SAY SO.** A blocked recipe waits, printing the reason and
   the holder every few seconds — "waiting: 1 heavy job held by
   ao-my-edotmw-63-root, 1.4 GB free, need 2.0". A silent wait is
   indistinguishable from a hang, which is exactly how M10's five seconds
   of terrain meshing got reported as a dead server. The wait has a
   timeout, and the timeout **fails loudly** rather than proceeding
   anyway — CLAUDE.md's oldest rule is that a recipe must never report
   success for something that did not run.

5. **A lock is held by a live process or it is not held.** Every lock
   carries pid, instance and timestamp; a holder whose pid is gone is
   reaped by the next arrival. The failure mode this guards is already
   present on the machine in another form: five containers from other
   instances are sitting `Exited` up to 42 hours old despite the
   teardown-scoped `--rm` design. A killed agent must not wedge the host.

6. **The gate lives OUTSIDE every worktree** — `%LOCALAPPDATA%/edotmw/`
   or `~/.edotmw/` — because it is the one piece of state that must be
   shared by construction. This is not a breach of D-095: D-095 forbids a
   worktree *touching another instance's containers*, and the gate
   touches nobody's containers. Its reaper keys on process liveness only.

7. **The WSL cap is a documented host step and a `doctor` check, never
   something a recipe writes.** `%USERPROFILE%\.wslconfig` is **absent**
   on this machine, so WSL2 may take 50% of RAM (~7.8 GB) on demand. A
   cap plus `autoMemoryReclaim` is the largest single lever available,
   and applying it needs `wsl --shutdown`, which would kill every other
   agent's running containers. **The repo must never do that to a
   machine.** `just doctor` reports the file's absence and prints the
   recommended contents; a human applies it.

## Rejected alternatives

- **A fixed max-N-jobs cap.** Rejected on the measurement above: the
  resident floor moved 1.2 GB in an hour and free memory moved the other
  way. Any N sized today is wrong tomorrow.
- **Gating on CPU or load average.** Rejected on the measurement: CPU was
  not the constraint in three of three profiled activities.
- **One global mutex.** Serialises the free recipes behind the slow ones
  and makes `just down` deadlock-prone.
- **Per-container `--memory` limits.** Caps the container, which was
  never the thing that grew; the +1.25 GB is the WSL VM around it.
- **Gating inside AO.** AO is an installed application, not a repo on
  this machine, so it cannot be changed from here — and it could not know
  a recipe's class if it could. AO's lever is session hygiene (below),
  which is different and complementary.
- **Building on a remote or CI host.** No CI exists (`.github/workflows`
  is absent) and D-014 already puts the GUI client on native hardware.
  Out of scope, and noted as the real fix if the session count keeps
  rising.

## Consequences

- **A recipe can now wait, so wall clock stops being a cost signal.** Any
  timing taken while a recipe was queued is void. This is the rule the
  project already applies to figures measured while the host was building
  containers — it now has a mechanism that can *report* the condition
  rather than leaving it to be noticed afterwards.
- Agents get slower and the machine stops thrashing. That trade is the
  decision.
- The gate is a new thing that can be wrong, and a wrong gate stops all
  work. Hence criteria 5 and 9: it must be observed failing, and it must
  have an off switch.

## Exit criteria

1. `host-budget.sh` exists, is the only definition of the budget, and a
   source-scanning test fails if any other file computes one — the D-095
   and `spawn_seed` pattern.
2. Every recipe declares a class, and a test fails if a recipe body
   invokes docker or Godot without one. **The uncalled-member family says
   the gap will be a recipe nobody remembered, not a wrong number.**
3. Two heavy recipes started together from two worktrees serialise, both
   complete, and available memory never drops below the reserve —
   measured with the sampler, not asserted.
4. A gate holder killed mid-run is reaped by the next arrival within one
   poll interval.
5. **Each check is observed to fail before it is trusted** (D-022): set
   the budget to zero, watch a heavy recipe wait and then fail loudly,
   restore it, watch it pass.
6. `just doctor` reports the host budget, current free memory, the
   live-session floor, and whether `.wslconfig` is present.
7. `just host-profile [SECONDS]` is a real recipe wrapping the committed
   sampler, so "did this help" is a measurement. The before-numbers are
   the table above.
8. A reap for **leaked containers whose worktree no longer exists** —
   keyed on the worktree being gone, never on age, so it cannot touch a
   live agent's instance.
9. The gate has a documented off switch (`EDOTMW_NO_GATE=1`), and
   `doctor` says when it is set.

## Revisit trigger

More RAM, a dedicated build host, or the live-session floor dropping far
enough that two heavy recipes fit — any of which makes the gate mostly
inert and worth deleting rather than tuning. Also: if the gate is ever
observed blocking work while memory was in fact free, that is a defect in
the budget, not a reason to raise the cap.

## Not in this decision, but found while measuring it

- **17 of 21 live worker sessions are idle, at ~190 MB each (~3.2 GB).**
  That is larger than every lever in this entry combined, and it is
  AO-side: the pipeline cannot reclaim it.
- Five containers from other instances sit `Exited` for up to 42 hours —
  exit criterion 8.
- 205 build-cache entries hold 1.24 GB. Harmless here (261 GB free) and
  explicitly not worth a recipe.

## What was built, and what the building found

`host-budget.sh` (the budget and the admission arithmetic), `host-gate.sh`
(the cross-worktree queue), `host-sample.ps1` (the instrument), 21 gated
recipes plus `_import`, `doctor` reporting, `host-status` / `host-profile`
/ `host-reap` / `reap-orphans`, and `tests/test_host_budget.gd`.
`just test-unit` green at 897 tests across 57 scripts.

Five defects were found by the work's own checks, and they are the part
worth reading:

1. **The gate stamped its own pid on the lock.** `acquire` exits the
   instant it returns a token, so the very first smoke test watched the
   reaper delete a live holder one second after creating it. The slot
   belongs to the RECIPE's shell; recipes pass `$$` explicitly, because
   command substitution makes `$PPID` unreliable.
2. **A bash trap replaces rather than appends.** Six recipes already tore
   down containers on EXIT. `bench-render` was wrongly counted among them
   and got no release at all; `lobby-shot` got two EXIT traps, the second
   of which would have silently dropped its teardown. Both were caught by
   `test_host_budget.gd` on its first run — the test earned its keep
   before the feature did.
3. **`docker ps -aq` silently overrides `--format`.** `reap-orphans`
   parsed container IDs as instance names, matched no branch, and queued
   five LIVE agents' containers for deletion.
4. **A container's branch is not its session.** Worktrees 30 and 38 were
   registered and active on branches their containers pre-dated, so an
   exact-branch rule proposed deleting them too. The rule keeps a
   container whose AO session is still live on any branch.
5. Both of (3) and (4) were caught **only because `reap-orphans` dry-runs
   unless `APPLY=1`**. That default is now the load-bearing part of the
   recipe, not a courtesy.

**And one live demonstration.** The first gated recipe run — an ordinary
`gen-terrain-preview` — found 2,064 MB free against 1,300 needed plus 768
reserved, waited 6 s, then ran. The gate was not a hypothetical on this
machine even for its first invocation.

## Exit criteria — discharged?

1. **Yes.** `host-budget.sh` is the sole definition; the test fails if
   any other file reads `MemAvailable`/`FreePhysicalMemory` — observed
   failing.
2. **Yes.** Observed failing with `ai-ladder`'s acquire removed.
3. **Partly — the honest answer.** Contention is verified by charging a
   simulated holder and by GPU exclusivity, and admission/refusal was
   watched at five free/charged pairs. Two heavy recipes started from two
   *different worktrees* has NOT been run: it needs a second agent's
   checkout, and staging one would have meant running a load test on a
   host already at 85-90% memory. This is the criterion to close first if
   the gate is ever doubted.
4. **Yes.** A holder with a dead pid is reaped on the next arrival.
5. **Yes.** Every check in `test_host_budget.gd` has been observed red:
   three by deliberate perturbation (ungated recipe, second memory
   reader, blinded reaper), two by finding real bugs.
6. **Yes**, including the `.wslconfig` absence and its recommended
   contents.
7. **Yes.** `just host-profile SECONDS TAG`.
8. **Yes**, dry-run by default. On the machine as found: 3 orphans
   (worktrees deleted), 3 kept (live). Not applied — removing another
   session's containers is the owner's call, not a side effect.
9. **Yes.** `EDOTMW_NO_GATE=1`, reported by `doctor` and by
   `host-status`.

## Amendment trigger for the numbers

Every figure in this entry was taken on 2026-08-18 with 22 agent sessions
live. If the session count changes materially, re-take them with
`just host-profile` before reasoning from them — the class costs are
rounded-up constants and the *reserve* is the number most likely to be
wrong first.
