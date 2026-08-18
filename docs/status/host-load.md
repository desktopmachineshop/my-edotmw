**Dev work is admitted against a host budget, and was not for nine
milestones** (D-20260818-dev-work-is-admitted-against-a-host-budget).
D-095 made parallel agents unable to COLLIDE — own compose project, own
container names, own UDP port. Nothing made them unable to STARVE each
other, and they share one laptop.

The cost was already written down three times before it was named: the
user memory note "Docker Desktop dies under parallel agents"; M6's
worst-tick figures discarded because "the host was building containers
throughout"; and `terrain.md`'s `bench-render` absolute moving 52.1 ms →
181.1 ms on an *unchanged build* over three hours. Three milestones paid
for host contention in thrown-away measurements without anyone treating
it as a thing to fix.

**Profiled first, because the obvious lever was the wrong one.** On the
owner's laptop (i5-13500H, 12C/16T, 15.6 GB, Iris Xe) with 22 agent
sessions live: CPU sat under 41% for every activity except `test-load`,
which touched 98% for seconds. Meanwhile **free memory never left the
1.5–2.4 GB band, before any recipe ran at all.** A gate on cores or load
average would have admitted exactly the jobs that then swap. The
measurements, their caveats and what was deliberately *not* measured are
in the decision entry — quote them from there, and re-take them with
`just host-profile` rather than trusting a number in prose.

Four things worth carrying forward:

- **Gate on memory, not on cores** — and on a *measured* pool, not a job
  count. The resident floor moved 1.2 GB inside the profiling hour
  (29 → 22 `claude` processes) **and free memory fell anyway**, because
  the WSL VM absorbed what was freed. *Freed memory never became
  headroom.* Any fixed "max N jobs" would have been sized against a floor
  that does not hold still, so admission reconstructs the pool every poll:
  `pool = free + charged`, `need = charged + cost(class)`. A job admitted
  but not yet grown into its memory is still charged in full, which is
  what stops two agents arriving in the same second from both being let
  in.
- **The biggest single number is not the pipeline's to fix.** An IDLE AO
  session costs what an active one costs (~190 MB), and 17 of 21 live
  workers were idle — ~3.2 GB, larger than the whole free pool and larger
  than every lever in the gate combined. Raised with the orchestrator;
  the gate handles the *burst* half only, and saying so is the point.
- **A destructive default is not a cleanup convenience.** `reap-orphans`
  removes containers whose worktree is gone, and its first two versions
  each proposed deleting **live** agents' containers — once because
  `docker ps -aq` silently overrides `--format` and yields container IDs,
  once because two worktrees had moved to a new branch since their
  container was made. Both were caught only because the recipe dry-runs
  unless `APPLY=1`. D-095's line is that a worktree never removes another
  instance's containers; a rule that can be wrong there is not allowed to
  be the one that runs unsupervised.
- **A bash trap REPLACES, it does not append.** Six recipes already tore
  down containers on EXIT; adding a second `trap ... EXIT` for the gate
  release would have silently dropped the teardown. `test_host_budget.gd`
  counts EXIT traps per recipe body for that reason — and caught the bug
  in the very wiring that introduced it, along with a `bench-render` that
  acquired a slot and never released it.

**The instruments are `just host-status` (who is holding the machine),
`just host-profile` (what a change actually bought) and `just doctor`
(the budget, plus whether `~/.wslconfig` exists).** The WSL cap is
reported, never applied: WSL2 with no `.wslconfig` may take 50% of RAM
and hold it, and capping it needs `wsl --shutdown`, which would kill
every other agent's running containers. The repo must never do that to a
machine — a human applies it at a quiet moment.

**Two unrelated things in this repo are now called a "gate", and they
landed the same day.** `gate-check.sh`
(D-20260818-the-fast-loop-carries-the-gate) is the set of log comparisons
a real multi-client run must survive — it decides whether a RUN passed.
`host-gate.sh` (this entry) decides whether a run may START. They share a
word and nothing else; neither reads the other.

**The off switch is `EDOTMW_NO_GATE=1`**, and `just doctor` says when it
is set. A wrong gate stops all work, so it has to be escapable and the
escape has to be visible.
