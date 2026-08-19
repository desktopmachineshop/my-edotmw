### D-20260818-fantasy-civs-supersede-the-historical-frame · 2026-08-18 · **PROPOSED — owner call, not in force**

**Decision (proposed):** The game's civilisations are FANTASY folks, not
historical cultures. The six-civ historical roster of D-071 (Legion,
Northmen, Magyars, Byzantines, Carthaginians, Chinese) is superseded as
CONTENT; the candidate replacement set and full rosters are designed in
`docs/plans/fantasy-civs.md` (Stoneblood giant-kin, Gravesworn undead,
Thornwood elves, Windmarch centaurs, Gildedreach free cities, Emberdeep
dwarves). Nothing is implemented; no `.tres` exists for any of it.

**What survives unchanged, and this entry depends on it staying so:**

- **D-047** — civs are data; mechanical asymmetry is declarative knobs
  every civ has; no `.gd` names a civ. The fantasy set was designed
  inside this rule and its ids grep clean against the codebase.
- **D-071's FRAME** — the seven-column table and the "no two civs match
  on more than one column" rule. Only the *content* of the table is
  superseded; the frame is reused with the historical Basis column
  becoming a fantasy Folk column.
- **D-070** — rosters grow by replacement; the content bill logic is
  unchanged.
- **D-072** — the power budget (V = sqrt(DPS×EHP), RP = f+w+1.5(g+s)),
  the line band, "price buys power", "no free lunch". Every unit in the
  fantasy rosters was screened against it on paper.
- **D-032** — the counter triangle and the three armour classes. Every
  fantasy unit takes one of infantry/cavalry/missile; mounted missile
  stays `cavalry` per D-072's rule.

**What is superseded or invalidated if accepted:**

- **D-071's civ set, arc table, frame content and rejected-alternatives
  reasoning** (Scythians, Sassanids, longbowmen — all moot).
- **D-069's epoch flavour** ("antiquity → high medieval") — the five
  VERBS (settle/field/hold/break/decide) survive; the historical
  dressing does not. M9 planning needs a re-flavour pass, not a
  re-design.
- **D-072's epoch-1 worked table** (legion_levy etc.) — its NUMBERS and
  method stand as the template; its names are dead.
- **The two shipped civs** (`/civs/legion.tres`, `/civs/northmen.tres`
  and their eight units) become placeholder content to be replaced, not
  extended.

**Three consequences that need their own decisions before implementation:**

1. **Issue #158 becomes load-bearing.** Two of the six fantasy
   identities (Gravesworn, Gildedreach) lean on `squad_cap_bonus` /
   `production_speed` / `gather_speed`, which nothing reads. Wire them
   or redesign those identities — leaving them inert is the one option
   that must not survive contact with this pivot.
2. **`model_id` keyed by archetype collides with fantasy races.** Two
   human civs sharing a levy model was fine; a dwarf and a centaur
   sharing one is not. Either the art bill multiplies per civ (against
   D-081's "a new civ is a content job" principle) or shared archetypes
   need race-neutral models, which centaurs make impossible. This wants
   its own decision entry when implementation is scheduled.
3. **The authored triangle budget moves ~300 → ~10,000 per unit**
   (owner's call, 2026-08-19, in `docs/plans/unit-model-briefs.md`),
   superseding D-081's budget. 10k-tri meshes drawn raw do not fit the
   measured frame (D-085/D-086: ~54 ms at 27,300 soldiers at ~300
   tris), so this commits the build pipeline to generating decimated
   LOD tiers, and `bench-render` must be re-measured on them before
   any of this content is called shippable. Amend D-081 properly when
   this entry is accepted.

**Rejected alternatives:** none recorded — this pivot is owner-initiated
taste, not a technical trade-off. The alternative is the status quo
(D-071's historical set), which remains fully specified if this entry is
rejected.

**Consequences if accepted:** D-071 gets a "Superseded by
D-20260818-fantasy-civs-supersede-the-historical-frame" amendment;
docs/status/m9-plan.md needs its civ list corrected; the fantasy roster
document graduates from `docs/plans/` into implementation issues.
`tests/test_civs.gd`'s civ-count expectations move exactly as D-071
already described for six civs.

**Revisit trigger:** inherited from D-071/D-047 — the first fantasy civ
whose identity cannot be expressed through a knob every civ has. Undead
fearlessness (`rout_threshold 0`) is the nearest candidate and is
flagged for verification in the design doc rather than assumed.

---
