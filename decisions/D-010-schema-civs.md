# D-010 schema log — CivDef

Part of **D-010** (data-driven definitions). The decision, the rules for
adding to this log, and the index of the other schema logs live in
[`D-010.md`](D-010.md); this file is only the log for civdef.

**Append at the END. Never reorder, never edit an entry in place.** One
file per workstream is what stops four branches conflicting on one
monolith — see `README.md` rule 1, which this split exists to make D-010
obey.

**Scope:** fields on `CivDef` (`civ_def.gd`) — D-047's mechanical
knobs. See `docs/status/civ-knobs.md` for the standing rule that a knob
is read through an APPLIED function and never as a raw field.

---

- **2026-08-28, #270 — `CivDef` gains `build_speed: float = 1.0`,
  `march_speed: float = 1.0` and `gather_speed_by_kind: Array[float] =
  []`, and `squad_cap_bonus` gains a documented negative range.** Four
  civs had identity lines in `docs/plans/fantasy-civs.md` that the
  three-field schema could not express: a quality civ that fields FEWER
  squads (the bonus only meaningfully went up), a fortification civ that
  cannot fortify faster (`production_speed` divides `UnitDef.build_time`
  only, so it touches units alone), a forage civ that is "wood-rich,
  gold-poor" (not a smaller scalar — four numbers), and a mobility civ
  whose whole identity sat in four `.tres` move speeds with nothing at
  the civ level.

  All four are additive with neutral defaults, so five of six civs read
  exactly as they did; an empty `gather_speed_by_kind` means the scalar
  applies to all four resources. Each is read through an applied function
  on the schema (`construction_time`, `march_rate`, `gather_rate(base,
  kind)`, `squad_cap`) with a named caller, per
  `D-20260823-a-civs-knobs-are-read-by-the-simulation` — the rule that
  exists because these fields' three predecessors shipped read by nothing
  for a milestone. `validate()` refuses a non-positive multiplier and a
  partly-filled resource table. Recorded in
  `D-20260828-four-more-knobs-and-every-one-has-a-caller`.

---

