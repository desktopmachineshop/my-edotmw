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

Headline state: M1–M5 and M7 complete; M6 in progress; M8 (Steam)
and M10 (scale optimisation) planned but not built; M9's civ half is
IMPLEMENTED (the six fantasy civs ship and Legion/Northmen are gone —
see `docs/status/fantasy-civs.md`), its epoch ladder still design-only.
**M10 runs before M8** — the map ladder grew on 2026-08-17 and the client
does not yet keep up with it. For current test counts or
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

@docs/status/ai-opponent.md

@docs/status/ai-fortification.md

@docs/status/m7.md

@docs/status/art-pipeline.md

@docs/status/gatherer-tools.md

@docs/status/terrain.md

@docs/status/spawns.md

@docs/status/the-opening.md

@docs/status/ground-fog.md

@docs/status/pathing.md

@docs/status/forests.md

@docs/status/world-look.md

@docs/status/lattice-copies.md

@docs/status/formation.md

@docs/status/rtw-battles.md

@docs/status/line-endings.md

@docs/status/host-load.md

@docs/status/sandbox.md

@docs/status/playtests-2026-08.md

@docs/status/naval.md

@docs/status/m8-plan.md

@docs/status/m8-export.md

@docs/status/join-handshake.md

@docs/status/main-menu.md

@docs/status/steam-boundary.md

@docs/status/host-in-process.md

@docs/status/alpha-loop.md

@docs/status/transport-seam.md

@docs/status/onboarding.md

@docs/status/civ-knobs.md

@docs/status/renewable-economy.md

@docs/status/fantasy-civs.md

@docs/status/tech-tree.md

@docs/status/m9-plan.md

@docs/status/m10-plan.md

@docs/status/client-render.md

@docs/status/server-memory.md

@docs/status/audio.md

@docs/status/game-browser.md

## What this project is

A large-scale real-time strategy game, inspired by *Empires: Dawn of the
Modern World* and *Rome: Total War* (formations and morale/routing,
specifically — not a campaign layer), on a single seamless map, 4-6
civilizations at launch, shipping on Steam.

**Scale target, MEASURED and superseding D-018's 20 players / 40,000
soldiers** (`D-20260828-the-shipping-scale`, #287): **~200 squads and
~3,100 soldiers in a match**, recommended shape **8 players x 25
squads**. Both budgets land there from opposite directions — D-020's
100 ms worst tick crosses between 180 and 240 squads server-side, and
30 fps on Intel Iris Xe crosses at ~200 client-side. **The budget is a
TOTAL, not a per-player allowance**, so `squad_cap` should be derived
from the seat count; at 40 per seat the lobby's own 24-seat ceiling is
arithmetically impossible. The 13x reduction from D-018 is the bill for
the trade `D-20260818-battle-quality-outranks-player-count` already
made. **Nothing may quietly re-quote 20 players.**

**That 200 is a DEDICATED server's number and NOT a host's**
(`D-20260828-the-host-pays-both-budgets`, #339). D-088 runs the sim
in-process inside a player's client, so a host pays both budgets out of
one second: measured, it holds **100-150 squads**, and at 200 it runs at
19.9-35.6 fps. The cause is structural rather than contention — **the
authoritative tick runs inside the render frame**, and a 46 ms tick
cannot fit a 33 ms budget by any scheduling. `just bench-render` in host
mode (`--host=1`) is the instrument; the three possible responses are #349 and the choice
is D-088's. Built in Godot specifically because its plain-text asset
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
terrain_knowledge.gd     What one SIDE believes the GROUND to be, and so
                        what its squads may path through
                        (D-20260818-pathing-knows-only-what-the-player-knows).
                        Fed from vision.gd's own coverage; keyed by SIDE,
                        because allies share sight (D-050). Unknown ground
                        reads PASSABLE, which is what makes a squad take
                        the shortest route it has no reason to doubt and
                        find out by walking. THIS, never `_passable`, is
                        what a flow field is solved against — `_passable`
                        answers only "may a squad stand here now".
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
prop_fog.gd              The same field, read by everything that STANDS on
                        the ground (D-20260817-fog-covers-props). D-106
                        fogged the terrain shader and nothing else, so a
                        scouted forest kept rendering at full brightness
                        over the dim ground it grows in (#81). Re-expresses
                        the imported glTF materials as a shader that can
                        multiply by `known`; the coordinate rides
                        per-instance custom data and comes from the CELL
                        (`TerrainChunk.fog_uv`, never world position — a
                        chunk root swings to a different torus copy every
                        frame). Buildings are deliberately NOT dimmed: once
                        seen, a building is knowledge, not sight (D-030,
                        D-101). All-static.
render_cull.gd           Wrap-aware render culling and LOD selection
                        (D-045). All-static and pure, so the half with
                        the interesting failure mode is testable without
                        a GPU. `visible_offsets_of_extent` returns EVERY
                        copy on screen, not one
                        (D-20260818-entities-are-drawn-at-every-visible-copy)
                        — a cull decision and nothing else, so a cull
                        mistake can no longer MOVE anything.
lattice_copies.gd        One thing in the world, drawn at every visible
                        lattice copy of the torus. The mechanism that
                        closes the copy-choice bug class: mirrors share
                        the source's MultiMesh/Mesh/material, are created
                        lazily, and are SIBLINGS — a building's facing is
                        rotation and its progress is scale, and a child's
                        offset would be turned and squashed by both.
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
                        The command panel is THREE COLUMNS and as tall
                        as the tallest of them, never their sum
                        (D-20260817-selection-bar-three-columns) — and a
                        chip strip that cannot show a building's whole
                        train list hides ORDERS, not labels.
                        Scale is measured against TWO references
                        (D-20260817-hud-scale-stops-at-1080p): FIT against
                        1280x720 below it, MAGNIFICATION against 1920x1080
                        above it. One ratio for both is what made every
                        element a constant FRACTION of the window at every
                        resolution — a bigger window bought no battlefield.
                        Also owns the HUD's non-obvious arithmetic: the
                        match clock, the n/cap readout, and the compass
                        dial's geometry (D-063).
lobby_layout.gd          The same, for the LOBBY screen
                        (D-20260817-lobby-fits-the-window). Its own file
                        because it answers to its own reference height:
                        the HUD is magnified against a 1280x720 window,
                        while the lobby is a full-page document scaled to
                        FIT `DESIGN_HEIGHT` of content. Sharing the HUD's
                        720 laid a 1000-tall window out in 720 design
                        pixels and pushed the last panel off the bottom.
                        Every size here is a SHARE of the design rect;
                        a fixed pixel count is the bug. The page also
                        scrolls (`_lobby_scroll`) — the backstop, not the
                        plan.
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
                        And it owns WHERE THE CROP IS LOOKING
                        (`focus_uv_of`/`cell_under`, #130): the minimap is
                        re-centred on the camera every frame, so which
                        cell sits under a pixel is a function of where the
                        player is standing. client.gd reads both — the
                        uniform it SETS and the click it RESOLVES — so the
                        two cannot drift, which is exactly how the click
                        mapping came to be a milestone behind the shader
                        under a comment arguing it was right.
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
                        identical to the wire format. Opens its file
                        through ArtifactPath, so a shipped build records
                        one at all.
artifact_path.gd         WHERE this project writes what it produces
                        (D-20260828). `res://` is a real directory in a
                        checkout and a READ-ONLY virtual filesystem
                        inside an exported build's .pck, so the first
                        ever exported build played a complete match and
                        recorded NO REPLAY, with the only notice a
                        push_error nobody in a release build can see
                        (#201). One base, decided once: `res://artifacts`
                        from a checkout, `user://artifacts` from a build,
                        and a path handed in from outside is REBASED
                        rather than refused — so every recipe, every
                        `--out=` and `just replay-info` keep finding
                        files exactly where they look for them today.
                        All-static.

--- networking ---
net_transport.gd         What the server and client need of a TRANSPORT
                        and nothing more (D-20260828, #184). ENet today
                        (`enet_transport.gd`), D-088's Steam relay
                        second. Its event constants are ENet's value for
                        value, so the seam was an addition beside the
                        netcode rather than a rewrite of it; peers stay
                        duck-typed to `ENetPacketPeer.send`, the shape
                        LoopbackPeer and HostLink already share. The
                        contract is RELIABLE-ORDERED (D-042: curves carry
                        no sequence number), and
                        tests/test_transport_ordering.gd drives a
                        deliberately reordering fake through it and FAILS
                        if the client does not diverge — the first time
                        that dependency has been falsifiable.
net_protocol.gd          The one definition of the wire protocol, shared
                        by server, client and bots so they can't drift.
                        Owns PROTOCOL_VERSION and the JOIN HANDSHAKE
                        (D-20260827, #179): a client's first packet is a
                        HELLO and the server admits nobody before it, so
                        a mismatched build is refused with a sentence
                        naming both builds instead of producing desyncs.
                        The version is its OWN number, never the build
                        string — two builds can differ and speak the
                        same wire.
host_link.gd             The CLIENT end of an in-process connection
                        (D-20260828, #182) — `loopback_peer.gd`'s mirror
                        image. That one carries packets to a client inside
                        the process; this one carries its ORDERS back, so
                        the ~30 ordering sites in client.gd are the same
                        code whether the player is hosting or joined over
                        a socket. A host cannot be handed a rule a guest
                        does not have, because there is no branch in which
                        to give it one.
client_state.gd          Everything a client knows, with no rendering
                        attached. The GUI client and the load-test bots
                        both run THIS — so test-load exercises the real
                        client path, and the client's logic is testable
                        headless even though the client itself isn't.
server.gd / server.tscn  Headless authoritative server (D-002).
client.gd / client.tscn  GUI client. Native-only, needs a GPU (D-014).
                        Starts at a MAIN MENU when no connection was asked
                        for on the command line (D-20260827, #180), so an
                        installed build has a way in; every failed,
                        refused or lost connection returns there with a
                        message. `main_menu.gd` is the pure half — which
                        endpoint a launch means, how a typed address
                        parses, what the title says.
bot_client.gd            Headless load-test bot. Runs N *virtual*
                        clients in one process, not N processes (memory
                        budget — see D-018).
static_defence.gd        WHEN an AI spends on something that cannot chase
                        anybody (D-20260828, #337). All-static, pure, and
                        it NAMES NO DOMAIN — no wall, gate, dock or ship —
                        because naval stage 7 answers the same question
                        about shore defences and #337 asked that the two
                        share it. A source scan in the tests enforces
                        that, since "knows nothing about walls" is not
                        something a behavioural test can see. A missing
                        threat key is NO evidence, never alarming
                        evidence, so a caller that has not learned to
                        report something new cannot start fortifying
                        because of it.
wall_plan.gd             WHERE a wall goes, and where its gate goes
                        (D-20260828). The half that knows what a wall is.
                        A SCREEN across the approach, not a ring: a ring
                        at radius 5 is 900 wood and 1,200 stone at the
                        shipped price, which no match of this length can
                        afford. Built from the MIDDLE outward, so a
                        half-built screen is a screen with short ends
                        rather than a fence with a hole in the road. Walls
                        and gates are found by their FIELDS, never by id
                        (D-047), and bearings go through `space.delta` so
                        a screen faces the short way round the seam.
bot_patrol.gd            What a load-test bot's scouting detachment does
                        (D-20260817-load-test-bots-must-manoeuvre). All-
                        static and pure, like formation.gd, so the half of
                        the load test with the interesting failure mode is
                        testable without a server. `test-load`'s
                        `reveal_events` gate asserts a MANOEUVRE — hidden,
                        then shown again — and the bots had stopped
                        performing one at all: the rally/recall pair was a
                        one-shot spent on the founding party, and the raid
                        pool is empty because every squad a bot owns is a
                        hauling crew. Leg boundaries are EVENTS (the scout
                        arrived), never timestamps, and both are stated in
                        the WATCHER's terms — "they have lost me" is the
                        condition a conceal actually counts, and on a map
                        where two starts are 13 cells apart against 11
                        cells of town-centre sight, "am I home yet" is not
                        the same question.
platform.gd              THE one script allowed to name Steam (D-093,
                        #181). A test fails if any other .gd names the
                        API — the D-046-criterion-3 pattern, and what
                        keeps D-021's one-category amendment from being a
                        hole. Absent Steam reports unavailable and costs
                        Steam FEATURES, never the game; that is the
                        configuration every automated context here runs
                        in, so the fallback is the constantly-tested path.
                        Called `Platform`, not `SteamPlatform`: the rule
                        is that no other .gd names Steam, so a boundary
                        whose own class name contains the word cannot be
                        CALLED from anywhere (#184 found this the moment
                        it tried). Note D-093's GDExtension premise is
                        measured FALSE (D-20260828) — GodotSteam ships a
                        modified engine — and the replacement is the
                        owner's call.
                        Note D-093's GDExtension premise is measured FALSE
                        (D-20260828) — GodotSteam ships a modified engine
                        — and the replacement is the owner's call.
lan_protocol.gd          THE definition of how a game announces itself on
                        a LOCAL NETWORK (#187): a query, a reply, and the
                        discovery port DERIVED from the game port so
                        D-095's per-instance ports keep two agents' dev
                        servers out of each other's lists. Deliberately
                        not net_protocol.gd's wire — that one is spoken
                        to a peer that has already joined.
lan_beacon.gd            The server end: answers "is anybody there" with
                        what this game currently is, freshly per reply. A
                        bind failure is NOT fatal — a game nobody can
                        find is still a game anybody can join by address.
lan_discovery.gd         The client end, and the reference implementation
                        of the PROVIDER duck type the browser holds an
                        array of (id/label/poll/take_seen/status). The
                        platform's provider comes from platform.gd
                        and is absent in every context this repo
                        automates, so the array simply has one in it.
game_browser.gd          What the pre-lobby's game list SAYS: merge,
                        expire, order, and whether a row can be pressed.
                        All-static and pure, like hud_layout.gd, because
                        a row that offers a join it cannot complete looks
                        exactly like a list that works.
cmd_args.gd              The one parse of `--key=value`, and the one check
                        that a value about to be read as a NUMBER is one
                        (D-20260817-recipe-args-are-positional). All three
                        binaries above refuse to start on an argument they
                        cannot use, because `int()` STRIPS non-digits
                        rather than failing: `--seed=SANDBOX=1` is seed 1,
                        a plausible and entirely wrong world. They each
                        kept a private copy of the parser before, which is
                        why none of them could be tested.

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
controls_reference.gd    THE list of what the controls do (D-20260828,
                        #282). One list, shown by BOTH the main menu and
                        the in-game menu, so they cannot drift. Its build
                        and train rows are DERIVED from client.gd's own
                        BUILD_KEYS/TRAIN_KEYS, and it documents BEHAVIOUR
                        rather than intent — writing it is how #302 was
                        found (G is a build key AND has a dead gather
                        branch, so the gather shortcut is unreachable).
opening_brief.gd         What a squad is FOR in the opening, and what to
                        do first (D-20260828, #284). All-static and pure,
                        and it names NO archetype and NO building: "can
                        this squad found" is `BuildingSim.can_build`
                        against `built_by` — the same call the ORDER GATE
                        makes, so the panel cannot promise something the
                        server will refuse. The founding building is
                        found by its RULE (`consumes_builder`).
civ_identity.gd          What a player is TOLD about a civ before they
                        pick it (D-20260828, #283) — its one-line pitch
                        and its signature unit, both from the .tres.
                        All-static and pure. `signature_unit` is an
                        ARCHETYPE (D-047), so a civ naming one it does
                        not field advertises NOTHING rather than somebody
                        else's troops. `CivDef.summary` was
                        declared-and-unread for six milestones, which is
                        why nobody noticed its cp1252 em dash arriving as
                        U+FFFD on every load (#214).
manual.gd                THE in-game instructions manual (D-20260828,
                        #305), menu -> Help and F1. Every page is one of
                        two things and there is no third. GENERATED —
                        rosters, stats, counters, costs, buildings,
                        formations — is computed from the shipped .tres
                        when the page OPENS, so there is no copy for the
                        data to disagree with and nothing to rebuild;
                        that is `TerrainGen.biome_color()`'s rule applied
                        to text. STAMPED is prose that cannot be derived,
                        under /manual as ManualPageDef. All-static and
                        pure. Prose may write `{Combat.CONST}` and gets
                        whatever combat.gd says — the same constant-map
                        lookup controls_reference.gd uses for its build
                        rows, so a page quoting a number quotes the real
                        one. Markup is `## `, `- `, and a blank line;
                        anything more would be a manual whose fit nobody
                        could check.
manual_page_def.gd       One hand-written page, and the STALENESS RULE.
                        A page names the files it describes and carries a
                        sha256 over them; `just build-manual` writes it,
                        `tests/test_manual.gd` recomputes it, so a
                        gameplay PR that moves a rule and forgets the page
                        goes red. PER PAGE, never one manifest — a single
                        hash would red every page on any gameplay change,
                        and a guard that fires on things it has nothing to
                        say about is one people learn to silence (#204).
                        `.tres` and not `.md` because export_presets.cfg
                        excludes *.md from every shipping build.
civ_standing.gd          Where a civ stands against the rest of the
                        shipped roster, MEASURED (D-20260828, #305).
                        Every advantage and disadvantage in the manual is
                        a comparison computed from the data: a knob
                        against `CivDef.new()`'s default, an archetype
                        against a count over /units, quality vs quantity
                        against D-072's V and V/RP. Six sentences keyed by
                        civ id would rot within two milestones AND break
                        D-046 criterion 3 — so a seventh civ writes its
                        own entry. A claim clears an 8% MARGIN rather than
                        merely differing.
unit_roster.gd          Loads /units in a stable order. Server, client
                        and tests all discover units through this.
/maps/*.tres            MapConfig resources (torus dimensions, squads
                        per player). Height must be even — D-008.
map_config.gd           MapConfig schema. Also WHERE PEOPLE START:
                        `spawn_points` scatters at a minimum spacing
                        (D-039) over the ONE walkable component every
                        start must share
                        (D-20260827-every-start-shares-one-landmass) —
                        `min_spawn_landmass` (D-104) is an absolute SIZE
                        and isolation is a RELATION, so a roomy island
                        passed it and left a player nobody could reach,
                        which under D-033 makes the match undecidable and
                        reads as a draw at the time cap.
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
                        a fixed-function material cannot express — and
                        `prop_fog.gdshader`, the same fog tap for the
                        models standing on that ground, at a coordinate
                        carried per MultiMesh instance.
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
/art/source/*.blend      THE source of truth for every unit and building
                        (D-20260821-game-assets-are-files). Ordinary
                        Blender files: open one, model it, save it, run
                        `just build-assets`. Marked BINARY in
                        .gitattributes and included in the staleness hash
                        — that hash is the only thing between "I edited
                        the model" and "the game still draws the old one".
art/lib/blend_source.py  Bakes one of those into the arrays `write_glb`
                        and `write_vat` take. Steps the timeline and
                        flattens through the DEPENDENCY GRAPH, so an
                        armature, shape keys or a modifier stack are all
                        invisible to it — a VAT stores final vertex
                        positions and has no opinion about how they were
                        produced. Visits objects in NAME order and asserts
                        the topology is constant across frames: a
                        generative modifier driven by the pose breaks the
                        mesh/VAT column contract QUIETLY, and the model
                        comes apart at one frame in sixty-four.
art/seed_source.py       Wrote the initial .blend files from the legacy
                        generators, so opening militia.blend gives the
                        militia that is in the game rather than an empty
                        scene. A migration, never part of the build, and
                        it refuses to overwrite an artist's file.
art/attach_tools.py      Puts the axe and the pickaxe on the gatherer's
                        back (D-20260825). A MIGRATION like seed_source.py,
                        never part of the build: it edits the .blend, and
                        `build-assets` bakes what the .blend says. The tools
                        become part of the SOLDIER MESH because they have to
                        — where a fist is mid-swing exists only in the VAT,
                        so a tool drawn from its own MultiMesh could be
                        placed at the soldier and never IN HIS HAND. One
                        bone per tool, weighted 1.0, whose REST pose is the
                        tool stowed; a clip that uses it sets that bone from
                        the HAND's matrix. Orientation is MEASURED, never a
                        magic angle per file. It also gives each HAND two
                        finger joints, because the supplied rig has none and
                        an open mitt cannot grip a haft. The handle is found by a
                        BALL AROUND THE BUTT TIP, not by the mesh's principal
                        axis, because a pickaxe's wide head drags that axis
                        off the haft and hung the tool 0.103 out of the fist.
                        Every step asserts its own result.
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
naval_shot.gd            And again for SHIPS ON WATER (naval stage 8),
                        framed on the busiest piece of coast with a hull
                        against the beach, a hull in open water and a
                        squad ashore. Real /units defs, real
                        `Formation.soldier_transforms_sampled` with the
                        water plane, drawn at every lattice copy. The
                        shore is ranked by HEIGHT first: ranked by water
                        sides it frames the flattest sandbar on the map,
                        which is a picture of two squads at the same
                        height proving nothing.

--- tooling ---
build_version.gd         THE one definition of which build this is
                        (D-20260827). The number lives in project.godot's
                        `application/config/version` and NOWHERE else —
                        `just export` greps the same line, so a binary and
                        the artifact it was written into cannot disagree.
                        All-static; a test fails if a second script names
                        the setting, and forbids a git sha or a timestamp
                        (D-081: two clean clones of one commit must export
                        the same bytes).
export_presets.cfg       The shipping builds, COMMITTED — Windows Client,
                        Windows Server, Linux Server. An exported binary
                        cannot be handed a scene on the command line, so
                        which one it starts in is a FEATURE TAG
                        (`custom_features="server"` against
                        `run/main_scene.server`); either half alone
                        exports a working client under the server's name.
justfile                 The full command vocabulary for local dev,
                        testing, and export. Use these recipes rather
                        than reconstructing godot/steamcmd invocations.
instance-id.sh           THE definition of this checkout's dev-instance
                        identity (D-095): instance name from the git
                        branch, udp port hashed from it. The justfile
                        derives its per-worktree compose project, ports
                        and container names from this — nothing may
                        re-derive it. See "Multi-agent isolation" below.
blender-path.sh          THE definition of where the Blender APPLICATION is
                        (D-20260821). instance-id.sh's sibling for a third
                        thing nothing else may re-derive. The `bpy` wheel
                        `bootstrap-art` installs has the window manager
                        COMPILED OUT — no flag opens a window on it — so
                        the GUI needs the separate application. That
                        application is an ORDINARY DESKTOP INSTALL this
                        repo neither downloads nor pins: it FINDS one, and
                        EDOTMW_BLENDER names one outright. Only the WHEEL
                        is pinned, because only the wheel bakes; a version
                        difference is REPORTED, never refused. `just
                        doctor` prints all three.
gate-check.sh            THE log comparisons a real multi-client run must
                        survive (D-20260818-the-fast-loop-carries-the-
                        gate): fog gating of squads and of resource
                        positions, and both civs having fielded
                        something. `test-load` AND `test-scenario` both
                        call it, so the loop people iterate in cannot
                        assert less than the five-minute gate — it
                        asserted three fewer things for three
                        milestones. A missing marker FAILS the check; a
                        comparison that silently skips is the vacuous
                        pass D-022's audit was written against.
host-budget.sh           THE definition of how much of this machine dev
                        work may use (D-20260818). instance-id.sh's
                        sibling: that one stops agents COLLIDING, this
                        one stops them STARVING each other. Gates on
                        MEMORY, because profiling found CPU under 41%
                        for everything but test-load while free RAM never
                        left 1.5-2.4 GB. Admission reconstructs the pool
                        (free + charged) every poll rather than counting
                        jobs — the resident floor moved 1.2 GB in an hour
                        and free memory fell anyway.
host-gate.sh             The cross-worktree queue built on it. Lock dir
                        lives OUTSIDE every worktree, because shared
                        state is the whole point; it touches no docker
                        object of any kind, which is what keeps D-095
                        intact. Reaps holders whose pid is gone, and a
                        child recipe INHERITS its parent's slot through
                        EDOTMW_GATE_HELD (test-load calls up calls
                        _import — three acquires would be a deadlock the
                        parent can never clear).
host-sample.ps1          The instrument. Every number in D-20260818 came
                        out of it; `just host-profile` wraps it. Same
                        rule as gen-terrain-shot: a claim that the gate
                        helped has to be measured, not argued.
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
                        needs a real GPU, and prints which one. Runs the
                        client's OWN render pipeline through
                        `squad_render.gd` (D-20260828), because for a
                        milestone it did not and said it did: every frame
                        time recorded in that window was a floor for a
                        client nobody was timing. Reports the frame in
                        PHASES with a residual, and the MIX that produced
                        it — a frame with nothing fighting prices no
                        duels.
world_index.gd           Things at WORLD positions, bucketed so "what is
                        near me" is a neighbourhood scan
                        (D-20260828-a-squad-looks-up-its-buildings, #325).
                        The client's building lookups walked EVERY known
                        building per drawn squad per frame — one
                        millisecond per building, measured, and buildings
                        only ever accumulate (D-030, D-076). A cell-disk
                        index was tried first, because `disk_offsets`
                        before `distance()` is the standing rule, and
                        measured TEN TIMES WORSE: a fourteen-unit reach
                        on a 1.73-unit cell pitch is a 469-cell disk.
                        So the rule has a boundary — `disk_offsets` is
                        for a radius of a FEW CELLS, not for sparse
                        things over many. The index NARROWS; every caller
                        still applies the test it always applied.
drawn_index.gd           Where every squad's men were DRAWN last frame,
                        indexed so the cross-squad jostle finds its
                        neighbours without walking the match
                        (D-20260828-the-jostle-looks-where-the-men-are,
                        #262). The walk it replaces was QUADRATIC in
                        drawn squads — 152 ms of a 387 ms frame at 630 of
                        them — and it fired for STANDING squads, i.e.
                        once the battle started. A uniform grid over
                        WORLD positions, deliberately NOT a torus disk
                        scan: these are lattice COPIES (D-20260818), and
                        normalising them would merge what the renderer
                        keeps separate. Per-soldier render state, legal
                        under D-006 clause 2 as amended, bounded by the
                        squads drawn (`begin` empties it every frame) and
                        readable only by a drawing surface — a test scans
                        for that.
bench_baseline.gd        The RECORDED render baseline and what a fresh
                        run may differ from it by (D-20260828, #286).
                        COUNTS gate — soldiers, drawn men, drawn squads,
                        draw calls are deterministic given the map,
                        roster, viewport and render path. MILLISECONDS
                        report and decide nothing: three recordings gave
                        identical counts while the wall clock moved 13%.
                        A FINGERPRINT (map, roster, generated manifest,
                        Godot version, and the SOURCE of the render path)
                        separates "re-record" from "regression", because
                        a check that calls a roster change a fault is a
                        check that gets muted. All-static and pure, so
                        the arithmetic that decides pass/fail is testable
                        without the GPU the measurement needs.
                        `just bench-stale` is the per-PR half and needs
                        no GPU at all.
squad_render.gd          THE per-squad render pipeline: duels, the
                        static-target deal, the building and tree
                        push-outs, the survivor easing, the decoration
                        and the clip. One definition, called by client.gd
                        and by the benchmark that claims to measure it
                        (D-20260828, #240) — a harness cannot drift from
                        a client whose function it runs. All-static and
                        pure over its inputs, except the `SoldierMotion`
                        the caller owns and passes in: D-006's amended
                        clause 2 puts the eased per-soldier positions
                        there and nowhere else.
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
  silhouette first. **Units and buildings are authored `.blend` FILES**
  under `art/source/` (D-20260821-game-assets-are-files) — the industry
  norm, and it supersedes D-081's generated roster. Props and the terrain
  atlas stay generated by committed Python, permanently: a script is
  genuinely the better tool for eighteen interchangeable ground-cover
  clumps, and `art/scatter/props.py` fails its own build on an inside-out
  part in a way no file can. Either way `just build-assets` drives
  **Blender headless as a library** (`bpy`, a PyPI wheel) and writes
  `generated/`.
- **Primitive tier (fallback):** `UnitDef.model_id` / `BuildingDef.model_id`
  default EMPTY, and an empty id means "use the capsule". So bots, tests
  and a clone that has never run `build-assets` all still work — a failed
  art build costs fidelity, not the game.

**The models read as blocks because of their SILHOUETTE, not their edges**
(D-20260821, and `docs/status/art-pipeline.md` for the pictures). Bevelling
every rigid part costs **5.7x to 23.7x the triangles and is not visually
distinguishable**; an articulated figure — thigh+shin, upper arm+forearm,
boots, pauldrons — fits in **288 of the 300 budget**. The ceiling is neither
the budget nor the runtime: **a VAT stores final vertex positions and has no
opinion about how they were produced**, so the client could already draw
skinned, subdivided animation at today's cost. The ceiling is `Part`, which
has one pivot and one group and so cannot express a knee. Nothing is wired
up; the direction is the owner's call.

**Both the generators and their output are committed** (D-081). The
generators are the source of truth; `generated/` is committed anyway so a
fresh clone plays without installing anything. Note `generated/` is
byte-identical between two runs on ONE platform and **not** across them —
the committed VATs are Windows-built and a Linux rebuild differs by ~31
bytes of EXR header per archetype with identical geometry. Rebuild on one
machine and say which. Two runs of
`build-assets` must be **byte-identical** — fixed seeds, sorted iteration,
no timestamps — and a test fails if `generated/` is stale with respect to
`art/`.

**A model bakes only ITS OWN clips, and a clip index is a NUMBERING**
(`D-20260825-a-gatherer-carries-the-tool-for-the-job`). `CLIP_ORDER` in
`art/lib/clips.py` is the index space; `clips_for(archetype)` says which
PREFIX of it a given model carries, and the manifest records it per model.
Most of the roster bakes the base four — the gatherer bakes three more,
because it is the only unit carrying tools. **Resolve every clip index
through `UnitMesh.clip_index`**: the shader finds a row by arithmetic
(`clip * frames_per_clip + local`), so asking a four-clip model for clip 4
lands on its NORMALS block and the model comes apart with nothing failing.
A model's triangle count is also a TEXTURE WIDTH — one VAT column per
flattened vertex against a 16,384 limit — and `art/build.py` refuses to
write a VAT past it.

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
- **An agent's quick launch is the dev build.** `quick-test` takes two
  POSITIONAL arguments, `SEED` then `SANDBOX`, and prints which it
  resolved (it printed nothing at all before):

  | you type | seed | sandbox (D-077 cheats panel) |
  |---|---|---|
  | `just quick-test` | 1337 | `auto` |
  | `just quick-test 1337 1` | 1337 | ON |
  | `just quick-test 1337 0` | 1337 | off |
  | `just quick-test 42` | 42 | `auto` |
  | `just quick-test SANDBOX=1` | — | **refused**, loudly |

  `auto` asks `instance-id.sh agent`: ON for any checkout that is not
  the owner's own default branch, off on `main`/`master`. The seed is
  the FIRST argument and nothing else sets it — there is no `SEED=`
  form, and there never was one that worked.
- **just takes recipe arguments POSITIONALLY** — `just quick-test 1337 1`,
  never `just quick-test SANDBOX=1`. A `NAME=value` written after a
  recipe name binds the whole string to that recipe's FIRST parameter,
  and GDScript's `int()` **strips the non-digits** rather than failing,
  so the recipe gets a plausible small number: `SANDBOX=1` launched with
  sandbox OFF on seed **1** instead of 1337, and `run-server LOBBY=1`
  starts one unasked-for AI and no lobby. Silent until
  D-20260817-recipe-args-are-positional; every numeric parameter goes
  through `recipe-arg.sh` now and fails loudly. **Anything measured
  through one of those invocations was measured on a different build or
  a different world than it claims.**

## Testing — use the justfile, and use it before claiming something works

`just` lives in `tools/` and is **not on PATH** — invoke it as
`./tools/just.exe <recipe>`. On a fresh clone run `./bootstrap.ps1`
first. Recipes call each other via `{{just_executable()}}` for the same
reason; a bare `just` inside a recipe will not resolve.

**Run recipes from a bash shell (Git Bash), not PowerShell.** From
PowerShell, `just` resolves `sh` to WSL's bash and dies with
`execvpe(/bin/bash) failed` before any recipe body runs.

**Every heavy command is ADMITTED against the host's spare memory
before it runs** (D-20260818). Several agents share one laptop, and the
machine fits roughly ONE heavy docker recipe at a time. A gated recipe
waits, saying what it is waiting for and who is ahead of it, then fails
loudly rather than proceeding if it waits out `EDOTMW_GATE_TIMEOUT`.

- `just host-status` — what the machine has left, and who holds it
- `just host-profile [SECONDS] [TAG]` — sample the host while you run
  something else. **The before-numbers for any tuning claim.**
- `just reap-orphans [APPLY]` — containers whose worktree is gone. DRY
  RUN unless `APPLY=1`, because two versions of its matching rule each
  proposed deleting a LIVE agent's containers.
- `EDOTMW_NO_GATE=1` is the off switch, and `just doctor` reports it.

**A recipe that waited is a recipe whose wall clock means nothing** —
the same rule this project already applies to figures measured while the
host was building containers.

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

- `just package [TARGET]` — wrap an exported build into the zip a tester
  downloads (#183): versioned filename, `docs/alpha/testers.md` inside as
  README.txt, sha256 printed. Packed by GODOT's ZIPPacker, because `zip`
  is not on Git Bash's PATH and a fresh clone must need nothing but
  `./bootstrap.ps1`.
- `just publish-itch [TARGET] [PROJECT]` — push a package to a PRIVATE
  itch.io channel via butler. **Never run against a real target**; what
  is verified is its refusal path. `docs/alpha/runbook.md` has the rest.
- `just export [TARGET]` — the shipping builds (D-094 criterion 1).
  Native only, and needs `just bootstrap-export-templates` first (~1.3 GB,
  into `tools/`, once). TARGET is `all` (default), `windows-client`,
  `windows-server` or `linux-server`. Prints the version it stamped;
  `docs/status/m8-export.md` has the rules that came out of it.
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
- `just menu-shot [SECONDS] [RESOLUTION] [CONTROLS] [MANUAL]` — a picture
  of the PRE-CONNECTION menu (#180), through the docker software-GL image
  with NO server running. Every other rendered check here is aimed at a
  connected client, so nothing could look at this screen; its first two
  runs found two defects nothing else could. **Look at
  `artifacts/main-menu.png`.** `CONTROLS=1` photographs the controls
  screen instead (#282); `MANUAL=<page>` photographs one page of the
  MANUAL (#305) — a page id rather than a flag, because "the manual" is a
  dozen screens and a shot of the first says nothing about the ones with
  tables on them. The recipe FAILS unless the client's `MANUAL page=`
  marker names the page that was asked for.
- `just test-client [SECONDS] [BOTS] [HOLD]` — the same client, rendered headlessly via
  Mesa's software rasteriser and checked automatically. Writes
  `artifacts/client-frame.png`; **look at it**, that is the point. Docker
  only. See D-014's 2026-07-29 amendment for why this doesn't contradict
  "the client can't be containerized".
- `just run-bots N [DURATION]` — N virtual load-test bots in one process.
  Requires a server to already be up (`just up`) — it deliberately does
  not start one, because a `run --rm` dependency leaks a container.
- `just profile [ONLY]` — the scale sweep, and since #304 a **steady-state
  per-phase tick ladder at 120 squads** (`ONLY=ladder`) with a knob per
  suspect and a `control` row that states the instrument's own noise
  floor. **Read the control row before believing any small difference**:
  this host drifts up to 2x between runs minutes apart. It is what
  attributed M6's long-standing 40.8 -> ~77 debt
  (`D-20260828-the-m6-rise-has-a-name`) — to combat and separation, and
  NOT to civs, teams or the economy, none of which is measurable at all.
- `just test-unit [FILTER] [TEST]` — GUT unit tests, headless *(green:
  781 tests across 51 scripts, measured 2026-08-17)*. FILTER selects
  files by substring, TEST selects one test by name (D-098).
- `just test-scenario [SCENARIO] [N] [DURATION]` — the fast integration
  loop: a real server and real bots starting mid-match from a scenario
  (~31 s at DURATION=15, ~50 s at the default 30, against `test-load`'s
  ~150 s). Fails unless the server's log confirms it actually played the
  scenario.
- `just scenarios` — the shipped mid-game scenarios and what each is for
- `just test-host [N] [DURATION] [AI]` — in-process hosting proved
  against REAL remote clients (#182): a hosting client, headless, with N
  bots joining it over a socket, and the state-hash machinery read on
  BOTH sides. Native only (the host is a client, D-014); binds this
  instance's port, never the shared default.
- `just test-handshake` — presents a deliberately wrong protocol version
  to a real server over a real socket and fails unless it is REFUSED with
  an actionable message, and unless a matched build is admitted in the
  same run (#179). The refusal path nothing else in the estate can reach,
  because every binary here is built from one `net_protocol.gd`.
- `just test-load N DURATION` — full load test: server + N bots for
  DURATION seconds. Checks the bots' exit status, an explicit VERDICT
  line, AND a log scan for engine diagnostics. Tears down via trap on
  success, failure, and Ctrl-C. Prints the per-squad update cost — the
  number to watch — plus how many client/server state-hash comparisons
  ran and how many desynced.
- `just ai-ladder [MATCHES] [SECONDS] [AI] [TEAMS] [PROFILES]` — headless AI-vs-AI
  matches on `maps/ladder.tres`, to make "smarter" a measurement (D-054).
  Runs a genuinely all-AI server (`--players=0`); **fails** unless every
  match is observed to leave the lobby, which for three milestones it did
  not (D-107). Quote a result WITH its cap — a stronger defence lengthens
  matches, and a truncated one reads as a draw. TEAMS defaults to 0, a
  free-for-all, so every number recorded before
  D-20260818-allied-ai-is-exercised-by-something stays comparable.
  PROFILES pairs DIFFICULTIES (D-20260818-ai-profiles-are-data) — a
  comma-separated list of `/ai/*.tres` ids dealt round-robin across the
  seats, empty meaning the shipped default, so a run written before
  profiles existed measures what it measured then.
- `just test-ai-teams [MATCHES] [SECONDS] [AI] [TEAMS] [SCENARIO] [PROFILES]` — real
  teamed all-AI matches that **fail if an AI aims its army at a friend**
  (#83, #119). The one thing in the estate that exercises an allied AI:
  the ladder is a free-for-all, every AI fixture seats on team 0 (not a
  team, D-050), and `--lobby=0` never handed `SquadSim.teams` over at
  all. ~5 minutes at its defaults, because it starts from a scenario
  (D-098) rather than an opening. It fails on `ally_objectives > 0` —
  and first on every way that zero could be vacuous: a match that never
  started, a simulation with no sides, a seat that saw no ally, a seat
  that never attacked. Given PROFILES it also fails if a difficulty was
  dealt and did not ARRIVE — the same "the one configuration nothing
  runs" rule applied to D-20260818-ai-profiles-are-data.
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
- `just browser-check [SECONDS]` — the game browser's gate (#187): a
  server announces on this instance's port, a headless client FINDS it,
  and the recipe fails unless it was listed by name, at that port, ONCE.
  Native, no GPU, no docker — a headless client still builds its menu and
  prints a `BROWSER_GAME` line per row.
- `just browser-shot [SECONDS] [RESOLUTION]` — the same thing as a
  PICTURE: the menu with a real discovered game in it, software-GL in
  docker like `menu-shot`. Fails if the list is empty, because a
  photograph of a feature not working is still a valid PNG. **Look at
  `artifacts/game-browser.png`.**
- `just gen-naval-shot [HEIGHT] [SEABED]` — a RENDERED picture of SHIPS
  ON WATER, framed on a coastline, with a land squad ashore for contrast.
  Software-rasterised, no GPU. **Look at `artifacts/naval-godot.png`.**
  `SEABED=1` derives the hulls the pre-stage-8 way and prints what that
  costs (a hull inshore rides 0.055 up the beach) — the difference is a
  NUMBER and is not visible in the frame, which the recipe says out loud.
- `just replay-info [FILE]` — read a replay back and reconstruct state.
- `just bootstrap-art` — fetch the pinned `bpy` into a gitignored venv.
  ~1 GB, and ONLY asset work needs it: everything else, including running
  and testing the game, works from the committed `generated/`. This is
  the WHEEL, which bakes and has no window.
- `just blender-gui [TARGET]` — open `art/source/<TARGET>.blend` in YOUR
  OWN locally installed Blender (D-20260821-game-assets-are-files). With
  no TARGET it lists what is authored. Native only, for the same reason
  as `run-client`. Model it, save it, then `just build-assets TARGET`.
  **There is no bootstrap recipe for Blender and nothing downloads one**
  — it is a standard desktop tool, installed normally;
  `blender-path.sh explain` says where it looked. It is also the one
  heavy recipe that is NOT host-gated and does NOT pass
  `--factory-startup`: a gate cannot protect a binary the owner can
  launch from the desktop anyway, and factory startup bought isolation
  only the human using the tool would have paid for.
- `just seed-art-source [ONLY]` — write `art/source/*.blend` from the
  LEGACY generators. A one-time migration, never part of the build, and
  it refuses to overwrite an existing source because that file is an
  artist's work now.
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
