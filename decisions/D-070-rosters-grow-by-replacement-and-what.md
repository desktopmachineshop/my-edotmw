### D-070 · 2026-08-04 · Accepted — rosters grow by replacement, and what that costs
**Decision:** Each epoch unlocks **genuinely new archetypes alongside the
old ones** (owner's call, 2026-08-04), rather than upgrading an existing
`UnitDef` in place. `spearmen` (E1) and `pikemen` (E3) are different
archetypes with different `.tres` files, not two versions of one.

**Rationale:** consistent with D-047, which rejected shared UnitDefs plus
per-civ multipliers because "it hides a unit's real numbers behind
arithmetic in another file, and this project optimises for stats being
directly readable and editable as text." The same argument applies across
epochs exactly as it did across civs. It also needs **no new lookup
machinery**: `UnitRoster.for_civ_archetype()` still returns one def per
(civ, archetype) pair, and epoch gating is a filter on top.

**The content bill, accepted up front rather than discovered in epoch 3.**
At 6 civs × 5 epochs with each civ fielding a subset per rung, the
endpoint is roughly **90–130 unit `.tres`**, against ~40 for
upgrade-in-place. That is the price of readable stats and it is being paid
knowingly. Epoch 1 alone is ~20 files, which is why it is the vertical
slice (D-072).

**Obsolescence is replacement's known failure mode, and upkeep is the
answer.** Under a hard squad cap, an epoch-1 levy squad at epoch 5 is
*strictly* bad: the cap makes power-per-squad the only currency, so cheap
units are worthless and the player is punished for owning them. Under
D-068's upkeep, power-per-*resource* matters again, and cheap old units
have a real job — screening, map presence, garrison, escorting builders —
because they cost less to keep. **This is the load-bearing connection
between D-068 and this entry: without upkeep, replacement rosters
manufacture trash.** If upkeep is ever dropped, this decision has to be
reopened with it.

**Rejected alternatives:**
- *Upgrade in place* (militia → man-at-arms). Rejected by the owner —
  ~40 files instead of ~130 and no obsolescence problem at all, but every
  unit's real numbers become a chain of edits across epochs.
- *Hybrid — core lines upgrade, each epoch adds one new archetype.*
  Rejected as the most design work to keep coherent for a benefit that
  upkeep already delivers.

**Proposed schema, logged against D-010 — NOT IMPLEMENTED.** This
milestone is documents only; nothing below exists in code yet, and this
list is the specification for M9, not a description of the repo:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `UnitDef.epoch` | `int` | `1` | earliest epoch this unit may be produced |
| `UnitDef.upkeep_food` | `float` | `0.0` | per soldier per second (D-068) |
| `BuildingDef.epoch` | `int` | `1` | earliest epoch this building may be founded |
| `CivDef.upkeep_modifier` | `float` | `1.0` | D-068 |
| `CivDef.epoch_advance_speed` | `float` | `1.0` | who climbs faster |
| `CivDef.epoch_names` | `Array[String]` | `[]` | five display strings, flavour only |

Gating is one added clause in the existing chain: a def is producible when
`def.epoch <= player_epoch`, checked beside the `for_civ_archetype()` null
test at `server.gd:1115`. Defaults are all chosen so an unaware `.tres`
is epoch-1 and free to keep — the same safe-default reasoning D-056 used
for `damage_vs_buildings`.

**Revisit trigger:** if the unit count passes ~130, or if two civs'
versions of the same rung stop differing by more than numbers, the
upgrade-in-place model should be re-costed honestly rather than defended.

---
