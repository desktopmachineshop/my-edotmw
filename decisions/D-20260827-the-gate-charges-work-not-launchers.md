# D-20260827 · 2026-08-27 · Accepted — the gate charges work, not launchers

**Decision:** the host admission gate's ledger and the machine's actual
occupancy must be **reconcilable**, and any disagreement must be **loud**.
Four clauses:

1. **A slot is released when the WORK is gone, not when the launcher
   is.** `host-gate.sh`'s reaper asks docker before dropping a
   dead-pid holder: if that holder's instance still has a running
   container, the slot is kept, marked `orphaned=1`, and reported once.
   It is released the moment the container is.
2. **`host-gate.sh occupancy` reports what is running beside what is
   charged**, and `status` calls it — so `just doctor` and
   `just host-status`, the two places people already look, say when the
   two disagree. A container charged to nobody is named, not merely
   counted.
3. **`release` says so too.** A recipe that hands its slot back while
   its own instance still has containers up has just made the ledger
   disagree, and no holder is left for the reaper to notice with. A
   report, never a refusal — `just up` leaves a server running on
   purpose — and silent in the ordinary case, because a recipe that tore
   down has nothing to list.
4. **`docker ps` is the only docker verb in the file, for ever.** The
   list is global by necessity: the holder whose launcher died may
   belong to any instance. That makes read-only the whole safety
   argument rather than a nicety, so it is asserted as an allowlist
   (every verb must be `ps`) rather than the denylist of four that was
   there before.

## Rationale

From #153, found by observation an hour after the gate landed:

```
host-gate:   0 holder(s), 0 MB charged, dir /c/Users/dmaso/.edotmw/gate
docker ps:   edotmw-ao-my-edotmw-10-root-quick-test   Up 2 hours
host-budget: 16005 MB total, 733 MB free, 768 MB reserved
host-budget: swap in use 2916 MB
```

The gate's accounting unit is a **pid**; the thing that occupies this
host is a **container**; the two part company when a launcher exits and
its container carries on.

**The failure inverts the feature rather than weakening it.** Before the
gate, an overloaded host was obvious. Now a stale container makes the
ledger read *empty*, so the budget reconstructs `pool = free + charged`
with a `charged` that has silently gone to zero while the memory is
still resident — and the machine looks quiet at the moment it is not.
It is silent too: everything crawls instead of queueing, which reads as
"the agents are stalled", and on the day it was found two live sessions
were misread as dead and one was killed mid-rebase.

**Why this stays inside D-095.** That decision forbids a worktree
*touching another instance's containers*. Reading the container list is
not touching it — `just reap-orphans` already reads exactly this list,
across every instance, and has since it existed. Nothing here removes,
stops or restarts a container, this instance's own included: telling a
human which worktree to run `just down` in is as far as it goes. The
allowlist in clause 4 is what makes that a property rather than a
promise.

**And it fails open.** No docker on PATH, a stopped daemon, a query past
`EDOTMW_GATE_DOCKER_TIMEOUT`: every one answers "nothing is running", so
the gate degrades to exactly the behaviour it had before this existed.
Wedging every agent on the machine because `docker ps` was slow would be
a worse bug than the one being fixed.

## Rejected alternatives

- **Charging measured container memory** (`docker stats`). The honest
  number, and it costs **2.9 s** against `docker ps`'s **0.44 s**
  (measured on the reporting host) on a five-second poll. It also
  answers a question nobody asked: the gate's costs are per-CLASS
  estimates rounded up, and mixing a measured figure into a
  reconstructed pool of estimates makes neither interpretable.
- **Charging every running container, holder or not**, at its class
  cost. That would make the ledger complete — and an idle `just up`
  server is ~71 MB RSS against a `heavy` class cost of 1,500 MB, so it
  would charge one agent's idle server twenty times its true weight and
  wedge the whole fleet. Being wrong high "costs a wait" in the budget's
  own words; here it would cost every agent every wait.
- **Reaping the container when its holder dies.** The obvious fix and a
  straight D-095 breach: the holder that dies may belong to any
  instance, and `just reap-orphans` has already been caught twice
  proposing to delete live agents' containers with a *better* matching
  rule than this one would have.
- **Making the reaper's container test use `reap-orphans`'s
  service-suffix regex.** That regex strips
  `-(server|bots|test|client-test)(-run)?-…`, and the container in
  #153's own evidence ends `-quick-test`, which it does not name. An
  exact name PREFIX ending at a dash needs no list of service names and
  cannot drift.
- **Leaving the backstop to clean up.** `EDOTMW_GATE_MAX_HOLD` would
  reap the orphan after two hours anyway — silently, which is the same
  under-count arriving later. The backstop still fires (a slot that can
  be held for ever is a machine nothing can use) and now says what it
  is dropping and what is still running when it does.

## Consequences

- **`gen-formation-icons` declares a host class.** It launches Godot and
  was the one `gen-*` recipe that never did, so `test_host_budget.gd`'s
  "a recipe nobody remembered" check has been red on `main` since it was
  added. That is this same under-count through the other door — work on
  the machine the ledger cannot see — so it is fixed here rather than
  filed.
- **`test_multi_agent_isolation`'s `--name` scan is scoped to docker
  lines.** It matched `art/attach_kit.py --name "{{TARGET}}"`, a Blender
  argument with nothing to do with D-095, and has been red on `main`
  since that recipe landed. **A guard that cries wolf is a guard
  somebody eventually relaxes rather than reads** — the same reason
  `test_host_budget`'s scans now read code lines rather than the prose
  explaining what the gate does not do.
- **The behaviour half is tested by EXECUTING the gate**
  (`tests/test_host_gate_occupancy.gd`), with docker STUBBED — a
  `docker` on PATH printing a fixture. The rule under test is what the
  gate does with an answer, and a test needing real containers could
  neither create the interesting case nor run with the daemon down.
  Same split as `test_gate_checks.gd`, and docker-runtime only for the
  same reason.
- **A gated recipe pays one `docker ps` on release** (~0.44 s), and the
  reaper pays one only when a holder's pid is actually gone, which is
  rare. The list is cached per pass, never across a wait.

## Revisit trigger

A container class whose memory differs from its gate class by more than
a factor of two — a long-lived `just up` server is already ~20x lighter
than `heavy`. At that point the honest fix is per-class costs that
distinguish "starting work" from "resident service", not a measured
figure mixed into a pool of estimates; that is a re-measurement of
`host-budget.sh`'s cost table, and it belongs in its own entry.
