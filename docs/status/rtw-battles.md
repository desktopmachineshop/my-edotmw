**RTW-quality battles — a programme, in progress
(D-20260818-battle-quality-outranks-player-count).** The owner accepted
the three formation tiers
(D-20260818-rome-total-war-formations-in-three-tiers) and then widened
the order on the same day's gap analysis: close every gap between this
game's fights and Rome: Total War-quality battles, unit control and
fighting — morale terms, control verbs, charges, visible deaths, the
lot — and **sacrifice total player count to afford it**. The programme
entry has the twelve workstreams in dependency order and the exit
criteria; the trade's mechanics matter more than its slogan:

- **D-018's 20 players / 40,000 soldiers stops being the binding
  budget, but its successor is not chosen — it will be MEASURED** at
  programme end (exit criterion 8) and recorded in an entry superseding
  D-018's number. Until then nothing may quietly re-quote 20, and every
  measurement still carries its squad count.
- **What does NOT move:** server authority; squad-level stochastic
  combat (D-024 — the gap analysis found no gap that needs per-soldier
  resolution); derived animation phase (D-082); the fairness rule
  (outcomes never depend on where a camera points); and D-006 clause 1
  until its explicit amendment, which is workstream 10's first act, not
  a side effect.

**Workstream 1 — Tier 1, cosmetic duels — landed.** In a melee the
render layer pairs each man with his nearest opponent, faces him, steps
him into contact (`CosmeticDuel`, all-static and pure, D-006 clause 2)
and strikes at his own opponent rather than the squad's centre-point.
Outcomes, wire and server untouched — `combat.gd` is not in the diff.
Three things worth knowing:

- **Pairing is memoryless on purpose, and that is a probe, not a
  shortcut.** Nearest-opponent is recomputed per frame from both squads'
  derived positions; it is stable because its inputs are (curves move on
  keyframes, casualties restamp), and `SoldierMotion.ease` glides the
  retargets when they do happen. The three-tier decision's collapse
  trigger — "if a man must REMEMBER his opponent, Tier 2 is not a pure
  function" — is therefore being tested from day one. If Tier 1 duels
  visibly re-target in play, that is the trigger firing; report it
  against the decision, do not add a cache.
- **The duel can never scatter a formation.** A man steps at most
  `MAX_STEP` (1.1) from his authoritative slot, stands `CONTACT_GAP`
  (0.7) short of his opponent, and past `ENGAGE_RANGE` (6.0) holds his
  slot exactly while still bracing toward the enemy. Selection,
  culling, separation and the composition hash all still read the
  derived transforms.
- **`just gen-duel-preview` is the instrument.** Two authored squads,
  real `Formation.slot_offset` lines, the real three-call pipeline
  client.gd runs per frame, screenshot to `artifacts/duel-godot.png` —
  **look at it**; the recipe fails if nobody moved or nobody reached
  contact, and prints the duel pass's µs with its squad sizes. It
  exists because `test-client` frames a spawn, which is the one place a
  melee is not (the same lesson as cliffs, forests and the fog edge).

**Not yet built:** workstreams 2–12 — visible deaths, Tier 2's contact
set, the morale terms (flank shock, chain rout, pursuit), facing and
width opcodes, charge, stances, drag placement and group formations,
formation specials as data, the D-006 amendment plus Tier 3, fatigue
and terrain height, generals. The decision entry is the map; each
workstream cites it and lands as its own PR.
