**The AI builds and uses static defence, and D-076's standing gap is
closed** (`D-20260828-an-ai-that-fortifies`, #337, 2026-08-28). CLAUDE.md
has carried the gap since D-076 landed: *no AI builds walls, gates or the
wall-top tier, so `just ai-ladder` cannot exercise any of that feature* —
the defect class that left `BuildingSim.damage()` uncalled for two
milestones (D-055).

```
just ai-ladder 1 420 2        # gates on a defence STANDING in a played match
just test-load 4 300          # bots build one gate and work it
```

**The root cause was not what the issue said, and it was worth more than
the walls.** The AI *looked* able to build them — every member of the wall
family passes `can_build(gatherers)` and produces nothing, so all of them
sat in `_wanted_buildings`'s support list. Measured on `main`,
`just ai-ladder 1 300 2`:

```
player 1000  buildings~2.0   first_attack=never
player 1001  buildings~2.0   first_attack~137s
```

**Two buildings each, all match.** `_kinds_below_floor` returned FOOD and
WOOD and nothing else, so **the AI has never gathered stone or gold in any
match ever played**. Every wall, gate and tower costs stone, so all of
them were unaffordable by construction — and because `_raise_buildings`
SAVES for what it cannot afford rather than skipping it, the
alphabetically-first support building (`garrison_gate`, 110 stone)
stalled the queue behind it and no storehouse was ever built either. The
feature was not merely unexercised by the ladder; it was **unreachable by
the economy**, and the ladder was right.

Seven things to know:

- **An AI gathers what its next purchase costs.** That is the fix, and it
  is general: naval's docks are another building whose price is not food,
  so stage 7 inherits it rather than rediscovering it.
- **The decision is shared with naval stage 7; the geometry is not.**
  `ai_investment.gd` answers "is now the moment to spend on something I
  have not got?" and **names no wall, gate, tower, dock, ship or shore**
  — a source scan in `tests/test_ai_investment.gd` enforces it, because
  that is not something a behavioural test can see. `wall_plan.gd` is the
  half that knows what a wall is, and `ai_naval.gd` is the half that
  knows what water is.
  **That sharing is real as of #365 and was not when this landed:** stage
  7 had been written in parallel with its own copy, and
  `D-20260828-one-ai-investment.md` is the third-party reconciliation —
  one file, both callers, with the case/threshold split that neither
  original had. `static_defence.gd` is gone; every function and every
  measurement below is unchanged inside it.
- **A screen, not a ring, and that is arithmetic.** A ring at radius 5 is
  30 cells — **900 wood and 1,200 stone** at the shipped price. An arc
  across the approach is five segments at 150 wood and 200 stone, and it
  is also the shape worth having at this match length.
- **Contact is a case in itself.** The first model treated fortifying as
  a response to being *hit*, and never fired: over two 300 s and one
  420 s run, `defences_ordered=0` on every seat, while one reported
  `buildings_lost=2 attacks_survived=43`. The only seat with a case was
  the one already losing, which by then had no barracks and so failed the
  precondition. The threat horizon is **half the way to the nearest other
  start** rather than a flat radius, because on the shipped ladder map
  two seats are further apart than any constant worth having.
- **Using a gate means CLOSING it.** "Set every gate to AUTO" is
  **vacuous** — new gates already start in auto mode, so the packet
  changes nothing and a counter of those packets passes against an AI
  that never used a gate. Sealing one is a real decision: an auto gate
  opens whenever the owner's own squad is within `AUTO_GATE_RADIUS`,
  *including* a squad fighting an attacker on the doorstep.
- **The bots build exactly ONE gate**, after something that trains is
  standing, and work it. `bot_build_plan.gd`'s header is right that a bot
  raising walls generally "would spend its wood on scenery"; this is the
  bounded exception, and it exists because D-076's two gate opcodes had
  **never crossed a real socket under load**.
- **`defence_appetite` is a difficulty axis and the shipped default USES
  it.** So **every ladder figure taken before #337 was taken against an
  AI that never fortified** — the standing "quote a result with its cap"
  rule gains a clause: quote which side of this change it came from.
  Shipping the knob at 0.0 to keep the default bit-for-bit identical was
  rejected: that is `gather_speed` at 1.0 on every civ for a milestone
  (#158), a knob no shipped data exercises.

**The gate is split on evidence rather than on the brief.** #337 asks for
a ladder gate proving a wall was BUILT and FOUGHT OVER. Measured:

| run | result |
|---|---|
| `ai-ladder 1 300 2` on `main` | no defences, ever |
| `ai-ladder 1 420 2`, contact model | **`defences_ordered=9 defences_standing=6`**, `buildings~10` against `main`'s 2 |
| `test-ai-teams 1 180 4 2 siege` | orders refused — the bases start close, and a screen five cells out lands in somebody's claim |
| **`ai-ladder 1 600 4`** | **`defences_standing=6 defences_fought=71 gate_orders=10 gates_sealed=4`** on one seat, `defences_standing=4` on another |

So **BUILT is gated** on the ladder, where it demonstrably happens, and
**FOUGHT OVER is reported beside it**. That is D-031's rule: `test-load
4 40` was the documented recommendation for a whole milestone and could
not have passed, and `load-testing.md` keeps `nodes_felled` a metric for
the same reason. The counter exists; the gate is one line the day
somebody measures a configuration that reliably produces a wall fight.

**The gate was observed to fail before being trusted** (D-022's audit
block). With every profile's `defence_appetite` forced to 0.0 and nothing
else changed, `just ai-ladder 1 300 2` reports:

```
  FAILED: no AI built any static defence — walls, gates and towers
    are shipped (D-076) and #337 exists because nothing exercised them.
```

Restored, the same recipe passes. **Two ladder runs were spent on the
guard rather than the feature**, and both failures are worth knowing:
the awk summary is a **single-quoted shell string**, so one apostrophe in
a comment (`D-076's`) ends the quoting and awk reports `cmd. line:N:
(END OF FILE)` pointing at a line that is perfectly fine; and a `printf`
whose format string is split across two lines makes `just` itself fail on
the em dash three lines below. Both notes are in the justfile now.

**And the bot half was dead code until a load test said so.** The bots
gathered **wood and nothing else** — not even food — which was fine while
the only thing they bought was a barracks, and stopped being fine the
moment they were asked to build a gate: `gate.tres` costs 45 **stone**.
The first `test-load 4 300` came back **clean with `gate_orders=0
gate_toggles=0`**, which is this issue's own defect class arriving inside
the fix for it. One crew per pass is diverted to whatever the next
purchase is short of, through the same `AiInvestment.scarcest_shortfall`
the AI reads — one rule, two callers, and naval a third.

Measured `test-load 4 300`, before and after that one line:

| | before | after |
|---|---|---|
| `gate_orders` / `gate_toggles` | **0 / 0** | **7 / 6** |
| desyncs | 0 of 1192 checks | 0 of 1196 |
| `conceal_events` / `reveal_events` | 161 / 133 | 228 / 202 |
| `casualties_applied` | 245 | 135 |
| `military_peak` | 9 | 6 |
| µs/squad | 116.34 at 46 squads | 140.61 at 38 squads |

Both runs clean, every gate green. **The diverted crew is not free** and
the table says so: fewer soldiers and fewer casualties in the same window,
and the per-squad figure is quoted with its squad count as ever — 38
against 46 squads is most of that difference, since per-tick fixed
overhead lands in the per-squad number when squads are few (M1's standing
caveat). Anything tuned against the old economy is measuring a slightly
different one; that is the standing "when the opening changes, every
timing tuned against the old one is stale" rule, and it is the price of
`test-load` exercising two opcodes it had never touched.

**Three defects in this change, each found by a real match rather than by
a test:**

- **`defences_standing=1` before anything was built** — `damage > 0`
  alone reads the TOWN CENTRE as a defence, so every seat began
  one-sixth through its investment cap.
- **A tower it could not afford blocked the walls behind it.**
  Save-rather-than-skip is right for the barracks and wrong here: a
  segment is 30 wood and 40 stone against a tower's 40 and 120, so saving
  meant a seat under attack built nothing at all.
- **40 orders, 1 standing.** A refused site was re-offered every think
  forever, because the "is it built yet" test looks for a building that a
  refusal guarantees will never appear. D-107 in the other direction —
  not a latch on an intent read as an outcome, but *no* latch, so the
  intent repeated. Cells inside a hostile `no_build_radius` are also not
  planned at all now: that refusal is a rule the AI can READ.

**An observation this work could not fix, recorded rather than filed.**
On the shipped ladder map, two seats on the same profile with the same
sixteen workers reported `peak_stockpile` **510 and 1,701** — a 3.3x
economy gap between civs, with the weaker seat never fielding an army at
all (`squads_peak=17 workers_peak=16`, so one military squad: the opening
general). That is present on `main` too and is the territory of #207's
civ-differentiation pass, not this one.
