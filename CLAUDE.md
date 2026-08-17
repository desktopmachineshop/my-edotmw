# CLAUDE.md — Project Instructions

This file is read automatically by Claude Code at the start of a session.
It exists so you don't have to re-derive the architecture from scratch
every time — the full reasoning lives in `decisions/` (one file per
decision; see `decisions/README.md`); this file is the condensed
"ground rules" version.

## Current status

The milestone-by-milestone narrative — what is complete, the standing
rules each milestone bought, and the measurements with their caveats —
lives in `docs/status/`, ONE FILE PER MILESTONE OR TOPIC, imported below
in reading order. **Edit the file for the thing you touched** (a fog
change edits `ground-fog.md`, a spawn change edits `spawns.md`); never
recreate a shared monolith here — that is what made every parallel merge
conflict (see `decisions/D-20260816-decision-docs-split.md`).

Headline state: M1–M5 and M7 complete; M6 in progress; M8 (Steam) and
M9 (epochs, six civs) planned but not built. For current test counts or
performance numbers, run the recipe (`just test-unit`, `just test-load`)
— a number quoted in prose is stale by construction on a merged tree,
and measurements belong in the decision entry that took them.

@docs/status/m1.md

@docs/status/m2.md

@docs/status/m3.md

@docs/status/load-testing.md

@docs/status/m4.md

@docs/status/m5.md

@docs/status/m6.md

@docs/status/m7.md

@docs/status/terrain.md

@docs/status/spawns.md

@docs/status/ground-fog.md

@docs/status/forests.md

@docs/status/world-look.md

@docs/status/formation.md

@docs/status/playtests-2026-08.md

@docs/status/m8-plan.md

@docs/status/m9-plan.md

## What this project is

A large-scale real-time strategy game, inspired by *Empires: Dawn of the
Modern World* and *Rome: Total War* (formations and morale/routing,
specifically — not a campaign layer), targeting **20 concurrent players
/ 2,000 soldiers each (40,000 total, ~50 squads/player, ~1,000 squads
total) on a single seamless map**, 4–6 civilizations at launch, shipping
on Steam. Built in Godot specifically because its plain-text asset
formats (`.tscn`/`.tres`) make the project directly editable by Claude
Code — that's a design constraint, not an afterthought.

**Before making any architectural decision, check `decisions/` first**
(grep for the topic or the D-id — some legacy IDs live inside sibling
entries rather than their own file). It's the living record of every
major call made so far, with rationale and rejected alternatives
attached. If a decision isn't in there yet, flag it explicitly rather
than picking silently — this project's whole workflow depends on
decisions being written down, not just implemented. **A new decision is
a NEW file** named `decisions/D-YYYYMMDD-slug.md` — never an append to
a shared file, and never a renumber of an existing ID
(`decisions/README.md` has the rules and why).

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
- **Combat is squad-level, stochastic, and server-only** (D-024). A
  squad-vs-squad engagement resolves as aggregate arithmetic over
  `alive`, `damage`, and `attack_interval`, rolled from a seeded RNG —
  never a per-soldier resolution, and never a client-side roll (clients
  receive outcomes, so there is no client RNG to diverge). Casualties
  are integer decrements to `alive`, with fractional damage carried in a
  per-squad accumulator. `alive` is the *only* formation input a death
  changes, so casualty slot reassignment (D-006 clause 3) needs no
  per-soldier identity anywhere — don't reintroduce one to make combat
  feel more "precise". Morale and routing are per-squad values (D-019),
  not per-soldier.
- **Fog of war is still curve gating, and only that** (D-004, D-025).
  Vision is a per-player field, stamped once per player over cells from
  their own squads, then a single O(1) lookup per squad
  (`Vision.is_visible`) — never a per-pair distance test, and
  radius-only: elevation does not occlude in M2. Reveal is a truthful
  pop-in (the same horizon-clipped curve any squad gets, sent fresh, no
  synthetic catch-up). Conceal is an explicit wire event, not an
  inference from a curve going quiet, because a client can't otherwise
  tell "out of vision" from "merely late". A concealed squad becomes a
  client-side ghost — last-known curve and composition, frozen — and a
  ghost must never be folded into `composition_hash()`: the server
  hashes exactly `visible_to(player)`, and a client that counted its own
  ghosts would hash a strictly larger set and desync on a perfectly
  healthy system. Don't build a second data-hiding mechanism anywhere —
  extend this one. **A ghost is data the client keeps, not a picture on
  screen** (D-099): a concealed squad is drawn nowhere — 3D view or
  minimap — while a building once seen stays drawn, unfaded, forever.
  Those two rules differ on purpose, and the transparent unit shader that
  used to fade a ghost is deleted rather than dormant.

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
animation_state.gd       Which clip a soldier plays and at what phase
                        (D-082). All-static, so there is nowhere for the
                        phase accumulator D-006 forbids to live.
cosmetic_offset.gd       Client-only visual jitter. One-way: simulation
                        must never read it back (D-006 clause 2).
squad_sim.gd             The authoritative 10 Hz sim (D-020) over packed
                        arrays (D-009). Ticked by an explicit
                        accumulator, never _physics_process (D-023).
combat.gd                Squad-vs-squad combat resolution (D-024),
                        server-only. A bucket map plus a per-attacker
                        disk scan, not a pairwise squad×squad scan —
                        same cost shape as vision.gd, same reason.
vision.gd                Per-player vision field over cells (D-025).
                        Stamped once per player, then an O(1) lookup
                        per squad — closes the "visible_to() returns
                        every squad" stub D-022 flagged for M1.
terrain_gen.gd           Periodic (seam-continuous) terrain noise, plus
                        `build_fields` — heights, colours, biomes and
                        passability in one pass (D-096). `corner_cells`
                        is THE definition of which three cells meet at a
                        corner, and it returns them sorted so all three
                        agree bit for bit. Every frequency it samples with
                        is a DENSITY against `REFERENCE_WIDTH`, scaled by
                        the map's own width in `effective_frequency`
                        (D-105) — so a bigger map is bigger, not finer.
terrain_fields.gd        What `build_fields` returns. One object, because
                        surface and colours are indexed identically and a
                        caller that paired them wrongly would just paint
                        the ground wrong with nothing failing.
terrain_chunk.gd         Chunked hex meshing (D-017) — never per-cell.
                        Owns the continuous cell-derived UVs (D-096), the
                        per-cell atlas tile slots the shader blends, the
                        cliff skirts (D-097) and the cell-derived fog UVs
                        (D-106).
terrain_fog.gd           What ONE CLIENT knows about each cell of the
                        ground (D-106): never seen, seen once, in sight
                        now. vision.gd's sibling on the other side of the
                        wire — the same disk stamp, but it decides how the
                        map is DRAWN rather than what is sent. Purely
                        presentational: nothing here reaches the wire,
                        which is what makes deriving it locally legal.
render_cull.gd           Wrap-aware render culling and LOD selection
                        (D-045). All-static and pure, so the half with
                        the interesting failure mode — which lattice copy
                        of a squad to draw — is testable without a GPU.
world_look.gd            The one definition of the lighting rig — sun,
                        sky, ambient, tonemap, fog (D-086). All-static,
                        guarded by a test that fails if any other script
                        constructs a DirectionalLight3D or Environment
                        directly. client.gd, bench_render.gd and
                        model_preview.gd all build off this now, so the
                        shipping rig and the benchmark rig cannot drift
                        apart the way three hand-copies did before.
hud_layout.gd            Where the HUD's pieces go, for a window of any
                        size (D-061). Scale AND anchoring — either alone
                        looks sufficient and is not. All-static, pure.
                        Also owns the HUD's non-obvious arithmetic: the
                        match clock, the n/cap readout, and the compass
                        dial's geometry (D-063).
scoreboard.gd            Who is in this match, and what this player is
                        ENTITLED to see about them (D-102). All-static and
                        pure. Identity (colour, civ, team) is public and
                        needs no plumbing — it was already on the client.
                        Army size is DERIVED from what the server chose to
                        send, never asked for, so an enemy's total cannot
                        be leaked by a future caller: own and ally counts
                        only, everyone else a dash. Standing (playing/
                        eliminated/victor) is the one thing here that had
                        to go on the wire, because fog makes it
                        underivable.
selection_pick.gd        Which thing a click selected, from every
                        candidate's screen geometry (D-061). Same split
                        as render_cull.gd: the client needs a GPU, the
                        ranking that was wrong does not.
minimap_paint.gd         What the minimap paints over the terrain, and how
                        big (D-101). Buildings are drawn from KNOWLEDGE,
                        not from sight — that is the only representation
                        persistent-explored fog (D-030) has anywhere, and
                        the minimap had no buildings pass at all until
                        this file existed. Footprints wrap; sizes come
                        from BuildingDef.no_build_radius, never a list of
                        ids. Also owns `fogged`, the minimap's three fog
                        TONES (D-20260817): the levels are TerrainFog's,
                        this file only decides what they look like on a
                        1px-per-cell image. Fog only ever subtracts, so
                        VISIBLE is biome_color untouched and the minimap
                        cannot invent a colour the 3D ground lacks.
                        `squad_marks` is the same shape for ARMIES
                        (D-20260817-minimap-squad-colours): owner in,
                        colour out through ClientState.colour_of, because
                        there is ONE definition of a player's colour
                        (D-052) and a drawing function may not keep its
                        own. It reads `composition`, never `curves` —
                        that is where the owner lives, and it is what
                        makes "a ghost is drawn nowhere" (D-099)
                        structural rather than a remembered check.
ground_cover.gd          Which decorative props dress a cell (D-100).
                        Same shape as resource_visuals.gd and the exact
                        OPPOSITE of what it dresses: cover is client-
                        derived, NOT fog-gated, and costs nothing on the
                        wire, because a grass tuft leaks no information.
                        All-static and pure. A cell holding a node,
                        building or wall gets none — the caller supplies
                        that fact rather than the module reading sim
                        state.
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
/civs/*.tres           Civilizations as data (D-047). A civ fields a
                        SUBSET of unit archetypes and tunes them its own
                        way, so the same type is not the same troops in
                        two armies. Mechanical differences are declarative
                        knobs EVERY civ has — never a per-civ branch, and
                        a test fails if any .gd file names a civ at all.
civ_def.gd              CivDef schema; civ_roster.gd loads them.
unit_roster.gd          Loads /units in a stable order. Server, client
                        and tests all discover units through this.
/maps/*.tres            MapConfig resources (torus dimensions, squads
                        per player). Height must be even — D-008.
map_config.gd           MapConfig schema.
primitive_unit.gd       One MultiMesh per squad (D-009). Wears an
                        authored model when the UnitDef names one, the
                        tier-1 primitive when it does not.
unit_mesh.gd            Loads authored models, their VATs and their
                        materials. CACHED — a .glb is a scene, and
                        loading one per squad is the M4 `by_id` defect
                        with a bigger constant.
/shaders/*.gdshader     Unit opaque, building static (D-082); the ghost
                        variant is gone with the ghost rendering (D-099).
                        VAT sampling shared via a .gdshaderinc. Plus
                        `terrain.gdshader` (D-096): three atlas taps per
                        ground fragment on continuous UVs, which is what
                        a fixed-function material cannot express.
/art/**.py              Committed asset GENERATORS (D-081) — the source
                        of truth for every model and texture. Plain
                        Python; `bpy` is imported only by art/lib/bake.py.
/generated/             Committed build output: .glb, VAT .exr, the
                        terrain atlas, and a manifest whose source hash
                        makes a stale build a test failure.
art/scatter/props.py     The ground-cover props (D-100). Fails its own
                        build on an inside-out part, a prop tall enough
                        to hide a soldier, or one that does not sit on
                        y=0 — the checks a triangle count cannot make.
                        Props carry real glTF MATERIALS, not vertex
                        colours: they are drawn from a MultiMesh, and a
                        MultiMesh overrides COLOR (see art/lib/bake.py).
model_preview.gd         Renders every authored model, animated, and
                        screenshots it. The picture is the point.
cover_preview.gd         The same idea for ground cover: every prop, on
                        generated terrain, with a real squad standing in
                        it so "cover never hides a unit" is looked at
                        rather than asserted.
forest_preview.gd        The same idea again for WOODS (D-108), framed on
                        the densest one on the map from a low angle —
                        because a lattice is invisible from overhead and
                        obvious at eye height. Real Economy.generate, real
                        trees_for, real batching; nothing it draws is its
                        own idea of a forest.

--- tooling ---
justfile                 The full command vocabulary for local dev,
                        testing, and export. Use these recipes rather
                        than reconstructing godot/steamcmd invocations.
instance-id.sh           THE definition of this checkout's dev-instance
                        identity (D-095): instance name from the git
                        branch, udp port hashed from it. The justfile
                        derives its per-worktree compose project, ports
                        and container names from this — nothing may
                        re-derive it. See "Multi-agent isolation" below.
scenario.gd              Applies a mid-game world (D-098). ALL-STATIC,
                        like formation.gd: a scenario is an opening
                        position, not a participant. Goes through the
                        game's own add_squad/add_building/credit, and is
                        the SAME applier the live server uses.
scenario_def.gd          The scenario schema; scenario_squad.gd and
                        scenario_building.gd are its entries. Offsets are
                        relative to a player's home, so one loadout drops
                        onto any map.
scenario_world.gd        A complete headless world for a GUT test, in one
                        call. Exposes the sim's OWN Vision, never a
                        second one.
/scenarios/*.tres        The shipped mid-game starts. `just scenarios`.
bench_render.gd          Client render benchmark (D-045). NATIVE — it
                        needs a real GPU, and prints which one.
terrain_preview.gd       Headless terrain preview + chunk profiling. The
                        PNG is a TOP-DOWN biome map, so it can show a
                        palette drifting and cannot show how the ground
                        looks — that is terrain_shot.gd's job.
terrain_shot.gd          A rendered picture of the ground in the SHIPPING
                        lighting rig, framed deliberately on the longest
                        stretch of passability boundary on the map
                        (D-096/D-097). Software-rasterised, so it answers
                        "is the picture right" and never "how fast".
replay_info.gd           Reads a replay back and reconstructs state.
/decisions/*.md          The living design doc, ONE FILE PER DECISION
                        (D-095 &co. cited in code live here — grep for
                        the id). Read before deciding; a new decision is
                        a new D-YYYYMMDD-slug.md file, never an append.
                        Rules in decisions/README.md; open questions in
                        decisions/OPEN-QUESTIONS.md.
game_design_decisions.md Stub pointer kept so legacy citations resolve.
                        Do not add entries to it.
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

## Mesh pipeline — the tiers, as they now stand

D-011's three tiers are **superseded by D-081**. Tier 1 (primitives) is
still there as the fallback, tier 2 (parametric composition) turned out to
be *how* tier 3 is written rather than a stop on the way, and tier 3 is
built:

- **Authored tier (current):** stylised low-poly, ~300 tris/soldier,
  silhouette first. Generated by committed Python under `art/` driving
  **Blender headless as a library** (`bpy`, a PyPI wheel — no GUI, no GPU,
  no system Blender). `just build-assets` writes `generated/`.
- **Primitive tier (fallback):** `UnitDef.model_id` / `BuildingDef.model_id`
  default EMPTY, and an empty id means "use the capsule". So bots, tests
  and a clone that has never run `build-assets` all still work — a failed
  art build costs fidelity, not the game.

**Both the generators and their output are committed** (D-081). The
generators are the source of truth; `generated/` is committed anyway so a
fresh clone plays without installing anything. Two runs of
`build-assets` must be **byte-identical** — fixed seeds, sorted iteration,
no timestamps — and a test fails if `generated/` is stale with respect to
`art/`.

**Soldiers are animated by a vertex animation texture (D-082), and the
phase is DERIVED, never accumulated.** `phase = fract(t*rate + hash(slot))`,
computed in the shader from `TIME`. That is the whole reason animation is
legal under D-006 clause 1: there is nowhere for per-soldier state to
live. `animation_state.gd` is all-static for the same structural reason
`formation.gd` and `cosmetic_offset.gd` are. **A phase counter advanced by
delta time, or a blend weight carried between frames, breaks it** — those
are integration state in a cosmetic disguise.

Terrain is textured by a **per-biome atlas that MODULATES the vertex
colour** (D-083) — `TerrainGen.biome_color()` is still the single source
of truth, which is what keeps the minimap and the preview PNG from
drifting from the 3D view without either of them being touched. Terrain
UVs come from the **cell**, never from world position, so all nine torus
copies agree by construction.

Three things bought the hard way, all in one milestone:

- **Godot's `detect_3d/compress_to` silently re-imports any texture used
  in 3D with VRAM block compression and mipmaps.** On a vertex animation
  texture that is corruption — neighbouring texels are unrelated vertices.
  Import settings are generated data now, not something remembered.
- **A rebuild is invisible to Godot until it re-imports.** Verifying a
  fresh bake against a stale `.godot` cache gives confident wrong answers;
  `build-assets` ends in an import for this reason.
- **Every `box()` was wound inside-out for a whole milestone.** Nothing
  failed — a small convex object under back-face culling shows its far
  side and the silhouette is identical — but normals derive from the
  winding, so everything was lit by the inverse of the sun. It was only
  visible once a *building* was big enough to see through. **The check
  that catches this class is a picture of something large.**
  (`art/scatter/props.py` now fails its own build on a part whose signed
  volume is negative, which is the same check without waiting for a
  building — but only for props.)
- **A colour that crosses an asset pipeline is not the colour that comes
  out** (D-100). Ground-cover props carry glTF materials rather than
  vertex colours, because a MultiMesh overrides `COLOR`; Godot's importer
  then converts `baseColorFactor` linear → sRGB and NOTHING converts it
  back, so an authored 0.36 rendered as 0.63 and every fern looked
  frosted beside ground painted with the same numbers. `bake.py`
  pre-compensates and a test compares the imported material against the
  authored value in the manifest. Same family as the VAT's silent VRAM
  compression: **assert the value on the far side of the boundary.**

## Multi-agent isolation (D-095) — HARD RULES

Several agents develop this repo in parallel, each in its own worktree,
each launching servers and clients for the owner to look at. Every
checkout is its own **dev instance**: `instance-id.sh` derives an
instance name from the git branch and a udp port from its hash
(20000–29999), and the justfile threads them through every compose
project name, container name, teardown sweep and client `--port`.
`just instance` prints this worktree's identity.

The rules, none of which need remembering because the recipes enforce
them — but which must not be undone:

- **Start and stop instances only through the just recipes, from your
  own worktree.** They are scoped so you structurally cannot touch
  another agent's containers. Never `docker rm`/`docker stop` by hand
  against anything outside your own `edotmw-<instance>` project, and
  never kill a GUI client process you did not start.
- **Never hardcode the shared literals back in** — `-p edotmw`, a fixed
  container `--name`, a `4433` host port or `--port=4433` in a recipe.
  `tests/test_multi_agent_isolation.gd` fails if they reappear. The
  in-container port is still 4433 by design; only the HOST side is
  per-instance.
- **Crossing instances is the owner's explicit call, never a default.**
  `EDOTMW_INSTANCE`/`EDOTMW_PORT` override the derivation when two
  checkouts should deliberately share; do not set them on your own
  initiative.
- **The client's title bar names its instance** (`eDotMW —
  claude-<session>  [host:port]`), which is how the owner tells several
  test windows apart. Launch clients only through the recipes so the
  `--instance` flag is always passed.
- **An agent's quick launch is the dev build:** `just quick-test`
  resolves `SANDBOX=auto` to on for `claude-*` instances (D-077's
  sandbox mode, cheats panel included) and off for the owner's own
  checkout. Pass `SANDBOX=0/1` to override either way.

## Testing — use the justfile, and use it before claiming something works

`just` lives in `tools/` and is **not on PATH** — invoke it as
`./tools/just.exe <recipe>`. On a fresh clone run `./bootstrap.ps1`
first. Recipes call each other via `{{just_executable()}}` for the same
reason; a bare `just` inside a recipe will not resolve.

**Run recipes from a bash shell (Git Bash), not PowerShell.** From
PowerShell, `just` resolves `sh` to WSL's bash and dies with
`execvpe(/bin/bash) failed` before any recipe body runs.

**Every command belongs to an INSTANCE, and a worktree is isolated
automatically** — see "Multi-agent isolation (D-095)" above for the rules.
Isolation is the default: there is no argument to remember, several
agents can run `test-load` at once without touching each other, and
`just instance` prints what this checkout resolved.

**Start mid-game when the opening is not what you are testing** (D-098).
The real opening costs ~150 s before anything downstream of it exists —
one founding party, a 40 s town hall that consumes it, production, then
armies walking across a 128×64 map. A **scenario** skips to a mid-game
world: bases standing, armies in reach, wallets full.

```
just scenarios                     # what exists and what each is for
just test-scenario siege 4 30      # real server + real bots, ~31 s
just test-unit scenarios           # one test file, ~11 s
just test-unit "" within_reach     # one test by name
```

In a GUT test the whole setup is two lines:

```gdscript
var w := ScenarioWorld.build("clash")   # two armies, already in reach
w.tick(2.0)                             # two seconds at the real 10 Hz
```

Three rules come with it:

- **A scenario is applied through the game's own calls** —
  `SquadSim.add_squad`, `BuildingSim.add_building`, `Economy.credit` —
  and `Scenario.apply_player` is the SAME function the live server uses.
  Never add a faster path that builds the world its own way; that is the
  `profile`-sweep blind spot with a new name.
- **A scenario cannot see founding, production or spawn placement**,
  because it skips them. `just test-load` still plays the real opening
  and is still the gate a change passes before it is called done — take
  its DURATION from `docs/status/load-testing.md` rather than from here,
  since marching distance scales with map size and a number written into
  prose goes stale the next time the map ladder moves.
- **`_import` is now skipped when nothing changed.** It prints when it
  skips; `EDOTMW_FORCE_IMPORT=1` forces it. If you ever suspect a stale
  cache, that flag is the first thing to try.

Lifecycle:

- `just doctor` — preflight: runtime prerequisites actually met?
- `just up` / `just down` / `just status` — all scoped to this instance
- `just instance` — this checkout's instance name, udp port and compose
  project (D-095). Read it before believing a failure is yours.
- `just nuke` — full teardown back to pure source. **Deletes `tools/`,
  including the `just` you ran it with** — that's intentional; re-run
  `./bootstrap.ps1` to come back.

Dev loop and tests:

- `just run-server` — headless authoritative server
- `just run-client [ADDRESS] [PORT]` — GUI client for a human to look at.
  **Native only**; needs a GPU (D-014), so it ignores `EDOTMW_RUNTIME` and
  says so if portable Godot is missing. WASD pans (relative to where the
  camera looks), wheel zooms, **Q/E and Ctrl+wheel turn the view**, the
  compass snaps back to north, right-click orders, ESC opens the game
  menu (D-063).
- `just test-client [SECONDS]` — the same client, rendered headlessly via
  Mesa's software rasteriser and checked automatically. Writes
  `artifacts/client-frame.png`; **look at it**, that is the point. Docker
  only. See D-014's 2026-07-29 amendment for why this doesn't contradict
  "the client can't be containerized".
- `just run-bots N [DURATION]` — N virtual load-test bots in one process.
  Requires a server to already be up (`just up`) — it deliberately does
  not start one, because a `run --rm` dependency leaks a container.
- `just test-unit [FILTER] [TEST]` — GUT unit tests, headless *(green:
  781 tests across 51 scripts, measured 2026-08-17)*. FILTER selects
  files by substring, TEST selects one test by name (D-098).
- `just test-scenario [SCENARIO] [N] [DURATION]` — the fast integration
  loop: a real server and real bots starting mid-match from a scenario
  (~31 s at DURATION=15, ~50 s at the default 30, against `test-load`'s
  ~150 s). Fails unless the server's log confirms it actually played the
  scenario.
- `just scenarios` — the shipped mid-game scenarios and what each is for
- `just test-load N DURATION` — full load test: server + N bots for
  DURATION seconds. Checks the bots' exit status, an explicit VERDICT
  line, AND a log scan for engine diagnostics. Tears down via trap on
  success, failure, and Ctrl-C. Prints the per-squad update cost — the
  number to watch — plus how many client/server state-hash comparisons
  ran and how many desynced.
- `just ai-ladder [MATCHES] [SECONDS] [AI]` — headless AI-vs-AI matches on
  `maps/ladder.tres`, to make "smarter" a measurement (D-054). Runs a
  genuinely all-AI server (`--players=0`); **fails** unless every match is
  observed to leave the lobby, which for three milestones it did not
  (D-107). Quote a result WITH its cap — a stronger defence lengthens
  matches, and a truncated one reads as a draw.
- `just gen-terrain-preview [CHUNK_SIZE]` — terrain PNG into `artifacts/`
  plus chunking cost, and the count of cliff faces the shipped map draws.
  Vary CHUNK_SIZE to settle D-017 with data. The PNG is **top-down biome
  colour**, so it cannot show how the ground looks.
- `just gen-terrain-shot [HEIGHT]` — a RENDERED picture of the ground, in
  the shipping lighting rig, framed on a cliff. Software-rasterised, no
  GPU needed. **Look at `artifacts/terrain-3d.png`.** It exists because
  every number `gen-terrain-preview` prints stayed healthy for two
  milestones while the ground read as a honeycomb of flat hexes, and
  because `test-client` aims its camera at a spawn — walkable ground by
  construction, and therefore the one place a cliff cannot be.
- `just gen-forest-preview [SECONDS]` — a RENDERED picture of a WOOD
  (D-108), framed on the densest forest on the map from a low angle, with
  real soldiers standing in it for scale. Real node placement
  (`Economy.generate`), real stands (`ResourceVisuals.trees_for`), real
  batching. Software-rasterised, no GPU. **Look at
  `artifacts/forest-godot.png`.** It exists because forests read as ranks
  and files for a milestone with every number healthy, and neither
  existing instrument could show it: `gen-terrain-preview`'s PNG is
  top-down with no trees in it, and `test-client` points at a spawn.
- `just replay-info [FILE]` — read a replay back and reconstruct state.
- `just bootstrap-art` — fetch the pinned `bpy` into a gitignored venv.
  ~1 GB, and ONLY asset work needs it: everything else, including running
  and testing the game, works from the committed `generated/`.
- `just build-assets [ARCHETYPE]` — rebuild models and textures from
  `art/`. Ends in an `--import`, because Godot serves assets from its
  cache and a rebuild it has not imported is invisible.
- `just gen-model-preview [SECONDS]` — every authored model, animated, on
  real terrain, through the REAL path (a `UnitDef`, a `PrimitiveUnit`,
  the shipping shaders). Software-rasterised, so unlike `bench-render` it
  needs no GPU. It renders TWICE and fails if the two frames are
  byte-identical — a frozen VAT would otherwise produce a perfectly
  plausible still. **Look at `artifacts/models-godot.png`.**
- `just gen-cover-preview [SECONDS]` — ground cover (D-100) on generated
  terrain, through the REAL path (`GroundCover`, `UnitMesh`, one MultiMesh
  per model), with a real squad standing in it. Software-rasterised, no
  GPU. Fails if nothing was drawn or if a palette names a model that did
  not load. **Look at `artifacts/cover-godot.png`** — every prop colour in
  `art/scatter/props.py` was chosen off that picture, because a prop's
  near-vertical geometry renders a good deal darker than ground painted
  with the same number.

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

Check `decisions/OPEN-QUESTIONS.md`. If you need an answer to something listed
there to proceed, surface that rather than guessing — these are marked
open because they genuinely haven't been resolved, not because they
were forgotten.
