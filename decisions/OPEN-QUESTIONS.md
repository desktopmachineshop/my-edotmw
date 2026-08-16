## 2. Open Questions / Not Yet Decided

Ordered by how much they block. ~~Struck through~~ entries are resolved
and now live as decisions above.

**Resolved this session:**
- ~~Q1 — What does "500 units" mean?~~ → D-018 (2,000 soldiers/player,
  ~50 squads/player, ~40 soldiers/squad)
- ~~Q2 — What is the Rome Total War half of the hybrid?~~ → D-019
  (formations & morale/routing only, no campaign layer)
- ~~Q9 — Simulation tick rate?~~ → D-020 (10 Hz; per-LOD-tier variation
  still open, deferred to M5 with D-012)
- ~~Q6 — C# in the shipping build?~~ → D-021 (no; GDExtension per-kernel
  is the escape hatch, and D-009's C# clause is narrowed accordingly)

**Blocking M1:**
- ~~D-006 confirmation~~ → confirmed 2026-07-28. The
  derived-soldier-positions keystone is Accepted, scoped by the purity /
  one-way-cosmetic-offset / deterministic-reassignment clauses in D-006's
  confirmation block. No longer blocks M1.
- ~~Q6 — C# in the shipping build?~~ → D-021 (no). Note for the record
  that the premise of this question — that it turns on export matrix and
  platform support — did not survive examination; it turned on toolchain
  cost and reversibility instead. **Nothing now blocks M1 on the
  decision side.**

**Blocking M2:**
- ~~Q7 — Combat model~~ → D-024 (2026-07-30): squad-level stochastic
  resolution, server-only, casualties as integer decrements to `alive`.
  The shape question is closed; per-unit tuning *values* are ordinary
  data work under D-010, not an open decision. Note what settled it —
  `alive` is the only formation input a death changes, so D-006 clause
  3's deterministic reassignment holds by construction and no
  per-soldier identity is needed anywhere.
- ~~Q9 — Simulation tick rate~~ → D-020 (10 Hz). The remainder — whether
  the tick rate **varies by LOD tier** — is still open and deferred to
  M5 with D-012, so it no longer blocks M2.
- ~~Fog reveal/conceal semantics~~ → D-025 (2026-07-30): true-position
  pop-in, announced stale ghost, per-player vision field. D-004 is no
  longer Provisional. **Nothing now blocks M2 on the decision side**;
  M2's exit criteria are D-026.

**Still open within M2's scope, deliberately deferred:**
- **Terrain-occluded line of sight.** D-025 makes vision radius-only;
  elevation does not occlude. Deferred rather than forgotten — it needs a
  height field the simulation does not carry yet, and it extends D-025's
  vision field rather than replacing it.
- ~~**Rally vs. permanent rout.**~~ → resolved 2026-07-30 as **rally with
  hysteresis**, which is what M2 already implements. D-024 said this call
  was best made against something playable; M3 is that thing, so the
  decision is to keep the implemented behaviour and revisit after the
  first real playtest rather than change it unplayed. D-024 no longer
  carries an open item.

**Raised by M2's review, 2026-07-30 — logged rather than fixed:**
- ~~**Simultaneous vs. sequential combat resolution.**~~ → **resolved
  2026-07-30 (M3): the round is now simultaneous.** Every attack reads
  strength and rout state from a snapshot taken at the start of the
  round, so squad id no longer decides mirror engagements. Two tests
  guard it, and perturbing the change back to live state makes them fail
  by exactly one soldier (13 vs 12) — the first-strike advantage, made
  visible. Original finding follows, kept for the trail. `Combat.resolve()`
  iterates attackers in squad-id order and applies damage immediately, so
  a lower-id squad kills part of its enemy *before* that enemy fires, and
  the enemy then attacks at reduced strength. It is deterministic, so
  replays are unaffected — but it is not neutral: identical unit types
  share an `attack_interval` and both start at `_last_attack_tick = -1`,
  so they fire on the same ticks indefinitely and the bias never averages
  out. Squads are spawned in join order, so **player 1 systematically
  wins mirror engagements.** Resolving from the round-start snapshot
  (`before_alive`, already taken) would make the round simultaneous. Left
  open because simultaneous-vs-sequential changes battle outcomes and
  therefore wants a D-024 amendment, not a silent patch.
- **Squads render off the map at the seam.** M2's `test-client` frame
  shows a squad drawn below the terrain's bottom edge, outside the
  meshed domain. `StateCurve` stores continuous *unwrapped* axial space
  by design (read its header), so a squad mid-seam-crossing samples to a
  position outside `[0, width) × [0, height)` while the terrain is meshed
  once. Client-side rendering only — the simulation wraps correctly, and
  no D-026 criterion covers it. Invisible until M2 because M1's frame had
  12 squads in one lane and none crossed a seam.

~~**Blocking M3**~~ — **all seven closed 2026-07-30.** D-027 is the
milestone's definition of done. Its shape: full gathering economy,
gatherer *squads* not individual workers, round-trip hauling, four
resources, player-placed construction, elimination victory, four unit
types with counters, and a visually wrapping torus. The seven remaining
items resolved as:

- ~~Are resource wallets private?~~ → **Private to owner.** Showing an
  opponent your stockpiles leaks information of the same family as
  D-003's intent leakage, and fog exists to withhold exactly that.
- ~~Which buildings exist?~~ → **Four**: town centre (gatherer squads,
  doubles as drop-off), barracks (military squads), storehouse (cheap
  forward drop-off), **defensive tower**. The tower is the consequential
  one — it makes buildings *attackers*, not merely destructible targets,
  which is a larger change to `combat.gd` than being a target. See D-029.
- ~~Do resource nodes deplete?~~ → **Finite, generous yields.**
  Depletion is what makes armies contest new ground as a match runs.
- ~~Where do nodes come from?~~ → **Derived from terrain biomes.** This
  invalidates `terrain_gen.gd`'s standing comment that it exposes
  `biome_color` "rather than a biome enum for now: M1 has no gameplay
  that reads biome" — biome becomes first-class simulation data. See
  D-037.
- ~~4-player fairness, given generated nodes?~~ → **Quadrant-symmetric
  generation.** `_sample` already embeds the map on a 3D torus with
  angular `u`/`v`, so doubling both makes the noise repeat twice per axis
  and the four quadrants come out bit-identical *by construction* — no
  scoring heuristic, no seed rejection. Fairness becomes a property of
  the generator. See D-036. **Superseded twice since:** D-036 revised
  dropped symmetric generation (it made every map the same map four
  times) in favour of free terrain plus a resource-fairness post-pass,
  and D-039 replaced the grid of spawn points with random placement at a
  minimum spacing. Fairness now lives entirely in
  `Economy.balance_for_spawns`, and spacing is the only thing placement
  guarantees.
- ~~Population cap?~~ → **Hard per-player squad cap**, sized to D-015's
  12–15 squads, bounding the match on the axis the architecture is
  actually sensitive to. **Gatherer squads count against the same cap**
  (decided 2026-07-30) — one shared ceiling covering military and
  economy alike, so every villager crew is an army slot not spent. That
  is the economy-versus-army tension made structural rather than a
  balance number, and it means the cap bounds *total* squad count, which
  is what keeps M2's measured per-squad budget valid at 4 players.
- ~~Is 64×32 big enough?~~ → **No. The map becomes 128×64 (8,192
  cells).** Evidence: M2's load test gated only 5 of 48 squads, and one
  squad's vision covers ~169 cells, so twelve squads nearly blanket the
  old map. Watch item: `FlowField.build` is a BFS per destination, and
  D-021 names that solver over 10,000+ cells as the prime GDExtension
  candidate — 8,192 sits just under it, so flow-field cost is measured
  rather than assumed.

**Blocking M4/M5:**
- ~~**Q8 — Map size in cells at ship**~~ → **answered by M4's profiling,
  not before it** (2026-07-30). Flow-field build is a BFS per destination
  over every cell, and D-021 already names that solver over 10,000+ cells
  as the prime GDExtension candidate — so map size is an *output* of
  profiling rather than an input to it. M4 sweeps cell counts through and
  past that threshold, finds where the solver breaks, and the ship size
  is chosen from that curve. Torus parity constraints from D-008 still
  bound whatever is chosen.
- ~~**Q15 — Scale validation hardware**~~ → **accept late validation of
  client rendering** (2026-07-30). Note precisely what this defers: Q15
  is about the *client* drawing 40,000 soldiers, which is GPU-bound and
  which the dev laptop cannot do. It is not about the simulation — D-009
  keeps squad state in packed arrays outside the scene tree, so a
  headless server at ~1,000 squads is pure CPU and runs locally, and
  `bot_client.gd` already runs N virtual clients in one process (D-018's
  memory analysis) deriving soldier transforms without rendering them.

  So M4 proceeds as **simulation and network scale-out, measured
  headless**, and the consequences for the two decisions that wait on it
  are unequal: **D-021's GDExtension trigger is fully served** (its named
  candidate, the flow-field solver, is server-side), while **D-012's LOD
  tiers are only partly served** — simulation LOD is measurable, but
  rendering LOD is not, and M5 must not design that half blind.

  **Deferral trigger:** client-render scale must be measured before M5
  commits to any *rendering* LOD tier, and in any case before M7 (Steam).
  Shipping without ever having drawn the target soldier count is the risk
  this decision knowingly accepts; the trigger is what keeps it accepted
  rather than forgotten.

  **Trigger met 2026-08-02 (M5), and RE-ARMED rather than closed.**
  `just bench-render` now draws the real client path at 100/250/500/1,000
  squads and reports frame time, worst frame, draw calls and the GPU it
  ran on (D-045). So rendering LOD is no longer designed blind — that
  half of the deferral is discharged.

  What is **not** discharged: this was measured on **Intel Iris Xe
  integrated graphics**, and 1,000 squads / 26,644 soldiers renders at
  28 fps there. Whether the target holds on the hardware players will
  actually use is still unmeasured, and an integrated GPU cannot answer
  it — favourably or unfavourably.

  **Sharpened trigger:** before M7, run `just bench-render` on a discrete
  GPU (the numbers are meaningless without the adapter name, which the
  recipe prints for exactly this reason) at the map size and squad count
  the ship configuration uses. The specific unknown is whether the
  remaining cost is CPU-bound — it is 90% CPU on integrated, which
  predicts a discrete GPU changes little and makes *derivation*, not
  fill rate, the thing to watch.

**Blocking M7 / product-level** *(header kept for history — "M7" here
is the old numbering, when Steam was M7; it is M8 now. All six product
questions in this block were closed by the M8 planning session,
2026-08-14, D-087 through D-094)*:
- ~~**Q3 — Who runs the server?**~~ → **D-088** (2026-08-14):
  player-hosted first — the host's machine runs the authoritative sim
  in-process, remote players arrive over Steam relay; official
  dedicated servers are a later rung and the eventual fix for
  host-quit and host-trust. The question's premise aged: hosting
  turned out measured-cheap (~half a core, ~20 KB/s up at 20 players).
- ~~**Q5 — Is 20 players a design target or an engineering
  ceiling?**~~ → **D-089** (2026-08-14): a **design target**, by the
  owner's call. What it obliges: Steam lobby browser + invites (no
  matchmaking service), AI seat-fill, and drop-in/drop-out via D-090's
  repossession. The engineering ceiling stays where D-018 put it.
- ~~**Q10 — Reconnection and desync recovery policy.**~~ → **D-090**
  (2026-08-14): disconnect hands the seat to an AI immediately (D-051
  built the right object); reconnection is repossession by SteamID,
  with no timeout — the AI *is* the grace mechanism; a client-detected
  desync recovers by drop-and-rejoin through the same path, because
  D-025's reveal semantics make a fresh join cheap. Supersedes
  D-033's wipe-on-disconnect for humans.
- ~~**Q11 — Anti-cheat posture.**~~ → **D-091** (2026-08-14): the
  architecture is the anti-cheat — server authority plus curve gating;
  no kernel AC, VAC defaults only. The host under D-088 is trusted,
  stated plainly; ranked play is explicitly gated on official
  dedicated servers.
- ~~Q12 — Art direction for mesh tiers 2 and 3 (D-011), and who
  produces it.~~ → **D-081** (2026-08-09; corrected 2026-08-11 — first
  recorded here as `D-064`, then briefly as `D-075`; both IDs collided
  with unrelated real entries; see D-081's own entry and its editorial
  note): stylised low-poly with strong
  silhouettes, ~300 tris/soldier; produced by committed Python scripts
  driving Blender headless as a library, not by hand in the GUI. Tier 2
  is absorbed rather than skipped — parametric composition is how the
  generators are written.
- ~~**Q13 — Persistence/saves** for long matches on a seamless map.~~
  → **D-092** (2026-08-14): out of M8, by the owner's call. The need
  decomposes into reconnection (D-090) and replays (D-016), both of
  which exist or are specified; true suspend/resume of a multiplayer
  session waits on a measured reason. Two revisit triggers named in
  the entry.
- ~~**Q14 — Terminology: what does "seamless" mean here?**~~ →
  **D-087** (2026-08-14): one contiguous wrapped map with no loading
  screens — true by construction since D-008, no streaming work exists
  anywhere in the plan because none is needed. Closed by writing the
  definition down.
- **Q15 — Age/tech progression, and what a 1–2 hour match is made of.**
  **DISCHARGED 2026-08-04 by D-068 through D-074.** The planning
  milestone the owner reserved on 2026-08-02 ran; the text below is kept
  as the brief it set, and every bullet in it is answered:

  | Q15 asked | Answered by |
  |---|---|
  | Ages: how many, what gates advancing, what each unlocks | **D-069** — five rungs, an `EpochDef` gate in `/epochs/*.tres`, one new verb per rung |
  | Whether progression is per-civ, declaratively | **D-069/D-070** — the ladder is shared; civs differ in contents only. **D-073** maps every civ claim to a knob and cut three that had none |
  | The phase-by-phase account of a 1–2 hour match | **D-068** — six phases, and every later number traces to it |
  | Economy scale, and whether the map is exhausted | **partially — see the correction below** |
  | Is an army a ratchet or a running cost? | **D-068** — a running cost. Per-soldier food upkeep; unpaid upkeep decays morale via D-019 rather than killing soldiers |
  | Interaction with D-018's scale and D-020's tick budget | **D-074 criterion 9**, plus a prerequisite: M6's unattributed 40.8 → ~77 µs/squad rise must be explained before M9 adds load on top of it |

  **One correction to the brief below, and one thing left genuinely
  open.** The economy figures quoted are stale: it says `NODE_STOCK` is
  900 with a node every 11 cells; `economy.gd:41` and `:50` now read
  `NODE_EVERY := 60` and `NODE_STOCK := 2400`. **The question the bullet
  was really asking — whether an hour-long match exhausts the map — was
  not answered and needs recomputing against the real constants once
  D-068's phase table has a consumption rate attached to it.** It is the
  one part of this brief that D-068–D-074 did not close.

  *Original brief, 2026-08-02:*

  The target is 1–2 hours (D-056). Matches currently decide in about
  three minutes, and D-056's tuning addresses only the worst of that.
  **The structural cause is that there is no progression to climb**: four
  buildings and four units per civ, no ages, no tech, no upgrades, so
  after roughly three minutes there is nothing to do but fight. No amount
  of health or squad-cap tuning reaches an hour from there.

  What the planning session has to settle, at minimum:
  - Ages/epochs: how many, what gates advancing, what each unlocks.
  - Whether progression is per-civ (D-047 says civs are data and no
    script may name one, so a tech tree must be declarative too).
  - What a 1–2 hour match is made of, phase by phase — opening,
    expansion, mid-war, late — because D-056's numbers should be DERIVED
    from that account rather than tuned until the symptom stops.
  - Economy scale: `NODE_STOCK` is 900 per node with a node every 11
    cells; an hour-long match at 40 squads/player may exhaust the map,
    which is either a designed pressure or a bug depending on the answer.
  - **Is an army a ratchet or a running cost?** *(raised by the owner,
    2026-08-02.)* There is **no upkeep** today — a unit costs a one-time
    price and nothing drains per tick — so army size only ever grows and
    losing one costs nothing but the rebuild. Upkeep would convert it to
    a steady state you keep paying for, which is what makes losing an
    army hurt, makes raiding workers a real strategy, and stops the
    endgame being two maxed doomstacks with nowhere to go. It is also the
    difference between a late game with economic texture and one where
    everybody accumulates until the map is bare.

    Deliberately NOT bolted on now: it touches economy, AI, UI and every
    balance number, and the phase-by-phase account of a 1–2 hour match is
    exactly what should decide it. Note it interacts with the squad cap —
    upkeep is a *soft* cap, and having both may be one mechanism too many.
  - Interaction with D-018's scale target and D-020's tick budget: more
    ages means more squads alive later, and the 1,000-squad figure is
    already the ceiling the architecture was sized for.
