# D-010 schema log — epochs and techs

Part of **D-010** (data-driven definitions). The decision, the rules for
adding to this log, and the index of the other schema logs live in
[`D-010.md`](D-010.md); this file is only the log for epochs and techs.

**Append at the END. Never reorder, never edit an entry in place.** One
file per workstream is what stops four branches conflicting on one
monolith — see `README.md` rule 1, which this split exists to make D-010
obey.

**Scope:** the M9 epoch/tech ladder — `EpochDef`, `TechDef`, and the
fields those add to `UnitDef`, `BuildingDef` and `CivDef`.

---

**Nothing here is implemented.** Every entry below is a
SPECIFICATION, kept so it has one home, and marked so nobody reads
this log as a description of the repo.

- **PROPOSED, not implemented — the M9 epoch schema (D-070).** Recorded
  here so the specification has one home, and marked clearly because
  **none of it exists in code**. The age/tech planning milestone was
  documents-only; anything reading this log as a description of the repo
  would be misled.

  | Field | Type | Default | Purpose |
  |---|---|---|---|
  | `UnitDef.epoch` | `int` | `1` | earliest epoch this unit may be produced |
  | `UnitDef.upkeep_food` | `float` | `0.0` | per soldier per second (D-068) |
  | `BuildingDef.epoch` | `int` | `1` | earliest epoch this building may be founded |
  | `CivDef.upkeep_modifier` | `float` | `1.0` | D-068 |
  | `CivDef.epoch_advance_speed` | `float` | `1.0` | who climbs faster |
  | `CivDef.build_speed` | `float` | `1.0` | D-073's parameterisation pass found no build-speed knob exists at all |
  | `CivDef.epoch_names` | `Array[String]` | `[]` | five display strings, flavour only |

  Plus a new resource type, `EpochDef`, in `/epochs/*.tres` — index,
  display name, `cost_*`, `research_time`, prerequisite building ids —
  so the ladder itself is editable text and no script names a rung.

  Every default is chosen so an unaware `.tres` is epoch-1, upkeep-free
  and valid, following the same safe-default reasoning as
  `damage_vs_buildings` above.
