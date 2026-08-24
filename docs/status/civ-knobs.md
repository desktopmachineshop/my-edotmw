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
- **A knob that is wired but unproven is the same defect one layer
  down, and the first version of this work had it.** Unwiring all three
  turned five tests red — but **both production BEHAVIOUR tests stayed
  green**, because they call `BuildingSim.enqueue` themselves. They prove
  the arithmetic and say nothing about whether the server performs it,
  and the source scan that did go red cannot see a caller passing the
  WRONG argument. Each knob now has a test that drives
  **`server._handle_order_produce` itself** and goes red without it.
- **"server.gd needs a socket and a scene tree" is true of `_ready()`,
  not of the file.** That is the same distinction D-075's 2026-08-16
  amendment had to make for `client.gd`, where reading the claim too
  widely cost a milestone of matches with no terrain. A Node that is
  never added to the tree does not run `_ready()`, and `LoopbackPeer` is
  already the server's own stand-in for a socket (D-051). The produce
  path is therefore testable end to end, shipped defs and all — **try
  before assuming otherwise.**
- **The caller-exists scan is still there and still carries D-106's own
  caveat: it only covers the callers it names.** A fourth knob added
  later is not covered by it.

**The gate passes and costs nothing visible.** `just test-load 4 300` on
the default map, 2026-08-24: clean, 0 desyncs over 1192 state-hash
checks, 0 dropped ticks, all three `gate-check.sh` comparisons green, and
**159.88 µs/squad at 49 squads** against the 167.7 µs at 48 squads
`m10-plan.md` records — the same number within two runs' noise, with
production at 2.7% of a squad-update. Quote it with its squad count, as
ever. A `test-scenario` run the same day reported 631 µs/squad on a host
down to 329 MB free with 6.6 GB of swap in use; that figure is junk and
the decision entry says so rather than leaving it to be found later.

**What the cap bonus costs the tick budget, stated rather than assumed.**
`squad_cap` is an ENGINEERING ceiling for D-018/D-020, not a design
lever, and `squad_cap_bonus` adds to it. Shipped cap is 40 on all three
maps and the largest shipped bonus is 4, so **D-018's 20-player target
worst-cases at 880 squads against the 1,000 `just profile` measures** —
inside what has been measured, +10%. The **lobby's 24-seat ceiling
worst-cases at 1,056**, which is past the sweep's top rung; note that
24 seats is 960 with no bonus at all, and that the tick budget is
*already* over at 1,000 squads on this tree (204.5 ms against D-020's
100 ms, open as #105). This change does not create that overrun and does
not fix it. `test_the_cap_bonus_worst_case_is_the_one_the_decision_records`
pins both numbers so a future civ's bonus is a deliberate re-measurement
rather than a silent one.

**Balance is untouched and deliberately so.** The shipped `.tres` numbers
are exactly what they were; this made them mean something. Northmen now
field 44 squads to the Legion's 40 and train 1.3x faster, so **every
`just ai-ladder` number taken before 2026-08-23 was measured against a
build where they did not** — quote a ladder result with its cap and with
which side of this change it came from. If the ladder says the numbers
are wrong, the fix is new numbers in the data. The same rule applies to
`test-load`: `production_speed` and `gather_speed` are multipliers on
rates feeding the economy and the AI opening, so timings move and a
per-squad cost is quoted with its squad count as ever.

**This is load-bearing for M9, not tidying.** Issue #191 (six fantasy
civs) builds two of its six identities on these fields — Gravesworn on
`squad_cap_bonus` and `production_speed`, Gildedreach on `gather_speed`
— and is gated on this landing first.
