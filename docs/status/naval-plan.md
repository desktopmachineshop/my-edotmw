**Naval is DESIGNED, and STAGE 2 of nine is built** — the design session
ran on 2026-08-28 (issue #301) and the water domain landed the same day.
Everything else in the cut-list is still specification: **no `.tres`
declares a ship, no dock exists, nothing embarks, and no AI sails**, so
treat every schema field named below that stage 2 did not add as a
specification rather than a description of the repo.

**What stage 2 built:** `SquadSim.DOMAIN_WATER` as a third value of
`_tier`, `set_navigable` taking the water graph the way `set_passable`
takes the land one, a third `FlowField` layer with its own budget and
cache, `UnitDef.movement_domain`, and water belief in
`TerrainKnowledge`. It consumes an array and never computes one, which is
what let stage 1 be written in parallel.

**The budget is measured.** A full naval solve on the `islands` preset is
5,690 cells / 5.8 ms at Skirmish, 22,149 / 22.9 ms at Standard, 48,717 /
52.0 ms at Large and 86,989 / 108.4 ms at Huge — about 1.03 us per cell,
so a Standard naval field is two thirds of a whole-map ground field. The
budget is set EQUAL to `field_cells_per_tick` (neither layer privileged),
which puts the first naval order at 1 tick on Skirmish and 2 on Standard.
**A live worst-tick figure is OWED**: nothing sails in a real match yet,
which is exactly the position D-076 reported for the wall layer, and the
number to quote comes from `test-load` on a water map once the AI stage
lands.

---

**The design, as written —** the design session ran on
2026-08-28 on the owner's directive (issue #301) and produced
`docs/plans/naval.md` plus three decisions:
`D-20260828-water-is-a-second-movement-domain`,
`D-20260828-a-carried-squad-is-cargo` and
`D-20260828-a-dock-stands-on-a-shore`. **No code exists** — treat every
schema field named below as a specification, never as a description of
the repo.

**It resolves #280 the other way.** `D-20260828-a-map-a-player-can-pick-
is-a-map-an-army-can-cross` measured that `islands` cannot host a match —
29-35% walkable across 12-268 components, **failing at two seats** — and
retired it. The owner overruled the conclusion, not the measurement:
build the game that map needs. That entry is superseded and its
`TerrainPreset.playable` flag becomes the switch the last stage flips.

The shape, in four sentences:

- **Water is a third value of `SquadSim._tier`**, which becomes a
  movement DOMAIN rather than a tier — ground, wall-top, water. D-076
  built every hard part already (a per-squad layer with its own
  passability, a second `FlowField` layer with its OWN budget, an
  explicit teleporting hop that keeps D-006 clause 1 intact, and a
  targeting rule about which layers reach which); naval drives it a third
  time rather than generalising it, which is the call D-076 itself made
  when it rejected a unified multi-tier graph.
- **A carried squad is CARGO and is not in the world** — no cell, no
  vision, and **absent from `visible_to` for everybody including its
  owner**, so `composition_hash()` agrees on both sides by construction.
  That is D-099's ghost lesson applied before it can bite: a client that
  counted its own cargo would hash a strictly larger set and desync on a
  healthy system. Cargo rides on the ship's own `SQUAD_INFO`.
- **You load at a dock and you land anywhere.** Deliberately asymmetric,
  and it is where naval departs from D-076: the wall-top has ONE door
  because a wall has a LINE to defend, and there is no line at sea. A
  rule that only let you land where a dock already stood would mean you
  can only invade an island the enemy has already settled.
- **Ten ships across six civs**, two of them combined attack-transports
  where the civ's axis argues for it (Stoneblood's quality, Windmarch's
  land-bound mobility). Every one passes D-072's screen, computed rather
  than asserted.

Five things worth knowing before anyone picks up a stage:

- **A unit's domain is a property of the UNIT, not of the order.** D-076
  infers the target tier from the destination cell, which is what let it
  add a whole tier with no wire change — but a shore cell is legal land
  AND adjacent to legal water, so the cell alone cannot say what was
  meant. A `movement_domain` field on the unit keeps the wire unchanged
  anyway and makes the ambiguity impossible rather than adjudicated.
- **D-076's 1,024 cells/tick must NOT be copied for the water layer.**
  `islands` is 65-71% water, so on the map this feature exists for the
  naval field solves over roughly TWICE the area the ground layer does.
  The budget is a measurement, taken the way D-076 took the wall
  layer's and quoted with its squad count — and it lands on a tick that
  is already over budget at scale (#105 has the 1,000-squad worst tick
  at 204.5 ms against D-020's 100 ms).
- **The AI must sail, or none of this exists.** D-076's own entry ends
  by recording that no AI builds or uses walls, so `just ai-ladder` has
  never exercised the whole wall system — which is exactly why #210 (an
  auto gate never opened for an ally) sat undetected. The plan makes the
  consumers part of the feature: new `AI_STATS` keys, a ladder gate that
  fails unless a landing happened, a `test-load` gate on embarks and
  landings, and a beachhead scenario for the fast loop. **If the schedule
  slips, cut content before consumers** — two ships the AI sails beat ten
  it has never heard of.
- **A zero must say WHICH leg broke.** `landings = 0` is what a land-only
  map, an unplayed match and a broken transport all report, so the
  verdict fails first on "no dock was built", then "no ship was trained",
  then "no squad embarked" — the vacuity discipline D-022's audit block
  and #119 both bought.
- **The "every start shares one landmass" rule becomes WRONG for naval
  maps.** (Its decision entry is on the #128 branch, PR #216, and is
  cited by id in `docs/plans/naval.md` rather than here — this page is
  imported into every session and may not name a decision that is not
  yet on this history, which is the drift guard doing its job.) One
  walkable component is right only while armies cannot cross water; it
  has to become "one reachable component, where reachable includes water
  for a side that can cross it". That is the last stage of the cut-list
  and it is what re-enables `islands`.

**Open, and named rather than assumed:** whether a naval game is fun here
(only the owner playing an islands match can say — D-085 criterion 14's
lesson applied in advance); whether two ships per civ is enough for the
axis differences to read in play; and what a naval map does to match
length, since marches become voyages and the standing rule applies —
when the opening changes, every timing tuned against the old one is
stale.

**One question left for the owner, one bool either way:** whether
`islands` is offered in the lobby WHILE naval is built — a period in
which it is still a map that cannot host a match — or stays hidden until
spawn placement knows the water graph. The design recommends hidden, so
the preset becomes visible on the day it becomes playable.
