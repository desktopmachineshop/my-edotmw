### D-20260828-the-shipping-scale · 2026-08-28 · Accepted — the shipping scale target, measured: ~200 squads, and the budget is a TOTAL

**Supersedes D-018's number.** The shipping target is **~200 squads and
~3,100 soldiers in a match**, not 1,000 squads and 40,000 soldiers.
Recommended shape: **8 players × 25 squads**.

**And the more important half: the budget is a TOTAL, not a per-player
allowance.** What both measurements bound is *squads in the world*, so
`squad_cap` should be derived from the seat count rather than being a
constant every seat gets — which is what makes a 20-seat lobby and a
4-seat one both fit, and what lets M8's 20-seat criterion be discharged
at all.

Issue #287, discharging
`D-20260818-battle-quality-outranks-player-count`'s **exit criterion 8**
("the maximum count holding D-020's 100 ms tick server-side and a stated
reference frame budget client-side … with hardware named … recorded in a
successor entry that supersedes D-018's number"). Unblocked by
`D-20260828-the-m6-rise-has-a-name` (#304), which built the instrument.

**D-020's 100 ms tick does not move.** D-018's amendment said what gives
is how many players fit inside it, and this is that number.

---

#### The server: `just profile scale`

Shipped 168×194 map, four sides, the world the server actually builds —
teams, civs, economy, buildings, research — 200 measured ticks after a
120-tick warm-up, best of 3 interleaved passes.

| squads | µs/squad | **ms/tick mean** | **ms/tick worst** |
|---|---|---|---|
| 60 | 234.55 | 14.07 | 30.3 |
| 120 | 252.80 | 30.34 | 62.0 |
| 150 | 209.08 | 31.36 | 81.8 |
| 180 | 203.40 | 36.61 | **91.1** |
| 210 | 175.96 | 36.95 | 74.7 |
| 240 | 196.11 | 47.07 | **116.7** |
| 480 | 166.43 | 79.89 | **218.8** |

**Read the WORST column, not the mean.** The mean fits D-020's budget
even at 480 squads; the worst tick crosses 100 ms between 180 and 240.
A mean that fits while the worst does not is a stutter a player feels,
and D-020's criterion has always been *ticks over budget*, not average
cost.

**Per-squad cost FALLS as the count rises** (234 → 166), which is the
fixed per-tick overhead amortising — the same effect
`docs/status/m1.md` warns makes low counts flatter a per-squad figure.
It is why the budget question has to be asked in milliseconds per tick.

**The worst column is spiky** — 210 reads 74.7 against 180's 91.1 —
because it is a maximum over 200 ticks and best-of-3 takes the minimum of
three maxima. That is why the crossing is stated as a band (180–240)
rather than a point.

#### The client: `just bench-render`, hardware named

**Intel(R) Iris(R) Xe Graphics** (integrated), Godot 4.7.1-stable, Vulkan
1.3.286 Forward+, shipped map, 120 measured frames per count. **Two
passes, both quoted** — one run is not a measurement.

| squads | soldiers | ms mean | fps | drawn | draw calls |
|---|---|---|---|---|---|
| 0 | 0 | 7.96 / 7.90 | 126 / 127 | 0 | 51 |
| 100 | 1,588 | 16.11 / 18.92 | 62 / 53 | 63 | 69 |
| **200** | **3,136** | **29.55 / 29.40** | **34 / 34** | 121 | 83 |
| 400 | 6,285 | 68.25 / 52.98 | 15 / 19 | 255 | 121 |

**The stated reference frame budget is 30 fps (33.3 ms) at 200 squads on
this hardware**, and it is met with a little room: 29.4–29.6 ms across
both passes, the tightest agreement anywhere in this entry. 60 fps costs
half of that — about 100 squads.

Terrain alone is 7.9 ms of every frame before a single soldier, which is
worth knowing: it is a quarter of a 30 fps budget spent on the ground.

#### Where they meet

**Both budgets land on the same number, from opposite directions**, and
that is what makes ~200 defensible rather than picked:

| | ceiling | at 200 squads |
|---|---|---|
| server, D-020's 100 ms worst tick | 180–240 squads | 36.6 ms mean, 91–117 ms worst |
| client, 30 fps on Iris Xe | ~200 squads | 29.4 ms, 34 fps |

**~3,100 soldiers against D-018's 40,000 is a 13× reduction, and it is
the trade the owner already made**: `D-20260818-battle-quality-outranks-player-count`
priced RTW battle quality above headcount and said the bill would be
measured rather than guessed. This is the bill.

#### The budget is a TOTAL — and that is the actionable part

`squad_cap` is 40 on all three shipped maps, per player, a constant
(D-056 raised it there; D-068 returned it to being an engineering ceiling
rather than a design lever). Against a **200-squad total** that is five
players, and it makes the lobby's own 24-seat ceiling arithmetically
impossible: 24 × 40 = 960 squads, nearly five times what the tick holds.

So the recommendation is not "cap the lobby at 8". It is:

> **`squad_cap` should be derived from the seat count**, so that the
> TOTAL is the constant — roughly `SQUAD_BUDGET / seats`, clamped to a
> floor below which a player has no army worth having.

`MapSettings.player_slots` already follows the seat count
(`D-20260817-starting-positions-follow-the-seats`), so the machinery to
know how many seats there are exists and is already used for exactly this
kind of derivation. At a 200 budget that gives 8 players 25 squads each,
4 players 50, and 20 players 10.

**Deliberately not implemented here.** It changes `squad_cap` — which
`MatchState.squad_cap_for`, the WELCOME message, the AI's refusals and
`docs/status/civ-knobs.md`'s worst-case arithmetic all read — and it
would invalidate every load-test figure taken against the current cap.
It is a change with a playtest attached, and this entry is the
measurement that justifies it. Same fence as
`D-20260828-the-phase-table-has-numbers`, for the same reason.

#### What discharges M8's 20-seat criterion

D-094's headline criterion is a 20-seat match with ≥3 real remote humans.
**It is not discharged by this entry, and this entry says precisely what
would discharge it:**

- **20 seats is reachable, at ~10 squads each.** That is the seat-derived
  cap above, and nothing measured here forbids it — 200 squads is 200
  squads however they are divided.
- **20 seats at the CURRENT cap is not**, and no amount of optimisation
  closes a 4.8× gap. Anyone re-quoting "20 players" without saying "at
  ten squads each" is quoting D-018's dead number.
- **The evidence needed is a played 20-seat match** — `just test-load 20`
  at the derived cap, reporting 0 dropped ticks and the worst tick under
  100 ms, plus the client figure above from a seat that can see a battle.
  The sweep cannot discharge it: *a green sweep is not a green server*
  (D-043), and the 20-player live match has still never been run.

#### The one thing neither measurement covers, and it may be the binding one

**D-088 makes the host a player**, running the authoritative simulation
*in-process* inside its own client. That host pays **both** budgets on
one machine, and nothing above measures the combination.

The arithmetic is not reassuring: at 200 squads the server wants
36.6 ms × 10 ticks = **366 ms of every second**, and the client wants
29.4 ms × 30 frames = **882 ms**. That is 1,248 ms of work per second,
and whether it fits depends entirely on how much of it can overlap
across cores — which this project has never measured and GDScript's
largely single-threaded execution makes an open question rather than a
safe assumption.

**So the host's ceiling is lower than 200 squads and is currently
unknown.** That is the next measurement, and it is **filed as #339**
rather than guessed at here.

**MEASURED 2026-08-28, and this trigger has fired**
(`D-20260828-the-host-pays-both-budgets`, #339). The host's ceiling is
**100-150 squads**, not 200: at 200 it runs at **19.9 / 35.6 fps** across
two passes, straddling the 30 fps this entry sets. The cause is not the
gradual contention the arithmetic above predicted — **the authoritative
tick runs inside the render frame**, and a 46 ms tick cannot fit a 33 ms
budget by any scheduling, so one frame in two is blown outright.

**The 200-squad number above therefore stands for a DEDICATED server and
does not stand for a host.** D-088's "player-hosted first, dedicated
later" is now a measured trade rather than a preference. The three
possible responses are #349 and the choice is D-088's, not a
measurement's.

Worth recording that the arithmetic above was wrong in an instructive
way: 366 + 882 = 1,248 ms/s predicted a hard breach, and the measured
totals are 734-908 — because **the frame rate collapses to make room**,
which an addition cannot show. A sum of two isolated measurements is not
a measurement of the combination.

---

#### Amended 2026-08-28 — the tick at this scale WITH the water layer, and what it does to #105

The orchestrator's question, and the right one: if the shipping scale is
~200 squads, what does the tick cost *at that scale* once naval's third
field layer is in it — and does #105's 1,000-squad breach still mean
anything?

`just profile water` is the section that answers it. **`islands`, 68.1%
navigable** — the most water-heavy preset, because a naval budget
measured on a map with no sea in it is not a budget — 200 squads held
constant with hulls REPLACING ground squads, since a fleet is a share of
an army and not a bonus one.

| hulls | ms/tick mean | ms worst | **fields** | combat |
|---|---|---|---|---|
| 0 | 38.68 / 39.37 | 91.7 / 97.6 | **20.38 / 20.31** | 103.20 / 105.16 |
| 10 | 36.43 / 36.92 | 85.5 / 93.9 | **20.65 / 20.46** | 88.81 / 90.22 |
| 20 | 33.93 / 50.41 | 59.6 / 161.6 | **15.64 / 20.96** | 83.89 / 126.96 |
| 40 | 33.76 / 37.33 | 68.6 / 102.9 | **19.67 / 20.37** | 76.92 / 86.80 |

Two quiet runs quoted; two more were taken on a loaded host and drifted
2× (the standing hazard). **Read the `fields` column** — it is a
within-phase measurement of identical work and it is the stable one, flat
at ~20 µs/squad across every run and every hull count.

**The water layer adds no measurable tick cost at this scale.** It is
inside the `fields` timing window (`_expand_pending_fields_water` sits
under `fields_started`), so this is not an omission — the layer is being
timed and it is not showing up. #343's own budget work is why: 24,576
cells/tick completes a cross-map water field on this map in one tick, and
the layer inherits D-20260818's neighbour-table fix for free.

**Adding hulls makes the tick slightly CHEAPER**, and the mechanism is
visible rather than inferred: combat falls monotonically (103 → 77) as
hulls replace ground squads, because ships spread over open sea engage
less and separate less than infantry. This is a composition effect, not
an optimisation.

**Headroom at the decided scale, stated plainly and not flattered:**

- **mean tick: ~38 ms against D-020's 100 — about 60% headroom.**
- **worst tick: 92–103 ms against 100 — essentially none.**

So 200 squads is **at the edge on the worst tick, not comfortably inside
it**, on the most demanding preset. That is the same conclusion the
server table above reached on the default preset (91.1 ms at 180), now
confirmed on a second preset with a third field layer running. It is why
the recommended shape is 8 × 25 rather than something nearer the ceiling.

**And #105's 1,000-squad breach stops being a breach.** The 204.5 ms
figure is real and its attribution stands (flow-field expansion, D-040
working as designed) — but 1,000 squads is **five times a scale nothing
ships at**. Measured against the decided number the same sweep is 38 ms
of a 100 ms budget. The correct reading is not "the tick is over budget",
it is "the tick is over budget at a count the game does not run at", and
`docs/status/m10-plan.md` said the former for a milestone. Recorded on
#105 itself with this trail.

**Nothing was recovered in this pass, and that is the honest report.**
The free recovery in this area was taken in
`D-20260828-the-m6-rise-has-a-name` (separation's stale scan radius).
What dominates now is combat, which is a priced design trade, and the
water layer, which costs nothing. There was no third thing.

#### Owner ratified 2026-08-29

**The owner ratified this entry outright** ("ratify all", against the
recommendation on page 5 of `docs/plans/owner-decisions.md`), which moves
it from Provisional to **Accepted** and supersedes D-018's 20-player /
40,000-soldier number as the figure this project builds against.

**The seat-derived `squad_cap` is ratified WITH it, and that is the half
worth naming.** The recommendation put the two together deliberately: a
scale target that did not say where the cap comes from would leave the
same number written down twice and free to disagree — which is the shape
this repo has paid for repeatedly (D-058/D-065, and `civ-knobs.md`'s
three knobs read by nothing). Ratifying the target without the
derivation would have re-opened exactly that gap.

**What this does NOT ratify:** the hosted figure. That is #339's, and it
is ratified separately in
`D-20260828-the-host-pays-both-budgets` — dedicated ~200, hosted
100-150. A single "the scale is 200" would have quietly claimed a number
the host measurement contradicts.

#### Rejected alternatives

- **Keep 20 players and cut squads per player to ~10 without saying so.**
  Rejected — it is the same number meaning something completely
  different, which is exactly how D-018's figure survived being wrong for
  four milestones.
- **Pick the number from the sweep's 1,000-squad row.** Rejected: the
  count sweep runs a BARE simulation (no teams, buildings, economy or
  four-sided combat), which is why #304 needed a separate harness at all.
  Its 1,000-squad figure is not a match.
- **Quote the mean tick and declare 480 squads viable.** Rejected — the
  worst tick at 480 is 218.8 ms, two whole tick budgets, and D-020's
  criterion is ticks over budget.
- **Wait for a discrete GPU before stating a client number.** Rejected —
  D-085's rule is that a frame time is quoted WITH its hardware, not that
  it may only be quoted on good hardware. Integrated graphics is also the
  more honest floor for a game that ships to strangers. The discrete-GPU
  re-run trigger stays armed, as it has since D-085.
- **Treat ~200 as a hardware limit to be optimised away.** Rejected as a
  misreading: `D-20260828-the-m6-rise-has-a-name` attributes the server
  side to combat's contact set, which is a *priced design trade* bought
  deliberately for frontage and envelopment. Buying the player count back
  means selling the battle quality back.

#### Consequences

- **D-018's 1,000 squads / 40,000 soldiers stops being the reference
  scale for quoting measurements.** Anything sized against it —
  bandwidth, MultiMesh counts, the load-test bot shape — is sized against
  a number 13× too large. None of that is wrong, it is just slack.
- **`docs/status/civ-knobs.md`'s worst case is re-based.** It pins 880
  squads at 20 players and 1,056 at 24 seats from `CivDef.squad_cap_bonus`;
  both are far past this budget, and both become moot under a
  seat-derived cap.
- **M10's #105 conclusion is unchanged but re-scoped**: the 1,000-squad
  sweep being over budget (204.5 ms) stops being a shipping problem and
  becomes a headroom question, because nothing ships at 1,000 squads.
- **Nothing may quietly re-quote 20 players**, which was D-018's
  amendment's own instruction, and it now has a number to be quoted
  instead.

#### Revisit trigger

**The host-pays-both measurement**, which could lower this number and is
the first thing that should be taken against it. And D-085's standing
one: a discrete-GPU `bench-render` moves the client column, and if it
moves it far enough the client stops being the binding constraint and the
server's 180–240 band becomes the whole answer.

---
