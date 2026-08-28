# Gap assessment, round 2 — the audit after the cycle

**Written:** 2026-08-28, ~13:00. **Against:** `main` at `cc2f4c6` and the
**80 open PRs** in flight. Round 1 is `docs/plans/gap-assessment.md`
(PR #265), written against the same `main` commit ~15 hours earlier.

**What changed since round 1.** Round 1 proposed 17 tickets. **Sixteen of
the seventeen now have a PR.** The seventeenth needs hardware nobody in
this estate has. That is an extraordinary rate of response and the work
is, on inspection, good — the naval chain, the tech tree, the farm, the
CI pipeline, the scale measurement and the audio foundation are each
better than the ticket that asked for them.

**What did not change: `main`.** It is the same commit round 1 audited.

```
$ git log --oneline -1 origin/main
cc2f4c6 Merge pull request #199 ...        # round 1's baseline
$ git log --oneline origin/main ^cc2f4c6 | wc -l
0
```

So round 2 is not a second content audit. The content gaps round 1 found
are answered, in branches. **The question that matters now is why none of
it is in the game, and what the second cycle has to do differently.**

**Severity scale**, unchanged from round 1:

| | meaning |
|---|---|
| **Blocker** | M8 (Steam-ready) cannot honestly be called done with this open |
| **High** | ships, and the first cohort of players will hit it and say so |
| **Medium** | costs the project time or credibility, not the release |
| **Low** | worth writing down before it is forgotten |

Every number below is quoted with its conditions, per the project's own
standing rule, and every one was measured today from the repo or from a
run rather than recalled.

**A word on my own position in this.** I am session 79 and I own twelve
of these eighty PRs, one of them eleven deep in a chain. The largest
finding below is one I helped cause, and one of the concrete examples is
a collision between my own work and another worker's. This is not an
audit of other people.

---

## 0. The headline

**One cycle produced 80 PRs, 91,106 added lines and 70 new decision
entries, and shipped none of it.** Every measurement in this document is
downstream of that.

```
open PRs                                80   (all created in the last ~15 hours)
merged to main this cycle                0
lines added across them            +91,106 / -3,254
new decision entries not on main        70   (main has 160: a 44% increase, invisible)
PRs with a single CI status check        0
```

Three things follow, and they are the whole document.

**The integration debt now exceeds the feature debt.** Round 1's headline
was "the simulation is ahead of the game". That is still true, but it is
no longer the binding constraint: the game has been written and cannot be
assembled. Thirty-two of the eighty PRs target `main` directly, and
**108 pairs of those 32 collide on a shared file** — `server.gd` is
touched by eleven of them, `client.gd` by eight. The remaining 48 are
stacked up to **eleven deep**, so each one's rebase is a function of ten
other merges.

**Nobody can answer what a full match feels like, and that is a
structural fact rather than an oversight.** D-056's 1–2 hour target
depends on three things that were all built this cycle — food that
renews (#246), something to spend a match deciding (#225/#296), and a way
to stop (#297) — and **no tree in existence contains more than one of
them.** The pacing question the orchestrator asked cannot be answered by
looking; it can only be answered by merging.

**CI exists, is proven, and guards nothing.** #294 is green, and its own
PR body links four deliberately-red runs proving each gate fails. Its
workflow files are not on `main`, so **zero of the eighty PRs has a
status check.** The eleven "main is red" incidents round 1 counted are
not being prevented; they are being deferred, and the tree that will
absorb them is 91k lines larger than the one that produced them.

---

## 1. The integration gap

### 1.1 Gap I1 — nothing merged, and the queue is now structurally hard to merge

**Severity: Blocker.**

**Evidence, all measured today.**

The 32 root PRs (those based on `main`) collide as follows:

| file | root PRs touching it |
|---|---|
| `server.gd` | **11** — #205 #225 #226 #237 #246 #248 #251 #255 #297 … |
| `client.gd` | **8** — #205 #216 #221 #225 #232 #237 #246 #297 |
| `justfile` | 6 |
| `CLAUDE.md` | 6 |
| `building_sim.gd` | 5 |
| `bot_client.gd` | 4 |
| `ai_player.gd`, `squad_sim.gd`, five `civs/*.tres` | 3 each |

**108 colliding pairs among 32 PRs.** GitHub reports all 80 as
`MERGEABLE`, and that is not reassuring — it is measured against each
PR's *own base*, which for 48 of them is another unmerged branch.
Mergeability against `main` after siblings land is not a fact anyone
currently has.

Chain depth, from GitHub's own `baseRefName` edges:

```
depth histogram (PRs that must merge before this one):
  0: 32   1: 12   2: 11   3: 3   4: 3   5: 5   6: 4   7: 2   8: 2   9: 2   10: 2   11: 2
```

The two eleven-deep PRs are **#348 (mine)** and **#340**.

**This is already being worked on and that work should be adopted, not
repeated.** PR #350 (`docs/plans/merge-order.md`) computes a
dependency-sorted order mechanically from the same edges, ships the
generator so it can be re-run rather than trusted, and found two things
no ordering resolves: **#340 is not naval stage 8** — it is a rebase of
the naval chain onto the performance chain, carrying 41 of the naval
chain's 62 files, with a byte-identical copy of one of its decision
entries — and **the hulls and dock are shipped by three independent
chains**. Round 2's contribution is not a second ordering. It is the
observation that an ordering is a *palliative*: the next cycle will
rebuild this queue in a day unless the rule that produced it changes.

**What the rule should be.** Round 1 recorded 29 open PRs as a process
risk. It is 80. The number that matters is not the count but the
**merge-to-open ratio, which is 0**. A concrete, checkable rule: *no
worker starts a new ticket while its own previous PR is unmerged and
un-reviewed*, and *a chain may not exceed depth 3* — beyond that, land
the base first or rebase onto `main`. Both are enforceable by the
orchestrator at assignment time, which is the only place they can be
enforced.

> **Proposed ticket 1 — Merge the queue before growing it: adopt #350's
> order, cap chain depth at 3, and pause new feature assignment**
> 80 PRs, 0 merged, 108 colliding pairs among the 32 roots, two chains
> eleven deep. #350 computes the order; this is the decision to *follow*
> it and to stop adding while it runs. Proposed rule: a worker's next
> ticket waits on its own previous PR landing, and no chain exceeds depth
> 3. Severity: **Blocker**.

### 1.2 Gap I2 — CI is built, proven, and guarding nothing

**Severity: Blocker.**

```
$ git ls-tree -r --name-only origin/main | grep -c '^\.github/workflows'
0
$ for n in 348 320 246 297 225 341; do gh pr view $n --json statusCheckRollup ...; done
PR #348 checks: 0   PR #320 checks: 0   PR #246 checks: 0
PR #297 checks: 0   PR #225 checks: 0   PR #341 checks: 0
```

#294 is the single highest-leverage merge in the queue and it is the one
merge whose value **decays with every day it waits**, because the tree it
would guard grows 91k lines a cycle. It is also nearly conflict-free: it
adds `.github/workflows/*` and `docs/ci.md`, files nothing else touches.

**It should be merged before the ordering exercise, not inside it.** Every
subsequent merge in #350's order is then verified by a machine rather
than by the next person to run a recipe by hand.

> **Proposed ticket 2 — Merge #294 first, out of order, so every
> subsequent merge is verified**
> CI exists, is green, and has four deliberately-red runs proving its
> gates fail. Zero of 80 PRs has a status check because the workflow is
> not on `main`. It touches only `.github/` and `docs/ci.md`, so it can
> land ahead of the dependency order without disturbing it. Severity:
> **Blocker**.

### 1.3 Gap I3 — the decision record, which this project runs on, is 70 entries behind

**Severity: High.**

```
decisions/ on main:                       160
distinct decision files across branches:  230
new, not on main:                          70   (+44%)
```

CLAUDE.md's opening instruction is *"Before making any architectural
decision, check `decisions/` first"*, and `decisions/README.md` exists
because a shared monolith made every parallel merge conflict. The
one-file-per-decision rule is doing its job — **70 new files, and not one
conflicts with another**. The failure is one layer up: a session that
reads `decisions/` today is reading a record that is 44% incomplete, and
has no way to know it.

This is the mechanism by which gap I4 below happened, and it will happen
again for every pair of workers whose tickets touch a shared concept.

> **Proposed ticket 3 — Land the decision entries ahead of their code**
> 70 new decision entries exist only in branches, so every session starts
> from a record 44% out of date. Decision files are append-only and
> conflict-free by construction (`decisions/README.md`), so they can be
> cherry-picked to `main` ahead of the implementations they describe —
> at the cost of the record briefly describing more than the code does,
> which is the *safer* of the two failure modes and the one D-065 did
> **not** warn about. Severity: **High**.

### 1.4 Gap I4 — two workers were told to share machinery and built it twice

**Severity: High.** This is the cycle's cost made concrete, and it is the
best single argument for gaps I1–I3.

The orchestrator assigned #337 (the AI builds walls) with an explicit
instruction to **reuse** whatever "the AI invests in static defence"
machinery naval stage 7 (#301) was creating, and to agree the interface
in the PR bodies if stage 7 was not ready.

What happened:

| | #348 (walls, session 79) | #342 (naval stage 7, session 81) |
|---|---|---|
| decision | `D-20260828-an-ai-that-fortifies` | `D-20260828-an-ai-invests-in-what-it-cannot-walk-to` |
| shared module | `static_defence.gd` (domain-free, scan-enforced) | none |
| `ai_player.gd` | +~200 lines | **+250 lines** |
| reuses the other | — | **no** (`git grep StaticDefence` on its branch: empty) |

Both landed the same day. Neither worker did anything wrong: when I
checked for stage 7's machinery it did not exist, so I built the seam and
posted the interface on the naval PR — and by then stage 7 was already
written. **There is no mechanism by which either of us could have seen
the other's tree**, because the only shared surface is `main` and nothing
reaches it.

The cost is not the duplicated design. It is that `ai_player.gd` now has
two independent ~200-line additions answering the same question, which
must be merged by hand by somebody who understands both.

> **Proposed ticket 4 — Reconcile the two "AI invests in static defence"
> designs into one**
> #348 and #342 each add ~200–250 lines to `ai_player.gd` and each carry
> their own decision entry for the same question. #348's
> `static_defence.gd` is deliberately domain-free and scan-enforced;
> #342's naval investment is written inline. One of them should become
> the other's caller. Whoever merges second should do it, and the
> interface is already documented on PR #327. Severity: **High**.

---

## 2. What a full match feels like — and why nobody can say

**Severity: Blocker (against D-056's target).**

The orchestrator asked what a full match feels like end-to-end now. The
honest answer is that **no such match can be played today**, and the
evidence is a table:

| branch | farm | techs | surrender | naval | walls-AI | manual |
|---|---|---|---|---|---|---|
| `my-edotmw-82/renewable-metals` | ✅ | — | — | — | — | — |
| `my-edotmw-83/ladder-and-pacing` | — | ✅ (65 files) | — | — | — | — |
| `my-edotmw-81/naval-7-ai-and-bots` | — | — | — | ✅ | — | — |
| `my-edotmw-79/ai-fortifies` | — | — | — | — | ✅ | ✅ |
| `main` | — | — | — | — | — | — |

**No tree contains more than two of the six.** D-056's 1–2 hour target
needs at minimum the farm (or the match is arithmetically bounded by
finite food — round 1's gap C1), the ladder (or there is nothing to
decide for the other 80 minutes — round 1's gap C5) and surrender (or a
lost player cannot stop — round 1's gap C3). Those three are in three
different trees that have never been combined.

**What can be said comes from the parts, and it is not encouraging.**

- **The ladder is ~7 minutes of banking in a match designed to run 90.**
  That is #296's own measurement, from the first work ever to compute
  D-068's missing rate: *"The whole ladder is ~7 minutes of banking in a
  match designed to run 90. D-069 required the gate to cost enough that
  paying it visibly means not fielding troops for a stretch — it does
  not, and it never could have been checked, because the rate it needed
  did not exist."*
- **Matches still end in minutes.** Measured by me today on the shipped
  ladder map with the current AI: `just ai-ladder 1 420 2` — **decided,
  1 of 1, inside 420 s**. At `1 600 4`, four seats hit the 600 s cap
  undecided. Neither is within an order of magnitude of 90 minutes.
- **The economy that would change this is unmerged and unmeasured
  together with the ladder that would spend it.**

So the pacing question is not open because nobody looked. It is open
because **the three answers to it have never been in the same
executable**, and the first honest measurement of match length is
downstream of gap I1.

> **Proposed ticket 5 — Measure a full match once the economy, the
> ladder and surrender are on one tree**
> D-056's 1–2 hour target has never been measured against a build
> containing the farm (#246), the tech ladder (#225/#296) and surrender
> (#297), because no such build exists. #296 measures the ladder alone at
> ~7 minutes of banking against a 90-minute design. The measurement wants
> `ai-ladder` at a cap long enough not to truncate, quoted with its cap
> and its roster, plus one human match. **Blocked on I1.** Severity:
> **Blocker (target)**.

---

## 3. What the velocity broke, or left half-integrated

Round 1's process section was about a missing machine (CI). Round 2's is
about a missing *shared present* — every gap here is a case of two good
pieces of work that could not see each other.

### 3.1 The naval chain ships three times

#350's finding, restated because it is the largest instance: `#340` is
based on the **performance** chain, not the naval one, and carries 41 of
the naval chain's 62 files including a byte-identical copy of one of its
decision entries. The hulls, `buildings/dock.tres` and
`tests/test_naval_roster.gd` are each *created* by more than one chain.
Merging naively double-applies naval.

**Severity: High.** Covered by #350; no new ticket.

### 3.2 The `.tres` data files are a shared mutable surface with no owner

Five `civs/*.tres` are edited by three root PRs each (#225 tech, #246
farm, #336 knobs, #321 openings). `unit_def.gd`'s schema is extended by
#314 (naval fields) and #328 (morale) independently, and `decisions/D-010.md`
— the schema log every one of them is required to append to — is touched
by three.

This is D-010 working exactly as designed and being overwhelmed by
concurrency: the log is a single file, and a single file is what
`decisions/README.md` says not to have.

> **Proposed ticket 6 — D-010's schema log is a monolith and four PRs
> append to it at once**
> `decisions/D-010.md` is edited by #246, #314 and #336; `unit_def.gd`
> gains fields from two chains independently. Every other decision in
> this project is one file per decision for precisely this reason
> (`decisions/README.md`, D-20260816). The schema log should follow —
> one entry per schema change, indexed — or it becomes the merge conflict
> that every data PR shares. Severity: **Medium**.

### 3.3 Two workers measured the client's frame in parallel

`my-edotmw-87` has **six** performance PRs in one chain (#263 #272 #298
#307 #317 #326 #329 #331), each attributing part of the same frame. That
is a coherent body of work and the chain is the right shape for it. The
risk is only that **the six are depth 5–10**, so the last of them is
gated on nine other merges — and its measurements were taken on a tree
that no longer resembles what it will land on.

**Severity: Medium.** A performance number taken on branch *N* of a
ten-deep chain is quoted against conditions that will not exist when it
merges; this project's own rule is that a figure carries its conditions,
and "the tree it was measured on" is now one of them.

> **Proposed ticket 7 — Re-take the headline performance numbers once
> the perf chain is on `main`**
> The `my-edotmw-87` chain is six PRs deep and every figure in it was
> measured on an intermediate branch. This project quotes a number with
> its conditions; for a deep chain the tree is a condition. One
> `bench-render` and one `test-load` after the chain lands, replacing the
> per-PR figures in the status pages. Severity: **Medium**.

### 3.4 What was *not* broken, and is worth saying

The three structural guards this project relies on all held under a
concurrency they were never designed for:

- **one file per decision** — 70 new entries, zero conflicts;
- **no `.gd` names a civ / a profile / Steam** — these scans caught real
  violations in this cycle, including one of mine (a profile name in a
  comment);
- **observe every check fail before trusting it** — #294 shipped four
  deliberately-red CI runs as its evidence, and #348's ladder gate was
  perturbed to red and back.

Those are the parts of the process that scaled. The part that did not is
the part with a single shared resource: `main`.

---

## 4. The next 10x player-facing win

Round 1's answer was onboarding, and onboarding was built: a controls
screen (#306), a manual (#320), a civ identity in the lobby (#295), a
first objective (#300). Round 2's answer is different, and it is not a
feature.

**The next 10x is a build in a stranger's hands, and every part of it
except the merge is already written.**

| piece | state |
|---|---|
| `just export` → three shipping binaries | #205, built |
| protocol handshake so a stale build is refused | #213, built |
| main menu / a way in without a command line | #239, built |
| in-process hosting, so one person can host | #256, built |
| versioned zip + tester runbook | #258, built |
| a way for a tester to send back what happened | #303, built |
| controls, manual, civ identity, first objective | #306 #320 #295 #300, built |
| **any of it on `main`** | **no** |

**The gap between this project and its first external playtest is a merge
queue, not a backlog.** That is a genuinely unusual and good position to
be in, and it is worth stating plainly because the volume of open PRs
disguises it.

The second-largest player-facing win is the one round 1 named and nobody
can act on: **a discrete-GPU `bench-render`** (#285, marked OWNER
ACTION). Every rendering number this project has is from one integrated
adapter, #229 measures the client at 5.4–5.9 fps at 1,000 squads, and
#341 has since *lowered the target* to ~200 squads on measured evidence —
which may well retire #229 as an incident, but only a run on real
hardware can say so.

> **Proposed ticket 8 — Ship an alpha build from a merged `main`, then
> run one external session**
> Every component of the alpha loop is built and unmerged: export (#205),
> handshake (#213), menu (#239), hosting (#256), package + runbook
> (#258), feedback (#303), onboarding (#295 #300 #306 #320). D-094
> criterion 10 needs a human who has never seen the repo to finish a
> match. The remaining work is a merge and an afternoon. Severity:
> **High**.

---

## 5. What the second 48-hour cycle should contain

Round 1's cycle answered "what is missing". It answered it well and it
proved the estate can produce, in a day, sixteen of seventeen things a
senior audit asked for. **The second cycle should answer "does it work
together", and it should be assigned differently to make that possible.**

**Phase A — integrate (the first ~12 hours, and nothing else in
parallel).**

1. Merge **#294** (CI) out of order. Every subsequent merge is then
   machine-verified.
2. Follow **#350**'s computed order, re-running its generator between
   landings rather than trusting the first pass.
3. Resolve the two decisions #350 says an ordering cannot: the **#340
   naval duplication**, and the **three chains that each create the
   hulls**.
4. Reconcile the **two static-defence designs** (gap I4).
5. Cherry-pick the **70 decision entries** ahead of their code, so the
   record every session reads is current while the merge runs.

**Phase B — measure the thing that now exists (the next ~12 hours).**
Nothing here is new work; all of it is impossible today.

6. `just test-unit`, `just test-load 4 300` and `just ai-ladder` on the
   merged tree — the first honest numbers since the cycle began. Expect
   them to be *worse* than any branch's, because branch figures were each
   taken without the other 79 PRs.
7. **The full-match pacing measurement** (ticket 5), which is the
   question this round was asked and could not answer.
8. `bench-render` on the merged client, replacing the six per-PR figures
   from the perf chain (ticket 7).

**Phase C — the external session (the remainder).**

9. Export, package and run **one alpha session with a person who has
   never seen the repo** (ticket 8). D-094 criterion 10.

**And the assignment rule that makes Phase A possible.** The reason this
cycle produced 80 PRs is that eleven workers were each given a good
ticket and none was given a reason to stop. Two rules, enforceable only
at assignment time:

- **A worker's next ticket waits on its own previous PR being merged.**
- **No chain deeper than 3.** Beyond that, land the base or rebase onto
  `main`.

> **Proposed ticket 9 — Adopt a merge-first assignment rule for cycle 2**
> Cycle 1's output was 80 PRs and 0 merges because nothing in the
> assignment loop was gated on landing. Proposed: a worker's next ticket
> waits on its previous PR merging, and chains cap at depth 3. Both are
> orchestrator-side and cost no engineering. Severity: **High**.

---

## 6. If I could only fix five things

In order, judged by risk-to-the-project per hour of work. All five are
integration; **none of them is a feature**, which is the difference
between this round and the last.

1. **Merge #294 (CI).** Cheapest item here, one nearly conflict-free
   diff, and it makes every one of the next 79 merges verifiable by a
   machine instead of by whoever runs a recipe next.
2. **Freeze new feature assignment and run #350's order.** The queue is
   still tractable at 80. It will not be at 160, and the current
   assignment loop produces another 80 a day.
3. **Cherry-pick the 70 decision entries to `main`.** Conflict-free by
   construction, and it is the only way a session started tomorrow can
   avoid gap I4 happening again.
4. **Measure a full match** once the farm, the ladder and surrender are
   on one tree. It is the question the owner's own D-056 has been open on
   since M6 and it has never been answerable.
5. **Run one external alpha session.** Everything it needs is built. It
   is the only instrument in this project that can see what none of the
   others can, and D-094 criterion 10 cannot be discharged without it.

**What I would explicitly NOT do next:** any new gameplay feature. The
estate has demonstrated it can produce them faster than it can absorb
them, and the binding constraint has moved.

---

## Appendix — proposed tickets, collected

For the orchestrator's convenience. Bodies are in the sections above.
**Nothing here is filed.**

| # | title | gap | severity |
|---|---|---|---|
| 1 | Merge the queue before growing it: adopt #350's order, cap chain depth at 3, pause new feature assignment | I1 | **Blocker** |
| 2 | Merge #294 first, out of order, so every subsequent merge is verified | I2 | **Blocker** |
| 3 | Land the 70 decision entries ahead of their code | I3 | High |
| 4 | Reconcile the two "AI invests in static defence" designs into one | I4 | High |
| 5 | Measure a full match once the economy, the ladder and surrender are on one tree | §2 | **Blocker (target)** |
| 6 | D-010's schema log is a monolith and four PRs append to it at once | 3.2 | Medium |
| 7 | Re-take the headline performance numbers once the perf chain is on `main` | 3.3 | Medium |
| 8 | Ship an alpha build from a merged `main`, then run one external session | §4 | High |
| 9 | Adopt a merge-first assignment rule for cycle 2 | §5 | High |

**Deliberately not proposed**, so the omissions are visible rather than
forgotten:

- **A second merge-order document.** #350 already computes one
  mechanically and ships its generator. Round 2's position is that the
  order is necessary and not sufficient, not that it is wrong.
- **New content of any kind** — epochs beyond the first ladder, per-civ
  buildings, more ships, localisation, controller support. All real, none
  of them the constraint.
- **The discrete-GPU bench** (#285). Still open, still owner action,
  still un-actionable from inside the estate — and #341 may have changed
  what it needs to prove by lowering the target to ~200 squads.
- **Anything about audio beyond #345.** That PR is explicitly the
  architecture and not the sound design, and it says so; judging the
  placeholder cues would be judging the wrong thing.

---

## Method, so the numbers can be checked or disputed

Every figure was taken on 2026-08-28 between 12:30 and 13:00, from
`origin/main` at `cc2f4c6` and the 80 open PRs as GitHub reported them.

- PR counts, bases, sizes and changed files: `gh pr list --json` and
  `gh pr view --json files`, not from reading titles.
- Collisions: the set of root PRs (base = `main`) per changed file, with
  every unordered pair sharing a file counted once — 108 pairs over 34
  shared files.
- Chain depth: transitive `baseRefName` edges to `main`, cycle-guarded.
- Decision counts: `git ls-tree` over `decisions/` on `main` and on every
  open PR head, deduplicated by path.
- Feature co-location: `git ls-tree` for `buildings/farm.tres`,
  `techs/`, `buildings/dock.tres`, `static_defence.gd`, `manual/` per
  branch.
- Match length: `just ai-ladder 1 420 2` and `1 600 4` on this worktree,
  shipped `ladder` map, default profiles, quoted with their caps.

Two claims are **not** measured and are labelled as judgements rather
than findings: that the queue becomes intractable at ~160 PRs, and that
the current assignment loop would produce another 80 in a day. Both are
extrapolations from one cycle.
