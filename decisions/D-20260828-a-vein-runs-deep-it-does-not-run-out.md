### D-20260828 · 2026-08-28 · Accepted — a vein runs deep; it does not run out

**Decision:** the renewable story, settled per resource (#277). Three of
the four are answered; the fourth needed no mechanism and the measurement
says why.

| resource | renewable source | mechanism |
|---|---|---|
| **food** | the **farm** | grown at a rate, worked by a crew (`D-20260828-food-is-grown-not-only-found`) |
| **wood** | **nothing new** | measured ample — see below |
| **stone** | the **deep mine** | the vein itself, at a tail rate |
| **gold** | the **deep mine** | the vein itself, at a slower tail rate |

**A mineral node is never exhausted.** When a gold or stone node's stock
reaches zero it does not deplete: it keeps regrowing toward a small tail
capacity at a slow permanent rate, so a held vein yields forever at a
fraction of its opening richness. **Trees are untouched** — a worked-out
tree is felled exactly as D-087 says, and the client animation is not
compromised or reinterpreted.

**The measurement first, because it changes what the issue is about.**
Generated from `maps/default.tres` at seed 1337 — 168x194, 32,592 cells,
20 seats:

| kind | nodes | total stock | per seat | cells per node |
|---|---|---|---|---|
| food | 1,939 | 203,595 | 10,179 | 16 |
| wood | 3,435 | 360,675 | 18,033 | 9 |
| stone | 137 | 328,800 | 16,440 | 237 |
| **gold** | **48** | 115,200 | **5,760** | **679** |

**Wood is not the blocker.** One node every nine cells and ~18,000 per
seat is about 120 barracks; #277 lists wood alongside the metals and the
map does not agree. **Gold is** — 48 nodes on the entire map, one per 679
cells, and they sit on the mountain perimeter (D-087), which is to say on
the contested ground. Per-seat totals flatter it badly: what a player can
actually reach is one or two veins, and one vein at a shipped crew's
~1.96/s is worked out in roughly **20 minutes**. In a 1–2 hour match
(D-056) that is a wall in the first third.

**Why the vein and not a building.** The farm is the right answer for food
because food genuinely comes from worked land, and land is everywhere —
which is exactly why it is the wrong shape for metal. A "gold mine you can
build anywhere" would delete map control from the late game in the same
stroke that D-039 scattered spawns and D-087 put ore on the mountain
perimeter to make those places worth holding. **The renewable metal has to
be the place, not the building**, or holding ground stops paying.

So the mechanism is the vein: the site keeps its value forever, the early
rush of a rich seam is unchanged, and the hard ceiling is gone. A player's
sustainable metal income becomes `veins held x tail rate` — the same shape
of equation the farm gave food, which is the point of the two rhyming.

**What it costs to build: nothing new anywhere.** No building, no schema,
no wire message, no client change, and no animation. A mineral node that
never reaches zero simply never enters `_depleted`, so no
`S2C_NODES_DEPLETED` is sent and nothing is felled — the outcrop stays on
the map because it is still there and still being worked, which is the
truthful drawing. That is the whole reason the mechanism is scoped to
minerals: **the tree's felling is the one player-visible thing #277's
brief said must not be compromised, and the way to not compromise it is
to not touch it.**

**The numbers, derived rather than chosen.**

- **Gold `0.25/s`, tail capacity `150`.** A heavy squad costs 30 gold; one
  vein at this rate funds one every two minutes in the late game, which
  is a trickle a player plans around rather than an income they live on.
- **Stone `0.4/s`, tail capacity `240`.** A tower costs 120 stone; one
  quarry funds one every five minutes.
- Capacities are **ten minutes of regrowth** in both cases, so a vein left
  alone buffers a raid or a rebuild and no more. That is what stops "come
  back in an hour" being a strategy, exactly as the farm's `grow_capacity`
  does.

Both are **far below a live seam** (a crew takes ~1.96/s until the 2,400
runs out), which is the property that matters: the opening is still a race
for rich ground, and the tail is a floor rather than a replacement.

**Rejected alternatives:**
- *A quarry / gold mine building on the farm's schema* (rejected on the
  design argument above — it is one `.tres` file and no code, which is
  precisely what makes it tempting, and it would let a player print metal
  on ground nobody contests. The schema stays general and the option
  stays open if play disagrees.)
- *Wood regrowth on D-087's per-cell stock* (rejected on the measurement:
  wood is not scarce. And it is the one change that would have forced a
  player-visible compromise — a regrown tree has to appear, which means
  either a new wire event and a growth animation, or a tree that pops
  into existence. The brief said the felling animation must stay
  truthful; the cheapest way to keep a promise is not to make a change
  that strains it.)
- *A passive trickle into the wallet* (rejected for the reason
  `D-20260828-food-is-grown-not-only-found` rejects it for food: income
  that does not go through a crew breaks D-028's claim that income scales
  with `alive`, so killing workers stops meaning anything and D-068's
  "raiding must be strategy, not flavour" dies with it.)
- *Prospecting — new veins discovered over time* (rejected as the answer
  to THIS issue: it is the most code, it needs new nodes to be revealed
  truthfully through the fog, and it makes the map's resource geography
  drift, which is the thing D-104's fairness pass works to get right at
  generation. Worth revisiting only if the tail proves too flat.)
- *A market converting food into gold* (**deferred, named, not
  rejected** — and the reason is #206's tech line. A market is a good
  building and a bad reflex: with no tech ladder to improve its rate it
  is a flat exchange, and a flat exchange between a renewable resource
  and a finite one puts an unbounded ceiling straight back. It wants to
  arrive WITH the tech that improves it, which PR #225 is building, and
  it is a strategic layer on top of a floor rather than a substitute for
  one. `D-20260828-food-is-grown-not-only-found` deferred trade for the
  metals; this entry keeps it deferred and says what it is waiting for.)

**Consequences:** a match no longer has a fixed metal budget, so D-068's
pricing of buildings and tech in wood and metal becomes writable against a
rate rather than a pile. Holding the mountain perimeter now pays
indefinitely, which raises the value of the ground D-087 already made
contested — expect that to show up in the AI ladder as longer matches
before it shows up anywhere else. Every ladder and load-test number taken
before this was measured against an economy with a hard metal ceiling.

**Measured:** see the PR. `just test-load 4 120` clean, with per-squad
cost quoted at its squad count as ever.

**Revisit trigger:** if a played match ever shows a player living
comfortably off tails alone — building continuously without contesting a
single fresh seam — the tail is too high and the lever is the rate, not
the capacity: capacity only buffers, rate is income. And if wood ever does
run short (the map ladder moving would do it, since these counts are the
default map's), the answer is the woodlot the farm's schema already
admits, not regrowth — for the animation reason above.

---
