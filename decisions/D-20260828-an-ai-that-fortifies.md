### D-20260828 · Accepted — an AI that fortifies, and the question naval shares with it

**Decision (issue #337; D-076's standing gap):** the AI builds and uses
static defence. The **decision** — "is now the moment to spend on
something that cannot chase anybody?" — lives in `static_defence.gd`,
which names no wall and is shared with naval stage 7 (#301). The
**geometry** lives in `wall_plan.gd`. `just ai-ladder` gates on a defence
having been built in a played match.

---

## What was actually wrong, which was not what the issue said

D-076's own entry records the gap: *"no AI building or using walls/gates
exists yet — `just ai-ladder` cannot exercise any of this feature."* That
is the D-055 family, where `BuildingSim.damage()` sat uncalled for two
milestones and no match could be won.

Reading the code, the AI looked *able* to build walls: every member of
the wall family passes `can_build(gatherers)` and produces nothing, so
they all landed in `_wanted_buildings`'s support list. Measured instead
of assumed — `just ai-ladder 1 300 2` on `main`:

```
player 1000  buildings~2.0   first_attack=never
player 1001  buildings~2.0   first_attack~137s
```

**Two buildings each, for the whole match.** The cause is one line:

```gdscript
func _kinds_below_floor() -> Array:      # before
    ...WOOD if below floor...
    out.append(Economy.ResourceKind.FOOD)
```

**The AI has never gathered stone or gold, in any match ever played.**
Every wall, gate and tower costs stone, so all of them were unaffordable
*by construction* — and because `_raise_buildings` **saves** for what it
cannot afford rather than skipping it, the alphabetically-first support
building (`garrison_gate`, 110 stone) stalled the queue behind it and the
AI never built a storehouse either.

So the feature was not merely unexercised by the ladder. **It was
unreachable by the economy**, and the ladder was right.

---

## Six calls

**1. An AI gathers what its next purchase costs.** `_kinds_below_floor`
now asks `StaticDefence.scarcest_shortfall` about the thing
`_wanted_buildings` is saving for. Naval inherits the fix rather than
rediscovering it: a dock is another building whose price is not food.

**2. Defence is NOT on the unconditional build list.** A wall is a shape,
in a place, against somebody — a different question from "what do I not
have yet". Left on that list, the AI put ONE wall segment on a
pseudo-random cell two steps from whichever gatherer was nearest, which
is a rock in a field bought with the wood that would have trained
soldiers.

**3. The decision is domain-free and the geometry is not.** #337 asked
that the walls work share whatever "the AI invests in static defence"
machinery naval stage 7 creates. Stage 7 is **not started** (stages 1–6
are in review; 7 depends on 4, 5 and 6), so this defines the seam and
stage 7 adopts it — the arrangement 86/87 used for CI. The contract is
below, and `tests/test_static_defence.gd` **enforces** the domain-freedom
with a source scan, because "this file knows nothing about walls" is not
something a behavioural test can see.

**4. A screen, not a ring, and that is arithmetic.** A ring at radius 5
is 30 cells: **900 wood and 1,200 stone** at the shipped `wall.tres`
price. Nothing in a match of this length can afford that. An arc across
the approach is five segments — 150 wood, 200 stone — and it is also the
shape worth having: a wall's job here is to make an attack go where the
defender chose, not to make the base airtight.

**5. Contact is a case in itself, and the first version did not think
so.** That version modelled fortifying as a response to being *hit*. It
never fired: measured over two 300 s and one 420 s ladder run,
`defences_ordered=0` on every seat, while one of them reported
`buildings_lost=2 attacks_survived=43` — the only seat with a case was
the one already losing, which by then had no barracks and so failed the
precondition. Players do not wall when they are bleeding; they wall when
they know who their neighbour is. `CONTACT_CASE` is the term that was
missing, and the horizon is now **half the way to the nearest other
start** rather than a flat radius, because on the shipped ladder map two
seats are further apart than any constant worth having.

**6. Using a gate means CLOSING it.** The obvious version — "set every
gate to AUTO" — is **vacuous**: `BuildingSim._gate_mode`'s own comment
says new gates start in auto mode, so an AI ordering AUTO sends a packet
that changes nothing, and a gate counting those packets would pass
against an AI that never used a gate. What is not vacuous is sealing one:
an auto gate opens whenever the owner's own squad is within
`AUTO_GATE_RADIUS`, *including* a squad fighting an attacker on the
doorstep — so at the moment a gate matters most it stands open for
whoever is winning that fight.

---

## The interface naval stage 7 is writing against — PINNED

```gdscript
# static_defence.gd — all-static, pure, names no domain.
static func pressure(threat: Dictionary, economy: Dictionary) -> float
static func wants_to_invest(threat: Dictionary, economy: Dictionary,
        appetite: float, standing: int, cap: int) -> bool
static func can_afford_with_reserve(wallet: PackedInt32Array,
        cost: PackedInt32Array, floors: PackedInt32Array) -> bool
static func cost_of(def: BuildingDef) -> PackedInt32Array
static func scarcest_shortfall(wallet: PackedInt32Array,
        cost: PackedInt32Array) -> int
```

`threat` reads `hostiles_near`, `nearest_hostile`, `horizon`,
`enemy_base_known`, `buildings_lost`, `attacks_survived`. `economy` reads
`military_buildings`, `army_squads`. **A missing key is no evidence, never
alarming evidence** — a test pins that — so stage 7 can supply a naval
threat without teaching this file anything, and a key added later cannot
make an old caller start fortifying.

`AiProfileDef.defence_appetite` is the difficulty axis, read as
`pressure >= 1.0 - appetite`. Stage 7 should read the same field rather
than adding a second one: how defensive an opponent is, is one trait.

---

## The gate, split on evidence rather than on the brief

#337 asks for a ladder gate proving a wall was **built** and **fought
over**. Measured:

| run | result |
|---|---|
| `ai-ladder 1 300 2` on `main` | `buildings~2.0`, no defences, ever |
| `ai-ladder 1 420 2`, first model | `defences_ordered=0` on both seats |
| `ai-ladder 1 420 2`, contact model | **`defences_ordered=9 defences_standing=6`**, `buildings~10` |
| `test-ai-teams 1 180 4 2 siege` | orders refused — bases start close, and a screen five cells out lands in somebody's claim |
| **`ai-ladder 1 600 4`** | **`defences_standing=6 defences_fought=71 gate_orders=10 gates_sealed=4`** on one seat, `defences_standing=4` on another |

So **BUILT is gated on the ladder**, where it demonstrably happens.
**FOUGHT OVER is reported, not gated**, and the reason is this project's
own most expensive rule: `test-load 4 40` was the documented
recommendation for a whole milestone and could not have passed (D-031),
and `docs/status/load-testing.md` keeps `nodes_felled` a metric for
exactly this reason. A gate that fails an honest run teaches people to
lower it. When somebody measures a configuration in which an AI reliably
attacks a wall, the counter is already there and the gate is one line.

---

## Rejected

- **Setting gates to AUTO as the "using" half.** Vacuous; see call 6.
- **A profile-tunable threat radius.** A difficulty setting able to make
  an AI fortify against somebody it saw once, forever, is a way to ship a
  broken opponent by data entry — the line `ai_profile.gd` already draws
  for `FOUND_RETRY` and the resource floors.
- **Letting bots raise walls generally.** `bot_build_plan.gd`'s header is
  right that a bot doing so "would spend its wood on scenery". The bots
  build exactly ONE gate, after something that trains is standing, and
  work it — enough to drive two opcodes that had never crossed a socket
  under load.
- **`defence_appetite = 0.0` as the default**, to keep the shipped
  default bit-for-bit the AI that shipped. It would ship a knob no
  profile exercises, which is `gather_speed` sitting at 1.0 on every civ
  for a milestone (#158). **The consequence is stated instead: every
  ladder figure taken before this was taken against an AI that never
  fortified**, and the standing "quote a result with its cap" rule gains
  a clause.

---

## Three defects in this change, each found by a real match

- **`defences_standing=1` before anything was built.** `damage > 0` alone
  reads the TOWN CENTRE as a defence, so every seat began one-sixth
  through its investment cap. `WallPlan.is_static_defence` is the rule.
- **A tower it could not afford blocked the walls behind it.** Save-
  rather-than-skip is right for the barracks and wrong here — a segment
  is 30 wood and 40 stone against a tower's 40 and 120, so saving meant a
  seat under attack built nothing at all.
- **40 orders, 1 standing.** A refused site was re-offered every think
  forever, because the "is it built yet" test looks for a building a
  refusal guarantees will never appear. D-107 in the other direction: not
  a latch on an intent read as an outcome, but *no* latch, so the intent
  repeated. Sites are now tried once per `DEFENCE_RETRY_SECONDS`, and
  cells inside a hostile `no_build_radius` are not planned at all — that
  refusal is a rule the AI can READ.

## Revisit trigger

Naval stage 7 needing a key `pressure` cannot express, or a second reader
of `defence_appetite` that wants it to mean something different. Also: an
AI that should man its own wall-top tier. Nothing here climbs one, and
D-076's tier-1 combat is still exercised by tests alone.
