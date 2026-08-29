# Owner decisions — the 48-hour review's landing page

Seven decisions that only the owner can make, gathered off the issues and
PR bodies they were scattered across — **plus an eighth page at the end
that is not a design call at all: the order to land things in.** Round 2
of the gap assessment (PR #357) found the binding constraint has moved
from "what is missing" to "nothing has merged", and the landing sequence
is what that implies for the next two days. Each page is the same shape: **the
evidence**, **the options**, **a recommendation with its reasoning**, and
**what unblocks** when it is decided.

Nothing here needs code written to answer it. Every number quoted is
measured and says where it came from; where a number is *not* measured
that is said outright, because two of these decisions are about exactly
that.

**Where the evidence lives.** Decisions 5, 6 and the load figures are in
PR #341 and PR #319 (mine, measured on this machine). Decisions 2 and 3
rest on `D-20260828-inside-the-derive-phase`, which is in **open PR
#317** and not yet on `main` — so those numbers are quoted from that
PR's issues (#315, #316) rather than from a merged entry, and I have not
re-measured them. Decision 7's evidence is on `main` already, in
`D-20260818-fantasy-civs-supersede-the-historical-frame` and
`docs/status/fantasy-civs.md`.

---

## OWNER RATIFIED — 2026-08-29

**The owner's answer was "ratify all": every recommendation on this page
was accepted as written.** Each page below carries a datelined
**Ratified** note saying what it became and where the record now lives.

| # | Decision | Ratified outcome |
|---|---|---|
| **#285** | Discrete-GPU run | **Stays OPEN** as the owner's action item — ratified *pending hardware*; run it and host mode in one sitting |
| **#315** | Derive cadence | **CLOSED, declined for now** — revisit when #285's discrete numbers still miss 60 fps |
| **#316** | GDExtension hatch | **CLOSED, hatch stays shut** — same trigger; D-093's shape recorded if ever opened |
| **#289** | Host-quit | **CLOSED** — dedicated-first for long matches; the D-088/D-092 revisit's answer |
| **#341** | ~200-squad successor | **Accepted, owner-ratified** — including the seat-derived `squad_cap` |
| **#339** | Player-hosted ceiling | **Two numbers ratified** (dedicated ~200, hosted 100-150); tick-off-the-render-thread filed for cycle 2 |
| **#191** | `model_id` keying | **Per-civ override on an archetype default**; schema + four-civ art queue filed for cycle 2 |
| **8** | Landing sequence + freeze | **Freeze ratified until cycle 2**, which opens with the full-match measurement and one external alpha session |

**Two of these are deliberately not "done".** #285 stays open because it
needs hardware nobody has yet, and closing a ratified-but-unperformed
action is how it stops being anybody's; #339 is ratified as a *pair* of
numbers rather than one, because a host pays the tick and the frame out
of the same second and averaging them would overstate what a hosted
match survives.

**Nothing here was ratified into code.** Every outcome above is a
decision record or an issue action; the two engineering consequences
(#339's threading change, #191's schema change) are filed for cycle 2
rather than started, because the freeze is ratified too.

---

## Read this first: three of the seven are coupled, and one gates two others

They are not seven independent questions.

```
   #285  discrete-GPU run  ─────┐   every client number in the project
   (one afternoon, owner's       │   is from one Intel Iris Xe iGPU
    hardware, no code)           │
                                 ├──▶  #315  derive cadence   ─┐
                                 │     (costs fidelity)         ├── pick ONE
                                 └──▶  #316  GDExtension       ─┘
                                       (costs plain-text build)

   #341  ratify 200 squads  ────────▶  #339/#349  does player-hosted survive?
   (supersedes D-018)                  (host holds 100-150, not 200)
                                              │
                                              └──▶ #289  host-quit at 1-2h
                                                   (worse if hosted stays)
```

- **#285 gates #315 and #316.** Both are answers to "the client frame is
  ~7× a 60 fps budget", and that figure is from *one integrated GPU*. A
  discrete card could halve it, and one of the two answers stops being
  needed. **Deciding #315 or #316 before #285 is deciding on one data
  point.**
- **#315 and #316 are alternatives, not steps.** Each issue says so of
  the other. Pick one.
- **#341 → #339 → #289** is a chain about *where a match runs*. Ratifying
  the 200-squad scale makes the hosted breach a live problem; how that is
  answered changes how bad host-quit is.

**Suggested order: #285 first (it is an afternoon and it informs two
others), then #341, then #339, then the rest.** #191's art question is
independent of all of it.

---

# 1. #285 — the discrete-GPU run

> **Blocker. Owner action: nobody else has the hardware.**

### The evidence

**Every render number this project has ever taken is from one Intel(R)
Iris(R) Xe integrated GPU.** M5's LOD table, D-086's lighting cost,
#229's regression work, `D-20260828-the-shipping-scale`'s client column,
and `D-20260828-the-host-pays-both-budgets` — all of it, one adapter.
D-085's own rule is that a frame time is quoted *with* its hardware, and
that rule has been honoured; what has not happened is a second data
point.

D-085 criterion 11 and D-094 criterion 9 both require a discrete-GPU run,
and the trigger has been armed since **M5** without firing. It is one
afternoon: a native `just bench-render` on a borrowed machine, recording
the adapter string the harness already prints.

### The options

1. **Run it.** A borrowed or owned discrete GPU, `just bench-render`
   (and `just bench-render` in host mode, `--host=1`, while there — see
   #339).
2. **Ship the integrated number as the floor** and never take a second.
3. **Defer past M8.**

### Recommendation — **run it, and run the host mode in the same sitting**

Option 1, and specifically take **four rows**: `bench-render` at
0/100/200/400 squads, and `bench-render` in host mode (`--host=1`) on `islands` at the
same counts. The second costs the same afternoon and answers #339's
"is the hosted breach hardware or architecture" in one shot.

The reasoning is that **integrated graphics is the honest floor and a
terrible basis for a design decision**. It is right that the shipping
number is quoted against modest hardware — most players do not have a
4090 — but two of the decisions below propose *changing what this project
builds* on the strength of a frame time from a single iGPU. That is one
data point deciding an architecture.

There is one prediction worth recording before the run, so it can be
wrong: **the host breach will NOT go away.** #339 attributes it to the
46 ms simulation tick landing inside the render frame, and the tick does
not care what GPU is fitted. A discrete card should move the *client*
column and leave the *sim* column where it is. If it moves both, the
attribution in #339 is wrong and should be re-taken.

### What unblocks

- **#315 and #316** get a second data point before either changes what
  the project builds.
- **D-085 criterion 11** and **D-094 criterion 9** discharge.
- **`D-20260828-the-shipping-scale`'s client column** gains its second
  hardware row, and the 30 fps reference budget stops resting on one
  adapter.

### Ratified 2026-08-29 — **pending hardware, issue stays OPEN**

Ratified as recommended, and **#285 is deliberately NOT closed**: it is an
action the owner performs, not a question they answer. It is annotated
*ratified-pending-hardware*. Both runs happen in one sitting — the client
sweep and `--host=1` — because #315, #316 and the client half of #341 all
read the same numbers.

---

# 2. #315 — derive a distant squad at a lower cadence

### The evidence

*(From PR #317, not yet merged; not re-measured by me.)*

`D-20260828-inside-the-derive-phase` attributed the client frame. After
two bit-identical hoists there is **no hot spot left**: what remains is
~12 µs per drawn man spread across a ground sample (51%), formation math
(23%), per-squad setup (16%) and the passability clamp (10%). The
`atan2` everyone suspects costs 0.02 µs.

At 1,000 squads the client draws 4,385 men and the frame is ~118 ms of
CPU — about **7× a 60 fps budget**. Tuning arithmetic does not close
that. **But note the scale this is quoted at**: 1,000 squads is five
times `D-20260828-the-shipping-scale`'s decided 200, and at 200 the
client measures 29.4 ms / 34 fps. The 7× figure describes a count nothing
ships at.

The proposal is to re-derive a *distant* squad every second or third
frame, holding its transforms between. The simulation advances at 10 Hz
(D-020), so a squad re-derived at 20–30 Hz is showing the same curve
sampled at times nobody can distinguish — and it is distant, at LOD tier
2 or 3, five to twelve men.

### The options

1. **Hold exactly** between derives.
2. **Interpolate** toward the last derived pose — more convincing, more
   state.
3. **Do nothing**, and take #316 instead.
4. **Do nothing at all**, on the grounds that the shipping scale does not
   need it.

### Recommendation — **option 4 for now, and re-ask only if #285 says so**

This is not a D-006 objection. D-006 clause 2, as amended by
`D-20260819-tier-three-lives-on-the-render-side`, already permits
bounded, one-way, outcome-blind per-soldier render state that survives
frames — `SoldierMotion` is exactly that. A held transform is the same
kind of thing. **The boundary question the issue raises is genuinely
answered: this is allowed.**

The reason to decline is that **the problem it solves is at a scale that
was retired**. The 7× figure is at 1,000 squads; the decided scale is 200,
where the client sits at 34 fps with the 30 fps budget met. Spending
fidelity — a pop risk at the tier boundary, a distant melee that stutters
because held men do not ease — to fix a count nothing runs at is paying a
real cost for a hypothetical one.

If #285 shows a discrete GPU does *not* improve the client column
materially, or if the shipping scale is later raised, this returns. It is
a good idea aimed at the wrong number.

### What unblocks

- Nothing is blocked *by* it. Deciding it closes an open design question
  and stops it being re-raised each time the derive phase is profiled.
- If accepted, it needs a decision entry settling the four things the
  issue lists — what "distant" means in `RenderCull`'s existing tiers,
  hold-vs-interpolate, per-squad or per-tier, and the anti-pop rule.

### Ratified 2026-08-29 — **CLOSED, declined for now**

Ratified as recommended and closed. **Revisit trigger: #285's
discrete-GPU numbers still fall short of 60 fps.** Declining is not a
judgement that the idea is wrong — it solves a 1,000-squad problem at a
200-squad scale, and #341 ratified 200 as the scale.

---

# 3. #316 — D-021's GDExtension hatch

### The evidence

*(Same provenance as decision 2 — PR #317.)*

D-021 says GDScript only, and names its own escape hatch: *"if a specific
kernel is measured to exceed budget, the escape hatch is GDExtension
(C++/Rust) scoped to that kernel — and only on M4 profiling evidence, not
on suspicion."* **That evidence now exists**:
`Formation.soldier_transforms_sampled` is ~12 µs per drawn man, called
once per drawn squad and again per fighting squad, and it is the
single most-executed arithmetic in the client.

Crucially, **everything cheap has already been taken and is written
down**: vision's `distance()` per cell (M2), `UnitRoster.by_id` per
produced squad (M4), terrain noise per soldier (M5), the per-squad
building scan (M6), the flow-field neighbour lookup (D-20260818), the
separation over-scan (`D-20260828-the-m6-rise-has-a-name`). The remaining
cost is GDScript's per-operation price, not a missing optimisation.

### The options

1. **Open the hatch** for that one kernel, held to D-093's standard — one
   boundary, a grep test, absent-native degrades to the GDScript path.
2. **Keep it shut** and take #315's fidelity trade instead.
3. **Keep it shut and do neither** (see #315's recommendation).

### Recommendation — **option 3 now; option 1 if the scale ever rises**

Same reasoning as #315, and it is the stronger case for waiting: the
trigger is met *at 1,000 squads*, and the decided scale is 200.

Two costs deserve naming because they are not performance costs. **The
build stops being plain-text-editable** — which is the constraint the
entire project is built around, stated in CLAUDE.md's opening paragraph:
Godot was chosen *because* `.tscn`/`.tres` make this editable by Claude
Code. And **a native kernel must be bit-identical**, because both machines
derive from `Formation` and a divergence is the M1 desync from D-022's
audit block. That is testable exactly as #245's equivalence sweep is
(21,096 men, `assert_eq`, never `almost_eq`) — but it is a permanent
obligation on every future change to that function.

D-093 already amended D-021 once, for Steam, and confined it to one
boundary script with a grep test. **If this is opened, it should be held
to precisely that standard** — and the fallback matters more here than it
did for Steam: absent Steam costs Steam features, whereas absent native
must cost *speed only*, never the game.

### What unblocks

- Closes the oldest standing "when would we ever" question in D-021.
- If accepted, it sets the precedent for how the second such request is
  handled — which is why the D-093 shape matters more than the decision.

### Ratified 2026-08-29 — **CLOSED, the hatch stays shut**

Ratified as recommended and closed, with the same trigger as #315.
D-021's GDExtension hatch remains shut. If it is ever opened, the shape
to follow is **D-093's**: one boundary script naming the dependency, a
grep-test enforcing that nothing else does, and an absent dependency
costing the feature and never the game. Recorded now so re-opening starts
from a known shape rather than from scratch.

---

# 4. #289 — host-quit ends a 1–2 hour match

### The evidence

D-088 accepted **host-quit kills the match** and D-092 accepted **no
saves**, both with eyes open — and both were priced against matches that
were then deciding in about **three minutes**. D-056 moved the target to
**1–2 hours**, and `D-20260827-the-tree-is-the-ladder` is the progression
that makes a long match a real prospect rather than an aspiration.

The loss is now different in kind. A host quitting ninety minutes into a
20-seat match destroys ninety minutes for twenty people, with no save, no
migration and no rejoin. D-090's reconnection work covers a *player*
dropping — the seat becomes an AI and can be reclaimed by SteamID — and
covers the host not at all.

### The options

1. **Host migration.** Rejected in D-088; the re-examination is explicitly
   invited by this ticket.
2. **A rejoinable-replay checkpoint.** Replays are already byte-identical
   to the wire (D-016), so the material exists.
3. **Dedicated-server-first for long matches**, leaving player-hosted for
   short ones.
4. **Accept it**, and say so in the lobby.

### Recommendation — **option 3, and it is nearly free given #339**

Decide this *after* #339, because #339 may make it moot: if the answer
there is "dedicated-first", host-quit stops being the common case by
construction and this becomes a short-match concern only.

Option 3 is recommended because it is the same answer #339 already
pushes toward and it costs no new machinery. Option 1 is a substantial
piece of work whose failure mode is subtle (a migrated host must
reconstruct authoritative state that the other clients only have fogged
views of — D-004 makes that genuinely hard, and D-090's
drop-and-rejoin trick works precisely because a *joining* client is cheap
while a *promoted* one is not). Option 2 is attractive and I would want
it eventually, but a checkpoint that can be rejoined is a save by another
name and reopens D-092 rather than sidestepping it.

Whatever is chosen, **option 4's honesty should be part of it**: if a
hosted match can be ended by one person closing a window, the lobby
should say so before nineteen other people commit two hours.

### What unblocks

- D-092's "no saves" gets its revisit answered rather than left standing
  against a target it was not priced for.
- M8's playtest loop can state what happens when the host leaves, which
  a tester will otherwise discover the hard way.

### Ratified 2026-08-29 — **CLOSED, dedicated-first for long matches**

Ratified as recommended and closed, and recorded as the answer to the
D-088/D-092 revisit in
`decisions/D-20260828-host-quit-is-priced-against-a-match-length-nobody-has-measured.md`.
The match-length measurement this entry says nobody has taken is what
cycle 2 opens with.

---

# 5. #341 — ratify the 200-squad successor to D-018

> **Everything from M8 onward prices against this number.**

### The evidence

D-018's 20 players / 1,000 squads / 40,000 soldiers was set pre-M4 and
was amended on 2026-08-18 to say the successor **would be measured**, not
chosen (`D-20260818-battle-quality-outranks-player-count`, exit criterion
8). `D-20260828-the-shipping-scale` is that measurement.

**~200 squads / ~3,100 soldiers**, recommended shape **8 players × 25
squads**. Both budgets land there from opposite directions: the server's
**worst** tick crosses D-020's 100 ms between **180 and 240** squads, and
the client crosses 30 fps at **~200** on Iris Xe. A 13× reduction from
D-018, and it is the bill for the trade the owner already made when
battle quality was priced above headcount.

The second finding matters as much: **the budget is a TOTAL, not a
per-player allowance.** `squad_cap` is 40 per player and constant, which
makes the lobby's own 24-seat ceiling arithmetically impossible — 960
squads against a tick holding ~200.

### The options

1. **Ratify 200 / 8 × 25**, and derive `squad_cap` from the seat count.
2. **Ratify a different total** — the measurement bounds ~200 on this
   hardware; a lower number buys headroom, a higher one needs evidence.
3. **Keep D-018's 20 players** and accept ~10 squads each.
4. **Defer** until #285's discrete-GPU run.

### Recommendation — **ratify option 1, and treat the seat-derived cap as part of it**

The number itself is as well-evidenced as this project can make it:
independently measured on both sides, from opposite directions, landing
in the same place, with hardware named and two passes quoted.

The part worth ratifying deliberately is the **total**, because it is the
half that changes code. A seat-derived `squad_cap` makes a 4-seat and a
24-seat lobby both fit without anyone re-quoting a dead number, and the
machinery exists — `MapSettings.player_slots` already derives from the
seat count. It was not implemented in #341 on purpose: it changes a value
`MatchState.squad_cap_for`, the WELCOME message, the AI's refusals and
`docs/status/civ-knobs.md` all read, and it invalidates every load-test
figure taken against the current cap. **That is a change with a playtest
attached and it wanted this ratification first.**

Option 4 is defensible but note what it defers: the client column is the
one #285 would move, and the *server* crossing at 180–240 is unaffected
by any GPU.

### What unblocks

- **M8's 20-seat criterion** becomes answerable: 20 seats at ~10 squads
  each, evidenced by a *played* match rather than a sweep.
- **M9's tick budget** gets a scale to be a budget against.
- The seat-derived `squad_cap` change can be scheduled.
- `docs/status/civ-knobs.md`'s worst-case arithmetic gets re-based.

### Ratified 2026-08-29 — **Accepted, including the seat-derived cap**

`decisions/D-20260828-the-shipping-scale.md` moves **Provisional ->
Accepted, owner-ratified**, superseding D-018's 20-player /
40,000-soldier number. The seat-derived `squad_cap` is ratified *with*
it, not separately — a target that did not say where the cap comes from
would leave one number written down twice and free to disagree, which is
the shape this repo has already paid for more than once.

---

# 6. #339 / #349 — does player-hosted survive at 100–150 squads?

### The evidence

D-088 chose **player-hosted first, official dedicated later**, with the
host running the authoritative simulation *in-process* inside its own
client. `D-20260828-the-host-pays-both-budgets` measured that combination
for the first time. **It breaches.**

At the decided 200 squads the host runs at **19.9 / 35.6 fps** across two
passes — straddling the 30 fps budget and missing it in one. Its ceiling
is **100–150 squads**. And the cause is structural rather than gradual:
the client's own per-frame work is only **9–14 ms**, while the frame is
17–60 ms. The rest is **the authoritative tick landing inside the render
frame** — 46 ms at 200 squads, ten times a second, against a 33 ms
budget. It cannot fit by any scheduling, and the two passes disagree at
150 and 200 precisely because the frame rate depends on *how ticks land*.

### The options

1. **Take the tick off the render thread** (#349 option 1). Keeps one
   scale number for hosted and dedicated. Real work: Godot threading plus
   GDScript, not a flag.
2. **Hosted matches run at a lower scale than dedicated ones.** Cheap and
   honest; the shipping scale becomes two numbers and the lobby has to
   explain one of them.
3. **Slice the tick** across frames. Fits this project's habit (D-040
   slices a field, #106 slices terrain meshing) but is probably
   impossible: D-024 resolves a combat round against a snapshot.
4. **Dedicated-first**, reversing D-088's ordering.

### Recommendation — **option 2 now, option 1 scheduled, and let it pull D-088 toward dedicated-first**

Option 2 is the honest short answer and costs nothing but a number and a
sentence in the lobby: hosted matches cap at ~120 squads, dedicated at
200. It is truthful today and it unblocks M8's playtest loop immediately.

Option 1 is the right long answer and should be scheduled rather than
done reflexively — it is the only response that keeps one scale number,
and D-002 does not stand in its way (the server is already authoritative
and already has its own accumulator; D-023's explicit-accumulator rule is
*satisfied*, not violated — the accumulator simply runs on the only
thread there is).

**And this should be read as evidence about D-088's ordering.** That
entry chose player-hosted first partly because dedicated is
infrastructure nobody wanted to run yet. The measurement says dedicated
is not merely nicer at the shipping scale — it is the only configuration
measured to work at it. That does not automatically reverse the ordering,
but it should be a deliberate re-affirmation rather than an inherited
default.

Option 3 is worth one honest look before dismissal, and I expect it to
fail on D-024.

### What unblocks

- **M8's hosted 20-seat playtest** gets a squad count that will actually
  hold, instead of discovering the breach with twenty testers in the
  lobby.
- **#289** (host-quit) becomes easier or moot depending on the answer.
- `D-20260828-the-shipping-scale`'s 200 stops being ambiguous about which
  configuration it describes.

### Ratified 2026-08-29 — **two numbers, and the fix is scheduled**

Both figures are ratified as shipping numbers: **~200 dedicated,
100-150 hosted**. Taking the simulation tick **off the render thread** is
filed as a cycle-2 engineering ticket — the breach is structural (a 46 ms
tick cannot fit a 33 ms frame by any scheduling), so it is a threading
change and not a tuning one. Until it lands, size the M8 hosted playtest
loop to 100-150.

---

# 7. The #191 art question — `model_id` keyed by archetype, or by civ

> **No issue exists for this.** It is recorded as consequence 2 of
> `D-20260818-fantasy-civs-supersede-the-historical-frame` and in
> `docs/status/fantasy-civs.md`. It probably wants one.

### The evidence

`UnitDef.model_id` is keyed by **archetype, never by civ** — D-081's
reasoning, and `unit_def.gd` states it plainly: *"a model keyed by civ
would make civ three an art task exactly as a code branch would make it a
programming task."* Two human civs sharing a `levy` model was fine.

The fantasy pivot broke the premise. **A dwarf levy and a centaur levy
cannot wear the same mesh**, and no race-neutral shape exists that is
both — centaurs make it geometrically impossible. What shipped is an
interim the owner already called on 2026-08-26: Emberdeep wears the
supplied dwarf models, Gildedreach borrows the two surviving human ones,
**and the other four civs' units are the primitive capsule tier**. That
is the designed degradation (D-064) working, and it is also four of six
civs currently fielding capsules.

### The options

1. **Key `model_id` by (civ, archetype).** Honest, and multiplies the art
   bill by up to six — against D-081's "a new civ is a content job, not
   an art project" principle.
2. **Keep archetype keying and give each civ its own archetypes.** The
   fantasy rosters already lean this way (Barrow Shades, Bowriders,
   Gatebreakers are civ-exclusive), so shared archetypes shrink to levy /
   spearmen / archers / cavalry / heavy.
3. **A per-civ override list**, archetype-keyed by default with a
   `model_overrides` map for the ones that genuinely differ.
4. **Ship capsules for four civs** and revisit after the art pipeline is
   faster.

### Recommendation — **option 3, with option 2 as the design pressure**

Option 3 costs one schema field, keeps the default keying and its test,
and lets a civ that has a body wear it without the other five needing
one. It degrades exactly as today: no override, no model, capsule.

Option 2 should be the *design* preference behind it — every archetype a
civ owns exclusively is an archetype with no sharing problem, and the
rosters are already most of the way there. That is a content direction
rather than a decision to take today.

Option 1 is the one to avoid taking by accident. It is what happens if
overrides are added with no rule about when they are allowed, and D-081's
principle is worth defending explicitly: **a new civ should be a content
job.** Whatever is chosen should say how many models a seventh civ would
cost.

### What unblocks

- The art queue: four civs are currently capsules and nobody can schedule
  their bodies without knowing how models are keyed.
- `docs/status/fantasy-civs.md`'s "deliberately not done" list, which
  names this as the open one.
- The supplied stylised elf in the owner's asset batch, which is waiting
  on a rig and on this answer.

---

### Ratified 2026-08-29 — **per-civ override on an archetype default**

Ratified as recommended. `model_id` keeps its **archetype** default and
gains a **per-civ override**; the existing fallback is untouched, so a
civ with no authored body still degrades to the primitive tier exactly as
it does today (D-064). Filed for cycle 2: the schema change and the
**four-civ art queue**. Not started, because the freeze is ratified.

---

# 8. The landing sequence — and the feature freeze

> **Not a design decision.** Three of these are process calls only the
> owner can make, and they gate every other page above. Evidence is
> round 2 of the gap assessment (`docs/plans/gap-assessment-2.md`, PR
> #357) and the merge order (`docs/plans/merge-order.md`, PR #350).

### The evidence

**Round 1's cycle produced ~80 PRs and 0 merges.** That is not a failure
of the work — round 2 records that the estate produced sixteen of the
seventeen things a senior audit asked for, in a day — it is a failure of
the loop around it: *"eleven workers were each given a good ticket and
none was given a reason to stop."* The queue is still tractable at 80.
It will not be at 160, and the current assignment loop produces another
80 a day.

Three things are now true at once, and each makes the others worse.
**CI exists, is proven, and is guarding nothing** (#294, gap I2) —
including four deliberately-red runs recorded as evidence that each gate
fails when it should. **The decision record is ~70 entries behind
`main`** (#364, gap I3), which is not bookkeeping: this project *runs* on
that record, and gap I4 is two workers building the same static-defence
machinery twice because neither could see the other's design. And
**#350's ordering surfaced two things an ordering cannot fix** — PR #340
is not naval stage 8 but a *rebase* of the naval chain carrying 41 of its
62 files, and the hulls and dock are each **created** by three
independent chains.

### The options

1. **Land in dependency order from the top** (#350 as written, CI in its
   computed place).
2. **CI first, out of order, then decisions, then #350's order.**
3. **Merge by importance** rather than dependency, taking conflicts as
   they come.
4. **Keep assigning features while merging.**

### Recommendation — **option 2, and ratify the freeze that makes it possible**

Three calls, in this order:

**(a) Ratify the feature freeze for cycle 2.** This is the one that has
to come first, because it is the only one that stops the denominator
growing while the rest happens. Round 2's assignment rule is the concrete
form: *a worker's next ticket waits on its own previous PR merging, and
no chain deeper than 3*. Both are orchestrator-side and cost no
engineering. **Without it every hour spent merging is matched by an hour
of new queue.**

**(b) Merge #294 (CI) out of order, first.** It is nearly conflict-free,
and it makes each of the next ~79 merges verifiable by a machine instead
of by whoever happens to run a recipe. Note its own honest caveat: it is
stacked on #243 → #222 **for a green baseline**, because CI added to a
red `main` is CI that is red on day one — so those two land with it.

**(c) Merge #364 (the ~70 decision entries) second.** Conflict-free by
construction — one file per decision, which is precisely what
`decisions/README.md` rule 1 was written to buy — and it is the only
thing that stops gap I4 recurring in a session started tomorrow. The
record every worker reads becomes current *while* the merge runs, rather
than after it.

**Then #350's computed order, re-running its generator between landings
rather than trusting the first pass** — the document says so of itself,
and its three input snapshots are deliberately uncommitted because they
are stale the moment anything merges. **82's rehearsal log belongs
beside it**: a record of the order actually being walked, so a landing
that goes wrong is diagnosable against what was rehearsed rather than
against a plan. *(That log did not exist on any branch at the time of
writing — it is expected beside #350 rather than missing from it.)*

**Two owner calls sit inside the sequence and cannot be deferred past
it**, both from #350: whether **#340** is dropped or reduced to a delta
against the naval chain, and **which of the three chains** creating the
hulls and the dock is the one that keeps them. Merging both the naval
chain and #340 double-applies naval; and one decision id currently has
**two different documents** (`D-20260828-water-is-a-second-movement-domain`
is byte-identical on #343 and #340, and *different* on #308), which
`decisions/README.md` rule 1 forbids outright.

### What unblocks — and what cycle 2 opens with

Everything above. **Every recommendation on pages 1–7 assumes a tree
where the thing being decided about exists**, and today none of them are
on one.

Two openers, both of which are *impossible today* and neither of which is
new work:

- **The full-match measurement** (round 2's ticket 5). D-056's 1–2 hour
  target has been open since M6 and has never been answerable, because
  the farm, the ladder, surrender and the tech tree are on four different
  branches. On one tree it is a recipe run.
- **One external alpha session** with someone who has never seen the
  repo (D-094 criterion 10). Everything it needs is built. It is the only
  instrument in this project that can see what none of the others can.

Expect the merged numbers to be **worse than any branch's** — every
figure in this document, mine included, was taken without the other 79
PRs present. That is the point of measuring on the merged tree, and it is
worth saying before the first number lands rather than after.

---

## Summary table

**Ratified 2026-08-29 — the owner accepted every recommendation below
("ratify all"). The Outcome column is what each became.**

| # | Decision | Recommendation | Outcome (ratified 2026-08-29) | Gates |
|---|---|---|---|---|
| **#285** | Discrete-GPU run | **Run it** — plus host mode (`--host=1`) in the same sitting | **OPEN** — ratified pending hardware | #315, #316, and the client half of #341 |
| **#315** | Derive cadence | **Decline for now** — solves a 1,000-squad problem at a 200-squad scale | **CLOSED** — declined for now | — |
| **#316** | GDExtension hatch | **Keep shut for now**; D-093's shape if ever opened | **CLOSED** — hatch stays shut | — |
| **#289** | Host-quit | **Dedicated-first for long matches**; decide after #339 | **CLOSED** — dedicated-first | D-092's revisit, M8 playtest loop |
| **#341** | Ratify ~200 squads | **Ratify**, including the seat-derived `squad_cap` | **Accepted**, owner-ratified | M8's 20-seat criterion, M9's budgets |
| **#339** | Player-hosted at 100–150 | **Two numbers now, tick off-thread scheduled** | **Ratified** — cycle-2 ticket filed | M8's hosted playtest, #289 |
| **#191** | `model_id` keying | **Per-civ override on archetype default** | **Ratified** — cycle-2 ticket filed | The art queue for four civs |
| **8** | The landing sequence | **Ratify the freeze; CI, then decisions, then #350's order** | **Ratified** — freeze holds until cycle 2 | Everything above, and cycle 2 |

### Ratified 2026-08-29 — **the freeze holds until cycle 2**

Ratified as recommended, the out-of-order merges included. **The freeze
stands until cycle 2 opens**, and cycle 2 opens with two things, in this
order:

1. **the full-match measurement** — an uncapped match, run to a natural
   conclusion. Every entry above that depends on match length (#289 most
   directly, D-056 and D-068 behind it) is currently priced against a
   number nobody has taken;
2. **one external alpha session** — a tester who is not the owner, on an
   installed build, because #183's loop is what turns "it runs here" into
   evidence.
