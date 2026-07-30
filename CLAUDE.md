# CLAUDE.md — Project Instructions

This file is read automatically by Claude Code at the start of a session.
It exists so you don't have to re-derive the architecture from scratch
every time — the full reasoning lives in `game_design_decisions.md`;
this file is the condensed "ground rules" version.

## Current status

**M1 (movement + netcode proof) complete**, as of 2026-07-29 — declared
done, then audited and found incomplete, then actually finished. `just
test-unit` is green at 141 tests across 10 scripts; `just test-load 4 12`
runs 4 bots against the server end to end and reports a clean verdict.
Every justfile recipe is real.

The headline measurement: **~1.5–2.7 µs per squad-update** at 48 squads,
against D-020's ~50 µs budget. That is the number D-018's full-scale
target and D-021's no-C# call both depend on, so re-measure it (via
`just test-load`, which prints it) whenever the simulation changes shape.
It moves run to run with host load — the order of magnitude is the
result, not the third digit.

**Always quote it with a squad count.** It is total tick time divided by
(ticks × squads), so per-tick fixed overhead lands in the per-squad
figure and inflates it when squads are few: a real play session with 12
squads measured ~3.9 µs against ~2 µs for the same code at 48. Comparing
the two numbers directly would read as a 2x regression that isn't there.
Since the whole point is extrapolating to ~1,000 squads, if anything
this metric flatters low counts and understates headroom.

**Read the audit block at the end of D-022 before adding any test or
check.** M1's first "complete" was wrong in two ways that are easy to
repeat: a test that supplied both client and server the same inputs
itself, and so could not see them disagreeing in the live system; and a
log grep for a word no code path ever printed, which passed vacuously
for the whole milestone and hid the first bug. The standing rule that
came out of it: **every check must be observed to fail before it is
trusted.**

Next is **M2**: combat + fog of war. Both are blocked on decisions, not
code — Q7 (combat model) and D-004's reveal/conceal semantics. See
`game_design_decisions.md` section 2.

D-006 (derived soldier positions) is Accepted and implemented in
`formation.gd`. Its three binding clauses are load-bearing for
everything built so far: soldier position is a **pure function** of
(squad curve, formation shape, slot index, terrain sample) with no
per-soldier integration state; client-side cosmetic offsets are
**one-way** and never read back by simulation; casualty slot
reassignment is **deterministic** (the formation restamps — soldiers
don't walk into a vacated slot). Emergent per-soldier movement of any
kind — local avoidance, collision push-back, jostling — is out of bounds
and is the explicit revisit trigger.

`Formation` is an all-static class on purpose: there is nowhere to put
per-soldier state, so the purity clause is enforced rather than merely
documented. Cosmetic motion lives in its own file (`cosmetic_offset.gd`)
for the same reason — the one-way boundary is structural.

Q7's *shape* (squad-level rolls vs. per-soldier resolution) is worth
settling before M2 starts. D-006 constrains it — any answer must be
expressible within the purity clause — and D-020 gives it a 100 ms
minimum round granularity.

## What this project is

A large-scale real-time strategy game, inspired by *Empires: Dawn of the
Modern World* and *Rome: Total War* (formations and morale/routing,
specifically — not a campaign layer), targeting **20 concurrent players
/ 2,000 soldiers each (40,000 total, ~50 squads/player, ~1,000 squads
total) on a single seamless map**, 4–6 civilizations at launch, shipping
on Steam. Built in Godot specifically because its plain-text asset
formats (`.tscn`/`.tres`) make the project directly editable by Claude
Code — that's a design constraint, not an afterthought.

**Before making any architectural decision, check `game_design_decisions.md`
first.** It's the living record of every major call made so far, with
rationale and rejected alternatives attached. If a decision isn't in
there yet, flag it explicitly rather than picking silently — this
project's whole workflow depends on decisions being written down, not
just implemented.

## Non-negotiable architecture (do not casually deviate from these)

- **Client-server, not lockstep.** Server is authoritative. Clients send
  input, receive curve-based state updates, interpolate locally.
- **Curve-based state sync.** Object state (position, build progress,
  etc.) is sent as keyframed curves, not per-tick snapshots. If an
  object isn't changing, it costs zero bandwidth. This is also the
  mechanism fog of war uses to gate what a client receives — don't build
  a separate fog-of-war data-hiding system, extend this one.
- **10 Hz simulation tick** (D-020). That is the rate authoritative state
  advances — it is *not* the curve keyframe emission rate or the
  flow-field recompute rate, both of which are lower and tuned
  separately. Don't collapse these into one number: an idle squad must
  still cost zero bandwidth regardless of tick rate. Per-squad update
  cost is budgeted against a 100 ms tick.
- **Squads, not individual units, are the atomic simulation unit** for
  movement and production. Pathfinding, networking, and unit production
  all operate at squad granularity. Don't reintroduce per-unit
  pathfinding or per-unit production queues.
- **Flow-field pathfinding**, computed per squad destination, not
  per-unit A*.
- **Wrapped flat hex grid (torus)**, not a true geodesic sphere. Every
  distance/neighbor/noise calculation must be wrap-aware (modulo
  indexing, toroidal distance via ghost-copy comparison, periodic noise
  sampling). This is a recurring "tax" — expect it in pathfinding,
  vision, minimap rendering, and terrain generation alike.
- **LOD is planned, not a fallback.** Combat resolution, economy
  simulation, and tick rate all vary by proximity to player attention
  (full fidelity near active play, aggregate/statistical far away).
  Global slowdown (PA-style time dilation) is an emergency safety valve
  only — never the primary way this project handles scale.
- **Everything that can be data-driven should be.** Unit stats, civ
  configs, terrain-gen parameters: plain text (`.tres`/JSON), not
  hardcoded. This is what makes the project actually editable via
  Claude Code rather than requiring the Godot editor GUI.

## Project layout

```
--- simulation core (all pure/headless, no scene tree) ---
torus_space.gd           THE wrap-aware hex grid (D-008). Every distance,
                        neighbour and world conversion goes through it.
                        Each method normalises its own inputs, so
                        forgetting to wrap cannot produce a wrong answer.
flow_field.gd            Per-destination flow field (D-007). One field
                        serves every squad heading there — that sharing
                        is the scaling claim, so don't make it per-squad.
state_curve.gd           Keyframed state curves (D-003). Stores points in
                        CONTINUOUS UNWRAPPED axial space; read the header
                        comment before touching it, or seam crossings
                        break in a way that looks like a netcode bug.
curve_replicator.gd      Per-client gating, horizon clipping and the
                        budgeted invalidation scheduler (D-003/D-004).
formation.gd             Derived soldier positions (D-006). All-static
                        and pure — no instance state, by construction.
cosmetic_offset.gd       Client-only visual jitter. One-way: simulation
                        must never read it back (D-006 clause 2).
squad_sim.gd             The authoritative 10 Hz sim (D-020) over packed
                        arrays (D-009). Ticked by an explicit
                        accumulator, never _physics_process (D-023).
terrain_gen.gd           Periodic (seam-continuous) terrain noise.
terrain_chunk.gd         Chunked hex meshing (D-017) — never per-cell.
replay_log.gd            Replays ARE the curve log (D-016), byte-
                        identical to the wire format.

--- networking ---
net_protocol.gd          The one definition of the wire protocol, shared
                        by server, client and bots so they can't drift.
client_state.gd          Everything a client knows, with no rendering
                        attached. The GUI client and the load-test bots
                        both run THIS — so test-load exercises the real
                        client path, and the client's logic is testable
                        headless even though the client itself isn't.
server.gd / server.tscn  Headless authoritative server (D-002).
client.gd / client.tscn  GUI client. Native-only, needs a GPU (D-014).
bot_client.gd            Headless load-test bot. Runs N *virtual*
                        clients in one process, not N processes (memory
                        budget — see D-018).

--- data ---
/units/*.tres          Unit definitions (UnitDef resources) — the MVP
                        roster lives here. Add new units by adding a
                        .tres file, not by writing new unit classes.
unit_def.gd             UnitDef schema — extend fields here when a new
                        unit needs a stat that doesn't exist yet, and
                        record the change in D-010's schema log.
unit_roster.gd          Loads /units in a stable order. Server, client
                        and tests all discover units through this.
/maps/*.tres            MapConfig resources (torus dimensions, squads
                        per player). Height must be even — D-008.
map_config.gd           MapConfig schema.
primitive_unit.gd       Tier-1 mesh generation (capsule/box/cylinder/
                        hull primitives) — see "Mesh pipeline" below.

--- tooling ---
justfile                 The full command vocabulary for local dev,
                        testing, and export. Use these recipes rather
                        than reconstructing godot/steamcmd invocations.
terrain_preview.gd       Headless terrain preview + chunk profiling.
replay_info.gd           Reads a replay back and reconstructs state.
game_design_decisions.md The living design doc. Read before deciding,
                        update after deciding.
bootstrap.ps1            Fresh-clone entry point. Fetches `just` into
                        tools/ so the recipes below can run at all.
                        Nothing is installed system-wide.
/tests/*.gd              GUT tests, run headless by `just test-unit`.
                        Each file names the decisions it guards in its
                        header — they exist to make silent architectural
                        drift fail loudly, so read that header before
                        changing what a test asserts.
Dockerfile               Pinned Godot headless image (D-001/D-014).
docker-compose.yml       server / bots / test services. Teardown-scoped:
                        pinned project name, --rm, no restart policy,
                        no named state volumes.
.godot-version           The pinned Godot version. Both the container
                        build and `just bootstrap` read this — bump it
                        here, not in either of them.
/tools/                  Gitignored. Portable `just` and (native runtime
                        only) portable Godot. `just nuke` deletes it.
```

## Mesh pipeline — respect the tiers

1. **Primitive tier** (current MVP state): capsules/boxes/cylinders,
   composed from `UnitDef` data, zero art dependency. This is where the
   project is right now — don't jump ahead to importing art assets
   unless explicitly asked.
2. **Modular/parametric tier**: interchangeable parts combined
   programmatically. Not started yet.
3. **Final-fidelity tier**: Blender via `bpy`, headless, exported as
   glTF. Not started yet.

Terrain follows the same philosophy: biome-colored hex mesh + elevation
vertex offset, chunked (not one mesh per cell — that's a performance
requirement at 10,000+ cell map sizes, not a style choice).

## Testing — use the justfile, and use it before claiming something works

`just` lives in `tools/` and is **not on PATH** — invoke it as
`./tools/just.exe <recipe>`. On a fresh clone run `./bootstrap.ps1`
first. Recipes call each other via `{{just_executable()}}` for the same
reason; a bare `just` inside a recipe will not resolve.

**Run recipes from a bash shell (Git Bash), not PowerShell.** From
PowerShell, `just` resolves `sh` to WSL's bash and dies with
`execvpe(/bin/bash) failed` before any recipe body runs.

Lifecycle:

- `just doctor` — preflight: runtime prerequisites actually met?
- `just up` / `just down` / `just status`
- `just nuke` — full teardown back to pure source. **Deletes `tools/`,
  including the `just` you ran it with** — that's intentional; re-run
  `./bootstrap.ps1` to come back.

Dev loop and tests:

- `just run-server` — headless authoritative server
- `just run-client [ADDRESS] [PORT]` — GUI client for a human to look at.
  **Native only**; needs a GPU (D-014), so it ignores `EDOTMW_RUNTIME` and
  says so if portable Godot is missing. WASD pans, wheel zooms,
  right-click orders.
- `just test-client [SECONDS]` — the same client, rendered headlessly via
  Mesa's software rasteriser and checked automatically. Writes
  `artifacts/client-frame.png`; **look at it**, that is the point. Docker
  only. See D-014's 2026-07-29 amendment for why this doesn't contradict
  "the client can't be containerized".
- `just run-bots N [DURATION]` — N virtual load-test bots in one process.
  Requires a server to already be up (`just up`) — it deliberately does
  not start one, because a `run --rm` dependency leaks a container.
- `just test-unit` — GUT unit tests, headless *(green: 141 tests)*
- `just test-load N DURATION` — full load test: server + N bots for
  DURATION seconds. Checks the bots' exit status, an explicit VERDICT
  line, AND a log scan for engine diagnostics. Tears down via trap on
  success, failure, and Ctrl-C. Prints the per-squad update cost — the
  number to watch — plus how many client/server state-hash comparisons
  ran and how many desynced.
- `just gen-terrain-preview [CHUNK_SIZE]` — terrain PNG into `artifacts/`
  plus chunking cost. Vary CHUNK_SIZE to settle D-017 with data.
- `just replay-info [FILE]` — read a replay back and reconstruct state.

Every recipe listed is real and verified; none are stubs.

**Any recipe that runs Godot against this project must import first.**
Godot resolves global `class_name`s from the import cache, and without it
scripts fail to parse with a misleading "Identifier not declared in the
current scope" plus a scatter of "cannot infer type" on unrelated lines.

This was previously written as "any new *headless* recipe must depend on
`_import`" — and that wording predicted the wrong set. `run-client` is
not headless, so it was never given the step, and it failed on the first
real launch exactly this way. Headlessness was never the relevant
property; needing global `class_name`s is, and everything needs those.

Note `run-client` cannot use the shared `_import` dependency: `_import`
follows `EDOTMW_RUNTIME`, which defaults to docker and populates
`.godot-container`, while the GUI client is always native (D-014) and
reads `.godot`. It runs a native import inline instead.

**Before reporting a change as done, run the relevant test recipe.**
Given the project's performance targets (40,000 soldiers / ~1,000
squads, 20 players), "it compiles" is not the same as "it holds up at
scale" — use `test-load` for anything touching netcode, pathfinding, or
simulation cost.

**A green run is not the same as a run that happened.** `test-load` once
reported "clean" while every bot had exited non-zero, because it only
grepped for words that didn't appear. Separately, its `desync` scan
matched no code path at all and passed vacuously for the whole of M1,
hiding a live bug in which every client derived soldier positions from a
different squad strength than the server used.

So, three rules, each bought with a real defect:

1. Assert the thing *did* happen, not merely that nothing complained.
   `test-load`'s verdict now fails if zero state-hash comparisons ran.
2. **Observe every new check fail before trusting it.** Perturb the
   thing it guards, watch it go red, then revert.
3. Don't scan for scary words — scan for structured markers. The word
   scan was later fixed again after it failed a good run by matching its
   own success line, "0 desyncs".

**Client/server agreement must be tested through the wire.** A test that
hands both sides the same inputs proves `Formation` is pure — which it
is — and cannot notice the live system feeding them different ones. See
D-006's "necessary but not sufficient" note.

**Numbers can all be right while the picture is wrong.** The first frame
the client ever rendered contained no soldiers, with every numeric check
passing: 12 squads drawn, 384 soldiers derived, zero desyncs. They were
deriving at y=0 and rendering inside the terrain. `just test-client`
exists for this class of bug — and the PNG it writes is meant to be
looked at, not just asserted about.

## Conventions

- **GDScript only — no C# in the shipping build** (D-021). This is a
  yes/no answer, not a preference: don't add a `.csproj`, don't reach for
  the .NET Godot artifact, don't assume the .NET SDK is available in the
  container. If a specific kernel is measured to exceed budget, the
  escape hatch is **GDExtension (C++/Rust) scoped to that kernel** — and
  only on M4 profiling evidence, not on suspicion.
- Godot headless mode (`--headless`) for anything scriptable — server,
  bots, tests, terrain preview generation. Don't assume the editor GUI
  is available.
- New units: add a `.tres` file under `/units/`, don't hardcode stats
  in scripts.
- Any forced binary-only or GUI-only step (hand-sculpted final meshes,
  visual editor-only configuration) should be flagged explicitly as an
  exception, not treated as the default path.

## When something isn't decided yet

Check the "Open Questions / Not Yet Decided" section at the bottom of
`game_design_decisions.md`. If you need an answer to something listed
there to proceed, surface that rather than guessing — these are marked
open because they genuinely haven't been resolved, not because they
were forgotten.
