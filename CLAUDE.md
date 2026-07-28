# CLAUDE.md — Project Instructions

This file is read automatically by Claude Code at the start of a session.
It exists so you don't have to re-derive the architecture from scratch
every time — the full reasoning lives in `game_design_decisions.md`;
this file is the condensed "ground rules" version.

## Current status

**M0 (skeleton) complete**, as of 2026-07-28. `just test-unit` runs GUT
headless through the `docker` runtime and passes; `just nuke` verified
to fully tear down containers/images/`tools/`/`.godot` caches back to
pure source. Nothing below is aspirational in structure anymore — the
directories and files this document names exist — but gameplay itself
hasn't started (that's M1). See `game_design_decisions.md` section 2 for
what's still genuinely undecided, and D-006 in particular, which is
provisional and blocks M1.

M1 needs, in order: (1) confirm or reject D-006 (derived soldier
positions — the netcode budget hinges on this), (2) answer Q6 (C# in
shipping build), (3) build the actual movement/curve-sync/flow-field
loop against M1's exit criteria in `game_design_decisions.md` section 2.

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
/units/*.tres          Unit definitions (UnitDef resources) — the MVP
                        roster lives here. Add new units by adding a
                        .tres file, not by writing new unit classes.
unit_def.gd             UnitDef schema — extend fields here when a new
                        unit needs a stat that doesn't exist yet.
primitive_unit.gd       Tier-1 mesh generation (capsule/box/cylinder/
                        hull primitives) — see "Mesh pipeline" below.
justfile                 The full command vocabulary for local dev,
                        testing, and export. Use these recipes rather
                        than reconstructing godot/steamcmd invocations.
bot_client.gd            Headless load-test bot — connects like a real
                        client, drives scripted behavior for testing at
                        scale. Runs N *virtual* clients in one process,
                        not N processes (memory budget — see D-018).
game_design_decisions.md The living design doc. Read before deciding,
                        update after deciding.
bootstrap.ps1            Fresh-clone entry point. Fetches `just` into
                        tools/ so the recipes below can run at all.
                        Nothing is installed system-wide.
/tests/*.gd              GUT tests, run headless by `just test-unit`.
                        test_unit_defs.gd guards D-009 and D-010 —
                        every .tres in /units/ is loaded and schema-
                        checked, so a malformed unit fails the suite.
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

Lifecycle:

- `just doctor` — preflight: runtime prerequisites actually met?
- `just up` / `just down` / `just status`
- `just nuke` — full teardown back to pure source. **Deletes `tools/`,
  including the `just` you ran it with** — that's intentional; re-run
  `./bootstrap.ps1` to come back.

Dev loop and tests:

- `just run-server` / `just run-client` — manual dev loop *(M1)*
- `just run-bots N` — N virtual load-test bots in one process
- `just test-unit` — GUT unit tests, headless *(green: 7 tests)*
- `just test-load N DURATION` — full load test: server + N bots for
  DURATION seconds, then scans logs for warnings/desyncs. Tears down via
  trap on success, failure, and Ctrl-C. *(gated on `run-server`, so M1)*
- `just gen-terrain-preview` — fast terrain-gen iteration loop *(M1)*

Recipes marked *(M1)* depend on scenes that don't exist yet and exit
non-zero with a clear message. That's deliberate — never make one
silently succeed to get a green run.

**Before reporting a change as done, run the relevant test recipe.**
Given the project's performance targets (40,000 soldiers / ~1,000
squads, 20 players), "it compiles" is not the same as "it holds up at
scale" — use `test-load` for anything touching netcode, pathfinding, or
simulation cost.

## Conventions

- GDScript preferred for gameplay logic; C# acceptable for
  performance-critical simulation code if profiling shows a need.
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
