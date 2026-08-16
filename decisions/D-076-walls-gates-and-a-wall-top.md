### D-076 · 2026-08-12 · Accepted — walls, gates, and a wall-top tier reached through one door
**Decision:** D-069 named this exact feature and fenced it out of M9:
*"no wall system... A real wall system is a substantial piece of
pathfinding and rendering work and needs its own decision."* This is that
decision. Two structures and two grades of each:

- **`wall` / `gate`** — single-cell segments, chained by placing several
  adjacent (the existing per-cell `ORDER_BUILD` path, unchanged). Pure
  ground blockers: `damage=0`, no wall-top presence. A gate additionally
  supports **manual open/close** and **auto-open when the owner's own
  squads are near**, mode switchable per-building from its selection HUD
  panel. `footprint_radius=0` on all four defs, so adjacent segments do
  not reject each other under `server._footprint_conflict`.
- **`garrison_wall` / `garrison_gate`** — pricier, `walkable_top=true`:
  their cell joins a real second passable layer (tier 1). Still
  `damage=0` — the structure itself never attacks; whatever squad is
  standing on it does, with its own stats plus a height bonus.
- **`wall_tower`** — the only access point. `is_access_tower=true` and a
  **per-INSTANCE** `access_direction` (chosen at placement, stored on
  `BuildingSim`, not on the shared `BuildingDef` — a def is one resource
  per archetype, so a door facing can't live there without every tower
  sharing one facing). Climbing/descending is legal **only** through the
  ground cell on that one side. **Not ownership-gated**: the check is
  pure geometry (which cell a squad occupies, which tower's door that
  is), so an enemy that fights through to the door climbs exactly like
  the owner would. A wall's tier-1 top is therefore a contestable
  objective, not an automatically safe one.

**Geometry: chained single cells, not edges.** `TorusSpace` has no edge
primitive and none was added. A wall is however many `wall`/`garrison_wall`
buildings a player places adjacent to each other — it reuses the entire
existing placement/passability/combat/replication pipeline, which is what
keeps this from being the "substantial" rewrite D-069 was worried about.

**The wall-top tier is a second `FlowField` layer, the class itself
unmodified, but NOT sharing the ground layer's cache or budget.**
`SquadSim._fields_top`/`_pending_fields_top`/`top_field_cells_per_tick` are
wholly separate from `_fields`/`_pending_fields`/`field_cells_per_tick`
(D-040's shared counter). Sharing it would let a wall-top solve silently
halve ground-pathing throughput on any tick both are active — confirmed by
reading `_field_for`'s budget accounting before writing the second copy,
not assumed. A squad's tier (`SquadSim._tier`, 0 or 1) is real per-squad
state; its POSITION within a tier is still a pure function of
`(curve, formation, slot, terrain sample)` exactly as D-006 requires —
climbing/descending is one explicit teleporting hop
(`SquadSim._teleport_curve`), never a curve-interpolated walk, which is
what keeps it legal under D-006 clause 1: there is nowhere for a
partial-climb value to live. `order_move`/`order_attack_move` infer the
target tier from whether the destination cell is itself on the wall-top
network (`BuildingSim.is_walkable_top_cell`) — **no wire change to
movement orders was needed**; a cross-tier order decomposes server-side
into "walk to the nearest reachable tower's door, hop, continue," the same
two-leg shape `server.gd`'s `_pending_builds` already uses for
out-of-reach construction.

**Combat gains exactly one new rule.** A tier-1 squad fights with its OWN
`UnitDef` stats — `Combat._resolve_attack` is untouched — from an
effective range of `base_range + BuildingDef.top_range_bonus`
(`Combat._attacker_range_cells`). Targeting eligibility
(`Combat._can_reach_tier`): a tier-1 defender can be hit by another
tier-1 attacker, or by anything **ranged** (`armour_class == "missile"`,
including every building — a tower's fire already "arcs up" thematically)
— never by a tier-0 melee squad. This is the whole reason climbing is a
real defensive choice and not a coat of paint.

**Destruction evicts, it does not kill.** `SquadSim._evict_stranded_tier1_squads`
runs whenever `resolve_squads_vs_buildings` reports a destruction this
tick, and drops any squad whose tier-1 cell no longer has a living
`walkable_top` structure under it to the nearest passable ground cell,
alive. An invisible instant-kill on top of losing the structure would be
a second, worse punishment nobody asked for.

**Rejected alternatives:**
- *An abstract garrison-capacity slot* (an early draft of this decision):
  a fixed-capacity "station a squad in the wall" order, protected but
  otherwise decorative. Rejected once the user asked to literally see
  units fighting from the wall — replaced by ordinary squad movement
  extended to a second tier, which is simpler and delivers the visual
  directly instead of needing a HUD counter to stand in for it.
- *Any adjacent cell as a climb point*: the first cut of the walkable tier
  let a squad climb from any ground cell next to any `walkable_top`
  segment. Caught before it shipped: it makes a wall's LINE pointless,
  since an attacker could climb up from outside anywhere along it. Access
  is now the tower's one door, full stop.
- *Ownership-gated climbing*: considered and explicitly rejected by the
  user — a wall an enemy could never contest from the top would make
  "storming the wall" impossible even after a real breakthrough.
- *A unified multi-tier BFS graph*: rejected for cost/complexity —
  `FlowField.expand()` is untouched; two independently-solved layers plus
  an explicit hop is far cheaper to reason about and to budget.

**Consequences:** `just test-unit` is green at **527 tests** across 34
scripts — `test_buildings.gd` gained 13 ground-level cases and
`test_wall_top.gd` is a new 12-case file for the tier itself.
`just test-load 4 120` reports a clean verdict at both phases — **63.62
µs/squad at 52 squads** after Phase A landed, **53.45 µs/squad at 52
squads** after Phase B (the difference is ordinary run-to-run variance per
the standing caveat, not a regression: no bot in that load test builds a
wall, so neither run exercises the new combat/vision branches under load —
they are only proven correct by `test_wall_top.gd`, not yet by a live
multi-client match). Worst tick stayed inside D-020's 100 ms budget in
both runs (22.8 ms, then 28.6 ms).

One dead end recorded rather than silently fixed: the first version of
the range-bonus tests ran 150 ticks and let `Combat.assign_idle_engagements`
chase-and-close the gap it was trying to hold open, which also produced
enough flow-field churn to OOM-kill the test container at its existing 1 GB
limit. Fixed by checking on tick 1 — provably before any chase order can
have moved anything — rather than by raising the container's memory limit,
which would have hidden a real test design fault instead of removing it.

**Revisit trigger:** the gate-toggle/flow-field-flush interaction is
flagged, not measured — `SquadSim.set_passable`'s full-cache flush runs on
every gate state change, and auto-mode is bounded to a check every 3 ticks
(`server.AUTO_GATE_CHECK_TICKS`) as a precaution, not because a spike was
observed. If a live match with several auto-mode gates shows the flow-field
spike M4 already found once, that is this entry's own revisit, the same
way D-040 was D-038's. Separately: no AI behavior for building or
using walls/gates exists yet — `just ai-ladder` cannot exercise any of this
feature until an AI player is taught to want one, which is future work.

**Amendment, 2026-08-12 — a real playtest immediately found three more
things.** The first live session (native client, human player) surfaced
one genuine defect and two placement-UX gaps, all fixed the same day:

1. **`_finish_build` consumed ANY builder unconditionally, not just
   founders.** It is shared by every building type, and the D-031
   consume-on-completion call had no check on who was building what — so
   a gatherer sent to raise a barracks, a tower, or a wall segment has
   apparently been vanishing the moment it finished for as long as this
   function has existed. Nothing failed loudly (the building still gets
   built), which is exactly this project's recurring declared-and-unread
   shape, just on the OTHER side of the call: not an unread field, an
   over-read one. Walls and gates, built in the numbers a real session
   produces, is what finally made it something a player noticed. Fixed by
   gating consumption on `UnitDef.archetype == &"founders"`.
2. **Facing generalised from the access tower's door to every building.**
   `BuildingSim._facing` (renamed from `_access_direction`) is now set on
   every instance, not just towers; `access_direction_of` keeps its
   original tower-only "does this door exist" contract unchanged, and a
   new `facing_of` answers the general rendering question. The rotate key
   works while ANY building is armed for placement, not only a
   `wall_tower`.
3. **Placement gained snapping and a drag-to-build-a-line tool**, both
   scoped to `footprint_radius == 0` defs (the existing wall-family
   signal, reused rather than adding a new one): the ghost snaps to the
   nearest cell adjacent to an existing wall-family building and
   auto-orients to face it; dragging computes the hex line between press
   and release (`_hex_line`, standard cube-coordinate rounding) and
   round-robins it across every eligible selected squad. That needed
   `_pending_builds` to become a QUEUE per squad rather than one site —
   `C2S_ORDER_BUILD` still replaces it (the original single-click
   behaviour), a new `C2S_ORDER_BUILD_QUEUE` appends. One squad alone
   still builds a whole line, just sequentially, `_advance_pending_builds`
   starting it toward each queued site as the previous one finishes.

None of the placement-UX pieces are reachable from a GUT test — they live
in `client.gd`, which needs a GPU the same way rendering does (D-014).
Verified by wire round-trip (`facing` on both `ORDER_BUILD` and
`BUILDING_INFO`, the new queue opcode) and by `BuildingSim` behaviour
(facing stored/wrapped for any building) — 532 tests green, `test-load`
still clean at 57.88 µs/squad — but the rotation math, the snap radius,
and the line tool itself are only proven by looking at them, the same
category `just test-client`'s casualty gate exists for elsewhere. Play
it before trusting the geometry.

**Amendment, 2026-08-13 — authored models for all five defs (D-064's
pipeline), plus two things the art pass exposed.** All five had been
rendering as primitives (`mesh_size`-overridden boxes/cylinder) since
launch; `art/buildings/__init__.py` gained a `shape` field (`block` |
`wall` | `tower_access`) that branches `build()` entirely rather than
stretching the existing gable/flat/spire roof cases, since a long low
segment and a squat access tower are different silhouettes from every
`block`-shape building that came before. `wall`/`gate` are a row of
tapered timber stakes (the cheap tier — no walkway, pure blocker);
`garrison_wall` is a crenellated stone rampart; `garrison_gate` is the
same walkway/parapet silhouette built from vertical timber slats instead
— **material marks the gate, not a gap in the wall**, since the user's
own spec put both garrison pieces in the "stone, crenellated" family and
only the gate in wood; `wall_tower` is a crenellated stone tower with a
door on local +X, the same axis `client.gd` rotates by `facing` that
`wall`/`gate` segments already used for their length — so the modelled
door always ends up pointing at the one ground cell D-076's climb check
actually permits, with no per-instance mesh logic. All five comfortably
inside the 400-tri building budget (108–192 tris; the existing four run
72–144).

1. **The gate open/closed colour cue only worked for `StandardMaterial3D`
   — the primitive path.** An authored model gets a `ShaderMaterial`
   (`UnitMesh.static_material_for`), which has no `albedo_color` to lerp,
   so `gate`/`garrison_gate` getting real models would have silently gone
   back to always reading "closed" the moment they shipped — caught
   before it shipped rather than after, this time. Fixed with a
   `gate_open` uniform on `building_static.gdshader` (lightens ALBEDO the
   same amount the primitive path already did) and a branch in
   `client.gd`'s per-frame gate-colour block that sets whichever the
   instance actually has.
2. **`model_preview.gd`'s camera was tuned for 4 buildings and silently
   clipped the ends of a row of 9** rather than failing — the same
   "numbers all pass while the picture is wrong" shape this project keeps
   finding (M1's empty first frame, M6's missing terrain, D-067's
   inside-out winding). Widened camera distance/FOV and a new
   `BUILDING_SPACING` constant so the whole roster fits one frame; the
   fix is the tool, not the models — nothing about the buildings
   themselves required it.

Also found and fixed, not a modelling issue: `just bootstrap-art` assumed
a POSIX venv layout (`bin/python`, `bin/pip`) and a pip that can
overwrite its own running executable — both true on Linux, neither true
on Windows, where `python -m venv` lays out `Scripts/` and pip refuses to
self-upgrade via its own shim. `blender_python`/`blender_pip` now branch
on `os_family()`, and the self-upgrade goes through `python -m pip`
instead of `pip.exe` directly — this project's tooling had simply never
been run through this recipe on native Windows before. Separately: the
docker-backed `_import` and native-backed `gen-model-preview` write to
two different cache directories (`.godot-container/` vs `.godot/`) —
`gen-model-preview`'s own `_import` dependency inherits `EDOTMW_RUNTIME`'s
docker default, so on a machine that has only ever run docker-backed
recipes, the native render step was reading an import cache that had
never heard of these files. Not a bug in either recipe alone, just an
untested combination; resolved here by running with
`EDOTMW_RUNTIME=native`, not by changing the recipes' default.

`just test-unit` green at 545 tests across 35 scripts (`test_art_assets.gd`'s
manifest-hash check among them); `just gen-model-preview` inspected
visually — every new building distinguishable by silhouette and material,
`wall_tower`'s crenellations and `garrison_gate`'s slats both read clearly,
`garrison_wall` partly buried by an unlucky hill in the small preview
terrain but its own merlons visible through the gap. No simulation code
changed, so `test-load` was not re-run.

---
