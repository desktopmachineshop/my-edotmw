# Game Design Decisions

Living decision log for my-edotmw. `CLAUDE.md` is the condensed ground-rules
summary of this file — if the two ever disagree, this file wins and
`CLAUDE.md` needs updating.

Format per entry: **ID · Date · Status · Decision · Rationale · Rejected
alternatives · Consequences · Revisit trigger**.

Status is one of:
- **Accepted** — settled, build against it
- **Provisional** — best current call, but explicitly cheap to overturn;
  has a revisit trigger
- **Superseded by D-0xx** — kept for history, no longer in force

New entries go at the top of section 1. Never edit history in place —
supersede instead, so the rationale trail survives.

---

## 1. Decisions

### D-018 · 2026-07-28 · Accepted
**Decision:** Full-scale target is 20 players × 2,000 individual soldiers
each (40,000 soldiers total), organized into ~50 squads/player (~1,000
squads total at full scale), implying an average squad size of ~40
soldiers.

**Rationale:** Dave's explicit call, replacing the ambiguous "500 units"
figure in the original brief (see former Q1, now resolved). This reading
(soldiers, not Total-War-style multi-soldier "units") keeps the
squad-atomic architecture's math tractable: 1,000 squads at a 10 Hz tick
is 10,000 squad-updates/second, roughly 4x the number modeled in the
original MVP planning pass but still within GDScript's budget assuming
D-006 holds.

**Rejected alternatives:** 500 soldiers/player (original brief, too
small to be interesting per Dave); 500 Total-War-style units/player
(~20,000 soldiers/player, ~400,000 total — an order of magnitude beyond
what's viable for this project's team size and hardware).

**Consequences:** Every downstream budget in `CLAUDE.md` and this file
(bandwidth, tick cost, MultiMesh instance counts, load-test bot shape)
should be sized against 1,000 squads / 40,000 soldiers at full scale, not
the original 250/10,000. MVP (M3) squad count per player stays modest
(~12-15) — full-scale squad density is a v1.0 target, not an MVP one.

**Revisit trigger:** If M1/M4 profiling shows squad-update cost exceeding
budget at this count, revisit either the squad-count target or the tick
rate before touching the architecture.

---

### D-019 · 2026-07-28 · Accepted
**Decision:** The "Rome Total War" half of the hybrid means **formations
and morale/routing only** — units fight and break in formation, morale
determines when a squad routs. No separate turn-based or persistent
campaign layer wrapping the RTS battles.

**Rationale:** Dave's explicit call (former Q2, now resolved). This
confirms squads are the right atomic simulation unit for a reason beyond
performance: formations and morale are inherently squad-level concepts,
not per-soldier ones.

**Rejected alternatives:** Campaign layer wrapping battles (Total War's
actual structure) — rejected as out of scope entirely, not just deferred;
"Total War" as aesthetic/scale reference only, no formal
formation/morale system — rejected, Dave wants the mechanics, not just
the vibe.

**Consequences:** Combat model (former Q7, still open) must define
formation shapes per squad, a morale stat and rout trigger/threshold, and
how routing interacts with flow-field movement (a routed squad presumably
gets a new, player-uncontrolled flow-field target). This also firms up
`unit_def.gd`'s schema: it needs formation-shape and morale-stat fields
from the start, not bolted on later.

**Revisit trigger:** None — this is a firm scope boundary, not a
provisional call.

---

### D-006 · 2026-07-28 · Provisional — highest priority to confirm, blocks M1
**Decision:** Individual soldier positions are a pure client-side
function of (squad curve, formation shape, slot index, terrain sample)
and are never networked. Only squads are networked entities. Combat
outcomes (damage, death, routing) replicate as sparse reliable events,
not continuous per-soldier state.

**Rationale:** This is the keystone that makes D-018's 1,000-squad
full-scale target tractable at all — it's what keeps the networking and
simulation cost at "squads" (~1,000) rather than "soldiers" (~40,000), a
40x difference. It also composes cleanly with D-019: formation shape is
exactly the function that would derive soldier slot positions.

**Rejected alternatives:** Per-soldier authoritative networked
positions — rejected provisionally, as it multiplies the netcode budget
by ~40x and wasn't shown to be necessary for anything in scope.

**Consequences:** Combat resolution cannot depend on true per-soldier
positions being known to the server at high precision — it has to work
off squad-level state plus a formation model. This needs explicit
confirmation before M1's flow-field/curve-sync proof is built, because
M1's exit criteria assume it.

**Revisit trigger:** If the combat model (informed by D-019) turns out to
require server-authoritative per-soldier positions — e.g., for precise
morale/rout triggers based on individual soldier deaths in specific
formation slots — revisit before M2.

---

### D-001 · 2026-07-28 · Accepted
**Decision:** Godot 4.7.1 (stable), pinned via `.godot-version`.

**Rationale:** Latest stable release as of 2026-07-28 (released
2026-07-14). Chosen for plain-text asset formats (`.tscn`/`.tres`) that
make the project directly editable by Claude Code.

**Rejected alternatives:** Godot 4.6.3 (prior stable branch) — no
compelling reason to pin behind latest stable for a greenfield project.

**Consequences:** Container image and portable native binary must both
resolve to this exact version. Bump this entry (don't silently update)
if a newer stable release becomes worth adopting.

**Revisit trigger:** A newer stable release ships with a fix or feature
this project specifically needs (e.g. `MultiMesh` improvements relevant
to D-009).

---

### D-002 · 2026-07-28 · Accepted
**Decision:** Client-server, authoritative server. Not lockstep.

**Rationale:** Lockstep desync debugging cost, 20-player join/rejoin
handling, and cheat resistance all favor authoritative server + client
interpolation over lockstep, despite lockstep being the historical RTS
default.

**Rejected alternatives:** Lockstep simulation (classic RTS netcode).

**Consequences:** Server needs enough CPU to simulate the full match
(see former Q3, still open — server hosting model). Clients send input,
receive curve-based state (D-003), interpolate locally.

**Revisit trigger:** None currently.

---

### D-003 · 2026-07-28 · Accepted
**Decision:** Object state (position, build progress, etc.) syncs as
keyframed curves, not per-tick snapshots. Curves are mandatorily clipped
to each client's visibility horizon and a bounded time window before
transmission.

**Rationale:** Near-zero bandwidth for idle objects. The clipping
requirement prevents two specific failure modes: intent leakage (a raw
curve reveals an enemy squad's future path before it happens) and
unbounded lookahead cost.

**Rejected alternatives:** Per-tick snapshot replication (simpler, but
scales linearly with object count and tick rate — incompatible with the
zero-cost-when-idle goal).

**Consequences:** Curve invalidation (re-pathing, especially many squads
at once, e.g. a large engagement) is a bandwidth spike risk and needs a
budgeted/prioritized update scheduler, not naive immediate replication.
This should be measured explicitly in M1's exit criteria.

**Revisit trigger:** If M1 profiling shows invalidation-storm bandwidth
exceeding budget, revisit the scheduler design (not the curve-based
approach itself).

---

### D-004 · 2026-07-28 · Accepted, semantics Provisional
**Decision:** Fog of war is implemented as curve gating on top of D-003
— a client simply doesn't receive curves for objects outside its
vision — not a separate data-hiding system.

**Rationale:** Avoids building and maintaining two parallel
visibility-gating mechanisms.

**Rejected alternatives:** Separate fog-of-war system layered on top of
full replication with client-side hiding (rejected — leaks true state to
a modified client, defeats the purpose of fog of war).

**Consequences:** Reveal/conceal semantics are not yet decided: does a
unit entering vision pop in at its true position, receive a short
synthetic catch-up curve, or does the client keep a stale "ghost" at
last-known position after it leaves vision? All three are legitimate;
needs an explicit pick before M2 (fog of war milestone).

**Revisit trigger:** Pick reveal/conceal semantics before M2 begins;
this entry stays Provisional until then.

---

### D-005 · 2026-07-28 · Accepted
**Decision:** Squads, not individual soldiers, are the atomic unit for
movement, pathfinding, production, and networking.

**Rationale:** Matches D-019's formation/morale mechanics (which are
inherently squad-level) and is what makes D-018's full-scale target
tractable via D-006.

**Rejected alternatives:** Per-soldier pathfinding/production (rejected —
doesn't scale to 40,000 soldiers and fights D-019's formation model).

**Consequences:** Don't reintroduce per-unit pathfinding or per-unit
production queues anywhere in the codebase.

**Revisit trigger:** None currently.

---

### D-007 · 2026-07-28 · Accepted
**Decision:** Flow-field pathfinding, computed per squad destination, not
per-soldier A*.

**Rationale:** Well-trodden technique (Supreme Commander 2, Planetary
Annihilation) that composes with squad-atomic movement (D-005) and scales
far better than per-agent A* at this unit count.

**Rejected alternatives:** Per-soldier A* (rejected — doesn't scale;
also redundant given D-006's derived soldier positions).

**Consequences:** None beyond standard flow-field implementation cost.

**Revisit trigger:** None currently.

---

### D-008 · 2026-07-28 · Accepted
**Decision:** Wrapped hex grid on a torus, using axial coordinates on a
parallelogram domain with row-parity constraints on map dimensions.
Wrap-awareness is enforced via a `HexCoord`/`TorusSpace` type rather than
left as a convention every call site has to remember.

**Rationale:** A true geodesic sphere is unnecessary complexity for the
stated design; a naive offset-coordinate rectangular grid does not wrap
cleanly without careful row-parity handling. Making wrap a type-level
concern prevents the "twentieth call site forgets ghost-copy distance"
class of bug.

**Rejected alternatives:** True geodesic sphere (rejected — much more
complex, not needed); offset-coordinate grid with wrap handled by
convention (rejected — proven bug-prone pattern, error-prone at scale).

**Consequences:** Every distance/neighbor/noise calculation
(pathfinding, vision, minimap, camera, drag-select, formation math, AI
targeting, terrain noise) must go through the wrap-aware type. Seam-
crossing cases must be in GUT tests from M1 onward.

**Revisit trigger:** None currently.

---

### D-009 · 2026-07-28 · Accepted
**Decision:** GDScript for gameplay logic at squad granularity. Rendering
via `MultiMesh`, with simulation state kept in packed arrays outside the
Godot scene tree — not one `Node` per soldier or per squad. C# only where
profiling shows a specific need.

**Rationale:** Godot's `Node`/scene-tree model is not designed for tens
of thousands of dynamic actors; the idiomatic "one scene instance per
unit" approach fails well before D-018's target. `MultiMesh` + packed
arrays is the path that actually scales, but it cuts against Godot's
default idiom and needs to be an explicit decision so early
implementation doesn't default to per-soldier scene instances.

**Rejected alternatives:** One `Node`/scene instance per soldier
(rejected — doesn't scale); one `Node` per squad (reconsider only if
squad count, not soldier count, turns out to be the bottleneck).

**Consequences:** Unit rendering code should be written against
`MultiMesh` from `primitive_unit.gd` onward, not retrofitted later.

**Revisit trigger:** If profiling shows packed-array simulation state is
itself the bottleneck (unlikely before M4).

---

### D-010 · 2026-07-28 · Accepted
**Decision:** Unit stats live in `/units/*.tres` against the `UnitDef`
schema (`unit_def.gd`). Schema changes are versioned and recorded here,
not just in the code.

**Rationale:** Data-driven units are what makes the project directly
editable via Claude Code rather than requiring the Godot editor GUI, per
`CLAUDE.md`'s core premise. `UnitDef` now needs formation-shape and
morale-stat fields per D-019 from the start.

**Rejected alternatives:** Hardcoded per-unit-type script subclasses
(rejected — defeats the data-driven goal).

**Consequences:** New units are added by adding a `.tres` file, not by
writing new unit classes. Squad size (~40 soldiers per D-018) is a
`UnitDef` field, not a global constant, so it can vary per unit type if
needed later.

**Revisit trigger:** None currently.

---

### D-011 · 2026-07-28 · Accepted
**Decision:** Mesh generation stays at the primitive tier (capsules,
boxes, cylinders composed from `UnitDef` data) through M3. Modular/
parametric (tier 2) and Blender/`bpy` final-fidelity (tier 3) are
unscheduled.

**Rationale:** Zero art dependency lets the architecture and gameplay
loop get validated before any art investment. Matches `CLAUDE.md`'s
existing tiering.

**Rejected alternatives:** Jumping to higher mesh fidelity early
(rejected — art investment before the architecture is proven is the
highest-waste failure mode for a project this size).

**Consequences:** `primitive_unit.gd` is the only mesh-generation code
needed through M3.

**Revisit trigger:** Revisit once M3 is complete and playtesting
suggests visual fidelity is limiting engagement, or once tiers 2/3 are
explicitly prioritized.

---

### D-012 · 2026-07-28 · Provisional
**Decision:** LOD is deferred to M5, implemented only for the tiers M4's
profiling shows are actually necessary. When built: **simulation** LOD is
keyed to server-computed game-state salience (in combat / near enemy /
near contested objective) and is identical for all observers — never
keyed to any individual client's camera. **Render** LOD may be keyed to
camera freely.

**Rationale:** Building LOD before M4 means building a complex,
fairness-sensitive system against guessed numbers instead of measured
ones. Keying simulation fidelity to an individual client's camera would
make combat outcomes depend on spectator behavior — a competitive-
fairness bug, not just a technical one. `CLAUDE.md`'s "LOD is planned,
not a fallback" is about keeping per-squad update cost measurable and
swappable from the start, not a mandate to build LOD first.

**Rejected alternatives:** Camera-keyed simulation LOD (rejected —
fairness bug); building full LOD before M4 (rejected — no measured data
to size it against).

**Consequences:** Per-squad update cost should be kept measurable and
swappable from M1 onward even though LOD itself isn't built until M5.

**Revisit trigger:** M4's profiling data determines which LOD tiers (if
any) are actually needed.

---

### D-013 · 2026-07-28 · Accepted
**Decision:** Global time dilation (PA-style slowdown) is an emergency
safety valve only, with a written trigger threshold once defined — never
the primary mechanism for handling scale.

**Rationale:** Matches `CLAUDE.md`'s existing non-negotiable. LOD (D-012)
and curve-based sync (D-003) are the primary scale mechanisms; time
dilation is a last-resort fallback for when those aren't enough in a
specific match.

**Rejected alternatives:** Time dilation as a routine scale-management
tool (rejected — degrades the play experience broadly instead of
targeting the actual cost).

**Consequences:** None yet — unscheduled until M5 or later.

**Revisit trigger:** Define the exact trigger threshold when this is
first implemented, not before.

---

### D-014 · 2026-07-28 · Accepted
**Decision:** Headless dev tooling (server, bots, GUT tests, terrain
preview) is containerized. The GUI Godot editor and the GUI game client
run natively via a portable, gitignored install — flagged as `CLAUDE.md`
exceptions, not eliminated. `EDOTMW_RUNTIME=native|docker` lets the
`justfile` recipes run against either backend, since WSL2 is currently
broken on the dev machine and Docker Desktop depends on it.

**Rationale:** Dave wants easy, complete teardown — no stray processes,
containers, or installed toolchains left on the machine. GPU-accelerated
GUI Godot in a container on Windows (via WSLg/X-forwarding) is slow and
fragile, and pointless given the dev machine's integrated Iris Xe GPU
anyway. The native-fallback runtime abstraction means M0 isn't blocked on
fixing WSL2.

**Rejected alternatives:** Containerizing the GUI client (rejected —
fragile, no GPU benefit on this hardware); requiring WSL2 fixed before
any dev work starts (rejected — unnecessarily blocks M0).

**Consequences:** `justfile` recipes are the stable interface; only the
backend invocation differs by `EDOTMW_RUNTIME`. Teardown for the native
path is `rm -rf tools/` (portable binaries) plus clearing
`%APPDATA%\Godot` if needed; for the docker path it's `just nuke`
(remove containers, image, `tools/`, `artifacts/`).

**Revisit trigger:** Once WSL2 is repaired and the docker path is
verified working, `EDOTMW_RUNTIME=docker` can become the default; native
stays as the fallback either way for the GUI pieces.

**Update 2026-07-28:** WSL2 repaired (firmware virtualization was
disabled — fixed in BIOS) and Docker Desktop installed. Docker path
verified end-to-end: `docker compose build server` succeeds (fetches
pinned Godot 4.7.1 inside the image per D-001), and
`docker compose run --rm bots -- --clients=3` runs `bot_client.gd`
through the full bind-mount + entrypoint chain correctly.
`docker compose down --remove-orphans` tears down cleanly. Trigger met
— `EDOTMW_RUNTIME` default switched to `docker` in the justfile; native
remains the fallback for the GUI editor/client (unaffected by this
change).

---

### D-015 · 2026-07-28 · Accepted (pending Dave's review of concrete M3 file output)
**Decision:** Milestone ladder M0 (skeleton) → M1 (movement + netcode
proof) → M2 (combat + fog) → M3 (launchable MVP) → M4 (scale-out
profiling) → M5 (LOD) → M6 (second civ) → M7 (Steam). M3's cut lines: 4
players, ~120-150 soldiers/player at ~12-15 squads/player (squad count
per player stays a small fraction of D-018's full-scale ~50/player — see
D-018 consequences), 1 civilization, fixed torus map, 3-4 unit types,
primitive meshes only, no simulation LOD, LAN/direct-IP only, no AI
opponent, replays included (near-free given D-003).

**Rationale:** Full derivation and per-milestone exit criteria are in the
2026-07-28 planning session (see project history / commit that adds
this file). Deliberately shrinks nearly every dial except squads/player,
since squad count is the axis the architecture is actually sensitive to.

**Rejected alternatives:** Scaling every dial down proportionally
(rejected — would hollow out the validation of the squad-atomic
architecture, the thing M1-M3 exist to prove).

**Consequences:** M0 deliverables (this commit and the files alongside
it) should make `CLAUDE.md` actually true: real `justfile` recipes,
real directory layout, this decision log, and container/native
scaffolding.

**Revisit trigger:** Re-derive squad/soldier counts if D-018 changes.

**Update 2026-07-28:** M0 exit criteria verified and met: `just
test-unit` runs GUT 9.6.1 headless via `docker compose run --rm test`
(2/2 smoke tests pass, including a `UnitDef` default-value check), and
`just nuke` confirmed to remove all containers/images plus
`tools/`/`artifacts/`/`.godot`/`.godot-container`, leaving the repo as
pure source. One operational note for M1: Godot's headless import step
(`godot --headless --path . --import`) must run before `gut_cmdln.gd`
can resolve GUT's and the project's own global `class_name`s (`UnitDef`,
`PrimitiveUnit`) — baked into the `test-unit` recipe now, keep this in
mind for any other headless recipe (`run-server`, `gen-terrain-preview`)
implemented in M1.

**Post-M0 review 2026-07-28.** A review pass over the M0 deliverables
found and fixed four real defects, all of which would have surfaced as
confusing failures during M1:

1. `bootstrap` only printed instructions, so the stated exit criterion
   ("fresh clone + bootstrap + `just test-unit` works") did not actually
   hold — and could not, since a fresh clone has no `just` to run
   `just bootstrap` with. Resolved by adding `bootstrap.ps1` (fetches
   pinned `just` into `tools/`) and making `just bootstrap` really fetch
   portable Godot for the native runtime.
2. Recipes invoked each other as a bare `just`, which is never on PATH
   (it lives in `tools/`). Broke `default` and every step of
   `test-load`. Now `{{just_executable()}}` — **and it must be quoted**:
   unquoted, bash eats the Windows path's backslashes and the command
   silently becomes `C:Usersdmaso...`. Worth remembering for any future
   recipe that interpolates a path on Windows.
3. `test-load` ran the bots in the foreground and only then slept, so
   `DURATION` measured nothing. Bots now run in the background for the
   requested duration, and teardown is trapped on `EXIT INT TERM` so an
   interrupted load test cannot leave containers running.
4. Nothing exercised the `.tres` files or `primitive_unit.gd` — the
   suite would have stayed green with a completely broken unit roster,
   despite D-010 being the premise the project rests on. `test_unit_defs.gd`
   now loads and schema-checks every `.tres` in `/units/` and asserts a
   squad renders as exactly one `MultiMesh` child (D-009). Verified to
   fail correctly by introducing a deliberately malformed unit.

Also noted, deliberately left as-is: `just nuke` deletes `tools/`
including the running `just` binary. That is correct behavior for
D-014's teardown guarantee; it's now documented rather than surprising.

---

### D-016 · 2026-07-28 · Accepted
**Decision:** Replays are the curve log from D-003 — adopted from M1
onward as the primary desync-forensics tool.

**Rationale:** D-003 makes curve logging nearly free, and replay capture
is valuable for debugging netcode/desync issues from the very first
milestone rather than being bolted on later.

**Rejected alternatives:** Building a separate replay-recording system
(rejected — redundant given D-003).

**Consequences:** None beyond ensuring curve logs are written to
`artifacts/` in a replayable format from M1.

**Revisit trigger:** None currently.

---

### D-017 · 2026-07-28 · Accepted, chunk size Open
**Decision:** Terrain uses a chunked hex mesh (not one mesh per cell) with
biome coloring and elevation vertex offset. Chunk size is determined by
profiling, not chosen upfront.

**Rationale:** One-mesh-per-cell is a known performance problem at
10,000+ cell map sizes (per `CLAUDE.md`); chunking is a hard requirement,
not a style choice. Chunk size has real tradeoffs (rebuild cost on
elevation edits vs. draw-call count) that are better measured than
guessed.

**Rejected alternatives:** One mesh per cell (rejected — doesn't scale);
picking a chunk size upfront without profiling (rejected — premature).

**Consequences:** `gen-terrain-preview` tooling should make chunk-size
experimentation fast.

**Revisit trigger:** Pick a concrete chunk size once M1's terrain work
starts and can be profiled.

---

## 2. Open Questions / Not Yet Decided

Ordered by how much they block. ~~Struck through~~ entries are resolved
and now live as decisions above.

**Resolved this session:**
- ~~Q1 — What does "500 units" mean?~~ → D-018 (2,000 soldiers/player,
  ~50 squads/player, ~40 soldiers/squad)
- ~~Q2 — What is the Rome Total War half of the hybrid?~~ → D-019
  (formations & morale/routing only, no campaign layer)

**Blocking M1:**
- **D-006 confirmation** — the derived-soldier-positions keystone is
  still Provisional. Confirm or reject before M1's flow-field/curve-sync
  proof is built (see D-006 above).
- **Q6 — C# in the shipping build?** Affects export matrix and platform
  support. GDScript is the default per `CLAUDE.md`; need a yes/no on
  whether C# is permitted at all, not just "if profiling shows a need."

**Blocking M2:**
- **Q7 — Combat model:** deterministic per-soldier resolution vs.
  stochastic squad-level rolls. Directly interacts with D-006 and D-012:
  squad-level rolls make LOD and D-006 easy, per-soldier resolution makes
  both hard. Now also needs to define formation-break and morale/rout
  thresholds per D-019.
- **Q9 — Simulation tick rate**, and whether it varies by LOD tier
  (relevant once D-012 is implemented at M5, but the tick rate itself is
  needed by M1).
- **Fog reveal/conceal semantics** — see D-004's open Provisional item.

**Blocking M4/M5:**
- **Q8 — Map size in cells at ship**; fixed or generated per match;
  torus dimension parity constraints from D-008.
- **Q15 — Scale validation hardware.** The dev laptop (Intel Iris Xe
  integrated GPU, 16 GB RAM) cannot validate 40,000-soldier *client*
  rendering. Cloud box, second machine, or accept late validation?

**Blocking M7 / product-level:**
- **Q3 — Who runs the server?** Dedicated (whose money, per-match cost?),
  player-hosted (lower unit ceiling), or Steam relay with a host player.
  Constrains the netcode budget and the business model.
- **Q5 — Is 20 players a design target or an engineering ceiling?** If a
  design target, matchmaking, drop-in/drop-out, and AI takeover for
  disconnects are all in scope and are large.
- **Q10 — Reconnection and desync recovery policy.**
- **Q11 — Anti-cheat posture.** Authoritative server (D-002) helps; the
  leak surfaces are curve horizon clipping (D-003) and client-derived
  soldier positions (D-006).
- **Q12 — Art direction** for mesh tiers 2 and 3 (D-011), and who
  produces it.
- **Q13 — Persistence/saves** for long matches on a seamless map.
- **Q14 — Terminology: what does "seamless" mean here** — no loading
  screens between regions, or one contiguous map? Implies very different
  streaming work.
