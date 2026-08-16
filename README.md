# my-edotmw

My attempt at a hybrid of *Empires: Dawn of the Modern World* and *Rome:
Total War* — large-scale RTS battles (squads, flow-field pathfinding, a
seamless wrapped map) with Total War-style formations and morale/routing
layered on top. No campaign layer.

See [`CLAUDE.md`](CLAUDE.md) for the architecture ground rules and
[`game_design_decisions.md`](game_design_decisions.md) for the full
decision log.

## Status

**M7 (real models and textures) landed; M9 (epochs, six civs) planned but
not built.** Movement, combat, fog of war, a playable skirmish MVP, scale
and performance targets, civs/lobby/AI, and authored art have all shipped
across milestones M1–M7. See the milestone ladder and `CLAUDE.md` for the
current, detailed status of each.

## Getting started

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/)
(WSL2 backend). Godot itself is *not* installed on your machine — the
container image builds its own pinned copy.

Run everything below from **Git Bash**, not PowerShell — most recipes
have a bash shebang body, and `just` invoked from PowerShell dies before
any recipe runs (see [`docs/COMMANDS.md`](docs/COMMANDS.md)).

```bash
powershell -File bootstrap.ps1   # fetch `just` into tools/ (nothing system-wide)
./tools/just.exe doctor          # verify prerequisites
./tools/just.exe test-unit       # run the headless test suite
./tools/just.exe quick-test      # play: you + 3 random-civ AI, no lobby
```

`just` is intentionally not on PATH — it lives in `tools/`, so the whole
toolchain can be removed with one command:

```bash
./tools/just.exe nuke        # remove containers, images, tools/, caches
```

That leaves the repo as pure source, which is the point: this dev
environment is designed to be fully switched off when you're not using
it (see `game_design_decisions.md` D-014).

Run `./tools/just.exe` with no arguments to list every recipe, or see
[`docs/COMMANDS.md`](docs/COMMANDS.md) for the full command reference.
