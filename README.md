# my-edotmw

My attempt at a hybrid of *Empires: Dawn of the Modern World* and *Rome:
Total War* — large-scale RTS battles (squads, flow-field pathfinding, a
seamless wrapped map) with Total War-style formations and morale/routing
layered on top. No campaign layer.

See [`CLAUDE.md`](CLAUDE.md) for the architecture ground rules and
[`game_design_decisions.md`](game_design_decisions.md) for the full
decision log.

## Status

**M0 (skeleton) complete.** The project structure, decision log, and
containerized dev environment exist and are verified; gameplay starts in
M1. See the milestone ladder in `game_design_decisions.md` (D-015).

## Getting started

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/)
(WSL2 backend). Godot itself is *not* installed on your machine — the
container image builds its own pinned copy.

```powershell
.\bootstrap.ps1              # fetch `just` into tools/ (nothing system-wide)
.\tools\just.exe doctor      # verify prerequisites
.\tools\just.exe test-unit   # run the headless test suite
```

`just` is intentionally not on PATH — it lives in `tools/`, so the whole
toolchain can be removed with one command:

```powershell
.\tools\just.exe nuke        # remove containers, images, tools/, caches
```

That leaves the repo as pure source, which is the point: this dev
environment is designed to be fully switched off when you're not using
it (see `game_design_decisions.md` D-014).

Run `.\tools\just.exe` with no arguments to list every recipe.
