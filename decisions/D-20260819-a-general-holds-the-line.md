# D-20260819 · A general holds the line

**Status:** ACCEPTED — workstream 12 of
D-20260818-battle-quality-outranks-player-count, deliberately
small-scoped as that entry demands ("if it grows — auras, abilities,
succession — it gets its own decision first"; this IS that first
decision, and it stays at presence and death).
**Extends:** D-20260819-morale-reads-the-fight (the aura and the death
shock are terms in the same model). **Schema:** `UnitDef.is_general`,
recorded against D-010's log.

## Decision

A general is a unit archetype flag, not a new entity kind:

- **`UnitDef.is_general`** — shipped as one small elite squad per civ
  (`.tres` only, primitive model until the art host unblocks; D-081's
  fallback rule means that costs looks, never function). Produced by the
  town centre, expensive, and **limited to one ALIVE per player**,
  enforced where production is already validated server-side.
- **Presence steadies:** allied squads within `GENERAL_AURA_CELLS` (10)
  of a living allied general recover morale at twice their rate and pay
  HALF the chain-rout shock. The aura reuses the tick's cell buckets
  over `disk_offsets` — the standing any-radius-scan rule.
- **Death shocks:** a general's squad dying in combat deals
  `GENERAL_DEATH_MORALE_LOSS` (24 — twice a chain rout) to every allied
  squad within the same radius, through the same shock machinery, and
  can cascade like any rout. Consumption/elimination events (fell =
  false) shock nobody — the wire already knows the difference
  (D-20260819-a-casualty-is-visible).

## Rejected alternatives

- **The founding party as the general.** D-031 spends it on the town
  hall by design; a general you must never use is a trap, and a
  founding party you dare not build with is worse.
- **Auras as flat combat buffs.** Damage auras relitigate the counter
  triangle; morale is what a commander's presence IS in this game's
  model.
- **Succession/bodyguard mechanics.** Scope. The revisit trigger below
  names them.

## Revisit trigger

If playtests want more of a general — abilities, succession, a
bodyguard rule, capture — that is the growth the programme entry
predicted and it reopens HERE, not in code. If the one-alive limit
chafes (team games wanting a second), it is a constant.
