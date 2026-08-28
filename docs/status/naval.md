**Naval stage 1 — the water graph — is built
(D-20260828-the-water-graph-is-the-inverse-of-the-ground, #301,
`docs/plans/naval.md` §7 row 1).** Water has a field, shores have a
predicate, and water components come out of the walk the map already
uses. **Nothing in the simulation changed**, which is what that row asks
for: this is the base every other naval stage builds on, so its answers
are pinned before anything depends on them.

```gdscript
var navigable := terrain.navigability(space)          # 1 iff below sea level
TerrainGen.is_shore(space, passable, navigable, i)    # static, both fields in
MapConfig.walkable_components(space, navigable)       # water bodies, no new walk
```

Four things to know before building stage 2 or 3 on it:

- **`navigability` is a SEPARATE array, not a third value in
  `passability`.** D-076's reasoning for keeping its wall-top field
  cache separate, reused: `_passable` has many readers and every one of
  them means LAND. A tri-state array would be read by all of them, and
  the ones that never learned the third value would not fail — they
  would treat open water as walkable ground.
- **The cut-list's "disjoint and cover the map" is half right, and the
  half that is wrong is load-bearing.** Disjoint: yes, on every preset,
  after ramp carving. Cover: **preset-dependent** — land too steep to
  walk is in neither field. Measured at 48x24, seed 1337: `plains`,
  `highlands` and `islands` are fully covered; `continents` leaves
  **91 of 1152 cells (7.9%)** in neither. What partitions the map is the
  DOMAIN — navigable is the water half, its complement the land half —
  and passability is a rule WITHIN land. Stage 2 dispatches on domain
  and stage 9 places spawns over these fields; a reader who believed the
  slogan would write `if not navigable then walkable` and put an army on
  a cliff.
- **`highlands` could not demonstrate that gap**, which is worth knowing
  because it is the preset anybody would reach for: D-20260826 opened it
  up completely ("44.1% dead space … fully open now"), and the same
  change gave `continents` real walls. The test measures the whole
  ladder and prints the table rather than asserting on one preset.
- **`is_shore` takes both fields as ARGUMENTS**, because which
  passability a caller means is a real question: `TerrainGen.passability`
  is the ground, `SquadSim._passable` has living buildings stamped out.
  A dock placement asks the first, a squad asks the second. It also
  explicitly refuses a navigable cell — not defensive, since the two
  arrays have the same shape and opposite meanings, and passing one
  twice would otherwise offer the open sea as dock sites.

**Measured, for the stages that will need it:** `continents` at 64x32 has
**164 shore cells**, so stage 3's dock has somewhere to stand; `islands`
at 64x32 has a largest connected sea of **1,565 cells**, which is what
stage 9 reasons about when deciding whether two starts can reach each
other.

**One naming wart, flagged and not churned:**
`MapConfig.walkable_components` is domain-agnostic and its name is not —
every naval stage will call it with a navigability field. It belongs to
an unmerged PR (#216); raised there rather than edited here.

---

**Stage 5 — combat across the shoreline — is built
(D-20260828-melee-does-not-cross-a-shoreline, §2.5, cut-list row 5).**
`Combat._can_reach_tier` is now `_can_reach_domain`, and `SquadSim`
declares `DOMAIN_GROUND` / `DOMAIN_WALL_TOP` / `DOMAIN_WATER`. Nothing
else in `combat.gd` moved: ships are squads, so the bucket map, the disk
scan and D-024's arithmetic are untouched.

**THE PLAN'S "same sentence" IS NOT THE SAME SENTENCE, and this is the
thing to know.** §2.5 says melee cannot cross a domain boundary and calls
that "the same sentence D-076 already enforces between ground and
wall-top". D-076's rule is **asymmetric**: it refuses melee UP onto a
wall and permits melee DOWN off one, which is what makes climbing a
defensive choice rather than a way to leave the battle.

Implementing §2.5 literally makes it symmetric and **takes that away** —
a wall-top squad becomes unable to fight the attackers at its foot. **No
existing test covers it**: `test_wall_top.gd`'s melee test uses an ARCHER
as the defender, so it asserts a ranged defender shoots back and says
nothing about melee downward. Verified rather than assumed — with melee
refused across every boundary the whole existing suite still passes, and
the only red is the new test written for it.

So: the plan is followed for water and deliberately **not** followed for
walls. A shoreline stops melee both ways; a wall stops it one way. If the
owner wants wall-tops to stop meleeing the ground, that is a change to
D-076, in D-076's file, with its own reasoning — not a side effect of
adding boats.

Two smaller things:

- **`DOMAIN_WATER` is declared before anything can be in it.** Stage 2
  puts squads there; stage 5 needs to name the domain it refuses melee
  across, and a bare `2` in `combat.gd` would be a second definition of
  the same fact.
- **The live half is stage 2's.** Nothing puts a squad in water yet, so
  the tests drive the predicate directly. A ship actually failing to be
  meleed is stage 2's gate; what stage 5 owes is a rule that is right
  before anything depends on it.

---

**Stage 7 — the AI's naval consumers — is built, and A LANDING HAPPENS
(D-20260828-an-ai-invests-in-what-it-cannot-walk-to, §6.1/§6.2/§6.3).**
Stage 2 landing (#343) unblocked it; `tests/test_naval_landing.gd` plays
the whole crossing against the real simulation — dock, board, sail, land
— with no test double and no direct call to `disembark`.

```
just test-unit naval_landing     # the crossing, ticked
bash gate-check.sh naval SERVER_LOG
```

Five things to know:

- **The trigger is REACHABILITY, not a map flag**: does my landmass hold
  a known enemy building? On `continents` that is almost always yes, so
  the behaviour costs nothing where it is not wanted. **Knowing of no
  enemy is not a reason to build a navy** — an AI that has scouted
  nothing says no, or it talks itself into a fleet before it has looked.
- **The gate's vacuity guards are ORDERED, and that is the point.**
  `landings=0` is what a land map, an unplayed match, a missing dock, an
  untrained transport and a broken disembark ALL report. `gate-check.sh
  naval` fails at the FIRST missing leg and names it, and skips entirely
  when no AI wanted a navy — a gate that failed on every land run would
  be turned off within a week.
- **`AiInvestment` is the reusable half and #337 (walls-AI) is its second
  customer.** An investment is a named, ordered list of steps; nothing in
  it names water.
- **Stage 4's order path is why stage 7 is small**: embark and landing
  ride the ORDINARY move order — a squad ordered onto a hull's cell
  boards it, a laden hull ordered at land records a landing — so the AI
  sends moves and knows nothing about boarding.
- **A single channel does not separate anything on a torus.** The
  landing fixture's first version had one, and the levy walked round the
  seam and arrived without touching water; only
  `test_a_land_squad_cannot_simply_walk_across` caught it. Same trap
  `formation.md` records for the wheeling fixture. **Stage 9 inherits
  this**: a naval map needs its water to close, or `islands` will seat
  starts that are reachable on foot.

**And the predicate deadlocked, which is why #351 has TWO causes.**
`needs_ships` asked "does my landmass hold a known enemy building?" — and
an AI cannot LEARN of an enemy across water without crossing, or cross
before it has learned. Found by worker 88 on the integrated tree, and
measured before concluding: on the default map the four seats land on
3-4 DIFFERENT islands, so placement was fine and `wants_navy` was still 0
with `enemy_buildings_seen=0` on all eight seat-matches.

It was designed in. This file argued at length that "knowing of no enemy
is not a reason to build a navy", which is right for a land map and is
its own exact mirror on a water one — the predicate could not tell "I
have cleared my island" from "I have never left my beach", and those
want opposite answers.

There are THREE states now, not two: an enemy on my landmass (fight on
foot), an enemy off it (sail), and nobody known — which splits on whether
the AI has LOOKED. Having scouted and found nobody, with substantial land
it cannot walk to, is not ignorance; it is having run out of world.
`min_spawn_landmass` decides "substantial" (D-104's own number, reused),
because generated maps are full of islets and every one of them would
otherwise be a reason to build a dock.

**And a dock was being built with no naval intent at all.**
`_wanted_buildings()` returns every def a gatherer may build, so seats
with `wants_navy=0 ships_peak=0` reported `docks=1`. The wasted wood is
the small half: §6.2's vacuity ladder gates FIRST on "no dock was ever
built", so a dock nobody meant would carry the gate past its first leg
and make it name the WRONG one. Excluded by `needs_shore` rather than by
id, so the next shore building inherits the rule.

**Found on the way, filed not fixed:** seven shipped `.tres` files are
not UTF-8, so every Godot run prints twelve parse warnings (#338).

---

**Superseded note (stage 7 before stage 2 landed):** **Stage 7 — the AI's naval decision layer — is built; the BEHAVIOUR is
blocked on stage 2 (D-20260828-an-ai-invests-in-what-it-cannot-walk-to,
§6.1/§6.3).** `ai_investment.gd`, `ai_naval.gd` and `bot_naval.gd` are
static, pure and tested; `AiProfileDef.naval_commitment` ships on all
three difficulties.

**The cut-list's done-condition is NOT met, and it is not a matter of
effort.** It asks for *"a landing happens in a played match"*, and today
no landing can happen on any map:

- **ships cannot move** — `SquadSim.is_passable` does not dispatch on the
  water domain and no water flow field exists (stage 2);
  `set_navigable`'s own comment says *"nothing paths on it today"*;
- **there is no naval map** — `islands` was retired (#280/#299) and
  `maps/isles.tres` is stage 9's, while §6.2 specifies the gates *on an
  islands map*.

So an AI could be given the whole behaviour and no landing would result,
however committed the profile. **Shipping AI naval behaviour that cannot
be run would BE the D-076 mistake rather than the fix for it** — which is
the argument §6 opens with — so the behaviour, the `AI_STATS` keys, the
bot's crossing and `beachhead.tres` land WITH stage 2.

Four things worth carrying:

- **The trigger is REACHABILITY, not a map flag**: does my landmass hold
  a known enemy building? On `continents` that is almost always yes, so
  the behaviour costs nothing where it is not wanted, and no map needs
  labelling. **Knowing of no enemy is not a reason to build a navy** —
  an AI that has scouted nothing says no, or it talks itself into a fleet
  before it has looked.
- **`AiInvestment` is the reusable half, and #337 (walls-AI) is its
  second customer.** An investment is a named, ordered list of steps —
  dock, transport, embark, landing — which is also how a harness reports
  WHICH leg broke rather than a bare zero. Nothing in it names water.
- **Stage 4 got the order path right, and it is worth knowing**: embark
  and landing ride the ORDINARY move order (a squad ordered onto a hull's
  cell boards it; a laden hull ordered at land records a landing), so no
  new opcode exists and §2.4's "orders never choose a domain" survives.
- **Three of the four steps could already succeed** once the behaviour is
  wired — dock (stage 3), transport (stage 6), embark (stage 4 spawns
  hulls at a dock's water side). Only the landing waits, so the ordered
  vacuity guards will report "stuck at landing" rather than a bare zero.

**Found on the way, filed not fixed:** seven shipped `.tres` files are
not UTF-8, so every Godot run prints twelve parse warnings (#338).

