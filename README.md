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

Tests do not have to run the whole match opening. A **scenario** starts
mid-game — bases already standing, armies already in reach — so an
integration run takes ~31 s (at DURATION=15; ~50 s at the default 30)
instead of ~150 s:

```powershell
.\tools\just.exe scenarios                  # what mid-game starts exist
.\tools\just.exe test-scenario siege 4 30   # real server + bots, mid-match
.\tools\just.exe test-unit scenarios        # just one test file, ~9s
```

`just test-load 4 120` still plays the real opening, and is still the run
that has to pass before a change is done — a scenario skips founding and
production, so it cannot see a bug in them. See `game_design_decisions.md`
D-076.

`just` is intentionally not on PATH — it lives in `tools/`, so the whole
toolchain can be removed with one command:

```powershell
.\tools\just.exe nuke        # remove containers, images, tools/, caches
```

That leaves the repo as pure source, which is the point: this dev
environment is designed to be fully switched off when you're not using
it (see `game_design_decisions.md` D-014).

Run `.\tools\just.exe` with no arguments to list every recipe.

## Playing, and running tests at the same time

Your game and any automated test runs are separate **instances**. Each
instance gets its own container project and its own network port, so a
test run cannot interrupt your game and your game cannot fail a test run.

### Play

```powershell
.\tools\just.exe lobby          # lobby server + GUI client, one command
.\tools\just.exe lobby 4        # ...with 4 player slots
.\tools\just.exe dev-down       # stop it (closing the client also does)
```

That is the `dev` instance, on port 4433. `lobby` is the only recipe that
starts it and `dev-down` the only one that stops it, whichever directory
either is run from.

### See what is running

```powershell
.\tools\just.exe instances
```

```
INSTANCE                     PROJECT                            PORT   CONTAINERS CHECKOUT
dev                          edotmw-dev                         4433   0          —
test-lobby-launch-9d5532     edotmw-test-lobby-launch-9d5532    4434   0          C:/Users/dmaso/Documents/github/my-edotmw/.claude/worktrees/lobby-launch-9d5532 <- you are here
note: project 'edotmw' exists — a pre-D-075 leftover, owned by no instance
```

A row marked `STALE` is a port still claimed by a checkout that no longer
exists — `just instance-free <instance>` releases it:

```
test-instance-probe    edotmw-test-instance-probe    4435   0    ...  STALE (checkout gone — just instance-free test-instance-probe)
```

### How an instance is chosen

You never name one — it comes from the directory you are in:

| Where you run `just` | Instance | Port |
|---|---|---|
| the main checkout | `dev` | 4433 |
| `.claude/worktrees/foo-1234` | `test-foo-1234` | first free from 4434 |

Every recipe prints what it resolved before doing anything else:

```
instance=test-foo-1234 project=edotmw-test-foo-1234 port=4434
```

Read that line before believing a failure — "which server was I actually
talking to" is the question it exists to answer. To force an instance,
set `EDOTMW_INSTANCE`:

```bash
EDOTMW_INSTANCE=test-scratch ./tools/just.exe test-load 4 120
```

One checkout runs one instance. Two instances driven from the *same*
directory would share the import cache and `artifacts/`, so use a
separate worktree rather than two `EDOTMW_INSTANCE` values in one.

### Why `just down` is refused in the main checkout

`down` tears down whichever instance it resolved. In the main checkout
that is `dev` — your game — so it refuses rather than guessing:

```
down: refusing to tear down the 'dev' instance implicitly.
      That is the human dev session. Run: just dev-down
```

Inside a worktree it resolves to that worktree's own `test-*` instance
and works normally. See `game_design_decisions.md` D-075.
