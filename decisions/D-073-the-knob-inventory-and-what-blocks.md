### D-073 · 2026-08-04 · Accepted — the knob inventory, and what blocks implementation
**Decision:** Every mechanical claim in D-071 is mapped here to the
parameter that expresses it. A claim with no knob is either **given a knob
every civ has, or cut** — settled on paper, before any code, because
`tests/test_civs.gd:43` makes "no script may name a civ" a test rather
than a guideline.

| Claim (D-071) | Knob | Status |
|---|---|---|
| Legion quality; wins even fights | `UnitDef` `health`/`damage`/`squad_size`/`cost_*` | exists |
| Legion *comitatenses*: never breaks | `UnitDef` `morale`, `rout_threshold`, `rout_rally_margin`, `morale_recovery_per_second` | exists |
| Legion bad at reacting | low `move_speed`; no fast archetype in its subset | exists (structural) |
| Northmen quantity | `squad_size` against `cost_*` | exists |
| Northmen Great Heathen Army | `CivDef.squad_cap_bonus`, `CivDef.production_speed` | **declared, INERT** |
| Northmen raiding | `move_speed`, `vision_range` | exists |
| Northmen no heavy foot | roster subset — which `.tres` name the civ | exists (structural) |
| Magyar mobility, map control | `move_speed`, `vision_range` | exists |
| Magyar poor siege | `UnitDef.damage_vs_buildings` (default 0.15) | exists |
| Magyar low infrastructure early | per-civ building availability | **blocked — defect 3** |
| Who climbs the ladder faster | `CivDef.epoch_advance_speed` | **new** |
| Byzantine fortification | `BuildingDef` `max_health`, `no_build_radius`, `attack_range`, `damage` | exists |
| Byzantine siege train | high `UnitDef.damage_vs_buildings` | exists |
| Byzantine bad early tempo | `BuildingDef.build_time`/`cost_*`; low `move_speed` | exists |
| Carthage highest gather | `CivDef.gather_speed` | **declared, INERT** |
| Carthage broad gold-priced roster | subset size + `cost_gold` | exists (structural) |
| Chinese reach, earliest missile | `attack_range` + `UnitDef.epoch` | exists + **new** |
| Chinese infrastructure-heavy | per-civ buildings | **blocked — defect 3** |
| Army as a running cost (D-068) | `UnitDef.upkeep_food`, `CivDef.upkeep_modifier` | **new** |
| Epoch gating (D-070) | `UnitDef.epoch`, `BuildingDef.epoch` | **new** |
| Civ-flavoured epoch names | `CivDef.epoch_names: Array[String]` | **new** |

**Three claims were cut here for having no knob.** Recording them is the
point of the exercise — each would have become a branch:

1. *"Legion squads do not rout while a friendly squad is adjacent."*
   Needs adjacency-aware morale that only one civ has. **Cut**, and
   re-expressed as simply the highest `morale` and `rout_rally_margin` in
   the game. The fantasy survives; the branch does not.
2. *"Byzantine builders raise fortifications faster."* **There is no
   build-speed knob at all** — `building_sim.gd:359` is
   `_progress += dt / build_time` with no multiplier, and
   `advance_production` at `:229` is the same. Rather than cut this,
   **add `CivDef.build_speed: float = 1.0`**, the obvious sibling of the
   two inert knobs beside it. This is the correct outcome of a
   parameterisation pass: the claim named a gap that every civ should
   have access to.
3. *"Carthage can hire another civ's units."* Would require a script to
   know another civ exists — the exact failure D-047 exists to prevent.
   **Cut**, and re-expressed as a broader *own* roster carrying gold
   costs.

**Four defects that block implementation.** None is caused by this
milestone; all sit directly under it:

1. **Three `CivDef` knobs are declared, shipped with non-default values,
   and read by nothing.** `squad_cap_bonus = 4` and
   `production_speed = 1.3` on northmen are inert —
   `match_state.gd:420`, `building_sim.gd:229` and `economy.gd:382` apply
   no multiplier anywhere. Two of D-071's six civ identities depend on
   them. This is the **fourth** instance of the declared-and-unread class
   (`UnitDef.cost`, `BuildingDef.cost`, `BuildingSim.damage` per D-055),
   and it is the defect class this project's testing discipline is blind
   to by construction: nothing fails, the game simply lacks a rule.
2. **`built_by` is keyed two ways.** `server.gd:993` passes the builder's
   **archetype**; `client.gd:1850` and `:1951` pass its **UnitDef id**;
   `building_def.gd:59` documents the field as ids. It works today only
   because both builders are neutral units where the two strings
   coincide. Epoch 3+ adds civ-specific builders and it breaks — the
   client will offer a build the server refuses.
3. **`BuildingDef.civ` is dead weight** — declared, always `neutral`,
   never filtered on anywhere. There is no `BuildingRoster.for_civ()`.
   Two civ identities above are blocked on it.
4. **`produces` is documented as UnitDef ids and actually holds
   archetypes** (`building_def.gd:55` versus `building_sim.gd:182`).
   Harmless today, actively misleading once epoch-gated production is
   written against the comment.

**Consequences:** defects 1 and 3 are prerequisites, not cleanup — two of
six civs cannot be expressed until they are fixed. Per D-022's standing
rule, each of the three inert knobs must be proved by a test **observed
to fail before it is trusted**: turn the knob, watch the test go red,
revert.

**Revisit trigger:** any future civ claim that reaches this table with no
knob and no general knob worth adding. That is the D-047 boundary, and
the honest response is to amend D-047, not to quietly add a branch.

---
