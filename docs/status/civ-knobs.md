**A civ's mechanical knobs are read by the simulation now, and were read
by nothing for a milestone**
(`decisions/D-20260823-a-civs-knobs-are-read-by-the-simulation.md`, #158,
found in the playtest P09 gap survey #35). `CivDef` shipped three —
`squad_cap_bonus`, `production_speed` and `gather_speed` — all three with
**zero** references outside `civ_def.gd` and the tests. The two shipped
civs differed by their roster, their colour and their opening stockpile;
every *declared* mechanical difference was inert. Northmen said
`squad_cap_bonus = 4` and `production_speed = 1.3` and could field
neither more troops nor sooner.

**Correcting the issue on one point, because it matters for what the
tests can prove:** #158's table says all three ship non-default. Only two
do. `gather_speed` is **1.0 on both shipped civs**, so no fixture reading
the roster could exercise it at all — which is why
`tests/test_civ_knobs.gd` builds a synthetic `CivDef` rather than picking
one out of `/civs`, and why `SquadSim.civs` holds a resolved def rather
than an id.

Fourth instance of the declared-and-unread family, after `UnitDef.cost`,
`BuildingDef.cost` and `BuildingSim.damage()` (D-055, which meant no
match could be won for two milestones). Nothing failed; the game quietly
lacked a rule.

Where each one is applied, which is the part worth knowing:

- **`squad_cap_bonus`** in `MatchState.squad_cap_for(sim, player)`, read
  by the refusal (`has_squad_capacity`) **and** by the `squad_cap` the
  server puts in each client's WELCOME. One number, because a HUD saying
  40 while the server refuses at 44 is a rule the player cannot see.
- **`production_speed`** at ENQUEUE, stored as real seconds. The queue
  head counts down at one second per second on the wire and the client
  draws that countdown (D-003), so a multiplier applied per TICK instead
  would leave every client's "— 12 s" wrong.
- **`gather_speed`** per tick in `Economy._gather`, never latched into
  the haul when the order was given — a cached copy of a fact the
  simulation already holds is the shape of the D-038 ownership cache that
  silently refused every produced squad an order.

Four things to carry forward, none of which are really about civs:

- **A knob is read through an APPLIED function on the schema, never as a
  raw field.** `CivDef.squad_cap()`, `.production_time()`,
  `.gather_rate()`. Two of the three are read on both sides of the wire —
  the server spends the production time, the client draws the bar — so
  `base / production_speed` written out twice is two copies of one rule
  free to drift (the D-058/D-065 family). It also gives the knob a
  caller you can grep for, which is the thing that was missing.
- **The simulation has to be TOLD.** `SquadSim.civs` is filled by
  `server.gd`'s `_hand_civs_to_sim()`, the exact sibling of
  `_hand_teams_to_sim()` and written beside it — including #119's lesson
  that the handover nothing performs is the dangerous half. It runs on
  every path a civ can become known, `_admit_player` included, because on
  the `--lobby=0` path a human is seated long after the match began.
  `server: SIM_CIVS …` is the marker, for the same reason `SIM_TEAMS` is:
  a harness asserting that civs reached the simulation must read the
  simulation.
- **It reads `server.gd`'s `_civ_of`, not `MatchState.civ_of`.** `_civ_of`
  is what resolves the ROSTER a player builds from, and it has a
  round-robin fallback the seatless runs use. A player whose troops came
  from one civ while their cap came from another is a fault nothing could
  see.
- **The test that would have caught this is not a behaviour test.**
  `tests/test_civ_knobs.gd` drives each knob by hand and every one of
  those tests passes with the server applying none of it. The one that
  could not is
  `test_every_mechanical_knob_is_read_by_something_that_ships`, a source
  scan for a shipping caller of each applied function — the same shape as
  `test_terrain_fog.gd`'s caller-exists test for D-106, and carrying
  D-106's own caveat: **it only covers the callers it names.** A fourth
  knob added later is not covered by it.

**Balance is untouched and deliberately so.** The shipped `.tres` numbers
are exactly what they were; this made them mean something. Northmen now
field 44 squads to the Legion's 40 and train 1.3x faster, so **every
`just ai-ladder` number taken before 2026-08-23 was measured against a
build where they did not** — quote a ladder result with its cap and with
which side of this change it came from. If the ladder says the numbers
are wrong, the fix is new numbers in the data.
