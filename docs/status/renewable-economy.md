**Food is GROWN now, not only found (D-20260828, #159, 2026-08-28).**
Every resource came from a finite node, so a match's whole economy was
fixed at generation and D-056's 1–2 hour target was not slow to reach, it
was **impossible**: past the sum of what the generator placed, nobody
could build anything. `buildings/farm.tres` is the answer — a building
that GROWS food at a rate, worked by an ordinary gatherer crew through
D-028's existing haul cycle. Build one with **J**, or from the civic
column of the build menu.

Six things to know before touching any of it, and most are not about
farms:

- **A farm adds INCOME, not stock, and that is the whole point.** D-068
  makes an army a food drain per second, so the answer to it has to be
  food per second — a bigger pile is a longer countdown, not a fix. A
  player's sustainable army becomes `total farm rate ÷ per-soldier
  upkeep`, an equation that could not be written at all before this.
  **The steady state per field is its own regrow rate however many crews
  stand in it**, so income is raised by owning more fields (more wood,
  more ground, a decision) rather than by piling workers on one square.
- **The crew still works it, and that was not a style choice.** A
  building that trickled food into the wallet is four lines and breaks
  D-028's central claim that income scales with `alive` — a player with
  every worker dead would keep full income, which deletes D-068's
  "raiding must be strategy, not flavour" in the same stroke that
  decision asks for it. It also leaves a crew whose forest is exhausted
  with nothing to do, which is the late game #159 is about.
- **A field does not block movement, and `BuildingDef.blocks_movement`
  has exactly one reader** (`BuildingSim.blocking_cells`). `Economy`
  decides a crew has arrived by comparing its cell with the work cell, so
  a farm that blocked its own cell would be a building nobody could ever
  work — with every other number healthy. First building in the roster
  that stands where a squad may also stand.
- **The farm registry is DERIVED from the living buildings, never
  accumulated.** `Economy.sync_farms(BuildingSim)` runs from
  `server._refresh_passability()`, because every path that raises or loses
  a building must already call that or ground passability would be wrong
  — so hanging the derivation off the same call makes it impossible to add
  a building path that remembers one and forgets the other (#119's
  finding: the handover nothing performs is the dangerous half). The one
  exception is the scenario path, which does not refresh passability at
  all today (a pre-existing gap, not fixed here) and so syncs explicitly.
- **A field belongs to somebody.** A node is unowned ground and anyone may
  work it — D-028, unchanged — but a farm is a building somebody paid for,
  so `Economy.may_work` admits its owner and its allies (D-050) and
  nothing else. Both the ORDER path and `_retarget` ask it: a rule only
  the order path enforces is not enforced, because `_retarget` walks the
  disk nearest-first and an enemy's field two cells away is exactly what
  it would take.
- **Nothing new is on the wire.** A field is a BUILDING, already
  replicated and already fog-gated knowledge (D-030), so the client
  derives "that cell is worked ground" from the def it already holds —
  `ClientState.farm_cells()`, the same shape as D-052's colour and
  D-20260825's tool choice. It is also why the farm's node is deliberately
  NOT in `Economy.nodes`: it would have grown a forest's worth of tree
  props on top of somebody's field.

**Wood is the strategically finite resource now, and that is chosen.**
Food is unbounded; wood, gold and stone are not. A farm converts a
one-time wood cost into perpetual food, which is the standard shape and
keeps the map's remaining nodes worth fighting over — "renewable" did not
quietly become "infinite". **Trade for the metals is deferred, not
rejected**; #159 lists it as optional and it is a second economy with its
own decisions. The schema is already general (`grows` names a resource
KIND), so a later woodlot or quarry is a `.tres` file and no code.

**The AI and the load-test bots farm, because a feature no harness
exercises is this project's most-repeated defect.** `ai_player` wants
`AiProfileDef.farms_wanted` fields once it has something that trains
troops (2 / 4 / 6 across cautious / balanced / relentless — the first
genuinely long-game difficulty axis in that file); `BotBuildPlan` wants
`FIELDS_WANTED` and `bot_client` puts one crew on each. `test-load`'s
verdict carries **`farms_peak` and `field_orders`** — two numbers, not
one, for the reason `military_peak` sits beside `raid_orders`: "nobody
could afford a field" and "fields were raised and never worked" are
different faults with the same symptom. **Both are METRICS, not gates**,
because a farm needs an opening plus 80 wood and the shipped map already
leaves two of four bots short of a barracks at 420 s — gating would fail
honest runs and re-set D-031's stale-timing trap for the fourth time.

**A bot raises ONE field before it starts saving for a barracks, and that
ordering was measured rather than preferred.** Producers-first is the
obvious order and is what `ai_player.gd` argues for — but a bot SAVES for
what it wants rather than falling through to something cheaper, and a
barracks is 150 wood against a bot's 140-200 `wood_peak` over two
minutes. Measured on `test-load 4 120` and on `test-scenario siege 4 90`:
`farms_peak=0 field_orders=0`, every bot reporting `cannot afford
barracks`. **A rule fully written, correctly called, and standing behind
a branch nothing reaches** — D-061's harder variant, arriving inside the
change written to avoid it. One field, not three: at 80 wood it delays
the barracks by about half a hauling round trip. The AI keeps
producers-first, because it saves too but its matches are long enough to
reach a barracks; **a played ladder run confirming an AI actually raises
one is still owed.**

**The gate, measured 2026-08-28** — `just test-load 4 150`, default map,
docker, on a shared host: **`VERDICT ok`, `test-load: clean`**, 0 desyncs
over 574 state-hash checks, 0 dropped ticks, all three `gate-check.sh`
comparisons green, `farms_peak=1 field_orders=1`. **179.70 µs per
squad-update at 32 squads**, of which the economy phase is 10.86 —
**quote it with the squad count**, since `docs/status/m10-plan.md`'s
167.7 is at 48 and per-tick fixed overhead inflates the figure when
squads are few. An earlier run of the same build measured 223.47 at the
same 32 squads on a busier host, which is the size of the noise.

**Every ladder and load-test number taken before this was measured against
an economy with a hard ceiling**, and the AI now spends wood on fields it
used to spend on something else. Quote a result with which side of this
change it came from, alongside the standing quote-it-with-its-cap,
-its-squad-count and -its-roster rules.

**This does not by itself reach 1–2 hours and does not claim to.** It
removes the reason the target was *impossible*. D-056's structural cause
— no progression — is #206 / PR #225's tech tree, and D-068's upkeep is
still unbuilt; what this buys is that both now have a resource economy
they can be priced against. The farm ships **ungated** by the tech tree
(checked against that branch: it reserves no farm tech), so a player has a
renewable economy from rung one.

**Two numbers worth knowing before tuning anything.** A shipped gatherer
crew is 7 × 0.28 = **1.96 units/s** raw with `carry_capacity` 45; a levy
squad is 48 food on a 10 s build, so **one barracks running flat out eats
4.8 food/s**. The shipped farm's 1.2/s makes four farms one continuously
producing barracks, and one crew per farm the natural ratio. When upkeep
lands, re-derive `grow_per_second` and `grow_capacity` *from the upkeep
rate* rather than tuning either alone — that is D-056's own recorded
failure.

---

**And the metals: a vein runs deep, it does not run out**
(`D-20260828-a-vein-runs-deep-it-does-not-run-out`, #277, 2026-08-28).
The farm answered food. A worked-out **gold or stone** node now regrows
toward a small tail capacity at a slow permanent rate instead of dying, so
the map's metal budget stops being fixed at generation.

**The measurement is the part to carry**, because it changes what the
issue was about. Generated from `maps/default.tres` at seed 1337 —
168x194, 32,592 cells, 20 seats:

| kind | nodes | total stock | per seat | cells per node |
|---|---|---|---|---|
| food | 1,939 | 203,595 | 10,179 | 16 |
| wood | 3,435 | 360,675 | 18,033 | 9 |
| stone | 137 | 328,800 | 16,440 | 237 |
| **gold** | **48** | 115,200 | **5,760** | **679** |

- **Wood is not the blocker.** One node every nine cells and about 120
  barracks per seat. #277 lists wood beside the metals and the map does
  not agree, so **no wood mechanism was built** — and the one that was
  considered (regrowth on D-087's per-cell stock) is the only change here
  that would have strained a player-visible promise, because a regrown
  tree has to *appear*. The cheapest way to keep the felling animation
  truthful was not to make a change that strains it.
- **Gold is.** 48 nodes on the whole map, on the mountain perimeter
  (D-087) — the contested ground. Per-seat totals flatter it badly: a
  player reaches one or two veins, and one vein at a crew's ~1.96/s is
  gone in roughly **twenty minutes**, a wall inside the first third of a
  1–2 hour match.

**Why the SITE and not a building, which is the design call.** A farm is
right for food because food comes from worked land and land is
everywhere; that is exactly why it is the wrong shape for metal. A mine a
player could raise anywhere would delete map control from the late game in
the same stroke that D-039's scattered spawns and D-087's ore placement
exist to create it. The renewable metal has to be *the place*.

Four things worth knowing before touching it:

- **It costs nothing new anywhere.** No building, no schema, no wire
  message, no client change, no animation. A vein never reaches zero, so
  it never enters `_depleted` and no felling is sent — and node stock is
  not replicated at all (`net_protocol.gd`: *"Their remaining STOCK is not
  sent"*), so a regrowing vein is invisible on the wire and the outcrop
  simply stays drawn, which is truthful.
- **The tail is a FLOOR, not a refill.** Only a vein already below its
  tail capacity regrows, so a fresh 2,400 seam is untouched and the
  opening is still a race for rich ground. Rates are far below a live
  seam by construction: gold 0.25/s and stone 0.4/s against a crew's
  ~1.96/s.
- **Capacity buffers; the rate is the income.** Ten minutes of regrowth
  each, so a vein left alone covers a raid or a rebuild and no more —
  the same job `BuildingDef.grow_capacity` does for a field.
- **The fractional carry is load-bearing.** 0.25/s at a 10 Hz tick is
  0.025 a tick, and an integer-only version adds `floor(0.025) = 0`
  forever: the mechanism correct and the shipped numbers doing nothing,
  which is D-055/D-066's family. A test drives one tick and forty.

**A market is deferred, named, and waiting on the tech tree.** A flat
exchange between a renewable resource and a finite one puts an unbounded
ceiling straight back, so trade wants to arrive *with* the tech that
improves its rate (#206 / PR #225). The deep mine is the floor; trade is
the strategic layer on top of it.

**Every ladder and load-test number taken before this** was measured
against an economy with a hard metal ceiling, and holding the mountain
perimeter now pays indefinitely — expect longer matches before anything
else.
