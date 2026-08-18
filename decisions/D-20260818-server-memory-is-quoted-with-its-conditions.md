# D-20260818 · 2026-08-18 · Accepted — server memory is quoted with its conditions, and here is the number on the new ladder

**Decision:** the server's memory figure carries the conditions it was
taken under — **players, squads and cells** — the way this project has
always quoted µs/squad with a squad count, and the number itself now
exists for the map ladder that shipped on 2026-08-17. Four clauses:

1. **One structured line, its own line.** `server: MEMORY <static>,
   <peak> — N player(s), M squad(s), WxH = C cells`, printed by
   `_memory_line()` from `_print_summary`. Memory used to ride along at
   the end of the bandwidth line as `mem=43.3 MB`, which is where a
   figure goes to be uncomparable.
2. **Players is a PEAK, and an all-AI server reports its seats.** The
   summary prints when the LAST client leaves, so a live count is 1
   however many played — the trap the bandwidth line already fell into
   and fixed. `--players=0` (the ladder) has no sockets at all, so
   `MatchState.player_count()` stands in.
3. **Cells come from the sim's own `TorusSpace`**, not from
   `MapSettings`, so the line reports the map that was actually
   simulated rather than the one that was requested.
4. **`EDOTMW_MAP` selects the MapConfig for a compose run**, mirroring
   `EDOTMW_SCENARIO`. `just test-load` brings the server up through
   `just up`, so before this there was **no way to load-test any map but
   the default** — which is a large part of why the top of the ladder
   had never been measured. `maps/huge.tres` is that top rung, 336x388.

**The budget, stated so a future number can fail it:** **256 MB of
server static memory at D-018's full target** — 20 players, ~1,000
squads — **on the largest shipped map**. It is deliberately generous
against what is measured below and deliberately far under the 2 GB the
compose service already caps the container at; the point of a budget is
that a regression trips it, not that it is tight.

## The measurements

`just test-load 20 300`, 2026-08-18, docker runtime, one run each, on a
**busy host** (six other agents' containers running concurrently — see
the caveat below, which is why only the memory columns are quoted here).
The huge-map row was driven by hand — `just up` then `just run-bots 20
300` — for the reason in "what the largest map broke", below.

| map | cells | players | squads | static | peak | container RSS |
|---|---|---|---|---|---|---|
| `maps/default.tres` 168x194 | 32,592 | 20 | 128 | **52.6 MB** | 56.3 MB | 70.7–71.3 MiB |
| `maps/default.tres` 168x194 | 32,592 | **0** (world built, nobody joined) | 0 | — | — | **71.0 MiB** |
| `maps/huge.tres` 336x388 | 130,368 | 20 | 20 | **65.3 MB** | 72.3 MB | — |

For reference, the two figures this replaces: **42.5 MB at 120 squads**
on 84x96 (M4, 8,064 cells) and **43.3 MB at 4 squads** on the new
default (the M10 plan's `quick-test` figure, 32,592 cells).

Client side, from the same runs (`bot_client.gd`'s own MEMORY line, N
virtual clients in ONE process, so this is a total and not a per-client
figure):

| map | virtual clients | soldiers derived | static | container RSS |
|---|---|---|---|---|
| default | 20 | 645 | **31.1 MB** | 61.9–62.1 MiB |
| huge | 20 | 60 | **30.5 MB** | — |

**What it says.** Three things, in the order they matter:

- **The map is the dominant allocator, and it is affordable.** Quadrupling
  the cell count — 32,592 to 130,368 — cost **12.7 MB of static memory**
  while the army *shrank* from 128 squads to 20, so the cells alone are
  worth rather more than that: call it **~140 bytes per cell**, ~4.6 MB
  per 32k cells. The largest shipped map is 65.3 MB with twenty players
  on it. There is no memory emergency anywhere on this ladder.
- **Twenty players and 128 squads are not visible at RSS granularity.**
  A server that had built the default world and had **nobody connected**
  sat at 71.0 MiB resident; the same server three hundred seconds into a
  twenty-player match sat at 70.7–71.3 MiB. The tracked static figure
  does move (43.3 MB at 4 squads in the M10 plan's `quick-test` run
  against 52.6 MB here), so the armies are not free — they are just
  small enough to disappear into the allocator's own slack.
- **The per-client figure is flat in map size.** Twenty virtual clients
  cost **31.1 MB** on the default map and **30.5 MB** on a map four
  times the size, in one process. Note this is a TOTAL for twenty, not
  M4's ~1.4 MB marginal figure re-taken: the bots derive soldiers for
  what fog lets them see, and on the huge map they had seen 60 soldiers
  against the default map's 645. A real client is a different measurement
  again — it meshes terrain, and that cost scales with the map (#106).

**Bandwidth, re-taken at the same time** because the issue asks for it
alongside: **193 B/client/s over 20 clients, 0 budget overruns** on the
default map, against M4's 595 B/client/s at the same player count on a
map a quarter the size. D-003's curve sync is not the thing under
pressure here.

## The caveat that matters more than the numbers

**The 20-player runs did not keep up with wall-clock.** 300 s of bots
produced **60.9 s of simulated time** on the default map: 139 of 609
ticks over D-020's 100 ms budget, worst tick 4,083 ms, peak RTT 10.2 s,
peak loss 21.8%, throttle floored at 0.00 — and `test-load` reported
**clean**, because every gate it owns (fog, civs, desyncs, casualties,
buildings) genuinely passed. Two things follow, neither of them this
entry's to fix:

- **Memory here is memory at 61 s of match, not at 300 s.** A longer
  match holds more squads, more curves and more buildings, so read the
  table as a floor. The map component of it is complete, though — the
  terrain, passability and node arrays are all allocated before the
  first tick.
- **The tick figures are #105's and criterion 6's**, and were taken on a
  host running six other agents' containers, which this project already
  knows makes worst-tick numbers unreliable (M6's 146 ms-versus-52 ms
  incident, and the `bench-render` session that drifted 52 → 181 ms).
  They are recorded because a 5x-behind server is not a detail, not
  because the third digit means anything. **Do not quote them as
  measurements of the code.**

### What the largest map broke on the way to being measured

**`just test-load` cannot run the Huge map at all**, and that is a
finding rather than an inconvenience. `just up` returns when the
container starts, the recipe immediately runs the bots, and
`bot_client.gd`'s `CONNECT_TIMEOUT_SECONDS` is **10 s** — while the
server spends ~30 s of that building 130,368 cells of terrain, 29,013
resource nodes and twenty spawn points before it opens a socket. Every
bot reports `no client connected within 10s — is the server up?` and the
recipe fails with the server working perfectly. Left alone deliberately:
the timeout is honest about what it saw, and the right fix (world
generation not blocking the socket, or a wait-for-ready in the recipe)
belongs to #106's start-up work rather than to a measurement issue.
`FOG_TOTAL_NODES=29013` against the default map's 7,694 is the other
half of the same sentence — #109's number, taken here for free.

**Static memory is not RSS**, and the gap is worth knowing before anyone
sizes a host from this table: `OS.get_static_memory_usage()` reported
52.6 MB while the container's RSS sat at ~71 MiB — roughly 1.35x, the
difference being everything Godot does not allocate through its own
tracked static pool. Every historical figure in this project (M4's 42.5
MB, the M10 plan's 43.3 MB) is the tracked one, so the table stays in
those units and RSS is carried beside it rather than replacing it.

## Rationale

`quick-test` reported `mem=43.3 MB` with **four squads alive** on the new
default map. M4 measured **42.5 MB at 120 squads** on a map a quarter the
size. Side by side those two read as "memory is flat, nothing to see";
attach their conditions and they say the opposite — the *map* is the
dominant allocator now and the armies are not. Nothing failed and
nothing could: the line was correct, it just could not be compared with
anything, and neither could the next one.

That is the same failure the project's oldest standing rule exists for.
µs/squad is never printed without its squad count, because the same code
measured 3.9 µs at 12 squads and 2 µs at 48. Memory acquired a second
axis when the map ladder moved and nobody added it.

**Why a whole extra line rather than more `key=value` on the bandwidth
one:** they answer to different conditions. Bandwidth is per client per
second and its condition is the client count; memory's conditions are
the map and the army. Sharing a line is what made memory an afterthought
at the end of a sentence about bytes.

**Why `EDOTMW_MAP` on the compose service rather than a `MAP` argument
to `test-load`:** the recipe brings the server up with `just up`, and the
service's `command:` is the only place its arguments are written. A
recipe parameter would have had to reach into that anyway, and
`EDOTMW_SCENARIO` had already established the shape.

## Rejected alternatives

- **A per-subsystem memory inventory** (bytes in `FlowField`, in
  `TerrainFields`, in `Economy`). Genuinely useful, and it is #105's
  attribution job, not this one's — #111 says *measure, do not optimise*,
  and an inventory is the first half of an optimisation. The cell-count
  slope between two runs on two map sizes answers "does the map
  dominate?" without instrumenting a single allocator.
- **Reporting RSS instead of tracked static memory.** RSS is the truer
  number for sizing a host and would have made every historical figure
  in this repo incomparable overnight. Recorded beside, not instead.
- **Sampling memory every status line instead of once at the end.** The
  status line is already the most-parsed line in the log and this would
  have made a 300 s run print it thirty times. The peak figure covers
  what periodic sampling was for.

## Consequences

- `just test-load` surfaces both MEMORY lines after its verdict, so the
  number lands in front of whoever ran it rather than in a log file.
- `maps/huge.tres` exists and is loadable, so the top rung of the ladder
  is testable by anything that takes a `--map`, not only by the lobby.
- M10 exit criterion 6 is **half** discharged: memory and bandwidth at 20
  players on the default map are measured and inside a stated budget;
  worst tick at that player count is emphatically not, and that half
  belongs to #105.

## Revisit trigger

Any of: server static memory above **128 MB** on a shipped map at
D-018's player target (half the budget, so the trigger fires before the
budget does); a per-client figure that stops being flat in map size; or
the arrival of dedicated servers (D-088), which changes who is paying
for this memory and therefore what a sensible budget is.
