### D-20260828 · Provisional — food is GROWN, not only found: the farm

**Decision:** A **farm** is a building that **grows** a resource at a
**rate**, and an ordinary gatherer crew works it through D-028's existing
haul cycle. It ships as `buildings/farm.tres` — 80 wood, 15 s, grows
**food** at **1.2/s** into a **180**-unit buffer, 400 HP, no attack, and
**does not block movement**, because the crew has to stand on it.

Four schema fields carry it (D-010), all with named readers:

| field | default | read by |
|---|---|---|
| `BuildingDef.grows` | `"none"` | `Economy.grows_kind` -> `Economy.sync_farms` |
| `BuildingDef.grow_capacity` | `0` | `Economy.sync_farms` |
| `BuildingDef.grow_per_second` | `0.0` | `Economy.sync_farms`, `Economy.tick` |
| `BuildingDef.blocks_movement` | `true` | `BuildingSim.blocking_cells` |

Nothing new crosses the wire. A farm is a BUILDING, and buildings are
already replicated and already fog-gated knowledge (D-030); a client
derives "that cell is worked for food" from the def it already has, the
same way D-20260825 derives which tool a gatherer draws from
`ClientState.nodes`.

---

**Rationale — the ceiling is a STOCK, and the fix has to be a RATE.**

Issue #159's finding is not a balance one. Every resource on the map comes
from a finite node, so a match's total economy is fixed at generation and
a long match is not slow, it is **impossible**: past the sum of what was
placed, nobody can build anything. D-056 set the target at 1-2 hours and
already recorded that tuning building health does not reach it; D-068 puts
first contact at 22 minutes and the decisive battle after 75, and then
makes an army a **running cost** — which is strictly worse against a fixed
stock, because a running cost against a finite pool is a countdown.

The two sides of D-068's ledger have to be the same KIND of quantity.
Upkeep is food per second; so the answer to it is food per second, not a
bigger pile. That is the whole shape of this decision: **a farm does not
add stock, it adds income**, and a player's sustainable army is
`total farm rate / per-soldier upkeep` — an equation that exists the
moment upkeep lands and cannot be written at all today.

**Why the crew still works it, rather than the farm paying out on its
own.** A building that trickled food into the wallet would be four lines
and is wrong three times over:

- It breaks D-028's central claim that income scales with `alive`. A
  player with every worker dead would have their full food income, and
  killing workers would stop meaning anything — which deletes D-068's
  "raiding must be strategy, not flavour" in the same stroke that
  decision asks for it.
- It leaves a crew whose forest is exhausted with **nothing to do**. That
  is today's late game, and it is the thing #159 is about.
- The genre answer is a worked field, in every game this project names as
  a reference. A crew standing in a crop is also the only picture that
  says "this is where your food comes from".

Worked, the farm reuses all of it: one curve, one flow field, one network
entity, output scaling with `alive`, fog gating free (D-028's own
argument, verbatim). `Economy.order_gather`, `_gather`, `_try_unload` and
`_retarget` each gained a farm branch and no new machinery.

**Why a BUFFER as well as a rate.** Stock accrues at `grow_per_second` up
to `grow_capacity` whether or not anybody is working it, and a crew takes
whatever has grown. Three consequences, all wanted: a fresh farm yields
**immediately** rather than after a fill-up; a farm left alone while its
crew hauls is not wasting its rate; and **the steady state per farm is the
regrow rate no matter how many crews stand on it**, so more income means
more farms, which means more wood and more ground — a decision — rather
than more workers on the same square.

**The numbers, derived rather than picked.** Every shipped gatherer is
`squad_size` 7 x `gather_rate` 0.28 = **1.96/s** raw with `carry_capacity`
45, so a crew fills in 23.0 s and then walks a round trip. A levy squad is
48 food on a 10 s `build_time`, so **one barracks running flat out eats
4.8 food/s**.

- **1.2 food/s** per farm: four farms sustain one barracks continuously,
  and one crew per farm is the natural ratio because the crew's raw 1.96
  exceeds it while hauling eats the difference. It is deliberately BELOW
  a crew's effective rate on a fresh nearby forest — a farm should be the
  economy you build when the good ground is gone or contested, not the
  one that makes chopping pointless.
- **180 capacity**: four carry-loads, 150 s of unworked growth. Long
  enough that a farm planted early is worth something when a crew reaches
  it, short enough that banking is not a strategy.
- **80 wood, 15 s**: the farm's own output pays its price back in about a
  minute, but the price is not the point — the **conversion** is. A
  one-time wood cost buys perpetual food, which is what removes the
  ceiling.
- **400 HP and no attack**: a farm is deliberately soft. D-067's "one
  squad must fail, two must succeed" is a rule about DEFENDED buildings;
  a field is not one, and a raid that burns a farm line should pay.

**Wood becomes the strategically finite resource, and that is chosen.**
Food is unbounded now; wood, gold and stone are not. That is the standard
shape, it gives the map's remaining nodes a job worth fighting over, and
it means "renewable" did not quietly become "infinite".

---

**Rejected alternatives:**

- *A passive trickle building.* Rejected for the three reasons above; the
  decisive one is that it makes worker-killing pointless and so deletes a
  D-068 requirement.
- *Regrowing forests.* Rejected. D-087 made nodes deplete **on purpose**
  and built crew auto-retarget and a felling animation on top of that;
  regrowth would make the felling a lie and un-decide D-087 to solve a
  problem a new building solves without touching it. It also removes the
  map's only remaining scarcity (see above).
- *Expiring farms that must be re-seeded for wood.* Rejected — re-seeding
  is a micro tax, and more importantly a farm that costs wood every N
  minutes is a **fixed exchange rate against a finite pool**, so the
  ceiling comes straight back one level up. The whole point is that the
  renewable thing must be renewable without an input.
- *Trade / a market for the metals.* Not rejected — **deferred, named**.
  #159 lists it as optional and it is a second economy with its own
  decisions (routes? a rate? a partner?). The schema here is already
  general (`grows` names a resource kind, not food), so a later
  woodlot or quarry is a `.tres` file and no code; a market is not.
- *A food-only schema (`grows_food: bool`).* Rejected for exactly that
  reason: the same three fields answer "a renewable of any kind" at no
  extra cost, and the alternative would have to be widened by a code
  change the first time anyone wants a coppice.

---

**Consequences:**

- **`BuildingDef.blocks_movement` is a new way for a building to be, and
  `blocking_cells()` is its only reader.** A farm must be walkable or the
  crew can never reach the cell it is told to work — `Economy` decides a
  crew has arrived by comparing `sim.cell_index_of(squad)` with the work
  cell. This is the first building in the roster that stands somewhere a
  squad may also stand, and every existing def keeps the default.
- **The farm registry is DERIVED from the buildings, never accumulated.**
  `Economy.sync_farms(BuildingSim)` rebuilds it from the living, complete
  buildings, and it runs from inside `server._refresh_passability()`.
  That is not tidiness: every path that raises or loses a building must
  ALREADY call that function or ground passability would be wrong, so
  hanging the derivation off the same call makes it impossible to add a
  building path that remembers one and forgets the other (#119's lesson:
  the handover nothing performs is the dangerous half). The function
  keeps its name because comments across `server.gd` cite it. Stock
  already grown survives a resync; a razed farm's entry does not. The one
  exception is `Scenario.apply_player`, which does not refresh
  passability at all today — a pre-existing gap, not fixed here — and so
  syncs explicitly, with a comment saying which gap it is inheriting.
- **The AI and the load-test bots farm.** `ai_player` wants farms once it
  has something that trains troops, up to `AiProfileDef.farms_wanted`,
  and `BotBuildPlan` asks for one per hauling crew up to a cap — because
  a feature no harness exercises is this project's most-repeated defect,
  and a renewable economy only a human ever builds would be exactly that.
  `test-load`'s verdict reports `farms_built` and `farm_food` beside the
  existing counters — METRICS, not gates, for D-087's own reason: a farm
  needs an opening plus 80 wood, and gating on it would re-set D-031's
  stale-timing trap.
- **Timings tuned against a food-limited economy are stale**, the standing
  rule. Nothing in the OPENING changed — a farm costs wood a player does
  not have at t=0 — but anything measured past the two-minute mark is now
  measured against an economy that does not run out.
- **This does not by itself reach 1-2 hours, and is not claimed to.** It
  removes the reason the target is *impossible*. D-056's structural cause
  (no progression) is #206 / PR #225's tech tree, and D-068's upkeep is
  unbuilt. What this buys is that both of those now have a resource
  economy they can be priced against.

**Coordination:** the tech tree (#206, PR #225) reserves no farm tech —
checked against that branch, 2026-08-28. `farm` ships **ungated**, on that
PR's own list beside the barracks, storehouse, tower and wall family, so a
player has a renewable economy from rung one. If the ladder later wants a
farm-efficiency line, `grow_per_second` is a building field and that PR's
effect vocabulary already admits building fields.

---

**Measured, 2026-08-28** — `just test-load 4 150`, default map, docker,
on a host running several other agents' worktrees:

**`VERDICT ok`, `test-load: clean`.** 0 desyncs over 574 state-hash
checks, 0 dropped ticks, all three `gate-check.sh` comparisons green
(fog gated 14 of 32 squads and 5,010 of 5,592 nodes from the
best-informed bot; 4 of 6 civs fielded). `casualties_applied=57
conceal_events=42 reveal_events=28`. **`farms_peak=1 field_orders=1`** —
a bot raised a field and put a crew on it, so the renewable path is
exercised through the real wire and not only in unit tests.

**179.70 µs per squad-update at 32 squads** (fields 32.44, curves 10.15,
vision 28.03, combat 71.10, buildings 12.52, production 1.91, **economy
10.86**, separation 13.10). Quote it with the squad count, as ever — this
figure is at 32 squads where `docs/status/m10-plan.md`'s 167.7 is at 48,
and per-tick fixed overhead lands in the per-squad number and inflates it
when squads are few. **No A/B against `main` was taken**, and the honest
reason it is not needed for THIS number is that the change does almost no
work in a run with one farm in it: `sync_farms` iterates the building
list only when a building is raised or lost, and the growth loop iterates
one entry per tick. An earlier run of the same build measured 223.47 at
the same 32 squads on a more loaded host, which is the size of the noise
here.

**A second finding, and the reason this entry has a measurement section
at all: the first version of the bots' build order shipped a rule
nothing could ever reach.** Producers first and fields after is the
obvious ordering and is what `ai_player.gd` argues for — but
`_raise_buildings` SAVES for what it wants rather than falling through to
something cheaper, and a barracks is 150 wood against a bot's 140-200
`wood_peak` over 120 s. Measured twice, on `test-load 4 120` and on
`test-scenario siege 4 90`: `farms_peak=0 field_orders=0`, every bot
reporting `cannot afford barracks`. **That is D-061's harder variant —
fully written, correctly called, standing behind a branch nothing reaches
— arriving inside the change written to avoid exactly that.** The bots
raise ONE field before they start saving, and the rest after; the AI
keeps producers-first because it saves too but its matches are long
enough to reach a barracks. `farms_peak` and `field_orders` are what made
the difference visible in one run, which is the argument for reporting
two numbers rather than one.

**Owed:** a `just ai-ladder` run on this build. The AI's fields are
reachable (a unit test drives `_wanted_count` and `_wanted_buildings`
against the shipped roster) and no played match has yet confirmed an AI
raises one — the same gap the bots turned out to have, and the only
instrument that can close it is the ladder.

**Revisit trigger:** upkeep landing (D-068). The moment a soldier costs
food per second, `grow_per_second` and `grow_capacity` stop being
free-standing numbers and become one half of a ratio — re-derive both from
the upkeep rate rather than tuning either alone, which is precisely the
failure D-056 recorded. Also fires if a `just ai-ladder` run on the six
shipped civs shows a side winning on farm count rather than on its axis.

---
