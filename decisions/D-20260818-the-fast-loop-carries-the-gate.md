# D-20260818 · 2026-08-18 · Accepted — the fast loop makes every check the gate makes

**Decision:** the log comparisons a real multi-client run must survive
live in **`gate-check.sh`**, once, and both `just test-load` and
`just test-scenario` call it. Three clauses:

1. **A comparison that needs two logs is a script, not a recipe body.**
   `fog-squads` (D-026 criterion 6's load half), `fog-nodes` (D-061) and
   `civs` (D-046 criterion 10) each compare a structured marker from the
   clients' log against one from the server's. They were written inline
   in `test-load` and copied nowhere. A plain script is also the only
   form the test estate can reach — the same reason `recipe-arg.sh` and
   `instance-id.sh` are scripts.
2. **A missing marker fails the check.** Every one of them treats "I
   could not find the two numbers" as a failure, never a skip. This is
   only restating what the inline versions already did, and it is the
   clause worth keeping loudest: a comparison that silently skips is
   indistinguishable from one that passed (D-022's audit).
3. **The fast loop may not assert less than the gate.**
   `tests/test_gate_checks.gd` fails if `test-load` runs a check
   `test-scenario` does not, and fails if either recipe reads one of the
   markers itself instead of going through the script. Both directions
   matter: the first is the defect that existed, the second is how it
   would come back.

**Nothing about what the gate proves changes.** `test-load` makes exactly
the checks it made yesterday, on the same markers, with the same
thresholds. The change is that the recipe people actually run between
gate runs now makes them too.

## Rationale

From **#112**: `just test-load` costs five minutes a run on the default
map, and this project's own guidance is that a single green run is not a
measurement — so an honest check is fifteen. The existing answer to that
is D-098's scenarios, and `just test-scenario` is the loop it created.

Measured on `main` at 1e6ba9c, in an isolated worktree (D-095):

| run | wall clock | verdict |
|---|---|---|
| `test-load 4 300` | **5 min 11 s** | FAILS — `conceal_events=0 reveal_events=0` |
| `test-scenario siege 4 15` | **25 s** | clean (`casualties=93 conceal=7 reveal=1`) |

So the loop was already twelve times cheaper. What it was not was
equivalent: `test-scenario`'s own header says *"the checks follow
test-load's shape"*, and of `test-load`'s four checks it had copied
**one**. Fog gating of squads, fog gating of resource positions and both
civilisations having fielded something were asserted by the five-minute
recipe **alone** — which, given how often a five-minute recipe gets run,
is close enough to *nothing* to be worth calling a gap rather than a
weaker check.

The three cost this recipe nothing: a scenario run already prints every
marker they read. Verified against the artefacts of a real
`test-scenario siege 4 15` run — `known_squads_max=11` against
`FOG_TOTAL_SQUADS=32`, `nodes_known_max=128` against
`FOG_TOTAL_NODES=7694`, `CIVS_FIELDED 2 of 2`. If anything fog gating is
*harder* to satisfy mid-game than during the opening, because a scenario
puts armies in reach and more of the board is therefore visible.

**This is the declared-and-unread family, in the harness, with the
comment as the evidence.** "The checks follow test-load's shape" is a
sentence describing behaviour in the passive voice, and CLAUDE.md's own
rule for those is to grep for the writer before believing it. Nothing
failed: `test-scenario` was correct about everything it did check.

## What is deliberately NOT in this change

- **The bots' manoeuvre.** `test-load 4 300` fails on `main` today with
  `conceal_events=0 reveal_events=0`, and the cause is #69/#84 — the bots
  had stopped manoeuvring at all. That is fixed by
  `D-20260817-load-test-bots-must-manoeuvre` on its own branch, which
  owns `bot_client.gd`. Re-fixing it here would collide for no gain.
- **A shorter DURATION for `test-load`.** #112 says so explicitly and it
  is right: D-031's trap is exactly a duration that stops reaching
  contact and is kept anyway. A gate that no longer reaches contact fails
  honestly, and that is the check working. The duration follows the map;
  the way to spend less time is to run the *loop* more and the *gate*
  less, which is what this decision buys.
- **`test-client`'s scripted phases.** `client.gd`'s capture scenario is
  still calibrated against a 128x64 map (`WITHDRAW_AT_SECONDS = 30`, with
  a comment saying the contested middle is ~25 s of marching away; it is
  roughly twice that now). Real, same family, and a bigger change than
  this one — it would make `test-client` *longer*, not shorter, so it
  does not belong in an iteration-cost fix. Named here so it is not lost.

## Rejected alternatives

- **Copy the three checks into `test-scenario`.** The cheapest edit, and
  it recreates the defect it fixes: two copies of a comparison drift, and
  the drift is invisible because both recipes still pass. The scan test
  would have nothing to anchor on.
- **A new scenario tuned for long marches, so a scenario run can also
  cover spawn distance.** Measured: `test-scenario developed 4 60` —
  `developed` is the one shipped scenario at real spawn separation —
  reports `casualties_applied=0 conceal_events=0 reveal_events=0`. Real
  spawn distance means a real march, and a real march is the thing that
  costs five minutes. A scenario cannot buy that back; only skipping the
  opening can, which is what `separation` already does.
- **Make `test-scenario` the gate.** Refused for the reason its own
  header gives: a scenario hands out finished buildings and adjacent
  armies, so it cannot see a bug in founding, in production or in spawn
  placement. `test-load` stays the gate.

## Consequences

- `test-scenario` now fails on three things it used to pass silently. It
  gains no wall-clock cost — the markers are already in the logs.
- `test-load`'s recipe body is 39 lines shorter and its checks are
  testable, which they were not: a recipe body is unreachable from GUT.
- One more instance for the standing list: **a harness that says it
  follows another harness's shape is a claim to check, not a fact.**

## Revisit trigger

If a fourth harness (`test-client`, `ai-ladder`) needs the same
comparisons, they go through `gate-check.sh` too and the scan test grows
a third recipe — not a fourth copy. And if any check here ever has to be
*relaxed* for the fast loop specifically, that is the point at which the
fast loop has stopped carrying the gate and this decision is wrong.
