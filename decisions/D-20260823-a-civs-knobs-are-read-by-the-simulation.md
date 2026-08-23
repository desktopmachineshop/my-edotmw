# D-20260823 · 2026-08-23 · Accepted — a civ's mechanical knobs are read by the simulation

**Decision:** `CivDef`'s three mechanical knobs — `squad_cap_bonus`,
`production_speed` and `gather_speed` — are **wired up**, not deleted.
Issue #158 put both options on the table and said the one that must not
survive is leaving them declared and unread. Five clauses:

1. **A knob is only ever read through an APPLIED function on `CivDef`.**
   `squad_cap(base)`, `production_time(base)` and `gather_rate(base)`.
   Nothing outside `civ_def.gd` touches the raw fields. Two of the three
   are read on both sides of the wire — the server spends the production
   time, the client draws the bar counting it down — so `base /
   production_speed` written out twice would be two copies of one rule
   free to drift, which is the D-058/D-065 family exactly.
2. **An unknown civ is a default-constructed `CivDef`, never null.**
   `CivRoster.effects_of(id)` never answers null, so no call site needs
   its own "what if there is no civ" default. "No civ" is a real state
   and not an error: a player is seated before the lobby resolves Random
   (D-048), and the load-test bots never learn a civ at all because a
   lobby is what broadcasts one.
3. **The simulation is TOLD who plays what.** `SquadSim.civs` is
   `player -> CivDef`, `SquadSim.civ_effects(player)` reads it, and
   `server.gd`'s `_hand_civs_to_sim()` fills it — the exact sibling of
   `_hand_teams_to_sim()`, one line above it, for the same reason.
4. **The handover happens on every path a player's civ can become
   known**: both ways a match starts, and `_admit_player`, which on the
   `--lobby=0` path runs long after the match began. `_civ_of` is total,
   so re-handing is idempotent.
5. **`_civ_of`, not `MatchState.civ_of`.** `_civ_of` is what resolves the
   ROSTER a player builds from. A player whose troops came from one civ
   while their cap came from another is a fault nothing could see.

**No new wire field, and no new tuning.** `squad_cap` is already
per-client in `S2C_WELCOME`, so the HUD's n/cap readout gets the
player's own ceiling for free. The shipped `.tres` values are unchanged
— this decision makes them mean something; whether 1.3 is the right
number is a balance question for M9, not this.

## Rationale

From **#158**, found in the playtest P09 gap survey (#35):

```
$ grep -rn "gather_speed" --include=*.gd . | grep -v "civ_def.gd\|tests/"
(no output)
```

Same for the other two. So the two shipped civs differed by their
roster, their colour and their opening stockpile, and every *declared*
mechanical difference was inert. Northmen ship `squad_cap_bonus = 4` and
`production_speed = 1.3` — a numbers civ that could field neither more
troops nor sooner.

**One correction to the issue, and it shaped the design:** its table
reports all three knobs as non-default in the shipped data. Only two are.
`gather_speed` reads **1.0 on both civs**, so it is wired here with no
shipped value exercising it — which is exactly why the fixture builds a
synthetic `CivDef` instead of naming a shipped one, and why
`SquadSim.civs` holds a resolved def rather than an id (see the rejected
alternatives).

This is the **fourth** instance of the declared-and-unread defect class,
after `UnitDef.cost`, `BuildingDef.cost` and `BuildingSim.damage()`
(D-055, which meant no match could be won for two milestones). Nothing
failed. The game quietly lacked a rule.

**Wiring beats deleting here for one reason that is not sentiment:**
CLAUDE.md lists this as one of two things M9 must fix *before it starts*,
because two of the six planned civ identities depend on these knobs, and
D-046's governing constraint is that mechanical asymmetry is a knob every
civ has rather than a per-civ branch. Deleting them does not remove the
requirement; it removes the only sanctioned shape for meeting it, and the
next civ that wants to be faster arrives with nowhere to say so.

### Where each one landed, and why there

| knob | applied at | why not elsewhere |
|---|---|---|
| `squad_cap_bonus` | `MatchState.squad_cap_for(sim, player)`, read by `has_squad_capacity` **and** by the WELCOME the HUD draws from | a HUD saying 40 while the server refuses at 44 is a rule the player cannot see |
| `production_speed` | `_handle_order_produce`, at **enqueue**, as real seconds | the queue head counts down at 1 s/s on the wire and the client draws that countdown (D-003) — a multiplier applied per TICK instead leaves every client's "— 12 s" wrong |
| `gather_speed` | `Economy._gather`, **per tick** | latching it into the haul when the order was given is a cached copy of a fact the simulation already holds, which is the shape of the D-038 ownership cache that silently refused every produced squad an order |

The client's production bar divides by `CivDef.production_time(build_time)`
for the building's OWNER, not by the raw `UnitDef.build_time`. Without
that, a civ at 1.3 draws a bar that starts 23% full — the arithmetic was
right on the server and the picture wrong, which is this project's
best-attested failure mode.

## Rejected alternatives

- **Delete the three fields and record that civ differentiation is
  roster-only.** #158's other branch, and legitimate. Rejected because
  M9's plan already depends on them (D-071/D-047) and D-046 forbids the
  per-civ branch that would otherwise be reached for.
- **Resolve the civ inside `Economy` / `BuildingSim` from a roster
  lookup.** Both would then know what a civ is, and both are on hot
  paths. The sim already holds `teams` for precisely this reason —
  MatchState owns CHOOSING, the sim owns the CONSEQUENCE.
- **Store the civ ID in `SquadSim.civs` and resolve on read.** Costs a
  roster lookup in the gather path and, more importantly, makes a knob no
  shipped civ turns yet untestable: `gather_speed` is 1.0 on both shipped
  civs, so a fixture that could only name a shipped civ would prove
  nothing about a third of this work. Holding the resolved `CivDef` lets
  a test hand in a synthetic one, exactly as every fixture here already
  builds a synthetic `UnitDef`.
- **A new wire field carrying the queue head's TOTAL**, so the client
  need not resolve production speed itself. The precedent exists
  (`health_fraction` is sent as a fraction so the client needs no copy of
  `max_health`). Rejected as more wire surface than one shared function,
  and there is no protocol version handshake until M8 (D-094).
- **Multiplying the squad cap rather than adding to it.** The field's own
  header already refused this: D-033's cap bounds total squad count,
  which is the axis the architecture is sensitive to (D-018), and a
  multiplier lets a civ definition quietly rewrite that budget.

## Consequences

- **Northmen now play differently, and every AI-ladder number taken
  before today is measured against a build where they did not.** They
  field 44 squads to the Legion's 40 and train 1.3x faster. Quote a
  ladder result with its cap *and*, from here, with which side of this
  change it was taken on.
- **`server: SIM_CIVS 1=…, 2=…` is a new log marker**, the sibling of
  `SIM_TEAMS`, printed for the same reason: a harness asserting that
  civs reached the SIMULATION must read the simulation.
- **`ScenarioWorld` hands its round-robin civs to the sim too.** A
  fixture whose troops came from a civ while its gather rate came from
  nobody would be measuring a match no server plays — the #119 "dormant
  half" trap, one file over.
- **`BuildingSim.enqueue` takes an optional `build_time`.** Omitted, it
  is the def's own, so every existing caller keeps the behaviour it had.
- **`tests/test_civ_knobs.gd` is the guard, and the load-bearing test in
  it is not a behaviour test.** `test_every_mechanical_knob_is_read_by_
  something_that_ships` scans for a shipping caller of each applied
  function; every other test in the file passes with the server applying
  none of it, because a mechanism with no caller fails nothing. Same
  shape as `test_terrain_fog.gd`'s caller-exists test for D-106 — and
  D-106's own lesson applies here too: **that test only covers the
  callers it names.** A fourth knob added later is not covered by it.
- **A knob nobody sets is the next failure**, not this one.
  `test_the_shipped_data_actually_turns_at_least_one_knob` fails if every
  shipped civ leaves all three at their defaults, because "mechanism
  correct, shipped numbers do nothing" (D-066) is what wiring a knob
  nobody turns would produce.

## Revisit trigger

- **A knob that genuinely resists being a parameter.** D-046's own rule:
  record it and amend D-046 rather than quietly writing the per-civ
  branch.
- **M9 needing a knob to vary by EPOCH as well as by civ** (D-069/the
  2026-08-23 fantasy ladder). `SquadSim.civs` holds one def per player;
  an epoch ladder makes that a def per player *per rung*, which is a
  change to the handover rather than to any call site.
- **The ladder showing the numbers are wrong.** That is a data change in
  `/civs/*.tres` and explicitly not a reason to reopen this.
