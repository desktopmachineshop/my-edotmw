# Command reference

Every command this project supports is a `just` recipe — there is no
other supported way to build the container, run the server, or drive a
test. This page is a practical reference; for *why* things are shaped
this way (docker vs. native, curve sync, the lobby, etc.) see
[`CLAUDE.md`](../CLAUDE.md) and
[`game_design_decisions.md`](../game_design_decisions.md).

Run `./tools/just.exe` with no arguments at any time to list every
recipe with its one-line doc comment — this page just organizes and
expands on the same list.

## Before you start

- **Use Git Bash, not PowerShell**, for every command below except
  `bootstrap.ps1` itself. Most recipes have a bash shebang body; invoked
  from PowerShell, `just` resolves `sh` to WSL's bash and dies with
  `execvpe(/bin/bash) failed` before the recipe runs at all.
- `just` is intentionally **not on PATH** — it lives in `tools/`, fetched
  by `bootstrap.ps1`. Invoke it as `./tools/just.exe <recipe>` (or
  `./tools/just <recipe>` if you're on macOS/Linux).
- Fresh clone, first time:

  ```bash
  powershell -File bootstrap.ps1   # fetches `just` into tools/ (Windows)
  ./tools/just.exe doctor          # verify prerequisites are met
  ./tools/just.exe test-unit       # run the headless test suite
  ```

- Default runtime is **docker** — the container builds its own pinned
  Godot, so Godot itself is not installed on your machine. Set
  `EDOTMW_RUNTIME=native` to use a portable Godot instead (only required
  for `run-client` and `bench-render`, which need a real GPU and use
  native unconditionally regardless of this variable).

## Setup & lifecycle

| Command | What it does |
|---|---|
| `just doctor` | Preflight check: is docker reachable (or is native Godot present), is `just` where it should be. Run this first when anything else fails mysteriously. |
| `just bootstrap` | Fetches the pinned **native** Godot into `tools/`. Only needed for `EDOTMW_RUNTIME=native`, `run-client`, `lobby`, and `bench-render` — everything else builds its own Godot inside the docker image. |
| `just bootstrap-art` | Installs the pinned `bpy` (headless Blender-as-a-library) into a gitignored venv, ~1 GB. Only needed for `build-assets` — running and testing the game works from the committed `generated/` output without it. |
| `just up` | Starts the server **detached** (docker only — native has no persistent "up" state; use `run-server` directly there). |
| `just down` | Stops everything this project started: containers, and any stray one-off container left over from an interrupted run. Safe to run any time, including when nothing is up. |
| `just status` | Shows what's currently running. |
| `just nuke` | Full teardown back to pure source: containers, images, `tools/` (**including the `just` binary you're running it with**), artifacts, import caches. Re-run `bootstrap.ps1` to come back. |

## Playing

| Command | What it does |
|---|---|
| `just quick-test [SEED]` | **The fastest way to see a real match.** You + 3 AI opponents, everyone's civ (yours included) drawn randomly, no lobby to click through. Starts a detached server, waits for it to come up, launches the native GUI client connected to it, and tears everything down on exit. Needs native Godot (`just bootstrap` first). Re-run with the same `SEED` (default `1337`) to reproduce the same civ draw. |
| `just lobby [PLAYERS]` | Play with the seat-picking screen: starts a lobby server and the GUI client together (they have to agree on port/mode, which is why this isn't just `run-server` + `run-client` typed separately). You're the admin — add AI seats, choose civs (including "Random" per seat), then press Start. `PLAYERS` is the human seat count, default 1. |
| `just run-client [ADDRESS] [PORT]` | Runs the GUI client natively against a server you started separately (`up`/`run-server`, or a remote address). **Native only** — needs a real GPU. Controls: WASD pans, wheel zooms, Q/E and Ctrl+wheel turn the view, ESC opens the game menu, right-click orders your selection. |
| `just run-server [AI] [MAP] [LOBBY]` | Headless authoritative server, foreground. `AI=N` seats N computer opponents without a lobby (round-robin civs by default). `LOBBY=1` holds the server in the lobby instead of starting immediately — the world isn't generated until an admin presses Start, since its size/seed/shape are still being chosen there. |

`run-server` doesn't expose every flag the server binary accepts as a
`just` parameter (e.g. `--seed`, `--random-civs`, `--players`) — those
are read from `OS.get_cmdline_user_args()` and can be passed straight
through docker compose or the native binary if you need a combination
`quick-test`/`lobby`/`run-server` don't already cover; see `server.gd`'s
`_ready()` for the full list.

## Load testing & bots

| Command | What it does |
|---|---|
| `just run-bots N [DURATION]` | Spawns N virtual load-test bots in a **single process** against an already-running server (`just up` first — this deliberately doesn't start one itself, to avoid leaking a container). `DURATION` in seconds, or `-1` (default) to run until stopped. Exit status reflects whether every bot connected and replicated. |
| `just test-load N DURATION` | The full load test: brings up a server, runs N bots for DURATION seconds, tears down, and checks the run several independent ways — bot exit status, an explicit VERDICT line, fog-of-war actually gating both squads and resource nodes, both civs having fielded something, and a scan for engine errors/warnings. **Use `just test-load 4 120`** as the baseline — shorter runs on the default map can fail before armies even meet or before the founding party finishes a town hall, and that's the check working, not a bug (see `CLAUDE.md`). Prints the per-squad update cost. |
| `just ai-ladder [MATCHES] [SECONDS] [AI]` | Headless AI-vs-AI matches on the small `ladder` map, to make "the AI got better" a measurement instead of an opinion. Reports decided/drawn counts, win rates, and per-civ economy stats over the sample — not just a bare win rate. Defaults: 10 matches, 600s cap, 2 AI. |

## Automated tests

| Command | What it does |
|---|---|
| `just test-unit [FILTER] [TEST]` | The GUT unit test suite, headless. `FILTER` selects test **files** by substring (`just test-unit scenarios`), `TEST` selects a single test by name (`just test-unit "" within_reach`) — the full suite is minutes, and iterating on one behaviour shouldn't cost that. |
| `just test-scenario [SCENARIO] [N] [DURATION]` | The fast integration loop: a **real** server and **real** bots, but starting mid-match from a scenario instead of playing the ~150 s opening (~31 s at `DURATION=15`, ~50 s at the default 30). Fails unless the server's own log confirms it actually played the scenario, and unless every entry the scenario describes was placed. **Not a replacement for `test-load`** — a scenario hands out finished buildings and adjacent armies, so it structurally cannot see a bug in founding, production, or spawn placement. |
| `just scenarios` | Lists the shipped mid-game scenarios and what each is for — the ids `test-scenario` and `--scenario` accept. |
| `just test-client [SECONDS] [BOTS]` | Renders the **real** GUI client headlessly (Mesa's software rasterizer, no GPU needed) with load-test bots as a live opponent, and checks the frame: exit status, VERDICT line, more than one flat color in the screenshot, and that casualties/conceals/reveals actually happened this run. Writes `artifacts/client-frame.png` — look at it, that's the point. Docker only. |

## Content pipeline (art)

| Command | What it does |
|---|---|
| `just build-assets [ONLY]` | Rebuilds every model and texture from the committed Python generators under `art/` (Blender headless-as-a-library — no GUI, no system Blender install). Ends in a Godot `--import`, because a rebuilt asset is invisible to the engine until it re-imports. `ONLY` restricts the build to one archetype. |
| `just gen-model-preview [SECONDS]` | Contact sheet of every authored model, animated, on real terrain, through the actual shipping render path. Renders twice at different times and fails if they're byte-identical (catches a frozen animation texture). Look at `artifacts/models-godot.png`. |

## Profiling & diagnostics

| Command | What it does |
|---|---|
| `just profile` | Scale sweep: simulation cost at 100/250/500/1000 squads. The shape of the curve is the deliverable — cost should stay flat per squad; a bend means something turned quadratic. Not a substitute for a live run — see `CLAUDE.md`'s note on the sweep missing defects a live match caught. |
| `just bench-render [COUNTS] [FRAMES] [HEIGHT]` | Client render benchmark: frame time and draw calls at each squad count in `COUNTS`. **Native only, needs a real GPU** — prints which one it ran on, because a frame time with no hardware attached isn't a usable number. |
| `just gen-terrain-preview [CHUNK_SIZE]` | Writes a terrain biome PNG to `artifacts/` and reports chunk-meshing cost at the given chunk size, without launching the full game. |
| `just lobby-shot [SECONDS] [AI] [PRESET]` | Screenshots the lobby seat-list screen into `artifacts/lobby.png`, so its layout can actually be looked at. Docker only. |
| `just replay-info [FILE]` | Reads a recorded replay curve log back and reconstructs world state from it — the primary desync-forensics tool. Defaults to `res://artifacts/replay-4433.edmw`. |

## Environment variables

| Variable | Effect |
|---|---|
| `EDOTMW_RUNTIME` | `docker` (default) or `native`. Recipes marked docker-only or native-only above ignore this and always use the runtime they need. |
| `EDOTMW_SCENARIO` | Starts the server mid-game from `res://scenarios/<id>.tres` instead of playing the opening. Set by `just test-scenario`; empty (the default) means the real opening. |
| `EDOTMW_FORCE_IMPORT` | `1` forces the Godot import step even when nothing has changed since the last one. `_import` normally skips (and says so) when no source file is newer than the stamp — reach for this first if you ever suspect a stale cache. |
