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

### D-023 · 2026-07-29 · Accepted
**Decision:** The authoritative simulation is driven by an **explicit
fixed-timestep accumulator owned by the sim**, not by Godot's
`_physics_process`. `physics/common/physics_ticks_per_second` in
`project.godot` is left at 10 only so the engine's own stepping doesn't
run wildly out of proportion to the sim; nothing reads it as the tick
rate. D-020 remains the single source of truth for 10 Hz.

**Rationale:** Three reasons, in order of weight. (1) D-009 keeps
simulation state in packed arrays outside the scene tree, so binding the
sim to a scene-tree callback is a coupling the design explicitly does not
need. (2) It makes the sim tickable without a `SceneTree` at all — unit
tests and replay playback drive `tick()` directly in a loop, which is
what lets the M1 suite test the simulation rather than only its parts.
(3) It keeps tick rate a property of the simulation (D-020) rather than a
project setting, so changing it can't happen by editing an engine config
field and silently invalidating D-018's budget math.

**Rejected alternatives:** `_physics_process` as the driver (rejected —
couples sim to the scene tree and to an engine setting, and makes
headless replay/test stepping awkward); `_process` with variable delta
(rejected outright — a variable-rate authoritative sim is not
reproducible, which breaks replays under D-016).

**Consequences:** The server node calls into the sim from `_process` with
an accumulator, consuming whole ticks and carrying the remainder. Tests
call `tick()` directly. `project.godot`'s physics tick setting is now
decorative with respect to the sim — noted in that file so nobody
"fixes" it into load-bearing status.

**Revisit trigger:** None currently.

---

### D-022 · 2026-07-29 · Accepted
**Decision:** M1's exit criteria, written down. D-015 named the milestone
ladder but deferred per-milestone exit criteria to "the 2026-07-28
planning session," which is not in the repo — so "M1 complete" was not a
checkable claim. These are derived from the already-accepted decisions
rather than newly invented, and each criterion names the decision it
discharges.

M1 ("movement + netcode proof") is complete when all of the following
hold and `just test-unit` is green:

1. **Torus is a type, not a convention** (D-008). A wrap-aware hex
   coordinate type exists; neighbor, distance, and interpolation all go
   through it. GUT tests cover seam-crossing cases explicitly — D-008
   requires this from M1 onward.
2. **Flow-field pathfinding** (D-007) computes a field per squad
   destination over the torus, CPU-side only, and a squad on the far side
   of a seam takes the short way around.
3. **Curve-based sync** (D-003) with all three properties demonstrated by
   test, not by inspection: an idle object costs zero bandwidth; curves
   are clipped to a visibility horizon so a client cannot read an enemy's
   future path (intent leakage); re-pathing goes through a budgeted
   scheduler rather than naive immediate replication.
4. **Derived soldier positions** (D-006) — a pure formation function
   drives `PrimitiveUnit`'s MultiMesh, with tests proving purity (same
   inputs → same outputs, no carried state) and deterministic casualty
   restamp.
5. **10 Hz authoritative sim** (D-020, D-009) with squad state in packed
   arrays outside the scene tree, and per-squad update cost measurable —
   D-012 requires the cost be measurable and swappable from M1 even
   though LOD isn't built until M5.
6. **Replay capture** (D-016): the curve log lands in `artifacts/` in a
   replayable format.
7. **Every M1-gated recipe is real**: `run-server`, `run-client`,
   `test-load`, `gen-terrain-preview` no longer exit with "NOT
   IMPLEMENTED UNTIL M1", and `just test-load N DURATION` runs clean.

**Explicitly NOT in M1** (so scope creep is visible if it happens):
combat resolution of any kind (Q7, M2), fog of war (D-004, M2), economy
or production, terrain generation beyond what `gen-terrain-preview`
needs to exercise chunking (D-017), and any LOD (D-012, M5).

**Rationale:** The project's workflow depends on decisions being written
down (CLAUDE.md). An unwritten definition of done for the milestone that
proves the whole architecture is the highest-leverage instance of that
gap. Writing the criteria as discharges of existing decisions also
surfaces whether the decisions actually cover M1 — they do, with no gaps
found while deriving this.

**Rejected alternatives:** Treating M1 as done when "movement works
visually" (rejected — that would pass without the three D-003 properties,
which are the entire point of the netcode proof). Reconstructing the
original planning session's criteria (rejected — not recoverable from the
repo; deriving from accepted decisions is both possible and more
authoritative).

**Consequences:** `CLAUDE.md`'s pointer to "M1's exit criteria in
`game_design_decisions.md` section 2" was wrong — section 2 is Open
Questions. Updated to point here.

**Revisit trigger:** If M2/M3 turn out to need something M1 was assumed
to have proven, add it here rather than quietly widening the milestone.

**M1 complete 2026-07-29.** All seven criteria met; `just test-unit` is
green at 127 tests / 10 scripts, and `just test-load 4 12` runs clean end
to end. Criterion by criterion:

1. `torus_space.gd` — wrap enforced by every method normalising its own
   inputs, so a call site that forgets to wrap cannot get a different
   answer than one that remembers. Seam cases are tested exhaustively
   (every cell pair for distance symmetry and the wrapped bound).
2. `flow_field.gd` — BFS from the destination through
   `TorusSpace.neighbor_index`, one field per destination shared by all
   squads heading there. Verified as exactly the analytic wrapped hex
   distance at every cell, which is the check a non-wrapping expansion
   fails.
3. `state_curve.gd` + `curve_replicator.gd` — all three D-003 properties
   proven by test: 500 idle objects cost literally zero bytes; a client
   decoding the raw wire bytes cannot recover an enemy position 10s
   ahead; a 1,000-squad simultaneous re-path stays inside the byte
   budget and drains without starvation.
4. `formation.gd` — all-static, no instance state. Purity is tested by
   evaluation order, by time-travel (sample late, then early, then late
   again), and by two independent evaluators standing in for client and
   server. Cosmetic offsets live in a separate file (`cosmetic_offset.gd`)
   so clause 2's one-way boundary is structural rather than a comment.
5. `squad_sim.gd` — packed arrays, no Nodes, explicit 10 Hz tick
   (D-023). **Measured 2.14 µs per squad-update** at 48 squads against
   D-020's ~50 µs budget — about 4% of budget, which is direct evidence
   for D-021's judgement that GDScript would fit.
6. `replay_log.gd` — the curve log, byte-identical to the wire format.
   `just replay-info` reads a real load-test replay back and
   reconstructs all 48 squads.
7. All recipes real; `run-client`, `gen-terrain-preview` and
   `replay-info` added.

**Defects found and fixed while building M1**, recorded because each was
silent rather than loud:

- `StateCurve.clipped()` dropped the keyframe sitting exactly on the
  window start — the common case, since the sim emits keyframes on the
  same tick boundary the replicator clips at.
- `just test-load` reported "clean" for a run in which every bot exited
  non-zero. Grepping for the absence of bad news cannot distinguish
  "nothing went wrong" from "nothing happened"; it now also checks exit
  status and an explicit verdict.
- `docker compose` `depends_on: server` under `run --rm` left a running
  server container behind after every bot run — a stray-container leak
  directly against D-014.
- `NetProtocol.decode_welcome` appended to `out["squads"]`, and
  `PackedInt32Array` is a value type in GDScript, so it appended to a
  copy. Clients silently believed they owned no squads.
- Terrain noise was sampled at ~1 feature per cell, producing per-cell
  static that still passed every aggregate check (plausible water
  fraction, plausible biome spread) while having no landmasses at all.
- Bot teardown ran twice (once from the run loop, once from
  `_finalize`), calling `peer_disconnect_now` on a peer whose host was
  already destroyed. Three ERROR lines per successful run.
- The container lacked `libfontconfig1`, so Godot logged ten fontconfig
  ERRORs on every invocation. Harmless individually, but a log where
  routine ERRORs are normal is a log where a real one goes unnoticed —
  and `test-load`'s scan reads exactly those logs. Both logs are now
  clean at zero ERROR lines on a passing run, which is what makes the
  scan worth anything.

**Deliberately still open, not silently assumed:** fog of war (D-004's
reveal semantics), combat (Q7), casualties (M1 has no combat, so
`alive` is only ever the full squad size), and per-squad selection in
the client (M3 UI work). Replication uses reliable ENet delivery
throughout; unreliable-with-resend is a refinement M4 can measure.

---

### D-021 · 2026-07-29 · Accepted
**Decision:** **No C# in the shipping build.** GDScript for all gameplay
and simulation code. Where profiling shows a specific kernel exceeding
budget, the escape hatch is **GDExtension (C++/Rust) scoped to that
kernel** — not a project-wide .NET conversion. This narrows D-009's
looser "C# only where profiling shows a specific need" clause; see the
note appended to D-009.

**Rationale:** Q6 framed this as a question about export matrix and
platform support. For this project it largely isn't: shipping is Steam
desktop (D-015 → M7), Godot's .NET builds export to Windows/Linux/macOS,
and there is no web target — the usual platform argument against C# does
not apply here. Dedicated servers (Q3, open) are Linux either way. The
decision therefore rests on toolchain cost and reversibility.

*Toolchain cost is permanent.* The current image is debian-slim plus one
Godot zip. .NET means the Mono/.NET Godot artifact, the .NET SDK in the
image, a NuGet restore, and a compile step gating `test-unit` on top of
the headless-import step D-015 already requires. That is paid on every
container operation from M1 onward, against D-014's explicit premise of
a small footprint and clean teardown.

*Reversibility is asymmetric.* Deciding no now and reversing at M4 costs
the container/export rework — which is the same work whether done now or
then, since existing GDScript keeps working alongside a later `.csproj`.
Deciding yes now pays the toolchain tax continuously across M1–M3 for a
bottleneck that is speculative.

*D-006's confirmation is what makes this tenable.* The strongest argument
for C# is that D-009's packed-array-outside-the-scene-tree design is
ergonomic in C# (structs, spans, generics) and ugly in GDScript (parallel
`PackedFloat32Array`s with hand-rolled index math). That argument was
substantially weakened on 2026-07-28: because soldier positions are
derived rather than stored, the hot data set is ~1,000 squads of state,
not ~40,000 soldiers — a 40x reduction. Manual index math over a thousand
entities is unpleasant but tractable. **Had D-006 been rejected, this
entry would likely have gone the other way.**

**Rejected alternatives:** C# permitted project-wide from the start
(rejected — continuous cost for speculative benefit; the hiring-pool and
static-typing arguments are real but don't outweigh it at this stage).
Leaving D-009's vague "C# if profiling shows a need" as the answer
(rejected — that phrasing can't be acted on when sizing the container or
export matrix, which is precisely why Q6 demanded a yes/no). GPU compute
shader as the general escape hatch for the flow-field solver (rejected as
*unsafe*: the authoritative server is headless and, depending on Q3, may
be CPU-only in a cloud VM — GPU acceleration is available to the client
renderer, not to the server-side solver).

**Explicitly not a reason:** .NET GC pauses. At D-020's 100 ms tick,
gen0 collections are noise and a gen2 pause is poolable. Recorded here so
the argument doesn't get re-raised as though it were load-bearing.

**Consequences:** Container and export stay single-toolchain. D-009's C#
clause is narrowed (note appended there); `CLAUDE.md`'s Conventions
section updated to match. Accept the ergonomic cost of parallel packed
arrays in GDScript for D-009's simulation state. Note that GDExtension is
deferred cost, not free: it brings its own native build matrix
(`.dll`/`.so`/`.dylib` per target), so the escape hatch should be reached
for once, deliberately, on measured evidence.

**Revisit trigger:** M4 profiling identifies a kernel exceeding budget
that GDScript-level optimization cannot close. The flow-field solver
(D-007) under D-003's invalidation-storm conditions is the prime
candidate — a wrap-aware pass over 10,000+ cells (Q8) recomputed for many
squads at once. Reverse to GDExtension for that kernel first; revisit
project-wide C# only if several kernels qualify.

---

### D-020 · 2026-07-28 · Accepted, per-LOD variation Open
**Decision:** Server simulation tick rate is **10 Hz** (100 ms). This is
the rate at which authoritative game state advances. It is explicitly
*not* the same number as either the curve keyframe emission rate (D-003)
or the flow-field recompute rate (D-007), both of which are lower and
independently tunable.

**Rationale:** 10 Hz was already load-bearing in D-018's accepted math
("1,000 squads at a 10 Hz tick is 10,000 squad-updates/second") while
remaining formally undecided — this entry closes that gap rather than
introducing a new number. The rate is defensible on its own terms: at
full scale it leaves ~50 µs per squad-update to consume half of one core,
which is a workable GDScript budget under D-009's packed-array design.

Crucially, D-003 decouples tick rate from *visual* smoothness. Under
snapshot replication 10 Hz would look choppy; under curve-based sync
clients interpolate continuously along a received curve, so tick rate
governs decision and combat-resolution latency, not motion fidelity. The
cost that remains is up to 100 ms of command quantization on top of
network RTT — well inside genre norms, where classic lockstep RTS
deliberately ran 200–500 ms command latency.

**Rejected alternatives:** 20–30 Hz (rejected — doubles or triples the
squad-update budget for latency the genre doesn't need and that D-003
already hides visually); 5 Hz (rejected — halves the cost but pushes
worst-case command quantization to 200 ms and coarsens combat resolution
to 200 ms rounds, which starts to constrain Q7's design space).

**Consequences:** Per-squad update cost should be measured against a
100 ms tick budget from M1 onward, per D-012's "keep it measurable and
swappable." Combat resolution (Q7) has a 100 ms minimum round
granularity. Do not conflate this number with network send rate — an
idle squad still costs zero bandwidth per D-003 regardless of tick rate,
and that property must survive M1's implementation.

**Revisit trigger:** M1/M4 profiling showing squad-update cost exceeding
the 100 ms budget at D-018's counts — per D-018's own revisit trigger,
tick rate is the dial to consider before the architecture. Whether the
tick rate itself varies by LOD tier remains **open** and is deferred to
M5 with the rest of D-012.

---

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

### D-006 · 2026-07-28 · Accepted (confirmed 2026-07-28 — see confirmation block below)
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

**Confirmed 2026-07-28.** Promoted Provisional → Accepted, with the scope
sharpened. The original entry bundled two separable claims: that soldier
positions are never *networked* (a bandwidth claim) and that they are
never *server-authoritative state* (a simulation-cost claim). Only the
first is load-bearing, and it does not depend on the second — if a
soldier's position is a pure function of replicated squad state, the
server may compute it whenever combat needs it and still send nothing.
Server and client agree by construction rather than by synchronization.

Three clauses, now binding:

1. **Purity.** A soldier's position is a pure function of (squad curve,
   formation shape, slot index, terrain sample). No per-soldier
   integration state — no velocity, no accumulated offset, no history
   carried across ticks.
2. **Cosmetic offsets are one-way.** Client-side visual offsets (idle
   sway, footfall jitter, terrain settling) are permitted and are never
   read back by simulation. This is where visual life comes from without
   touching the keystone.
3. **Casualty slot reassignment is deterministic**, derived from the
   ordered death-event log — which is already replicated as sparse
   reliable events, so reassignment stays inside the purity boundary.
   The formation restamps; soldiers do not walk to fill a dead man's
   slot.

**Corrected revisit trigger** (replaces the original above, which was
miswritten): the trigger is *not* "combat needs server-authoritative
per-soldier positions" — under clause 1 that is free. The trigger is
**emergent per-soldier movement**: local avoidance, collision push-back,
soldiers physically jostling, neighbors pathing into a vacated slot. Any
of those gives a soldier its own integration state and breaks clause 1,
at which point the only options are networking ~40,000 entities or
accepting divergence. Revisit before M2 if the combat model wants one.

**Consequence for Q7.** This constrains the still-open combat model
rather than waiting on it. Q7 must resolve to something expressible
within clause 1: squad-level stochastic resolution satisfies it
trivially; deterministic per-soldier resolution satisfies it only if
resolution *reads* derived positions without perturbing them; per-soldier
resolution that physically moves soldiers as a result of combat does not
satisfy it and trips the corrected trigger above.

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

**Narrowed 2026-07-29 by D-021.** The "C# only where profiling shows a
specific need" clause above is superseded: C# is **not** permitted in the
shipping build at all. The escape hatch for a kernel that exceeds budget
is GDExtension (C++/Rust) scoped to that kernel. The rest of this entry —
GDScript at squad granularity, `MultiMesh` rendering, packed arrays
outside the scene tree — stands unchanged. See D-021 for the reasoning,
including why D-006's confirmation is what makes GDScript tenable for the
packed-array design.

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

**Schema log** (this entry requires schema changes be recorded here, not
just in code):

- **2026-07-29, M1 — added `formation_spacing: float = 1.0`.** Formation
  geometry (D-006/D-019) needs a per-unit centre-to-centre spacing;
  cavalry and skirmishers do not occupy the footprint of line infantry.
  Existing `.tres` files pick up the default, so this is backward
  compatible.

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
- **Q7 — Combat model:** deterministic per-soldier resolution vs.
  stochastic squad-level rolls. Directly interacts with D-006 and D-012:
  squad-level rolls make LOD and D-006 easy, per-soldier resolution makes
  both hard. Now also needs to define formation-break and morale/rout
  thresholds per D-019. **As of D-006's confirmation this is constrained,
  not merely interacting:** any answer must be expressible within D-006's
  purity clause — see "Consequence for Q7" there. The *shape* of the
  answer (squad-level rolls vs. per-soldier resolution) is worth calling
  early even though the thresholds themselves can wait for M2.
- ~~Q9 — Simulation tick rate~~ → D-020 (10 Hz). The remainder — whether
  the tick rate **varies by LOD tier** — is still open and deferred to
  M5 with D-012, so it no longer blocks M2.
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
