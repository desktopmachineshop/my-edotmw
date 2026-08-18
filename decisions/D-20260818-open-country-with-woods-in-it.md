# D-20260818 · 2026-08-18 · Accepted — wood density is scaled to 0.60, and open ground is a measured number

**Decision:** every WOOD band in `Economy._bands` is multiplied by **0.60**
— forest `lerpf(0.65, 0.98, f)` → `lerpf(0.39, 0.59, f)`, grassland
`0.05 + 0.22 g²` → `0.03 + 0.132 g²`, dry grassland `0.10` → `0.06`, beach
`0.10` → `0.06` — and the share of walkable cells that hold no node is
reported by `gen-terrain-preview` and pinned by a test.

Four clauses:

1. **The ENDPOINTS are scaled, not the field.** D-087's shape — wet hearts
   dense, treelines frayed, lone trees in dry country — is a property of
   the moisture argument, not of the numbers it is lerped between, so
   scaling both endpoints thins the woods without flattening them. A flat
   subtraction would erase the dry edge first and a stride would put the
   hex lattice back (D-108).
2. **A band written off another band's cut point must be written off it in
   code.** The thresholds are absolute cut points tested in order, so
   lowering wood in dry grassland re-prices gold unless gold's `below`
   moves with it. `dry_wood` is a local now and gold is `dry_wood + 0.017`;
   grassland's food band was already `wood + food` and needed nothing.
   **Gold and food are the same width after this change as before it, and
   that is checked by counting them, not by reading the arithmetic.**
3. **Total wood on the map falls with the node count. `TREE_STOCK` stays
   105.** Raising stock to hold the total constant would break the pinned
   "one shipped crew works a tree out in ~60 s" relationship and turn each
   tree back into a marker that ticks down slowly — the thing D-087 moved
   away from. Wood was not scarce and is not scarce now (see below).
4. **`RETARGET_RADIUS` stays 8**, because it was measured rather than
   reasoned about: at 0.60 exactly **0 of 3,411** wood nodes have no other
   wood node within 8 cells.

## Rationale

Reported by the owner from playtest #30 (P05), issue #94: there is barely
any open space, and the standard map reads as woodland with clearings
rather than open country with woods in it.

**The issue's own diagnosis was that the wet heart sits at 98%. It does
not, and that matters for which number to change.** The forest band's
argument `f` is moisture rescaled from `MOISTURE_FOREST` to 1.0, so the
0.98 endpoint is paid only where moisture reaches 1. Measured over six
seeds on the shipped 168×194 map:

| seed | forest cells | f p50 | f max | realised band p50 | realised band max |
|---|---|---|---|---|---|
| 1337 | 4,311 | 0.128 | 0.570 | 0.69 | 0.84 |
| 1 | 4,465 | 0.130 | 0.676 | 0.69 | 0.87 |
| 2 | 3,542 | 0.129 | 0.725 | 0.69 | 0.89 |
| 42 | 4,114 | 0.167 | 0.688 | 0.71 | 0.88 |
| 20260801 | 4,634 | 0.190 | 0.708 | 0.71 | 0.88 |
| 999983 | 4,190 | 0.143 | 0.590 | 0.70 | 0.84 |

So **the density a player actually walks through is the FLOOR, 0.65**, and
the ceiling is decoration: the median forest cell rolls at ~0.69–0.71 and
the single wettest cell on a whole map at 0.84–0.89. A change that only
lowered the ceiling would have measured as almost nothing. This is worth
carrying forward as a shape of mistake rather than as a fact about trees:
**an interpolation's endpoints are not its outputs, and the endpoint that
reads alarming may be the one nothing ever reaches.**

### What 0.60 costs, measured

`just gen-terrain-preview` on the shipped map (168×194, 32,592 cells,
26,724 walkable, seed 1337), before → after:

| | before | after | change |
|---|---|---|---|
| resource nodes | 7,664 | 5,530 | −27.8% |
| wood nodes | 5,553 | 3,411 | **−38.6%** |
| food nodes | 1,908 | 1,920 | +0.6% |
| gold nodes | 52 | 48 | −4 |
| stone nodes | 151 | 151 | — |
| open walkable ground | 71.3% | **79.3%** | +8.0 pts |
| forest biome wooded | 70.2% | 43.8% | −26.4 pts |
| wood on the map | 583,065 | 358,155 | −38.6% |
| wood nodes with none within 8 cells | 0 of 5,553 | 0 of 3,411 | — |
| wood within 9 cells of a start | min 13, mean 42.9 | min 4, mean 24.4 | — |

The scale was picked off a sweep of 1.00 / 0.75 / 0.70 / 0.65 / 0.60 /
0.50 against the real band table, not off the requested percentage: 0.60
is where the wood node count lands nearest the requested −40%, and 0.50 is
where the first isolated wood node appears (1 of 2,799), which is the first
sign that `RETARGET_RADIUS` would have to move with the density.

**Food and gold are effectively unchanged, and the wobble they do show is
real rather than a bug.** Each band is an absolute cut point, so scaling
wood slides food's window down by the same width it keeps: cells whose roll
was just under the old wood cut become food, and cells just under the old
food cut become nothing. Those two sets are the same size only in
expectation — each cell has its own band widths — so the count moves by
tens on a map of thousands. +0.6% food and −4 gold nodes is that, not a
lost invariant.

**Wood is still abundant, which is why the total was allowed to fall.**
358,155 wood over 20 seats is ~17,900 each, against 150 for a town centre
or a barracks and 30 for a wall segment — about 119 barracks-equivalents
per player, from natural nodes alone, before anything is contested. The
project's pacing problem is that matches end in minutes (D-056), not that
resources run out.

**The fairness post-pass (D-104) does no more work than before ON THE
SHIPPED MAP.** Its quota is 1 node of each kind within `fairness_radius` 9,
and the worst-off of 20 starts still has 4 wood nodes in reach against 13
before — so no start on the default map needs a wood top-up at either
density. On a map that was already short of wood the pass does start
working, which is what the beach test below found; that is the pass doing
its job, and the guarantee is what makes the thinning safe there.

### The instrument, which did not exist

Neither existing recipe reported the thing being complained about.
`gen-terrain-preview` reported chunk counts, water and impassability and no
resources at all — the issue's claim that it prints node counts was simply
not true of the code. `gen-forest-preview` renders one wood and says
nothing about how much of the map is wood. So the recipe now prints node
counts by kind, **the share of walkable cells that hold no node**, and the
forest biome's own wooded share — the last because a whole-map average is
dominated by open grassland and would have looked healthy throughout.

`test_open_ground_is_most_of_the_walkable_map` pins the whole-map number
two-sidedly (>75% open, <92%), and
`test_forests_are_dense_and_open_ground_is_not` gained an upper bound of
its own. Both were observed red before the change: 71.2% open, 73% of
forest cells wooded.

**Why a node is the right thing to count.** A resource node is ground
nobody can build on — `server._is_buildable` refuses it and `client.gd`
mirrors the refusal — so "share of walkable cells with no node" is not a
cosmetic statistic; it is the buildable map. That is also the number issue
#55 quotes as "resource nodes block 30% of walkable cells": measured 28.7%
before, **20.7% after**, so #55's percentage should be re-read off this
recipe rather than assumed.

### The one test that went red for a reason worth writing down

`test_no_top_up_lands_on_a_beach_while_better_ground_is_free` failed after
the change: one fairness top-up landed on a beach on the `islands` fixture.
It was a **wood** top-up, on a beach that grows wood.

Nothing was breached. `Economy._ground_ranks` ranks a cell NATURAL for any
kind its own band table grows, and D-087 puts palms on beaches — so a beach
is the RIGHT ground for a tree and the wrong ground for a rock, and the code
has said so since D-104. The assertion was simply wider than the rule it
guarded: it counted every beach top-up of any kind, and until the woods
thinned there had never been a world in which those two readings differed.
An islands start that had natural wood in reach before now needs a top-up,
and the only wood-growing ground it can walk to is its own shoreline.

The test counts beach top-ups of a kind the beach does not grow now, with
the exception written out as the test's own statement of the rule rather
than read back out of `_bands` — D-022's audit again: a check that asks the
implementation for its own answer cannot see it being wrong. The
biome-blind counter-arm still fires, so the narrowing did not make it
vacuous.

**The general shape, which is the reason this is in the decision and not
just in the commit:** an assertion can be broader than its rule for a whole
milestone and never say so, because nothing generates the case that
separates them. A density change is exactly the kind of edit that generates
those cases — it does not break rules, it visits worlds the fixtures never
reached.

## Rejected alternatives

- **Lower only the 0.98 ceiling** (the issue's reading). Measured to change
  almost nothing: 31 cells on the whole shipped map have f ≥ 0.5.
- **Raise `TREE_STOCK` to hold total wood constant.** Breaks the pinned
  ~60 s crew-per-tree relationship and undoes D-087's "a forest is
  consumed tree by tree, visibly".
- **A single `WOOD_DENSITY` multiplier constant.** Reads as tidier and
  hides the shipped densities behind arithmetic; every other band in the
  table is a literal, and the point of the table is that the numbers can
  be read off it.
- **Thin by a stride (every Nth node).** Puts the hex lattice back into the
  woods, which is exactly what D-108 spent a milestone removing.
- **Move `RETARGET_RADIUS` with the density as a precaution.** Not needed
  at 0.60 by measurement, and a radius raised on suspicion would march
  crews onto ground the player never chose.

## Consequences

- **Every world generates differently.** Node placement is a pure function
  of the seed and this table, so every map, replay and test that counts
  nodes changes. The two economy density tests moved with it; nothing else
  in the suite asserts a node count.
- **#109's numbers are now stale in this direction.** Placement cost is
  budgeted against 7,694 nodes on the default map; the same map now
  generates 5,530. That makes #109 cheaper, not settled — the work is
  unbudgeted either way.
- **The map is more buildable.** 79.3% of walkable ground takes a building
  against 71.3%, which is the same lever #55 is about.
- **Total wood on the map fell 38.6%** and nothing rose to compensate. If
  the economy playtest (#36, P08) finds the opening starved, the knob to
  reach for is this table again, not `TREE_STOCK`.

## Revisit trigger

- The economy playtest (#36, P08) reporting that wood runs short, or that
  crews idle after felling — the second would mean `RETARGET_RADIUS` needs
  to move after all, and the measurement to re-take is the isolated-node
  count above.
- A future map preset or ladder rung whose forest `f` distribution reaches
  much higher than 0.73, since the ceiling is decoration only while it
  stays unreachable.
